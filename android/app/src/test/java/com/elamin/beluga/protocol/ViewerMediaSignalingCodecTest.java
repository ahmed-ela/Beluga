package com.elamin.beluga.protocol;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.Base64;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.junit.Before;
import org.junit.Test;
import com.elamin.beluga.protocol.PairingPayloadDecoder.CommitPayload;
import com.elamin.beluga.protocol.PairingPayloadDecoder.ConfirmationPayload;
import com.elamin.beluga.protocol.PairingPayloadDecoder.HelloPayload;
import com.elamin.beluga.protocol.ViewerMediaSignalingCodec.CodecFailure;
import com.elamin.beluga.protocol.ViewerMediaSignalingCodec.FailureCode;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.Agreement;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.PreparedViewer;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.ReconnectPreparation;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.SessionCredential;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.ViewerIdentity;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.ViewerPairRecord;

/** PUBLIC Swift-derived keys only; codec tests are not WSS/native media/device proof. */
public final class ViewerMediaSignalingCodecTest {
    private static final String PAIRING_SHA = "7d8a58cd34400271d0c68ac1e263450c4ad4978337ae1bb87246362a6d0ec06a";
    private static final String RECONNECT_SHA = "3c8ef42139c81e4cff10fcc1957aa0460a7548792ce7e952498966eff51c629e";
    private static final String MEDIA_SHA = "121c509e314c599ca9239715a3e1924513f29700f440d4bfe84bcb9b09b33510";
    private static final String DEADLINE = "2026-10-03T12:00:00.125Z";
    private Map<String, byte[]> pairing, reconnect, media;

    @Before public void loadActualAuthenticatedSavedPairReferences() throws Exception {
        pairing = load("/public-swift-engine-v1.tsv", PAIRING_SHA, 45);
        reconnect = load("/public-swift-saved-pair-reconnect-v1.tsv", RECONNECT_SHA, 98);
        media = load("/public-swift-media-signaling-v1.tsv", MEDIA_SHA, 40);
        assertEquals(PAIRING_SHA, text(reconnect.get("basis.original-pairing-fixture-sha256")));
        assertArrayEquals(pairing.get("derived.pair-root-public-test-only"), reconnect.get("basis.root-public-test-only"));
        assertArrayEquals(pairing.get("derived.transcript-hash"), reconnect.get("basis.transcript-hash"));
        Set<String> inventory = new HashSet<>(Arrays.asList("basis.reconnect-sha256", "derived.admission", "derived.channel",
                "derived.host-key", "derived.viewer-key", "ready.host", "ready.viewer"));
        for (String name : new String[] {"host-identity", "host-offer", "host-candidate", "host-end", "viewer-identity",
                "viewer-answer", "viewer-candidate", "viewer-show", "viewer-hide", "viewer-keyframe", "viewer-end"})
            for (String suffix : new String[] {"payload", "outbound", "inbound"}) inventory.add("capture." + name + "." + suffix);
        assertEquals(inventory, media.keySet()); assertEquals(RECONNECT_SHA, text(media.get("basis.reconnect-sha256")));
        assertArrayEquals(reference("credential.host-to-viewer"), media.get("derived.host-key"));
        assertArrayEquals(reference("credential.viewer-to-host"), media.get("derived.viewer-key"));
        assertEquals(referenceText("credential.channel"), text(media.get("derived.channel")));
        assertEquals(referenceText("credential.admission"), text(media.get("derived.admission")));
    }
    @Test public void allFortyActualSwiftCaptureRowsBindDirectionKeysPayloadAndSealedWire() throws Exception {
        String[] viewerNames = {"identity", "answer", "candidate", "show", "hide", "keyframe", "end"};
        byte[][] nonces = new byte[viewerNames.length][];
        for (int i = 0; i < nonces.length; i++) nonces[i] = Arrays.copyOfRange(cipher(capture("viewer-" + viewerNames[i], "outbound")), 0, 12);
        int[] nextNonce = {0};
        try (ViewerMediaSignalingCodec codec = new ViewerMediaSignalingCodec(credential(), () -> nonces[nextNonce[0]++].clone(), 0)) {
            ViewerMediaSignalingCodec.Event ready = codec.receive(media.get("ready.viewer"));
            assertEquals(2, ready.copyICEServers().length);
            assertEquals("public-test-password", ready.copyICEServers()[1].credential());
            String sdp = "v=0\r\no=- 1 2 IN IP4 127.0.0.1\r\ns=Beluga\r\nt=0 0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=rtpmap:111 opus/48000/2\r\na=fmtp:111 stereo=1;sprop-stereo=1\r\n";
            MediaSignalPayload[] viewer = {
                MediaSignalPayload.identity(UUID.fromString("AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE"), fill(0x43, 32), "Beluga Android"),
                MediaSignalPayload.answer(sdp),
                MediaSignalPayload.candidate(new MediaSignalPayload.Candidate("candidate:2 1 udp 2113937151 192.0.2.2 5001 typ host", "0", 0, null)),
                MediaSignalPayload.control(MediaSignalPayload.Control.SHOW_SCREEN), MediaSignalPayload.control(MediaSignalPayload.Control.HIDE_SCREEN),
                MediaSignalPayload.control(MediaSignalPayload.Control.REQUEST_KEY_FRAME), MediaSignalPayload.end(MediaSignalPayload.EndReason.VIEWER_DISCONNECTED)
            };
            for (int i = 0; i < viewer.length; i++) {
                assertArrayEquals(capture("viewer-" + viewerNames[i], "payload"), viewer[i].canonicalBytes());
                ViewerMediaSignalingCodec.Outbound sealed = codec.seal(viewer[i]); assertEquals(i, sealed.sequence());
                assertArrayEquals(capture("viewer-" + viewerNames[i], "outbound"), sealed.copyWireBytes());
                assertArrayEquals(capture("viewer-" + viewerNames[i], "payload"), openViewer(sealed));
                assertArrayEquals(sealed.copyWireBytes(), bytes(text(capture("viewer-" + viewerNames[i], "inbound")).replace("\"from\":\"viewer\",", "")));
            }
            for (String name : new String[] {"identity", "offer", "candidate", "end"}) {
                byte[] wire = capture("host-" + name, "inbound");
                MediaSignalPayload decoded = codec.receive(wire).payload();
                assertArrayEquals(capture("host-" + name, "payload"), decoded.canonicalBytes());
                assertArrayEquals(capture("host-" + name, "outbound"), bytes(text(wire).replace("\"from\":\"host\",", "")));
            }
        }
        try (ViewerMediaSignalingCodec codec = codec(0)) {
            refused(FailureCode.INVALID_WIRE, () -> codec.receive(media.get("ready.host")));
        }
    }
    @Test public void freshCredentialHeadersMatchActualSwiftAndAreRedacted() throws Exception {
        try (ViewerMediaSignalingCodec codec = ViewerMediaSignalingCodec.create(credential())) {
            ViewerMediaSignalingCodec.JoinHeaders headers = codec.copyJoinHeaders();
            assertEquals("viewer", headers.role()); assertEquals(referenceText("credential.channel"), headers.channelID());
            assertEquals(referenceText("credential.admission"), headers.admissionProofForUpgradeHeader());
            assertFalse(headers.toString().contains(headers.channelID()));
            assertFalse(headers.toString().contains(headers.admissionProofForUpgradeHeader()));
            assertFalse(codec.toString().contains(headers.channelID()));
        }
    }
    @Test public void upgradeIsNotReadyAndDuplicateReadyNeverResetsSequenceOrReplay() throws Exception {
        try (ViewerMediaSignalingCodec codec = codec(0)) {
            refused(FailureCode.NOT_READY, () -> codec.seal(MediaSignalPayload.answer("v=0\r\n")));
            refused(FailureCode.NOT_READY, () -> codec.receive(host(0, bytes("{\"kind\":\"offer\",\"sdp\":\"v=0\\r\\n\"}"))));
            ready(codec); assertEquals(0, codec.seal(MediaSignalPayload.answer("v=0\r\n")).sequence());
            byte[] received = host(8, MediaSignalPayload.offer("v=0\r\n").canonicalBytes());
            codec.receive(received); ready(codec);
            assertEquals(1, codec.seal(MediaSignalPayload.control(MediaSignalPayload.Control.HIDE_SCREEN)).sequence());
            refused(FailureCode.REPLAYED_SEQUENCE, () -> codec.receive(received));
            refused(FailureCode.INVALID_WIRE, () -> codec.receive(bytes(readyWire("[]").replace(DEADLINE, "2026-10-03T12:00:01.125Z"))));
            refused(FailureCode.INVALID_WIRE, () -> codec.receive(bytes("{\"type\":\"waiting\",\"invitationExpiresAt\":\"" + DEADLINE + "\"}")));
        }
    }
    @Test public void typedViewerAnswerCandidateControlEndAndIdentityHaveExactDirection() throws Exception {
        try (ViewerMediaSignalingCodec codec = codec(0)) {
            ready(codec);
            MediaSignalPayload[] payloads = {
                MediaSignalPayload.answer("v=0\r\nm=video 9 UDP/TLS/RTP/SAVPF 102\r\na=rtpmap:102 H264/90000\r\n"),
                MediaSignalPayload.candidate(new MediaSignalPayload.Candidate("candidate:1 1 UDP 1 127.0.0.1 9000 typ host", "0", 0, "fresh")),
                MediaSignalPayload.control(MediaSignalPayload.Control.SHOW_SCREEN),
                MediaSignalPayload.end(MediaSignalPayload.EndReason.NORMAL),
                MediaSignalPayload.identity(UUID.fromString("12345678-1234-5678-abcd-123456789abc"), fill(5, 32), "日本語 / \"😀\"")
            };
            for (int index = 0; index < payloads.length; index++) {
                ViewerMediaSignalingCodec.Outbound sealed = codec.seal(payloads[index]); assertEquals(index, sealed.sequence());
                assertArrayEquals(payloads[index].canonicalBytes(), openViewer(sealed));
                byte[] returned = sealed.copyWireBytes(); returned[0] ^= 1;
                assertEquals('{', sealed.copyWireBytes()[0]);
                assertFalse(sealed.toString().contains(referenceText("credential.channel")));
            }
            refused(FailureCode.INVALID_PAYLOAD, () -> codec.seal(MediaSignalPayload.offer("v=0\r\n")));
            refused(FailureCode.INVALID_PAYLOAD, () -> codec.seal(MediaSignalPayload.hostIdentity(UUID.randomUUID(), fill(2, 32), "host")));
            assertTrue(text(payloads[0].canonicalBytes()).contains("RTP\\/SAVPF"));
            assertTrue(text(payloads[4].canonicalBytes()).contains("日本語 \\/"));
        }
    }
    @Test public void hostOfferCandidateEndAndIdentityDecodeWithoutWrongRoleAuthority() throws Exception {
        try (ViewerMediaSignalingCodec codec = codec(0)) {
            ready(codec);
            MediaSignalPayload offer = codec.receive(host(0, bytes("{\"kind\":\"offer\",\"sdp\":\"v=0\\r\\n\"}"))).payload();
            assertEquals(MediaSignalPayload.Kind.OFFER, offer.kind()); assertEquals("v=0\r\n", offer.sdp());
            MediaSignalPayload candidate = codec.receive(host(1, bytes("{\"kind\":\"candidate\",\"candidate\":{\"sdp\":\"candidate:x\",\"sdpMid\":null,\"sdpMLineIndex\":null,\"usernameFragment\":null}}"))).payload();
            assertEquals("candidate:x", candidate.candidate().sdp()); assertEquals(null, candidate.candidate().sdpMid());
            byte[] key = fill(7, 32);
            MediaSignalPayload identity = codec.receive(host(2, MediaSignalPayload.hostIdentity(UUID.fromString("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"), key, "Mac 日本語").canonicalBytes())).payload();
            assertEquals("host", identity.identity().role()); assertEquals("Mac 日本語", identity.identity().displayName());
            key[0] ^= 1; assertEquals(7, identity.identity().copyPublicKey()[0]);
            byte[] copy = identity.identity().copyPublicKey(); copy[0] ^= 1; assertEquals(7, identity.identity().copyPublicKey()[0]);
            assertEquals(MediaSignalPayload.EndReason.HOST_STOPPED,
                    codec.receive(host(3, bytes("{\"kind\":\"end\",\"endReason\":\"hostStopped\"}"))).payload().endReason());
        }
    }
    @Test public void hostAnswerControlRestartPairingAndAvailabilityPayloadsAreRefused() throws Exception {
        try (ViewerMediaSignalingCodec codec = codec(0)) {
            ready(codec);
            for (String payload : new String[] {"{\"kind\":\"answer\",\"sdp\":\"v=0\"}",
                    "{\"kind\":\"control\",\"control\":\"showScreen\"}",
                    "{\"kind\":\"iceRestartRequest\",\"iceRestartRequest\":{\"protocolVersion\":1,\"requestID\":1}}",
                    "{\"kind\":\"hello\",\"hello\":{}}", "{\"kind\":\"reconnectResponse\",\"reconnectResponse\":{}}"})
                refused(FailureCode.INVALID_PAYLOAD, () -> codec.receive(host(0, bytes(payload))));
        }
    }
    @Test public void authenticationPrecedesReplayAndWindowAllowsLimitedReordering() throws Exception {
        try (ViewerMediaSignalingCodec codec = codec(0)) {
            ready(codec); byte[] plain = MediaSignalPayload.offer("v=0").canonicalBytes();
            byte[] valid = host(10, plain); byte[] corrupted = hostWithCipher(10, flipped(cipher(valid)), "hostToViewer", referenceText("credential.channel"), 10, 1);
            refused(FailureCode.AUTHENTICATION_FAILED, () -> codec.receive(corrupted));
            codec.receive(valid); codec.receive(host(8, plain)); codec.receive(host(9, plain));
            refused(FailureCode.REPLAYED_SEQUENCE, () -> codec.receive(host(8, plain)));
            codec.receive(host(100, plain));
            refused(FailureCode.SEQUENCE_OUTSIDE_WINDOW, () -> codec.receive(host(36, plain)));
        }
    }
    @Test public void sequenceChannelDirectionVersionAndOuterRoleAreBound() throws Exception {
        try (ViewerMediaSignalingCodec codec = codec(0)) {
            ready(codec); byte[] valid = host(0, MediaSignalPayload.offer("v=0").canonicalBytes()); byte[] combined = cipher(valid);
            for (byte[] wire : new byte[][] {
                hostWithCipher(1, combined, "hostToViewer", referenceText("credential.channel"), 1, 1),
                hostWithCipher(0, combined, "viewerToHost", referenceText("credential.channel"), 0, 1),
                hostWithCipher(0, combined, "hostToViewer", "0000000000000000000000000000000000000000000000000000", 0, 1),
                hostWithCipher(0, combined, "hostToViewer", referenceText("credential.channel"), 0, 2),
                bytes(text(valid).replace("\"from\":\"host\"", "\"from\":\"viewer\"")),
                hostWithCipher(1, combined, "hostToViewer", referenceText("credential.channel"), 0, 1) }) {
                try { codec.receive(wire); fail("mutated media envelope accepted"); }
                catch (CodecFailure expected) { assertTrue(expected.code() == FailureCode.INVALID_WIRE || expected.code() == FailureCode.AUTHENTICATION_FAILED); }
            }
            codec.receive(valid); // None of those failures consumed the authentic sequence.
        }
    }
    @Test public void strictJsonRejectsDuplicateUnknownDepthNumericUtf8AndTrailingInputs() throws Exception {
        try (ViewerMediaSignalingCodec codec = codec(0)) {
            for (String wire : new String[] {"{\"type\":\"ready\",\"type\":\"ready\"}",
                    readyWire("[]").replace("\"iceServers\":[]", "\"iceServers\":[],\"extra\":0"),
                    readyWire("[]") + "{}", "/*comment*/" + readyWire("[]"),
                    readyWire("[]").replace("\"viewer\"", "'viewer'"),
                    readyWire("[[[[[[[[]]]]]]]]")}) refused(FailureCode.INVALID_WIRE, () -> codec.receive(bytes(wire)));
            byte[] malformedUTF8 = bytes(readyWire("[]")); malformedUTF8[5] = (byte) 0xFF;
            refused(FailureCode.INVALID_WIRE, () -> codec.receive(malformedUTF8));
            ready(codec);
            for (String sequence : new String[] {"-1", "1.0", "1e0", "01", "2147483648", "true", "null"}) {
                byte[] wire = host(1, MediaSignalPayload.offer("v=0").canonicalBytes());
                refused(FailureCode.INVALID_WIRE, () -> codec.receive(bytes(text(wire).replace("\"seq\":1", "\"seq\":" + sequence))));
            }
            refused(FailureCode.INVALID_WIRE, () -> codec.receive(new byte[90_001]));
        }
    }
    @Test public void decryptedPayloadSchemasAreClosedBoundedAndSurrogateStrict() throws Exception {
        try (ViewerMediaSignalingCodec codec = codec(0)) {
            ready(codec);
            for (String payload : new String[] {"{\"kind\":\"offer\",\"sdp\":\"v=0\",\"sdp\":\"v=1\"}",
                    "{\"kind\":\"offer\",\"sdp\":\"v=0\",\"extra\":0}", "{\"kind\":\"offer\",\"sdp\":\"\\uD800\"}",
                    "{\"kind\":\"offer\",\"sdp\":\"\"}",
                    "{\"kind\":\"candidate\",\"candidate\":{\"sdp\":\"x\",\"sdpMLineIndex\":65536}}",
                    "{\"kind\":\"candidate\",\"candidate\":{\"sdp\":\"x\",\"usernameFragment\":\"old new\"}}",
                    "{\"kind\":\"identity\",\"identity\":{\"deviceID\":\"1-2-3-4-5\",\"role\":\"host\",\"publicKey\":\"AQ==\"}}",
                    text(MediaSignalPayload.identity(UUID.randomUUID(), fill(3, 32), "viewer").canonicalBytes())}) {
                try { codec.receive(host(0, bytes(payload))); fail("invalid host payload accepted"); }
                catch (CodecFailure expected) { assertTrue(expected.code() == FailureCode.INVALID_WIRE || expected.code() == FailureCode.INVALID_PAYLOAD); }
            }
            refused(FailureCode.INVALID_WIRE, () -> codec.receive(host(0, bytes("{\"kind\":\"offer\",\"sdp\":\"" + repeat('x', 40_001) + "\"}"))));
        }
    }
    @Test public void readyAdmitsBoundedStunAndTurnPasswordsOnlyInMemory() throws Exception {
        String servers = "[{\"urls\":[\"stun:stun.example:3478\"]},{\"urls\":[\"turn:turn.example:3478?transport=udp\",\"turns:turn.example:443?transport=tcp\"],\"username\":\"PUBLIC user\",\"credential\":\"PUBLIC password\",\"credentialType\":\"password\"}]";
        try (ViewerMediaSignalingCodec codec = codec(0)) {
            ViewerMediaSignalingCodec.Event event = codec.receive(bytes(readyWire(servers)));
            assertEquals(ViewerMediaSignalingCodec.Kind.READY, event.kind());
            ViewerMediaSignalingCodec.ICEServer[] copied = event.copyICEServers(); assertEquals(2, copied.length);
            assertEquals("PUBLIC password", copied[1].credential()); assertFalse(copied[1].toString().contains("PUBLIC password"));
            String[] urls = copied[1].copyURLs(); urls[0] = "bad";
            assertTrue(event.copyICEServers()[1].copyURLs()[0].startsWith("turn:")); copied[1] = null;
            assertEquals("PUBLIC user", event.copyICEServers()[1].username());
        }
    }
    @Test public void malformedIceUrlsCapabilitiesPasswordShapesAndDateAreRefused() throws Exception {
        for (String server : new String[] {"{\"urls\":[]}", "{\"urls\":[\"https://example\"]}", "{\"urls\":[\"turn:user@example\"]}",
                "{\"urls\":[\"stun:host bad\"]}", "{\"urls\":[\"turn:host\"]}",
                "{\"urls\":[\"turn:host\"],\"username\":\"u\",\"credential\":\"p\",\"credentialType\":\"oauth\"}",
                "{\"urls\":[\"stun:host\"],\"username\":\"u\",\"credential\":\"p\",\"credentialType\":\"password\"}",
                "{\"urls\":[\"stun:host\"],\"urls\":[\"stun:host\"]}", "{\"urls\":[\"stun:host\"],\"extra\":null}"}) {
            try (ViewerMediaSignalingCodec codec = codec(0)) { refused(FailureCode.INVALID_WIRE, () -> codec.receive(bytes(readyWire("[" + server + "]")))); }
        }
        for (String deadline : new String[] {"2026-02-30T12:00:00.000Z", "2026-10-03T12:00:00Z", "2026-10-03T12:00:00.000+18:01"}) {
            try (ViewerMediaSignalingCodec codec = codec(0)) { refused(FailureCode.INVALID_WIRE, () -> codec.receive(bytes(readyWire("[]").replace(DEADLINE, deadline)))); }
        }
        try (ViewerMediaSignalingCodec codec = codec(0)) {
            refused(FailureCode.INVALID_WIRE, () -> codec.receive(bytes(readyWire("[" + repeatServer(17) + "]"))));
            refused(FailureCode.INVALID_WIRE, () -> codec.receive(bytes(readyWire("[]").replace("viewer", "host"))));
        }
    }
    @Test public void maximumSequenceNeverWrapsAndInvalidNonceCannotAuthorizeBytes() throws Exception {
        try (ViewerMediaSignalingCodec codec = codec(ViewerMediaSignalingCodec.MAXIMUM_SEQUENCE)) {
            ready(codec); assertEquals(ViewerMediaSignalingCodec.MAXIMUM_SEQUENCE, codec.seal(MediaSignalPayload.answer("v=0")).sequence());
            refused(FailureCode.SEQUENCE_EXHAUSTED, () -> codec.seal(MediaSignalPayload.answer("v=0")));
        }
        try (ViewerMediaSignalingCodec codec = new ViewerMediaSignalingCodec(credential(), () -> new byte[11], 0)) {
            ready(codec); refused(FailureCode.PROVIDER_FAILED, () -> codec.seal(MediaSignalPayload.answer("v=0")));
        }
    }
    @Test public void providerReentryAndRevocationCannotCompleteAQueuedSeal() throws Exception {
        ViewerMediaSignalingCodec[] owner = new ViewerMediaSignalingCodec[1];
        owner[0] = new ViewerMediaSignalingCodec(credential(), () -> {
            try { owner[0].seal(MediaSignalPayload.answer("v=0")); fail("reentrant seal accepted"); }
            catch (CodecFailure expected) { assertEquals(FailureCode.REENTRANT, expected.code()); }
            owner[0].close(); return fill(2, 12);
        }, 0);
        ready(owner[0]); refused(FailureCode.CLOSED, () -> owner[0].seal(MediaSignalPayload.answer("v=0")));
    }
    @Test public void terminalEventsAndCloseNeverReviveTheOneUseCredential() throws Exception {
        SessionCredential credential = credential(); ViewerMediaSignalingCodec codec = ViewerMediaSignalingCodec.create(credential);
        ready(codec); assertEquals(ViewerMediaSignalingCodec.Kind.PEER_LEFT, codec.receive(bytes("{\"type\":\"peer-left\",\"role\":\"host\"}")).kind());
        refused(FailureCode.CLOSED, codec::copyJoinHeaders); codec.close();
        try { credential.channelID(); fail("transferred terminal credential still live"); }
        catch (ViewerPairingAuthenticator.AuthFailure expected) { assertEquals(ViewerPairingAuthenticator.FailureCode.INVALID_RECONNECT, expected.code()); }
        try (ViewerMediaSignalingCodec error = codec(0)) {
            assertEquals(ViewerMediaSignalingCodec.ServerError.RATE_LIMITED,
                    error.receive(bytes("{\"type\":\"error\",\"error\":\"rate_limited\"}")).serverError());
            refused(FailureCode.CLOSED, () -> ready(error));
        }
    }
    @Test public void valueBoundsDefensiveCopiesAndUnicodeDoNotExposeSensitiveText() {
        for (Runnable invalid : new Runnable[] {
            () -> MediaSignalPayload.answer(""), () -> MediaSignalPayload.answer(repeat('x', 40_001)),
            () -> MediaSignalPayload.answer("\uD800"), () -> new MediaSignalPayload.Candidate("x", null, -1, null),
            () -> new MediaSignalPayload.Candidate("x", null, null, ""),
            () -> MediaSignalPayload.identity(UUID.randomUUID(), new byte[0], null),
            () -> MediaSignalPayload.identity(UUID.randomUUID(), fill(1, 32), repeat('é', 129)) }) {
            try { invalid.run(); fail("malformed typed value admitted"); } catch (IllegalArgumentException expected) { assertFalse(expected.getMessage().contains("é")); }
        }
        MediaSignalPayload valid = MediaSignalPayload.identity(UUID.randomUUID(), fill(1, 32), "日本語 / 😀");
        assertFalse(valid.toString().contains("日本語")); assertFalse(valid.identity().toString().contains("日本語"));
    }

    private ViewerMediaSignalingCodec codec(long sequence) throws Exception {
        return new ViewerMediaSignalingCodec(credential(), () -> fill(0x5A, 12), sequence);
    }
    private SessionCredential credential() throws Exception {
        UUID viewer = UUID.fromString(text(pairing.get("input.viewer-device-id")));
        ViewerIdentity identity = ViewerPairingAuthenticator.viewerIdentity(viewer, pairing.get("input.viewer-signing-seed"));
        PreparedViewer prepared = ViewerPairingAuthenticator.authenticateRetainedLocalHello(viewer,
                text(pairing.get("input.viewer-display-name")), pairing.get("input.viewer-signing-seed"), pairing.get("input.invitation-secret"),
                pairing.get("input.viewer-ephemeral-private"), pairing.get("input.viewer-nonce"),
                (HelloPayload) PairingPayloadDecoder.decode(pairing.get("hello.viewer.payload")));
        Agreement agreement = ViewerPairingAuthenticator.acceptHost(prepared, (HelloPayload) PairingPayloadDecoder.decode(pairing.get("hello.host.payload")));
        ViewerPairRecord pending = agreement.makePendingRecord(agreement.authenticateHostConfirmation(
                (ConfirmationPayload) PairingPayloadDecoder.decode(pairing.get("confirmation.host.payload"))), 1700000000.25);
        ViewerPairRecord accepted = pending.prepareAcknowledgement((CommitPayload) PairingPayloadDecoder.decode(pairing.get("commit.proposal.payload")), identity).record();
        ViewerPairRecord active = accepted.acceptCompletion((CommitPayload) PairingPayloadDecoder.decode(pairing.get("commit.completion.payload")), identity).record();
        ReconnectPreparation reconnectPreparation = active.authenticateRetainedReconnect(identity,
                reference("input.viewer-ephemeral-private"), reference("input.viewer-nonce"), ReconnectMessages.decodeRequest(reference("request.full")));
        return reconnectPreparation.complete(ReconnectMessages.decodeResponse(reference("response.full")));
    }
    private static void ready(ViewerMediaSignalingCodec codec) throws CodecFailure { codec.receive(bytes(readyWire("[]"))); }
    private static String readyWire(String ice) { return "{\"type\":\"ready\",\"role\":\"viewer\",\"invitationExpiresAt\":\"" + DEADLINE + "\",\"iceServers\":" + ice + "}"; }
    private byte[] host(long sequence, byte[] plaintext) throws Exception {
        byte[] combined = BouncyCastlePairingCrypto.sealCombined(reference("credential.host-to-viewer"), fill(0x2B, 12), plaintext, expectedAAD(sequence, 1));
        return hostWithCipher(sequence, combined, "hostToViewer", referenceText("credential.channel"), sequence, 1);
    }
    private byte[] hostWithCipher(long sequence, byte[] combined, String direction, String channel, long innerSequence, int version) {
        String envelope = "{\"version\":" + version + ",\"channelID\":\"" + channel + "\",\"direction\":\"" + direction
                + "\",\"sequence\":" + innerSequence + ",\"ciphertext\":\"" + Base64.getEncoder().encodeToString(combined) + "\"}";
        return bytes("{\"type\":\"signal\",\"from\":\"host\",\"seq\":" + sequence + ",\"envelope\":\""
                + Base64.getUrlEncoder().withoutPadding().encodeToString(bytes(envelope)) + "\"}");
    }
    private byte[] openViewer(ViewerMediaSignalingCodec.Outbound outbound) throws Exception {
        return BouncyCastlePairingCrypto.openCombined(reference("credential.viewer-to-host"), cipher(outbound.copyWireBytes()), expectedAAD(outbound.sequence(), 2));
    }
    private byte[] expectedAAD(long sequence, int direction) throws Exception {
        ByteArrayOutputStream result = new ByteArrayOutputStream(); result.write(bytes("AudioStreamer.Signaling.Envelope.AAD.v1\0"));
        result.write(1); result.write(bytes(referenceText("credential.channel"))); result.write(0); result.write(direction);
        result.write(ByteBuffer.allocate(8).putLong(sequence).array());
        assertArrayEquals(result.toByteArray(), ViewerMediaSignalingCodec.aad(referenceText("credential.channel"), sequence, direction));
        return result.toByteArray();
    }
    private static byte[] cipher(byte[] wire) {
        String envelope = text(Base64.getUrlDecoder().decode(field(text(wire), "envelope")));
        return Base64.getDecoder().decode(field(envelope, "ciphertext").replace("\\/", "/"));
    }
    private static String field(String object, String name) {
        Matcher matcher = Pattern.compile("\\\"" + name + "\\\":\\\"([^\\\"]+)\\\"").matcher(object);
        assertTrue("test fixture field required", matcher.find()); return matcher.group(1);
    }
    private byte[] reference(String suffix) { byte[] value = reconnect.get("reconnect.first." + suffix); if (value == null) throw new AssertionError("missing fixed public reference"); return value.clone(); }
    private String referenceText(String suffix) { return text(reference(suffix)); }
    private byte[] capture(String name, String suffix) {
        byte[] value = media.get("capture." + name + "." + suffix);
        if (value == null) throw new AssertionError("missing fixed actual Swift media capture"); return value.clone();
    }
    private static Map<String, byte[]> load(String path, String expectedHash, int count) throws Exception {
        byte[] bytes;
        try (InputStream stream = ViewerMediaSignalingCodecTest.class.getResourceAsStream(path)) {
            if (stream == null) throw new AssertionError("missing public test fixture");
            ByteArrayOutputStream output = new ByteArrayOutputStream(); byte[] buffer = new byte[4_096]; int read;
            while ((read = stream.read(buffer)) != -1) { if (output.size() + read > 96_000) throw new AssertionError("oversized public fixture"); output.write(buffer, 0, read); }
            bytes = output.toByteArray();
        }
        StringBuilder hash = new StringBuilder(); for (byte b : MessageDigest.getInstance("SHA-256").digest(bytes)) hash.append(String.format(java.util.Locale.ROOT, "%02x", b & 255));
        assertEquals(expectedHash, hash.toString()); Map<String, byte[]> result = new TreeMap<>(); String previous = null;
        for (String row : text(bytes).split("\n", -1)) {
            if (row.startsWith("#") || row.isEmpty()) continue;
            String[] fields = row.split("\t", -1); assertEquals(2, fields.length);
            assertTrue(previous == null || previous.compareTo(fields[0]) < 0); previous = fields[0];
            byte[] value = Base64.getDecoder().decode(fields[1]); assertEquals(fields[1], Base64.getEncoder().encodeToString(value));
            assertEquals(null, result.put(fields[0], value));
        }
        assertEquals(count, result.size()); return result;
    }
    private static byte[] bytes(String text) { return text.getBytes(StandardCharsets.UTF_8); }
    private static String text(byte[] bytes) { return new String(bytes, StandardCharsets.UTF_8); }
    private static byte[] fill(int value, int length) { byte[] bytes = new byte[length]; Arrays.fill(bytes, (byte) value); return bytes; }
    private static byte[] flipped(byte[] bytes) { byte[] copy = bytes.clone(); copy[copy.length - 1] ^= 1; return copy; }
    private static String repeat(char c, int count) { char[] chars = new char[count]; Arrays.fill(chars, c); return new String(chars); }
    private static String repeatServer(int count) { StringBuilder value = new StringBuilder(); for (int i = 0; i < count; i++) { if (i != 0) value.append(','); value.append("{\"urls\":[\"stun:host\"]}"); } return value.toString(); }
    @FunctionalInterface private interface Throwing { void run() throws Exception; }
    private static void refused(FailureCode code, Throwing operation) throws Exception {
        try { operation.run(); fail("media signaling refusal required"); }
        catch (CodecFailure expected) { assertEquals(code, expected.code()); }
    }
}
