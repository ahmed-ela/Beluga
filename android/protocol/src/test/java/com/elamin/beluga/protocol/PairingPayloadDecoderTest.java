package com.elamin.beluga.protocol;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.Base64;
import java.util.Map;
import java.util.TreeMap;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Phase;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Role;
import com.elamin.beluga.protocol.PairingPayloadDecoder.CommitPayload;
import com.elamin.beluga.protocol.PairingPayloadDecoder.ConfirmationPayload;
import com.elamin.beluga.protocol.PairingPayloadDecoder.DecodeFailure;
import com.elamin.beluga.protocol.PairingPayloadDecoder.HelloPayload;
import com.elamin.beluga.protocol.PairingPayloadDecoder.Payload;

/** Public JVM fixtures only: successful decode is structural, NEVER authentication or pairing. */
public final class PairingPayloadDecoderTest {
    private static final String FIXTURE_SHA = "7d8a58cd34400271d0c68ac1e263450c4ad4978337ae1bb87246362a6d0ec06a";
    private static final String[] MESSAGES = { "hello.host", "hello.viewer", "confirmation.host", "confirmation.viewer",
            "commit.proposal", "commit.acknowledgement", "commit.completion", "commit.activationAcknowledgement" };
    private static final String HOST_ID = "11111111-2222-3333-4444-555555555555";
    private static final String VIEWER_ID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE";
    private static int assertions;
    private PairingPayloadDecoderTest() { }

    public static void main(String[] args) throws Exception {
        check(args.length == 1, "explicit hash-checked public fixture path required");
        Map<String, byte[]> fixture = loadFixture(Paths.get(args[0]));
        testActualSwiftTypedRoundTrips(fixture);
        testSchemaAndTypes(fixture);
        testDuplicatesAndGrammar(fixture);
        testUUIDsRolesAndPhases(fixture);
        testBase64(fixture);
        testNamesAndOptionalNil(fixture);
        testByteAndDepthLimits(fixture);
        testDefensiveOutputs(fixture);
        System.out.println("Pairing inbound STRUCTURAL decoder: 8 actual Swift payloads; assertions: " + assertions + "; no authentication claim");
    }

    private static void testActualSwiftTypedRoundTrips(Map<String, byte[]> fixture) throws Exception {
        for (String name : MESSAGES) {
            byte[] wire = value(fixture, name + ".payload");
            Payload payload = PairingPayloadDecoder.decode(wire);
            byte[] unsigned, full, reencoded;
            boolean host = name.endsWith(".host") || name.equals("commit.proposal") || name.equals("commit.completion");
            if (payload instanceof HelloPayload) {
                HelloPayload hello = (HelloPayload) payload;
                check(payload.kind() == PairingPayloadDecoder.Kind.HELLO && hello.protocolVersion() == 1, "typed hello kind/version");
                check(hello.deviceID().equals(UUID.fromString(host ? HOST_ID : VIEWER_ID)), "hello identity accessor");
                check(hello.role() == (host ? Role.HOST : Role.VIEWER), "hello role accessor");
                check(hello.displayName().equals(host ? "Test Mac" : "Test iPhone"), "hello name accessor");
                equal(value(fixture, "derived." + (host ? "host" : "viewer") + "-signing-public-key"), hello.signingPublicKey(), "hello signing accessor");
                equal(value(fixture, "derived." + (host ? "host" : "viewer") + "-ephemeral-public-key"), hello.ephemeralKeyAgreementPublicKey(), "hello ephemeral accessor");
                equal(value(fixture, "input." + (host ? "host" : "viewer") + "-nonce"), hello.nonce(), "hello nonce accessor");
                check(hello.authenticationTag().length == 32 && hello.signature().length == 64, "hello tag/signature accessors");
                unsigned = PairingCanonicalCodec.unsignedHello(hello.canonicalFields());
                full = PairingCanonicalCodec.fullHello(hello.canonicalMessage());
                reencoded = PairingCanonicalCodec.helloPayload(hello.canonicalMessage());
            } else if (payload instanceof ConfirmationPayload) {
                ConfirmationPayload confirmation = (ConfirmationPayload) payload;
                check(payload.kind() == PairingPayloadDecoder.Kind.CONFIRMATION && confirmation.protocolVersion() == 1, "typed confirmation kind/version");
                check(confirmation.pairID().equals(UUID.fromString(text(value(fixture, "derived.pair-id-text")))), "confirmation pair accessor");
                check(confirmation.senderDeviceID().equals(UUID.fromString(host ? HOST_ID : VIEWER_ID)), "confirmation sender accessor");
                check(confirmation.recipientDeviceID().equals(UUID.fromString(host ? VIEWER_ID : HOST_ID)), "confirmation recipient accessor");
                check(confirmation.senderRole() == (host ? Role.HOST : Role.VIEWER), "confirmation role accessor");
                equal(value(fixture, "derived.transcript-hash"), confirmation.transcriptHash(), "confirmation transcript accessor");
                check(confirmation.confirmationTag().length == 32 && confirmation.signature().length == 64, "confirmation tag/signature accessors");
                unsigned = PairingCanonicalCodec.unsignedConfirmation(confirmation.canonicalFields());
                full = PairingCanonicalCodec.fullConfirmation(confirmation.canonicalMessage());
                reencoded = PairingCanonicalCodec.confirmationPayload(confirmation.canonicalMessage());
            } else {
                check(payload instanceof CommitPayload, "closed commit subtype");
                CommitPayload commit = (CommitPayload) payload;
                check(payload.kind() == PairingPayloadDecoder.Kind.COMMIT && commit.protocolVersion() == 1, "typed commit kind/version");
                check(commit.pairID().equals(UUID.fromString(text(value(fixture, "derived.pair-id-text")))), "commit pair accessor");
                check(commit.commitID().equals(UUID.fromString(text(value(fixture, "derived.commit-id-text")))), "commit identity accessor");
                check(commit.senderDeviceID().equals(UUID.fromString(host ? HOST_ID : VIEWER_ID)), "commit sender accessor");
                check(commit.recipientDeviceID().equals(UUID.fromString(host ? VIEWER_ID : HOST_ID)), "commit recipient accessor");
                check(commit.senderRole() == (host ? Role.HOST : Role.VIEWER), "commit role accessor");
                Phase phase = name.endsWith(".proposal") ? Phase.PROPOSAL : name.endsWith(".acknowledgement") ? Phase.ACKNOWLEDGEMENT
                        : name.endsWith(".completion") ? Phase.COMPLETION : Phase.ACTIVATION_ACKNOWLEDGEMENT;
                check(commit.phase() == phase, "commit phase accessor");
                equal(value(fixture, "derived.transcript-hash"), commit.transcriptHash(), "commit transcript accessor");
                check(commit.commitTag().length == 32 && commit.signature().length == 64, "commit tag/signature accessors");
                unsigned = PairingCanonicalCodec.unsignedCommit(commit.canonicalFields());
                full = PairingCanonicalCodec.fullCommit(commit.canonicalMessage());
                reencoded = PairingCanonicalCodec.commitPayload(commit.canonicalMessage());
            }
            equal(value(fixture, name + ".unsigned"), unsigned, "actual Swift unsigned roundtrip");
            equal(value(fixture, name + ".full"), full, "actual Swift full roundtrip");
            equal(wire, reencoded, "actual Swift payload roundtrip");
            check(payload.toString().equals("<redacted Beluga pairing payload>"), "redacted typed output");
        }
    }

    private static void testSchemaAndTypes(Map<String, byte[]> fixture) throws Exception {
        String hello = text(value(fixture, "hello.host.payload"));
        String confirmation = text(value(fixture, "confirmation.host.payload"));
        String commit = text(value(fixture, "commit.proposal.payload"));
        for (String version : new String[] { "0", "2", "-1", "+1", "01", "1.0", "1e0", "\"1\"", "true", "false", "null", "[]", "{}" })
            refuse(field(hello, "protocolVersion", version));
        for (String missing : new String[] { "deviceID", "role", "signingPublicKey", "ephemeralKeyAgreementPublicKey", "nonce", "authenticationTag", "signature" })
            refuse(removeStringField(hello, missing));
        refuse(hello.replace("\"protocolVersion\":1,", ""));
        for (String field : new String[] { "deviceID", "role", "displayName", "signingPublicKey", "ephemeralKeyAgreementPublicKey", "nonce", "authenticationTag", "signature" }) {
            if (!field.equals("displayName")) refuse(field(hello, field, "null"));
            refuse(field(hello, field, "1"));
            refuse(field(hello, field, "[]"));
        }
        refuse("{}"); refuse("[]"); refuse("null"); refuse("1");
        refuse(hello.replace("\"kind\":\"hello\"", "\"kind\":null"));
        refuse(hello.replace("\"kind\":\"hello\"", "\"kind\":\"unknown\""));
        refuse(hello.replace("\"kind\":\"hello\"", "\"kind\":\"confirmation\""));
        refuse(hello.substring(0, hello.length() - 1) + ",\"extra\":null}");
        refuse(hello.replace("\"hello\":{", "\"hello\":{\"extra\":null,"));
        refuse(hello.substring(0, hello.length() - 1) + ",\"commit\":{}}");
        refuse("{\"kind\":\"hello\",\"hello\":null}");
        for (String required : new String[] { "pairID", "senderDeviceID", "senderRole", "recipientDeviceID", "transcriptHash", "confirmationTag", "signature" })
            refuse(removeStringField(confirmation, required));
        for (String required : new String[] { "pairID", "commitID", "senderDeviceID", "senderRole", "recipientDeviceID", "transcriptHash", "phase", "commitTag", "signature" })
            refuse(removeStringField(commit, required));
    }

    private static void testDuplicatesAndGrammar(Map<String, byte[]> fixture) throws Exception {
        String hello = text(value(fixture, "hello.host.payload"));
        refuse(hello.replace("\"kind\":\"hello\"", "\"kind\":\"hello\",\"kind\":\"hello\""));
        refuse(hello.replace("\"kind\":\"hello\"", "\"kind\":\"hello\",\"" + "\\" + "u006bind\":\"hello\""));
        refuse(hello.replace("\"displayName\":\"Test Mac\"", "\"displayName\":null,\"displayName\":\"Test Mac\""));
        refuse(hello.replace("\"displayName\":\"Test Mac\"", "\"displayName\":null,\"" + "\\" + "u0064isplayName\":null"));
        refuse(hello.replace("\"protocolVersion\":1", "\"protocolVersion\":1,\"protocolVersion\":1"));
        refuse(hello + "{}"); refuse(hello + "junk");
        refuse(hello.substring(0, hello.length() - 1));
        refuse(hello.substring(0, hello.length() - 1) + ",}");
        refuse(hello.replace("\"deviceID\":", "\"deviceID\" "));
        refuse(hello.replace(",\"nonce\"", " \"nonce\""));
        refuse(hello.replace("\"kind\"", "'kind'"));
        refuse(hello.replace("\"hello\":{", "\"hello\":{/*not JSON*/"));
        refuse(field(hello, "displayName", "\"bad\\q\""));
        refuse(field(hello, "displayName", "\"" + "\\" + "u00GG\""));
        refuse(field(hello, "displayName", "\"" + "\\" + "u001\""));
        equal(value(fixture, "hello.host.payload"), PairingCanonicalCodec.helloPayload(((HelloPayload)
                PairingPayloadDecoder.decode(utf8(" \n\t" + hello + "\r "))).canonicalMessage()), "JSON whitespace admitted");
        String escapedKey = hello.replace("\"kind\"", "\"" + "\\" + "u006bind\"");
        check(PairingPayloadDecoder.decode(utf8(escapedKey)) instanceof HelloPayload, "escaped known key admitted once");
    }

    private static void testUUIDsRolesAndPhases(Map<String, byte[]> fixture) throws Exception {
        String hello = text(value(fixture, "hello.viewer.payload"));
        for (String bad : new String[] { "a-b-c-d-e", "1-2222-3333-4444-555555555555", "00000000-0000-0000-0000-000000000000",
                "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEEE", "AAAAAAAABBBBCCCCDDDDEEEEEEEEEEEE", "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEZ", " " + VIEWER_ID })
            refuse(field(hello, "deviceID", quote(bad)));
        HelloPayload lower = (HelloPayload) PairingPayloadDecoder.decode(utf8(field(hello, "deviceID", quote("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))));
        equal(value(fixture, "hello.viewer.payload"), PairingCanonicalCodec.helloPayload(lower.canonicalMessage()), "UUID case canonicalized by existing codec");
        for (String role : new String[] { "HOST", "Host", "phone", "", "viewer " }) refuse(field(hello, "role", quote(role)));
        String confirmation = text(value(fixture, "confirmation.host.payload"));
        refuse(field(confirmation, "recipientDeviceID", quote(HOST_ID)));
        for (String key : new String[] { "pairID", "senderDeviceID", "recipientDeviceID" })
            refuse(field(confirmation, key, quote("00000000-0000-0000-0000-000000000000")));
        String commit = text(value(fixture, "commit.proposal.payload"));
        refuse(field(commit, "commitID", quote("00000000-0000-0000-0000-000000000000")));
        refuse(field(commit, "senderRole", quote("viewer")));
        refuse(field(commit, "phase", quote("acknowledgement")));
        for (String bad : new String[] { "activationacknowledgement", "PROPOSAL", "", "unknown" }) refuse(field(commit, "phase", quote(bad)));
    }

    private static void testBase64(Map<String, byte[]> fixture) throws Exception {
        String hello = text(value(fixture, "hello.host.payload"));
        for (int length : new int[] { 0, 31, 33, 64 }) refuse(field(hello, "signingPublicKey", quote(Base64.getEncoder().encodeToString(new byte[length]))));
        for (int length : new int[] { 0, 32, 63, 65 }) refuse(field(hello, "signature", quote(Base64.getEncoder().encodeToString(new byte[length]))));
        String zero32 = Base64.getEncoder().encodeToString(new byte[32]);
        for (String bad : new String[] { zero32.substring(0, 43), zero32 + "=", " " + zero32.substring(1),
                "=" + zero32.substring(1), "_" + zero32.substring(1), "-" + zero32.substring(1),
                zero32.substring(0, 42) + "B=", zero32.substring(0, 40) + "AA==" })
            refuse(field(hello, "signingPublicKey", quote(bad)));
        String zero64 = Base64.getEncoder().encodeToString(new byte[64]);
        refuse(field(hello, "signature", quote(zero64.substring(0, 85) + "B==")));
        for (String key : new String[] { "ephemeralKeyAgreementPublicKey", "nonce", "authenticationTag" })
            refuse(field(hello, key, quote(zero32.substring(0, 43))));
        String confirmation = text(value(fixture, "confirmation.host.payload"));
        for (String key : new String[] { "transcriptHash", "confirmationTag" }) refuse(field(confirmation, key, quote(zero32.substring(0, 43))));
        String commit = text(value(fixture, "commit.proposal.payload"));
        for (String key : new String[] { "transcriptHash", "commitTag" }) refuse(field(commit, key, quote(zero32.substring(0, 43))));
        // Structural lengths do not authenticate points, tags or signatures. Preserve that boundary.
        String zeros = field(field(field(hello, "signingPublicKey", quote(zero32)), "ephemeralKeyAgreementPublicKey", quote(zero32)),
                "signature", quote(zero64));
        HelloPayload structuralOnly = (HelloPayload) PairingPayloadDecoder.decode(utf8(zeros));
        equal(new byte[32], structuralOnly.signingPublicKey(), "structural zero key is not an authentication claim");
        equal(new byte[64], structuralOnly.signature(), "structural zero signature is not authenticated");
    }

    private static void testNamesAndOptionalNil(Map<String, byte[]> fixture) throws Exception {
        String hello = text(value(fixture, "hello.host.payload"));
        HelloPayload omitted = (HelloPayload) PairingPayloadDecoder.decode(utf8(removeStringField(hello, "displayName")));
        HelloPayload nil = (HelloPayload) PairingPayloadDecoder.decode(utf8(field(hello, "displayName", "null")));
        check(omitted.displayName() == null && nil.displayName() == null, "omitted/null optional name");
        equal(PairingCanonicalCodec.helloPayload(omitted.canonicalMessage()), PairingCanonicalCodec.helloPayload(nil.canonicalMessage()), "nil emits omitted name");
        check(!text(PairingCanonicalCodec.helloPayload(nil.canonicalMessage())).contains("displayName"), "no explicit nil re-encoding");
        HelloPayload spaced = (HelloPayload) PairingPayloadDecoder.decode(utf8(field(hello, "displayName", quote(" Mac "))));
        check(spaced.displayName().equals(" Mac "), "authenticated name bytes never trimmed");
        String encoded = "\"A\\\"B\\\\C\\/D" + "\\" + "u0045\"";
        HelloPayload escaped = (HelloPayload) PairingPayloadDecoder.decode(utf8(field(hello, "displayName", encoded)));
        check(escaped.displayName().equals("A\"B\\C/DE"), "JSON escapes decode exactly");
        String maximum = repeat('x', 128);
        check(((HelloPayload) PairingPayloadDecoder.decode(utf8(field(hello, "displayName", quote(maximum))))).displayName().equals(maximum), "128-byte ASCII name admitted");
        for (String bad : new String[] { "\"\"", "\" \"", "\"\\t\"", "\"\\n\"", "\"" + "\\" + "u0000\"", quote(repeat('x', 129)),
                "\"" + "\\" + "uD800\"", "\"" + (char) 0x7f + "\"" })
            refuse(field(hello, "displayName", bad));
        for (String admitted : new String[] { "\"caf\u00e9\"", "\"" + "\\" + "u00e9\"", "\"" + "\\" + "uD83D" + "\\" + "uDE00\"" })
            check(PairingPayloadDecoder.decode(utf8(field(hello, "displayName", admitted))) instanceof HelloPayload,
                    "exact reviewed Unicode profile broadens ASCII-only admission");
        refuse(field(hello, "displayName", "\"raw\ncontrol\""));
    }

    private static void testByteAndDepthLimits(Map<String, byte[]> fixture) throws Exception {
        refuse((byte[]) null); refuse(new byte[0]);
        byte[] hello = value(fixture, "hello.host.payload");
        int cap = PairingPayloadDecoder.MAXIMUM_PLAINTEXT_BYTES;
        byte[] exact = new byte[cap]; Arrays.fill(exact, (byte) ' '); System.arraycopy(hello, 0, exact, 0, hello.length);
        check(PairingPayloadDecoder.decode(exact) instanceof HelloPayload, "exact byte cap with bounded valid whitespace");
        refuse(Arrays.copyOf(exact, cap + 1));
        for (byte[] bad : new byte[][] { { (byte) 0xc0, (byte) 0xaf }, { (byte) 0xe2, (byte) 0x82 },
                { (byte) 0xed, (byte) 0xa0, (byte) 0x80 }, { (byte) 0x80 }, { (byte) 0xff } }) refuse(bad);
        refuse(concat(new byte[] { (byte) 0xef, (byte) 0xbb, (byte) 0xbf }, hello));
        refuse(field(text(hello), "nonce", "{}"));
        refuse(field(text(hello), "nonce", "{\"nested\":{}}"));
        refuse("{\"hello\":{\"x\":" + repeat('{', 4000) + ",\"kind\":\"hello\"}");
        refuse(field(text(hello), "displayName", quote(repeat('x', 257))));
    }

    private static void testDefensiveOutputs(Map<String, byte[]> fixture) throws Exception {
        for (String name : MESSAGES) {
            byte[] source = value(fixture, name + ".payload").clone();
            Payload payload = PairingPayloadDecoder.decode(source);
            Arrays.fill(source, (byte) 0);
            byte[] reencoded;
            if (payload instanceof HelloPayload) {
                HelloPayload hello = (HelloPayload) payload;
                for (byte[] bytes : new byte[][] { hello.signingPublicKey(), hello.ephemeralKeyAgreementPublicKey(), hello.nonce(), hello.authenticationTag(), hello.signature() }) Arrays.fill(bytes, (byte) 0);
                reencoded = PairingCanonicalCodec.helloPayload(hello.canonicalMessage());
                equal(value(fixture, "derived." + (name.endsWith("host") ? "host" : "viewer") + "-signing-public-key"), hello.signingPublicKey(), "hello defensive getter");
            } else if (payload instanceof ConfirmationPayload) {
                ConfirmationPayload confirmation = (ConfirmationPayload) payload;
                for (byte[] bytes : new byte[][] { confirmation.transcriptHash(), confirmation.confirmationTag(), confirmation.signature() }) Arrays.fill(bytes, (byte) 0);
                reencoded = PairingCanonicalCodec.confirmationPayload(confirmation.canonicalMessage());
                equal(value(fixture, "derived.transcript-hash"), confirmation.transcriptHash(), "confirmation defensive getter");
            } else {
                CommitPayload commit = (CommitPayload) payload;
                for (byte[] bytes : new byte[][] { commit.transcriptHash(), commit.commitTag(), commit.signature() }) Arrays.fill(bytes, (byte) 0);
                reencoded = PairingCanonicalCodec.commitPayload(commit.canonicalMessage());
                equal(value(fixture, "derived.transcript-hash"), commit.transcriptHash(), "commit defensive getter");
            }
            equal(value(fixture, name + ".payload"), reencoded, "input/getter mutation cannot alter codec object");
        }
    }

    private static Map<String, byte[]> loadFixture(Path path) throws Exception {
        check(path.isAbsolute(), "absolute public fixture");
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try (InputStream input = Files.newInputStream(path)) {
            byte[] chunk = new byte[4096]; int count;
            while ((count = input.read(chunk)) != -1) { check(out.size() + count <= 128 * 1024, "bounded fixture"); out.write(chunk, 0, count); }
        }
        byte[] data = out.toByteArray();
        equal(hex(FIXTURE_SHA), MessageDigest.getInstance("SHA-256").digest(data), "exact original Swift fixture SHA");
        for (byte c : data) check(c >= 0, "ASCII fixture");
        String text = new String(data, StandardCharsets.US_ASCII);
        check(text.startsWith("# beluga.public-test-pairing-crypto.v1\n") && text.endsWith("\n"), "fixture schema");
        Map<String, byte[]> values = new TreeMap<>(); String last = "";
        for (String row : text.split("\n")) {
            if (row.startsWith("#")) continue;
            String[] columns = row.split("\t", -1);
            check(columns.length == 2 && columns[0].matches("[A-Za-z0-9.-]{1,80}") && columns[0].compareTo(last) > 0, "unique sorted fixture rows");
            byte[] bytes = Base64.getDecoder().decode(columns[1]);
            check(bytes.length > 0 && bytes.length <= 8192 && Base64.getEncoder().encodeToString(bytes).equals(columns[1]), "canonical bounded fixture Base64");
            check(values.put(columns[0], bytes) == null, "no duplicate fixture"); last = columns[0];
        }
        check(values.size() == 45, "all original fixture rows retained");
        return values;
    }

    private static String field(String json, String name, String replacement) {
        Matcher match = Pattern.compile("\\\"" + Pattern.quote(name) + "\\\":(?:\\\"[^\\\"]*\\\"|1)").matcher(json);
        check(match.find(), "fixture field to mutate exists");
        return match.replaceFirst(Matcher.quoteReplacement("\"" + name + "\":" + replacement));
    }
    private static String removeStringField(String json, String name) {
        Matcher match = Pattern.compile("\\\"" + Pattern.quote(name) + "\\\":\\\"[^\\\"]*\\\",").matcher(json);
        if (match.find()) return match.replaceFirst("");
        match = Pattern.compile(",\\\"" + Pattern.quote(name) + "\\\":\\\"[^\\\"]*\\\"").matcher(json);
        check(match.find(), "fixture field to remove exists"); return match.replaceFirst("");
    }
    private static byte[] value(Map<String, byte[]> values, String name) { byte[] bytes = values.get(name); check(bytes != null, "fixture row required"); return bytes; }
    private static byte[] utf8(String text) { return text.getBytes(StandardCharsets.UTF_8); }
    private static String text(byte[] bytes) { return new String(bytes, StandardCharsets.UTF_8); }
    private static String quote(String value) { return "\"" + value + "\""; } // Only controlled public mutation fixtures.
    private static String repeat(char value, int count) { char[] chars = new char[count]; Arrays.fill(chars, value); return new String(chars); }
    private static byte[] concat(byte[] a, byte[] b) { byte[] out = Arrays.copyOf(a, a.length + b.length); System.arraycopy(b, 0, out, a.length, b.length); return out; }
    private static byte[] hex(String value) { byte[] out = new byte[value.length() / 2]; for (int i = 0; i < out.length; i++) out[i] = (byte) Integer.parseInt(value.substring(i * 2, i * 2 + 2), 16); return out; }
    private static void equal(byte[] expected, byte[] actual, String label) { check(Arrays.equals(expected, actual), label); }
    private static void check(boolean valid, String label) { assertions++; if (!valid) throw new AssertionError(label); }
    private static void refuse(String value) throws Exception { refuse(utf8(value)); }
    private static void refuse(byte[] value) throws Exception {
        try { PairingPayloadDecoder.decode(value); throw new AssertionError("structural refusal required"); }
        catch (DecodeFailure failure) {
            check(failure.getMessage().equals("Invalid Beluga v1 pairing payload"), "fixed redacted error");
            check(failure.getCause() == null && failure.getSuppressed().length == 0, "no upstream diagnostics");
            check(!failure.toString().contains("Test Mac") && !failure.toString().contains("signingPublicKey"), "no raw pairing fields in error");
        }
    }
}
