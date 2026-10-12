package com.elamin.beluga.protocol;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.lang.reflect.Field;
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
import org.junit.Before;
import org.junit.Test;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Role;
import com.elamin.beluga.protocol.PairingPayloadDecoder.CommitPayload;
import com.elamin.beluga.protocol.PairingPayloadDecoder.ConfirmationPayload;
import com.elamin.beluga.protocol.PairingPayloadDecoder.HelloPayload;
import com.elamin.beluga.protocol.ViewerAvailabilityEnvelopeCodec.EnvelopeFailure;
import com.elamin.beluga.protocol.ViewerAvailabilityEnvelopeCodec.FailureCode;
import com.elamin.beluga.protocol.ViewerAvailabilityEnvelopeCodec.Kind;
import com.elamin.beluga.protocol.ViewerAvailabilityEnvelopeCodec.ServerError;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.Agreement;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.PreparedViewer;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.ViewerIdentity;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.ViewerPairRecord;

/** Actual independent Swift captures; no socket, durable request send, media or device proof. */
public final class ViewerAvailabilityEnvelopeCodecTest {
    private static final String CAPTURE_SHA = "c204b3e755aacdc8e4563f448547e0e85d17ce5b081e103b53b54f26e530ed20";
    private static final String PAIRING_SHA = "7d8a58cd34400271d0c68ac1e263450c4ad4978337ae1bb87246362a6d0ec06a";
    private Map<String, byte[]> capture, pairing;
    private ViewerPairRecord active, pending;
    private String exchange;

    @Before public void loadActualSwiftCapturesAndAuthenticatedActiveRecord() throws Exception {
        capture = load("/public-swift-availability-v1.tsv", CAPTURE_SHA, 20);
        pairing = load("/public-swift-engine-v1.tsv", PAIRING_SHA, 45);
        Set<String> expected = new HashSet<>(Arrays.asList("basis.pairing-sha256", "basis.reconnect-sha256", "input.pair-id",
                "input.root-public-test-only", "input.transcript", "derived.channel", "derived.viewer-admission",
                "derived.host-key", "derived.viewer-key", "exchange.wire", "exchange.raw"));
        for (String name : new String[] {"activation", "request", "response"})
            for (String field : new String[] {"payload", "outbound", "inbound"}) expected.add("capture." + name + "." + field);
        assertEquals(expected, capture.keySet());
        assertEquals(PAIRING_SHA, text(value("basis.pairing-sha256")));
        assertArrayEquals(pairing.get("derived.pair-root-public-test-only"), value("input.root-public-test-only"));
        assertArrayEquals(pairing.get("derived.transcript-hash"), value("input.transcript"));
        assertArrayEquals(pairing.get("derived.pair-id-text"), value("input.pair-id"));
        assertEquals(32, value("derived.host-key").length); assertEquals(32, value("derived.viewer-key").length);
        assertFalse(Arrays.equals(value("derived.host-key"), value("derived.viewer-key")));
        exchange = text(value("exchange.wire")); assertEquals(22, exchange.length());
        assertArrayEquals(value("exchange.raw"), Base64.getUrlDecoder().decode(exchange));
        UUID viewer = UUID.fromString(text(pairing.get("input.viewer-device-id")));
        ViewerIdentity identity = ViewerPairingAuthenticator.viewerIdentity(viewer, pairing.get("input.viewer-signing-seed"));
        PreparedViewer prepared = ViewerPairingAuthenticator.authenticateRetainedLocalHello(viewer,
                text(pairing.get("input.viewer-display-name")), pairing.get("input.viewer-signing-seed"),
                pairing.get("input.invitation-secret"), pairing.get("input.viewer-ephemeral-private"), pairing.get("input.viewer-nonce"),
                (HelloPayload) PairingPayloadDecoder.decode(pairing.get("hello.viewer.payload")));
        Agreement agreement = ViewerPairingAuthenticator.acceptHost(prepared,
                (HelloPayload) PairingPayloadDecoder.decode(pairing.get("hello.host.payload")));
        pending = agreement.makePendingRecord(agreement.authenticateHostConfirmation(
                (ConfirmationPayload) PairingPayloadDecoder.decode(pairing.get("confirmation.host.payload"))), 1700000000.25);
        ViewerPairRecord accepted = pending.prepareAcknowledgement(
                (CommitPayload) PairingPayloadDecoder.decode(pairing.get("commit.proposal.payload")), identity).record();
        active = accepted.acceptCompletion((CommitPayload) PairingPayloadDecoder.decode(pairing.get("commit.completion.payload")), identity).record();
    }

    @Test public void realViewerDerivationActivationThenRequestAndHostResponseMatchSwiftBytes() throws Exception {
        final int[] nonce = {0};
        byte[][] capturedNonces = { capturedNonce("activation"), capturedNonce("request") };
        try (ViewerAvailabilityLocator locator = active.availabilityLocator();
             ViewerAvailabilityEnvelopeCodec codec = locator.codecForFixture(() -> capturedNonces[nonce[0]++], 0)) {
            ViewerAvailabilityEnvelopeCodec.JoinHeaders headers = locator.copyJoinHeaders();
            assertEquals("viewer", headers.role()); assertEquals(text(value("derived.channel")), headers.channelID());
            assertEquals(text(value("derived.viewer-admission")), headers.admissionProofForUpgradeHeader());
            ready(codec);
            ViewerAvailabilityEnvelopeCodec.Outbound activation = codec.sealActivation(pairing.get("commit.activationAcknowledgement.payload"));
            assertEquals(0, activation.sequence()); assertEquals(exchange, activation.exchangeID());
            assertArrayEquals(value("capture.activation.outbound"), activation.copyWireBytes());
            ViewerAvailabilityEnvelopeCodec.Outbound request = codec.sealRequest(value("capture.request.payload"));
            assertEquals(1, request.sequence()); assertArrayEquals(value("capture.request.outbound"), request.copyWireBytes());
            for (String name : new String[] {"activation", "request"})
                assertArrayEquals(value("capture." + name + ".payload"), BouncyCastlePairingCrypto.openCombined(
                        value("derived.viewer-key"), capturedCombined(name), aad(name.equals("activation") ? 0 : 1, 2)));
            ViewerAvailabilityEnvelopeCodec.Event response = codec.receive(value("capture.response.inbound"));
            assertEquals(Kind.SIGNAL_RESPONSE, response.kind()); assertEquals(exchange, response.exchangeID());
            assertArrayEquals(value("capture.response.payload"), ReconnectMessages.responsePayload(response.response()));
            assertEquals(2, nonce[0]);
            assertArrayEquals(value("capture.response.payload"), BouncyCastlePairingCrypto.openCombined(
                    value("derived.host-key"), capturedCombined("response"), aad(0, 1)));
        }
    }

    @Test public void duplicateReadyPreservesSequenceAndReplayAdmission() throws Exception {
        try (ViewerAvailabilityEnvelopeCodec codec = codec()) {
            ready(codec); assertEquals(0, codec.sealActivation(pairing.get("commit.activationAcknowledgement.payload")).sequence());
            assertEquals(Kind.SIGNAL_RESPONSE, codec.receive(value("capture.response.inbound")).kind());
            ready(codec); assertEquals(1, codec.sealRequest(value("capture.request.payload")).sequence());
            refused(FailureCode.REPLAYED_SEQUENCE, () -> codec.receive(value("capture.response.inbound")));
        }
    }

    @Test public void newExchangeRekeysAndOldMessagesCannotCrossIt() throws Exception {
        try (ViewerAvailabilityEnvelopeCodec codec = codec()) {
            ready(codec); codec.sealRequest(value("capture.request.payload"));
            String changed = Base64.getUrlEncoder().withoutPadding().encodeToString(repeat(0x33, 16));
            assertEquals(Kind.READY, codec.receive(readyWire(changed)).kind());
            assertEquals(changed, codec.currentExchangeID());
            assertEquals(0, codec.sealRequest(value("capture.request.payload")).sequence());
            refused(FailureCode.INVALID_WIRE, () -> codec.receive(value("capture.response.inbound")));
            // Exchange replacement policy is the future session owner's responsibility, not proof of retry safety.
        }
    }

    @Test public void peerLeftRequiresExactHostAndExchangeAndClearsOnlyThatState() throws Exception {
        try (ViewerAvailabilityEnvelopeCodec codec = codec()) {
            ready(codec);
            refused(FailureCode.INVALID_WIRE, () -> codec.receive(ascii("{\"exchangeID\":\"" + exchange + "\",\"role\":\"viewer\",\"type\":\"availability-peer-left\"}")));
            assertEquals(exchange, codec.currentExchangeID());
            assertEquals(Kind.PEER_LEFT, codec.receive(ascii("{\"exchangeID\":\"" + exchange + "\",\"role\":\"host\",\"type\":\"availability-peer-left\"}")).kind());
            assertNull(codec.currentExchangeID()); refused(FailureCode.NOT_READY, () -> codec.sealRequest(value("capture.request.payload")));
            refused(FailureCode.INVALID_WIRE, () -> codec.receive(ascii("{\"exchangeID\":\"" + exchange + "\",\"role\":\"host\",\"type\":\"availability-peer-left\"}")));
        }
    }

    @Test public void waitingAndSafeErrorsCarryNoResetOrPairingAuthority() throws Exception {
        try (ViewerAvailabilityEnvelopeCodec codec = codec()) {
            ready(codec); codec.sealRequest(value("capture.request.payload"));
            assertEquals(Kind.WAITING, codec.receive(ascii("{\"type\":\"availability-waiting\"}")).kind());
            assertEquals(exchange, codec.currentExchangeID()); assertEquals(1, codec.sealRequest(value("capture.request.payload")).sequence());
            String[] names = {"availability_unavailable", "peer_unavailable", "rate_limited", "role_already_claimed", "unknown_code"};
            ServerError[] errors = {ServerError.PEER_UNAVAILABLE, ServerError.PEER_UNAVAILABLE, ServerError.RATE_LIMITED, ServerError.ROLE_CONFLICT, ServerError.REQUEST_REJECTED};
            for (int i = 0; i < names.length; i++) {
                ViewerAvailabilityEnvelopeCodec.Event event = codec.receive(ascii("{\"error\":\"" + names[i] + "\",\"type\":\"error\"}"));
                assertEquals(Kind.SERVER_ERROR, event.kind()); assertEquals(errors[i], event.serverError()); assertNull(event.response());
            }
            for (String bad : new String[] {"", "with-hyphen", "a/b", "a b", "\\n", "a".repeat(65)})
                refused(FailureCode.INVALID_WIRE, () -> codec.receive(ascii("{\"error\":\"" + bad + "\",\"type\":\"error\"}")));
        }
    }

    @Test public void strictSchemasNumbersBase64RolesAndBoundsRefuseWithoutConsumingResponse() throws Exception {
        try (ViewerAvailabilityEnvelopeCodec codec = codec()) {
            ready(codec); String original = text(value("capture.response.inbound"));
            for (String bad : new String[] {
                original.replace("\"host\"", "\"viewer\""), original.replace("\"seq\":0", "\"seq\":0.0"),
                original.replace("\"seq\":0", "\"seq\":\"0\""), original.replace("\"seq\":0", "\"seq\":true"),
                original.replace("\"seq\":0", "\"seq\":-1"), original.replace("\"seq\":0", "\"seq\":00"),
                original.replace("\"seq\":0", "\"seq\":2147483648"), original.replace("\"seq\":0", "\"seq\":0,\"seq\":0"),
                original.substring(0, original.length() - 1) + ",\"extra\":0}", original + "x",
                original.replace("\"type\":\"availability-signal\"", "\"type\":\"signal\"")
            }) refused(FailureCode.INVALID_WIRE, () -> codec.receive(ascii(bad)));
            for (String bad : new String[] {"{\"type\":\"waiting\"}", "{\"type\":\"availability-probe-ack\",\"nonce\":\"x\"}",
                    "{\"type\":\"availability-waiting\",\"extra\":0}", "{\"role\":\"viewer\",\"exchangeID\":\"" + exchange + "=\",\"type\":\"availability-ready\"}"})
                refused(FailureCode.INVALID_WIRE, () -> codec.receive(ascii(bad)));
            refused(FailureCode.INVALID_WIRE, () -> codec.receive(new byte[90_001]));
            byte[] nonAscii = value("capture.response.inbound").clone(); nonAscii[0] = (byte) 0xff;
            refused(FailureCode.INVALID_WIRE, () -> codec.receive(nonAscii));
            Map<String, Object> inner = inner(value("capture.response.outbound"));
            String innerText = text(Base64.getUrlDecoder().decode((String) outer(value("capture.response.outbound")).get("envelope")));
            for (String badInner : new String[] {innerText.replace("\"version\":1", "\"version\":2"),
                    innerText.replace("hostToViewer", "viewerToHost"), innerText.replace(text(value("derived.channel")), "0".repeat(52)),
                    innerText.replace("\"sequence\":0", "\"sequence\":1"), innerText.replace(exchange, "A".repeat(22)),
                    innerText.substring(0, innerText.length() - 1) + ",\"extra\":0}",
                    innerText.replace((String) inner.get("ciphertext"), ((String) inner.get("ciphertext")) + "=")})
                refused(FailureCode.INVALID_WIRE, () -> codec.receive(inboundEnvelope(ascii(badInner), 0)));
            assertEquals(Kind.SIGNAL_RESPONSE, codec.receive(value("capture.response.inbound")).kind());
        }
    }

    @Test public void failedAeadOrPayloadNeverConsumesReplayWindow() throws Exception {
        try (ViewerAvailabilityEnvelopeCodec codec = codec()) {
            ready(codec); byte[] combined = capturedCombined("response"); combined[combined.length - 1] ^= 1;
            refused(FailureCode.AUTHENTICATION_FAILED, () -> codec.receive(hostWire(0, value("capture.response.payload"), combined)));
            refused(FailureCode.INVALID_PAYLOAD, () -> codec.receive(hostWire(0, value("capture.request.payload"), null)));
            refused(FailureCode.INVALID_PAYLOAD, () -> codec.receive(hostWire(0, ascii("{\"kind\":\"pairingCommit\"}"), null)));
            assertEquals(Kind.SIGNAL_RESPONSE, codec.receive(value("capture.response.inbound")).kind());
            refused(FailureCode.REPLAYED_SEQUENCE, () -> codec.receive(value("capture.response.inbound")));
        }
    }

    @Test public void sixtyFourReplayWindowAcceptsOutOfOrderWithinItAndRefusesOldOrDuplicate() throws Exception {
        try (ViewerAvailabilityEnvelopeCodec codec = codec()) {
            ready(codec); assertEquals(Kind.SIGNAL_RESPONSE, codec.receive(hostWire(63, value("capture.response.payload"), null)).kind());
            assertEquals(Kind.SIGNAL_RESPONSE, codec.receive(hostWire(0, value("capture.response.payload"), null)).kind());
            refused(FailureCode.REPLAYED_SEQUENCE, () -> codec.receive(hostWire(0, value("capture.response.payload"), null)));
            assertEquals(Kind.SIGNAL_RESPONSE, codec.receive(hostWire(64, value("capture.response.payload"), null)).kind());
            refused(FailureCode.SEQUENCE_OUTSIDE_WINDOW, () -> codec.receive(hostWire(0, value("capture.response.payload"), null)));
            assertEquals(Kind.SIGNAL_RESPONSE, codec.receive(hostWire(1, value("capture.response.payload"), null)).kind());
        }
    }

    @Test public void lastSequenceSealsOnceThenCannotWrapOrReclaimIt() throws Exception {
        try (ViewerAvailabilityLocator locator = active.availabilityLocator();
             ViewerAvailabilityEnvelopeCodec codec = locator.codecForFixture(() -> repeat(0x44, 12), ViewerAvailabilityEnvelopeCodec.MAXIMUM_SEQUENCE)) {
            ready(codec); assertEquals(2_147_483_647L, codec.sealRequest(value("capture.request.payload")).sequence());
            ready(codec); refused(FailureCode.SEQUENCE_EXHAUSTED, () -> codec.sealRequest(value("capture.request.payload")));
        }
    }

    @Test public void nonceReentryCannotResetOrSealAfterCloseAndFailureDoesNotInventSend() throws Exception {
        ViewerAvailabilityEnvelopeCodec[] reference = {null};
        try (ViewerAvailabilityLocator locator = active.availabilityLocator()) {
            reference[0] = locator.codecForFixture(() -> {
                try { reference[0].sealRequest(value("capture.request.payload")); fail("recursive seal admitted"); }
                catch (EnvelopeFailure expected) { assertEquals(FailureCode.REENTRANT, expected.code()); }
                return repeat(0x55, 12);
            }, 0);
            try (ViewerAvailabilityEnvelopeCodec codec = reference[0]) { ready(codec); assertEquals(0, codec.sealRequest(value("capture.request.payload")).sequence()); }
            reference[0] = locator.codecForFixture(() -> { reference[0].close(); return repeat(0x55, 12); }, 0);
            try (ViewerAvailabilityEnvelopeCodec codec = reference[0]) {
                ready(codec); refused(FailureCode.CLOSED, () -> codec.sealRequest(value("capture.request.payload"))); assertNull(codec.currentExchangeID());
            }
        }
    }

    @Test public void payloadRolePhaseAndReadyAreRequiredButNotPersistenceClaims() throws Exception {
        try (ViewerAvailabilityEnvelopeCodec codec = codec()) {
            refused(FailureCode.NOT_READY, () -> codec.sealRequest(value("capture.request.payload"))); ready(codec);
            for (String key : new String[] {"hello.viewer.payload", "commit.acknowledgement.payload", "commit.completion.payload"})
                refused(FailureCode.INVALID_PAYLOAD, () -> codec.sealActivation(pairing.get(key)));
            refused(FailureCode.INVALID_PAYLOAD, () -> codec.sealRequest(value("capture.response.payload")));
            refused(FailureCode.INVALID_PAYLOAD, () -> codec.sealActivation(new byte[8193]));
            assertEquals(0, codec.sealActivation(pairing.get("commit.activationAcknowledgement.payload")).sequence());
        }
        try { pending.availabilityLocator(); fail("pending locator admitted"); }
        catch (ViewerPairingAuthenticator.AuthFailure expected) { assertEquals(ViewerPairingAuthenticator.FailureCode.INVALID_RECONNECT, expected.code()); }
    }

    @Test public void closedStateCopiesAndRedactionExposeNoHostRegistrationOrRawRoot() throws Exception {
        ViewerAvailabilityLocator locator = active.availabilityLocator(); ViewerAvailabilityEnvelopeCodec codec = locator.createCodec();
        ready(codec); ViewerAvailabilityEnvelopeCodec.Outbound outbound = codec.sealRequest(value("capture.request.payload"));
        byte[] before = outbound.copyWireBytes(), changed = outbound.copyWireBytes(); changed[0] = 0;
        assertArrayEquals(before, outbound.copyWireBytes());
        for (Field field : ViewerAvailabilityLocator.class.getDeclaredFields())
            assertFalse(field.getName().equals("root") || field.getName().toLowerCase().contains("host"));
        assertEquals("<redacted Beluga viewer availability headers>", locator.copyJoinHeaders().toString());
        assertEquals("<redacted Beluga viewer availability locator>", locator.toString());
        assertEquals("<redacted Beluga viewer availability codec>", codec.toString());
        assertEquals("<redacted Beluga availability outbound>", outbound.toString());
        codec.close(); codec.close(); locator.close(); locator.close(); assertNull(codec.currentExchangeID());
        refused(FailureCode.CLOSED, codec::copyJoinHeaders); refused(FailureCode.CLOSED, locator::copyJoinHeaders);
        refused(FailureCode.CLOSED, locator::createCodec); refused(FailureCode.CLOSED, () -> codec.receive(readyWire(exchange)));
    }

    @Test public void bootstrapStillRejectsSixthFieldAfterSharedParserExtraction() throws Exception {
        // Existing public sequence fixture, not a generated or live invitation.
        PairingInvitation invitation = PairingInvitation.parseManual("04002-0G30G-2GC1R-81450-P30D1-R7H04-8J2EZ-G8AG3");
        try (PairingBootstrapEnvelopeCodec bootstrap = PairingBootstrapEnvelopeCodec.create(invitation, Role.VIEWER)) {
            try { bootstrap.open(ascii("{\"type\":\"signal\",\"from\":\"host\",\"seq\":0,\"envelope\":\"x\",\"extra\":0,\"sixth\":0}")); fail("sixth bootstrap field admitted"); }
            catch (PairingBootstrapEnvelopeCodec.EnvelopeFailure expected) { assertEquals(PairingBootstrapEnvelopeCodec.FailureCode.INVALID_WIRE, expected.code()); }
        }
    }

    private ViewerAvailabilityEnvelopeCodec codec() throws Exception {
        try (ViewerAvailabilityLocator locator = active.availabilityLocator()) { return locator.createCodec(); }
    }
    private void ready(ViewerAvailabilityEnvelopeCodec codec) throws Exception { assertEquals(Kind.READY, codec.receive(readyWire(exchange)).kind()); }
    private static byte[] readyWire(String exchange) { return ascii("{\"exchangeID\":\"" + exchange + "\",\"role\":\"viewer\",\"type\":\"availability-ready\"}"); }
    private byte[] hostWire(long sequence, byte[] payload, byte[] suppliedCombined) throws Exception {
        byte[] combined = suppliedCombined == null ? BouncyCastlePairingCrypto.sealCombined(value("derived.host-key"),
                ByteBuffer.allocate(12).putInt(0x66778899).putLong(sequence).array(), payload, aad(sequence, 1)) : suppliedCombined;
        byte[] inner = ascii("{\"channelID\":\"" + text(value("derived.channel")) + "\",\"ciphertext\":\"" + Base64.getEncoder().encodeToString(combined)
                + "\",\"direction\":\"hostToViewer\",\"exchangeID\":\"" + exchange + "\",\"sequence\":" + sequence + ",\"version\":1}");
        return inboundEnvelope(inner, sequence);
    }
    private byte[] inboundEnvelope(byte[] inner, long sequence) {
        return ascii("{\"envelope\":\"" + Base64.getUrlEncoder().withoutPadding().encodeToString(inner) + "\",\"exchangeID\":\"" + exchange
                + "\",\"from\":\"host\",\"seq\":" + sequence + ",\"type\":\"availability-signal\"}");
    }
    private byte[] aad(long sequence, int direction) {
        return ReconnectMessages.domain("AudioStreamer.Availability.Envelope.AAD.v1", new byte[] {1}, value("derived.channel"),
                value("exchange.raw"), new byte[] {(byte) direction}, ByteBuffer.allocate(8).putLong(sequence).array());
    }
    private byte[] capturedNonce(String name) throws Exception { return Arrays.copyOf(capturedCombined(name), 12); }
    private byte[] capturedCombined(String name) throws Exception { return Base64.getDecoder().decode((String) inner(value("capture." + name + ".outbound")).get("ciphertext")); }
    private static Map<String, Object> outer(byte[] wire) throws Exception { return PairingBootstrapEnvelopeCodec.parseAvailabilityWire(wire, 90_000); }
    private static Map<String, Object> inner(byte[] wire) throws Exception {
        return PairingBootstrapEnvelopeCodec.parseAvailabilityWire(Base64.getUrlDecoder().decode((String) outer(wire).get("envelope")), 65_536);
    }
    private byte[] value(String key) { byte[] result = capture.get(key); if (result == null) throw new AssertionError("Public fixture row required"); return result.clone(); }
    private static Map<String, byte[]> load(String resource, String sha, int count) throws Exception {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        try (InputStream input = ViewerAvailabilityEnvelopeCodecTest.class.getResourceAsStream(resource)) {
            if (input == null) throw new AssertionError("Public fixture resource required");
            byte[] chunk = new byte[4096]; int read;
            while ((read = input.read(chunk)) != -1) { assertTrue(bytes.size() + read <= 128 * 1024); bytes.write(chunk, 0, read); }
        }
        byte[] file = bytes.toByteArray(); assertArrayEquals(hex(sha), MessageDigest.getInstance("SHA-256").digest(file));
        for (byte b : file) assertTrue(b >= 0);
        Map<String, byte[]> result = new TreeMap<>(); String previous = "";
        for (String line : text(file).split("\n")) {
            if (line.startsWith("#")) continue;
            String[] fields = line.split("\t", -1); assertEquals(2, fields.length);
            assertTrue(fields[0].matches("[A-Za-z0-9.-]{1,100}") && previous.compareTo(fields[0]) < 0);
            byte[] decoded = Base64.getDecoder().decode(fields[1]); assertTrue(decoded.length > 0 && decoded.length <= 90_000);
            assertEquals(fields[1], Base64.getEncoder().encodeToString(decoded)); assertNull(result.put(fields[0], decoded)); previous = fields[0];
        }
        assertEquals(count, result.size()); return result;
    }
    private interface Attempt { void run() throws Exception; }
    private static void refused(FailureCode code, Attempt attempt) throws Exception {
        try { attempt.run(); fail("Availability unexpectedly admitted"); }
        catch (EnvelopeFailure expected) { assertEquals(code, expected.code()); assertEquals("Beluga availability envelope refused: " + code.name(), expected.getMessage()); assertNull(expected.getCause()); }
    }
    private static byte[] hex(String value) { byte[] result = new byte[value.length() / 2]; for (int i = 0; i < result.length; i++) result[i] = (byte) Integer.parseInt(value.substring(i * 2, i * 2 + 2), 16); return result; }
    private static byte[] repeat(int value, int size) { byte[] result = new byte[size]; Arrays.fill(result, (byte) value); return result; }
    private static String text(byte[] value) { return new String(value, StandardCharsets.US_ASCII); }
    private static byte[] ascii(String value) { return value.getBytes(StandardCharsets.US_ASCII); }
}
