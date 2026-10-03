package com.elamin.beluga.protocol;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.Base64;
import java.util.Locale;
import java.util.Map;
import java.util.TreeMap;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Commit;
import com.elamin.beluga.protocol.PairingCanonicalCodec.CommitFields;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Phase;
import com.elamin.beluga.protocol.PairingPayloadDecoder.CommitPayload;
import com.elamin.beluga.protocol.PairingPayloadDecoder.ConfirmationPayload;
import com.elamin.beluga.protocol.PairingPayloadDecoder.HelloPayload;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.Agreement;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.AuthFailure;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.FailureCode;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.PreparedViewer;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.RecordPhase;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.RecordRecoveryAction;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.RecordTransition;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.ViewerIdentity;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.ViewerPairRecord;

/** Public fixed seeds only. External signed malformed bodies are TEST fixtures, not production bypasses. */
public final class ViewerPairRecordTest {
    private static final String FIXTURE_SHA = "7d8a58cd34400271d0c68ac1e263450c4ad4978337ae1bb87246362a6d0ec06a";
    private static final String DOMAIN = "Beluga.Android.PrivateViewerPairRecord.Signature.v1";
    private static final UUID OTHER_ID = UUID.fromString("99999999-8888-7777-6666-555555555555");
    private static final double CREATED_AT = 1700000000.25;
    private static Map<String, byte[]> fixture;
    private static int assertions;
    private ViewerPairRecordTest() { }

    public static void main(String[] arguments) throws Exception {
        check(arguments.length == 1, "explicit hash-checked public fixture path required");
        fixture = load(Path.of(arguments[0]));
        testExactAgreementFactoryAndOrderedImmutableTransitions();
        testAuthenticatedEquivalentReplayUsesExactRetainedBytes();
        testPrivateEncodingRoundtripAndIndependentLayout();
        testOuterSignatureFramingAndTrustedIdentity();
        testCorrectlySignedMalformedBodies();
        testRecoveryCommitAuthenticationAndCanonicalBytes();
        testFullUInt64PreservationAndNoReservation();
        testDefensiveCopiesAndSecretRetentionBoundary();
        System.out.println("Private viewer record candidate assertions: " + assertions
                + "; PASS (in-memory candidates only; no storage/send/Android durability proof)");
    }

    private static void testExactAgreementFactoryAndOrderedImmutableTransitions() throws Exception {
        Agreement agreement = agreement(), sameLogicalAgreement = agreement();
        ViewerPairingAuthenticator.VerifiedHostConfirmation proof = agreement.authenticateHostConfirmation(hostConfirmation());
        refused(FailureCode.IDENTITY_MISMATCH, () -> sameLogicalAgreement.makePendingRecord(proof, CREATED_AT));
        refused(FailureCode.IDENTITY_MISMATCH, () -> agreement.makePendingRecord(null, CREATED_AT));
        for (double bad : new double[] { Double.NaN, Double.NEGATIVE_INFINITY, Double.POSITIVE_INFINITY })
            refused(FailureCode.MALFORMED_INPUT, () -> agreement.makePendingRecord(proof, bad));
        ViewerPairRecord pending = agreement.makePendingRecord(proof, CREATED_AT);
        check(pending.phase() == RecordPhase.PENDING && pending.recoveryAction().kind() == RecordRecoveryAction.Kind.AWAIT_PROPOSAL,
                "authenticated pending candidate waits; no persisted/paired flag");
        check(pending.recoveryAction().unsentRetainedPayload() == null, "pending contains no retained commit");
        check(pending.pairID().equals(id("derived.pair-id-text")) && pending.commitID().equals(id("derived.commit-id-text")), "actual Swift derived IDs");
        check(pending.viewerDeviceID().equals(id("input.viewer-device-id")) && pending.hostDeviceID().equals(id("input.host-device-id")), "actual local/remote identity");
        check(pending.hostDisplayName().equals("Test Mac") && pending.createdAtEpochSeconds() == CREATED_AT, "exact nonsecret metadata");
        check(pending.nextOutboundReconnectSequence().equals("1") && pending.highestAcceptedReconnectSequence().equals("0"), "initial unsigned counters");
        refused(FailureCode.INVALID_COMMIT, () -> pending.acceptCompletion(hostCommit("completion"), identity()));
        refused(FailureCode.INVALID_COMMIT, () -> pending.prepareAcknowledgement(hostCommit("acknowledgement"), identity()));
        refused(FailureCode.IDENTITY_MISMATCH, () -> pending.prepareAcknowledgement(hostCommit("proposal"),
                ViewerPairingAuthenticator.viewerIdentity(OTHER_ID, data("input.viewer-signing-seed"))));
        RecordTransition acknowledged = pending.prepareAcknowledgement(hostCommit("proposal"), identity());
        check(pending.phase() == RecordPhase.PENDING && acknowledged.record().phase() == RecordPhase.ACCEPTED_ISSUED, "immutable pending predecessor");
        verifyResponse(acknowledged.unsentRetainedPayload(), "acknowledgement");
        equal(acknowledged.unsentRetainedPayload(), acknowledged.record().recoveryAction().unsentRetainedPayload(), "same retained ACK candidate");
        RecordTransition completed = acknowledged.record().acceptCompletion(hostCommit("completion"), identity());
        check(acknowledged.record().phase() == RecordPhase.ACCEPTED_ISSUED && completed.record().phase() == RecordPhase.ACTIVE, "immutable accepted predecessor");
        verifyResponse(completed.unsentRetainedPayload(), "activationAcknowledgement");
        equal(completed.unsentRetainedPayload(), completed.record().recoveryAction().unsentRetainedPayload(), "same retained activation candidate");
        refused(FailureCode.INVALID_COMMIT, () -> completed.record().prepareAcknowledgement(hostCommit("proposal"), identity()));
    }

    private static void testAuthenticatedEquivalentReplayUsesExactRetainedBytes() throws Exception {
        ViewerPairRecord accepted = accepted(), active = accepted.acceptCompletion(hostCommit("completion"), identity()).record();
        byte[] ack = accepted.recoveryAction().unsentRetainedPayload(), activation = active.recoveryAction().unsentRetainedPayload();
        equal(ack, accepted.prepareAcknowledgement(hostCommit("proposal"), identity()).unsentRetainedPayload(), "exact duplicate ACK reuse");
        equal(activation, active.acceptCompletion(hostCommit("completion"), identity()).unsentRetainedPayload(), "exact duplicate activation reuse");
        CommitPayload equivalentProposal = freshlySignedHostCommit(hostCommit("proposal"));
        CommitPayload equivalentCompletion = freshlySignedHostCommit(hostCommit("completion"));
        // Actual CryptoKit fixture signatures versus BC signatures, no assumed hardcoded crypto outputs.
        check(!Arrays.equals(hostCommit("proposal").signature(), equivalentProposal.signature())
                && !Arrays.equals(hostCommit("completion").signature(), equivalentCompletion.signature()), "actual distinct valid incoming-signature witnesses");
        equal(ack, accepted.prepareAcknowledgement(equivalentProposal, identity()).unsentRetainedPayload(), "equivalent authentic proposal cannot replace retained ACK");
        equal(activation, active.acceptCompletion(equivalentCompletion, identity()).unsentRetainedPayload(), "equivalent authentic completion cannot replace activation");
        CommitPayload corruptProposal = commit(changedField(data("commit.proposal.payload"), "signature", base64(flipped(hostCommit("proposal").signature()))));
        refused(FailureCode.AUTHENTICATION_FAILED, () -> accepted.prepareAcknowledgement(corruptProposal, identity()));
        CommitPayload corruptCompletion = commit(changedField(data("commit.completion.payload"), "commitTag", base64(flipped(hostCommit("completion").commitTag()))));
        refused(FailureCode.AUTHENTICATION_FAILED, () -> active.acceptCompletion(corruptCompletion, identity()));
        CommitPayload wrongCommit = commit(changedField(data("commit.proposal.payload"), "commitID", OTHER_ID.toString()));
        refused(FailureCode.INVALID_COMMIT, () -> accepted.prepareAcknowledgement(wrongCommit, identity()));
        equal(ack, accepted.recoveryAction().unsentRetainedPayload(), "failed replay cannot mutate ACK");
        equal(activation, active.recoveryAction().unsentRetainedPayload(), "failed replay cannot mutate activation");
    }

    private static void testPrivateEncodingRoundtripAndIndependentLayout() throws Exception {
        ViewerPairRecord[] records = { pending(), accepted(), active() };
        for (ViewerPairRecord record : records) {
            byte[] encoded = encode(record), body = body(encoded);
            check(encoded.length <= 16384 && body[0] == 1 && body[1] == 1 && body[3] == 2 && body[4] == 1, "bounded explicit private schema/viewer-host roles");
            equal(uuidBytes(id("derived.pair-id-text")), Arrays.copyOfRange(body, 5, 21), "independent actual pair field");
            equal(uuidBytes(id("derived.commit-id-text")), Arrays.copyOfRange(body, 21, 37), "independent actual commit field");
            equal(uuidBytes(id("input.viewer-device-id")), Arrays.copyOfRange(body, 37, 53), "independent local identity field");
            equal(uuidBytes(id("input.host-device-id")), Arrays.copyOfRange(body, 53, 69), "independent remote identity field");
            equal(data("derived.viewer-signing-public-key"), Arrays.copyOfRange(body, 69, 101), "actual local key field");
            equal(data("derived.host-signing-public-key"), Arrays.copyOfRange(body, 101, 133), "actual peer key field");
            int nameLength = ByteBuffer.wrap(body, 133, 4).getInt();
            check(nameLength == 8, "known public fixture name length");
            equal("Test Mac".getBytes(StandardCharsets.UTF_8), Arrays.copyOfRange(body, 137, 137 + nameLength), "raw exact public name");
            check(Double.longBitsToDouble(ByteBuffer.wrap(body, 137 + nameLength, 8).getLong()) == CREATED_AT, "explicit epoch-seconds private time profile");
            equal(data("derived.transcript-hash"), Arrays.copyOfRange(body, 145 + nameLength, 177 + nameLength), "actual transcript field");
            equal(data("derived.pair-root-public-test-only"), Arrays.copyOfRange(body, 177 + nameLength, 209 + nameLength), "public fixed root fixture, no production getter");
            ViewerPairRecord restored = ViewerPairRecord.restore(encoded, identity());
            check(restored.phase() == record.phase() && restored.pairID().equals(record.pairID()) && restored.commitID().equals(record.commitID()), "typed phase and identifiers restore");
            equal(body, body(encode(restored)), "complete canonical body roundtrip");
            equal(record.recoveryAction().unsentRetainedPayload(), restored.recoveryAction().unsentRetainedPayload(), "exact retained bytes survive restore");
        }
    }

    private static void testOuterSignatureFramingAndTrustedIdentity() throws Exception {
        byte[] encoded = encode(pending());
        refused(FailureCode.MALFORMED_INPUT, () -> ViewerPairRecord.restore(null, identity()));
        for (int length : new int[] { 0, 11, 75, encoded.length - 1 })
            refused(FailureCode.MALFORMED_INPUT, () -> ViewerPairRecord.restore(Arrays.copyOf(encoded, length), identity()));
        refused(FailureCode.MALFORMED_INPUT, () -> ViewerPairRecord.restore(new byte[16385], identity()));
        refused(FailureCode.MALFORMED_INPUT, () -> ViewerPairRecord.restore(Arrays.copyOf(encoded, encoded.length + 1), identity()));
        byte[] badHeader = encoded.clone(); badHeader[0] ^= 1;
        refused(FailureCode.MALFORMED_INPUT, () -> ViewerPairRecord.restore(badHeader, identity()));
        byte[] badLength = encoded.clone(); ByteBuffer.wrap(badLength, 8, 4).putInt(Integer.MAX_VALUE);
        refused(FailureCode.MALFORMED_INPUT, () -> ViewerPairRecord.restore(badLength, identity()));
        byte[] corruptBody = encoded.clone(); corruptBody[12] = (byte) 0xFF;
        refused(FailureCode.AUTHENTICATION_FAILED, () -> ViewerPairRecord.restore(corruptBody, identity()));
        byte[] corruptSignature = encoded.clone(); corruptSignature[corruptSignature.length - 1] ^= 1;
        refused(FailureCode.AUTHENTICATION_FAILED, () -> ViewerPairRecord.restore(corruptSignature, identity()));
        refused(FailureCode.AUTHENTICATION_FAILED, () -> ViewerPairRecord.restore(signedBody(body(encoded), DOMAIN + ".wrong"), identity()));
        ViewerIdentity differentKey = ViewerPairingAuthenticator.viewerIdentity(id("input.viewer-device-id"), data("input.host-signing-seed"));
        refused(FailureCode.AUTHENTICATION_FAILED, () -> ViewerPairRecord.restore(encoded, differentKey));
        ViewerIdentity differentID = ViewerPairingAuthenticator.viewerIdentity(OTHER_ID, data("input.viewer-signing-seed"));
        refused(FailureCode.IDENTITY_MISMATCH, () -> ViewerPairRecord.restore(encoded, differentID));
        refused(FailureCode.IDENTITY_MISMATCH, () -> pending().encodeForPrivateStorage(differentID));
        refused(FailureCode.IDENTITY_MISMATCH, () -> pending().encodeForPrivateStorage(differentKey));
        // Valid local signatures do not override schema validation or grant a storage receipt.
        refused(FailureCode.MALFORMED_INPUT, () -> ViewerPairRecord.restore(signedBody(new byte[0], DOMAIN), identity()));
    }

    private static void testCorrectlySignedMalformedBodies() throws Exception {
        byte[] pending = body(encode(pending())), accepted = body(encode(accepted())), active = body(encode(active()));
        for (int offset : new int[] { 0, 1, 3, 4 }) {
            byte[] changed = pending.clone(); changed[offset] = (byte) 0xFF;
            refuseSigned(FailureCode.MALFORMED_INPUT, changed);
        }
        byte[] hostOnlyState = pending.clone(); hostOnlyState[2] = 4;
        refuseSigned(FailureCode.MALFORMED_INPUT, hostOnlyState); // acceptedReceived is host-only.
        byte[] localID = pending.clone(); localID[37] ^= 1; refuseSigned(FailureCode.IDENTITY_MISMATCH, localID);
        byte[] localKey = pending.clone(); localKey[69] ^= 1; refuseSigned(FailureCode.IDENTITY_MISMATCH, localKey);
        byte[] equalPeerKey = pending.clone(); System.arraycopy(equalPeerKey, 69, equalPeerKey, 101, 32);
        refuseSigned(FailureCode.IDENTITY_MISMATCH, equalPeerKey);
        byte[] equalPeerID = pending.clone(); System.arraycopy(equalPeerID, 37, equalPeerID, 53, 16);
        refuseSigned(FailureCode.MALFORMED_INPUT, equalPeerID);
        byte[] zeroPair = pending.clone(); Arrays.fill(zeroPair, 5, 21, (byte) 0); refuseSigned(FailureCode.MALFORMED_INPUT, zeroPair);
        for (int offset : new int[] { 5, 21, 145 + nameLength(pending), 177 + nameLength(pending) }) {
            byte[] changed = pending.clone(); changed[offset] ^= 1; refuseSigned(FailureCode.MALFORMED_INPUT, changed);
        }
        byte[] zeroNext = pending.clone(); Arrays.fill(zeroNext, 209 + nameLength(pending), 217 + nameLength(pending), (byte) 0);
        refuseSigned(FailureCode.MALFORMED_INPUT, zeroNext);
        byte[] timeNaN = pending.clone(); ByteBuffer.wrap(timeNaN, 137 + nameLength(pending), 8).putLong(Double.doubleToRawLongBits(Double.NaN));
        refuseSigned(FailureCode.MALFORMED_INPUT, timeNaN);
        byte[] nameTooLarge = pending.clone(); ByteBuffer.wrap(nameTooLarge, 133, 4).putInt(129); refuseSigned(FailureCode.MALFORMED_INPUT, nameTooLarge);
        byte[] invalidUTF8 = pending.clone(); invalidUTF8[137] = (byte) 0xFF; refuseSigned(FailureCode.MALFORMED_INPUT, invalidUTF8);
        byte[] controlName = pending.clone(); controlName[137] = 0; refuseSigned(FailureCode.MALFORMED_INPUT, controlName);
        byte[] absentRecovery = pending.clone(); absentRecovery[2] = 2; refuseSigned(FailureCode.INVALID_COMMIT, absentRecovery);
        byte[] activeWithoutRecovery = pending.clone(); activeWithoutRecovery[2] = 3; refuseSigned(FailureCode.INVALID_COMMIT, activeWithoutRecovery);
        byte[] pendingWithACK = accepted.clone(); pendingWithACK[2] = 1; refuseSigned(FailureCode.INVALID_COMMIT, pendingWithACK);
        byte[] activeWithACK = accepted.clone(); activeWithACK[2] = 3; refuseSigned(FailureCode.INVALID_COMMIT, activeWithACK);
        byte[] acceptedWithActivation = active.clone(); acceptedWithActivation[2] = 2; refuseSigned(FailureCode.INVALID_COMMIT, acceptedWithActivation);
        byte[] tooLargeRecovery = accepted.clone(); ByteBuffer.wrap(tooLargeRecovery, 225 + nameLength(accepted), 4).putInt(8193);
        refuseSigned(FailureCode.MALFORMED_INPUT, tooLargeRecovery);
        refuseSigned(FailureCode.MALFORMED_INPUT, Arrays.copyOf(accepted, accepted.length - 1));
        refuseSigned(FailureCode.MALFORMED_INPUT, Arrays.copyOf(pending, pending.length + 1));
    }

    private static void testRecoveryCommitAuthenticationAndCanonicalBytes() throws Exception {
        byte[] accepted = body(encode(accepted())), active = body(encode(active()));
        for (byte[] original : new byte[][] { accepted, active }) {
            CommitPayload retained = commit(recovery(original));
            refuseSigned(FailureCode.AUTHENTICATION_FAILED, replacingRecovery(original,
                    changedField(recovery(original), "commitTag", base64(flipped(retained.commitTag())))));
            refuseSigned(FailureCode.AUTHENTICATION_FAILED, replacingRecovery(original,
                    changedField(recovery(original), "signature", base64(flipped(retained.signature())))));
            for (String field : new String[] { "pairID", "commitID", "senderDeviceID", "recipientDeviceID" })
                refuseSigned(FailureCode.INVALID_COMMIT, replacingRecovery(original, changedField(recovery(original), field, OTHER_ID.toString())));
            refuseSigned(FailureCode.INVALID_COMMIT, replacingRecovery(original,
                    changedField(recovery(original), "transcriptHash", base64(flipped(retained.transcriptHash())))));
            String notCanonical = new String(recovery(original), StandardCharsets.UTF_8).replace("\"kind\":", "\"kind\" : ");
            refuseSigned(FailureCode.MALFORMED_INPUT, replacingRecovery(original, notCanonical.getBytes(StandardCharsets.UTF_8)));
        }
        ViewerPairRecord restoredAccepted = ViewerPairRecord.restore(signedBody(accepted, DOMAIN), identity());
        equal(recovery(accepted), restoredAccepted.prepareAcknowledgement(hostCommit("proposal"), identity()).unsentRetainedPayload(), "restore exact ACK replay");
        ViewerPairRecord restoredActive = ViewerPairRecord.restore(signedBody(active, DOMAIN), identity());
        equal(recovery(active), restoredActive.acceptCompletion(hostCommit("completion"), identity()).unsentRetainedPayload(), "restore exact activation replay");
    }

    private static void testFullUInt64PreservationAndNoReservation() throws Exception {
        byte[] body = body(encode(pending())); int offset = 209 + nameLength(body);
        for (long bits : new long[] { Long.MAX_VALUE, Long.MIN_VALUE, -1L }) {
            byte[] changed = body.clone(); ByteBuffer.wrap(changed, offset, 16).putLong(bits).putLong(bits);
            ViewerPairRecord record = ViewerPairRecord.restore(signedBody(changed, DOMAIN), identity());
            String expected = bits == Long.MAX_VALUE ? "9223372036854775807" : bits == Long.MIN_VALUE ? "9223372036854775808" : "18446744073709551615";
            check(record.nextOutboundReconnectSequence().equals(expected) && record.highestAcceptedReconnectSequence().equals(expected), "full UInt64 preserved without signed truncation");
            ViewerPairRecord accepted = record.prepareAcknowledgement(hostCommit("proposal"), identity()).record();
            ViewerPairRecord active = accepted.acceptCompletion(hostCommit("completion"), identity()).record();
            check(active.nextOutboundReconnectSequence().equals(expected) && active.highestAcceptedReconnectSequence().equals(expected), "pairing transitions do not reserve/reset counters");
            equal(body(encode(active)), body(encode(ViewerPairRecord.restore(encode(active), identity()))), "maximum-counter roundtrip");
        }
    }

    private static void testDefensiveCopiesAndSecretRetentionBoundary() throws Exception {
        ViewerPairRecord active = active(); byte[] original = active.recoveryAction().unsentRetainedPayload();
        byte[] response = active.recoveryAction().unsentRetainedPayload(); Arrays.fill(response, (byte) 0);
        equal(original, active.recoveryAction().unsentRetainedPayload(), "recovery plan output defensive");
        byte[] encoded = encode(active), reference = encoded.clone(); ViewerPairRecord restored = ViewerPairRecord.restore(encoded, identity());
        Arrays.fill(encoded, (byte) 0); equal(body(reference), body(encode(restored)), "restore owns bytes, not external encoding");
        ViewerPairingAuthenticator.PrivateRecordEncoding privateEncoding = active.encodeForPrivateStorage(identity());
        byte[] exposed = privateEncoding.copyForPrivateStorage(); Arrays.fill(exposed, (byte) 0);
        equal(body(reference), body(privateEncoding.copyForPrivateStorage()), "private encoding getter defensive");
        for (Field field : ViewerPairRecord.class.getDeclaredFields()) {
            check(Modifier.isPrivate(field.getModifiers()) || (Modifier.isPublic(field.getModifiers()) && Modifier.isStatic(field.getModifiers()) && Modifier.isFinal(field.getModifiers())), "record fields closed");
            check(Modifier.isFinal(field.getModifiers()), "record fields immutable");
            check(!field.getType().equals(ViewerIdentity.class) && !field.getType().equals(PreparedViewer.class)
                    && !field.getType().equals(Agreement.class) && !field.getType().getSimpleName().equals("SigningIdentity")
                    && !field.getType().getSimpleName().equals("Material"), "record retains no seed/bootstrap/identity owner");
        }
        for (java.lang.reflect.Constructor<?> constructor : ViewerPairRecord.class.getDeclaredConstructors())
            check(Modifier.isPrivate(constructor.getModifiers()), "no arbitrary authenticated record constructor");
        check(active.toString().equals("<redacted immutable Beluga viewer record candidate>")
                && privateEncoding.toString().equals("<redacted private Beluga viewer record encoding>")
                && active.recoveryAction().toString().equals("<redacted Beluga viewer record recovery plan>"), "fixed redacted descriptions");
        check(!identity().toString().contains("Test") && !identity().toString().contains("AAAA"), "identity description redacted");
        // No reflection reads secret values; no provider/JVM zeroization or encrypted-disk claim.
    }

    private static ViewerIdentity identity() throws Exception { return ViewerPairingAuthenticator.viewerIdentity(id("input.viewer-device-id"), data("input.viewer-signing-seed")); }
    private static Agreement agreement() throws Exception {
        PreparedViewer prepared = ViewerPairingAuthenticator.authenticateRetainedLocalHello(id("input.viewer-device-id"), "Test iPhone",
                data("input.viewer-signing-seed"), data("input.invitation-secret"), data("input.viewer-ephemeral-private"), data("input.viewer-nonce"), hello(data("hello.viewer.payload")));
        return ViewerPairingAuthenticator.acceptHost(prepared, hello(data("hello.host.payload")));
    }
    private static ViewerPairRecord pending() throws Exception { Agreement agreement = agreement(); return agreement.makePendingRecord(agreement.authenticateHostConfirmation(hostConfirmation()), CREATED_AT); }
    private static ViewerPairRecord accepted() throws Exception { return pending().prepareAcknowledgement(hostCommit("proposal"), identity()).record(); }
    private static ViewerPairRecord active() throws Exception { return accepted().acceptCompletion(hostCommit("completion"), identity()).record(); }
    private static ConfirmationPayload hostConfirmation() throws Exception { return (ConfirmationPayload) PairingPayloadDecoder.decode(data("confirmation.host.payload")); }
    private static CommitPayload hostCommit(String phase) throws Exception { return commit(data("commit." + phase + ".payload")); }
    private static HelloPayload hello(byte[] bytes) throws Exception { return (HelloPayload) PairingPayloadDecoder.decode(bytes); }
    private static CommitPayload commit(byte[] bytes) throws Exception { return (CommitPayload) PairingPayloadDecoder.decode(bytes); }
    private static byte[] encode(ViewerPairRecord record) throws Exception { return record.encodeForPrivateStorage(identity()).copyForPrivateStorage(); }
    private static void verifyResponse(byte[] payload, String phase) throws Exception {
        CommitPayload generated = commit(payload), reference = hostCommit(phase);
        equal(data("commit." + phase + ".unsigned"), PairingCanonicalCodec.unsignedCommit(generated.canonicalFields()), "actual Swift local unsigned response");
        equal(reference.commitTag(), generated.commitTag(), "actual Swift local MAC response");
        check(BouncyCastlePairingCrypto.ed25519Verify(data("derived.viewer-signing-public-key"),
                PairingCanonicalCodec.commitSignatureInput(generated.canonicalMessage()), generated.signature()), "actual generated response signature authenticates");
    }
    private static CommitPayload freshlySignedHostCommit(CommitPayload original) throws Exception {
        byte[] signature = BouncyCastlePairingCrypto.ed25519Sign(data("input.host-signing-seed"), PairingCanonicalCodec.commitSignatureInput(original.canonicalMessage()));
        CommitFields fields = new CommitFields(1, original.pairID(), original.commitID(), original.senderDeviceID(),
                original.senderRole(), original.recipientDeviceID(), original.transcriptHash(), original.phase());
        CommitPayload result = commit(PairingCanonicalCodec.commitPayload(new Commit(fields, original.commitTag(), signature)));
        check(BouncyCastlePairingCrypto.ed25519Verify(data("derived.host-signing-public-key"), PairingCanonicalCodec.commitSignatureInput(result.canonicalMessage()), result.signature()), "fresh equivalent host signature valid");
        return result;
    }
    // Independent TEST-only private envelope recipe, signing with public fixed fixture identity.
    private static byte[] signedBody(byte[] body, String domain) throws Exception {
        byte[] label = domain.getBytes(StandardCharsets.US_ASCII);
        byte[] input = ByteBuffer.allocate(label.length + 1 + 8 + body.length).put(label).put((byte) 0).putLong(body.length).put(body).array();
        byte[] signature = BouncyCastlePairingCrypto.ed25519Sign(data("input.viewer-signing-seed"), input);
        return ByteBuffer.allocate(12 + body.length + 64).put("BVR-SIG1".getBytes(StandardCharsets.US_ASCII)).putInt(body.length).put(body).put(signature).array();
    }
    private static void refuseSigned(FailureCode code, byte[] body) throws Exception { byte[] signed = signedBody(body, DOMAIN); refused(code, () -> ViewerPairRecord.restore(signed, identity())); }
    private static byte[] body(byte[] encoded) { check(encoded.length >= 76, "bounded own test envelope"); int length = ByteBuffer.wrap(encoded, 8, 4).getInt(); check(length == encoded.length - 76, "test envelope exact length"); return Arrays.copyOfRange(encoded, 12, 12 + length); }
    private static int nameLength(byte[] body) { return ByteBuffer.wrap(body, 133, 4).getInt(); }
    private static byte[] recovery(byte[] body) { int offset = 225 + nameLength(body), length = ByteBuffer.wrap(body, offset, 4).getInt(); check(offset + 4 + length == body.length, "test retained payload exact framing"); return Arrays.copyOfRange(body, offset + 4, body.length); }
    private static byte[] replacingRecovery(byte[] body, byte[] recovery) { int offset = 225 + nameLength(body); return ByteBuffer.allocate(offset + 4 + recovery.length).put(body, 0, offset).putInt(recovery.length).put(recovery).array(); }
    private static byte[] changedField(byte[] payload, String key, String value) {
        String source = new String(payload, StandardCharsets.UTF_8); Matcher field = Pattern.compile("\"" + Pattern.quote(key) + "\":\"[^\"]*\"").matcher(source);
        check(field.find(), "controlled field exists"); int start = field.start(), end = field.end(); check(!field.find(), "controlled field unique");
        return (source.substring(0, start) + "\"" + key + "\":\"" + value + "\"" + source.substring(end)).getBytes(StandardCharsets.UTF_8);
    }
    private static byte[] uuidBytes(UUID value) { return ByteBuffer.allocate(16).putLong(value.getMostSignificantBits()).putLong(value.getLeastSignificantBits()).array(); }
    private static byte[] flipped(byte[] value) { byte[] changed = value.clone(); changed[0] ^= 1; return changed; }
    private static String base64(byte[] value) { return Base64.getEncoder().encodeToString(value); }
    private static byte[] data(String key) { byte[] value = fixture.get(key); check(value != null, "exact public fixture row"); return value.clone(); }
    private static UUID id(String key) { return UUID.fromString(new String(data(key), StandardCharsets.US_ASCII)); }
    private static Map<String, byte[]> load(Path path) throws Exception {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        try (InputStream input = Files.newInputStream(path)) { byte[] chunk = new byte[4096]; int count; while ((count = input.read(chunk)) != -1) { check(output.size() + count <= 131072, "bounded fixture"); output.write(chunk, 0, count); } }
        byte[] raw = output.toByteArray(); StringBuilder digest = new StringBuilder();
        for (byte value : MessageDigest.getInstance("SHA-256").digest(raw)) digest.append(String.format(Locale.ROOT, "%02x", value & 255));
        check(digest.toString().equals(FIXTURE_SHA), "exact45 real Swift fixture digest"); for (byte value : raw) check(value >= 0, "ASCII public fixture container");
        String source = new String(raw, StandardCharsets.US_ASCII); check(source.startsWith("# beluga.public-test-pairing-crypto.v1\n") && source.endsWith("\n"), "exact fixture schema");
        Map<String, byte[]> rows = new TreeMap<>(); String previous = "";
        for (String row : source.split("\n")) { if (row.startsWith("#")) continue; String[] parts = row.split("\t", -1); check(parts.length == 2 && parts[0].matches("[A-Za-z0-9.-]{1,80}") && parts[0].compareTo(previous) > 0, "canonical unique sorted rows"); byte[] value = Base64.getDecoder().decode(parts[1]); check(value.length > 0 && value.length <= 8192 && base64(value).equals(parts[1]), "bounded canonical Base64"); check(rows.put(parts[0], value) == null, "no duplicate row"); previous = parts[0]; }
        check(rows.size() == 45, "complete original45 inventory"); return rows;
    }
    private interface Checked { void run() throws Exception; }
    private static void refused(FailureCode code, Checked operation) throws Exception {
        try { operation.run(); throw new AssertionError("expected record refusal"); }
        catch (AuthFailure error) { check(error.code() == code && error.getCause() == null && error.getSuppressed().length == 0, "exact redacted refusal category"); check(error.getMessage().equals("Beluga viewer authentication refused: " + code.name()), "fixed record failure diagnostic"); }
    }
    private static void check(boolean value, String label) { assertions++; if (!value) throw new AssertionError(label); }
    private static void equal(byte[] expected, byte[] actual, String label) { check(Arrays.equals(expected, actual), label); }
}
