package com.elamin.beluga.protocol;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.Arrays;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

/** Dependency-free JVM tests, using deliberately unauthenticated public synthetic bytes. */
public final class PairingCanonicalCodecTest {
    private static final UUID HOST_ID = UUID.fromString("11111111-2222-3333-4444-555555555555");
    private static final UUID VIEWER_ID = UUID.fromString("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE");
    private static final UUID PAIR_ID = UUID.fromString("01020304-0506-5708-890A-0B0C0D0E0F10");
    private static final UUID COMMIT_ID = UUID.fromString("10203040-5060-5708-90A0-B0C0D0E0F000");
    private static int assertions;
    private PairingCanonicalCodecTest() { }

    public static void main(String[] args) throws Exception {
        if (args.length > 1) throw new IllegalArgumentException("Optional private synthetic-vector output path only");
        testCanonicalHelloAndOptionalOmission();
        testBase64StandardAlphabetPaddingAndNoSlashEscaping();
        testExactConfirmationAndCommitSchema();
        testBoundsVersionRoleAndRedaction();
        testDefensiveCopies();
        Map<String, byte[]> vectors = vectors();
        check(vectors.size() == 37, "exact synthetic vector inventory");
        checkFrame(vectors.get("domain-hello-psk"), "Hello.PSK", vectors.get("hello-host-unsigned"));
        checkFrame(vectors.get("domain-hello-signature"), "Hello.Signature",
                vectors.get("hello-host-unsigned"), fill(0x51, 32));
        checkFrame(vectors.get("domain-transcript"), "Transcript", vectors.get("transcript-full"));
        checkFrame(vectors.get("domain-confirmation-mac"), "Confirmation.MAC", vectors.get("confirmation-host-unsigned"));
        checkFrame(vectors.get("domain-confirmation-signature"), "Confirmation.Signature",
                vectors.get("confirmation-host-unsigned"), fill(0x72, 32));
        String[] phases = {"proposal", "acknowledgement", "completion", "activationAcknowledgement"};
        for (String phase : phases) {
            checkFrame(vectors.get("domain-commit-" + phase + "-mac"), "Commit.MAC",
                    vectors.get("commit-" + phase + "-unsigned"));
            checkFrame(vectors.get("domain-commit-" + phase + "-signature"), "Commit.Signature",
                    vectors.get("commit-" + phase + "-unsigned"), fill(0x74, 32));
        }
        for (byte[] vector : vectors.values()) check(vector.length <= PairingCanonicalCodec.MAXIMUM_ENCODED_BYTES, "bounded vector");
        if (args.length == 1) writeSyntheticVectors(Path.of(args[0]), vectors);
        System.out.println("Pairing canonical codec: " + assertions + " assertions; PASS (outbound synthetic JVM draft only)");
    }

    private static PairingCanonicalCodec.HelloFields hostFields() {
        return new PairingCanonicalCodec.HelloFields(1, HOST_ID, PairingCanonicalCodec.Role.HOST,
                " Test Mac / \"Desk\" \\ ", fill(0x11, 32), fill(0x31, 32), fill(0x41, 32));
    }
    private static PairingCanonicalCodec.Hello host() {
        return new PairingCanonicalCodec.Hello(hostFields(), fill(0x51, 32), fill(0x61, 64));
    }
    private static PairingCanonicalCodec.HelloFields viewerFields() {
        return new PairingCanonicalCodec.HelloFields(1, VIEWER_ID, PairingCanonicalCodec.Role.VIEWER,
                null, fill(0x22, 32), fill(0x32, 32), fill(0x42, 32));
    }
    private static PairingCanonicalCodec.Hello viewer() {
        return new PairingCanonicalCodec.Hello(viewerFields(), fill(0x52, 32), fill(0x62, 64));
    }
    private static PairingCanonicalCodec.HelloFields slashFields() {
        return new PairingCanonicalCodec.HelloFields(1, HOST_ID, PairingCanonicalCodec.Role.HOST,
                null, fill(0xff, 32), fill(0xfb, 32), fill(0xff, 32));
    }
    private static PairingCanonicalCodec.Hello slashHello() {
        return new PairingCanonicalCodec.Hello(slashFields(), fill(0xff, 32), fill(0xff, 64));
    }
    private static PairingCanonicalCodec.ConfirmationFields confirmationFields() {
        return new PairingCanonicalCodec.ConfirmationFields(1, PAIR_ID, HOST_ID,
                PairingCanonicalCodec.Role.HOST, VIEWER_ID, fill(0x71, 32));
    }
    private static PairingCanonicalCodec.Confirmation confirmation() {
        return new PairingCanonicalCodec.Confirmation(confirmationFields(), fill(0x72, 32), fill(0x73, 64));
    }
    private static PairingCanonicalCodec.CommitFields commitFields(PairingCanonicalCodec.Phase phase) {
        boolean host = phase == PairingCanonicalCodec.Phase.PROPOSAL || phase == PairingCanonicalCodec.Phase.COMPLETION;
        return new PairingCanonicalCodec.CommitFields(1, PAIR_ID, COMMIT_ID,
                host ? HOST_ID : VIEWER_ID, host ? PairingCanonicalCodec.Role.HOST : PairingCanonicalCodec.Role.VIEWER,
                host ? VIEWER_ID : HOST_ID, fill(0x71, 32), phase);
    }
    private static PairingCanonicalCodec.Commit commit(PairingCanonicalCodec.Phase phase) {
        return new PairingCanonicalCodec.Commit(commitFields(phase), fill(0x74, 32), fill(0x75, 64));
    }

    private static void testCanonicalHelloAndOptionalOmission() {
        String expected = "{\"deviceID\":\"11111111-2222-3333-4444-555555555555\","
                + "\"displayName\":\" Test Mac / \\\"Desk\\\" \\\\ \","
                + "\"ephemeralKeyAgreementPublicKey\":\"" + b64(fill(0x31, 32)) + "\","
                + "\"nonce\":\"" + b64(fill(0x41, 32)) + "\",\"protocolVersion\":1,"
                + "\"role\":\"host\",\"signingPublicKey\":\"" + b64(fill(0x11, 32)) + "\"}";
        check(expected.equals(text(PairingCanonicalCodec.unsignedHello(hostFields()))), "hello exact ASCII JSON order/escaping/no trimming");
        String viewer = text(PairingCanonicalCodec.unsignedHello(viewerFields()));
        check(!viewer.contains("displayName") && !viewer.contains("null"), "nil optional is omitted");
        check(viewer.contains("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"), "uppercase Foundation UUID spelling");
        check(!expected.contains("\\/"), "slash remains unescaped");
        String full = text(PairingCanonicalCodec.fullHello(host()));
        check(full.startsWith("{\"authenticationTag\":"), "full hello sorted first field");
        check(full.indexOf("\"signature\"") < full.indexOf("\"signingPublicKey\""), "signature sorted before signingPublicKey");
        check(text(PairingCanonicalCodec.helloPayload(host())).equals("{\"hello\":" + full + ",\"kind\":\"hello\"}"), "explicit payload wrapper");
        check(text(PairingCanonicalCodec.transcript(host(), viewer())).equals("{\"host\":" + full
                + ",\"viewer\":" + text(PairingCanonicalCodec.fullHello(viewer())) + "}"), "transcript uses full host/viewer order");
        reject(() -> PairingCanonicalCodec.transcript(viewer(), host()));
    }

    private static void testExactConfirmationAndCommitSchema() {
        String common = "\"pairID\":\"01020304-0506-5708-890A-0B0C0D0E0F10\",\"protocolVersion\":1,"
                + "\"recipientDeviceID\":\"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\","
                + "\"senderDeviceID\":\"11111111-2222-3333-4444-555555555555\",\"senderRole\":\"host\"";
        check(text(PairingCanonicalCodec.unsignedConfirmation(confirmationFields())).equals("{" + common
                + ",\"transcriptHash\":\"" + b64(fill(0x71, 32)) + "\"}"), "confirmation exact unsigned schema");
        String full = text(PairingCanonicalCodec.fullConfirmation(confirmation()));
        check(full.equals("{\"confirmationTag\":\"" + b64(fill(0x72, 32)) + "\"," + common
                + ",\"signature\":\"" + b64(fill(0x73, 64)) + "\",\"transcriptHash\":\""
                + b64(fill(0x71, 32)) + "\"}"), "confirmation exact full schema");
        check(text(PairingCanonicalCodec.confirmationPayload(confirmation())).equals("{\"confirmation\":" + full
                + ",\"kind\":\"confirmation\"}"), "confirmation payload sorted");
        String commit = text(PairingCanonicalCodec.fullCommit(commit(PairingCanonicalCodec.Phase.PROPOSAL)));
        check(commit.startsWith("{\"commitID\":\"10203040-5060-5708-90A0-B0C0D0E0F000\",\"commitTag\":"), "commit prefix order");
        check(commit.contains("\"phase\":\"proposal\",\"protocolVersion\":1"), "phase spelling and integer1");
        check(text(PairingCanonicalCodec.commitPayload(commit(PairingCanonicalCodec.Phase.PROPOSAL))).equals("{\"commit\":"
                + commit + ",\"kind\":\"commit\"}"), "commit wrapper sorted");
    }

    private static void testBase64StandardAlphabetPaddingAndNoSlashEscaping() {
        String full = text(PairingCanonicalCodec.fullHello(slashHello()));
        check(full.contains("\"signingPublicKey\":\"" + b64(fill(0xff, 32)) + "\""), "32-byte Base64 matches JDK reference and one padding");
        check(full.contains("\"ephemeralKeyAgreementPublicKey\":\"" + b64(fill(0xfb, 32)) + "\""), "plus/slash alphabet matches JDK reference");
        check(full.contains("\"signature\":\"" + b64(fill(0xff, 64)) + "\""), "64-byte Base64 matches JDK reference and two padding");
        check(b64(fill(0xff, 32)).endsWith("=") && !b64(fill(0xff, 32)).endsWith("=="), "32-byte padding reference");
        check(b64(fill(0xff, 64)).endsWith("=="), "64-byte padding reference");
        check(full.contains("////") && full.contains("+/v7") && !full.contains("\\/"), "standard slash remains unescaped");
        // Cover nonrepeating bytes across both fixed admitted lengths.
        byte[] sequence32 = new byte[32], sequence64 = new byte[64];
        for (int i = 0; i < 64; i++) { sequence64[i] = (byte) (i * 37); if (i < 32) sequence32[i] = (byte) (i * 19); }
        PairingCanonicalCodec.HelloFields fields = new PairingCanonicalCodec.HelloFields(1, HOST_ID,
                PairingCanonicalCodec.Role.HOST, null, sequence32, sequence32, sequence32);
        full = text(PairingCanonicalCodec.fullHello(new PairingCanonicalCodec.Hello(fields, sequence32, sequence64)));
        check(full.contains("\"nonce\":\"" + b64(sequence32) + "\""), "nonrepeating32 Base64 matches JDK reference");
        check(full.contains("\"signature\":\"" + b64(sequence64) + "\""), "nonrepeating64 Base64 matches JDK reference");
    }

    private static void testBoundsVersionRoleAndRedaction() {
        String[] invalidNames = {"", "   ", "A\tB", "A\nB", "\u007f", "\uD800", "A".repeat(129)};
        for (String name : invalidNames) reject(() -> new PairingCanonicalCodec.HelloFields(1, HOST_ID,
                PairingCanonicalCodec.Role.HOST, name, fill(1, 32), fill(2, 32), fill(3, 32)));
        check(PairingCanonicalCodec.unsignedHello(new PairingCanonicalCodec.HelloFields(1, HOST_ID,
                PairingCanonicalCodec.Role.HOST, "A".repeat(128), fill(1, 32), fill(2, 32), fill(3, 32))).length < 8192, "exact ASCII name bound");
        check(text(PairingCanonicalCodec.unsignedHello(new PairingCanonicalCodec.HelloFields(1, HOST_ID,
                PairingCanonicalCodec.Role.HOST, "π", fill(1, 32), fill(2, 32), fill(3, 32)))).contains("π"), "reviewed Unicode profile broadens the old ASCII-only refusal");
        reject(() -> new PairingCanonicalCodec.HelloFields(2, HOST_ID, PairingCanonicalCodec.Role.HOST,
                null, fill(1, 32), fill(2, 32), fill(3, 32)));
        reject(() -> new PairingCanonicalCodec.HelloFields(1, new UUID(0, 0), PairingCanonicalCodec.Role.HOST,
                null, fill(1, 32), fill(2, 32), fill(3, 32)));
        reject(() -> new PairingCanonicalCodec.HelloFields(1, HOST_ID, null, null, fill(1, 32), fill(2, 32), fill(3, 32)));
        reject(() -> new PairingCanonicalCodec.HelloFields(1, HOST_ID, PairingCanonicalCodec.Role.HOST,
                null, fill(1, 31), fill(2, 32), fill(3, 32)));
        reject(() -> new PairingCanonicalCodec.Hello(hostFields(), null, fill(1, 64)));
        reject(() -> new PairingCanonicalCodec.Hello(hostFields(), fill(1, 32), fill(1, 63)));
        reject(() -> new PairingCanonicalCodec.ConfirmationFields(1, PAIR_ID, HOST_ID,
                PairingCanonicalCodec.Role.HOST, HOST_ID, fill(1, 32)));
        reject(() -> new PairingCanonicalCodec.ConfirmationFields(1, PAIR_ID, HOST_ID,
                PairingCanonicalCodec.Role.HOST, VIEWER_ID, fill(1, 33)));
        for (PairingCanonicalCodec.Phase phase : PairingCanonicalCodec.Phase.values()) {
            boolean host = phase == PairingCanonicalCodec.Phase.PROPOSAL || phase == PairingCanonicalCodec.Phase.COMPLETION;
            reject(() -> new PairingCanonicalCodec.CommitFields(1, PAIR_ID, COMMIT_ID, HOST_ID,
                    host ? PairingCanonicalCodec.Role.VIEWER : PairingCanonicalCodec.Role.HOST, VIEWER_ID, fill(1, 32), phase));
        }
        reject(() -> PairingCanonicalCodec.unsignedHello(null));
        reject(() -> PairingCanonicalCodec.transcript(null, viewer()));
        Object[] redacted = {hostFields(), host(), confirmationFields(), confirmation(),
                commitFields(PairingCanonicalCodec.Phase.PROPOSAL), commit(PairingCanonicalCodec.Phase.PROPOSAL)};
        for (Object object : redacted) check(object.toString().startsWith("<redacted Beluga pairing "), "redacted description");
    }

    private static void testDefensiveCopies() {
        byte[] key = fill(1, 32), ephemeral = fill(2, 32), nonce = fill(3, 32);
        byte[] tag = fill(4, 32), signature = fill(5, 64);
        PairingCanonicalCodec.HelloFields fields = new PairingCanonicalCodec.HelloFields(1, HOST_ID,
                PairingCanonicalCodec.Role.HOST, null, key, ephemeral, nonce);
        PairingCanonicalCodec.Hello hello = new PairingCanonicalCodec.Hello(fields, tag, signature);
        byte[] initial = PairingCanonicalCodec.fullHello(hello);
        for (byte[] input : new byte[][] {key, ephemeral, nonce, tag, signature}) Arrays.fill(input, (byte) 0);
        check(Arrays.equals(initial, PairingCanonicalCodec.fullHello(hello)), "caller mutation cannot change hello");
        Arrays.fill(initial, (byte) 0);
        check(PairingCanonicalCodec.fullHello(hello)[0] == '{', "returned encoding is independent");
        byte[] hash = fill(1, 32), confirmTag = fill(2, 32), confirmSignature = fill(3, 64);
        PairingCanonicalCodec.ConfirmationFields confirmation = new PairingCanonicalCodec.ConfirmationFields(1,
                PAIR_ID, HOST_ID, PairingCanonicalCodec.Role.HOST, VIEWER_ID, hash);
        PairingCanonicalCodec.Confirmation full = new PairingCanonicalCodec.Confirmation(confirmation, confirmTag, confirmSignature);
        initial = PairingCanonicalCodec.fullConfirmation(full);
        for (byte[] input : new byte[][] {hash, confirmTag, confirmSignature}) Arrays.fill(input, (byte) 0);
        check(Arrays.equals(initial, PairingCanonicalCodec.fullConfirmation(full)), "caller mutation cannot change confirmation");
        hash = fill(1, 32); tag = fill(2, 32); signature = fill(3, 64);
        PairingCanonicalCodec.CommitFields commit = new PairingCanonicalCodec.CommitFields(1, PAIR_ID, COMMIT_ID,
                HOST_ID, PairingCanonicalCodec.Role.HOST, VIEWER_ID, hash, PairingCanonicalCodec.Phase.PROPOSAL);
        PairingCanonicalCodec.Commit fullCommit = new PairingCanonicalCodec.Commit(commit, tag, signature);
        initial = PairingCanonicalCodec.fullCommit(fullCommit);
        for (byte[] input : new byte[][] {hash, tag, signature}) Arrays.fill(input, (byte) 0);
        check(Arrays.equals(initial, PairingCanonicalCodec.fullCommit(fullCommit)), "caller mutation cannot change commit");
    }

    private static Map<String, byte[]> vectors() {
        Map<String, byte[]> result = new LinkedHashMap<>();
        result.put("hello-host-unsigned", PairingCanonicalCodec.unsignedHello(hostFields()));
        result.put("hello-host-full", PairingCanonicalCodec.fullHello(host()));
        result.put("hello-viewer-unsigned", PairingCanonicalCodec.unsignedHello(viewerFields()));
        result.put("hello-viewer-full", PairingCanonicalCodec.fullHello(viewer()));
        result.put("payload-hello-host", PairingCanonicalCodec.helloPayload(host()));
        result.put("transcript-full", PairingCanonicalCodec.transcript(host(), viewer()));
        result.put("domain-hello-psk", PairingCanonicalCodec.helloPskInput(hostFields()));
        result.put("domain-hello-signature", PairingCanonicalCodec.helloSignatureInput(host()));
        result.put("domain-transcript", PairingCanonicalCodec.transcriptInput(host(), viewer()));
        result.put("confirmation-host-unsigned", PairingCanonicalCodec.unsignedConfirmation(confirmationFields()));
        result.put("confirmation-host-full", PairingCanonicalCodec.fullConfirmation(confirmation()));
        result.put("payload-confirmation-host", PairingCanonicalCodec.confirmationPayload(confirmation()));
        result.put("domain-confirmation-mac", PairingCanonicalCodec.confirmationMacInput(confirmationFields()));
        result.put("domain-confirmation-signature", PairingCanonicalCodec.confirmationSignatureInput(confirmation()));
        result.put("hello-slash-unsigned", PairingCanonicalCodec.unsignedHello(slashFields()));
        result.put("hello-slash-full", PairingCanonicalCodec.fullHello(slashHello()));
        result.put("payload-hello-slash", PairingCanonicalCodec.helloPayload(slashHello()));
        PairingCanonicalCodec.Phase[] phases = PairingCanonicalCodec.Phase.values();
        String[] names = {"proposal", "acknowledgement", "completion", "activationAcknowledgement"};
        for (int i = 0; i < phases.length; i++) {
            String prefix = "commit-" + names[i];
            result.put(prefix + "-unsigned", PairingCanonicalCodec.unsignedCommit(commitFields(phases[i])));
            result.put(prefix + "-full", PairingCanonicalCodec.fullCommit(commit(phases[i])));
            result.put("payload-" + prefix, PairingCanonicalCodec.commitPayload(commit(phases[i])));
            result.put("domain-" + prefix + "-mac", PairingCanonicalCodec.commitMacInput(commitFields(phases[i])));
            result.put("domain-" + prefix + "-signature", PairingCanonicalCodec.commitSignatureInput(commit(phases[i])));
        }
        return result;
    }
    private static void checkFrame(byte[] frame, String suffix, byte[]... pieces) {
        byte[] label = ("AudioStreamer.Pairing." + suffix + ".v1").getBytes(StandardCharsets.US_ASCII);
        ByteBuffer cursor = ByteBuffer.wrap(frame);
        byte[] actual = new byte[label.length]; cursor.get(actual);
        check(Arrays.equals(label, actual) && cursor.get() == 0, "exact domain and NUL");
        for (byte[] piece : pieces) {
            check(cursor.getLong() == piece.length, "UInt64 BE byte length");
            actual = new byte[piece.length]; cursor.get(actual);
            check(Arrays.equals(piece, actual), "exact framed piece");
        }
        check(!cursor.hasRemaining(), "no extra domain bytes");
    }
    private static void writeSyntheticVectors(Path path, Map<String, byte[]> vectors) throws Exception {
        if (!path.isAbsolute()) throw new IllegalArgumentException("Synthetic-vector path must be explicit and absolute");
        StringBuilder rows = new StringBuilder("# Public synthetic unauthenticated codec bytes only; never real credentials.\n");
        for (Map.Entry<String, byte[]> entry : vectors.entrySet()) rows.append(entry.getKey()).append('\t')
                .append(b64(entry.getValue())).append('\n');
        Files.write(path, rows.toString().getBytes(StandardCharsets.US_ASCII), StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE);
    }
    private static byte[] fill(int value, int count) { byte[] bytes = new byte[count]; Arrays.fill(bytes, (byte) value); return bytes; }
    private static String b64(byte[] bytes) { return Base64.getEncoder().encodeToString(bytes); }
    private static String text(byte[] bytes) { return new String(bytes, StandardCharsets.UTF_8); }
    private static void reject(Runnable action) {
        try { action.run(); } catch (IllegalArgumentException expected) {
            check("Invalid Beluga v1 pairing codec input".equals(expected.getMessage()), "input error redacted"); return;
        }
        throw new AssertionError("Expected bounded codec refusal");
    }
    private static void check(boolean condition, String label) { if (!condition) throw new AssertionError(label); assertions++; }
}
