package com.elamin.beluga.protocol;

import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.UUID;

/** Closed session-signaling values, not native peer, display, microphone or input authority. */
public final class MediaSignalPayload {
    public enum Kind { OFFER, ANSWER, CANDIDATE, CONTROL, END, IDENTITY }
    public enum Control {
        SHOW_SCREEN("showScreen"), HIDE_SCREEN("hideScreen"), REQUEST_KEY_FRAME("requestKeyFrame");
        final String wire;
        Control(String wire) { this.wire = wire; }
    }
    public enum EndReason {
        NORMAL("normal"), HOST_STOPPED("hostStopped"), VIEWER_DISCONNECTED("viewerDisconnected"),
        REPLACED("replaced"), PROTOCOL_ERROR("protocolError");
        final String wire;
        EndReason(String wire) { this.wire = wire; }
    }
    public static final class Candidate {
        private final String sdp, mid, usernameFragment;
        private final Integer index;
        public Candidate(String sdp, String sdpMid, Integer sdpMLineIndex, String usernameFragment) {
            this.sdp = text(sdp, 8_192, false);
            mid = sdpMid == null ? null : text(sdpMid, 128, true);
            if (sdpMLineIndex != null && (sdpMLineIndex < 0 || sdpMLineIndex > 65_535)) throw malformed();
            index = sdpMLineIndex;
            this.usernameFragment = usernameFragment == null ? null : text(usernameFragment, 256, false);
            if (usernameFragment != null && containsWhitespace(usernameFragment)) throw malformed();
        }
        public String sdp() { return sdp; }
        public String sdpMid() { return mid; }
        public Integer sdpMLineIndex() { return index; }
        public String usernameFragment() { return usernameFragment; }
        @Override public String toString() { return "<redacted Beluga media ICE candidate>"; }
    }
    public static final class Identity {
        private final UUID deviceID;
        private final String role, displayName;
        private final byte[] publicKey;
        private Identity(UUID deviceID, String role, byte[] publicKey, String displayName) {
            if (deviceID == null || publicKey == null || publicKey.length == 0 || publicKey.length > 1_024
                    || !("host".equals(role) || "viewer".equals(role))) throw malformed();
            this.deviceID = deviceID; this.role = role; this.publicKey = publicKey.clone();
            this.displayName = displayName == null ? null : text(displayName, 256, true);
        }
        public UUID deviceID() { return deviceID; }
        public String role() { return role; }
        public String displayName() { return displayName; }
        public byte[] copyPublicKey() { return publicKey.clone(); }
        @Override public String toString() { return "<redacted Beluga media identity assertion>"; }
    }
    private final Kind kind;
    private final String sdp;
    private final Candidate candidate;
    private final Control control;
    private final EndReason reason;
    private final Identity identity;
    private MediaSignalPayload(Kind kind, String sdp, Candidate candidate, Control control, EndReason reason, Identity identity) {
        this.kind = kind; this.sdp = sdp; this.candidate = candidate;
        this.control = control; this.reason = reason; this.identity = identity;
    }
    public static MediaSignalPayload answer(String sdp) { return description(Kind.ANSWER, sdp); }
    static MediaSignalPayload offer(String sdp) { return description(Kind.OFFER, sdp); }
    private static MediaSignalPayload description(Kind kind, String sdp) {
        return new MediaSignalPayload(kind, text(sdp, 40_000, false), null, null, null, null);
    }
    public static MediaSignalPayload candidate(Candidate candidate) {
        if (candidate == null) throw malformed();
        return new MediaSignalPayload(Kind.CANDIDATE, null, candidate, null, null, null);
    }
    public static MediaSignalPayload control(Control control) {
        if (control == null) throw malformed();
        return new MediaSignalPayload(Kind.CONTROL, null, null, control, null, null);
    }
    public static MediaSignalPayload end(EndReason reason) {
        if (reason == null) throw malformed();
        return new MediaSignalPayload(Kind.END, null, null, null, reason, null);
    }
    public static MediaSignalPayload identity(UUID deviceID, byte[] publicKey, String displayName) {
        return identity(new Identity(deviceID, "viewer", publicKey, displayName));
    }
    static MediaSignalPayload hostIdentity(UUID deviceID, byte[] publicKey, String displayName) {
        return identity(new Identity(deviceID, "host", publicKey, displayName));
    }
    private static MediaSignalPayload identity(Identity identity) {
        return new MediaSignalPayload(Kind.IDENTITY, null, null, null, null, identity);
    }
    public Kind kind() { return kind; }
    public String sdp() { return sdp; }
    public Candidate candidate() { return candidate; }
    public Control control() { return control; }
    public EndReason endReason() { return reason; }
    public Identity identity() { return identity; }
    @Override public String toString() { return "<redacted Beluga media signal payload>"; }

    /** Fixed-schema Foundation sorted-key encoding; this is not a general JSON parser. */
    byte[] canonicalBytes() {
        String result;
        switch (kind) {
            case OFFER: case ANSWER:
                result = "{\"kind\":" + quote(kind == Kind.OFFER ? "offer" : "answer") + ",\"sdp\":" + quote(sdp) + "}";
                break;
            case CANDIDATE:
                StringBuilder value = new StringBuilder("{\"candidate\":{\"sdp\":").append(quote(candidate.sdp));
                if (candidate.index != null) value.append(",\"sdpMLineIndex\":").append(candidate.index);
                if (candidate.mid != null) value.append(",\"sdpMid\":").append(quote(candidate.mid));
                if (candidate.usernameFragment != null) value.append(",\"usernameFragment\":").append(quote(candidate.usernameFragment));
                result = value.append("},\"kind\":\"candidate\"}").toString();
                break;
            case CONTROL: result = "{\"control\":" + quote(control.wire) + ",\"kind\":\"control\"}"; break;
            case END: result = "{\"endReason\":" + quote(reason.wire) + ",\"kind\":\"end\"}"; break;
            case IDENTITY:
                StringBuilder asserted = new StringBuilder("{\"identity\":{\"deviceID\":")
                        .append(quote(identity.deviceID.toString().toUpperCase(Locale.ROOT)));
                if (identity.displayName != null) asserted.append(",\"displayName\":").append(quote(identity.displayName));
                result = asserted.append(",\"publicKey\":")
                        .append(quote(PairingBootstrapEnvelopeCodec.encodeBase64(identity.publicKey, false)))
                        .append(",\"role\":").append(quote(identity.role)).append("},\"kind\":\"identity\"}").toString();
                break;
            default: throw malformed();
        }
        return result.getBytes(StandardCharsets.UTF_8);
    }
    static String text(String value, int maximumBytes, boolean allowEmpty) {
        if (value == null || (!allowEmpty && value.isEmpty()) || value.length() > maximumBytes) throw malformed();
        for (int index = 0; index < value.length(); index++) {
            char c = value.charAt(index);
            if (Character.isHighSurrogate(c)) {
                if (++index == value.length() || !Character.isLowSurrogate(value.charAt(index))) throw malformed();
            } else if (Character.isLowSurrogate(c)) throw malformed();
        }
        if (value.getBytes(StandardCharsets.UTF_8).length > maximumBytes) throw malformed();
        return value;
    }
    static boolean containsWhitespace(String value) {
        for (int i = 0; i < value.length();) {
            int scalar = value.codePointAt(i);
            if (Character.isWhitespace(scalar) || Character.isSpaceChar(scalar) || scalar == 0x85) return true;
            i += Character.charCount(scalar);
        }
        return false;
    }
    static String quote(String value) {
        StringBuilder result = new StringBuilder(value.length() + 2).append('"');
        for (int i = 0; i < value.length(); i++) {
            char c = value.charAt(i);
            switch (c) {
                case '"': result.append("\\\""); break;
                case '\\': result.append("\\\\"); break;
                case '/': result.append("\\/"); break;
                case '\b': result.append("\\b"); break;
                case '\f': result.append("\\f"); break;
                case '\n': result.append("\\n"); break;
                case '\r': result.append("\\r"); break;
                case '\t': result.append("\\t"); break;
                default:
                    if (c < 0x20) {
                        String hex = Integer.toHexString(c); result.append("\\u");
                        for (int zero = hex.length(); zero < 4; zero++) result.append('0');
                        result.append(hex);
                    } else result.append(c);
            }
        }
        return result.append('"').toString();
    }
    private static IllegalArgumentException malformed() { return new IllegalArgumentException("Invalid Beluga media signal value"); }
}
