package com.elamin.beluga.protocol;

import java.io.ByteArrayOutputStream;
import java.math.BigInteger;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.UUID;
import com.elamin.beluga.protocol.BouncyCastlePairingCrypto.CryptoFailure;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Commit;
import com.elamin.beluga.protocol.PairingCanonicalCodec.CommitFields;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Confirmation;
import com.elamin.beluga.protocol.PairingCanonicalCodec.ConfirmationFields;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Hello;
import com.elamin.beluga.protocol.PairingCanonicalCodec.HelloFields;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Phase;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Role;
import com.elamin.beluga.protocol.PairingPayloadDecoder.CommitPayload;
import com.elamin.beluga.protocol.PairingPayloadDecoder.ConfirmationPayload;
import com.elamin.beluga.protocol.PairingPayloadDecoder.HelloPayload;

/**
 * PRIVATE viewer authentication plus immutable persistable-record candidates.
 * No method grants send, storage acknowledgement, paired UI or transport authority.
 * Names follow the separately reviewed Foundation reference-profile codec/decoder.
 * Private immutable objects retain copied secret material in memory; no JVM wipe promise.
 */
public final class ViewerPairingAuthenticator {
    private ViewerPairingAuthenticator() { }
    public enum FailureCode {
        MALFORMED_INPUT, ROLE_CONFLICT, IDENTITY_MISMATCH, AUTHENTICATION_FAILED,
        TRANSCRIPT_MISMATCH, INVALID_COMMIT, INVALID_RECONNECT, SEQUENCE_EXHAUSTED, PROVIDER_FAILED
    }
    public static final class AuthFailure extends Exception {
        private static final long serialVersionUID = 1L;
        private final FailureCode code;
        private AuthFailure(FailureCode code) {
            super("Beluga viewer authentication refused: " + code.name()); this.code = code;
        }
        public FailureCode code() { return code; }
    }

    /** Raw-seed in-memory test handle; NOT Android Keystore enrollment or a storage receipt. */
    public static ViewerIdentity viewerIdentity(UUID deviceID, byte[] signingSeed) throws AuthFailure {
        require(deviceID != null && (deviceID.getMostSignificantBits() != 0 || deviceID.getLeastSignificantBits() != 0),
                FailureCode.MALFORMED_INPUT);
        byte[] seed = exact(signingSeed, 32);
        try {
            return new ViewerIdentity(new SigningIdentity(deviceID, seed, BouncyCastlePairingCrypto.ed25519PublicKey(seed)));
        } catch (CryptoFailure error) { throw normalized(error); }
        finally { clear(seed); }
    }

    public static final class ViewerIdentity {
        private final SigningIdentity signing;
        private ViewerIdentity(SigningIdentity signing) { this.signing = signing; }
        public UUID deviceID() { return signing.deviceID; }
        public byte[] signingPublicKey() { return signing.publicKey.clone(); }
        @Override public String toString() { return "<redacted in-memory Beluga viewer signing identity>"; }
    }

    /** Creates one local hello; caller supplies already admitted identity/ephemeral/random material. */
    public static PreparedViewer prepare(UUID deviceID, String displayName, byte[] signingSeed,
            byte[] invitationSecret, byte[] ephemeralPrivate, byte[] nonce) throws AuthFailure {
        try {
            Material local = material(deviceID, displayName, signingSeed, invitationSecret, ephemeralPrivate, nonce);
            byte[] tag = mac(local.invitation, PairingCanonicalCodec.helloPskInput(local.fields));
            byte[] signature = sign(local.seed,
                    PairingCanonicalCodec.helloSignatureInput(new Hello(local.fields, tag, new byte[64])));
            return new PreparedViewer(local, new Hello(local.fields, tag, signature));
        } catch (CryptoFailure error) { throw normalized(error); }
        catch (IllegalArgumentException ignored) { throw refused(FailureCode.MALFORMED_INPUT); }
    }

    /**
     * Revalidates a retained local hello, not a persistence/recovery admission shortcut.
     * Every unsigned field must match independently derived local material. Signature bytes
     * may differ across valid Ed25519 implementations, but MAC and signature must authenticate.
     */
    public static PreparedViewer authenticateRetainedLocalHello(UUID deviceID, String displayName,
            byte[] signingSeed, byte[] invitationSecret, byte[] ephemeralPrivate, byte[] nonce,
            HelloPayload retained) throws AuthFailure {
        require(retained != null, FailureCode.MALFORMED_INPUT);
        try {
            Material local = material(deviceID, displayName, signingSeed, invitationSecret, ephemeralPrivate, nonce);
            require(equal(PairingCanonicalCodec.unsignedHello(local.fields),
                    PairingCanonicalCodec.unsignedHello(retained.canonicalFields())), FailureCode.IDENTITY_MISMATCH);
            authenticateHello(local.invitation, retained);
            return new PreparedViewer(local, retained.canonicalMessage());
        } catch (CryptoFailure error) { throw normalized(error); }
        catch (IllegalArgumentException ignored) { throw refused(FailureCode.MALFORMED_INPUT); }
    }

    /** Exact local material plus authenticated/generated full viewer hello; not a paired state. */
    public static final class PreparedViewer {
        private final Material local;
        private final Hello hello;
        private PreparedViewer(Material local, Hello hello) { this.local = local; this.hello = hello; }
        public UUID deviceID() { return local.deviceID; }
        public byte[] signingPublicKey() { return local.publicKey.clone(); }
        public byte[] helloPayload() { return PairingCanonicalCodec.helloPayload(hello); }
        @Override public String toString() { return "<redacted prepared Beluga viewer hello>"; }
    }

    /** Host PSK+signature authentication happens before any peer X25519 agreement is attempted. */
    public static Agreement acceptHost(PreparedViewer viewer, HelloPayload host) throws AuthFailure {
        require(viewer != null && host != null, FailureCode.MALFORMED_INPUT);
        require(host.role() == Role.HOST && !host.deviceID().equals(viewer.local.deviceID), FailureCode.ROLE_CONFLICT);
        // Mirrors the eventual record's distinct remote identity requirement, before producing
        // material that a future reducer might attempt to persist.
        require(!equal(host.signingPublicKey(), viewer.local.publicKey), FailureCode.IDENTITY_MISMATCH);
        byte[] shared = null;
        byte[] input = null;
        try {
            authenticateHello(viewer.local.invitation, host);
            shared = BouncyCastlePairingCrypto.x25519Agreement(viewer.local.ephemeral, host.ephemeralKeyAgreementPublicKey());
            require(shared.length == 32 && !allZero(shared), FailureCode.AUTHENTICATION_FAILED);
            byte[] transcript = BouncyCastlePairingCrypto.sha256(
                    PairingCanonicalCodec.transcriptInput(host.canonicalMessage(), viewer.hello));
            input = new byte[52];
            System.arraycopy(viewer.local.invitation, 0, input, 0, 20);
            System.arraycopy(shared, 0, input, 20, 32);
            byte[] root = derive(input, transcript, "AudioStreamer.Pairing.Root.v1");
            UUID pair = derivedUUID(derive(root, transcript, "AudioStreamer.Pairing.ID.v1"));
            UUID commit = derivedUUID(derive(root, transcript, "AudioStreamer.Pairing.CommitID.v1"));
            return new Agreement(viewer.local, host, pair, commit, transcript, root);
        } catch (CryptoFailure error) { throw normalized(error); }
        catch (IllegalArgumentException ignored) { throw refused(FailureCode.MALFORMED_INPUT); }
        finally { clear(shared); clear(input); }
    }

    /** Immutable cryptographic agreement only; there is deliberately no raw-root or active getter. */
    public static final class Agreement {
        private final SigningIdentity local;
        private final UUID hostID, pairID, commitID;
        private final String hostName;
        private final byte[] hostKey, transcript, root;
        private Agreement(Material local, HelloPayload host, UUID pair, UUID commit, byte[] transcript, byte[] root) {
            // No reference to PreparedViewer/Material survives this boundary: invitation,
            // ephemeral private key, nonce and bootstrap hello can be dropped by their owner.
            this.local = new SigningIdentity(local.deviceID, local.seed, local.publicKey);
            hostID = host.deviceID(); hostName = host.displayName(); hostKey = host.signingPublicKey();
            pairID = pair; commitID = commit; this.transcript = transcript.clone(); this.root = root.clone();
            clear(root);
        }
        public UUID viewerDeviceID() { return local.deviceID; }
        public UUID hostDeviceID() { return hostID; }
        public String hostDisplayName() { return hostName; }
        public UUID pairID() { return pairID; }
        public UUID commitID() { return commitID; }
        public byte[] transcriptHash() { return transcript.clone(); }
        public byte[] hostSigningPublicKey() { return hostKey.clone(); }
        @Override public String toString() { return "<redacted Beluga viewer cryptographic agreement>"; }

        /** Authenticated candidate only. A trusted store must persist it before confirmation send. */
        public ViewerPairRecord makePendingRecord(VerifiedHostConfirmation proof, double createdAtEpochSeconds)
                throws AuthFailure {
            require(proof != null && proof.owner == this, FailureCode.IDENTITY_MISMATCH);
            return new ViewerPairRecord(pairID, commitID, local.deviceID, local.publicKey, hostID, hostKey,
                    hostName, createdAtEpochSeconds, transcript, root, RecordPhase.PENDING, null, 1L, 0L);
        }

        public VerifiedHostConfirmation authenticateHostConfirmation(ConfirmationPayload confirmation) throws AuthFailure {
            require(confirmation != null, FailureCode.MALFORMED_INPUT);
            require(confirmation.pairID().equals(pairID) && confirmation.senderDeviceID().equals(hostID)
                    && confirmation.senderRole() == Role.HOST && confirmation.recipientDeviceID().equals(local.deviceID)
                    && equal(confirmation.transcriptHash(), transcript), FailureCode.TRANSCRIPT_MISMATCH);
            byte[] key = null;
            try {
                key = derive(root, transcript, "AudioStreamer.Pairing.Confirmation.host.v1");
                byte[] expected = mac(key, PairingCanonicalCodec.confirmationMacInput(confirmation.canonicalFields()));
                require(equal(expected, confirmation.confirmationTag())
                        && BouncyCastlePairingCrypto.ed25519Verify(hostKey,
                        PairingCanonicalCodec.confirmationSignatureInput(confirmation.canonicalMessage()), confirmation.signature()),
                        FailureCode.AUTHENTICATION_FAILED);
                return new VerifiedHostConfirmation(this);
            } catch (CryptoFailure error) { throw normalized(error); }
            finally { clear(key); }
        }

        /** Stateless authenticity only: a later reducer MUST enforce proposal/completion ordering. */
        public VerifiedHostCommit authenticateHostCommit(CommitPayload commit, Phase expectedPhase) throws AuthFailure {
            require(commit != null && expectedPhase != null, FailureCode.MALFORMED_INPUT);
            require((expectedPhase == Phase.PROPOSAL || expectedPhase == Phase.COMPLETION)
                    && commit.phase() == expectedPhase && commit.pairID().equals(pairID) && commit.commitID().equals(commitID)
                    && commit.senderDeviceID().equals(hostID) && commit.senderRole() == Role.HOST
                    && commit.recipientDeviceID().equals(local.deviceID) && equal(commit.transcriptHash(), transcript),
                    FailureCode.INVALID_COMMIT);
            byte[] key = null;
            try {
                key = derive(root, transcript, commitLabel("host", expectedPhase));
                byte[] expected = mac(key, PairingCanonicalCodec.commitMacInput(commit.canonicalFields()));
                require(equal(expected, commit.commitTag())
                        && BouncyCastlePairingCrypto.ed25519Verify(hostKey,
                        PairingCanonicalCodec.commitSignatureInput(commit.canonicalMessage()), commit.signature()),
                        FailureCode.AUTHENTICATION_FAILED);
                return new VerifiedHostCommit(this, expectedPhase);
            } catch (CryptoFailure error) { throw normalized(error); }
            finally { clear(key); }
        }

        /** Non-authorizing construction: pending record+invitation binding MUST be durable before send. */
        public Confirmation constructUnsentViewerConfirmation(VerifiedHostConfirmation proof) throws AuthFailure {
            require(proof != null && proof.owner == this, FailureCode.IDENTITY_MISMATCH);
            byte[] key = null;
            try {
                ConfirmationFields fields = new ConfirmationFields(1, pairID, local.deviceID, Role.VIEWER, hostID, transcript);
                key = derive(root, transcript, "AudioStreamer.Pairing.Confirmation.viewer.v1");
                byte[] tag = mac(key, PairingCanonicalCodec.confirmationMacInput(fields));
                byte[] signature = sign(local.seed,
                        PairingCanonicalCodec.confirmationSignatureInput(new Confirmation(fields, tag, new byte[64])));
                return new Confirmation(fields, tag, signature);
            } catch (CryptoFailure error) { throw normalized(error); }
            finally { clear(key); }
        }

        /** Non-authorizing construction: acceptedIssued/active state MUST be durable before send. */
        public Commit constructUnsentViewerCommit(VerifiedHostCommit proof) throws AuthFailure {
            require(proof != null && proof.owner == this, FailureCode.IDENTITY_MISMATCH);
            require(proof.phase == Phase.PROPOSAL || proof.phase == Phase.COMPLETION, FailureCode.INVALID_COMMIT);
            Phase phase = proof.phase == Phase.PROPOSAL ? Phase.ACKNOWLEDGEMENT : Phase.ACTIVATION_ACKNOWLEDGEMENT;
            byte[] key = null;
            try {
                CommitFields fields = new CommitFields(1, pairID, commitID, local.deviceID, Role.VIEWER, hostID, transcript, phase);
                key = derive(root, transcript, commitLabel("viewer", phase));
                byte[] tag = mac(key, PairingCanonicalCodec.commitMacInput(fields));
                byte[] signature = sign(local.seed,
                        PairingCanonicalCodec.commitSignatureInput(new Commit(fields, tag, new byte[64])));
                return new Commit(fields, tag, signature);
            } catch (CryptoFailure error) { throw normalized(error); }
            finally { clear(key); }
        }
    }

    /** Closed proof of host message authenticity, not persistence or permission to transmit. */
    public static final class VerifiedHostConfirmation {
        private final Agreement owner;
        private VerifiedHostConfirmation(Agreement owner) { this.owner = owner; }
        @Override public String toString() { return "<redacted authenticated Beluga host confirmation>"; }
    }
    public static final class VerifiedHostCommit {
        private final Agreement owner;
        private final Phase phase;
        private VerifiedHostCommit(Agreement owner, Phase phase) { this.owner = owner; this.phase = phase; }
        public Phase phase() { return phase; }
        @Override public String toString() { return "<redacted authenticated Beluga host commit>"; }
    }

    public enum RecordPhase { PENDING, ACCEPTED_ISSUED, ACTIVE }

    /** Candidate plus exact retained response; neither field acknowledges storage or authorizes send. */
    public static final class RecordTransition {
        private final ViewerPairRecord record;
        private final byte[] response;
        private RecordTransition(ViewerPairRecord record, byte[] response) {
            this.record = record; this.response = response.clone();
        }
        public ViewerPairRecord record() { return record; }
        public byte[] unsentRetainedPayload() { return response.clone(); }
        @Override public String toString() { return "<redacted Beluga viewer record transition candidate>"; }
    }

    /** Recovery plan only. A later trusted availability/storage runner must authorize actual transmission. */
    public static final class RecordRecoveryAction {
        public enum Kind { AWAIT_PROPOSAL, RESEND_RETAINED }
        private final Kind kind;
        private final byte[] retained;
        private RecordRecoveryAction(Kind kind, byte[] retained) {
            this.kind = kind; this.retained = retained == null ? null : retained.clone();
        }
        public Kind kind() { return kind; }
        public byte[] unsentRetainedPayload() { return retained == null ? null : retained.clone(); }
        @Override public String toString() { return "<redacted Beluga viewer record recovery plan>"; }
    }

    /** Contains private root material. Use only an eventual encrypted private store, NEVER logs/defaults. */
    public static final class PrivateRecordEncoding {
        private final byte[] bytes;
        private PrivateRecordEncoding(byte[] bytes) { this.bytes = bytes.clone(); }
        public byte[] copyForPrivateStorage() { return bytes.clone(); }
        @Override public String toString() { return "<redacted private Beluga viewer record encoding>"; }
    }

    /**
     * Opaque immutable record candidate. No seed, bootstrap owner, identity handle or raw-root getter.
     * Phase names describe protocol contents, not proof of a durable write or connected/paired UI.
     */
    public static final class ViewerPairRecord {
        public static final int MAXIMUM_PRIVATE_RECORD_BYTES = 16 * 1024;
        private static final byte[] ENVELOPE = "BVR-SIG1".getBytes(StandardCharsets.US_ASCII);
        private static final byte[] STORAGE_DOMAIN = "Beluga.Android.PrivateViewerPairRecord.Signature.v1"
                .getBytes(StandardCharsets.US_ASCII);
        private final UUID pairID, commitID, localID, remoteID;
        private final byte[] localKey, remoteKey, transcript, root, recovery;
        private final String remoteName;
        private final double createdAt;
        private final RecordPhase phase;
        // Raw big-endian UInt64 bits, not signed quantities; reconnect reserves one immutable successor.
        private final long nextOutbound, highestAccepted;

        private ViewerPairRecord(UUID pair, UUID commit, UUID local, byte[] localKey, UUID remote,
                byte[] remoteKey, String remoteName, double createdAt, byte[] transcript, byte[] root,
                RecordPhase phase, byte[] recovery, long nextOutbound, long highestAccepted) throws AuthFailure {
            require(nonzeroID(pair) && nonzeroID(commit) && nonzeroID(local) && nonzeroID(remote)
                    && !local.equals(remote) && phase != null && nextOutbound != 0
                    && !Double.isNaN(createdAt) && !Double.isInfinite(createdAt), FailureCode.MALFORMED_INPUT);
            this.pairID = pair; this.commitID = commit; this.localID = local; this.remoteID = remote;
            this.localKey = exact(localKey, 32); this.remoteKey = exact(remoteKey, 32);
            require(!equal(this.localKey, this.remoteKey), FailureCode.IDENTITY_MISMATCH);
            try { this.remoteName = PairingDisplayNamePolicy.validate(remoteName); }
            catch (IllegalArgumentException ignored) { throw refused(FailureCode.MALFORMED_INPUT); }
            this.createdAt = createdAt; this.transcript = exact(transcript, 32); this.root = exact(root, 32);
            this.phase = phase; this.nextOutbound = nextOutbound; this.highestAccepted = highestAccepted;
            require(recovery == null || (recovery.length > 0 && recovery.length <= PairingCanonicalCodec.MAXIMUM_ENCODED_BYTES),
                    FailureCode.MALFORMED_INPUT);
            this.recovery = recovery == null ? null : recovery.clone();
            try {
                // This private format admits only records produced by the actual v1 Agreement formulas,
                // not a generic importer for arbitrary Swift Codable records.
                require(pair.equals(derivedUUID(derive(this.root, this.transcript, "AudioStreamer.Pairing.ID.v1")))
                        && commit.equals(derivedUUID(derive(this.root, this.transcript, "AudioStreamer.Pairing.CommitID.v1"))),
                        FailureCode.MALFORMED_INPUT);
                validateRecovery();
            } catch (CryptoFailure error) { throw normalized(error); }
        }

        public UUID pairID() { return pairID; }
        public UUID commitID() { return commitID; }
        public UUID viewerDeviceID() { return localID; }
        public UUID hostDeviceID() { return remoteID; }
        public String hostDisplayName() { return remoteName; }
        public double createdAtEpochSeconds() { return createdAt; }
        public RecordPhase phase() { return phase; }
        public String nextOutboundReconnectSequence() { return unsignedDecimal(nextOutbound); }
        public String highestAcceptedReconnectSequence() { return unsignedDecimal(highestAccepted); }
        /** Routing capability only; selection, durable admission, socket and media authority remain external. */
        public ViewerAvailabilityLocator availabilityLocator() throws AuthFailure {
            require(phase == RecordPhase.ACTIVE, FailureCode.INVALID_RECONNECT);
            try { return ViewerAvailabilityLocator.derive(root, pairID, transcript); }
            catch (CryptoFailure error) { throw normalized(error); }
        }
        @Override public String toString() { return "<redacted immutable Beluga viewer record candidate>"; }

        public RecordRecoveryAction recoveryAction() {
            return phase == RecordPhase.PENDING
                    ? new RecordRecoveryAction(RecordRecoveryAction.Kind.AWAIT_PROPOSAL, null)
                    : new RecordRecoveryAction(RecordRecoveryAction.Kind.RESEND_RETAINED, recovery);
        }

        /**
         * Reserves the next unsigned sequence in a candidate, not the durable record. The caller
         * MUST persist the frozen exact candidate before sending any request. Supplied ephemeral
         * material/nonce must be cryptographically fresh in the eventual session composition.
         */
        public ReconnectPreparation prepareReconnect(ViewerIdentity identity, byte[] ephemeralPrivate, byte[] nonce)
                throws AuthFailure {
            return prepareReconnect(identity, ephemeralPrivate, nonce, null);
        }

        /** Package-only authenticated retained-request reconstruction; never a raw-secret import. */
        ReconnectPreparation authenticateRetainedReconnect(ViewerIdentity identity, byte[] ephemeralPrivate,
                byte[] nonce, ReconnectMessages.Request retained) throws AuthFailure {
            require(retained != null, FailureCode.MALFORMED_INPUT);
            return prepareReconnect(identity, ephemeralPrivate, nonce, retained);
        }

        private ReconnectPreparation prepareReconnect(ViewerIdentity identity, byte[] ephemeralPrivate,
                byte[] nonce, ReconnectMessages.Request retained) throws AuthFailure {
            validateIdentity(identity);
            require(phase == RecordPhase.ACTIVE, FailureCode.INVALID_RECONNECT);
            require(nextOutbound != -1L, FailureCode.SEQUENCE_EXHAUSTED);
            byte[] privateKey = exact(ephemeralPrivate, 32), ownedNonce = null, signature = null;
            try {
                ownedNonce = exact(nonce, 32);
                byte[] publicKey = BouncyCastlePairingCrypto.x25519PublicKey(privateKey);
                ReconnectMessages.Request unsigned = new ReconnectMessages.Request(1, pairID, localID, Role.VIEWER,
                        remoteID, unsignedDecimal(nextOutbound), publicKey, ownedNonce, new byte[64]);
                ReconnectMessages.Request request;
                if (retained == null) {
                    signature = sign(identity.signing.seed, ReconnectMessages.requestSignatureInput(unsigned));
                    request = new ReconnectMessages.Request(1, pairID, localID, Role.VIEWER, remoteID,
                            unsignedDecimal(nextOutbound), publicKey, ownedNonce, signature);
                } else {
                    require(equal(ReconnectMessages.unsignedRequest(unsigned), ReconnectMessages.unsignedRequest(retained)),
                            FailureCode.IDENTITY_MISMATCH);
                    require(BouncyCastlePairingCrypto.ed25519Verify(localKey,
                            ReconnectMessages.requestSignatureInput(unsigned), retained.signature()), FailureCode.AUTHENTICATION_FAILED);
                    request = retained;
                }
                // UInt64 max is unusable on the NEXT attempt. Signed wrap here preserves UInt64 bits.
                ViewerPairRecord candidate = new ViewerPairRecord(pairID, commitID, localID, localKey, remoteID,
                        remoteKey, remoteName, createdAt, transcript, root, phase, recovery, nextOutbound + 1L, highestAccepted);
                return new ReconnectPreparation(this, candidate, candidate.encodeForPrivateStorage(identity), request, privateKey);
            } catch (CryptoFailure error) { throw normalized(error); }
            catch (IllegalArgumentException ignored) { throw refused(FailureCode.MALFORMED_INPUT); }
            finally { clear(privateKey); clear(ownedNonce); clear(signature); }
        }

        /** Reauthenticates even a duplicate proposal; exact retained ACK is never regenerated. */
        public RecordTransition prepareAcknowledgement(CommitPayload proposal, ViewerIdentity identity) throws AuthFailure {
            validateIdentity(identity);
            require(phase == RecordPhase.PENDING || phase == RecordPhase.ACCEPTED_ISSUED, FailureCode.INVALID_COMMIT);
            try {
                verifyCommit(proposal, Phase.PROPOSAL, false);
                if (phase == RecordPhase.ACCEPTED_ISSUED) return new RecordTransition(this, recovery);
                byte[] response = localCommit(Phase.ACKNOWLEDGEMENT, identity);
                ViewerPairRecord next = successor(RecordPhase.ACCEPTED_ISSUED, response);
                return new RecordTransition(next, response);
            } catch (CryptoFailure error) { throw normalized(error); }
        }

        /** Reauthenticates duplicate completion; exact retained activation is never regenerated. */
        public RecordTransition acceptCompletion(CommitPayload completion, ViewerIdentity identity) throws AuthFailure {
            validateIdentity(identity);
            require(phase == RecordPhase.ACCEPTED_ISSUED || phase == RecordPhase.ACTIVE, FailureCode.INVALID_COMMIT);
            try {
                verifyCommit(completion, Phase.COMPLETION, false);
                if (phase == RecordPhase.ACTIVE) return new RecordTransition(this, recovery);
                byte[] response = localCommit(Phase.ACTIVATION_ACKNOWLEDGEMENT, identity);
                ViewerPairRecord next = successor(RecordPhase.ACTIVE, response);
                return new RecordTransition(next, response);
            } catch (CryptoFailure error) { throw normalized(error); }
        }

        /** Local signature is tamper/identity binding, NOT encryption, freshness or storage authority. */
        public PrivateRecordEncoding encodeForPrivateStorage(ViewerIdentity identity) throws AuthFailure {
            validateIdentity(identity);
            byte[] body = body(), signature = null;
            try {
                signature = sign(identity.signing.seed, signatureInput(body));
                byte[] encoded = ByteBuffer.allocate(ENVELOPE.length + 4 + body.length + 64)
                        .put(ENVELOPE).putInt(body.length).put(body).put(signature).array();
                require(encoded.length <= MAXIMUM_PRIVATE_RECORD_BYTES, FailureCode.MALFORMED_INPUT);
                return new PrivateRecordEncoding(encoded);
            } catch (CryptoFailure error) { throw normalized(error); }
            finally { clear(body); clear(signature); }
        }

        /**
         * Verify against trusted caller identity BEFORE decoding body fields. No embedded-key authority.
         * A correctly signed old encoding is still replayable: freshness belongs to the future store.
         */
        public static ViewerPairRecord restore(byte[] privateEncoding, ViewerIdentity identity) throws AuthFailure {
            require(identity != null && privateEncoding != null && privateEncoding.length >= ENVELOPE.length + 4 + 64
                    && privateEncoding.length <= MAXIMUM_PRIVATE_RECORD_BYTES, FailureCode.MALFORMED_INPUT);
            byte[] owned = privateEncoding.clone(), body = null, signature = null;
            try {
                ByteBuffer envelope = ByteBuffer.wrap(owned);
                byte[] header = new byte[ENVELOPE.length]; envelope.get(header);
                require(equal(header, ENVELOPE), FailureCode.MALFORMED_INPUT);
                int length = envelope.getInt();
                require(length >= 0 && length == owned.length - ENVELOPE.length - 4 - 64, FailureCode.MALFORMED_INPUT);
                body = new byte[length]; envelope.get(body); signature = new byte[64]; envelope.get(signature);
                require(BouncyCastlePairingCrypto.ed25519Verify(identity.signing.publicKey, signatureInput(body), signature),
                        FailureCode.AUTHENTICATION_FAILED);
                BodyReader reader = new BodyReader(body);
                require(reader.unsignedByte() == 1 && reader.unsignedByte() == 1, FailureCode.MALFORMED_INPUT);
                RecordPhase phase;
                switch (reader.unsignedByte()) {
                    case 1: phase = RecordPhase.PENDING; break;
                    case 2: phase = RecordPhase.ACCEPTED_ISSUED; break;
                    case 3: phase = RecordPhase.ACTIVE; break;
                    default: throw refused(FailureCode.MALFORMED_INPUT);
                }
                // Fixed viewer-only role encoding. acceptedReceived is deliberately not representable.
                require(reader.unsignedByte() == 2 && reader.unsignedByte() == 1, FailureCode.MALFORMED_INPUT);
                UUID pair = reader.uuid(), commit = reader.uuid(), local = reader.uuid(), remote = reader.uuid();
                byte[] localKey = reader.fixed(32), remoteKey = reader.fixed(32);
                String name = reader.name(); double createdAt = Double.longBitsToDouble(reader.longBits());
                byte[] transcript = reader.fixed(32), root = reader.fixed(32);
                long next = reader.longBits(), highest = reader.longBits();
                int recoveryLength = reader.integer();
                require(recoveryLength >= 0 && recoveryLength <= PairingCanonicalCodec.MAXIMUM_ENCODED_BYTES,
                        FailureCode.MALFORMED_INPUT);
                byte[] recovery = recoveryLength == 0 ? null : reader.fixed(recoveryLength);
                require(reader.finished(), FailureCode.MALFORMED_INPUT);
                ViewerPairRecord result = new ViewerPairRecord(pair, commit, local, localKey, remote, remoteKey,
                        name, createdAt, transcript, root, phase, recovery, next, highest);
                result.validateIdentity(identity);
                require(equal(result.body(), body), FailureCode.MALFORMED_INPUT);
                return result;
            } catch (CryptoFailure error) { throw normalized(error); }
            finally { clear(owned); clear(body); clear(signature); }
        }

        private ViewerPairRecord successor(RecordPhase phase, byte[] retained) throws AuthFailure {
            return new ViewerPairRecord(pairID, commitID, localID, localKey, remoteID, remoteKey, remoteName,
                    createdAt, transcript, root, phase, retained, nextOutbound, highestAccepted);
        }
        private void validateIdentity(ViewerIdentity identity) throws AuthFailure {
            require(identity != null, FailureCode.MALFORMED_INPUT);
            require(localID.equals(identity.signing.deviceID) && equal(localKey, identity.signing.publicKey),
                    FailureCode.IDENTITY_MISMATCH);
        }
        private byte[] localCommit(Phase phase, ViewerIdentity identity) throws CryptoFailure {
            CommitFields fields = new CommitFields(1, pairID, commitID, localID, Role.VIEWER, remoteID, transcript, phase);
            byte[] key = null;
            try {
                key = derive(root, transcript, commitLabel("viewer", phase));
                byte[] tag = mac(key, PairingCanonicalCodec.commitMacInput(fields));
                byte[] signature = sign(identity.signing.seed,
                        PairingCanonicalCodec.commitSignatureInput(new Commit(fields, tag, new byte[64])));
                return PairingCanonicalCodec.commitPayload(new Commit(fields, tag, signature));
            } finally { clear(key); }
        }
        private void verifyCommit(CommitPayload commit, Phase expectedPhase, boolean local) throws AuthFailure, CryptoFailure {
            UUID sender = local ? localID : remoteID, recipient = local ? remoteID : localID;
            Role role = local ? Role.VIEWER : Role.HOST;
            byte[] key = null;
            require(commit != null && commit.phase() == expectedPhase && commit.pairID().equals(pairID)
                    && commit.commitID().equals(commitID) && commit.senderDeviceID().equals(sender)
                    && commit.senderRole() == role && commit.recipientDeviceID().equals(recipient)
                    && equal(commit.transcriptHash(), transcript), FailureCode.INVALID_COMMIT);
            try {
                key = derive(root, transcript, commitLabel(local ? "viewer" : "host", expectedPhase));
                byte[] expected = mac(key, PairingCanonicalCodec.commitMacInput(commit.canonicalFields()));
                require(equal(expected, commit.commitTag())
                        && BouncyCastlePairingCrypto.ed25519Verify(local ? localKey : remoteKey,
                        PairingCanonicalCodec.commitSignatureInput(commit.canonicalMessage()), commit.signature()),
                        FailureCode.AUTHENTICATION_FAILED);
            } finally { clear(key); }
        }
        private void validateRecovery() throws AuthFailure, CryptoFailure {
            if (phase == RecordPhase.PENDING) {
                require(recovery == null, FailureCode.INVALID_COMMIT); return;
            }
            require(recovery != null, FailureCode.INVALID_COMMIT);
            try {
                PairingPayloadDecoder.Payload payload = PairingPayloadDecoder.decode(recovery);
                require(payload instanceof CommitPayload, FailureCode.INVALID_COMMIT);
                CommitPayload commit = (CommitPayload) payload;
                verifyCommit(commit, phase == RecordPhase.ACCEPTED_ISSUED
                        ? Phase.ACKNOWLEDGEMENT : Phase.ACTIVATION_ACKNOWLEDGEMENT, true);
                require(equal(recovery, PairingCanonicalCodec.commitPayload(commit.canonicalMessage())), FailureCode.MALFORMED_INPUT);
            } catch (PairingPayloadDecoder.DecodeFailure ignored) { throw refused(FailureCode.MALFORMED_INPUT); }
        }

        private byte[] body() {
            ByteArrayOutputStream output = new ByteArrayOutputStream();
            output.write(1); output.write(1);
            output.write(phase == RecordPhase.PENDING ? 1 : phase == RecordPhase.ACCEPTED_ISSUED ? 2 : 3);
            output.write(2); output.write(1);
            writeUUID(output, pairID); writeUUID(output, commitID); writeUUID(output, localID); writeUUID(output, remoteID);
            write(output, localKey); write(output, remoteKey);
            byte[] name = remoteName == null ? null : remoteName.getBytes(StandardCharsets.UTF_8);
            write(output, ByteBuffer.allocate(4).putInt(name == null ? -1 : name.length).array());
            if (name != null) write(output, name);
            write(output, ByteBuffer.allocate(8).putLong(Double.doubleToRawLongBits(createdAt)).array());
            write(output, transcript); write(output, root);
            write(output, ByteBuffer.allocate(16).putLong(nextOutbound).putLong(highestAccepted).array());
            write(output, ByteBuffer.allocate(4).putInt(recovery == null ? 0 : recovery.length).array());
            if (recovery != null) write(output, recovery);
            return output.toByteArray();
        }
        private static byte[] signatureInput(byte[] body) {
            return ByteBuffer.allocate(STORAGE_DOMAIN.length + 1 + 8 + body.length)
                    .put(STORAGE_DOMAIN).put((byte) 0).putLong(body.length).put(body).array();
        }
        private static String unsignedDecimal(long bits) {
            return new BigInteger(1, ByteBuffer.allocate(8).putLong(bits).array()).toString();
        }
        private static void writeUUID(ByteArrayOutputStream output, UUID id) {
            write(output, ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array());
        }
        private static void write(ByteArrayOutputStream output, byte[] bytes) { output.write(bytes, 0, bytes.length); }
        private static boolean nonzeroID(UUID id) {
            return id != null && (id.getMostSignificantBits() != 0 || id.getLeastSignificantBits() != 0);
        }
        private static final class BodyReader {
            private final ByteBuffer bytes;
            private BodyReader(byte[] body) { bytes = ByteBuffer.wrap(body); }
            private byte[] fixed(int length) throws AuthFailure {
                require(length >= 0 && bytes.remaining() >= length, FailureCode.MALFORMED_INPUT);
                byte[] value = new byte[length]; bytes.get(value); return value;
            }
            private int unsignedByte() throws AuthFailure { return fixed(1)[0] & 255; }
            private int integer() throws AuthFailure { return ByteBuffer.wrap(fixed(4)).getInt(); }
            private long longBits() throws AuthFailure { return ByteBuffer.wrap(fixed(8)).getLong(); }
            private UUID uuid() throws AuthFailure { return new UUID(longBits(), longBits()); }
            private String name() throws AuthFailure {
                int length = integer(); if (length == -1) return null;
                require(length >= 0 && length <= 128, FailureCode.MALFORMED_INPUT);
                try {
                    return StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                            .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(fixed(length))).toString();
                } catch (CharacterCodingException ignored) { throw refused(FailureCode.MALFORMED_INPUT); }
            }
            private boolean finished() { return !bytes.hasRemaining(); }
        }
    }

    /**
     * Unsent reconnect reservation plus ephemeral initiator. It has no storage receipt or owner
     * lease. Completion reauthenticates like Swift; repeated verification is not replay admission.
     * Closing drops this object's ephemeral copy; managed-memory erasure is not guaranteed.
     */
    public static final class ReconnectPreparation implements AutoCloseable {
        private final ViewerPairRecord predecessor, candidate;
        private final PrivateRecordEncoding encoding;
        private final ReconnectMessages.Request request;
        private final byte[] ephemeral;
        private boolean closed;
        private ReconnectPreparation(ViewerPairRecord predecessor, ViewerPairRecord candidate,
                PrivateRecordEncoding encoding, ReconnectMessages.Request request, byte[] ephemeral) {
            this.predecessor = predecessor; this.candidate = candidate; this.encoding = encoding;
            this.request = request; this.ephemeral = ephemeral.clone();
        }
        public ViewerPairRecord candidate() { return candidate; }
        public PrivateRecordEncoding candidateEncoding() { return encoding; }
        public ReconnectMessages.Request request() { return request; }
        public byte[] requestPayload() { return ReconnectMessages.requestPayload(request); }
        synchronized boolean matchesPredecessor(ViewerPairRecord actual) throws AuthFailure {
            byte[] expected = null, observed = null;
            try {
                require(!closed && actual != null, FailureCode.INVALID_RECONNECT);
                expected = predecessor.body(); observed = actual.body();
                return equal(expected, observed);
            } finally { clear(expected); clear(observed); }
        }
        /** Verifies all response binding and host signature before peer X25519 processing. */
        public synchronized SessionCredential complete(ReconnectMessages.Response response) throws AuthFailure {
            require(!closed && response != null, FailureCode.INVALID_RECONNECT);
            byte[] requestDigest = null, shared = null, transcriptHash = null, keyMaterial = null, sessionRoot = null;
            try {
                requestDigest = BouncyCastlePairingCrypto.sha256(ReconnectMessages.fullRequest(request));
                require(response.pairID().equals(predecessor.pairID)
                        && response.requesterDeviceID().equals(predecessor.localID)
                        && response.responderDeviceID().equals(predecessor.remoteID)
                        && response.responderRole() == Role.HOST && response.requestSequence().equals(request.sequence())
                        && equal(response.requestDigest(), requestDigest), FailureCode.INVALID_RECONNECT);
                require(BouncyCastlePairingCrypto.ed25519Verify(predecessor.remoteKey,
                        ReconnectMessages.responseSignatureInput(response), response.signature()), FailureCode.AUTHENTICATION_FAILED);
                shared = BouncyCastlePairingCrypto.x25519Agreement(ephemeral, response.ephemeralKeyAgreementPublicKey());
                require(shared.length == 32 && !allZero(shared), FailureCode.AUTHENTICATION_FAILED);
                transcriptHash = BouncyCastlePairingCrypto.sha256(ReconnectMessages.transcriptInput(request, response));
                keyMaterial = new byte[64];
                System.arraycopy(predecessor.root, 0, keyMaterial, 0, 32); System.arraycopy(shared, 0, keyMaterial, 32, 32);
                sessionRoot = derive(keyMaterial, transcriptHash, "AudioStreamer.Reconnect.SessionRoot.v1");
                return SessionCredential.deriveSession(sessionRoot, transcriptHash);
            } catch (CryptoFailure error) { throw normalized(error); }
            catch (IllegalArgumentException ignored) { throw refused(FailureCode.MALFORMED_INPUT); }
            finally { clear(requestDigest); clear(shared); clear(transcriptHash); clear(keyMaterial); clear(sessionRoot); }
        }
        @Override public synchronized void close() { closed = true; clear(ephemeral); }
        @Override public String toString() { return "<redacted unsent Beluga reconnect preparation>"; }
    }

    /** Fresh in-memory session keys only. Not Codable, durable, connected, or a native lease. */
    public static final class SessionCredential implements AutoCloseable {
        public enum Direction { HOST_TO_VIEWER, VIEWER_TO_HOST }
        private static final int MAXIMUM_PAYLOAD = 65_536;
        private static final String CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
        private final String channel;
        private final byte[] admission, hostToViewer, viewerToHost;
        private boolean closed;
        private SessionCredential(byte[] channel, byte[] admission, byte[] host, byte[] viewer) throws AuthFailure {
            require(channel.length == 32 && admission.length == 32 && host.length == 32 && viewer.length == 32
                    && !equal(host, viewer), FailureCode.MALFORMED_INPUT);
            this.channel = crockford(channel); this.admission = admission.clone();
            hostToViewer = host.clone(); viewerToHost = viewer.clone();
        }
        private static SessionCredential deriveSession(byte[] root, byte[] transcript) throws CryptoFailure, AuthFailure {
            byte[] salt = null, channel = null, admission = null, host = null, viewer = null;
            try {
                salt = ReconnectMessages.domain("AudioStreamer.DurableRendezvous.Salt.v1", transcript,
                        "session".getBytes(StandardCharsets.UTF_8));
                channel = derive(root, salt, "AudioStreamer.DurableRendezvous.session.channel.v1");
                admission = derive(root, salt, "AudioStreamer.DurableRendezvous.session.admission.v1");
                host = derive(root, salt, "AudioStreamer.DurableRendezvous.session.host-to-viewer.v1");
                viewer = derive(root, salt, "AudioStreamer.DurableRendezvous.session.viewer-to-host.v1");
                return new SessionCredential(channel, admission, host, viewer);
            } finally { clear(salt); clear(channel); clear(admission); clear(host); clear(viewer); }
        }
        synchronized String channelID() throws AuthFailure {
            require(!closed, FailureCode.INVALID_RECONNECT); return channel;
        }
        synchronized String admissionProofForTransport() throws AuthFailure {
            require(!closed, FailureCode.INVALID_RECONNECT);
            return ReconnectMessages.base64(admission).replace('+', '-').replace('/', '_').replace("=", "");
        }
        /** Caller owns exact wire AAD, fresh nonce allocation and replay policy; none is implied here. */
        synchronized byte[] sealForTransport(Direction direction, byte[] plaintext, byte[] nonce, byte[] aad)
                throws AuthFailure {
            require(!closed && direction != null && plaintext != null && plaintext.length <= MAXIMUM_PAYLOAD
                    && nonce != null && nonce.length == 12 && aad != null && aad.length <= ReconnectMessages.MAXIMUM_BYTES,
                    FailureCode.MALFORMED_INPUT);
            try { return BouncyCastlePairingCrypto.sealCombined(key(direction), nonce, plaintext, aad); }
            catch (CryptoFailure error) { throw normalized(error); }
        }
        synchronized byte[] openForTransport(Direction direction, byte[] combined, byte[] aad) throws AuthFailure {
            require(!closed && direction != null && combined != null && combined.length >= 28
                    && combined.length <= MAXIMUM_PAYLOAD + 28 && aad != null && aad.length <= ReconnectMessages.MAXIMUM_BYTES,
                    FailureCode.MALFORMED_INPUT);
            try { return BouncyCastlePairingCrypto.openCombined(key(direction), combined, aad); }
            catch (CryptoFailure error) { throw normalized(error); }
        }
        private byte[] key(Direction direction) { return direction == Direction.HOST_TO_VIEWER ? hostToViewer : viewerToHost; }
        private static String crockford(byte[] bytes) {
            StringBuilder result = new StringBuilder(52); int accumulator = 0, bits = 0;
            for (byte value : bytes) {
                accumulator = (accumulator << 8) | (value & 255); bits += 8;
                while (bits >= 5) { bits -= 5; result.append(CROCKFORD.charAt((accumulator >>> bits) & 31)); }
            }
            if (bits > 0) result.append(CROCKFORD.charAt((accumulator << (5 - bits)) & 31));
            return result.toString();
        }
        @Override public synchronized void close() { closed = true; clear(admission); clear(hostToViewer); clear(viewerToHost); }
        @Override public String toString() { return "<redacted fresh Beluga session credential>"; }
    }

    private static final class SigningIdentity {
        private final UUID deviceID;
        private final byte[] seed, publicKey;
        private SigningIdentity(UUID deviceID, byte[] seed, byte[] publicKey) {
            this.deviceID = deviceID; this.seed = seed.clone(); this.publicKey = publicKey.clone();
        }
    }
    private static final class Material {
        private final UUID deviceID;
        private final byte[] seed, invitation, ephemeral, publicKey;
        private final HelloFields fields;
        private Material(UUID id, byte[] seed, byte[] invitation, byte[] ephemeral, byte[] publicKey, HelloFields fields) {
            deviceID = id; this.seed = seed.clone(); this.invitation = invitation.clone(); this.ephemeral = ephemeral.clone();
            this.publicKey = publicKey.clone(); this.fields = fields;
        }
    }
    private static Material material(UUID id, String name, byte[] seed, byte[] invitation, byte[] ephemeral, byte[] nonce)
            throws AuthFailure, CryptoFailure {
        byte[] ownedSeed = exact(seed, 32), ownedInvitation = null, ownedEphemeral = null, ownedNonce = null;
        try {
            ownedInvitation = exact(invitation, 20); ownedEphemeral = exact(ephemeral, 32); ownedNonce = exact(nonce, 32);
            require(id != null && (id.getMostSignificantBits() != 0 || id.getLeastSignificantBits() != 0), FailureCode.MALFORMED_INPUT);
            byte[] publicKey = BouncyCastlePairingCrypto.ed25519PublicKey(ownedSeed);
            byte[] ephemeralPublic = BouncyCastlePairingCrypto.x25519PublicKey(ownedEphemeral);
            HelloFields fields = new HelloFields(1, id, Role.VIEWER, name, publicKey, ephemeralPublic, ownedNonce);
            return new Material(id, ownedSeed, ownedInvitation, ownedEphemeral, publicKey, fields);
        } finally { clear(ownedSeed); clear(ownedInvitation); clear(ownedEphemeral); clear(ownedNonce); }
    }
    private static void authenticateHello(byte[] invitation, HelloPayload hello) throws AuthFailure, CryptoFailure {
        byte[] expected = mac(invitation, PairingCanonicalCodec.helloPskInput(hello.canonicalFields()));
        require(equal(expected, hello.authenticationTag()) && BouncyCastlePairingCrypto.ed25519Verify(hello.signingPublicKey(),
                PairingCanonicalCodec.helloSignatureInput(hello.canonicalMessage()), hello.signature()), FailureCode.AUTHENTICATION_FAILED);
    }
    private static byte[] derive(byte[] input, byte[] salt, String label) throws CryptoFailure {
        return BouncyCastlePairingCrypto.hkdfSha256(input, salt, label.getBytes(StandardCharsets.UTF_8), 32);
    }
    private static byte[] mac(byte[] key, byte[] input) throws CryptoFailure { return BouncyCastlePairingCrypto.hmacSha256(key, input); }
    private static byte[] sign(byte[] seed, byte[] input) throws CryptoFailure { return BouncyCastlePairingCrypto.ed25519Sign(seed, input); }
    private static String commitLabel(String role, Phase phase) {
        String name;
        switch (phase) {
            case PROPOSAL: name = "proposal"; break;
            case ACKNOWLEDGEMENT: name = "acknowledgement"; break;
            case COMPLETION: name = "completion"; break;
            case ACTIVATION_ACKNOWLEDGEMENT: name = "activationAcknowledgement"; break;
            default: throw new IllegalArgumentException("Invalid Beluga phase");
        }
        return "AudioStreamer.Pairing.Commit." + role + "." + name + ".v1";
    }
    private static UUID derivedUUID(byte[] bytes) {
        byte[] first = Arrays.copyOf(bytes, 16); clear(bytes);
        first[6] = (byte) ((first[6] & 15) | 0x50); first[8] = (byte) ((first[8] & 63) | 0x80);
        ByteBuffer buffer = ByteBuffer.wrap(first);
        return new UUID(buffer.getLong(), buffer.getLong());
    }
    private static boolean equal(byte[] a, byte[] b) {
        if (a.length != b.length) return false;
        int difference = 0; for (int i = 0; i < a.length; i++) difference |= a[i] ^ b[i]; return difference == 0;
    }
    private static boolean allZero(byte[] bytes) { int bits = 0; for (byte value : bytes) bits |= value; return bits == 0; }
    private static byte[] exact(byte[] bytes, int length) throws AuthFailure {
        require(bytes != null && bytes.length == length, FailureCode.MALFORMED_INPUT); return bytes.clone();
    }
    private static void clear(byte[] bytes) { if (bytes != null) Arrays.fill(bytes, (byte) 0); }
    private static void require(boolean value, FailureCode code) throws AuthFailure { if (!value) throw refused(code); }
    private static AuthFailure refused(FailureCode code) { return new AuthFailure(code); }
    private static AuthFailure normalized(CryptoFailure error) {
        return refused(error.code() == BouncyCastlePairingCrypto.FailureCode.AUTHENTICATION_FAILED
                ? FailureCode.AUTHENTICATION_FAILED : FailureCode.PROVIDER_FAILED);
    }
}
