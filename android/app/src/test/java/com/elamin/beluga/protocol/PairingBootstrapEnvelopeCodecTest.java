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
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.junit.Before;
import org.junit.Test;
import com.elamin.beluga.protocol.PairingBootstrapEnvelopeCodec.EnvelopeFailure;
import com.elamin.beluga.protocol.PairingBootstrapEnvelopeCodec.FailureCode;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Role;

/** Existing app JUnit4. PUBLIC Swift captures only; no socket, durable send or Android device. */
public final class PairingBootstrapEnvelopeCodecTest {
    private static final String FIXTURE_SHA = "28690a8285418f4cc6373233302a63e5a3217c063d32032d73dd1bb2ff6f550f";
    private static final String RESOURCE = "/public-swift-bootstrap-envelopes-v1.tsv";
    private Map<String, byte[]> fixture;
    private PairingInvitation invitation;

    @Before public void loadIndependentActualSwiftCapture() throws Exception {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        try (InputStream input = getClass().getResourceAsStream(RESOURCE)) {
            if (input == null) throw new AssertionError("Exact public bootstrap resource required");
            byte[] chunk = new byte[4096]; int count;
            while ((count = input.read(chunk)) != -1) {
                assertTrue("Fixture bounded before append", bytes.size() + count <= 128 * 1024);
                bytes.write(chunk, 0, count);
            }
        }
        byte[] file = bytes.toByteArray();
        assertArrayEquals(hex(FIXTURE_SHA), MessageDigest.getInstance("SHA-256").digest(file));
        for (byte b : file) assertTrue(b >= 0);
        String[] lines = text(file).split("\n", -1);
        assertEquals(32, lines.length);
        assertEquals("# PUBLIC synthetic bootstrap-envelope captures; NEVER production credentials", lines[0]);
        assertEquals("# Actual Swift PairingBootstrapSignalingClient send and receive; random AEAD nonces retained", lines[1]);
        assertEquals("", lines[31]);
        fixture = new TreeMap<>(); Set<String> expected = new HashSet<>();
        expected.addAll(Arrays.asList("input.invitation-secret", "derived.channel", "derived.admission", "derived.host-key", "derived.viewer-key"));
        for (String role : new String[] {"host", "viewer"}) for (int index = 0; index < 4; index++)
            for (String field : new String[] {"payload", "outbound", "inbound"}) expected.add("capture." + role + "." + index + "." + field);
        String previous = "";
        for (int index = 2; index < 31; index++) {
            String[] fields = lines[index].split("\t", -1);
            assertEquals(2, fields.length);
            assertTrue(fields[0].matches("[A-Za-z0-9.-]{1,100}") && previous.compareTo(fields[0]) < 0);
            byte[] decoded = Base64.getDecoder().decode(fields[1]);
            assertTrue(decoded.length > 0 && decoded.length <= 8192);
            assertEquals(fields[1], Base64.getEncoder().encodeToString(decoded));
            assertEquals(null, fixture.put(fields[0], decoded)); previous = fields[0];
        }
        assertEquals(expected, fixture.keySet());
        assertArrayEquals(range(0, 20), value("input.invitation-secret"));
        assertEquals(32, value("derived.host-key").length);
        assertEquals(32, value("derived.viewer-key").length);
        assertFalse(Arrays.equals(value("derived.host-key"), value("derived.viewer-key")));
        invitation = invitation(value("input.invitation-secret"));
    }

    @Test public void invitationHkdfAndEightActualSwiftProductionCapturesMatchExactly() throws Exception {
        for (Role role : Role.values()) {
            String sender = role == Role.HOST ? "host" : "viewer";
            final int[] cursor = {0};
            try (PairingBootstrapEnvelopeCodec sending = PairingBootstrapEnvelopeCodec.createForFixture(invitation, role,
                        () -> capturedNonce(sender, cursor[0]++));
                 PairingBootstrapEnvelopeCodec receiving = codec(role == Role.HOST ? Role.VIEWER : Role.HOST)) {
                PairingBootstrapEnvelopeCodec.JoinHeaders join = sending.copyJoinHeaders();
                assertEquals(text(value("derived.channel")), join.channelID());
                assertEquals(text(value("derived.admission")), join.admissionProofForUpgradeHeader());
                assertEquals(sender, join.role());
                for (int index = 0; index < 4; index++) {
                    String prefix = "capture." + sender + "." + index + ".";
                    byte[] payload = value(prefix + "payload");
                    PairingBootstrapEnvelopeCodec.Outbound outbound = sending.seal(payload);
                    assertEquals(index, outbound.sequence());
                    assertArrayEquals(value(prefix + "outbound"), outbound.copyWireBytes());
                    PairingBootstrapEnvelopeCodec.Signal opened = receiving.open(value(prefix + "inbound"));
                    assertEquals(index, opened.sequence());
                    assertArrayEquals(payload, PairingBootstrapEnvelopeCodec.canonicalPayload(opened.structurallyAdmittedPayload()));
                    // Both separately exported Swift keys participate in independent raw AEAD proof.
                    byte[] combined = ciphertext(value(prefix + "outbound"));
                    byte[] key = value("derived." + sender + "-key");
                    assertArrayEquals(payload, BouncyCastlePairingCrypto.openCombined(key, combined, aad(sender, index)));
                }
                assertEquals(4, cursor[0]);
            }
        }
    }

    @Test public void onlyExplicitWireAndHeaderExportsRevealCapabilitiesAndCopiesAreIndependent() throws Exception {
        try (PairingBootstrapEnvelopeCodec host = codec(Role.HOST); PairingBootstrapEnvelopeCodec viewer = codec(Role.VIEWER)) {
            PairingBootstrapEnvelopeCodec.JoinHeaders headers = host.copyJoinHeaders();
            PairingBootstrapEnvelopeCodec.Outbound outbound = host.seal(value("capture.host.0.payload"));
            byte[] original = outbound.copyWireBytes(); byte[] changed = outbound.copyWireBytes(); changed[0] = 0;
            assertArrayEquals(original, outbound.copyWireBytes());
            PairingBootstrapEnvelopeCodec.Signal signal = viewer.open(forward(original, "host"));
            for (Object object : new Object[] {host, headers, outbound, signal, signal.structurallyAdmittedPayload()}) {
                assertTrue(object.toString().contains("redacted"));
                assertFalse(object.toString().contains(headers.channelID()));
                assertFalse(object.toString().contains(headers.admissionProofForUpgradeHeader()));
            }
        }
    }

    @Test public void closeIsIdempotentAndDoesNotPermitCodecOrHeaderReuse() throws Exception {
        PairingBootstrapEnvelopeCodec host = codec(Role.HOST); host.close(); host.close();
        refuses(FailureCode.CLOSED, host::copyJoinHeaders);
        refuses(FailureCode.CLOSED, () -> host.seal(value("capture.host.0.payload")));
        refuses(FailureCode.CLOSED, () -> host.open(value("capture.viewer.0.inbound")));
    }

    @Test public void unknownMissingDuplicateEscapedDuplicateAndWrongTypedOuterFieldsAreRefused() throws Exception {
        String original = text(value("capture.host.0.inbound"));
        List<String> mutants = Arrays.asList(
                original.replace("\"type\":\"signal\"", "\"type\":\"offer\""),
                original.substring(0, original.length() - 1) + ",\"extra\":1}",
                original.replace(",\"seq\":0", ""),
                original.replace("\"seq\":0", "\"seq\":0,\"seq\":0"),
                original.replace("\"seq\":0", "\"seq\":0,\"s\\u0065q\":0"),
                original.replace("\"seq\":0", "\"seq\":null"),
                original.replace("\"seq\":0", "\"seq\":true"),
                original.replace("\"seq\":0", "\"seq\":\"0\""),
                original.replace("\"seq\":0", "\"seq\":0.0"),
                original.replace("\"seq\":0", "\"seq\":0e0"),
                original + "{}", original + "\0");
        for (String mutant : mutants) try (PairingBootstrapEnvelopeCodec viewer = codec(Role.VIEWER)) {
            refuses(FailureCode.INVALID_WIRE, () -> viewer.open(ascii(mutant)));
        }
    }

    @Test public void noncanonicalNumbersAndOuterInnerSequenceMismatchAreRefused() throws Exception {
        String original = text(value("capture.host.0.inbound"));
        for (String spelling : new String[] {"-1", "+0", "00", "2147483648", "18446744073709551615"})
            try (PairingBootstrapEnvelopeCodec viewer = codec(Role.VIEWER)) {
                refuses(FailureCode.INVALID_WIRE, () -> viewer.open(ascii(original.replace("\"seq\":0", "\"seq\":" + spelling))));
            }
        try (PairingBootstrapEnvelopeCodec viewer = codec(Role.VIEWER)) {
            refuses(FailureCode.INVALID_WIRE, () -> viewer.open(ascii(original.replace("\"seq\":0", "\"seq\":1"))));
        }
    }

    @Test public void exactEnvelopeSchemaAndNumberTypesRejectAliasesAndUnknownFields() throws Exception {
        String outer = text(value("capture.host.0.inbound"));
        String envelope = text(envelopeBytes(value("capture.host.0.inbound")));
        for (String mutant : new String[] {
                envelope.substring(0, envelope.length() - 1) + ",\"extra\":0}",
                envelope.replace("\"version\":1", "\"version\":1,\"version\":1"),
                envelope.replace("\"version\":1", "\"version\":1,\"ver\\u0073ion\":1"),
                envelope.replace("\"version\":1", "\"version\":true"),
                envelope.replace("\"sequence\":0", "\"sequence\":\"0\""),
                envelope.replace("\"sequence\":0", "\"sequence\":0.0"),
                envelope + "x" }) try (PairingBootstrapEnvelopeCodec viewer = codec(Role.VIEWER)) {
            refuses(FailureCode.INVALID_WIRE, () -> viewer.open(replaceEnvelope(outer, ascii(mutant))));
        }
    }

    @Test public void wrongFromVersionChannelDirectionAndReflectionAreDistinctRefusals() throws Exception {
        String original = text(value("capture.host.0.inbound"));
        String envelope = text(envelopeBytes(value("capture.host.0.inbound")));
        try (PairingBootstrapEnvelopeCodec viewer = codec(Role.VIEWER); PairingBootstrapEnvelopeCodec host = codec(Role.HOST)) {
            refuses(FailureCode.INVALID_WIRE, () -> viewer.open(ascii(original.replace("\"from\":\"host\"", "\"from\":\"viewer\""))));
            refuses(FailureCode.INVALID_WIRE, () -> host.open(value("capture.host.0.inbound")));
            refuses(FailureCode.UNSUPPORTED_VERSION, () -> viewer.open(replaceEnvelope(original, ascii(envelope.replace("\"version\":1", "\"version\":2")))));
            refuses(FailureCode.WRONG_CHANNEL, () -> viewer.open(replaceEnvelope(original,
                    ascii(envelope.replace(text(value("derived.channel")), repeat('0', 52))))));
            refuses(FailureCode.UNEXPECTED_DIRECTION, () -> viewer.open(replaceEnvelope(original,
                    ascii(envelope.replace("hostToViewer", "viewerToHost")))));
        }
    }

    @Test public void allNonceCiphertextTagAndAadTamperingFailsBeforeReplayAdmission() throws Exception {
        byte[] original = value("capture.host.0.inbound"); byte[] combined = ciphertext(original);
        for (int offset : new int[] {0, 12, combined.length - 1}) try (PairingBootstrapEnvelopeCodec viewer = codec(Role.VIEWER)) {
            byte[] changed = combined.clone(); changed[offset] ^= 1;
            refuses(FailureCode.AUTHENTICATION_FAILED, () -> viewer.open(replaceCiphertext(original, changed)));
            assertEquals(0, viewer.open(original).sequence());
        }
        try (PairingBootstrapEnvelopeCodec viewer = codec(Role.VIEWER)) {
            String envelope = text(envelopeBytes(original)).replace("\"sequence\":0", "\"sequence\":1");
            byte[] changed = replaceEnvelope(text(original).replace("\"seq\":0", "\"seq\":1"), ascii(envelope));
            refuses(FailureCode.AUTHENTICATION_FAILED, () -> viewer.open(changed));
            assertEquals(0, viewer.open(original).sequence());
        }
    }

    @Test public void wrongInvitationAndWrongDirectionalKeyNeverAuthenticate() throws Exception {
        byte[] secret = value("input.invitation-secret").clone(); secret[0] ^= 1;
        try (PairingBootstrapEnvelopeCodec wrong = PairingBootstrapEnvelopeCodec.create(invitation(secret), Role.VIEWER);
             PairingBootstrapEnvelopeCodec viewer = codec(Role.VIEWER)) {
            refuses(FailureCode.WRONG_CHANNEL, () -> wrong.open(value("capture.host.0.inbound")));
            byte[] forged = signal("host", 0, value("capture.host.0.payload"), value("derived.viewer-key"));
            refuses(FailureCode.AUTHENTICATION_FAILED, () -> viewer.open(forged));
        }
    }

    @Test public void mediaMalformedAndWrongSenderPayloadsCannotEnterBootstrapAndDoNotReserveSequences() throws Exception {
        try (PairingBootstrapEnvelopeCodec host = codec(Role.HOST); PairingBootstrapEnvelopeCodec viewer = codec(Role.VIEWER)) {
            refuses(FailureCode.INVALID_PAYLOAD, () -> host.seal(ascii("{\"kind\":\"offer\",\"sdp\":\"v=0\"}")));
            refuses(FailureCode.INVALID_PAYLOAD, () -> host.seal(value("capture.viewer.0.payload")));
            assertEquals(0, host.seal(value("capture.host.0.payload")).sequence());
            byte[] wrongRole = signal("host", 0, value("capture.viewer.0.payload"), value("derived.host-key"));
            refuses(FailureCode.INVALID_PAYLOAD, () -> viewer.open(wrongRole));
            byte[] media = signal("host", 0, ascii("{\"kind\":\"offer\",\"sdp\":\"v=0\"}"), value("derived.host-key"));
            refuses(FailureCode.INVALID_PAYLOAD, () -> viewer.open(media));
            assertEquals(0, viewer.open(value("capture.host.0.inbound")).sequence());
        }
    }

    @Test public void replayWindowAllowsReorderingAndRejectsDuplicatesAndAgedPackets() throws Exception {
        try (PairingBootstrapEnvelopeCodec viewer = codec(Role.VIEWER)) {
            byte[] payload = value("capture.host.0.payload"), key = value("derived.host-key");
            for (long sequence : new long[] {10, 8, 9}) assertEquals(sequence, viewer.open(signal("host", sequence, payload, key)).sequence());
            refuses(FailureCode.REPLAYED_SEQUENCE, () -> viewer.open(signal("host", 8, payload, key)));
            assertEquals(100, viewer.open(signal("host", 100, payload, key)).sequence());
            refuses(FailureCode.SEQUENCE_OUTSIDE_WINDOW, () -> viewer.open(signal("host", 36, payload, key)));
            assertEquals(37, viewer.open(signal("host", 37, payload, key)).sequence());
            refuses(FailureCode.REPLAYED_SEQUENCE, () -> viewer.open(signal("host", 37, payload, key)));
        }
    }

    @Test public void maximumTransportSequenceIsAllowedOnceAndThenExhausted() throws Exception {
        try (PairingBootstrapEnvelopeCodec host = PairingBootstrapEnvelopeCodec.createForFixture(invitation, Role.HOST,
                    () -> range(0, 12), PairingBootstrapEnvelopeCodec.MAXIMUM_SEQUENCE);
             PairingBootstrapEnvelopeCodec viewer = codec(Role.VIEWER)) {
            PairingBootstrapEnvelopeCodec.Outbound last = host.seal(value("capture.host.0.payload"));
            assertEquals(PairingBootstrapEnvelopeCodec.MAXIMUM_SEQUENCE, last.sequence());
            assertEquals(last.sequence(), viewer.open(forward(last.copyWireBytes(), "host")).sequence());
            refuses(FailureCode.SEQUENCE_EXHAUSTED, () -> host.seal(value("capture.host.0.payload")));
        }
    }

    @Test public void base64CanonicalPaddingAlphabetAndTailAreCheckedAtBothLayers() throws Exception {
        String original = text(value("capture.host.0.inbound"));
        String encoded = field(original, "envelope");
        for (String mutant : new String[] {encoded + "=", "+" + encoded.substring(1), "/" + encoded.substring(1),
                encoded + " ", "A", "AB", "AAB"}) try (PairingBootstrapEnvelopeCodec viewer = codec(Role.VIEWER)) {
            refuses(FailureCode.INVALID_WIRE, () -> viewer.open(ascii(original.replace(encoded, mutant))));
        }
        String envelope = text(envelopeBytes(value("capture.host.0.inbound")));
        String ciphertext = field(envelope, "ciphertext");
        for (String mutant : new String[] {"AB==", "AAB=", ciphertext.replace('+', '-').replace('/', '_') + "=", "", "AAAA===="})
            try (PairingBootstrapEnvelopeCodec viewer = codec(Role.VIEWER)) {
                refuses(FailureCode.INVALID_WIRE, () -> viewer.open(replaceEnvelope(original, ascii(envelope.replace(ciphertext, mutant)))));
            }
    }

    @Test public void boundsAndInvalidUtf8RefuseBeforeParsingOrProviderUse() throws Exception {
        try (PairingBootstrapEnvelopeCodec viewer = codec(Role.VIEWER); PairingBootstrapEnvelopeCodec host = codec(Role.HOST)) {
            refuses(FailureCode.INVALID_WIRE, () -> viewer.open(null));
            refuses(FailureCode.INVALID_WIRE, () -> viewer.open(new byte[0]));
            refuses(FailureCode.INVALID_WIRE, () -> viewer.open(new byte[PairingBootstrapEnvelopeCodec.MAXIMUM_WIRE_BYTES + 1]));
            refuses(FailureCode.INVALID_WIRE, () -> viewer.open(new byte[] {(byte) 0xc0, (byte) 0x80}));
            refuses(FailureCode.INVALID_PAYLOAD, () -> host.seal(new byte[PairingPayloadDecoder.MAXIMUM_PLAINTEXT_BYTES + 1]));
            String oversizedEnvelope = repeat('A', ((PairingBootstrapEnvelopeCodec.MAXIMUM_ENVELOPE_BYTES + 2) / 3) * 4 + 1);
            refuses(FailureCode.INVALID_WIRE, () -> viewer.open(ascii("{\"envelope\":\"" + oversizedEnvelope + "\",\"from\":\"host\",\"seq\":0,\"type\":\"signal\"}")));
        }
    }

    @Test public void fieldOrderWhitespaceAndEscapedAsciiHaveUnambiguousCompatibleMeaning() throws Exception {
        String original = text(value("capture.host.0.inbound")); String envelope = field(original, "envelope");
        byte[] reordered = ascii(" \n{\"type\":\"signal\", \"seq\":0,\"from\":\"h\\u006fst\",\"envelope\":\"" + envelope + "\"} \t");
        try (PairingBootstrapEnvelopeCodec viewer = codec(Role.VIEWER)) {
            assertArrayEquals(value("capture.host.0.payload"), PairingBootstrapEnvelopeCodec.canonicalPayload(viewer.open(reordered).structurallyAdmittedPayload()));
        }
    }

    @Test public void entropyFailureAndInlineCloseDoNotProduceWireOrClaimSuccess() throws Exception {
        try (PairingBootstrapEnvelopeCodec host = PairingBootstrapEnvelopeCodec.createForFixture(invitation, Role.HOST, () -> new byte[11])) {
            refuses(FailureCode.PROVIDER_FAILED, () -> host.seal(value("capture.host.0.payload")));
        }
        final PairingBootstrapEnvelopeCodec[] instance = new PairingBootstrapEnvelopeCodec[1];
        instance[0] = PairingBootstrapEnvelopeCodec.createForFixture(invitation, Role.HOST, () -> { instance[0].close(); return new byte[12]; });
        try { refuses(FailureCode.CLOSED, () -> instance[0].seal(value("capture.host.0.payload"))); }
        finally { instance[0].close(); }
    }

    @Test public void productionEntropyAndSerializedReservationsRemainUniqueUnderBoundedConcurrentCalls() throws Exception {
        try (PairingBootstrapEnvelopeCodec host = PairingBootstrapEnvelopeCodec.create(invitation, Role.HOST)) {
            ExecutorService workers = Executors.newFixedThreadPool(4);
            try {
                List<Callable<PairingBootstrapEnvelopeCodec.Outbound>> calls = new ArrayList<>();
                for (int index = 0; index < 16; index++) calls.add(() -> host.seal(value("capture.host.0.payload")));
                List<Future<PairingBootstrapEnvelopeCodec.Outbound>> results = workers.invokeAll(calls, 5, TimeUnit.SECONDS);
                Set<Long> sequences = new HashSet<>(); Set<String> nonces = new HashSet<>();
                for (Future<PairingBootstrapEnvelopeCodec.Outbound> result : results) {
                    assertFalse(result.isCancelled()); PairingBootstrapEnvelopeCodec.Outbound output = result.get(1, TimeUnit.SECONDS);
                    assertTrue(sequences.add(Long.valueOf(output.sequence())));
                    assertTrue(nonces.add(Base64.getEncoder().encodeToString(Arrays.copyOf(ciphertext(output.copyWireBytes()), 12))));
                }
                assertEquals(16, sequences.size()); assertEquals(16, nonces.size());
                for (long sequence = 0; sequence < 16; sequence++) assertTrue(sequences.contains(Long.valueOf(sequence)));
            } finally { workers.shutdownNow(); assertTrue(workers.awaitTermination(5, TimeUnit.SECONDS)); }
        }
    }

    private PairingBootstrapEnvelopeCodec codec(Role role) throws EnvelopeFailure {
        return PairingBootstrapEnvelopeCodec.create(invitation, role);
    }
    private byte[] capturedNonce(String role, int index) {
        return Arrays.copyOf(ciphertext(value("capture." + role + "." + index + ".outbound")), 12);
    }
    private byte[] value(String name) { byte[] bytes = fixture.get(name); if (bytes == null) throw new AssertionError("Missing public vector"); return bytes.clone(); }
    private byte[] aad(String role, long sequence) {
        byte[] domain = ascii("AudioStreamer.Signaling.Envelope.AAD.v1\0"), channel = value("derived.channel");
        return ByteBuffer.allocate(domain.length + 1 + channel.length + 2 + 8).put(domain).put((byte) 1)
                .put(channel).put((byte) 0).put((byte) (role.equals("host") ? 1 : 2)).putLong(sequence).array();
    }
    private byte[] signal(String role, long sequence, byte[] plaintext, byte[] key) throws Exception {
        // Synthetic fixture-only nonce; sequence-derived bytes here NEVER define product entropy.
        byte[] nonce = ByteBuffer.allocate(12).putInt(role.equals("host") ? 1 : 2).putLong(sequence).array();
        byte[] combined = BouncyCastlePairingCrypto.sealCombined(key, nonce, plaintext, aad(role, sequence));
        String envelope = "{\"channelID\":\"" + text(value("derived.channel")) + "\",\"ciphertext\":\"" + Base64.getEncoder().encodeToString(combined)
                + "\",\"direction\":\"" + (role.equals("host") ? "hostToViewer" : "viewerToHost") + "\",\"sequence\":" + sequence + ",\"version\":1}";
        return ascii("{\"envelope\":\"" + Base64.getUrlEncoder().withoutPadding().encodeToString(ascii(envelope))
                + "\",\"from\":\"" + role + "\",\"seq\":" + sequence + ",\"type\":\"signal\"}");
    }
    private static byte[] forward(byte[] outbound, String from) {
        String text = text(outbound); String envelope = field(text, "envelope");
        Matcher sequence = Pattern.compile("\"seq\":([0-9]+)").matcher(text);
        if (!sequence.find()) throw new AssertionError("Expected captured sequence");
        return ascii("{\"envelope\":\"" + envelope + "\",\"from\":\"" + from + "\",\"seq\":" + sequence.group(1) + ",\"type\":\"signal\"}");
    }
    private static byte[] envelopeBytes(byte[] wire) { return Base64.getUrlDecoder().decode(field(text(wire), "envelope")); }
    private static byte[] ciphertext(byte[] wire) { return Base64.getDecoder().decode(field(text(envelopeBytes(wire)), "ciphertext")); }
    private static byte[] replaceEnvelope(String outer, byte[] envelope) {
        return ascii(outer.replace(field(outer, "envelope"), Base64.getUrlEncoder().withoutPadding().encodeToString(envelope)));
    }
    private static byte[] replaceCiphertext(byte[] outer, byte[] ciphertext) {
        String envelope = text(envelopeBytes(outer));
        return replaceEnvelope(text(outer), ascii(envelope.replace(field(envelope, "ciphertext"), Base64.getEncoder().encodeToString(ciphertext))));
    }
    private static String field(String text, String name) {
        Matcher match = Pattern.compile("\"" + name + "\":\"([^\"]*)\"").matcher(text);
        if (!match.find()) throw new AssertionError("Expected public fixture field");
        String value = match.group(1); if (match.find()) throw new AssertionError("Duplicate public fixture field"); return value;
    }
    private static PairingInvitation invitation(byte[] secret) throws Exception {
        assertEquals(20, secret.length); byte[] body = new byte[21]; body[0] = 1; System.arraycopy(secret, 0, body, 1, 20);
        MessageDigest digest = MessageDigest.getInstance("SHA-256"); digest.update(ascii("AudioStreamer.RemoteInvitation.Checksum.v1\0"));
        byte[] packet = Arrays.copyOf(body, 25); System.arraycopy(digest.digest(body), 0, packet, 21, 4);
        String alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"; StringBuilder code = new StringBuilder(); int buffer = 0, bits = 0;
        for (byte b : packet) { buffer = (buffer << 8) | (b & 255); bits += 8; while (bits >= 5) { bits -= 5; code.append(alphabet.charAt((buffer >>> bits) & 31)); } }
        return PairingInvitation.parseManual(code.toString());
    }
    private interface Operation { Object run() throws Exception; }
    private static void refuses(FailureCode expected, Operation operation) throws Exception {
        try { operation.run(); fail("Expected bounded redacted envelope refusal"); }
        catch (EnvelopeFailure error) {
            assertEquals(expected, error.code()); assertEquals("Beluga pairing envelope refused: " + expected.name(), error.getMessage());
            assertEquals(null, error.getCause()); assertEquals(0, error.getSuppressed().length);
        }
    }
    private static byte[] range(int start, int end) { byte[] bytes = new byte[end - start]; for (int index = 0; index < bytes.length; index++) bytes[index] = (byte) (start + index); return bytes; }
    private static String repeat(char c, int count) { char[] chars = new char[count]; Arrays.fill(chars, c); return new String(chars); }
    private static String text(byte[] bytes) { return new String(bytes, StandardCharsets.US_ASCII); }
    private static byte[] ascii(String text) { return text.getBytes(StandardCharsets.US_ASCII); }
    private static byte[] hex(String value) { byte[] bytes = new byte[value.length() / 2]; for (int index = 0; index < bytes.length; index++) bytes[index] = (byte) Integer.parseInt(value.substring(index * 2, index * 2 + 2), 16); return bytes; }
}
