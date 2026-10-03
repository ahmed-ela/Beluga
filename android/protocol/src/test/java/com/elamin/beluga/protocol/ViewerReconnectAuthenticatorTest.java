package com.elamin.beluga.protocol;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.Base64;
import java.util.HashSet;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import com.elamin.beluga.protocol.PairingPayloadDecoder.CommitPayload;
import com.elamin.beluga.protocol.PairingPayloadDecoder.ConfirmationPayload;
import com.elamin.beluga.protocol.PairingPayloadDecoder.HelloPayload;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.StoreStamp;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.Agreement;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.AuthFailure;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.FailureCode;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.PreparedViewer;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.ReconnectPreparation;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.SessionCredential;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.SessionCredential.Direction;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.ViewerIdentity;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.ViewerPairRecord;

/** PUBLIC synthetic fixtures only. Candidates and cryptographic completion are NOT durable sends. */
public final class ViewerReconnectAuthenticatorTest {
    private static final String PAIRING_SHA = "7d8a58cd34400271d0c68ac1e263450c4ad4978337ae1bb87246362a6d0ec06a";
    private static final String RECONNECT_SHA = "3c8ef42139c81e4cff10fcc1957aa0460a7548792ce7e952498966eff51c629e";
    private static final String PRIVATE_DOMAIN = "Beluga.Android.PrivateViewerPairRecord.Signature.v1";
    private static final UUID OTHER_ID = UUID.fromString("99999999-8888-7777-6666-555555555555");
    private static final UUID SLOT = UUID.fromString("12345678-1234-5678-ABCD-123456789ABC");
    private static final double CREATED_AT = 1700000000.25;
    private static Map<String, byte[]> pairing, reconnect;
    private static int assertions;
    private ViewerReconnectAuthenticatorTest() { }

    public static void main(String[] arguments) throws Exception {
        check(arguments.length == 2, "two explicit public reference fixture paths required");
        pairing = load(Path.of(arguments[0]), PAIRING_SHA, "beluga.public-test-pairing-crypto.v1", 45, null);
        reconnect = load(Path.of(arguments[1]), RECONNECT_SHA,
                "beluga.public-test-saved-pair-reconnect.v1", referenceNames().size(), referenceNames());
        check(referenceNames().size() == 98, "fixed four-case actual Swift reference inventory");
        check(text("basis.original-pairing-fixture-sha256").equals(PAIRING_SHA), "same retained pairing fixture basis");
        for (String name : new String[] { "pair-id-text", "commit-id-text", "transcript-hash", "root-public-test-only" })
            equal(data("derived." + (name.equals("root-public-test-only") ? "pair-root-public-test-only" : name)),
                    reference("basis." + name), "independently captured exact original pair basis");
        check(text("boundary.maximum.refusal").equals("sequenceExhausted"), "actual Swift exhaustion refusal");
        testActualSwiftCapturesAndOpaqueDirectionKeys();
        testGeneratedRequestAndRetainedRequestAuthentication();
        testActivePhaseExactIdentityAndMalformedPreparation();
        testUnsignedBoundariesAndImmutableReservation();
        testEveryHostResponseBindingAndAuthentication();
        testExactFullSignedRequestDigestAndCrossReservationReplay();
        testCatalogReservationCASAndUnchangedBootstrapWriteContract();
        testStrictMessageDecodingAndDefensiveCopies();
        testClosedAndRedactedNonAuthorizingSurfaces();
        System.out.println("Saved-pair reconnect protocol assertions: " + assertions
                + "; PASS (actual Swift cryptographic references; no storage/WSS/media/device proof)");
    }

    private static void testActualSwiftCapturesAndOpaqueDirectionKeys() throws Exception {
        for (String name : new String[] { "first", "second", "high", "max-minus-one" }) {
            String prefix = prefix(name);
            ViewerPairRecord original = withCounters(active(), text(prefix + "counter.viewer.before"), "0");
            byte[] before = body(encode(original));
            ReconnectPreparation prepared = retained(original, name);
            equal(reference(prefix + "request.full"), ReconnectMessages.fullRequest(prepared.request()), "exact authenticated retained Swift request");
            equal(reference(prefix + "request.payload"), prepared.requestPayload(), "exact unsent request wrapper");
            equal(reference(prefix + "request.unsigned"), ReconnectMessages.unsignedRequest(prepared.request()), "actual Swift unsigned request");
            equal(reference(prefix + "request.signature-input"), ReconnectMessages.requestSignatureInput(prepared.request()), "request domain frame");
            check(prepared.candidate().nextOutboundReconnectSequence().equals(text(prefix + "counter.viewer.after")), "actual UInt64 reservation result");
            check(prepared.candidate().highestAcceptedReconnectSequence().equals("0"), "viewer reservation does not alter inbound counter");
            equal(before, body(encode(original)), "predecessor remains byte-equivalent");
            byte[] expectedBody = before.clone();
            ByteBuffer.wrap(expectedBody, counterOffset(expectedBody), 8).putLong(unsignedBits(text(prefix + "counter.viewer.after")));
            equal(expectedBody, body(prepared.candidateEncoding().copyForPrivateStorage()), "only exact outbound reservation field changes");
            ReconnectMessages.Response response = response(reference(prefix + "response.full"));
            equal(reference(prefix + "response.unsigned"), ReconnectMessages.unsignedResponse(response), "actual Swift unsigned response");
            equal(reference(prefix + "response.signature-input"), ReconnectMessages.responseSignatureInput(response), "response domain frame");
            equal(reference(prefix + "response.payload"), ReconnectMessages.responsePayload(response), "actual Swift response wrapper");
            equal(reference(prefix + "request-digest"), BouncyCastlePairingCrypto.sha256(ReconnectMessages.fullRequest(prepared.request())), "host digest covers FULL signed request");
            equal(reference(prefix + "transcript.domain-input"), ReconnectMessages.transcriptInput(prepared.request(), response), "actual full signed transcript domain");
            SessionCredential credential = prepared.complete(response);
            check(credential.channelID().equals(text(prefix + "credential.channel")), "actual Swift session routing identifier");
            check(credential.admissionProofForTransport().equals(text(prefix + "credential.admission")), "actual Swift admission proof");
            verifyOpaqueKey(credential, Direction.HOST_TO_VIEWER, reference(prefix + "credential.host-to-viewer"));
            verifyOpaqueKey(credential, Direction.VIEWER_TO_HOST, reference(prefix + "credential.viewer-to-host"));
            SessionCredential repeated = prepared.complete(response);
            check(repeated.channelID().equals(credential.channelID()), "stateless Swift-parity reauthentication is not send authority");
            equal(before, body(encode(original)), "completion never mutates original durable-candidate counters");
        }
    }

    private static void verifyOpaqueKey(SessionCredential credential, Direction direction, byte[] swiftKey) throws Exception {
        byte[] nonce = fill(0x2A, 12), aad = ascii("PUBLIC fixed interoperability AAD"), plain = ascii("PUBLIC session-key comparison");
        byte[] expected = BouncyCastlePairingCrypto.sealCombined(swiftKey, nonce, plain, aad);
        byte[] sealed = credential.sealForTransport(direction, plain, nonce, aad);
        equal(expected, sealed, "opaque production direction key equals independently captured Swift key");
        equal(plain, credential.openForTransport(direction, sealed, aad), "exact opaque key opens its authenticated box");
        Direction opposite = direction == Direction.HOST_TO_VIEWER ? Direction.VIEWER_TO_HOST : Direction.HOST_TO_VIEWER;
        refuseCredential(() -> credential.openForTransport(opposite, sealed, aad));
        refuseCredential(() -> credential.openForTransport(direction, flipped(sealed), aad));
        refuseCredential(() -> credential.openForTransport(direction, sealed, flipped(aad)));
    }

    private static void testGeneratedRequestAndRetainedRequestAuthentication() throws Exception {
        ViewerPairRecord record = active();
        ReconnectPreparation generated = record.prepareReconnect(identity(), reference(prefix("first") + "input.viewer-ephemeral-private"),
                reference(prefix("first") + "input.viewer-nonce"));
        equal(reference(prefix("first") + "request.unsigned"), ReconnectMessages.unsignedRequest(generated.request()), "generated unsigned fields match Swift");
        check(BouncyCastlePairingCrypto.ed25519Verify(data("derived.viewer-signing-public-key"),
                ReconnectMessages.requestSignatureInput(generated.request()), generated.request().signature()), "actual generated signature authenticates");
        // Do not compare fresh Ed25519 signature bytes to the distinct retained CryptoKit capture.
        ReconnectMessages.Request captured = request(reference(prefix("first") + "request.full"));
        byte[] requestBefore = ReconnectMessages.fullRequest(captured);
        for (String key : new String[] { "pairID", "requesterDeviceID", "targetDeviceID" }) {
            ReconnectMessages.Request wrong = request(changedString(requestBefore, key, OTHER_ID.toString()));
            refused(FailureCode.IDENTITY_MISMATCH, () -> record.authenticateRetainedReconnect(identity(),
                    reference(prefix("first") + "input.viewer-ephemeral-private"), reference(prefix("first") + "input.viewer-nonce"), wrong));
        }
        ReconnectMessages.Request badSignature = request(changedString(requestBefore, "signature", base64(flipped(captured.signature()))));
        refused(FailureCode.AUTHENTICATION_FAILED, () -> record.authenticateRetainedReconnect(identity(),
                reference(prefix("first") + "input.viewer-ephemeral-private"), reference(prefix("first") + "input.viewer-nonce"), badSignature));
        refused(FailureCode.IDENTITY_MISMATCH, () -> record.authenticateRetainedReconnect(identity(), fill(0x71, 32),
                reference(prefix("first") + "input.viewer-nonce"), captured));
        refused(FailureCode.IDENTITY_MISMATCH, () -> record.authenticateRetainedReconnect(identity(),
                reference(prefix("first") + "input.viewer-ephemeral-private"), fill(0x72, 32), captured));
        refused(FailureCode.IDENTITY_MISMATCH, () -> withCounters(record, "2", "0").authenticateRetainedReconnect(identity(),
                reference(prefix("first") + "input.viewer-ephemeral-private"), reference(prefix("first") + "input.viewer-nonce"), captured));
    }

    private static void testActivePhaseExactIdentityAndMalformedPreparation() throws Exception {
        for (ViewerPairRecord record : new ViewerPairRecord[] { pending(), accepted() })
            refused(FailureCode.INVALID_RECONNECT, () -> record.prepareReconnect(identity(), fill(0x51, 32), fill(0x61, 32)));
        ViewerPairRecord active = active(); byte[] before = body(encode(active));
        refused(FailureCode.IDENTITY_MISMATCH, () -> active.prepareReconnect(
                ViewerPairingAuthenticator.viewerIdentity(OTHER_ID, data("input.viewer-signing-seed")), fill(0x51, 32), fill(0x61, 32)));
        refused(FailureCode.IDENTITY_MISMATCH, () -> active.prepareReconnect(
                ViewerPairingAuthenticator.viewerIdentity(id("input.viewer-device-id"), fill(0x99, 32)), fill(0x51, 32), fill(0x61, 32)));
        refused(FailureCode.MALFORMED_INPUT, () -> active.prepareReconnect(null, fill(0x51, 32), fill(0x61, 32)));
        for (byte[] bad : new byte[][] { null, new byte[0], new byte[31], new byte[33] }) {
            refused(FailureCode.MALFORMED_INPUT, () -> active.prepareReconnect(identity(), bad, fill(0x61, 32)));
            refused(FailureCode.MALFORMED_INPUT, () -> active.prepareReconnect(identity(), fill(0x51, 32), bad));
        }
        equal(before, body(encode(active)), "every refused preparation preserves immutable original");
    }

    private static void testUnsignedBoundariesAndImmutableReservation() throws Exception {
        for (String sequence : new String[] { "1", "9223372036854775807", "9223372036854775808", "18446744073709551614" }) {
            ViewerPairRecord original = withCounters(active(), sequence, "18446744073709551615");
            byte[] before = body(encode(original));
            ReconnectPreparation preparation = original.prepareReconnect(identity(), fill(0x51, 32), fill(0x61, 32));
            check(preparation.request().sequence().equals(sequence), "unsigned decimal never narrows through signed Long");
            String expected = new java.math.BigInteger(sequence).add(java.math.BigInteger.ONE).toString();
            check(preparation.candidate().nextOutboundReconnectSequence().equals(expected), "exact unsigned increment");
            check(preparation.candidate().highestAcceptedReconnectSequence().equals("18446744073709551615"), "inbound full UInt64 preserved");
            equal(before, body(encode(original)), "reservation is immutable");
            ViewerPairRecord restored = ViewerPairRecord.restore(preparation.candidateEncoding().copyForPrivateStorage(), identity());
            check(restored.nextOutboundReconnectSequence().equals(expected), "signed private candidate retains exact increment");
        }
        ViewerPairRecord exhausted = withCounters(active(), "18446744073709551615", "0");
        byte[] before = body(encode(exhausted));
        refused(FailureCode.SEQUENCE_EXHAUSTED, () -> exhausted.prepareReconnect(identity(), fill(0x51, 32), fill(0x61, 32)));
        equal(before, body(encode(exhausted)), "max refuses without wrapping or resetting");
    }

    private static void testEveryHostResponseBindingAndAuthentication() throws Exception {
        ReconnectPreparation preparation = retained(active(), "first");
        byte[] full = reference(prefix("first") + "response.full");
        for (String field : new String[] { "pairID", "requesterDeviceID", "responderDeviceID" }) {
            ReconnectMessages.Response changed = response(changedString(full, field, OTHER_ID.toString()));
            refused(FailureCode.INVALID_RECONNECT, () -> preparation.complete(changed));
        }
        ReconnectMessages.Response wrongSequence = response(changedNumber(full, "requestSequence", "2"));
        refused(FailureCode.INVALID_RECONNECT, () -> preparation.complete(wrongSequence));
        ReconnectMessages.Response good = response(full);
        ReconnectMessages.Response wrongDigest = response(changedString(full, "requestDigest", base64(flipped(good.requestDigest()))));
        refused(FailureCode.INVALID_RECONNECT, () -> preparation.complete(wrongDigest));
        for (String field : new String[] { "signature", "nonce", "ephemeralKeyAgreementPublicKey" }) {
            byte[] value = field.equals("signature") ? good.signature() : field.equals("nonce") ? good.nonce() : good.ephemeralKeyAgreementPublicKey();
            ReconnectMessages.Response changed = response(changedString(full, field, base64(flipped(value))));
            refused(FailureCode.AUTHENTICATION_FAILED, () -> preparation.complete(changed));
        }
        ReconnectMessages.Response lowOrder = signedResponse(changedString(full, "ephemeralKeyAgreementPublicKey", base64(new byte[32])), data("input.host-signing-seed"));
        check(BouncyCastlePairingCrypto.ed25519Verify(data("derived.host-signing-public-key"),
                ReconnectMessages.responseSignatureInput(lowOrder), lowOrder.signature()), "low-order witness has actual valid host signature");
        refused(FailureCode.AUTHENTICATION_FAILED, () -> preparation.complete(lowOrder));
        ReconnectMessages.Response impersonated = signedResponse(full, fill(0x99, 32));
        refused(FailureCode.AUTHENTICATION_FAILED, () -> preparation.complete(impersonated));
        malformed(() -> response(changedString(full, "responderRole", "viewer")));
    }

    private static void testExactFullSignedRequestDigestAndCrossReservationReplay() throws Exception {
        ViewerPairRecord record = active(); ReconnectPreparation retained = retained(record, "first");
        ReconnectMessages.Response captured = response(reference(prefix("first") + "response.full"));
        // Independent signed wrong-digest witness: hashing only unsigned request must not admit.
        byte[] unsignedDigest = BouncyCastlePairingCrypto.sha256(ReconnectMessages.unsignedRequest(retained.request()));
        ReconnectMessages.Response unsignedOnly = signedResponse(changedString(reference(prefix("first") + "response.full"),
                "requestDigest", base64(unsignedDigest)), data("input.host-signing-seed"));
        refused(FailureCode.INVALID_RECONNECT, () -> retained.complete(unsignedOnly));
        ReconnectPreparation next = retained.candidate().prepareReconnect(identity(), fill(0x53, 32), fill(0x63, 32));
        refused(FailureCode.INVALID_RECONNECT, () -> next.complete(captured));
        ReconnectPreparation sameSequenceDifferentEphemeral = record.prepareReconnect(identity(), fill(0x71, 32), fill(0x61, 32));
        refused(FailureCode.INVALID_RECONNECT, () -> sameSequenceDifferentEphemeral.complete(captured));
        ReconnectPreparation sameSequenceDifferentNonce = record.prepareReconnect(identity(), fill(0x51, 32), fill(0x72, 32));
        refused(FailureCode.INVALID_RECONNECT, () -> sameSequenceDifferentNonce.complete(captured));
    }

    private static void testCatalogReservationCASAndUnchangedBootstrapWriteContract() throws Exception {
        ViewerStorageCatalog catalog = catalog();
        try {
            StoreStamp stamp = catalog.stamp(SLOT); ViewerPairRecord original = catalog.entry(SLOT).record;
            ReconnectPreparation preparation = original.prepareReconnect(identity(), fill(0x51, 32), fill(0x61, 32));
            byte[] before = catalog.encode();
            storageRefused(() -> catalog.write(stamp, preparation.candidateEncoding().copyForPrivateStorage()));
            equal(before, catalog.encode(), "bootstrap writer cannot smuggle active reconnect reservation");
            ViewerStorageCatalog reserved = catalog.reserveReconnect(stamp, preparation);
            try {
                check(reserved.fileRevision == catalog.fileRevision + 1 && reserved.catalogRevision == catalog.catalogRevision + 1
                        && reserved.selectionRevision == catalog.selectionRevision, "reservation advances exact catalog/file not selection");
                check(reserved.selectedSlot.equals(SLOT) && reserved.admissionRevision(SLOT) == 1, "selection and admitted pair preserved");
                check(reserved.entry(SLOT).record.nextOutboundReconnectSequence().equals("2"), "actual catalog candidate contains reserved next sequence");
                equal(preparation.candidateEncoding().copyForPrivateStorage(), reserved.entry(SLOT).bytes(), "catalog retains once-frozen exact candidate bytes");
                equal(before, catalog.encode(), "catalog predecessor immutable");
                storageRefused(() -> reserved.reserveReconnect(stamp, preparation));
                storageRefused(() -> reserved.reserveReconnect(reserved.stamp(SLOT), preparation));
                ReconnectPreparation fresh = reserved.entry(SLOT).record.prepareReconnect(identity(), fill(0x53, 32), fill(0x63, 32));
                ViewerStorageCatalog third = reserved.reserveReconnect(reserved.stamp(SLOT), fresh);
                try { check(third.entry(SLOT).record.nextOutboundReconnectSequence().equals("3"), "new exact stamp reserves next monotonic sequence"); }
                finally { third.close(); }
            } finally { reserved.close(); }
            ReconnectPreparation jumped = withCounters(original, "3", "0").prepareReconnect(identity(), fill(0x51, 32), fill(0x61, 32));
            storageRefused(() -> catalog.reserveReconnect(stamp, jumped));
            ReconnectPreparation wrongInbound = withCounters(original, "1", "1").prepareReconnect(identity(), fill(0x51, 32), fill(0x61, 32));
            storageRefused(() -> catalog.reserveReconnect(stamp, wrongInbound));
            ViewerStorageCatalog unselected = catalog.select(null, catalog.catalogRevision, catalog.selectionRevision);
            try { storageRefused(() -> unselected.reserveReconnect(unselected.stamp(SLOT), preparation)); }
            finally { unselected.close(); }
            storageRefused(() -> catalog.reserveReconnect(null, preparation));
            storageRefused(() -> catalog.reserveReconnect(stamp, null));
        } finally { catalog.close(); }
    }

    private static void testStrictMessageDecodingAndDefensiveCopies() throws Exception {
        byte[] valid = reference(prefix("first") + "request.full"), responseBytes = reference(prefix("first") + "response.full");
        for (String sequence : new String[] { "0", "-1", "18446744073709551616", "01", "1.0", "1e0" }) {
            malformed(() -> request(changedNumber(valid, "sequence", sequence)));
            malformed(() -> response(changedNumber(responseBytes, "requestSequence", sequence)));
        }
        for (byte[] bytes : new byte[][] { null, new byte[0], new byte[] { (byte) 0xFF }, new byte[8193],
                ascii(new String(valid, StandardCharsets.US_ASCII).replace("\"protocolVersion\":1", "\"protocolVersion\":1,\"protocolVersion\":1")),
                ascii(new String(valid, StandardCharsets.US_ASCII).replace("\"protocolVersion\":1", "\"extra\":1,\"protocolVersion\":1")) })
            malformed(() -> request(bytes));
        malformed(() -> request(changedString(valid, "requesterRole", "host")));
        malformed(() -> request(changedString(valid, "pairID", "00000000-0000-0000-0000-000000000000")));
        malformed(() -> request(changedString(valid, "nonce", "AA==")));
        malformed(() -> request(changedNumber(valid, "protocolVersion", "2")));
        malformed(() -> response(changedNumber(responseBytes, "protocolVersion", "2")));
        // Whitespace is supported by Swift JSON decoding; the signed bytes are canonicalized.
        equal(valid, ReconnectMessages.fullRequest(request(ascii(new String(valid, StandardCharsets.US_ASCII) + " \n"))), "admitted whitespace canonicalizes without changing authenticated fields");
        equal(valid, ReconnectMessages.fullRequest(request(ascii(new String(valid, StandardCharsets.US_ASCII).replace("\"nonce\":", "\"nonce\" :")))), "schema parser canonicalizes harmless JSON spacing");
        ReconnectMessages.Payload requestWrapper = ReconnectMessages.decodePayload(reference(prefix("first") + "request.payload"));
        ReconnectMessages.Payload responseWrapper = ReconnectMessages.decodePayload(reference(prefix("first") + "response.payload"));
        check(requestWrapper.kind() == ReconnectMessages.Kind.RECONNECT_REQUEST && requestWrapper.response() == null,
                "closed request wrapper cannot masquerade as a response");
        check(responseWrapper.kind() == ReconnectMessages.Kind.RECONNECT_RESPONSE && responseWrapper.request() == null,
                "closed response wrapper cannot masquerade as a request");
        equal(valid, ReconnectMessages.fullRequest(requestWrapper.request()), "full authenticated request nested in wrapper");
        equal(responseBytes, ReconnectMessages.fullResponse(responseWrapper.response()), "full authenticated response nested in wrapper");
        malformed(() -> ReconnectMessages.decodePayload(changedString(reference(prefix("first") + "request.payload"), "kind", "reconnectResponse")));
        malformed(() -> ReconnectMessages.decodePayload(ascii("{\"kind\":\"reconnectRequest\",\"reconnectRequest\":"
                + new String(valid, StandardCharsets.US_ASCII) + ",\"reconnectResponse\":"
                + new String(responseBytes, StandardCharsets.US_ASCII) + "}")));
        ReconnectPreparation prepared = retained(active(), "first");
        byte[] copy = prepared.requestPayload(), expected = copy.clone(); Arrays.fill(copy, (byte) 0);
        equal(expected, prepared.requestPayload(), "request wrapper defensive");
        byte[] encoded = prepared.candidateEncoding().copyForPrivateStorage(), exact = encoded.clone(); Arrays.fill(encoded, (byte) 0);
        equal(exact, prepared.candidateEncoding().copyForPrivateStorage(), "once-frozen private candidate defensive");
        ReconnectMessages.Request request = prepared.request(); byte[] nonce = request.nonce(); Arrays.fill(nonce, (byte) 0);
        equal(reference(prefix("first") + "request.full"), ReconnectMessages.fullRequest(request), "request getters own arrays");
        ReconnectMessages.Response response = response(responseBytes); byte[] signature = response.signature(); Arrays.fill(signature, (byte) 0);
        equal(responseBytes, ReconnectMessages.fullResponse(response), "response getters own arrays");
        byte[] originalResponse = responseBytes.clone(); responseBytes[0] ^= 1;
        equal(originalResponse, ReconnectMessages.fullResponse(response), "decoder detaches raw input buffer");
    }

    private static void testClosedAndRedactedNonAuthorizingSurfaces() throws Exception {
        ReconnectPreparation prepared = retained(active(), "first");
        SessionCredential credential = prepared.complete(response(reference(prefix("first") + "response.full")));
        for (Object value : new Object[] { prepared, prepared.request(), response(reference(prefix("first") + "response.full")), credential }) {
            check(value.toString().contains("redacted") && !value.toString().contains(text(prefix("first") + "credential.channel"))
                    && !value.toString().contains(active().pairID().toString()), "descriptions reveal no identifiers or material");
            for (Constructor<?> constructor : value.getClass().getDeclaredConstructors())
                if (value instanceof ReconnectPreparation || value instanceof SessionCredential)
                    check(!Modifier.isPublic(constructor.getModifiers()), "no arbitrary public authentication/credential constructor");
        }
        for (Method method : ReconnectPreparation.class.getDeclaredMethods()) {
            for (Class<?> type : method.getParameterTypes())
                check(type != boolean.class && type != Boolean.class, "no echoed persisted Boolean grants authority");
            check(!method.getName().equals("send") && !method.getName().equals("markPersisted"), "core owns no transport/durability shortcut");
        }
        for (Field field : SessionCredential.class.getDeclaredFields()) {
            check(Modifier.isPrivate(field.getModifiers()), "opaque credential fields private");
            check(Modifier.isFinal(field.getModifiers()) || field.getName().equals("closed") && field.getType() == boolean.class,
                    "only explicit close state is mutable; credential material remains final");
            check(!field.getType().equals(ViewerIdentity.class) && !field.getType().equals(ViewerPairRecord.class), "session credential retains no durable root owner/signing identity");
        }
        check(!java.io.Serializable.class.isAssignableFrom(SessionCredential.class), "session secret not default serializable");
        prepared.close();
        refused(FailureCode.INVALID_RECONNECT, () -> prepared.complete(response(reference(prefix("first") + "response.full"))));
        ViewerStorageCatalog catalog = catalog();
        try { storageRefused(() -> catalog.reserveReconnect(catalog.stamp(SLOT), prepared)); }
        finally { catalog.close(); }
        credential.close();
        refused(FailureCode.INVALID_RECONNECT, credential::channelID);
        refused(FailureCode.INVALID_RECONNECT, credential::admissionProofForTransport);
        refuseCredential(() -> credential.sealForTransport(Direction.VIEWER_TO_HOST, new byte[0], new byte[12], new byte[0]));
        // These structural tests do not authenticate malicious in-process callers or prove a store write.
    }

    private static ReconnectPreparation retained(ViewerPairRecord record, String name) throws Exception {
        String p = prefix(name);
        return record.authenticateRetainedReconnect(identity(), reference(p + "input.viewer-ephemeral-private"),
                reference(p + "input.viewer-nonce"), request(reference(p + "request.full")));
    }
    private static ViewerIdentity identity() throws Exception { return ViewerPairingAuthenticator.viewerIdentity(id("input.viewer-device-id"), data("input.viewer-signing-seed")); }
    private static Agreement agreement() throws Exception {
        PreparedViewer prepared = ViewerPairingAuthenticator.authenticateRetainedLocalHello(id("input.viewer-device-id"), "Test iPhone",
                data("input.viewer-signing-seed"), data("input.invitation-secret"), data("input.viewer-ephemeral-private"), data("input.viewer-nonce"),
                (HelloPayload) PairingPayloadDecoder.decode(data("hello.viewer.payload")));
        return ViewerPairingAuthenticator.acceptHost(prepared, (HelloPayload) PairingPayloadDecoder.decode(data("hello.host.payload")));
    }
    private static ViewerPairRecord pending() throws Exception {
        Agreement agreement = agreement();
        return agreement.makePendingRecord(agreement.authenticateHostConfirmation((ConfirmationPayload) PairingPayloadDecoder.decode(data("confirmation.host.payload"))), CREATED_AT);
    }
    private static ViewerPairRecord accepted() throws Exception { return pending().prepareAcknowledgement(commit("proposal"), identity()).record(); }
    private static ViewerPairRecord active() throws Exception { return accepted().acceptCompletion(commit("completion"), identity()).record(); }
    private static CommitPayload commit(String phase) throws Exception { return (CommitPayload) PairingPayloadDecoder.decode(data("commit." + phase + ".payload")); }
    private static byte[] encode(ViewerPairRecord record) throws Exception { return record.encodeForPrivateStorage(identity()).copyForPrivateStorage(); }
    private static ViewerStorageCatalog catalog() throws Exception {
        ViewerStorageCatalog[] catalogs = new ViewerStorageCatalog[6];
        try {
            catalogs[0] = ViewerStorageCatalog.firstEnrollment(id("input.viewer-device-id"), data("input.viewer-signing-seed"));
            catalogs[1] = catalogs[0].begin(SLOT, fill(0x33, 32), 0, 0);
            catalogs[2] = catalogs[1].write(catalogs[1].stamp(SLOT), encode(pending()));
            catalogs[3] = catalogs[2].write(catalogs[2].stamp(SLOT), encode(accepted()));
            catalogs[4] = catalogs[3].admit(catalogs[3].stamp(SLOT), 0, fill(0x33, 32));
            catalogs[5] = catalogs[4].write(catalogs[4].stamp(SLOT), encode(active()));
            return catalogs[5];
        } finally { for (int i = 0; i < 5; i++) if (catalogs[i] != null) catalogs[i].close(); }
    }
    private static ViewerPairRecord withCounters(ViewerPairRecord record, String next, String highest) throws Exception {
        byte[] body = body(encode(record)); ByteBuffer.wrap(body, counterOffset(body), 16).putLong(unsignedBits(next)).putLong(unsignedBits(highest));
        return ViewerPairRecord.restore(signedBody(body), identity());
    }
    private static byte[] signedBody(byte[] body) throws Exception {
        byte[] label = ascii(PRIVATE_DOMAIN);
        byte[] input = ByteBuffer.allocate(label.length + 1 + 8 + body.length).put(label).put((byte) 0).putLong(body.length).put(body).array();
        byte[] signature = BouncyCastlePairingCrypto.ed25519Sign(data("input.viewer-signing-seed"), input);
        return ByteBuffer.allocate(12 + body.length + 64).put(ascii("BVR-SIG1")).putInt(body.length).put(body).put(signature).array();
    }
    private static byte[] body(byte[] encoded) {
        check(encoded.length >= 76, "bounded test private envelope"); int size = ByteBuffer.wrap(encoded, 8, 4).getInt();
        check(size == encoded.length - 76, "test private body framing"); return Arrays.copyOfRange(encoded, 12, 12 + size);
    }
    private static int counterOffset(byte[] body) { return 209 + ByteBuffer.wrap(body, 133, 4).getInt(); }
    private static long unsignedBits(String value) {
        java.math.BigInteger integer = new java.math.BigInteger(value);
        check(integer.signum() >= 0 && integer.bitLength() <= 64, "test setup is exact unsigned64 before preserving raw bits");
        return integer.longValue();
    }
    private static ReconnectMessages.Request request(byte[] bytes) throws ReconnectMessages.DecodeFailure { return ReconnectMessages.decodeRequest(bytes); }
    private static ReconnectMessages.Response response(byte[] bytes) throws ReconnectMessages.DecodeFailure { return ReconnectMessages.decodeResponse(bytes); }
    private static ReconnectMessages.Response signedResponse(byte[] full, byte[] seed) throws Exception {
        ReconnectMessages.Response original = response(full);
        byte[] signed = BouncyCastlePairingCrypto.ed25519Sign(seed, ReconnectMessages.responseSignatureInput(original));
        return response(changedString(full, "signature", base64(signed)));
    }
    private static byte[] changedString(byte[] value, String key, String replacement) { return changed(value, key, "\"[^\"]*\"", "\"" + replacement + "\""); }
    private static byte[] changedNumber(byte[] value, String key, String replacement) { return changed(value, key, "[0-9]+", replacement); }
    private static byte[] changed(byte[] value, String key, String pattern, String replacement) {
        String text = new String(value, StandardCharsets.US_ASCII); Matcher match = Pattern.compile("\"" + Pattern.quote(key) + "\":" + pattern).matcher(text);
        check(match.find(), "controlled unique field exists"); int start = match.start(), end = match.end(); check(!match.find(), "controlled field occurs once");
        return ascii(text.substring(0, start) + "\"" + key + "\":" + replacement + text.substring(end));
    }
    private static Set<String> referenceNames() {
        Set<String> names = new HashSet<>();
        String[] suffixes = { "input.viewer-ephemeral-private", "input.host-ephemeral-private", "input.viewer-nonce", "input.host-nonce",
            "counter.viewer.before", "counter.viewer.after", "counter.host.before", "counter.host.after", "request.unsigned", "request.full",
            "request.payload", "request.signature-input", "response.unsigned", "response.full", "response.payload", "response.signature-input",
            "request-digest", "transcript.canonical", "transcript.domain-input", "credential.channel", "credential.admission", "credential.host-to-viewer", "credential.viewer-to-host" };
        for (String name : new String[] { "first", "second", "high", "max-minus-one" }) for (String suffix : suffixes) names.add(prefix(name) + suffix);
        names.addAll(Arrays.asList("basis.original-pairing-fixture-sha256", "basis.pair-id-text", "basis.commit-id-text",
                "basis.transcript-hash", "basis.root-public-test-only", "boundary.maximum.refusal"));
        return names;
    }
    private static Map<String, byte[]> load(Path path, String expectedSHA, String schema, int count, Set<String> expectedNames) throws Exception {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try (InputStream input = Files.newInputStream(path)) { byte[] chunk = new byte[4096]; int n; while ((n = input.read(chunk)) != -1) { check(out.size() + n <= 131072, "bounded PUBLIC fixture"); out.write(chunk, 0, n); } }
        byte[] raw = out.toByteArray(); StringBuilder hex = new StringBuilder();
        for (byte b : MessageDigest.getInstance("SHA-256").digest(raw)) hex.append(String.format(Locale.ROOT, "%02x", b & 255));
        check(expectedSHA.matches("[a-f0-9]{64}") && expectedSHA.equals(hex.toString()), "independently pinned actual Swift fixture SHA");
        for (byte b : raw) check(b >= 0, "ASCII TSV container");
        String text = new String(raw, StandardCharsets.US_ASCII); check(text.startsWith("# " + schema + "\n") && text.endsWith("\n"), "exact actual fixture schema");
        Map<String, byte[]> rows = new TreeMap<>(); String previous = "";
        for (String row : text.split("\n")) {
            if (row.startsWith("#")) continue;
            String[] columns = row.split("\t", -1); check(columns.length == 2 && columns[0].matches("[A-Za-z0-9.-]{1,96}") && columns[0].compareTo(previous) > 0, "unique canonical sorted fixture names");
            byte[] decoded = Base64.getDecoder().decode(columns[1]); check(decoded.length > 0 && decoded.length <= 8192 && base64(decoded).equals(columns[1]), "bounded canonical padded Base64");
            check(rows.put(columns[0], decoded) == null, "no duplicate fixture row"); previous = columns[0];
        }
        check(rows.size() == count && (expectedNames == null || rows.keySet().equals(expectedNames)), "complete independently fixed reference inventory"); return rows;
    }
    private static String prefix(String name) { return "reconnect." + name + "."; }
    private static String text(String key) { return new String(reference(key), StandardCharsets.US_ASCII); }
    private static byte[] reference(String key) { byte[] value = reconnect.get(key); check(value != null, "exact reconnect fixture row"); return value.clone(); }
    private static byte[] data(String key) { byte[] value = pairing.get(key); check(value != null, "exact initial pairing fixture row"); return value.clone(); }
    private static UUID id(String key) { return UUID.fromString(new String(data(key), StandardCharsets.US_ASCII)); }
    private static byte[] fill(int value, int count) { byte[] bytes = new byte[count]; Arrays.fill(bytes, (byte) value); return bytes; }
    private static byte[] flipped(byte[] bytes) { byte[] result = bytes.clone(); result[0] ^= 1; return result; }
    private static byte[] ascii(String text) { return text.getBytes(StandardCharsets.US_ASCII); }
    private static String base64(byte[] bytes) { return Base64.getEncoder().encodeToString(bytes); }
    private interface Checked { void run() throws Exception; }
    private static void refused(FailureCode code, Checked operation) throws Exception {
        try { operation.run(); throw new AssertionError("expected reconnect refusal"); }
        catch (AuthFailure error) { check(error.code() == code && error.getCause() == null && error.getSuppressed().length == 0, "exact normalized redacted auth refusal"); check(error.getMessage().equals("Beluga viewer authentication refused: " + code.name()), "fixed error excludes payloads and keys"); }
    }
    private static void storageRefused(Checked operation) throws Exception {
        try { operation.run(); throw new AssertionError("expected exact catalog refusal"); }
        catch (ViewerStorageCatalog.Failure error) { check(error.getMessage().equals("Beluga private storage refused"), "fixed storage diagnostic"); }
    }
    private static void malformed(Checked operation) throws Exception {
        try { operation.run(); throw new AssertionError("expected malformed reconnect message refusal"); }
        catch (ReconnectMessages.DecodeFailure error) { check(error.getCause() == null && error.getSuppressed().length == 0
                && error.getMessage().equals("Invalid Beluga v1 reconnect payload"), "fixed decoder error retains no raw input or cause"); }
    }
    private static void refuseCredential(Checked operation) throws Exception {
        try { operation.run(); throw new AssertionError("expected opaque credential authentication refusal"); }
        catch (AuthFailure error) { check(error.code() == FailureCode.AUTHENTICATION_FAILED || error.code() == FailureCode.MALFORMED_INPUT, "bounded normalized opaque credential refusal"); }
    }
    private static void check(boolean condition, String message) { assertions++; if (!condition) throw new AssertionError(message); }
    private static void equal(byte[] expected, byte[] actual, String message) { check(Arrays.equals(expected, actual), message); }
}
