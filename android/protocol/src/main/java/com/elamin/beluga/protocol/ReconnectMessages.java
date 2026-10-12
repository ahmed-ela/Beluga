package com.elamin.beluga.protocol;

import java.io.ByteArrayOutputStream;
import java.math.BigInteger;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.regex.Pattern;
import org.bouncycastle.util.encoders.Base64;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Role;

/** Closed v1 reconnect wire values. Structural decoding is never peer authentication. */
public final class ReconnectMessages {
    public static final int MAXIMUM_BYTES = 8192;
    private static final BigInteger MAXIMUM_UINT64 = new BigInteger("18446744073709551615");
    private static final Pattern UUID_SHAPE = Pattern.compile(
            "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}");
    private ReconnectMessages() { }

    public static final class DecodeFailure extends Exception {
        private static final long serialVersionUID = 1L;
        private DecodeFailure() { super("Invalid Beluga v1 reconnect payload"); }
    }

    public static final class Request {
        private final UUID pair, requester, target;
        private final String sequence;
        private final byte[] ephemeral, nonce, signature;
        public Request(int protocolVersion, UUID pairID, UUID requesterDeviceID, Role requesterRole,
                UUID targetDeviceID, String sequence, byte[] ephemeralKeyAgreementPublicKey,
                byte[] nonce, byte[] signature) {
            demand(protocolVersion == 1 && requesterRole == Role.VIEWER);
            pair = id(pairID); requester = id(requesterDeviceID); target = id(targetDeviceID);
            demand(!requester.equals(target)); this.sequence = positiveSequence(sequence);
            ephemeral = fixed(ephemeralKeyAgreementPublicKey, 32); this.nonce = fixed(nonce, 32);
            this.signature = fixed(signature, 64);
        }
        public int protocolVersion() { return 1; }
        public UUID pairID() { return pair; }
        public UUID requesterDeviceID() { return requester; }
        public Role requesterRole() { return Role.VIEWER; }
        public UUID targetDeviceID() { return target; }
        public String sequence() { return sequence; }
        public byte[] ephemeralKeyAgreementPublicKey() { return ephemeral.clone(); }
        public byte[] nonce() { return nonce.clone(); }
        public byte[] signature() { return signature.clone(); }
        @Override public String toString() { return "<redacted Beluga reconnect request>"; }
    }

    public static final class Response {
        private final UUID pair, requester, responder;
        private final String sequence;
        private final byte[] digest, ephemeral, nonce, signature;
        public Response(int protocolVersion, UUID pairID, UUID requesterDeviceID, UUID responderDeviceID,
                Role responderRole, String requestSequence, byte[] requestDigest,
                byte[] ephemeralKeyAgreementPublicKey, byte[] nonce, byte[] signature) {
            demand(protocolVersion == 1 && responderRole == Role.HOST);
            pair = id(pairID); requester = id(requesterDeviceID); responder = id(responderDeviceID);
            demand(!requester.equals(responder)); sequence = positiveSequence(requestSequence);
            digest = fixed(requestDigest, 32); ephemeral = fixed(ephemeralKeyAgreementPublicKey, 32);
            this.nonce = fixed(nonce, 32); this.signature = fixed(signature, 64);
        }
        public int protocolVersion() { return 1; }
        public UUID pairID() { return pair; }
        public UUID requesterDeviceID() { return requester; }
        public UUID responderDeviceID() { return responder; }
        public Role responderRole() { return Role.HOST; }
        public String requestSequence() { return sequence; }
        public byte[] requestDigest() { return digest.clone(); }
        public byte[] ephemeralKeyAgreementPublicKey() { return ephemeral.clone(); }
        public byte[] nonce() { return nonce.clone(); }
        public byte[] signature() { return signature.clone(); }
        @Override public String toString() { return "<redacted Beluga reconnect response>"; }
    }

    public enum Kind { RECONNECT_REQUEST, RECONNECT_RESPONSE }
    public static final class Payload {
        private final Request request;
        private final Response response;
        private Payload(Request request, Response response) { this.request = request; this.response = response; }
        public Kind kind() { return request == null ? Kind.RECONNECT_RESPONSE : Kind.RECONNECT_REQUEST; }
        public Request request() { return request; }
        public Response response() { return response; }
        @Override public String toString() { return "<redacted Beluga reconnect payload>"; }
    }

    public static byte[] unsignedRequest(Request value) {
        Request r = present(value);
        return ascii("{" + requestPrefix(r) + "," + field("targetDeviceID", uuid(r.target)) + "}");
    }
    public static byte[] fullRequest(Request value) {
        Request r = present(value);
        return ascii("{" + requestPrefix(r) + "," + field("signature", base64(r.signature))
                + "," + field("targetDeviceID", uuid(r.target)) + "}");
    }
    private static String requestPrefix(Request r) {
        return field("ephemeralKeyAgreementPublicKey", base64(r.ephemeral)) + ","
                + field("nonce", base64(r.nonce)) + "," + field("pairID", uuid(r.pair))
                + ",\"protocolVersion\":1," + field("requesterDeviceID", uuid(r.requester))
                + ",\"requesterRole\":\"viewer\",\"sequence\":" + r.sequence;
    }
    public static byte[] unsignedResponse(Response value) {
        return ascii("{" + responsePrefix(present(value)) + "}");
    }
    public static byte[] fullResponse(Response value) {
        Response r = present(value);
        return ascii("{" + responsePrefix(r) + "," + field("signature", base64(r.signature)) + "}");
    }
    private static String responsePrefix(Response r) {
        return field("ephemeralKeyAgreementPublicKey", base64(r.ephemeral)) + ","
                + field("nonce", base64(r.nonce)) + "," + field("pairID", uuid(r.pair))
                + ",\"protocolVersion\":1," + field("requestDigest", base64(r.digest))
                + ",\"requestSequence\":" + r.sequence + "," + field("requesterDeviceID", uuid(r.requester))
                + "," + field("responderDeviceID", uuid(r.responder)) + ",\"responderRole\":\"host\"";
    }
    public static byte[] requestPayload(Request request) {
        return ascii("{\"kind\":\"reconnectRequest\",\"reconnectRequest\":" + text(fullRequest(request)) + "}");
    }
    public static byte[] responsePayload(Response response) {
        return ascii("{\"kind\":\"reconnectResponse\",\"reconnectResponse\":" + text(fullResponse(response)) + "}");
    }
    public static byte[] requestSignatureInput(Request request) {
        return domain("AudioStreamer.Reconnect.Request.Signature.v1", unsignedRequest(request));
    }
    public static byte[] responseSignatureInput(Response response) {
        return domain("AudioStreamer.Reconnect.Response.Signature.v1", unsignedResponse(response));
    }
    public static byte[] transcriptInput(Request request, Response response) {
        return domain("AudioStreamer.Reconnect.Transcript.v1", ascii("{\"request\":"
                + text(fullRequest(request)) + ",\"response\":" + text(fullResponse(response)) + "}"));
    }

    public static Request decodeRequest(byte[] fullMessage) throws DecodeFailure {
        try { return request(parse(fullMessage, false)); }
        catch (IllegalArgumentException ignored) { throw refused(); }
    }
    public static Response decodeResponse(byte[] fullMessage) throws DecodeFailure {
        try { return response(parse(fullMessage, false)); }
        catch (IllegalArgumentException ignored) { throw refused(); }
    }
    public static Payload decodePayload(byte[] payload) throws DecodeFailure {
        Map<String, Object> root = parse(payload, true);
        String kind = string(root, "kind");
        if ("reconnectRequest".equals(kind)) {
            exactKeys(root, "kind", "reconnectRequest");
            return new Payload(request(object(root.get("reconnectRequest"))), null);
        }
        if ("reconnectResponse".equals(kind)) {
            exactKeys(root, "kind", "reconnectResponse");
            return new Payload(null, response(object(root.get("reconnectResponse"))));
        }
        throw refused();
    }
    private static Request request(Map<String, Object> fields) throws DecodeFailure {
        exactKeys(fields, "protocolVersion", "pairID", "requesterDeviceID", "requesterRole", "targetDeviceID",
                "sequence", "ephemeralKeyAgreementPublicKey", "nonce", "signature");
        version(fields); if (!"viewer".equals(string(fields, "requesterRole"))) throw refused();
        try {
            return new Request(1, uuid(fields, "pairID"), uuid(fields, "requesterDeviceID"), Role.VIEWER,
                    uuid(fields, "targetDeviceID"), number(fields, "sequence"), data(fields, "ephemeralKeyAgreementPublicKey", 32),
                    data(fields, "nonce", 32), data(fields, "signature", 64));
        } catch (IllegalArgumentException ignored) { throw refused(); }
    }
    private static Response response(Map<String, Object> fields) throws DecodeFailure {
        exactKeys(fields, "protocolVersion", "pairID", "requesterDeviceID", "responderDeviceID", "responderRole",
                "requestSequence", "requestDigest", "ephemeralKeyAgreementPublicKey", "nonce", "signature");
        version(fields); if (!"host".equals(string(fields, "responderRole"))) throw refused();
        try {
            return new Response(1, uuid(fields, "pairID"), uuid(fields, "requesterDeviceID"), uuid(fields, "responderDeviceID"),
                    Role.HOST, number(fields, "requestSequence"), data(fields, "requestDigest", 32),
                    data(fields, "ephemeralKeyAgreementPublicKey", 32), data(fields, "nonce", 32), data(fields, "signature", 64));
        } catch (IllegalArgumentException ignored) { throw refused(); }
    }

    // Small bounded ASCII schema parser; no generic framework or unsigned-to-floating conversion.
    private static Map<String, Object> parse(byte[] input, boolean wrapper) throws DecodeFailure {
        if (input == null || input.length == 0 || input.length > MAXIMUM_BYTES) throw refused();
        byte[] owned = input.clone();
        try {
            for (byte b : owned) if (b < 0) throw refused();
            Parser parser = new Parser(new String(owned, StandardCharsets.US_ASCII));
            Map<String, Object> result = parser.object(wrapper ? 1 : 0);
            parser.space(); if (parser.offset != parser.source.length()) throw refused();
            return result;
        } finally { Arrays.fill(owned, (byte) 0); }
    }
    private static final class Numeric {
        private final String value;
        private Numeric(String value) { this.value = value; }
    }
    private static final class Parser {
        private final String source; private int offset;
        private Parser(String source) { this.source = source; }
        private Map<String, Object> object(int remainingDepth) throws DecodeFailure {
            space(); take('{'); space(); Map<String, Object> result = new HashMap<>();
            if (!consume('}')) while (true) {
                if (result.size() >= 10) throw refused();
                String key = quoted(64); if (result.containsKey(key)) throw refused();
                space(); take(':'); space();
                Object value;
                if (peek('"')) value = quoted(128);
                else if (peek('{') && remainingDepth > 0) value = object(remainingDepth - 1);
                else value = numeric();
                result.put(key, value); space(); if (consume('}')) break;
                take(','); space();
            }
            return result;
        }
        private Numeric numeric() throws DecodeFailure {
            int start = offset;
            while (offset < source.length() && source.charAt(offset) >= '0' && source.charAt(offset) <= '9') {
                if (offset - start >= 20) throw refused(); offset++;
            }
            if (start == offset || offset - start > 1 && source.charAt(start) == '0') throw refused();
            String value = source.substring(start, offset);
            if (new BigInteger(value).compareTo(MAXIMUM_UINT64) > 0) throw refused();
            return new Numeric(value);
        }
        private String quoted(int maximum) throws DecodeFailure {
            take('"'); StringBuilder value = new StringBuilder(); boolean ended = false;
            while (offset < source.length()) {
                char c = source.charAt(offset++); if (c == '"') { ended = true; break; }
                if (c == '\\') {
                    if (offset == source.length()) throw refused(); char escaped = source.charAt(offset++);
                    if (escaped == '"' || escaped == '\\' || escaped == '/') c = escaped;
                    else if (escaped == 'u') {
                        if (offset + 4 > source.length()) throw refused(); int scalar = 0;
                        for (int i = 0; i < 4; i++) {
                            int digit = Character.digit(source.charAt(offset++), 16); if (digit < 0) throw refused();
                            scalar = (scalar << 4) | digit;
                        }
                        if (scalar < 0x20 || scalar > 0x7e) throw refused(); c = (char) scalar;
                    } else throw refused();
                }
                if (c < 0x20 || c > 0x7e || value.length() >= maximum) throw refused(); value.append(c);
            }
            if (!ended) throw refused(); return value.toString();
        }
        private void space() {
            while (offset < source.length()) {
                char c = source.charAt(offset); if (c != ' ' && c != '\t' && c != '\n' && c != '\r') break; offset++;
            }
        }
        private boolean peek(char expected) { return offset < source.length() && source.charAt(offset) == expected; }
        private boolean consume(char expected) { if (!peek(expected)) return false; offset++; return true; }
        private void take(char expected) throws DecodeFailure { if (!consume(expected)) throw refused(); }
    }
    @SuppressWarnings("unchecked")
    private static Map<String, Object> object(Object value) throws DecodeFailure {
        if (!(value instanceof Map<?, ?>)) throw refused(); return (Map<String, Object>) value;
    }
    private static void exactKeys(Map<String, Object> fields, String... names) throws DecodeFailure {
        if (fields.size() != names.length) throw refused();
        for (String name : names) if (!fields.containsKey(name)) throw refused();
    }
    private static String string(Map<String, Object> fields, String key) throws DecodeFailure {
        Object value = fields.get(key); if (!(value instanceof String)) throw refused(); return (String) value;
    }
    private static String number(Map<String, Object> fields, String key) throws DecodeFailure {
        Object value = fields.get(key); if (!(value instanceof Numeric)) throw refused(); return ((Numeric) value).value;
    }
    private static void version(Map<String, Object> fields) throws DecodeFailure {
        if (!"1".equals(number(fields, "protocolVersion"))) throw refused();
    }
    private static UUID uuid(Map<String, Object> fields, String key) throws DecodeFailure {
        String value = string(fields, key); if (!UUID_SHAPE.matcher(value).matches()) throw refused();
        try { return id(UUID.fromString(value)); } catch (IllegalArgumentException ignored) { throw refused(); }
    }
    private static byte[] data(Map<String, Object> fields, String key, int count) throws DecodeFailure {
        String value = string(fields, key);
        if (value.length() != ((count + 2) / 3) * 4) throw refused();
        byte[] decoded = null;
        try {
            decoded = Base64.decode(value);
            if (decoded.length != count || !base64(decoded).equals(value)) throw refused();
            return decoded;
        } catch (RuntimeException ignored) { throw refused(); }
        finally { if (decoded != null && decoded.length != count) Arrays.fill(decoded, (byte) 0); }
    }
    static byte[] domain(String label, byte[]... pieces) {
        ByteArrayOutputStream out = new ByteArrayOutputStream(); byte[] name = ascii(label);
        out.write(name, 0, name.length); out.write(0);
        for (byte[] piece : pieces) {
            demand(piece != null && piece.length <= MAXIMUM_BYTES);
            byte[] length = ByteBuffer.allocate(8).putLong(piece.length).array();
            out.write(length, 0, 8); out.write(piece, 0, piece.length);
        }
        return out.toByteArray();
    }
    static String base64(byte[] value) { return Base64.toBase64String(value); }
    static String positiveSequence(String value) {
        demand(value != null && value.length() > 0 && value.length() <= 20 && value.charAt(0) >= '1' && value.charAt(0) <= '9');
        for (int i = 0; i < value.length(); i++) demand(value.charAt(i) >= '0' && value.charAt(i) <= '9');
        demand(new BigInteger(value).compareTo(MAXIMUM_UINT64) <= 0); return value;
    }
    private static String field(String key, String value) { return "\"" + key + "\":\"" + value + "\""; }
    private static String uuid(UUID value) { return value.toString().toUpperCase(Locale.ROOT); }
    private static UUID id(UUID value) {
        demand(value != null && (value.getMostSignificantBits() != 0 || value.getLeastSignificantBits() != 0)); return value;
    }
    private static byte[] fixed(byte[] value, int length) { demand(value != null && value.length == length); return value.clone(); }
    private static <T> T present(T value) { demand(value != null); return value; }
    private static byte[] ascii(String value) {
        byte[] bytes = value.getBytes(StandardCharsets.US_ASCII); demand(bytes.length <= MAXIMUM_BYTES); return bytes;
    }
    private static String text(byte[] value) { return new String(value, StandardCharsets.US_ASCII); }
    private static void demand(boolean condition) { if (!condition) throw new IllegalArgumentException("Invalid Beluga v1 reconnect input"); }
    private static DecodeFailure refused() { return new DecodeFailure(); }
}
