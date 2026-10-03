package com.elamin.beluga.protocol;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Calendar;
import java.util.Date;
import java.util.GregorianCalendar;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.TimeZone;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Role;

/**
 * Stateless, bounded current pairing-broker event framing. No socket or reset authority.
 * READY is a broker transport observation, NEVER an authenticated or durably paired Mac.
 * SIGNAL is untrusted routed ciphertext; PairingBootstrapEnvelopeCodec.open is still required.
 */
public final class PairingBootstrapBrokerEventParser {
    public static final int MAXIMUM_WIRE_BYTES = PairingBootstrapEnvelopeCodec.MAXIMUM_WIRE_BYTES;
    private static final String BASE64URL = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    private static final Object EMPTY_ICE = new Object();
    private PairingBootstrapBrokerEventParser() { }

    public static final class ParseFailure extends Exception {
        private static final long serialVersionUID = 1L;
        private ParseFailure() { super("Invalid Beluga v1 pairing broker event"); }
    }
    public enum Kind { WAITING, READY, SIGNAL_WIRE, PEER_LEFT, SERVER_ERROR }
    public enum ServerError { PEER_UNAVAILABLE, RATE_LIMITED, INVITATION_UNAVAILABLE, INVITATION_EXPIRED, ROLE_CONFLICT, REQUEST_REJECTED }
    public abstract static class Event {
        private final Kind kind;
        private Event(Kind kind) { this.kind = kind; }
        public final Kind kind() { return kind; }
        @Override public final String toString() { return "<redacted Beluga pairing broker event>"; }
    }
    public static final class Waiting extends Event {
        private final long expiresAt;
        private Waiting(long expiresAt) { super(Kind.WAITING); this.expiresAt = expiresAt; }
        /** Broker-claimed deadline, conservatively floored to milliseconds, not current validity. */
        public long claimedInvitationExpiresAtEpochMillis() { return expiresAt; }
    }
    public static final class Ready extends Event {
        private final Role role;
        private final long expiresAt;
        private Ready(Role role, long expiresAt) { super(Kind.READY); this.role = role; this.expiresAt = expiresAt; }
        public Role localRole() { return role; }
        public long claimedInvitationExpiresAtEpochMillis() { return expiresAt; }
    }
    public static final class PeerLeft extends Event {
        private final Role role;
        private PeerLeft(Role role) { super(Kind.PEER_LEFT); this.role = role; }
        /** Observation only; the owner must retire/drain before admitting a replacement cycle. */
        public Role departedRole() { return role; }
    }
    public static final class ErrorEvent extends Event {
        private final ServerError error;
        private ErrorEvent(ServerError error) { super(Kind.SERVER_ERROR); this.error = error; }
        public ServerError error() { return error; }
    }
    public static final class SignalWire extends Event {
        private final Role claimedSender;
        private final long sequence;
        private final byte[] wire;
        private SignalWire(Role claimedSender, long sequence, byte[] wire) {
            super(Kind.SIGNAL_WIRE); this.claimedSender = claimedSender; this.sequence = sequence; this.wire = wire.clone();
        }
        public Role claimedSenderRole() { return claimedSender; }
        public long claimedSequence() { return sequence; }
        public byte[] copyUntrustedWireBytes() { return wire.clone(); }
    }

    /** Accepts only a TEXT frame's UTF8 bytes after transport endpoint/subprotocol admission. */
    public static Event parse(byte[] textFrame, Role localRole) throws ParseFailure {
        if (localRole == null || textFrame == null || textFrame.length == 0 || textFrame.length > MAXIMUM_WIRE_BYTES) throw refused();
        byte[] owned = textFrame.clone();
        try {
            // Current broker metadata and Base64URL ciphertext are ASCII. Malformed/non-ASCII
            // input cannot be normalized through a replacement-character UTF8 decoder.
            for (byte b : owned) if (b < 0) throw refused();
            Map<String, Object> object = new FlatParser(new String(owned, StandardCharsets.US_ASCII)).object();
            String type = string(object, "type");
            switch (type) {
                case "waiting":
                    exactKeys(object, "type", "invitationExpiresAt");
                    return new Waiting(expiry(string(object, "invitationExpiresAt")));
                case "ready":
                    exactKeys(object, "type", "role", "invitationExpiresAt", "iceServers");
                    if (role(string(object, "role")) != localRole || object.get("iceServers") != EMPTY_ICE) throw refused();
                    // Worker mode==='pairing' deliberately sends [] and never issues TURN.
                    // Stricter than Swift's <=16 decoder: legacy/media ready is not bootstrap.
                    return new Ready(localRole, expiry(string(object, "invitationExpiresAt")));
                case "signal":
                    exactKeys(object, "type", "from", "seq", "envelope");
                    Role sender = role(string(object, "from"));
                    if (sender == localRole) throw refused();
                    long sequence = number(object, "seq");
                    validateEnvelopeSpelling(string(object, "envelope"));
                    return new SignalWire(sender, sequence, owned);
                case "peer-left":
                    exactKeys(object, "type", "role");
                    Role departed = role(string(object, "role"));
                    if (departed == localRole) throw refused();
                    return new PeerLeft(departed);
                case "error":
                    exactKeys(object, "type", "error");
                    String error = string(object, "error");
                    if (error.length() == 0 || error.length() > 128) throw refused();
                    return new ErrorEvent(serverError(error));
                default: throw refused();
            }
        } finally { Arrays.fill(owned, (byte) 0); }
    }

    private static ServerError serverError(String value) {
        switch (value) {
            case "peer_unavailable": return ServerError.PEER_UNAVAILABLE;
            case "rate_limited": return ServerError.RATE_LIMITED;
            case "invitation_unavailable": return ServerError.INVITATION_UNAVAILABLE;
            case "invitation_expired": return ServerError.INVITATION_EXPIRED;
            case "role_already_claimed": return ServerError.ROLE_CONFLICT;
            default: return ServerError.REQUEST_REJECTED;
        }
    }
    private static void validateEnvelopeSpelling(String value) throws ParseFailure {
        int length = value.length();
        int maximum = PairingBootstrapEnvelopeCodec.MAXIMUM_ENVELOPE_BYTES;
        if (length == 0 || length > ((maximum + 2) / 3) * 4 || length % 4 == 1 || length * 6 / 8 > maximum) throw refused();
        int last = 0;
        for (int index = 0; index < length; index++) { last = BASE64URL.indexOf(value.charAt(index)); if (last < 0) throw refused(); }
        // A nonzero unused tail permits multiple textual spellings of the same bytes.
        if ((length % 4 == 2 && (last & 15) != 0) || (length % 4 == 3 && (last & 3) != 0)) throw refused();
    }
    private static long expiry(String value) throws ParseFailure {
        // API23-safe ISO8601 subset: Gregorian year0001..9999, required fractional seconds
        // (1..9 digits), uppercase T, UTC Z or an explicit +/-HH:mm offset up to18h.
        // Calendar normalization and ancient Foundation calendar parity are not accepted.
        if (value.length() < 22 || value.length() > 64 || value.charAt(4) != '-' || value.charAt(7) != '-'
                || value.charAt(10) != 'T' || value.charAt(13) != ':' || value.charAt(16) != ':' || value.charAt(19) != '.') throw refused();
        int year = digits(value, 0, 4), month = digits(value, 5, 2), day = digits(value, 8, 2);
        int hour = digits(value, 11, 2), minute = digits(value, 14, 2), second = digits(value, 17, 2);
        if (year == 0 || month < 1 || month > 12 || day < 1 || hour > 23 || minute > 59 || second > 59) throw refused();
        int offset = 20, fraction = 0, milliseconds = 0;
        while (offset < value.length() && isDigit(value.charAt(offset))) {
            if (fraction >= 9) throw refused();
            if (fraction < 3) milliseconds = milliseconds * 10 + value.charAt(offset) - '0';
            fraction++; offset++;
        }
        if (fraction == 0) throw refused();
        for (int index = fraction; index < 3; index++) milliseconds *= 10;
        int zoneMinutes = 0;
        if (offset < value.length() && value.charAt(offset) == 'Z') {
            if (offset + 1 != value.length()) throw refused();
        } else {
            if (offset + 6 != value.length() || (value.charAt(offset) != '+' && value.charAt(offset) != '-')
                    || value.charAt(offset + 3) != ':') throw refused();
            int zoneHour = digits(value, offset + 1, 2), zoneMinute = digits(value, offset + 4, 2);
            if (zoneHour > 23 || zoneMinute > 59) throw refused();
            zoneMinutes = (zoneHour * 60 + zoneMinute) * (value.charAt(offset) == '+' ? 1 : -1);
            // Matches the actual Foundation formatter's inclusive18h offset boundary.
            if (Math.abs(zoneMinutes) > 18 * 60) throw refused();
        }
        GregorianCalendar calendar = new GregorianCalendar(TimeZone.getTimeZone("UTC"), Locale.ROOT);
        calendar.setGregorianChange(new Date(Long.MIN_VALUE)); // ISO8601's proleptic Gregorian calendar.
        calendar.setLenient(false); calendar.clear();
        calendar.set(Calendar.YEAR, year); calendar.set(Calendar.MONTH, month - 1); calendar.set(Calendar.DAY_OF_MONTH, day);
        calendar.set(Calendar.HOUR_OF_DAY, hour); calendar.set(Calendar.MINUTE, minute); calendar.set(Calendar.SECOND, second);
        calendar.set(Calendar.MILLISECOND, milliseconds);
        try { return calendar.getTimeInMillis() - zoneMinutes * 60_000L; }
        catch (IllegalArgumentException ignored) { throw refused(); }
    }
    private static int digits(String text, int start, int count) throws ParseFailure {
        if (start < 0 || start > text.length() - count) throw refused(); int value = 0;
        for (int index = start; index < start + count; index++) {
            char c = text.charAt(index); if (!isDigit(c)) throw refused(); value = value * 10 + c - '0';
        }
        return value;
    }
    private static boolean isDigit(char c) { return c >= '0' && c <= '9'; }
    private static Role role(String value) throws ParseFailure {
        if (value.equals("host")) return Role.HOST;
        if (value.equals("viewer")) return Role.VIEWER;
        throw refused();
    }
    private static String string(Map<String, Object> map, String key) throws ParseFailure {
        Object value = map.get(key); if (!(value instanceof String)) throw refused(); return (String) value;
    }
    private static long number(Map<String, Object> map, String key) throws ParseFailure {
        Object value = map.get(key); if (!(value instanceof Long)) throw refused(); return ((Long) value).longValue();
    }
    private static void exactKeys(Map<String, Object> object, String... keys) throws ParseFailure {
        if (object.size() != keys.length) throw refused();
        for (String key : keys) if (!object.containsKey(key)) throw refused();
    }

    // Only flat strings, bounded unsigned integers and the literal EMPTY [] can enter this schema.
    private static final class FlatParser {
        private final String text; private int offset;
        private FlatParser(String text) { this.text = text; }
        Map<String, Object> object() throws ParseFailure {
            whitespace(); take('{'); whitespace(); Map<String, Object> fields = new HashMap<>();
            if (!consume('}')) {
                while (true) {
                    if (fields.size() >= 4) throw refused();
                    String key = quoted(32); if (fields.containsKey(key)) throw refused();
                    whitespace(); take(':'); whitespace(); Object value;
                    if (offset < text.length() && text.charAt(offset) == '"') value = quoted(MAXIMUM_WIRE_BYTES);
                    else if (consume('[')) { whitespace(); take(']'); value = EMPTY_ICE; }
                    else value = unsignedNumber();
                    fields.put(key, value); whitespace(); if (consume('}')) break;
                    take(','); whitespace();
                }
            }
            whitespace(); if (offset != text.length()) throw refused(); return fields;
        }
        private Long unsignedNumber() throws ParseFailure {
            int start = offset; long value = 0;
            while (offset < text.length() && isDigit(text.charAt(offset))) {
                if (offset - start >= 10 || (offset > start && text.charAt(start) == '0')) throw refused();
                value = value * 10 + text.charAt(offset++) - '0';
                if (value > PairingBootstrapEnvelopeCodec.MAXIMUM_SEQUENCE) throw refused();
            }
            if (offset == start) throw refused(); return Long.valueOf(value);
        }
        private String quoted(int maximum) throws ParseFailure {
            take('"'); StringBuilder result = new StringBuilder();
            while (offset < text.length()) {
                char c = text.charAt(offset++); if (c == '"') return result.toString();
                if (c < 32) throw refused();
                if (c == '\\') {
                    if (offset >= text.length()) throw refused(); char escape = text.charAt(offset++);
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
                            if (offset > text.length() - 4) throw refused(); int scalar = 0;
                            for (int index = 0; index < 4; index++) {
                                char digit = text.charAt(offset++);
                                int value = digit >= '0' && digit <= '9' ? digit - '0'
                                        : digit >= 'A' && digit <= 'F' ? digit - 'A' + 10
                                        : digit >= 'a' && digit <= 'f' ? digit - 'a' + 10 : -1;
                                if (value < 0) throw refused(); scalar = (scalar << 4) | value;
                            }
                            if (scalar > 127) throw refused(); c = (char) scalar; break;
                        default: throw refused();
                    }
                }
                if (result.length() >= maximum) throw refused(); result.append(c);
            }
            throw refused();
        }
        private void whitespace() { while (offset < text.length() && " \t\r\n".indexOf(text.charAt(offset)) >= 0) offset++; }
        private boolean consume(char c) { if (offset < text.length() && text.charAt(offset) == c) { offset++; return true; } return false; }
        private void take(char c) throws ParseFailure { if (!consume(c)) throw refused(); }
    }
    private static ParseFailure refused() { return new ParseFailure(); }
}
