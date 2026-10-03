package com.elamin.beluga.protocol;

import java.io.ByteArrayOutputStream;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.UUID;

/**
 * Private outbound-only v1 codec draft. Encoding is NOT authentication or pairing.
 * No decoder, cryptographic primitive, invitation, persistent identity, or transport lives here.
 * Display names use the explicit Foundation-26.5.1-25F80 reference profile, not Java categories.
 * The profile's exact source/runtime/fixture provenance lives in PairingDisplayNamePolicy.
 */
public final class PairingCanonicalCodec {
    public static final int MAXIMUM_ENCODED_BYTES = 8192;
    private static final int VERSION = 1;
    private static final String BASE64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    private PairingCanonicalCodec() { }

    public enum Role {
        HOST("host"), VIEWER("viewer");
        private final String wire;
        Role(String wire) { this.wire = wire; }
    }

    public enum Phase {
        PROPOSAL("proposal", Role.HOST),
        ACKNOWLEDGEMENT("acknowledgement", Role.VIEWER),
        COMPLETION("completion", Role.HOST),
        ACTIVATION_ACKNOWLEDGEMENT("activationAcknowledgement", Role.VIEWER);
        private final String wire;
        private final Role sender;
        Phase(String wire, Role sender) { this.wire = wire; this.sender = sender; }
    }

    public static final class HelloFields {
        private final UUID deviceID;
        private final Role role;
        private final String displayName;
        private final byte[] signingPublicKey;
        private final byte[] ephemeralKeyAgreementPublicKey;
        private final byte[] nonce;

        public HelloFields(int protocolVersion, UUID deviceID, Role role, String displayName,
                byte[] signingPublicKey, byte[] ephemeralKeyAgreementPublicKey, byte[] nonce) {
            version(protocolVersion);
            this.deviceID = nonzero(deviceID);
            this.role = present(role);
            this.displayName = PairingDisplayNamePolicy.validate(displayName);
            this.signingPublicKey = copyExact(signingPublicKey, 32);
            this.ephemeralKeyAgreementPublicKey = copyExact(ephemeralKeyAgreementPublicKey, 32);
            this.nonce = copyExact(nonce, 32);
        }

        @Override public String toString() { return "<redacted Beluga pairing hello fields>"; }
    }

    public static final class Hello {
        private final HelloFields fields;
        private final byte[] authenticationTag;
        private final byte[] signature;
        public Hello(HelloFields fields, byte[] authenticationTag, byte[] signature) {
            this.fields = present(fields);
            this.authenticationTag = copyExact(authenticationTag, 32);
            this.signature = copyExact(signature, 64);
        }
        @Override public String toString() { return "<redacted Beluga pairing hello>"; }
    }

    public static final class ConfirmationFields {
        private final UUID pairID;
        private final UUID senderDeviceID;
        private final Role senderRole;
        private final UUID recipientDeviceID;
        private final byte[] transcriptHash;
        public ConfirmationFields(int protocolVersion, UUID pairID, UUID senderDeviceID,
                Role senderRole, UUID recipientDeviceID, byte[] transcriptHash) {
            version(protocolVersion);
            this.pairID = nonzero(pairID);
            this.senderDeviceID = nonzero(senderDeviceID);
            this.senderRole = present(senderRole);
            this.recipientDeviceID = nonzero(recipientDeviceID);
            if (senderDeviceID.equals(recipientDeviceID)) throw invalid();
            this.transcriptHash = copyExact(transcriptHash, 32);
        }
        @Override public String toString() { return "<redacted Beluga pairing confirmation fields>"; }
    }

    public static final class Confirmation {
        private final ConfirmationFields fields;
        private final byte[] confirmationTag;
        private final byte[] signature;
        public Confirmation(ConfirmationFields fields, byte[] confirmationTag, byte[] signature) {
            this.fields = present(fields);
            this.confirmationTag = copyExact(confirmationTag, 32);
            this.signature = copyExact(signature, 64);
        }
        @Override public String toString() { return "<redacted Beluga pairing confirmation>"; }
    }

    public static final class CommitFields {
        private final ConfirmationFields common;
        private final UUID commitID;
        private final Phase phase;
        public CommitFields(int protocolVersion, UUID pairID, UUID commitID,
                UUID senderDeviceID, Role senderRole, UUID recipientDeviceID,
                byte[] transcriptHash, Phase phase) {
            common = new ConfirmationFields(protocolVersion, pairID, senderDeviceID,
                    senderRole, recipientDeviceID, transcriptHash);
            this.commitID = nonzero(commitID);
            this.phase = present(phase);
            if (phase.sender != senderRole) throw invalid();
        }
        @Override public String toString() { return "<redacted Beluga pairing commit fields>"; }
    }

    public static final class Commit {
        private final CommitFields fields;
        private final byte[] commitTag;
        private final byte[] signature;
        public Commit(CommitFields fields, byte[] commitTag, byte[] signature) {
            this.fields = present(fields);
            this.commitTag = copyExact(commitTag, 32);
            this.signature = copyExact(signature, 64);
        }
        @Override public String toString() { return "<redacted Beluga pairing commit>"; }
    }

    public static byte[] unsignedHello(HelloFields value) {
        HelloFields f = present(value);
        return bytes("{" + field("deviceID", uuid(f.deviceID)) + nameField(f.displayName)
                + "," + field("ephemeralKeyAgreementPublicKey", base64(f.ephemeralKeyAgreementPublicKey))
                + "," + field("nonce", base64(f.nonce)) + ",\"protocolVersion\":1,"
                + field("role", f.role.wire) + "," + field("signingPublicKey", base64(f.signingPublicKey)) + "}");
    }

    public static byte[] fullHello(Hello value) {
        Hello h = present(value);
        HelloFields f = h.fields;
        return bytes("{" + field("authenticationTag", base64(h.authenticationTag)) + ","
                + field("deviceID", uuid(f.deviceID)) + nameField(f.displayName) + ","
                + field("ephemeralKeyAgreementPublicKey", base64(f.ephemeralKeyAgreementPublicKey))
                + "," + field("nonce", base64(f.nonce)) + ",\"protocolVersion\":1,"
                + field("role", f.role.wire) + "," + field("signature", base64(h.signature))
                + "," + field("signingPublicKey", base64(f.signingPublicKey)) + "}");
    }

    public static byte[] unsignedConfirmation(ConfirmationFields value) {
        ConfirmationFields f = present(value);
        return bytes("{" + confirmationBody(f) + "}");
    }

    public static byte[] fullConfirmation(Confirmation value) {
        Confirmation c = present(value);
        ConfirmationFields f = c.fields;
        return bytes("{" + field("confirmationTag", base64(c.confirmationTag)) + ","
                + confirmationPrefix(f) + "," + field("signature", base64(c.signature))
                + "," + field("transcriptHash", base64(f.transcriptHash)) + "}");
    }

    public static byte[] unsignedCommit(CommitFields value) {
        CommitFields f = present(value);
        return bytes("{" + field("commitID", uuid(f.commitID)) + ","
                + commitBody(f) + "}");
    }

    public static byte[] fullCommit(Commit value) {
        Commit c = present(value);
        CommitFields f = c.fields;
        return bytes("{" + field("commitID", uuid(f.commitID)) + ","
                + field("commitTag", base64(c.commitTag)) + "," + commitPrefix(f)
                + "," + field("signature", base64(c.signature)) + ","
                + field("transcriptHash", base64(f.common.transcriptHash)) + "}");
    }

    public static byte[] helloPayload(Hello hello) {
        return bytes("{\"hello\":" + text(fullHello(hello)) + ",\"kind\":\"hello\"}");
    }

    public static byte[] confirmationPayload(Confirmation confirmation) {
        return bytes("{\"confirmation\":" + text(fullConfirmation(confirmation))
                + ",\"kind\":\"confirmation\"}");
    }

    public static byte[] commitPayload(Commit commit) {
        return bytes("{\"commit\":" + text(fullCommit(commit)) + ",\"kind\":\"commit\"}");
    }

    /** Full hello objects, including tags/signatures, always host first, viewer second. */
    public static byte[] transcript(Hello host, Hello viewer) {
        present(host); present(viewer);
        if (host.fields.role != Role.HOST || viewer.fields.role != Role.VIEWER
                || host.fields.deviceID.equals(viewer.fields.deviceID)) throw invalid();
        return bytes("{\"host\":" + text(fullHello(host)) + ",\"viewer\":"
                + text(fullHello(viewer)) + "}");
    }

    public static byte[] helloPskInput(HelloFields fields) {
        return frame("Hello.PSK", unsignedHello(fields));
    }
    public static byte[] helloSignatureInput(Hello hello) {
        present(hello);
        return frame("Hello.Signature", unsignedHello(hello.fields), hello.authenticationTag);
    }
    public static byte[] transcriptInput(Hello host, Hello viewer) {
        return frame("Transcript", transcript(host, viewer));
    }
    public static byte[] confirmationMacInput(ConfirmationFields fields) {
        return frame("Confirmation.MAC", unsignedConfirmation(fields));
    }
    public static byte[] confirmationSignatureInput(Confirmation confirmation) {
        present(confirmation);
        return frame("Confirmation.Signature", unsignedConfirmation(confirmation.fields),
                confirmation.confirmationTag);
    }
    public static byte[] commitMacInput(CommitFields fields) {
        return frame("Commit.MAC", unsignedCommit(fields));
    }
    public static byte[] commitSignatureInput(Commit commit) {
        present(commit);
        return frame("Commit.Signature", unsignedCommit(commit.fields), commit.commitTag);
    }

    private static String confirmationPrefix(ConfirmationFields f) {
        return field("pairID", uuid(f.pairID)) + ",\"protocolVersion\":1,"
                + field("recipientDeviceID", uuid(f.recipientDeviceID)) + ","
                + field("senderDeviceID", uuid(f.senderDeviceID)) + ","
                + field("senderRole", f.senderRole.wire);
    }
    private static String confirmationBody(ConfirmationFields f) {
        return confirmationPrefix(f) + "," + field("transcriptHash", base64(f.transcriptHash));
    }
    private static String commitPrefix(CommitFields f) {
        return field("pairID", uuid(f.common.pairID)) + "," + field("phase", f.phase.wire)
                + ",\"protocolVersion\":1," + field("recipientDeviceID", uuid(f.common.recipientDeviceID))
                + "," + field("senderDeviceID", uuid(f.common.senderDeviceID))
                + "," + field("senderRole", f.common.senderRole.wire);
    }
    private static String commitBody(CommitFields f) {
        return commitPrefix(f) + "," + field("transcriptHash", base64(f.common.transcriptHash));
    }
    private static String nameField(String name) {
        return name == null ? "" : "," + field("displayName", name);
    }
    // Only fixed schema values and policy-validated names reach this encoder.
    private static String field(String key, String value) { return quote(key) + ":" + quote(value); }
    private static String quote(String value) {
        StringBuilder result = new StringBuilder(value.length() + 2).append('"');
        for (int i = 0; i < value.length(); i++) {
            char c = value.charAt(i);
            if (c < 0x20 || Character.isLowSurrogate(c)) throw invalid();
            if (Character.isHighSurrogate(c)) {
                if (i + 1 == value.length() || !Character.isLowSurrogate(value.charAt(i + 1))) throw invalid();
                result.append(c).append(value.charAt(++i));
                continue;
            }
            if (c == '"' || c == '\\') result.append('\\');
            result.append(c);
        }
        return result.append('"').toString();
    }
    private static String uuid(UUID id) { return id.toString().toUpperCase(Locale.ROOT); }
    private static UUID nonzero(UUID id) {
        present(id);
        if (id.getMostSignificantBits() == 0 && id.getLeastSignificantBits() == 0) throw invalid();
        return id;
    }
    private static void version(int version) { if (version != VERSION) throw invalid(); }
    private static byte[] copyExact(byte[] value, int length) {
        if (value == null || value.length != length) throw invalid();
        return value.clone();
    }
    private static <T> T present(T value) { if (value == null) throw invalid(); return value; }
    // Bounded standard Base64 serialization, not a cryptographic primitive. Avoid
    // java.util.Base64's Android API26 dependency for the existing API23 app floor.
    private static String base64(byte[] value) {
        if (value.length > 64) throw invalid();
        StringBuilder encoded = new StringBuilder(((value.length + 2) / 3) * 4);
        for (int i = 0; i < value.length; i += 3) {
            int remaining = value.length - i;
            int bits = (value[i] & 255) << 16;
            if (remaining > 1) bits |= (value[i + 1] & 255) << 8;
            if (remaining > 2) bits |= value[i + 2] & 255;
            encoded.append(BASE64_ALPHABET.charAt((bits >>> 18) & 63));
            encoded.append(BASE64_ALPHABET.charAt((bits >>> 12) & 63));
            encoded.append(remaining > 1 ? BASE64_ALPHABET.charAt((bits >>> 6) & 63) : '=');
            encoded.append(remaining > 2 ? BASE64_ALPHABET.charAt(bits & 63) : '=');
        }
        return encoded.toString();
    }
    private static String text(byte[] value) { return new String(value, StandardCharsets.UTF_8); }
    private static byte[] bytes(String value) {
        byte[] encoded = value.getBytes(StandardCharsets.UTF_8);
        if (encoded.length > MAXIMUM_ENCODED_BYTES) throw invalid();
        return encoded;
    }
    private static byte[] frame(String fixedSuffix, byte[]... pieces) {
        byte[] domain = ("AudioStreamer.Pairing." + fixedSuffix + ".v1").getBytes(StandardCharsets.US_ASCII);
        long total = domain.length + 1L;
        for (byte[] piece : pieces) total += 8L + piece.length;
        if (total > MAXIMUM_ENCODED_BYTES) throw invalid();
        ByteArrayOutputStream output = new ByteArrayOutputStream((int) total);
        output.write(domain, 0, domain.length);
        output.write(0);
        for (byte[] piece : pieces) {
            byte[] length = ByteBuffer.allocate(8).putLong(piece.length).array();
            output.write(length, 0, length.length);
            output.write(piece, 0, piece.length);
        }
        return output.toByteArray();
    }
    private static IllegalArgumentException invalid() {
        return new IllegalArgumentException("Invalid Beluga v1 pairing codec input");
    }
}
