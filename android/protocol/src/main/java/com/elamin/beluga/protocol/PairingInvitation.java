package com.elamin.beluga.protocol;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Arrays;

/** Wire-compatible invitation parser; possession is not proof of completed pairing. */
public final class PairingInvitation {
    public static final int MAXIMUM_QR_BYTES = 128;
    public static final int MAXIMUM_MANUAL_CHARACTERS = 256;
    private static final String QR_PREFIX = "BELUGA-PAIRING-V1\n";
    private static final String ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
    private static final byte[] CHECKSUM_DOMAIN =
            "AudioStreamer.RemoteInvitation.Checksum.v1\0".getBytes(StandardCharsets.US_ASCII);
    private final byte[] packet;

    private PairingInvitation(byte[] validatedPacket) {
        packet = validatedPacket.clone();
    }

    /** Human entry permits the same ASCII separators and O/I/L aliases as Swift. */
    public static PairingInvitation parseManual(String text) {
        if (text == null || text.length() > MAXIMUM_MANUAL_CHARACTERS) throw invalid();
        byte[] decoded = new byte[25];
        int accumulator = 0, bits = 0, symbols = 0, written = 0;
        for (int i = 0; i < text.length(); i++) {
            char symbol = text.charAt(i);
            if (symbol == '\t' || symbol == '\n' || symbol == '\r'
                    || symbol == ' ' || symbol == '-') continue;
            if (symbol >= 'a' && symbol <= 'z') symbol -= 32;
            if (symbol == 'O') symbol = '0';
            if (symbol == 'I' || symbol == 'L') symbol = '1';
            int value = ALPHABET.indexOf(symbol);
            if (value < 0 || ++symbols > 40) throw invalid();
            accumulator = (accumulator << 5) | value;
            bits += 5;
            if (bits >= 8) {
                bits -= 8;
                decoded[written++] = (byte) (accumulator >>> bits);
            }
        }
        if (symbols != 40 || written != 25 || bits != 0 || decoded[0] != 1) throw invalid();
        byte[] checksum = checksum(Arrays.copyOf(decoded, 21));
        if (!MessageDigest.isEqual(checksum, Arrays.copyOfRange(decoded, 21, 25))) throw invalid();
        return new PairingInvitation(decoded);
    }

    /** QR input is exact canonical text, not a URL and not permissive human entry. */
    public static PairingInvitation parseQRCode(String payload) {
        if (payload == null || payload.length() > MAXIMUM_QR_BYTES
                || payload.getBytes(StandardCharsets.UTF_8).length > MAXIMUM_QR_BYTES
                || !payload.startsWith(QR_PREFIX)) throw invalid();
        String code = payload.substring(QR_PREFIX.length());
        PairingInvitation invitation = parseManual(code);
        if (!invitation.exportedCode().equals(code)) throw invalid();
        return invitation;
    }

    /** Explicit secret export for pairing/display only; never log this value. */
    public String exportedCode() {
        StringBuilder result = new StringBuilder(47);
        int accumulator = 0, bits = 0, symbols = 0;
        for (byte raw : packet) {
            accumulator = (accumulator << 8) | (raw & 255);
            bits += 8;
            while (bits >= 5) {
                bits -= 5;
                if (symbols != 0 && symbols % 5 == 0) result.append('-');
                result.append(ALPHABET.charAt((accumulator >>> bits) & 31));
                symbols++;
            }
        }
        return result.toString();
    }

    @Override public String toString() { return "<redacted Beluga pairing invitation>"; }

    /** Trusted pairing composition only. The caller owns and wipes this transient copy. */
    byte[] copySecretForPairing() { return Arrays.copyOfRange(packet, 1, 21); }

    /** Same durable admission namespace and canonical spelling as ViewerPairingStore.swift. */
    byte[] admissionFingerprint() {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            digest.update("AudioStreamer.WorldwideInvitation.Admitted.v1\0".getBytes(StandardCharsets.UTF_8));
            byte[] code = exportedCode().getBytes(StandardCharsets.UTF_8);
            try { return digest.digest(code); }
            finally { Arrays.fill(code, (byte) 0); }
        } catch (NoSuchAlgorithmException unavailable) {
            throw new IllegalStateException("Required SHA-256 implementation unavailable");
        }
    }

    private static byte[] checksum(byte[] body) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            digest.update(CHECKSUM_DOMAIN);
            return Arrays.copyOf(digest.digest(body), 4);
        } catch (NoSuchAlgorithmException unavailable) {
            throw new IllegalStateException("Required SHA-256 implementation unavailable");
        }
    }

    private static IllegalArgumentException invalid() {
        return new IllegalArgumentException("Invalid Beluga pairing invitation");
    }
}
