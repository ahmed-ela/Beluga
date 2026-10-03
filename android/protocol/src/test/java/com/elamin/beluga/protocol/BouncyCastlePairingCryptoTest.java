package com.elamin.beluga.protocol;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;
import java.security.MessageDigest;
import java.security.Provider;
import java.security.Security;
import java.util.Arrays;
import java.util.Base64;
import java.util.Locale;
import java.util.Map;
import java.util.TreeMap;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import com.elamin.beluga.protocol.BouncyCastlePairingCrypto.CryptoFailure;
import com.elamin.beluga.protocol.BouncyCastlePairingCrypto.FailureCode;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Commit;
import com.elamin.beluga.protocol.PairingCanonicalCodec.CommitFields;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Confirmation;
import com.elamin.beluga.protocol.PairingCanonicalCodec.ConfirmationFields;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Hello;
import com.elamin.beluga.protocol.PairingCanonicalCodec.HelloFields;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Phase;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Role;

/** JVM-only public fixtures. Test-side recipes are not a pairing state machine or durable proof. */
public final class BouncyCastlePairingCryptoTest {
    private static final String FIXTURE_SHA256 = "7d8a58cd34400271d0c68ac1e263450c4ad4978337ae1bb87246362a6d0ec06a";
    private static final String[] SIGNED_MESSAGES = { "hello.host", "hello.viewer", "confirmation.host", "confirmation.viewer",
            "commit.proposal", "commit.acknowledgement", "commit.completion", "commit.activationAcknowledgement" };
    private static int assertions;
    private BouncyCastlePairingCryptoTest() { }

    public static void main(String[] args) throws Exception {
        check(args.length == 1 || args.length == 2, "explicit public fixture path and optional private output required");
        String[] before = providerNames();
        Map<String, byte[]> expected = loadPublicFixture(Paths.get(args[0]));
        testPublishedPrimitiveVectors();
        testCombinedLayoutAndAuthentication();
        testBoundsAndRedaction();
        Map<String, byte[]> generatedSignatures = testActualSwiftEngineFixtures(expected);
        check(Arrays.equals(before, providerNames()), "provider registration changed");
        // Every invariant must THROW before a create-new output can exist.
        if (args.length == 2) writePublicSignatures(Paths.get(args[1]), generatedSignatures);
        System.out.println("BC adapter public Swift vectors matched: 45; assertions: " + assertions);
    }

    private static Map<String, byte[]> testActualSwiftEngineFixtures(Map<String, byte[]> expected) throws Exception {
        Map<String, byte[]> actual = new TreeMap<>();
        Map<String, byte[]> generatedSignatures = new TreeMap<>();
        byte[] secret = new byte[20];
        for (int i = 0; i < secret.length; i++) secret[i] = (byte) i;
        UUID hostID = UUID.fromString("11111111-2222-3333-4444-555555555555");
        UUID viewerID = UUID.fromString("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE");
        byte[] hostSeed = fill(0x11, 32), viewerSeed = fill(0x22, 32);
        byte[] hostPrivate = fill(0x31, 32), viewerPrivate = fill(0x32, 32);
        byte[] hostNonce = fill(0x41, 32), viewerNonce = fill(0x42, 32);
        byte[] hostPublic = BouncyCastlePairingCrypto.ed25519PublicKey(hostSeed);
        byte[] viewerPublic = BouncyCastlePairingCrypto.ed25519PublicKey(viewerSeed);
        byte[] hostEphemeral = BouncyCastlePairingCrypto.x25519PublicKey(hostPrivate);
        byte[] viewerEphemeral = BouncyCastlePairingCrypto.x25519PublicKey(viewerPrivate);
        put(actual, "input.invitation-secret", secret);
        put(actual, "input.host-device-id", uuidText(hostID));
        put(actual, "input.viewer-device-id", uuidText(viewerID));
        put(actual, "input.host-display-name", utf8("Test Mac"));
        put(actual, "input.viewer-display-name", utf8("Test iPhone"));
        put(actual, "input.host-signing-seed", hostSeed);
        put(actual, "input.viewer-signing-seed", viewerSeed);
        put(actual, "input.host-ephemeral-private", hostPrivate);
        put(actual, "input.viewer-ephemeral-private", viewerPrivate);
        put(actual, "input.host-nonce", hostNonce);
        put(actual, "input.viewer-nonce", viewerNonce);
        put(actual, "derived.host-signing-public-key", hostPublic);
        put(actual, "derived.viewer-signing-public-key", viewerPublic);
        put(actual, "derived.host-ephemeral-public-key", hostEphemeral);
        put(actual, "derived.viewer-ephemeral-public-key", viewerEphemeral);
        Hello host = publicHello(actual, generatedSignatures, expected, "host", hostID, Role.HOST, "Test Mac", hostPublic, hostEphemeral, hostNonce, hostSeed, secret);
        Hello viewer = publicHello(actual, generatedSignatures, expected, "viewer", viewerID, Role.VIEWER, "Test iPhone", viewerPublic, viewerEphemeral, viewerNonce, viewerSeed, secret);
        byte[] shared = BouncyCastlePairingCrypto.x25519Agreement(hostPrivate, viewerEphemeral);
        equal(shared, BouncyCastlePairingCrypto.x25519Agreement(viewerPrivate, hostEphemeral), "mutual agreement");
        byte[] transcript = BouncyCastlePairingCrypto.sha256(PairingCanonicalCodec.transcriptInput(host, viewer));
        byte[] root = BouncyCastlePairingCrypto.hkdfSha256(concat(secret, shared), transcript, utf8("AudioStreamer.Pairing.Root.v1"), 32);
        byte[] pairRaw = publicUUIDBytes(BouncyCastlePairingCrypto.hkdfSha256(root, transcript, utf8("AudioStreamer.Pairing.ID.v1"), 32));
        byte[] commitRaw = publicUUIDBytes(BouncyCastlePairingCrypto.hkdfSha256(root, transcript, utf8("AudioStreamer.Pairing.CommitID.v1"), 32));
        UUID pairID = uuid(pairRaw), commitID = uuid(commitRaw);
        put(actual, "derived.transcript-hash", transcript);
        put(actual, "derived.pair-root-public-test-only", root);
        put(actual, "derived.pair-id-raw16", pairRaw);
        put(actual, "derived.pair-id-text", uuidText(pairID));
        put(actual, "derived.commit-id-raw16", commitRaw);
        put(actual, "derived.commit-id-text", uuidText(commitID));
        publicConfirmation(actual, generatedSignatures, expected, "host", pairID, hostID, Role.HOST, viewerID, transcript, root, hostSeed, hostPublic);
        publicConfirmation(actual, generatedSignatures, expected, "viewer", pairID, viewerID, Role.VIEWER, hostID, transcript, root, viewerSeed, viewerPublic);
        publicCommit(actual, generatedSignatures, expected, "proposal", Phase.PROPOSAL, pairID, commitID, hostID, Role.HOST, viewerID, transcript, root, hostSeed, hostPublic);
        publicCommit(actual, generatedSignatures, expected, "acknowledgement", Phase.ACKNOWLEDGEMENT, pairID, commitID, viewerID, Role.VIEWER, hostID, transcript, root, viewerSeed, viewerPublic);
        publicCommit(actual, generatedSignatures, expected, "completion", Phase.COMPLETION, pairID, commitID, hostID, Role.HOST, viewerID, transcript, root, hostSeed, hostPublic);
        publicCommit(actual, generatedSignatures, expected, "activationAcknowledgement", Phase.ACTIVATION_ACKNOWLEDGEMENT, pairID, commitID, viewerID, Role.VIEWER, hostID, transcript, root, viewerSeed, viewerPublic);
        check(actual.size() == 45 && actual.keySet().equals(expected.keySet()), "exact Swift fixture inventory");
        for (Map.Entry<String, byte[]> item : actual.entrySet()) equal(expected.get(item.getKey()), item.getValue(), "public fixture " + item.getKey());
        refuse(FailureCode.AUTHENTICATION_FAILED, () -> BouncyCastlePairingCrypto.x25519Agreement(hostPrivate, new byte[32]));
        byte[] lowOrder = new byte[32]; lowOrder[0] = 1;
        refuse(FailureCode.AUTHENTICATION_FAILED, () -> BouncyCastlePairingCrypto.x25519Agreement(hostPrivate, lowOrder));
        check(generatedSignatures.keySet().equals(signatureInventory().keySet()), "exact eight generated public triplets");
        return generatedSignatures;
    }

    private static Hello publicHello(Map<String, byte[]> actual, Map<String, byte[]> generated, Map<String, byte[]> expected,
            String role, UUID id, Role sender, String name,
            byte[] publicKey, byte[] ephemeral, byte[] nonce, byte[] seed, byte[] secret) throws Exception {
        HelloFields fields = new HelloFields(1, id, sender, name, publicKey, ephemeral, nonce);
        byte[] tag = BouncyCastlePairingCrypto.hmacSha256(secret, PairingCanonicalCodec.helloPskInput(fields));
        Hello unsignedSignature = new Hello(fields, tag, new byte[64]);
        byte[] signedBytes = PairingCanonicalCodec.helloSignatureInput(unsignedSignature);
        byte[] signature = authenticateRetainedAndGenerate(generated, expected, "hello." + role, seed, publicKey, signedBytes);
        Hello hello = new Hello(fields, tag, signature);
        put(actual, "hello." + role + ".unsigned", PairingCanonicalCodec.unsignedHello(fields));
        put(actual, "hello." + role + ".full", PairingCanonicalCodec.fullHello(hello));
        put(actual, "hello." + role + ".payload", PairingCanonicalCodec.helloPayload(hello));
        return hello;
    }

    private static void publicConfirmation(Map<String, byte[]> actual, Map<String, byte[]> generated, Map<String, byte[]> expected,
            String role, UUID pair, UUID sender,
            Role senderRole, UUID recipient, byte[] transcript, byte[] root, byte[] seed, byte[] publicKey) throws Exception {
        ConfirmationFields fields = new ConfirmationFields(1, pair, sender, senderRole, recipient, transcript);
        byte[] key = BouncyCastlePairingCrypto.hkdfSha256(root, transcript, utf8("AudioStreamer.Pairing.Confirmation." + role + ".v1"), 32);
        byte[] tag = BouncyCastlePairingCrypto.hmacSha256(key, PairingCanonicalCodec.confirmationMacInput(fields));
        byte[] signedBytes = PairingCanonicalCodec.confirmationSignatureInput(new Confirmation(fields, tag, new byte[64]));
        byte[] signature = authenticateRetainedAndGenerate(generated, expected, "confirmation." + role, seed, publicKey, signedBytes);
        Confirmation message = new Confirmation(fields, tag, signature);
        put(actual, "confirmation." + role + ".unsigned", PairingCanonicalCodec.unsignedConfirmation(fields));
        put(actual, "confirmation." + role + ".full", PairingCanonicalCodec.fullConfirmation(message));
        put(actual, "confirmation." + role + ".payload", PairingCanonicalCodec.confirmationPayload(message));
    }

    private static void publicCommit(Map<String, byte[]> actual, Map<String, byte[]> generated, Map<String, byte[]> expected,
            String phase, Phase phaseValue, UUID pair, UUID commit,
            UUID sender, Role role, UUID recipient, byte[] transcript, byte[] root, byte[] seed, byte[] publicKey) throws Exception {
        String roleName = role == Role.HOST ? "host" : "viewer";
        CommitFields fields = new CommitFields(1, pair, commit, sender, role, recipient, transcript, phaseValue);
        byte[] key = BouncyCastlePairingCrypto.hkdfSha256(root, transcript, utf8("AudioStreamer.Pairing.Commit." + roleName + "." + phase + ".v1"), 32);
        byte[] tag = BouncyCastlePairingCrypto.hmacSha256(key, PairingCanonicalCodec.commitMacInput(fields));
        byte[] signedBytes = PairingCanonicalCodec.commitSignatureInput(new Commit(fields, tag, new byte[64]));
        byte[] signature = authenticateRetainedAndGenerate(generated, expected, "commit." + phase, seed, publicKey, signedBytes);
        Commit message = new Commit(fields, tag, signature);
        put(actual, "commit." + phase + ".unsigned", PairingCanonicalCodec.unsignedCommit(fields));
        put(actual, "commit." + phase + ".full", PairingCanonicalCodec.fullCommit(message));
        put(actual, "commit." + phase + ".payload", PairingCanonicalCodec.commitPayload(message));
    }

    /** The original fixture is independently digest-bound; this is NOT an incoming JSON decoder. */
    private static byte[] authenticateRetainedAndGenerate(Map<String, byte[]> generated, Map<String, byte[]> expected,
            String prefix, byte[] seed, byte[] publicKey, byte[] signedBytes) throws Exception {
        byte[] full = expected.get(prefix + ".full");
        check(full != null && full.length > 0 && full.length <= 8192, "bounded retained signed fixture");
        for (byte value : full) check(value >= 0, "ASCII retained signed fixture");
        Matcher field = Pattern.compile("\"signature\":\"([A-Za-z0-9+/]{86}==)\"")
                .matcher(new String(full, StandardCharsets.US_ASCII));
        check(field.find(), "exact retained signature field");
        String text = field.group(1);
        byte[] retained = Base64.getDecoder().decode(text);
        check(retained.length == 64 && Base64.getEncoder().encodeToString(retained).equals(text) && !field.find(), "unique canonical retained signature");
        // CryptoKit may randomize Ed25519. Authenticate its exact original signature before
        // preserving it in the FULL hello transcript; do not demand deterministic byte equality.
        verifyWithTamperNegatives(publicKey, signedBytes, retained, "retained Swift");
        byte[] fresh = BouncyCastlePairingCrypto.ed25519Sign(seed, signedBytes);
        verifyWithTamperNegatives(publicKey, signedBytes, fresh, "new BC");
        put(generated, prefix + ".message", signedBytes);
        put(generated, prefix + ".public-key", publicKey);
        put(generated, prefix + ".signature", fresh);
        return retained;
    }

    private static void verifyWithTamperNegatives(byte[] key, byte[] message, byte[] signature, String label) throws Exception {
        check(BouncyCastlePairingCrypto.ed25519Verify(key, message, signature), label + " signature verified");
        check(!BouncyCastlePairingCrypto.ed25519Verify(key, message, flipped(signature)), label + " signature tamper refused");
        check(!BouncyCastlePairingCrypto.ed25519Verify(key, flipped(message), signature), label + " message tamper refused");
        check(!BouncyCastlePairingCrypto.ed25519Verify(flipped(key), message, signature), label + " key tamper refused");
    }

    private static Map<String, byte[]> signatureInventory() {
        Map<String, byte[]> expected = new TreeMap<>();
        for (String message : SIGNED_MESSAGES) for (String suffix : new String[] { ".message", ".public-key", ".signature" })
            put(expected, message + suffix, new byte[0]);
        return expected;
    }

    private static void writePublicSignatures(Path path, Map<String, byte[]> generated) throws Exception {
        check(path.isAbsolute(), "absolute public-signature output path");
        check(generated.size() == 24 && generated.keySet().equals(signatureInventory().keySet()), "exact output triplet inventory");
        StringBuilder rows = new StringBuilder("# beluga.public-test-bc-signatures.v1\n");
        for (Map.Entry<String, byte[]> item : generated.entrySet()) {
            int length = item.getValue().length;
            check(length > 0 && length <= 8192, "bounded generated public value");
            if (item.getKey().endsWith(".public-key")) check(length == 32, "output public key length");
            if (item.getKey().endsWith(".signature")) check(length == 64, "output signature length");
            rows.append(item.getKey()).append('\t').append(Base64.getEncoder().encodeToString(item.getValue())).append('\n');
        }
        byte[] bytes = rows.toString().getBytes(StandardCharsets.US_ASCII);
        check(bytes.length <= 128 * 1024, "bounded generated public file");
        Files.write(path, bytes, StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE);
    }

    private static void testPublishedPrimitiveVectors() throws Exception {
        // RFC5869 Appendix A.1: SHA256 extract+expand, not expand-only.
        equal(hex("3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865"),
                BouncyCastlePairingCrypto.hkdfSha256(fill(0x0b, 22), hex("000102030405060708090a0b0c"), hex("f0f1f2f3f4f5f6f7f8f9"), 42), "RFC5869 A.1");
        // RFC5869 Appendix A.3: empty salt/info.
        equal(hex("8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8"),
                BouncyCastlePairingCrypto.hkdfSha256(fill(0x0b, 22), new byte[0], new byte[0], 42), "RFC5869 A.3");
        equal(hex("b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"),
                BouncyCastlePairingCrypto.hmacSha256(fill(0x0b, 20), utf8("Hi There")), "RFC4231 case1");
        equal(hex("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
                BouncyCastlePairingCrypto.sha256(new byte[0]), "SHA256 empty");
        byte[] seed = hex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60");
        byte[] publicKey = hex("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a");
        byte[] signature = hex("e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155" +
                "5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b");
        equal(publicKey, BouncyCastlePairingCrypto.ed25519PublicKey(seed), "RFC8032 vector1 public");
        equal(signature, BouncyCastlePairingCrypto.ed25519Sign(seed, new byte[0]), "RFC8032 vector1 signature");
        check(BouncyCastlePairingCrypto.ed25519Verify(publicKey, new byte[0], signature), "RFC8032 vector1 verified");
        check(!BouncyCastlePairingCrypto.ed25519Verify(new byte[32], new byte[0], signature), "invalid public key refused");
    }

    private static void testCombinedLayoutAndAuthentication() throws Exception {
        // RFC8439 section2.8.2, with the exact deployed combined nonce-prefix layout.
        byte[] key = hex("808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f");
        byte[] nonce = hex("070000004041424344454647");
        byte[] aad = hex("50515253c0c1c2c3c4c5c6c7");
        byte[] plaintext = utf8("Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.");
        byte[] body = hex("d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d6" +
                "3dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b36" +
                "92ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc" +
                "3ff4def08e4b7a9de576d26586cec64b6116" + "1ae10b594f09e26a7e902ecbd0600691");
        byte[] combined = BouncyCastlePairingCrypto.sealCombined(key, nonce, plaintext, aad);
        equal(concat(nonce, body), combined, "RFC8439 combined");
        equal(plaintext, BouncyCastlePairingCrypto.openCombined(key, combined, aad), "RFC8439 opened");
        for (int offset : new int[] { 0, 12, combined.length - 1 }) {
            byte[] changed = combined.clone(); changed[offset] ^= 1;
            refuse(FailureCode.AUTHENTICATION_FAILED, () -> BouncyCastlePairingCrypto.openCombined(key, changed, aad));
        }
        refuse(FailureCode.AUTHENTICATION_FAILED, () -> BouncyCastlePairingCrypto.openCombined(flipped(key), combined, aad));
        refuse(FailureCode.AUTHENTICATION_FAILED, () -> BouncyCastlePairingCrypto.openCombined(key, combined, flipped(aad)));
        byte[] empty = BouncyCastlePairingCrypto.sealCombined(key, nonce, new byte[0], new byte[0]);
        check(empty.length == 28, "empty combined length");
        equal(new byte[0], BouncyCastlePairingCrypto.openCombined(key, empty, new byte[0]), "empty authenticated plaintext");
        equal(key, hex("808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f"), "key not mutated");
        equal(nonce, hex("070000004041424344454647"), "nonce not mutated");
    }

    private static void testBoundsAndRedaction() throws Exception {
        byte[] key = fill(0x77, 32), nonce = new byte[12], data = utf8("PUBLIC-SENTINEL");
        for (byte[] bad : new byte[][] { null, new byte[0], new byte[31], new byte[33], new byte[64] }) {
            refuse(FailureCode.MALFORMED_INPUT, () -> BouncyCastlePairingCrypto.ed25519PublicKey(bad));
            refuse(FailureCode.MALFORMED_INPUT, () -> BouncyCastlePairingCrypto.ed25519Sign(bad, data));
            refuse(FailureCode.MALFORMED_INPUT, () -> BouncyCastlePairingCrypto.x25519PublicKey(bad));
            refuse(FailureCode.MALFORMED_INPUT, () -> BouncyCastlePairingCrypto.x25519Agreement(key, bad));
            refuse(FailureCode.MALFORMED_INPUT, () -> BouncyCastlePairingCrypto.sealCombined(bad, nonce, data, data));
        }
        for (int bad : new int[] { -1, 0, BouncyCastlePairingCrypto.MAXIMUM_HKDF_BYTES + 1 })
            refuse(FailureCode.MALFORMED_INPUT, () -> BouncyCastlePairingCrypto.hkdfSha256(key, key, data, bad));
        refuse(FailureCode.MALFORMED_INPUT, () -> BouncyCastlePairingCrypto.hkdfSha256(new byte[0], key, data, 32));
        refuse(FailureCode.MALFORMED_INPUT, () -> BouncyCastlePairingCrypto.hkdfSha256(key, null, data, 32));
        refuse(FailureCode.MALFORMED_INPUT, () -> BouncyCastlePairingCrypto.hkdfSha256(key, key, null, 32));
        refuse(FailureCode.MALFORMED_INPUT, () -> BouncyCastlePairingCrypto.hmacSha256(new byte[0], data));
        refuse(FailureCode.MALFORMED_INPUT, () -> BouncyCastlePairingCrypto.hmacSha256(key, null));
        refuse(FailureCode.MALFORMED_INPUT, () -> BouncyCastlePairingCrypto.ed25519Verify(key, data, new byte[63]));
        refuse(FailureCode.MALFORMED_INPUT, () -> BouncyCastlePairingCrypto.ed25519Verify(key, data, new byte[65]));
        for (byte[] bad : new byte[][] { null, new byte[11], new byte[13] })
            refuse(FailureCode.MALFORMED_INPUT, () -> BouncyCastlePairingCrypto.sealCombined(key, bad, data, data));
        refuse(FailureCode.MALFORMED_INPUT, () -> BouncyCastlePairingCrypto.openCombined(key, new byte[27], data));
        byte[] oversized = new byte[BouncyCastlePairingCrypto.MAXIMUM_DATA_BYTES + 1];
        refuse(FailureCode.MALFORMED_INPUT, () -> BouncyCastlePairingCrypto.sha256(oversized));
        refuse(FailureCode.MALFORMED_INPUT, () -> BouncyCastlePairingCrypto.ed25519Sign(key, oversized));
        refuse(FailureCode.MALFORMED_INPUT, () -> BouncyCastlePairingCrypto.hmacSha256(key, oversized));
        refuse(FailureCode.MALFORMED_INPUT, () -> BouncyCastlePairingCrypto.sealCombined(key, nonce, oversized, data));
        refuse(FailureCode.MALFORMED_INPUT, () -> BouncyCastlePairingCrypto.sealCombined(key, nonce, data, oversized));
        equal(fill(0x77, 32), key, "caller seed/key bytes retained unchanged");
    }

    private static Map<String, byte[]> loadPublicFixture(Path path) throws Exception {
        check(path.isAbsolute(), "public fixture path absolute");
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try (InputStream stream = Files.newInputStream(path)) {
            byte[] chunk = new byte[4096];
            int count;
            while ((count = stream.read(chunk)) != -1) {
                check(out.size() + count <= 128 * 1024, "bounded public fixture file");
                out.write(chunk, 0, count);
            }
        }
        byte[] bytes = out.toByteArray();
        equal(hex(FIXTURE_SHA256), MessageDigest.getInstance("SHA-256").digest(bytes), "independent public fixture SHA256");
        for (byte value : bytes) check(value >= 0, "ASCII public fixture");
        String text = new String(bytes, StandardCharsets.US_ASCII);
        check(text.startsWith("# beluga.public-test-pairing-crypto.v1\n") && text.endsWith("\n"), "public fixture schema");
        Map<String, byte[]> result = new TreeMap<>();
        String last = "";
        for (String line : text.split("\n")) {
            if (line.startsWith("#")) continue;
            String[] fields = line.split("\t", -1);
            check(fields.length == 2 && fields[0].matches("[A-Za-z0-9.-]{1,80}") && last.compareTo(fields[0]) < 0, "unique sorted public fixture names");
            byte[] value = Base64.getDecoder().decode(fields[1]);
            check(value.length > 0 && value.length <= 8192 && Base64.getEncoder().encodeToString(value).equals(fields[1]), "canonical bounded public fixture bytes");
            check(result.put(fields[0], value) == null, "duplicate public fixture refused");
            last = fields[0];
        }
        check(result.size() == 45, "public fixture count");
        return result;
    }

    private static void put(Map<String, byte[]> map, String name, byte[] value) {
        check(map.put(name, value.clone()) == null, "duplicate generated vector");
    }
    private static byte[] publicUUIDBytes(byte[] derived) {
        byte[] result = Arrays.copyOf(derived, 16);
        result[6] = (byte) ((result[6] & 15) | 0x50);
        result[8] = (byte) ((result[8] & 63) | 0x80);
        return result;
    }
    private static UUID uuid(byte[] raw) { ByteBuffer bytes = ByteBuffer.wrap(raw); return new UUID(bytes.getLong(), bytes.getLong()); }
    private static byte[] uuidText(UUID value) { return utf8(value.toString().toUpperCase(Locale.ROOT)); }
    private static byte[] utf8(String value) { return value.getBytes(StandardCharsets.UTF_8); }
    private static byte[] fill(int value, int count) { byte[] result = new byte[count]; Arrays.fill(result, (byte) value); return result; }
    private static byte[] flipped(byte[] value) { byte[] result = value.clone(); result[0] ^= 1; return result; }
    private static byte[] concat(byte[] a, byte[] b) { byte[] result = Arrays.copyOf(a, a.length + b.length); System.arraycopy(b, 0, result, a.length, b.length); return result; }
    private static byte[] hex(String value) {
        check(value.matches("(?:[0-9a-f]{2})*"), "canonical test hex");
        byte[] result = new byte[value.length() / 2];
        for (int i = 0; i < result.length; i++) result[i] = (byte) Integer.parseInt(value.substring(i * 2, i * 2 + 2), 16);
        return result;
    }
    private static void equal(byte[] expected, byte[] actual, String label) { check(Arrays.equals(expected, actual), label); }
    private static void check(boolean value, String label) { assertions++; if (!value) throw new AssertionError(label); }
    private interface CheckedOperation { void run() throws CryptoFailure; }
    private static void refuse(FailureCode code, CheckedOperation operation) throws Exception {
        try { operation.run(); throw new AssertionError("expected typed refusal"); }
        catch (CryptoFailure error) {
            check(error.code() == code, "exact typed refusal");
            check(error.getCause() == null && error.getSuppressed().length == 0, "no upstream secret diagnostics retained");
            check(error.getMessage().equals("Beluga pairing crypto refused: " + code.name()), "fixed redacted diagnostic");
            check(!error.toString().contains("PUBLIC-SENTINEL"), "input absent from diagnostic");
        }
    }
    private static String[] providerNames() { Provider[] values = Security.getProviders(); String[] names = new String[values.length]; for (int i = 0; i < names.length; i++) names[i] = values[i].getName(); return names; }
}
