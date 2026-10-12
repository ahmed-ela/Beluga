package com.elamin.beluga.protocol;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;
import com.elamin.beluga.protocol.BouncyCastlePairingCrypto.CryptoFailure;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Role;
import com.elamin.beluga.protocol.PairingPayloadDecoder.CommitPayload;
import com.elamin.beluga.protocol.PairingPayloadDecoder.ConfirmationPayload;
import com.elamin.beluga.protocol.PairingPayloadDecoder.DecodeFailure;
import com.elamin.beluga.protocol.PairingPayloadDecoder.HelloPayload;
import com.elamin.beluga.protocol.PairingPayloadDecoder.Payload;

/**
 * Invitation-encrypted v1 signal framing for ONE admitted peer cycle, not a socket/client.
 * A transport must close this instance on failure/uncertainty and after commit. Peer replacement
 * requires a fresh instance only after an independently validated peer-left event and drain.
 * Envelope possession authenticates invitation transport only; the pairing authenticator and
 * persist-before-send reducer remain REQUIRED. This component never claims paired/connected.
 */
public final class PairingBootstrapEnvelopeCodec implements AutoCloseable {
    public static final int MAXIMUM_WIRE_BYTES = 90_000;
    public static final int MAXIMUM_ENVELOPE_BYTES = 65_536;
    public static final long MAXIMUM_SEQUENCE = 2_147_483_647L;
    private static final int MAXIMUM_COMBINED_BYTES = PairingPayloadDecoder.MAXIMUM_PLAINTEXT_BYTES + 28;
    private static final String BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    private static final String CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
    private static final byte[] SALT = ascii("AudioStreamer.RemoteSession.HKDF-SHA256.v1\0");
    private static final byte[] AAD_DOMAIN = ascii("AudioStreamer.Signaling.Envelope.AAD.v1\0");
    private final Role role;
    private final String channel;
    private final byte[] admission, sendingKey, receivingKey;
    private final NonceSource nonces;
    private long nextSequence;
    private long highestReceived = -1;
    private long receivedBitmap;
    private boolean closed;

    public enum FailureCode {
        CLOSED, INVALID_WIRE, UNSUPPORTED_VERSION, WRONG_CHANNEL, UNEXPECTED_DIRECTION,
        INVALID_PAYLOAD, AUTHENTICATION_FAILED, PROVIDER_FAILED, SEQUENCE_EXHAUSTED,
        REPLAYED_SEQUENCE, SEQUENCE_OUTSIDE_WINDOW
    }
    public static final class EnvelopeFailure extends Exception {
        private static final long serialVersionUID = 1L;
        private final FailureCode code;
        private EnvelopeFailure(FailureCode code) {
            super("Beluga pairing envelope refused: " + code.name()); this.code = code;
        }
        public FailureCode code() { return code; }
    }

    /** Production entropy is owned here; no caller-provided nonce is accepted by this API. */
    public static PairingBootstrapEnvelopeCodec create(PairingInvitation invitation, Role role)
            throws EnvelopeFailure {
        try {
            SecureRandom random = new SecureRandom();
            return createForFixture(invitation, role, () -> { byte[] nonce = new byte[12]; random.nextBytes(nonce); return nonce; });
        } catch (RuntimeException ignored) { throw failure(FailureCode.PROVIDER_FAILED); }
    }

    // Package-only entropy seam for independent captured synthetic fixtures, not a nonce policy.
    interface NonceSource { byte[] nextNonce(); }
    static PairingBootstrapEnvelopeCodec createForFixture(PairingInvitation invitation, Role role,
            NonceSource nonces) throws EnvelopeFailure {
        return createForFixture(invitation, role, nonces, 0);
    }
    static PairingBootstrapEnvelopeCodec createForFixture(PairingInvitation invitation, Role role,
            NonceSource nonces, long initialSequence) throws EnvelopeFailure {
        if (invitation == null || role == null || nonces == null) throw failure(FailureCode.INVALID_PAYLOAD);
        if (initialSequence < 0 || initialSequence > MAXIMUM_SEQUENCE) throw failure(FailureCode.INVALID_PAYLOAD);
        byte[] secret = null, channelBytes = null, admission = null, host = null, viewer = null;
        try {
            secret = invitationSecret(invitation);
            channelBytes = derive(secret, "rendezvous-channel");
            admission = derive(secret, "rendezvous-admission-proof");
            host = derive(secret, "signaling-host-to-viewer");
            viewer = derive(secret, "signaling-viewer-to-host");
            PairingBootstrapEnvelopeCodec result = new PairingBootstrapEnvelopeCodec(role, crockford(channelBytes), admission,
                    role == Role.HOST ? host : viewer, role == Role.HOST ? viewer : host, nonces);
            result.nextSequence = initialSequence;
            return result;
        } catch (CryptoFailure ignored) { throw failure(FailureCode.PROVIDER_FAILED); }
        finally { clear(secret); clear(channelBytes); clear(admission); clear(host); clear(viewer); }
    }

    private PairingBootstrapEnvelopeCodec(Role role, String channel, byte[] admission,
            byte[] sendingKey, byte[] receivingKey, NonceSource nonces) {
        this.role = role; this.channel = channel; this.admission = admission.clone();
        this.sendingKey = sendingKey.clone(); this.receivingKey = receivingKey.clone(); this.nonces = nonces;
    }

    /** Deliberate capability export for bounded upgrade headers only. Never URL/log/persist it. */
    public synchronized JoinHeaders copyJoinHeaders() throws EnvelopeFailure {
        requireOpen(); return new JoinHeaders(channel, wireRole(role), encodeBase64(admission, true));
    }
    public static final class JoinHeaders {
        private final String channel, role, admissionProof;
        private JoinHeaders(String channel, String role, String admissionProof) {
            this.channel = channel; this.role = role; this.admissionProof = admissionProof;
        }
        public String channelID() { return channel; }
        public String role() { return role; }
        public String admissionProofForUpgradeHeader() { return admissionProof; }
        @Override public String toString() { return "<redacted Beluga pairing upgrade headers>"; }
    }

    /** Returns a current-peer-cycle outbound signal. Does NOT authorize its durable send. */
    public synchronized Outbound seal(byte[] payloadBytes) throws EnvelopeFailure {
        requireOpen();
        Payload payload = payload(payloadBytes, role);
        if (nextSequence > MAXIMUM_SEQUENCE) throw failure(FailureCode.SEQUENCE_EXHAUSTED);
        byte[] plaintext = canonicalPayload(payload), nonce = null, combined = null;
        try {
            try { nonce = nonces.nextNonce(); }
            catch (RuntimeException ignored) { throw failure(FailureCode.PROVIDER_FAILED); }
            requireOpen();
            if (nonce == null || nonce.length != 12) throw failure(FailureCode.PROVIDER_FAILED);
            // Own a copy before provider use; only the component's production factory owns entropy.
            nonce = nonce.clone();
            long sequence = nextSequence;
            combined = BouncyCastlePairingCrypto.sealCombined(sendingKey, nonce, plaintext,
                    aad(channel, sendingDirection(), sequence));
            nextSequence++; // Reservations are never reclaimed on later framing/send failures.
            byte[] envelope = envelope(channel, sendingDirection(), sequence, combined);
            if (envelope.length > MAXIMUM_ENVELOPE_BYTES) throw failure(FailureCode.INVALID_PAYLOAD);
            byte[] wire = ascii("{\"envelope\":\"" + encodeBase64(envelope, true)
                    + "\",\"seq\":" + sequence + ",\"type\":\"signal\"}");
            if (wire.length > MAXIMUM_WIRE_BYTES) throw failure(FailureCode.INVALID_PAYLOAD);
            return new Outbound(sequence, wire);
        } catch (CryptoFailure ignored) { throw failure(FailureCode.PROVIDER_FAILED); }
        finally { clear(plaintext); clear(nonce); clear(combined); }
    }
    public static final class Outbound {
        private final long sequence;
        private final byte[] wire;
        private Outbound(long sequence, byte[] wire) { this.sequence = sequence; this.wire = wire.clone(); }
        public long sequence() { return sequence; }
        public byte[] copyWireBytes() { return wire.clone(); }
        @Override public String toString() { return "<redacted Beluga outbound pairing signal>"; }
    }

    /**
     * Opens one server-forwarded {type,from,seq,envelope} signal. Authentication precedes replay
     * admission; no failed message consumes replay state. The caller must retire/close on error,
     * matching Swift's terminal receive-loop policy, rather than continue a compromised socket.
     */
    public synchronized Signal open(byte[] forwardedWire) throws EnvelopeFailure {
        requireOpen();
        Map<String, Object> outer = parse(forwardedWire, MAXIMUM_WIRE_BYTES);
        exactKeys(outer, "type", "from", "seq", "envelope");
        if (!"signal".equals(string(outer, "type")) || !wireRole(opposite(role)).equals(string(outer, "from"))) {
            throw failure(FailureCode.INVALID_WIRE);
        }
        long sequence = number(outer, "seq");
        byte[] envelopeBytes = decodeBase64(string(outer, "envelope"), true, MAXIMUM_ENVELOPE_BYTES);
        byte[] combined = null, plaintext = null;
        try {
            Map<String, Object> envelope = parse(envelopeBytes, MAXIMUM_ENVELOPE_BYTES);
            exactKeys(envelope, "version", "channelID", "direction", "sequence", "ciphertext");
            if (number(envelope, "version") != 1) throw failure(FailureCode.UNSUPPORTED_VERSION);
            String envelopeChannel = string(envelope, "channelID");
            if (!channel.equals(envelopeChannel)) throw failure(FailureCode.WRONG_CHANNEL);
            String direction = string(envelope, "direction");
            if (!receivingDirection().equals(direction)) throw failure(FailureCode.UNEXPECTED_DIRECTION);
            if (number(envelope, "sequence") != sequence) throw failure(FailureCode.INVALID_WIRE);
            combined = decodeBase64(string(envelope, "ciphertext"), false, MAXIMUM_COMBINED_BYTES);
            if (combined.length < 28) throw failure(FailureCode.INVALID_WIRE);
            try {
                plaintext = BouncyCastlePairingCrypto.openCombined(receivingKey, combined, aad(channel, direction, sequence));
            } catch (CryptoFailure error) {
                throw failure(error.code() == BouncyCastlePairingCrypto.FailureCode.AUTHENTICATION_FAILED
                        ? FailureCode.AUTHENTICATION_FAILED : FailureCode.PROVIDER_FAILED);
            }
            Payload payload = payload(plaintext, opposite(role));
            acceptSequence(sequence);
            return new Signal(sequence, payload);
        } finally { clear(envelopeBytes); clear(combined); clear(plaintext); }
    }
    public static final class Signal {
        private final long sequence;
        private final Payload payload;
        private Signal(long sequence, Payload payload) { this.sequence = sequence; this.payload = payload; }
        public long sequence() { return sequence; }
        public Payload structurallyAdmittedPayload() { return payload; }
        @Override public String toString() { return "<redacted Beluga inbound pairing signal>"; }
    }

    /** No reset/reopen method: closing retires this cycle's cryptographic state. */
    @Override public synchronized void close() {
        if (closed) return;
        closed = true; clear(admission); clear(sendingKey); clear(receivingKey);
        receivedBitmap = 0; highestReceived = -1;
    }
    @Override public String toString() { return "<redacted Beluga pairing envelope codec>"; }

    private void requireOpen() throws EnvelopeFailure { if (closed) throw failure(FailureCode.CLOSED); }
    private String sendingDirection() { return role == Role.HOST ? "hostToViewer" : "viewerToHost"; }
    private String receivingDirection() { return role == Role.HOST ? "viewerToHost" : "hostToViewer"; }
    private static Role opposite(Role role) { return role == Role.HOST ? Role.VIEWER : Role.HOST; }
    private static String wireRole(Role role) { return role == Role.HOST ? "host" : "viewer"; }
    private void acceptSequence(long sequence) throws EnvelopeFailure {
        if (highestReceived < 0) { highestReceived = sequence; receivedBitmap = 1; return; }
        if (sequence > highestReceived) {
            long advance = sequence - highestReceived;
            receivedBitmap = advance >= 64 ? 1 : (receivedBitmap << (int) advance) | 1;
            highestReceived = sequence; return;
        }
        long age = highestReceived - sequence;
        if (age >= 64) throw failure(FailureCode.SEQUENCE_OUTSIDE_WINDOW);
        long mask = 1L << (int) age;
        if ((receivedBitmap & mask) != 0) throw failure(FailureCode.REPLAYED_SEQUENCE);
        receivedBitmap |= mask;
    }

    private static Payload payload(byte[] bytes, Role expected) throws EnvelopeFailure {
        try {
            Payload result = PairingPayloadDecoder.decode(bytes);
            Role actual;
            if (result instanceof HelloPayload) actual = ((HelloPayload) result).role();
            else if (result instanceof ConfirmationPayload) actual = ((ConfirmationPayload) result).senderRole();
            else if (result instanceof CommitPayload) actual = ((CommitPayload) result).senderRole();
            else throw failure(FailureCode.INVALID_PAYLOAD);
            if (actual != expected) throw failure(FailureCode.INVALID_PAYLOAD);
            return result;
        } catch (DecodeFailure | IllegalArgumentException ignored) { throw failure(FailureCode.INVALID_PAYLOAD); }
    }
    static byte[] canonicalPayload(Payload payload) {
        if (payload instanceof HelloPayload) return PairingCanonicalCodec.helloPayload(((HelloPayload) payload).canonicalMessage());
        if (payload instanceof ConfirmationPayload) return PairingCanonicalCodec.confirmationPayload(((ConfirmationPayload) payload).canonicalMessage());
        if (payload instanceof CommitPayload) return PairingCanonicalCodec.commitPayload(((CommitPayload) payload).canonicalMessage());
        throw new IllegalArgumentException("Invalid Beluga v1 pairing payload");
    }
    private static byte[] derive(byte[] secret, String info) throws CryptoFailure {
        return BouncyCastlePairingCrypto.hkdfSha256(secret, SALT, ascii(info), 32);
    }
    private static byte[] invitationSecret(PairingInvitation invitation) throws EnvelopeFailure {
        // The existing validated type exposes only its explicit canonical export, not raw bytes.
        // This transient String cannot be erased in a managed runtime; it is never retained here.
        String code = invitation.exportedCode();
        if (code.length() != 47) throw failure(FailureCode.INVALID_PAYLOAD);
        byte[] packet = new byte[25]; int accumulator = 0, bits = 0, written = 0, symbols = 0;
        try {
            for (int i = 0; i < code.length(); i++) {
                char c = code.charAt(i); if (c == '-') continue;
                int value = CROCKFORD.indexOf(c);
                if (value < 0 || ++symbols > 40) throw failure(FailureCode.INVALID_PAYLOAD);
                accumulator = (accumulator << 5) | value; bits += 5;
                if (bits >= 8) { bits -= 8; packet[written++] = (byte) (accumulator >>> bits); }
            }
            if (symbols != 40 || written != 25 || bits != 0 || packet[0] != 1) throw failure(FailureCode.INVALID_PAYLOAD);
            return Arrays.copyOfRange(packet, 1, 21);
        } finally { clear(packet); }
    }
    private static String crockford(byte[] bytes) {
        StringBuilder value = new StringBuilder(52); int accumulator = 0, bits = 0;
        for (byte b : bytes) {
            accumulator = (accumulator << 8) | (b & 255); bits += 8;
            while (bits >= 5) { bits -= 5; value.append(CROCKFORD.charAt((accumulator >>> bits) & 31)); }
        }
        if (bits > 0) value.append(CROCKFORD.charAt((accumulator << (5 - bits)) & 31));
        return value.toString();
    }
    private static byte[] aad(String channel, String direction, long sequence) {
        byte[] route = ascii(channel);
        ByteBuffer buffer = ByteBuffer.allocate(AAD_DOMAIN.length + 1 + route.length + 2 + 8);
        return buffer.put(AAD_DOMAIN).put((byte) 1).put(route).put((byte) 0)
                .put((byte) ("hostToViewer".equals(direction) ? 1 : 2)).putLong(sequence).array();
    }
    private static byte[] envelope(String channel, String direction, long sequence, byte[] combined) {
        return ascii("{\"channelID\":\"" + channel + "\",\"ciphertext\":\"" + encodeBase64(combined, false)
                + "\",\"direction\":\"" + direction + "\",\"sequence\":" + sequence + ",\"version\":1}");
    }

    // Small serialization codecs, not custom cryptography or an Android API26 Base64 dependency.
    static String encodeBase64(byte[] bytes, boolean url) {
        StringBuilder result = new StringBuilder(((bytes.length + 2) / 3) * 4);
        for (int i = 0; i < bytes.length; i += 3) {
            int remaining = bytes.length - i;
            int value = (bytes[i] & 255) << 16;
            if (remaining > 1) value |= (bytes[i + 1] & 255) << 8;
            if (remaining > 2) value |= bytes[i + 2] & 255;
            result.append(symbol((value >>> 18) & 63, url)).append(symbol((value >>> 12) & 63, url));
            if (remaining > 1) result.append(symbol((value >>> 6) & 63, url)); else if (!url) result.append('=');
            if (remaining > 2) result.append(symbol(value & 63, url)); else if (!url) result.append('=');
        }
        return result.toString();
    }
    private static char symbol(int value, boolean url) {
        char symbol = BASE64.charAt(value);
        return url && symbol == '+' ? '-' : url && symbol == '/' ? '_' : symbol;
    }
    static byte[] decodeBase64(String value, boolean url, int maximum) throws EnvelopeFailure {
        int length = value.length();
        if (length == 0 || length > ((maximum + 2) / 3) * 4 || length % 4 == 1) throw failure(FailureCode.INVALID_WIRE);
        if (!url && length % 4 != 0) throw failure(FailureCode.INVALID_WIRE);
        int padding = 0;
        if (!url) {
            if (value.charAt(length - 1) == '=') padding++;
            if (length > 1 && value.charAt(length - 2) == '=') padding++;
        }
        int symbols = length - padding;
        int decodedLength = symbols * 6 / 8;
        if (decodedLength > maximum || decodedLength == 0) throw failure(FailureCode.INVALID_WIRE);
        byte[] result = new byte[decodedLength]; int accumulator = 0, bits = 0, written = 0;
        boolean success = false;
        try {
            for (int i = 0; i < symbols; i++) {
                char c = value.charAt(i);
                if (url) { if (c == '-') c = '+'; else if (c == '_') c = '/'; else if (c == '+' || c == '/') throw failure(FailureCode.INVALID_WIRE); }
                int digit = BASE64.indexOf(c);
                if (digit < 0) throw failure(FailureCode.INVALID_WIRE);
                accumulator = (accumulator << 6) | digit; bits += 6;
                if (bits >= 8) { bits -= 8; if (written >= result.length) throw failure(FailureCode.INVALID_WIRE); result[written++] = (byte) (accumulator >>> bits); }
            }
            if (written != result.length || !encodeBase64(result, url).equals(value)) throw failure(FailureCode.INVALID_WIRE);
            success = true; return result;
        } finally { if (!success) clear(result); }
    }
    private static Map<String, Object> parse(byte[] input, int maximum) throws EnvelopeFailure {
        return parse(input, maximum, 5);
    }
    /** Separate six-field availability framing; bootstrap remains limited to five fields. */
    static Map<String, Object> parseAvailabilityWire(byte[] input, int maximum) throws EnvelopeFailure {
        return parse(input, maximum, 6);
    }
    private static Map<String, Object> parse(byte[] input, int maximum, int maximumFields) throws EnvelopeFailure {
        if (input == null || input.length == 0 || input.length > maximum) throw failure(FailureCode.INVALID_WIRE);
        byte[] owned = input.clone();
        try {
            for (byte b : owned) if (b < 0) throw failure(FailureCode.INVALID_WIRE);
            return new FlatParser(new String(owned, StandardCharsets.US_ASCII), maximumFields).object();
        } finally { clear(owned); }
    }
    private static void exactKeys(Map<String, Object> map, String... names) throws EnvelopeFailure {
        if (map.size() != names.length) throw failure(FailureCode.INVALID_WIRE);
        for (String name : names) if (!map.containsKey(name)) throw failure(FailureCode.INVALID_WIRE);
    }
    private static String string(Map<String, Object> map, String key) throws EnvelopeFailure {
        Object value = map.get(key); if (!(value instanceof String)) throw failure(FailureCode.INVALID_WIRE); return (String) value;
    }
    private static long number(Map<String, Object> map, String key) throws EnvelopeFailure {
        Object value = map.get(key); if (!(value instanceof Long)) throw failure(FailureCode.INVALID_WIRE); return ((Long) value).longValue();
    }
    private static final class FlatParser {
        private final String text; private final int maximumFields; private int offset;
        private FlatParser(String text, int maximumFields) { this.text = text; this.maximumFields = maximumFields; }
        Map<String, Object> object() throws EnvelopeFailure {
            whitespace(); take('{'); whitespace(); Map<String, Object> fields = new HashMap<>();
            if (!consume('}')) {
                while (true) {
                    if (fields.size() >= maximumFields) throw failure(FailureCode.INVALID_WIRE);
                    String key = quoted(32); if (fields.containsKey(key)) throw failure(FailureCode.INVALID_WIRE);
                    whitespace(); take(':'); whitespace();
                    Object value = offset < text.length() && text.charAt(offset) == '"' ? quoted(MAXIMUM_WIRE_BYTES) : unsignedNumber();
                    fields.put(key, value); whitespace();
                    if (consume('}')) break;
                    take(','); whitespace();
                }
            }
            whitespace(); if (offset != text.length()) throw failure(FailureCode.INVALID_WIRE); return fields;
        }
        private Long unsignedNumber() throws EnvelopeFailure {
            int start = offset; long result = 0;
            while (offset < text.length()) {
                char c = text.charAt(offset); if (c < '0' || c > '9') break;
                if (offset - start >= 10 || (offset > start && text.charAt(start) == '0')) throw failure(FailureCode.INVALID_WIRE);
                result = result * 10 + c - '0'; if (result > MAXIMUM_SEQUENCE) throw failure(FailureCode.INVALID_WIRE); offset++;
            }
            if (offset == start) throw failure(FailureCode.INVALID_WIRE); return Long.valueOf(result);
        }
        private String quoted(int maximum) throws EnvelopeFailure {
            take('"'); StringBuilder result = new StringBuilder();
            while (offset < text.length()) {
                char c = text.charAt(offset++); if (c == '"') return result.toString();
                if (c < 32) throw failure(FailureCode.INVALID_WIRE);
                if (c == '\\') {
                    if (offset >= text.length()) throw failure(FailureCode.INVALID_WIRE);
                    char escape = text.charAt(offset++);
                    switch (escape) {
                        case '"': c = '"'; break;
                        case '\\': c = '\\'; break;
                        case '/': c = '/'; break;
                        case 'b': c = '\b'; break;
                        case 'f': c = '\f'; break;
                        case 'n': c = '\n'; break;
                        case 'r': c = '\r'; break;
                        case 't': c = '\t'; break;
                        case 'u':
                            if (offset > text.length() - 4) throw failure(FailureCode.INVALID_WIRE);
                            int scalar = 0;
                            for (int i = 0; i < 4; i++) {
                                char digit = text.charAt(offset++);
                                int value = digit >= '0' && digit <= '9' ? digit - '0'
                                        : digit >= 'A' && digit <= 'F' ? digit - 'A' + 10
                                        : digit >= 'a' && digit <= 'f' ? digit - 'a' + 10 : -1;
                                if (value < 0) throw failure(FailureCode.INVALID_WIRE); scalar = (scalar << 4) | value;
                            }
                            if (scalar > 127) throw failure(FailureCode.INVALID_WIRE); c = (char) scalar; break;
                        default: throw failure(FailureCode.INVALID_WIRE);
                    }
                }
                if (result.length() >= maximum) throw failure(FailureCode.INVALID_WIRE); result.append(c);
            }
            throw failure(FailureCode.INVALID_WIRE);
        }
        private void whitespace() { while (offset < text.length() && " \t\r\n".indexOf(text.charAt(offset)) >= 0) offset++; }
        private boolean consume(char c) { if (offset < text.length() && text.charAt(offset) == c) { offset++; return true; } return false; }
        private void take(char c) throws EnvelopeFailure { if (!consume(c)) throw failure(FailureCode.INVALID_WIRE); }
    }
    private static byte[] ascii(String text) { return text.getBytes(StandardCharsets.US_ASCII); }
    private static EnvelopeFailure failure(FailureCode code) { return new EnvelopeFailure(code); }
    private static void clear(byte[] value) { if (value != null) Arrays.fill(value, (byte) 0); }
}
