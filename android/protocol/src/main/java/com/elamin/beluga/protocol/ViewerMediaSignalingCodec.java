package com.elamin.beluga.protocol;

import com.google.gson.Strictness;
import com.google.gson.stream.JsonReader;
import com.google.gson.stream.JsonToken;
import java.io.IOException;
import java.io.StringReader;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Calendar;
import java.util.Date;
import java.util.GregorianCalendar;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.TimeZone;
import java.util.UUID;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.AuthFailure;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.SessionCredential;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.SessionCredential.Direction;

/**
 * One-use viewer media AEAD/broker codec, not a WebSocket, native peer or send authority.
 * create transfers exclusive ownership of a fresh authenticated reconnect credential. The owner
 * must retire its session on any failure, bind READY to that exact socket, and never allocate a
 * replacement codec using the same credential. HTTP101 alone cannot authorize signaling/media.
 * No invitation/pairing/availability messages, key updates or automatic reconnect are accepted.
 */
public final class ViewerMediaSignalingCodec implements AutoCloseable {
    public static final int MAXIMUM_WIRE_BYTES = 90_000;
    public static final int MAXIMUM_ENVELOPE_BYTES = 65_536;
    public static final long MAXIMUM_SEQUENCE = 2_147_483_647L;
    private final SessionCredential credential;
    private final String channel;
    private final NonceSource nonces;
    private long nextSequence, highestReceived = -1, receivedBitmap;
    private boolean closed, operationInProgress;
    private Ready ready;

    public enum FailureCode {
        CLOSED, NOT_READY, REENTRANT, INVALID_WIRE, INVALID_PAYLOAD, AUTHENTICATION_FAILED,
        PROVIDER_FAILED, SEQUENCE_EXHAUSTED, REPLAYED_SEQUENCE, SEQUENCE_OUTSIDE_WINDOW
    }
    public static final class CodecFailure extends Exception {
        private static final long serialVersionUID = 1L;
        private final FailureCode code;
        private CodecFailure(FailureCode code) { super("Beluga media signaling refused: " + code.name()); this.code = code; }
        public FailureCode code() { return code; }
    }
    public enum Kind { WAITING, READY, SIGNAL, PEER_LEFT, SERVER_ERROR }
    public enum ServerError {
        PEER_UNAVAILABLE, RATE_LIMITED, INVITATION_UNAVAILABLE, INVITATION_EXPIRED, ROLE_CONFLICT, REQUEST_REJECTED
    }
    public static final class JoinHeaders {
        private final String channel, proof;
        private JoinHeaders(String channel, String proof) { this.channel = channel; this.proof = proof; }
        public String channelID() { return channel; }
        public String role() { return "viewer"; }
        /** Upgrade-only capability: never a URL, log or persisted value. No Mode/subprotocol. */
        public String admissionProofForUpgradeHeader() { return proof; }
        @Override public String toString() { return "<redacted Beluga viewer media headers>"; }
    }
    public static final class ICEServer {
        private final String[] urls;
        private final String username, password;
        private ICEServer(String[] urls, String username, String password) {
            this.urls = urls.clone(); this.username = username; this.password = password;
        }
        public String[] copyURLs() { return urls.clone(); }
        public String username() { return username; }
        /** Ephemeral TURN credential for this exact broker session only; never log/persist. */
        public String credential() { return password; }
        private boolean sameAs(ICEServer other) {
            return Arrays.equals(urls, other.urls) && same(username, other.username) && same(password, other.password);
        }
        @Override public String toString() { return "<redacted Beluga media ICE server>"; }
    }
    public static final class Event {
        private final Kind kind;
        private final long expiresAt;
        private final ICEServer[] servers;
        private final MediaSignalPayload payload;
        private final ServerError error;
        private Event(Kind kind, long expiresAt, ICEServer[] servers, MediaSignalPayload payload, ServerError error) {
            this.kind = kind; this.expiresAt = expiresAt; this.servers = servers == null ? null : servers.clone();
            this.payload = payload; this.error = error;
        }
        public Kind kind() { return kind; }
        /** Broker-claimed deadline, not authentication or a fresh wall/monotonic clock proof. */
        public long claimedInvitationExpiresAtEpochMillis() { return expiresAt; }
        public ICEServer[] copyICEServers() { return servers == null ? new ICEServer[0] : servers.clone(); }
        public MediaSignalPayload payload() { return payload; }
        public ServerError serverError() { return error; }
        @Override public String toString() { return "<redacted Beluga media broker event>"; }
    }
    public static final class Outbound {
        private final long sequence;
        private final byte[] wire;
        private Outbound(long sequence, byte[] wire) { this.sequence = sequence; this.wire = wire.clone(); }
        public long sequence() { return sequence; }
        public byte[] copyWireBytes() { return wire.clone(); }
        @Override public String toString() { return "<redacted Beluga media signaling outbound>"; }
    }
    @FunctionalInterface interface NonceSource { byte[] nextNonce(); }
    public static ViewerMediaSignalingCodec create(SessionCredential credential) throws CodecFailure {
        SecureRandom random = new SecureRandom();
        return new ViewerMediaSignalingCodec(credential, () -> { byte[] bytes = new byte[12]; random.nextBytes(bytes); return bytes; }, 0);
    }
    ViewerMediaSignalingCodec(SessionCredential credential, NonceSource nonces, long initialSequence) throws CodecFailure {
        if (credential == null || nonces == null || initialSequence < 0 || initialSequence > MAXIMUM_SEQUENCE)
            throw failure(FailureCode.INVALID_WIRE);
        try { channel = credential.channelID(); }
        catch (AuthFailure error) { throw failure(FailureCode.CLOSED); }
        this.credential = credential; this.nonces = nonces; nextSequence = initialSequence;
    }
    public synchronized JoinHeaders copyJoinHeaders() throws CodecFailure {
        requireOpen();
        try { return new JoinHeaders(channel, credential.admissionProofForTransport()); }
        catch (AuthFailure error) { throw failure(FailureCode.CLOSED); }
    }
    public synchronized Outbound seal(MediaSignalPayload payload) throws CodecFailure {
        begin(); byte[] plaintext = null, nonce = null, aad = null, combined = null, envelope = null, wire = null;
        try {
            requireReady();
            if (payload == null || payload.kind() == MediaSignalPayload.Kind.OFFER
                    || (payload.kind() == MediaSignalPayload.Kind.IDENTITY && !"viewer".equals(payload.identity().role())))
                throw failure(FailureCode.INVALID_PAYLOAD);
            if (nextSequence > MAXIMUM_SEQUENCE) throw failure(FailureCode.SEQUENCE_EXHAUSTED);
            plaintext = payload.canonicalBytes();
            if (plaintext.length > MAXIMUM_ENVELOPE_BYTES - 28) throw failure(FailureCode.INVALID_PAYLOAD);
            byte[] supplied = nonces.nextNonce(); requireReady();
            if (supplied == null || supplied.length != 12) throw failure(FailureCode.PROVIDER_FAILED);
            nonce = supplied.clone();
            long sequence = nextSequence;
            aad = aad(channel, sequence, 2);
            combined = credential.sealForTransport(Direction.VIEWER_TO_HOST, plaintext, nonce, aad);
            nextSequence++; // Successfully sealed sequences are spent even if framing/native send later fails.
            envelope = ascii("{\"channelID\":\"" + channel + "\",\"ciphertext\":"
                    + MediaSignalPayload.quote(base64(combined, false))
                    + ",\"direction\":\"viewerToHost\",\"sequence\":" + sequence + ",\"version\":1}");
            if (envelope.length > MAXIMUM_ENVELOPE_BYTES) throw failure(FailureCode.INVALID_WIRE);
            wire = ascii("{\"envelope\":\"" + base64(envelope, true) + "\",\"seq\":" + sequence + ",\"type\":\"signal\"}");
            if (wire.length > MAXIMUM_WIRE_BYTES) throw failure(FailureCode.INVALID_WIRE);
            return new Outbound(sequence, wire);
        } catch (AuthFailure error) { throw normalize(error); }
        catch (RuntimeException error) { throw failure(FailureCode.PROVIDER_FAILED); }
        finally { clear(plaintext); clear(nonce); clear(aad); clear(combined); clear(envelope); clear(wire); operationInProgress = false; }
    }
    public synchronized Event receive(byte[] wire) throws CodecFailure {
        begin();
        try {
            Map<String, Object> object = parse(wire, MAXIMUM_WIRE_BYTES);
            String type = string(object, "type", 32, false);
            switch (type) {
                case "waiting":
                    exact(object, "type", "invitationExpiresAt");
                    if (ready != null) throw failure(FailureCode.INVALID_WIRE);
                    return new Event(Kind.WAITING, expiry(string(object, "invitationExpiresAt", 64, false)), null, null, null);
                case "ready":
                    exact(object, "type", "role", "invitationExpiresAt", "iceServers");
                    if (!"viewer".equals(string(object, "role", 8, false))) throw failure(FailureCode.INVALID_WIRE);
                    Ready incoming = new Ready(expiry(string(object, "invitationExpiresAt", 64, false)), servers(object.get("iceServers")));
                    if (ready != null && !ready.sameAs(incoming)) throw failure(FailureCode.INVALID_WIRE);
                    if (ready == null) ready = incoming; // Exact duplicate never resets keys, sequence or replay state.
                    return new Event(Kind.READY, ready.expiresAt, ready.servers, null, null);
                case "signal": return open(object);
                case "peer-left":
                    exact(object, "type", "role");
                    if (!"host".equals(string(object, "role", 8, false))) throw failure(FailureCode.INVALID_WIRE);
                    close(); return new Event(Kind.PEER_LEFT, 0, null, null, null);
                case "error":
                    exact(object, "type", "error");
                    String message = string(object, "error", 64, false);
                    for (int i = 0; i < message.length(); i++) {
                        char c = message.charAt(i);
                        if (!(c >= 'A' && c <= 'Z') && !(c >= 'a' && c <= 'z') && !(c >= '0' && c <= '9') && c != '_')
                            throw failure(FailureCode.INVALID_WIRE);
                    }
                    close(); return new Event(Kind.SERVER_ERROR, 0, null, null, serverError(message));
                default: throw failure(FailureCode.INVALID_WIRE);
            }
        } finally { operationInProgress = false; }
    }
    private Event open(Map<String, Object> object) throws CodecFailure {
        requireReady(); exact(object, "type", "from", "seq", "envelope");
        if (!"host".equals(string(object, "from", 8, false))) throw failure(FailureCode.INVALID_WIRE);
        long sequence = number(object, "seq", MAXIMUM_SEQUENCE);
        byte[] envelope = decode(string(object, "envelope", 87_384, false), true, MAXIMUM_ENVELOPE_BYTES);
        byte[] combined = null, aad = null, plaintext = null;
        try {
            Map<String, Object> inner = parse(envelope, MAXIMUM_ENVELOPE_BYTES);
            exact(inner, "version", "channelID", "direction", "sequence", "ciphertext");
            if (number(inner, "version", 255) != 1 || !channel.equals(string(inner, "channelID", 128, false))
                    || !"hostToViewer".equals(string(inner, "direction", 32, false))
                    || sequence != number(inner, "sequence", MAXIMUM_SEQUENCE)) throw failure(FailureCode.INVALID_WIRE);
            combined = decode(string(inner, "ciphertext", 87_384, false), false, MAXIMUM_ENVELOPE_BYTES + 28);
            if (combined.length < 28) throw failure(FailureCode.INVALID_WIRE);
            aad = aad(channel, sequence, 1);
            plaintext = credential.openForTransport(Direction.HOST_TO_VIEWER, combined, aad);
            MediaSignalPayload payload = payload(parse(plaintext, MAXIMUM_ENVELOPE_BYTES));
            accept(sequence); // Authentication AND typed payload validation precede replay mutation.
            return new Event(Kind.SIGNAL, 0, null, payload, null);
        } catch (AuthFailure error) { throw normalize(error); }
        finally { clear(envelope); clear(combined); clear(aad); clear(plaintext); }
    }
    private static MediaSignalPayload payload(Map<String, Object> object) throws CodecFailure {
        String kind = string(object, "kind", 32, false);
        try {
            switch (kind) {
                case "offer": exact(object, "kind", "sdp"); return MediaSignalPayload.offer(string(object, "sdp", 40_000, false));
                case "candidate":
                    exact(object, "kind", "candidate"); Map<String, Object> c = object(object.get("candidate"));
                    optionalKeys(c, new String[] {"sdp"}, "sdpMid", "sdpMLineIndex", "usernameFragment");
                    Integer index = c.get("sdpMLineIndex") == null ? null : Integer.valueOf((int) number(c, "sdpMLineIndex", 65_535));
                    return MediaSignalPayload.candidate(new MediaSignalPayload.Candidate(string(c, "sdp", 8_192, false),
                            optionalString(c, "sdpMid", 128, true), index, optionalString(c, "usernameFragment", 256, false)));
                case "end":
                    exact(object, "kind", "endReason"); String end = string(object, "endReason", 32, false);
                    for (MediaSignalPayload.EndReason reason : MediaSignalPayload.EndReason.values())
                        if (reason.wire.equals(end)) return MediaSignalPayload.end(reason);
                    throw failure(FailureCode.INVALID_PAYLOAD);
                case "identity":
                    exact(object, "kind", "identity"); Map<String, Object> i = object(object.get("identity"));
                    optionalKeys(i, new String[] {"deviceID", "role", "publicKey"}, "displayName");
                    if (!"host".equals(string(i, "role", 8, false))) throw failure(FailureCode.INVALID_PAYLOAD);
                    String id = string(i, "deviceID", 36, false);
                    UUID uuid = UUID.fromString(id);
                    if (!uuid.toString().equalsIgnoreCase(id)) throw failure(FailureCode.INVALID_PAYLOAD);
                    byte[] publicKey = decode(string(i, "publicKey", 1_368, false), false, 1_024);
                    try { return MediaSignalPayload.hostIdentity(uuid, publicKey, optionalString(i, "displayName", 256, true)); }
                    finally { clear(publicKey); }
                default: throw failure(FailureCode.INVALID_PAYLOAD); // Host answer/control/restart are not viewer-receiver messages.
            }
        } catch (IllegalArgumentException error) { throw failure(FailureCode.INVALID_PAYLOAD); }
    }
    private static ICEServer[] servers(Object input) throws CodecFailure {
        List<Object> list = list(input); if (list.size() > 16) throw failure(FailureCode.INVALID_WIRE);
        ICEServer[] result = new ICEServer[list.size()];
        for (int index = 0; index < list.size(); index++) {
            Map<String, Object> server = object(list.get(index));
            if (server.size() == 1) exact(server, "urls"); else exact(server, "urls", "username", "credential", "credentialType");
            List<Object> urls = list(server.get("urls")); if (urls.isEmpty() || urls.size() > 8) throw failure(FailureCode.INVALID_WIRE);
            String[] strings = new String[urls.size()]; boolean turn = false;
            for (int u = 0; u < urls.size(); u++) {
                String url = scalarString(urls.get(u), 2_048, false); int colon = url.indexOf(':');
                String scheme = colon <= 0 ? "" : url.substring(0, colon).toLowerCase(Locale.ROOT);
                if (MediaSignalPayload.containsWhitespace(url) || url.indexOf('@') >= 0
                        || !(scheme.equals("stun") || scheme.equals("stuns") || scheme.equals("turn") || scheme.equals("turns")))
                    throw failure(FailureCode.INVALID_WIRE);
                turn |= scheme.equals("turn") || scheme.equals("turns"); strings[u] = url;
            }
            String username = optionalString(server, "username", 1_024, false);
            String password = optionalString(server, "credential", 1_024, false);
            String credentialType = optionalString(server, "credentialType", 32, false);
            if (turn ? username == null || password == null || !"password".equals(credentialType)
                    : username != null || password != null || credentialType != null) throw failure(FailureCode.INVALID_WIRE);
            result[index] = new ICEServer(strings, username, password);
        }
        return result;
    }
    private static final class Ready {
        final long expiresAt; final ICEServer[] servers;
        Ready(long expiresAt, ICEServer[] servers) { this.expiresAt = expiresAt; this.servers = servers; }
        boolean sameAs(Ready other) {
            if (expiresAt != other.expiresAt || servers.length != other.servers.length) return false;
            for (int i = 0; i < servers.length; i++) if (!servers[i].sameAs(other.servers[i])) return false;
            return true;
        }
    }
    private void accept(long sequence) throws CodecFailure {
        if (highestReceived < 0) { highestReceived = sequence; receivedBitmap = 1; return; }
        if (sequence > highestReceived) {
            long advance = sequence - highestReceived;
            receivedBitmap = advance >= 64 ? 1 : (receivedBitmap << (int) advance) | 1; highestReceived = sequence; return;
        }
        long age = highestReceived - sequence;
        if (age >= 64) throw failure(FailureCode.SEQUENCE_OUTSIDE_WINDOW);
        long mask = 1L << (int) age;
        if ((receivedBitmap & mask) != 0) throw failure(FailureCode.REPLAYED_SEQUENCE);
        receivedBitmap |= mask;
    }
    // This v1 AAD is NOT remoteDomainSeparated/length-prefixed availability framing.
    static byte[] aad(String channel, long sequence, int direction) {
        byte[] prefix = ascii("AudioStreamer.Signaling.Envelope.AAD.v1\0");
        byte[] route = ascii(channel);
        return ByteBuffer.allocate(prefix.length + 1 + route.length + 1 + 1 + 8)
                .put(prefix).put((byte) 1).put(route).put((byte) 0).put((byte) direction).putLong(sequence).array();
    }
    private void begin() throws CodecFailure {
        requireOpen(); if (operationInProgress) throw failure(FailureCode.REENTRANT); operationInProgress = true;
    }
    private void requireOpen() throws CodecFailure {
        if (closed) throw failure(FailureCode.CLOSED);
        try { credential.channelID(); } catch (AuthFailure error) { throw failure(FailureCode.CLOSED); }
    }
    private void requireReady() throws CodecFailure { requireOpen(); if (ready == null) throw failure(FailureCode.NOT_READY); }
    @Override public synchronized void close() { if (!closed) { closed = true; ready = null; credential.close(); } }
    @Override public String toString() { return "<redacted Beluga viewer media signaling codec>"; }
    private static CodecFailure failure(FailureCode code) { return new CodecFailure(code); }
    private static CodecFailure normalize(AuthFailure error) {
        return failure(error.code() == ViewerPairingAuthenticator.FailureCode.AUTHENTICATION_FAILED
                ? FailureCode.AUTHENTICATION_FAILED : FailureCode.PROVIDER_FAILED);
    }
    private static ServerError serverError(String error) {
        switch (error) {
            case "peer_unavailable": return ServerError.PEER_UNAVAILABLE;
            case "rate_limited": return ServerError.RATE_LIMITED;
            case "invitation_unavailable": return ServerError.INVITATION_UNAVAILABLE;
            case "invitation_expired": return ServerError.INVITATION_EXPIRED;
            case "role_already_claimed": return ServerError.ROLE_CONFLICT;
            default: return ServerError.REQUEST_REJECTED;
        }
    }
    private static boolean same(String a, String b) { return a == null ? b == null : a.equals(b); }
    private static byte[] ascii(String input) { return input.getBytes(StandardCharsets.US_ASCII); }
    private static void clear(byte[] value) { if (value != null) Arrays.fill(value, (byte) 0); }
    private static String base64(byte[] bytes, boolean url) { return PairingBootstrapEnvelopeCodec.encodeBase64(bytes, url); }
    private static byte[] decode(String value, boolean url, int maximum) throws CodecFailure {
        try { return PairingBootstrapEnvelopeCodec.decodeBase64(value, url, maximum); }
        catch (PairingBootstrapEnvelopeCodec.EnvelopeFailure error) { throw failure(FailureCode.INVALID_WIRE); }
    }
    private static String string(Map<String, Object> fields, String name, int maximum, boolean empty) throws CodecFailure {
        return scalarString(fields.get(name), maximum, empty);
    }
    private static String scalarString(Object value, int maximum, boolean empty) throws CodecFailure {
        if (!(value instanceof String)) throw failure(FailureCode.INVALID_WIRE);
        try { return MediaSignalPayload.text((String) value, maximum, empty); }
        catch (IllegalArgumentException error) { throw failure(FailureCode.INVALID_WIRE); }
    }
    private static String optionalString(Map<String, Object> fields, String name, int maximum, boolean empty) throws CodecFailure {
        return fields.get(name) == null ? null : string(fields, name, maximum, empty);
    }
    private static long number(Map<String, Object> fields, String name, long maximum) throws CodecFailure {
        Object value = fields.get(name);
        if (!(value instanceof Long) || ((Long) value).longValue() > maximum) throw failure(FailureCode.INVALID_WIRE);
        return ((Long) value).longValue();
    }
    private static void exact(Map<String, Object> fields, String... names) throws CodecFailure {
        if (fields.size() != names.length) throw failure(FailureCode.INVALID_WIRE);
        for (String name : names) if (!fields.containsKey(name)) throw failure(FailureCode.INVALID_WIRE);
    }
    private static void optionalKeys(Map<String, Object> fields, String[] required, String... optional) throws CodecFailure {
        for (String name : required) if (!fields.containsKey(name)) throw failure(FailureCode.INVALID_WIRE);
        for (String name : fields.keySet()) {
            boolean known = false;
            for (String key : required) known |= key.equals(name);
            for (String key : optional) known |= key.equals(name);
            if (!known) throw failure(FailureCode.INVALID_WIRE);
        }
    }
    @SuppressWarnings("unchecked") private static Map<String, Object> object(Object value) throws CodecFailure {
        if (!(value instanceof Map<?, ?>)) throw failure(FailureCode.INVALID_WIRE);
        return (Map<String, Object>) value; // Only the private bounded JsonReader creates these typed maps.
    }
    @SuppressWarnings("unchecked") private static List<Object> list(Object value) throws CodecFailure {
        if (!(value instanceof List<?>)) throw failure(FailureCode.INVALID_WIRE);
        return (List<Object>) value;
    }
    private static Map<String, Object> parse(byte[] input, int maximum) throws CodecFailure {
        if (input == null || input.length == 0 || input.length > maximum) throw failure(FailureCode.INVALID_WIRE);
        try {
            String text = StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(input)).toString();
            try (JsonReader reader = new JsonReader(new StringReader(text))) {
                reader.setStrictness(Strictness.STRICT);
                int[] fields = {0}; Map<String, Object> result = object(read(reader, 0, fields, maximum));
                if (reader.peek() != JsonToken.END_DOCUMENT) throw failure(FailureCode.INVALID_WIRE);
                return result;
            }
        } catch (CharacterCodingException error) { throw failure(FailureCode.INVALID_WIRE); }
        catch (IOException | IllegalArgumentException | IllegalStateException error) { throw failure(FailureCode.INVALID_WIRE); }
    }
    private static Object read(JsonReader reader, int depth, int[] fields, int maximum) throws IOException, CodecFailure {
        if (depth > 6) throw failure(FailureCode.INVALID_WIRE);
        switch (reader.peek()) {
            case BEGIN_OBJECT:
                reader.beginObject(); Map<String, Object> object = new LinkedHashMap<>();
                while (reader.hasNext()) {
                    if (++fields[0] > 128 || object.size() >= 16) throw failure(FailureCode.INVALID_WIRE);
                    String key = scalarString(reader.nextName(), 64, false);
                    if (object.containsKey(key)) throw failure(FailureCode.INVALID_WIRE);
                    object.put(key, read(reader, depth + 1, fields, maximum));
                }
                reader.endObject(); return object;
            case BEGIN_ARRAY:
                reader.beginArray(); List<Object> values = new ArrayList<>();
                while (reader.hasNext()) {
                    if (values.size() >= 16) throw failure(FailureCode.INVALID_WIRE);
                    values.add(read(reader, depth + 1, fields, maximum));
                }
                reader.endArray(); return values;
            case STRING: return scalarString(reader.nextString(), maximum, true);
            case NUMBER:
                String number = reader.nextString();
                if (number.isEmpty() || number.length() > 10 || (number.length() > 1 && number.charAt(0) == '0'))
                    throw failure(FailureCode.INVALID_WIRE);
                long result = 0;
                for (int i = 0; i < number.length(); i++) {
                    char digit = number.charAt(i); if (digit < '0' || digit > '9') throw failure(FailureCode.INVALID_WIRE);
                    result = result * 10 + digit - '0';
                }
                if (result > MAXIMUM_SEQUENCE) throw failure(FailureCode.INVALID_WIRE);
                return Long.valueOf(result);
            case NULL: reader.nextNull(); return null;
            default: throw failure(FailureCode.INVALID_WIRE);
        }
    }
    private static long expiry(String value) throws CodecFailure {
        // Same API23-safe proleptic Gregorian/fractional ISO8601 subset as the bootstrap parser.
        if (value.length() < 22 || value.length() > 64 || value.charAt(4) != '-' || value.charAt(7) != '-'
                || value.charAt(10) != 'T' || value.charAt(13) != ':' || value.charAt(16) != ':' || value.charAt(19) != '.')
            throw failure(FailureCode.INVALID_WIRE);
        int year = digits(value, 0, 4), month = digits(value, 5, 2), day = digits(value, 8, 2);
        int hour = digits(value, 11, 2), minute = digits(value, 14, 2), second = digits(value, 17, 2);
        if (year == 0 || month < 1 || month > 12 || day < 1 || hour > 23 || minute > 59 || second > 59)
            throw failure(FailureCode.INVALID_WIRE);
        int offset = 20, fraction = 0, milliseconds = 0;
        while (offset < value.length() && value.charAt(offset) >= '0' && value.charAt(offset) <= '9') {
            if (fraction >= 9) throw failure(FailureCode.INVALID_WIRE);
            if (fraction < 3) milliseconds = milliseconds * 10 + value.charAt(offset) - '0';
            fraction++; offset++;
        }
        if (fraction == 0) throw failure(FailureCode.INVALID_WIRE);
        for (int i = fraction; i < 3; i++) milliseconds *= 10;
        int zoneMinutes = 0;
        if (offset < value.length() && value.charAt(offset) == 'Z') {
            if (offset + 1 != value.length()) throw failure(FailureCode.INVALID_WIRE);
        } else {
            if (offset + 6 != value.length() || (value.charAt(offset) != '+' && value.charAt(offset) != '-')
                    || value.charAt(offset + 3) != ':') throw failure(FailureCode.INVALID_WIRE);
            int zoneHour = digits(value, offset + 1, 2), zoneMinute = digits(value, offset + 4, 2);
            if (zoneHour > 23 || zoneMinute > 59) throw failure(FailureCode.INVALID_WIRE);
            zoneMinutes = (zoneHour * 60 + zoneMinute) * (value.charAt(offset) == '+' ? 1 : -1);
            if (Math.abs(zoneMinutes) > 18 * 60) throw failure(FailureCode.INVALID_WIRE);
        }
        GregorianCalendar calendar = new GregorianCalendar(TimeZone.getTimeZone("UTC"), Locale.ROOT);
        calendar.setGregorianChange(new Date(Long.MIN_VALUE)); calendar.setLenient(false); calendar.clear();
        calendar.set(Calendar.YEAR, year); calendar.set(Calendar.MONTH, month - 1); calendar.set(Calendar.DAY_OF_MONTH, day);
        calendar.set(Calendar.HOUR_OF_DAY, hour); calendar.set(Calendar.MINUTE, minute); calendar.set(Calendar.SECOND, second);
        calendar.set(Calendar.MILLISECOND, milliseconds);
        try { return calendar.getTimeInMillis() - zoneMinutes * 60_000L; }
        catch (IllegalArgumentException error) { throw failure(FailureCode.INVALID_WIRE); }
    }
    private static int digits(String value, int start, int count) throws CodecFailure {
        if (start < 0 || start > value.length() - count) throw failure(FailureCode.INVALID_WIRE);
        int result = 0;
        for (int i = start; i < start + count; i++) {
            char digit = value.charAt(i); if (digit < '0' || digit > '9') throw failure(FailureCode.INVALID_WIRE);
            result = result * 10 + digit - '0';
        }
        return result;
    }
}
