package com.elamin.beluga.protocol;

import android.content.Context;
import android.media.AudioAttributes;
import android.os.Looper;
import java.nio.ByteBuffer;
import java.security.MessageDigest;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.BooleanSupplier;
import org.webrtc.AudioTrack;
import org.webrtc.DataChannel;
import org.webrtc.DefaultVideoDecoderFactory;
import org.webrtc.IceCandidate;
import org.webrtc.Logging;
import org.webrtc.MediaConstraints;
import org.webrtc.MediaStream;
import org.webrtc.MediaStreamTrack;
import org.webrtc.PeerConnection;
import org.webrtc.PeerConnectionFactory;
import org.webrtc.RtcError;
import org.webrtc.RtpCapabilities;
import org.webrtc.RtpReceiver;
import org.webrtc.RtpTransceiver;
import org.webrtc.SdpObserver;
import org.webrtc.SessionDescription;
import org.webrtc.VideoFrame;
import org.webrtc.VideoSink;
import org.webrtc.VideoTrack;
import org.webrtc.audio.JavaAudioDeviceModule;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.SessionCredential;

/**
 * Receive-only M150 native receiver.
 * Exclusively owns one transferred credential, WSS connection, ADM, factory and peer. Creates
 * no local tracks, recording prewarm, AudioRecord request, event log or media artifact. It must
 * only be constructed after exact saved-pair reservation and authenticated reconnect handoff.
 *
 * active() is operational readiness, never decoded PCM/video proof. Product integration and
 * runtime qualification remain separate. The public M150 DataChannel has no protocol/ordered/
 * reliability readback; exact v2 command/ACK establishes application compatibility, not its label.
 * One exact surface lifetime owns presentation independently from receive-only audio.
 */
final class WebRtcViewerReceiver implements ViewerConnectionSession.Media {
    private static final int MAXIMUM_TASKS = 256, MAXIMUM_TASK_BYTES = 512 * 1_024;
    private static final int MAXIMUM_CANDIDATES = 256, MAXIMUM_CHANNELS = 16;
    private static final long STARTUP_NANOS = 30_000_000_000L, DRAIN_NANOS = 10_000_000_000L;
    private static final String CONTROL_LABEL = "audiostreamer.control";
    private static final Object PROCESS_NATIVE_LOCK = new Object();
    private static boolean processInitialized, processInitializationFailed;
    // The session parent drops its media reference even after failed cleanup. Retain exact owners
    // independently; this process must not create a successor after any unproved native lifetime.
    private static final Set<WebRtcViewerReceiver> QUARANTINED = new HashSet<>();

    private enum Stage {
        NONE, CODEC_CREATE, SOCKET_CONNECT, SIGNAL_DECODE, BROKER_READY, HOST_IDENTITY,
        OFFER_PARSE, NATIVE_INITIALIZE, ADM_CREATE, FACTORY_CREATE, PEER_CREATE,
        SET_REMOTE, TRANSCEIVER_BIND, CREATE_ANSWER, ANSWER_VALIDATE, SET_LOCAL,
        ANSWER_SEND, SIGNAL_SEND, LOCAL_ICE, LOCAL_ICE_BIND,
        LOCAL_ICE_CALLBACK_SHAPE, LOCAL_ICE_CALLBACK_FRAGMENT, LOCAL_ICE_CALLBACK_PAYLOAD,
        REMOTE_ICE, ACTIVE_PLAYOUT,
        SOCKET_TERMINAL, PEER_CALLBACK, ICE_CALLBACK, AUDIO_CALLBACK, CONTROL_CALLBACK,
        VIDEO_CALLBACK, MAILBOX, STARTUP, WORKER_LOOP, WORKER_TASK, HEALTH_ADMISSION, DRAIN
    }
    private enum Category { NONE, REFUSAL, VALIDATION, CODEC, TRANSPORT, NATIVE, CALLBACK, INTERRUPTION, CLEANUP, RUNTIME, LINKAGE, UNKNOWN }
    private enum DiagnosticCode {
        NONE, UNSPECIFIED, REFUSED, INVALID_ARGUMENT, UNEXPECTED_EXCEPTION, NATIVE_ERROR,
        LINKAGE_ERROR, INTERRUPTED, STARTUP_TIMEOUT, SDP_FAILED, SDP_DUPLICATE,
        AUDIO_INIT, AUDIO_START, AUDIO_RUNTIME, RECORDING_STARTED, MAILBOX_OVERFLOW,
        CONTROL_CLOSED, CONTROL_PROTOCOL, VIDEO_FAILURE, TRACK_REMOVED, CLEANUP_UNPROVEN,
        NATIVE_CANDIDATE_NULL, NATIVE_CANDIDATE_SDP_NULL, NATIVE_CANDIDATE_SDP_TOO_LONG,
        NATIVE_CANDIDATE_PAYLOAD_INVALID
    }
    private static final class FailureSnapshot {
        final Stage stage; final Category category; final Enum<?> code;
        FailureSnapshot(Stage stage, Category category, Enum<?> code) {
            this.stage = stage; this.category = category; this.code = code;
        }
    }
    private final AtomicReference<FailureSnapshot> firstFailure = new AtomicReference<>();
    private final WorkerCancellation cancellation = new WorkerCancellation();
    private volatile Stage diagnosticStage = Stage.NONE;
    private void record(Stage stage, Category category, Enum<?> code) {
        firstFailure.compareAndSet(null, new FailureSnapshot(stage, category, code));
    }
    private void recordException(Stage stage, Throwable error) {
        if (error instanceof WebRtcViewerSdp.CandidateFailure)
            record(stage, Category.VALIDATION, ((WebRtcViewerSdp.CandidateFailure) error).code);
        else if (error instanceof ViewerMediaSignalingCodec.CodecFailure)
            record(stage, Category.CODEC, ((ViewerMediaSignalingCodec.CodecFailure) error).code());
        else if (error instanceof NettyPairingWssTransport.TransportFailure)
            record(stage, Category.TRANSPORT, ((NettyPairingWssTransport.TransportFailure) error).code());
        else if (error instanceof InterruptedException) record(stage, Category.INTERRUPTION, DiagnosticCode.INTERRUPTED);
        else if (error instanceof LinkageError) record(stage, Category.LINKAGE, DiagnosticCode.LINKAGE_ERROR);
        else if (error instanceof Refused) record(stage, Category.REFUSAL, DiagnosticCode.REFUSED);
        else if (error instanceof IllegalArgumentException) record(stage, Category.VALIDATION, DiagnosticCode.INVALID_ARGUMENT);
        else if (error instanceof Error) record(stage, Category.NATIVE, DiagnosticCode.NATIVE_ERROR);
        else record(stage, Category.RUNTIME, DiagnosticCode.UNEXPECTED_EXCEPTION);
    }

    private final Context context;
    private final UUID viewerID, hostID;
    private final byte[] viewerKey, hostKey;
    private final BooleanSupplier parentAuthorized;
    private final ViewerConnectionSession.MediaListener listener;
    private final SessionCredential credential;
    private final AndroidViewerPlaybackOutput output;
    private final Object mailbox = new Object();
    private final ArrayDeque<Task> tasks = new ArrayDeque<>();
    // Transferred wrappers are owned here before their queued processing, including on overflow.
    private final Set<DataChannel> ownedChannels = new HashSet<>();
    private final AtomicBoolean revoked = new AtomicBoolean(), closing = new AtomicBoolean();
    private final AtomicBoolean failed = new AtomicBoolean(), endedPublished = new AtomicBoolean();
    private final AtomicBoolean failurePublished = new AtomicBoolean();
    private final AtomicInteger callbacks = new AtomicInteger(), pendingSDP = new AtomicInteger();
    private final Object presentationOwner = new Object();
    private volatile SurfaceSlot surfaceSlot;
    private boolean presentationClosed;
    private final AtomicReference<CompletableFuture<Void>> pendingControlWrite = new AtomicReference<>();
    private volatile ViewerScreenSession screenSession;
    private volatile ScreenBinding screenBinding;
    private final CompletableFuture<Void> drained = new CompletableFuture<>();
    private final long startupDeadline = System.nanoTime() + STARTUP_NANOS;
    private Thread worker;
    private int taskBytes;
    private boolean interrupted;
    private volatile boolean allocationUncertain;
    // Everything below is owned by the serial receiver worker, never by peer observer threads.
    private ViewerMediaSignalingCodec codec;
    private NettyPairingWssTransport socket;
    private JavaAudioDeviceModule adm;
    private PeerConnectionFactory factory;
    private PeerConnection peer;
    private DataChannel control;
    private AudioTrack audio;
    private VideoTrack video;
    private List<RtpTransceiver> transceivers = Collections.emptyList();
    private WebRtcViewerSdp.Description remoteDescription, localDescription;
    private List<PeerConnection.IceServer> iceServers = Collections.emptyList();
    private final ArrayDeque<MediaSignalPayload.Candidate> remoteCandidates = new ArrayDeque<>();
    private final ArrayDeque<MediaSignalPayload.Candidate> localCandidates = new ArrayDeque<>();
    private boolean brokerReady, credentialAdmitted, answered, active, playout;

    interface Work { void run() throws Exception; }
    static final class RequestedCancellation extends Exception {
        private static final long serialVersionUID = 1L;
        RequestedCancellation() { super("Beluga receiver stop requested"); }
    }
    /** Only the pure screen-model admission runs under this lock; never JNI or callbacks. */
    static final class WorkerCancellation {
        private boolean requested, authorizationLost;
        synchronized void request() { requested = true; }
        synchronized boolean requested() { return requested; }
        private void demandOpen() throws Refused, RequestedCancellation {
            if (authorizationLost) throw new Refused();
            if (requested) throw new RequestedCancellation();
        }
        void demand(boolean retired, BooleanSupplier parentAuthorized) throws Refused, RequestedCancellation {
            synchronized (this) { demandOpen(); if (retired) throw new Refused(); }
            final boolean authorized;
            try { authorized = parentAuthorized.getAsBoolean(); }
            catch (RuntimeException refused) {
                synchronized (this) { authorizationLost = true; }
                throw new Refused();
            }
            synchronized (this) {
                // Once sampled false, authorization loss remains a failure even if stop raced
                // that sample. A stop already observed above never samples the parent.
                if (!authorized) { authorizationLost = true; throw new Refused(); }
                demandOpen();
            }
        }
        synchronized void admit(Work pureAdmission) throws Exception {
            demandOpen(); pureAdmission.run();
        }
    }
    /** Published once by the native worker; UI treats native handles only as identity tokens. */
    private static final class ScreenBinding {
        final ViewerScreenSession model;
        final Object peer, control, track;
        ScreenBinding(ViewerScreenSession model, Object peer, Object control, Object track) {
            this.model = model; this.peer = peer; this.control = control; this.track = track;
        }
    }
    /** Reserved before construction and retained through the parent's separate drainage receipt. */
    private static final class SurfaceSlot {
        final CompletableFuture<WebRtcVideoSurface> constructed = new CompletableFuture<>();
        volatile WebRtcVideoSurface surface;
    }
    private static final class Task {
        final int bytes; final Work work;
        Task(int bytes, Work work) { this.bytes = bytes; this.work = work; }
    }
    static final class Refused extends Exception {
        private static final long serialVersionUID = 1L;
        Refused() { super("Beluga native receiver refused"); }
    }
    private static final class DrainFailed extends Exception {
        private static final long serialVersionUID = 1L;
        DrainFailed() { super("Beluga native receiver cleanup unproved"); }
    }

    /** Validation failures here are strictly before thread, socket, JNI or native allocation. */
    static WebRtcViewerReceiver start(Context suppliedContext, SessionCredential credential,
            UUID viewerID, byte[] viewerKey, UUID hostID, byte[] hostKey,
            BooleanSupplier authorized, ViewerConnectionSession.MediaListener listener)
            throws ViewerConnectionSession.PreallocationRefusal {
        Context application = suppliedContext == null ? null : suppliedContext.getApplicationContext();
        if (application == null || credential == null || authorized == null || listener == null
                || !validID(viewerID) || !validID(hostID) || viewerID.equals(hostID)
                || viewerKey == null || viewerKey.length != 32 || hostKey == null || hostKey.length != 32
                || MessageDigest.isEqual(viewerKey, hostKey)) throw new ViewerConnectionSession.PreallocationRefusal();
        try { if (!authorized.getAsBoolean()) throw new ViewerConnectionSession.PreallocationRefusal(); }
        catch (RuntimeException refused) { throw new ViewerConnectionSession.PreallocationRefusal(); }
        synchronized (PROCESS_NATIVE_LOCK) {
            if (processInitializationFailed || !QUARANTINED.isEmpty()) throw new ViewerConnectionSession.PreallocationRefusal();
        }
        WebRtcViewerReceiver receiver = new WebRtcViewerReceiver(application, credential,
                viewerID, viewerKey, hostID, hostKey, authorized, listener);
        Thread owned = new Thread(receiver::run, "Beluga-native-viewer"); owned.setDaemon(true);
        receiver.worker = owned;
        try { owned.start(); }
        catch (RuntimeException refused) { throw new ViewerConnectionSession.PreallocationRefusal(); }
        return receiver;
    }
    private WebRtcViewerReceiver(Context context, SessionCredential credential, UUID viewerID,
            byte[] viewerKey, UUID hostID, byte[] hostKey, BooleanSupplier authorized,
            ViewerConnectionSession.MediaListener listener) {
        this.context = context; this.credential = credential; this.viewerID = viewerID;
        this.viewerKey = viewerKey.clone(); this.hostID = hostID; this.hostKey = hostKey.clone();
        parentAuthorized = authorized; this.listener = listener;
        output = new AndroidViewerPlaybackOutput(context, this::live, this::fail);
    }
    private static boolean validID(UUID id) {
        return id != null && (id.getMostSignificantBits() != 0 || id.getLeastSignificantBits() != 0);
    }
    /** Short delivery/command revocation. Native playout disable is serialized, not synchronous. */
    @Override public void revoke() {
        cancellation.request();
        retire();
    }
    private void retire() {
        output.revoke(); revoked.set(true); closing.set(true);
        WebRtcVideoSurface surface;
        synchronized (presentationOwner) {
            presentationClosed = true;
            surface = surfaceSlot == null ? null : surfaceSlot.surface;
        }
        if (surface != null) surface.revoke();
        ViewerScreenSession screen = screenSession;
        if (screen != null) screen.close();
        CompletableFuture<Void> pending = pendingControlWrite.getAndSet(null);
        if (pending != null) pending.completeExceptionally(new Refused());
        synchronized (mailbox) { mailbox.notifyAll(); }
    }
    @Override public CompletionStage<Void> close() {
        revoke(); return drained.thenApply(value -> value);
    }
    /** Observe exact drainage without initiating or weakening the parent's close. */
    CompletionStage<Void> completion() { return drained.thenApply(value -> value); }
    /**
     * Main-thread-only integration seam.
     * Construction must not allocate GL before mounting. One receiver admits one lifetime only;
     * a detached/failed surface cannot be replaced without the entire parent drainage receipt.
     */
    WebRtcVideoSurface createVideoSurface(Context uiContext) {
        if (Looper.myLooper() != Looper.getMainLooper()) throw new IllegalStateException("Main thread required");
        if (uiContext == null || uiContext.getApplicationContext() != context || !live()) return null;
        ScreenBinding binding = screenBinding;
        if (binding == null) return null;
        SurfaceSlot slot = new SurfaceSlot();
        synchronized (presentationOwner) {
            if (presentationClosed || surfaceSlot != null) return null;
            surfaceSlot = slot;
        }
        try {
            WebRtcVideoSurface surface = new WebRtcVideoSurface(uiContext, binding.model, binding.peer,
                    binding.control, binding.track, () -> { record(Stage.VIDEO_CALLBACK, Category.NATIVE, DiagnosticCode.VIDEO_FAILURE); fail(); });
            boolean retired;
            synchronized (presentationOwner) { slot.surface = surface; retired = presentationClosed; }
            if (retired || !live()) surface.revoke();
            // Never drop ownership even if cancellation won during View construction.
            slot.constructed.complete(surface);
            return retired || !live() ? null : surface;
        } catch (RuntimeException | Error uncertain) {
            recordException(Stage.VIDEO_CALLBACK, uncertain);
            allocationUncertain = true;
            slot.constructed.completeExceptionally(new DrainFailed());
            fail(); return null;
        }
    }
    /** The foreground owner supplies explicit scene/Show/Hide; this getter grants no Show. */
    ViewerScreenSession screenControlModel() { return live() ? screenSession : null; }
    @Override public String toString() { return "<Beluga native receiver; no decoded-media proof>"; }

    private boolean live() {
        if (revoked.get() || closing.get()) return false;
        try { return parentAuthorized.getAsBoolean(); }
        catch (RuntimeException refused) { return false; }
    }
    private void demandLive() throws Refused, RequestedCancellation {
        cancellation.demand(revoked.get() || closing.get(), parentAuthorized);
    }
    private void fail() {
        record(diagnosticStage, Category.UNKNOWN, DiagnosticCode.UNSPECIFIED);
        failed.set(true); retire();
        // Failure is an immediate fixed observation, NOT a drainage receipt. The actual parent
        // retires and closes the credential synchronously, and ignores later active() calls.
        // Never invoke this external callback while holding the receiver's mailbox/native lock.
        if (failurePublished.compareAndSet(false, true)) {
            try { listener.failed(); }
            catch (RuntimeException callbackUnproved) { allocationUncertain = true; }
        }
    }
    private boolean enqueue(int bytes, Work work) {
        if (bytes < 0 || work == null) { record(Stage.MAILBOX, Category.VALIDATION, DiagnosticCode.INVALID_ARGUMENT); fail(); return false; }
        boolean overflow;
        synchronized (mailbox) {
            if (closing.get()) return false;
            overflow = tasks.size() == MAXIMUM_TASKS || bytes > MAXIMUM_TASK_BYTES - taskBytes;
            if (!overflow) {
                tasks.addLast(new Task(bytes, work)); taskBytes += bytes; mailbox.notifyAll(); return true;
            }
        }
        record(Stage.MAILBOX, Category.REFUSAL, DiagnosticCode.MAILBOX_OVERFLOW); fail(); return false;
    }
    private Task take() throws InterruptedException {
        synchronized (mailbox) {
            if (tasks.isEmpty() && !closing.get()) mailbox.wait(50);
            Task task = tasks.pollFirst(); if (task != null) taskBytes -= task.bytes;
            return task;
        }
    }
    private void run() {
        boolean clean = false;
        try {
            diagnosticStage = Stage.CODEC_CREATE;
            demandLive(); codec = ViewerMediaSignalingCodec.create(credential); credentialAdmitted = true; demandLive();
            ViewerMediaSignalingCodec.JoinHeaders join = codec.copyJoinHeaders(); demandLive();
            // A cancellation during connect is owned by this worker and joined in finally.
            try {
                diagnosticStage = Stage.SOCKET_CONNECT;
                socket = NettyPairingWssTransport.connectSession(
                        NettyPairingWssTransport.PRODUCTION_ORIGIN, join, signalingListener());
                if (socket == null) throw new Refused();
            } catch (NettyPairingWssTransport.TransportFailure preallocationRefused) {
                throw preallocationRefused;
            } catch (RuntimeException | Error allocationUnknown) {
                // connectValidated can allocate its group before constructor/start returns a
                // handle. An unchecked outcome therefore cannot prove that nothing was owned.
                allocationUncertain = true; recordException(Stage.SOCKET_CONNECT, allocationUnknown); fail(); throw allocationUnknown;
            }
            demandLive();
            while (!closing.get()) {
                diagnosticStage = Stage.WORKER_LOOP;
                demandLive();
                if (!active && System.nanoTime() - startupDeadline >= 0) {
                    record(Stage.STARTUP, Category.REFUSAL, DiagnosticCode.STARTUP_TIMEOUT); throw new Refused();
                }
                Task task = take();
                diagnosticStage = Stage.WORKER_TASK;
                demandLive();
                if (task != null) task.work.run();
                ViewerScreenSession screen = screenSession;
                if (screen != null) screen.poll();
                checkReady();
            }
        } catch (RequestedCancellation stopped) { /* Explicit cancellation is not a native failure. */ }
        catch (InterruptedException stopped) { interrupted = true; recordException(diagnosticStage, stopped); fail(); }
        catch (Exception refused) { recordException(diagnosticStage, refused); fail(); }
        catch (Error unavailableNative) { allocationUncertain = true; recordException(diagnosticStage, unavailableNative); fail(); }
        finally {
            retire();
            try { clean = drain(); }
            catch (Exception | LinkageError failure) {
                recordException(Stage.DRAIN, failure); output.cleanupUnproved(); quarantine(); clean = false;
            }
            if (!clean) record(Stage.DRAIN, Category.CLEANUP, DiagnosticCode.CLEANUP_UNPROVEN);
            if (failed.get() || !clean) fail();
            else if (endedPublished.compareAndSet(false, true)) {
                try { listener.ended(); }
                catch (RuntimeException ignored) { clean = false; }
            }
            if (allocationUncertain) clean = false;
            if (!clean) quarantine();
            // Completion is last worker action; no session work or allocation occurs afterward.
            if (clean) drained.complete(null); else drained.completeExceptionally(new DrainFailed());
            if (interrupted) Thread.currentThread().interrupt();
        }
    }
    private NettyPairingWssTransport.Listener signalingListener() {
        return new NettyPairingWssTransport.Listener() {
            @Override public void onOpen() { enqueue(0, () -> { demandLive(); }); }
            @Override public void onText(byte[] wire) {
                // Netty has already produced an owned bounded array. Reserve before queuing it.
                if (wire == null || wire.length == 0 || wire.length > ViewerMediaSignalingCodec.MAXIMUM_WIRE_BYTES) {
                    record(Stage.SIGNAL_DECODE, Category.CODEC, ViewerMediaSignalingCodec.FailureCode.INVALID_WIRE); fail(); return;
                }
                if (!enqueue(wire.length, () -> {
                    try { diagnosticStage = Stage.SIGNAL_DECODE; signal(codec.receive(wire)); } finally { Arrays.fill(wire, (byte) 0); }
                })) Arrays.fill(wire, (byte) 0);
            }
            @Override public void onTerminal(NettyPairingWssTransport.FailureCode reason) {
                if (!closing.get()) { record(Stage.SOCKET_TERMINAL, Category.TRANSPORT, reason); fail(); }
                synchronized (mailbox) { mailbox.notifyAll(); }
            }
        };
    }
    private void signal(ViewerMediaSignalingCodec.Event event) throws Exception {
        demandLive();
        switch (event.kind()) {
            case WAITING: if (brokerReady) throw new Refused(); break;
            case READY:
                diagnosticStage = Stage.BROKER_READY;
                if (!brokerReady) {
                    if (event.claimedInvitationExpiresAtEpochMillis() <= System.currentTimeMillis()) throw new Refused();
                    List<PeerConnection.IceServer> admitted = new ArrayList<>();
                    for (ViewerMediaSignalingCodec.ICEServer server : event.copyICEServers()) {
                        PeerConnection.IceServer.Builder builder = PeerConnection.IceServer.builder(Arrays.asList(server.copyURLs()));
                        if (server.username() != null) builder.setUsername(server.username());
                        if (server.credential() != null) builder.setPassword(server.credential());
                        admitted.add(builder.createIceServer());
                    }
                    iceServers = Collections.unmodifiableList(admitted); brokerReady = true;
                }
                break;
            case SIGNAL:
                MediaSignalPayload payload = event.payload(); if (payload == null) throw new Refused();
                switch (payload.kind()) {
                    case IDENTITY:
                        diagnosticStage = Stage.HOST_IDENTITY;
                        byte[] asserted = payload.identity().copyPublicKey();
                        try {
                            if (!hostID.equals(payload.identity().deviceID()) || !"host".equals(payload.identity().role())
                                    || !MessageDigest.isEqual(hostKey, asserted)) throw new Refused();
                        } finally { Arrays.fill(asserted, (byte) 0); }
                        break;
                    case OFFER:
                        if (remoteDescription != null || answered) throw new Refused();
                        applyOffer(payload.sdp());
                        break;
                    case CANDIDATE: remoteCandidate(payload.candidate()); break;
                    case END: revoke(); break;
                    default: throw new Refused();
                }
                break;
            case PEER_LEFT: case SERVER_ERROR: throw new Refused();
            default: throw new Refused();
        }
    }
    private void send(MediaSignalPayload payload) throws Exception {
        diagnosticStage = payload.kind() == MediaSignalPayload.Kind.ANSWER ? Stage.ANSWER_SEND : Stage.SIGNAL_SEND;
        demandLive(); byte[] wire = codec.seal(payload).copyWireBytes();
        try { await(socket.sendGuarded(wire, this::live).toCompletableFuture(), startupOrDrainDeadline(), true); }
        finally { Arrays.fill(wire, (byte) 0); }
    }
    private long startupOrDrainDeadline() { return active ? System.nanoTime() + DRAIN_NANOS : startupDeadline; }
    private void initializeNative(Context context) throws Refused {
        synchronized (PROCESS_NATIVE_LOCK) {
            if (processInitializationFailed) throw new Refused();
            if (processInitialized) return;
            try {
                PeerConnectionFactory.initialize(PeerConnectionFactory.InitializationOptions.builder(context)
                        .setEnableInternalTracer(false)
                        .setInjectableLogger((message, severity, tag) -> { }, Logging.Severity.LS_NONE)
                        .createInitializationOptions());
                processInitialized = true;
            } catch (RuntimeException | LinkageError failure) {
                recordException(Stage.NATIVE_INITIALIZE, failure); processInitializationFailed = true; throw new Refused();
            }
        }
    }
    private void allocatePeer() throws Exception {
        demandLive();
        diagnosticStage = Stage.NATIVE_INITIALIZE;
        try { initializeNative(context); }
        catch (Refused unavailable) { allocationUncertain = true; throw unavailable; }
        demandLive();
        diagnosticStage = Stage.ADM_CREATE;
        try { adm = JavaAudioDeviceModule.builder(context).setOutputSampleRate(48_000)
                .setUseStereoOutput(true).setUseHardwareAcousticEchoCanceler(false)
                .setUseHardwareNoiseSuppressor(false).setEnableVolumeLogger(false)
                .setAudioTrackStateCallback(output)
                // M150 otherwise defaults this output to voice communication / speech. This
                // per-track policy is media playback, not a global AudioManager mode/route change.
                .setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                .setAudioTrackErrorCallback(new JavaAudioDeviceModule.AudioTrackErrorCallback() {
                    private void outputFailed(DiagnosticCode code) {
                        callbacks.incrementAndGet();
                        try { record(Stage.AUDIO_CALLBACK, Category.NATIVE, code); fail(); }
                        finally { callbacks.decrementAndGet(); synchronized (mailbox) { mailbox.notifyAll(); } }
                    }
                    @Override public void onWebRtcAudioTrackInitError(String ignored) { outputFailed(DiagnosticCode.AUDIO_INIT); }
                    @Override public void onWebRtcAudioTrackStartError(JavaAudioDeviceModule.AudioTrackStartErrorCode ignoredCode,
                            String ignored) { outputFailed(DiagnosticCode.AUDIO_START); }
                    @Override public void onWebRtcAudioTrackError(String ignored) { outputFailed(DiagnosticCode.AUDIO_RUNTIME); }
                })
                .setAudioRecordStateCallback(new JavaAudioDeviceModule.AudioRecordStateCallback() {
                    @Override public void onWebRtcAudioRecordStart() { record(Stage.AUDIO_CALLBACK, Category.NATIVE, DiagnosticCode.RECORDING_STARTED); fail(); }
                    @Override public void onWebRtcAudioRecordStop() { }
                }).createAudioDeviceModule(); }
        catch (RuntimeException | LinkageError uncertain) { allocationUncertain = true; throw uncertain; }
        // Disable actual AudioRecord creation before the ADM native pointer is given to a factory.
        adm.setAudioRecordEnabled(false); adm.setMicrophoneMute(true); adm.setSpeakerMute(true);
        demandLive();
        diagnosticStage = Stage.FACTORY_CREATE;
        try { factory = PeerConnectionFactory.builder().setAudioDeviceModule(adm)
                .setVideoDecoderFactory(new DefaultVideoDecoderFactory(null)).createPeerConnectionFactory(); }
        catch (RuntimeException | LinkageError uncertain) { allocationUncertain = true; throw uncertain; }
        demandLive();
        PeerConnection.RTCConfiguration configuration = new PeerConnection.RTCConfiguration(iceServers);
        configuration.sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN;
        configuration.bundlePolicy = PeerConnection.BundlePolicy.MAXBUNDLE;
        configuration.rtcpMuxPolicy = PeerConnection.RtcpMuxPolicy.REQUIRE;
        configuration.continualGatheringPolicy = PeerConnection.ContinualGatheringPolicy.GATHER_CONTINUALLY;
        configuration.iceCandidatePoolSize = 0;
        diagnosticStage = Stage.PEER_CREATE;
        try { peer = factory.createPeerConnection(configuration, peerObserver()); }
        catch (RuntimeException | LinkageError uncertain) { allocationUncertain = true; throw uncertain; }
        if (peer == null) { allocationUncertain = true; throw new Refused(); }
        peer.setAudioRecording(false); peer.setAudioPlayout(false); demandLive();
    }
    private void applyOffer(String text) throws Exception {
        // The trusted factory composition supplies the exact stored IDs/keys. The unforgeable
        // credential was derived only after signed host-response verification over the exact
        // persisted request; direction-bound AEAD authenticates this offer's DTLS fingerprint.
        // Current Mac emits no separate identity packet; any optional assertion was checked above.
        demandLive(); if (!brokerReady || !credentialAdmitted || peer != null) throw new Refused();
        diagnosticStage = Stage.OFFER_PARSE;
        WebRtcViewerSdp.Description offer = WebRtcViewerSdp.offer(text);
        allocatePeer();
        diagnosticStage = Stage.SET_REMOTE;
        CompletableFuture<SessionDescription> setRemote = new CompletableFuture<>();
        pendingSDP.incrementAndGet();
        SdpObserver remoteOperation = sdp(setRemote, false, Stage.SET_REMOTE);
        try { peer.setRemoteDescription(remoteOperation, new SessionDescription(SessionDescription.Type.OFFER, offer.text)); }
        catch (RuntimeException refused) { remoteOperation.onSetFailure(null); throw refused; }
        await(setRemote, startupDeadline, true); demandLive(); remoteDescription = offer;
        diagnosticStage = Stage.TRANSCEIVER_BIND;
        // getTransceivers disposes prior returned wrappers. Obtain ONCE; peer owns their disposal.
        transceivers = peer.getTransceivers(); Set<String> observed = new HashSet<>();
        for (RtpTransceiver transceiver : transceivers) {
            WebRtcViewerSdp.Section section = offer.locate(transceiver.getMid(), null);
            if (!observed.add(section.mid) || "application".equals(section.kind) || transceiver.getSender().track() != null) throw new Refused();
            if (!transceiver.setDirection(section.receivesMedia()
                    ? RtpTransceiver.RtpTransceiverDirection.RECV_ONLY : RtpTransceiver.RtpTransceiverDirection.INACTIVE)) throw new Refused();
            if (section == offer.audio) {
                preferCodec(transceiver, MediaStreamTrack.MediaType.MEDIA_TYPE_AUDIO, false);
                MediaStreamTrack track = transceiver.getReceiver().track();
                if (!(track instanceof AudioTrack) || !"system-audio".equals(track.id())) throw new Refused();
                audio = (AudioTrack) track; audio.setEnabled(false);
            } else if (section == offer.video) {
                preferCodec(transceiver, MediaStreamTrack.MediaType.MEDIA_TYPE_VIDEO, true);
                MediaStreamTrack track = transceiver.getReceiver().track();
                if (!(track instanceof VideoTrack)) throw new Refused(); video = (VideoTrack) track;
                video.addSink(frameObserver); // Borrowed frame callback; NO queued/replayed PCM/frame.
            }
        }
        if (audio == null || video == null || observed.size() != offer.sections.size() - 1) throw new Refused();
        while (!remoteCandidates.isEmpty()) addRemote(remoteCandidates.removeFirst());
        diagnosticStage = Stage.CREATE_ANSWER;
        CompletableFuture<SessionDescription> createAnswer = new CompletableFuture<>(); pendingSDP.incrementAndGet();
        SdpObserver answerOperation = sdp(createAnswer, true, Stage.CREATE_ANSWER);
        try { peer.createAnswer(answerOperation, new MediaConstraints()); }
        catch (RuntimeException refused) { answerOperation.onCreateFailure(null); throw refused; }
        SessionDescription nativeAnswer = await(createAnswer, startupDeadline, true); demandLive();
        if (nativeAnswer == null || nativeAnswer.type != SessionDescription.Type.ANSWER) throw new Refused();
        diagnosticStage = Stage.ANSWER_VALIDATE;
        WebRtcViewerSdp.Description answer = WebRtcViewerSdp.stereoAnswer(nativeAnswer.description, offer);
        CompletableFuture<SessionDescription> setLocal = new CompletableFuture<>(); pendingSDP.incrementAndGet();
        diagnosticStage = Stage.SET_LOCAL;
        SdpObserver localOperation = sdp(setLocal, false, Stage.SET_LOCAL);
        try { peer.setLocalDescription(localOperation, new SessionDescription(SessionDescription.Type.ANSWER, answer.text)); }
        catch (RuntimeException refused) { localOperation.onSetFailure(null); throw refused; }
        await(setLocal, startupDeadline, true); demandLive(); localDescription = answer;
        send(MediaSignalPayload.answer(answer.text)); answered = true;
        while (!localCandidates.isEmpty()) sendLocal(localCandidates.removeFirst());
    }
    private void preferCodec(RtpTransceiver transceiver, MediaStreamTrack.MediaType kind, boolean h264) throws Refused {
        RtpCapabilities capability = factory.getRtpReceiverCapabilities(kind);
        List<RtpCapabilities.CodecCapability> codecs = new ArrayList<>(); boolean primary = false;
        for (RtpCapabilities.CodecCapability codec : capability.codecs) {
            String mime = codec.mimeType == null ? "" : codec.mimeType;
            if ((!h264 && mime.equalsIgnoreCase("audio/opus")) || (h264 && mime.equalsIgnoreCase("video/H264"))) {
                codecs.add(codec); primary = true;
            } else if (h264 && (mime.equalsIgnoreCase("video/rtx") || mime.equalsIgnoreCase("video/red")
                    || mime.equalsIgnoreCase("video/ulpfec") || mime.equalsIgnoreCase("video/flexfec-03"))) codecs.add(codec);
        }
        if (!primary) throw new Refused();
        RtcError applied = transceiver.setCodecPreferences(codecs);
        if (applied == null || !applied.isSuccess()) throw new Refused();
    }
    private SdpObserver sdp(CompletableFuture<SessionDescription> result, boolean creating, Stage operation) {
        AtomicBoolean delivered = new AtomicBoolean();
        return new SdpObserver() {
            private void finish(SessionDescription description, boolean success) {
                callbacks.incrementAndGet();
                try {
                    if (!delivered.compareAndSet(false, true)) { record(operation, Category.CALLBACK, DiagnosticCode.SDP_DUPLICATE); fail(); return; }
                    pendingSDP.decrementAndGet();
                    if (!success) record(operation, Category.NATIVE, DiagnosticCode.SDP_FAILED);
                    if (success) result.complete(description); else result.completeExceptionally(new Refused());
                } finally { callbacks.decrementAndGet(); synchronized (mailbox) { mailbox.notifyAll(); } }
            }
            @Override public void onCreateSuccess(SessionDescription description) { finish(description, creating); }
            @Override public void onSetSuccess() { finish(null, !creating); }
            @Override public void onCreateFailure(String ignored) { finish(null, false); }
            @Override public void onSetFailure(String ignored) { finish(null, false); }
        };
    }
    private void remoteCandidate(MediaSignalPayload.Candidate candidate) throws Exception {
        diagnosticStage = Stage.REMOTE_ICE;
        if (candidate == null || (candidate.sdpMid() == null && candidate.sdpMLineIndex() == null)
                || (candidate.sdpMid() != null && (candidate.sdpMid().isEmpty() || hasWhitespace(candidate.sdpMid())))) throw new Refused();
        if (remoteDescription == null) {
            if (remoteCandidates.size() == MAXIMUM_CANDIDATES) throw new Refused(); remoteCandidates.addLast(candidate);
        } else addRemote(candidate);
    }
    private static boolean hasWhitespace(String value) {
        for (int i = 0; i < value.length(); i++) if (Character.isWhitespace(value.charAt(i))) return true; return false;
    }
    private void addRemote(MediaSignalPayload.Candidate value) throws Exception {
        diagnosticStage = Stage.REMOTE_ICE;
        demandLive();
        // Exactly one offer generation; no restart/replacement exists to guess an untagged epoch.
        MediaSignalPayload.Candidate candidate = WebRtcViewerSdp.candidate(remoteDescription, value, false);
        if (!peer.addIceCandidate(new IceCandidate(candidate.sdpMid(), candidate.sdpMLineIndex(), candidate.sdp()))) throw new Refused();
    }
    private void sendLocal(MediaSignalPayload.Candidate value) throws Exception {
        diagnosticStage = Stage.LOCAL_ICE;
        if (!answered || localDescription == null) {
            if (localCandidates.size() == MAXIMUM_CANDIDATES) throw new Refused(); localCandidates.addLast(value); return;
        }
        diagnosticStage = Stage.LOCAL_ICE_BIND;
        send(MediaSignalPayload.candidate(WebRtcViewerSdp.candidate(localDescription, value, false)));
    }
    private PeerConnection.Observer peerObserver() {
        return new PeerConnection.Observer() {
            private void observed(Runnable event) {
                callbacks.incrementAndGet();
                try { event.run(); } catch (RuntimeException refused) { fail(); }
                finally { callbacks.decrementAndGet(); synchronized (mailbox) { mailbox.notifyAll(); } }
            }
            private void wake() { enqueue(0, () -> { }); }
            @Override public void onSignalingChange(PeerConnection.SignalingState value) {
                observed(() -> { if (value == PeerConnection.SignalingState.CLOSED && !closing.get()) {
                    record(Stage.PEER_CALLBACK, Category.NATIVE, value); fail();
                } else wake(); });
            }
            @Override public void onIceConnectionChange(PeerConnection.IceConnectionState value) {
                observed(() -> {
                if (value == PeerConnection.IceConnectionState.DISCONNECTED || value == PeerConnection.IceConnectionState.FAILED
                        || value == PeerConnection.IceConnectionState.CLOSED) { if (!closing.get()) {
                    record(Stage.ICE_CALLBACK, Category.NATIVE, value); fail();
                } } else wake();
                });
            }
            @Override public void onConnectionChange(PeerConnection.PeerConnectionState value) {
                observed(() -> {
                if (value == PeerConnection.PeerConnectionState.DISCONNECTED || value == PeerConnection.PeerConnectionState.FAILED
                        || value == PeerConnection.PeerConnectionState.CLOSED) { if (!closing.get()) {
                    record(Stage.PEER_CALLBACK, Category.NATIVE, value); fail();
                } } else wake();
                });
            }
            @Override public void onIceConnectionReceivingChange(boolean receiving) { observed(this::wake); }
            @Override public void onIceGatheringChange(PeerConnection.IceGatheringState state) { observed(this::wake); }
            @Override public void onIceCandidate(IceCandidate candidate) {
                observed(() -> {
                if (candidate == null || candidate.sdp == null || candidate.sdp.length() > 8_192) {
                    DiagnosticCode code = candidate == null ? DiagnosticCode.NATIVE_CANDIDATE_NULL
                            : candidate.sdp == null ? DiagnosticCode.NATIVE_CANDIDATE_SDP_NULL
                            : DiagnosticCode.NATIVE_CANDIDATE_SDP_TOO_LONG;
                    record(Stage.LOCAL_ICE_CALLBACK_SHAPE, Category.VALIDATION, code); fail(); return;
                }
                Stage callbackStage = Stage.LOCAL_ICE_CALLBACK_FRAGMENT;
                try {
                    String fragment = WebRtcViewerSdp.candidateFragment(candidate.sdp);
                    callbackStage = Stage.LOCAL_ICE_CALLBACK_PAYLOAD;
                    MediaSignalPayload.Candidate owned = new MediaSignalPayload.Candidate(candidate.sdp, candidate.sdpMid,
                            candidate.sdpMLineIndex, fragment);
                    enqueue(candidate.sdp.length(), () -> sendLocal(owned));
                } catch (RuntimeException refused) {
                    if (callbackStage == Stage.LOCAL_ICE_CALLBACK_PAYLOAD && refused instanceof IllegalArgumentException)
                        record(callbackStage, Category.VALIDATION, DiagnosticCode.NATIVE_CANDIDATE_PAYLOAD_INVALID);
                    else recordException(callbackStage, refused);
                    fail();
                }
                });
            }
            @Override public void onIceCandidatesRemoved(IceCandidate[] candidates) { observed(() -> { }); }
            @Override public void onAddStream(MediaStream stream) { observed(() -> { }); }
            @Override public void onRemoveStream(MediaStream stream) { observed(() -> { if (!closing.get()) {
                record(Stage.PEER_CALLBACK, Category.NATIVE, DiagnosticCode.TRACK_REMOVED); fail();
            } }); }
            @Override public void onAddTrack(RtpReceiver receiver, MediaStream[] streams) { observed(this::wake); }
            @Override public void onRemoveTrack(RtpReceiver receiver) { observed(() -> { if (!closing.get()) {
                record(Stage.PEER_CALLBACK, Category.NATIVE, DiagnosticCode.TRACK_REMOVED); fail();
            } }); }
            @Override public void onTrack(RtpTransceiver borrowed) {
                // The SDK automatically disposes this wrapper after this callback. Never retain it.
                observed(this::wake);
            }
            @Override public void onDataChannel(DataChannel channel) { captureChannel(channel); }
            @Override public void onRenegotiationNeeded() { observed(() -> { }); }
        };
    }
    private void captureChannel(DataChannel channel) {
        callbacks.incrementAndGet();
        try {
            if (channel == null) { fail(); return; }
            boolean overflow;
            synchronized (mailbox) { overflow = ownedChannels.size() == MAXIMUM_CHANNELS; if (!overflow) ownedChannels.add(channel); }
            if (overflow) {
                fail();
                // This transferred wrapper cannot be abandoned. Only this channel, NOT the peer,
                // is disposed in the callback; peer disposal is always on the serial worker.
                try { channel.close(); channel.dispose(); } catch (RuntimeException uncertain) { allocationUncertain = true; }
                return;
            }
            enqueue(0, () -> {
                diagnosticStage = Stage.CONTROL_CALLBACK;
                if (!CONTROL_LABEL.equals(channel.label())) { disposeChannel(channel); return; }
                if (control != null || peer == null || video == null) throw new Refused(); control = channel;
                final PeerConnection boundPeer = peer;
                final VideoTrack boundTrack = video;
                final ViewerScreenSession boundScreen = new ViewerScreenSession(boundPeer, channel, boundTrack,
                        (bytes, guard) -> sendControl(boundPeer, channel, bytes, guard), System::nanoTime,
                        reason -> { record(Stage.CONTROL_CALLBACK, Category.CALLBACK, reason); fail(); });
                screenSession = boundScreen;
                screenBinding = new ScreenBinding(boundScreen, boundPeer, channel, boundTrack);
                if (!live()) { boundScreen.close(); throw new Refused(); }
                channel.registerObserver(new DataChannel.Observer() {
                    @Override public void onBufferedAmountChange(long previous) { }
                    @Override public void onStateChange() {
                        callbacks.incrementAndGet();
                        try {
                            DataChannel.State state = channel.state();
                            if (state == DataChannel.State.CLOSING || state == DataChannel.State.CLOSED) { if (!closing.get()) {
                                record(Stage.CONTROL_CALLBACK, Category.NATIVE, state); fail();
                            } }
                            else enqueue(0, () -> { });
                        } catch (RuntimeException refused) { recordException(Stage.CONTROL_CALLBACK, refused); fail(); }
                        finally { callbacks.decrementAndGet(); }
                    }
                    @Override public void onMessage(DataChannel.Buffer buffer) {
                        callbacks.incrementAndGet();
                        try {
                            if (buffer == null || buffer.binary || buffer.data == null
                                    || buffer.data.remaining() == 0
                                    || buffer.data.remaining() > ViewerScreenControlCodec.MAXIMUM_MESSAGE_BYTES) {
                                record(Stage.CONTROL_CALLBACK, Category.VALIDATION, DiagnosticCode.CONTROL_PROTOCOL); fail(); return;
                            }
                            ByteBuffer borrowed = buffer.data.duplicate();
                            byte[] owned = new byte[borrowed.remaining()]; borrowed.get(owned);
                            if (!enqueue(owned.length, () -> {
                                try {
                                    diagnosticStage = Stage.CONTROL_CALLBACK;
                                    demandLive();
                                    if (peer != boundPeer || control != channel || video != boundTrack
                                            || screenSession != boundScreen) throw new Refused();
                                    boundScreen.receive(boundPeer, channel, owned);
                                } finally { Arrays.fill(owned, (byte) 0); }
                            })) Arrays.fill(owned, (byte) 0);
                        } catch (RuntimeException refused) {
                            recordException(Stage.CONTROL_CALLBACK, refused);
                            fail();
                        } finally { callbacks.decrementAndGet(); }
                    }
                });
            });
        } finally { callbacks.decrementAndGet(); synchronized (mailbox) { mailbox.notifyAll(); } }
    }
    private final VideoSink frameObserver = new VideoSink() {
        @Override public void onFrame(VideoFrame borrowed) {
            callbacks.incrementAndGet();
            try {
                if (borrowed != null && live()) {
                    SurfaceSlot slot = surfaceSlot;
                    WebRtcVideoSurface surface = slot == null ? null : slot.surface;
                    // The surface validates the exact current Show/scene lease before retaining.
                    if (surface != null) surface.onFrame(borrowed);
                }
            } catch (RuntimeException | LinkageError refused) {
                recordException(Stage.VIDEO_CALLBACK, refused);
                fail();
            } finally { callbacks.decrementAndGet(); }
        }
    };
    /** Native operations stay on the serial receiver worker; caller never owns its channel. */
    private CompletionStage<Void> sendControl(PeerConnection boundPeer, DataChannel boundChannel,
            byte[] bytes, BooleanSupplier authorized) {
        CompletableFuture<Void> result = new CompletableFuture<>();
        if (bytes == null || bytes.length == 0 || bytes.length > ViewerScreenControlCodec.MAXIMUM_MESSAGE_BYTES
                || authorized == null || !live() || !pendingControlWrite.compareAndSet(null, result)) {
            result.completeExceptionally(new Refused()); return result;
        }
        byte[] owned = bytes.clone();
        if (!enqueue(owned.length, () -> {
            try {
                demandLive();
                if (peer != boundPeer || control != boundChannel || !nativeHealthy()
                        || boundChannel.bufferedAmount() < 0 || boundChannel.bufferedAmount() >= 262_144
                        || !authorized.getAsBoolean()) throw new Refused();
                if (!boundChannel.send(new DataChannel.Buffer(ByteBuffer.wrap(owned), false))) throw new Refused();
                demandLive();
                pendingControlWrite.compareAndSet(result, null);
                result.complete(null);
            } catch (Exception refusal) {
                pendingControlWrite.compareAndSet(result, null);
                result.completeExceptionally(new Refused());
            } finally { Arrays.fill(owned, (byte) 0); }
        })) {
            pendingControlWrite.compareAndSet(result, null);
            Arrays.fill(owned, (byte) 0); result.completeExceptionally(new Refused());
        }
        return result;
    }
    private boolean nativeHealthy() {
        return peer != null && control != null
                && peer.connectionState() == PeerConnection.PeerConnectionState.CONNECTED
                && (peer.iceConnectionState() == PeerConnection.IceConnectionState.CONNECTED
                    || peer.iceConnectionState() == PeerConnection.IceConnectionState.COMPLETED)
                && peer.signalingState() == PeerConnection.SignalingState.STABLE
                && control.state() == DataChannel.State.OPEN;
    }
    private void checkReady() throws Exception {
        if (peer == null || !answered || !credentialAdmitted || !brokerReady || control == null) return;
        diagnosticStage = Stage.HEALTH_ADMISSION;
        demandLive();
        boolean healthy = nativeHealthy();
        if (!healthy) { if (active) throw new Refused(); return; }
        cancellation.admit(() -> {
            if (screenSession == null || !screenSession.admitHealthy(peer, control)) throw new Refused();
        });
        if (!playout) {
            diagnosticStage = Stage.ACTIVE_PLAYOUT;
            demandLive(); audio.setEnabled(true); adm.setSpeakerMute(true);
            output.markPlayoutRequested(); peer.setAudioPlayout(true);
            // Native work is not an atomic parent cancellation barrier. Revoke always wins the
            // subsequent admission; a raced enable is immediately disabled by worker drainage.
            demandLive(); playout = true;
        }
        if (!output.authorized()) { if (active) throw new Refused(); return; }
        if (!active) {
            demandLive(); adm.setSpeakerMute(false);
            demandLive(); if (failed.get() || !output.authorized()) throw new Refused(); active = true;
            demandLive(); if (failed.get()) throw new Refused();
            // A failure accepted immediately after this check synchronously retires the parent;
            // its active() admission then refuses this raced notification. No receiver lock is
            // held across either callback, and native teardown still has its separate future.
            listener.active();
        }
    }
    private <T> T await(CompletableFuture<T> future, long deadline, boolean requireLive) throws Exception {
        while (true) {
            if (requireLive) demandLive();
            long remaining = deadline - System.nanoTime(); if (remaining <= 0) throw new Refused();
            try { return future.get(Math.min(remaining, 50_000_000L), TimeUnit.NANOSECONDS); }
            catch (TimeoutException pending) { /* Bounded cancellation recheck; no arbitrary callback joins. */ }
            catch (InterruptedException stopped) { interrupted = true; throw stopped; }
            catch (ExecutionException refused) {
                recordException(requireLive ? diagnosticStage : Stage.DRAIN, refused.getCause()); throw new Refused();
            }
        }
    }
    private void disposeChannel(DataChannel exact) {
        exact.unregisterObserver(); exact.close(); exact.dispose();
        synchronized (mailbox) { ownedChannels.remove(exact); }
        if (control == exact) control = null;
    }
    private void quarantine() {
        synchronized (PROCESS_NATIVE_LOCK) {
            QUARANTINED.add(this); processInitializationFailed = true;
        }
    }
    private boolean drain() throws Exception {
        long deadline = System.nanoTime() + DRAIN_NANOS;
        boolean clean = !allocationUncertain, stopReturned = true;
        if (audio != null) try { audio.setEnabled(false); }
        catch (RuntimeException | LinkageError refused) { clean = false; }
        if (adm != null) try { adm.setSpeakerMute(true); adm.setAudioRecordEnabled(false); }
        catch (RuntimeException | LinkageError refused) { clean = false; }
        if (peer != null) {
            try { peer.setAudioPlayout(false); peer.setAudioRecording(false); }
            catch (RuntimeException | LinkageError refused) { clean = false; stopReturned = false; }
        }
        // StopPlayout's native Boolean is not exposed by PeerConnection. The exact Java receipt,
        // or proof that playout was never requested, must precede ANY native graph destruction.
        boolean outputStopped = stopReturned && output.finishOutputStop();
        boolean mayDisposeNative = clean && outputStopped;
        if (!outputStopped) { output.cleanupUnproved(); clean = false; }
        if (!mayDisposeNative) quarantine();
        else if (peer != null) {
            try { peer.close(); }
            catch (RuntimeException | LinkageError refused) { clean = false; mayDisposeNative = false; quarantine(); }
        }
        CompletableFuture<Void> socketClose = socket == null ? CompletableFuture.completedFuture(null)
                : socket.closeAsync().toCompletableFuture();
        while ((pendingSDP.get() != 0 || callbacks.get() != 0) && System.nanoTime() - deadline < 0) {
            synchronized (mailbox) { mailbox.wait(20); }
        }
        if (pendingSDP.get() != 0 || callbacks.get() != 0) { clean = false; mayDisposeNative = false; quarantine(); }
        if (mayDisposeNative && video != null) try { video.removeSink(frameObserver); }
        catch (RuntimeException | LinkageError refused) { clean = false; mayDisposeNative = false; quarantine(); }
        boolean presentationDrained = true;
        SurfaceSlot slot = surfaceSlot;
        if (slot != null) try {
            WebRtcVideoSurface surface = await(slot.constructed, deadline, false);
            await(surface.closeAsync().toCompletableFuture(), deadline, false);
        } catch (Exception unproved) { clean = false; presentationDrained = false; quarantine(); }
        // The output receipt drives main-owner cleanup; it must never wait on this final future.
        try { await(output.drained().toCompletableFuture(), deadline, false); }
        catch (Exception unproved) { clean = false; mayDisposeNative = false; quarantine(); }
        DataChannel[] channels;
        synchronized (mailbox) { channels = ownedChannels.toArray(new DataChannel[0]); tasks.clear(); taskBytes = 0; }
        if (mayDisposeNative && presentationDrained) {
            for (DataChannel channel : channels) try { disposeChannel(channel); }
            catch (RuntimeException | LinkageError refused) { clean = false; mayDisposeNative = false; quarantine(); break; }
            if (mayDisposeNative && pendingSDP.get() == 0 && callbacks.get() == 0) {
                if (peer != null) try { peer.dispose(); peer = null; transceivers = Collections.emptyList(); audio = null; video = null; }
                catch (RuntimeException | LinkageError refused) { clean = false; quarantine(); }
                if (peer == null && factory != null) try { factory.dispose(); factory = null; }
                catch (RuntimeException | LinkageError refused) { clean = false; quarantine(); }
                if (factory == null && adm != null) try { adm.release(); adm = null; }
                catch (RuntimeException | LinkageError refused) { clean = false; quarantine(); }
            }
            // A wrapper transferred across peer disposal still belongs to this exact receiver.
            if (peer == null) {
                synchronized (mailbox) { channels = ownedChannels.toArray(new DataChannel[0]); }
                for (DataChannel channel : channels) try { disposeChannel(channel); }
                catch (RuntimeException | LinkageError refused) { clean = false; quarantine(); }
            }
        }
        try { await(socketClose, deadline, false); } catch (Exception refused) { clean = false; }
        if (callbacks.get() != 0 || pendingSDP.get() != 0 || peer != null || factory != null || adm != null) clean = false;
        synchronized (mailbox) { if (!ownedChannels.isEmpty()) clean = false; }
        if (codec != null) codec.close(); else credential.close();
        iceServers = Collections.emptyList(); remoteDescription = null; localDescription = null;
        remoteCandidates.clear(); localCandidates.clear(); Arrays.fill(viewerKey, (byte) 0); Arrays.fill(hostKey, (byte) 0);
        if (!clean) quarantine();
        return clean;
    }
}
