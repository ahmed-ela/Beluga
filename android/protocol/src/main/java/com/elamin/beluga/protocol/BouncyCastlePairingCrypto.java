package com.elamin.beluga.protocol;

import java.util.Arrays;
import org.bouncycastle.crypto.InvalidCipherTextException;
import org.bouncycastle.crypto.digests.SHA256Digest;
import org.bouncycastle.crypto.generators.HKDFBytesGenerator;
import org.bouncycastle.crypto.macs.HMac;
import org.bouncycastle.crypto.modes.ChaCha20Poly1305;
import org.bouncycastle.crypto.params.AEADParameters;
import org.bouncycastle.crypto.params.HKDFParameters;
import org.bouncycastle.crypto.params.KeyParameter;
import org.bouncycastle.math.ec.rfc7748.X25519;
import org.bouncycastle.math.ec.rfc8032.Ed25519;

/**
 * Private primitive-only draft for the exact BC 1.86 lightweight API.
 * No JCA registration, key generation/storage, transcript, state, transport or permission logic.
 * Inputs are copied; clearing owned arrays is best effort, not a JVM/provider zeroization promise.
 * The 1 MiB primitive cap is not a replacement for lower protocol/message admission limits.
 */
public final class BouncyCastlePairingCrypto {
    public static final int MAXIMUM_DATA_BYTES = 1024 * 1024;
    public static final int MAXIMUM_HKDF_BYTES = 255 * 32;
    private static final int KEY_BYTES = 32;
    private static final int SIGNATURE_BYTES = 64;
    private static final int NONCE_BYTES = 12;
    private static final int TAG_BYTES = 16;
    private BouncyCastlePairingCrypto() { }

    public enum FailureCode { MALFORMED_INPUT, AUTHENTICATION_FAILED, PROVIDER_FAILED }

    /** Fixed redacted diagnostics; deliberately does not retain an upstream cause or inputs. */
    public static final class CryptoFailure extends Exception {
        private static final long serialVersionUID = 1L;
        private final FailureCode code;
        private CryptoFailure(FailureCode code) {
            super("Beluga pairing crypto refused: " + code.name());
            this.code = code;
        }
        public FailureCode code() { return code; }
    }

    /** A 32-byte RFC8032 seed, not a 64-byte expanded secret or private||public representation. */
    public static byte[] ed25519PublicKey(byte[] seed) throws CryptoFailure {
        byte[] owned = exact(seed, KEY_BYTES);
        try {
            byte[] result = new byte[KEY_BYTES];
            Ed25519.generatePublicKey(owned, 0, result, 0);
            return result;
        } catch (RuntimeException ignored) { throw failure(FailureCode.PROVIDER_FAILED); }
        finally { clear(owned); }
    }

    /** Plain Ed25519 over the supplied bytes: no prehash, context or added suffix. */
    public static byte[] ed25519Sign(byte[] seed, byte[] message) throws CryptoFailure {
        byte[] ownedSeed = exact(seed, KEY_BYTES);
        byte[] ownedMessage = null;
        try {
            ownedMessage = bounded(message, 0, MAXIMUM_DATA_BYTES);
            byte[] result = new byte[SIGNATURE_BYTES];
            Ed25519.sign(ownedSeed, 0, ownedMessage, 0, ownedMessage.length, result, 0);
            return result;
        } catch (RuntimeException ignored) { throw failure(FailureCode.PROVIDER_FAILED); }
        finally { clear(ownedSeed); clear(ownedMessage); }
    }

    /** False denotes a rejected signature; malformed lengths are a typed refusal. */
    public static boolean ed25519Verify(byte[] publicKey, byte[] message, byte[] signature) throws CryptoFailure {
        byte[] ownedPublic = exact(publicKey, KEY_BYTES);
        byte[] ownedMessage = null;
        byte[] ownedSignature = null;
        try {
            ownedMessage = bounded(message, 0, MAXIMUM_DATA_BYTES);
            ownedSignature = exact(signature, SIGNATURE_BYTES);
            return Ed25519.verify(ownedSignature, 0, ownedPublic, 0, ownedMessage, 0, ownedMessage.length);
        } catch (RuntimeException ignored) { throw failure(FailureCode.PROVIDER_FAILED); }
        finally { clear(ownedPublic); clear(ownedMessage); clear(ownedSignature); }
    }

    public static byte[] x25519PublicKey(byte[] privateKey) throws CryptoFailure {
        byte[] owned = exact(privateKey, KEY_BYTES);
        try {
            byte[] result = new byte[KEY_BYTES];
            X25519.generatePublicKey(owned, 0, result, 0);
            return result;
        } catch (RuntimeException ignored) { throw failure(FailureCode.PROVIDER_FAILED); }
        finally { clear(owned); }
    }

    /** RFC7748 raw 32-byte agreement; upstream's all-zero result is never returned. */
    public static byte[] x25519Agreement(byte[] privateKey, byte[] peerPublicKey) throws CryptoFailure {
        byte[] ownedPrivate = exact(privateKey, KEY_BYTES);
        byte[] ownedPeer = null;
        byte[] result = new byte[KEY_BYTES];
        boolean succeeded = false;
        try {
            ownedPeer = exact(peerPublicKey, KEY_BYTES);
            if (!X25519.calculateAgreement(ownedPrivate, 0, ownedPeer, 0, result, 0)) {
                throw failure(FailureCode.AUTHENTICATION_FAILED);
            }
            succeeded = true;
            return result;
        } catch (RuntimeException ignored) { throw failure(FailureCode.PROVIDER_FAILED); }
        finally { clear(ownedPrivate); clear(ownedPeer); if (!succeeded) clear(result); }
    }

    public static byte[] sha256(byte[] data) throws CryptoFailure {
        byte[] owned = bounded(data, 0, MAXIMUM_DATA_BYTES);
        try {
            SHA256Digest digest = new SHA256Digest();
            digest.update(owned, 0, owned.length);
            byte[] result = new byte[KEY_BYTES];
            if (digest.doFinal(result, 0) != result.length) throw failure(FailureCode.PROVIDER_FAILED);
            return result;
        } catch (RuntimeException ignored) { throw failure(FailureCode.PROVIDER_FAILED); }
        finally { clear(owned); }
    }

    /** Existing hello PSK is 20 bytes; derived MAC keys are 32 bytes. */
    public static byte[] hmacSha256(byte[] key, byte[] data) throws CryptoFailure {
        byte[] ownedKey = bounded(key, 1, MAXIMUM_DATA_BYTES);
        byte[] ownedData = null;
        try {
            ownedData = bounded(data, 0, MAXIMUM_DATA_BYTES);
            HMac mac = new HMac(new SHA256Digest());
            mac.init(new KeyParameter(ownedKey));
            mac.update(ownedData, 0, ownedData.length);
            byte[] result = new byte[KEY_BYTES];
            if (mac.doFinal(result, 0) != result.length) throw failure(FailureCode.PROVIDER_FAILED);
            return result;
        } catch (RuntimeException ignored) { throw failure(FailureCode.PROVIDER_FAILED); }
        finally { clear(ownedKey); clear(ownedData); }
    }

    /** RFC5869 extract AND expand. Info is already UTF-8 bytes; this adds no domain framing. */
    public static byte[] hkdfSha256(byte[] input, byte[] salt, byte[] info, int outputBytes) throws CryptoFailure {
        if (outputBytes < 1 || outputBytes > MAXIMUM_HKDF_BYTES) throw failure(FailureCode.MALFORMED_INPUT);
        byte[] ownedInput = bounded(input, 1, MAXIMUM_DATA_BYTES);
        byte[] ownedSalt = null;
        byte[] ownedInfo = null;
        try {
            ownedSalt = bounded(salt, 0, MAXIMUM_DATA_BYTES);
            ownedInfo = bounded(info, 0, MAXIMUM_DATA_BYTES);
            HKDFBytesGenerator generator = new HKDFBytesGenerator(new SHA256Digest());
            generator.init(new HKDFParameters(ownedInput, ownedSalt, ownedInfo));
            byte[] result = new byte[outputBytes];
            if (generator.generateBytes(result, 0, result.length) != result.length) throw failure(FailureCode.PROVIDER_FAILED);
            return result;
        } catch (RuntimeException ignored) { throw failure(FailureCode.PROVIDER_FAILED); }
        finally { clear(ownedInput); clear(ownedSalt); clear(ownedInfo); }
    }

    /** nonce12 || ciphertext || tag16. Caller owns fresh nonce generation/non-reuse. */
    public static byte[] sealCombined(byte[] key, byte[] nonce, byte[] plaintext, byte[] aad) throws CryptoFailure {
        byte[] ownedKey = exact(key, KEY_BYTES);
        byte[] ownedNonce = null;
        byte[] ownedPlaintext = null;
        byte[] ownedAAD = null;
        byte[] body = null;
        try {
            ownedNonce = exact(nonce, NONCE_BYTES);
            ownedPlaintext = bounded(plaintext, 0, MAXIMUM_DATA_BYTES);
            ownedAAD = bounded(aad, 0, MAXIMUM_DATA_BYTES);
            body = crypt(true, ownedKey, ownedNonce, ownedPlaintext, ownedAAD);
            byte[] result = new byte[NONCE_BYTES + body.length];
            System.arraycopy(ownedNonce, 0, result, 0, NONCE_BYTES);
            System.arraycopy(body, 0, result, NONCE_BYTES, body.length);
            return result;
        } finally { clear(ownedKey); clear(ownedNonce); clear(ownedPlaintext); clear(ownedAAD); clear(body); }
    }

    /** Returns plaintext only after complete tag verification; no partial plaintext is exposed. */
    public static byte[] openCombined(byte[] key, byte[] combined, byte[] aad) throws CryptoFailure {
        byte[] ownedKey = exact(key, KEY_BYTES);
        byte[] ownedCombined = null;
        byte[] ownedAAD = null;
        byte[] nonce = null;
        byte[] body = null;
        try {
            ownedCombined = bounded(combined, NONCE_BYTES + TAG_BYTES, MAXIMUM_DATA_BYTES + NONCE_BYTES + TAG_BYTES);
            ownedAAD = bounded(aad, 0, MAXIMUM_DATA_BYTES);
            nonce = Arrays.copyOfRange(ownedCombined, 0, NONCE_BYTES);
            body = Arrays.copyOfRange(ownedCombined, NONCE_BYTES, ownedCombined.length);
            return crypt(false, ownedKey, nonce, body, ownedAAD);
        } finally { clear(ownedKey); clear(ownedCombined); clear(ownedAAD); clear(nonce); clear(body); }
    }

    private static byte[] crypt(boolean encrypt, byte[] key, byte[] nonce, byte[] data, byte[] aad) throws CryptoFailure {
        byte[] result = null;
        boolean succeeded = false;
        try {
            ChaCha20Poly1305 cipher = new ChaCha20Poly1305();
            cipher.init(encrypt, new AEADParameters(new KeyParameter(key), TAG_BYTES * 8, nonce, aad));
            int expected = encrypt ? data.length + TAG_BYTES : data.length - TAG_BYTES;
            if (cipher.getOutputSize(data.length) != expected) throw failure(FailureCode.PROVIDER_FAILED);
            result = new byte[expected];
            int written = cipher.processBytes(data, 0, data.length, result, 0);
            written += cipher.doFinal(result, written);
            if (written != expected) throw failure(FailureCode.PROVIDER_FAILED);
            succeeded = true;
            return result;
        } catch (InvalidCipherTextException ignored) { throw failure(FailureCode.AUTHENTICATION_FAILED); }
        catch (RuntimeException ignored) { throw failure(FailureCode.PROVIDER_FAILED); }
        finally { if (!succeeded) clear(result); }
    }

    private static byte[] exact(byte[] value, int length) throws CryptoFailure {
        return bounded(value, length, length);
    }
    private static byte[] bounded(byte[] value, int minimum, int maximum) throws CryptoFailure {
        if (value == null || value.length < minimum || value.length > maximum) throw failure(FailureCode.MALFORMED_INPUT);
        return value.clone();
    }
    private static CryptoFailure failure(FailureCode code) { return new CryptoFailure(code); }
    private static void clear(byte[] value) { if (value != null) Arrays.fill(value, (byte) 0); }
}
