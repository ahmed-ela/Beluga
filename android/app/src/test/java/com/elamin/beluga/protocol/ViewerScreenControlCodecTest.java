package com.elamin.beluga.protocol;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.Base64;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import org.junit.Test;
import com.elamin.beluga.protocol.ViewerScreenControlCodec.Acknowledgement;
import com.elamin.beluga.protocol.ViewerScreenControlCodec.CodecFailure;
import com.elamin.beluga.protocol.ViewerScreenControlCodec.Command;
import com.elamin.beluga.protocol.ViewerScreenControlCodec.Kind;
import com.elamin.beluga.protocol.ViewerScreenControlCodec.Message;
import com.elamin.beluga.protocol.ViewerScreenControlCodec.ScreenState;

/** Wire admission only; not native data-channel, current Show, capture-health, or input proof. */
public final class ViewerScreenControlCodecTest {
    private static final String SWIFT_SHA = "515a9f854188a19203d5302da23e067d5afd856906534670857cdecc0c1eb8d1";
    private static final String MAX = "18446744073709551615";
    private static final String CAPABILITY = "{\"protocolVersion\":1,\"inputSessionID\":\"11111111-2222-3333-4444-555555555555\","
            + "\"screenRequestID\":1,\"maxMessageBytes\":4096}";
    private static final String[] FEATURES = {"supportsPrimaryDrag", "supportsScroll", "supportsFocusedWindowResize",
            "supportsFocusedWindowResizeScaleRebinding", "supportsFocusedWindowMove", "supportsFocusedWindowMoveScaleRebinding",
            "supportsFocusedWindowMoveRecoverableOffscreen"};

    @Test public void allFortyNineActualSwiftRowsBindCommandsAcknowledgementsAndCapabilityVariants() throws Exception {
        Map<String, byte[]> reference = swiftReference();
        Set<String> expected = new HashSet<>(Arrays.asList("constants.version", "constants.channel-label",
                "constants.channel-protocol", "constants.maximum-message-bytes", "constants.maximum-buffered-bytes"));
        String[] labels = {"one", "signed-max", "high", "unsigned-max"};
        String[] ids = {"1", "9223372036854775807", "9223372036854775808", MAX};
        String[] commands = {"showScreen", "hideScreen", "requestKeyFrame"};
        Command[] nativeCommands = {Command.SHOW_SCREEN, Command.HIDE_SCREEN, Command.REQUEST_KEY_FRAME};
        String[] variants = {"inactive", "active", "active-default-capability", "active-full-capability"};
        for (int index = 0; index < labels.length; index++) {
            String prefix = "wire.id." + labels[index] + ".";
            for (int command = 0; command < commands.length; command++) {
                String wireName = prefix + "command." + commands[command];
                String javaName = "java.id." + labels[index] + ".command." + commands[command];
                expected.add(wireName); expected.add(javaName);
                byte[] encoded = ViewerScreenControlCodec.encodeCommand(ids[index], nativeCommands[command]);
                assertArrayEquals(reference.get(wireName), encoded);
                assertArrayEquals(reference.get(javaName), encoded);
            }
            for (String variant : variants) {
                String name = prefix + "ack." + variant; expected.add(name);
                Message decoded = ViewerScreenControlCodec.decodeHostMessage(reference.get(name));
                assertEquals(Kind.ACK, decoded.kind());
                assertEquals(ids[index], decoded.acknowledgement().requestID());
                assertEquals(variant.equals("inactive") ? ScreenState.INACTIVE : ScreenState.ACTIVE,
                        decoded.acknowledgement().state());
            }
        }
        assertEquals("2", text(reference.get("constants.version")));
        assertEquals(Integer.toString(ViewerScreenControlCodec.MAXIMUM_MESSAGE_BYTES), text(reference.get("constants.maximum-message-bytes")));
        assertEquals("262144", text(reference.get("constants.maximum-buffered-bytes")));
        // The SHA admission binds both exact channel literals. This wire codec does not negotiate a channel.
        assertTrue(reference.get("constants.channel-label").length > 0);
        assertTrue(reference.get("constants.channel-protocol").length > 0);
        for (String name : new String[] {"unsupported-version", "unsigned-overflow", "negative-id", "unknown-command"}) {
            String key = "refusal." + name; expected.add(key);
            // These are observations from actual Swift decoding, not fabricated Java negative inputs.
            assertEquals("refused", text(reference.get(key)));
        }
        assertEquals(49, expected.size());
        assertEquals(expected, reference.keySet());
    }

    @Test public void allThreeCommandsEncodeFullUnsignedNumericIDsDeterministically() throws Exception {
        Command[] commands = {Command.SHOW_SCREEN, Command.HIDE_SCREEN, Command.REQUEST_KEY_FRAME};
        String[] names = {"showScreen", "hideScreen", "requestKeyFrame"};
        for (String id : new String[] {"1", "9223372036854775807", "9223372036854775808", MAX})
            for (int index = 0; index < commands.length; index++) {
                String expected = "{\"command\":{\"command\":\"" + names[index] + "\",\"id\":" + id
                        + "},\"kind\":\"command\",\"version\":2}";
                byte[] first = ViewerScreenControlCodec.encodeCommand(id, commands[index]);
                assertArrayEquals(bytes(expected), first);
                assertArrayEquals(first, ViewerScreenControlCodec.encodeCommand(id, commands[index]));
                assertTrue(first.length <= ViewerScreenControlCodec.MAXIMUM_MESSAGE_BYTES);
                refused(() -> ViewerScreenControlCodec.decodeHostMessage(first)); // A reflected command is not an ACK.
            }
    }

    @Test public void commandRejectsNumericAliasesOverflowZeroAndMissingArguments() throws Exception {
        for (String id : new String[] {null, "", "0", "00", "01", "-1", "+1", " 1", "1 ", "1.0", "1e0",
                "18446744073709551616", "999999999999999999999", "١", "1\n"})
            refused(() -> ViewerScreenControlCodec.encodeCommand(id, Command.SHOW_SCREEN));
        refused(() -> ViewerScreenControlCodec.encodeCommand("1", null));
    }

    @Test public void acknowledgementPreservesAllUnsignedBitsAndOnlyExplicitState() throws Exception {
        for (String id : new String[] {"1", "9223372036854775807", "9223372036854775808", MAX})
            for (ScreenState state : ScreenState.values()) {
                Message message = decode(ack(id, state == ScreenState.ACTIVE ? "active" : "inactive", ""));
                assertEquals(Kind.ACK, message.kind());
                assertEquals(id, message.acknowledgement().requestID());
                assertEquals(state, message.acknowledgement().state());
                assertFalse(message.toString().contains(id));
                assertFalse(message.acknowledgement().toString().contains(id));
            }
    }

    @Test public void optionalCapabilityOmittedOrNullAndOldMinimalSchemaAreCompatible() throws Exception {
        assertEquals(ScreenState.ACTIVE, decode(ack("1", "active", "")).acknowledgement().state());
        assertEquals(ScreenState.ACTIVE, decode(ack("1", "active", ",\"inputCapability\":null")).acknowledgement().state());
        assertEquals(ScreenState.INACTIVE, decode(ack("1", "inactive", ",\"inputCapability\":null")).acknowledgement().state());
        assertEquals("1", decode(ack("1", "active", ",\"inputCapability\":" + CAPABILITY)).acknowledgement().requestID());
        refuse(ack("1", "inactive", ",\"inputCapability\":" + CAPABILITY));
        // Neither Boolean feature support nor the token is retained/exposed in the returned ACK.
        assertEquals(2, Acknowledgement.class.getDeclaredFields().length);
    }

    @Test public void allSevenOptionalCapabilityFeaturesAcceptOnlyNativeBooleans() throws Exception {
        String all = CAPABILITY.substring(0, CAPABILITY.length() - 1);
        for (String feature : FEATURES) all += ",\"" + feature + "\":true";
        all += "}";
        assertEquals(Kind.ACK, decode(ack("1", "active", ",\"inputCapability\":" + all)).kind());
        for (String feature : FEATURES) {
            for (String literal : new String[] {"true", "false"}) {
                String one = CAPABILITY.replace("}", ",\"" + feature + "\":" + literal + "}");
                assertEquals(Kind.ACK, decode(ack("1", "active", ",\"inputCapability\":" + one)).kind());
            }
            for (String literal : new String[] {"null", "0", "1", "\"true\"", "[]", "{}"}) {
                String bad = CAPABILITY.replace("}", ",\"" + feature + "\":" + literal + "}");
                refuse(ack("1", "active", ",\"inputCapability\":" + bad));
            }
        }
    }

    @Test public void capabilityRequiresExactProtocolSizeNonzeroUUIDAndAcknowledgedRequest() throws Exception {
        for (String bad : new String[] {
                CAPABILITY.replace("\"protocolVersion\":1", "\"protocolVersion\":2"),
                CAPABILITY.replace("\"protocolVersion\":1", "\"protocolVersion\":1.0"),
                CAPABILITY.replace("\"maxMessageBytes\":4096", "\"maxMessageBytes\":4095"),
                CAPABILITY.replace("\"maxMessageBytes\":4096", "\"maxMessageBytes\":\"4096\""),
                CAPABILITY.replace("\"screenRequestID\":1", "\"screenRequestID\":2"),
                CAPABILITY.replace("\"screenRequestID\":1", "\"screenRequestID\":0"),
                CAPABILITY.replace("\"screenRequestID\":1", "\"screenRequestID\":1e0"),
                CAPABILITY.replace("11111111-2222-3333-4444-555555555555", "00000000-0000-0000-0000-000000000000"),
                CAPABILITY.replace("11111111-2222-3333-4444-555555555555", "1-2-3-4-5"),
                CAPABILITY.replace("}", ",\"futureAuthority\":true}"),
                "null", "[]", "true", "\"capability\""
        }) {
            if (!bad.equals("null")) refuse(ack("1", "active", ",\"inputCapability\":" + bad));
        }
        for (String field : new String[] {"protocolVersion", "inputSessionID", "screenRequestID", "maxMessageBytes"}) {
            String bad = CAPABILITY.replaceAll("\\\"" + field + "\\\":(\\\"[^\\\"]*\\\"|[0-9]+),?", "")
                    .replace(",}", "}");
            refuse(ack("1", "active", ",\"inputCapability\":" + bad));
        }
        String lower = CAPABILITY.replace("11111111-2222-3333-4444-555555555555", "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee");
        assertEquals(Kind.ACK, decode(ack("1", "active", ",\"inputCapability\":" + lower)).kind());
        String high = CAPABILITY.replace("\"screenRequestID\":1", "\"screenRequestID\":" + MAX);
        assertEquals(MAX, decode(ack(MAX, "active", ",\"inputCapability\":" + high)).acknowledgement().requestID());
    }

    @Test public void acknowledgementIDsMustBeUnquotedCanonicalNonzeroUInt64Numbers() throws Exception {
        for (String id : new String[] {"0", "-0", "-1", "+1", "01", "1.0", "1e0", "1E+0", "\"1\"", "null",
                "true", "[]", "{}", "18446744073709551616", "999999999999999999999"}) refuse(ack(id, "active", ""));
    }

    @Test public void acknowledgementEnvelopeSchemaStateAndVersionAreExact() throws Exception {
        String good = ack("1", "active", "");
        for (String bad : new String[] {good.replace("\"version\":2", "\"version\":1"),
                good.replace("\"version\":2", "\"version\":2.0"), good.replace("\"version\":2", "\"version\":\"2\""),
                good.replace("\"version\":2,", ""), good.replace("\"kind\":\"ack\",", ""),
                good.replace("\"active\"", "\"playing\""), good.replace("\"active\"", "null"),
                good.replace("\"id\":1,", ""), good.replace(",\"state\":\"active\"", ""),
                good.replace("\"kind\":\"ack\"", "\"kind\":\"acknowledgement\""),
                good.replace("\"acknowledgement\"", "\"ack\""),
                good.replace("{\"id\":1,\"state\":\"active\"}", "null"),
                good.replace("{\"id\":1,\"state\":\"active\"}", "[]"),
                good.replace("{\"id\":1,\"state\":\"active\"}", "{\"id\":1,\"state\":\"active\",\"authority\":true}"),
                good.substring(0, good.length() - 1) + ",\"extra\":null}"}) refuse(bad);
    }

    @Test public void duplicatesAtEveryAcknowledgementLevelAndDecodedAliasAreRefused() throws Exception {
        String good = ack("1", "active", "");
        refuse(good.replace("\"version\":2", "\"version\":2,\"version\":2"));
        refuse(good.replace("\"kind\":\"ack\"", "\"kind\":\"ack\",\"kind\":\"ack\""));
        refuse(good.replace("\"id\":1", "\"id\":1,\"id\":1"));
        refuse(good.replace("\"id\":1", "\"id\":1,\"\\u0069d\":1"));
        refuse(good.replace("\"state\":\"active\"", "\"state\":\"active\",\"state\":\"inactive\""));
        refuse(ack("1", "active", ",\"inputCapability\":" + CAPABILITY.replace("\"protocolVersion\":1", "\"protocolVersion\":1,\"protocolVersion\":1")));
        refuse(ack("1", "active", ",\"inputCapability\":" + CAPABILITY + ",\"inputCapability\":null"));
    }

    @Test public void knownHostNonScreenMessagesAreBoundedNonAuthorizingObservations() throws Exception {
        for (String kind : new String[] {"inputFeedback", "remoteMediaState", "remoteMediaCommandAcknowledgement", "macHostedCallEvidence"}) {
            Message message = decode(other(kind, "{\"nested\":{\"items\":[1,-2,3.5,1e2,true,null,\"Café / 🎥\"]}}"));
            assertEquals(Kind.NON_SCREEN, message.kind());
            assertNull(message.acknowledgement());
            assertFalse(message.toString().contains("Café"));
            refuse(other(kind, "null")); refuse(other(kind, "[]"));
            refuse(other(kind, "{\"a\":1,\"a\":1}"));
        }
    }

    @Test public void screenMediaLifecycleEventsCannotBeSilentlyTreatedAsOrdinaryMessages() throws Exception {
        for (String kind : new String[] {"screenMediaSuspension", "screenMediaMarkerReady", "screenMediaResumeReady",
                "screenMediaResumedAcknowledgement", "screenMediaCancellation", "screenMediaCoveredAcknowledgement",
                "screenMediaMarkerPresentation", "screenMediaResumeRequest", "screenMediaFutureLifecycle"}) {
            Message parsed = decode(other(kind, "{\"screenRequestID\":1}"));
            assertEquals(Kind.UNSUPPORTED_SCREEN_EVENT, parsed.kind());
            assertNull(parsed.acknowledgement());
        }
        for (String kind : new String[] {"screenMedia", "screenMediaX1", "screenMedia_Notice", "screenMedia🎥"}) refuse(other(kind, "{}"));
    }

    @Test public void reflectedViewerKindsUnknownUnionAndMixedBodiesAreRefused() throws Exception {
        for (String kind : new String[] {"command", "input", "remoteMediaStateRefresh", "remoteMediaCommand",
                "macHostedCallChallenge", "futureMessage", "ACK"}) refuse(other(kind, "{}"));
        refuse(other("remoteMediaState", "{}").replace("\"remoteMediaState\":{}", "\"inputFeedback\":{}"));
        refuse(other("remoteMediaState", "{}").replace("{}", "{},\"acknowledgement\":{\"id\":1,\"state\":\"active\"}"));
    }

    @Test public void utf8JSONAndTrailingSyntaxAreStrictAndDiagnosticsStayRedacted() throws Exception {
        refused(() -> ViewerScreenControlCodec.decodeHostMessage(null));
        refused(() -> ViewerScreenControlCodec.decodeHostMessage(new byte[0]));
        refused(() -> ViewerScreenControlCodec.decodeHostMessage(new byte[] {(byte) 0xc3, 0x28}));
        String good = ack("1", "active", "");
        for (String bad : new String[] {good + good, good + " secret-payload", "/* comment */" + good,
                good.replace("\"version\"", "version"), good.replace("\"ack\"", "'ack'"),
                good.replace("\"active\"", "\"\\uD800\""),
                other("remoteMediaState", "{\"value\":\"\\uDC00\"}"),
                other("remoteMediaState", "{\"value\":NaN}"), other("remoteMediaState", "{\"value\":Infinity}")}) refuse(bad);
        assertEquals(Kind.ACK, decode(" \n\t" + good + "\r\n ").kind());
    }

    @Test public void byteDepthNodeObjectArrayAndNumberResourcesAreBounded() throws Exception {
        String good = ack("1", "active", "");
        byte[] exact = Arrays.copyOf(bytes(good), ViewerScreenControlCodec.MAXIMUM_MESSAGE_BYTES);
        Arrays.fill(exact, bytes(good).length, exact.length, (byte) ' ');
        assertEquals(Kind.ACK, ViewerScreenControlCodec.decodeHostMessage(exact).kind());
        refused(() -> ViewerScreenControlCodec.decodeHostMessage(Arrays.copyOf(exact, exact.length + 1)));
        String nested = "{}";
        for (int index = 0; index < 13; index++) nested = "{\"x\":" + nested + "}";
        refuse(other("remoteMediaState", nested));
        StringBuilder array = new StringBuilder("[");
        for (int index = 0; index < 129; index++) { if (index > 0) array.append(','); array.append('0'); }
        array.append(']'); refuse(other("remoteMediaState", "{\"x\":" + array + "}"));
        StringBuilder object = new StringBuilder("{");
        for (int index = 0; index < 33; index++) { if (index > 0) object.append(','); object.append('"').append(index).append("\":0"); }
        object.append('}'); refuse(other("remoteMediaState", object.toString()));
        String repeated = "[" + repeat("0,", 127) + "0]";
        refuse(other("remoteMediaState", "{\"a\":" + repeated + ",\"b\":" + repeated + ",\"c\":" + repeated + ",\"d\":" + repeated + "}"));
        refuse(other("remoteMediaState", "{\"" + repeat("k", 65) + "\":0}"));
        refuse(other("remoteMediaState", "{\"x\":" + repeat("1", 65) + "}"));
    }

    private static Message decode(String wire) throws CodecFailure { return ViewerScreenControlCodec.decodeHostMessage(bytes(wire)); }
    private static void refuse(String wire) throws Exception { refused(() -> decode(wire)); }
    private static String ack(String id, String state, String optional) {
        return "{\"version\":2,\"kind\":\"ack\",\"acknowledgement\":{\"id\":" + id + ",\"state\":\"" + state + "\"" + optional + "}}";
    }
    private static String other(String kind, String payload) {
        return "{\"version\":2,\"kind\":\"" + kind + "\",\"" + kind + "\":" + payload + "}";
    }
    private static String repeat(String value, int count) {
        StringBuilder result = new StringBuilder();
        for (int index = 0; index < count; index++) result.append(value);
        return result.toString();
    }
    private static byte[] bytes(String value) { return value.getBytes(StandardCharsets.UTF_8); }
    private static String text(byte[] value) { return new String(value, StandardCharsets.UTF_8); }
    private static Map<String, byte[]> swiftReference() throws Exception {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        try (InputStream input = ViewerScreenControlCodecTest.class.getResourceAsStream("/public-swift-screen-control-v1.tsv")) {
            if (input == null) throw new AssertionError("Missing actual Swift wire fixture");
            byte[] chunk = new byte[4096];
            for (int count; (count = input.read(chunk)) != -1;) {
                if (output.size() + count > 96000) throw new AssertionError("Oversized public fixture");
                output.write(chunk, 0, count);
            }
        }
        byte[] raw = output.toByteArray();
        assertEquals(11227, raw.length);
        StringBuilder digest = new StringBuilder();
        for (byte value : MessageDigest.getInstance("SHA-256").digest(raw)) digest.append(String.format("%02x", value & 255));
        assertEquals(SWIFT_SHA, digest.toString());
        String[] lines = text(raw).split("\n", -1);
        assertEquals("# beluga.public-test-screen-control.v1", lines[0]);
        assertEquals("# PUBLIC synthetic IDs and capabilities encoded/decoded by actual Swift source.", lines[1]);
        assertEquals("# Fixture sorted keys only; no channel, capture, renderer, recovery or device proof.", lines[2]);
        assertEquals("", lines[lines.length - 1]);
        Map<String, byte[]> rows = new TreeMap<>();
        String previous = "";
        for (int index = 3; index < lines.length - 1; index++) {
            String[] pair = lines[index].split("\t", -1);
            assertEquals(2, pair.length);
            assertTrue(pair[0].matches("[A-Za-z0-9.-]{1,128}"));
            assertTrue(pair[0].compareTo(previous) > 0); previous = pair[0];
            byte[] decoded = Base64.getDecoder().decode(pair[1]);
            assertTrue(decoded.length <= ViewerScreenControlCodec.MAXIMUM_MESSAGE_BYTES);
            assertEquals(pair[1], Base64.getEncoder().encodeToString(decoded));
            assertNull(rows.put(pair[0], decoded));
        }
        assertEquals(49, rows.size());
        return rows;
    }
    @FunctionalInterface private interface Throwing { void run() throws Exception; }
    private static void refused(Throwing operation) throws Exception {
        try { operation.run(); fail("Expected bounded screen-control refusal"); }
        catch (CodecFailure failure) {
            assertEquals("Invalid Beluga screen-control message", failure.getMessage());
            assertNull(failure.getCause());
        }
    }
}
