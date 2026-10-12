package com.elamin.beluga.protocol;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.Base64;
import java.util.HashSet;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Commit;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Confirmation;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Hello;
import com.elamin.beluga.protocol.PairingCanonicalCodec.HelloFields;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Phase;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Role;
import com.elamin.beluga.protocol.PairingPayloadDecoder.CommitPayload;
import com.elamin.beluga.protocol.PairingPayloadDecoder.ConfirmationPayload;
import com.elamin.beluga.protocol.PairingPayloadDecoder.HelloPayload;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.Agreement;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.AuthFailure;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.FailureCode;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.PreparedViewer;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.VerifiedHostCommit;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.VerifiedHostConfirmation;

/** PRIVATE standalone JVM tests. No storage acknowledgements, reducer, transport or Android proof. */
public final class ViewerPairingAuthenticatorTest {
    private static final String FIXTURE_SHA256 = "7d8a58cd34400271d0c68ac1e263450c4ad4978337ae1bb87246362a6d0ec06a";
    private static final UUID OTHER_ID = UUID.fromString("99999999-8888-7777-6666-555555555555");
    private static Map<String, byte[]> fixtures;
    private static int assertions;
    private ViewerPairingAuthenticatorTest() { }

    public static void main(String[] arguments) throws Exception {
        check(arguments.length == 1, "explicit hash-checked public fixture path required");
        fixtures = load(Paths.get(arguments[0]));
        testActualSwiftViewerAgreementAndHostMessages();
        testGeneratedViewerUsesItsActualFullSignedTranscript();
        testRetainedViewerBindsEveryLocalUnsignedField();
        testHostHelloIdentityAuthenticationAndLowOrderRefusals();
        testConfirmationAndCommitBindingRefusals();
        testProofOwnershipAndStructuralSecretRetention();
        testMalformedAndRedactedSurfaces();
        System.out.println("Viewer authentication public fixture assertions: " + assertions);
    }

    private static void testActualSwiftViewerAgreementAndHostMessages() throws Exception {
        PreparedViewer prepared = retainedViewer();
        equal(data("hello.viewer.payload"), prepared.helloPayload(), "verified retained local full hello preserved");
        Agreement agreement = ViewerPairingAuthenticator.acceptHost(prepared, hostHello());
        check(agreement.pairID().equals(id("derived.pair-id-text")), "actual Swift pair ID");
        check(agreement.commitID().equals(id("derived.commit-id-text")), "actual Swift commit ID");
        check(agreement.viewerDeviceID().equals(id("input.viewer-device-id")) && agreement.hostDeviceID().equals(id("input.host-device-id")), "exact local/remote identities");
        check(agreement.hostDisplayName().equals("Test Mac"), "host name preserved");
        equal(data("derived.transcript-hash"), agreement.transcriptHash(), "actual full signed transcript");
        equal(data("derived.host-signing-public-key"), agreement.hostSigningPublicKey(), "actual host key");
        VerifiedHostConfirmation confirmation = agreement.authenticateHostConfirmation(hostConfirmation());
        verifyConstructedViewerConfirmation(agreement.constructUnsentViewerConfirmation(confirmation));
        VerifiedHostCommit proposal = agreement.authenticateHostCommit(hostCommit("proposal"), Phase.PROPOSAL);
        check(proposal.phase() == Phase.PROPOSAL, "authenticated proposal phase");
        verifyConstructedViewerCommit(agreement.constructUnsentViewerCommit(proposal), "acknowledgement");
        VerifiedHostCommit completion = agreement.authenticateHostCommit(hostCommit("completion"), Phase.COMPLETION);
        verifyConstructedViewerCommit(agreement.constructUnsentViewerCommit(completion), "activationAcknowledgement");
        // Repeated cryptographic verification is allowed; it is NOT durable recovery or
        // out-of-order acceptance. A future reducer must separately enforce persist-before-send.
        agreement.authenticateHostConfirmation(hostConfirmation());
        agreement.authenticateHostCommit(hostCommit("proposal"), Phase.PROPOSAL);
        byte[] hash = agreement.transcriptHash(); hash[0] ^= 1;
        byte[] key = agreement.hostSigningPublicKey(); key[0] ^= 1;
        equal(data("derived.transcript-hash"), agreement.transcriptHash(), "agreement transcript defensive copy");
        equal(data("derived.host-signing-public-key"), agreement.hostSigningPublicKey(), "agreement peer key defensive copy");
    }

    private static void verifyConstructedViewerConfirmation(Confirmation message) throws Exception {
        ConfirmationPayload decoded = confirmation(PairingCanonicalCodec.confirmationPayload(message));
        ConfirmationPayload reference = confirmation(data("confirmation.viewer.payload"));
        equal(data("confirmation.viewer.unsigned"), PairingCanonicalCodec.unsignedConfirmation(decoded.canonicalFields()), "constructed viewer confirmation unsigned");
        equal(reference.confirmationTag(), decoded.confirmationTag(), "independent actual Swift confirmation MAC");
        check(BouncyCastlePairingCrypto.ed25519Verify(data("derived.viewer-signing-public-key"),
                PairingCanonicalCodec.confirmationSignatureInput(decoded.canonicalMessage()), decoded.signature()), "constructed viewer confirmation signature valid");
        // No signature-byte equality: original Swift signatures may be randomized.
    }

    private static void verifyConstructedViewerCommit(Commit message, String phase) throws Exception {
        CommitPayload decoded = commit(PairingCanonicalCodec.commitPayload(message));
        CommitPayload reference = commit(data("commit." + phase + ".payload"));
        equal(data("commit." + phase + ".unsigned"), PairingCanonicalCodec.unsignedCommit(decoded.canonicalFields()), "constructed viewer commit unsigned");
        equal(reference.commitTag(), decoded.commitTag(), "independent actual Swift commit MAC");
        check(decoded.phase() == reference.phase(), "constructed viewer commit role/phase");
        check(BouncyCastlePairingCrypto.ed25519Verify(data("derived.viewer-signing-public-key"),
                PairingCanonicalCodec.commitSignatureInput(decoded.canonicalMessage()), decoded.signature()), "constructed viewer commit signature valid");
    }

    private static void testGeneratedViewerUsesItsActualFullSignedTranscript() throws Exception {
        PreparedViewer prepared = ViewerPairingAuthenticator.prepare(id("input.viewer-device-id"), "Test iPhone",
                data("input.viewer-signing-seed"), data("input.invitation-secret"), data("input.viewer-ephemeral-private"), data("input.viewer-nonce"));
        HelloPayload local = hello(prepared.helloPayload());
        equal(data("hello.viewer.unsigned"), PairingCanonicalCodec.unsignedHello(local.canonicalFields()), "generated local unsigned fields");
        equal(hello(data("hello.viewer.payload")).authenticationTag(), local.authenticationTag(), "generated local MAC");
        check(BouncyCastlePairingCrypto.ed25519Verify(local.signingPublicKey(), PairingCanonicalCodec.helloSignatureInput(local.canonicalMessage()), local.signature()), "generated local signature valid");
        Agreement agreement = ViewerPairingAuthenticator.acceptHost(prepared, hostHello());
        equal(BouncyCastlePairingCrypto.sha256(PairingCanonicalCodec.transcriptInput(hostHello().canonicalMessage(), local.canonicalMessage())),
                agreement.transcriptHash(), "fresh agreement binds ACTUAL full local signature");
        // A different valid local signature changes the transcript; no fixture-root equality is inferred.
    }

    private static void testRetainedViewerBindsEveryLocalUnsignedField() throws Exception {
        byte[] payload = data("hello.viewer.payload");
        String[][] scalarChanges = { { "deviceID", quoted(OTHER_ID.toString()) }, { "displayName", quoted("PUBLIC-SENTINEL") }, { "role", quoted("host") } };
        for (String[] change : scalarChanges) {
            HelloPayload changed = hello(replace(payload, change[0], change[1]));
            refused(FailureCode.IDENTITY_MISMATCH, () -> retainedViewer(changed));
        }
        HelloPayload local = hello(payload);
        String[] fields = { "signingPublicKey", "ephemeralKeyAgreementPublicKey", "nonce" };
        byte[][] values = { local.signingPublicKey(), local.ephemeralKeyAgreementPublicKey(), local.nonce() };
        for (int i = 0; i < fields.length; i++) {
            HelloPayload changed = hello(replace(payload, fields[i], quoted(base64(flipped(values[i])))));
            refused(FailureCode.IDENTITY_MISMATCH, () -> retainedViewer(changed));
        }
        for (String field : new String[] { "authenticationTag", "signature" }) {
            byte[] value = field.equals("authenticationTag") ? local.authenticationTag() : local.signature();
            HelloPayload changed = hello(replace(payload, field, quoted(base64(flipped(value)))));
            refused(FailureCode.AUTHENTICATION_FAILED, () -> retainedViewer(changed));
        }
        refused(FailureCode.IDENTITY_MISMATCH, () -> ViewerPairingAuthenticator.authenticateRetainedLocalHello(
                OTHER_ID, "Test iPhone", data("input.viewer-signing-seed"), data("input.invitation-secret"),
                data("input.viewer-ephemeral-private"), data("input.viewer-nonce"), local));
        refused(FailureCode.AUTHENTICATION_FAILED, () -> ViewerPairingAuthenticator.authenticateRetainedLocalHello(
                id("input.viewer-device-id"), "Test iPhone", data("input.viewer-signing-seed"), flipped(data("input.invitation-secret")),
                data("input.viewer-ephemeral-private"), data("input.viewer-nonce"), local));
    }

    private static void testHostHelloIdentityAuthenticationAndLowOrderRefusals() throws Exception {
        PreparedViewer prepared = retainedViewer();
        byte[] payload = data("hello.host.payload");
        HelloPayload host = hostHello();
        refused(FailureCode.ROLE_CONFLICT, () -> ViewerPairingAuthenticator.acceptHost(prepared,
                hello(replace(payload, "role", quoted("viewer")))));
        refused(FailureCode.ROLE_CONFLICT, () -> ViewerPairingAuthenticator.acceptHost(prepared,
                hello(replace(payload, "deviceID", quoted(id("input.viewer-device-id").toString())))));
        refused(FailureCode.IDENTITY_MISMATCH, () -> ViewerPairingAuthenticator.acceptHost(prepared,
                hello(replace(payload, "signingPublicKey", quoted(base64(prepared.signingPublicKey()))))));
        for (String field : new String[] { "authenticationTag", "signature", "nonce", "ephemeralKeyAgreementPublicKey" }) {
            byte[] value = field.equals("authenticationTag") ? host.authenticationTag() : field.equals("signature") ? host.signature()
                    : field.equals("nonce") ? host.nonce() : host.ephemeralKeyAgreementPublicKey();
            HelloPayload changed = hello(replace(payload, field, quoted(base64(flipped(value)))));
            refused(FailureCode.AUTHENTICATION_FAILED, () -> ViewerPairingAuthenticator.acceptHost(prepared, changed));
        }
        PreparedViewer wrongPSK = ViewerPairingAuthenticator.prepare(id("input.viewer-device-id"), "Test iPhone",
                data("input.viewer-signing-seed"), flipped(data("input.invitation-secret")), data("input.viewer-ephemeral-private"), data("input.viewer-nonce"));
        refused(FailureCode.AUTHENTICATION_FAILED, () -> ViewerPairingAuthenticator.acceptHost(wrongPSK, host));
        for (int point : new int[] { 0, 1 }) {
            byte[] lowOrder = new byte[32]; lowOrder[0] = (byte) point;
            HelloPayload authenticatedLowOrder = signedPublicHostHello(lowOrder);
            refused(FailureCode.AUTHENTICATION_FAILED, () -> ViewerPairingAuthenticator.acceptHost(prepared, authenticatedLowOrder));
        }
    }

    private static HelloPayload signedPublicHostHello(byte[] publicPoint) throws Exception {
        HelloPayload reference = hostHello();
        HelloFields fields = new HelloFields(1, reference.deviceID(), Role.HOST, reference.displayName(), reference.signingPublicKey(), publicPoint, reference.nonce());
        byte[] tag = BouncyCastlePairingCrypto.hmacSha256(data("input.invitation-secret"), PairingCanonicalCodec.helloPskInput(fields));
        byte[] signature = BouncyCastlePairingCrypto.ed25519Sign(data("input.host-signing-seed"),
                PairingCanonicalCodec.helloSignatureInput(new Hello(fields, tag, new byte[64])));
        return hello(PairingCanonicalCodec.helloPayload(new Hello(fields, tag, signature)));
    }

    private static void testConfirmationAndCommitBindingRefusals() throws Exception {
        Agreement agreement = ViewerPairingAuthenticator.acceptHost(retainedViewer(), hostHello());
        byte[] confirmation = data("confirmation.host.payload");
        for (String field : new String[] { "pairID", "senderDeviceID", "recipientDeviceID" }) {
            ConfirmationPayload changed = confirmation(replace(confirmation, field, quoted(OTHER_ID.toString())));
            refused(FailureCode.TRANSCRIPT_MISMATCH, () -> agreement.authenticateHostConfirmation(changed));
        }
        refused(FailureCode.TRANSCRIPT_MISMATCH, () -> agreement.authenticateHostConfirmation(
                confirmation(replace(confirmation, "senderRole", quoted("viewer")))));
        refused(FailureCode.TRANSCRIPT_MISMATCH, () -> agreement.authenticateHostConfirmation(
                confirmation(replace(confirmation, "transcriptHash", quoted(base64(flipped(data("derived.transcript-hash"))))))));
        for (String field : new String[] { "confirmationTag", "signature" }) {
            ConfirmationPayload reference = hostConfirmation();
            byte[] value = field.equals("confirmationTag") ? reference.confirmationTag() : reference.signature();
            ConfirmationPayload changed = confirmation(replace(confirmation, field, quoted(base64(flipped(value)))));
            refused(FailureCode.AUTHENTICATION_FAILED, () -> agreement.authenticateHostConfirmation(changed));
        }
        byte[] proposal = data("commit.proposal.payload");
        for (String field : new String[] { "pairID", "commitID", "senderDeviceID", "recipientDeviceID" }) {
            CommitPayload changed = commit(replace(proposal, field, quoted(OTHER_ID.toString())));
            refused(FailureCode.INVALID_COMMIT, () -> agreement.authenticateHostCommit(changed, Phase.PROPOSAL));
        }
        refused(FailureCode.INVALID_COMMIT, () -> agreement.authenticateHostCommit(hostCommit("completion"), Phase.PROPOSAL));
        refused(FailureCode.INVALID_COMMIT, () -> agreement.authenticateHostCommit(hostCommit("proposal"), Phase.COMPLETION));
        refused(FailureCode.INVALID_COMMIT, () -> agreement.authenticateHostCommit(hostCommit("acknowledgement"), Phase.ACKNOWLEDGEMENT));
        refused(FailureCode.INVALID_COMMIT, () -> agreement.authenticateHostCommit(hostCommit("activationAcknowledgement"), Phase.ACTIVATION_ACKNOWLEDGEMENT));
        CommitPayload changedHash = commit(replace(proposal, "transcriptHash", quoted(base64(flipped(data("derived.transcript-hash"))))));
        refused(FailureCode.INVALID_COMMIT, () -> agreement.authenticateHostCommit(changedHash, Phase.PROPOSAL));
        for (String field : new String[] { "commitTag", "signature" }) {
            CommitPayload reference = hostCommit("proposal");
            byte[] value = field.equals("commitTag") ? reference.commitTag() : reference.signature();
            CommitPayload changed = commit(replace(proposal, field, quoted(base64(flipped(value)))));
            refused(FailureCode.AUTHENTICATION_FAILED, () -> agreement.authenticateHostCommit(changed, Phase.PROPOSAL));
        }
    }

    private static void testProofOwnershipAndStructuralSecretRetention() throws Exception {
        PreparedViewer prepared = retainedViewer();
        Agreement first = ViewerPairingAuthenticator.acceptHost(prepared, hostHello());
        Agreement second = ViewerPairingAuthenticator.acceptHost(prepared, hostHello());
        check(first.pairID().equals(second.pairID()), "identical logical agreement fixture");
        VerifiedHostConfirmation confirmation = first.authenticateHostConfirmation(hostConfirmation());
        VerifiedHostCommit proposal = first.authenticateHostCommit(hostCommit("proposal"), Phase.PROPOSAL);
        refused(FailureCode.IDENTITY_MISMATCH, () -> second.constructUnsentViewerConfirmation(confirmation));
        refused(FailureCode.IDENTITY_MISMATCH, () -> second.constructUnsentViewerCommit(proposal));
        Class<?> identity = Class.forName(ViewerPairingAuthenticator.class.getName() + "$SigningIdentity");
        Set<String> identityFields = new HashSet<>();
        for (Field field : identity.getDeclaredFields()) {
            check(Modifier.isPrivate(field.getModifiers()) && Modifier.isFinal(field.getModifiers()), "private immutable signing identity fields");
            identityFields.add(field.getName());
        }
        check(identityFields.equals(new HashSet<>(Arrays.asList("deviceID", "seed", "publicKey"))), "agreement signing identity excludes bootstrap secret fields");
        for (Field field : Agreement.class.getDeclaredFields()) {
            check(!field.getType().getSimpleName().equals("Material") && !field.getType().equals(PreparedViewer.class), "agreement has no bootstrap owner reference");
        }
        // This inspects structure only; no reflection reads secret values and no JVM wipe claim.
        check(first.toString().equals("<redacted Beluga viewer cryptographic agreement>"), "agreement redacted");
        check(prepared.toString().equals("<redacted prepared Beluga viewer hello>"), "participant redacted");
        check(!confirmation.toString().contains(first.hostDeviceID().toString()) && !proposal.toString().contains("Test Mac"), "proofs redacted");
    }

    private static void testMalformedAndRedactedSurfaces() throws Exception {
        byte[] seed = data("input.viewer-signing-seed"), secret = data("input.invitation-secret"), ephemeral = data("input.viewer-ephemeral-private"), nonce = data("input.viewer-nonce");
        for (byte[] bad : new byte[][] { null, new byte[0], new byte[31], new byte[33] }) {
            refused(FailureCode.MALFORMED_INPUT, () -> ViewerPairingAuthenticator.prepare(id("input.viewer-device-id"), "PUBLIC-SENTINEL", bad, secret, ephemeral, nonce));
        }
        refused(FailureCode.MALFORMED_INPUT, () -> ViewerPairingAuthenticator.prepare(new UUID(0, 0), "Test iPhone", seed, secret, ephemeral, nonce));
        refused(FailureCode.MALFORMED_INPUT, () -> ViewerPairingAuthenticator.prepare(id("input.viewer-device-id"), " ", seed, secret, ephemeral, nonce));
        refused(FailureCode.MALFORMED_INPUT, () -> ViewerPairingAuthenticator.prepare(id("input.viewer-device-id"),
                new String(new char[] { 0xD800 }), seed, secret, ephemeral, nonce));
        String unicodeName = "Unicode \u00e9";
        PreparedViewer unicode = ViewerPairingAuthenticator.prepare(id("input.viewer-device-id"), unicodeName, seed, secret, ephemeral, nonce);
        HelloPayload unicodeHello = hello(unicode.helloPayload());
        check(unicodeHello.displayName().equals(unicodeName), "derivative Unicode name preserved by unchanged authentication core");
        equal(BouncyCastlePairingCrypto.hmacSha256(secret, PairingCanonicalCodec.helloPskInput(unicodeHello.canonicalFields())),
                unicodeHello.authenticationTag(), "Unicode unsigned name is covered by hello MAC");
        check(BouncyCastlePairingCrypto.ed25519Verify(unicodeHello.signingPublicKey(),
                PairingCanonicalCodec.helloSignatureInput(unicodeHello.canonicalMessage()), unicodeHello.signature()),
                "Unicode signed name is covered by hello signature");
        Agreement unicodeAgreement = ViewerPairingAuthenticator.acceptHost(unicode, hostHello());
        equal(BouncyCastlePairingCrypto.sha256(PairingCanonicalCodec.transcriptInput(hostHello().canonicalMessage(), unicodeHello.canonicalMessage())),
                unicodeAgreement.transcriptHash(), "Unicode agreement uses actual signed full local hello");
        refused(FailureCode.MALFORMED_INPUT, () -> ViewerPairingAuthenticator.prepare(id("input.viewer-device-id"), "Test iPhone", seed, new byte[19], ephemeral, nonce));
        refused(FailureCode.MALFORMED_INPUT, () -> ViewerPairingAuthenticator.prepare(id("input.viewer-device-id"), "Test iPhone", seed, secret, new byte[31], nonce));
        refused(FailureCode.MALFORMED_INPUT, () -> ViewerPairingAuthenticator.prepare(id("input.viewer-device-id"), "Test iPhone", seed, secret, ephemeral, new byte[31]));
        refused(FailureCode.MALFORMED_INPUT, () -> ViewerPairingAuthenticator.acceptHost(null, hostHello()));
        refused(FailureCode.MALFORMED_INPUT, () -> ViewerPairingAuthenticator.acceptHost(retainedViewer(), null));
        Agreement agreement = ViewerPairingAuthenticator.acceptHost(retainedViewer(), hostHello());
        refused(FailureCode.MALFORMED_INPUT, () -> agreement.authenticateHostConfirmation(null));
        refused(FailureCode.MALFORMED_INPUT, () -> agreement.authenticateHostCommit(hostCommit("proposal"), null));
        refused(FailureCode.IDENTITY_MISMATCH, () -> agreement.constructUnsentViewerConfirmation(null));
        refused(FailureCode.IDENTITY_MISMATCH, () -> agreement.constructUnsentViewerCommit(null));
    }

    private static PreparedViewer retainedViewer() throws Exception { return retainedViewer(hello(data("hello.viewer.payload"))); }
    private static PreparedViewer retainedViewer(HelloPayload hello) throws Exception {
        return ViewerPairingAuthenticator.authenticateRetainedLocalHello(id("input.viewer-device-id"), "Test iPhone",
                data("input.viewer-signing-seed"), data("input.invitation-secret"), data("input.viewer-ephemeral-private"), data("input.viewer-nonce"), hello);
    }
    private static HelloPayload hostHello() throws Exception { return hello(data("hello.host.payload")); }
    private static ConfirmationPayload hostConfirmation() throws Exception { return confirmation(data("confirmation.host.payload")); }
    private static CommitPayload hostCommit(String phase) throws Exception { return commit(data("commit." + phase + ".payload")); }
    private static HelloPayload hello(byte[] bytes) throws Exception { return (HelloPayload) PairingPayloadDecoder.decode(bytes); }
    private static ConfirmationPayload confirmation(byte[] bytes) throws Exception { return (ConfirmationPayload) PairingPayloadDecoder.decode(bytes); }
    private static CommitPayload commit(byte[] bytes) throws Exception { return (CommitPayload) PairingPayloadDecoder.decode(bytes); }
    private static byte[] data(String name) { byte[] bytes = fixtures.get(name); check(bytes != null, "exact fixture name"); return bytes.clone(); }
    private static UUID id(String name) { return UUID.fromString(new String(data(name), StandardCharsets.US_ASCII)); }
    private static byte[] flipped(byte[] data) { byte[] changed = data.clone(); changed[0] ^= 1; return changed; }
    private static String base64(byte[] bytes) { return Base64.getEncoder().encodeToString(bytes); }
    private static String quoted(String text) { check(text.indexOf('"') < 0 && text.indexOf('\\') < 0, "simple synthetic scalar"); return "\"" + text + "\""; }
    private static byte[] replace(byte[] bytes, String key, String scalar) {
        String text = new String(bytes, StandardCharsets.US_ASCII);
        Matcher found = Pattern.compile("\"" + Pattern.quote(key) + "\":(?:\"[^\"]*\"|1)").matcher(text);
        check(found.find(), "synthetic field present"); int start = found.start(), end = found.end();
        check(!found.find(), "synthetic field unique");
        return (text.substring(0, start) + "\"" + key + "\":" + scalar + text.substring(end)).getBytes(StandardCharsets.US_ASCII);
    }
    private static Map<String, byte[]> load(Path path) throws Exception {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try (InputStream file = Files.newInputStream(path)) {
            byte[] chunk = new byte[4096]; int read;
            while ((read = file.read(chunk)) != -1) { check(out.size() + read <= 128 * 1024, "bounded public fixture"); out.write(chunk, 0, read); }
        }
        byte[] bytes = out.toByteArray();
        StringBuilder digest = new StringBuilder();
        for (byte value : MessageDigest.getInstance("SHA-256").digest(bytes)) digest.append(String.format(Locale.ROOT, "%02x", value & 255));
        check(digest.toString().equals(FIXTURE_SHA256), "independently pinned actual Swift fixture SHA");
        for (byte value : bytes) check(value >= 0, "ASCII public fixture");
        String text = new String(bytes, StandardCharsets.US_ASCII);
        check(text.startsWith("# beluga.public-test-pairing-crypto.v1\n") && text.endsWith("\n"), "exact fixture schema");
        Map<String, byte[]> parsed = new TreeMap<>(); String last = "";
        for (String line : text.split("\n")) {
            if (line.startsWith("#")) continue;
            String[] fields = line.split("\t", -1);
            check(fields.length == 2 && fields[0].matches("[A-Za-z0-9.-]{1,80}") && fields[0].compareTo(last) > 0, "unique bounded sorted fixture names");
            byte[] value = Base64.getDecoder().decode(fields[1]);
            check(value.length > 0 && value.length <= 8192 && base64(value).equals(fields[1]), "bounded canonical fixture bytes");
            check(parsed.put(fields[0], value) == null, "unique fixture row"); last = fields[0];
        }
        check(parsed.size() == 45, "exact digest-bound fixture count");
        return parsed;
    }
    private interface Checked { void run() throws Exception; }
    private static void refused(FailureCode code, Checked operation) throws Exception {
        try { operation.run(); throw new AssertionError("expected viewer auth refusal"); }
        catch (AuthFailure failure) {
            check(failure.code() == code, "exact failure category");
            check(failure.getCause() == null && failure.getSuppressed().length == 0, "no upstream diagnostics");
            check(failure.getMessage().equals("Beluga viewer authentication refused: " + code.name()), "fixed redacted failure");
            check(!failure.toString().contains("PUBLIC-SENTINEL"), "input absent from failure");
        }
    }
    private static void equal(byte[] first, byte[] second, String label) { check(Arrays.equals(first, second), label); }
    private static void check(boolean condition, String label) { assertions++; if (!condition) throw new AssertionError(label); }
}
