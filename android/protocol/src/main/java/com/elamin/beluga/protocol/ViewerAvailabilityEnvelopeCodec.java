package com.elamin.beluga.protocol;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Map;
import java.util.UUID;
import com.elamin.beluga.protocol.BouncyCastlePairingCrypto.CryptoFailure;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Phase;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Role;
import com.elamin.beluga.protocol.PairingPayloadDecoder.CommitPayload;

/**
 * Viewer-only availability AEAD and bounded broker framing, not a socket or send authority.
 * Callers must bind retained activation/request bytes to a selected durable record and retained
 * owner. A decrypted response is still untrusted until the reconnect authenticator checks it.
 * No pending-pair recovery, host probes, TURN, SDP, media or automatic retry is supported.
 */
public final class ViewerAvailabilityEnvelopeCodec implements AutoCloseable {
    public static final int MAXIMUM_WIRE_BYTES = PairingBootstrapEnvelopeCodec.MAXIMUM_WIRE_BYTES;
    public static final int MAXIMUM_ENVELOPE_BYTES = PairingBootstrapEnvelopeCodec.MAXIMUM_ENVELOPE_BYTES;
    public static final long MAXIMUM_SEQUENCE = PairingBootstrapEnvelopeCodec.MAXIMUM_SEQUENCE;
    private final UUID pairID;
    private final String channel;
    private final byte[] admission, seed;
    private final NonceSource nonces;
    private final long initialSequence;
    private byte[] exchange, sendingKey, receivingKey;
    private String exchangeID;
    private long nextSequence, highestReceived = -1, receivedBitmap;
    private boolean closed, operationInProgress;

    public enum FailureCode {
        CLOSED, NOT_READY, REENTRANT, INVALID_WIRE, INVALID_PAYLOAD, AUTHENTICATION_FAILED,
        PROVIDER_FAILED, SEQUENCE_EXHAUSTED, REPLAYED_SEQUENCE, SEQUENCE_OUTSIDE_WINDOW
    }
    public static final class EnvelopeFailure extends Exception {
        private static final long serialVersionUID = 1L;
        private final FailureCode code;
        private EnvelopeFailure(FailureCode code) { super("Beluga availability envelope refused: " + code.name()); this.code = code; }
        public FailureCode code() { return code; }
    }
    public enum Kind { WAITING, READY, SIGNAL_RESPONSE, PEER_LEFT, SERVER_ERROR }
    public enum ServerError { PEER_UNAVAILABLE, RATE_LIMITED, ROLE_CONFLICT, REQUEST_REJECTED }
    public static final class Event {
        private final Kind kind; private final String exchangeID;
        private final ReconnectMessages.Response response; private final ServerError error;
        private Event(Kind kind, String exchangeID, ReconnectMessages.Response response, ServerError error) {
            this.kind = kind; this.exchangeID = exchangeID; this.response = response; this.error = error;
        }
        public Kind kind() { return kind; }
        public String exchangeID() { return exchangeID; }
        public ReconnectMessages.Response response() { return response; }
        public ServerError serverError() { return error; }
        @Override public String toString() { return "<redacted Beluga availability event>"; }
    }
    public static final class JoinHeaders {
        private final String channel, proof;
        JoinHeaders(String channel, String proof) { this.channel = channel; this.proof = proof; }
        public String channelID() { return channel; }
        public String role() { return "viewer"; }
        /** Upgrade-only capability. Do not log, persist, or place in a URL. */
        public String admissionProofForUpgradeHeader() { return proof; }
        @Override public String toString() { return "<redacted Beluga viewer availability headers>"; }
    }
    public static final class Outbound {
        private final String exchangeID; private final long sequence; private final byte[] wire;
        private Outbound(String exchangeID, long sequence, byte[] wire) {
            this.exchangeID = exchangeID; this.sequence = sequence; this.wire = wire.clone();
        }
        public String exchangeID() { return exchangeID; }
        public long sequence() { return sequence; }
        public byte[] copyWireBytes() { return wire.clone(); }
        @Override public String toString() { return "<redacted Beluga availability outbound>"; }
    }
    @FunctionalInterface interface NonceSource { byte[] nextNonce(); }
    ViewerAvailabilityEnvelopeCodec(UUID pairID, String channel, byte[] admission, byte[] seed,
            NonceSource nonces, long initialSequence) throws EnvelopeFailure {
        if (pairID == null || channel == null || channel.length() != 52 || admission == null || admission.length != 32
                || seed == null || seed.length != 32 || nonces == null || initialSequence < 0 || initialSequence > MAXIMUM_SEQUENCE)
            throw failure(FailureCode.INVALID_WIRE);
        this.pairID = pairID; this.channel = channel; this.admission = admission.clone(); this.seed = seed.clone();
        this.nonces = nonces; this.initialSequence = initialSequence;
    }

    public synchronized JoinHeaders copyJoinHeaders() throws EnvelopeFailure {
        requireOpen(); return new JoinHeaders(channel, encode(admission, true));
    }
    public synchronized String currentExchangeID() { return closed ? null : exchangeID; }

    public synchronized Outbound sealRequest(byte[] requestPayload) throws EnvelopeFailure {
        begin();
        byte[] canonical = null;
        try {
            ReconnectMessages.Payload decoded = ReconnectMessages.decodePayload(requestPayload);
            if (decoded.kind() != ReconnectMessages.Kind.RECONNECT_REQUEST) throw failure(FailureCode.INVALID_PAYLOAD);
            canonical = ReconnectMessages.requestPayload(decoded.request());
            return seal(canonical);
        } catch (ReconnectMessages.DecodeFailure | IllegalArgumentException error) { throw failure(FailureCode.INVALID_PAYLOAD); }
        finally { clear(canonical); operationInProgress = false; }
    }

    /** Retained activation is resent before reconnect, because the host may still be acceptedIssued. */
    public synchronized Outbound sealActivation(byte[] retainedPairingPayload) throws EnvelopeFailure {
        begin(); byte[] canonical = null, full = null;
        try {
            PairingPayloadDecoder.Payload decoded = PairingPayloadDecoder.decode(retainedPairingPayload);
            if (!(decoded instanceof CommitPayload)) throw failure(FailureCode.INVALID_PAYLOAD);
            CommitPayload commit = (CommitPayload) decoded;
            if (commit.senderRole() != Role.VIEWER || commit.phase() != Phase.ACTIVATION_ACKNOWLEDGEMENT)
                throw failure(FailureCode.INVALID_PAYLOAD);
            full = PairingCanonicalCodec.fullCommit(commit.canonicalMessage());
            canonical = ascii("{\"kind\":\"pairingCommit\",\"pairingCommit\":" + new String(full, StandardCharsets.US_ASCII) + "}");
            return seal(canonical);
        } catch (PairingPayloadDecoder.DecodeFailure | IllegalArgumentException error) { throw failure(FailureCode.INVALID_PAYLOAD); }
        finally { clear(full); clear(canonical); operationInProgress = false; }
    }

    public synchronized Event receive(byte[] wire) throws EnvelopeFailure {
        begin();
        try {
            Map<String, Object> fields = parse(wire, MAXIMUM_WIRE_BYTES);
            String type = string(fields, "type");
            switch (type) {
                case "availability-waiting":
                    exact(fields, "type"); return event(Kind.WAITING, null);
                case "availability-ready":
                    exact(fields, "type", "role", "exchangeID");
                    if (!"viewer".equals(string(fields, "role"))) throw failure(FailureCode.INVALID_WIRE);
                    String incoming = string(fields, "exchangeID");
                    byte[] raw = exchange(incoming);
                    try { if (!incoming.equals(exchangeID)) installExchange(incoming, raw); }
                    finally { clear(raw); }
                    return event(Kind.READY, incoming);
                case "availability-signal":
                    return openSignal(fields);
                case "availability-peer-left":
                    exact(fields, "type", "role", "exchangeID");
                    String leaving = string(fields, "exchangeID");
                    if (!"host".equals(string(fields, "role")) || exchangeID == null || !exchangeID.equals(leaving))
                        throw failure(FailureCode.INVALID_WIRE);
                    clearExchange(); return event(Kind.PEER_LEFT, leaving);
                case "error":
                    exact(fields, "type", "error"); String error = string(fields, "error");
                    if (error.isEmpty() || error.length() > 64) throw failure(FailureCode.INVALID_WIRE);
                    for (int i = 0; i < error.length(); i++) {
                        char c = error.charAt(i);
                        if (!(c >= 'A' && c <= 'Z') && !(c >= 'a' && c <= 'z') && !(c >= '0' && c <= '9') && c != '_')
                            throw failure(FailureCode.INVALID_WIRE);
                    }
                    ServerError category = "availability_unavailable".equals(error) || "peer_unavailable".equals(error)
                            ? ServerError.PEER_UNAVAILABLE : "rate_limited".equals(error) ? ServerError.RATE_LIMITED
                            : "role_already_claimed".equals(error) ? ServerError.ROLE_CONFLICT : ServerError.REQUEST_REJECTED;
                    return new Event(Kind.SERVER_ERROR, null, null, category);
                default: throw failure(FailureCode.INVALID_WIRE);
            }
        } finally { operationInProgress = false; }
    }

    private Outbound seal(byte[] payload) throws EnvelopeFailure {
        requireReady();
        if (payload.length > ReconnectMessages.MAXIMUM_BYTES) throw failure(FailureCode.INVALID_PAYLOAD);
        if (nextSequence > MAXIMUM_SEQUENCE) throw failure(FailureCode.SEQUENCE_EXHAUSTED);
        byte[] nonce = null, combined = null, aad = null, envelope = null, wire = null;
        long sequence = nextSequence;
        try {
            byte[] supplied = nonces.nextNonce(); requireOpen();
            if (supplied == null || supplied.length != 12) throw failure(FailureCode.PROVIDER_FAILED);
            nonce = supplied.clone(); aad = aad(sequence, 2);
            combined = BouncyCastlePairingCrypto.sealCombined(sendingKey, nonce, payload, aad);
            nextSequence++; // Never reclaim a successfully sealed sequence after a framing/send failure.
            envelope = ascii("{\"channelID\":\"" + channel + "\",\"ciphertext\":\"" + encode(combined, false)
                    + "\",\"direction\":\"viewerToHost\",\"exchangeID\":\"" + exchangeID + "\",\"sequence\":" + sequence + ",\"version\":1}");
            if (envelope.length > MAXIMUM_ENVELOPE_BYTES) throw failure(FailureCode.INVALID_WIRE);
            wire = ascii("{\"envelope\":\"" + encode(envelope, true) + "\",\"exchangeID\":\"" + exchangeID
                    + "\",\"seq\":" + sequence + ",\"type\":\"availability-signal\"}");
            if (wire.length > MAXIMUM_WIRE_BYTES) throw failure(FailureCode.INVALID_WIRE);
            return new Outbound(exchangeID, sequence, wire);
        } catch (CryptoFailure error) { throw normalize(error); }
        catch (RuntimeException error) { throw failure(FailureCode.PROVIDER_FAILED); }
        finally { clear(nonce); clear(combined); clear(aad); clear(envelope); clear(wire); }
    }

    private Event openSignal(Map<String, Object> fields) throws EnvelopeFailure {
        exact(fields, "type", "from", "exchangeID", "seq", "envelope"); requireReady();
        long sequence = number(fields, "seq");
        if (!"host".equals(string(fields, "from")) || !exchangeID.equals(string(fields, "exchangeID")))
            throw failure(FailureCode.INVALID_WIRE);
        byte[] encoded = decode(string(fields, "envelope"), true, MAXIMUM_ENVELOPE_BYTES);
        byte[] combined = null, plaintext = null, aad = null;
        try {
            Map<String, Object> inner = parse(encoded, MAXIMUM_ENVELOPE_BYTES);
            exact(inner, "version", "channelID", "exchangeID", "direction", "sequence", "ciphertext");
            if (number(inner, "version") != 1 || !channel.equals(string(inner, "channelID"))
                    || !exchangeID.equals(string(inner, "exchangeID")) || !"hostToViewer".equals(string(inner, "direction"))
                    || sequence != number(inner, "sequence")) throw failure(FailureCode.INVALID_WIRE);
            combined = decode(string(inner, "ciphertext"), false, ReconnectMessages.MAXIMUM_BYTES + 28);
            aad = aad(sequence, 1); plaintext = BouncyCastlePairingCrypto.openCombined(receivingKey, combined, aad);
            ReconnectMessages.Payload payload = ReconnectMessages.decodePayload(plaintext);
            if (payload.kind() != ReconnectMessages.Kind.RECONNECT_RESPONSE) throw failure(FailureCode.INVALID_PAYLOAD);
            acceptSequence(sequence);
            return new Event(Kind.SIGNAL_RESPONSE, exchangeID, payload.response(), null);
        } catch (CryptoFailure error) { throw normalize(error); }
        catch (ReconnectMessages.DecodeFailure | IllegalArgumentException error) { throw failure(FailureCode.INVALID_PAYLOAD); }
        finally { clear(encoded); clear(combined); clear(plaintext); clear(aad); }
    }

    private void installExchange(String incoming, byte[] raw) throws EnvelopeFailure {
        byte[] salt = null, send = null, receive = null;
        try {
            salt = ReconnectMessages.domain("AudioStreamer.Availability.Exchange.Salt.v1", ViewerAvailabilityLocator.uuid(pairID), raw);
            send = ViewerAvailabilityLocator.derive(seed, salt, "AudioStreamer.Availability.Exchange.Signaling.ViewerToHost.v1");
            receive = ViewerAvailabilityLocator.derive(seed, salt, "AudioStreamer.Availability.Exchange.Signaling.HostToViewer.v1");
            clearExchange(); exchangeID = incoming; exchange = raw.clone(); sendingKey = send; receivingKey = receive;
            send = null; receive = null; nextSequence = initialSequence;
        } catch (CryptoFailure error) { throw normalize(error); }
        finally { clear(salt); clear(send); clear(receive); }
    }
    private byte[] aad(long sequence, int direction) {
        return ReconnectMessages.domain("AudioStreamer.Availability.Envelope.AAD.v1", new byte[] {1}, ascii(channel),
                exchange, new byte[] {(byte) direction}, ByteBuffer.allocate(8).putLong(sequence).array());
    }
    private void acceptSequence(long sequence) throws EnvelopeFailure {
        if (highestReceived < 0) { highestReceived = sequence; receivedBitmap = 1; return; }
        if (sequence > highestReceived) {
            long advance = sequence - highestReceived;
            receivedBitmap = advance >= 64 ? 1 : (receivedBitmap << (int) advance) | 1;
            highestReceived = sequence; return;
        }
        long age = highestReceived - sequence;
        if (age >= 64) throw failure(FailureCode.SEQUENCE_OUTSIDE_WINDOW);
        long mask = 1L << (int) age;
        if ((receivedBitmap & mask) != 0) throw failure(FailureCode.REPLAYED_SEQUENCE);
        receivedBitmap |= mask;
    }
    private void begin() throws EnvelopeFailure {
        requireOpen(); if (operationInProgress) throw failure(FailureCode.REENTRANT); operationInProgress = true;
    }
    private void requireOpen() throws EnvelopeFailure { if (closed) throw failure(FailureCode.CLOSED); }
    private void requireReady() throws EnvelopeFailure { requireOpen(); if (exchangeID == null) throw failure(FailureCode.NOT_READY); }
    private void clearExchange() {
        clear(exchange); clear(sendingKey); clear(receivingKey);
        exchange = null; sendingKey = null; receivingKey = null; exchangeID = null;
        nextSequence = 0; highestReceived = -1; receivedBitmap = 0;
    }
    @Override public synchronized void close() { if (!closed) { closed = true; clearExchange(); clear(admission); clear(seed); } }
    @Override public String toString() { return "<redacted Beluga viewer availability codec>"; }
    static EnvelopeFailure failure(FailureCode code) { return new EnvelopeFailure(code); }
    private static EnvelopeFailure normalize(CryptoFailure error) {
        return failure(error.code() == BouncyCastlePairingCrypto.FailureCode.AUTHENTICATION_FAILED
                ? FailureCode.AUTHENTICATION_FAILED : FailureCode.PROVIDER_FAILED);
    }
    private static Event event(Kind kind, String exchange) { return new Event(kind, exchange, null, null); }
    private static Map<String, Object> parse(byte[] input, int maximum) throws EnvelopeFailure {
        try { return PairingBootstrapEnvelopeCodec.parseAvailabilityWire(input, maximum); }
        catch (PairingBootstrapEnvelopeCodec.EnvelopeFailure error) { throw failure(FailureCode.INVALID_WIRE); }
    }
    private static byte[] decode(String value, boolean url, int maximum) throws EnvelopeFailure {
        try { return PairingBootstrapEnvelopeCodec.decodeBase64(value, url, maximum); }
        catch (PairingBootstrapEnvelopeCodec.EnvelopeFailure error) { throw failure(FailureCode.INVALID_WIRE); }
    }
    private static String encode(byte[] value, boolean url) { return PairingBootstrapEnvelopeCodec.encodeBase64(value, url); }
    private static byte[] exchange(String value) throws EnvelopeFailure {
        if (value.length() != 22) throw failure(FailureCode.INVALID_WIRE);
        byte[] raw = decode(value, true, 16);
        if (raw.length != 16) { clear(raw); throw failure(FailureCode.INVALID_WIRE); } return raw;
    }
    private static void exact(Map<String, Object> fields, String... keys) throws EnvelopeFailure {
        if (fields.size() != keys.length) throw failure(FailureCode.INVALID_WIRE);
        for (String key : keys) if (!fields.containsKey(key)) throw failure(FailureCode.INVALID_WIRE);
    }
    private static String string(Map<String, Object> fields, String key) throws EnvelopeFailure {
        Object value = fields.get(key); if (!(value instanceof String)) throw failure(FailureCode.INVALID_WIRE); return (String) value;
    }
    private static long number(Map<String, Object> fields, String key) throws EnvelopeFailure {
        Object value = fields.get(key); if (!(value instanceof Long)) throw failure(FailureCode.INVALID_WIRE); return ((Long) value).longValue();
    }
    private static byte[] ascii(String value) { return value.getBytes(StandardCharsets.US_ASCII); }
    private static void clear(byte[] value) { if (value != null) Arrays.fill(value, (byte) 0); }
}
