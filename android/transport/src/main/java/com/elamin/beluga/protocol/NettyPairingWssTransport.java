package com.elamin.beluga.protocol;

import io.netty.bootstrap.Bootstrap;
import io.netty.buffer.Unpooled;
import io.netty.buffer.UnpooledByteBufAllocator;
import io.netty.channel.Channel;
import io.netty.channel.ChannelFuture;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import io.netty.channel.ChannelInitializer;
import io.netty.channel.ChannelOption;
import io.netty.channel.ChannelPipeline;
import io.netty.channel.EventLoop;
import io.netty.channel.EventLoopGroup;
import io.netty.channel.FixedRecvByteBufAllocator;
import io.netty.channel.MultiThreadIoEventLoopGroup;
import io.netty.channel.SimpleChannelInboundHandler;
import io.netty.channel.WriteBufferWaterMark;
import io.netty.channel.nio.NioIoHandler;
import io.netty.channel.socket.SocketChannel;
import io.netty.channel.socket.nio.NioSocketChannel;
import io.netty.handler.codec.http.DefaultHttpHeaders;
import io.netty.handler.codec.http.FullHttpResponse;
import io.netty.handler.codec.http.HttpClientCodec;
import io.netty.handler.codec.http.HttpHeaderNames;
import io.netty.handler.codec.http.HttpHeaders;
import io.netty.handler.codec.http.HttpObjectAggregator;
import io.netty.handler.codec.http.websocketx.BinaryWebSocketFrame;
import io.netty.handler.codec.http.websocketx.CloseWebSocketFrame;
import io.netty.handler.codec.http.websocketx.ContinuationWebSocketFrame;
import io.netty.handler.codec.http.websocketx.PingWebSocketFrame;
import io.netty.handler.codec.http.websocketx.PongWebSocketFrame;
import io.netty.handler.codec.http.websocketx.TextWebSocketFrame;
import io.netty.handler.codec.http.websocketx.WebSocketClientHandshaker;
import io.netty.handler.codec.http.websocketx.WebSocketClientHandshakerFactory;
import io.netty.handler.codec.http.websocketx.WebSocketFrame;
import io.netty.handler.codec.http.websocketx.WebSocketFrameAggregator;
import io.netty.handler.codec.http.websocketx.WebSocketVersion;
import io.netty.handler.ssl.SslHandler;
import io.netty.util.ReferenceCountUtil;
import io.netty.util.concurrent.ScheduledFuture;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.URI;
import java.net.URISyntaxException;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.BooleanSupplier;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLEngine;
import javax.net.ssl.SSLParameters;

/**
 * Profile-bound pairing or saved-pair availability WSS transport. HTTP101 is only transport evidence.
 * Listener callbacks must return promptly and never block awaiting a transport completion.
 * There is no reconnect, protocol parser, persistence, media, logging or permission request here.
 */
public final class NettyPairingWssTransport {
    public static final String PRODUCTION_ORIGIN = "wss://audiostreamer-rendezvous.elaminahmed03.workers.dev";
    public static final String SUBPROTOCOL = "audiostreamer.pairing.v1";
    public static final String AVAILABILITY_SUBPROTOCOL = "audiostreamer.availability.v1";
    static final String HOST = "audiostreamer-rendezvous.elaminahmed03.workers.dev";
    static final int MAXIMUM_MESSAGE_BYTES = 90_000;
    static final int MAXIMUM_FRAGMENTS = 64;
    static final int MAXIMUM_PENDING_SENDS = 4;
    static final int MAXIMUM_PENDING_SEND_BYTES = 360_000;
    static final int MAXIMUM_PENDING_CONTROLS = 4;
    static final long OPEN_TIMEOUT_SECONDS = 30;
    static final long WRITE_TIMEOUT_SECONDS = 10;
    static final long FRAGMENT_TIMEOUT_SECONDS = 10;

    private enum Profile {
        PAIRING("/v1/rendezvous", SUBPROTOCOL),
        AVAILABILITY("/v2/availability", AVAILABILITY_SUBPROTOCOL);
        final String path, subprotocol;
        Profile(String path, String subprotocol) { this.path = path; this.subprotocol = subprotocol; }
    }

    public enum FailureCode {
        INVALID_ENDPOINT, INVALID_HEADERS, TLS_CONFIGURATION, CONNECT_FAILED, RESOLVER_BUSY, OPEN_TIMEOUT,
        UPGRADE_REFUSED, INVALID_FRAME, MESSAGE_TOO_LARGE, FRAGMENT_LIMIT, FRAGMENT_TIMEOUT,
        INVALID_TEXT, NOT_OPEN, SEND_BACKPRESSURE, WRITE_FAILED, WRITE_TIMEOUT,
        CALLBACK_FAILED, REMOTE_CLOSED, CLOSED, DRAIN_FAILED
    }

    public static final class TransportFailure extends Exception {
        private static final long serialVersionUID = 1L;
        private final FailureCode code;
        private TransportFailure(FailureCode code) {
            super("Beluga pairing socket refused: " + code.name()); this.code = code;
        }
        public FailureCode code() { return code; }
    }

    public interface Listener {
        void onOpen();
        /** Owns one bounded copy; no later transport mutation of this array occurs. */
        void onText(byte[] utf8);
        /**
         * Called once after the owned cleanup barriers finish. DRAIN_FAILED means cleanup is
         * unproved, not a clean close or replacement authority; closeAsync also fails.
         */
        void onTerminal(FailureCode reason);
    }

    private final URI url;
    private final Profile profile;
    private final Listener listener;
    private final EventLoopGroup group;
    private final CompletableFuture<Void> opened = new CompletableFuture<>();
    private final CompletableFuture<Void> drained = new CompletableFuture<>();
    private final CompletableFuture<ProcessPairingDnsResolver.Registration> registrationPublished =
            new CompletableFuture<>();
    private final CompletableFuture<Void> registrationDrained = new CompletableFuture<>();
    private final CompletableFuture<Void> loopDrained = new CompletableFuture<>();
    private final CompletableFuture<Void> socketDrained = new CompletableFuture<>();
    private final AtomicBoolean retired = new AtomicBoolean();
    private final AtomicBoolean closeStarted = new AtomicBoolean();
    private final Object sendLock = new Object();
    private final Set<Send> sends = new LinkedHashSet<>();
    private int sendBytes;
    private volatile Channel channel;
    private volatile FailureCode terminalReason = FailureCode.CLOSED;
    private volatile boolean isOpen;
    private ScheduledFuture<?> openDeadline;

    private NettyPairingWssTransport(URI url, Profile profile, Listener listener, EventLoopGroup group) {
        this.url = url; this.profile = profile; this.listener = listener; this.group = group;
        // A null channel at retirement alone proves nothing: a claimed or queued DNS delivery
        // could still be running. Only detached handoff AND terminated loop prove no allocator
        // can publish a channel later. Neither may overwrite a failed first native close.
        CompletableFuture.allOf(registrationDrained, loopDrained).whenComplete((ignored, error) -> {
            if (error != null) socketDrained.completeExceptionally(failure(FailureCode.DRAIN_FAILED));
            else if (channel == null) socketDrained.complete(null);
        });
        CompletableFuture.allOf(registrationDrained, loopDrained, socketDrained)
                .whenComplete((ignored, error) -> finishDrain(error));
    }

    /** Validates trusted configuration/capabilities before allocating a network owner. */
    public static NettyPairingWssTransport connect(String endpoint,
            PairingBootstrapEnvelopeCodec.JoinHeaders join, Listener listener) throws TransportFailure {
        URI url = endpoint(endpoint);
        HttpHeaders headers = upgradeHeaders(join);
        return connectValidated(url, Profile.PAIRING, headers, listener);
    }

    /** Saved-pair viewer availability; never reinterprets bootstrap headers or route. */
    public static NettyPairingWssTransport connectAvailability(String endpoint,
            ViewerAvailabilityEnvelopeCodec.JoinHeaders join, Listener listener) throws TransportFailure {
        URI url = availabilityEndpoint(endpoint);
        HttpHeaders headers = availabilityUpgradeHeaders(join);
        return connectValidated(url, Profile.AVAILABILITY, headers, listener);
    }

    private static NettyPairingWssTransport connectValidated(URI url, Profile profile,
            HttpHeaders headers, Listener listener) throws TransportFailure {
        if (listener == null) throw failure(FailureCode.INVALID_HEADERS);
        SSLEngine engine = tlsEngine();
        MultiThreadIoEventLoopGroup group = new MultiThreadIoEventLoopGroup(1, NioIoHandler.newFactory());
        NettyPairingWssTransport result = new NettyPairingWssTransport(url, profile, listener, group);
        result.start(ProcessPairingDnsResolver.process(),
                (owner, address) -> owner.connectResolved(address, headers, engine), () -> { });
        return result;
    }

    private void start(ProcessPairingDnsResolver resolver, ResolvedConnector connector,
            Runnable afterRegisterBeforePublish) {
        group.terminationFuture().addListener(future -> {
            if (future.isSuccess()) loopDrained.complete(null);
            else loopDrained.completeExceptionally(failure(FailureCode.DRAIN_FAILED));
        });
        try {
            EventLoop loop = group.next();
            openDeadline = loop.schedule(
                    () -> retire(FailureCode.OPEN_TIMEOUT), OPEN_TIMEOUT_SECONDS, TimeUnit.SECONDS);
            ProcessPairingDnsResolver.Registration registration = resolver.register(loop, result -> {
                // Resolver delivery is fenced to this registration on this exact loop. Do not
                // attach an allocating continuation to registrationPublished: its completing
                // thread can be the caller, not the owned loop.
                if (retired.get()) return;
                if (!loop.inEventLoop() || !result.isSuccess()) {
                    retire(FailureCode.CONNECT_FAILED); return;
                }
                try { connector.connect(this, result.address()); }
                catch (Exception ignored) { retire(FailureCode.CONNECT_FAILED); }
            });
            try { afterRegisterBeforePublish.run(); }
            finally { registrationPublished.complete(registration); }
        } catch (ProcessPairingDnsResolver.ResolutionFailure error) {
            registrationPublished.complete(null);
            retire(error.code() == ProcessPairingDnsResolver.Failure.BUSY
                    ? FailureCode.RESOLVER_BUSY : FailureCode.CONNECT_FAILED);
        } catch (RuntimeException ignored) {
            registrationPublished.complete(null);
            retire(FailureCode.CONNECT_FAILED);
        }
    }

    public CompletionStage<Void> whenOpen() { return opened.thenApply(ignored -> null); }

    /** Success means the complete masked frame reached local transport write completion, not peer receipt. */
    public CompletionStage<Void> send(byte[] utf8) {
        return sendGuarded(utf8, () -> true);
    }

    /** Session-authorized send; queued writes recheck the exact retired-owner latch on the loop. */
    CompletionStage<Void> sendGuarded(byte[] utf8, BooleanSupplier authorized) {
        if (utf8 == null || utf8.length == 0 || utf8.length > MAXIMUM_MESSAGE_BYTES) {
            return refused(FailureCode.INVALID_TEXT);
        }
        Send send;
        synchronized (sendLock) {
            if (retired.get() || !isOpen) return refused(FailureCode.NOT_OPEN);
            try { if (authorized == null || !authorized.getAsBoolean()) return refused(FailureCode.NOT_OPEN); }
            catch (RuntimeException refused) { return refused(FailureCode.NOT_OPEN); }
            if (sends.size() == MAXIMUM_PENDING_SENDS
                    || utf8.length > MAXIMUM_PENDING_SEND_BYTES - sendBytes) {
                return refused(FailureCode.SEND_BACKPRESSURE);
            }
            send = new Send(utf8.clone(), authorized);
            sends.add(send); sendBytes += send.bytes.length;
        }
        try {
            requireUtf8(send.bytes);
            Channel owned = channel;
            if (owned == null) throw failure(FailureCode.NOT_OPEN);
            owned.eventLoop().execute(() -> write(owned, send));
        } catch (TransportFailure error) {
            finishSend(send, error.code());
        } catch (RejectedExecutionException ignored) {
            finishSend(send, FailureCode.NOT_OPEN);
        }
        return send.result.thenApply(ignored -> null);
    }

    /**
     * Retirement is synchronous; completion joins this registration, socket and loop. A platform
     * DNS lookup can remain process-owned and busy; success does not claim native DNS cancellation.
     */
    public CompletionStage<Void> closeAsync() {
        retire(FailureCode.CLOSED);
        return drained.thenApply(ignored -> null);
    }

    @Override public String toString() { return "<redacted Beluga pairing WSS transport>"; }

    private void connectResolved(InetAddress address, HttpHeaders headers, SSLEngine engine) {
        try {
            if (retired.get()) return;
            FixedRecvByteBufAllocator receive = new FixedRecvByteBufAllocator(8192);
            receive.maxMessagesPerRead(1);
            Bootstrap bootstrap = new Bootstrap().group(group).channelFactory(() -> {
                        // Publish before init/register/connect can fail. The native doClose latch also
                        // observes unsafe/forcible closes, whose closeFuture may never be completed.
                        try {
                            ObservedNioSocketChannel owned = new ObservedNioSocketChannel(socketDrained);
                            channel = owned;
                            return owned;
                        } catch (RuntimeException | Error error) {
                            // A constructor can have opened a native channel before failing, and
                            // its attempted cleanup is not observable through our doClose override.
                            // The later no-channel fallback must never relabel that as clean drain.
                            socketDrained.completeExceptionally(failure(FailureCode.DRAIN_FAILED));
                            throw error;
                        }
                    })
                    .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, 15_000)
                    .option(ChannelOption.TCP_NODELAY, true)
                    .option(ChannelOption.ALLOCATOR, new UnpooledByteBufAllocator(false))
                    .option(ChannelOption.RECVBUF_ALLOCATOR, receive)
                    .option(ChannelOption.WRITE_BUFFER_WATER_MARK, new WriteBufferWaterMark(90_000, 180_000))
                    .handler(new ChannelInitializer<SocketChannel>() {
                        @Override protected void initChannel(SocketChannel owned) {
                            if (retired.get()) { owned.close(); return; }
                            SslHandler tls = new SslHandler(engine);
                            tls.setHandshakeTimeoutMillis(15_000);
                            owned.pipeline().addLast("tls", tls);
                            installPipeline(owned, headers);
                            tls.handshakeFuture().addListener(future -> {
                                if (!future.isSuccess()) retire(FailureCode.CONNECT_FAILED);
                                else if (retired.get()) owned.close();
                                else beginUpgrade(owned);
                            });
                        }
                    });
            ChannelFuture connection = bootstrap.connect(new InetSocketAddress(address, 443));
            connection.addListener(future -> {
                if (!future.isSuccess()) retire(FailureCode.CONNECT_FAILED);
                else if (retired.get()) connection.channel().close();
            });
            if (retired.get()) connection.channel().close();
        } catch (Exception ignored) { retire(FailureCode.CONNECT_FAILED); }
    }

    /**
     * The pinned public subclass seam observes the real first native close, not closeFuture:
     * AbstractChannel marks closeFuture successful even when doClose throws, and a later
     * duplicate close promise may succeed. Neither can replace this first outcome.
     */
    private static final class ObservedNioSocketChannel extends NioSocketChannel {
        private final CompletableFuture<Void> firstNativeClose;
        ObservedNioSocketChannel(CompletableFuture<Void> firstNativeClose) {
            this.firstNativeClose = firstNativeClose;
        }
        @Override protected void doClose() throws Exception {
            try {
                super.doClose();
                firstNativeClose.complete(null);
            } catch (Exception | Error error) {
                firstNativeClose.completeExceptionally(failure(FailureCode.DRAIN_FAILED));
                throw error;
            }
        }
    }

    private void installPipeline(Channel owned, HttpHeaders headers) {
        ChannelPipeline pipeline = owned.pipeline();
        pipeline.addLast("http", new HttpClientCodec(4096, 8192, 4096));
        pipeline.addLast("http-body", new HttpObjectAggregator(4096));
        pipeline.addLast("upgrade", new UpgradeHandler(WebSocketClientHandshakerFactory.newHandshaker(
                url, WebSocketVersion.V13, profile.subprotocol, false, headers,
                MAXIMUM_MESSAGE_BYTES, true, false, 1000)));
        pipeline.addLast("frame-budget", new FrameBudget());
        WebSocketFrameAggregator aggregator = new WebSocketFrameAggregator(MAXIMUM_MESSAGE_BYTES);
        aggregator.setMaxCumulationBufferComponents(MAXIMUM_FRAGMENTS);
        pipeline.addLast("message-budget", aggregator);
        pipeline.addLast("delivery", new Delivery());
    }

    private void beginUpgrade(Channel owned) {
        UpgradeHandler handler = owned.pipeline().get(UpgradeHandler.class);
        if (handler == null || retired.get()) { retire(FailureCode.UPGRADE_REFUSED); return; }
        handler.handshaker.handshake(owned).addListener(future -> {
            if (!future.isSuccess()) retire(FailureCode.UPGRADE_REFUSED);
        });
    }

    private final class UpgradeHandler extends SimpleChannelInboundHandler<FullHttpResponse> {
        private final WebSocketClientHandshaker handshaker;
        UpgradeHandler(WebSocketClientHandshaker handshaker) { this.handshaker = handshaker; }
        @Override protected void channelRead0(ChannelHandlerContext context, FullHttpResponse response) {
            if (retired.get()) return;
            try {
                validateUpgrade(response, profile);
                handshaker.finishHandshake(context.channel(), response);
                context.pipeline().remove(this);
                if (retired.get()) return;
                isOpen = true;
                if (openDeadline != null) openDeadline.cancel(false);
                listener.onOpen();
                if (!retired.get()) opened.complete(null);
            } catch (Exception ignored) { retire(FailureCode.UPGRADE_REFUSED); }
        }
        @Override public void exceptionCaught(ChannelHandlerContext context, Throwable error) {
            retire(FailureCode.UPGRADE_REFUSED);
        }
    }

    static void validateUpgrade(FullHttpResponse response) throws TransportFailure {
        validateUpgrade(response, Profile.PAIRING);
    }

    private static void validateUpgrade(FullHttpResponse response, Profile profile) throws TransportFailure {
        List<String> protocols = response.headers().getAll(HttpHeaderNames.SEC_WEBSOCKET_PROTOCOL);
        if (!response.decoderResult().isSuccess() || response.status().code() != 101
                || protocols.size() != 1 || !profile.subprotocol.equals(protocols.get(0))
                || response.headers().contains(HttpHeaderNames.SEC_WEBSOCKET_EXTENSIONS)
                || response.headers().contains(HttpHeaderNames.LOCATION)
                || response.content().isReadable() || !response.trailingHeaders().isEmpty()) {
            throw failure(FailureCode.UPGRADE_REFUSED);
        }
        for (String name : new String[] {"Sec-WebSocket-Accept", "Upgrade", "Connection"}) {
            if (response.headers().getAll(name).size() != 1) throw failure(FailureCode.UPGRADE_REFUSED);
        }
        if (!"Upgrade".equalsIgnoreCase(response.headers().get(HttpHeaderNames.CONNECTION))) {
            throw failure(FailureCode.UPGRADE_REFUSED);
        }
    }

    private final class FrameBudget extends ChannelInboundHandlerAdapter {
        private int fragments;
        private int bytes;
        private ScheduledFuture<?> fragmentDeadline;
        @Override public void channelRead(ChannelHandlerContext context, Object message) {
            if (!(message instanceof WebSocketFrame)) { context.fireChannelRead(message); return; }
            WebSocketFrame frame = (WebSocketFrame) message;
            FailureCode refusal = null;
            if (retired.get() || !isOpen || frame.rsv() != 0) refusal = FailureCode.INVALID_FRAME;
            else if (frame instanceof BinaryWebSocketFrame) refusal = FailureCode.INVALID_FRAME;
            else if (frame instanceof TextWebSocketFrame || frame instanceof ContinuationWebSocketFrame) {
                boolean first = frame instanceof TextWebSocketFrame;
                if ((first && fragments != 0) || (!first && fragments == 0)) refusal = FailureCode.INVALID_FRAME;
                else if (frame.content().readableBytes() > MAXIMUM_MESSAGE_BYTES - bytes) refusal = FailureCode.MESSAGE_TOO_LARGE;
                else if (++fragments > MAXIMUM_FRAGMENTS) refusal = FailureCode.FRAGMENT_LIMIT;
                else {
                    bytes += frame.content().readableBytes();
                    if (first && !frame.isFinalFragment()) fragmentDeadline = context.executor().schedule(
                            () -> retire(FailureCode.FRAGMENT_TIMEOUT), FRAGMENT_TIMEOUT_SECONDS, TimeUnit.SECONDS);
                    if (frame.isFinalFragment()) reset();
                }
            }
            if (refusal != null) { ReferenceCountUtil.release(frame); retire(refusal); }
            else context.fireChannelRead(frame);
        }
        private void reset() {
            fragments = 0; bytes = 0;
            if (fragmentDeadline != null) fragmentDeadline.cancel(false);
            fragmentDeadline = null;
        }
        @Override public void channelInactive(ChannelHandlerContext context) {
            reset(); context.fireChannelInactive();
        }
        @Override public void handlerRemoved(ChannelHandlerContext context) { reset(); }
    }

    private final class Delivery extends SimpleChannelInboundHandler<WebSocketFrame> {
        private int controls;
        @Override protected void channelRead0(ChannelHandlerContext context, WebSocketFrame frame) {
            if (retired.get()) return;
            if (frame instanceof TextWebSocketFrame) {
                int length = frame.content().readableBytes();
                if (length == 0 || length > MAXIMUM_MESSAGE_BYTES) { retire(FailureCode.INVALID_TEXT); return; }
                byte[] owned = new byte[length]; frame.content().getBytes(frame.content().readerIndex(), owned);
                try { requireUtf8(owned); listener.onText(owned); }
                catch (TransportFailure ignored) { retire(FailureCode.INVALID_TEXT); }
                catch (RuntimeException ignored) { retire(FailureCode.CALLBACK_FAILED); }
            } else if (frame instanceof PingWebSocketFrame) {
                if (++controls > MAXIMUM_PENDING_CONTROLS) { retire(FailureCode.SEND_BACKPRESSURE); return; }
                ChannelFuture write = context.writeAndFlush(new PongWebSocketFrame(frame.content().retainedDuplicate()));
                ScheduledFuture<?> deadline = context.executor().schedule(
                        () -> retire(FailureCode.WRITE_TIMEOUT), WRITE_TIMEOUT_SECONDS, TimeUnit.SECONDS);
                write.addListener(future -> {
                    deadline.cancel(false); controls--;
                    if (!future.isSuccess()) retire(FailureCode.WRITE_FAILED);
                });
            } else if (frame instanceof CloseWebSocketFrame) retire(FailureCode.REMOTE_CLOSED);
            else if (!(frame instanceof PongWebSocketFrame)) retire(FailureCode.INVALID_FRAME);
        }
        @Override public void exceptionCaught(ChannelHandlerContext context, Throwable error) {
            retire(FailureCode.INVALID_FRAME);
        }
        @Override public void channelInactive(ChannelHandlerContext context) {
            retire(FailureCode.REMOTE_CLOSED); context.fireChannelInactive();
        }
    }

    private void write(Channel owned, Send send) {
        if (retired.get() || !isOpen || channel != owned || !owned.isActive()) {
            finishSend(send, FailureCode.NOT_OPEN); return;
        }
        try {
            if (!send.authorized.getAsBoolean()) { finishSend(send, FailureCode.NOT_OPEN); return; }
        } catch (RuntimeException refused) { finishSend(send, FailureCode.NOT_OPEN); return; }
        try {
            ChannelFuture write = owned.writeAndFlush(new TextWebSocketFrame(Unpooled.wrappedBuffer(send.bytes)));
            ScheduledFuture<?> deadline = owned.eventLoop().schedule(() -> {
                finishSend(send, FailureCode.WRITE_TIMEOUT); retire(FailureCode.WRITE_TIMEOUT);
            }, WRITE_TIMEOUT_SECONDS, TimeUnit.SECONDS);
            write.addListener(future -> {
                deadline.cancel(false);
                if (!future.isSuccess()) { finishSend(send, FailureCode.WRITE_FAILED); retire(FailureCode.WRITE_FAILED); }
                else finishSend(send, retired.get() ? FailureCode.CLOSED : null);
            });
        } catch (RuntimeException ignored) { finishSend(send, FailureCode.WRITE_FAILED); retire(FailureCode.WRITE_FAILED); }
    }

    private void finishSend(Send send, FailureCode reason) {
        synchronized (sendLock) {
            if (!sends.remove(send)) return;
            sendBytes -= send.bytes.length;
        }
        if (reason == null) send.result.complete(null);
        else send.result.completeExceptionally(failure(reason));
    }

    private void retire(FailureCode reason) {
        synchronized (sendLock) {
            // Gate retirement and reservation are one transaction; drain cannot miss a late send.
            if (retired.compareAndSet(false, true)) { terminalReason = reason; isOpen = false; }
        }
        if (!closeStarted.compareAndSet(false, true)) return;
        // register() may have scheduled delivery before returning the opaque registration. Even
        // in that case close cannot certify detach until the exact registration is published.
        registrationPublished.whenComplete((registration, error) -> {
            if (error != null) {
                registrationDrained.completeExceptionally(failure(FailureCode.DRAIN_FAILED));
            } else if (registration == null) {
                registrationDrained.complete(null);
            } else {
                try {
                    registration.detach().whenComplete((ignored, detachError) -> {
                        if (detachError == null) registrationDrained.complete(null);
                        else registrationDrained.completeExceptionally(failure(FailureCode.DRAIN_FAILED));
                    });
                } catch (RuntimeException ignored) {
                    registrationDrained.completeExceptionally(failure(FailureCode.DRAIN_FAILED));
                }
            }
        });
        if (openDeadline != null) openDeadline.cancel(false);
        opened.completeExceptionally(failure(terminalReason));
        Channel owned = channel;
        if (owned != null) {
            try {
                owned.close().addListener(future -> {
                    // Covers refusal to execute close as well as actual doClose failure.
                    // Success here alone is never native-close proof.
                    if (!future.isSuccess()) socketDrained.completeExceptionally(failure(FailureCode.DRAIN_FAILED));
                });
            } catch (RuntimeException ignored) {
                socketDrained.completeExceptionally(failure(FailureCode.DRAIN_FAILED));
            }
        }
        if (group != null) {
            try { group.shutdownGracefully(0, 5, TimeUnit.SECONDS); }
            catch (RuntimeException ignored) {
                loopDrained.completeExceptionally(failure(FailureCode.DRAIN_FAILED));
            }
        }
    }

    private void finishDrain(Throwable error) {
        List<Send> pending;
        synchronized (sendLock) { pending = new ArrayList<>(sends); }
        for (Send send : pending) finishSend(send, FailureCode.CLOSED);
        try { listener.onTerminal(error == null ? terminalReason : FailureCode.DRAIN_FAILED); }
        catch (RuntimeException ignored) { drained.completeExceptionally(failure(FailureCode.CALLBACK_FAILED)); return; }
        if (error == null) drained.complete(null);
        else drained.completeExceptionally(failure(FailureCode.DRAIN_FAILED));
    }

    private static final class Send {
        final byte[] bytes;
        final BooleanSupplier authorized;
        final CompletableFuture<Void> result = new CompletableFuture<>();
        Send(byte[] bytes, BooleanSupplier authorized) { this.bytes = bytes; this.authorized = authorized; }
    }

    static URI endpoint(String value) throws TransportFailure {
        return endpoint(value, Profile.PAIRING);
    }

    static URI availabilityEndpoint(String value) throws TransportFailure {
        return endpoint(value, Profile.AVAILABILITY);
    }

    private static URI endpoint(String value, Profile profile) throws TransportFailure {
        try {
            URI supplied = new URI(value);
            if (!"wss".equals(supplied.getScheme()) || !HOST.equals(supplied.getHost())
                    || (supplied.getPort() != -1 && supplied.getPort() != 443)
                    || supplied.getRawUserInfo() != null || supplied.getRawQuery() != null
                    || supplied.getRawFragment() != null
                    || !("".equals(supplied.getRawPath()) || "/".equals(supplied.getRawPath()))) {
                throw failure(FailureCode.INVALID_ENDPOINT);
            }
            return new URI("wss", null, HOST, -1, profile.path, null, null);
        } catch (URISyntaxException | NullPointerException ignored) { throw failure(FailureCode.INVALID_ENDPOINT); }
    }

    static HttpHeaders upgradeHeaders(PairingBootstrapEnvelopeCodec.JoinHeaders join) throws TransportFailure {
        if (join == null || !"viewer".equals(join.role()) || !crockfordChannel(join.channelID())
                || !urlProof(join.admissionProofForUpgradeHeader())) throw failure(FailureCode.INVALID_HEADERS);
        return new DefaultHttpHeaders()
                .set("X-AudioStreamer-Channel", join.channelID())
                .set("X-AudioStreamer-Role", "viewer")
                .set("X-AudioStreamer-Admission", join.admissionProofForUpgradeHeader());
    }

    static HttpHeaders availabilityUpgradeHeaders(ViewerAvailabilityEnvelopeCodec.JoinHeaders join)
            throws TransportFailure {
        if (join == null || !"viewer".equals(join.role()) || !crockfordChannel(join.channelID())
                || !urlProof(join.admissionProofForUpgradeHeader())) throw failure(FailureCode.INVALID_HEADERS);
        return new DefaultHttpHeaders()
                .set("X-AudioStreamer-Channel", join.channelID())
                .set("X-AudioStreamer-Role", "viewer")
                .set("X-AudioStreamer-Admission", join.admissionProofForUpgradeHeader())
                .set("X-AudioStreamer-Mode", "availability");
    }

    private static boolean crockfordChannel(String value) {
        if (value == null || value.length() != 52) return false;
        for (int i = 0; i < value.length(); i++) if ("0123456789ABCDEFGHJKMNPQRSTVWXYZ".indexOf(value.charAt(i)) < 0) return false;
        return "0G".indexOf(value.charAt(51)) >= 0;
    }

    private static boolean urlProof(String value) {
        if (value == null || value.length() != 43) return false;
        String alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
        for (int i = 0; i < value.length(); i++) if (alphabet.indexOf(value.charAt(i)) < 0) return false;
        return (alphabet.indexOf(value.charAt(42)) & 3) == 0;
    }

    static SSLEngine tlsEngine() throws TransportFailure {
        try {
            SSLContext context = SSLContext.getInstance("TLS");
            context.init(null, null, null); // Platform trust/key managers; never trust-all.
            SSLEngine engine = context.createSSLEngine(HOST, 443);
            engine.setUseClientMode(true);
            List<String> protocols = new ArrayList<>();
            for (String name : engine.getSupportedProtocols()) {
                if ("TLSv1.2".equals(name) || "TLSv1.3".equals(name)) protocols.add(name);
            }
            if (protocols.isEmpty()) throw failure(FailureCode.TLS_CONFIGURATION);
            engine.setEnabledProtocols(protocols.toArray(new String[0]));
            SSLParameters parameters = engine.getSSLParameters();
            parameters.setEndpointIdentificationAlgorithm("HTTPS");
            engine.setSSLParameters(parameters);
            return engine;
        } catch (GeneralSecurityException | RuntimeException ignored) { throw failure(FailureCode.TLS_CONFIGURATION); }
    }

    private static void requireUtf8(byte[] value) throws TransportFailure {
        try {
            StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(value));
        } catch (CharacterCodingException ignored) { throw failure(FailureCode.INVALID_TEXT); }
    }

    private static CompletionStage<Void> refused(FailureCode reason) {
        CompletableFuture<Void> result = new CompletableFuture<>();
        result.completeExceptionally(failure(reason)); return result;
    }
    private static TransportFailure failure(FailureCode code) { return new TransportFailure(code); }

    // Package-only EmbeddedChannel seam. No DNS, SSL, socket, NIO group or production permission.
    static NettyPairingWssTransport embedded(Channel channel, PairingBootstrapEnvelopeCodec.JoinHeaders join,
            Listener listener, CompletableFuture<Void> testLoopDrain, CompletableFuture<Void> testRegistrationDrain,
            CompletableFuture<Void> testFirstNativeClose)
            throws TransportFailure {
        return embedded(channel, Profile.PAIRING, upgradeHeaders(join), listener,
                testLoopDrain, testRegistrationDrain, testFirstNativeClose);
    }

    static NettyPairingWssTransport embeddedAvailability(Channel channel,
            ViewerAvailabilityEnvelopeCodec.JoinHeaders join, Listener listener,
            CompletableFuture<Void> testLoopDrain, CompletableFuture<Void> testRegistrationDrain,
            CompletableFuture<Void> testFirstNativeClose) throws TransportFailure {
        return embedded(channel, Profile.AVAILABILITY, availabilityUpgradeHeaders(join), listener,
                testLoopDrain, testRegistrationDrain, testFirstNativeClose);
    }

    private static NettyPairingWssTransport embedded(Channel channel, Profile profile, HttpHeaders headers,
            Listener listener, CompletableFuture<Void> testLoopDrain,
            CompletableFuture<Void> testRegistrationDrain, CompletableFuture<Void> testFirstNativeClose)
            throws TransportFailure {
        NettyPairingWssTransport result = new NettyPairingWssTransport(
                endpoint(PRODUCTION_ORIGIN, profile), profile, listener, null);
        result.channel = channel;
        testFirstNativeClose.whenComplete((ignored, error) -> {
            if (error == null) result.socketDrained.complete(null);
            else result.socketDrained.completeExceptionally(failure(FailureCode.DRAIN_FAILED));
        });
        testLoopDrain.whenComplete((ignored, error) -> {
            if (error == null) result.loopDrained.complete(null); else result.loopDrained.completeExceptionally(error);
        });
        testRegistrationDrain.whenComplete((ignored, error) -> {
            if (error == null) result.registrationDrained.complete(null);
            else result.registrationDrained.completeExceptionally(error);
        });
        result.installPipeline(channel, headers);
        result.beginUpgrade(channel);
        return result;
    }

    // Package-only production-registration fixture. Only the native connect action is replaced;
    // detach, retirement, executor delivery and actual owned-loop termination remain real.
    interface ResolvedConnector {
        void connect(NettyPairingWssTransport owner, InetAddress address) throws Exception;
    }

    static NettyPairingWssTransport withResolverForFixture(ProcessPairingDnsResolver resolver,
            EventLoopGroup group, Listener listener, ResolvedConnector connector) throws TransportFailure {
        return withResolverForFixture(resolver, group, listener, connector, () -> { });
    }

    static NettyPairingWssTransport withResolverForFixture(ProcessPairingDnsResolver resolver,
            EventLoopGroup group, Listener listener, ResolvedConnector connector,
            Runnable afterRegisterBeforePublish) throws TransportFailure {
        NettyPairingWssTransport result = new NettyPairingWssTransport(
                endpoint(PRODUCTION_ORIGIN), Profile.PAIRING, listener, group);
        result.start(resolver, connector, afterRegisterBeforePublish);
        return result;
    }

    void observeSocketForFixture(Channel owned, CompletableFuture<Void> firstNativeClose) {
        channel = owned;
        firstNativeClose.whenComplete((ignored, error) -> {
            if (error == null) socketDrained.complete(null);
            else socketDrained.completeExceptionally(failure(FailureCode.DRAIN_FAILED));
        });
    }
}
