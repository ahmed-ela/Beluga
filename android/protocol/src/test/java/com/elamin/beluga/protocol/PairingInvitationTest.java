package com.elamin.beluga.protocol;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.Locale;

/** Dependency-free host JVM test. Fixtures contain only public dummy secrets. */
public final class PairingInvitationTest {
    private static int assertions;
    private static final String PREFIX = "BELUGA-PAIRING-V1\n";

    public static void main(String[] args) throws Exception {
        if (args.length != 1) throw new IllegalArgumentException("Expected fixture path");
        int fixtures = 0;
        for (String line : Files.readAllLines(Paths.get(args[0]), StandardCharsets.UTF_8)) {
            if (line.startsWith("#") || line.isEmpty()) continue;
            String[] fields = line.split("\t", -1);
            check(fields.length == 3 && fields[1].length() == 40, "fixture shape");
            String code = fields[2];
            PairingInvitation parsed = PairingInvitation.parseManual(code);
            check(parsed.exportedCode().equals(code), "canonical round trip");
            check(PairingInvitation.parseQRCode(PREFIX + code).exportedCode().equals(code), "QR round trip");
            check(PairingInvitation.parseManual(code.toLowerCase(Locale.ROOT)).exportedCode().equals(code), "manual case");
            check(PairingInvitation.parseManual(" \t" + code.replace('-', '\n') + "\r").exportedCode().equals(code), "manual separators");
            check(PairingInvitation.parseManual(code.replace('0', 'O').replace('1', 'L')).exportedCode().equals(code), "manual aliases");
            check(PairingInvitation.parseManual(code.replace('1', 'I')).exportedCode().equals(code), "manual I alias");
            check(parsed.toString().equals("<redacted Beluga pairing invitation>"), "description redacted");
            rejectQR(PREFIX + code.toLowerCase(Locale.ROOT));
            rejectQR(PREFIX + code.replace("-", ""));
            rejectQR(PREFIX + code + "\n");
            rejectQR(PREFIX.replace("V1", "V2") + code);
            rejectQR("https://example.invalid/" + code);
            rejectQR(code);
            rejectManual(code.substring(1));
            rejectManual(code + "0");
            rejectManual("8" + code.substring(1)); // Unknown packet version.
            rejectManual(code.substring(0, code.length() - 1) + (code.endsWith("0") ? "1" : "0"));
            rejectManual(code.replace('0', '\uff10')); // Unicode look-alike is never an ASCII alias.
            rejectManual("U" + code.substring(1));
            rejectManual("\u0000" + code.substring(1));
            rejectManual(code.substring(0, 3) + (code.charAt(3) == '0' ? '1' : '0') + code.substring(4));
            check(PairingInvitation.parseManual(repeat(' ', 256 - code.length()) + code).exportedCode().equals(code), "exact manual bound");
            rejectManual(repeat(' ', 257 - code.length()) + code);
            fixtures++;
        }
        check(fixtures == 3, "expected fixed fixture count");
        rejectQR(null);
        rejectManual(null);
        rejectQR(repeat('A', 129));
        rejectQR(PREFIX + repeat('\u00e9', 65));
        rejectManual(repeat(' ', 257));
        rejectManual("U");
        System.out.println("Pairing invitation fixtures: " + fixtures + "; assertions: " + assertions + "; PASS");
    }

    private static String repeat(char value, int count) {
        char[] chars = new char[count];
        java.util.Arrays.fill(chars, value);
        return new String(chars);
    }
    private static void rejectQR(String input) { reject(input, true); }
    private static void rejectManual(String input) { reject(input, false); }
    private static void reject(String input, boolean qr) {
        try {
            if (qr) PairingInvitation.parseQRCode(input); else PairingInvitation.parseManual(input);
        } catch (IllegalArgumentException expected) {
            check(expected.getMessage().equals("Invalid Beluga pairing invitation"), "error redacted");
            return;
        }
        throw new AssertionError("Expected invalid invitation rejection");
    }
    private static void check(boolean condition, String label) {
        if (!condition) throw new AssertionError(label);
        assertions++;
    }
}
