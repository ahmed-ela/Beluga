package com.elamin.beluga.protocol;

import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Pattern;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Commit;
import com.elamin.beluga.protocol.PairingCanonicalCodec.CommitFields;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Confirmation;
import com.elamin.beluga.protocol.PairingCanonicalCodec.ConfirmationFields;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Hello;
import com.elamin.beluga.protocol.PairingCanonicalCodec.HelloFields;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Phase;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Role;

/**
 * PRIVATE strict, structural v1 plaintext decoder. This does not authenticate a peer,
 * accept an invitation, advance persistence, handle an envelope, or open a connection.
 * Names use the explicit Foundation-26.5.1-25F80 profile, not universal OS Unicode parity.
 * Canonical serialization and domain framing remain solely in PairingCanonicalCodec.
 */
public final class PairingPayloadDecoder {
    public static final int MAXIMUM_PLAINTEXT_BYTES = PairingCanonicalCodec.MAXIMUM_ENCODED_BYTES;
    private static final String ERROR = "Invalid Beluga v1 pairing payload";
    private static final int MAXIMUM_OBJECT_FIELDS = 10;
    private static final int MAXIMUM_STRING_CHARACTERS = 256;
    private static final Pattern UUID_SHAPE = Pattern.compile(
            "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}");
    private static final Set<String> HELLO_KEYS = keys("protocolVersion", "deviceID", "role",
            "signingPublicKey", "ephemeralKeyAgreementPublicKey", "nonce", "authenticationTag", "signature");
    private static final Set<String> CONFIRMATION_KEYS = keys("protocolVersion", "pairID", "senderDeviceID",
            "senderRole", "recipientDeviceID", "transcriptHash", "confirmationTag", "signature");
    private static final Set<String> COMMIT_KEYS = keys("protocolVersion", "pairID", "commitID", "senderDeviceID",
            "senderRole", "recipientDeviceID", "transcriptHash", "phase", "commitTag", "signature");
    private PairingPayloadDecoder() { }

    /** A fixed diagnostic with no JSON, names, key bytes, upstream cause or parser location. */
    public static final class DecodeFailure extends Exception {
        private static final long serialVersionUID = 1L;
        private DecodeFailure() { super(ERROR); }
    }

    public enum Kind { HELLO, CONFIRMATION, COMMIT }

    /** Closed, immutable typed result; parsed maps and raw input never escape. */
    public abstract static class Payload {
        private final Kind kind;
        private Payload(Kind kind) { this.kind = kind; }
        public final Kind kind() { return kind; }
        @Override public final String toString() { return "<redacted Beluga pairing payload>"; }
    }

    public static final class HelloPayload extends Payload {
        private final UUID deviceID;
        private final Role role;
        private final String displayName;
        private final byte[] signingPublicKey, ephemeralKeyAgreementPublicKey, nonce, authenticationTag, signature;
        private final HelloFields fields;
        private final Hello message;
        private HelloPayload(UUID deviceID, Role role, String displayName, byte[] signingPublicKey,
                byte[] ephemeralKeyAgreementPublicKey, byte[] nonce, byte[] authenticationTag, byte[] signature) {
            super(Kind.HELLO);
            this.deviceID = deviceID; this.role = role; this.displayName = displayName;
            this.signingPublicKey = signingPublicKey.clone();
            this.ephemeralKeyAgreementPublicKey = ephemeralKeyAgreementPublicKey.clone();
            this.nonce = nonce.clone(); this.authenticationTag = authenticationTag.clone(); this.signature = signature.clone();
            fields = new HelloFields(1, deviceID, role, displayName, signingPublicKey, ephemeralKeyAgreementPublicKey, nonce);
            message = new Hello(fields, authenticationTag, signature);
        }
        public int protocolVersion() { return 1; }
        public UUID deviceID() { return deviceID; }
        public Role role() { return role; }
        public String displayName() { return displayName; }
        public byte[] signingPublicKey() { return signingPublicKey.clone(); }
        public byte[] ephemeralKeyAgreementPublicKey() { return ephemeralKeyAgreementPublicKey.clone(); }
        public byte[] nonce() { return nonce.clone(); }
        public byte[] authenticationTag() { return authenticationTag.clone(); }
        public byte[] signature() { return signature.clone(); }
        public HelloFields canonicalFields() { return fields; }
        public Hello canonicalMessage() { return message; }
    }

    public static final class ConfirmationPayload extends Payload {
        private final UUID pairID, senderDeviceID, recipientDeviceID;
        private final Role senderRole;
        private final byte[] transcriptHash, confirmationTag, signature;
        private final ConfirmationFields fields;
        private final Confirmation message;
        private ConfirmationPayload(UUID pairID, UUID senderDeviceID, Role senderRole, UUID recipientDeviceID,
                byte[] transcriptHash, byte[] confirmationTag, byte[] signature) {
            super(Kind.CONFIRMATION);
            this.pairID = pairID; this.senderDeviceID = senderDeviceID; this.senderRole = senderRole;
            this.recipientDeviceID = recipientDeviceID;
            this.transcriptHash = transcriptHash.clone(); this.confirmationTag = confirmationTag.clone(); this.signature = signature.clone();
            fields = new ConfirmationFields(1, pairID, senderDeviceID, senderRole, recipientDeviceID, transcriptHash);
            message = new Confirmation(fields, confirmationTag, signature);
        }
        public int protocolVersion() { return 1; }
        public UUID pairID() { return pairID; }
        public UUID senderDeviceID() { return senderDeviceID; }
        public Role senderRole() { return senderRole; }
        public UUID recipientDeviceID() { return recipientDeviceID; }
        public byte[] transcriptHash() { return transcriptHash.clone(); }
        public byte[] confirmationTag() { return confirmationTag.clone(); }
        public byte[] signature() { return signature.clone(); }
        public ConfirmationFields canonicalFields() { return fields; }
        public Confirmation canonicalMessage() { return message; }
    }

    public static final class CommitPayload extends Payload {
        private final UUID pairID, commitID, senderDeviceID, recipientDeviceID;
        private final Role senderRole;
        private final Phase phase;
        private final byte[] transcriptHash, commitTag, signature;
        private final CommitFields fields;
        private final Commit message;
        private CommitPayload(UUID pairID, UUID commitID, UUID senderDeviceID, Role senderRole, UUID recipientDeviceID,
                byte[] transcriptHash, Phase phase, byte[] commitTag, byte[] signature) {
            super(Kind.COMMIT);
            this.pairID = pairID; this.commitID = commitID; this.senderDeviceID = senderDeviceID;
            this.senderRole = senderRole; this.recipientDeviceID = recipientDeviceID; this.phase = phase;
            this.transcriptHash = transcriptHash.clone(); this.commitTag = commitTag.clone(); this.signature = signature.clone();
            fields = new CommitFields(1, pairID, commitID, senderDeviceID, senderRole, recipientDeviceID, transcriptHash, phase);
            message = new Commit(fields, commitTag, signature);
        }
        public int protocolVersion() { return 1; }
        public UUID pairID() { return pairID; }
        public UUID commitID() { return commitID; }
        public UUID senderDeviceID() { return senderDeviceID; }
        public Role senderRole() { return senderRole; }
        public UUID recipientDeviceID() { return recipientDeviceID; }
        public Phase phase() { return phase; }
        public byte[] transcriptHash() { return transcriptHash.clone(); }
        public byte[] commitTag() { return commitTag.clone(); }
        public byte[] signature() { return signature.clone(); }
        public CommitFields canonicalFields() { return fields; }
        public Commit canonicalMessage() { return message; }
    }

    /** Only structurally admits one current plaintext payload. Authentication is REQUIRED later. */
    public static Payload decode(byte[] plaintext) throws DecodeFailure {
        if (plaintext == null || plaintext.length == 0 || plaintext.length > MAXIMUM_PLAINTEXT_BYTES) throw refused();
        byte[] owned = plaintext.clone();
        try {
            String text = StandardCharsets.UTF_8.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(owned)).toString();
            Map<String, Object> root = new Parser(text).root();
            String kind = string(root, "kind");
            if (!root.keySet().equals(keys("kind", kind))) throw refused();
            Map<String, Object> body = object(root.get(kind));
            if ("hello".equals(kind)) {
                Set<String> admitted = new HashSet<>(HELLO_KEYS);
                if (body.containsKey("displayName")) admitted.add("displayName");
                schema(body, admitted);
                String name = null;
                if (body.get("displayName") != null) name = string(body, "displayName");
                return new HelloPayload(uuid(body, "deviceID"), role(body, "role"), name,
                        bytes(body, "signingPublicKey", 32), bytes(body, "ephemeralKeyAgreementPublicKey", 32),
                        bytes(body, "nonce", 32), bytes(body, "authenticationTag", 32), bytes(body, "signature", 64));
            }
            if ("confirmation".equals(kind)) {
                schema(body, CONFIRMATION_KEYS);
                return new ConfirmationPayload(uuid(body, "pairID"), uuid(body, "senderDeviceID"),
                        role(body, "senderRole"), uuid(body, "recipientDeviceID"), bytes(body, "transcriptHash", 32),
                        bytes(body, "confirmationTag", 32), bytes(body, "signature", 64));
            }
            if ("commit".equals(kind)) {
                schema(body, COMMIT_KEYS);
                return new CommitPayload(uuid(body, "pairID"), uuid(body, "commitID"), uuid(body, "senderDeviceID"),
                        role(body, "senderRole"), uuid(body, "recipientDeviceID"), bytes(body, "transcriptHash", 32),
                        phase(body), bytes(body, "commitTag", 32), bytes(body, "signature", 64));
            }
            throw refused();
        } catch (CharacterCodingException | IllegalArgumentException ignored) {
            throw refused();
        } finally {
            Arrays.fill(owned, (byte) 0);
        }
    }

    private static Set<String> keys(String... names) {
        return Collections.unmodifiableSet(new HashSet<>(Arrays.asList(names)));
    }
    private static void schema(Map<String, Object> body, Set<String> admitted) throws DecodeFailure {
        if (!body.keySet().equals(admitted) || !Integer.valueOf(1).equals(body.get("protocolVersion"))) throw refused();
    }
    @SuppressWarnings("unchecked") // Only our parser can make a Map; keys are decoded Strings.
    private static Map<String, Object> object(Object value) throws DecodeFailure {
        if (!(value instanceof Map)) throw refused();
        return (Map<String, Object>) value;
    }
    private static String string(Map<String, Object> object, String key) throws DecodeFailure {
        Object value = object.get(key);
        if (!(value instanceof String)) throw refused();
        return (String) value;
    }
    private static UUID uuid(Map<String, Object> body, String key) throws DecodeFailure {
        String text = string(body, key);
        if (!UUID_SHAPE.matcher(text).matches()) throw refused();
        UUID id = UUID.fromString(text);
        if (id.getMostSignificantBits() == 0 && id.getLeastSignificantBits() == 0) throw refused();
        return id;
    }
    private static Role role(Map<String, Object> body, String key) throws DecodeFailure {
        String value = string(body, key);
        if ("host".equals(value)) return Role.HOST;
        if ("viewer".equals(value)) return Role.VIEWER;
        throw refused();
    }
    private static Phase phase(Map<String, Object> body) throws DecodeFailure {
        String value = string(body, "phase");
        if ("proposal".equals(value)) return Phase.PROPOSAL;
        if ("acknowledgement".equals(value)) return Phase.ACKNOWLEDGEMENT;
        if ("completion".equals(value)) return Phase.COMPLETION;
        if ("activationAcknowledgement".equals(value)) return Phase.ACTIVATION_ACKNOWLEDGEMENT;
        throw refused();
    }

    /** Fixed-length standard Base64 DATA decoding, not a cryptographic primitive or encoder. */
    private static byte[] bytes(Map<String, Object> body, String key, int length) throws DecodeFailure {
        String value = string(body, key);
        int padding = (3 - length % 3) % 3;
        int encoded = ((length + 2) / 3) * 4;
        if (value.length() != encoded) throw refused();
        for (int i = encoded - padding; i < encoded; i++) if (value.charAt(i) != '=') throw refused();
        byte[] result = new byte[length];
        int out = 0;
        for (int i = 0; i < encoded; i += 4) {
            int a = sextet(value.charAt(i)), b = sextet(value.charAt(i + 1));
            int c = i + 2 < encoded - padding ? sextet(value.charAt(i + 2)) : 0;
            int d = i + 3 < encoded - padding ? sextet(value.charAt(i + 3)) : 0;
            result[out++] = (byte) ((a << 2) | (b >>> 4));
            if (out < length) result[out++] = (byte) ((b << 4) | (c >>> 2));
            if (out < length) result[out++] = (byte) ((c << 6) | d);
            if (i + 4 == encoded && ((padding == 2 && (b & 15) != 0) || (padding == 1 && (c & 3) != 0))) throw refused();
        }
        if (out != length) throw refused();
        return result;
    }
    private static int sextet(char c) throws DecodeFailure {
        if (c >= 'A' && c <= 'Z') return c - 'A';
        if (c >= 'a' && c <= 'z') return c - 'a' + 26;
        if (c >= '0' && c <= '9') return c - '0' + 52;
        if (c == '+') return 62;
        if (c == '/') return 63;
        throw refused();
    }
    private static DecodeFailure refused() { return new DecodeFailure(); }

    /** Bounded current-schema JSON subset: objects, strict scalar strings, null and integer 1. */
    private static final class Parser {
        private final String text;
        private int offset;
        private Parser(String text) { this.text = text; }
        private Map<String, Object> root() throws DecodeFailure {
            whitespace();
            Map<String, Object> value = object(1);
            whitespace();
            if (offset != text.length()) throw refused();
            return value;
        }
        private Map<String, Object> object(int depth) throws DecodeFailure {
            if (depth > 2) throw refused();
            take('{'); whitespace();
            Map<String, Object> values = new LinkedHashMap<>();
            if (consume('}')) return values;
            while (true) {
                if (values.size() >= MAXIMUM_OBJECT_FIELDS) throw refused();
                String key = quoted();
                if (key.length() > 64 || values.containsKey(key)) throw refused();
                whitespace(); take(':'); whitespace();
                values.put(key, value(depth));
                whitespace();
                if (consume('}')) return values;
                take(','); whitespace();
            }
        }
        private Object value(int depth) throws DecodeFailure {
            if (offset >= text.length()) throw refused();
            char c = text.charAt(offset);
            if (c == '{') return object(depth + 1);
            if (c == '"') return quoted();
            if (text.startsWith("null", offset)) { offset += 4; return null; }
            if (c == '1') { offset++; return Integer.valueOf(1); }
            // Arrays, booleans and all other numeric forms cannot enter this schema.
            throw refused();
        }
        private String quoted() throws DecodeFailure {
            take('"');
            StringBuilder value = new StringBuilder();
            while (offset < text.length()) {
                char c = text.charAt(offset++);
                if (c == '"') return value.toString();
                if (c < 0x20) throw refused();
                boolean escaped = false;
                if (c == '\\') {
                    if (offset >= text.length()) throw refused();
                    char escape = text.charAt(offset++);
                    escaped = true;
                    switch (escape) {
                        case '"': c = '"'; break;
                        case '\\': c = '\\'; break;
                        case '/': c = '/'; break;
                        case 'b': c = '\b'; break;
                        case 'f': c = '\f'; break;
                        case 'n': c = '\n'; break;
                        case 'r': c = '\r'; break;
                        case 't': c = '\t'; break;
                        case 'u': c = unicodeCodeUnit(); break;
                        default: throw refused();
                    }
                }
                if (Character.isHighSurrogate(c)) {
                    char low;
                    if (escaped) {
                        if (!consume('\\') || !consume('u')) throw refused();
                        low = unicodeCodeUnit();
                    } else {
                        if (offset >= text.length()) throw refused();
                        low = text.charAt(offset++);
                    }
                    if (!Character.isLowSurrogate(low)) throw refused();
                    appendBounded(value, c); appendBounded(value, low);
                } else {
                    if (Character.isLowSurrogate(c)) throw refused();
                    appendBounded(value, c);
                }
            }
            throw refused();
        }
        private void appendBounded(StringBuilder value, char c) throws DecodeFailure {
            if (value.length() >= MAXIMUM_STRING_CHARACTERS) throw refused();
            value.append(c);
        }
        private char unicodeCodeUnit() throws DecodeFailure {
            if (offset > text.length() - 4) throw refused();
            int value = 0;
            for (int i = 0; i < 4; i++) {
                char c = text.charAt(offset++);
                int digit;
                if (c >= '0' && c <= '9') digit = c - '0';
                else if (c >= 'a' && c <= 'f') digit = c - 'a' + 10;
                else if (c >= 'A' && c <= 'F') digit = c - 'A' + 10;
                else throw refused();
                value = (value << 4) | digit;
            }
            return (char) value;
        }
        private void whitespace() {
            while (offset < text.length()) {
                char c = text.charAt(offset);
                if (c != ' ' && c != '\n' && c != '\r' && c != '\t') return;
                offset++;
            }
        }
        private boolean consume(char c) {
            if (offset >= text.length() || text.charAt(offset) != c) return false;
            offset++; return true;
        }
        private void take(char c) throws DecodeFailure { if (!consume(c)) throw refused(); }
    }
}
