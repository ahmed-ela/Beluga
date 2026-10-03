package com.elamin.beluga.protocol;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import io.netty.buffer.ByteBuf;
import io.netty.buffer.Unpooled;
import io.netty.channel.ChannelDuplexHandler;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelPromise;
import io.netty.channel.embedded.EmbeddedChannel;
import io.netty.handler.codec.http.DefaultFullHttpResponse;
import io.netty.handler.codec.http.FullHttpResponse;
import io.netty.handler.codec.http.HttpHeaderNames;
import io.netty.handler.codec.http.HttpHeaders;
import io.netty.handler.codec.http.HttpResponseStatus;
import io.netty.handler.codec.http.HttpVersion;
import io.netty.util.ReferenceCountUtil;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import javax.net.ssl.SSLEngine;
import org.junit.Test;

/** Real Netty HTTP/frame/write tests and platform TLS configuration; no sockets, handshake or Android. */
public final class NettyPairingWssTransportTest {
    @Test public void exactConfiguredOriginConstructsOnlyPairingRoute() throws Exception {
        assertEquals(NettyPairingWssTransport.PRODUCTION_ORIGIN + "/v1/rendezvous",
                NettyPairingWssTransport.endpoint(NettyPairingWssTransport.PRODUCTION_ORIGIN).toString());
        assertEquals(NettyPairingWssTransport.endpoint(NettyPairingWssTransport.PRODUCTION_ORIGIN),
                NettyPairingWssTransport.endpoint(NettyPairingWssTransport.PRODUCTION_ORIGIN + ":443/"));
        for (String value : new String[] {null, "", "ws://localhost", "wss://other.example",
                NettyPairingWssTransport.PRODUCTION_ORIGIN + ":444",
                NettyPairingWssTransport.PRODUCTION_ORIGIN + "/v1/rendezvous",
                NettyPairingWssTransport.PRODUCTION_ORIGIN + "?admission=x",
                NettyPairingWssTransport.PRODUCTION_ORIGIN + "#x",
                "wss://x@" + NettyPairingWssTransport.HOST,
                "wss://" + NettyPairingWssTransport.HOST + "."}) {
            try { NettyPairingWssTransport.endpoint(value); fail("Expected exact endpoint refusal"); }
            catch (NettyPairingWssTransport.TransportFailure error) {
                assertEquals(NettyPairingWssTransport.FailureCode.INVALID_ENDPOINT, error.code());
                assertEquals(null, error.getCause());
            }
        }
    }

    @Test public void mintedViewerHeadersAreOnlyBoundedCompatibilityCapabilities() throws Exception {
        HttpHeaders headers = NettyPairingWssTransport.upgradeHeaders(join(PairingCanonicalCodec.Role.VIEWER));
        assertEquals(3, headers.size());
        assertEquals("viewer", headers.get("X-AudioStreamer-Role"));
        assertEquals(52, headers.get("X-AudioStreamer-Channel").length());
        assertEquals(43, headers.get("X-AudioStreamer-Admission").length());
        assertFalse(headers.contains("X-AudioStreamer-Mode"));
        assertFalse(headers.contains("X-AudioStreamer-Viewer-Admission"));
        assertFalse(headers.contains(HttpHeaderNames.SEC_WEBSOCKET_EXTENSIONS));
        try { NettyPairingWssTransport.upgradeHeaders(join(PairingCanonicalCodec.Role.HOST)); fail("Expected viewer-only refusal"); }
        catch (NettyPairingWssTransport.TransportFailure error) {
            assertEquals(NettyPairingWssTransport.FailureCode.INVALID_HEADERS, error.code());
        }
    }

    @Test public void availabilityOriginCannotAcceptRoutesOrUrlCapabilities() throws Exception {
        assertEquals(NettyPairingWssTransport.PRODUCTION_ORIGIN + "/v2/availability",
                NettyPairingWssTransport.availabilityEndpoint(NettyPairingWssTransport.PRODUCTION_ORIGIN).toString());
        assertEquals(NettyPairingWssTransport.availabilityEndpoint(NettyPairingWssTransport.PRODUCTION_ORIGIN),
                NettyPairingWssTransport.availabilityEndpoint(NettyPairingWssTransport.PRODUCTION_ORIGIN + ":443/"));
        for (String value : new String[] {null, "", "ws://localhost", "wss://other.example",
                NettyPairingWssTransport.PRODUCTION_ORIGIN + ":444",
                NettyPairingWssTransport.PRODUCTION_ORIGIN + "/v2/availability",
                NettyPairingWssTransport.PRODUCTION_ORIGIN + "/v1/rendezvous",
                NettyPairingWssTransport.PRODUCTION_ORIGIN + "/%76%32/availability",
                NettyPairingWssTransport.PRODUCTION_ORIGIN + "?admission=x",
                NettyPairingWssTransport.PRODUCTION_ORIGIN + "#x",
                "wss://viewer@" + NettyPairingWssTransport.HOST,
                "wss://" + NettyPairingWssTransport.HOST + "."}) {
            try { NettyPairingWssTransport.availabilityEndpoint(value); fail("Expected exact availability endpoint refusal"); }
            catch (NettyPairingWssTransport.TransportFailure error) {
                assertEquals(NettyPairingWssTransport.FailureCode.INVALID_ENDPOINT, error.code());
            }
        }
        // The old entry point still constructs only v1 even after using the new profile.
        assertEquals(NettyPairingWssTransport.PRODUCTION_ORIGIN + "/v1/rendezvous",
                NettyPairingWssTransport.endpoint(NettyPairingWssTransport.PRODUCTION_ORIGIN).toString());
    }

    @Test public void availabilityHeadersAreViewerOnlyWithFixedModeAndNoHostRegistration() throws Exception {
        ViewerAvailabilityEnvelopeCodec.JoinHeaders join = availabilityJoin();
        HttpHeaders headers = NettyPairingWssTransport.availabilityUpgradeHeaders(join);
        assertEquals(4, headers.size());
        assertEquals("availability", headers.get("X-AudioStreamer-Mode"));
        assertEquals("viewer", headers.get("X-AudioStreamer-Role"));
        assertEquals(join.channelID(), headers.get("X-AudioStreamer-Channel"));
        assertEquals(join.admissionProofForUpgradeHeader(), headers.get("X-AudioStreamer-Admission"));
        assertEquals(52, headers.get("X-AudioStreamer-Channel").length());
        assertEquals(43, headers.get("X-AudioStreamer-Admission").length());
        assertFalse(headers.contains("X-AudioStreamer-Viewer-Admission"));
        assertFalse(headers.contains("X-AudioStreamer-Host-Admission"));
        assertFalse(headers.contains(HttpHeaderNames.SEC_WEBSOCKET_EXTENSIONS));
        assertTrue(join.toString().contains("redacted"));
        try { NettyPairingWssTransport.availabilityUpgradeHeaders(null); fail("Expected missing availability capability refusal"); }
        catch (NettyPairingWssTransport.TransportFailure error) {
            assertEquals(NettyPairingWssTransport.FailureCode.INVALID_HEADERS, error.code());
        }
        HttpHeaders bootstrap = NettyPairingWssTransport.upgradeHeaders(join(PairingCanonicalCodec.Role.VIEWER));
        assertEquals(3, bootstrap.size());
        assertFalse(bootstrap.contains("X-AudioStreamer-Mode"));
        assertFalse(bootstrap.contains("X-AudioStreamer-Viewer-Admission"));
    }

    @Test public void availabilityHandshakeOffersOnlyItsExactPathHeadersAndProtocol() throws Exception {
        try (Fixture fixture = new Fixture(true)) {
            assertTrue(fixture.request.startsWith("GET /v2/availability HTTP/1.1\r\n"));
            assertEquals(NettyPairingWssTransport.AVAILABILITY_SUBPROTOCOL,
                    header(fixture.request, "Sec-WebSocket-Protocol"));
            assertEquals("availability", header(fixture.request, "X-AudioStreamer-Mode"));
            assertEquals("viewer", header(fixture.request, "X-AudioStreamer-Role"));
            assertEquals(fixture.availabilityHeaders.channelID(), header(fixture.request, "X-AudioStreamer-Channel"));
            assertEquals(fixture.availabilityHeaders.admissionProofForUpgradeHeader(),
                    header(fixture.request, "X-AudioStreamer-Admission"));
            String lower = fixture.request.toLowerCase(java.util.Locale.ROOT);
            assertFalse(lower.contains("x-audiostreamer-viewer-admission"));
            assertFalse(lower.contains("x-audiostreamer-host-admission"));
            assertFalse(lower.contains("sec-websocket-extensions"));
            assertFalse(fixture.request.contains("?"));
            assertFalse(fixture.transport.whenOpen().toCompletableFuture().isDone());
            fixture.open();
            assertFalse(fixture.transport.whenOpen().toCompletableFuture().isCompletedExceptionally());
            assertEquals(1, fixture.listener.opens);
            // HTTP101 is still only transport evidence; no saved-Mac status or READY is synthesized.
            assertTrue(fixture.listener.messages.isEmpty());
        }
    }

    @Test public void availabilityMissingWrongBootstrapCommaAndDuplicateProtocolsNeverOpen() throws Exception {
        for (int mode = 0; mode < 7; mode++) {
            try (Fixture fixture = new Fixture(true)) {
                FullHttpResponse response = fixture.response();
                if (mode == 0) response.headers().remove(HttpHeaderNames.SEC_WEBSOCKET_PROTOCOL);
                if (mode == 1) response.headers().set(HttpHeaderNames.SEC_WEBSOCKET_PROTOCOL, "wrong.v1");
                if (mode == 2) response.headers().set(HttpHeaderNames.SEC_WEBSOCKET_PROTOCOL, NettyPairingWssTransport.SUBPROTOCOL);
                if (mode == 3) response.headers().set(HttpHeaderNames.SEC_WEBSOCKET_PROTOCOL,
                        NettyPairingWssTransport.AVAILABILITY_SUBPROTOCOL + ", " + NettyPairingWssTransport.SUBPROTOCOL);
                if (mode == 4) response.headers().add(HttpHeaderNames.SEC_WEBSOCKET_PROTOCOL,
                        NettyPairingWssTransport.AVAILABILITY_SUBPROTOCOL);
                if (mode == 5) response.headers().set(HttpHeaderNames.SEC_WEBSOCKET_PROTOCOL, "audiostreamer.Availability.v1");
                if (mode == 6) response.headers().set(HttpHeaderNames.SEC_WEBSOCKET_PROTOCOL,
                        NettyPairingWssTransport.AVAILABILITY_SUBPROTOCOL + " ");
                fixture.channel.writeInbound(response); fixture.channel.runPendingTasks();
                assertFailure(fixture.transport.whenOpen(), NettyPairingWssTransport.FailureCode.UPGRADE_REFUSED);
                assertEquals(0, fixture.listener.opens); assertTrue(fixture.listener.messages.isEmpty());
                assertFalse(fixture.channel.isOpen());
            }
        }
    }

    @Test public void bootstrapCannotAcceptAvailabilityProtocolReply() throws Exception {
        try (Fixture fixture = new Fixture()) {
            FullHttpResponse response = fixture.response();
            response.headers().set(HttpHeaderNames.SEC_WEBSOCKET_PROTOCOL, NettyPairingWssTransport.AVAILABILITY_SUBPROTOCOL);
            fixture.channel.writeInbound(response); fixture.channel.runPendingTasks();
            assertFailure(fixture.transport.whenOpen(), NettyPairingWssTransport.FailureCode.UPGRADE_REFUSED);
            assertEquals(0, fixture.listener.opens);
            assertFalse(fixture.request.toLowerCase(java.util.Locale.ROOT).contains("x-audiostreamer-mode"));
        }
    }

    @Test public void availabilityRedirectsExtensionsAndWrongChallengeRemainRefused() throws Exception {
        for (int mode = 0; mode < 5; mode++) {
            try (Fixture fixture = new Fixture(true)) {
                FullHttpResponse response = fixture.response();
                if (mode == 0) response.setStatus(HttpResponseStatus.TEMPORARY_REDIRECT);
                if (mode == 1) response.headers().set(HttpHeaderNames.SEC_WEBSOCKET_EXTENSIONS, "permessage-deflate");
                if (mode == 2) response.headers().set(HttpHeaderNames.LOCATION,
                        NettyPairingWssTransport.PRODUCTION_ORIGIN + "/v1/rendezvous");
                if (mode == 3) response.headers().add(HttpHeaderNames.SEC_WEBSOCKET_ACCEPT, fixture.accept);
                if (mode == 4) response.headers().set(HttpHeaderNames.SEC_WEBSOCKET_ACCEPT, "wrong");
                fixture.channel.writeInbound(response); fixture.channel.runPendingTasks();
                assertFailure(fixture.transport.whenOpen(), NettyPairingWssTransport.FailureCode.UPGRADE_REFUSED);
                assertEquals(0, fixture.listener.opens);
            }
        }
    }

    @Test public void availabilityUsesSameGuardedWriteAndExactCloseBarriers() throws Exception {
        try (Fixture fixture = new Fixture(true)) {
            fixture.open();
            HeldWrites held = new HeldWrites(); fixture.channel.pipeline().addFirst("held", held);
            AtomicBoolean authorized = new AtomicBoolean(true);
            CompletionStage<Void> send = fixture.transport.sendGuarded(bytes(1, 'a'), authorized::get);
            authorized.set(false); fixture.channel.runPendingTasks();
            assertFailure(send, NettyPairingWssTransport.FailureCode.NOT_OPEN);
            assertTrue(held.pending.isEmpty()); assertNull(fixture.channel.readOutbound());
            CompletionStage<Void> close = fixture.transport.closeAsync();
            assertFalse(close.toCompletableFuture().isDone());
            fixture.loopDrain.complete(null);
            assertFalse(close.toCompletableFuture().isDone());
            fixture.dnsDrain.complete(null);
            assertTrue(close.toCompletableFuture().isDone());
            assertFalse(close.toCompletableFuture().isCompletedExceptionally());
            assertEquals(1, fixture.listener.terminals);
        }
    }

    @Test public void actualPlatformTlsEngineHasExactPeerAndVerificationConfiguration() throws Exception {
        // No connection or handshake: real platform engine configuration only, not TLS trust proof.
        SSLEngine engine = NettyPairingWssTransport.tlsEngine();
        assertTrue(engine.getUseClientMode());
        assertEquals(NettyPairingWssTransport.HOST, engine.getPeerHost());
        assertEquals(443, engine.getPeerPort());
        assertEquals("HTTPS", engine.getSSLParameters().getEndpointIdentificationAlgorithm());
        assertTrue(engine.getEnabledProtocols().length > 0);
        for (String protocol : engine.getEnabledProtocols()) {
            assertTrue(protocol.equals("TLSv1.2") || protocol.equals("TLSv1.3"));
            assertTrue(Arrays.asList(engine.getSupportedProtocols()).contains(protocol));
        }
    }

    @Test public void realHandshakeOffersOneProtocolAndNoCompression() throws Exception {
        try (Fixture fixture = new Fixture()) {
            String request = fixture.request;
            assertTrue(request.startsWith("GET /v1/rendezvous HTTP/1.1\r\n"));
            assertEquals(NettyPairingWssTransport.SUBPROTOCOL, header(request, "Sec-WebSocket-Protocol"));
            assertFalse(request.toLowerCase(java.util.Locale.ROOT).contains("sec-websocket-extensions"));
            assertFalse(request.contains("?"));
            assertFalse(fixture.transport.whenOpen().toCompletableFuture().isDone());
            fixture.open();
            assertTrue(fixture.transport.whenOpen().toCompletableFuture().isDone());
            assertEquals(1, fixture.listener.opens);
            assertEquals(0, fixture.listener.terminals);
        }
    }

    @Test public void missingWrongCommaAndDuplicateProtocolsFailBeforeOpen() throws Exception {
        for (int mode = 0; mode < 4; mode++) {
            try (Fixture fixture = new Fixture()) {
                FullHttpResponse response = fixture.response();
                if (mode == 0) response.headers().remove(HttpHeaderNames.SEC_WEBSOCKET_PROTOCOL);
                if (mode == 1) response.headers().set(HttpHeaderNames.SEC_WEBSOCKET_PROTOCOL, "wrong.v1");
                if (mode == 2) response.headers().set(HttpHeaderNames.SEC_WEBSOCKET_PROTOCOL,
                        NettyPairingWssTransport.SUBPROTOCOL + ", other");
                if (mode == 3) response.headers().add(HttpHeaderNames.SEC_WEBSOCKET_PROTOCOL, NettyPairingWssTransport.SUBPROTOCOL);
                fixture.channel.writeInbound(response);
                fixture.channel.runPendingTasks();
                assertFailure(fixture.transport.whenOpen(), NettyPairingWssTransport.FailureCode.UPGRADE_REFUSED);
                assertEquals(0, fixture.listener.opens);
            }
        }
    }

    @Test public void redirectsExtensionsDuplicateAcceptAndWrongChallengeFailClosed() throws Exception {
        for (int mode = 0; mode < 5; mode++) {
            try (Fixture fixture = new Fixture()) {
                FullHttpResponse response = fixture.response();
                if (mode == 0) response.setStatus(HttpResponseStatus.FOUND);
                if (mode == 1) response.headers().set(HttpHeaderNames.SEC_WEBSOCKET_EXTENSIONS, "permessage-deflate");
                if (mode == 2) response.headers().set(HttpHeaderNames.LOCATION, "https://other.example/");
                if (mode == 3) response.headers().add(HttpHeaderNames.SEC_WEBSOCKET_ACCEPT, fixture.accept);
                if (mode == 4) response.headers().set(HttpHeaderNames.SEC_WEBSOCKET_ACCEPT, "wrong");
                fixture.channel.writeInbound(response);
                fixture.channel.runPendingTasks();
                assertFailure(fixture.transport.whenOpen(), NettyPairingWssTransport.FailureCode.UPGRADE_REFUSED);
                assertEquals(0, fixture.listener.opens);
            }
        }
    }

    @Test public void oversizedActualHttpHeadersFailBeforeOpen() throws Exception {
        try (Fixture fixture = new Fixture()) {
            String response = "HTTP/1.1 101 Switching Protocols\r\nX-Fill: "
                    + repeat('x', 9000) + "\r\n\r\n";
            fixture.channel.writeInbound(Unpooled.copiedBuffer(response, StandardCharsets.US_ASCII));
            fixture.channel.runPendingTasks();
            assertTrue(fixture.transport.whenOpen().toCompletableFuture().isCompletedExceptionally());
            assertEquals(0, fixture.listener.opens);
        }
    }

    @Test public void exactNinetyThousandFragmentedTextIsDeliveredOnce() throws Exception {
        try (Fixture fixture = new Fixture()) {
            fixture.open();
            fixture.channel.writeInbound(frame(1, false, bytes(40_000, 'a')));
            assertEquals(0, fixture.listener.messages.size());
            fixture.channel.writeInbound(frame(0, true, bytes(50_000, 'b')));
            assertEquals(1, fixture.listener.messages.size());
            byte[] delivered = fixture.listener.messages.get(0);
            assertEquals(90_000, delivered.length);
            assertEquals('a', delivered[0]); assertEquals('b', delivered[89_999]);
        }
    }

    @Test public void cumulativeOverflowNeverReachesListener() throws Exception {
        try (Fixture fixture = new Fixture()) {
            fixture.open();
            fixture.channel.writeInbound(frame(1, false, bytes(50_000, 'a')));
            fixture.channel.writeInbound(frame(0, true, bytes(40_001, 'b')));
            assertEquals(0, fixture.listener.messages.size());
            assertFalse(fixture.channel.isOpen());
        }
    }

    @Test public void declaredOversizedFrameIsRejectedWithNoBodyPresent() throws Exception {
        try (Fixture fixture = new Fixture()) {
            fixture.open();
            ByteBuf header = Unpooled.buffer(10).writeByte(0x81).writeByte(127).writeLong(90_001);
            fixture.channel.writeInbound(header);
            fixture.channel.runPendingTasks();
            assertEquals(0, fixture.listener.messages.size());
            assertFalse(fixture.channel.isOpen());
        }
    }

    @Test public void emptyFragmentFloodIsCountBounded() throws Exception {
        try (Fixture fixture = new Fixture()) {
            fixture.open();
            fixture.channel.writeInbound(frame(1, false, new byte[0]));
            for (int i = 1; i < 64; i++) fixture.channel.writeInbound(frame(0, false, new byte[0]));
            assertTrue(fixture.channel.isOpen());
            fixture.channel.writeInbound(frame(0, false, new byte[0]));
            assertFalse(fixture.channel.isOpen());
            assertEquals(0, fixture.listener.messages.size());
        }
    }

    @Test public void unfinishedFragmentHasAbsoluteDeadline() throws Exception {
        try (Fixture fixture = new Fixture()) {
            fixture.open();
            fixture.channel.writeInbound(frame(1, false, bytes(1, 'a')));
            fixture.channel.advanceTimeBy(9, TimeUnit.SECONDS);
            fixture.channel.runScheduledPendingTasks();
            fixture.channel.writeInbound(frame(0, false, bytes(1, 'a')));
            fixture.channel.advanceTimeBy(2, TimeUnit.SECONDS);
            fixture.channel.runScheduledPendingTasks();
            assertFalse(fixture.channel.isOpen());
            assertEquals(0, fixture.listener.messages.size());
        }
    }

    @Test public void binaryInvalidUtf8MaskAndRsvNeverReachListener() throws Exception {
        for (int mode = 0; mode < 4; mode++) {
            try (Fixture fixture = new Fixture()) {
                fixture.open();
                ByteBuf value;
                if (mode == 0) value = frame(2, true, bytes(1, 'a'));
                else if (mode == 1) value = frame(1, true, new byte[] {(byte) 0xc3, 0x28});
                else if (mode == 2) value = Unpooled.buffer(7).writeByte(0x81).writeByte(0x81).writeInt(0).writeByte('a');
                else value = Unpooled.buffer(3).writeByte(0xc1).writeByte(1).writeByte('a');
                fixture.channel.writeInbound(value);
                fixture.channel.runPendingTasks();
                assertFalse(fixture.channel.isOpen());
                assertEquals(0, fixture.listener.messages.size());
            }
        }
    }

    @Test public void realSendPromiseIsNotQueueAcknowledgementAndCopiesCallerBytes() throws Exception {
        try (Fixture fixture = new Fixture()) {
            fixture.open();
            HeldWrites held = new HeldWrites(); fixture.channel.pipeline().addFirst("held", held);
            byte[] caller = "hello".getBytes(StandardCharsets.UTF_8);
            CompletionStage<Void> write = fixture.transport.send(caller);
            Arrays.fill(caller, (byte) 'x'); fixture.channel.runPendingTasks();
            assertEquals(1, held.pending.size());
            assertFalse(write.toCompletableFuture().isDone());
            ByteBuf wire = (ByteBuf) held.pending.get(0).message;
            assertEquals(0x81, wire.getUnsignedByte(wire.readerIndex()));
            assertTrue((wire.getUnsignedByte(wire.readerIndex() + 1) & 128) != 0);
            assertEquals("hello", unmaskSmallText(wire));
            held.succeedFirst();
            assertTrue(write.toCompletableFuture().isDone());
            assertFalse(write.toCompletableFuture().isCompletedExceptionally());
        }
    }

    @Test public void outstandingSendCountIsBoundedAndCapacityReturnsOnlyOnCompletion() throws Exception {
        try (Fixture fixture = new Fixture()) {
            fixture.open();
            HeldWrites held = new HeldWrites(); fixture.channel.pipeline().addFirst("held", held);
            List<CompletionStage<Void>> accepted = new ArrayList<>();
            for (int i = 0; i < 4; i++) accepted.add(fixture.transport.send(bytes(90_000, 'a')));
            fixture.channel.runPendingTasks();
            assertEquals(4, held.pending.size());
            assertFailure(fixture.transport.send(bytes(1, 'a')), NettyPairingWssTransport.FailureCode.SEND_BACKPRESSURE);
            for (CompletionStage<Void> value : accepted) assertFalse(value.toCompletableFuture().isDone());
            held.succeedFirst();
            CompletionStage<Void> fifth = fixture.transport.send(bytes(1, 'b'));
            fixture.channel.runPendingTasks();
            assertFalse(fifth.toCompletableFuture().isDone());
            assertEquals(4, held.pending.size());
        }
    }

    @Test public void queuedGuardedWriteIsRevokedBeforeActualNettyWriterAndReturnsCapacity() throws Exception {
        try (Fixture fixture = new Fixture()) {
            fixture.open();
            HeldWrites held = new HeldWrites(); fixture.channel.pipeline().addFirst("held", held);
            AtomicBoolean authorized = new AtomicBoolean(true);
            CompletionStage<Void> queued = fixture.transport.sendGuarded(bytes(90_000, 'a'), authorized::get);
            // EmbeddedEventLoop has accepted, but not executed, the production write Runnable.
            // Unlike holding a ChannelPromise after write(), this is the exact pre-write cut.
            assertFalse(queued.toCompletableFuture().isDone());
            assertTrue(held.pending.isEmpty()); assertNull(fixture.channel.readOutbound());
            authorized.set(false);
            fixture.channel.runPendingTasks();
            assertFailure(queued, NettyPairingWssTransport.FailureCode.NOT_OPEN);
            assertTrue(held.pending.isEmpty()); assertNull(fixture.channel.readOutbound());
            assertTrue(fixture.channel.isOpen()); assertEquals(0, fixture.listener.terminals);
            // Revocation of this exact send is not permission to stop another session or leak
            // a reserved count/byte slot. All four full-sized slots must now be reusable.
            List<CompletionStage<Void>> fresh = new ArrayList<>();
            for (int index = 0; index < 4; index++) {
                fresh.add(fixture.transport.sendGuarded(bytes(90_000, 'b'), () -> true));
            }
            fixture.channel.runPendingTasks();
            assertEquals(4, held.pending.size());
            assertFailure(fixture.transport.sendGuarded(bytes(1, 'c'), () -> true),
                    NettyPairingWssTransport.FailureCode.SEND_BACKPRESSURE);
            for (CompletionStage<Void> value : fresh) assertFalse(value.toCompletableFuture().isDone());
            for (CompletionStage<Void> value : fresh) {
                held.succeedFirst();
                assertTrue(value.toCompletableFuture().isDone());
                assertFalse(value.toCompletableFuture().isCompletedExceptionally());
            }
        }
    }

    @Test public void rejectedGuardAtAdmissionNeverQueuesOrReachesActualNettyWriter() throws Exception {
        try (Fixture fixture = new Fixture()) {
            fixture.open();
            HeldWrites held = new HeldWrites(); fixture.channel.pipeline().addFirst("held", held);
            assertFailure(fixture.transport.sendGuarded(bytes(1, 'a'), () -> false),
                    NettyPairingWssTransport.FailureCode.NOT_OPEN);
            fixture.channel.runPendingTasks();
            assertTrue(held.pending.isEmpty()); assertNull(fixture.channel.readOutbound());
            assertTrue(fixture.channel.isOpen()); assertEquals(0, fixture.listener.terminals);
        }
    }

    @Test public void throwingQueuedGuardFailsClosedWithoutNativeWrite() throws Exception {
        try (Fixture fixture = new Fixture()) {
            fixture.open();
            HeldWrites held = new HeldWrites(); fixture.channel.pipeline().addFirst("held", held);
            AtomicBoolean rejected = new AtomicBoolean();
            CompletionStage<Void> queued = fixture.transport.sendGuarded(bytes(1, 'a'), () -> {
                if (rejected.get()) throw new IllegalStateException("fixed fixture guard refusal");
                return true;
            });
            assertFalse(queued.toCompletableFuture().isDone());
            rejected.set(true); fixture.channel.runPendingTasks();
            assertFailure(queued, NettyPairingWssTransport.FailureCode.NOT_OPEN);
            assertTrue(held.pending.isEmpty()); assertNull(fixture.channel.readOutbound());
            assertTrue(fixture.channel.isOpen()); assertEquals(0, fixture.listener.terminals);
        }
    }

    @Test public void heldWriteTimeoutRetiresAndFailsExactTicket() throws Exception {
        try (Fixture fixture = new Fixture()) {
            fixture.open();
            HeldWrites held = new HeldWrites(); fixture.channel.pipeline().addFirst("held", held);
            CompletionStage<Void> write = fixture.transport.send(bytes(1, 'a'));
            fixture.channel.runPendingTasks();
            fixture.channel.advanceTimeBy(11, TimeUnit.SECONDS);
            fixture.channel.runScheduledPendingTasks();
            assertFailure(write, NettyPairingWssTransport.FailureCode.WRITE_TIMEOUT);
            assertFalse(fixture.channel.isOpen());
        }
    }

    @Test public void invalidOutgoingUtf8AndSizeDoNotReachNativeWriter() throws Exception {
        try (Fixture fixture = new Fixture()) {
            fixture.open();
            assertFailure(fixture.transport.send(new byte[] {(byte) 0xff}), NettyPairingWssTransport.FailureCode.INVALID_TEXT);
            assertFailure(fixture.transport.send(bytes(90_001, 'a')), NettyPairingWssTransport.FailureCode.INVALID_TEXT);
            assertFailure(fixture.transport.send(new byte[0]), NettyPairingWssTransport.FailureCode.INVALID_TEXT);
            assertNull(fixture.channel.readOutbound());
        }
    }

    @Test public void controlWriteFloodIsBounded() throws Exception {
        try (Fixture fixture = new Fixture()) {
            fixture.open();
            HeldWrites held = new HeldWrites(); fixture.channel.pipeline().addFirst("held", held);
            for (int i = 0; i < 4; i++) fixture.channel.writeInbound(frame(9, true, bytes(1, 'p')));
            assertEquals(4, held.pending.size());
            fixture.channel.writeInbound(frame(9, true, bytes(1, 'p')));
            assertFalse(fixture.channel.isOpen());
            assertEquals(0, fixture.listener.messages.size());
        }
    }

    @Test public void closeCoalescesAndWaitsForDnsLoopAndFinalCallback() throws Exception {
        try (Fixture fixture = new Fixture()) {
            fixture.open();
            CompletionStage<Void> first = fixture.transport.closeAsync();
            CompletionStage<Void> second = fixture.transport.closeAsync();
            assertFalse(first.toCompletableFuture().isDone());
            assertFalse(second.toCompletableFuture().isDone());
            assertFailure(fixture.transport.send(bytes(1, 'a')), NettyPairingWssTransport.FailureCode.NOT_OPEN);
            fixture.loopDrain.complete(null);
            assertFalse(first.toCompletableFuture().isDone());
            fixture.listener.inTerminal = () -> {
                assertFalse(first.toCompletableFuture().isDone());
                assertFalse(second.toCompletableFuture().isDone());
            };
            fixture.dnsDrain.complete(null);
            assertTrue(first.toCompletableFuture().isDone());
            assertTrue(second.toCompletableFuture().isDone());
            assertEquals(1, fixture.listener.terminals);
        }
    }

    @Test public void failedDrainIsNeverReportedAsSuccessfulClose() throws Exception {
        try (Fixture fixture = new Fixture()) {
            fixture.open();
            CompletionStage<Void> close = fixture.transport.closeAsync();
            fixture.dnsDrain.complete(null);
            fixture.loopDrain.completeExceptionally(new IllegalStateException("synthetic public failure"));
            assertFailure(close, NettyPairingWssTransport.FailureCode.DRAIN_FAILED);
            assertEquals(1, fixture.listener.terminals);
            assertEquals(NettyPairingWssTransport.FailureCode.DRAIN_FAILED, fixture.listener.terminalReason);
        }
    }

    @Test public void firstActualNativeCloseFailureSurvivesSuccessfulDuplicateClose() throws Exception {
        try (Fixture fixture = new Fixture()) {
            fixture.open();
            fixture.channel.failActualClose = true;
            // Real AbstractChannel invokes doClose, marks closeFuture complete, but fails this promise.
            ChannelPromise first = fixture.channel.newPromise();
            fixture.channel.close(first);
            assertTrue(first.isDone()); assertFalse(first.isSuccess());
            assertTrue(fixture.channel.closeFuture().isSuccess());
            // Pinned AbstractChannel's closeInitiated branch reports this duplicate as successful.
            assertTrue(fixture.channel.close().isSuccess());
            CompletionStage<Void> close = fixture.transport.closeAsync();
            fixture.loopDrain.complete(null); fixture.dnsDrain.complete(null);
            assertFailure(close, NettyPairingWssTransport.FailureCode.DRAIN_FAILED);
            assertEquals(1, fixture.listener.terminals);
            assertEquals(NettyPairingWssTransport.FailureCode.DRAIN_FAILED, fixture.listener.terminalReason);
        }
    }

    @Test public void closeDuringOpenCallbackCannotResurrectOpen() throws Exception {
        try (Fixture fixture = new Fixture()) {
            fixture.listener.inOpen = () -> fixture.transport.closeAsync();
            fixture.open();
            assertFailure(fixture.transport.whenOpen(), NettyPairingWssTransport.FailureCode.CLOSED);
            assertFalse(fixture.channel.isOpen());
            assertFailure(fixture.transport.send(bytes(1, 'a')), NettyPairingWssTransport.FailureCode.NOT_OPEN);
        }
    }

    @Test public void closedOwnerDoesNotDeliverLaterFrames() throws Exception {
        try (Fixture fixture = new Fixture()) {
            fixture.open();
            fixture.listener.inText = () -> fixture.transport.closeAsync();
            // Both raw frames are already in the same decoder input before the first callback closes.
            ByteBuf coalesced = frame(1, true, bytes(1, 'a'));
            ByteBuf late = frame(1, true, bytes(1, 'b'));
            try { coalesced.writeBytes(late); } finally { late.release(); }
            fixture.channel.writeInbound(coalesced);
            assertEquals(1, fixture.listener.messages.size());
            assertEquals('a', fixture.listener.messages.get(0)[0]);
            assertFalse(fixture.channel.isOpen());
            assertFailure(fixture.transport.send(bytes(1, 'a')), NettyPairingWssTransport.FailureCode.NOT_OPEN);
        }
    }

    private static final class Observation implements NettyPairingWssTransport.Listener {
        int opens, terminals;
        NettyPairingWssTransport.FailureCode terminalReason;
        final List<byte[]> messages = new ArrayList<>();
        Runnable inOpen, inText, inTerminal;
        @Override public void onOpen() { opens++; if (inOpen != null) inOpen.run(); }
        @Override public void onText(byte[] bytes) { messages.add(bytes); if (inText != null) inText.run(); }
        @Override public void onTerminal(NettyPairingWssTransport.FailureCode reason) {
            terminals++; terminalReason = reason; if (inTerminal != null) inTerminal.run();
        }
    }

    private static final class Fixture implements AutoCloseable {
        final CompletableFuture<Void> firstNativeClose = new CompletableFuture<>();
        final ObservedEmbeddedChannel channel = new ObservedEmbeddedChannel(firstNativeClose);
        final Observation listener = new Observation();
        final CompletableFuture<Void> loopDrain = new CompletableFuture<>();
        final CompletableFuture<Void> dnsDrain = new CompletableFuture<>();
        final NettyPairingWssTransport transport;
        final ViewerAvailabilityEnvelopeCodec.JoinHeaders availabilityHeaders;
        final String subprotocol;
        final String request, accept;
        Fixture() throws Exception { this(false); }
        Fixture(boolean availability) throws Exception {
            availabilityHeaders = availability ? availabilityJoin() : null;
            subprotocol = availability ? NettyPairingWssTransport.AVAILABILITY_SUBPROTOCOL : NettyPairingWssTransport.SUBPROTOCOL;
            transport = availability
                    ? NettyPairingWssTransport.embeddedAvailability(channel, availabilityHeaders,
                            listener, loopDrain, dnsDrain, firstNativeClose)
                    : NettyPairingWssTransport.embedded(channel, join(PairingCanonicalCodec.Role.VIEWER),
                            listener, loopDrain, dnsDrain, firstNativeClose);
            channel.runPendingTasks();
            ByteArrayOutputStream bytes = new ByteArrayOutputStream();
            Object outgoing;
            while ((outgoing = channel.readOutbound()) != null) {
                try {
                    assertTrue(outgoing instanceof ByteBuf);
                    ByteBuf value = (ByteBuf) outgoing;
                    byte[] owned = new byte[value.readableBytes()]; value.readBytes(owned); bytes.write(owned);
                } finally { ReferenceCountUtil.release(outgoing); }
            }
            request = new String(bytes.toByteArray(), StandardCharsets.US_ASCII);
            String key = header(request, "Sec-WebSocket-Key");
            accept = Base64.getEncoder().encodeToString(MessageDigest.getInstance("SHA-1").digest(
                    (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").getBytes(StandardCharsets.US_ASCII)));
        }
        FullHttpResponse response() {
            FullHttpResponse result = new DefaultFullHttpResponse(HttpVersion.HTTP_1_1, HttpResponseStatus.SWITCHING_PROTOCOLS);
            result.headers().set(HttpHeaderNames.UPGRADE, "websocket");
            result.headers().set(HttpHeaderNames.CONNECTION, "Upgrade");
            result.headers().set(HttpHeaderNames.SEC_WEBSOCKET_ACCEPT, accept);
            result.headers().set(HttpHeaderNames.SEC_WEBSOCKET_PROTOCOL, subprotocol);
            return result;
        }
        void open() {
            channel.writeInbound(response()); channel.runPendingTasks();
        }
        @Override public void close() {
            transport.closeAsync(); channel.runPendingTasks(); channel.runScheduledPendingTasks();
            channel.finishAndReleaseAll();
            dnsDrain.complete(null); loopDrain.complete(null);
        }
    }

    private static final class ObservedEmbeddedChannel extends EmbeddedChannel {
        private final CompletableFuture<Void> firstNativeClose;
        boolean failActualClose;
        ObservedEmbeddedChannel(CompletableFuture<Void> firstNativeClose) {
            this.firstNativeClose = firstNativeClose;
        }
        @Override protected void doClose() throws Exception {
            try {
                super.doClose();
                if (failActualClose) throw new IllegalStateException("synthetic native close failure");
                firstNativeClose.complete(null);
            } catch (Exception | Error error) {
                firstNativeClose.completeExceptionally(error);
                throw error;
            }
        }
    }

    private static final class HeldWrites extends ChannelDuplexHandler {
        final List<Held> pending = new ArrayList<>();
        @Override public void write(ChannelHandlerContext context, Object message, ChannelPromise promise) {
            pending.add(new Held(message, promise));
        }
        void succeedFirst() {
            Held held = pending.remove(0); ReferenceCountUtil.release(held.message); held.promise.setSuccess();
        }
        @Override public void close(ChannelHandlerContext context, ChannelPromise promise) {
            for (Held held : pending) { ReferenceCountUtil.release(held.message); held.promise.tryFailure(new IllegalStateException("synthetic closed")); }
            pending.clear(); context.close(promise);
        }
    }
    private static final class Held {
        final Object message; final ChannelPromise promise;
        Held(Object message, ChannelPromise promise) { this.message = message; this.promise = promise; }
    }

    private static ByteBuf frame(int opcode, boolean last, byte[] payload) {
        ByteBuf result = Unpooled.buffer(payload.length + 10);
        result.writeByte((last ? 128 : 0) | opcode);
        if (payload.length < 126) result.writeByte(payload.length);
        else if (payload.length <= 65535) result.writeByte(126).writeShort(payload.length);
        else result.writeByte(127).writeLong(payload.length);
        return result.writeBytes(payload);
    }
    private static String unmaskSmallText(ByteBuf wire) {
        int start = wire.readerIndex(); int length = wire.getUnsignedByte(start + 1) & 127;
        assertTrue(length < 126); byte[] decoded = new byte[length];
        for (int i = 0; i < length; i++) decoded[i] = (byte) (wire.getByte(start + 6 + i) ^ wire.getByte(start + 2 + i % 4));
        return new String(decoded, StandardCharsets.UTF_8);
    }
    private static String header(String request, String name) {
        Matcher match = Pattern.compile("(?im)^" + Pattern.quote(name) + ":\\s*([^\\r\\n]+)\\r?$").matcher(request);
        assertTrue(match.find()); String value = match.group(1).trim(); assertFalse(match.find()); return value;
    }
    private static PairingBootstrapEnvelopeCodec.JoinHeaders join(PairingCanonicalCodec.Role role) throws Exception {
        // Public deterministic zero-secret invitation only. No real user capability or saved key.
        byte[] body = new byte[21]; body[0] = 1;
        MessageDigest hash = MessageDigest.getInstance("SHA-256");
        hash.update("AudioStreamer.RemoteInvitation.Checksum.v1\0".getBytes(StandardCharsets.US_ASCII));
        byte[] packet = Arrays.copyOf(body, 25); System.arraycopy(hash.digest(body), 0, packet, 21, 4);
        StringBuilder code = new StringBuilder(); int bits = 0, accumulator = 0;
        for (byte value : packet) {
            accumulator = (accumulator << 8) | (value & 255); bits += 8;
            while (bits >= 5) { bits -= 5; code.append("0123456789ABCDEFGHJKMNPQRSTVWXYZ".charAt((accumulator >>> bits) & 31)); }
        }
        try (PairingBootstrapEnvelopeCodec codec = PairingBootstrapEnvelopeCodec.createForFixture(
                PairingInvitation.parseManual(code.toString()), role, () -> new byte[12])) {
            return codec.copyJoinHeaders();
        }
    }

    private static ViewerAvailabilityEnvelopeCodec.JoinHeaders availabilityJoin() throws Exception {
        // Actual authenticated ACTIVE record path, using only retained PUBLIC synthetic inputs.
        // This does not simulate Android durable admission or a selected saved-Mac owner.
        Map<String, byte[]> rows = publicPairingFixture();
        UUID viewerID = UUID.fromString(new String(publicValue(rows, "input.viewer-device-id"), StandardCharsets.US_ASCII));
        ViewerPairingAuthenticator.ViewerIdentity identity = ViewerPairingAuthenticator.viewerIdentity(
                viewerID, publicValue(rows, "input.viewer-signing-seed"));
        ViewerPairingAuthenticator.PreparedViewer prepared = ViewerPairingAuthenticator.authenticateRetainedLocalHello(
                viewerID, "Test iPhone", publicValue(rows, "input.viewer-signing-seed"),
                publicValue(rows, "input.invitation-secret"), publicValue(rows, "input.viewer-ephemeral-private"),
                publicValue(rows, "input.viewer-nonce"),
                (PairingPayloadDecoder.HelloPayload) PairingPayloadDecoder.decode(publicValue(rows, "hello.viewer.payload")));
        ViewerPairingAuthenticator.Agreement agreement = ViewerPairingAuthenticator.acceptHost(prepared,
                (PairingPayloadDecoder.HelloPayload) PairingPayloadDecoder.decode(publicValue(rows, "hello.host.payload")));
        ViewerPairingAuthenticator.ViewerPairRecord pending = agreement.makePendingRecord(
                agreement.authenticateHostConfirmation((PairingPayloadDecoder.ConfirmationPayload)
                        PairingPayloadDecoder.decode(publicValue(rows, "confirmation.host.payload"))), 1700000000.25);
        ViewerPairingAuthenticator.ViewerPairRecord accepted = pending.prepareAcknowledgement(
                (PairingPayloadDecoder.CommitPayload) PairingPayloadDecoder.decode(publicValue(rows, "commit.proposal.payload")), identity).record();
        ViewerPairingAuthenticator.ViewerPairRecord active = accepted.acceptCompletion(
                (PairingPayloadDecoder.CommitPayload) PairingPayloadDecoder.decode(publicValue(rows, "commit.completion.payload")), identity).record();
        try (ViewerAvailabilityLocator locator = active.availabilityLocator()) {
            return locator.copyJoinHeaders();
        }
    }

    private static Map<String, byte[]> publicPairingFixture() throws Exception {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        try (InputStream input = NettyPairingWssTransportTest.class.getResourceAsStream("/public-swift-engine-v1.tsv")) {
            assertNotNull("Exact PUBLIC synthetic Swift resource required", input);
            byte[] chunk = new byte[4096]; int count;
            while ((count = input.read(chunk)) != -1) {
                assertTrue("PUBLIC fixture bounded before append", output.size() + count <= 64 * 1024);
                output.write(chunk, 0, count);
            }
        }
        byte[] file = output.toByteArray();
        byte[] digest = MessageDigest.getInstance("SHA-256").digest(file);
        StringBuilder hex = new StringBuilder();
        for (byte value : digest) hex.append(String.format(java.util.Locale.ROOT, "%02x", value & 255));
        assertEquals("7d8a58cd34400271d0c68ac1e263450c4ad4978337ae1bb87246362a6d0ec06a", hex.toString());
        Map<String, byte[]> rows = new TreeMap<>(); String previous = "";
        for (String line : new String(file, StandardCharsets.US_ASCII).split("\n")) {
            if (line.startsWith("#")) continue;
            String[] fields = line.split("\t", -1); assertEquals(2, fields.length);
            assertTrue(previous.compareTo(fields[0]) < 0);
            byte[] value = Base64.getDecoder().decode(fields[1]);
            assertEquals(fields[1], Base64.getEncoder().encodeToString(value));
            assertNull(rows.put(fields[0], value)); previous = fields[0];
        }
        assertEquals(45, rows.size()); return rows;
    }

    private static byte[] publicValue(Map<String, byte[]> rows, String name) {
        byte[] value = rows.get(name); assertNotNull("Required PUBLIC fixture row", value); return value.clone();
    }
    private static byte[] bytes(int size, char value) { byte[] result = new byte[size]; Arrays.fill(result, (byte) value); return result; }
    private static String repeat(char value, int count) { char[] result = new char[count]; Arrays.fill(result, value); return new String(result); }
    private static void assertFailure(CompletionStage<Void> stage, NettyPairingWssTransport.FailureCode expected) {
        CompletableFuture<Void> result = stage.toCompletableFuture();
        assertTrue("Expected a completed refusal, not a blocking wait", result.isDone());
        try { result.join(); fail("Expected redacted failure"); }
        catch (CompletionException error) {
            Throwable cause = error.getCause();
            assertTrue(cause instanceof NettyPairingWssTransport.TransportFailure);
            NettyPairingWssTransport.TransportFailure failure = (NettyPairingWssTransport.TransportFailure) cause;
            assertEquals(expected, failure.code()); assertEquals(null, failure.getCause());
            assertEquals(0, failure.getSuppressed().length);
        }
    }
}
