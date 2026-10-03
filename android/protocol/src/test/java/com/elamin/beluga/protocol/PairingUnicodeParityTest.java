package com.elamin.beluga.protocol;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.text.Normalizer;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.UUID;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Hello;
import com.elamin.beluga.protocol.PairingCanonicalCodec.HelloFields;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Role;
import com.elamin.beluga.protocol.PairingPayloadDecoder.DecodeFailure;
import com.elamin.beluga.protocol.PairingPayloadDecoder.HelloPayload;

/** Private dependency-free JVM fixture tests. All names/bytes are public synthetic values. */
public final class PairingUnicodeParityTest {
    private static final String SHA256 = "f29705703eee4b18d32df294f0f3224a66f98c9e8d4f9e4300305667eafc92a6";
    private static final UUID HOST_ID = UUID.fromString("11111111-2222-3333-4444-555555555555");
    private static int assertions;
    private PairingUnicodeParityTest() { }

    public static void main(String[] args) throws Exception {
        if (args.length != 1) throw new IllegalArgumentException("One hash-checked public fixture path required");
        Map<String, byte[]> fixture = loadFixture(Path.of(args[0]));
        testAllObservedNameAdmissionsAndCanonicalBytes(fixture);
        testRawJSONAtStructuralAdmissionBoundary(fixture);
        testCompleteLegalScalarClassification(fixture);
        testExactPreservationBoundsAndIllFormedUTF16(fixture);
        testObservationMutantsFailReferenceComparisons(fixture);
        testUnicodeDoesNotBroadenSchemaAndRedaction(fixture);
        System.out.println("Pairing Unicode profile: " + assertions
                + " assertions; PASS (exact Foundation 26.5.1/25F80 reference, not universal/device proof)");
    }

    private static void testAllObservedNameAdmissionsAndCanonicalBytes(Map<String, byte[]> fixture) throws Exception {
        int admitted = 0, refused = 0;
        for (String id : nameIDs()) {
            String prefix = "case." + id;
            boolean present = bool(fixture, prefix + ".present");
            String name = present ? strictUTF8(value(fixture, prefix + ".utf8")) : null;
            check(Integer.parseInt(text(fixture, prefix + ".utf8-count")) == (name == null ? 0 : name.getBytes(StandardCharsets.UTF_8).length),
                    "actual UTF8 fixture length");
            boolean expected = bool(fixture, prefix + ".admitted");
            check(PairingDisplayNamePolicy.isValid(name) == expected, "all95 actual Foundation name results");
            if (!expected) {
                refuseName(name);
                refusePayload(value(fixture, prefix + ".hello-payload"));
                refused++;
                continue;
            }
            HelloFields fields = fields(name);
            Hello hello = new Hello(fields, fill(0x51, 32), fill(0x61, 64));
            equal(value(fixture, prefix + ".hello-unsigned"), PairingCanonicalCodec.unsignedHello(fields), "actual unsigned bytes");
            equal(value(fixture, prefix + ".hello-full"), PairingCanonicalCodec.fullHello(hello), "actual full bytes");
            equal(value(fixture, prefix + ".hello-payload"), PairingCanonicalCodec.helloPayload(hello), "actual payload bytes");
            equal(value(fixture, prefix + ".hello-psk-domain"), PairingCanonicalCodec.helloPskInput(fields), "actual PSK frame bytes");
            equal(value(fixture, prefix + ".hello-signature-domain"), PairingCanonicalCodec.helloSignatureInput(hello), "actual signature frame bytes");
            HelloPayload decoded = (HelloPayload) PairingPayloadDecoder.decode(value(fixture, prefix + ".hello-payload"));
            check(decoded.displayName() == null ? name == null : decoded.displayName().equals(name), "exact name scalar sequence retained");
            equal(value(fixture, prefix + ".hello-full"), PairingCanonicalCodec.fullHello(decoded.canonicalMessage()), "typed canonical roundtrip");
            equal(value(fixture, prefix + ".hello-payload"), PairingCanonicalCodec.helloPayload(decoded.canonicalMessage()), "typed wrapper roundtrip");
            check(decoded.toString().equals("<redacted Beluga pairing payload>"), "unchanged output redaction");
            admitted++;
        }
        check(admitted == 27 && refused == 68, "complete positive/negative95 inventory");
    }

    private static void testRawJSONAtStructuralAdmissionBoundary(Map<String, byte[]> fixture) throws Exception {
        int positive = 0, negative = 0;
        for (String id : jsonIDs()) {
            String prefix = "json." + id;
            boolean parsedByFoundation = bool(fixture, prefix + ".decoded");
            boolean admitted = bool(fixture, prefix + ".admitted");
            check(parsedByFoundation == decodedJSONIDs().contains(id), "actual Foundation decode status inventory");
            byte[] payload = wrapFull(value(fixture, prefix + ".input"));
            if (!admitted) {
                // The public Java decoder includes structural admission. It must refuse
                // NUL/control names even when Foundation's bare JSON decoder parsed them.
                refusePayload(payload);
                negative++;
            } else {
                check(parsedByFoundation, "admission needs successful string decode");
                HelloPayload decoded = (HelloPayload) PairingPayloadDecoder.decode(payload);
                equal(value(fixture, prefix + ".name-utf8"), decoded.displayName().getBytes(StandardCharsets.UTF_8), "actual escaped/raw scalar bytes");
                equal(value(fixture, prefix + ".canonical-full"), PairingCanonicalCodec.fullHello(decoded.canonicalMessage()), "actual Foundation reencoding");
                positive++;
            }
        }
        check(positive == 4 && negative == 8, "all12 JSON structural outcomes");
    }

    private static void testCompleteLegalScalarClassification(Map<String, byte[]> fixture) throws Exception {
        List<int[]> controls = ranges(value(fixture, "classifier.controlCharacters.ranges"), 533, 24970,
                "6424fbe40d790ac91ab3ec7e1fe57f67a852beb25f9e961cce1e99191b3d49ee");
        List<int[]> whitespace = ranges(value(fixture, "classifier.whitespacesAndNewlines.ranges"), 10, 26,
                "03a0b2f83effdef631f4abec9430132aca72ac1298fc2205f3810988c50ddaae");
        int count = 0, controlIndex = 0, whitespaceIndex = 0;
        for (int scalar = 0; scalar <= 0x10FFFF; scalar++) {
            if (scalar >= 0xD800 && scalar <= 0xDFFF) continue;
            while (controlIndex < controls.size() && controls.get(controlIndex)[1] < scalar) controlIndex++;
            while (whitespaceIndex < whitespace.size() && whitespace.get(whitespaceIndex)[1] < scalar) whitespaceIndex++;
            // Sequential independent golden scan; production uses binary search.
            boolean control = controlIndex < controls.size() && controls.get(controlIndex)[0] <= scalar;
            boolean white = whitespaceIndex < whitespace.size() && whitespace.get(whitespaceIndex)[0] <= scalar;
            check(PairingDisplayNamePolicy.isControl(scalar) == control, "complete observed control membership");
            check(PairingDisplayNamePolicy.isWhitespace(scalar) == white, "complete observed whitespace membership");
            count++;
        }
        check(count == 1112064 && text(fixture, "classifier.scalar-count").equals("1112064"), "all legal scalars checked");
        check(PairingDisplayNamePolicy.REFERENCE_PROFILE.equals("Foundation-26.5.1-25F80-display-name-v1"), "explicit runtime-reference profile");
        check(PairingDisplayNamePolicy.FIXTURE_SHA256.equals(SHA256), "profile fixture provenance");
        for (int illegal : new int[] { -1, 0xD800, 0xDFFF, 0x110000, Integer.MAX_VALUE }) {
            try { PairingDisplayNamePolicy.isControl(illegal); throw new AssertionError("invalid scalar accepted"); }
            catch (IllegalArgumentException expected) { assertions++; }
        }
    }

    private static void testExactPreservationBoundsAndIllFormedUTF16(Map<String, byte[]> fixture) throws Exception {
        for (String malformed : new String[] { new String(new char[] { 0xD800 }), new String(new char[] { 0xDC00 }),
                new String(new char[] { 0xDC00, 0xD800 }), new String(new char[] { 'A', 0xD800, 'B' }) }) {
            refuseName(malformed);
        }
        for (String id : new String[] { "precomposed", "decomposed", "ascii-padding", "nbsp-padding" }) {
            String name = strictUTF8(value(fixture, "case." + id + ".utf8"));
            check(PairingDisplayNamePolicy.validate(name) == name, "same original immutable string returned");
        }
        check(!Arrays.equals(value(fixture, "case.precomposed.hello-full"), value(fixture, "case.decomposed.hello-full")), "no NFC/NFD canonical collapse");
        check(PairingDisplayNamePolicy.isValid(repeat("\u00E9", 64)) && !PairingDisplayNamePolicy.isValid(repeat("\u00E9", 65)), "2byte UTF8 bound");
        check(PairingDisplayNamePolicy.isValid(repeat(new String(Character.toChars(0x1F433)), 32))
                && !PairingDisplayNamePolicy.isValid(repeat(new String(Character.toChars(0x1F433)), 32) + "a"), "4byte UTF8 bound");
        check(!PairingDisplayNamePolicy.isValid(new String(Character.toChars(0xE0101))), "observed nonstandard plane14 membership retained");
        check(PairingDisplayNamePolicy.isValid("A\u2028B") && PairingDisplayNamePolicy.isValid("A\u2029B"), "embedded separator admission");
        check(!PairingDisplayNamePolicy.isValid("\u2028") && !PairingDisplayNamePolicy.isValid("\u2029"), "separator-only blankness");

        byte[] absent = value(fixture, "case.nil.hello-payload");
        String explicitNull = strictUTF8(absent).replace("\"hello\":{", "\"hello\":{\"displayName\":null,");
        HelloPayload nil = (HelloPayload) PairingPayloadDecoder.decode(explicitNull.getBytes(StandardCharsets.UTF_8));
        check(nil.displayName() == null, "explicit-null optional retained as nil");
        equal(absent, PairingCanonicalCodec.helloPayload(nil.canonicalMessage()), "explicit null reencodes as omitted optional");
        HelloPayload emptySource = (HelloPayload) PairingPayloadDecoder.decode(absent);
        check(emptySource.displayName() == null, "absent optional remains nil, not empty");
    }

    private static void testObservationMutantsFailReferenceComparisons(Map<String, byte[]> fixture) throws Exception {
        String decomposed = strictUTF8(value(fixture, "case.decomposed.utf8"));
        notEqual(value(fixture, "case.decomposed.hello-full"), PairingCanonicalCodec.fullHello(hello(Normalizer.normalize(decomposed, Normalizer.Form.NFC))), "normalization mutant changes authenticated bytes");
        String padded = strictUTF8(value(fixture, "case.ascii-padding.utf8"));
        notEqual(value(fixture, "case.ascii-padding.hello-full"), PairingCanonicalCodec.fullHello(hello(padded.trim())), "trimming mutant changes authenticated bytes");
        String separatorJSON = strictUTF8(value(fixture, "case.embedded-002028.hello-full"));
        notEqual(value(fixture, "case.embedded-002028.hello-full"), separatorJSON.replace("\u2028", "\\u2028").getBytes(StandardCharsets.UTF_8), "separator escaping mutant changes canonical bytes");
        String tooWide = strictUTF8(value(fixture, "case.two-byte-130.utf8"));
        check(tooWide.length() <= 128 && !PairingDisplayNamePolicy.isValid(tooWide), "UTF16-count mutant would accept a rejected name");
        check(PairingDisplayNamePolicy.isControl(0xE0101), "omitting repeated plane14 membership must be caught");
        check(PairingDisplayNamePolicy.isWhitespace(0xA0) && !Character.isWhitespace(0xA0), "Java whitespace-category substitute is not reference policy");
    }

    private static void testUnicodeDoesNotBroadenSchemaAndRedaction(Map<String, byte[]> fixture) throws Exception {
        String wire = strictUTF8(value(fixture, "case.chinese.hello-payload"));
        refusePayload(wire.replace("\"kind\":\"hello\"", "\"kind\":\"hello\",\"" + "\\" + "u006bind\":\"hello\"").getBytes(StandardCharsets.UTF_8));
        refusePayload(wire.replace("\"hello\":{", "\"hello\":{\"unknown\u00E9\":null,").getBytes(StandardCharsets.UTF_8));
        refusePayload(wire.replace("\"role\":\"host\"", "\"role\":\"host\u0301\"").getBytes(StandardCharsets.UTF_8));
        for (String token : new String[] { "\"" + "\\" + "uD800\"", "\"" + "\\" + "uDC00\"", "\"" + "\\" + "uD800" + "\\" + "u0041\"" }) {
            byte[] full = insertRawName(value(fixture, "case.nil.hello-full"), token.getBytes(StandardCharsets.US_ASCII));
            refusePayload(wrapFull(full));
        }
    }

    private static Map<String, byte[]> loadFixture(Path fixturePath) throws Exception {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        try (InputStream input = Files.newInputStream(fixturePath)) {
            byte[] chunk = new byte[4096]; int count;
            while ((count = input.read(chunk)) != -1) {
                check(output.size() + count <= 1024 * 1024, "bounded exact fixture"); output.write(chunk, 0, count);
            }
        }
        byte[] raw = output.toByteArray();
        check(hex(MessageDigest.getInstance("SHA-256").digest(raw)).equals(SHA256), "exact actual Foundation fixture digest");
        for (byte value : raw) check(value >= 0, "ASCII TSV container");
        String input = new String(raw, StandardCharsets.US_ASCII);
        check(input.startsWith("# beluga.public-foundation-unicode-name.v1\n") && input.endsWith("\n"), "fixture schema");
        Map<String, byte[]> rows = new TreeMap<>(); String last = "";
        for (String row : input.split("\n")) {
            if (row.startsWith("#")) continue;
            String[] parts = row.split("\t", -1);
            check(parts.length == 2 && parts[0].matches("[A-Za-z0-9.-]{1,128}") && parts[0].compareTo(last) > 0, "canonical sorted unique keys");
            byte[] decoded = Base64.getDecoder().decode(parts[1]);
            check(decoded.length <= 16 * 1024 && Base64.getEncoder().encodeToString(decoded).equals(parts[1]), "canonical bounded Base64 including empty values");
            check(rows.put(parts[0], decoded) == null, "no duplicate rows"); last = parts[0];
        }
        check(rows.size() == 1198 && rows.keySet().equals(expectedRows()), "all1198 exact keys without omissions or extras");
        check(text(rows, "metadata.case-count").equals("95") && text(rows, "metadata.vector-count").equals("1198"), "count metadata matches exact inventory");
        check(text(rows, "metadata.operating-system").equals("Version 26.5.1 (Build 25F80)"), "explicit observed runtime");
        return rows;
    }
    private static Set<String> expectedRows() {
        Set<String> keys = new HashSet<>(Arrays.asList("metadata.authority", "metadata.case-count", "metadata.operating-system", "metadata.schema", "metadata.vector-count",
                "classifier.controlCharacters.ranges", "classifier.whitespacesAndNewlines.ranges", "classifier.scalar-count", "classifier.surrogate-range-excluded", "classifier.range-notation"));
        String[] suffixes = { "present", "utf8", "utf8-count", "scalar-values", "admitted", "trimmed-empty", "contains-control", "hello-unsigned", "hello-full", "hello-payload", "hello-psk-domain", "hello-signature-domain" };
        for (String id : nameIDs()) for (String suffix : suffixes) keys.add("case." + id + "." + suffix);
        for (String id : jsonIDs()) {
            for (String suffix : new String[] { "input", "decoded", "admitted" }) keys.add("json." + id + "." + suffix);
            if (decodedJSONIDs().contains(id)) { keys.add("json." + id + ".name-utf8"); keys.add("json." + id + ".canonical-full"); }
        }
        check(keys.size() == 1198, "static expected1198 inventory"); return keys;
    }
    private static Set<String> nameIDs() {
        Set<String> ids = new HashSet<>(Arrays.asList("nil", "empty", "ascii", "ascii-padding", "quotes-slash-backslash", "precomposed", "decomposed", "combining-only",
                "chinese", "japanese", "arabic", "hebrew", "devanagari", "korean", "emoji", "emoji-variation", "emoji-zwj", "replacement-scalar", "noncharacter-ffff", "noncharacter-max",
                "ascii-128", "ascii-129", "two-byte-128", "two-byte-130", "three-byte-128", "three-byte-129", "four-byte-128", "four-byte-129", "decomposed-128", "decomposed-129", "nbsp-padding"));
        for (int scalar : new int[] { 0x20, 0x09, 0x0A, 0x0D, 0x85, 0xA0, 0x1680, 0x2000, 0x2007, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0x200B }) ids.add("only-" + hexScalar(scalar));
        for (int scalar : new int[] { 0x7F, 0x85, 0x200B, 0x200C, 0x200D, 0x200E, 0x200F, 0x2028, 0x2029, 0x202E, 0x2060, 0x2066, 0x2069, 0xFE0F, 0xFEFF, 0x1D173, 0xE0001 }) ids.add("embedded-" + hexScalar(scalar));
        for (int scalar = 0; scalar < 32; scalar++) ids.add("c0-" + hexScalar(scalar));
        check(ids.size() == 95, "static95 name identities"); return ids;
    }
    private static Set<String> jsonIDs() {
        return new HashSet<>(Arrays.asList("high-surrogate", "low-surrogate", "reversed-surrogates", "paired-surrogates", "nul-escape", "line-separator-escape",
                "paragraph-separator-escape", "slash-escape", "short-control-escapes", "raw-utf8-surrogate", "overlong-utf8", "truncated-utf8"));
    }
    private static Set<String> decodedJSONIDs() {
        return new HashSet<>(Arrays.asList("paired-surrogates", "nul-escape", "line-separator-escape", "paragraph-separator-escape", "slash-escape", "short-control-escapes"));
    }
    private static List<int[]> ranges(byte[] raw, int count, int members, String digest) throws Exception {
        check(hex(MessageDigest.getInstance("SHA-256").digest(raw)).equals(digest), "exact observed table digest");
        List<int[]> ranges = new ArrayList<>(); int last = -2, total = 0;
        for (String row : strictUTF8(raw).split("\n")) {
            check(row.matches("[0-9A-F]{6}-[0-9A-F]{6}"), "canonical range row");
            int low = Integer.parseInt(row.substring(0, 6), 16), high = Integer.parseInt(row.substring(7), 16);
            check(low <= high && low > last + 1 && high <= 0x10FFFF && !(low <= 0xDFFF && high >= 0xD800), "sorted disjoint maximal legal scalar ranges");
            total += high - low + 1; ranges.add(new int[] { low, high }); last = high;
        }
        check(ranges.size() == count && total == members, "exact range and member inventory"); return ranges;
    }
    private static HelloFields fields(String name) { return new HelloFields(1, HOST_ID, Role.HOST, name, fill(0x11, 32), fill(0x31, 32), fill(0x41, 32)); }
    private static Hello hello(String name) { return new Hello(fields(name), fill(0x51, 32), fill(0x61, 64)); }
    private static byte[] wrapFull(byte[] full) { return concat(concat("{\"kind\":\"hello\",\"hello\":".getBytes(StandardCharsets.US_ASCII), full), new byte[] { '}' }); }
    private static byte[] insertRawName(byte[] full, byte[] token) {
        check(full[0] == '{', "controlled full JSON object");
        return concat(concat(concat("{\"displayName\":".getBytes(StandardCharsets.US_ASCII), token), new byte[] { ',' }), Arrays.copyOfRange(full, 1, full.length));
    }
    private static byte[] concat(byte[] first, byte[] second) { byte[] joined = Arrays.copyOf(first, first.length + second.length); System.arraycopy(second, 0, joined, first.length, second.length); return joined; }
    private static String strictUTF8(byte[] value) throws Exception { return StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(value)).toString(); }
    private static byte[] value(Map<String, byte[]> rows, String id) { byte[] bytes = rows.get(id); check(bytes != null, "required fixture key"); return bytes; }
    private static String text(Map<String, byte[]> rows, String id) throws Exception { return strictUTF8(value(rows, id)); }
    private static boolean bool(Map<String, byte[]> rows, String id) throws Exception { String value = text(rows, id); check(value.equals("true") || value.equals("false"), "canonical boolean observation"); return value.equals("true"); }
    private static byte[] fill(int value, int count) { byte[] bytes = new byte[count]; Arrays.fill(bytes, (byte) value); return bytes; }
    private static String repeat(String value, int count) { StringBuilder result = new StringBuilder(); for (int i = 0; i < count; i++) result.append(value); return result.toString(); }
    private static String hexScalar(int value) { return String.format(Locale.ROOT, "%06X", value); }
    private static String hex(byte[] bytes) { StringBuilder out = new StringBuilder(); for (byte value : bytes) out.append(String.format(Locale.ROOT, "%02x", value & 255)); return out.toString(); }
    private static void check(boolean value, String label) { assertions++; if (!value) throw new AssertionError(label); }
    private static void equal(byte[] expected, byte[] actual, String label) { check(Arrays.equals(expected, actual), label); }
    private static void notEqual(byte[] expected, byte[] actual, String label) { check(!Arrays.equals(expected, actual), label); }
    private static void refuseName(String name) {
        try { fields(name); throw new AssertionError("invalid name admitted"); }
        catch (IllegalArgumentException expected) {
            check(expected.getMessage().equals("Invalid Beluga v1 pairing codec input")
                    && expected.getCause() == null && expected.getSuppressed().length == 0,
                    "fixed redacted name refusal without upstream name");
        }
    }
    private static void refusePayload(byte[] bytes) throws Exception {
        try { PairingPayloadDecoder.decode(bytes); throw new AssertionError("structural payload admitted"); }
        catch (DecodeFailure expected) {
            check(expected.getMessage().equals("Invalid Beluga v1 pairing payload") && expected.getCause() == null && expected.getSuppressed().length == 0,
                    "fixed redacted refusal without upstream payload");
        }
    }
}
