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
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * Receive-only base screen-control v2 wire admission. Parsed ACKs are observations, not
 * current-channel, request ownership, capture-health, or remote-input authority.
 */
public final class ViewerScreenControlCodec {
    public static final int MAXIMUM_MESSAGE_BYTES = 4096;
    private static final String UINT64_MAX = "18446744073709551615";
    private static final String FAILURE = "Invalid Beluga screen-control message";
    private static final Set<String> NON_SCREEN_KINDS = names("inputFeedback", "remoteMediaState",
            "remoteMediaCommandAcknowledgement", "macHostedCallEvidence");
    private static final Set<String> CAPABILITY_REQUIRED = names("protocolVersion", "inputSessionID",
            "screenRequestID", "maxMessageBytes");
    private static final Set<String> CAPABILITY_BOOLEANS = names("supportsPrimaryDrag", "supportsScroll",
            "supportsFocusedWindowResize", "supportsFocusedWindowResizeScaleRebinding",
            "supportsFocusedWindowMove", "supportsFocusedWindowMoveScaleRebinding",
            "supportsFocusedWindowMoveRecoverableOffscreen");

    public enum Command { SHOW_SCREEN, HIDE_SCREEN, REQUEST_KEY_FRAME }
    public enum Kind { ACK, NON_SCREEN, UNSUPPORTED_SCREEN_EVENT }
    public enum ScreenState { ACTIVE, INACTIVE }

    public static final class CodecFailure extends Exception {
        private static final long serialVersionUID = 1L;
        private CodecFailure() { super(FAILURE); }
    }

    public static final class Acknowledgement {
        private final String requestID;
        private final ScreenState state;
        private Acknowledgement(String requestID, ScreenState state) {
            this.requestID = requestID;
            this.state = state;
        }
        public String requestID() { return requestID; }
        public ScreenState state() { return state; }
        @Override public String toString() { return "Beluga screen acknowledgement [redacted]"; }
    }

    public static final class Message {
        private final Kind kind;
        private final Acknowledgement acknowledgement;
        private Message(Kind kind, Acknowledgement acknowledgement) {
            this.kind = kind;
            this.acknowledgement = acknowledgement;
        }
        public Kind kind() { return kind; }
        public Acknowledgement acknowledgement() { return acknowledgement; }
        @Override public String toString() { return "Beluga screen-control observation [redacted]"; }
    }

    private ViewerScreenControlCodec() {}

    /** Deterministic JSON encoding; ordinary Swift JSONEncoder field order is not a wire invariant. */
    public static byte[] encodeCommand(String canonicalNonzeroUInt64ID, Command command) throws CodecFailure {
        String id = unsignedID(canonicalNonzeroUInt64ID);
        if (command == null) throw new CodecFailure();
        String wire;
        switch (command) {
            case SHOW_SCREEN: wire = "showScreen"; break;
            case HIDE_SCREEN: wire = "hideScreen"; break;
            case REQUEST_KEY_FRAME: wire = "requestKeyFrame"; break;
            default: throw new CodecFailure();
        }
        return ("{\"command\":{\"command\":\"" + wire + "\",\"id\":" + id
                + "},\"kind\":\"command\",\"version\":2}").getBytes(StandardCharsets.UTF_8);
    }

    public static Message decodeHostMessage(byte[] input) throws CodecFailure {
        Map<String, Object> envelope = object(parse(input));
        exactKeys(envelope, names("version", "kind", payloadKey(envelope)));
        exactNumber(envelope.get("version"), "2");
        String kind = string(envelope.get("kind"));
        if (kind.equals("ack")) {
            Map<String, Object> ack = object(envelope.get("acknowledgement"));
            requiredOptionalKeys(ack, names("id", "state"), names("inputCapability"));
            String id = unsignedNumber(ack.get("id"));
            String state = string(ack.get("state"));
            ScreenState parsedState;
            if (state.equals("active")) parsedState = ScreenState.ACTIVE;
            else if (state.equals("inactive")) parsedState = ScreenState.INACTIVE;
            else throw new CodecFailure();
            Object capability = ack.get("inputCapability");
            if (capability != null) {
                if (parsedState != ScreenState.ACTIVE) throw new CodecFailure();
                validateCapability(object(capability), id);
            }
            return new Message(Kind.ACK, new Acknowledgement(id, parsedState));
        }
        // Unrelated bodies are bounded/duplicate-free JSON objects only. They are NOT semantically
        // admitted here, exposed to callers, or permitted to affect screen/input/session authority.
        object(envelope.get(kind));
        if (NON_SCREEN_KINDS.contains(kind)) return new Message(Kind.NON_SCREEN, null);
        if (isScreenExtension(kind)) return new Message(Kind.UNSUPPORTED_SCREEN_EVENT, null);
        throw new CodecFailure();
    }

    private static String payloadKey(Map<String, Object> envelope) throws CodecFailure {
        String kind = string(envelope.get("kind"));
        if (kind.equals("ack")) return "acknowledgement";
        if (NON_SCREEN_KINDS.contains(kind) || isScreenExtension(kind)) return kind;
        throw new CodecFailure();
    }

    private static boolean isScreenExtension(String kind) {
        return kind.length() > "screenMedia".length() && kind.length() <= 64
                && kind.startsWith("screenMedia") && kind.matches("[A-Za-z]+");
    }

    private static void validateCapability(Map<String, Object> capability, String ackID) throws CodecFailure {
        requiredOptionalKeys(capability, CAPABILITY_REQUIRED, CAPABILITY_BOOLEANS);
        exactNumber(capability.get("protocolVersion"), "1");
        exactNumber(capability.get("maxMessageBytes"), "4096");
        if (!unsignedNumber(capability.get("screenRequestID")).equals(ackID)) throw new CodecFailure();
        String uuid = string(capability.get("inputSessionID"));
        if (!uuid.matches("[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"))
            throw new CodecFailure();
        UUID parsed = UUID.fromString(uuid);
        if (parsed.getMostSignificantBits() == 0 && parsed.getLeastSignificantBits() == 0) throw new CodecFailure();
        for (String field : CAPABILITY_BOOLEANS)
            if (capability.containsKey(field) && !(capability.get(field) instanceof Boolean)) throw new CodecFailure();
        // Intentionally retain no UUID/feature/token and grant no input capability. Only the
        // current request owner can distinguish an active Show from an active keyframe ACK;
        // this receive-only codec does not implement that remote-input authorization path.
    }

    private static Object parse(byte[] input) throws CodecFailure {
        if (input == null || input.length == 0 || input.length > MAXIMUM_MESSAGE_BYTES) throw new CodecFailure();
        final String text;
        try {
            text = StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(input)).toString();
        } catch (CharacterCodingException failure) { throw new CodecFailure(); }
        try (JsonReader reader = new JsonReader(new StringReader(text))) {
            reader.setStrictness(Strictness.STRICT);
            Object parsed = value(reader, 0, new int[] {0});
            if (reader.peek() != JsonToken.END_DOCUMENT) throw new CodecFailure();
            return parsed;
        } catch (IOException | IllegalStateException | NumberFormatException failure) { throw new CodecFailure(); }
    }

    private static Object value(JsonReader reader, int depth, int[] count) throws IOException, CodecFailure {
        if (depth > 12 || ++count[0] > 512) throw new CodecFailure();
        switch (reader.peek()) {
            case BEGIN_OBJECT: {
                Map<String, Object> result = new LinkedHashMap<>();
                reader.beginObject();
                while (reader.hasNext()) {
                    String key = checkedString(reader.nextName());
                    if (key.isEmpty() || key.getBytes(StandardCharsets.UTF_8).length > 64
                            || result.size() >= 32 || result.containsKey(key)) throw new CodecFailure();
                    result.put(key, value(reader, depth + 1, count));
                }
                reader.endObject();
                return result;
            }
            case BEGIN_ARRAY: {
                List<Object> result = new ArrayList<>();
                reader.beginArray();
                while (reader.hasNext()) {
                    if (result.size() >= 128) throw new CodecFailure();
                    result.add(value(reader, depth + 1, count));
                }
                reader.endArray();
                return result;
            }
            case STRING: return checkedString(reader.nextString());
            case NUMBER: {
                String number = reader.nextString();
                if (number.length() > 64 || !number.matches("-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?"))
                    throw new CodecFailure();
                return new NumberLexeme(number);
            }
            case BOOLEAN: return reader.nextBoolean();
            case NULL: reader.nextNull(); return null;
            default: throw new CodecFailure();
        }
    }

    private static String checkedString(String text) throws CodecFailure {
        for (int index = 0; index < text.length(); index++) {
            char current = text.charAt(index);
            if (Character.isHighSurrogate(current)) {
                if (++index >= text.length() || !Character.isLowSurrogate(text.charAt(index))) throw new CodecFailure();
            } else if (Character.isLowSurrogate(current)) throw new CodecFailure();
        }
        return text;
    }

    private static final class NumberLexeme {
        private final String value;
        private NumberLexeme(String value) { this.value = value; }
    }

    private static String unsignedNumber(Object value) throws CodecFailure {
        if (!(value instanceof NumberLexeme)) throw new CodecFailure();
        return unsignedID(((NumberLexeme) value).value);
    }

    private static String unsignedID(String id) throws CodecFailure {
        if (id == null || id.isEmpty() || id.length() > 20 || id.charAt(0) < '1' || id.charAt(0) > '9')
            throw new CodecFailure();
        for (int index = 1; index < id.length(); index++)
            if (id.charAt(index) < '0' || id.charAt(index) > '9') throw new CodecFailure();
        if (id.length() == 20 && id.compareTo(UINT64_MAX) > 0) throw new CodecFailure();
        return id;
    }

    private static void exactNumber(Object value, String expected) throws CodecFailure {
        if (!(value instanceof NumberLexeme) || !((NumberLexeme) value).value.equals(expected)) throw new CodecFailure();
    }

    private static String string(Object value) throws CodecFailure {
        if (!(value instanceof String)) throw new CodecFailure();
        return (String) value;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> object(Object value) throws CodecFailure {
        if (!(value instanceof Map<?, ?>)) throw new CodecFailure();
        // All maps originate only in the local bounded parser, which always emits String keys.
        return (Map<String, Object>) value;
    }

    private static void exactKeys(Map<String, Object> object, Set<String> expected) throws CodecFailure {
        if (!object.keySet().equals(expected)) throw new CodecFailure();
    }

    private static void requiredOptionalKeys(Map<String, Object> object, Set<String> required, Set<String> optional)
            throws CodecFailure {
        if (!object.keySet().containsAll(required)) throw new CodecFailure();
        for (String field : object.keySet())
            if (!required.contains(field) && !optional.contains(field)) throw new CodecFailure();
    }

    private static Set<String> names(String... values) { return new HashSet<>(Arrays.asList(values)); }
}
