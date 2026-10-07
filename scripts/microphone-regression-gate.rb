#!/usr/bin/ruby
# Offline contributor evidence only. No physical destination or installed HAL probe is used.
require 'digest'
require 'fileutils'
require 'find'
require 'json'
require 'open3'
require 'rexml/document'
require 'set'
require 'shellwords'
require 'tmpdir'
require_relative 'microphone-simulator-signing'

module MicrophoneRegressionGate
  SCHEMA = 'beluga.microphone-regressions.offline.v1'.freeze
  XCODE_VERSION = "Xcode 26.6\nBuild version 17F113\n".freeze
  XCODEBUILD_SHA256 = 'd508f0e1901151843804e4af512d4587ad0e422039e43e14abf22792360ad3d4'.freeze
  RUST_VERSION = '1.97.1'.freeze
  RUSTUP_HOME = '/Volumes/t7/opensteamer-rustup-1.97.1'.freeze
  CARGO_HOME = '/Volumes/t7/opensteamer-cargo-1.97.1'.freeze
  NODE_ENTRYPOINT = '/opt/homebrew/bin/node'.freeze
  RUST_SOURCE_FILES = %w[Cargo.toml Cargo.lock rust-toolchain.toml .gitignore src/lib.rs
                       include/opensteamer_audio_transaction_authority.h include/module.modulemap
                       scripts/build-xcframework.sh scripts/verify-xcframework.sh tests/reducer.rs tests/ffi.rs
                       tests/c_abi_smoke.c tests/swift_import_smoke.swift THIRD_PARTY_NOTICES.html].freeze
  BELUGA_CORE_CRATE = 'shared/Rust/BelugaCore'.freeze
  BELUGA_CORE_ARTIFACT = 'shared/Vendor/BelugaCore.xcframework'.freeze
  BELUGA_CORE_SOURCE_FILES = %w[Cargo.toml Cargo.lock rust-toolchain.toml .gitignore README.md THIRD_PARTY_NOTICES.html
                               src/lib.rs src/host_lifecycle.rs src/handoff_transactions.rs src/handoff_offers.rs src/youtube_handoff_operation.rs src/invitation_acceptance.rs src/replay_policy.rs src/pairing_catalog_checkpoint.rs src/reconnect_counters.rs src/pairing_commit.rs src/supported_player_arbitration.rs include/beluga_core.h include/module.modulemap
                               tests/policy.rs tests/host_lifecycle.rs tests/handoff_transactions.rs tests/handoff_offers.rs tests/youtube_handoff_operation.rs tests/invitation_acceptance.rs tests/replay_policy.rs tests/pairing_catalog_checkpoint.rs tests/reconnect_counters.rs tests/pairing_commit.rs tests/supported_player_arbitration.rs tests/c_abi_smoke.c tests/swift_import_smoke.swift
                               scripts/artifact_support.rb scripts/build-xcframework.rb scripts/verify-xcframework.rb
                               scripts/mutation-tests.rb
    src/availability_retry.rs
    tests/availability_retry.rs
    src/safe_output_retry.rs
    tests/safe_output_retry.rs
    src/system_audio_start.rs
    tests/system_audio_start.rs
    src/hosted_call_policy.rs
    tests/hosted_call_policy.rs
  ].freeze
  BELUGA_CORE_FRAMEWORK = 'BelugaCore.framework'.freeze
  BELUGA_CORE_SLICES = {
    'macos-arm64' => { 'SupportedArchitectures' => ['arm64'], 'SupportedPlatform' => 'macos' },
    'ios-arm64' => { 'SupportedArchitectures' => ['arm64'], 'SupportedPlatform' => 'ios' },
    'ios-arm64_x86_64-simulator' => { 'SupportedArchitectures' => %w[arm64 x86_64],
                                     'SupportedPlatform' => 'ios', 'SupportedPlatformVariant' => 'simulator' }
  }.freeze
  BELUGA_CORE_ARTIFACT_FILES = (%w[Info.plist SOURCE_MANIFEST.sha256 BUILD_METADATA.txt THIRD_PARTY_NOTICES.html] +
    BELUGA_CORE_SLICES.keys.flat_map do |slice|
      %w[BelugaCore Headers/beluga_core.h Modules/module.modulemap Info.plist].map { |path| slice + '/' + BELUGA_CORE_FRAMEWORK + '/' + path }
    end).freeze
  BELUGA_CORE_FRAMEWORK_INFO = {
    'CFBundleExecutable' => 'BelugaCore', 'CFBundleName' => 'BelugaCore',
    'CFBundleIdentifier' => 'com.elamin.beluga.core', 'CFBundleInfoDictionaryVersion' => '6.0',
    'CFBundlePackageType' => 'FMWK', 'CFBundleShortVersionString' => '0.1.0', 'CFBundleVersion' => '1'
  }.freeze
  BELUGA_CORE_TARGETS = %w[aarch64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios].freeze
  BELUGA_CORE_METADATA_PREFIX = (['rust-toolchain=' + RUST_VERSION, 'packaging-profile=static-framework-v1'] +
    BELUGA_CORE_TARGETS.map { |target| 'supported-target=' + target } +
    ['supported-architecture=arm64', 'simulator-architectures=arm64,x86_64', 'abi-version=1']).freeze
  C_PINNED = {
    'core invariant' => ['visible-first/writer-first joins and leaves', '1000 fresh epochs', 'concurrent lifecycle and timeline stress'],
    'driver interface' => ['shared timeline both start orders and restart seed',
                           'idle dual-endpoint registrations do not starve new reader',
                           'active client capacity remains bounded and recovers',
                           'diagnostic v2 matches representable frozen v1 state',
                           'registration allocation failure preserves writer and allows retry',
                           'zero timestamp publication keeps returned lifecycle',
                           'diagnostic snapshot concurrent coherency and progress']
  }.freeze
  PAIRING_FILES = {
    'ViewerPairingPersistenceTests' => 'iOS/opensteamer/Tests/ViewerPairingPersistenceTests.swift',
    'ViewerPairedMacCatalogTests' => 'iOS/opensteamer/Tests/ViewerPairedMacCatalogTests.swift',
    'BelugaRustInvitationAcceptanceActionTests' => 'iOS/opensteamer/Tests/InvitationAcceptanceActionNativeTests.swift',
    'BelugaRustInvitationAcceptanceTests' => 'iOS/opensteamer/Tests/BelugaRustInvitationAcceptanceTests.swift',
  }.freeze
  PAIRING_CLASSES = PAIRING_FILES.keys.freeze
  PAIRING_SOURCE_SHA256 = {
    'ViewerPairingPersistenceTests' => '2ee5308801720111b504549146c652057583af8ac9601335efa8e63ea837e724',
    'ViewerPairedMacCatalogTests' => '2ed701ff30341c49c279681f16d944d79635135b30c76cf9f5ca6b23df29f63e',
    'BelugaRustInvitationAcceptanceActionTests' => 'ff5c34c02c5210afaa4ca076a3c86a6b335d2c92418c2719493a5e7941c4e176',
    'BelugaRustInvitationAcceptanceTests' => '4e71293a0f04075eee0d8c354fb365c2a8960f13c70331299d8e4433f95402e0',
  }.freeze
  PAIRING_BY_CLASS = {
    'ViewerPairingPersistenceTests' => %w[
      testActualKeychainDecodeBridgeRefusalSurvivesBothReadsWithoutChangingBytes
      testActualIssuedCatalogReadbackBridgeRefusalPrecedesInterruptedBootstrapFallback
      testAbsoluteDeadlineClosesAHealthySocketThatWaitsForeverForTheMac
      testAcceptedIssuedRecordSurvivesRelaunchForCommitRecovery
      testActiveViewerResendsActivationProofBeforeReconnectRequest
      testAdmissionBoundaryRelaunchesThroughRecoverablePairingRecord
      testAuthenticatedCompletionPersistsBeforeInvitationDeletionExactlyOnce
      testAvailabilityRetriesWhenHostRegistrationIsNotReady
      testAvailabilityRetrySleepIsCancellableWithoutLosingPairing
      testAvailabilityRetryUsesThirtySecondDeadlineAndFourSecondCap
      testBothEmptyNamespacesCreateIdentityOnlyInPrimary
      testCancellationDuringViewerConfirmationSendCannotPublishCommittingState
      testCancelledOperationCannotCloseOrResetReplacementOperation
      testCancelledSuspendedActivationCannotOverwriteReplacementPair
      testCancelledSuspendedActivationCannotResavePairAfterForget
      testCorruptPrimaryRecordFailsClosedWithoutLegacyFallback
      testDeadlineCloseBeforeReadySendStillPublishesRetainedPairRecovery
      testDifferentInvitationBypassesPriorAdmissionMarker
      testFailedHydrationCanRetryAfterProtectedDataBecomesAvailable
      testFailureBeforeRecoverableBoundaryLeavesInvitationRetryable
      testForgetDeletesPairButPreservesViewerIdentity
      testFreshAttemptRetiresTerminalMediaHistoryButPassiveLifecycleDoesNot
      testFreshExchangeImmediatelyResendsWithANewerReconnectSequence
      testHostOnlyAcceptedReceivedStateIsRejectedByViewerStore
      testInterruptedPairingRetriesSavedInvitationThenFallsBackToDurablePair
      testInterruptedPairingRetriesTransientReplacementConflict
      testLegacyForgetPromotesIdentityAndDeletesSelectedLegacyPairLast
      testLegacyIdentityOnlyIsNotFallbackAndCreatesOnlyPrimaryIdentity
      testLegacyReadFailureDoesNotCreatePrimaryIdentity
      testLegacySelectedForgetAcceptsEqualPrimaryIdentityWithoutRewritingIt
      testLegacySelectedForgetPromotesExactIdentityThenDeletesBothPairs
      testLegacySelectedForgetRejectsConflictingPrimaryIdentityBeforeDeleting
      testNamespaceSelectorPrefersCompletePrimaryPairWithoutProbingLegacy
      testNamespaceSelectorPropagatesKeychainReadFailureWithoutFallback
      testNamespaceSelectorUsesCompleteLegacyPairOnlyWhenPrimaryIsEmpty
      testPairOnlyKeychainNamespaceFailsClosedWithoutCreatingIdentity
      testPairOnlyPrimaryFailsClosedWithoutProbingLegacyOrWriting
      testPairPersistenceFailureNeverDeletesInvitation
      testPairedMacMustBeBoundToExactViewerIdentity
      testPairingKeychainItemsAreThisDeviceOnly
      testPairingPreparationKeepsBackgroundLeaseUntilExplicitCancellation
      testPendingPairingCompletionCannotDeleteInvitation
      testPendingRecordCannotPersistAdmissionBoundary
      testPendingViewerRecordHydratesOnlyAsRecoveryState
      testPrimaryForgetDeletesUnselectedLegacyPairBeforeSelectedPrimaryPair
      testPrimaryIdentityOnlyIsExplicitlyUnpairedAndDoesNotProbeLegacy
      testPrimaryRecordBoundToAnotherIdentityFailsClosedWithoutMixing
      testPrimarySelectedForgetDeletesBothPairsAndPreservesBothIdentities
      testReadyThenProcessDeathWithoutPairLeavesSavedInvitationRetryable
      testReconnectDeadlineAlsoBoundsASuspendedRequestSend
      testReconnectResponseAtAbsoluteDeadlineCannotStartMedia
      testSavingAfterLegacySelectionWritesOnlyLegacyNamespace
      testSilentReconnectResponseClosesAttemptAndRetriesWithNextSequence
      testStoredHostIdentityIsRejectedInsteadOfSilentlyReplaced
      testSuccessfulRecoveryBootstrapAvailabilityDeadlineDoesNotFallbackOrRestartBudget
      testSuccessfulRecoveryBootstrapNontransientAvailabilityErrorDoesNotFallback
      testThreeColdReconnectPayloadSequencesAreAcceptedByTheRealHostRecord
      testViewerIdentityAndPairedMacSurviveStateReconstruction
      testViewerPersistenceFailurePreventsConfirmationTransmission
      testViewerPersistsPendingRecordBeforeSendingItsConfirmation
      testReconnectCounterSaveFailureBlocksRequestAndColdRetryUsesStoredPredecessor
      testReconnectCounterWriteThenThrowBurnsDurablyAndColdRetryNeverReusesIt
    ].freeze,
    'ViewerPairedMacCatalogTests' => %w[
      testAddingAndForgettingMacsNeverDropsOtherPairsOrRotatesIdentity
      testCatalogRejectsIdentityMismatchAndMissingIdentityWithoutManufacturingReplacement
      testCorruptionUnknownSelectionAndWriteFailureFailClosedWithoutDeletingPairs
      testInterruptedSecondPairRetainsFirstActiveMacAndPendingSelectionAcrossRelaunch
      testMigratedPendingMacDoesNotGuessWhichUnboundInvitationBelongsToIt
      testMigrationAndSecondMacPreserveIdentityAndBothIndependentPairsAcrossRelaunch
      testPendingMacRecoveryBindsInvitationToExactSelectedPairAcrossRelaunch
      testSavedMacSwitchWaitsForBothRetirementsAndRejectsEveryStaleBoundary
    ].freeze,
    'BelugaRustInvitationAcceptanceActionTests' => %w[
      testAbsentAdmissionCallbackStillConsumesTheAcceptedIssuedBoundary
      testCallbackReceivesExactSuppliedRecordWithoutInventedPairBinding
      testCompletionDoesNotRequireAnAdmissionCallOrSuccessfulAdmission
      testCopiesAfterAdmissionPreserveConsumptionButRetireIndependently
      testCopiesBeforeAdmissionHaveIndependentOnceOnlyGates
      testExactCancelRetiresAllGatesAndIsIdempotent
      testExactGenerationRejectsEveryNonActivePhaseWithoutCallback
      testExactGenerationRejectsEveryNonRecoverablePhaseWithoutCallback
      testForeignCancelCannotRetireOrResetTheCurrentOwner
      testForeignGenerationReturnsBeforeRecoverableAndActiveValidation
      testRearmAfterCompletionOrCancellationCreatesFreshAuthority
      testRearmWithDifferentGenerationReplacesClosuresAndRejectsTheOldOwner
      testRearmingOneValueCopyCannotReplaceAnotherCopiesClosure
      testSameUUIDRearmResetsConsumptionAndInstallsOnlyNewClosures
      testSeededTracePreservesFrozenOrderingOutcomesCallbacksAndRecords
      testSuccessfulAdmissionRunsOnceAndDuplicateReturnsBeforePhaseCheck
      testSuccessfulCompletionRetiresAllGatesBeforeAnyLatePhaseCheck
      testThrowingAdmissionPreservesRetryAndConsumesOnlyAfterSuccess
      testThrowingCallbacksRetainActualEffectsButPermitRetry
      testThrowingCompletionDoesNotRetireEitherCallback
      testThrowingCompletionPreservesAlreadyConsumedAdmission
      testUnarmedCallsReturnBeforeEveryPairingPhaseGuard
    ].freeze,
    'BelugaRustInvitationAcceptanceTests' => %w[
      testBoundaryCannotLoseExactCancelRetirementOnMalformedOutput
      testBoundaryRejectsAdmissionPlanThatClearsCompletionAuthority
      testBoundaryRejectsCallbackKindAndPreparedFlagsSwaps
      testBoundaryRejectsCompletionPlanThatLosesRetirement
      testBoundaryRejectsForgedAdmissionPermissionForWrongPhase
      testBoundaryRejectsForgedCallbackPermissionForForeignUUID
      testBoundaryRejectsForgedCompletionPermissionForWrongPhase
      testBoundaryRejectsMalformedVersionsStatusesBooleansAndImpossibleStates
      testBoundaryRejectsPreEffectAdmissionConsumption
      testBoundaryRejectsPreEffectCompletionRetirement
      testBoundaryRejectsWrongStatusAndFabricatedCompletionBoolean
      testControlsAcceptEveryLegitimateStateGuardAndIndependentValueCopy
      testDifferentGenerationAndCancelledCallsCannotUseRetiredNativeOwner
      testPartialEffectCallbackFailurePropagatesAndExactRetryRemainsPossible
      testPrevalidatedCandidateCommitsFromActualSuccessWithNoPostEffectFFIOrReplay
      testSameUUIDRearmRotatesOwnerAndOnlyReplacementClosuresCanRun
    ].freeze,
  }.freeze
  PAIRING_PINNED = PAIRING_BY_CLASS.flat_map { |name, methods| methods.map { |method| name + '/' + method } }.sort.freeze
  PAIRING_APP_ROOT = 'iOS/opensteamer/Sources/App/OpensteamerApp.swift'.freeze
  PAIRING_APP_ROOT_SHA256 = '8109b0dbae6db7f1555e6dbfb10a70dcba5c364709a99be4630b1af3bbe1f08f'.freeze
  PAIRING_INERT_CONDITIONS = 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG OPENSTEAMER_UPDATE_VALIDATION_HOST'.freeze
  PAIRING_PROOF_FILES = { 'Beluga.SwiftFileList' => 1024 * 1024, 'opensteamer-OutputFileMap.json' => 4 * 1024 * 1024,
                          'OpensteamerApp.o' => 16 * 1024 * 1024, 'app-swift-driver.txt' => 1024 * 1024 }.freeze
  PAIRING_PHASE_TIMEOUTS = { 'pairing-inert-build' => 600, 'pairing-tests' => 900, 'pairing-summary' => 30,
                             'pairing-results' => 30, 'pairing-signature' => 30, 'pairing-entitlements' => 30 }.freeze
  PAIRING_OVERALL_SECONDS = 1200

  SIMULATOR_CLASSES = %w[WorldwideAudioLifecycleTests WebRTCAudioPlaybackSessionTests IOSAudioDiagnosticsJournalTests
                        ScreenVideoIdleTimerTests ScreenVideoIdleTimerViewTests
                        YouTubeHandoffOperationTests YouTubeHandoffWebViewTests
                        YouTubeHandoffCoordinatorTests BelugaRustYouTubeHandoffOperationTests].freeze
  SIMULATOR_SKIPS = %w[
    WorldwideAudioLifecycleTests/testPhysicalDeviceCanConfigureLegacyBackgroundPlaybackSession
    WebRTCAudioPlaybackSessionTests/testPhysicalPolicyScenarioOriginalOrder
    WebRTCAudioPlaybackSessionTests/testPhysicalPolicyScenarioInitialIdle
    WebRTCAudioPlaybackSessionTests/testPhysicalPolicyScenarioPostInputRead
    WebRTCAudioPlaybackSessionTests/testPhysicalPolicyScenarioColdDuplexFirst
    WebRTCAudioPlaybackSessionTests/testPhysicalPolicyScenarioProductionOrder
    WebRTCAudioPlaybackSessionTests/testPhysicalInertPolicyAfterRemoteCommandCenterShared
    WebRTCAudioPlaybackSessionTests/testPhysicalInertPolicyAfterDisabledPlayCommandTarget
    WebRTCAudioPlaybackSessionTests/testPhysicalInertPolicyAfterNowPlayingInfoCenterDefault
    WebRTCAudioPlaybackSessionTests/testPhysicalInertPolicyAfterClearingNowPlayingInfo
    WebRTCAudioPlaybackSessionTests/testPhysicalInertPolicyAfterStoppedPlaybackState
    WebRTCAudioPlaybackSessionTests/testPhysicalInertPolicyAfterPlayCommandTargetOnly
    WebRTCAudioPlaybackSessionTests/testPhysicalInertPolicyAfterDisablingPlayCommandOnly
    WebRTCAudioPlaybackSessionTests/testPhysicalInertPolicyAfterDisabledPlayTargetRemoval
    WebRTCAudioPlaybackSessionTests/testPhysicalInertPolicyRestoresCapturedDefaultAfterTargetRemoval
    WebRTCAudioPlaybackSessionTests/testPhysicalInertPolicyRegistersTargetAfterInactiveDuplexSetter
    WebRTCAudioPlaybackSessionTests/testPhysicalInertPolicySetsInactiveDuplexWhileTargetIsRegistered
    WebRTCAudioPlaybackSessionTests/testPhysicalInertPolicyAfterBeginReceivingRemoteControlEvents
    WebRTCAudioPlaybackSessionTests/testPhysicalInertDevelopmentHostMicrophonePermissionSetup
    WebRTCAudioPlaybackSessionTests/testPhysicalInertInputTapCharacterizesRegisteredMediaCommandPolicy
    WebRTCAudioPlaybackSessionTests/testPhysicalSoleViewerRemoteIOCapturesMicrophoneAcrossPublicAdmissionCycles
    WebRTCAudioPlaybackSessionTests/testPeerUsesStereoRemoteIOAndReceivesNativePlayoutCallbacks
  ].freeze
  SIMULATOR_PINNED = %w[
    ScreenVideoIdleTimerTests/testPausedOrStoppedObservationReleasesPriorPlayingEvidence
    ScreenVideoIdleTimerTests/testAudioOnlyOrHiddenScreenDoesNotPreventSleep
    ScreenVideoIdleTimerTests/testForeignOrRemovedOwnerExpiryCannotReleaseSuccessor
    ScreenVideoIdleTimerViewTests/testNativeIdleTimerTracksScenePlaybackHideAndViewRemoval
    WorldwideAudioLifecycleTests/testExternalPausePublishesNotificationWhileStatisticsReaderIsSuspended
    WorldwideAudioLifecycleTests/testOrdinaryRawMicrophoneProfileRequiresExactTupleAndSupportedEffectivePolicy
    WorldwideAudioLifecycleTests/testTransportUncertaintyClosesMicrophonePrivacyBeforeOutputOnlyOwnerReturns
    WorldwideAudioLifecycleTests/testPublicOutputOnlyDisableClosesMicrophonePrivacyBeforeNativeAttemptForSuccessAndFailure
    WorldwideAudioLifecycleTests/testSuspendedRawMicrophoneStatisticsReadCannotRepublishAcrossEveryRevocationBoundary
    WorldwideAudioLifecycleTests/testWiredMicrophoneOracleRequiresFreshExclusiveRouteAndPrivacyAuthority
    WorldwideAudioLifecycleTests/testManualMicrophoneOffCancelsPendingAutomaticAttemptAndPersistsAcrossRecovery
    WorldwideAudioLifecycleTests/testNewAuthenticatedSessionMayRetryAutomaticMicrophoneAfterDenial
    WorldwideAudioLifecycleTests/testReplacementConnectionWaitsForRetiredPeerCloseBeforeAudioActivation
    WorldwideAudioLifecycleTests/testReconnectNoOutboundRTPLifecycleCompositionRecoversOnceAcrossDelayedSameTargetNotification
    WorldwideAudioLifecycleTests/testTransportUncertaintyRetiresEstablishedMicrophoneBeforeHealthyReAdmission
    WorldwideAudioLifecycleTests/testFreshPreparationWaitsForExactRetiredPeerClose
    WorldwideAudioLifecycleTests/testDeferredMicrophonePermissionCannotCrossRevocationBoundaries
    WorldwideAudioLifecycleTests/testRetiredPollingProofCannotApplyHealthyDiagnosticsToReplacementAudio
    WorldwideAudioLifecycleTests/testRetiredRecoveryAuthorizationBlocksDelayedNativeSideEffect
    WebRTCAudioPlaybackSessionTests/testFrameworkMicrophoneStopClosesCaptureWithoutStealingOutputOnlyTransaction
    WebRTCAudioPlaybackSessionTests/testPendingCategoryRouteCursorRequiresExactChainedTransactionEvidence
    WebRTCAudioPlaybackSessionTests/testMicrophoneApprovalRejectsZeroWrongStaleRevokedAndRetiredGenerations
    WebRTCAudioPlaybackSessionTests/testWiredMicrophoneNativeSelectionAndEveryTransactionBoundary
    YouTubeHandoffOperationTests/testOnlyAdvancingExactVisiblePlaybackConfirmsOnce
    YouTubeHandoffOperationTests/testOnlyReservedExactCompletionMovesPlaybackAndCannotBeReplayed
    YouTubeHandoffOperationTests/testCommittedPlayerAllowsLocalControlsPastOfferDeadlineWithoutNewAuthority
    YouTubeHandoffOperationTests/testPendingPlaybackInterruptionCannotReviveAfterSuccessReply
    YouTubeHandoffOperationTests/testCompletionRequiresFreshContinuingPhonePlaybackNotFreshOriginalProof
    YouTubeHandoffOperationTests/testMissingCompletionTimesOutUnknownAndDoesNotRenewOriginalDeadline
    YouTubeHandoffWebViewTests/testOwnedMainFrameCanConfirmThenDismantleRevokesAndHides
    YouTubeHandoffWebViewTests/testBackgroundRevokesPlayerAndCannotResumeOldOperation
    YouTubeHandoffWebViewTests/testSuppliedCompletionKeepsWebViewAliveForLocalPauseSeekAndRateControls
    YouTubeHandoffWebViewTests/testDismissAfterReservationClosesWebViewWithoutClaimingMacWasUntouched
    WorldwideAudioLifecycleTests/testComposedHandoffReceiverUsesRealPeerAndScopedAudioOwner
    WorldwideAudioLifecycleTests/testComposedHandoffTransportRetirementCannotSendMacPause
    WorldwideAudioLifecycleTests/testMediaHandoffMutesOnlyOwnedDownlinkWithoutChangingMicrophoneOrNativeSession
    WorldwideAudioLifecycleTests/testMediaHandoffRequiresPreparedHealthyProvenAudioAndFreshCallState
    WorldwideAudioLifecycleTests/testMediaHandoffStaleReleaseCannotUnmuteReplacementOwnerOrSession
    WorldwideAudioLifecycleTests/testMediaHandoffRevocationKeepsMuteThroughRecoveryUntilExactPlayerCleanup
    WorldwideAudioLifecycleTests/testMediaHandoffReleasingAfterRouteLossNeverClearsExplicitResume
    WorldwideAudioLifecycleTests/testMediaHandoffRevokesOnInterruptionCallProofLossAndTrackReplacement
    WorldwideAudioLifecycleTests/testMediaHandoffInvalidationAllowsReentrantExactCleanupWithoutOpeningUnhealthyTrack
    WorldwideAudioLifecycleTests/testMediaHandoffAdmissionDoesNotReturnOwnerRetiredBySnapshotReentrancy
    WorldwideAudioLifecycleTests/testMediaHandoffMuteDoesNotMaskFrozenCallbacksOrLaterUnmutedDecodeFailure
    WorldwideAudioLifecycleTests/testMediaHandoffMuteOwnerChangeStartsFreshLivenessWindow
    WorldwideAudioLifecycleTests/testMediaHandoffRoundTripBetweenSamplesResetsLivenessWindow
    WorldwideAudioLifecycleTests/testMediaHandoffStatsReadCannotCrossSuppressionChangesIncludingRoundTrip
    YouTubeHandoffCoordinatorTests/testExactOfferDispatchesOnceAndFastCompletionKeepsLocalPlayer
    YouTubeHandoffCoordinatorTests/testDismissRevokesImmediatelyButCannotUnmuteUntilExactStopAcknowledgement
    YouTubeHandoffCoordinatorTests/testOwnerInvalidationBeforePlaybackClosesWithoutSendingPause
    YouTubeHandoffCoordinatorTests/testPresentationSelectsTopmostOnceAndRejectsAmbiguityOrReplacement
    YouTubeHandoffCoordinatorTests/testNativeWebKitStopAcknowledgesBeforeReleaseAndOnlyOnce
    YouTubeHandoffCoordinatorTests/testUnpresentedOfferTimesOutWithoutHoldingAudioForever
    YouTubeHandoffCoordinatorTests/testSwiftUIPresenterActuallyMountsOnePlayerAboveRootAndFullScreen
    YouTubeHandoffCoordinatorTests/testAcquisitionRevocationCannotCreateAPlayerOrLeakSuppression
    YouTubeHandoffCoordinatorTests/testStaleConnectionAndRegressingClockCannotAcquireAudio
    BelugaRustYouTubeHandoffOperationTests/testFrozenOriginalConfirmationAndAllCompletionOutcomesMatch
    BelugaRustYouTubeHandoffOperationTests/testNativeMessageDomainsAndSequenceObservationOrderingMatch
    BelugaRustYouTubeHandoffOperationTests/testWholeNativeProofEqualityRejectsEveryPublicFieldMutation
    BelugaRustYouTubeHandoffOperationTests/testSignedZeroProofAliasUsesSwiftEqualityAndRetainsOriginalBits
    BelugaRustYouTubeHandoffOperationTests/testArbitraryConstructorClockBitsPreserveOriginalObservationSemantics
    BelugaRustYouTubeHandoffOperationTests/testAdjacentThresholdsAndUnrenewedProofAgeMatchFrozenArithmetic
    BelugaRustYouTubeHandoffOperationTests/testCopiesBeforeMintProduceNonSubstitutablePrivateEvidenceUUIDs
    BelugaRustYouTubeHandoffOperationTests/testCopiesWithExistingProofRevokeIndependentlyWithoutReminting
    BelugaRustYouTubeHandoffOperationTests/testInterruptedOrStalePhonePlaybackPreservesTruthfulMacOutcome
    BelugaRustYouTubeHandoffOperationTests/testBooleanClockFailureIsSilentButRevokesAndRepeatBeginIsEarlyNoop
    BelugaRustYouTubeHandoffOperationTests/testZeroCandidateDoesNotChangeBranchesThatCannotMint
    BelugaRustYouTubeHandoffOperationTests/testMaximumTokenMintsOnceAndExistingProofPendingAndLocalBranchesRemainUsable
    BelugaRustYouTubeHandoffOperationTests/testZeroCandidateOnlyEligibleMintFailsClosedAfterClockAndSequenceBurn
    BelugaRustYouTubeHandoffOperationTests/testLocalPlaybackNeverReopensHandoffAuthorityAndRetainsPausedOutcome
    BelugaRustYouTubeHandoffOperationTests/testBoundedReachableTraceParityChecksEveryCopiedScalarAndPublicEffect
    BelugaRustYouTubeHandoffOperationTests/testSeededLongTraceParityUsesFrozenOriginalWithoutDelegatingPolicy
    BelugaRustYouTubeHandoffOperationTests/testCopiedBoundaryAcceptsLegitimateMintFailureClearAndSilentBooleanResults
    BelugaRustYouTubeHandoffOperationTests/testCopiedBoundaryRejectsForgedMintRetainedProofRewriteAndCleanup
    BelugaRustYouTubeHandoffOperationTests/testCopiedBoundaryRejectsMissingRevocationFictionalOutcomesAndReplay
    BelugaRustYouTubeHandoffOperationTests/testMalformedCopiedOutputFailsClosedWithHonestStatusAndSilentBoolFallback
  ].freeze
  # Exact reviewed native/reference bytes; refresh only after review of any change.
  SUPPORTED_PLAYER_SOURCE_SHA256 = {
    'macOS/Sources/CaptureServer/BelugaRustSupportedPlayerArbitration.swift' => 'bfd79da465e40bb7ab1101876ea96c1bf92ba9a64ce2f14092f0d4870cf42b01',
    'macOS/Sources/CaptureServer/MacSupportedNowPlayingRuntime.swift' => 'fa5eabd215535707046d220b6ace63ef97e30815ef3f4842f3221608cedc084e',
    'macOS/Tests/CaptureServerTests/BelugaRustSupportedPlayerArbitrationTests.swift' => '1467ebb5a6e4eb07c5187718523e3749df3b2fa799551593eabfb42eb2888ead',
    'macOS/Tests/CaptureServerTests/SupportedPlayerArbitrationOriginalReference.swift' => 'bcd7f51c1bd987ff0032cda2a0e936ab72401f5846a9ea2c32a964b2040a8694',
    'macOS/Tests/CaptureServerTests/MacSupportedNowPlayingRuntimeTests.swift' => 'ee02e658eede1a4713f02c03f2e7b4372372946d3b36cbc2d8d2676407f82314',
  }.freeze
  SUPPORTED_PLAYER_FILES = {
    'CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests' => 'macOS/Tests/CaptureServerTests/BelugaRustSupportedPlayerArbitrationTests.swift',
    'CaptureServerTests.MacSupportedNowPlayingRuntimeTests' => 'macOS/Tests/CaptureServerTests/MacSupportedNowPlayingRuntimeTests.swift'
  }.freeze
  SUPPORTED_PLAYER_PINNED = {
    'CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests' => %w[
      CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testActualCopiedABIAndAll48LiteralOriginalDecisions
      CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testAll48CurrentNativeHistoriesMatchIndependentOriginalAndRetainedHold
      CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testAll48StaleNativeHistoriesCannotCallCoreOrRetireCurrentAuthority
      CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testEveryBoundedCopiedOutputCorruptionRetriesRevokesAndCanRecover
      CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testUnselectedChildRetryRevokesBothCatalogCommandsAndActualHandoff
      CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testMusicHoldSurvivesAbsentRetryAndBothPausedRecovery
      CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testFirstRetryCallbackCannotBeOverwrittenByDuplicateSnapshot
      CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testStopThenFreshPublicationCannotBeClearedByOldRetryJoin
      CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testStartingNewFetchDoesNotRevokeQueuedOrdinaryOrActualHandoff
      CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testInvalidCurrentOutputRetiresActualHandoffBeforeNativePauseEffect
      CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testWrappedSnapshotsPreserveExactNativeValuesCapabilitiesAndHandoffReference
      CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testSameNativeClientAndItemRetainTokensAcrossRateChanges
      CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testReplacementNativeClientOrItemRetiresQueuedOrdinaryAuthority
      CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testNoMediaClearsHoldBeforePausedFallbackAndRetiresQueuedCommand
      CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testOriginalRateGreaterThanZeroComparisonIsNotNewNumericValidation
      CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testNativeProjectionRequiresExactSlotsAndValidHold
      CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testActualRawInvalidInputsReturnInvalidAndNativeDecoderRejectsThem
      CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testAdditionalBrowserCannotHandoffWhenMusicIsSelected
      CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testDistinctInvalidDiagnosticIsThrottledAndContainsNoNativeContent
      CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testExternalRevocationAndStopRejectBothHeldOrdinaryAndHandoff
    ],
    'CaptureServerTests.MacSupportedNowPlayingRuntimeTests' => %w[
      CaptureServerTests.MacSupportedNowPlayingRuntimeTests/testSimultaneouslyDiscoveredPlayersPublishStablePrimaryAndIndependentCatalog
      CaptureServerTests.MacSupportedNowPlayingRuntimeTests/testSameInnerIdentityWithReplacementTokenRetiresPriorPublication
      CaptureServerTests.MacSupportedNowPlayingRuntimeTests/testPlayingYouTubeWinsPausedMusicAndPreservesExactMetadataAndCapabilities
      CaptureServerTests.MacSupportedNowPlayingRuntimeTests/testNewlyPlayingMusicDoesNotStealPrimaryUntilBrowserPauses
      CaptureServerTests.MacSupportedNowPlayingRuntimeTests/testSelectedSourceRetryRetiresCommandAuthorityWithoutSwitchingPlayer
      CaptureServerTests.MacSupportedNowPlayingRuntimeTests/testCommandGoesOnlyToSelectedSourceAndExternalRevocationClosesPendingAction
      CaptureServerTests.MacSupportedNowPlayingRuntimeTests/testSourceReplacementRejectsOldSnapshotAndAlreadyQueuedCommand
      CaptureServerTests.MacSupportedNowPlayingRuntimeTests/testQueuedCommandCannotRegainAuthorityAfterSourceReturnsToSameIdentity
      CaptureServerTests.MacSupportedNowPlayingRuntimeTests/testQueuedCommandCannotRegainAuthorityAfterItemReturnsToSameIdentity
      CaptureServerTests.MacSupportedNowPlayingRuntimeTests/testStopRevokesPendingCommandEvenAfterFreshFetchRestoresSameIdentity
      CaptureServerTests.MacSupportedNowPlayingRuntimeTests/testOutOfOrderFetchCannotReplaceNewerSelection
      CaptureServerTests.MacSupportedNowPlayingRuntimeTests/testDuplicateCallbacksCannotOverwriteFirstSourceResultOrCompleteTwice
      CaptureServerTests.MacSupportedNowPlayingRuntimeTests/testFetchCompletionAfterStopCannotReviveSelection
      CaptureServerTests.MacSupportedNowPlayingRuntimeTests/testMissingPlayersClearSelectionAndDiagnosticsContainNoMediaContent
    ]
  }.transform_values(&:freeze).freeze

  # Exact reviewed bodies. The coordinator is separately bound by the existing
  # pairing map to preserve that family's refusal ordering and diagnostics.
  BATCH_A_NATIVE_SOURCE_SHA256 = {
    'macOS/Sources/CaptureServer/BelugaRustAvailabilityRetry.swift' => '49fae2bf28a0b5f7aafbf3d531e979475eedfc6df1377dbf1c672d44973ca4ae',
    'macOS/Sources/CaptureServer/InertBatchARoutingObserverJoin.swift' => '2128c2468754ba927d7e8bbde6b17c540f592a8de034cd5e18c1eb00cb61d6d4',
    'macOS/Sources/CaptureServer/WorldwideHostLifecycle.swift' => '74d5f9ab042933f3ae9df7421043c3c1aca9d73f1be1ce3a752967ceefc0f7f1',
    'macOS/Sources/CaptureServer/WorldwideIPhoneMicrophoneForwardingDriver.swift' => 'f858dd89fc822d0a69a9cc369e5a869ebd2a0fa0a51dc5db39597f6fa3938daa',
    'macOS/Sources/CaptureServer/WorldwideMacHostedCallPolicies.swift' => '4761079aad79da792df639bed0adfcac9848125a85523f332d265a1b235aaeee',
    'macOS/Sources/CaptureServer/WorldwideSafeOutputInvariantRetryPolicy.swift' => '75e12a1781ccb95f96f79215236b3cb3385803e3ef48f12916fd0751ee427d9b',
    'macOS/Sources/CaptureServer/WorldwideScreenService.swift' => '3bd0169d15aa9abdc72e47cd33a45615cc9c61f9c134d466257665804bc5ae51',
    'macOS/Sources/CaptureServer/WorldwideScreenServiceAudioRoutingDependencies.swift' => '0afa9c4a0fdd13b5a430e90b7fb37c760df7d6d98858b7419f25aa7a39349575',
    'macOS/Sources/CaptureServer/WorldwideSystemAudioRecoveryPolicy.swift' => 'c3eabf280010b36f74d8ddac55b04e68dba7ca2aa379fc10bf1e964c619b7b3e',
    'macOS/Tests/CaptureServerTests/AvailabilityRetryOriginalReference.swift' => '67e656ef51cff56e47745d5dbd3987f725eb2d30b95b52b4f0eceb9748c17952',
    'macOS/Tests/CaptureServerTests/BelugaRustAvailabilityRetryTests.swift' => '15f5e23682ba1522813cb5e424813a9248b0b775fa026f86caf743328e8b4802',
    'macOS/Tests/CaptureServerTests/BelugaRustBatchAPolicyFacadeTests.swift' => 'c91aff6b8bb3c3c4aff3028f4db9bb113851502b23278ad6701a32086a0db83e',
    'macOS/Tests/CaptureServerTests/InertBatchAAudioRoutingFixture.swift' => 'd92fd86f92b64eae9a3093654fbe40df56e4fc1f1393b84671710a839e189435',
    'macOS/Tests/CaptureServerTests/WorldwideAvailabilityRetryCoordinatorTests.swift' => '6ff33071df215369dfcf13e918bd4d8e9614f14b2d9cf273e83e9f058e2197bf',
    'macOS/Tests/CaptureServerTests/WorldwideHostLifecycleTests.swift' => 'a115621eba5bb8366a17948e23b8d6743a259bc235251e40778e079fd02a9e26',
    'macOS/Tests/CaptureServerTests/WorldwideMacHostedCallObservationPolicyTests.swift' => '748cf680db492738702723f7f583de068e9a3e366bf95a29a5187cda677b78f0',
    'macOS/Tests/CaptureServerTests/WorldwideScreenServiceBatchAFaultTests.swift' => 'f5966786f3a5c4e9b65857991973f026e567c82eb5bc2d1810c124ce770d5c4e',
    'macOS/Tests/CaptureServerTests/WorldwideScreenServiceBatchASuccessorTests.swift' => '9017cc304acdbe53dc90a58ff053f4fa04ce5bcb9704faeb2e7c1965ef41fbed',
    'macOS/Tests/CaptureServerTests/WorldwideSystemAudioRecoveryTests.swift' => '7ecb3d6a348559d3e5cfcb25abf7d3ca941ede127ecd7b7e1e284879907b08ee',
  }.freeze

  # Exact reviewed native test declaration and discovery enrollment.
  BATCH_A_NATIVE_FILES = {
    'CaptureServerTests.BelugaRustAvailabilityRetryTests' => 'macOS/Tests/CaptureServerTests/BelugaRustAvailabilityRetryTests.swift',
    'CaptureServerTests.WorldwideAvailabilityRetryCoordinatorTests' => 'macOS/Tests/CaptureServerTests/WorldwideAvailabilityRetryCoordinatorTests.swift',
    'CaptureServerTests.BelugaRustBatchAPolicyFacadeTests' => 'macOS/Tests/CaptureServerTests/BelugaRustBatchAPolicyFacadeTests.swift',
    'CaptureServerTests.WorldwideSystemAudioRecoveryTests' => 'macOS/Tests/CaptureServerTests/WorldwideSystemAudioRecoveryTests.swift',
    'CaptureServerTests.WorldwideMacHostedCallObservationPolicyTests' => 'macOS/Tests/CaptureServerTests/WorldwideMacHostedCallObservationPolicyTests.swift',
    'CaptureServerTests.WorldwideScreenServiceBatchAFaultTests' => 'macOS/Tests/CaptureServerTests/WorldwideScreenServiceBatchAFaultTests.swift',
    'CaptureServerTests.WorldwideScreenServiceBatchASuccessorTests' => 'macOS/Tests/CaptureServerTests/WorldwideScreenServiceBatchASuccessorTests.swift',
  }.freeze
  BATCH_A_NATIVE_PINNED = {
    'CaptureServerTests.BelugaRustAvailabilityRetryTests' => %w[
      CaptureServerTests.BelugaRustAvailabilityRetryTests/testActualCABIAndAllFourteenLegalTransitionsMatchOriginal
      CaptureServerTests.BelugaRustAvailabilityRetryTests/testIndependentOriginalTracesPreserveDelayBooleanEqualityAndCopies
      CaptureServerTests.BelugaRustAvailabilityRetryTests/testEveryMalformedCopiedOutputRetainsRawStateAndFaultsWithoutRemint
      CaptureServerTests.BelugaRustAvailabilityRetryTests/testBoundaryRejectsAllUnknownRawFieldsAndImpossibleValidatedStates
      CaptureServerTests.BelugaRustAvailabilityRetryTests/testFailureUsesActualPriorDelayAndResetsValidatedOnlyAfterCommit
      CaptureServerTests.BelugaRustAvailabilityRetryTests/testCopyFaultCustodyDoesNotResetOrFaultAnIndependentOriginal
    ],
    'CaptureServerTests.WorldwideAvailabilityRetryCoordinatorTests' => %w[
      CaptureServerTests.WorldwideAvailabilityRetryCoordinatorTests/testAvailabilityUpgradeThenServerErrorBackoffUsesOneActualFailureProposal
      CaptureServerTests.WorldwideAvailabilityRetryCoordinatorTests/testAvailabilityWaitingAndReadyResetOnlyAfterNativeHandling
      CaptureServerTests.WorldwideAvailabilityRetryCoordinatorTests/testMalformedValidStateProposalClosesExactClientBeforeDistinctTerminalError
      CaptureServerTests.WorldwideAvailabilityRetryCoordinatorTests/testMalformedFailureProposalClosesExactClientThenStopsWithoutSleeping
      CaptureServerTests.WorldwideAvailabilityRetryCoordinatorTests/testCancellationOrOwnerReplacementDuringExactCloseCannotStopSuccessor
      CaptureServerTests.WorldwideAvailabilityRetryCoordinatorTests/testRetrySleepFailureDoesNotConsumeSecondPolicyProposalForSameFailure
      CaptureServerTests.WorldwideAvailabilityRetryCoordinatorTests/testDuplicateReadyRefusesBeforeResetAndRetriesOnlyAfterExactClose
    ],
    'CaptureServerTests.BelugaRustBatchAPolicyFacadeTests' => %w[
      CaptureServerTests.BelugaRustBatchAPolicyFacadeTests/testRetryEveryInitialOutputFieldFaultIsStickyAndNonAuthorizing
      CaptureServerTests.BelugaRustBatchAPolicyFacadeTests/testRetryEveryTransitionOutputFieldFaultRetainsExactBeforeSnapshot
      CaptureServerTests.BelugaRustBatchAPolicyFacadeTests/testRetryCopiesKeepIndependentCountersAndFaultLifetimes
      CaptureServerTests.BelugaRustBatchAPolicyFacadeTests/testRetryActualCClampsArbitrarySignedNativeLimitsAndKeepsLiteralTrace
      CaptureServerTests.BelugaRustBatchAPolicyFacadeTests/testSystemAudioEveryOutputFieldRefusesAcrossAll64TypedInputs
      CaptureServerTests.BelugaRustBatchAPolicyFacadeTests/testHostedEveryOutputFieldRefusesAcrossAdmissionAndEvidenceFunctions
      CaptureServerTests.BelugaRustBatchAPolicyFacadeTests/testHostedUUIDTupleAndMaximumNumericValuesProjectLosslessly
      CaptureServerTests.BelugaRustBatchAPolicyFacadeTests/testHostedValidPoisonAndAbsentGenerationStayLegitimateRefusals
    ],
    'CaptureServerTests.WorldwideSystemAudioRecoveryTests' => %w[
      CaptureServerTests.WorldwideSystemAudioRecoveryTests/testStartPolicyResumesOnlyAnExactPausedPeerGeneration
      CaptureServerTests.WorldwideSystemAudioRecoveryTests/testPauseResumeRotatesTransportAndEvidenceTokensWithoutCopyingProof
      CaptureServerTests.WorldwideSystemAudioRecoveryTests/testStaleAudioAuthorizationCannotForwardAfterRollover
      CaptureServerTests.WorldwideSystemAudioRecoveryTests/testEvidenceTokenRequiresChallengeAndRotatesForEpochMismatch
      CaptureServerTests.WorldwideSystemAudioRecoveryTests/testInactiveEvidenceIsOneShotAndEpochBound
      CaptureServerTests.WorldwideSystemAudioRecoveryTests/testServiceRecoveryRetainsSourceAndFullStopDestroysIt
    ],
    'CaptureServerTests.WorldwideMacHostedCallObservationPolicyTests' => %w[
      CaptureServerTests.WorldwideMacHostedCallObservationPolicyTests/testWireEvidenceStateDistinguishesProspectiveArmFromPoison
      CaptureServerTests.WorldwideMacHostedCallObservationPolicyTests/testRejectsReorderedObservationEvenWhenChallengeMatches
      CaptureServerTests.WorldwideMacHostedCallObservationPolicyTests/testRejectsObservationFromPriorChallenge
      CaptureServerTests.WorldwideMacHostedCallObservationPolicyTests/testRejectsPriorSequenceWhenNonceIsReused
      CaptureServerTests.WorldwideMacHostedCallObservationPolicyTests/testRejectsWrongCallEpochEvenWhenSequenceAndNonceMatch
      CaptureServerTests.WorldwideMacHostedCallObservationPolicyTests/testRejectsMissingOrInvalidChallenge
      CaptureServerTests.WorldwideMacHostedCallObservationPolicyTests/testPeerGenerationFenceRejectsStaleSourceOrChallenge
    ],
    'CaptureServerTests.WorldwideScreenServiceBatchAFaultTests' => %w[
      CaptureServerTests.WorldwideScreenServiceBatchAFaultTests/testStickyFaultRefusesAdmissionWhenNeedsRedriveIsFalse
      CaptureServerTests.WorldwideScreenServiceBatchAFaultTests/testSuccessResetFaultRevokesCommittedNativeProofBeforeReturningFalse
      CaptureServerTests.WorldwideScreenServiceBatchAFaultTests/testStopResetFaultContinuesRealTeardown
      CaptureServerTests.WorldwideScreenServiceBatchAFaultTests/testSecondaryProfileFaultHasNoRouteOperations
      CaptureServerTests.WorldwideScreenServiceBatchAFaultTests/testForeignFailureHistorySurvivesStickyFault
      CaptureServerTests.WorldwideScreenServiceBatchAFaultTests/testHostedNoneAndEvidenceFaultConsumeWatermark
      CaptureServerTests.WorldwideScreenServiceBatchAFaultTests/testHostedObservationFaultAndMissingPeerDoNotConsumeWatermark
      CaptureServerTests.WorldwideScreenServiceBatchAFaultTests/testHostedHealthyProjectionAndOldChallengeKeepExactOrder
    ],
    'CaptureServerTests.WorldwideScreenServiceBatchASuccessorTests' => %w[
      CaptureServerTests.WorldwideScreenServiceBatchASuccessorTests/testStartupJoinsExactInitialObserverBeforeTransportStaging
      CaptureServerTests.WorldwideScreenServiceBatchASuccessorTests/testSuccessResetTypedCatchPreservesForeignHistoryAfterActualInputCallbacksJoin
    ],
  }.transform_values(&:freeze).freeze

  MAC_CLASSES = %w[
    CaptureCoreTests.CoreAudioProcessTapAggregateConfigurationTests
    CaptureCoreTests.CoreAudioProcessTapStartupDiagnosticsTests
    CaptureCoreTests.BlackHoleDefaultInputLeaseTests
    CaptureCoreTests.WorldwideSafeOutputInvariantTests
    CaptureCoreTests.BlackHoleRouteHealthTests
    CaptureServerTests.WorldwideIPhoneMicrophoneForwardingDriverTests
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests
    CaptureServerTests.WorldwideIPhoneMicrophoneForwardingWebRTCIntegrationTests
    CaptureServerTests.BlackHoleMicrophoneOutputTests
    CaptureServerTests.WorldwideVirtualMicrophoneDriverIdleTests
    CaptureServerTests.WorldwideSharedClockEpochRecoveryTests
    CaptureServerTests.WorldwidePairedPhoneCatalogTests
    CaptureServerTests.WorldwideHostCoordinatorTests
    CaptureServerTests.WorldwidePreparedMediaMenuIntegrationTests
    CaptureServerTests.WorldwideHostPairingCommitPersistenceTests
    CaptureServerTests.WorldwidePairingCommitDecodeFaultTests
    CaptureServerTests.WorldwideHostLifecycleTests
    CaptureServerTests.WorldwidePairingCatalogBootstrapTests
    CaptureServerTests.BelugaRustPairingCatalogCheckpointTests
    CaptureServerTests.BelugaPhoneCatalogMenuTests
    CaptureServerTests.WorldwidePairingStoreTests
    CaptureServerTests.WorldwideHostProcessLockTests
    CaptureServerTests.BelugaMenuBarTests
    CaptureServerTests.BelugaMediaHandoffMenuTests
    CaptureServerTests.BelugaRustHandoffPolicyTests
    CaptureServerTests.BelugaRustHostLifecycleTests
    CaptureServerTests.BelugaUpdateCandidateMetadataTests
    CaptureServerTests.BelugaUpdateInstalledArtifactTests
    CaptureServerTests.BelugaUpdateSparkleSessionTests
    CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests
    CaptureServerTests.MacSupportedNowPlayingRuntimeTests
    CaptureServerTests.BelugaRustAvailabilityRetryTests
    CaptureServerTests.WorldwideAvailabilityRetryCoordinatorTests
    CaptureServerTests.BelugaRustBatchAPolicyFacadeTests
    CaptureServerTests.WorldwideSystemAudioRecoveryTests
    CaptureServerTests.WorldwideMacHostedCallObservationPolicyTests
    CaptureServerTests.WorldwideScreenServiceBatchAFaultTests
    CaptureServerTests.WorldwideScreenServiceBatchASuccessorTests
  ].freeze
  MAC_PINNED = %w[
    CaptureCoreTests.CoreAudioProcessTapAggregateConfigurationTests/testEveryFreshAggregateStartsWithoutWaitingForTappedPlayback
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testDeviceBeforeConnectionSelectsAtHealthyBoundaryWithoutTrack
    CaptureServerTests.WorldwideIPhoneMicrophoneForwardingDriverTests/testLANCoexistencePolicySuppressesEveryHealthyInput
    CaptureServerTests.WorldwideIPhoneMicrophoneForwardingWebRTCIntegrationTests/testLateRealInboundRTPRevivesExhaustedForwardingOnSamePeerAndTrack
    CaptureServerTests.WorldwideSharedClockEpochRecoveryTests/testPublicIdleCannotOverrideAnActiveOrChangedDriverEpoch
    CaptureServerTests.WorldwideSharedClockEpochRecoveryTests/testDriverDiagnosticReadFailureKeepsPublicIdleUnproved
    CaptureServerTests.WorldwideSharedClockEpochRecoveryTests/testSystemWidePropertyFailureDoesNotFallBackToProcessLocalIdle
    CaptureServerTests.WorldwideVirtualMicrophoneDriverIdleTests/testCompleteV2IdleOverflowInventoryProvesMirroredIdle
    CaptureServerTests.WorldwideVirtualMicrophoneDriverIdleTests/testActiveV2OverflowLeaseCannotProveIdle
    CaptureServerTests.WorldwideVirtualMicrophoneDriverIdleTests/testV2DecoderRejectsMalformedDuplicateStaleAndIncompleteInventories
    CaptureServerTests.WorldwideVirtualMicrophoneDriverIdleTests/testV2MirroredProofRejectsRegistryChurnAndMixedFormats
    CaptureServerTests.WorldwideVirtualMicrophoneDriverIdleTests/testReaderFallsBackToFrozenV1OnlyWhenV2PropertyIsAbsent
    CaptureServerTests.WorldwideVirtualMicrophoneDriverIdleTests/testReaderRejectsUnavailableOrMalformedV2WithoutV1Fallback
    CaptureServerTests.WorldwideVirtualMicrophoneDriverIdleTests/testV2PropertyBoundaryRejectsOversizedAndStaleObservations
    CaptureServerTests.WorldwideVirtualMicrophoneDriverIdleTests/testV2FailureCountersDoNotInvalidateTruthfulIdleInventory
    CaptureServerTests.WorldwidePairedPhoneCatalogTests/testMigrationRetainsBothReconnectCountersAndIgnoresLaterLegacyChanges
    CaptureServerTests.WorldwidePairedPhoneCatalogTests/testEmptyCatalogIsAuthoritativeAndNeverImportsFutureLegacyRecord
    CaptureServerTests.WorldwidePairedPhoneCatalogTests/testUpdateCannotResurrectForgottenPhoneEvenWithFreshToken
    CaptureServerTests.WorldwidePairedPhoneCatalogTests/testCounterAdvanceRetainsSiblingAndSelectionButRegressionFails
    CaptureServerTests.WorldwideHostCoordinatorTests/testLegacyReadersAndWritersRefuseAfterMigrationIncludingEmptyTombstone
    CaptureServerTests.WorldwideHostCoordinatorTests/testSelectionWaitsForExactOldCloseAndRechecksOwnerBeforeMutation
    CaptureServerTests.WorldwideHostCoordinatorTests/testActivePeerAndUnvalidatedSocketCannotAuthorizeCatalogActions
    CaptureServerTests.WorldwideHostCoordinatorTests/testStopDuringRecoverySendCannotPersistLateCompletionSent
    CaptureServerTests.WorldwideHostPairingCommitPersistenceTests/testAcknowledgementFirstSaveFailureBlocksCompletionAndColdRetryUsesStoredProposal
    CaptureServerTests.WorldwideHostPairingCommitPersistenceTests/testAcknowledgementFirstWriteThenThrowKeepsReceivedWithoutCacheForColdRecovery
    CaptureServerTests.WorldwideHostPairingCommitPersistenceTests/testAcknowledgementSecondSaveFailureKeepsReceivedWithoutCacheForColdRecovery
    CaptureServerTests.WorldwideHostPairingCommitPersistenceTests/testAcknowledgementSecondWriteThenThrowKeepsExactCachedCompletionWithoutSending
    CaptureServerTests.WorldwideHostPairingCommitPersistenceTests/testCompletionSendRequiresBothDurableAcknowledgementCutsAndNeverActivatesHost
    CaptureServerTests.WorldwidePairingCommitDecodeFaultTests/testLegacyRecordDecodeBridgeRefusalPreservesExactBytesWithoutMigrationOrDeletion
    CaptureServerTests.WorldwidePairingCommitDecodeFaultTests/testCatalogLoadAndCheckpointReadbackBridgeRefusalNeverResetNamespaceOrWrite
    CaptureServerTests.WorldwidePairingCommitDecodeFaultTests/testCandidateRecordRoundtripBridgeRefusalPreservesOriginalCatalogAndIdentityPriority
    CaptureServerTests.WorldwideHostLifecycleTests/testMediaDepartureReturnsPairedHostToAvailability
    CaptureServerTests.WorldwideHostLifecycleTests/testInvitationMustCommitBeforeAvailabilityCanAcceptViewer
    CaptureServerTests.WorldwideHostLifecycleTests/testBootstrapLossAfterDurableRecordMovesToAvailabilityRecovery
    CaptureServerTests.WorldwideHostLifecycleTests/testStaleDepartureCannotClearNewExchange
    CaptureServerTests.WorldwidePairingCatalogBootstrapTests/testStopBeforeHeldCompletionReturnsCannotPersistCompletionSent
    CaptureServerTests.BelugaPhoneCatalogMenuTests/testPresentedConfirmationTicketIsStaleAfterCatalogRevisionChanges
    CaptureServerTests.BelugaPhoneCatalogMenuTests/testShutdownDropsLateSuccessAndFailureFromNonCooperativeCommand
    CaptureServerTests.WorldwidePairingStoreTests/testCorruptIdentityFailsClosedInsteadOfRotatingKeys
    CaptureServerTests.WorldwidePairingStoreTests/testRelaunchRecoversCompletionButBarsMediaUntilViewerActivationAck
    CaptureServerTests.WorldwideHostProcessLockTests/testReleasedLockCanBeReacquired
    CaptureServerTests.WorldwideHostProcessLockTests/testSecondWorldwideHostCannotAcquireSamePerUserLock
    CaptureServerTests.BelugaMenuBarTests/testMenuStartsRuntimeAtMostOnce
    CaptureServerTests.BelugaMenuBarTests/testExpiredInvitationAndShutdownClearSecretPresentation
    CaptureServerTests.BelugaMediaHandoffMenuTests/testControlStaysVisibleAcrossDisconnectReconnectAndUnavailablePresentation
    CaptureServerTests.BelugaMediaHandoffMenuTests/testClickSendsExactTargetOnceAndDoesNotClaimTransferCompletion
    CaptureServerTests.BelugaMediaHandoffMenuTests/testSessionChangeBeforeTaskRunsPreventsDispatch
    CaptureServerTests.BelugaMediaHandoffMenuTests/testLateOldResultCannotPublishIntoReplacementSession
    CaptureServerTests.BelugaMediaHandoffMenuTests/testShutdownClearsTargetAndIgnoresLateCompletionAndCallbacks
    CaptureServerTests.BelugaMediaHandoffMenuTests/testPreparedTargetAndInFlightRequestSurviveAvailabilityPresentationChanges
    CaptureServerTests.WorldwidePreparedMediaMenuIntegrationTests/testTargetIsAbsentUntilStartupAndAuthenticatedResponseBothReturn
    CaptureServerTests.WorldwidePreparedMediaMenuIntegrationTests/testPeerLeftThenReadyBRetainsPreparedAAndActualMenuDispatch
    CaptureServerTests.WorldwidePreparedMediaMenuIntegrationTests/testTransportRetryAndReadyBRetainAWithoutStartingOrStoppingMedia
    CaptureServerTests.WorldwidePreparedMediaMenuIntegrationTests/testInFlightARequestSurvivesAvailabilityOnlyReadyB
    CaptureServerTests.WorldwidePreparedMediaMenuIntegrationTests/testActualReconnectBRevokesAAdmissionBeforeAwaitedNativeStop
    CaptureServerTests.WorldwidePreparedMediaMenuIntegrationTests/testSameExchangeReplacementRequiresFreshOwnerNonce
    CaptureServerTests.WorldwidePreparedMediaMenuIntegrationTests/testActualReplacementRejectsLateInFlightAResultAndMenuPublication
    CaptureServerTests.WorldwidePreparedMediaMenuIntegrationTests/testLateOldCompletionDoesNotRetirePreparedReplacement
    CaptureServerTests.WorldwidePreparedMediaMenuIntegrationTests/testAuthenticatedReplayDoesNotRevokePreparedAOrAttemptNewMedia
    CaptureServerTests.WorldwidePreparedMediaMenuIntegrationTests/testGenuineForeignPairRequestDoesNotRevokePreparedAOrAttemptNewMedia
    CaptureServerTests.WorldwidePreparedMediaMenuIntegrationTests/testHigherCurrentPairRequestWithForgedSignatureCannotRevokeOrConstructMedia
    CaptureServerTests.WorldwidePreparedMediaMenuIntegrationTests/testFailedStartupNeverMintsTargetOrSendsReconnectResponse
    CaptureServerTests.WorldwidePreparedMediaMenuIntegrationTests/testFailedResponseNeverMintsPreparedTarget
    CaptureServerTests.WorldwidePreparedMediaMenuIntegrationTests/testUnconfirmedNativeStopRetainsServiceButRevokesMenuAndCatalogAuthority
    CaptureServerTests.WorldwidePreparedMediaMenuIntegrationTests/testOwnerLossDuringResponseSuspensionNeverGrantsPreparedCapability
    CaptureServerTests.WorldwidePreparedMediaMenuIntegrationTests/testShutdownRevokesBeforeSuspendedNativeStopAndRejectsLateMove
    CaptureServerTests.WorldwidePreparedMediaMenuIntegrationTests/testMicrophoneSnapshotForwarderUsesExactRetainedServiceAcrossAvailabilityLoss
    CaptureServerTests.WorldwidePreparedMediaMenuIntegrationTests/testReconnectCounterWriteFailureBlocksEffectsAndRetryUsesDurablePredecessor
    CaptureServerTests.WorldwidePreparedMediaMenuIntegrationTests/testReconnectCounterWriteThenThrowRetainsActualDurableBurnWithoutEffects
    CaptureServerTests.BelugaRustHandoffPolicyTests/testEveryKnownInputMatchesIndependentAdmissionAndReasonSpecification
    CaptureServerTests.BelugaRustHandoffPolicyTests/testUnknownAbiCannotEnableOrHideStartedControl
    CaptureServerTests.BelugaRustHandoffPolicyTests/testEveryUnknownFlagBitFailsClosedEvenWhenAdmissionFlagsAreReady
    CaptureServerTests.BelugaRustHandoffPolicyTests/testAbiFailureTakesPrecedenceOverUnknownFlagsAndRuntimeReadiness
    CaptureServerTests.BelugaRustHandoffPolicyTests/testDisabledReasonsAlwaysHaveAnExplanationButReadyDoesNot
    CaptureServerTests.BelugaRustHandoffPolicyTests/testMalformedForeignOutputFailsClosedWithoutHidingStartedControl
    CaptureServerTests.BelugaRustHostLifecycleTests/testEveryReachableSmallStateAndEventMatchesIndependentReference
    CaptureServerTests.BelugaRustHostLifecycleTests/testSeededLifecycleChurnHasTraceParityWithoutCollapsingAvailabilityAndMedia
    CaptureServerTests.BelugaRustHostLifecycleTests/testDelayedDepartureCannotClearReplacementOrEndAnotherMediaOwner
    CaptureServerTests.BelugaRustHostLifecycleTests/testExchangeAdmissionCountsUtf8BytesAndPreservesOpaqueStringContents
    CaptureServerTests.BelugaRustHostLifecycleTests/testCanonicalEquivalentStringsRetainExistingSwiftEqualityButNotRewriteStoredBytes
    CaptureServerTests.BelugaRustHostLifecycleTests/testStopIsTerminalIdempotentAndClearsBothIndependentOwners
    CaptureServerTests.BelugaRustHostLifecycleTests/testValueCopiesAndEqualityPreserveIndependentLifecycleAuthority
    CaptureServerTests.BelugaRustHostLifecycleTests/testEqualityDependsOnPublicStateNotPrivateTokenAllocationHistory
    CaptureServerTests.BelugaUpdateCandidateMetadataTests/testSignedSingleViewerSchemaIsRejectedEvenWithAHigherOrMaximumBuild
    CaptureServerTests.BelugaUpdateInstalledArtifactTests/testCatalogVersionMustBePresentExactIntegerNotInferredFromOwnershipOrHighBuild
    CaptureServerTests.BelugaUpdateInstalledArtifactTests/testCatalogMarkerIsCoveredByFullTreeAndTamperingCannotVerifyCandidate
    CaptureServerTests.BelugaUpdateSparkleSessionTests/testSignedHighBuildSingleViewerCandidateIsRejectedBeforeBindingOrInstall
    CaptureServerTests.BelugaRustPairingCatalogCheckpointTests/testRevokedCheckpointNeverCallsOwnerOrCatalog
    CaptureServerTests.BelugaRustPairingCatalogCheckpointTests/testInvalidProcessOwnerRefusesAllCatalogAccess
    CaptureServerTests.BelugaRustPairingCatalogCheckpointTests/testCheckpointAddsExactlyOnceEvenForDifferentValidPhone
    CaptureServerTests.BelugaRustPairingCatalogCheckpointTests/testDeviceUUIDMismatchRefusesAllCatalogAccess
    CaptureServerTests.BelugaRustPairingCatalogCheckpointTests/testPairUUIDMismatchRefusesAllCatalogAccess
    CaptureServerTests.BelugaRustPairingCatalogCheckpointTests/testCommitUUIDMismatchRefusesAllCatalogAccess
    CaptureServerTests.BelugaRustPairingCatalogCheckpointTests/testThrowingAddAndUpdatePreserveActualCheckpointState
    CaptureServerTests.BelugaRustPairingCatalogCheckpointTests/testRevocationRetainsExactPairForInterruptedReadback
    CaptureServerTests.BelugaRustPairingCatalogCheckpointTests/testEqualRevisionDifferentSnapshotCannotPassReadback
    CaptureServerTests.BelugaRustPairingCatalogCheckpointTests/testMalformedAllowedCandidateCannotAuthorizeNativeWrite
    CaptureServerTests.BelugaRustPairingCatalogCheckpointTests/testReadbackAfterRevokeAndOwnerLossStillReturnsExactPair
    CaptureServerTests.BelugaRustPairingCatalogCheckpointTests/testReadbackLoadErrorPrecedesSnapshotPolicyOrBridgeFault
    CaptureServerTests.BelugaRustPairingCatalogCheckpointTests/testWriteThenThrowDoesNotInventRollbackOrBindingSuccess
    CaptureServerTests.BelugaRustPairingCatalogCheckpointTests/testNativeAliasesShareRevocationWithoutAffectingAnotherAttempt
    CaptureServerTests.BelugaRustPairingCatalogCheckpointTests/testCatalogGenerationRevisionRecordAndLegacyReceiptAllFenceReadback
    CaptureServerTests.BelugaRustPairingCatalogCheckpointTests/testMalformedRevokeIsStickyWithoutErasingKnownSnapshotOrBinding
    CaptureServerTests.BelugaRustPairingCatalogCheckpointTests/testMalformedInitialCannotInvokeOwnerOrStore
    CaptureServerTests.BelugaRustPairingCatalogCheckpointTests/testActualCopiedBoundaryAndLayoutsPreserveAllValidCases
    CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testActualCopiedABIAndAll48LiteralOriginalDecisions
    CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testAll48CurrentNativeHistoriesMatchIndependentOriginalAndRetainedHold
    CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testAll48StaleNativeHistoriesCannotCallCoreOrRetireCurrentAuthority
    CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testEveryBoundedCopiedOutputCorruptionRetriesRevokesAndCanRecover
    CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testUnselectedChildRetryRevokesBothCatalogCommandsAndActualHandoff
    CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testMusicHoldSurvivesAbsentRetryAndBothPausedRecovery
    CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testFirstRetryCallbackCannotBeOverwrittenByDuplicateSnapshot
    CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testStopThenFreshPublicationCannotBeClearedByOldRetryJoin
    CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testStartingNewFetchDoesNotRevokeQueuedOrdinaryOrActualHandoff
    CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testInvalidCurrentOutputRetiresActualHandoffBeforeNativePauseEffect
    CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testWrappedSnapshotsPreserveExactNativeValuesCapabilitiesAndHandoffReference
    CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testSameNativeClientAndItemRetainTokensAcrossRateChanges
    CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testReplacementNativeClientOrItemRetiresQueuedOrdinaryAuthority
    CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testNoMediaClearsHoldBeforePausedFallbackAndRetiresQueuedCommand
    CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testOriginalRateGreaterThanZeroComparisonIsNotNewNumericValidation
    CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testNativeProjectionRequiresExactSlotsAndValidHold
    CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testActualRawInvalidInputsReturnInvalidAndNativeDecoderRejectsThem
    CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testAdditionalBrowserCannotHandoffWhenMusicIsSelected
    CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testDistinctInvalidDiagnosticIsThrottledAndContainsNoNativeContent
    CaptureServerTests.BelugaRustSupportedPlayerArbitrationTests/testExternalRevocationAndStopRejectBothHeldOrdinaryAndHandoff
    CaptureServerTests.MacSupportedNowPlayingRuntimeTests/testSimultaneouslyDiscoveredPlayersPublishStablePrimaryAndIndependentCatalog
    CaptureServerTests.MacSupportedNowPlayingRuntimeTests/testSameInnerIdentityWithReplacementTokenRetiresPriorPublication
    CaptureServerTests.MacSupportedNowPlayingRuntimeTests/testPlayingYouTubeWinsPausedMusicAndPreservesExactMetadataAndCapabilities
    CaptureServerTests.MacSupportedNowPlayingRuntimeTests/testNewlyPlayingMusicDoesNotStealPrimaryUntilBrowserPauses
    CaptureServerTests.MacSupportedNowPlayingRuntimeTests/testSelectedSourceRetryRetiresCommandAuthorityWithoutSwitchingPlayer
    CaptureServerTests.MacSupportedNowPlayingRuntimeTests/testCommandGoesOnlyToSelectedSourceAndExternalRevocationClosesPendingAction
    CaptureServerTests.MacSupportedNowPlayingRuntimeTests/testSourceReplacementRejectsOldSnapshotAndAlreadyQueuedCommand
    CaptureServerTests.MacSupportedNowPlayingRuntimeTests/testQueuedCommandCannotRegainAuthorityAfterSourceReturnsToSameIdentity
    CaptureServerTests.MacSupportedNowPlayingRuntimeTests/testQueuedCommandCannotRegainAuthorityAfterItemReturnsToSameIdentity
    CaptureServerTests.MacSupportedNowPlayingRuntimeTests/testStopRevokesPendingCommandEvenAfterFreshFetchRestoresSameIdentity
    CaptureServerTests.MacSupportedNowPlayingRuntimeTests/testOutOfOrderFetchCannotReplaceNewerSelection
    CaptureServerTests.MacSupportedNowPlayingRuntimeTests/testDuplicateCallbacksCannotOverwriteFirstSourceResultOrCompleteTwice
    CaptureServerTests.MacSupportedNowPlayingRuntimeTests/testFetchCompletionAfterStopCannotReviveSelection
    CaptureServerTests.MacSupportedNowPlayingRuntimeTests/testMissingPlayersClearSelectionAndDiagnosticsContainNoMediaContent
    CaptureServerTests.BelugaRustAvailabilityRetryTests/testActualCABIAndAllFourteenLegalTransitionsMatchOriginal
    CaptureServerTests.BelugaRustAvailabilityRetryTests/testIndependentOriginalTracesPreserveDelayBooleanEqualityAndCopies
    CaptureServerTests.BelugaRustAvailabilityRetryTests/testEveryMalformedCopiedOutputRetainsRawStateAndFaultsWithoutRemint
    CaptureServerTests.BelugaRustAvailabilityRetryTests/testBoundaryRejectsAllUnknownRawFieldsAndImpossibleValidatedStates
    CaptureServerTests.BelugaRustAvailabilityRetryTests/testFailureUsesActualPriorDelayAndResetsValidatedOnlyAfterCommit
    CaptureServerTests.BelugaRustAvailabilityRetryTests/testCopyFaultCustodyDoesNotResetOrFaultAnIndependentOriginal
    CaptureServerTests.WorldwideAvailabilityRetryCoordinatorTests/testAvailabilityUpgradeThenServerErrorBackoffUsesOneActualFailureProposal
    CaptureServerTests.WorldwideAvailabilityRetryCoordinatorTests/testAvailabilityWaitingAndReadyResetOnlyAfterNativeHandling
    CaptureServerTests.WorldwideAvailabilityRetryCoordinatorTests/testMalformedValidStateProposalClosesExactClientBeforeDistinctTerminalError
    CaptureServerTests.WorldwideAvailabilityRetryCoordinatorTests/testMalformedFailureProposalClosesExactClientThenStopsWithoutSleeping
    CaptureServerTests.WorldwideAvailabilityRetryCoordinatorTests/testCancellationOrOwnerReplacementDuringExactCloseCannotStopSuccessor
    CaptureServerTests.WorldwideAvailabilityRetryCoordinatorTests/testRetrySleepFailureDoesNotConsumeSecondPolicyProposalForSameFailure
    CaptureServerTests.BelugaRustBatchAPolicyFacadeTests/testRetryEveryInitialOutputFieldFaultIsStickyAndNonAuthorizing
    CaptureServerTests.BelugaRustBatchAPolicyFacadeTests/testRetryEveryTransitionOutputFieldFaultRetainsExactBeforeSnapshot
    CaptureServerTests.BelugaRustBatchAPolicyFacadeTests/testRetryCopiesKeepIndependentCountersAndFaultLifetimes
    CaptureServerTests.BelugaRustBatchAPolicyFacadeTests/testRetryActualCClampsArbitrarySignedNativeLimitsAndKeepsLiteralTrace
    CaptureServerTests.BelugaRustBatchAPolicyFacadeTests/testSystemAudioEveryOutputFieldRefusesAcrossAll64TypedInputs
    CaptureServerTests.BelugaRustBatchAPolicyFacadeTests/testHostedEveryOutputFieldRefusesAcrossAdmissionAndEvidenceFunctions
    CaptureServerTests.BelugaRustBatchAPolicyFacadeTests/testHostedUUIDTupleAndMaximumNumericValuesProjectLosslessly
    CaptureServerTests.BelugaRustBatchAPolicyFacadeTests/testHostedValidPoisonAndAbsentGenerationStayLegitimateRefusals
    CaptureServerTests.WorldwideSystemAudioRecoveryTests/testStartPolicyResumesOnlyAnExactPausedPeerGeneration
    CaptureServerTests.WorldwideSystemAudioRecoveryTests/testPauseResumeRotatesTransportAndEvidenceTokensWithoutCopyingProof
    CaptureServerTests.WorldwideSystemAudioRecoveryTests/testStaleAudioAuthorizationCannotForwardAfterRollover
    CaptureServerTests.WorldwideSystemAudioRecoveryTests/testEvidenceTokenRequiresChallengeAndRotatesForEpochMismatch
    CaptureServerTests.WorldwideSystemAudioRecoveryTests/testInactiveEvidenceIsOneShotAndEpochBound
    CaptureServerTests.WorldwideSystemAudioRecoveryTests/testServiceRecoveryRetainsSourceAndFullStopDestroysIt
    CaptureServerTests.WorldwideMacHostedCallObservationPolicyTests/testWireEvidenceStateDistinguishesProspectiveArmFromPoison
    CaptureServerTests.WorldwideMacHostedCallObservationPolicyTests/testRejectsReorderedObservationEvenWhenChallengeMatches
    CaptureServerTests.WorldwideMacHostedCallObservationPolicyTests/testRejectsObservationFromPriorChallenge
    CaptureServerTests.WorldwideMacHostedCallObservationPolicyTests/testRejectsPriorSequenceWhenNonceIsReused
    CaptureServerTests.WorldwideMacHostedCallObservationPolicyTests/testRejectsWrongCallEpochEvenWhenSequenceAndNonceMatch
    CaptureServerTests.WorldwideMacHostedCallObservationPolicyTests/testRejectsMissingOrInvalidChallenge
    CaptureServerTests.WorldwideMacHostedCallObservationPolicyTests/testPeerGenerationFenceRejectsStaleSourceOrChallenge
    CaptureServerTests.WorldwideHostLifecycleTests/testSafeOutputRetryPolicyBacksOffThenProbesAfterCappedCooldown
    CaptureServerTests.WorldwideHostLifecycleTests/testAvailabilityBackoffDoesNotResetForUpgradeFollowedByServerError
    CaptureServerTests.WorldwideHostLifecycleTests/testValidAvailabilityStateResetsBackoffAndIsReportedOncePerConnection
    CaptureServerTests.WorldwideScreenServiceBatchAFaultTests/testStickyFaultRefusesAdmissionWhenNeedsRedriveIsFalse
    CaptureServerTests.WorldwideScreenServiceBatchAFaultTests/testSuccessResetFaultRevokesCommittedNativeProofBeforeReturningFalse
    CaptureServerTests.WorldwideScreenServiceBatchAFaultTests/testStopResetFaultContinuesRealTeardown
    CaptureServerTests.WorldwideScreenServiceBatchAFaultTests/testSecondaryProfileFaultHasNoRouteOperations
    CaptureServerTests.WorldwideScreenServiceBatchAFaultTests/testForeignFailureHistorySurvivesStickyFault
    CaptureServerTests.WorldwideScreenServiceBatchAFaultTests/testHostedNoneAndEvidenceFaultConsumeWatermark
    CaptureServerTests.WorldwideScreenServiceBatchAFaultTests/testHostedObservationFaultAndMissingPeerDoNotConsumeWatermark
    CaptureServerTests.WorldwideScreenServiceBatchAFaultTests/testHostedHealthyProjectionAndOldChallengeKeepExactOrder
    CaptureServerTests.WorldwideScreenServiceBatchASuccessorTests/testStartupJoinsExactInitialObserverBeforeTransportStaging
    CaptureServerTests.WorldwideScreenServiceBatchASuccessorTests/testSuccessResetTypedCatchPreservesForeignHistoryAfterActualInputCallbacksJoin
    CaptureServerTests.WorldwideAvailabilityRetryCoordinatorTests/testDuplicateReadyRefusesBeforeResetAndRetriesOnlyAfterExactClose
  ].freeze
  RUST_PINNED = %w[
    ordinary_raw_microphone_effective_sharing_preserves_requested_and_observed_values
    ordinary_raw_microphone_profile_rejects_other_policies_and_all_tuple_or_owner_changes
    ordinary_microphone_sharing_profile_does_not_expand_other_targets
  ].freeze
  BELUGA_CORE_PINNED = %w[
    exhaustive_4096_flag_values_match_independent_specification
    stable_visibility_survives_missing_target_and_session_churn
    unknown_abi_versions_fail_closed_and_preserve_safe_visibility
    every_unknown_bit_fails_closed
    each_original_enabled_guard_is_required
    disabled_reason_priority_is_stable
    exported_scalar_abi_matches_safe_policy_and_layout
    exhaustive_reachable_state_event_graph_matches_reference
    availability_reconnect_does_not_replace_or_clear_old_media_owner
    original_utf8_bound_applies_only_to_availability_admission
    malformed_state_or_abi_fails_terminally_closed
    stop_is_terminal_and_repeated_stop_is_idempotent
    deterministic_long_churn_trace_matches_reference
    lifecycle_scalar_exports_and_layout_match_safe_core
    stale_media_end_preserves_current_media_owner
    exhaustive_transaction_state_event_graph_matches_reference
    host_busy_rejects_replacement_without_revocation
    host_completion_requires_exact_receipt_and_envelope
    cached_reply_is_idempotent_and_conflicting_reply_rejected
    host_revocation_occurs_on_finish_replacement_and_clear
    viewer_completion_and_expiry_require_exact_identity
    clear_and_expiry_report_unknown_once_without_pause_effect
    invalid_transaction_inputs_fail_closed
    transaction_scalar_exports_and_layout_match_core
    deterministic_transaction_churn_matches_reference
    independent_slots_preserve_other_owner
    rejected_new_sequence_burns_and_retires_before_late_validation
    matching_consumption_cannot_revive_after_late_failure
    wrong_identity_and_invalid_phone_observation_do_not_consume
    exact_freshness_sample_deadline_and_uncertainty_boundaries
    clear_preserves_counters_and_send_capacity_cannot_wrap
    source_description_numeric_crosscheck_matches_reference
    raw_float_bits_preserve_signed_zero_and_extreme_derived_deadline
    bounded_deterministic_original_reference_trace_matches_all_projections
    malformed_abi_state_and_unknown_flags_fail_closed_without_native_authority
    commit_header_and_current_primary_identity_are_independent
    received_primary_matches_the_incoming_not_the_retired_receipt
    actual_double_adjacent_boundaries_have_expected_decisions
    maximum_received_sequence_does_not_wrap_or_disable_independent_send
    tentative_scalar_layout_sizes_alignments_and_offsets_are_explicit
    nonfinite_events_preserve_order_but_nonfinite_owned_state_is_invalid
    unknown_operation_is_invalid_unchanged_without_retirement_or_success
    wire_authorization_and_exact_numeric_identity_guard_slots
    exported_offer_functions_match_safe_reducer
    copied_abi_layout_is_exact_and_pointer_free
    ready_stationary_paused_and_wrong_position_do_not_confirm
    slow_provider_requires_the_advancing_original_request_timeline
    advancing_exact_visible_playback_confirms_once_without_refreshing_proof
    blocked_provider_requests_play_but_never_claims_confirmation
    hidden_once_visible_and_every_terminal_failure_cannot_revive
    foreign_identity_returns_before_time_but_matching_replay_observes_time
    wrong_video_burns_matching_sequence_before_terminal_failure
    original_proof_age_never_renews_but_completion_uses_latest_sample
    interruption_or_seek_cannot_revive_previously_confirmed_authority
    clock_regression_and_nonfinite_clock_fail_without_rewriting_last_bits
    only_reserved_correlated_completion_moves_and_cannot_be_replayed
    committed_local_controls_past_deadline_never_reopen_authority
    pending_interruption_becomes_unknown_and_late_success_cannot_revive
    successful_native_pause_is_retained_even_when_phone_freshness_fails
    reply_timeout_precedes_offer_timeout_and_never_renews_deadline
    every_pending_failure_retains_proof_but_becomes_unknown_terminal
    rejected_and_unknown_completion_results_retain_their_honest_status
    whole_native_proof_equality_and_scalar_identity_are_separate_guards
    initial_nonfinite_and_signed_zero_bits_are_stored_without_observation
    negative_monotone_times_can_confirm_and_reserve_negative_reply_deadline
    duration_tolerance_can_confirm_evidence_beyond_original_request_duration
    sample_partial_presence_burns_sequence_but_never_processes_partial_sample
    candidate_zero_is_ignored_before_the_genuine_new_proof_mint_point
    eligible_zero_candidate_fails_invalid_bridge_after_clock_and_sequence_burn
    maximum_candidate_is_valid_once_and_later_candidate_zero_cannot_remint
    raw_state_value_copies_are_independent_and_native_fact_blocks_cross_proof
    exact_advance_elapsed_and_original_proof_age_boundaries_match_double_semantics
    is_current_silent_failure_does_not_fabricate_an_emitted_failure_event
    malformed_abi_and_every_structural_state_field_fail_byte_identically
    malformed_opcodes_domains_optional_payloads_and_primitive_fields_fail_closed
    deterministic_independent_traces_compare_every_raw_state_event_and_boolean
    initial_is_canonical_and_owns_nothing
    arm_replaces_optional_callback_and_resets_consumed
    foreign_admission_ignores_phase_before_any_error
    already_consumed_admission_ignores_invalid_phase
    matched_admission_rejects_nonrecoverable_native_phases
    nil_admission_callback_still_consumes_after_accepted_issued
    callback_preparation_never_consumes_before_native_success
    thrown_admission_callback_remains_armed_retryable
    successful_admission_is_consumed_once
    active_completion_does_not_require_admission
    idle_and_foreign_completion_ignore_phase
    matched_completion_checks_active_only_after_owner_guard
    thrown_completion_preserves_every_owned_field
    successful_completion_clears_owner_callbacks_and_consumed
    cancellation_is_exact_and_rearm_cannot_be_cancelled_by_foreign_owner
    stale_callback_ack_rejects_same_flags_rearm_native_owner_mismatch
    copied_states_are_independent_and_do_not_share_consumption
    malformed_inputs_never_invite_callback_or_clear_existing_owner
    forged_callback_ack_without_an_eligible_prepared_shape_is_invalid
    exact_raw_layout_is_copy_only_and_has_no_native_pointer
    all_reachable_original_states_and_events_match_independent_flat_reference
    seeded_original_trace_with_rearm_cancellation_and_value_copies_matches
    zero_is_valid_then_duplicate_is_unchanged
    first_maximum_sequence_is_valid_without_allocation
    age_63_is_admitted_and_age_64_rejects_without_change
    advance_63_retains_only_in_window_history
    advance_64_does_not_shift_by_64_and_retires_history
    advance_above_window_remains_one_bit
    maximum_adjacent_arithmetic_never_wraps
    reordered_packets_accumulate_without_erasing_seen_bits
    value_copies_are_independent_and_reset_is_a_fresh_value
    bounded_event_traces_match_frozen_original_at_every_step
    all_boundary_sequence_pairs_match_reference
    malformed_raw_state_is_unchanged_and_never_accepted
    unknown_abi_rejects_without_canonicalizing_or_resetting
    copied_scalar_layout_is_24_and_32_bytes
    canonical_looking_accepted_duplicate_is_rejected_by_boundary
    canonical_looking_history_clearing_accepted_output_is_rejected
    output_for_different_input_cannot_authorize_current_packet
    rejected_outputs_cannot_mutate_history_or_change_error_class
    unknown_disposition_and_reserved_output_are_never_committed
    initial_output_must_not_invent_populated_or_stale_owner_history
    scalar_call_order_model_opens_first_but_burns_before_post_decode_semantic_validation
    checkpoint_initial_and_copied_layout_are_exact
    checkpoint_all_valid_states_and_boolean_facts_match_original
    checkpoint_bounded_committed_and_failed_effect_traces_match_original
    checkpoint_revocation_is_terminal_without_erasing_binding
    checkpoint_readback_ignores_revocation_and_owner_but_requires_snapshot
    checkpoint_rejected_input_preserves_exact_state
    checkpoint_unknown_abi_opcode_flags_and_booleans_fail_closed
    checkpoint_raw_value_copies_do_not_share_mutation
    reconnect_copied_layout_and_export_are_exact
    reconnect_all_bounded_numeric_inputs_match_original
    reconnect_outbound_zero_and_maximum_preserve_native_ordering
    reconnect_inbound_strict_newer_includes_authenticated_maximum
    reconnect_opposite_counters_never_change
    reconnect_large_u64_values_never_round_through_float
    reconnect_rejected_events_preserve_exact_snapshot
    reconnect_unknown_abi_opcode_and_reserved_fields_fail_closed
    reconnect_outbound_unused_request_sequence_is_rejected
    reconnect_candidate_is_committed_only_after_modeled_constructor_success
    reconnect_bounded_effect_success_and_failure_traces_match_original
    reconnect_raw_value_copies_remain_independent
    pairing_commit_exact_copied_layout_and_export
    pairing_commit_all_720_syntactic_cases_match_frozen_original
    pairing_commit_recovery_getter_is_not_global_stored_shape_validation
    pairing_commit_proposal_preserves_cache_or_requires_original_constructor
    pairing_commit_ack_cached_replay_still_authenticates_and_does_not_tighten_cache
    pairing_commit_host_ack_replay_reauthenticates_and_preserves_exact_cache
    pairing_commit_active_host_completion_is_ephemeral_not_reopened
    pairing_commit_send_success_never_activates_or_retires_completion
    pairing_commit_active_viewer_authenticates_before_missing_cache_refusal
    pairing_commit_issued_viewer_requires_completion_auth_and_activation_constructor
    pairing_commit_activation_ack_authenticates_active_replay_and_retires_cache
    pairing_commit_role_and_phase_guards_precede_inbound_authentication
    pairing_commit_stored_shape_exactly_matches_original_eight_allowed_shapes
    pairing_commit_invalid_abi_domains_and_reserved_fields_preserve_raw_snapshot
    pairing_commit_unused_uuid_fact_is_not_an_alternative_authorization
    pairing_commit_proposals_commit_only_after_modeled_authentication_and_constructor
    pairing_commit_seeded_bounded_histories_and_value_copies_match_reference
    pairing_commit_all_rejected_plans_preserve_whole_candidate_without_actions
    pairing_commit_every_ready_plan_has_deterministic_modeled_failure_and_cache_custody
    pairing_commit_critical_modeled_error_priority_uses_literal_original_traces
    literal_reference_covers_every_typed_input_exactly_once
    literal_48_cases_match_original_native_priority
    every_raw_closed_field_rejects_against_all_48_valid_bases
    every_distinct_pair_of_invalid_fields_stays_invalid
    every_valid_output_has_closed_action_source_and_zero_reserved
    copied_layout_pins_every_field_offset_size_and_alignment
    a_retry_from_either_child_beats_a_playing_successor
    retry_retains_selected_provider_even_when_absent
    selected_playing_music_beats_browser_playing_fallback
    playing_tie_without_selection_bootstraps_browser
    paused_selected_music_is_retained_over_browser_available_fallback
    paused_tie_without_selection_bootstraps_browser
    absence_publishes_none_and_does_not_retain_stale_selection
    unsupported_abi_is_canonical_invalid_not_a_selection
    reserved_input_is_canonical_invalid_not_a_selection
    unknown_selected_source_is_not_normalized_to_none
    unknown_child_observation_is_not_normalized_to_retry
    availability_retry_layout_and_actual_export_are_exact
    availability_retry_all_fourteen_literal_transitions_match
    availability_retry_reset_and_became_marker_match_each_state
    availability_retry_repeated_valid_state_is_reported_only_once
    availability_retry_failure_returns_old_delay_and_clears_validation
    availability_retry_failures_double_then_saturate_at_thirty
    availability_retry_valid_failure_valid_rearms_marker
    availability_retry_bounded_histories_match_original_native_and_literals
    availability_retry_long_traces_remain_bounded_without_counter_overflow
    availability_retry_closed_raw_state_domains_never_normalize
    availability_retry_unknown_call_abi_is_invalid_unchanged
    availability_retry_closed_event_opcode_and_reserved_never_reset
    availability_retry_two_invalid_fields_preserve_exact_raw_state
    availability_retry_no_websocket_upgrade_operation_exists
    availability_retry_value_inputs_are_unmodified_for_valid_and_refused_calls
    literal_cooldown_does_not_probe_one_tick_early_or_rearm_at_cap
    default_failure_budget_has_exact_literal_delays_and_sixty_tick_cooldown
    signed_constructor_preserves_every_limit_domain_and_clamps_to_one
    one_attempt_budget_and_maximum_counters_do_not_overflow
    failure_when_exhausted_preserves_partially_elapsed_cooldown
    exponent_caps_at_thirty_without_an_invented_sixty_four_entry_limit
    copies_are_independent_and_read_only_ticks_do_not_create_failure_history
    bounded_adversarial_histories_match_frozen_original_not_production_helpers
    invalid_bridge_never_resets_or_normalizes_a_state
    invalid_constructor_envelope_preserves_requested_values_but_is_not_accepted
    copied_abi_layout_and_c_exports_bind_actual_production
    sixty_four_literal_cases_and_frozen_guards_match_actual_production
    new_start_ignores_generation_but_resume_and_live_require_it
    every_closed_field_refuses_against_every_valid_combination
    legitimate_no_match_is_not_invalid_bridge_and_c_export_is_exact
    literal_observation_watermarks_are_strict_and_never_wrap_at_u64_max
    invalid_or_missing_challenge_is_legitimate_refusal_not_bridge_error
    old_sequence_nonce_and_epoch_each_refuse_independently
    cartesian_boundary_observations_match_frozen_original_without_identity_truncation
    four_literal_evidence_states_distinguish_poison_from_empty_prospective_arm
    literal_peer_fence_distinguishes_absence_zero_and_extreme_generation
    invalid_observation_fields_refuse_instead_of_authorizing
    invalid_evidence_fields_do_not_alias_legitimate_poison
    invalid_peer_fields_refuse_even_with_matching_generation_payloads
    uuid_bytes_layout_and_observation_c_export_are_exact
  ].freeze
  BELUGA_CORE_MUTANT_TESTS = {
    'visibility-coupled-to-target' => 'stable_visibility_survives_missing_target_and_session_churn',
    'unknown-flags-ignored' => 'every_unknown_bit_fails_closed',
    'command-admission-removed' => 'each_original_enabled_guard_is_required',
    'availability-departure-clears-media' => 'availability_reconnect_does_not_replace_or_clear_old_media_owner',
    'stale-media-end-clears-owner' => 'stale_media_end_preserves_current_media_owner',
    'transaction-busy-admission-removed' => 'host_busy_rejects_replacement_without_revocation',
    'transaction-receipt-match-removed' => 'host_completion_requires_exact_receipt_and_envelope',
    'transaction-envelope-match-removed' => 'host_completion_requires_exact_receipt_and_envelope',
    'transaction-conflicting-reply-accepted' => 'cached_reply_is_idempotent_and_conflicting_reply_rejected',
    'transaction-revocation-removed' => 'host_revocation_occurs_on_finish_replacement_and_clear',
    'transaction-timeout-reports-success' => 'clear_and_expiry_report_unknown_once_without_pause_effect',
    'offers-source-identity-bypassed' => 'commit_header_and_current_primary_identity_are_independent',
    'offers-commit-identity-bypassed' => 'commit_header_and_current_primary_identity_are_independent',
    'offers-receive-auth-bypassed' => 'wire_authorization_and_exact_numeric_identity_guard_slots',
    'offers-receive-sequence-burn-removed' => 'rejected_new_sequence_burns_and_retires_before_late_validation',
    'offers-receive-old-retirement-removed' => 'rejected_new_sequence_burns_and_retires_before_late_validation',
    'offers-receive-sequence-replay-admitted' => 'rejected_new_sequence_burns_and_retires_before_late_validation',
    'offers-sent-consuming-retirement-removed' => 'matching_consumption_cannot_revive_after_late_failure',
    'offers-received-consuming-retirement-removed' => 'matching_consumption_cannot_revive_after_late_failure',
    'offers-phone-sample-age-widened' => 'wrong_identity_and_invalid_phone_observation_do_not_consume',
    'offers-freshness-inclusive' => 'actual_double_adjacent_boundaries_have_expected_decisions',
    'offers-deadline-inclusive' => 'actual_double_adjacent_boundaries_have_expected_decisions',
    'offers-timeline-tolerance-widened' => 'exact_freshness_sample_deadline_and_uncertainty_boundaries',
    'offers-host-position-tolerance-widened' => 'actual_double_adjacent_boundaries_have_expected_decisions',
    'offers-clear-resets-counters' => 'clear_preserves_counters_and_send_capacity_cannot_wrap',
    'offers-sent-sequence-reused' => 'clear_preserves_counters_and_send_capacity_cannot_wrap',
    'offers-unknown-operation-clears-state' => 'unknown_operation_is_invalid_unchanged_without_retirement_or_success',
    'phone-foreign-clock-before-identity' => 'foreign_identity_returns_before_time_but_matching_replay_observes_time',
    'phone-stale-sequence-before-clock' => 'foreign_identity_returns_before_time_but_matching_replay_observes_time',
    'phone-repeated-begin-reservation' => 'only_reserved_correlated_completion_moves_and_cannot_be_replayed',
    'phone-original-proof-age-refreshed' => 'original_proof_age_never_renews_but_completion_uses_latest_sample',
    'phone-paused-outcome-forgotten' => 'successful_native_pause_is_retained_even_when_phone_freshness_fails',
    'phone-pending-failure-keeps-reservation' => 'every_pending_failure_retains_proof_but_becomes_unknown_terminal',
    'invitation-phase-before-owner-and-consumed' => 'foreign_admission_ignores_phase_before_any_error',
    'invitation-nil-admission-not-consumed' => 'nil_admission_callback_still_consumes_after_accepted_issued',
    'invitation-prepared-state-committed-prematurely' => 'callback_preparation_never_consumes_before_native_success',
    'invitation-thrown-callback-consumes' => 'thrown_admission_callback_remains_armed_retryable',
    'invitation-completion-requires-admission' => 'active_completion_does_not_require_admission',
    'invitation-arm-keeps-consumed' => 'arm_replaces_optional_callback_and_resets_consumed',
    'invitation-foreign-cancellation-clears-owner' => 'cancellation_is_exact_and_rearm_cannot_be_cancelled_by_foreign_owner',
    'invitation-native-prepared-owner-ignored' => 'stale_callback_ack_rejects_same_flags_rearm_native_owner_mismatch',
    'invitation-success-callback-not-committed' => 'successful_completion_clears_owner_callbacks_and_consumed',
    'replay-zero-clamped' => 'bounded_event_traces_match_frozen_original_at_every_step',
    'replay-maximum-clamped' => 'bounded_event_traces_match_frozen_original_at_every_step',
    'replay-age63-refused' => 'bounded_event_traces_match_frozen_original_at_every_step',
    'replay-advance63-clears-history' => 'bounded_event_traces_match_frozen_original_at_every_step',
    'replay-duplicate-bit-ignored' => 'bounded_event_traces_match_frozen_original_at_every_step',
    'replay-short-advance-clears-history' => 'bounded_event_traces_match_frozen_original_at_every_step',
    'replay-reorder-clears-history' => 'bounded_event_traces_match_frozen_original_at_every_step',
    'replay-unknown-abi-resets-state' => 'unknown_abi_rejects_without_canonicalizing_or_resetting',
    'replay-malformed-state-resets-history' => 'malformed_raw_state_is_unchanged_and_never_accepted',
    'replay-populated-bit-zero-ignored' => 'malformed_raw_state_is_unchanged_and_never_accepted',
    'replay-impossible-past-bits-ignored' => 'malformed_raw_state_is_unchanged_and_never_accepted',
    'checkpoint-revoked-add-admitted' => 'checkpoint_revocation_is_terminal_without_erasing_binding',
    'checkpoint-add-owner-bypassed' => 'checkpoint_all_valid_states_and_boolean_facts_match_original',
    'checkpoint-update-owner-bypassed' => 'checkpoint_all_valid_states_and_boolean_facts_match_original',
    'checkpoint-second-add-admitted' => 'checkpoint_all_valid_states_and_boolean_facts_match_original',
    'checkpoint-update-tuple-bypassed' => 'checkpoint_all_valid_states_and_boolean_facts_match_original',
    'checkpoint-readback-snapshot-bypassed' => 'checkpoint_readback_ignores_revocation_and_owner_but_requires_snapshot',
    'checkpoint-revoke-erases-binding' => 'checkpoint_revocation_is_terminal_without_erasing_binding',
    'checkpoint-unknown-opcode-admitted' => 'checkpoint_unknown_abi_opcode_flags_and_booleans_fail_closed',
    'checkpoint-unknown-flags-admitted' => 'checkpoint_unknown_abi_opcode_flags_and_booleans_fail_closed',
    'checkpoint-unknown-abi-admitted' => 'checkpoint_unknown_abi_opcode_flags_and_booleans_fail_closed',
    'checkpoint-unbound-update-admitted' => 'checkpoint_all_valid_states_and_boolean_facts_match_original',
    'checkpoint-revoked-readback-denied' => 'checkpoint_readback_ignores_revocation_and_owner_but_requires_snapshot',
    'reconnect-outbound-zero-refused' => 'reconnect_outbound_zero_and_maximum_preserve_native_ordering',
    'reconnect-outbound-maximum-wraps' => 'reconnect_outbound_zero_and_maximum_preserve_native_ordering',
    'reconnect-outbound-increment-removed' => 'reconnect_all_bounded_numeric_inputs_match_original',
    'reconnect-equal-inbound-admitted' => 'reconnect_inbound_strict_newer_includes_authenticated_maximum',
    'reconnect-inbound-highwater-removed' => 'reconnect_inbound_strict_newer_includes_authenticated_maximum',
    'reconnect-outbound-resets-inbound' => 'reconnect_opposite_counters_never_change',
    'reconnect-inbound-resets-outbound' => 'reconnect_opposite_counters_never_change',
    'reconnect-unknown-abi-admitted' => 'reconnect_unknown_abi_opcode_and_reserved_fields_fail_closed',
    'reconnect-state-reserved-ignored' => 'reconnect_unknown_abi_opcode_and_reserved_fields_fail_closed',
    'reconnect-event-reserved-ignored' => 'reconnect_unknown_abi_opcode_and_reserved_fields_fail_closed',
    'reconnect-unknown-opcode-admitted' => 'reconnect_unknown_abi_opcode_and_reserved_fields_fail_closed',
    'reconnect-unused-outbound-sequence-admitted' => 'reconnect_outbound_unused_request_sequence_is_rejected',
    'pairing-commit-issued-cached-ack-skips-auth' => 'pairing_commit_ack_cached_replay_still_authenticates_and_does_not_tighten_cache',
    'pairing-commit-host-ack-replay-drops-cache' => 'pairing_commit_host_ack_replay_reauthenticates_and_preserves_exact_cache',
    'pairing-commit-active-completion-reopens-host' => 'pairing_commit_active_host_completion_is_ephemeral_not_reopened',
    'pairing-commit-completion-send-activates-host' => 'pairing_commit_send_success_never_activates_or_retires_completion',
    'pairing-commit-active-completion-refusal-before-auth' => 'pairing_commit_active_viewer_authenticates_before_missing_cache_refusal',
    'pairing-commit-active-cached-completion-skips-auth' => 'pairing_commit_active_viewer_authenticates_before_missing_cache_refusal',
    'pairing-commit-activation-replay-skips-auth' => 'pairing_commit_activation_ack_authenticates_active_replay_and_retires_cache',
    'pairing-commit-activation-keeps-obsolete-cache' => 'pairing_commit_activation_ack_authenticates_active_replay_and_retires_cache',
    'pairing-commit-issued-viewer-forgets-activation-constructor' => 'pairing_commit_issued_viewer_requires_completion_auth_and_activation_constructor',
    'pairing-commit-pending-ack-forgets-constructor' => 'pairing_commit_ack_cached_replay_still_authenticates_and_does_not_tighten_cache',
    'pairing-commit-proposal-retains-empty-cache' => 'pairing_commit_proposal_preserves_cache_or_requires_original_constructor',
    'pairing-commit-recovery-tighter-than-original' => 'pairing_commit_recovery_getter_is_not_global_stored_shape_validation',
    'pairing-commit-active-stored-shape-allows-cache' => 'pairing_commit_stored_shape_exactly_matches_original_eight_allowed_shapes',
    'pairing-commit-mark-uuid-mismatch-admitted' => 'pairing_commit_send_success_never_activates_or_retires_completion',
    'pairing-commit-outer-abi-ignored' => 'pairing_commit_invalid_abi_domains_and_reserved_fields_preserve_raw_snapshot',
    'pairing-commit-state-reserved-ignored' => 'pairing_commit_invalid_abi_domains_and_reserved_fields_preserve_raw_snapshot',
    'pairing-commit-event-reserved-ignored' => 'pairing_commit_invalid_abi_domains_and_reserved_fields_preserve_raw_snapshot',
    'pairing-commit-unused-uuid-fact-admitted' => 'pairing_commit_unused_uuid_fact_is_not_an_alternative_authorization',
    'pairing-commit-host-ack-phase-guard-removed' => 'pairing_commit_role_and_phase_guards_precede_inbound_authentication',
    'pairing-commit-invalid-role-canonicalized' => 'pairing_commit_invalid_abi_domains_and_reserved_fields_preserve_raw_snapshot',
    'supported-player-retry-requires-both-children' => 'a_retry_from_either_child_beats_a_playing_successor',
    'supported-player-retry-forgets-selection-hold' => 'retry_retains_selected_provider_even_when_absent',
    'supported-player-selected-playing-is-not-sticky' => 'selected_playing_music_beats_browser_playing_fallback',
    'supported-player-playing-fallback-prefers-music' => 'playing_tie_without_selection_bootstraps_browser',
    'supported-player-paused-current-source-is-not-retained' => 'paused_selected_music_is_retained_over_browser_available_fallback',
    'supported-player-available-fallback-prefers-music' => 'paused_tie_without_selection_bootstraps_browser',
    'supported-player-no-media-fabricates-browser' => 'absence_publishes_none_and_does_not_retain_stale_selection',
    'supported-player-unknown-abi-is-accepted' => 'unsupported_abi_is_canonical_invalid_not_a_selection',
    'supported-player-reserved-input-is-accepted' => 'reserved_input_is_canonical_invalid_not_a_selection',
    'supported-player-unknown-selection-is-normalized-none' => 'unknown_selected_source_is_not_normalized_to_none',
    'supported-player-unknown-child-is-normalized-retry' => 'unknown_child_observation_is_not_normalized_to_retry',
    'supported-player-reserved-output-is-nonzero' => 'every_valid_output_has_closed_action_source_and_zero_reserved',
    'supported-player-input-field-offsets-are-reordered' => 'copied_layout_pins_every_field_offset_size_and_alignment',
    'supported-player-output-field-offsets-are-reordered' => 'copied_layout_pins_every_field_offset_size_and_alignment',
    'availability-valid-reset-removed' => 'availability_retry_reset_and_became_marker_match_each_state',
    'availability-repeated-valid-marker-inverted' => 'availability_retry_repeated_valid_state_is_reported_only_once',
    'availability-failure-returns-doubled-delay' => 'availability_retry_failure_returns_old_delay_and_clears_validation',
    'availability-failure-state-not-advanced-or-cleared' => 'availability_retry_all_fourteen_literal_transitions_match',
    'availability-sixteen-never-reaches-cap' => 'availability_retry_failures_double_then_saturate_at_thirty',
    'availability-cap-wraps-to-one' => 'availability_retry_failures_double_then_saturate_at_thirty',
    'availability-zero-delay-normalized' => 'availability_retry_closed_raw_state_domains_never_normalize',
    'availability-validated-delay-invariant-removed' => 'availability_retry_closed_raw_state_domains_never_normalize',
    'availability-nonboolean-validation-accepted' => 'availability_retry_closed_raw_state_domains_never_normalize',
    'availability-call-abi-ignored' => 'availability_retry_unknown_call_abi_is_invalid_unchanged',
    'availability-state-abi-ignored' => 'availability_retry_closed_raw_state_domains_never_normalize',
    'availability-state-reserved-ignored' => 'availability_retry_closed_raw_state_domains_never_normalize',
    'availability-event-reserved-ignored' => 'availability_retry_closed_event_opcode_and_reserved_never_reset',
    'availability-unknown-operation-becomes-failure' => 'availability_retry_closed_event_opcode_and_reserved_never_reset',
    'availability-refusal-resets-raw-state' => 'availability_retry_two_invalid_fields_preserve_exact_raw_state',
    'availability-result-reserved-not-zero' => 'availability_retry_all_fourteen_literal_transitions_match',
    'safe-output-budget-tick-equality' => 'literal_cooldown_does_not_probe_one_tick_early_or_rearm_at_cap',
    'safe-output-cooldown-stalls' => 'literal_cooldown_does_not_probe_one_tick_early_or_rearm_at_cap',
    'safe-output-cap-rearms-partly-elapsed-cooldown' => 'failure_when_exhausted_preserves_partially_elapsed_cooldown',
    'safe-output-exponent-cap-thirty-one' => 'exponent_caps_at_thirty_without_an_invented_sixty_four_entry_limit',
    'safe-output-clamp-failed-to-two' => 'signed_constructor_preserves_every_limit_domain_and_clamps_to_one',
    'safe-output-clamp-backoff-to-two' => 'signed_constructor_preserves_every_limit_domain_and_clamps_to_one',
    'safe-output-clamp-cooldown-to-two' => 'signed_constructor_preserves_every_limit_domain_and_clamps_to_one',
    'safe-output-no-capped-cooldown' => 'default_failure_budget_has_exact_literal_delays_and_sixty_tick_cooldown',
    'safe-output-backoff-tick-admits' => 'literal_cooldown_does_not_probe_one_tick_early_or_rearm_at_cap',
    'safe-output-reset-leaves-one-failure' => 'copies_are_independent_and_read_only_ticks_do_not_create_failure_history',
    'system-audio-resume-needs-authorization' => 'sixty_four_literal_cases_and_frozen_guards_match_actual_production',
    'system-audio-resume-ignores-peer-generation' => 'new_start_ignores_generation_but_resume_and_live_require_it',
    'system-audio-new-start-adds-generation-fence' => 'new_start_ignores_generation_but_resume_and_live_require_it',
    'system-audio-live-accepts-paused' => 'sixty_four_literal_cases_and_frozen_guards_match_actual_production',
    'system-audio-invalid-boolean-becomes-false' => 'every_closed_field_refuses_against_every_valid_combination',
    'hosted-call-equal-watermark-admits' => 'literal_observation_watermarks_are_strict_and_never_wrap_at_u64_max',
    'hosted-call-ignores-challenge-sequence' => 'old_sequence_nonce_and_epoch_each_refuse_independently',
    'hosted-call-ignores-observation-nonce' => 'old_sequence_nonce_and_epoch_each_refuse_independently',
    'hosted-call-ignores-observation-epoch' => 'old_sequence_nonce_and_epoch_each_refuse_independently',
    'hosted-call-accepts-other-positive-protocol' => 'invalid_or_missing_challenge_is_legitimate_refusal_not_bridge_error',
    'hosted-call-accepts-zero-challenge-sequence' => 'invalid_or_missing_challenge_is_legitimate_refusal_not_bridge_error',
    'hosted-call-accepts-zero-nonce' => 'invalid_or_missing_challenge_is_legitimate_refusal_not_bridge_error',
    'hosted-call-accepts-zero-epoch' => 'invalid_or_missing_challenge_is_legitimate_refusal_not_bridge_error',
    'hosted-call-accepts-identical-nonce-and-epoch' => 'invalid_or_missing_challenge_is_legitimate_refusal_not_bridge_error',
    'hosted-call-peer-current-zero-admits' => 'literal_peer_fence_distinguishes_absence_zero_and_extreme_generation',
    'hosted-call-peer-ignores-audio-generation' => 'literal_peer_fence_distinguishes_absence_zero_and_extreme_generation',
    'hosted-call-peer-ignores-challenge-generation' => 'literal_peer_fence_distinguishes_absence_zero_and_extreme_generation',
    'hosted-call-poison-becomes-active' => 'four_literal_evidence_states_distinguish_poison_from_empty_prospective_arm',
    'hosted-call-inactive-becomes-none' => 'four_literal_evidence_states_distinguish_poison_from_empty_prospective_arm',
    'hosted-call-invalid-boolean-becomes-true' => 'invalid_evidence_fields_do_not_alias_legitimate_poison',
    'safe-output-initializer-envelope-or-becomes-and' => 'invalid_constructor_envelope_preserves_requested_values_but_is_not_accepted',
    'safe-output-invalid-initializer-fabricates-failure-counter' => 'invalid_constructor_envelope_preserves_requested_values_but_is_not_accepted',
    'hosted-call-peer-accepts-zero-abi' => 'invalid_peer_fields_refuse_even_with_matching_generation_payloads',
    'hosted-call-peer-ignores-reserved-one' => 'invalid_peer_fields_refuse_even_with_matching_generation_payloads',
  }.freeze
  BELUGA_CORE_MUTANTS = BELUGA_CORE_MUTANT_TESTS.keys.freeze
  BELUGA_CORE_RUNTIME_MARKERS = [
    'BelugaCore C ABI PASS: 4096 flags and unknown ABI',
    'BelugaCore C lifecycle ABI PASS: reconnect ownership and invalid ABI',
    'BelugaCore C transaction ABI PASS: exact identity, cached reply, revocation and unknown outcome',
    'BelugaCore C offers ABI PASS: independent owners, sequence burn, consuming rejection and exact layouts',
    'BelugaCore C phone operation ABI PASS: exact layouts, original ordering, immutable proof and honest pause outcomes',
    'BelugaCore C invitation acceptance ABI PASS: exact layouts, original guard order and one-use callback outcomes',
    'BelugaCore C signaling replay ABI PASS: exact layouts, zero/MAX, 63/64 window and unchanged rejection',
    'BelugaCore C catalog checkpoint ABI PASS: exact layouts, candidate custody, terminal revoke and full readback',
    'BelugaCore C reconnect counters ABI PASS: exact layouts, zero/MAX, strict admission and unchanged refusal',
    'BelugaCore C pairing commit ABI PASS: exact layouts, phase plans, auth ordering and unchanged refusal',
    'BelugaCore C supported player arbitration ABI PASS: exact layouts, 48 literal choices and 720 closed-field refusals',
    'BelugaCore C availability retry ABI PASS: exact layouts, 14 literal transitions and 280 unchanged refusals',
    'BelugaCore C safe output retry ABI PASS: exact layouts, frozen literal transitions and unchanged refusals',
    'BelugaCore C system audio start ABI PASS: exact layouts, 64 literal choices and 1152 closed-field refusals',
    'BelugaCore C hosted call ABI PASS: exact layouts, strict watermark and generation identity, unchanged refusals',
    'BelugaCore Swift import/link PASS: 4096 flags and unknown ABI',
    'BelugaCore Swift lifecycle import/link PASS: reconnect ownership and invalid ABI',
    'BelugaCore Swift transaction import/link PASS: exact identity, cached reply, revocation and unknown outcome',
    'BelugaCore Swift offers import/link PASS: independent owners, sequence burn, consuming rejection and exact layouts',
    'BelugaCore Swift phone operation import/link PASS: exact layouts, original ordering, immutable proof and honest pause outcomes',
    'BelugaCore Swift invitation acceptance import/link PASS: exact layouts, original guard order and one-use callback outcomes',
    'BelugaCore Swift signaling replay import/link PASS: exact layouts, zero/MAX, 63/64 window and unchanged rejection',
    'BelugaCore Swift catalog checkpoint import/link PASS: exact layouts, candidate custody, terminal revoke and full readback',
    'BelugaCore Swift reconnect counters import/link PASS: exact layouts, zero/MAX, strict admission and unchanged refusal',
    'BelugaCore Swift pairing commit import/link PASS: exact layouts, phase plans, auth ordering and unchanged refusal',
    'BelugaCore Swift supported player arbitration import/link PASS: exact layouts, 48 literal choices and 720 closed-field refusals',
    'BelugaCore Swift availability retry import/link PASS: exact layouts, 14 literal transitions and 280 unchanged refusals',
    'BelugaCore Swift safe output retry import/link PASS: exact layouts, frozen literal transitions and unchanged refusals',
    'BelugaCore Swift system audio start import/link PASS: exact layouts, 64 literal choices and 1152 closed-field refusals',
    'BelugaCore Swift hosted call import/link PASS: exact layouts, strict watermark and generation identity, unchanged refusals',
  ].freeze
  GATE_PINNED = %w[
    test_beluga_core_has_independent_discovered_non_skipping_coverage
    test_beluga_core_phases_and_exact_crate_commands_are_mandatory
    test_beluga_core_rehashed_results_cannot_omit_or_skip_discovered_cases
    test_beluga_core_ignored_artifact_complete_bytes_are_source_bound
    test_beluga_core_rejects_missing_unbound_symlinked_or_empty_artifact
    test_beluga_core_rejects_absent_or_symlinked_artifact
    test_beluga_core_actual_link_and_named_assertion_mutations_cannot_be_skipped
    test_beluga_core_rejects_stale_or_missing_source_manifest_and_unbound_source
    test_beluga_core_rejects_symlinked_source_and_duplicate_manifest_records
    test_beluga_core_pinned_link_tools_cannot_be_omitted_or_replaced
    test_beluga_core_rehashed_header_slice_or_tool_metadata_drift_is_rejected
    test_handoff_menu_and_rust_policy_classes_and_critical_cases_are_mandatory
    test_gate_named_inventory_pins_new_refusal_cases
    test_gate_named_results_reject_omission_duplication_failure_skip_and_bad_footer
    test_gate_named_phase_cannot_remove_verbose_or_rehash_skipped_results
    test_shared_handoff_classes_and_every_critical_source_case_are_mandatory
    test_shared_handoff_phase_cannot_skip_cases_weaken_filter_or_borrow_old_coverage
    test_simulator_handoff_completion_cleanup_and_audio_leases_cannot_be_omitted_or_skipped
    test_beluga_core_multiplatform_slice_inventory_and_each_copied_abi_are_exact
    test_beluga_core_all_reviewed_targets_sdks_and_cross_links_are_mandatory
    test_beluga_core_transaction_tests_and_each_negative_mutant_are_mandatory
    test_beluga_core_framework_layout_rejects_flat_header_collision_and_wrong_bundle_metadata
    test_beluga_core_static_framework_executable_refuses_dynamic_or_malformed_fat_payload
    test_beluga_core_offers_source_tests_link_smokes_and_mutants_are_mandatory
    test_shared_handoff_offers_full_discovered_and_pinned_coverage_cannot_be_removed
    test_beluga_core_compiled_mutation_assertions_reject_uncompiled_wrong_case_and_bad_footer
    test_beluga_core_phone_operation_source_tests_link_smokes_and_mutants_are_mandatory
    test_beluga_core_invitation_source_tests_link_smokes_and_mutants_are_mandatory
    test_beluga_core_replay_source_tests_link_smokes_and_mutants_are_mandatory
    test_shared_replay_source_discovery_and_every_critical_case_are_exact
    test_shared_replay_named_results_reject_missing_duplicate_skip_failure_and_wrong_suite
    test_shared_replay_suite_boundaries_counts_order_and_concurrency_are_exact
    test_shared_replay_phases_and_coverage_cannot_be_removed_or_rehashed
    test_shared_replay_observer_execution_cannot_be_borrowed_from_other_suites
    test_pairing_inventory_is_exact104_separate_from_original_simulator_skips
    test_pairing_zero_skip_named_results_cannot_omit_duplicate_or_fail_cases
    test_pairing_compiler_requires_fresh_inert_driver_source_filelist_map_and_object
    test_pairing_owned_compiler_files_and_lock_replacement_fail_closed
    test_pairing_receipt_cannot_omit_rehash_or_weaken_inert_phases_and_artifacts
    test_pairing_run_never_launches_without_fresh_compiler_custody
    test_pairing_executor_success_nonzero_and_timeout_retire_exact_group
    test_pairing_executor_reaped_leader_cannot_abandon_living_descendant
    test_pairing_executor_interruption_still_reaps_and_proves_group_absent
    test_pairing_executor_eperm_never_becomes_a_successful_absence_proof
    test_pairing_stale_object_and_forged_process_records_refuse_before_launch
    test_beluga_core_catalog_checkpoint_source_and_named_cases_are_mandatory
    test_beluga_core_catalog_checkpoint_link_contract_cannot_be_borrowed
    test_native_catalog_checkpoint_class_and_every_critical_case_are_mandatory
    test_native_catalog_checkpoint_results_and_rehashed_coverage_cannot_be_borrowed
    test_beluga_core_catalog_checkpoint_each_compiled_assertion_mutant_is_mandatory
    test_beluga_core_reconnect_counters_source_and_named_cases_are_mandatory
    test_beluga_core_reconnect_counters_link_contract_cannot_be_borrowed
    test_beluga_core_reconnect_counters_each_compiled_assertion_mutant_is_mandatory
    test_shared_reconnect_counters_source_discovery_and_every_critical_case_are_exact
    test_shared_reconnect_counters_named_results_reject_missing_duplicate_skip_failure_and_wrong_suite
    test_shared_reconnect_counters_suite_boundaries_counts_order_and_concurrency_are_exact
    test_shared_reconnect_counters_phase_and_coverage_cannot_be_removed_or_rehashed
    test_shared_reconnect_counters_actual_suite_execution_cannot_be_borrowed
    test_beluga_core_pairing_commit_source_and_named_cases_are_mandatory
    test_beluga_core_pairing_commit_link_contract_cannot_be_borrowed
    test_beluga_core_pairing_commit_each_compiled_assertion_mutant_is_mandatory
    test_shared_pairing_commit_source_discovery_and_every_critical_case_are_exact
    test_shared_pairing_commit_named_results_reject_missing_duplicate_skip_failure_and_wrong_suite
    test_shared_pairing_commit_suite_boundaries_counts_order_and_concurrency_are_exact
    test_shared_pairing_commit_phase_and_coverage_cannot_be_removed_or_rehashed
    test_shared_pairing_commit_actual_suite_execution_cannot_be_borrowed
    test_pairing_commit_concrete_native_reference_and_caller_sources_are_mandatory
    test_pairing_commit_enrollment_preserves_exact_previous_prefixes
    test_pairing_commit_mac_ack_storage_and_viewer_decode_composition_are_mandatory
    test_beluga_core_supported_player_source_and_named_cases_are_mandatory
    test_beluga_core_supported_player_link_contract_cannot_be_borrowed
    test_beluga_core_supported_player_each_compiled_assertion_mutant_is_mandatory
    test_supported_player_native_source_and_discovery_are_exact
    test_supported_player_native_companions_reject_changed_missing_and_linked_bytes
    test_supported_player_native_results_and_rehashed_coverage_cannot_be_borrowed
    test_supported_player_enrollment_preserves_exact_previous_prefixes
    test_batch_a_core_source_and_named_cases_are_mandatory
    test_batch_a_link_contract_cannot_be_borrowed
    test_batch_a_each_compiled_assertion_mutant_is_mandatory
    test_batch_a_native_source_discovery_and_original_lifecycle_cases_are_mandatory
    test_batch_a_native_source_declaration_drift_missing_and_linked_bytes_are_rejected
    test_batch_a_native_results_and_rehashed_coverage_cannot_be_borrowed
    test_batch_a_enrollment_preserves_exact_previous_prefixes
    test_batch_a_actor_source_discovery_and_each_exact_case_are_mandatory
    test_batch_a_native_body_companions_reject_rehashed_tamper_missing_and_linked_bytes
    test_batch_a_actor_enrollment_preserves_prior_complete_inventory
  ].freeze
  SHARED_SIGNALING_SUITE = 'RemoteSessionCoreTests.DurableSignalingClientTests'.freeze
  SHARED_SIGNALING_FILTER = '^RemoteSessionCoreTests\\.DurableSignalingClientTests/'.freeze
  SHARED_SIGNALING_PINNED = %w[
    availabilityBindsExactExchangeToEnvelopeAndRotatesKeys
    availabilityClientRekeysAfterReadyAndRelaysSignedReconnectMessage
    availabilityCloseWinningSuspendedConnectCannotReopenClient
    availabilityClosesBeforeHeartbeatWhenFirstProtocolStateNeverArrives
    availabilityLocatorsSeparateRoleCapabilitiesAndRejectRoleSubstitution
    availabilityMapsBoundedUnavailableErrorForTransientRetry
    availabilityPingFailureClosesAVisiblyOpenGhostSocket
    availabilityRejectsLegacyWaitingAndUsesExactAvailabilityMode
    availabilityRejectsUnboundedOrExtendedErrorSchemas
    availabilityValidFirstStateCancelsDeadlineAndStartsHeartbeat
    hostSendsCanonicalProbeAndMatchingAckKeepsAvailabilityOpen
    matchingAckBeforeSuspendedSendReturnsCompletesExactProbe
    mismatchedAckForActiveProbeFailsClosed
    missingApplicationProbeAckClosesHostAvailability
    pairingBootstrapCloseWinningSuspendedConnectCannotReopenClient
    pairingBootstrapRestartsSequencesAndReplayWindowForReplacementPeer
    pairingBootstrapUsesNegotiatedPairingModeAndBoundedPayloads
    probeDeadlineClosesHostWhileTransportSendIsSuspended
    sessionCloseWinningSuspendedConnectCannotReopenClient
    staleProbeAckFailsClosedAndCannotBlessReplacementClient
    transportCancellationPingFailsClosedWhenLivenessTaskIsNotCancelled
    viewerHeartbeatsNeverSendApplicationProbes
    availabilitySecondCloseJoinsNativeFinishAndPreservesFirstTerminalError
    pairingSecondCloseJoinsNativeFinishAndPreservesFirstTerminalError
    availabilityCloseJoinsConnectionFailureCleanup
    availabilityPublicCloseJoinsDistinctLateSuccessReclose
    pairingPublicCloseJoinsDistinctLateSuccessReclose
  ].map { |name| SHARED_SIGNALING_SUITE + '/' + name + '()' }.freeze
  # Three independent Swift Testing suites: source, discovery and each real run
  # are bound separately. The original signaling phase and its pins stay exact.
  SHARED_REPLAY_PHASES = {
    'shared-replay-native-tests' => 'RemoteSessionCoreTests.BelugaRustSignalingReplayTests',
    'shared-replay-authentication-tests' => 'RemoteSessionCoreTests.RemoteSignalingReplayAuthenticationTests',
    'shared-replay-durable-tests' => 'RemoteSessionCoreTests.DurableSignalingReplayObservationTests'
  }.freeze
  SHARED_REPLAY_FILES = {
    'RemoteSessionCoreTests.BelugaRustSignalingReplayTests' => 'shared/Tests/RemoteSessionCoreTests/BelugaRustSignalingReplayTests.swift',
    'RemoteSessionCoreTests.RemoteSignalingReplayAuthenticationTests' => 'shared/Tests/RemoteSessionCoreTests/RemoteSignalingReplayAuthenticationTests.swift',
    'RemoteSessionCoreTests.DurableSignalingReplayObservationTests' => 'shared/Tests/RemoteSessionCoreTests/DurableSignalingReplayObservationTests.swift'
  }.freeze
  SHARED_REPLAY_PINNED = {
    'RemoteSessionCoreTests.BelugaRustSignalingReplayTests' => %w[
      actualCopiedABILayoutAndInitialAreExact
      actualNativeGuardMatchesIndependentOriginalBoundedTraces
      zeroMaximumAnd63Versus64BoundariesUseActualExports
      duplicateAndOutsideRejectionsPreserveEveryStoredFieldWithoutFaulting
      sendableCopiesHaveIndependentStoredWindowsAndFaultLifetimes
      malformedInitialCannotCallStepOrManufactureEmptyRecovery
      unknownDecisionAndReservedOutputCannotCommit
      canonicalLookingAcceptedDuplicateIsRejectedByActualAdapter
      shortAdvanceCannotErasePreviouslyAcceptedHistory
      validOutputForAnotherSequenceCannotCommit
      validOutputForAnotherHistoryCannotCommit
      unexpectedInitialOrPopulatedPresenceCannotCommit
      wrongABIMissingCurrentBitOrNegativeHistoryCannotCommit
      rejectionCannotMutateAnyStoredHistoryField
      falseDuplicateForUnseenSequenceCannotPreserveThenRejectAsReplay
      falseOutsideForInWindowUnseenSequenceCannotCommit
      contradictoryHighestOrReorderedExtraBitCannotCommit
      stickyBridgeFaultStopsAllProducerCallsWithoutRetryOrReset
      observerReportsOnlyActualStoredStateAfterCommitOrRefusal
    ].map { |name| 'RemoteSessionCoreTests.BelugaRustSignalingReplayTests/' + name + '()' }.freeze,
    'RemoteSessionCoreTests.RemoteSignalingReplayAuthenticationTests' => %w[
      receiverAuthenticationFailureDoesNotConsumeSequenceOrAdvanceHistory
      authenticatedUndecodablePlaintextDoesNotConsumeSequence
      authenticatedHeaderTamperCannotConsumeMaximumDirectReceiverSequence
    ].map { |name| 'RemoteSessionCoreTests.RemoteSignalingReplayAuthenticationTests/' + name + '()' }.freeze,
    'RemoteSessionCoreTests.DurableSignalingReplayObservationTests' => %w[
      pairingSemanticFailureFollowsActualStoredReplayCommit
      availabilitySemanticFailureFollowsActualStoredReplayCommit
      validatedPairingDepartureResetsOnceAndAllowsFreshZero
      availabilityExactDepartureAndRepeatedReadyPreserveOriginalResetOrder
      wrongRolePairingDepartureCannotResetStoredReplayOwner
      foreignAvailabilityDepartureOrReadyCannotResetStoredReplayOwner
    ].map { |name| 'RemoteSessionCoreTests.DurableSignalingReplayObservationTests/' + name + '()' }.freeze
  }.freeze
  SHARED_RECONNECT_COUNTER_PHASE = 'shared-reconnect-counter-tests'.freeze
  SHARED_RECONNECT_COUNTER_SUITE = 'RemoteSessionCoreTests.BelugaRustReconnectCounterTests'.freeze
  SHARED_RECONNECT_COUNTER_FILE = 'shared/Tests/RemoteSessionCoreTests/BelugaRustReconnectCounterTests.swift'.freeze
  SHARED_RECONNECT_COUNTER_PINNED = %w[
    actualCopiedABIHasExactLayoutsAndNoInitialState
    actualExportMatchesIndependentNumericOracleForEntireBoundaryAlphabet
    invalidABIAndReservedInputsRemainUnchangedAtActualExport
    actualOutboundZeroProposalDoesNotBypassNativeRequestValidation
    outboundMaximumMinusOneIssuesOnceAndThenExhaustsWithoutMutation
    outboundMaximumRefusesBeforeInvalidConstructorInputs
    inboundMaximumIsAcceptedOnceThenStaleWithoutMutation
    inboundStrictlyNewerSequencesPreserveOutboundCounter
    outboundActiveGuardPrecedesIdentityExhaustionAndProducer
    outboundIdentityGuardPrecedesExhaustionAndProducer
    inboundActiveAndIdentityGuardsPrecedeAuthenticationAndProducer
    inboundProtocolAndStructureGuardsPrecedeProducer
    tamperedStaleAuthenticationPrecedesNumericAdmission
    authenticatedStaleRefusesBeforeInvalidConstructorInputs
    outboundConstructorFailuresPreserveEntireOriginalRecord
    inboundConstructorFailuresPreserveEntireOriginalRecord
    signedZeroAgreementKeyFailurePreservesEntireOriginalRecord
    nativeConstructorsUseOriginalSequenceAndUnmodifiedRecord
    genuineReconnectCompletesMatchingCredentialsAndSignals
    copiedOutputValidationRejectsEveryFieldAndDecisionMismatch
    canonicalLookingProposalCannotAdmitExhaustedOrStaleRequests
    copiedRefusalCannotResetOrAdvanceEitherCounter
    malformedProducerResultFailsBeforeConstructorAndPreservesRecord
    copiedOutputCannotCommitOtherSlotOrUncorrelatedSequence
    freshProjectionUsesCurrentRecordWithoutStoredProducerOrShadowState
    valueCopiesAndCodableKeepIndependentWholeRecordSemantics
    redactedErrorsAndRecordNeverExposeCountersOrCredentials
  ].map { |name| SHARED_RECONNECT_COUNTER_SUITE + '/' + name + '()' }.freeze

  SHARED_PAIRING_COMMIT_PHASE = 'shared-pairing-commit-tests'.freeze
  SHARED_PAIRING_COMMIT_SUITE = 'RemoteSessionCoreTests.BelugaRustPairingCommitTests'.freeze
  SHARED_PAIRING_COMMIT_FILE = 'shared/Tests/RemoteSessionCoreTests/BelugaRustPairingCommitTests.swift'.freeze
  SHARED_PAIRING_COMMIT_SOURCE_SHA256 = {
    'macOS/Sources/CaptureServer/WorldwideHostCoordinator.swift' => 'be95b82e366197cd4fa9f1f2835699c210350614ea3ee5be0ef67a169b93fa8b',
    'macOS/Sources/CaptureServer/WorldwidePairedPhoneCatalogStore.swift' => '94b2cc4456bb47b0d52d705b5a01dd9cf6d6c5b915569650471cc4e0254402f7',
    'macOS/Sources/CaptureServer/WorldwidePairingStore.swift' => 'a00a3c47ecba1c7021d136a9c9e2d93d7c1d0ed10f94e65fc8a4faa8c07a3914',
    'iOS/opensteamer/Sources/Security/ViewerPairingStore.swift' => 'e365d5907849d5aac26dbc8db72e1df2b8c72709b5fdb5d0f81066b194387c2a',
    'iOS/opensteamer/Sources/Security/ViewerPairedMacCatalogStore.swift' => '81793eb2ff472d05a7f8d0409ded43cd0968ac2e731c27bff33ef75e3d2b9bb1',
    'iOS/opensteamer/Sources/ViewModels/WorldwideViewerConnectionCoordinator.swift' => '15bbb2ed7c7645417f6404cf0a70550c8c5d76241ef787b6a3ea13813d3151cc',
    'shared/Sources/RemoteSessionCore/BelugaRustPairingCommitBoundary.swift' => 'd48f62d623cdbd157c3aa156326bc5751bea2d28618f35ce044290a16412f8b4',
    'shared/Sources/RemoteSessionCore/BelugaPairingCommitFaultComposition.swift' => '3f11d44be35930f1a2cb36b2601cf39a7e4be6ecc056500f3e5199ec8710ac52',
    'shared/Sources/RemoteSessionCore/RemotePairedDevice.swift' => '45ce3ab193aaf69a993fce92b3f2a729bb1b62286046a63d7e5016f7c48b16af',
    'shared/Sources/RemoteSessionCore/RemoteSessionCoreError.swift' => '232e3bc453d40e57dfd14bc21dd51f64c40f427f6eed34ac56d77809a5ea12d8',
    'shared/Tests/RemoteSessionCoreTests/BelugaRustPairingCommitTests.swift' => '56018df935a12320ed1e22735cc0c659567577258fbc15f4359f5304831549c0',
    'shared/Tests/RemoteSessionCoreTests/BelugaRustPairingCommitReference.swift' => '7232aa39bcc94fed5211483a83b9e41e7461466626d89e9f5b1d7b39c11585c3'
  }.freeze
  # Concrete Mac composition fixtures are separately bound, not extra native/caller companions.
  SHARED_PAIRING_COMMIT_MAC_SOURCE_SHA256 = {
    'macOS/Tests/CaptureServerTests/WorldwideHostPairingCommitPersistenceTests.swift' => '074551166189d0848189c685b6e3518aed32cdacf1ea4ebbf4dbc41c34f0401d',
    'macOS/Tests/CaptureServerTests/WorldwidePairingCommitDecodeFaultTests.swift' => 'bd1732268e43e2b7d75de93da4cfc96beefd8cb6f57161ef21009db2b6e20526'
  }.freeze
  SHARED_PAIRING_COMMIT_PINNED = %w[
    actualCopiedLayoutsAndAll720PlansMatchFrozenOriginal
    genuineSevenTransitionsAndEveryCachedReturnRetainWholeCommit
    genuineEveryCommitOperationPreservesAllOtherFieldsAndNontrivialExactCounters
    coldValueRoundTripsKeepBothHostAcknowledgementCutsAndSendNonactivation
    identityMismatchWinsBeforePolicyAndProducerForEveryIdentityTakingMethod
    originalRoleAndPhaseRefusalPrecedesBadInboundAuthentication
    cachedIssuedAcknowledgementAuthenticatesActualNewProposalBeforeExactReturn
    hostAcknowledgementReplayReauthenticatesAndPreservesKnownUnusualCache
    activeViewerAuthenticatesCompletionBeforeMissingOrWrongCacheRefusal
    activeHostCompletionIsGenuineEphemeralAndDoesNotReopenRecovery
    markCompletionSentRequiresExactNativeUUIDAndNeverActivatesOrRetires
    genuineAuthenticationFailurePreservesWholeRecordAtAllInboundOperations
    knownWeirdTypedStatesKeepOriginalGetterWithoutGlobalStoredShapeGate
    pendingViewerCanReplaceKnownCacheOnlyAfterActualProposalAuthentication
    issuedViewerReplaysUnusualKnownCacheAfterAuthenticatingActualProposal
    storedShapeValidationRemainsSeparateAndVerifiesActualOpaqueCacheProof
    malformedGetterIsExplicitInvalidBridgeNeverLegitimateNoneOrRecordMutation
    malformedMintOutputCannotCreateOrCommitARecoveryObject
    malformedAuthPlansCannotBypassActualPeerProofOrReplaceCachedValue
    allSevenOperationsRejectMalformedCopiedOutputWithoutWholeRecordMutation
    copiedOutputCannotConvertPostAuthRefusalIntoPrematureRefusalOrSuccess
    valueCopiesRemainIndependentWithNoSharedProducerOrNativeCommitLedger
    producerIsCalledExactlyOnceWithNoPostEffectAcknowledgement
    invalidAbiClosedDomainsReservedAndUnusedFactsRefuseExactRawSnapshot
    storedShapeBridgeFailureRemainsDistinctAndCannotAlterTrustworthyBytes
    decodedFaultContextIsClosedAndOriginalImmutableGuardWins
    absentAndNonmatchingDecodeUseActualPlanAndRetainNoContext
    fourGenuineMintSitesPreserveOriginalInjectedErrorAndWholePredecessor
    cachedReturnsActualAuthenticationAndRefusalsNeverInvokeConstructionProbe
  ].map { |name| SHARED_PAIRING_COMMIT_SUITE + '/' + name + '()' }.freeze

  SHARED_HANDOFF_CLASSES = %w[WebRTCTransportTests.MediaHandoffProtocolTests
                            WebRTCTransportTests.MediaHandoffTransactionTests
                            WebRTCTransportTests.RemoteMediaControlsProtocolTests
                            WebRTCTransportTests.BelugaRustHandoffTransactionTests
                            WebRTCTransportTests.BelugaRustHandoffOffersTests].freeze
  SHARED_HANDOFF_PINNED = %w[
    WebRTCTransportTests.MediaHandoffProtocolTests/testDefaultOffAndExactAdditiveSDPEcho
    WebRTCTransportTests.MediaHandoffProtocolTests/testReceiptIsExactOneUseAndDuplicateCannotRenewDeadline
    WebRTCTransportTests.MediaHandoffProtocolTests/testSourceReplacementPauseSeekRateAndClockRegressionRevokeReceipt
    WebRTCTransportTests.MediaHandoffProtocolTests/testDeadlineDiscardAndContinuityResetCannotReviveReceipt
    WebRTCTransportTests.MediaHandoffTransactionTests/testNativeOfferConsumptionIsOneUseAndRetiredTimelineCannotRevive
    WebRTCTransportTests.MediaHandoffTransactionTests/testStalePlaybackSampleDoesNotDispatchAndFreshReceiptCommitsOnce
    WebRTCTransportTests.MediaHandoffTransactionTests/testExactReceiptAndExactCompletionRequiredNoConflictingReplay
    WebRTCTransportTests.MediaHandoffTransactionTests/testTimeoutAndClearAreUnknownAndCannotReviveNativeAuthority
    WebRTCTransportTests.MediaHandoffTransactionTests/testNativeDisconnectRecoveryRetiresCommitBeforeActorDrain
    WebRTCTransportTests.RemoteMediaControlsProtocolTests/testRealPeerHandoffCommitAndExactNativeResultAreSeparateFromOrdinaryPause
    WebRTCTransportTests.RemoteMediaControlsProtocolTests/testRealPeerHandoffCancellationRevokesUnexecutedNativeReceipt
    WebRTCTransportTests.RemoteMediaControlsProtocolTests/testRealPeerHandoffMissingHostReplyIsUnknownNotSuccess
    WebRTCTransportTests.RemoteMediaControlsProtocolTests/testMalformedOrderedControlRevokesAdmittedHandoffExecution
    WebRTCTransportTests.RemoteMediaControlsProtocolTests/testHandoffRevokedDuringValidationCannotReachSynchronousNativeSend
    WebRTCTransportTests.RemoteMediaControlsProtocolTests/testRealPeerHandoffOfferIsOneUseNonAuthorizingAndExactSourceBound
    WebRTCTransportTests.RemoteMediaControlsProtocolTests/testMalformedOrderedControlRevokesPendingHandoffReceipt
    WebRTCTransportTests.BelugaRustHandoffTransactionTests/testEveryReachableSmallTransactionStateAndEventMatchesOriginalReference
    WebRTCTransportTests.BelugaRustHandoffTransactionTests/testSeededTransactionChurnMatchesStateResultsAndNativeRevocations
    WebRTCTransportTests.BelugaRustHandoffTransactionTests/testHostAndViewerSlotsRemainIndependentAcrossFinishExpireAndReplacement
    WebRTCTransportTests.BelugaRustHandoffTransactionTests/testSameEnvelopeDifferentReceiptCannotFinishOrReplaceBusyHost
    WebRTCTransportTests.BelugaRustHandoffTransactionTests/testEveryResultIsIdempotentAndConflictingReplyDoesNotChangeLedger
    WebRTCTransportTests.BelugaRustHandoffTransactionTests/testClearAndReplacementRetireExactNativeReceiptWithoutRevokingAnother
    WebRTCTransportTests.BelugaRustHandoffTransactionTests/testClosedExpiredAndLostContinuityReceiptsPreserveCallerBoundaryBehavior
    WebRTCTransportTests.BelugaRustHandoffTransactionTests/testMalformedViewerEnvelopeNeverAdmitsAndMismatchedCompletionNeverClears
    WebRTCTransportTests.BelugaRustHandoffTransactionTests/testMalformedHostEnvelopeRetainsOriginalAdmissionAndEqualitySemantics
    WebRTCTransportTests.BelugaRustHandoffTransactionTests/testCanonicalEquivalentEnvelopeMatchesPreserveOriginalBytesAndNoSecondValidityGate
    WebRTCTransportTests.BelugaRustHandoffTransactionTests/testValueCopiesKeepIndependentSlotsButShareNativeRevocation
    WebRTCTransportTests.BelugaRustHandoffTransactionTests/testCopiedScalarBoundaryRejectsMissingRetirementEffectsAndReplay
    WebRTCTransportTests.BelugaRustHandoffTransactionTests/testCopiedScalarBoundaryAcceptsLegitimateCustodyTransitions
    WebRTCTransportTests.BelugaRustHandoffOffersTests/testAllBoundedSmallEventTracesMatchOriginalReference
    WebRTCTransportTests.BelugaRustHandoffOffersTests/testSeededLongChurnKeepsBothSlotsAndReceiptIdentityInParity
    WebRTCTransportTests.BelugaRustHandoffOffersTests/testSnapshotAgeBoundariesAndFiniteNegativeClockMatchOriginalReference
    WebRTCTransportTests.BelugaRustHandoffOffersTests/testTimelineClockPositionAndStrictDeadlineBoundariesMatchReference
    WebRTCTransportTests.BelugaRustHandoffOffersTests/testTimelineDriftScalesWithRateAndKeepsInclusiveBoundary
    WebRTCTransportTests.BelugaRustHandoffOffersTests/testHostPhoneDriftUsesItsDistinctInclusiveBound
    WebRTCTransportTests.BelugaRustHandoffOffersTests/testPlaybackSamplePreflightPreservesReceiptUntilConsumption
    WebRTCTransportTests.BelugaRustHandoffOffersTests/testOriginalRevisionFloorDoesNotBecomeLatestRevisionHighWater
    WebRTCTransportTests.BelugaRustHandoffOffersTests/testHigherRejectedSequenceBurnsFloorAndRetiresPreviousReceipt
    WebRTCTransportTests.BelugaRustHandoffOffersTests/testMatchingConsumptionBurnsBeforeLateValidation
    WebRTCTransportTests.BelugaRustHandoffOffersTests/testMismatchAndCounterfeitInputsPreserveExactPendingAuthority
    WebRTCTransportTests.BelugaRustHandoffOffersTests/testFailedPreparationDoesNotBurnButFailedSendDoesBurnSequence
    WebRTCTransportTests.BelugaRustHandoffOffersTests/testNativeSourceKeepsFractionalOriginalDeadlineAndBounds
    WebRTCTransportTests.BelugaRustHandoffOffersTests/testSentAndReceivedSlotsRemainIndependentAcrossSingleSlotFailures
    WebRTCTransportTests.BelugaRustHandoffOffersTests/testClearRetainsCountersButNewNegotiationResetsThem
    WebRTCTransportTests.BelugaRustHandoffOffersTests/testCanonicalNativeEqualityPreservesOriginalBytesAndValueCopies
    WebRTCTransportTests.BelugaRustHandoffOffersTests/testCanonicalAliasCannotBypassUTF8BoundOrBurnSequenceOnPreparationFailure
    WebRTCTransportTests.BelugaRustHandoffOffersTests/testCommitHeaderAndCurrentPrimaryIdentityAreIndependent
    WebRTCTransportTests.BelugaRustHandoffOffersTests/testReceivePrimaryIsBoundToIncomingEnvelopeNotRetiredReceipt
    WebRTCTransportTests.BelugaRustHandoffOffersTests/testNonfiniteReceiveClockDoesNotMoveEarlyGuardsAheadOfSequenceBurn
    WebRTCTransportTests.BelugaRustHandoffOffersTests/testSignedZeroStorageAndRoundedLargeClockDeadlineMatchOriginalReference
    WebRTCTransportTests.BelugaRustHandoffOffersTests/testNativeSourceSnapshotAgeAndScaledDriftKeepOriginalBounds
    WebRTCTransportTests.BelugaRustHandoffOffersTests/testActualSuppliedCommitUnicodeAndNaNPreservePreconsumeValidityOrdering
    WebRTCTransportTests.BelugaRustHandoffOffersTests/testSeededSendCounterExhaustionRefusesMaxAndClearCannotResetIt
    WebRTCTransportTests.BelugaRustHandoffOffersTests/testSeededReceiverMaxBurnAndIndependentSenderRemainInOriginalParity
    WebRTCTransportTests.BelugaRustHandoffOffersTests/testTokenMaxIssuesOnceAndExhaustionCannotReuseOrResetMintCapacity
    WebRTCTransportTests.BelugaRustHandoffOffersTests/testTokenExhaustionStillExpiresSentAndRetiresReplacedReceived
    WebRTCTransportTests.BelugaRustHandoffOffersTests/testZeroCounterSeedIsTerminalButZeroTokenOnlyRefusesNewMint
    WebRTCTransportTests.BelugaRustHandoffOffersTests/testCopiedOfferBoundaryAcceptsAllLegitimateCustodyTransitions
    WebRTCTransportTests.BelugaRustHandoffOffersTests/testCopiedOfferBoundaryRejectsForgedMintConsumptionRetirementAndCounterReset
  ].freeze
  PHASES = %w[gate-self-tests simulator-signing-self-tests release-hook-self-tests host-release-hook-self-tests mac-producer-contract-tests product-identity product-identity-mutations rust-artifact-validation beluga-core-artifact-validation beluga-core-link beluga-core-mutations mac-discovery mac-tests shared-signaling-tests shared-replay-native-tests shared-replay-authentication-tests shared-replay-durable-tests shared-reconnect-counter-tests shared-pairing-commit-tests shared-handoff-tests simulator-tests simulator-summary simulator-results simulator-signature
              simulator-entitlements pairing-inert-build pairing-tests pairing-summary pairing-results pairing-signature pairing-entitlements rust-discovery rust-tests beluga-core-discovery beluga-core-tests driver-tests driver-sanitizers driver-diagnostic-reader driver-build-1
              driver-build-2 driver-verifier driver-load driver-malformed-bundles].freeze
  PROTECTED_ROOTS = ['/Applications', '/Library', '/System', '/Users/ahmed/Library/Application Support/opensteamer'].freeze

  def self.require!(condition, message)
    raise RuntimeError, message unless condition
  end

  # Source and Swift Testing logs are UTF-8 even under the scrubbed C locale.
  def self.utf8_text(bytes, label)
    require!(bytes.is_a?(String), label + ' is not text')
    text = bytes.dup.force_encoding(Encoding::UTF_8)
    require!(text.valid_encoding?, label + ' is not valid UTF-8')
    text
  end

  def self.exact_keys!(value, keys, label)
    require!(value.is_a?(Hash) && value.keys.sort == keys.sort, "#{label} has an unrecognized field set")
  end

  def self.sha(path)
    Digest::SHA256.file(path).hexdigest
  end

  def self.parse_json(text, label)
    JSON.parse(text)
  rescue JSON::ParserError
    raise RuntimeError, label + ' JSON is malformed (contents redacted)'
  end

  def self.regular!(path)
    stat = File.lstat(path)
    require!(stat.file? && !stat.symlink?, "not a regular non-symlink file: #{path}")
    stat
  end

  def self.resolve_node(path = NODE_ENTRYPOINT)
    require!(File.exist?(path), 'required existing Node executable is unavailable; do not install or upgrade tools')
    resolved = File.realpath(path)
    require!(regular!(resolved).file? && File.executable?(resolved), 'required existing Node executable is not executable')
    resolved
  end

  def self.source_identity(root)
    output, status = Open3.capture2('/usr/bin/git', '-C', root, 'ls-files', '--cached', '--others', '--exclude-standard', '-z')
    require!(status.success?, 'could not inventory source')
    paths = output.split("\0")
    # These ignored binary inputs are consumed by Xcode and must match the tested bytes.
    paths << 'shared/Vendor/LiveKitWebRTC/LiveKitWebRTC.xcframework.zip'
    artifact = File.join(root, 'iOS/opensteamer/Frameworks/OpensteamerAudioTransactionAuthority.xcframework')
    require!(File.directory?(artifact) && !File.symlink?(artifact), 'Rust XCFramework is absent or symlinked')
    Find.find(artifact) do |path|
      require!(!File.symlink?(path), 'Rust XCFramework contains a symlink')
      paths << path.delete_prefix(root + '/') if File.file?(path)
    end
    core_artifact = File.join(root, BELUGA_CORE_ARTIFACT)
    require!(File.directory?(core_artifact) && !File.symlink?(core_artifact) && File.realpath(core_artifact) == core_artifact,
             'Beluga core XCFramework is absent, symlinked or noncanonical')
    Find.find(core_artifact) do |path|
      stat = File.lstat(path)
      require!(!stat.symlink? && (stat.file? || stat.directory?), 'Beluga core XCFramework contains an unsupported node')
      paths << path.delete_prefix(root + '/') if stat.file?
    end
    entries = paths.uniq.sort.map do |relative|
      require!(!relative.start_with?('/') && !relative.split('/').include?('..'), 'unsafe source path')
      path = File.join(root, relative)
      stat = regular!(path)
      [relative, 'file', stat.mode & 0777, sha(path)]
    end
    { 'sha256' => Digest::SHA256.hexdigest(JSON.generate(entries)), 'files' => entries }
  end

  def self.simulator_inventory(root)
    methods = []
    Dir.glob(File.join(root, 'iOS/opensteamer/Tests/**/*.swift')).sort.each do |path|
      text = utf8_text(File.binread(path), 'Simulator test source')
      matches = []
      text.to_enum(:scan, /\b(?:final\s+)?class\s+(\w+)\s*:\s*XCTestCase\b/).each do
        match = Regexp.last_match
        matches << [match[1], match.end(0)]
      end
      matches.each_with_index do |(name, offset), index|
        next unless SIMULATOR_CLASSES.include?(name)
        ending = index + 1 < matches.length ? matches[index + 1][1] : text.length
        text[offset...ending].scan(/\bfunc\s+(test\w+)\s*\(/).each { |entry| methods << name + '/' + entry.first }
      end
    end
    require!(!methods.empty? && methods.uniq.length == methods.length, 'empty or duplicate Simulator source inventory')
    SIMULATOR_CLASSES.each { |name| require!(methods.any? { |id| id.start_with?(name + '/') }, "missing Simulator class: #{name}") }
    (SIMULATOR_PINNED + SIMULATOR_SKIPS).each { |id| require!(methods.include?(id), "missing critical Simulator test: #{id}") }
    methods.sort
  end

  def self.validate_simulator(summary, results, expected, simulator)
    require!(summary.is_a?(Hash) && summary['result'] == 'Passed', 'Simulator result did not pass')
    require!(summary['totalTestCount'] == expected.length && summary['passedTests'] == expected.length - SIMULATOR_SKIPS.length &&
             summary['skippedTests'] == SIMULATOR_SKIPS.length && summary['failedTests'] == 0 &&
             summary['expectedFailures'] == 0 && summary['testFailures'] == [], 'Simulator summary counts are incomplete or disagree')
    configurations = summary['devicesAndConfigurations']
    require!(configurations.is_a?(Array) && configurations.length == 1, 'Simulator result has multiple or missing configurations')
    configuration = configurations.first
    device = configuration['device'] || {}
    require!(device['deviceId'].to_s.casecmp?(simulator) && device['platform'].to_s.include?('Simulator'), 'result belongs to a physical or different destination')
    %w[passedTests skippedTests failedTests expectedFailures].each do |key|
      require!(configuration[key] == summary[key], 'Simulator per-configuration count disagrees')
    end
    cases = []
    walk = lambda do |node|
      if node.is_a?(Hash)
        cases << node if node['nodeType'] == 'Test Case'
        node.each_value { |value| walk.call(value) }
      elsif node.is_a?(Array)
        node.each { |value| walk.call(value) }
      end
    end
    walk.call(results)
    require!(!cases.empty?, 'zero Simulator tests executed')
    observed = cases.map do |node|
      id = node.fetch('nodeIdentifier', '').sub(/\(\)\z/, '').sub(/\AopensteamerTests\//, '')
      require!(expected.include?(id), 'unexpected Simulator test identity')
      wanted = SIMULATOR_SKIPS.include?(id) ? 'Skipped' : 'Passed'
      require!(node['result'] == wanted, "unexpected failure, skip or status for #{id}")
      id
    end
    require!(observed.uniq.length == observed.length && observed.sort == expected.sort, 'missing or duplicate Simulator test results')
    expected - SIMULATOR_SKIPS
  end

  def self.validate_xunit(text, expected)
    cases = REXML::XPath.match(REXML::Document.new(text), '//testcase')
    require!(!cases.empty?, 'zero Mac tests executed')
    observed = cases.map do |entry|
      id = entry.attributes['classname'].to_s + '/' + entry.attributes['name'].to_s
      short = id.split('.').last
      aliases = expected.select { |candidate| candidate.split('.').last == short }
      id = aliases.first if !expected.include?(id) && aliases.length == 1
      require!(expected.include?(id), "unexpected Mac result: #{id}")
      require!(!entry.elements['skipped'] && !entry.elements['failure'] && !entry.elements['error'], "Mac test failed or skipped: #{id}")
      require!(['', 'run', 'passed', 'success'].include?(entry.attributes['status'].to_s.downcase), 'unrecognized Mac test status')
      id
    end
    require!(observed.uniq.length == observed.length && observed.sort == expected.sort, 'missing or duplicate Mac test results')
    expected
  rescue REXML::ParseException
    raise RuntimeError, 'Mac xUnit is malformed (contents redacted)'
  end

  def self.validate_mac_log(text, expected)
    text = utf8_text(text, 'Mac test result')
    lines = text.lines.map(&:chomp)
    starts = lines.each_index.select { |index| lines[index].match?(/\ATest Suite 'Selected tests' started at .+\.\z/) }
    ends = lines.each_index.select { |index| lines[index].match?(/\ATest Suite 'Selected tests' passed at .+\.\z/) }
    require!(starts.length == 1 && ends.length == 1 && starts.first < ends.first, 'missing or duplicate Selected tests suite')
    active = nil
    started = []
    passed = []
    lines.each_with_index do |line, index|
      require!(!line.match?(/\ATest Suite '.+' (failed|skipped) at /), 'Mac suite failed or skipped')
      next unless line.start_with?('Test Case ')
      match = /\ATest Case '-\[([\w.]+) (test\w+)\]' (started\.|(passed|failed|skipped) \([\d.]+ seconds\)\.)\z/.match(line)
      require!(match && index > starts.first && index < ends.first, 'malformed or out-of-suite Mac result')
      id = match[1] + '/' + match[2]
      require!(expected.include?(id), "unexpected Mac test: #{id}")
      if match[3] == 'started.'
        require!(!active && !started.include?(id), 'duplicate or interleaved Mac start')
        started << id
        active = id
      else
        require!(match[4] == 'passed' && active == id && !passed.include?(id), 'Mac test failed, skipped or lacked a matching start')
        passed << id
        active = nil
      end
    end
    require!(!active && !passed.empty? && passed.sort == expected.sort, 'missing Mac result or zero executed tests')
    footer = /\A\s*Executed (\d+) tests?, with (?:(\d+) (?:tests? )?skipped and )?(\d+) failures? \((\d+) unexpected\) in [\d.]+ \([\d.]+\) seconds\z/.match(lines[ends.first + 1].to_s)
    require!(footer && footer[1].to_i == expected.length && footer[2].to_i == 0 && footer[3].to_i == 0 && footer[4].to_i == 0, 'Mac footer has missing, skipped or failed coverage')
    expected
  end

  def self.mac_inventory(text)
    text = utf8_text(text, 'Mac test discovery')
    methods = text.lines.map(&:strip).select { |line| line.match?(/\A\w+\.\w+\/test\w+\z/) }
    require!(!methods.empty? && methods.uniq.length == methods.length, 'empty or duplicate Mac discovery')
    MAC_CLASSES.each { |name| require!(methods.any? { |id| id.start_with?(name + '/') }, "missing Mac test class: #{name}") }
    MAC_PINNED.each { |id| require!(methods.include?(id), "missing critical Mac test: #{id}") }
    methods.select { |id| MAC_CLASSES.include?(id.split('/').first) }.sort
  end

  def self.shared_signaling_inventory(text)
    text = utf8_text(text, 'shared signaling discovery')
    methods = text.lines.map(&:strip).select { |line| line.start_with?(SHARED_SIGNALING_SUITE + '/') }
    require!((1..128).cover?(methods.length) && methods.uniq.length == methods.length &&
             methods.all? { |id| id.match?(/\ARemoteSessionCoreTests\.DurableSignalingClientTests\/\w+\(\)\z/) } &&
             (SHARED_SIGNALING_PINNED - methods).empty?, 'shared signaling discovery is incomplete, malformed or duplicated')
    methods.sort
  end

  def self.shared_replay_source_inventory(root)
    SHARED_REPLAY_FILES.to_h do |suite, relative|
      path = File.join(root, relative)
      regular!(path)
      source = utf8_text(File.binread(path), 'shared replay source')
      name = suite.split('.').last
      methods = source.scan(/^\s*@Test(?:\(.*\))?\s+func (\w+)\s*\(/).flatten
      ids = methods.map { |method| suite + '/' + method + '()' }
      require!(source.scan(/^\s*struct #{Regexp.escape(name)}\s*\{/).length == 1 &&
               (1..128).cover?(ids.length) && ids.uniq.length == ids.length &&
               source.scan(/^\s*@Test\b/).length == ids.length &&
               (SHARED_REPLAY_PINNED.fetch(suite) - ids).empty?,
               'shared replay source inventory is incomplete, malformed or duplicated: ' + suite)
      [suite, ids.sort]
    end
  end

  def self.validate_supported_player_sources(root)
    SUPPORTED_PLAYER_SOURCE_SHA256.each do |relative, expected|
      path = File.join(root, relative)
      require!(File.exist?(path), 'supported player source companion is missing: ' + relative)
      stat = regular!(path)
      require!(File.realpath(path) == path && stat.size <= 2 * 1024 * 1024 &&
               sha(path) == expected, 'supported player reviewed native/reference source changed: ' + relative)
      utf8_text(File.binread(path), 'supported player source companion')
    end
    nil
  end

  def self.supported_player_source_inventory(root)
    validate_supported_player_sources(root)
    SUPPORTED_PLAYER_FILES.map do |suite, relative|
      source = utf8_text(File.binread(File.join(root, relative)), 'supported player native test source')
      name = suite.split('.').last
      methods = source.scan(/^[ \t]*func (test\w+)[ \t]*\(/).flatten
      ids = methods.map { |method| suite + '/' + method }
      require!(source.scan(/^[ \t]*final class #{Regexp.escape(name)}[ \t]*:[ \t]*XCTestCase[ \t]*\{/).length == 1 &&
               ids.uniq.length == ids.length && ids.sort == SUPPORTED_PLAYER_PINNED.fetch(suite).sort,
               'supported player native source inventory is incomplete, malformed or duplicated: ' + suite)
      [suite, ids.sort]
    end.to_h
  end

  def self.validate_batch_a_native_sources(root)
    BATCH_A_NATIVE_SOURCE_SHA256.each do |relative, expected|
      path = File.join(root, relative)
      require!(File.exist?(path), 'Batch A native source companion is missing: ' + relative)
      stat = regular!(path)
      require!(File.realpath(path) == path && stat.size <= 2 * 1024 * 1024 && sha(path) == expected,
               'Batch A reviewed native/reference source changed: ' + relative)
      utf8_text(File.binread(path), 'Batch A native source companion')
    end
    nil
  end

  def self.batch_a_native_source_inventory(root)
    validate_batch_a_native_sources(root)
    BATCH_A_NATIVE_FILES.map do |suite, relative|
      path = File.join(root, relative)
      require!(File.exist?(path), 'Batch A native source companion is missing: ' + relative)
      stat = regular!(path)
      require!(File.realpath(path) == path && stat.size <= 2 * 1024 * 1024,
               'Batch A native source companion is not canonical or is unbounded: ' + relative)
      source = utf8_text(File.binread(path), 'Batch A native test source')
      name = suite.split('.').last
      methods = source.scan(/^[ \t]*func (test\w+)[ \t]*\(/).flatten
      ids = methods.map { |method| suite + '/' + method }
      require!(source.scan(/^[ \t]*final class #{Regexp.escape(name)}[ \t]*:[ \t]*XCTestCase[ \t]*\{/).length == 1 &&
               ids.uniq.length == ids.length && ids.sort == BATCH_A_NATIVE_PINNED.fetch(suite).sort,
               'Batch A native source inventory is incomplete, malformed or duplicated: ' + suite)
      [suite, ids.sort]
    end.to_h
  end

  def self.batch_a_native_inventory(root, text)
    source = batch_a_native_source_inventory(root)
    lines = utf8_text(text, 'Batch A native discovery').lines.map(&:strip)
    source.map do |suite, expected|
      methods = lines.select { |line| line.start_with?(suite + '/') }
      require!(methods.uniq.length == methods.length &&
               methods.all? { |id| id.match?(/\A#{Regexp.escape(suite)}\/test\w+\z/) } &&
               methods.sort == expected,
               'Batch A native discovery differs from exact source inventory: ' + suite)
      [suite, methods.sort]
    end.to_h
  end

  def self.supported_player_inventory(root, text)
    source = supported_player_source_inventory(root)
    lines = utf8_text(text, 'supported player native discovery').lines.map(&:strip)
    source.map do |suite, expected|
      methods = lines.select { |line| line.start_with?(suite + '/') }
      require!(methods.uniq.length == methods.length &&
               methods.all? { |id| id.match?(/\A#{Regexp.escape(suite)}\/test\w+\z/) } &&
               methods.sort == expected,
               'supported player native discovery differs from exact source inventory: ' + suite)
      [suite, methods.sort]
    end.to_h
  end

  def self.shared_replay_inventory(root, text)
    source = shared_replay_source_inventory(root)
    lines = utf8_text(text, 'shared replay discovery').lines.map(&:strip)
    source.to_h do |suite, expected|
      methods = lines.select { |line| line.start_with?(suite + '/') }
      require!(methods.uniq.length == methods.length &&
               methods.all? { |id| id.match?(/\A#{Regexp.escape(suite)}\/\w+\(\)\z/) } &&
               methods.sort == expected,
               'shared replay discovery differs from exact source inventory: ' + suite)
      [suite, methods.sort]
    end
  end

  def self.shared_reconnect_counter_source_inventory(root)
    path = File.join(root, SHARED_RECONNECT_COUNTER_FILE)
    regular!(path)
    source = utf8_text(File.binread(path), 'shared reconnect counter source')
    name = SHARED_RECONNECT_COUNTER_SUITE.split('.').last
    methods = source.scan(/^[ \t]*@Test(?:\(.*\))?[ \t]+func (\w+)[ \t]*\(/).flatten
    ids = methods.map { |method| SHARED_RECONNECT_COUNTER_SUITE + '/' + method + '()' }
    require!(source.bytesize <= 2 * 1024 * 1024 &&
             source.scan(/^\s*struct #{Regexp.escape(name)}\s*\{/).length == 1 &&
             (1..128).cover?(ids.length) && ids.uniq.length == ids.length &&
             source.scan(/^\s*@Test\b/).length == ids.length &&
             (SHARED_RECONNECT_COUNTER_PINNED - ids).empty?,
             'shared reconnect counter source inventory is incomplete, malformed or duplicated')
    ids.sort
  end

  def self.shared_reconnect_counter_inventory(root, text)
    expected = shared_reconnect_counter_source_inventory(root)
    suite = SHARED_RECONNECT_COUNTER_SUITE
    methods = utf8_text(text, 'shared reconnect counter discovery').lines.map(&:strip).select { |line| line.start_with?(suite + '/') }
    require!(methods.uniq.length == methods.length &&
             methods.all? { |id| id.match?(/\A#{Regexp.escape(suite)}\/\w+\(\)\z/) } &&
             methods.sort == expected,
             'shared reconnect counter discovery differs from exact source inventory')
    methods.sort
  end

  def self.validate_shared_pairing_commit_sources(root)
    SHARED_PAIRING_COMMIT_SOURCE_SHA256.merge(SHARED_PAIRING_COMMIT_MAC_SOURCE_SHA256).each do |relative, expected|
      path = File.join(root, relative)
      require!(File.exist?(path), 'pairing commit source companion is missing: ' + relative)
      stat = regular!(path)
      require!(File.realpath(path) == path && stat.size <= 2 * 1024 * 1024 &&
               sha(path) == expected, 'pairing commit reviewed native/reference/caller source changed: ' + relative)
      utf8_text(File.binread(path), 'pairing commit source companion')
    end
    nil
  end

  def self.shared_pairing_commit_source_inventory(root)
    path = File.join(root, SHARED_PAIRING_COMMIT_FILE)
    regular!(path)
    source = utf8_text(File.binread(path), 'shared pairing commit source')
    name = SHARED_PAIRING_COMMIT_SUITE.split('.').last
    methods = source.scan(/^[ \t]*@Test(?:\(.*\))?[ \t]+func (\w+)[ \t]*\(/).flatten
    ids = methods.map { |method| SHARED_PAIRING_COMMIT_SUITE + '/' + method + '()' }
    require!(source.bytesize <= 2 * 1024 * 1024 &&
             source.scan(/^\s*struct #{Regexp.escape(name)}\s*\{/).length == 1 &&
             (1..128).cover?(ids.length) && ids.uniq.length == ids.length &&
             source.scan(/^\s*@Test\b/).length == ids.length &&
             ids.sort == SHARED_PAIRING_COMMIT_PINNED.sort,
             'shared pairing commit source inventory is incomplete, malformed or duplicated')
    validate_shared_pairing_commit_sources(root)
    ids.sort
  end

  def self.shared_pairing_commit_inventory(root, text)
    expected = shared_pairing_commit_source_inventory(root)
    suite = SHARED_PAIRING_COMMIT_SUITE
    methods = utf8_text(text, 'shared pairing commit discovery').lines.map(&:strip).select { |line| line.start_with?(suite + '/') }
    require!(methods.uniq.length == methods.length &&
             methods.all? { |id| id.match?(/\A#{Regexp.escape(suite)}\/\w+\(\)\z/) } &&
             methods.sort == expected,
             'shared pairing commit discovery differs from exact source inventory')
    methods.sort
  end

  def self.shared_handoff_inventory(text)
    methods = utf8_text(text, 'shared handoff discovery').lines.map(&:strip).select do |line|
      SHARED_HANDOFF_CLASSES.any? { |name| line.start_with?(name + '/') }
    end
    require!(!methods.empty? && methods.uniq.length == methods.length &&
             methods.all? { |id| id.match?(/\AWebRTCTransportTests\.\w+\/test\w+\z/) },
             'shared handoff discovery is empty, malformed or duplicated')
    SHARED_HANDOFF_CLASSES.each { |name| require!(methods.any? { |id| id.start_with?(name + '/') }, 'missing shared handoff class: ' + name) }
    SHARED_HANDOFF_PINNED.each { |id| require!(methods.include?(id), 'missing critical shared handoff test: ' + id) }
    methods.sort
  end

  # Exact pinned Swift Testing console format. Starts/passes may interleave,
  # but each discovered method must start once before passing once in one suite.
  def self.validate_shared_signaling(text, expected)
    text = utf8_text(text, 'shared signaling result')
    require!(text.bytesize <= 2 * 1024 * 1024 && (1..128).cover?(expected.length) &&
             expected.uniq.length == expected.length &&
             expected.all? { |id| id.match?(/\ARemoteSessionCoreTests\.DurableSignalingClientTests\/\w+\(\)\z/) },
             'shared signaling result bounds or expected inventory are invalid')
    lines = text.lines.map(&:chomp)
    require!(lines.length <= 4096, 'shared signaling result exceeds line bound')
    run_starts = []
    suite_starts = []
    suite_passes = []
    footers = []
    starts = {}
    passes = {}
    lines.each_with_index do |line, index|
      if line == '◇ Test run started.'
        run_starts << index
      elsif line == '◇ Suite DurableSignalingClientTests started.'
        suite_starts << index
      elsif line.match?(/\A✔ Suite DurableSignalingClientTests passed after \d+(?:\.\d+)? seconds\.\z/)
        suite_passes << index
      elsif (match = /\A✔ Test run with (\d+) tests in (\d+) suite passed after \d+(?:\.\d+)? seconds\.\z/.match(line))
        footers << [index, match[1].to_i, match[2].to_i]
      elsif (match = /\A◇ Test (\w+\(\)) started\.\z/.match(line))
        id = SHARED_SIGNALING_SUITE + '/' + match[1]
        require!(expected.include?(id) && !starts.key?(id), 'shared signaling start is unexpected or duplicated')
        starts[id] = index
      elsif (match = /\A✔ Test (\w+\(\)) passed after \d+(?:\.\d+)? seconds\.\z/.match(line))
        id = SHARED_SIGNALING_SUITE + '/' + match[1]
        require!(expected.include?(id) && starts.key?(id) && starts[id] < index && !passes.key?(id),
                 'shared signaling pass is unexpected, duplicated or lacks a matching start')
        passes[id] = index
      else
        require!(!line.match?(/\A(?:\S+\s+)?(?:Test|Suite)\b/),
                 'shared signaling result is malformed, failed, skipped or belongs to another suite')
      end
    end
    require!(run_starts.length == 1 && suite_starts.length == 1 && suite_passes.length == 1 && footers.length == 1 &&
             run_starts.first < suite_starts.first && suite_starts.first < suite_passes.first &&
             suite_passes.first < footers.first[0] && footers.first.drop(1) == [expected.length, 1],
             'shared signaling suite/run footer is missing, duplicated, out of order or disagrees')
    require!(starts.keys.sort == expected.sort && passes.keys.sort == expected.sort &&
             (starts.values + passes.values).all? { |index| index > suite_starts.first && index < suite_passes.first },
             'shared signaling cases are missing or outside the exact suite')
    expected.sort
  end

  def self.validate_shared_replay(text, expected, suite)
    require!(SHARED_REPLAY_FILES.key?(suite), 'shared replay result names an unreviewed suite')
    name = suite.split('.').last
    text = utf8_text(text, 'shared replay result')
    require!(text.bytesize <= 2 * 1024 * 1024 && (1..128).cover?(expected.length) &&
             expected.uniq.length == expected.length &&
             (SHARED_REPLAY_PINNED.fetch(suite) - expected).empty? &&
             expected.all? { |id| id.match?(/\A#{Regexp.escape(suite)}\/\w+\(\)\z/) },
             'shared replay result bounds or expected inventory are invalid')
    lines = text.lines.map(&:chomp)
    require!(lines.length <= 4096, 'shared replay result exceeds line bound')
    run_starts = []
    suite_starts = []
    suite_passes = []
    footers = []
    starts = {}
    passes = {}
    lines.each_with_index do |line, index|
      if line == '◇ Test run started.'
        run_starts << index
      elsif line == "◇ Suite #{name} started."
        suite_starts << index
      elsif line.match?(/\A✔ Suite #{Regexp.escape(name)} passed after \d+(?:\.\d+)? seconds\.\z/)
        suite_passes << index
      elsif (match = /\A✔ Test run with (\d+) tests in (\d+) suite passed after \d+(?:\.\d+)? seconds\.\z/.match(line))
        footers << [index, match[1].to_i, match[2].to_i]
      elsif (match = /\A◇ Test (\w+\(\)) started\.\z/.match(line))
        id = suite + '/' + match[1]
        require!(expected.include?(id) && !starts.key?(id), 'shared replay start is unexpected or duplicated')
        starts[id] = index
      elsif (match = /\A✔ Test (\w+\(\)) passed after \d+(?:\.\d+)? seconds\.\z/.match(line))
        id = suite + '/' + match[1]
        require!(expected.include?(id) && starts.key?(id) && starts[id] < index && !passes.key?(id),
                 'shared replay pass is unexpected, duplicated or lacks a matching start')
        passes[id] = index
      else
        require!(!line.match?(/\A(?:\S+\s+)?(?:Test|Suite)\b/),
                 'shared replay result is malformed, failed, skipped or belongs to another suite')
      end
    end
    require!(run_starts.length == 1 && suite_starts.length == 1 && suite_passes.length == 1 && footers.length == 1 &&
             run_starts.first < suite_starts.first && suite_starts.first < suite_passes.first &&
             suite_passes.first < footers.first[0] && footers.first.drop(1) == [expected.length, 1],
             'shared replay suite/run footer is missing, duplicated, out of order or disagrees')
    require!(starts.keys.sort == expected.sort && passes.keys.sort == expected.sort &&
             (starts.values + passes.values).all? { |index| index > suite_starts.first && index < suite_passes.first },
             'shared replay cases are missing or outside the exact suite')
    expected.sort
  end

  def self.validate_shared_reconnect_counter(text, expected)
    suite = SHARED_RECONNECT_COUNTER_SUITE
    name = suite.split('.').last
    text = utf8_text(text, 'shared reconnect counter result')
    require!(text.bytesize <= 2 * 1024 * 1024 && (1..128).cover?(expected.length) &&
             expected.uniq.length == expected.length &&
             (SHARED_RECONNECT_COUNTER_PINNED - expected).empty? &&
             expected.all? { |id| id.match?(/\A#{Regexp.escape(suite)}\/\w+\(\)\z/) },
             'shared reconnect counter result bounds or expected inventory are invalid')
    lines = text.lines.map(&:chomp)
    require!(lines.length <= 4096, 'shared reconnect counter result exceeds line bound')
    run_starts = []
    suite_starts = []
    suite_passes = []
    footers = []
    starts = {}
    passes = {}
    lines.each_with_index do |line, index|
      if line == '◇ Test run started.'
        run_starts << index
      elsif line == "◇ Suite #{name} started."
        suite_starts << index
      elsif line.match?(/\A✔ Suite #{Regexp.escape(name)} passed after \d+(?:\.\d+)? seconds\.\z/)
        suite_passes << index
      elsif (match = /\A✔ Test run with (\d+) tests in (\d+) suite passed after \d+(?:\.\d+)? seconds\.\z/.match(line))
        footers << [index, match[1].to_i, match[2].to_i]
      elsif (match = /\A◇ Test (\w+\(\)) started\.\z/.match(line))
        id = suite + '/' + match[1]
        require!(expected.include?(id) && !starts.key?(id), 'shared reconnect counter start is unexpected or duplicated')
        starts[id] = index
      elsif (match = /\A✔ Test (\w+\(\)) passed after \d+(?:\.\d+)? seconds\.\z/.match(line))
        id = suite + '/' + match[1]
        require!(expected.include?(id) && starts.key?(id) && starts[id] < index && !passes.key?(id),
                 'shared reconnect counter pass is unexpected, duplicated or lacks a matching start')
        passes[id] = index
      else
        require!(!line.match?(/\A(?:\S+\s+)?(?:Test|Suite)\b/),
                 'shared reconnect counter result is malformed, failed, skipped or belongs to another suite')
      end
    end
    require!(run_starts.length == 1 && suite_starts.length == 1 && suite_passes.length == 1 && footers.length == 1 &&
             run_starts.first < suite_starts.first && suite_starts.first < suite_passes.first &&
             suite_passes.first < footers.first[0] && footers.first.drop(1) == [expected.length, 1],
             'shared reconnect counter suite/run footer is missing, duplicated, out of order or disagrees')
    require!(starts.keys.sort == expected.sort && passes.keys.sort == expected.sort &&
             (starts.values + passes.values).all? { |index| index > suite_starts.first && index < suite_passes.first },
             'shared reconnect counter cases are missing or outside the exact suite')
    expected.sort
  end

  def self.validate_shared_pairing_commit(text, expected)
    suite = SHARED_PAIRING_COMMIT_SUITE
    name = suite.split('.').last
    text = utf8_text(text, 'shared pairing commit result')
    require!(text.bytesize <= 2 * 1024 * 1024 && (1..128).cover?(expected.length) &&
             expected.uniq.length == expected.length &&
             expected.sort == SHARED_PAIRING_COMMIT_PINNED.sort &&
             expected.all? { |id| id.match?(/\A#{Regexp.escape(suite)}\/\w+\(\)\z/) },
             'shared pairing commit result bounds or expected inventory are invalid')
    lines = text.lines.map(&:chomp)
    require!(lines.length <= 4096, 'shared pairing commit result exceeds line bound')
    run_starts = []
    suite_starts = []
    suite_passes = []
    footers = []
    starts = {}
    passes = {}
    lines.each_with_index do |line, index|
      if line == '◇ Test run started.'
        run_starts << index
      elsif line == "◇ Suite #{name} started."
        suite_starts << index
      elsif line.match?(/\A✔ Suite #{Regexp.escape(name)} passed after \d+(?:\.\d+)? seconds\.\z/)
        suite_passes << index
      elsif (match = /\A✔ Test run with (\d+) tests in (\d+) suite passed after \d+(?:\.\d+)? seconds\.\z/.match(line))
        footers << [index, match[1].to_i, match[2].to_i]
      elsif (match = /\A◇ Test (\w+\(\)) started\.\z/.match(line))
        id = suite + '/' + match[1]
        require!(expected.include?(id) && !starts.key?(id), 'shared pairing commit start is unexpected or duplicated')
        starts[id] = index
      elsif (match = /\A✔ Test (\w+\(\)) passed after \d+(?:\.\d+)? seconds\.\z/.match(line))
        id = suite + '/' + match[1]
        require!(expected.include?(id) && starts.key?(id) && starts[id] < index && !passes.key?(id),
                 'shared pairing commit pass is unexpected, duplicated or lacks a matching start')
        passes[id] = index
      else
        require!(!line.match?(/\A(?:\S+\s+)?(?:Test|Suite)\b/),
                 'shared pairing commit result is malformed, failed, skipped or belongs to another suite')
      end
    end
    require!(run_starts.length == 1 && suite_starts.length == 1 && suite_passes.length == 1 && footers.length == 1 &&
             run_starts.first < suite_starts.first && suite_starts.first < suite_passes.first &&
             suite_passes.first < footers.first[0] && footers.first.drop(1) == [expected.length, 1],
             'shared pairing commit suite/run footer is missing, duplicated, out of order or disagrees')
    require!(starts.keys.sort == expected.sort && passes.keys.sort == expected.sort &&
             (starts.values + passes.values).all? { |index| index > suite_starts.first && index < suite_passes.first },
             'shared pairing commit cases are missing or outside the exact suite')
    expected.sort
  end

  def self.rust_inventory(text)
    methods = text.lines.map { |line| /\A([\w:]+): test\s*\z/.match(line)&.[](1) }.compact
    require!(!methods.empty? && methods.uniq.length == methods.length, 'empty or duplicate Rust discovery')
    RUST_PINNED.each { |id| require!(methods.include?(id), "missing critical Rust test: #{id}") }
    methods.sort
  end

  def self.beluga_core_inventory(text)
    methods = utf8_text(text, 'Beluga core discovery').lines.map { |line| /\A([\w:]+): test\s*\z/.match(line)&.[](1) }.compact
    require!(!methods.empty? && methods.uniq.length == methods.length, 'empty or duplicate Beluga core discovery')
    BELUGA_CORE_PINNED.each { |id| require!(methods.include?(id), "missing critical Beluga core test: #{id}") }
    methods.sort
  end

  def self.validate_rust(text, expected)
    matches = text.lines.map { |line| /\A\s*test ([\w:]+) \.\.\. (ok|FAILED|ignored)\s*\z/.match(line) }.compact
    require!(matches.all? { |match| match[2] == 'ok' }, 'Rust test failed or was ignored')
    observed = matches.map { |match| match[1] }
    require!(!observed.empty? && observed.uniq.length == observed.length && observed.sort == expected.sort, 'missing, duplicate or zero Rust results')
    summaries = text.scan(/test result: ok\. (\d+) passed; (\d+) failed; (\d+) ignored; (\d+) measured; (\d+) filtered out;/)
    require!(!summaries.empty? && summaries.all? { |entry| entry.drop(1).all? { |number| number.to_i == 0 } } &&
             summaries.sum { |entry| entry[0].to_i } == expected.length, 'Rust result footer disagrees or contains ignored coverage')
    expected
  end

  def self.c_inventory(root)
    %w[Core Driver].map do |kind|
      name = kind == 'Core' ? 'OpensteamerVirtualAudioCoreTests.c' : 'OpensteamerVirtualMicrophoneDriverTests.c'
      text = File.read(File.join(root, 'macOS/VirtualAudioDriver/tests', name))
      array = text[/\}\s*tests\[\]\s*=\s*\{(.*?)\n\s*\};/m, 1]
      require!(array, 'missing native C behavioral inventory')
      names = array.scan(/\{\s*"([^"]+)"\s*,/).flatten
      require!(!names.empty? && names.uniq.length == names.length, 'empty or duplicate C behavioral inventory')
      label = kind == 'Core' ? 'core invariant' : 'driver interface'
      C_PINNED.fetch(label).each { |name| require!(names.include?(name), 'missing critical native C test: ' + name) }
      { 'kind' => label, 'names' => names }
    end
  end

  def self.validate_c(text, inventories, repetitions = 1)
    expected = inventories.flat_map do |inventory|
      names = inventory.fetch('names')
      names.map { |name| 'PASS: ' + name } + ["PASS: #{names.length}/#{names.length} production #{inventory.fetch('kind')} tests"]
    end * repetitions
    observed = text.lines.map(&:chomp).select { |line| line.start_with?('PASS: ') }
    require!(observed == expected, 'C behavioral results are missing, duplicated or incomplete')
    inventories
  end

  def self.tree_identity(path)
    entries = []
    Find.find(path) do |entry|
      stat = File.lstat(entry)
      require!(!stat.symlink? && (stat.file? || stat.directory?), 'artifact tree contains an unsupported node')
      relative = entry == path ? '.' : entry.delete_prefix(path + '/')
      entries << [relative, stat.directory? ? 'directory' : 'file', stat.mode & 0777, stat.file? ? sha(entry) : nil]
    end
    require!(entries.any? { |entry| entry[1] == 'file' }, 'artifact tree is empty')
    Digest::SHA256.hexdigest(JSON.generate(entries.sort))
  end

  # Pairing owns a distinct zero-skip inventory. Never broaden the ordinary
  # app-root Simulator suite or borrow its physical exclusions.
  def self.pairing_inventory(root)
    require!(PAIRING_PINNED.length == 108 && PAIRING_PINNED.uniq.length == 108 &&
             PAIRING_FILES.keys == PAIRING_BY_CLASS.keys && PAIRING_FILES.keys == PAIRING_SOURCE_SHA256.keys,
             'pairing reviewed inventory is malformed')
    observed = []
    PAIRING_FILES.each do |name, relative|
      path = File.join(root, relative)
      bytes = pairing_owned_bytes(path, 4 * 1024 * 1024)
      require!(Digest::SHA256.hexdigest(bytes) == PAIRING_SOURCE_SHA256.fetch(name), 'pairing reviewed source changed: ' + name)
      text = utf8_text(bytes, 'pairing source')
      classes = text.scan(/\b(?:final\s+)?class\s+(\w+)\s*:\s*XCTestCase\b/).flatten
      methods = text.scan(/\bfunc\s+(test\w+)\s*\(/).flatten.sort
      require!(classes == [name] && methods == PAIRING_BY_CLASS.fetch(name).sort && methods.uniq == methods,
               'pairing source inventory is missing, duplicated or unexpected: ' + name)
      observed.concat(methods.map { |method| name + '/' + method })
    end
    require!(observed.sort == PAIRING_PINNED, 'pairing source inventory differs from reviewed names')
    observed.sort
  end

  def self.validate_pairing(summary, results, expected, simulator)
    require!(expected == PAIRING_PINNED && expected.length == 108 && expected.uniq.length == 108, 'pairing expected inventory changed')
    require!(summary.is_a?(Hash) && summary['result'] == 'Passed' &&
             summary.values_at('totalTestCount', 'passedTests', 'skippedTests', 'failedTests', 'expectedFailures', 'testFailures') ==
             [108, 108, 0, 0, 0, []], 'pairing summary requires exactly 108 passes and zero skips/failures')
    configurations = summary['devicesAndConfigurations']
    require!(configurations.is_a?(Array) && configurations.length == 1 && configurations.first.is_a?(Hash), 'pairing requires one configuration')
    configuration = configurations.first
    device = configuration['device']
    require!(device.is_a?(Hash) && device['deviceId'].to_s.casecmp?(simulator) && device['platform'].to_s.include?('Simulator'),
             'pairing belongs to a physical or different destination')
    %w[passedTests skippedTests failedTests expectedFailures].each do |key|
      require!(configuration[key] == summary[key], 'pairing per-configuration counts disagree')
    end
    require!(results.is_a?(Hash), 'pairing result tree is malformed')
    cases = []
    walk = lambda do |node|
      if node.is_a?(Hash)
        cases << node if node['nodeType'] == 'Test Case'
        node.each_value { |value| walk.call(value) }
      elsif node.is_a?(Array)
        node.each { |value| walk.call(value) }
      end
    end
    walk.call(results)
    observed = cases.map do |node|
      id = node.fetch('nodeIdentifier', '').sub(/\(\)\z/, '').sub(/\AopensteamerTests\//, '')
      require!(expected.include?(id) && node['result'] == 'Passed', 'pairing unexpected, failed or skipped case: ' + id)
      id
    end
    require!(observed.length == 108 && observed.uniq.length == 108 && observed.sort == expected,
             'pairing cases are absent, duplicated, extra or unexecuted')
    observed.sort
  end

  def self.pairing_stat_identity(stat)
    [stat.dev, stat.ino, stat.size, stat.uid, stat.nlink, stat.mode, stat.mtime.to_r, stat.ctime.to_r]
  end

  def self.pairing_owned_bytes(path, maximum)
    require!(File.realpath(path) == path, 'pairing evidence path is noncanonical: ' + path)
    before = File.lstat(path)
    require!(before.file? && !before.symlink? && before.uid == Process.uid && before.nlink == 1 &&
             before.size.positive? && before.size <= maximum, 'pairing evidence file is unsafe, empty or unbounded: ' + path)
    bytes = File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
      opened = file.stat
      require!(pairing_stat_identity(opened) == pairing_stat_identity(before), 'pairing file identity changed at open')
      contents = file.read(maximum + 1)
      require!(contents.bytesize == before.size && pairing_stat_identity(file.stat) == pairing_stat_identity(opened),
               'pairing file identity changed during read')
      contents
    end
    require!(pairing_stat_identity(File.lstat(path)) == pairing_stat_identity(before) && Digest::SHA256.hexdigest(bytes) == sha(path),
             'pairing file identity changed after read')
    bytes
  rescue SystemCallError
    raise RuntimeError, 'pairing evidence file is absent or inaccessible: ' + path
  end

  PAIRING_PROCESS_KEYS = %w[schema phase pid pgid argvSHA256 startedAtNanoseconds finishedAtNanoseconds timeoutSeconds
                            leaderReaped leaderExitStatus leaderSignal groupAbsent absenceProof termSent killSent completion].freeze
  PAIRING_OBJECT_KEYS = %w[device inode size uid links mode modifiedAtNanoseconds changedAtNanoseconds].freeze

  def self.validate_pairing_process(record, name, argv, latest_nanoseconds, timeout_limit)
    exact_keys!(record, PAIRING_PROCESS_KEYS, 'pairing process teardown proof')
    require!(record['schema'] == 'beluga.pairing.process-group.v1' && record['phase'] == name &&
             PAIRING_PHASE_TIMEOUTS.key?(name) && record['argvSHA256'] == Digest::SHA256.hexdigest(JSON.generate(argv)),
             'pairing process proof belongs to a different phase or command')
    require!(%w[pid pgid startedAtNanoseconds finishedAtNanoseconds].all? do |key|
      record[key].is_a?(Integer) && record[key].positive? && record[key] < 2**63
    end, 'pairing process identity or time bounds are malformed')
    duration = record['finishedAtNanoseconds'] - record['startedAtNanoseconds']
    timeout = record['timeoutSeconds']
    require!(record['pid'] == record['pgid'] && record['pid'] < 2**31 && duration >= 0 &&
             record['finishedAtNanoseconds'] <= latest_nanoseconds && timeout.is_a?(Numeric) && timeout.finite? &&
             timeout.positive? && timeout <= [PAIRING_PHASE_TIMEOUTS.fetch(name), timeout_limit].min &&
             duration <= ((timeout + 3.0) * 1_000_000_000).ceil,
             'pairing process deadline or owned leader/group identity changed')
    require!(record.values_at('leaderReaped', 'leaderExitStatus', 'leaderSignal', 'groupAbsent', 'absenceProof', 'completion') ==
             [true, 0, nil, true, 'ESRCH', 'success'] &&
             [true, false].include?(record['termSent']) && [true, false].include?(record['killSent']) &&
             (!record['killSent'] || record['termSent']), 'pairing process lacks successful exact reap and ESRCH teardown')
    record
  end

  def self.validate_pairing_processes(records, expected_commands, latest_nanoseconds, timeout_limit)
    require!(records.is_a?(Array) && records.map { |record| record.is_a?(Hash) && record['phase'] } == PAIRING_PHASE_TIMEOUTS.keys,
             'pairing process proofs are missing, duplicated or reordered')
    records.each { |record| validate_pairing_process(record, record['phase'], expected_commands.fetch(record['phase']), latest_nanoseconds, timeout_limit) }
    require!(records.map { |record| record['pgid'] }.uniq.length == 6 &&
             records.each_cons(2).all? { |before, after| before['finishedAtNanoseconds'] <= after['startedAtNanoseconds'] } &&
             records.last['finishedAtNanoseconds'] - records.first['startedAtNanoseconds'] <= PAIRING_OVERALL_SECONDS * 1_000_000_000,
             'pairing process group ordering or overall deadline changed')
    records
  end

  def self.pairing_object_metadata(path)
    before = File.lstat(path)
    bytes = pairing_owned_bytes(path, PAIRING_PROOF_FILES.fetch('OpensteamerApp.o'))
    after = File.lstat(path)
    require!(pairing_stat_identity(before) == pairing_stat_identity(after) && bytes.bytesize == before.size,
             'pairing App root object changed during metadata collection')
    { 'device' => before.dev, 'inode' => before.ino, 'size' => before.size, 'uid' => before.uid,
      'links' => before.nlink, 'mode' => before.mode, 'modifiedAtNanoseconds' => (before.mtime.to_r * 1_000_000_000).to_i,
      'changedAtNanoseconds' => (before.ctime.to_r * 1_000_000_000).to_i }
  rescue SystemCallError
    raise RuntimeError, 'pairing App root object metadata is absent or inaccessible'
  end

  def self.validate_pairing_object_metadata(record, bytes, build_process = nil, retained = false)
    exact_keys!(record, PAIRING_OBJECT_KEYS, 'pairing App root object metadata')
    require!(PAIRING_OBJECT_KEYS.all? { |key| record[key].is_a?(Integer) && record[key] >= 0 && record[key] < 2**64 } &&
             record['inode'].positive? && record['links'] == 1 && record['uid'] == Process.uid &&
             record['mode'] < 2**16 && (record['mode'] & 0170000) == 0100000 &&
             record['size'] == bytes.bytesize && record['size'].positive? && record['size'] <= PAIRING_PROOF_FILES.fetch('OpensteamerApp.o') &&
             %w[modifiedAtNanoseconds changedAtNanoseconds].all? { |key| record[key].positive? && record[key] < 2**63 } &&
             (!retained || (record['mode'] & 0777) == 0600), 'pairing App root object metadata is unsafe or unbounded')
    if build_process
      start = build_process.fetch('startedAtNanoseconds'); finish = build_process.fetch('finishedAtNanoseconds')
      require!(%w[modifiedAtNanoseconds changedAtNanoseconds].all? { |key| record[key] >= start && record[key] <= finish },
               'pairing App root object is stale or outside the actual inert build wall interval')
    end
    record
  end

  def self.pairing_compiler_paths(scratch)
    base = File.join(scratch, 'DerivedData/Build/Intermediates.noindex/opensteamer.build/Debug-iphonesimulator/opensteamer.build/Objects-normal/arm64')
    PAIRING_PROOF_FILES.keys.first(3).map { |name| [name, File.join(base, name)] }.to_h
  end

  # Only actual fresh xcodebuild compiler output admits test launch. All inputs
  # here are subsequently retained and recomputed by receipt verification.
  def self.pairing_compiler_proof(root, scratch, developer, tools, build_text, bytes_by_name, build_process, original_object_metadata, retained_object_metadata = nil)
    exact_keys!(bytes_by_name, PAIRING_PROOF_FILES.keys.first(3), 'pairing compiler files')
    app_root = File.join(root, PAIRING_APP_ROOT)
    require!(Digest::SHA256.hexdigest(pairing_owned_bytes(app_root, 1024 * 1024)) == PAIRING_APP_ROOT_SHA256,
             'pairing reviewed inert App root changed')
    swiftc = File.join(developer, 'Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc')
    require!(tools[swiftc] == sha(swiftc), 'pairing actual compiler identity changed')
    paths = pairing_compiler_paths(scratch)
    text = utf8_text(build_text, 'pairing inert build result')
    drivers = text.lines.each_with_object([]) do |line, matches|
      next unless line.strip.start_with?('builtin-SwiftDriver -- ')
      tokens = Shellwords.shellsplit(line.strip)
      next unless tokens[0, 3] == ['builtin-SwiftDriver', '--', swiftc]
      indices = tokens.each_index.select { |index| tokens[index] == '-module-name' }
      next unless indices.length == 1 && tokens[indices.first + 1] == 'opensteamer'
      matches << [line, tokens]
    end
    require!(drivers.length == 1, 'pairing needs a unique fresh actual app SwiftDriver before launch')
    driver, tokens = drivers.first
    definitions = []
    tokens.each_with_index do |token, index|
      definitions << tokens[index + 1] if token == '-D'
      definitions << token[2..-1] if token.start_with?('-D') && token != '-D'
    end
    targets = tokens.each_index.select { |index| tokens[index] == '-target' }
    maps = tokens.each_index.select { |index| tokens[index] == '-output-file-map' }
    require!(definitions.count('DEBUG') == 1 && definitions.count('OPENSTEAMER_UPDATE_VALIDATION_HOST') == 1 &&
             targets.length == 1 && tokens[targets.first + 1] == 'arm64-apple-ios17.0-simulator' && maps.length == 1 &&
             tokens[maps.first + 1] == paths.fetch('opensteamer-OutputFileMap.json') &&
             tokens.count('@' + paths.fetch('Beluga.SwiftFileList')) == 1 && tokens.include?('-c'),
             'pairing actual app compiler does not prove inert definitions/target/input/output')
    marker = 'SwiftCompile normal arm64 ' + app_root + " (in target 'opensteamer' from project 'opensteamer')"
    require!(text.lines.count { |line| line.strip == marker } == 1 &&
             text.lines.count { |line| line.strip == '** BUILD SUCCEEDED **' } == 1 && !text.include?('** BUILD FAILED **'),
             'pairing requires fresh successful App root compilation; incremental-only proof refuses before launch')
    inputs = utf8_text(bytes_by_name.fetch('Beluga.SwiftFileList'), 'pairing file list').lines.flat_map { |line| Shellwords.shellsplit(line) }
    require!(inputs.count(app_root) == 1, 'pairing file list must bind exact App root once')
    map = parse_json(utf8_text(bytes_by_name.fetch('opensteamer-OutputFileMap.json'), 'pairing output map'), 'pairing output map')
    require!(map.is_a?(Hash) && map[app_root].is_a?(Hash) && map[app_root]['object'] == paths.fetch('OpensteamerApp.o'),
             'pairing output map must bind exact App root object')
    exact_keys!(build_process, PAIRING_PROCESS_KEYS, 'pairing inert build process')
    require!(build_process['phase'] == 'pairing-inert-build' && build_process.values_at('leaderReaped', 'leaderExitStatus', 'leaderSignal', 'groupAbsent', 'absenceProof', 'completion') ==
             [true, 0, nil, true, 'ESRCH', 'success'] &&
             %w[startedAtNanoseconds finishedAtNanoseconds].all? { |key| build_process[key].is_a?(Integer) && build_process[key].positive? } &&
             build_process['startedAtNanoseconds'] <= build_process['finishedAtNanoseconds'], 'pairing inert build lacks a bounded successful process interval')
    validate_pairing_object_metadata(original_object_metadata, bytes_by_name.fetch('OpensteamerApp.o'), build_process)
    validate_pairing_object_metadata(retained_object_metadata, bytes_by_name.fetch('OpensteamerApp.o'), nil, true) if retained_object_metadata
    records = paths.map do |name, path|
      bytes = bytes_by_name.fetch(name)
      require!(bytes.is_a?(String) && bytes.bytesize.positive? && bytes.bytesize <= PAIRING_PROOF_FILES.fetch(name), 'pairing compiler input/output is empty or unbounded')
      { 'path' => path, 'retainedPath' => 'pairing-inert-root-contract/' + name,
        'byteCount' => bytes.bytesize, 'sha256' => Digest::SHA256.hexdigest(bytes) }
    end
    { 'schema' => 'beluga.pairing-inert-compiler.v1', 'appRoot' => PAIRING_APP_ROOT, 'appRootSHA256' => PAIRING_APP_ROOT_SHA256,
      'compiler' => swiftc, 'compilerSHA256' => tools.fetch(swiftc), 'target' => 'arm64-apple-ios17.0-simulator',
      'buildSettingArgv' => PAIRING_INERT_CONDITIONS, 'requiredDefinitions' => %w[DEBUG OPENSTEAMER_UPDATE_VALIDATION_HOST],
      'proofPhase' => 'pairing-inert-build', 'proofLogSHA256' => Digest::SHA256.hexdigest(build_text), 'compileMarker' => marker,
      'driverPath' => 'pairing-inert-root-contract/app-swift-driver.txt', 'driverSHA256' => Digest::SHA256.hexdigest(driver),
      'files' => records, 'buildProcessSHA256' => Digest::SHA256.hexdigest(JSON.generate(build_process)),
      'originalObjectMetadata' => original_object_metadata, 'retainedObjectMetadata' => retained_object_metadata }
  rescue ArgumentError
    raise RuntimeError, 'pairing compiler command framing is malformed'
  end

  def self.validate_pairing_contract(root, directory, invocation, tools, build_text, contract, build_process)
    exact_keys!(contract, %w[schema appRoot appRootSHA256 compiler compilerSHA256 target buildSettingArgv requiredDefinitions
                            proofPhase proofLogSHA256 compileMarker driverPath driverSHA256 files buildProcessSHA256 originalObjectMetadata retainedObjectMetadata], 'pairing compiler contract')
    parent = File.join(directory, 'pairing-inert-root-contract')
    stat = File.lstat(parent)
    require!(File.realpath(parent) == parent && stat.directory? && !stat.symlink? && stat.uid == Process.uid && (stat.mode & 0777) == 0700 &&
             Dir.children(parent).sort == PAIRING_PROOF_FILES.keys.sort, 'pairing retained compiler inventory is unsafe or incomplete')
    bytes = PAIRING_PROOF_FILES.map { |name, maximum| [name, pairing_owned_bytes(File.join(parent, name), maximum)] }.to_h
    retained_metadata = pairing_object_metadata(File.join(parent, 'OpensteamerApp.o'))
    require!(contract['retainedObjectMetadata'] == retained_metadata, 'pairing retained object metadata differs from actual build evidence')
    expected = pairing_compiler_proof(root, invocation.fetch('scratch'), invocation.fetch('developer_directory'), tools, build_text,
                                     bytes.reject { |name, _| name == 'app-swift-driver.txt' }, build_process,
                                     contract['originalObjectMetadata'], retained_metadata)
    require!(contract == expected && Digest::SHA256.hexdigest(bytes.fetch('app-swift-driver.txt')) == expected.fetch('driverSHA256'),
             'pairing retained compiler contract differs from actual build evidence')
    expected
  end

  def self.pairing_commands(root, directory, invocation, simulator)
    developer = invocation.fetch('developer_directory')
    base = [File.join(developer, 'usr/bin/xcodebuild')]
    common = ['-project', File.join(root, 'iOS/opensteamer/opensteamer.xcodeproj'), '-scheme', 'opensteamer', '-configuration', 'Debug',
              '-destination', 'platform=iOS Simulator,id=' + simulator, '-derivedDataPath', File.join(invocation.fetch('scratch'), 'DerivedData'), '-jobs', '2']
    signing = [PAIRING_INERT_CONDITIONS, 'DEVELOPMENT_TEAM=MSMG8CJLB3', 'CODE_SIGNING_ALLOWED=YES']
    result = File.join(directory, 'pairing.xcresult')
    app = File.join(directory, 'pairing-app/Beluga.app')
    { 'pairing-inert-build' => base + ['build'] + common + signing,
      'pairing-tests' => base + ['test'] + common + ['-resultBundlePath', result, '-parallel-testing-enabled', 'NO',
        '-test-timeouts-enabled', 'YES', '-default-test-execution-time-allowance', '90', '-maximum-test-execution-time-allowance', '90'] +
        PAIRING_CLASSES.map { |name| '-only-testing:opensteamerTests/' + name } + signing,
      'pairing-summary' => ['/usr/bin/xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', result, '--compact'],
      'pairing-results' => ['/usr/bin/xcrun', 'xcresulttool', 'get', 'test-results', 'tests', '--path', result, '--compact'],
      'pairing-signature' => ['/usr/bin/codesign', '--verify', '--strict', app],
      'pairing-entitlements' => ['/usr/bin/ruby', File.join(root, 'scripts/microphone-simulator-signing.rb'), app] }
  end

  def self.commands(root, directory, invocation, tools, simulator, mac_methods, handoff_methods)
    exact_keys!(invocation, %w[developer_directory scratch swift_scratch timeout_seconds], 'invocation')
    developer = invocation.fetch('developer_directory')
    scratch = invocation.fetch('scratch')
    require!(developer.is_a?(String) && developer.start_with?('/') && scratch.is_a?(String) && scratch.start_with?('/') &&
             invocation['timeout_seconds'].is_a?(Integer) && (1..3600).cover?(invocation['timeout_seconds']), 'invalid invocation context')
    require!(directory.start_with?(scratch + '/validation-runs/microphone-'), 'receipt is outside its fresh invocation directory')
    swift_scratch = invocation.fetch('swift_scratch')
    require!([File.join(scratch, 'swift-build'), File.join(scratch, 'SwiftPM')].include?(swift_scratch), 'Swift cache escapes the dedicated scratch root')
    swift = File.join(developer, 'Toolchains/XcodeDefault.xctoolchain/usr/bin/swift')
    xcodebuild = File.join(developer, 'usr/bin/xcodebuild')
    require!(tools.key?(swift) && tools.key?(xcodebuild), 'recorded Xcode tools do not match invocation')
    require!(%w[swiftc clang].all? { |name| tools.key?(File.join(developer, 'Toolchains/XcodeDefault.xctoolchain/usr/bin', name)) } &&
             %w[/usr/bin/lipo /usr/bin/plutil /usr/bin/xcrun].all? { |path| tools.key?(path) },
             'recorded Beluga core tools do not match invocation')
    cargo_candidates = tools.keys.select { |path| File.basename(path) == 'cargo' }
    require!(cargo_candidates.length == 1, 'ambiguous Cargo identity')
    cargo = cargo_candidates.first
    require!(tools.key?(File.join(File.dirname(cargo), 'rustc')), 'recorded Beluga core Rust compiler does not match Cargo invocation')
    swift_base = [swift, 'test', '--package-path', root, '--scratch-path', swift_scratch, '--jobs', '2']
    filter = '^(?:' + mac_methods.map { |id| Regexp.escape(id) }.join('|') + ')$'
    handoff_filter = '^(?:' + handoff_methods.map { |id| Regexp.escape(id) }.join('|') + ')$'
    result = File.join(directory, 'simulator.xcresult')
    app = File.join(directory, 'simulator-app/Beluga.app')
    sim = [xcodebuild, 'test', '-project', File.join(root, 'iOS/opensteamer/opensteamer.xcodeproj'), '-scheme', 'opensteamer', '-configuration', 'Debug',
           '-destination', 'platform=iOS Simulator,id=' + simulator, '-derivedDataPath', File.join(scratch, 'DerivedData'), '-resultBundlePath', result,
           '-parallel-testing-enabled', 'NO', '-jobs', '2', '-test-timeouts-enabled', 'YES', '-default-test-execution-time-allowance', '90',
           '-maximum-test-execution-time-allowance', '90']
    sim += SIMULATOR_CLASSES.map { |name| '-only-testing:opensteamerTests/' + name }
    sim += ['DEVELOPMENT_TEAM=MSMG8CJLB3', 'CODE_SIGNING_ALLOWED=YES']
    driver = File.join(root, 'macOS/VirtualAudioDriver')
    make = ['/usr/bin/make', '-B', '-C', driver, 'BUILD_DIR=' + File.join(scratch, 'DriverBuild'), 'DEVELOPER_DIR=' + developer]
    bundles = [1, 2].map { |number| File.join(directory, 'driver-build-' + number.to_s, 'OpensteamerVirtualMicrophone.driver') }
    {
      'gate-self-tests' => ['/usr/bin/ruby', File.join(root, 'scripts/test-validate-microphone-regressions.rb'), '--verbose'],
      'simulator-signing-self-tests' => ['/usr/bin/ruby', File.join(root, 'scripts/test-microphone-simulator-signing.rb'), '--verbose'],
      'release-hook-self-tests' => ['/usr/bin/ruby', File.join(root, 'scripts/test-microphone-release-gate.rb')],
      'host-release-hook-self-tests' => ['/usr/bin/ruby', File.join(root, 'scripts/test-microphone-host-release-gate.rb')],
      'mac-producer-contract-tests' => ['/usr/bin/ruby', File.join(root, 'macOS/scripts/verify-beluga-mac-client-tests.rb'), '--verbose'],
      'product-identity' => ['/bin/zsh', File.join(root, 'scripts/check-product-identity.sh'), root],
      'product-identity-mutations' => ['/bin/zsh', File.join(root, 'scripts/test-product-identity.sh')],
      'rust-artifact-validation' => ['/usr/bin/ruby', File.join(root, 'scripts/microphone-regression-gate.rb'), '--verify-rust-artifact'],
      'beluga-core-artifact-validation' => ['/usr/bin/ruby', File.join(root, 'scripts/microphone-regression-gate.rb'), '--verify-beluga-core-artifact'],
      'beluga-core-link' => ['/usr/bin/ruby', File.join(root, BELUGA_CORE_CRATE, 'scripts/verify-xcframework.rb'), File.join(root, BELUGA_CORE_ARTIFACT)],
      'beluga-core-mutations' => ['/usr/bin/ruby', File.join(root, BELUGA_CORE_CRATE, 'scripts/mutation-tests.rb')],
      'mac-discovery' => swift_base + ['--list-tests'],
      'mac-tests' => swift_base + ['--skip-build', '--filter', filter, '--xunit-output', File.join(directory, 'mac-results.xml')],
      'shared-signaling-tests' => swift_base + ['--skip-build', '--disable-xctest', '--filter', SHARED_SIGNALING_FILTER],
      SHARED_RECONNECT_COUNTER_PHASE => swift_base + ['--skip-build', '--disable-xctest', '--filter', '^' + Regexp.escape(SHARED_RECONNECT_COUNTER_SUITE) + '/'],
      SHARED_PAIRING_COMMIT_PHASE => swift_base + ['--skip-build', '--disable-xctest', '--filter', '^' + Regexp.escape(SHARED_PAIRING_COMMIT_SUITE) + '/'],
      'shared-handoff-tests' => swift_base + ['--skip-build', '--filter', handoff_filter],
      'simulator-tests' => sim,
      'simulator-summary' => ['/usr/bin/xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', result, '--compact'],
      'simulator-results' => ['/usr/bin/xcrun', 'xcresulttool', 'get', 'test-results', 'tests', '--path', result, '--compact'],
      'simulator-signature' => ['/usr/bin/codesign', '--verify', '--strict', app],
      'simulator-entitlements' => ['/usr/bin/ruby', File.join(root, 'scripts/microphone-simulator-signing.rb'), app],
      'rust-discovery' => [cargo, 'test', '--offline', '--locked', '--', '--list'],
      'rust-tests' => [cargo, 'test', '--offline', '--locked', '--', '--test-threads=1'],
      'beluga-core-discovery' => [cargo, 'test', '--offline', '--locked', '--manifest-path', File.join(root, BELUGA_CORE_CRATE, 'Cargo.toml'), '--', '--list'],
      'beluga-core-tests' => [cargo, 'test', '--offline', '--locked', '--manifest-path', File.join(root, BELUGA_CORE_CRATE, 'Cargo.toml'), '--', '--test-threads=1'],
      'driver-tests' => make + %w[test-core test-driver],
      'driver-sanitizers' => make + %w[test-sanitizers],
      'driver-diagnostic-reader' => make + %w[test-diagnostic-snapshot-reader],
      'driver-build-1' => [File.join(driver, 'scripts/build-driver.sh'), bundles[0]],
      'driver-build-2' => [File.join(driver, 'scripts/build-driver.sh'), bundles[1]],
      'driver-verifier' => [File.join(driver, 'scripts/verify-driver-bundle.sh'), bundles[0]],
      'driver-load' => [File.join(driver, 'scripts/test-built-driver-bundle.sh'), bundles[0]],
      'driver-malformed-bundles' => [File.join(driver, 'scripts/test-driver-bundle-verifier.sh'), bundles[0]]
    }.merge(SHARED_REPLAY_PHASES.to_h do |phase, suite|
      [phase, swift_base + ['--skip-build', '--disable-xctest', '--filter', '^' + Regexp.escape(suite) + '/']]
    end).merge(pairing_commands(root, directory, invocation, simulator))
  end

  def self.gate_inventory(root)
    source = utf8_text(File.binread(File.join(root, 'scripts/test-validate-microphone-regressions.rb')), 'Gate behavioral source')
    methods = source.scan(/^\s*def (test\w+)(?:\(|\s|$)/).flatten
    require!(methods.length >= 41 && methods.uniq.length == methods.length && (GATE_PINNED - methods).empty?,
             'gate behavioral harness inventory is incomplete or duplicated')
    methods.sort
  end

  def self.validate_harness(text, expected = nil)
    text = utf8_text(text, 'Gate behavioral result')
    if expected
      lines = text.lines
      case_lines = lines.each_with_index.select { |line, _| line.start_with?('MicrophoneRegressionGateTests#') }
      cases = case_lines.map { |line, _| /\AMicrophoneRegressionGateTests#(test\w+) = \d+(?:\.\d+)? s = ([.SEF])\s*\z/.match(line) }
      require!(!expected.empty? && cases.all? { |entry| entry && entry[2] == '.' } &&
               cases.map { |entry| entry[1] }.sort == expected,
               'gate behavioral results are absent, duplicated, unexpected, failed or skipped')
      summaries = lines.each_with_index.map do |line, index|
        match = /\A(\d+) runs, (\d+) assertions, (\d+) failures, (\d+) errors, (\d+) skips\s*\z/.match(line)
        [match, index] if match
      end.compact
      require!(summaries.length == 1 && summaries.first[0][1].to_i == expected.length &&
               summaries.first[0][2].to_i >= expected.length && summaries.first[0].captures.drop(2).all? { |value| value.to_i == 0 } &&
               summaries.first[1] > case_lines.last[1], 'gate behavioral harness footer is incomplete')
      return
    end
    summaries = text.lines.map { |line| /\A(\d+) runs, (\d+) assertions, (\d+) failures, (\d+) errors, (\d+) skips\s*\z/.match(line) }.compact
    require!(summaries.length == 1 && summaries.first[1].to_i >= 41 && summaries.first[2].to_i >= summaries.first[1].to_i &&
             summaries.first.captures.drop(2).all? { |number| number.to_i == 0 }, 'gate behavioral harness has missing, failed or skipped coverage')
  end

  def self.validate_host_release_harness(text)
    require!(text.lines.map(&:chomp).count('microphone host release gate behavior tests passed') == 1, 'host release hook behavioral harness is incomplete')
  end

  MAC_PRODUCER_PINNED = %w[
    test_release_configuration_accepts_only_configured_exact_identity_version_and_feed
    test_ownership_protocol_producer_refuses_in_process_sdk_startup
    test_catalog_producer_requires_migration_checkpoint_routing_and_legacy_account_fence
    test_catalog_marker_is_exact_integer_not_boolean_string_float_missing_or_future_version
    test_codesign_parser_rejects_duplicate_identity_development_adhoc_no_runtime_or_no_timestamp
    test_codesign_parser_accepts_real_space_record_and_utf8_bytes_without_mutating_input
    test_codesign_parser_refuses_ambiguous_records_and_spoofed_runtime_flags
    test_candidate_identity_is_derived_from_actual_executable_and_full_signed_app_tree
    test_candidate_identity_cannot_stamp_v2_onto_an_app_with_old_or_missing_catalog_marker
    test_producer_admits_only_v2_catalog_contract_even_for_high_build_candidate
    test_appcast_contains_exact_signed_payload_version_arm64_and_public_github_release_url
    test_package_binds_final_mounted_candidate_metadata_before_whole_feed_signing
    test_release_builder_binds_tools_before_identity_and_scrubs_every_swift_child
    test_keeps_original_product_and_current_tooling_sources_separate
    test_a_success_report_or_machine_journal_claim_cannot_replace_failed_observation
    test_retained_collector_uses_raw_blob_sha256_and_actual_receipt_modes
    test_retained_collector_refuses_ignored_dependency_mode_bytes_and_membership_drift
    test_retained_collector_reader_pins_exact_bytes_digest_bound_and_inode
    test_retained_factory_requires_actual_current_receipt_before_reading_evidence
    test_retained_native_source_boundary_rejects_raw_hash_or_data_parser
    test_package_authority_requires_exactly_one_build_or_complete_retained_binding
    test_retained_admitted_provenance_cannot_mutate_product_or_tooling_fences
    test_retained_boundary_rechecks_ignored_input_inventory_and_tested_tool_bytes
    test_retained_product_log_requires_one_exact_success_terminal
    test_trial_admission_pins_manifest_source_receipt_and_toolchain
    test_trial_metadata_stages_and_verifies_both_slots_without_changing_production
    test_trial_metadata_rejects_mixed_slot_config_provenance_and_plists
    test_trial_metadata_requires_integer_build_in_both_signed_configs
    test_trial_metadata_requires_native_integer_catalog_and_ownership_markers
    test_trial_native_verifier_rejects_loose_bindings_before_native_work
    test_trial_build_report_admission_binds_both_actual_slot_artifacts
    test_trial_build_report_rejects_mixed_authority_candidates_and_json_types
    test_trial_build_admission_rechecks_report_logs_app_and_production_evidence
    test_trial_package_refuses_loose_authority_production_accounts_and_recovery_before_commands
    test_trial_appcast_parses_exact_admitted_urls_and_rejects_bad_payload_identity
    test_shared_appcast_preserves_fixed_production_bytes_and_escapes_all_dynamic_xml
    test_trial_package_shared_workflow_emits_only_nonpromotable_reports
    test_trial_package_rejects_wrong_lookup_key_before_any_sign_command
    test_trial_package_rechecks_authority_at_signing_notary_and_handoff_boundaries
  ].freeze

  def self.mac_producer_inventory(root)
    source = %w[verify-beluga-mac-client-tests.rb retained-beluga-mac-client-tests.rb update-trial-artifact-tests.rb update-trial-package-tests.rb].map do |name|
      utf8_text(File.binread(File.join(root, 'macOS/scripts', name)), 'Mac producer source')
    end.join("\n")
    methods = source.scan(/^\s*def (test\w+)(?:\(|\s|$)/).flatten
    require!(!methods.empty? && methods.uniq.length == methods.length && (MAC_PRODUCER_PINNED - methods).empty?,
             'Mac producer harness inventory is incomplete or duplicated')
    methods.sort
  end

  def self.validate_mac_producer_harness(text, expected)
    text = utf8_text(text, 'Mac producer result')
    lines = text.lines
    case_lines = lines.each_with_index.select { |line, _| line.start_with?('BelugaMacClientContractTests#') }
    cases = case_lines.map do |line, _|
      /\ABelugaMacClientContractTests#(test\w+) = [\d.]+ s = ([.SEF])\s*\z/.match(line)
    end
    require!(cases.all? { |entry| entry && entry[2] == '.' } &&
             cases.map { |entry| entry[1] }.sort == expected && !expected.empty?,
             'Mac producer behavioral results are absent, duplicated, unexpected, failed or skipped')
    summaries = lines.each_with_index.map do |line, index|
      match = /\A(\d+) runs, (\d+) assertions, (\d+) failures, (\d+) errors, (\d+) skips\s*\z/.match(line)
      [match, index] if match
    end.compact
    require!(summaries.length == 1 && summaries.first[0][1].to_i == expected.length &&
             summaries.first[0][2].to_i >= expected.length &&
             summaries.first[0].captures.drop(2).all? { |value| value.to_i == 0 } &&
             summaries.first[1] > case_lines.last[1], 'Mac producer harness footer is incomplete')
  end

  SIMULATOR_SIGNING_PINNED = %w[
    test_wrong_thin_architecture_filetype_and_physical_platform_refuse
    test_missing_duplicate_and_malformed_load_commands_refuse
    test_duplicate_xml_keys_wrong_identifier_and_group_refuse
    test_canonical_der_changes_or_noncanonical_encoding_refuse
    test_code_directory_page_hash_and_unsigned_bytes_refuse
    test_collector_first_or_final_signature_failure_never_returns_record
    test_collector_detects_executable_or_info_mutation_at_every_tool_boundary
    test_collector_same_bytes_file_replacement_and_symlink_refuse
    test_collector_digest_pin_refuses_same_size_bytes_with_stat_times_masked
    test_collector_stat_pin_refuses_mode_change_with_unchanged_bytes
    test_replay_rejects_false_green_unknown_fields_paths_and_bounds
    test_production_api_has_no_executor_or_signature_skip_option
  ].freeze

  def self.simulator_signing_inventory(root)
    source = File.read(File.join(root, 'scripts/test-microphone-simulator-signing.rb'))
    methods = source.scan(/^\s*def (test\w+)(?:\(|\s|$)/).flatten
    require!(methods.uniq.length == methods.length && (SIMULATOR_SIGNING_PINNED - methods).empty?,
             'Simulator signing harness inventory is incomplete or duplicated')
    methods.sort
  end

  def self.validate_simulator_signing_harness(text, expected)
    cases = text.lines.map do |line|
      /\AMicrophoneSimulatorSigningTests#(test\w+) = [\d.]+ s = ([.SEF])\s*\z/.match(line)
    end.compact
    require!(cases.all? { |entry| entry[2] == '.' } && cases.map { |entry| entry[1] }.sort == expected,
             'Simulator signing behavioral results are absent, duplicated, failed or skipped')
    summaries = text.lines.map { |line| /\A(\d+) runs, (\d+) assertions, (\d+) failures, (\d+) errors, (\d+) skips\s*\z/.match(line) }.compact
    require!(summaries.length == 1 && summaries.first[1].to_i == expected.length &&
             summaries.first[2].to_i >= expected.length && summaries.first.captures.drop(2).all? { |value| value.to_i == 0 } &&
             text.lines.map(&:chomp).count('microphone Simulator signing behavior tests passed') == 1,
             'Simulator signing harness footer or terminal marker is incomplete')
  end

  def self.validate_driver_load(text)
    lines = text.lines.map(&:chomp)
    required = ['VERIFIED_BUILT_DRIVER_BUNDLE_LOAD',
                'PASS: loaded production driver idle-registration pressure and exact PCM',
                'PASS: loaded driver pristine and retired idle contract mutations']
    require!(required.all? { |marker| lines.count(marker) == 1 }, 'driver load pressure and exact PCM oracle is incomplete')
  end

  def self.install_interrupt_handlers
    %w[INT TERM].each { |signal| Signal.trap(signal) { raise Interrupt } }
  end

  def self.validate_checksum_manifest(directory, manifest_path, required_paths)
    entries = File.readlines(manifest_path).map do |line|
      match = /\A([0-9a-f]{64}) [ *](.+)\n?\z/.match(line)
      require!(match, 'checksum manifest contains an invalid record')
      relative = match[2].sub(/\A\.\//, '')
      require!(!relative.start_with?('/') && !relative.split('/').include?('..'), 'checksum manifest escapes its source root')
      path = File.join(directory, relative)
      regular!(path)
      require!(sha(path) == match[1], 'Rust source or artifact checksum differs: ' + relative)
      relative
    end
    require!(entries.uniq.length == entries.length && entries.sort == required_paths.sort, 'Rust source or artifact manifest has missing, duplicate or unbound files')
  end

  def self.validate_rust_artifacts(root)
    crate = File.join(root, 'iOS/opensteamer/Rust/AudioTransactionAuthority')
    artifact = File.join(root, 'iOS/opensteamer/Frameworks/OpensteamerAudioTransactionAuthority.xcframework')
    source_manifest = File.join(crate, 'SOURCE_MANIFEST.sha256')
    # The checked-in build workflow must enroll additions in the source manifest
    # and rebuild the published artifact; never repair the manifest here.
    additional = %w[src include scripts tests].flat_map do |directory|
      Dir.glob(File.join(crate, directory, '**', '*')).select { |path| File.file?(path) }.map { |path| path.delete_prefix(crate + '/') }
    end
    validate_checksum_manifest(crate, source_manifest, (RUST_SOURCE_FILES + additional).uniq)
    require!(File.binread(source_manifest) == File.binread(File.join(artifact, 'SOURCE_MANIFEST.sha256')), 'Rust published source manifest is stale')
    paths = []
    Find.find(artifact) do |path|
      require!(!File.symlink?(path), 'Rust artifact contains a symlink')
      paths << path.delete_prefix(artifact + '/') if File.file?(path) && File.basename(path) != 'ARTIFACT_MANIFEST.sha256'
    end
    validate_checksum_manifest(artifact, File.join(artifact, 'ARTIFACT_MANIFEST.sha256'), paths)
    require!(paths.include?('ios-arm64/libopensteamer_audio_transaction_authority.a') &&
             paths.include?('ios-arm64_x86_64-simulator/libopensteamer_audio_transaction_authority-simulator.a'), 'Rust device or Simulator slice is missing')
  end

  def self.beluga_core_files(directory, exclude: [])
    require!(File.directory?(directory) && !File.symlink?(directory) && File.realpath(directory) == directory,
             'Beluga core source or artifact directory is absent, symlinked or noncanonical')
    paths = []
    Find.find(directory) do |path|
      stat = File.lstat(path)
      require!(!stat.symlink? && (stat.file? || stat.directory?), 'Beluga core source or artifact contains an unsupported node')
      relative = path.delete_prefix(directory + '/')
      Find.prune if exclude.include?(relative) && stat.directory?
      paths << relative if stat.file? && !exclude.include?(relative)
    end
    paths.sort
  end

  def self.beluga_core_plist_value(element)
    case element.name
    when 'dict'
      children = element.elements.to_a
      require!(children.length.even?, 'Beluga core XCFramework plist dictionary is malformed')
      result = {}
      children.each_slice(2) do |key, value|
        require!(key.name == 'key' && key.text && !result.key?(key.text), 'Beluga core XCFramework plist has malformed or duplicate keys')
        result[key.text] = beluga_core_plist_value(value)
      end
      result
    when 'array' then element.elements.map { |value| beluga_core_plist_value(value) }
    when 'string'
      require!(element.elements.to_a.empty?, 'Beluga core XCFramework plist string is malformed')
      element.text.to_s
    else raise RuntimeError, 'Beluga core XCFramework plist contains an unsupported value'
    end
  end

  def self.beluga_core_plist(bytes, label)
    document = REXML::Document.new(utf8_text(bytes, label))
    require!(document.root && document.root.name == 'plist' && document.root.attributes['version'] == '1.0' &&
             document.root.elements.to_a.length == 1, label + ' root differs')
    beluga_core_plist_value(document.root.elements.to_a.first)
  rescue REXML::ParseException
    raise RuntimeError, label + ' is malformed'
  end

  def self.beluga_core_framework_info(slice)
    require!(BELUGA_CORE_SLICES.key?(slice), 'Beluga core framework slice is unreviewed')
    platform = { 'macos-arm64' => 'MacOSX', 'ios-arm64' => 'iPhoneOS', 'ios-arm64_x86_64-simulator' => 'iPhoneSimulator' }.fetch(slice)
    minimum = slice == 'macos-arm64' ? { 'LSMinimumSystemVersion' => '13.0' } : { 'MinimumOSVersion' => '16.0' }
    BELUGA_CORE_FRAMEWORK_INFO.merge('CFBundleSupportedPlatforms' => [platform]).merge(minimum)
  end

  def self.beluga_core_static_archive(path, slice)
    File.open(path, 'rb') do |file|
      magic = file.read(8)
      if slice != 'ios-arm64_x86_64-simulator'
        require!(magic == "!<arch>\n", 'Beluga core framework executable is not a static archive')
      else
        require!(magic && magic.byteslice(0, 4) == "\xca\xfe\xba\xbe".b && magic.byteslice(4, 4).unpack('N').first == 2,
                 'Beluga core Simulator executable is not the reviewed universal static archive')
        table = file.read(40)
        require!(table && table.bytesize == 40, 'Beluga core Simulator static archive descriptor is truncated')
        entries = 2.times.map { |index| table.byteslice(index * 20, 20).unpack('N5') }
        require!(entries.map(&:first).sort == [0x01000007, 0x0100000c], 'Beluga core Simulator static archive CPU inventory differs')
        ranges = entries.map { |_, _, offset, size, _| [offset, offset + size, size] }.sort
        require!(ranges.all? { |offset, finish, size| offset >= 48 && size >= 8 && finish <= file.stat.size } &&
                 ranges.first[1] <= ranges.last[0], 'Beluga core Simulator static archive ranges are invalid or overlap')
        ranges.each do |offset, _, _|
          file.seek(offset)
          require!(file.read(8) == "!<arch>\n", 'Beluga core Simulator slice is not a static archive')
        end
      end
    end
  end

  def self.validate_beluga_core_artifacts(root)
    crate = File.join(root, BELUGA_CORE_CRATE)
    artifact = File.join(root, BELUGA_CORE_ARTIFACT)
    source_manifest = File.join(crate, 'SOURCE_MANIFEST.sha256')
    source_paths = beluga_core_files(crate, exclude: %w[target SOURCE_MANIFEST.sha256])
    require!(source_paths == BELUGA_CORE_SOURCE_FILES.sort, 'Beluga core required source files are missing or unbound')
    regular!(source_manifest)
    validate_checksum_manifest(crate, source_manifest, source_paths)
    artifact_paths = beluga_core_files(artifact, exclude: %w[ARTIFACT_MANIFEST.sha256])
    require!(artifact_paths == BELUGA_CORE_ARTIFACT_FILES.sort, 'Beluga core artifact has missing or unbound files')
    require!(artifact_paths.all? { |path| regular!(File.join(artifact, path)).size.positive? }, 'Beluga core artifact contains an empty required file')
    regular!(File.join(artifact, 'ARTIFACT_MANIFEST.sha256'))
    validate_checksum_manifest(artifact, File.join(artifact, 'ARTIFACT_MANIFEST.sha256'), artifact_paths)
    require!(File.binread(source_manifest) == File.binread(File.join(artifact, 'SOURCE_MANIFEST.sha256')), 'Beluga core published source manifest is stale')
    BELUGA_CORE_SLICES.keys.each do |slice|
      framework = File.join(artifact, slice, BELUGA_CORE_FRAMEWORK)
      beluga_core_static_archive(File.join(framework, 'BelugaCore'), slice)
      { 'beluga_core.h' => 'Headers/beluga_core.h', 'module.modulemap' => 'Modules/module.modulemap' }.each do |name, published|
        require!(File.binread(File.join(crate, 'include', name)) == File.binread(File.join(framework, published)),
                 'Beluga core published header, module or notice differs')
      end
      info = beluga_core_plist(File.binread(File.join(framework, 'Info.plist')), 'Beluga core framework plist')
      require!(info == beluga_core_framework_info(slice), 'Beluga core framework bundle metadata differs from the reviewed platform or identity')
    end
    require!(File.binread(File.join(crate, 'THIRD_PARTY_NOTICES.html')) == File.binread(File.join(artifact, 'THIRD_PARTY_NOTICES.html')),
             'Beluga core published header, module or notice differs')
    plist = beluga_core_plist(File.binread(File.join(artifact, 'Info.plist')), 'Beluga core XCFramework plist')
    exact_keys!(plist, %w[AvailableLibraries CFBundlePackageType XCFrameworkFormatVersion], 'Beluga core XCFramework plist')
    libraries = plist['AvailableLibraries']
    require!(plist['CFBundlePackageType'] == 'XFWK' && plist['XCFrameworkFormatVersion'] == '1.0' &&
             libraries.is_a?(Array) && libraries.length == BELUGA_CORE_SLICES.length, 'Beluga core XCFramework slice inventory differs')
    identifiers = libraries.map { |library| library.is_a?(Hash) && library['LibraryIdentifier'] }
    require!(identifiers.all? { |identifier| identifier.is_a?(String) } &&
             identifiers.sort == BELUGA_CORE_SLICES.keys.sort, 'Beluga core XCFramework slice identities differ')
    libraries.each do |library|
      expected = BELUGA_CORE_SLICES.fetch(library.fetch('LibraryIdentifier')).merge(
        'LibraryIdentifier' => library.fetch('LibraryIdentifier'),
        'LibraryPath' => BELUGA_CORE_FRAMEWORK, 'BinaryPath' => BELUGA_CORE_FRAMEWORK + '/BelugaCore')
      require!(library == expected, 'Beluga core XCFramework is not the exact reviewed platform, architecture or ABI slice')
    end
    metadata = utf8_text(File.binread(File.join(artifact, 'BUILD_METADATA.txt')), 'Beluga core build metadata').lines.map(&:chomp)
    tail = metadata.drop(BELUGA_CORE_METADATA_PREFIX.length)
    require!(metadata.take(BELUGA_CORE_METADATA_PREFIX.length) == BELUGA_CORE_METADATA_PREFIX && tail.length == 12 &&
             tail[0].match?(/\Arustc 1\.97\.1 \([a-f0-9]+ \d{4}-\d{2}-\d{2}\)\z/) && tail[1] == 'binary: rustc' &&
             tail[2].match?(/\Acommit-hash: [a-f0-9]{40}\z/) && tail[3].match?(/\Acommit-date: \d{4}-\d{2}-\d{2}\z/) &&
             tail[4] == 'host: aarch64-apple-darwin' && tail[5] == 'release: ' + RUST_VERSION &&
             tail[6].match?(/\ALLVM version: \d+(?:\.\d+){1,2}\z/) &&
             tail[7, 2] == XCODE_VERSION.lines.map(&:chomp) &&
             %w[macos iphoneos iphonesimulator].each_with_index.all? { |sdk, index| tail[9 + index].match?(/\A#{sdk}-sdk=\d+(?:\.\d+){0,2}\z/) },
             'Beluga core build metadata differs from the reviewed Rust, Xcode or target identity')
  rescue REXML::ParseException
    raise RuntimeError, 'Beluga core XCFramework plist is malformed'
  rescue SystemCallError
    raise RuntimeError, 'Beluga core artifact validation could not read a required file'
  end

  def self.validate_beluga_core_link(text)
    lines = utf8_text(text, 'Beluga core link result').lines.map(&:chomp)
    markers = BELUGA_CORE_RUNTIME_MARKERS + ['BELUGA_CORE_LINK_SMOKE_PASS'] +
              BELUGA_CORE_TARGETS.drop(1).map { |target| 'BELUGA_CORE_CROSS_LINK_PASS target=' + target }
    observed = lines.select do |line|
      line.start_with?('BelugaCore C ', 'BelugaCore Swift ', 'BELUGA_CORE_LINK_SMOKE_PASS', 'BELUGA_CORE_CROSS_LINK_PASS')
    end
    require!(observed == markers,
             'Beluga core actual archive C and Swift link oracle is incomplete')
  end

  def self.validate_beluga_core_mutations(text)
    lines = utf8_text(text, 'Beluga core mutation result').lines.map(&:chomp)
    expected = BELUGA_CORE_MUTANTS.map { |name| 'BELUGA_CORE_MUTANT_REJECTED ' + name + ' assertion-failed' }
    observed = lines.select { |line| line.start_with?('BELUGA_CORE_MUTANT_REJECTED') }
    footer = 'BELUGA_CORE_MUTATIONS_PASS cases=' + BELUGA_CORE_MUTANTS.length.to_s
    require!(observed == expected && lines.count(footer) == 1 &&
             lines.select { |line| line.start_with?('BELUGA_CORE_MUTATIONS_PASS') } == [footer] &&
             expected.all? { |line| lines.index(line) < lines.index(footer) },
             'Beluga core assertion-failing mutation oracle is incomplete, duplicate or out of order')
    # Each marker must close a fresh compiled, exact single-case assertion
    # failure. A compile error, unrelated failing test or summary alone cannot
    # substitute for the producer's source-bound exit-101 behavioral oracle.
    offset = 0
    BELUGA_CORE_MUTANT_TESTS.each do |name, test|
      marker = 'BELUGA_CORE_MUTANT_REJECTED ' + name + ' assertion-failed'
      finish = lines.index(marker)
      segment = lines[offset...finish]
      compiled = segment.select { |line| line.match?(/\A\s*Finished\b/) }
      cases = segment.select { |line| line.match?(/\Atest \S+ \.\.\. /) }
      panics = segment.select { |line| line.start_with?("thread '") && line.include?(' panicked at ') }
      assertions = segment.select { |line| line.start_with?('assertion ') }
      results = segment.select { |line| line.start_with?('test result:') }
      errors = segment.select { |line| line.start_with?('error') }
      require!(compiled.length == 1 && compiled.first.match?(/\A\s*Finished `test` profile \[[^\r\n]+\] target\(s\) in [^\r\n]+\z/) &&
               segment.select { |line| line.start_with?('running ') } == ['running 1 test'] &&
               cases == ['test ' + test + ' ... FAILED'] &&
               panics.length == 1 && panics.first.match?(/\Athread '#{Regexp.escape(test)}'(?: \(\d+\))? panicked at [^\r\n]+\z/) &&
               assertions.length == 1 && assertions.first.match?(/\Aassertion `left == right` failed(?:: [^\r\n]*)?\z/) &&
               results.length == 1 && results.first.match?(/\Atest result: FAILED\. 0 passed; 1 failed; 0 ignored; 0 measured; \d+ filtered out; finished in [^\r\n]+\z/) &&
               errors.length == 1 && errors.first.match?(/\Aerror: test failed, to rerun pass `--test [a-z_]+`\z/) &&
               segment.none? { |line| line.include?('could not compile') },
               'Beluga core assertion-failing mutation oracle is incomplete: missing compiled intended assertion for ' + name)
      offset = finish + 1
    end
    require!(lines[offset..-1].none? do |line|
      line.match?(/\A\s*Finished\b/) || line.start_with?('running ', 'test ', "thread '", 'assertion ', 'error') ||
        line.include?('could not compile')
    end, 'Beluga core assertion-failing mutation oracle is incomplete: unframed trailing result')
  end

  # New pairing phases alone use retained-PGID teardown. Do not change the
  # existing phase executor's behavior as part of this additive seam.
  class PairingExecutor
    attr_reader :last_proof, :last_pgid

    def wall_nanoseconds
      (Time.now.to_r * 1_000_000_000).to_i
    end

    def group_present?(pgid)
      Process.kill(0, -pgid)
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      raise RuntimeError, 'pairing owned process group cannot be proven absent: EPERM'
    end

    def signal_group(signal, pgid)
      Process.kill(signal, -pgid)
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      raise RuntimeError, 'pairing owned process group teardown refused: EPERM'
    end

    def reap_leader(pid)
      return if @leader_status
      result = Process.waitpid2(pid, Process::WNOHANG)
      @leader_status = result[1] if result
    rescue Errno::ECHILD
      raise RuntimeError, 'pairing exact owned leader was not reaped by this executor'
    end

    def await_absence(pid, pgid, seconds, can_reap = true)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
      loop do
        reap_leader(pid) if can_reap
        return true unless group_present?(pgid)
        return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        sleep 0.01
      end
    end

    def teardown(pid, pgid)
      reap_error = nil
      begin
        reap_leader(pid)
      rescue Exception => error
        reap_error = error
      end
      # Reaping failure does not waive teardown of this still-owned group.
      begin
        if group_present?(pgid)
          @term_sent = signal_group('TERM', pgid)
          unless await_absence(pid, pgid, 0.25, !reap_error)
            @kill_sent = signal_group('KILL', pgid)
            MicrophoneRegressionGate.require!(await_absence(pid, pgid, 2.0, !reap_error), 'pairing owned process group survived bounded teardown')
          end
        end
      ensure
        reap_leader(pid) unless @leader_status || reap_error
      end
      raise reap_error if reap_error
      MicrophoneRegressionGate.require!(@leader_status && !group_present?(pgid),
                                       'pairing teardown lacks exact leader reap and final ESRCH proof')
    end

    def run(argv, environment, root, log, timeout)
      @last_proof = nil; @leader_status = nil; @term_sent = false; @kill_sent = false
      @completion = nil; @last_pgid = nil
      MicrophoneRegressionGate.require!(timeout.is_a?(Numeric) && timeout.finite? && timeout.positive?, 'pairing command timeout is invalid')
      pid = nil; pgid = nil; primary_error = nil
      started = wall_nanoseconds
      begin
        pid = Process.spawn(environment, *argv, chdir: root, out: log, err: [:child, :out], pgroup: true, unsetenv_others: true)
        pgid = pid; @last_pgid = pgid # Retained even after the leader is reaped.
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        loop do
          reap_leader(pid)
          if @leader_status
            @completion = @leader_status.success? ? 'success' : 'exit-failure'
            break
          end
          if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
            @completion = 'timeout'
            raise RuntimeError, 'pairing command exceeded its deadline; inspect ' + log
          end
          sleep 0.01
        end
      rescue Exception => error # Interruption still owns and must retire this exact group.
        primary_error = error
        @completion ||= 'interrupted'
      ensure
        if pgid
          begin
            teardown(pid, pgid)
            @last_proof = { 'schema' => 'beluga.pairing.process-group.v1', 'pid' => pid, 'pgid' => pgid,
              'argvSHA256' => Digest::SHA256.hexdigest(JSON.generate(argv)), 'startedAtNanoseconds' => started,
              'finishedAtNanoseconds' => wall_nanoseconds, 'timeoutSeconds' => timeout,
              'leaderReaped' => true, 'leaderExitStatus' => @leader_status.exitstatus, 'leaderSignal' => @leader_status.termsig,
              'groupAbsent' => true, 'absenceProof' => 'ESRCH', 'termSent' => @term_sent, 'killSent' => @kill_sent,
              'completion' => @completion }
          rescue Exception => cleanup_error
            primary_error = cleanup_error # A safety failure takes precedence; never return a passing proof.
            @last_proof = nil
          end
        end
      end
      raise primary_error if primary_error
      MicrophoneRegressionGate.require!(@leader_status && @leader_status.success? && @last_proof,
                                       'pairing command exited unsuccessfully; inspect ' + log)
      File.read(log)
    end
  end

  class Executor
    def run(argv, environment, root, log, timeout)
      pid = Process.spawn(environment, *argv, chdir: root, out: log, err: [:child, :out], pgroup: true, unsetenv_others: true)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        result = Process.waitpid2(pid, Process::WNOHANG)
        if result
          pid = nil
          MicrophoneRegressionGate.require!(result[1].success?, "command exited unsuccessfully: #{argv.first}; inspect #{log}")
          return File.read(log)
        end
        MicrophoneRegressionGate.require!(Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline, "command exceeded deadline; inspect #{log}")
        sleep 0.05
      end
    ensure
      if pid
        begin
          Process.kill('TERM', -pid)
          sleep 0.15
          Process.kill('KILL', -pid)
        rescue Errno::ESRCH
        rescue Errno::EPERM
          # Darwin can leave only the exited group leader's zombie. Accept that
          # case only after reaping this exact owned child.
          reaped = Process.waitpid(pid, Process::WNOHANG)
          raise unless reaped == pid
        ensure
          begin
            Process.waitpid(pid)
          rescue Errno::ECHILD
          end
        end
      end
    end
  end

  class Runner
    attr_reader :evidence

    def initialize(root, options, executor = Executor.new, pairing_executor = PairingExecutor.new)
      @root = File.realpath(root)
      @options = options
      @executor = executor
      @pairing_executor = pairing_executor
      @pairing_processes = []
      @phases = []
    end

    def check_source
      MicrophoneRegressionGate.require!(MicrophoneRegressionGate.source_identity(@root) == @source, 'source changed during the invocation; use a fresh run')
    end

    def check_tools
      @tools.each { |path, digest| MicrophoneRegressionGate.require!(MicrophoneRegressionGate.sha(path) == digest, "tool identity changed: #{path}") }
    end

    def phase(name, argv, environment = @environment, root = @root)
      check_source
      check_tools
      check_pairing_fences
      timeout = @options.fetch(:timeout)
      if PAIRING_PHASE_TIMEOUTS.key?(name)
        MicrophoneRegressionGate.require!(@pairing_deadline, 'pairing phase was not admitted under its owned bounded group')
        remaining = @pairing_deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        MicrophoneRegressionGate.require!(remaining.positive?, 'pairing group exceeded its bounded deadline')
        timeout = [timeout, PAIRING_PHASE_TIMEOUTS.fetch(name), remaining].min
      end
      log = File.join(@evidence, name + '.log')
      puts "microphone-regressions: #{name}; deadline #{timeout}s; log #{log}"
      executor = PAIRING_PHASE_TIMEOUTS.key?(name) ? @pairing_executor : @executor
      text = executor.run(argv, environment, root, log, timeout)
      if PAIRING_PHASE_TIMEOUTS.key?(name)
        proof = executor.last_proof
        MicrophoneRegressionGate.require!(proof.is_a?(Hash), 'pairing phase lacks owned process teardown evidence')
        proof = proof.merge('phase' => name)
        MicrophoneRegressionGate.validate_pairing_process(proof, name, argv, (Time.now.to_r * 1_000_000_000).to_i, timeout)
        @pairing_processes << proof
      end
      check_source
      check_tools
      check_pairing_fences
      @phases << { 'name' => name, 'argv' => argv, 'log' => File.basename(log), 'sha256' => MicrophoneRegressionGate.sha(log) }
      text
    end

    def artifact(name, path)
      { 'name' => name, 'path' => path.delete_prefix(@evidence + '/'), 'sha256' => File.directory?(path) ? MicrophoneRegressionGate.tree_identity(path) : MicrophoneRegressionGate.sha(path), 'tree' => File.directory?(path) }
    end

    def check_pairing_fences
      return unless @pairing_started
      MicrophoneRegressionGate.require!(!@pairing_deadline || Process.clock_gettime(Process::CLOCK_MONOTONIC) < @pairing_deadline,
                                       'pairing group exceeded its bounded deadline')
      lock_path = @pairing_lock_path
      actual = File.lstat(lock_path)
      held = @lock.stat
      MicrophoneRegressionGate.require!(File.realpath(lock_path) == lock_path && actual.file? && !actual.symlink? &&
                                       actual.uid == Process.uid && actual.nlink == 1 && (actual.mode & 0777) == 0600 &&
                                       held.uid == Process.uid && held.nlink == 1 && (held.mode & 0777) == 0600 &&
                                       [actual.dev, actual.ino] == [held.dev, held.ino] && [held.dev, held.ino] == @pairing_lock_identity,
                                       'pairing canonical cache lock identity changed')
      (@pairing_compiler_files || []).each do |record|
        name = File.basename(record.fetch('path'))
        bytes = MicrophoneRegressionGate.pairing_owned_bytes(record.fetch('path'), PAIRING_PROOF_FILES.fetch(name))
        MicrophoneRegressionGate.require!(bytes.bytesize == record.fetch('byteCount') && Digest::SHA256.hexdigest(bytes) == record.fetch('sha256'),
                                         'pairing compiled source/input/object changed before receipt')
      end
      if @pairing_object_metadata
        path = MicrophoneRegressionGate.pairing_compiler_paths(@options.fetch(:scratch)).fetch('OpensteamerApp.o')
        MicrophoneRegressionGate.require!(MicrophoneRegressionGate.pairing_object_metadata(path) == @pairing_object_metadata,
                                         'pairing actual compiled App root object metadata changed before receipt')
      end
      nil
    end

    def run_pairing(scratch, developer, simulator)
      @pairing_started = true
      @pairing_lock_path = File.join(scratch, '.microphone-regressions.lock')
      @pairing_deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + PAIRING_OVERALL_SECONDS
      @pairing_lock_identity = [@lock.stat.dev, @lock.stat.ino]
      check_pairing_fences
      @pairing_methods = MicrophoneRegressionGate.pairing_inventory(@root)
      context = { 'developer_directory' => developer, 'scratch' => scratch }
      argv = MicrophoneRegressionGate.pairing_commands(@root, @evidence, context, simulator)
      build_text = phase('pairing-inert-build', argv.fetch('pairing-inert-build')) # Compile only. No test launch yet.
      paths = MicrophoneRegressionGate.pairing_compiler_paths(scratch)
      bytes = paths.map { |name, path| [name, MicrophoneRegressionGate.pairing_owned_bytes(path, PAIRING_PROOF_FILES.fetch(name))] }.to_h
      @pairing_contract = MicrophoneRegressionGate.pairing_compiler_proof(@root, scratch, developer, @tools, build_text, bytes,
        @pairing_processes.first, @pairing_object_metadata = MicrophoneRegressionGate.pairing_object_metadata(paths.fetch('OpensteamerApp.o')))
      @pairing_compiler_files = @pairing_contract.fetch('files')
      @pairing_proof_path = File.join(@evidence, 'pairing-inert-root-contract')
      Dir.mkdir(@pairing_proof_path, 0700)
      driver = build_text.lines.find { |line| Digest::SHA256.hexdigest(line) == @pairing_contract.fetch('driverSHA256') }
      MicrophoneRegressionGate.require!(driver, 'pairing actual driver line is absent')
      bytes.merge('app-swift-driver.txt' => driver).each do |name, contents|
        File.open(File.join(@pairing_proof_path, name), File::WRONLY | File::CREAT | File::EXCL, 0600) do |file|
          file.write(contents); file.flush; file.fsync
        end
      end
      @pairing_contract['retainedObjectMetadata'] = MicrophoneRegressionGate.pairing_object_metadata(File.join(@pairing_proof_path, 'OpensteamerApp.o'))
      MicrophoneRegressionGate.validate_pairing_contract(@root, @evidence, context, @tools, build_text, @pairing_contract, @pairing_processes.first)
      check_source; check_tools; check_pairing_fences # Admission fence, after actual compile proof, immediately before tests.
      phase('pairing-tests', argv.fetch('pairing-tests'))
      summary = phase('pairing-summary', argv.fetch('pairing-summary'))
      results = phase('pairing-results', argv.fetch('pairing-results'))
      MicrophoneRegressionGate.validate_pairing(MicrophoneRegressionGate.parse_json(summary, 'pairing summary'),
                                               MicrophoneRegressionGate.parse_json(results, 'pairing results'), @pairing_methods, simulator)
      @pairing_result = File.join(@evidence, 'pairing.xcresult')
      source_app = File.join(scratch, 'DerivedData/Build/Products/Debug-iphonesimulator/Beluga.app')
      identity = MicrophoneRegressionGate.tree_identity(source_app)
      parent = File.join(@evidence, 'pairing-app')
      Dir.mkdir(parent, 0700)
      FileUtils.cp_r(source_app, parent, preserve: true)
      @pairing_app = File.join(parent, 'Beluga.app')
      MicrophoneRegressionGate.require!(MicrophoneRegressionGate.tree_identity(@pairing_app) == identity &&
                                       MicrophoneRegressionGate.tree_identity(source_app) == identity, 'pairing signed app changed during retention')
      phase('pairing-signature', argv.fetch('pairing-signature'))
      entitlements = phase('pairing-entitlements', argv.fetch('pairing-entitlements'))
      MicrophoneSimulatorSigning.validate_record(MicrophoneRegressionGate.parse_json(entitlements, 'pairing signed identity'), expected_app: @pairing_app)
      check_source; check_tools; check_pairing_fences
      MicrophoneRegressionGate.validate_pairing_contract(@root, @evidence, context, @tools, build_text, @pairing_contract, @pairing_processes.first)
      MicrophoneRegressionGate.validate_pairing_processes(@pairing_processes, argv, (Time.now.to_r * 1_000_000_000).to_i, @options.fetch(:timeout))
      @pairing_deadline = nil # The bounded pairing group is complete; preserve compiler and lock fences through receipt.
    end

    def run
      MicrophoneRegressionGate.require!(RUBY_PLATFORM.include?('darwin'), 'this gate requires Darwin/macOS')
      simulator = @options.fetch(:simulator)
      MicrophoneRegressionGate.require!(simulator.match?(/\A[0-9A-Fa-f]{8}-(?:[0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}\z/), 'select one explicit Simulator UUID')
      developer = ENV['DEVELOPER_DIR']
      MicrophoneRegressionGate.require!(developer && developer.start_with?('/') && File.directory?(developer), 'set DEVELOPER_DIR to the reviewed Xcode developer directory')
      developer = File.realpath(developer)
      xcodebuild = File.join(developer, 'usr/bin/xcodebuild')
      swift = File.join(developer, 'Toolchains/XcodeDefault.xctoolchain/usr/bin/swift')
      MicrophoneRegressionGate.require!(MicrophoneRegressionGate.sha(xcodebuild) == XCODEBUILD_SHA256, 'Xcode executable differs from reviewed pin')
      scratch = @options.fetch(:scratch)
      MicrophoneRegressionGate.require!(scratch.start_with?('/') && File.directory?(scratch) && !File.symlink?(scratch), 'scratch must be an existing absolute dedicated non-symlink cache')
      scratch = File.realpath(scratch)
      MicrophoneRegressionGate.require!(![Dir.home, '/', @root, developer].include?(scratch) && !@root.start_with?(scratch + '/') && !scratch.start_with?(@root + '/') &&
                                       PROTECTED_ROOTS.none? { |path| scratch == path || scratch.start_with?(path + '/') }, 'scratch overlaps a broad, source or protected runtime root')
      stat = File.stat(scratch)
      MicrophoneRegressionGate.require!(stat.uid == Process.uid && (stat.mode & 0777) == 0700, 'scratch must be owner-owned mode 0700')
      lock_path = File.join(scratch, '.microphone-regressions.lock')
      MicrophoneRegressionGate.require!(!File.symlink?(lock_path), 'scratch lock is a symlink')
      @lock = File.open(lock_path, File::RDWR | File::CREAT, 0600)
      MicrophoneRegressionGate.require!(@lock.stat.uid == Process.uid && @lock.stat.nlink == 1 && (@lock.stat.mode & 0777) == 0600 && @lock.flock(File::LOCK_EX | File::LOCK_NB), 'scratch lock is unsafe or held by another invocation')
      swift_child = File.exist?(File.join(scratch, 'swift-build')) ? 'swift-build' : 'SwiftPM'
      @swift_scratch = File.join(scratch, swift_child)
      ['validation-runs', 'DerivedData', swift_child, 'RustTarget', 'DriverBuild'].each do |child|
        path = File.join(scratch, child)
        MicrophoneRegressionGate.require!(!File.symlink?(path), 'cache child is a symlink')
        FileUtils.mkdir_p(path, mode: 0700)
        child_stat = File.stat(path)
        MicrophoneRegressionGate.require!(child_stat.directory? && child_stat.uid == Process.uid && [0700, 0755].include?(child_stat.mode & 0777), 'cache child is unsafe')
      end
      @evidence = Dir.mktmpdir('microphone-', File.join(scratch, 'validation-runs'))
      File.chmod(0700, @evidence)
      @source = MicrophoneRegressionGate.source_identity(@root)
      @environment = { 'PATH' => '/usr/bin:/bin:/usr/sbin:/sbin', 'HOME' => Dir.home, 'DEVELOPER_DIR' => developer,
                       'TMPDIR' => @evidence, 'LC_ALL' => 'C', 'CARGO_NET_OFFLINE' => 'true', 'RUSTUP_HOME' => RUSTUP_HOME, 'CARGO_HOME' => CARGO_HOME }
      clang = File.join(developer, 'Toolchains/XcodeDefault.xctoolchain/usr/bin/clang')
      swiftc = File.join(developer, 'Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc')
      @tools = ([xcodebuild, swift, swiftc, clang, '/usr/bin/lipo', '/usr/bin/make', '/usr/bin/ruby', '/usr/bin/xcrun'] +
                MicrophoneSimulatorSigning::DEPENDENCIES).uniq.map { |path| [path, MicrophoneRegressionGate.sha(path)] }.to_h
      node = MicrophoneRegressionGate.resolve_node
      @tools[node] = MicrophoneRegressionGate.sha(node)
      @environment['PATH'] = File.dirname(node) + ':' + @environment.fetch('PATH')
      version_log = File.join(@evidence, 'xcode-version.log')
      version = @executor.run([xcodebuild, '-version'], @environment, @root, version_log, 30)
      MicrophoneRegressionGate.require!(version == XCODE_VERSION, 'reviewed Xcode version/build changed')
      devices_log = File.join(@evidence, 'simulator-devices.json')
      devices_text = @executor.run(['/usr/bin/xcrun', 'simctl', 'list', 'devices', '--json'], @environment, @root, devices_log, 30)
      devices = MicrophoneRegressionGate.parse_json(devices_text, 'Simulator device inventory').fetch('devices').values.flatten
      matching = devices.select { |entry| entry['udid'].to_s.casecmp?(simulator) && entry['isAvailable'] == true }
      MicrophoneRegressionGate.require!(matching.length == 1, 'selected destination is not one available Simulator')
      rustup = File.join(CARGO_HOME, 'bin/rustup')
      rust_log = File.join(@evidence, 'rust-toolchain.log')
      cargo_path = @executor.run([rustup, 'which', '--toolchain', RUST_VERSION, 'cargo'], @environment, @root, rust_log, 30).strip
      MicrophoneRegressionGate.require!(cargo_path.start_with?('/') && File.executable?(cargo_path), 'pinned installed Rust toolchain is absent; do not install or upgrade it')
      cargo = File.realpath(cargo_path)
      rustc = File.join(File.dirname(cargo), 'rustc')
      @tools[cargo] = MicrophoneRegressionGate.sha(cargo)
      @tools[rustc] = MicrophoneRegressionGate.sha(rustc)
      rust_version_log = File.join(@evidence, 'rust-version.log')
      rust_version = @executor.run([rustc, '--version'], @environment, @root, rust_version_log, 30)
      MicrophoneRegressionGate.require!(rust_version.start_with?('rustc ' + RUST_VERSION + ' '), 'Rust compiler is not the pinned version')
      @environment['PATH'] = File.dirname(cargo) + ':' + @environment.fetch('PATH')
      @environment['RUSTUP_TOOLCHAIN'] = RUST_VERSION
      @environment['CARGO_TARGET_DIR'] = File.join(scratch, 'RustTarget')
      core_environment = @environment.merge('BELUGA_CORE_CARGO_BIN' => cargo, 'BELUGA_CORE_RUSTC_BIN' => rustc,
                                           'BELUGA_CORE_CLANG_BIN' => clang, 'BELUGA_CORE_SWIFTC_BIN' => swiftc,
                                           'BELUGA_CORE_WORK_DIRECTORY' => File.join(@evidence, 'beluga-core-work'))
      MicrophoneRegressionGate.validate_harness(phase('gate-self-tests', ['/usr/bin/ruby', File.join(@root, 'scripts/test-validate-microphone-regressions.rb'), '--verbose']),
                                               MicrophoneRegressionGate.gate_inventory(@root))
      signing_tests = phase('simulator-signing-self-tests', ['/usr/bin/ruby', File.join(@root, 'scripts/test-microphone-simulator-signing.rb'), '--verbose'])
      MicrophoneRegressionGate.validate_simulator_signing_harness(signing_tests, MicrophoneRegressionGate.simulator_signing_inventory(@root))
      release_tests = phase('release-hook-self-tests', ['/usr/bin/ruby', File.join(@root, 'scripts/test-microphone-release-gate.rb')])
      MicrophoneRegressionGate.require!(release_tests.lines.map(&:chomp).count('microphone release gate behavior tests passed') == 1, 'release hook behavioral harness did not complete')
      host_release_tests = phase('host-release-hook-self-tests', ['/usr/bin/ruby', File.join(@root, 'scripts/test-microphone-host-release-gate.rb')])
      MicrophoneRegressionGate.validate_host_release_harness(host_release_tests)
      producer_tests = phase('mac-producer-contract-tests', ['/usr/bin/ruby', File.join(@root, 'macOS/scripts/verify-beluga-mac-client-tests.rb'), '--verbose'])
      MicrophoneRegressionGate.validate_mac_producer_harness(producer_tests, MicrophoneRegressionGate.mac_producer_inventory(@root))
      identity = phase('product-identity', ['/bin/zsh', File.join(@root, 'scripts/check-product-identity.sh'), @root])
      MicrophoneRegressionGate.require!(identity.lines.map(&:chomp).count('Beluga product identity check passed') == 1, 'product identity checker did not complete')
      identity_mutations = phase('product-identity-mutations', ['/bin/zsh', File.join(@root, 'scripts/test-product-identity.sh')])
      MicrophoneRegressionGate.require!(identity_mutations.lines.map(&:chomp).count('opensteamer product identity regression tests passed') == 1, 'product identity mutations did not complete')
      phase('rust-artifact-validation', ['/usr/bin/ruby', File.join(@root, 'scripts/microphone-regression-gate.rb'), '--verify-rust-artifact'])
      MicrophoneRegressionGate.validate_rust_artifacts(@root)
      phase('beluga-core-artifact-validation', ['/usr/bin/ruby', File.join(@root, 'scripts/microphone-regression-gate.rb'), '--verify-beluga-core-artifact'])
      MicrophoneRegressionGate.validate_beluga_core_artifacts(@root)
      MicrophoneRegressionGate.validate_beluga_core_link(phase('beluga-core-link',
        ['/usr/bin/ruby', File.join(@root, BELUGA_CORE_CRATE, 'scripts/verify-xcframework.rb'), File.join(@root, BELUGA_CORE_ARTIFACT)], core_environment))
      MicrophoneRegressionGate.validate_beluga_core_mutations(phase('beluga-core-mutations',
        ['/usr/bin/ruby', File.join(@root, BELUGA_CORE_CRATE, 'scripts/mutation-tests.rb')], core_environment))
      swift_base = [swift, 'test', '--package-path', @root, '--scratch-path', @swift_scratch, '--jobs', '2']
      mac_discovery = phase('mac-discovery', swift_base + ['--list-tests'])
      mac_methods = MicrophoneRegressionGate.mac_inventory(mac_discovery)
      MicrophoneRegressionGate.supported_player_inventory(@root, mac_discovery)
      MicrophoneRegressionGate.batch_a_native_inventory(@root, mac_discovery)
      shared_methods = MicrophoneRegressionGate.shared_signaling_inventory(mac_discovery)
      replay_methods = MicrophoneRegressionGate.shared_replay_inventory(@root, mac_discovery)
      reconnect_methods = MicrophoneRegressionGate.shared_reconnect_counter_inventory(@root, mac_discovery)
      commit_methods = MicrophoneRegressionGate.shared_pairing_commit_inventory(@root, mac_discovery)
      handoff_methods = MicrophoneRegressionGate.shared_handoff_inventory(mac_discovery)
      filter = '^(?:' + mac_methods.map { |id| Regexp.escape(id) }.join('|') + ')$'
      mac_xml = File.join(@evidence, 'mac-results.xml')
      mac_log = phase('mac-tests', swift_base + ['--skip-build', '--filter', filter, '--xunit-output', mac_xml])
      mac_format = File.file?(mac_xml) ? 'xunit' : 'darwin-xctest-log'
      if mac_format == 'xunit'
        MicrophoneRegressionGate.validate_xunit(File.read(mac_xml), mac_methods)
      else
        MicrophoneRegressionGate.validate_mac_log(mac_log, mac_methods)
      end
      shared_log = phase('shared-signaling-tests', swift_base + ['--skip-build', '--disable-xctest', '--filter', SHARED_SIGNALING_FILTER])
      MicrophoneRegressionGate.validate_shared_signaling(shared_log, shared_methods)
      SHARED_REPLAY_PHASES.each do |name, suite|
        log = phase(name, swift_base + ['--skip-build', '--disable-xctest', '--filter', '^' + Regexp.escape(suite) + '/'])
        MicrophoneRegressionGate.validate_shared_replay(log, replay_methods.fetch(suite), suite)
      end
      reconnect_log = phase(SHARED_RECONNECT_COUNTER_PHASE, swift_base + ['--skip-build', '--disable-xctest', '--filter', '^' + Regexp.escape(SHARED_RECONNECT_COUNTER_SUITE) + '/'])
      MicrophoneRegressionGate.validate_shared_reconnect_counter(reconnect_log, reconnect_methods)
      commit_log = phase(SHARED_PAIRING_COMMIT_PHASE, swift_base + ['--skip-build', '--disable-xctest', '--filter', '^' + Regexp.escape(SHARED_PAIRING_COMMIT_SUITE) + '/'])
      MicrophoneRegressionGate.validate_shared_pairing_commit(commit_log, commit_methods)
      handoff_filter = '^(?:' + handoff_methods.map { |id| Regexp.escape(id) }.join('|') + ')$'
      handoff_log = phase('shared-handoff-tests', swift_base + ['--skip-build', '--filter', handoff_filter])
      MicrophoneRegressionGate.validate_mac_log(handoff_log, handoff_methods)
      sim_methods = MicrophoneRegressionGate.simulator_inventory(@root)
      result = File.join(@evidence, 'simulator.xcresult')
      sim_args = [xcodebuild, 'test', '-project', File.join(@root, 'iOS/opensteamer/opensteamer.xcodeproj'), '-scheme', 'opensteamer', '-configuration', 'Debug',
                  '-destination', 'platform=iOS Simulator,id=' + simulator, '-derivedDataPath', File.join(scratch, 'DerivedData'), '-resultBundlePath', result,
                  '-parallel-testing-enabled', 'NO', '-jobs', '2', '-test-timeouts-enabled', 'YES', '-default-test-execution-time-allowance', '90',
                  '-maximum-test-execution-time-allowance', '90']
      sim_args.concat(SIMULATOR_CLASSES.map { |name| '-only-testing:opensteamerTests/' + name })
      sim_args.concat(['DEVELOPMENT_TEAM=MSMG8CJLB3', 'CODE_SIGNING_ALLOWED=YES'])
      phase('simulator-tests', sim_args)
      summary_text = phase('simulator-summary', ['/usr/bin/xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', result, '--compact'])
      results_text = phase('simulator-results', ['/usr/bin/xcrun', 'xcresulttool', 'get', 'test-results', 'tests', '--path', result, '--compact'])
      MicrophoneRegressionGate.validate_simulator(MicrophoneRegressionGate.parse_json(summary_text, 'Simulator summary'), MicrophoneRegressionGate.parse_json(results_text, 'Simulator results'), sim_methods, simulator)
      source_app = File.join(scratch, 'DerivedData/Build/Products/Debug-iphonesimulator/Beluga.app')
      app_identity = MicrophoneRegressionGate.tree_identity(source_app)
      retained_app_parent = File.join(@evidence, 'simulator-app')
      Dir.mkdir(retained_app_parent, 0700)
      FileUtils.cp_r(source_app, retained_app_parent, preserve: true)
      app = File.join(retained_app_parent, 'Beluga.app')
      MicrophoneRegressionGate.require!(MicrophoneRegressionGate.tree_identity(app) == app_identity &&
                                       MicrophoneRegressionGate.tree_identity(source_app) == app_identity,
                                       'signed Simulator app changed during its retained artifact copy')
      phase('simulator-signature', ['/usr/bin/codesign', '--verify', '--strict', app])
      entitlements = phase('simulator-entitlements', ['/usr/bin/ruby', File.join(@root, 'scripts/microphone-simulator-signing.rb'), app])
      MicrophoneSimulatorSigning.validate_record(MicrophoneRegressionGate.parse_json(entitlements, 'Simulator signed identity'), expected_app: app)
      run_pairing(scratch, developer, simulator) # The ordinary signed app above is already retained; pairing never launches the ordinary root.
      crate = File.join(@root, 'iOS/opensteamer/Rust/AudioTransactionAuthority')
      rust_methods = MicrophoneRegressionGate.rust_inventory(phase('rust-discovery', [cargo, 'test', '--offline', '--locked', '--', '--list'], @environment, crate))
      MicrophoneRegressionGate.validate_rust(phase('rust-tests', [cargo, 'test', '--offline', '--locked', '--', '--test-threads=1'], @environment, crate), rust_methods)
      core_base = [cargo, 'test', '--offline', '--locked', '--manifest-path', File.join(@root, BELUGA_CORE_CRATE, 'Cargo.toml'), '--']
      core_methods = MicrophoneRegressionGate.beluga_core_inventory(phase('beluga-core-discovery', core_base + ['--list']))
      MicrophoneRegressionGate.validate_rust(phase('beluga-core-tests', core_base + ['--test-threads=1']), core_methods)
      driver = File.join(@root, 'macOS/VirtualAudioDriver')
      c_methods = MicrophoneRegressionGate.c_inventory(@root)
      make_base = ['/usr/bin/make', '-B', '-C', driver, 'BUILD_DIR=' + File.join(scratch, 'DriverBuild'), 'DEVELOPER_DIR=' + developer]
      MicrophoneRegressionGate.validate_c(phase('driver-tests', make_base + %w[test-core test-driver]), c_methods)
      MicrophoneRegressionGate.validate_c(phase('driver-sanitizers', make_base + %w[test-sanitizers]), c_methods, 2)
      diagnostic = phase('driver-diagnostic-reader', make_base + %w[test-diagnostic-snapshot-reader])
      MicrophoneRegressionGate.require!(diagnostic.lines.map(&:chomp).include?('DIAGNOSTIC_SNAPSHOT_READER_TESTS_PASSED_WITHOUT_CORE_AUDIO_IO'), 'diagnostic reader self-test did not complete without Core Audio I/O')
      bundles = [1, 2].map do |number|
        parent = File.join(@evidence, 'driver-build-' + number.to_s)
        Dir.mkdir(parent, 0700)
        bundle = File.join(parent, 'OpensteamerVirtualMicrophone.driver')
        phase('driver-build-' + number.to_s, [File.join(driver, 'scripts/build-driver.sh'), bundle])
        bundle
      end
      MicrophoneRegressionGate.require!(MicrophoneRegressionGate.tree_identity(bundles[0]) == MicrophoneRegressionGate.tree_identity(bundles[1]), 'fresh universal driver builds differ')
      phase('driver-verifier', [File.join(driver, 'scripts/verify-driver-bundle.sh'), bundles[0]])
      load = phase('driver-load', [File.join(driver, 'scripts/test-built-driver-bundle.sh'), bundles[0]])
      MicrophoneRegressionGate.validate_driver_load(load)
      phase('driver-malformed-bundles', [File.join(driver, 'scripts/test-driver-bundle-verifier.sh'), bundles[0]])
      check_source
      check_tools
      artifacts = [artifact('simulator-result', result), artifact('driver-bundle-1', bundles[0]), artifact('driver-bundle-2', bundles[1])]
      check_pairing_fences
      artifacts << artifact('simulator-app', app)
      artifacts.concat([artifact('pairing-result', @pairing_result), artifact('pairing-app', @pairing_app), artifact('pairing-inert-root-contract', @pairing_proof_path)])
      artifacts << artifact('mac-xunit', mac_xml) if File.file?(mac_xml)
      receipt = { 'schema' => SCHEMA, 'status' => 'passed', 'scope' => 'offline-source-only', 'root' => @root,
                  'created_at' => Time.now.to_i, 'source' => @source, 'tools' => @tools, 'simulator' => simulator,
                  'invocation' => { 'developer_directory' => developer, 'scratch' => scratch, 'swift_scratch' => @swift_scratch, 'timeout_seconds' => @options.fetch(:timeout) },
                  'mac_format' => mac_format, 'phases' => @phases, 'artifacts' => artifacts, 'pairing_inert_root' => @pairing_contract, 'pairing_processes' => @pairing_processes,
                  'coverage' => { 'mac' => mac_methods, 'simulator' => sim_methods, 'intentional_simulator_skips' => SIMULATOR_SKIPS, 'pairing' => @pairing_methods,
                                  'rust' => rust_methods, 'beluga_core' => core_methods, 'shared_handoff' => handoff_methods, 'shared_replay' => replay_methods, 'shared_reconnect_counters' => reconnect_methods, 'shared_pairing_commit' => commit_methods, 'c' => c_methods } }
      path = File.join(@evidence, 'receipt.json')
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0600) { |file| file.write(JSON.pretty_generate(receipt) + "\n"); file.flush; file.fsync }
      digest = MicrophoneRegressionGate.sha(path)
      MicrophoneRegressionGate.verify_receipt(path, digest, @root)
      puts "microphone-regressions: PASS (offline source evidence only); receipt #{path}; sha256 #{digest}"
      path
    ensure
      @lock.close if @lock
    end
  end

  def self.verify_receipt(path, expected_digest, root, now = Time.now.to_i)
    require!(path.start_with?('/') && expected_digest.match?(/\A[0-9a-f]{64}\z/), 'receipt requires an absolute path and independently retained SHA-256')
    stat = regular!(path)
    require!(stat.uid == Process.uid && stat.nlink == 1 && (stat.mode & 0777) == 0600 && stat.size <= 8 * 1024 * 1024, 'receipt has unsafe owner, mode, links or size')
    parent = File.lstat(File.dirname(path))
    require!(parent.directory? && !parent.symlink? && parent.uid == Process.uid && (parent.mode & 0777) == 0700 &&
             File.realpath(File.dirname(path)) == File.dirname(path), 'receipt parent must be canonical, owner-owned and private mode 0700')
    require!(File.realpath(path) == path && sha(path) == expected_digest, 'receipt bytes or canonical path changed')
    receipt = parse_json(File.read(path), 'Receipt')
    exact_keys!(receipt, %w[schema status scope root created_at source tools simulator invocation mac_format phases artifacts coverage pairing_inert_root pairing_processes], 'receipt')
    require!(receipt['schema'] == SCHEMA && receipt['status'] == 'passed' && receipt['scope'] == 'offline-source-only' && receipt['root'] == File.realpath(root), 'wrong receipt identity or scope')
    require!(receipt['created_at'].is_a?(Integer) && receipt['created_at'] <= now && now - receipt['created_at'] <= 7 * 86400, 'future or expired receipt')
    require!(receipt['source'] == source_identity(root), 'receipt source identity is stale or changed')
    tools = receipt['tools']
    require!(tools.is_a?(Hash) && !tools.empty? && tools.any? { |tool, digest| tool.end_with?('/usr/bin/xcodebuild') && digest == XCODEBUILD_SHA256 } &&
             %w[swift swiftc clang lipo make ruby xcrun codesign cargo rustc node].all? { |name| tools.keys.any? { |tool| File.basename(tool) == name } } &&
             tools.keys.count { |tool| File.basename(tool) == 'node' } == 1, 'receipt lacks reviewed tool identities')
    require!(MicrophoneSimulatorSigning::DEPENDENCIES.all? { |tool| tools.key?(tool) }, 'receipt lacks exact Simulator signing tool identities')
    tools.each { |tool, digest| require!(tool.start_with?('/') && sha(tool) == digest, 'receipt tool identity drifted') }
    phases = receipt['phases']
    require!(phases.is_a?(Array) && phases.map { |entry| entry['name'] } == PHASES, 'receipt has absent, duplicate or reordered phases')
    directory = File.dirname(path)
    read_phase = lambda do |name|
      entry = phases.find { |candidate| candidate['name'] == name }
      exact_keys!(entry, %w[name argv log sha256], 'phase')
      require!(entry['log'] == name + '.log' && entry['argv'].is_a?(Array) && !entry['argv'].empty? && entry['argv'].all? { |arg| arg.is_a?(String) }, 'invalid phase invocation')
      log = File.join(directory, entry['log'])
      regular!(log)
      require!(sha(log) == entry['sha256'], 'phase log was changed')
      File.read(log)
    end
    PHASES.each { |name| read_phase.call(name) }
    validate_harness(read_phase.call('gate-self-tests'), gate_inventory(root))
    validate_simulator_signing_harness(read_phase.call('simulator-signing-self-tests'), simulator_signing_inventory(root))
    require!(read_phase.call('release-hook-self-tests').lines.map(&:chomp).count('microphone release gate behavior tests passed') == 1, 'release hook behavioral harness is incomplete')
    validate_host_release_harness(read_phase.call('host-release-hook-self-tests'))
    validate_mac_producer_harness(read_phase.call('mac-producer-contract-tests'), mac_producer_inventory(root))
    require!(read_phase.call('product-identity').lines.map(&:chomp).count('Beluga product identity check passed') == 1, 'product identity checker is incomplete')
    require!(read_phase.call('product-identity-mutations').lines.map(&:chomp).count('opensteamer product identity regression tests passed') == 1, 'product identity mutations are incomplete')
    validate_rust_artifacts(root)
    validate_beluga_core_artifacts(root)
    validate_beluga_core_link(read_phase.call('beluga-core-link'))
    validate_beluga_core_mutations(read_phase.call('beluga-core-mutations'))
    artifacts = receipt['artifacts']
    required_artifacts = %w[simulator-result driver-bundle-1 driver-bundle-2 simulator-app pairing-result pairing-app pairing-inert-root-contract]
    required_artifacts << 'mac-xunit' if receipt['mac_format'] == 'xunit'
    require!(artifacts.is_a?(Array) && artifacts.map { |entry| entry['name'] } == required_artifacts, 'receipt artifacts are incomplete or duplicated')
    check_artifacts = lambda do
      artifacts.each do |entry|
        exact_keys!(entry, %w[name path sha256 tree], 'artifact')
        relative = entry['path']
        require!(relative.is_a?(String) && !relative.start_with?('/') && !relative.split('/').include?('..'), 'artifact escapes receipt directory')
        artifact_path = File.join(directory, relative)
        require!(File.realpath(artifact_path) == artifact_path, 'artifact path is not canonical')
        observed = entry['tree'] == true ? tree_identity(artifact_path) : sha(artifact_path)
        require!(observed == entry['sha256'], 'artifact bytes changed')
      end
    end
    check_artifacts.call
    coverage = receipt['coverage']
    exact_keys!(coverage, %w[mac simulator intentional_simulator_skips pairing rust beluga_core shared_handoff shared_replay shared_reconnect_counters shared_pairing_commit c], 'coverage')
    mac = mac_inventory(read_phase.call('mac-discovery'))
    supported_player_inventory(root, read_phase.call('mac-discovery'))
    batch_a_native_inventory(root, read_phase.call('mac-discovery'))
    shared = shared_signaling_inventory(read_phase.call('mac-discovery'))
    replay = shared_replay_inventory(root, read_phase.call('mac-discovery'))
    reconnect = shared_reconnect_counter_inventory(root, read_phase.call('mac-discovery'))
    commit = shared_pairing_commit_inventory(root, read_phase.call('mac-discovery'))
    handoff = shared_handoff_inventory(read_phase.call('mac-discovery'))
    require!(coverage['mac'] == mac, 'Mac coverage differs from discovery')
    require!(coverage['shared_handoff'] == handoff, 'shared handoff coverage differs from discovery')
    require!(coverage['shared_replay'] == replay, 'shared replay coverage differs from exact source discovery')
    require!(coverage['shared_reconnect_counters'] == reconnect, 'shared reconnect counter coverage differs from exact source discovery')
    require!(coverage['shared_pairing_commit'] == commit, 'shared pairing commit coverage differs from exact source discovery')
    expected_commands = commands(root, directory, receipt['invocation'], tools, receipt['simulator'], mac, handoff)
    phases.each { |entry| require!(entry['argv'] == expected_commands.fetch(entry['name']), 'phase command does not match canonical offline invocation: ' + entry['name']) }
    validate_pairing_processes(receipt['pairing_processes'], expected_commands, (receipt['created_at'] + 1) * 1_000_000_000, receipt['invocation'].fetch('timeout_seconds'))
    if receipt['mac_format'] == 'xunit'
      xml = artifacts.find { |entry| entry['name'] == 'mac-xunit' }
      validate_xunit(File.read(File.join(directory, xml['path'])), mac)
    else
      require!(receipt['mac_format'] == 'darwin-xctest-log', 'unrecognized Mac result format')
      validate_mac_log(read_phase.call('mac-tests'), mac)
    end
    validate_shared_signaling(read_phase.call('shared-signaling-tests'), shared)
    SHARED_REPLAY_PHASES.each do |name, suite|
      validate_shared_replay(read_phase.call(name), replay.fetch(suite), suite)
    end
    validate_shared_reconnect_counter(read_phase.call(SHARED_RECONNECT_COUNTER_PHASE), reconnect)
    validate_shared_pairing_commit(read_phase.call(SHARED_PAIRING_COMMIT_PHASE), commit)
    validate_mac_log(read_phase.call('shared-handoff-tests'), handoff)
    sim = simulator_inventory(root)
    require!(coverage['simulator'] == sim && coverage['intentional_simulator_skips'] == SIMULATOR_SKIPS, 'Simulator coverage or skip contract changed')
    validate_simulator(parse_json(read_phase.call('simulator-summary'), 'Simulator summary'), parse_json(read_phase.call('simulator-results'), 'Simulator results'), sim, receipt['simulator'])
    pairing = pairing_inventory(root)
    require!(coverage['pairing'] == pairing, 'pairing coverage differs from exact source inventory')
    validate_pairing(parse_json(read_phase.call('pairing-summary'), 'pairing summary'), parse_json(read_phase.call('pairing-results'), 'pairing results'), pairing, receipt['simulator'])
    validate_pairing_contract(root, directory, receipt['invocation'], tools, read_phase.call('pairing-inert-build'), receipt['pairing_inert_root'], receipt['pairing_processes'].first)
    %w[pairing-result pairing-app pairing-inert-root-contract].zip(%w[pairing.xcresult pairing-app/Beluga.app pairing-inert-root-contract]).each do |name, relative|
      retained = artifacts.find { |entry| entry['name'] == name }
      require!(retained['path'] == relative && retained['tree'] == true, 'pairing evidence does not bind exact retained artifact path')
    end
    rust = rust_inventory(read_phase.call('rust-discovery'))
    require!(coverage['rust'] == rust, 'Rust coverage differs from discovery')
    validate_rust(read_phase.call('rust-tests'), rust)
    core = beluga_core_inventory(read_phase.call('beluga-core-discovery'))
    require!(coverage['beluga_core'] == core, 'Beluga core coverage differs from discovery')
    validate_rust(read_phase.call('beluga-core-tests'), core)
    native = c_inventory(root)
    require!(coverage['c'] == native, 'native inventory differs from source')
    validate_c(read_phase.call('driver-tests'), native)
    validate_c(read_phase.call('driver-sanitizers'), native, 2)
    require!(read_phase.call('driver-diagnostic-reader').lines.map(&:chomp).include?('DIAGNOSTIC_SNAPSHOT_READER_TESTS_PASSED_WITHOUT_CORE_AUDIO_IO'), 'diagnostic reader self-test is incomplete')
    require!(artifacts[1]['sha256'] == artifacts[2]['sha256'], 'universal driver builds differ')
    validate_driver_load(read_phase.call('driver-load'))
    require!(read_phase.call('driver-malformed-bundles').lines.map(&:chomp).include?('ALL_DRIVER_BUNDLE_VERIFIER_MUTATIONS_REJECTED'), 'driver malformed-bundle mutations are incomplete')
    sim_phase = phases.find { |entry| entry['name'] == 'simulator-tests' }['argv']
    require!(sim_phase.include?('platform=iOS Simulator,id=' + receipt['simulator']) && sim_phase.include?('DEVELOPMENT_TEAM=MSMG8CJLB3') && sim_phase.include?('CODE_SIGNING_ALLOWED=YES') &&
             SIMULATOR_CLASSES.all? { |name| sim_phase.include?('-only-testing:opensteamerTests/' + name) } &&
             sim_phase.none? { |arg| arg.start_with?('-skip-testing:') || arg == 'CODE_SIGNING_ALLOWED=NO' }, 'Simulator signing or whole-suite invocation changed')
    app = File.join(directory, 'simulator-app/Beluga.app')
    retained_app = artifacts.find { |entry| entry['name'] == 'simulator-app' }
    require!(retained_app['path'] == 'simulator-app/Beluga.app' && retained_app['tree'] == true,
             'Simulator signing evidence does not bind the retained app artifact')
    signed_record = parse_json(read_phase.call('simulator-entitlements'), 'Simulator signed identity')
    MicrophoneSimulatorSigning.validate_record(signed_record, expected_app: app)
    require!(MicrophoneSimulatorSigning.collect(app) == signed_record, 'retained Simulator signed identity changed')
    pairing_app = File.join(directory, 'pairing-app/Beluga.app')
    pairing_signed = parse_json(read_phase.call('pairing-entitlements'), 'pairing signed identity')
    MicrophoneSimulatorSigning.validate_record(pairing_signed, expected_app: pairing_app)
    require!(MicrophoneSimulatorSigning.collect(pairing_app) == pairing_signed, 'retained pairing signed identity changed')
    # Recollection invokes read-only tools. Fence the complete invocation again,
    # not just the main executable/Info bytes observed inside the collector.
    PHASES.each { |name| read_phase.call(name) }
    check_artifacts.call
    validate_pairing_contract(root, directory, receipt['invocation'], tools, read_phase.call('pairing-inert-build'), receipt['pairing_inert_root'], receipt['pairing_processes'].first)
    require!(receipt['source'] == source_identity(root), 'receipt source identity changed during verification')
    tools.each { |tool, digest| require!(sha(tool) == digest, 'receipt tool identity drifted during verification') }
    current = regular!(path)
    require!(current.nlink == 1 && MicrophoneSimulatorSigning.stat_record(current) == MicrophoneSimulatorSigning.stat_record(stat) &&
             File.realpath(path) == path && sha(path) == expected_digest, 'receipt bytes or filesystem identity changed during verification')
    require!(File.realpath(File.dirname(path)) == File.dirname(path) &&
             MicrophoneSimulatorSigning.stat_record(File.lstat(File.dirname(path))) == MicrophoneSimulatorSigning.stat_record(parent),
             'receipt parent identity changed during verification')
    receipt
  end

  def self.main(arguments)
    root = File.dirname(File.dirname(File.realpath(__FILE__)))
    if arguments == ['--verify-rust-artifact']
      validate_rust_artifacts(root)
      puts 'microphone-regressions: Rust source and published artifact checksums verified'
      return
    end
    if arguments == ['--verify-beluga-core-artifact']
      validate_beluga_core_artifacts(root)
      puts 'microphone-regressions: Beluga core source and published artifact checksums verified'
      return
    end
    if arguments == ['--help']
      puts 'DEVELOPER_DIR=/reviewed/Xcode.app/Contents/Developer scripts/validate-microphone-regressions.sh --scratch-path /existing/private/cache --simulator-udid UUID [--timeout-seconds 1..3600]'
      puts 'scripts/validate-microphone-regressions.sh --verify-receipt /absolute/receipt.json --receipt-sha256 independently-retained-sha256'
      puts 'Runs every offline microphone phase for every feature; preserves dedicated caches and creates fresh evidence. Does not prove physical audio, paired reconnect, installed driver, or deployment.'
      return
    end
    options = { timeout: 1800 }
    seen = Set.new
    until arguments.empty?
      key = arguments.shift
      require!(!seen.include?(key), 'duplicate option')
      seen << key
      require!(%w[--scratch-path --simulator-udid --timeout-seconds --verify-receipt --receipt-sha256].include?(key), 'unknown option')
      value = arguments.shift
      require!(value && !value.start_with?('--'), 'missing option value')
      case key
      when '--scratch-path' then options[:scratch] = value
      when '--simulator-udid' then options[:simulator] = value
      when '--verify-receipt' then options[:receipt] = value
      when '--receipt-sha256' then options[:digest] = value
      when '--timeout-seconds'
        require!(value.match?(/\A\d+\z/) && (1..3600).cover?(value.to_i), 'deadline must be 1 through 3600 seconds')
        options[:timeout] = value.to_i
      end
    end
    if options[:receipt]
      require!(seen.sort == %w[--receipt-sha256 --verify-receipt].sort, 'receipt verification accepts only receipt and digest')
      verify_receipt(options.fetch(:receipt), options.fetch(:digest), root)
      puts 'microphone-regressions: receipt verified for current source and tools (offline source evidence only)'
    else
      require!(options[:scratch] && options[:simulator] && !options[:digest], 'select explicit scratch and Simulator; receipt digest is verification-only')
      Runner.new(root, options).run
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    $stdout.sync = true
    MicrophoneRegressionGate.install_interrupt_handlers
    MicrophoneRegressionGate.main(ARGV.dup)
  rescue Interrupt
    warn 'microphone-regressions: FAIL: interrupted; owned subprocesses terminated'
    exit 130
  rescue StandardError => error
    warn 'microphone-regressions: FAIL: ' + error.message
    exit 1
  end
end
