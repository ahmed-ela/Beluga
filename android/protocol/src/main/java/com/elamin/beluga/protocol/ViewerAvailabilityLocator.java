package com.elamin.beluga.protocol;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.Arrays;
import java.util.UUID;
import com.elamin.beluga.protocol.BouncyCastlePairingCrypto.CryptoFailure;

/** Viewer-only derived availability routing. No host registration capability or pair root is retained. */
public final class ViewerAvailabilityLocator implements AutoCloseable {
    private static final String CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
    private final UUID pairID;
    private final String channel;
    private final byte[] admission, exchangeSeed;
    private boolean closed;

    private ViewerAvailabilityLocator(UUID pairID, String channel, byte[] admission, byte[] seed) {
        this.pairID = pairID; this.channel = channel;
        this.admission = admission.clone(); exchangeSeed = seed.clone();
    }

    /** Called only by the authenticated ACTIVE record; no public raw-root import. */
    static ViewerAvailabilityLocator derive(byte[] root, UUID pairID, byte[] transcript) throws CryptoFailure {
        byte[] route = null, channelBytes = null, admission = null, seed = null;
        byte[] routeSalt = null, seedSalt = null;
        try {
            routeSalt = ReconnectMessages.domain("AudioStreamer.Availability.Route.Salt.v1", uuid(pairID), transcript);
            route = derive(root, routeSalt, "AudioStreamer.Availability.Route.v1");
            channelBytes = derive(route, transcript, "AudioStreamer.Availability.Channel.v2");
            admission = derive(route, transcript, "AudioStreamer.Availability.Admission.Viewer.v2");
            seedSalt = ReconnectMessages.domain("AudioStreamer.Availability.ExchangeSeed.Salt.v1", uuid(pairID), transcript);
            seed = derive(root, seedSalt, "AudioStreamer.Availability.ExchangeSeed.v1");
            return new ViewerAvailabilityLocator(pairID, crockford(channelBytes), admission, seed);
        } finally {
            clear(route); clear(channelBytes); clear(admission); clear(seed); clear(routeSalt); clear(seedSalt);
        }
    }

    public synchronized ViewerAvailabilityEnvelopeCodec.JoinHeaders copyJoinHeaders()
            throws ViewerAvailabilityEnvelopeCodec.EnvelopeFailure {
        requireOpen(); return new ViewerAvailabilityEnvelopeCodec.JoinHeaders(channel,
                PairingBootstrapEnvelopeCodec.encodeBase64(admission, true));
    }

    public synchronized ViewerAvailabilityEnvelopeCodec createCodec()
            throws ViewerAvailabilityEnvelopeCodec.EnvelopeFailure {
        requireOpen();
        SecureRandom random = new SecureRandom();
        return new ViewerAvailabilityEnvelopeCodec(pairID, channel, admission, exchangeSeed,
                () -> { byte[] nonce = new byte[12]; random.nextBytes(nonce); return nonce; }, 0);
    }

    /** Package-only deterministic entropy seam; never selected by application composition. */
    synchronized ViewerAvailabilityEnvelopeCodec codecForFixture(ViewerAvailabilityEnvelopeCodec.NonceSource nonces,
            long initialSequence) throws ViewerAvailabilityEnvelopeCodec.EnvelopeFailure {
        requireOpen(); return new ViewerAvailabilityEnvelopeCodec(pairID, channel, admission, exchangeSeed, nonces, initialSequence);
    }

    @Override public synchronized void close() {
        if (!closed) { closed = true; clear(admission); clear(exchangeSeed); }
    }
    @Override public String toString() { return "<redacted Beluga viewer availability locator>"; }
    private void requireOpen() throws ViewerAvailabilityEnvelopeCodec.EnvelopeFailure {
        if (closed) throw ViewerAvailabilityEnvelopeCodec.failure(ViewerAvailabilityEnvelopeCodec.FailureCode.CLOSED);
    }
    static byte[] derive(byte[] input, byte[] salt, String label) throws CryptoFailure {
        return BouncyCastlePairingCrypto.hkdfSha256(input, salt, label.getBytes(StandardCharsets.US_ASCII), 32);
    }
    static byte[] uuid(UUID value) { return ByteBuffer.allocate(16).putLong(value.getMostSignificantBits()).putLong(value.getLeastSignificantBits()).array(); }
    private static String crockford(byte[] value) {
        StringBuilder output = new StringBuilder(52); int bits = 0, accumulator = 0;
        for (byte b : value) {
            accumulator = (accumulator << 8) | (b & 255); bits += 8;
            while (bits >= 5) { bits -= 5; output.append(CROCKFORD.charAt((accumulator >>> bits) & 31)); }
        }
        if (bits > 0) output.append(CROCKFORD.charAt((accumulator << (5 - bits)) & 31));
        return output.toString();
    }
    private static void clear(byte[] value) { if (value != null) Arrays.fill(value, (byte) 0); }
}
