package com.elamin.beluga.protocol;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.Base64;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import org.junit.Before;
import org.junit.Test;
import com.elamin.beluga.protocol.PairingBootstrapBrokerEventParser.ErrorEvent;
import com.elamin.beluga.protocol.PairingBootstrapBrokerEventParser.Event;
import com.elamin.beluga.protocol.PairingBootstrapBrokerEventParser.Kind;
import com.elamin.beluga.protocol.PairingBootstrapBrokerEventParser.ParseFailure;
import com.elamin.beluga.protocol.PairingBootstrapBrokerEventParser.PeerLeft;
import com.elamin.beluga.protocol.PairingBootstrapBrokerEventParser.Ready;
import com.elamin.beluga.protocol.PairingBootstrapBrokerEventParser.ServerError;
import com.elamin.beluga.protocol.PairingBootstrapBrokerEventParser.SignalWire;
import com.elamin.beluga.protocol.PairingBootstrapBrokerEventParser.Waiting;
import com.elamin.beluga.protocol.PairingBootstrapEnvelopeCodec.EnvelopeFailure;
import com.elamin.beluga.protocol.PairingBootstrapEnvelopeCodec.FailureCode;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Role;

/** Host JUnit4 only: independent PUBLIC Swift captures and synthetic broker control frames. */
public final class PairingBootstrapBrokerEventParserTest {
    private static final String FIXTURE_SHA = "28690a8285418f4cc6373233302a63e5a3217c063d32032d73dd1bb2ff6f550f";
    private Map<String, byte[]> fixture;
    private PairingInvitation invitation;

    @Before public void loadExactActualSwiftCapture() throws Exception {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        try (InputStream input = getClass().getResourceAsStream("/public-swift-bootstrap-envelopes-v1.tsv")) {
            if (input == null) throw new AssertionError("Exact public capture resource required");
            byte[] chunk = new byte[4096]; int count;
            while ((count = input.read(chunk)) != -1) {
                assertTrue(output.size() + count <= 128 * 1024); output.write(chunk, 0, count);
            }
        }
        byte[] file = output.toByteArray();
        assertArrayEquals(hex(FIXTURE_SHA), MessageDigest.getInstance("SHA-256").digest(file));
        for (byte b : file) assertTrue(b >= 0);
        String[] lines = text(file).split("\n", -1);
        assertEquals(32, lines.length);
        assertEquals("# PUBLIC synthetic bootstrap-envelope captures; NEVER production credentials", lines[0]);
        assertEquals("# Actual Swift PairingBootstrapSignalingClient send and receive; random AEAD nonces retained", lines[1]);
        assertEquals("", lines[31]);
        Set<String> expected = new HashSet<>(Arrays.asList("input.invitation-secret", "derived.channel", "derived.admission", "derived.host-key", "derived.viewer-key"));
        for (String role : new String[] {"host", "viewer"}) for (int index = 0; index < 4; index++)
            for (String field : new String[] {"payload", "outbound", "inbound"}) expected.add("capture." + role + "." + index + "." + field);
        fixture = new TreeMap<>(); String previous = "";
        for (int index = 2; index < 31; index++) {
            String[] row = lines[index].split("\t", -1); assertEquals(2, row.length);
            assertTrue(row[0].matches("[A-Za-z0-9.-]{1,100}") && previous.compareTo(row[0]) < 0);
            byte[] decoded = Base64.getDecoder().decode(row[1]);
            assertTrue(decoded.length > 0 && decoded.length <= 8192);
            assertEquals(row[1], Base64.getEncoder().encodeToString(decoded));
            assertEquals(null, fixture.put(row[0], decoded)); previous = row[0];
        }
        assertEquals(expected, fixture.keySet()); invitation = invitation(value("input.invitation-secret"));
    }

    @Test public void waitingAndReadyAreOnlyTypedBrokerObservations() throws Exception {
        Waiting waiting = (Waiting) parse(waiting("1970-01-01T00:00:00.000Z"), Role.VIEWER);
        assertEquals(Kind.WAITING, waiting.kind()); assertEquals(0, waiting.claimedInvitationExpiresAtEpochMillis());
        for (Role role : Role.values()) {
            Ready ready = (Ready) parse(ready(wireRole(role), "2000-01-01T00:00:00.123Z", "[]"), role);
            assertEquals(Kind.READY, ready.kind()); assertEquals(role, ready.localRole());
            assertEquals(946684800123L, ready.claimedInvitationExpiresAtEpochMillis());
            refuses(ready(wireRole(opposite(role)), "2000-01-01T00:00:00.123Z", "[]"), role);
        }
        // An already expired deadline is structurally valid; no wall clock or pairing authority.
        assertEquals(-1, ((Waiting) parse(waiting("1969-12-31T23:59:59.9999Z"), Role.VIEWER)).claimedInvitationExpiresAtEpochMillis());
    }

    @Test public void fractionalUtcAndOffsetDatesAreValidatedWithoutNormalization() throws Exception {
        for (String fraction : new String[] {"1", "10", "100", "1000", "100000000"}) assertDeadline("1970-01-01T00:00:00." + fraction + "Z", 100);
        assertDeadline("1970-01-01T00:00:00.12Z", 120);
        assertDeadline("1970-01-01T00:00:00.123456789Z", 123);
        assertDeadline("1970-01-01T01:30:00.123+01:30", 123);
        assertDeadline("1969-12-31T22:30:00.9-01:30", 900);
        assertDeadline("1970-01-01T18:00:00.0+18:00", 0);
        assertDeadline("1970-01-01T00:00:00.0-18:00", 64800000);
        assertDeadline("2000-02-29T00:00:00.0Z", 951782400000L);
        assertTrue(((Waiting) parse(waiting("0001-01-01T00:00:00.0Z"), Role.VIEWER)).claimedInvitationExpiresAtEpochMillis() < 0);
        assertTrue(((Waiting) parse(waiting("9999-12-31T23:59:59.999Z"), Role.VIEWER)).claimedInvitationExpiresAtEpochMillis() > 0);
        // Proleptic Gregorian, not GregorianCalendar's default 1582 cutover gap.
        assertTrue(parse(waiting("1582-10-10T00:00:00.0Z"), Role.VIEWER) instanceof Waiting);
    }

    @Test public void invalidAndIntentionallyUnsupportedDateFormsAreRefused() throws Exception {
        for (String date : new String[] {"0000-01-01T00:00:00.0Z", "10000-01-01T00:00:00.0Z", "1900-02-29T00:00:00.0Z",
                "2001-02-29T00:00:00.0Z", "2000-02-30T00:00:00.0Z", "2000-04-31T00:00:00.0Z", "2000-00-01T00:00:00.0Z",
                "2000-13-01T00:00:00.0Z", "2000-01-00T00:00:00.0Z", "2000-01-01T24:00:00.0Z", "2000-01-01T00:60:00.0Z",
                "2000-01-01T00:00:60.0Z", "2000-01-01t00:00:00.0Z", "2000-01-01T00:00:00.0z", "2000-01-01T00:00:00Z",
                "2000-01-01T00:00:00.Z", "2000-01-01T00:00:00.0000000000Z", "2000-01-01T00:00:00.0", "2000-01-01T00:00:00.0+24:00",
                "2000-01-01T00:00:00.0+00:60", "2000-01-01T00:00:00.0+0130", "2000-01-01T00:00:00.0+01:3", "2000-01-01T00:00:00.0Zx",
                "2000-01-01T00:00:00.0+01:30x", "2000-01-01T00:00:00.0Z ",
                "2000-01-01T00:00:00.0+18:01", "2000-01-01T00:00:00.0-18:01",
                "2000-01-01T00:00:00.0+19:00", "2000-01-01T00:00:00.0-19:00",
                "2000-01-01T00:00:00.0+23:59", "2000-01-01T00:00:00.0-23:59",
                "2000-01-01T00:00:00.0Z" + repeat('0', 64)})
            refuses(waiting(date), Role.VIEWER);
        refuses(waiting("2000-0x-01T00:00:00.0Z"), Role.VIEWER);
    }

    @Test public void pairingReadyRefusesNonemptyIceAndNeverExportsTurnCredentials() throws Exception {
        for (String ice : new String[] {"null", "{}", "true", "\"[]\"", "[[]]", "[1]", "[{\"urls\":[\"stun:example.test\"]}]",
                "[{\"urls\":[\"turn:example.test\"],\"username\":\"private\",\"credential\":\"private\"}]"})
            refuses(ready("viewer", "2000-01-01T00:00:00.0Z", ice), Role.VIEWER);
        assertTrue(parse(ready("viewer", "2000-01-01T00:00:00.0Z", "[ \r\n\t]"), Role.VIEWER) instanceof Ready);
    }

    @Test public void peerLeftRequiresOppositeRoleAndCarriesNoResetOrReplacementAuthority() throws Exception {
        for (Role role : Role.values()) {
            PeerLeft left = (PeerLeft) parse("{\"type\":\"peer-left\",\"role\":\"" + wireRole(opposite(role)) + "\"}", role);
            assertEquals(Kind.PEER_LEFT, left.kind()); assertEquals(opposite(role), left.departedRole());
            refuses("{\"type\":\"peer-left\",\"role\":\"" + wireRole(role) + "\"}", role);
        }
        refuses("{\"type\":\"peer-left\",\"role\":\"other\"}", Role.VIEWER);
        try (PairingBootstrapEnvelopeCodec viewer = PairingBootstrapEnvelopeCodec.create(invitation, Role.VIEWER)) {
            SignalWire first = (SignalWire) PairingBootstrapBrokerEventParser.parse(value("capture.host.0.inbound"), Role.VIEWER);
            assertEquals(0, viewer.open(first.copyUntrustedWireBytes()).sequence());
            parse("{\"type\":\"peer-left\",\"role\":\"host\"}", Role.VIEWER);
            envelopeRefuses(FailureCode.REPLAYED_SEQUENCE, () -> viewer.open(first.copyUntrustedWireBytes()));
        }
    }

    @Test public void serverErrorsAreClosedAndNeverRetainFreeformDiagnosticText() throws Exception {
        String[] wire = {"peer_unavailable", "rate_limited", "invitation_unavailable", "invitation_expired", "role_already_claimed", "request_rejected"};
        ServerError[] expected = {ServerError.PEER_UNAVAILABLE, ServerError.RATE_LIMITED, ServerError.INVITATION_UNAVAILABLE,
                ServerError.INVITATION_EXPIRED, ServerError.ROLE_CONFLICT, ServerError.REQUEST_REJECTED};
        for (int index = 0; index < wire.length; index++) {
            ErrorEvent error = (ErrorEvent) parse("{\"type\":\"error\",\"error\":\"" + wire[index] + "\"}", Role.VIEWER);
            assertEquals(Kind.SERVER_ERROR, error.kind()); assertEquals(expected[index], error.error());
        }
        String unknown = "synthetic-untrusted-private-error";
        ErrorEvent error = (ErrorEvent) parse("{\"type\":\"error\",\"error\":\"" + unknown + "\"}", Role.VIEWER);
        assertEquals(ServerError.REQUEST_REJECTED, error.error()); assertFalse(error.toString().contains(unknown));
        assertEquals(ServerError.REQUEST_REJECTED, ((ErrorEvent) parse("{\"type\":\"error\",\"error\":\"" + repeat('x', 128) + "\"}", Role.VIEWER)).error());
        refuses("{\"type\":\"error\",\"error\":\"\"}", Role.VIEWER);
        refuses("{\"type\":\"error\",\"error\":\"" + repeat('x', 129) + "\"}", Role.VIEWER);
    }

    @Test public void allEightActualSwiftForwardedEnvelopesRouteThenAuthenticateSeparately() throws Exception {
        for (Role sender : Role.values()) try (PairingBootstrapEnvelopeCodec receiver = PairingBootstrapEnvelopeCodec.create(invitation, opposite(sender))) {
            for (int index = 0; index < 4; index++) {
                String prefix = "capture." + wireRole(sender) + "." + index + ".";
                byte[] input = value(prefix + "inbound"), original = input.clone();
                SignalWire signal = (SignalWire) PairingBootstrapBrokerEventParser.parse(input, opposite(sender));
                assertEquals(Kind.SIGNAL_WIRE, signal.kind()); assertEquals(sender, signal.claimedSenderRole());
                assertEquals(index, signal.claimedSequence()); assertArrayEquals(original, signal.copyUntrustedWireBytes());
                input[0] = 0; byte[] exported = signal.copyUntrustedWireBytes(); exported[0] = 0;
                assertArrayEquals(original, signal.copyUntrustedWireBytes());
                PairingBootstrapEnvelopeCodec.Signal authenticated = receiver.open(signal.copyUntrustedWireBytes());
                assertArrayEquals(value(prefix + "payload"), PairingBootstrapEnvelopeCodec.canonicalPayload(authenticated.structurallyAdmittedPayload()));
                assertFalse(signal.toString().contains(text(value("derived.channel"))));
                assertFalse(signal.toString().contains(text(value("derived.admission"))));
                assertTrue(signal.toString().contains("redacted"));
            }
        }
    }

    @Test public void structuralSignalAdmissionNeverMeansInnerCiphertextOrPayloadAuthentication() throws Exception {
        SignalWire signal = (SignalWire) parse(signal("host", "0", "AA"), Role.VIEWER);
        assertEquals(0, signal.claimedSequence());
        try (PairingBootstrapEnvelopeCodec receiver = PairingBootstrapEnvelopeCodec.create(invitation, Role.VIEWER)) {
            envelopeRefuses(FailureCode.INVALID_WIRE, () -> receiver.open(signal.copyUntrustedWireBytes()));
            SignalWire real = (SignalWire) PairingBootstrapBrokerEventParser.parse(value("capture.host.0.inbound"), Role.VIEWER);
            assertEquals(0, receiver.open(real.copyUntrustedWireBytes()).sequence());
        }
        // Parser routes bounded structural media-looking ciphertext but no media field/schema itself.
        refuses("{\"type\":\"offer\",\"sdp\":\"v=0\"}", Role.VIEWER);
        refuses("{\"type\":\"candidate\",\"candidate\":\"private\"}", Role.VIEWER);
        refuses("{\"type\":\"expired\"}", Role.VIEWER); // Actual expiry is error:invitation_expired.
    }

    @Test public void signalSequenceAndBase64urlBoundsAreExact() throws Exception {
        assertEquals(2147483647L, ((SignalWire) parse(signal("host", "2147483647", "AA"), Role.VIEWER)).claimedSequence());
        for (String sequence : new String[] {"2147483648", "18446744073709551615", "-1", "+0", "00", "0.0", "0e0", "true", "null", "\"0\""})
            refuses(signal("host", sequence, "AA"), Role.VIEWER);
        for (String envelope : new String[] {"", "A", "AB", "AAB", "AA=", "AA==", "+A", "/A", "A A", "AA ", "AA-"})
            refuses(signal("host", "0", envelope), Role.VIEWER);
        for (String envelope : new String[] {"AA", "AAA", "AAAA", "_w", "__8", "____"}) assertTrue(parse(signal("host", "0", envelope), Role.VIEWER) instanceof SignalWire);
        String maximum = Base64.getUrlEncoder().withoutPadding().encodeToString(new byte[PairingBootstrapEnvelopeCodec.MAXIMUM_ENVELOPE_BYTES]);
        assertTrue(parse(signal("host", "0", maximum), Role.VIEWER) instanceof SignalWire);
        String oversized = Base64.getUrlEncoder().withoutPadding().encodeToString(new byte[PairingBootstrapEnvelopeCodec.MAXIMUM_ENVELOPE_BYTES + 1]);
        refuses(signal("host", "0", oversized), Role.VIEWER);
        refuses(signal("viewer", "0", "AA"), Role.VIEWER); refuses(signal("other", "0", "AA"), Role.VIEWER);
    }

    @Test public void exactSchemasRefuseUnknownMissingDuplicateAndWrongTypes() throws Exception {
        for (String frame : new String[] {
                "{}", "[]", "null", "true", "{\"type\":\"waiting\"}", waiting("2000-01-01T00:00:00.0Z").replace("}", ",\"extra\":0}"),
                "{\"type\":\"waiting\",\"type\":\"waiting\",\"invitationExpiresAt\":\"2000-01-01T00:00:00.0Z\"}",
                "{\"type\":\"waiting\",\"t\\u0079pe\":\"waiting\",\"invitationExpiresAt\":\"2000-01-01T00:00:00.0Z\"}",
                "{\"type\":1,\"invitationExpiresAt\":\"2000-01-01T00:00:00.0Z\"}", "{\"type\":\"waiting\",\"invitationExpiresAt\":0}",
                "{\"type\":\"waiting\",\"invitationExpiresAt\":null}", "{\"type\":\"waiting\",\"invitationExpiresAt\":true}",
                "{\"type\":\"waiting\",\"invitationExpiresAt\":{}}", "{\"type\":\"waiting\",\"invitationExpiresAt\":[]}",
                ready("viewer", "2000-01-01T00:00:00.0Z", "[]").replace("}", ",\"extra\":1}"),
                "{\"type\":\"ready\",\"role\":\"viewer\",\"invitationExpiresAt\":\"2000-01-01T00:00:00.0Z\"}",
                signal("host", "0", "AA").replace("\"seq\":0", "\"seq\":0,\"seq\":0"),
                signal("host", "0", "AA").replace("\"seq\":0", "\"seq\":0,\"s\\u0065q\":0"),
                "{\"type\":\"signal\",\"seq\":0,\"from\":\"host\",\"envelope\":[]}",
                "{\"type\":\"peer-left\",\"role\":[]}", "{\"type\":\"error\",\"error\":[]}", "{\"type\":\"error\",\"error\":0}",
                "{\"type\":\"peer-left\",\"role\":\"host\",\"peerID\":\"private\"}", "{\"type\":\"error\",\"error\":\"rate_limited\",\"details\":\"private\"}",
                waiting("2000-01-01T00:00:00.0Z") + "{}", waiting("2000-01-01T00:00:00.0Z") + "\0"}) refuses(frame, Role.VIEWER);
    }

    @Test public void fieldOrderWhitespaceAndEscapedAsciiKeepOneMeaning() throws Exception {
        Ready ready = (Ready) parse(" \n { \"iceServers\" : [ ], \"invitationExpiresAt\":\"1970-01-01T00:00:00.123Z\", \"r\\u006fle\":\"vi\\u0065wer\", \"type\":\"ready\" } \t", Role.VIEWER);
        assertEquals(123, ready.claimedInvitationExpiresAtEpochMillis()); assertEquals(Role.VIEWER, ready.localRole());
        SignalWire signal = (SignalWire) parse("{\"type\":\"signal\",\"seq\":0,\"from\":\"h\\u006fst\",\"envelope\":\"_w\"}", Role.VIEWER);
        assertEquals(Role.HOST, signal.claimedSenderRole());
    }

    @Test public void byteBoundsMalformedUtf8AndDiagnosticsFailClosed() throws Exception {
        refusesBytes(null, Role.VIEWER); refusesBytes(new byte[0], Role.VIEWER);
        refusesBytes(new byte[PairingBootstrapBrokerEventParser.MAXIMUM_WIRE_BYTES + 1], Role.VIEWER);
        refusesBytes(new byte[] {(byte) 0xc0, (byte) 0x80}, Role.VIEWER);
        refusesBytes("{\"type\":\"error\",\"error\":\"é\"}".getBytes(StandardCharsets.UTF_8), Role.VIEWER);
        refuses("{\"type\":\"error\",\"error\":\"\\u00e9\"}", Role.VIEWER);
        refuses("{\"type\":\"error\",\"error\":\"\\ud800\"}", Role.VIEWER);
        refuses("{\"type\":\"error\",\"error\":\"x\nprivate\"}", Role.VIEWER);
        refuses(waiting("1970-01-01T00:00:00.0Z"), null);
        for (Event event : new Event[] {parse(waiting("2000-01-01T00:00:00.0Z"), Role.VIEWER),
                parse(ready("viewer", "2000-01-01T00:00:00.0Z", "[]"), Role.VIEWER),
                parse("{\"type\":\"peer-left\",\"role\":\"host\"}", Role.VIEWER),
                parse("{\"type\":\"error\",\"error\":\"private\"}", Role.VIEWER)}) {
            assertEquals("<redacted Beluga pairing broker event>", event.toString());
        }
    }

    private static Event parse(String frame, Role role) throws ParseFailure { return PairingBootstrapBrokerEventParser.parse(ascii(frame), role); }
    private static String waiting(String date) { return "{\"type\":\"waiting\",\"invitationExpiresAt\":\"" + date + "\"}"; }
    private static String ready(String role, String date, String ice) { return "{\"type\":\"ready\",\"role\":\"" + role + "\",\"invitationExpiresAt\":\"" + date + "\",\"iceServers\":" + ice + "}"; }
    private static String signal(String from, String seq, String envelope) { return "{\"type\":\"signal\",\"from\":\"" + from + "\",\"seq\":" + seq + ",\"envelope\":\"" + envelope + "\"}"; }
    private static Role opposite(Role role) { return role == Role.HOST ? Role.VIEWER : Role.HOST; }
    private static String wireRole(Role role) { return role == Role.HOST ? "host" : "viewer"; }
    private static void assertDeadline(String date, long expected) throws Exception { assertEquals(expected, ((Waiting) parse(waiting(date), Role.VIEWER)).claimedInvitationExpiresAtEpochMillis()); }
    private byte[] value(String name) { byte[] bytes = fixture.get(name); if (bytes == null) throw new AssertionError("Missing exact public fixture"); return bytes.clone(); }
    private static void refuses(String frame, Role role) throws Exception { refusesBytes(ascii(frame), role); }
    private static void refusesBytes(byte[] frame, Role role) throws Exception {
        try { PairingBootstrapBrokerEventParser.parse(frame, role); fail("Expected bounded event refusal"); }
        catch (ParseFailure error) { assertEquals("Invalid Beluga v1 pairing broker event", error.getMessage()); assertEquals(null, error.getCause()); assertEquals(0, error.getSuppressed().length); }
    }
    private interface Action { Object run() throws Exception; }
    private static void envelopeRefuses(FailureCode expected, Action action) throws Exception {
        try { action.run(); fail("Expected independent envelope refusal"); }
        catch (EnvelopeFailure error) { assertEquals(expected, error.code()); assertEquals(null, error.getCause()); }
    }
    private static PairingInvitation invitation(byte[] secret) throws Exception {
        assertEquals(20, secret.length); byte[] body = new byte[21]; body[0] = 1; System.arraycopy(secret, 0, body, 1, 20);
        MessageDigest digest = MessageDigest.getInstance("SHA-256"); digest.update(ascii("AudioStreamer.RemoteInvitation.Checksum.v1\0"));
        byte[] packet = Arrays.copyOf(body, 25); System.arraycopy(digest.digest(body), 0, packet, 21, 4);
        String alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"; StringBuilder code = new StringBuilder(); int buffer = 0, bits = 0;
        for (byte b : packet) { buffer = (buffer << 8) | (b & 255); bits += 8; while (bits >= 5) { bits -= 5; code.append(alphabet.charAt((buffer >>> bits) & 31)); } }
        return PairingInvitation.parseManual(code.toString());
    }
    private static String repeat(char c, int count) { char[] chars = new char[count]; Arrays.fill(chars, c); return new String(chars); }
    private static String text(byte[] bytes) { return new String(bytes, StandardCharsets.US_ASCII); }
    private static byte[] ascii(String value) { return value.getBytes(StandardCharsets.US_ASCII); }
    private static byte[] hex(String value) { byte[] bytes = new byte[value.length() / 2]; for (int index = 0; index < bytes.length; index++) bytes[index] = (byte) Integer.parseInt(value.substring(index * 2, index * 2 + 2), 16); return bytes; }
}
