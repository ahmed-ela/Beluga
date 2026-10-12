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
require_relative '../shared/Rust/BelugaCore/scripts/mutation-tests'

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
    src/display_admission.rs
    tests/display_admission.rs
    src/output_dimensions.rs
    tests/output_dimensions.rs
    src/ice_recovery.rs
    tests/ice_recovery.rs
    src/screen_liveness.rs
    src/screen_liveness_tests.rs
    src/update_operation.rs
    tests/update_operation.rs
    src/packet_send_queue.rs
    tests/packet_send_queue.rs
    src/rtt_evidence.rs
    tests/rtt_evidence.rs
    src/tier_demand.rs
    tests/tier_demand.rs
    src/media_command_gate.rs
    tests/media_command_gate.rs
    src/screen_suspension.rs
    tests/screen_suspension.rs
    src/phone_catalog.rs
    tests/phone_catalog.rs
    src/runtime_catalog.rs
    tests/runtime_catalog.rs
    src/update_admission.rs
    tests/update_admission.rs
    src/update_sparkle_admission.rs
    tests/update_sparkle_admission.rs
    src/network_adaptation_candidate/mod.rs
    src/network_adaptation_candidate/dependencies.rs
    src/network_adaptation_candidate/time_assignments.rs
    src/network_adaptation_candidate/diagnostics.rs
    src/network_adaptation_candidate/policy.rs
    src/network_adaptation_candidate/service.rs
    src/network_adaptation_candidate/bookkeeping.rs
    src/network_adaptation_candidate/state_codec.rs
    src/network_adaptation_candidate/bookkeeping_tests.rs
    src/network_adaptation_candidate/native_option_traces.rs
    src/network_adaptation_candidate/time_assignment_tests.rs
    src/network_adaptation_candidate/report_clock_tests.rs
    src/network_adaptation_candidate/preparation_clock_tests.rs
    src/network_adaptation_candidate/continuation_clock_tests.rs
    src/network_adaptation_candidate/collector_clock_tests.rs
    src/native_clock_assay.rs
    src/native_owner_codec.rs
    src/native_owner_events.rs
    src/network_adaptation_owner_events.rs
    src/network_adaptation_owner_events_tests.rs
    src/native_owner_clock_events.rs
    src/network_adaptation_owner_clocked_events.rs
    src/network_adaptation_owner_clocked_events_tests.rs
    src/network_adaptation_owner_prepare_events.rs
    src/network_adaptation_owner_prepare_events_tests.rs
    src/network_adaptation_owner_inactive_events.rs
    src/network_adaptation_owner_inactive_events_tests.rs
    src/network_adaptation_owner_begin_active_events.rs
    src/network_adaptation_owner_begin_active_events_tests.rs
    src/network_adaptation_owner_completion_events.rs
    src/network_adaptation_owner_completion_events_tests.rs
    src/network_adaptation_owner_failure_events.rs
    src/network_adaptation_owner_failure_events_tests.rs
    src/microphone_forwarding_evidence.rs
    tests/microphone_forwarding_evidence.rs
    src/microphone_forwarding_retry.rs
    tests/microphone_forwarding_retry.rs
    tests/owner_codec_golden.rs
    tests/owner_codec_ffi.rs
    tests/owner_event_ffi.rs
    src/update_unarmed_completion.rs
    tests/update_unarmed_completion.rs
    src/update_abort.rs
    tests/update_abort.rs
    src/handoff_source_position.rs
    tests/handoff_source_position.rs
    src/microphone_input_lease.rs
    tests/microphone_input_lease.rs
    src/microphone_output_format.rs
    tests/microphone_output_format.rs
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
                        YouTubeHandoffCoordinatorTests BelugaRustYouTubeHandoffOperationTests
    WorldwideICERecoveryPolicyReceiverTests
    WorldwideICERecoveryPolicyChainTests
    WorldwideScreenLivenessBridgeCustodyTests
  ].freeze
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
    WorldwideICERecoveryPolicyReceiverTests/testCurrentPolicyFaultClearsActualViewerAndJoinsNativeRetirement
    WorldwideICERecoveryPolicyReceiverTests/testCapturedOldPolicyFaultCannotCloseReplacementViewer
    WorldwideICERecoveryPolicyChainTests/testActualCorruptCheckingCResultRetiresMatchingViewerThroughInstalledCallbackOnce
    WorldwideICERecoveryPolicyChainTests/testDelayedActualCPolicyFaultCannotRetireReplacementViewerCoordinator
    WorldwideScreenLivenessBridgeCustodyTests/testBridgeFaultRetainsExplicitlyStaleEvidenceRefusesHeartbeatAndSuccessfulObservationRecovers
    WorldwideScreenLivenessBridgeCustodyTests/testBridgeFaultDuringNegotiationCannotReportRetainedSnapshotOrBurnSequence
    WorldwideScreenLivenessBridgeCustodyTests/testLaterFaultCannotTurnAcceptedSendCompletionIntoCurrentEvidenceStatus
    WorldwideScreenLivenessBridgeCustodyTests/testBridgeFaultDuringFalseNegotiationRetainsUnavailableStatusWithoutSendOrSequence
    WorldwideScreenLivenessBridgeCustodyTests/testLaterFaultCannotTurnThrowingSendCompletionIntoHeartbeatUnavailableStatus
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
    'macOS/Sources/CaptureServer/WorldwideIPhoneMicrophoneForwardingDriver.swift' => '6383ce54886f701081cd8de20a353df55785b23df9c34cfc6d258bd889b55a9c',
    'macOS/Sources/CaptureServer/WorldwideMacHostedCallPolicies.swift' => '4761079aad79da792df639bed0adfcac9848125a85523f332d265a1b235aaeee',
    'macOS/Sources/CaptureServer/WorldwideSafeOutputInvariantRetryPolicy.swift' => '75e12a1781ccb95f96f79215236b3cb3385803e3ef48f12916fd0751ee427d9b',
    'macOS/Sources/CaptureServer/WorldwideScreenService.swift' => 'db8a5a28db70cdc419ed3f88e0d1c0da9472d96655b3cc6cce52ce00b3ffb73a',
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

  DISPLAY_ADMISSION_NATIVE_SOURCE_SHA256 = {
    'macOS/Sources/CaptureCore/ScreenVideoOutputPolicy.swift' => '7dcdfa94e616edb69edebe7109ae008e5cf0b208c79878d489a57c050e4a8d36',
    'macOS/Tests/CaptureCoreTests/ScreenVideoOutputPolicyTests.swift' => 'dceb67808a0fc74debacf39f6a760881b95662b860a4e4182c3a4c0e4ca67de0',
    'macOS/Sources/CaptureCore/ScreenVideoCaptureSource.swift' => 'e84af22636a4b0539204186fa32045681af5452111bb96ee0ad147c441f3d1f9',
    'Package.swift' => '944f1b409c8018dc5b637958ac96d8b016cc152e8f000ea687855e0d3a93e715',
    'macOS/Sources/CaptureCore/BelugaRustDisplayAdmission.swift' => '24c40ee446d23e723e64f1e5242b923870ac1701e213b435a702ec344db33072',
    'macOS/Tests/CaptureCoreTests/ScreenVideoDisplayAdmissionOriginalReference.swift' => 'f55cad3d3145d80532b97f4fb95cfa6006e7233437391ac33bcbe81aa4f2155f',
    'macOS/Tests/CaptureCoreTests/ScreenVideoDisplayAdmissionRustTests.swift' => '9c9a77f12defb9a54d3ec61a674fc8405e92779787915dabf033dc08f4184605',
  }.freeze
  DISPLAY_ADMISSION_NATIVE_FILES = {
    'CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests' => 'macOS/Tests/CaptureCoreTests/ScreenVideoDisplayAdmissionRustTests.swift',
    'CaptureCoreTests.ScreenVideoOutputPolicyTests' => 'macOS/Tests/CaptureCoreTests/ScreenVideoOutputPolicyTests.swift',
  }.freeze
  DISPLAY_ADMISSION_NATIVE_PINNED = {
    'CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests' => %w[
      CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests/testCopiedABIHasSevenExactLayoutsAndAllFiftyTwoOffsets
      CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests/testDisplayRequirementActualCMatchesFrozenIdentityAndExactTopology
      CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests/testRawTopologyPreservesU64CountAndIgnoresAbsentSingletonOnlyWhenOptional
      CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests/testDimensionKindActualCMatchesFrozenIdentityWithoutIDNormalization
      CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests/testOrdinarySourceActualCPreservesSignedEndpointsAndIrrelevantNaNs
      CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests/testOwnedSourceActualCMatchesFrozenAdjacentFloatAndIntegerBoundaries
      CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests/testLegitimateOwnedAbsenceIsNilWhileMalformedBridgeThrows
      CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests/testStabilityActualCMatchesFrozenSignedDomainAndSingleAxisDrift
      CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests/testAllFourRawExportsHaveIndependentCanonicalEnvelopeRefusals
      CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests/testRequirementCopiedCResultCorruptionThrowsRatherThanFalseOrTrueFallback
      CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests/testKindCopiedCResultCorruptionThrowsBeforeAnyLogicalEarlyReturn
      CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests/testSourceCopiedCResultCorruptionThrowsRatherThanNilOrLogicalFallback
      CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests/testStabilityCopiedCResultCorruptionThrowsRatherThanFalseFallback
      CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests/testActualCInputsStayBitExactIncludingAbsentMetadataNaNAndSignedZero
      CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests/testTypedFacadePreservesHighBitIdentityTopologyKindAndOrdinarySourceAliases
      CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests/testTypedFacadeProjectsEveryRawInputBitAfterCallingActualC
    ],
    'CaptureCoreTests.ScreenVideoOutputPolicyTests' => %w[
      CaptureCoreTests.ScreenVideoOutputPolicyTests/testCaptureStartupRejectsFramebufferResolutionDrift
      CaptureCoreTests.ScreenVideoOutputPolicyTests/testOwnedDisplayRequirementAcceptsExactSoleMainIdentity
      CaptureCoreTests.ScreenVideoOutputPolicyTests/testOwnedDisplayRequirementRejectsRecycledIDIdentity
      CaptureCoreTests.ScreenVideoOutputPolicyTests/testOwnedDisplayRequirementRejectsTopologyDrift
      CaptureCoreTests.ScreenVideoOutputPolicyTests/testOrdinaryDisplayKeepsScreenCaptureKitLogicalDimensions
      CaptureCoreTests.ScreenVideoOutputPolicyTests/testOpenSteamerPhoneDisplayUsesFramebufferPixels
      CaptureCoreTests.ScreenVideoOutputPolicyTests/testOpenSteamerCombinedDisplayUsesFramebufferPixels
      CaptureCoreTests.ScreenVideoOutputPolicyTests/testMatchingProductFromAnotherVendorKeepsLogicalDimensions
      CaptureCoreTests.ScreenVideoOutputPolicyTests/testUnknownOpenSteamerProductKeepsLogicalDimensions
      CaptureCoreTests.ScreenVideoOutputPolicyTests/testOwnedDisplayResolvesEverySupportedSelectedFramebuffer
      CaptureCoreTests.ScreenVideoOutputPolicyTests/testOrdinaryDisplayIgnoresFilterPixelScale
      CaptureCoreTests.ScreenVideoOutputPolicyTests/testOwnedDisplayRejectsInvalidFilterGeometry
      CaptureCoreTests.ScreenVideoOutputPolicyTests/testOwnedDisplayRejectsFramebufferOverflow
      CaptureCoreTests.ScreenVideoOutputPolicyTests/testOwnedDisplayUsesCurrentCoreGraphicsFramebufferDespiteStaleFilterScale
      CaptureCoreTests.ScreenVideoOutputPolicyTests/testOwnedDisplayAcceptsOnlyReconciledFilterAndCoreGraphicsFramebuffer
      CaptureCoreTests.ScreenVideoOutputPolicyTests/testPhoneRetinaModeUsesFullFramebufferPixels
      CaptureCoreTests.ScreenVideoOutputPolicyTests/testLandscapeFramebufferScalesWithinWidthCap
      CaptureCoreTests.ScreenVideoOutputPolicyTests/testOddDimensionsRoundDownForVideoChromaPlanes
      CaptureCoreTests.ScreenVideoOutputPolicyTests/testInvalidDimensionsFailClosed
    ],
  }.transform_values(&:freeze).freeze

  OUTPUT_DIMENSIONS_SOURCE_SHA256 = {
    'shared/Rust/BelugaCore/src/output_dimensions.rs' => '7acbb390a74b9324a9ceddd49c258b74027f46c08ccac12425ca7c3a409ddfb2',
    'shared/Rust/BelugaCore/tests/output_dimensions.rs' => '2f72bcc2762c75f1e2100168a6a7fb4f876ab8de4f5c11b53b93789e59b740b7',
    'shared/Rust/BelugaCore/src/lib.rs' => '5a4db763fdef546ccdf9de324256f8b49c4ad9932e664432a93830ec46d55e2d',
    'shared/Rust/BelugaCore/include/beluga_core.h' => '2ea355f72241c8c62d0eb53b5d342784172637a305ffa3570b290814782d2dcd',
    'macOS/Sources/CaptureCore/ScreenVideoOutputPolicy.swift' => '7dcdfa94e616edb69edebe7109ae008e5cf0b208c79878d489a57c050e4a8d36',
    'macOS/Sources/CaptureCore/BelugaRustOutputDimensions.swift' => '411410bdd9624df3aec1357a622146ecdf03d524b3564598e51409f409aab129',
    'macOS/Tests/CaptureCoreTests/ScreenVideoOutputDimensionsOriginalReference.swift' => 'd770ac0d4e0688009d15f593d84cc3e412372e222ae69b7ca3e6d98acabfd79d',
    'macOS/Tests/CaptureCoreTests/ScreenVideoOutputDimensionsRustTests.swift' => '5117e0e2dc2ffff362e964703a633fe43b7a55c71fed46c246d5ba0b3bce8623',
  }.freeze
  OUTPUT_DIMENSIONS_NATIVE_FILES = {
    'CaptureCoreTests.ScreenVideoOutputDimensionsRustTests' => 'macOS/Tests/CaptureCoreTests/ScreenVideoOutputDimensionsRustTests.swift',
  }.freeze
  OUTPUT_DIMENSIONS_NATIVE_PINNED = {
    'CaptureCoreTests.ScreenVideoOutputDimensionsRustTests' => %w[
      CaptureCoreTests.ScreenVideoOutputDimensionsRustTests/testActualCOutputHasTwoExactLayoutsAndAllTwelveOffsets
      CaptureCoreTests.ScreenVideoOutputDimensionsRustTests/testActualCAndTypedOutputMatchIndependentLiteralModesAndFrozenOriginal
      CaptureCoreTests.ScreenVideoOutputDimensionsRustTests/testRepresentableSignedMatrixMatchesFrozenOriginalWithoutNewCaps
      CaptureCoreTests.ScreenVideoOutputDimensionsRustTests/testEachInvalidSignedSlotKeepsOriginalErrorAndCanonicalNoArithmeticPayload
      CaptureCoreTests.ScreenVideoOutputDimensionsRustTests/testNearestPositiveTiesAndMinimumHeightRemainOriginal
      CaptureCoreTests.ScreenVideoOutputDimensionsRustTests/testOriginalFloatingPrecisionLossAndRepresentableUpperNeighborRemainExact
      CaptureCoreTests.ScreenVideoOutputDimensionsRustTests/testFormerTwoToSixtyThreeConversionTrapIsDistinctTypedErrorNotDimensions
      CaptureCoreTests.ScreenVideoOutputDimensionsRustTests/testMaximumSignedHeightCanRemainRepresentableAfterWidthCapping
      CaptureCoreTests.ScreenVideoOutputDimensionsRustTests/testTypedFacadeRecordsFullSignedInputWordsOnlyAfterActualC
      CaptureCoreTests.ScreenVideoOutputDimensionsRustTests/testMalformedRawInputEnvelopeIsRefusedWithoutLegitimateOutcome
      CaptureCoreTests.ScreenVideoOutputDimensionsRustTests/testEveryCopiedResultFieldCorruptionThrowsBridgeErrorAfterActualC
      CaptureCoreTests.ScreenVideoOutputDimensionsRustTests/testInvalidAndOutOfRangeResultsCannotForgeDimensionsOrOtherErrors
      CaptureCoreTests.ScreenVideoOutputDimensionsRustTests/testRoundedPositiveZeroCannotBeSilentlyNormalizedToNegativeZero
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
    CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests
    CaptureCoreTests.ScreenVideoOutputPolicyTests
    CaptureCoreTests.ScreenVideoOutputDimensionsRustTests
    CaptureServerTests.WorldwideICERecoveryPolicyReceiverTests
    CaptureServerTests.WorldwideICERecoveryPolicyChainTests
    CaptureServerTests.BelugaUpdateOperationTests
    CaptureServerTests.BelugaUpdateBrokerSessionTests
    CaptureServerTests.BelugaUpdateFenceStoreTests
    CaptureServerTests.BelugaUpdateOperationRustCustodyTests
    CaptureServerTests.BelugaRustPacketSendQueueTests
    CaptureServerTests.BelugaRustRoundTripTimeEvidenceTests
    CaptureServerTests.BelugaRustTierDemandTests
    CaptureServerTests.BelugaRustMediaCommandGateTests
    CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests
    CaptureServerTests.BelugaRustPhoneCatalogNativeParityTests
    CaptureServerTests.BelugaRustRuntimeCatalogTests
    CaptureServerTests.WorldwideRuntimeCatalogAdmissionActorTests
    CaptureServerTests.WorldwideRuntimeCatalogBridgeFaultActorTests
    CaptureServerTests.BelugaUpdateControllerTests
    CaptureServerTests.BelugaRustSparkleAdmissionTests
    CaptureServerTests.BelugaRustUpdateAvailabilityTests
    CaptureServerTests.BelugaRustMicrophoneForwardingEvidenceTests
    CaptureServerTests.BelugaRustMicrophoneForwardingRetryTests
    CaptureServerTests.BelugaRustUnarmedCompletionTests
    CaptureServerTests.BelugaUpdateSparkleFinishedCycleTests
    CaptureServerTests.BelugaRustUpdateAbortTests
    CaptureServerTests.BelugaRustMacChromeHandoffSourcePolicyTests
    CaptureServerTests.BelugaRustMicrophoneInputLeaseTests
    CaptureServerTests.BelugaRustMicrophoneOutputFormatTests
    CaptureServerTests.BelugaRenderedAXBridgeTests
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
    CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests/testCopiedABIHasSevenExactLayoutsAndAllFiftyTwoOffsets
    CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests/testDisplayRequirementActualCMatchesFrozenIdentityAndExactTopology
    CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests/testRawTopologyPreservesU64CountAndIgnoresAbsentSingletonOnlyWhenOptional
    CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests/testDimensionKindActualCMatchesFrozenIdentityWithoutIDNormalization
    CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests/testOrdinarySourceActualCPreservesSignedEndpointsAndIrrelevantNaNs
    CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests/testOwnedSourceActualCMatchesFrozenAdjacentFloatAndIntegerBoundaries
    CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests/testLegitimateOwnedAbsenceIsNilWhileMalformedBridgeThrows
    CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests/testStabilityActualCMatchesFrozenSignedDomainAndSingleAxisDrift
    CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests/testAllFourRawExportsHaveIndependentCanonicalEnvelopeRefusals
    CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests/testRequirementCopiedCResultCorruptionThrowsRatherThanFalseOrTrueFallback
    CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests/testKindCopiedCResultCorruptionThrowsBeforeAnyLogicalEarlyReturn
    CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests/testSourceCopiedCResultCorruptionThrowsRatherThanNilOrLogicalFallback
    CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests/testStabilityCopiedCResultCorruptionThrowsRatherThanFalseFallback
    CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests/testActualCInputsStayBitExactIncludingAbsentMetadataNaNAndSignedZero
    CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests/testTypedFacadePreservesHighBitIdentityTopologyKindAndOrdinarySourceAliases
    CaptureCoreTests.ScreenVideoDisplayAdmissionRustTests/testTypedFacadeProjectsEveryRawInputBitAfterCallingActualC
    CaptureCoreTests.ScreenVideoOutputPolicyTests/testCaptureStartupRejectsFramebufferResolutionDrift
    CaptureCoreTests.ScreenVideoOutputPolicyTests/testOwnedDisplayRequirementAcceptsExactSoleMainIdentity
    CaptureCoreTests.ScreenVideoOutputPolicyTests/testOwnedDisplayRequirementRejectsRecycledIDIdentity
    CaptureCoreTests.ScreenVideoOutputPolicyTests/testOwnedDisplayRequirementRejectsTopologyDrift
    CaptureCoreTests.ScreenVideoOutputPolicyTests/testOrdinaryDisplayKeepsScreenCaptureKitLogicalDimensions
    CaptureCoreTests.ScreenVideoOutputPolicyTests/testOpenSteamerPhoneDisplayUsesFramebufferPixels
    CaptureCoreTests.ScreenVideoOutputPolicyTests/testOpenSteamerCombinedDisplayUsesFramebufferPixels
    CaptureCoreTests.ScreenVideoOutputPolicyTests/testMatchingProductFromAnotherVendorKeepsLogicalDimensions
    CaptureCoreTests.ScreenVideoOutputPolicyTests/testUnknownOpenSteamerProductKeepsLogicalDimensions
    CaptureCoreTests.ScreenVideoOutputPolicyTests/testOwnedDisplayResolvesEverySupportedSelectedFramebuffer
    CaptureCoreTests.ScreenVideoOutputPolicyTests/testOrdinaryDisplayIgnoresFilterPixelScale
    CaptureCoreTests.ScreenVideoOutputPolicyTests/testOwnedDisplayRejectsInvalidFilterGeometry
    CaptureCoreTests.ScreenVideoOutputPolicyTests/testOwnedDisplayRejectsFramebufferOverflow
    CaptureCoreTests.ScreenVideoOutputPolicyTests/testOwnedDisplayUsesCurrentCoreGraphicsFramebufferDespiteStaleFilterScale
    CaptureCoreTests.ScreenVideoOutputPolicyTests/testOwnedDisplayAcceptsOnlyReconciledFilterAndCoreGraphicsFramebuffer
    CaptureCoreTests.ScreenVideoOutputPolicyTests/testPhoneRetinaModeUsesFullFramebufferPixels
    CaptureCoreTests.ScreenVideoOutputPolicyTests/testLandscapeFramebufferScalesWithinWidthCap
    CaptureCoreTests.ScreenVideoOutputPolicyTests/testOddDimensionsRoundDownForVideoChromaPlanes
    CaptureCoreTests.ScreenVideoOutputPolicyTests/testInvalidDimensionsFailClosed
    CaptureCoreTests.ScreenVideoOutputDimensionsRustTests/testActualCOutputHasTwoExactLayoutsAndAllTwelveOffsets
    CaptureCoreTests.ScreenVideoOutputDimensionsRustTests/testActualCAndTypedOutputMatchIndependentLiteralModesAndFrozenOriginal
    CaptureCoreTests.ScreenVideoOutputDimensionsRustTests/testRepresentableSignedMatrixMatchesFrozenOriginalWithoutNewCaps
    CaptureCoreTests.ScreenVideoOutputDimensionsRustTests/testEachInvalidSignedSlotKeepsOriginalErrorAndCanonicalNoArithmeticPayload
    CaptureCoreTests.ScreenVideoOutputDimensionsRustTests/testNearestPositiveTiesAndMinimumHeightRemainOriginal
    CaptureCoreTests.ScreenVideoOutputDimensionsRustTests/testOriginalFloatingPrecisionLossAndRepresentableUpperNeighborRemainExact
    CaptureCoreTests.ScreenVideoOutputDimensionsRustTests/testFormerTwoToSixtyThreeConversionTrapIsDistinctTypedErrorNotDimensions
    CaptureCoreTests.ScreenVideoOutputDimensionsRustTests/testMaximumSignedHeightCanRemainRepresentableAfterWidthCapping
    CaptureCoreTests.ScreenVideoOutputDimensionsRustTests/testTypedFacadeRecordsFullSignedInputWordsOnlyAfterActualC
    CaptureCoreTests.ScreenVideoOutputDimensionsRustTests/testMalformedRawInputEnvelopeIsRefusedWithoutLegitimateOutcome
    CaptureCoreTests.ScreenVideoOutputDimensionsRustTests/testEveryCopiedResultFieldCorruptionThrowsBridgeErrorAfterActualC
    CaptureCoreTests.ScreenVideoOutputDimensionsRustTests/testInvalidAndOutOfRangeResultsCannotForgeDimensionsOrOtherErrors
    CaptureCoreTests.ScreenVideoOutputDimensionsRustTests/testRoundedPositiveZeroCannotBeSilentlyNormalizedToNegativeZero
    CaptureServerTests.WorldwideICERecoveryPolicyReceiverTests/testCurrentPolicyFaultStopsActualInertServiceAndJoinsCleanup
    CaptureServerTests.WorldwideICERecoveryPolicyReceiverTests/testCapturedOldPolicyFaultCannotStopReplacementInertGeneration
    CaptureServerTests.WorldwideICERecoveryPolicyChainTests/testActualCorruptCheckingCResultStopsMatchingHostThroughInstalledCallbackOnce
    CaptureServerTests.WorldwideICERecoveryPolicyChainTests/testDelayedActualCPolicyFaultCannotStopReplacementHostCoordinator
    CaptureServerTests.WorldwidePreparedMediaMenuIntegrationTests/testDirectReadyBRetainsPreparedAUntilAuthenticatedReconnectReplacesIt
    CaptureServerTests.BelugaUpdateBrokerSessionTests/testAbsentFenceAndHighBuildNeverInferControlledHistory
    CaptureServerTests.BelugaUpdateBrokerSessionTests/testCancelAndDeclineNeverBorrowOtherCandidateOrArmedAuthority
    CaptureServerTests.BelugaUpdateBrokerSessionTests/testCompetingLeasePreventsVerificationAndAnyMarkerCreation
    CaptureServerTests.BelugaUpdateBrokerSessionTests/testControlledFreshNoUpdateRetiresOnlyPreparedFenceThenReleasesLease
    CaptureServerTests.BelugaUpdateBrokerSessionTests/testCrashClosesLeaseButRestoredMarkerBlocksAnotherCycle
    CaptureServerTests.BelugaUpdateBrokerSessionTests/testCrossThreadGettersDuringSDKCallbackAreBoundedAndMatchPublishedState
    CaptureServerTests.BelugaUpdateBrokerSessionTests/testDeclinedCandidateRechecksNativeProofAndUnchangedPredecessor
    CaptureServerTests.BelugaUpdateBrokerSessionTests/testDeniedControlledHistoryBeforePreparationCannotStartSDK
    CaptureServerTests.BelugaUpdateBrokerSessionTests/testDeniedInstallAuthorizationKeepsUnarmedMarkerAndLease
    CaptureServerTests.BelugaUpdateBrokerSessionTests/testDuplicateStartNeverInvokesSDKAgain
    CaptureServerTests.BelugaUpdateBrokerSessionTests/testFailedFinalClearAndCancellationRetainExactFenceAndCompetingLease
    CaptureServerTests.BelugaUpdateBrokerSessionTests/testFailedPredecessorVerificationRetainsLeaseWithoutStartingUpdater
    CaptureServerTests.BelugaUpdateBrokerSessionTests/testFreshExplicitCancelOrDeclineReleasesOnlyTheMatchingUnarmedRecord
    CaptureServerTests.BelugaUpdateBrokerSessionTests/testFreshReplacementContextAndProvenReadinessClearFenceBeforeLeaseRelease
    CaptureServerTests.BelugaUpdateBrokerSessionTests/testIdenticalBytesWithReplacedMarkerInodeRejectBeforeUpdaterStart
    CaptureServerTests.BelugaUpdateBrokerSessionTests/testMismatchedInstalledIdentityCannotManufactureCandidateOrCompletion
    CaptureServerTests.BelugaUpdateBrokerSessionTests/testNoUpdateCannotRetireCandidateArmedCancelledOrFailedOperation
    CaptureServerTests.BelugaUpdateBrokerSessionTests/testNoUpdateFinalProofRevalidatesHistorySDKContextAndExactPreparedInode
    CaptureServerTests.BelugaUpdateBrokerSessionTests/testNoUpdateWrongBindingNonceOrPredecessorCannotClear
    CaptureServerTests.BelugaUpdateBrokerSessionTests/testOperationMismatchCannotStartOrModifyTheMarker
    CaptureServerTests.BelugaUpdateBrokerSessionTests/testPreparationOwnsLeaseBeforeVerificationAndStoragePrecedesUpdaterStart
    CaptureServerTests.BelugaUpdateBrokerSessionTests/testPreparedCrashCannotRestoreControlledNoUpdateAuthority
    CaptureServerTests.BelugaUpdateBrokerSessionTests/testReadinessChallengeIsOneUseAndCancellationCannotRetireMarker
    CaptureServerTests.BelugaUpdateBrokerSessionTests/testRejectedReentryAfterIrreversibleClearCannotRegressSuccessfulCommit
    CaptureServerTests.BelugaUpdateBrokerSessionTests/testRepeatedInstallAuthorizationStillRevalidatesCurrentMarker
    CaptureServerTests.BelugaUpdateBrokerSessionTests/testSDKStartupRequiresExactStagedBrokerBinding
    CaptureServerTests.BelugaUpdateBrokerSessionTests/testStorageRevalidationFailureNeverReturnsInstallAuthorization
    CaptureServerTests.BelugaUpdateBrokerSessionTests/testSwallowedSynchronousReentryFailsOuterSDKStartClosed
    CaptureServerTests.BelugaUpdateBrokerSessionTests/testThrowingStartIsConsumedAndRetainsPreparedFenceAndLease
    CaptureServerTests.BelugaUpdateFenceStoreTests/testAbsentReadDoesNotCreateDirectoryOrMarker
    CaptureServerTests.BelugaUpdateFenceStoreTests/testBrokerBindingCanPublishOnceWhilePreparedAndCannotDisappearOrChange
    CaptureServerTests.BelugaUpdateFenceStoreTests/testExactFreshCompletionAndReadinessCanClearOnlyCurrentTerminal
    CaptureServerTests.BelugaUpdateFenceStoreTests/testExclusiveCreateAndReadRestoreBlockedPreparedOperation
    CaptureServerTests.BelugaUpdateFenceStoreTests/testInitialBrokerPublicationCannotSkipPreparedStage
    CaptureServerTests.BelugaUpdateFenceStoreTests/testMalformedOversizeDuplicateAndTrailingRecordsFailClosed
    CaptureServerTests.BelugaUpdateFenceStoreTests/testOperationTargetPredecessorAndMenuBindingsCannotChange
    CaptureServerTests.BelugaUpdateFenceStoreTests/testPreparedMarkerNeverClearsOnIdleCancelFailureOrExit
    CaptureServerTests.BelugaUpdateFenceStoreTests/testPureMetadataGuardsRejectForeignOwnersLinksAndSpecialModes
    CaptureServerTests.BelugaUpdateFenceStoreTests/testReplacementAdvancesSameOperationAndRejectsStaleSnapshot
    CaptureServerTests.BelugaUpdateFenceStoreTests/testRestoredTerminalCannotBePersistedAsNewAuthorityOrClearFence
    CaptureServerTests.BelugaUpdateFenceStoreTests/testSameBytesNewInodeOrNewDirectoryCannotSatisfyOldSnapshot
    CaptureServerTests.BelugaUpdateFenceStoreTests/testSecondCreateNeverOverwritesExactOrDifferentOperation
    CaptureServerTests.BelugaUpdateFenceStoreTests/testStagesAndBoundCandidateCannotRegressOrChange
    CaptureServerTests.BelugaUpdateFenceStoreTests/testSymlinkHardlinkWrongModeAndNonRegularMarkerAreRejected
    CaptureServerTests.BelugaUpdateFenceStoreTests/testSymlinkOrPublicServiceDirectoryIsNeverFollowedOrRepaired
    CaptureServerTests.BelugaUpdateFenceStoreTests/testWrongEffectiveUIDAndNonPreparedCreatePerformNoWrites
    CaptureServerTests.BelugaUpdateOperationRustCustodyTests/testCanonicalWireAndAsymmetricHistoricalRecordShapesAreUnchanged
    CaptureServerTests.BelugaUpdateOperationRustCustodyTests/testClosedTrueRuntimePredicateIsRejectedAfterActualCResultWithoutGrantingActivation
    CaptureServerTests.BelugaUpdateOperationRustCustodyTests/testCopiedABILayoutUsesOnlyExactWordStructs
    CaptureServerTests.BelugaUpdateOperationRustCustodyTests/testDeniedVoidObservationsAreBoundaryFaultsNotSilentRetentionOfFreshProof
    CaptureServerTests.BelugaUpdateOperationRustCustodyTests/testEqualityIgnoresProducerClosureButIncludesEveryEphemeralProofAndValueFault
    CaptureServerTests.BelugaUpdateOperationRustCustodyTests/testExactNativeBindingNonceAndReadinessFactsAreCopiedNotBroadAuthority
    CaptureServerTests.BelugaUpdateOperationRustCustodyTests/testMalformedQueriesDenyImmediatelyButDoNotMutateOrLatchAnOperationValue
    CaptureServerTests.BelugaUpdateOperationRustCustodyTests/testMalformedVoidObserveDeniesFreshReleaseWithoutPublishingOrPoisoningCopies
    CaptureServerTests.BelugaUpdateOperationRustCustodyTests/testMutationResultCorruptionsPublishNoNativeValueOrWireAndLatchLocalFault
    CaptureServerTests.BelugaUpdateOperationRustCustodyTests/testNewValidatedInstanceIsOnlyMutationFaultRecoveryAndNeverRestoresFreshProof
    CaptureServerTests.BelugaUpdateOperationRustCustodyTests/testOrdinaryClosedMutationDenialIsNotABridgeFaultAndCanRetry
    CaptureServerTests.BelugaUpdateOperationRustCustodyTests/testOversizedTerminalEncodingDeniesCommitWithoutLosingOriginalFreshChallenge
    CaptureServerTests.BelugaUpdateOperationRustCustodyTests/testReadinessPreflightDenialNeverCommitsAndCommitCorruptionNeverPublishes
    CaptureServerTests.BelugaUpdateOperationRustCustodyTests/testReadinessUsesTwoCallsOnOriginalSnapshotAndExactNativeEncodingBoundFact
    CaptureServerTests.BelugaUpdateOperationTests/testArmingMayPrecedeCandidateDiscoveryButUnknownCandidateCannotFinish
    CaptureServerTests.BelugaUpdateOperationTests/testBoundedCanonicalRecordRejectsOversizeWhitespaceAndDuplicateKeys
    CaptureServerTests.BelugaUpdateOperationTests/testBrokerCDHashAndRestoredNestedBindingAreStrictlyValidated
    CaptureServerTests.BelugaUpdateOperationTests/testBrokerIsExactOneTimePreparedBindingAndCannotChangeAfterArming
    CaptureServerTests.BelugaUpdateOperationTests/testCandidateIsOnceBoundAndRejectsRegressionsOrChangedInstalledBytes
    CaptureServerTests.BelugaUpdateOperationTests/testDecoderRevalidatesNestedIdentitiesInsteadOfTrustingSynthesizedCodable
    CaptureServerTests.BelugaUpdateOperationTests/testEveryRestoredStageIsBlockedAndOldReadinessCannotAuthorizeRecovery
    CaptureServerTests.BelugaUpdateOperationTests/testExactFreshTerminalAndNewMenuProofPermitOnlyFenceRelease
    CaptureServerTests.BelugaUpdateOperationTests/testFreshReadinessRequiresDifferentMenuAndExactOneUseChallenge
    CaptureServerTests.BelugaUpdateOperationTests/testMissingHistoricalBrokerBindingStaysFencedWithoutInventingFreshAuthority
    CaptureServerTests.BelugaUpdateOperationTests/testNonTerminalEventsNeverClearTheStickyArmingStage
    CaptureServerTests.BelugaUpdateOperationTests/testPreparedOrReplayedTerminalAndReadinessCannotSkipStages
    CaptureServerTests.BelugaUpdateOperationTests/testRestoreRejectsWrongExpectedBindingsAndUnknownOrIncompleteSchema
    CaptureServerTests.BelugaUpdateOperationTests/testTargetAndArtifactValidationAreLexicalNotFilesystemOperations
    CaptureServerTests.BelugaUpdateOperationTests/testUnserializableOversizedTerminalRecordCannotGrantRelease
    CaptureServerTests.BelugaUpdateOperationTests/testWrongOperationTargetAndUIDCannotAdvanceAnyAuthority
    CaptureServerTests.BelugaRustPacketSendQueueTests/testActualCThreeLayoutsAndAllThirtyOneOffsets
    CaptureServerTests.BelugaRustPacketSendQueueTests/testOrdinaryCounterAndPartialBaselineMatrixMatchesFrozenOriginal
    CaptureServerTests.BelugaRustPacketSendQueueTests/testCurrentFloatAndOptionalRejectionsClearWithoutLosingValidSignedZero
    CaptureServerTests.BelugaRustPacketSendQueueTests/testThresholdNeighborsKeepOriginalInclusiveAndExclusiveDecisions
    CaptureServerTests.BelugaRustPacketSendQueueTests/testExactLeaseAgesIncludeBoundaryButNotOneAttosecondBeyondOrBeforeZero
    CaptureServerTests.BelugaRustPacketSendQueueTests/testSoftPressureSaturatesAndFreshRTTDoesNotCountQueuePressureTwice
    CaptureServerTests.BelugaRustPacketSendQueueTests/testCapacityRawBaselineKeepsOriginalNonfiniteAndPartialSemantics
    CaptureServerTests.BelugaRustPacketSendQueueTests/testCapacityCannotStampRenewOrConsumeOrdinaryLeasesAndPressure
    CaptureServerTests.BelugaRustPacketSendQueueTests/testTierResetRetainsCounterBaselineWhilePathResetRetiresIt
    CaptureServerTests.BelugaRustPacketSendQueueTests/testMalformedABIFieldsRejectWithCanonicalEmptyResultForEveryOpcode
    CaptureServerTests.BelugaRustPacketSendQueueTests/testFacadeOrdinarySequencePublishesOnlyActualCStateAndExactNativeStamps
    CaptureServerTests.BelugaRustPacketSendQueueTests/testFacadeResetUsesEmptyEventAfterAdvancingNativeLowOrSoftLease
    CaptureServerTests.BelugaRustPacketSendQueueTests/testFacadeEveryForgedResultWordAfterActualCRejectsAndLatchesClosed
    CaptureServerTests.BelugaRustPacketSendQueueTests/testFacadeFaultCannotResumeByResetCounterRepairOrCapacityFallback
    CaptureServerTests.BelugaRustPacketSendQueueTests/testFacadeCapacityUsesActualTemporaryBaselineAndRejectsForgeryWithoutOrdinaryMutation
    CaptureServerTests.BelugaRustRoundTripTimeEvidenceTests/testActualCFourLayoutsFiftyOffsetsAndArrayWidths
    CaptureServerTests.BelugaRustRoundTripTimeEvidenceTests/testLegacyBootstrapMissingAndStrictUnavailableKeepOriginalDistinction
    CaptureServerTests.BelugaRustRoundTripTimeEvidenceTests/testNativeDistinctReferenceLearningNeverLearnsDuplicatesOrInflation
    CaptureServerTests.BelugaRustRoundTripTimeEvidenceTests/testInclusiveInflationAndFloatBoundariesPreservePreAndPostLearning
    CaptureServerTests.BelugaRustRoundTripTimeEvidenceTests/testFullCountersAndIndependentAdvancementRetainExactUInt64
    CaptureServerTests.BelugaRustRoundTripTimeEvidenceTests/testInvalidTelemetryAndExplicitFingerprintLengthAreUnknownNotABIRejection
    CaptureServerTests.BelugaRustRoundTripTimeEvidenceTests/testPairABARegressionAndScalarContradictionConsumeIdentityOnce
    CaptureServerTests.BelugaRustRoundTripTimeEvidenceTests/testSignedExactAgeBoundariesAndDuplicateLeasesNeverRenew
    CaptureServerTests.BelugaRustRoundTripTimeEvidenceTests/testLifecycleAndRejectedIdentityOperationsPreserveDistinctOriginalState
    CaptureServerTests.BelugaRustRoundTripTimeEvidenceTests/testFastPositiveAndAdmittedFailedApplyCopyOnlyFenceWithoutRenewal
    CaptureServerTests.BelugaRustRoundTripTimeEvidenceTests/testFastNegativeTombstonesPoisonButFreshPressureRemainsForOrdinaryOnce
    CaptureServerTests.BelugaRustRoundTripTimeEvidenceTests/testFastRouteAndPrimaryLeaseAreEvaluatedBeforeCloneAdvancement
    CaptureServerTests.BelugaRustRoundTripTimeEvidenceTests/testInvalidABIStateAndEventRejectWithExactBeforeStateAndZeroAuthority
    CaptureServerTests.BelugaRustRoundTripTimeEvidenceTests/testEveryCopiedResultWordIsDeniedAndFacadeFaultIsSticky
    CaptureServerTests.BelugaRustRoundTripTimeEvidenceTests/testFacadeNamedClockOperationsFastProjectionAndReplacementMatchActualC
    CaptureServerTests.BelugaRustTierDemandTests/testActualCTwoLayoutsAndAllTwentyThreeOffsets
    CaptureServerTests.BelugaRustTierDemandTests/testAbsentBandwidthProfilesMatchFrozenReferenceForAllTiersAndBoundaryCaps
    CaptureServerTests.BelugaRustTierDemandTests/testSustainableTierEveryDemandBoundaryAndAdjacentDoubles
    CaptureServerTests.BelugaRustTierDemandTests/testUpgradeAdmissionEveryMarginAndConfiguredClampBoundary
    CaptureServerTests.BelugaRustTierDemandTests/testConfiguredVideoBudgetFlooringAndFullUInt32CapRange
    CaptureServerTests.BelugaRustTierDemandTests/testLiteralCeilingArtifactsAndCalibratedDemandAreNotRationalized
    CaptureServerTests.BelugaRustTierDemandTests/testInitialTierPreservesSurvivalCeilingAtEveryConfiguredDemandBoundary
    CaptureServerTests.BelugaRustTierDemandTests/testMalformedFactDomainsReturnCanonicalDenialAndVerifierRefusesIt
    CaptureServerTests.BelugaRustTierDemandTests/testEveryCopiedProjectionByteIsRejectedByActualExportedVerifier
    CaptureServerTests.BelugaRustTierDemandTests/testFacadeCachesOnlyVerifiedImmutableProfilesAndUsesOneActualDynamicProjection
    CaptureServerTests.BelugaRustTierDemandTests/testFacadeDynamicFailureIsStickyWithoutFallbackOrFurtherProducerCalls
    CaptureServerTests.BelugaRustTierDemandTests/testPublicPolicyInitializationDenialCannotArmAnySpeculativePermission
    CaptureServerTests.BelugaRustTierDemandTests/testPublicPolicyDynamicDenialRetiresConfirmedProbeAndCannotRearm
    CaptureServerTests.BelugaRustTierDemandTests/testPublicPolicySamePeerFaultCustodyCannotPoisonForeignPeerOrImportPositiveState
    CaptureServerTests.BelugaRustMediaCommandGateTests/testActualCThreeLayoutsAndAllFifteenOffsets
    CaptureServerTests.BelugaRustMediaCommandGateTests/testActualCInitialOpenCloseAndRepeatedTransitionsMatchFrozenOriginal
    CaptureServerTests.BelugaRustMediaCommandGateTests/testActualCInvalidationAndNativeRemoveReaddMatchOriginalOwner
    CaptureServerTests.BelugaRustMediaCommandGateTests/testNativeMembershipUsesSwiftEqualityAndPreservesCapturedUTF8Spelling
    CaptureServerTests.BelugaRustMediaCommandGateTests/testActualCFullUInt64WrapAndIndependentCountersMatchFrozenOriginal
    CaptureServerTests.BelugaRustMediaCommandGateTests/testEveryMalformedStateEventAndUnusedWordReturnsCanonicalDenial
    CaptureServerTests.BelugaRustMediaCommandGateTests/testActualVerifierRejectsEveryCopiedResultByteIncludingQueryState
    CaptureServerTests.BelugaRustMediaCommandGateTests/testActualFacadeEveryOpcodeDenialRetainsStateAndLatchesWithoutFurtherCalls
    CaptureServerTests.BelugaRustMediaCommandGateTests/testActualLockedOwnerEveryOpcodeDenialRetainsContextAndNoAuthorityCanResume
    CaptureServerTests.BelugaRustMediaCommandGateTests/testFirstDeniedClosePreservesSetAndLaterFaultedCloseClearsOnlySet
    CaptureServerTests.BelugaRustMediaCommandGateTests/testOrdinaryNativeRefusalAndUnchangedContextAssignmentsNeverFaultOrRotate
    CaptureServerTests.BelugaRustMediaCommandGateTests/testControllerMalformedOpenCannotStartPollingOrGrantPreparedWork
    CaptureServerTests.BelugaRustMediaCommandGateTests/testControllerMalformedCaptureCannotPrepareACommandOrHandoff
    CaptureServerTests.BelugaRustMediaCommandGateTests/testControllerMalformedQueuedOrFinalAdmissionCannotDispatchNativeCommand
    CaptureServerTests.BelugaRustMediaCommandGateTests/testControllerMalformedQueuedOrFinalHandoffAdmissionCannotAttemptNativePause
    CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testActualCLayoutsAndEveryThirtyThreeFieldOffsets
    CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testActualCCompleteNinePhaseTranscriptAndProjection
    CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testActualCBothConfirmationOrdersSameEpochAndRebinding
    CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testActualCUnnegotiatedAndInvalidBindingsPreserveWholeState
    CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testActualCStaleBindingRefusalMatrixAcrossEveryPhase
    CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testActualCWholePhaseEventAdmissionAndRefusalMatrix
    CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testActualCGenerationWrapAndRetireActivateNeverRewind
    CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testActualCAbortRestoresPriorCompletedProvenanceWithOrWithoutCover
    CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testActualCCancelAllOwnedPhasesButNeverOrdinaryActive
    CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testActualCReplacementShowProtectsAgainstStaleCleanupAndRollback
    CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testActualCVerifierRejectsEveryOneHundredTwentyEightCopiedResultBytes
    CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testActualCMalformedStateAndUnusedEventFieldsAreCanonicalDenials
    CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeWholeTranscriptAndDeepCustodyMatchFrozenReference
    CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativePhaseEventRefusalAndFullWidthBindingsMatchFrozenReference
    CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeWholePhaseEventAdmissionAndRefusalMatrix
    CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeFixedSeededChurnUsesFrozenExpectationsWithoutNativeEffects
    CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeBothJoinOrdersPublishPartialNoneActionAndReboundBinding
    CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeProvenanceAbortCancelRollbackAndReplacementIsolation
    CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeMarkerReadyAndExactEchoKeepEntirePayloadDomain
    CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeMarkerPresentationRejectsInvalidReceiverSourceShapeAndDeepEcho
    CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeResumeReadyPreservesSeparateRTPDomainsAndSerialLimits
    CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeResumeRequestAndFinalizationRequireFullNestedEquality
    CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeUnicodeEqualityPreservesIncomingReceiverSpelling
    CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeValueCopiesRemainIndependentAcrossEveryPhase
    CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeDeepCustodyValidatorRejectsForeignUUIDNoticeAndExtraStandaloneProofs
    CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeDeepCustodyValidatorRejectsInvalidNestedLeafAndPriorProvenance
    CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeEveryMutatingOpcodeRejectsCopiedResultWithoutPartialPublication
    CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeBeginRejectsEveryCopiedResultByteAndRetainsGenerator
    CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeNonmutatingQueryDenialNeverPoisonsOwnerOrCopy
    CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeNonmutatingCopiedRefusalCannotForgeAuthorityGrant
    CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeFaultInOneCopyCannotPoisonHealthySiblingOrClearRetainedDiagnostic
    CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeInitialProjectionCopiedResultFailureLatchesWithoutGrant
    CaptureServerTests.BelugaRustPhoneCatalogNativeParityTests/testNativeGoldenAllCountsOccupiedSlotsAndSelectionsPreserveCompleteCustody
    CaptureServerTests.BelugaRustPhoneCatalogNativeParityTests/testNativeMaximumRevisionAllowsExactNoopAndOperationErrorsBeatExhaustion
    CaptureServerTests.BelugaRustPhoneCatalogNativeParityTests/testNativeDualUInt64CountersAndRevisionSuccessorRemainExactAboveSignedRange
    CaptureServerTests.BelugaRustPhoneCatalogNativeParityTests/testNativeActualCryptoRecoveryStatesMatchOriginalTransitionAndCachedCommitRules
    CaptureServerTests.BelugaRustPhoneCatalogNativeParityTests/testNativeDuplicateAxesBeatCapacityAndBindingBeatsBothCounterRegressions
    CaptureServerTests.BelugaRustPhoneCatalogNativeParityTests/testNativeBadCurrentPrecedesStaleTokenAndStaleTokenSuppressesCandidateValidation
    CaptureServerTests.BelugaRustPhoneCatalogNativeParityTests/testNativeLoadedAdmissionOrderingReceiptLifetimeAndDecodeBridgePropagation
    CaptureServerTests.BelugaRustPhoneCatalogNativeParityTests/testNativeBeforeWriteFailureRetainsBytesAndOldTokenCanRetry
    CaptureServerTests.BelugaRustPhoneCatalogNativeParityTests/testNativeWriteThenThrowLeavesDurableSuccessorAndOldTokenRetryIsStale
    CaptureServerTests.BelugaRustPhoneCatalogNativeParityTests/testNativeActualProducerStageTraceKeepsOriginalLazyCuts
    CaptureServerTests.BelugaRustPhoneCatalogNativeParityTests/testNativeEveryByteOfActualCopiedResultRejectsAtEveryUsedStageWithZeroWrites
    CaptureServerTests.BelugaRustPhoneCatalogNativeParityTests/testNativeMalformedInputTagsAndUnusedFieldsCannotBecomeCheckedBusinessResults
    CaptureServerTests.BelugaRustPhoneCatalogNativeParityTests/testNativeConcurrentSameTokenHasExactlyOneWinnerAcrossTwoInstances
    CaptureServerTests.BelugaRustRuntimeCatalogTests/testExactLinkedLayoutAndAllNativeStageIDs
    CaptureServerTests.BelugaRustRuntimeCatalogTests/testFirstPairGrantIsHistoricalAndConsumedBeforeBootstrapStop
    CaptureServerTests.BelugaRustRuntimeCatalogTests/testValidRefusalPreservesStateWithoutPoisonAndNativeErrorOrdering
    CaptureServerTests.BelugaRustRuntimeCatalogTests/testMalformedResultCannotInstallStateOrGrantAuthority
    CaptureServerTests.BelugaRustRuntimeCatalogTests/testEveryResultByteBitIsRejectedBeforeNativeStateAdoptionAndPoisonIsSticky
    CaptureServerTests.BelugaRustRuntimeCatalogTests/testMalformedEventEchoCannotBecomeVerifiedSuccess
    CaptureServerTests.BelugaRustRuntimeCatalogTests/testCallerCannotRecreateConsumedFirstPairGrant
    CaptureServerTests.BelugaRustRuntimeCatalogTests/testRevokedCopiedAuthorityAllowsOnlyExactRetainedDrainNotNewAdmission
    CaptureServerTests.WorldwideRuntimeCatalogAdmissionActorTests/testFrozenQuietOwnerFreshCatalogTicketOrderingKeepsNativeCallbacksLazy
    CaptureServerTests.WorldwideRuntimeCatalogAdmissionActorTests/testFrozenFirstPairReferenceConsumesIntentOnceAndKeepsReadbackAuthoritySeparate
    CaptureServerTests.WorldwideRuntimeCatalogAdmissionActorTests/testDefaultMutationCapabilityRefusesBeforeRetiringWaitingClient
    CaptureServerTests.WorldwideRuntimeCatalogAdmissionActorTests/testSelectionWaitsForReturnedExactOldCloseAndIndependentlyHeldAvailabilityTask
    CaptureServerTests.WorldwideRuntimeCatalogAdmissionActorTests/testForeignDurableWriteWhileExactOldTaskIsHeldPreventsMutationAndRecovery
    CaptureServerTests.WorldwideRuntimeCatalogAdmissionActorTests/testCancelledSelectStillDrainsThenAppliesOriginalSelectionSemantics
    CaptureServerTests.WorldwideRuntimeCatalogAdmissionActorTests/testCancelledPairAnotherRecoversOnlyAfterExactOldTaskTerminalBoundary
    CaptureServerTests.WorldwideRuntimeCatalogAdmissionActorTests/testStopJoinsRetainedAvailabilityTaskAndPreventsLateSelection
    CaptureServerTests.WorldwideRuntimeCatalogAdmissionActorTests/testPostDrainMutationDenialResumesUnchangedSelectionWithoutGrantingMutationTicket
    CaptureServerTests.WorldwideRuntimeCatalogAdmissionActorTests/testSelectionWriteFailureRecoversOnlyExactUnchangedDurablePredecessor
    CaptureServerTests.WorldwideRuntimeCatalogAdmissionActorTests/testFirstPairSelectionUsesExactActiveReadbackOnlyAfterOwnedBootstrapTeardown
    CaptureServerTests.WorldwideRuntimeCatalogAdmissionActorTests/testFirstPairOwnerAndMutationRevalidationPreserveDistinctPostTeardownCuts
    CaptureServerTests.WorldwideRuntimeCatalogAdmissionActorTests/testFirstPairHeldTeardownRejectsSameTokenDifferentCompleteNativeCheckpoint
    CaptureServerTests.WorldwideRuntimeCatalogAdmissionActorTests/testStoppedFirstPairLateOwnedCallbackCannotSelectIntoFreshCoordinator
    CaptureServerTests.WorldwideRuntimeCatalogBridgeFaultActorTests/testStartupInstalledFaultRejectsBeforeActorAdoptionAndRemainsSticky
    CaptureServerTests.WorldwideRuntimeCatalogBridgeFaultActorTests/testCorruptFinalEndDeniesSelectSuccessWithoutRollingBackActualDurableWrite
    CaptureServerTests.WorldwideRuntimeCatalogBridgeFaultActorTests/testCorruptFinalEndDeniesForgetSuccessWithoutRestoringDeletedTrust
    CaptureServerTests.WorldwideRuntimeCatalogBridgeFaultActorTests/testCorruptFinalEndDeniesPairInvitationSuccessAndClosesExactBootstrap
    CaptureServerTests.WorldwideRuntimeCatalogBridgeFaultActorTests/testMalformedAdmissionKeepsLiveNativeClientUntilAuthorizedStopAndNeverReproposes
    CaptureServerTests.WorldwideRuntimeCatalogBridgeFaultActorTests/testMalformedWhileRetirementHeldRetainsExactTaskForStopDrainWithoutWriteOrSuccessor
    CaptureServerTests.WorldwideRuntimeCatalogBridgeFaultActorTests/testRetiredGenerationTerminalDoesNotConsumeArmedFaultOrTearDownSuccessor
    CaptureServerTests.BelugaUpdateControllerTests/testIdleCheckIsExplicitSerialAndReenablesOnlyAfterWorkerCompletion
    CaptureServerTests.BelugaUpdateControllerTests/testPendingMarkerBlocksBeforeUIAndReadinessRunsExactlyOnce
    CaptureServerTests.BelugaUpdateControllerTests/testReadinessAndCheckFailureStayBlockedWithoutAutomaticRetry
    CaptureServerTests.BelugaUpdateControllerTests/testActiveMediaPairingSharingAndTeardownDenyCheckWithoutWorker
    CaptureServerTests.BelugaUpdateControllerTests/testActualRustMenuPolicyKeepsCorruptedPlanBlockedAndNeverStartsWorker
    CaptureServerTests.BelugaUpdateControllerTests/testEveryNativeAdmissionCombinationUsesRustWithoutDispatching
    CaptureServerTests.BelugaUpdateControllerTests/testBusyPlanRefusalAfterTaskCreationNeverEntersCheckOrReadinessWorker
    CaptureServerTests.BelugaRustSparkleAdmissionTests/testExactLayoutsAndTwelveOriginalGuardCombinationsThroughActualABI
    CaptureServerTests.BelugaRustSparkleAdmissionTests/testUnknownABIPhaseAndEveryPhaseSpecificUnknownFlagRefuse
    CaptureServerTests.BelugaRustSparkleAdmissionTests/testEveryResultFieldAndCoherentWrongActionsAreCorrelatedToActualRequest
    CaptureServerTests.BelugaRustSparkleAdmissionTests/testQueryAndAdmissionCannotCrossVerifiedPhasesAndValidDenialsStayValid
    CaptureServerTests.BelugaRustUpdateAvailabilityTests/testExactCopiedLayoutsAndAll512OriginalPolicyCombinations
    CaptureServerTests.BelugaRustUpdateAvailabilityTests/testUnknownABIAndEveryUnknownFlagDenyWithoutForeignAuthority
    CaptureServerTests.BelugaRustUpdateAvailabilityTests/testEveryCopiedResultFieldIsVerifiedAgainstTheActualRequest
    CaptureServerTests.BelugaRustUpdateAvailabilityTests/testCoherentForeignPlansCannotGrantOrEraseRecoveryAndNoFallbackExists
    CaptureServerTests.BelugaRustMicrophoneForwardingEvidenceTests/testReadinessMatchesBothOriginalIndependentVotes
    CaptureServerTests.BelugaRustMicrophoneForwardingEvidenceTests/testWatermarkMatchesOriginalGuardedTransitionAndOptionalHistories
    CaptureServerTests.BelugaRustMicrophoneForwardingEvidenceTests/testFreshnessMatchesOriginalConditionalClockAndExactDeadline
    CaptureServerTests.BelugaRustMicrophoneForwardingEvidenceTests/testReadinessRejectsEveryReturnedByteAndLatchesWithoutFallback
    CaptureServerTests.BelugaRustMicrophoneForwardingEvidenceTests/testWatermarkRejectsEveryReturnedByteWithoutChangingNativeHistory
    CaptureServerTests.BelugaRustMicrophoneForwardingEvidenceTests/testCorruptedFirstFreshnessResultNeverReadsNativeClock
    CaptureServerTests.BelugaRustMicrophoneForwardingEvidenceTests/testCorruptedSecondFreshnessResultReadsOnceButPublishesNoDecision
    CaptureServerTests.BelugaRustMicrophoneForwardingEvidenceTests/testInvalidStatusZeroNeverBecomesLegitimateFalseAcrossFamilies
    CaptureServerTests.BelugaRustMicrophoneForwardingRetryTests/testLiteralLayoutsOffsetsAndDiscriminants
    CaptureServerTests.BelugaRustMicrophoneForwardingRetryTests/testEligibilityLiteralAbsencePermissionFaultAndStrictBoundary
    CaptureServerTests.BelugaRustMicrophoneForwardingRetryTests/testRecordLiteralIncrementConsumesPermissionAndRejectsOverflow
    CaptureServerTests.BelugaRustMicrophoneForwardingRetryTests/testAllElevenFailureCategoriesHaveLiteralVotes
    CaptureServerTests.BelugaRustMicrophoneForwardingRetryTests/testRetryFalsePreservesPriorPermissionAndNeverCreatesHistory
    CaptureServerTests.BelugaRustMicrophoneForwardingRetryTests/testLiteralDefaultThreeAndMaximumOneSequences
    CaptureServerTests.BelugaRustMicrophoneForwardingRetryTests/testFixedExhaustAfterRefusalRetainsAbsentRedriveAndClosesPresentPermission
    CaptureServerTests.BelugaRustMicrophoneForwardingRetryTests/testMalformedInputsAndMatchingInvalidStatusZeroNeverBecomeFalseVotes
    CaptureServerTests.BelugaRustMicrophoneForwardingRetryTests/testEveryReturnedByteIsCorrelatedForEveryOperation
    CaptureServerTests.BelugaRustMicrophoneForwardingRetryTests/testAcceptedFalseCorrelationAndCoherentDecisionFlips
    CaptureServerTests.BelugaUpdateSparkleSessionTests/testCheckPrefixNeverQueriesNativeAuthorityForIneligibleCallbacks
    CaptureServerTests.BelugaUpdateSparkleSessionTests/testAuthorityReentryConsumesFreshRequestAndOuterDenialPreservesNestedCycle
    CaptureServerTests.BelugaUpdateSparkleSessionTests/testAuthorityCompletionReentryReadsFreshRequestWithoutNewStateGuard
    CaptureServerTests.BelugaUpdateSparkleSessionTests/testCopiedPolicyRefusalNeverQueriesOrConsumesPendingNativeRequest
    CaptureServerTests.BelugaUpdateSparkleSessionTests/testCoherentWrongPhaseResultsCannotQueryOrAdmitNativeCycle
    CaptureServerTests.BelugaUpdateSparkleSessionTests/testOuterCopiedRefusalPreservesNestedAdmissionAndConsumedRequest
    CaptureServerTests.BelugaRustUnarmedCompletionTests/testExactLayoutsAndAllSixLiteralReasonsThroughActualCAndPacking
    CaptureServerTests.BelugaRustUnarmedCompletionTests/testEveryBitPackingAndOriginalCandidateAndFoundItemOmissions
    CaptureServerTests.BelugaRustUnarmedCompletionTests/testUnsupportedABISeparateFailureKindAndEveryUnknownFlagRefuse
    CaptureServerTests.BelugaRustUnarmedCompletionTests/testWholeResultAndCoherentCrossRequestReasonsCannotManufactureCompletion
    CaptureServerTests.BelugaUpdateSparkleFinishedCycleTests/testFinishedCycleEarlierEligibilityFailuresSkipSDKGetterAndAuthority
    CaptureServerTests.BelugaUpdateSparkleFinishedCycleTests/testFinishedCycleIdleGetterPrecedesInitialAuthorityAndDenialSkipsLaterQueries
    CaptureServerTests.BelugaUpdateSparkleFinishedCycleTests/testFinishedCycleInitialAuthorityReentrySelectsFreshAcknowledgedAndAbortedFailure
    CaptureServerTests.BelugaUpdateSparkleFinishedCycleTests/testFinishedCycleInitialAuthorityReentrySelectsFreshCancellationAfterPresentation
    CaptureServerTests.BelugaUpdateSparkleFinishedCycleTests/testFinishedCycleInitialAuthorityReentrySelectsFreshDeclineAndExactNativePayload
    CaptureServerTests.BelugaUpdateSparkleFinishedCycleTests/testFinishedCycleInitialAuthorityReentrySelectsFreshNoUpdateIdentity
    CaptureServerTests.BelugaUpdateSparkleFinishedCycleTests/testFinishedCycleNestedObservationClearsOuterProofBeforeRetirement
    CaptureServerTests.BelugaUpdateSparkleFinishedCycleTests/testFinishedCycleSDKGetterReentryCreatesFreshNoUpdateBeforeAuthority
    CaptureServerTests.BelugaUpdateSparkleFinishedCycleTests/testFinishedCycleSuccessfulPairHasExactSDKAuthorityAndRetirementOrder
    CaptureServerTests.BelugaUpdateSparkleSessionTests/testActualPrivateBrokerUnarmedProducerABIControlHasAttributedLeaseWitness
    CaptureServerTests.BelugaUpdateSparkleSessionTests/testActualPrivateBrokerUnarmedVerifierTwoControlHasAttributedLeaseWitness
    CaptureServerTests.BelugaRustUpdateAbortTests/testExactRequestAndResultLayoutsThroughActualC
    CaptureServerTests.BelugaRustUpdateAbortTests/testAllSixFactBitsAndOriginalFirstIfPriorityThroughActualClassify
    CaptureServerTests.BelugaRustUpdateAbortTests/testUnknownABIAndEveryUnknownFlagRefuse
    CaptureServerTests.BelugaRustUpdateAbortTests/testWholeResultFieldsAndCoherentWrongSupportedActionsRefuse
    CaptureServerTests.BelugaUpdateSparkleSessionTests/testMatchedAbortPreservesNativeNSErrorIdentityAndObservation
    CaptureServerTests.BelugaUpdateSparkleSessionTests/testDuplicateAcknowledgedAbortPoisonsWhileStillDeliveringOriginalEvent
    CaptureServerTests.BelugaUpdateSparkleSessionTests/testActualPrivateBrokerAbortProducerABIControlHasAttributedLeaseWitness
    CaptureServerTests.BelugaUpdateSparkleSessionTests/testActualPrivateBrokerAbortVerifierTwoControlHasAttributedLeaseWitness
    CaptureServerTests.BelugaUpdateSparkleSessionTests/testActualPrivateBrokerAbortCoherentActionControlHasAttributedLeaseWitness
    CaptureServerTests.BelugaRustMacChromeHandoffSourcePolicyTests/testImportedLayoutsAndEveryNumericPrepareAxisAgainstFrozenNativeReducer
    CaptureServerTests.BelugaRustMacChromeHandoffSourcePolicyTests/testOptionalPresenceAndNativeCapabilityAdmissionRemainExact
    CaptureServerTests.BelugaRustMacChromeHandoffSourcePolicyTests/testEveryCurrentNumericMatchAxisAndNilAgainstFrozenNativeReducer
    CaptureServerTests.BelugaRustMacChromeHandoffSourcePolicyTests/testNativeMatchStringFactsAreExactNotUUIDNormalizationOrHashAuthority
    CaptureServerTests.BelugaRustMacChromeHandoffSourcePolicyTests/testMatchToleranceBoundariesAndNoConstructorRevalidation
    CaptureServerTests.BelugaRustMacChromeHandoffSourcePolicyTests/testAdmittedAnchorNumericAxesRemainUnrewrittenAtMatchesBoundary
    CaptureServerTests.BelugaRustMacChromeHandoffSourcePolicyTests/testRawMatchPredicateHasNoExtraAnchorCapturePolicyOrFusedArithmetic
    CaptureServerTests.BelugaRustMacChromeHandoffSourcePolicyTests/testMalformedABIReservedAndUnknownFlagsFailClosedButMissingFactsAreOrdinaryRefusal
    CaptureServerTests.BelugaRustMacChromeHandoffSourcePolicyTests/testForeignResultsAndEveryCopiedResultFieldUseActualRustValidators
    CaptureServerTests.BelugaRustMicrophoneInputLeaseTests/testInputLeaseLiteralLayoutsAndAllFourCopiedOperations
    CaptureServerTests.BelugaRustMicrophoneInputLeaseTests/testInputLeaseNativeIntegerBoundaryAndNoSuccessfulSwiftFallback
    CaptureServerTests.BelugaRustMicrophoneInputLeaseTests/testInputLeaseWholeResultRejectsEveryFieldAndCoherentWrongAction
    CaptureServerTests.BelugaRustMicrophoneInputLeaseTests/testInputLeaseMalformedFactsRemainRefusedEvenWithCanonicalInvalidResult
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testRustInputLeaseAdmissionPreservesClampedOneAndLiteralThreeBudgets
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testRustInputLeaseNativeOutcomeKeepsProofLazyAndTerminalCleanupExact
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testRustInputLeaseReleaseVoteKeepsOneExactCleanupEpisodeAndExternalFence
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testRustInputLeaseRetainedCleanupRedrivesOnSameHealthyIdentityWithoutReadmission
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testNativeReleaseProtectionRetainsNestedUncertaintyAndExactPendingCleanup
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testNativeReleaseContextRetainsNestedNewerPeerWhenOwnerDoesNotChange
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testNativeReleaseContextRetainsNestedMonitorWhenOwnerDoesNotChange
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testNativeReleaseContextRetainsNestedDeviceSnapshotWhenOwnerDoesNotChange
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testNativeReleaseEpisodePreservesReentrantReplacementForEveryActualDisposition
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testNativeReleaseEpisodeDoesNotOverwriteReentrantNewerHealthyPeer
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testNativeReleaseEpisodeDoesNotOverwriteReentrantMonitorEpoch
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testNativeReleaseEpisodeFencesSameGenerationAuthorizationChange
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testNativeReleaseEpisodeStopsBeforeGenerationlessShutdownAfterNestedCleanup
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testRustInputLeaseActualCRefusalAfterAcquiredKeepsExactCleanupOwnership
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testRustInputLeaseActualCRefusalAtPostKeyLoopBudgetKeepsExactCleanupOwnership
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testRustInputLeaseActualCRefusalAfterFirstRetryableReleaseKeepsExactCleanupOwnership
    CaptureServerTests.BelugaRustMicrophoneOutputFormatTests/testOutputFormatLiteralLayoutsAndEveryFieldOffset
    CaptureServerTests.BelugaRustMicrophoneOutputFormatTests/testOutputFormatExactSuccessAndSDKLiteralParity
    CaptureServerTests.BelugaRustMicrophoneOutputFormatTests/testOutputFormatAllSixteenKnownRejectionsMatchOriginalSwift
    CaptureServerTests.BelugaRustMicrophoneOutputFormatTests/testOutputFormatEverySimultaneousErrorPairKeepsOriginalFirstGuard
    CaptureServerTests.BelugaRustMicrophoneOutputFormatTests/testOutputFormatAllFourSignedStatusExtremesPreserveOriginalDiagnostics
    CaptureServerTests.BelugaRustMicrophoneOutputFormatTests/testOutputFormatAllUInt32DomainsStayExactAndFullWidth
    CaptureServerTests.BelugaRustMicrophoneOutputFormatTests/testOutputFormatRateEdgeCasesAndNaNPayloadsMatchOriginalBits
    CaptureServerTests.BelugaRustMicrophoneOutputFormatTests/testOutputFormatCopiesAllNativeReadValuesWithoutNormalization
    CaptureServerTests.BelugaRustMicrophoneOutputFormatTests/testOutputFormatWholeResultRejectsAllTwentyFieldCorruptions
    CaptureServerTests.BelugaRustMicrophoneOutputFormatTests/testOutputFormatWholeResultRejectsCoherentWrongDecision
    CaptureServerTests.BelugaRustMicrophoneOutputFormatTests/testOutputFormatMalformedWireThrowsWithoutSwiftFallback
    CaptureServerTests.BelugaMediaHandoffMenuTests/testRenderedControlObservesStartupDisconnectReconnectOnSameHostingView
    CaptureServerTests.BelugaMediaHandoffMenuTests/testRenderedPressKeepsExactTargetAndObservesInFlightCompletion
    CaptureServerTests.BelugaMediaHandoffMenuTests/testRenderedUpdaterDisablesWithoutHidingOrDispatchingOnSameHost
    CaptureServerTests.BelugaMediaHandoffMenuTests/testRenderedControlKeepsObservationAfterSameHostDetachReattach
    CaptureServerTests.BelugaRenderedAXBridgeTests/testWrongReturnSignaturesRefuseBeforeInvocation
    CaptureServerTests.BelugaRenderedAXBridgeTests/testDeniedAndMalformedPermissionsRefuseBeforeTargetInvocation
    CaptureServerTests.BelugaRenderedAXBridgeTests/testMissingTitleOnlyIsOptionalAndDeclaredNilTitleIsSeparate
    CaptureServerTests.BelugaRenderedAXBridgeTests/testTextBoundCoversAllPropertiesBeforeOutputAndCountsUTF16
    CaptureServerTests.BelugaRenderedAXBridgeTests/testChildrenBoundAndWrongObjectTypeRefuseBeforeOutput
    CaptureServerTests.BelugaRenderedAXBridgeTests/testProviderExceptionsAreExplicitForAllThreeEntryPoints
    CaptureServerTests.BelugaRenderedAXBridgeTests/testGenuineNoIsSuccessfulNotMissingOrFailed
    CaptureServerTests.BelugaRenderedAXBridgeTests/testRoleSpecificRequiredTextHonorsDenialAndExactRoleCardinality
    CaptureServerTests.BelugaMediaHandoffMenuTests/testActualMenuPopoverReopensWithCurrentSessionWithoutReplacingContent
    CaptureServerTests.BelugaMediaHandoffMenuTests/testActualMenuPopoverCompositorShowsPersistentControlAcrossReconnect
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
    display_admission_all_seven_layouts_and_every_field_offset_are_literal
    display_requirement_each_original_identity_and_liveness_guard_is_independent
    display_requirement_sole_topology_is_exact_singleton_including_duplicates
    display_requirement_sole_main_mismatch_alone_refuses
    display_requirement_optional_topology_ignores_main_count_and_singleton
    display_requirement_identity_and_display_ids_preserve_zero_and_u32_maximum
    source_kind_frozen_literal_table_selects_only_the_two_owned_products
    source_kind_cartesian_boundaries_match_independent_frozen_native
    source_dimensions_all_twenty_nine_supported_native_modes_return_exact_pixels
    ordinary_source_preserves_entire_signed_domain_before_any_metadata_guard
    owned_source_logical_width_and_height_minimum_are_two
    owned_source_logical_width_and_height_maximum_are_32768
    owned_source_pixel_width_and_height_minimum_are_two
    owned_source_pixel_width_and_height_maximum_are_32768
    owned_source_core_graphics_logical_minimum_literals_and_exact_snapshot_equality
    owned_source_core_graphics_width_snapshot_mismatch_alone_refuses
    owned_source_core_graphics_height_snapshot_mismatch_alone_refuses
    owned_source_filter_width_must_be_finite
    owned_source_filter_height_must_be_finite
    owned_source_scale_includes_one_and_four_and_refuses_actual_double_neighbors
    owned_source_filter_width_half_pixel_boundary_is_inclusive_both_directions
    owned_source_filter_height_half_pixel_boundary_is_inclusive_both_directions
    owned_source_returns_current_framebuffer_independent_of_scale_ratio_or_rounding
    owned_source_literal_startup_geometry_trace_covers_stale_scale_and_refusals
    owned_source_cartesian_integer_and_float_boundaries_match_frozen_native
    source_stability_requires_both_dimensions_exactly_equal_without_sanity_limits
    source_stability_literal_startup_trace_refuses_single_axis_drift_and_recovers
    display_requirement_unknown_abi_is_invalid_independent_of_policy_result
    display_requirement_reserved_is_invalid_independent_of_policy_result
    display_requirement_each_raw_boolean_domain_is_closed_even_if_ignored
    source_kind_unknown_abi_and_reserved_are_independent_invalid_inputs
    source_dimensions_invalid_bridge_is_distinct_from_legitimate_owned_absence
    source_stability_unknown_abi_and_reserved_are_independent_invalid_inputs
    display_admission_all_copied_inputs_remain_exact_including_nan_payload_bits
    source_kind_and_dimensions_high_bit_identity_aliases_remain_ordinary
    output_abi_has_exact_two_layouts_and_twelve_offsets
    output_literal_supported_modes_preserve_cap_round_even_and_height_floor
    output_each_original_signed_guard_refuses_before_arithmetic
    output_width_cap_is_a_minimum_without_upscaling
    output_even_width_is_chosen_before_scaling
    output_positive_half_ties_round_away_before_even_height
    output_non_ties_keep_nearest_not_floor_or_ceil
    output_height_chroma_adjustment_rounds_down_after_nearest
    output_height_floor_keeps_two_when_scaled_rounds_to_zero_or_one
    output_float_multiply_then_divide_is_not_integer_ratio
    output_full_signed_projection_does_not_narrow_source_or_cap
    output_original_f64_precision_loss_is_not_replaced_by_exact_rational_or_height_cap
    output_two_to_sixty_three_is_distinct_refusal_not_saturation_or_dimensions
    output_adjacent_representable_upper_value_still_returns_dimensions
    output_maximum_height_can_remain_representable_after_width_capping
    output_malformed_envelope_is_not_a_legitimate_dimension_error
    output_copies_have_no_state_or_mutating_input_ownership
    ice_layouts_and_offsets_are_exact
    ice_initializer_preserves_full_positive_int64_domain
    ice_initializer_refuses_nonpositive_reserved_and_noncanonical
    ice_abi_refuses_zero_and_high_alias
    ice_grace_acceleration_advances_epoch_and_coalesces_attempts
    ice_zero_grace_starts_attempting_without_grace_effect
    ice_success_wait_retry_then_exactly_once_exhaustion
    ice_failed_restart_consumes_attempt_and_skips_timeout
    ice_each_failed_sleep_stops_then_same_epoch_finish_resets_idle
    ice_epoch_wrap_zero_is_a_current_workflow
    ice_maximum_final_attempt_does_not_increment_past_int64
    ice_connection_resets_exhaustion_and_preserves_wrapping
    ice_direct_cancel_repeats_but_cancelled_ice_signals_do_not
    ice_cancel_retains_delivered_flag_but_clears_attempts
    ice_stale_restart_and_noncooperative_sleep_have_no_successor
    ice_task_cancellation_admission_stops_but_finish_is_epoch_only
    ice_stale_finish_cannot_release_replacement_task
    ice_exhaust_admission_observes_late_task_cancellation
    ice_new_checking_unknown_never_start_recovery
    ice_current_wait_kind_and_program_counter_are_exact
    ice_event_envelope_rejects_alias_boolean_reserved_and_unused_fields
    ice_state_envelope_rejects_every_closed_field_corruption
    ice_finish_preserves_cancelled_and_exhausted_terminal_state
    ice_all_active_phases_coalesce_failed_and_requested
    ice_exhaust_admission_cursor_requires_final_attempt
    screen_liveness::tests::cover_before_track_before_initial_and_reset_evidence
    screen_liveness::tests::missing_track_precedes_initial_and_render_evidence
    screen_liveness::tests::covered_samples_still_advance_floor_and_change_clock
    screen_liveness::tests::missing_track_samples_still_advance_floor_and_change_clock
    screen_liveness::tests::presented_progress_precedes_stale_age_and_inbound_decode_stalls
    screen_liveness::tests::advancing_unchanged_frame_ignores_recent_content_clock_then_retained_frame_uses_it
    screen_liveness::tests::presentation_floor_milliseconds_and_content_exact_nanoseconds_remain_distinct
    screen_liveness::tests::future_presentation_is_zero_age_but_future_content_change_is_not_fresh
    screen_liveness::tests::each_single_counter_regression_clears_all_six_deltas_and_recent_clock
    screen_liveness::tests::generation_inequality_wins_over_regression_including_max_to_zero
    screen_liveness::tests::optional_counter_holes_only_break_adjacent_comparison
    screen_liveness::tests::renderer_hole_discards_render_deltas_without_erasing_recent_change
    screen_liveness::tests::zero_inbound_precedes_decoded_progress_and_optional_positive_order_is_original
    screen_liveness::tests::full_width_counters_are_neither_truncated_rounded_nor_wrapped
    screen_liveness::tests::dimensions_choose_each_axis_independently_with_inclusive_original_bounds
    screen_liveness::tests::fps_option_preserves_raw_bits_and_filters_only_original_finite_range
    screen_liveness::tests::metadata_only_inbound_record_presence_is_not_fabricated_or_erased
    screen_liveness::tests::presentation_age_saturates_after_safe_full_width_subtraction
    screen_liveness::tests::zeroed_reset_state_clears_both_history_slots
    screen_liveness::tests::malformed_raw_shape_and_abi_are_rejected_without_state_mutation
    screen_liveness::tests::copied_states_remain_independent_floors
    screen_liveness::tests::fresh_presentation_still_requires_positive_content_samples
    screen_liveness::tests::exact_all_copied_layout_sizes_alignments_and_field_offsets
    screen_liveness::tests::bounded_seeded_native_value_traces_match_frozen_original_at_every_event
    screen_liveness::tests::unknown_zero_and_full_width_abi_refuse_complete_copied_state
    screen_liveness::tests::absent_inbound_record_rejects_each_nonzero_optional_payload_unchanged
    screen_liveness::tests::malformed_recent_change_option_refuses_complete_before_state_unchanged
    screen_liveness::tests::absent_previous_sample_and_change_payloads_refuse_complete_before_state_unchanged
    updater_operation_exact_copied_layout_and_export
    updater_operation_all_458752_closed_scalar_cases_match_original
    updater_operation_literal_broker_binding_is_once_prepared_and_exact
    updater_operation_literal_candidate_requires_exact_new_artifact_and_early_stage
    updater_operation_literal_arming_requires_exact_binding_and_bound_broker
    updater_operation_literal_install_requires_exact_candidate_broker_and_nonfresh_completion
    updater_operation_literal_restored_terminal_needs_fresh_proof_but_retains_recorded_stage
    updater_operation_literal_install_clears_only_ephemeral_readiness_and_challenge
    updater_operation_literal_challenge_requires_fresh_nonready_unissued_candidate_and_all_nonce_guards
    updater_operation_literal_readiness_preflight_changes_no_state_before_encoding
    updater_operation_literal_readiness_commit_requires_all_matches_and_bounded_encoding
    updater_operation_literal_cancellation_and_idle_never_release_fresh_or_armed_state
    updater_operation_literal_failure_revokes_only_ephemeral_proof_and_challenge
    updater_operation_literal_release_requires_broker_terminal_and_both_fresh_proofs
    updater_operation_literal_runtime_never_activates_and_armed_getter_is_stage_only
    updater_operation_literal_complete_accepted_trace_is_not_runtime_authority
    updater_operation_malformed_abi_state_and_reserved_preserve_exact_old_state_deny_all
    updater_operation_malformed_event_domains_unknown_opcodes_and_unused_facts_preserve_state
    packet_send_queue_exact_layout_and_all_offsets
    packet_send_queue_first_and_partial_baselines_seed_without_measurement
    packet_send_queue_invalid_observed_delays_clear_baseline_as_legitimate_unavailable
    packet_send_queue_missing_observed_components_clear_both_baselines
    packet_send_queue_regressing_counts_or_delay_seed_current_valid_values
    packet_send_queue_equal_counts_require_equal_delay_for_no_packets
    packet_send_queue_full_width_counter_difference_precedes_double_conversion
    packet_send_queue_literal_thresholds_and_adjacent_ieee_values
    packet_send_queue_soft_pressure_requires_two_reports_and_stamps_each_measurement
    packet_send_queue_immediate_pressure_does_not_wait_for_soft_confirmation
    packet_send_queue_fresh_rtt_pressure_clears_soft_count_but_not_immediate_classification
    packet_send_queue_soft_lease_is_exactly_closed_zero_through_one_point_five_seconds
    packet_send_queue_no_packets_never_renew_low_or_soft_stamps
    packet_send_queue_no_packets_expired_or_future_stamps_are_cleared
    packet_send_queue_no_packets_nil_soft_preserves_original_counter_branch
    packet_send_queue_signed_int_counter_saturates_without_wrap
    packet_send_queue_measured_low_delay_stamps_and_soft_or_unavailable_clear
    packet_send_queue_tier_reset_retains_raw_baseline_and_path_reset_clears_it
    packet_send_queue_low_lease_query_is_nonmutating_and_has_no_telemetry
    packet_send_queue_capacity_growth_needs_fresh_ordinary_low_lease
    packet_send_queue_capacity_no_packets_borrows_but_never_renews_low_lease
    packet_send_queue_capacity_never_accumulates_or_retires_ordinary_pressure
    packet_send_queue_capacity_temporary_baseline_validation_does_not_change_evidence
    packet_send_queue_raw_negative_infinite_fast_baseline_can_measure_infinite_delay
    packet_send_queue_raw_nan_or_positive_infinite_prior_is_unavailable_then_seeded
    packet_send_queue_raw_negative_finite_prior_uses_original_difference
    packet_send_queue_signed_zero_and_subnormal_delay_bits_are_preserved
    packet_send_queue_exact_signed_duration_components_do_not_quantize
    packet_send_queue_malformed_state_words_have_canonical_no_authority_result
    packet_send_queue_malformed_events_and_noncanonical_absent_ages_deny
    packet_send_queue_reset_and_query_reject_irrelevant_nonzero_input_fields
    packet_send_queue_no_packets_fresh_rtt_pressure_retires_soft_only
    rtt_evidence_all_four_layouts_and_every_field_offset_are_literal
    rtt_evidence_initial_and_first_native_provisional_reference_are_exact
    rtt_evidence_native_three_distinct_healthy_references_saturate_without_cached_credit
    rtt_evidence_legacy_three_sample_bootstrap_uses_sorted_median
    rtt_evidence_legacy_nil_refreshes_age_and_does_not_mint_native_health
    rtt_evidence_literal_inflation_thresholds_and_ieee_neighbors_are_unchanged
    rtt_evidence_baseline_falls_at_most_ten_milliseconds_and_never_rises
    rtt_evidence_response_counts_are_full_width_and_either_counter_can_advance
    rtt_evidence_cached_healthy_lease_is_closed_at_four_seconds_without_quantization
    rtt_evidence_cached_watermark_never_renews_clock_or_repeats_inflation_pressure
    rtt_evidence_scalar_contradiction_consumes_identity_and_cannot_be_repaired_in_place
    rtt_evidence_invalid_current_consumes_first_privilege_and_valid_watermark
    rtt_evidence_unavailable_promotes_fence_to_tombstone_and_blocks_revival
    rtt_evidence_pair_a_b_a_reseeds_and_clears_only_reference_not_peer_clock
    rtt_evidence_regression_reseeds_without_discarding_same_pair_baseline
    rtt_evidence_malformed_measurement_is_accepted_unknown_not_abi_rejection
    rtt_evidence_zero_totals_and_signed_zero_raw_bits_are_preserved_without_health
    rtt_evidence_future_clock_age_consumes_tuple_but_cannot_stamp_or_authorize
    rtt_evidence_path_hide_and_peer_reset_have_distinct_identity_and_clock_ownership
    rtt_evidence_disabled_initial_privilege_requires_seed_then_distinct_advancement
    rtt_evidence_inactive_tombstone_replaces_watermark_but_preserves_fence_and_clock
    rtt_evidence_revoke_allow_initial_and_ordering_are_narrow_named_operations
    rtt_evidence_age_only_and_primary_query_have_no_hidden_state_or_evidence_effects
    rtt_evidence_fast_positive_commits_only_fence_never_ordinary_reference_or_clock
    rtt_evidence_fast_pressure_preserves_watermark_for_one_ordinary_pressure_decision
    rtt_evidence_fast_fence_scalar_contradiction_cannot_be_reinterpreted_as_ordinary_advancement
    rtt_evidence_fast_negative_reseeds_identity_and_clears_reference_only_for_pair_change
    rtt_evidence_fast_route_change_copies_watermark_but_never_healthy_clock_or_baseline
    rtt_evidence_fast_nil_is_unavailable_not_legacy_scalar_authority
    rtt_evidence_fence_copy_is_typed_identity_only_and_never_renews_health
    rtt_evidence_malformed_state_fields_preserve_exact_before_without_authority
    rtt_evidence_malformed_event_tags_and_unused_fields_cannot_obtain_authority
    rtt_evidence_well_typed_mixed_legacy_native_states_are_not_semantically_rejected
    rtt_evidence_actual_verifier_rejects_every_result_word_and_wrong_input_correlation
    tier_demand_layouts_and_all_twenty_three_field_offsets_are_literal
    tier_demand_all_eight_literal_fifty_megabit_profiles_preserve_distinct_fields
    tier_demand_basis_points_and_calibrated_baselines_do_not_follow_configured_ceiling
    tier_demand_configured_video_budget_reserve_floor_and_tiny_cap_are_literal
    tier_demand_full_width_scaling_divides_as_integers_before_conversion
    tier_demand_binary64_total_rtp_ceiling_artifacts_are_not_algebraically_removed
    tier_demand_total_rtp_clips_to_configured_cap_before_rounding_up
    tier_demand_required_diagnostic_is_not_capped_by_restrictive_sender_budget
    tier_demand_initial_tier_is_no_better_than_survival_even_at_full_capacity
    tier_demand_initial_tier_inclusive_emergency_and_survival_cap_boundaries
    tier_demand_sustainable_admission_is_inclusive_at_every_literal_ieee_neighbor
    tier_demand_sustainable_quality_cannot_bypass_configured_cap_with_huge_bandwidth
    tier_demand_highest_upgrade_can_skip_tiers_but_never_select_current_or_lower_quality
    tier_demand_upgrade_margin_is_independent_and_inclusive_at_ieee_neighbors
    tier_demand_upgrade_threshold_saturates_at_cap_without_admitting_over_cap_demand
    tier_demand_direct_threshold_is_adjacent_not_the_highest_qualified_upgrade
    tier_demand_direct_threshold_preserves_exact_unrounded_bits_and_ceil_projection
    tier_demand_direct_threshold_absence_is_canonical_at_full_or_over_cap_neighbor
    tier_demand_absent_bandwidth_preserves_profiles_without_minting_quality_evidence
    tier_demand_smallest_positive_subnormal_bandwidth_is_valid_but_not_capacity
    tier_demand_maximum_finite_bandwidth_is_valid_without_overflow_or_scaling_capacity
    tier_demand_malformed_abi_cap_tier_and_option_tags_reject_canonical_without_authority
    tier_demand_absent_bandwidth_rejects_every_noncanonical_payload_including_negative_zero
    tier_demand_present_bandwidth_rejects_zero_negative_nonfinite_and_nan_payloads
    tier_demand_actual_recomputing_verifier_rejects_every_copied_result_word
    tier_demand_verifier_recomputes_changed_cap_tier_and_qualifying_bandwidth
    tier_demand_verifier_never_admits_even_exact_canonical_rejection
    tier_demand_bandwidth_observations_never_mutate_immutable_profile_projections
    media_command_gate_layouts_and_all_fifteen_offsets_are_literal
    media_command_gate_initial_closed_state_refuses_all_queries_without_fault
    media_command_gate_open_and_close_literals_increment_both_counters
    media_command_gate_invalidation_changes_only_command_epoch
    media_command_gate_lifecycle_query_ignores_command_epoch
    media_command_gate_capture_uses_only_open_and_native_membership_fact
    media_command_gate_admission_requires_all_four_original_conditions
    media_command_gate_accepted_queries_leave_every_state_word_unchanged
    media_command_gate_open_wraps_each_full_uint64_counter_independently
    media_command_gate_close_wraps_each_full_uint64_counter_independently
    media_command_gate_invalidate_wraps_without_rotating_lifecycle_or_open
    media_command_gate_full_uint64_equality_and_wrapped_zero_remain_legal
    media_command_gate_invalid_state_abi_and_boolean_tags_are_canonical_denial
    media_command_gate_unknown_opcode_reserved_and_membership_tags_are_denied
    media_command_gate_each_opcode_rejects_noncanonical_unused_payload
    media_command_gate_canonical_denial_cannot_be_validated_as_a_reset
    media_command_gate_verifier_rejects_each_of_all_forty_copied_bytes
    media_command_gate_verifier_recomputes_exact_successor_and_permission
    media_command_gate_native_membership_remove_readd_does_not_invalidate_epochs
    media_command_gate_fixed_order_original_owner_small_traces_preserve_full_state
    media_command_gate_fixed_seeded_churn_preserves_both_context_authorities
    screen_suspension_three_layouts_and_all_thirty_three_offsets_are_literal
    screen_suspension_initial_and_all_phase_projections_match_frozen_diagnostics
    screen_suspension_activate_all_phases_clears_provenance_without_rewinding_counter
    screen_suspension_retire_every_phase_preserves_full_generator
    screen_suspension_zero_or_stale_activation_and_unnegotiated_begin_leave_state_exact
    screen_suspension_begin_wraps_full_uint64_and_skips_only_zero
    screen_suspension_new_generation_retains_prior_completed_provenance_in_full
    screen_suspension_cover_first_then_inactive_joins_and_rebinds_entire_scalar_state
    screen_suspension_inactive_first_partial_none_action_publishes_rebinding_and_rejects_stale_cover
    screen_suspension_inactive_inclusive_visibility_and_each_foreign_axis_remain_exact
    screen_suspension_duplicate_confirmations_refuse_every_field_without_advancing_generator
    screen_suspension_abort_restores_prior_with_or_without_cover_but_not_after_inactive
    screen_suspension_exact_resume_sequence_preserves_full_state_and_final_mask_sixty_nine
    screen_suspension_each_resume_fact_is_required_independently_not_only_notice_pairs
    screen_suspension_scalar_notice_pairs_remain_rust_owned_even_with_all_native_facts_true
    screen_suspension_commit_has_original_request_fact_without_added_attempt_guard
    screen_suspension_completed_active_and_every_suspension_owned_phase_cancel_exactly
    screen_suspension_ordinary_active_and_idle_have_no_cancellation_provenance
    screen_suspension_stale_cleanup_cannot_retire_or_suspend_any_foreign_binding
    screen_suspension_rollback_requires_completed_active_exact_binding_notice_and_validity
    screen_suspension_owns_and_authorizes_are_exact_nonmutating_full_state_queries
    screen_suspension_full_uint64_bindings_and_recovery_zero_never_narrow_or_reorder
    screen_suspension_binding_predicate_ignores_recovery_but_rejects_zero_peer_or_visibility
    screen_suspension_invalid_state_words_masks_and_join_flags_have_canonical_denial
    screen_suspension_prior_pair_canonicality_keeps_equal_generations_and_full_width_legal
    screen_suspension_each_opcode_rejects_only_noncanonical_unused_payload
    screen_suspension_unknown_operations_and_denial_never_validate_as_reset_or_grant
    screen_suspension_verifier_rejects_every_one_of_all_128_copied_result_bytes
    screen_suspension_full_phase_event_refusal_matrix_snapshots_all_fields
    screen_suspension_every_out_of_order_proof_and_stale_binding_is_ordinary_refusal
    screen_suspension_fixed_complete_cycles_preserve_provenance_abort_rollback_and_generator
    screen_suspension_fixed_seeded_churn_matches_independent_native_enum_algebra
    phone_catalog_abi_exact_all_field_layouts
    phone_catalog_header_schema_host_capacity_precedence
    phone_catalog_uniqueness_every_axis_and_combinations
    phone_catalog_selection_receipt_exact_admission
    phone_catalog_token_all_operations_missing_foreign_stale
    phone_catalog_add_duplicate_precedes_full_capacity
    phone_catalog_lookup_all_counts_targets_unknown
    phone_catalog_binding_precedes_counter_and_phase_regressions
    phone_catalog_phase_rank_original_four_tags
    phone_catalog_both_full_u64_counters_all_boundaries
    phone_catalog_recovery_invalid_bridge_precedes_retention
    phone_catalog_recovery_same_phase_exact_resend_retention
    phone_catalog_select_nil_member_and_unknown_every_count
    phone_catalog_forget_every_count_slot_and_unknown
    phone_catalog_plan_add_complete_append_no_implicit_selection
    phone_catalog_plan_update_exact_target_and_siblings_all_slots
    phone_catalog_plan_select_only_selection_all_slots
    phone_catalog_plan_forget_survivor_order_selection_reindex_original_target
    phone_catalog_finish_noop_original_sources_before_maximum
    phone_catalog_finish_all_operations_exact_single_successor
    phone_catalog_finish_changed_exhaustion_zero_successor_fields
    phone_catalog_inverse_append_forget_and_forget_append_full_maps
    phone_catalog_input_unknown_abi_stage_operation_and_stage_mismatch
    phone_catalog_every_unused_input_field_is_rejected
    phone_catalog_invalid_flags_tags_counts_slots_and_equality_facts
    phone_catalog_verifier_rejects_every_output_byte_after_actual_c
    phone_catalog_verifier_malformed_status0_never_valid_business_denials_valid
    runtime_catalog_all_layouts_and_offsets
    runtime_catalog_startup_guard_stopped_precedence
    runtime_catalog_startup_eligibility_five_native_facts
    runtime_catalog_preflight_unknown_and_cancel_capacity_precedence
    runtime_catalog_quiet_every_structural_axis
    runtime_catalog_ordered_authority_presence_freshness
    runtime_catalog_begin_consumes_only_historical_pair_grant
    runtime_catalog_idle_intent_malformed_before_bad_ticket
    runtime_catalog_retirement_exact_phase_and_finish
    runtime_catalog_end_preserves_intent_and_publish_value
    runtime_catalog_recovery_and_resume_separate_native_callbacks
    runtime_catalog_install_intent_rejects_counterfeit_grant
    runtime_catalog_clear_and_take_intent_presence_match
    runtime_catalog_bootstrap_start_phase_owner_identity
    runtime_catalog_commit_before_after_stop_callback_cuts
    runtime_catalog_activation_every_admitted_and_readback_axis
    runtime_catalog_bootstrap_end_has_no_cancellation_fact
    runtime_catalog_availability_start_and_full_generation_binding
    runtime_catalog_current_client_and_persist_full_tuple
    runtime_catalog_prepared_target_every_service_record_axis
    runtime_catalog_prepared_lifecycle_prefix_before_owner_capable_client
    runtime_catalog_media_move_cancel_prefix_before_target_owner_query
    runtime_catalog_revoke_denies_new_but_retains_teardown_custody
    runtime_catalog_pair_catch_notifications_and_terminal_axes
    runtime_catalog_all_15_legal_states_58_rows_every_fact_subset
    runtime_catalog_malformed_every_state_field_and_shape
    runtime_catalog_malformed_every_event_field_and_unused_bit
    runtime_catalog_verifier_rejects_every_output_byte_change
    runtime_catalog_verifier_does_not_accept_foreign_context_or_status_zero
    runtime_catalog_lifetime_first_pair_grant_single_consumption
    runtime_catalog_lifetime_shutdown_retained_exact_drain_not_new_admission
    runtime_catalog_lifetime_end_before_commit_keeps_intent_until_take
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
    'display-envelope-version-ignored' => 'display_requirement_unknown_abi_is_invalid_independent_of_policy_result',
    'display-envelope-reserved-ignored' => 'display_requirement_reserved_is_invalid_independent_of_policy_result',
    'display-requirement-envelope-bypassed' => 'display_requirement_unknown_abi_is_invalid_independent_of_policy_result',
    'display-kind-envelope-bypassed' => 'source_kind_unknown_abi_and_reserved_are_independent_invalid_inputs',
    'display-source-envelope-bypassed' => 'source_dimensions_invalid_bridge_is_distinct_from_legitimate_owned_absence',
    'display-stability-envelope-bypassed' => 'source_stability_unknown_abi_and_reserved_are_independent_invalid_inputs',
    'display-raw-sole-boolean-domain-opened' => 'display_requirement_each_raw_boolean_domain_is_closed_even_if_ignored',
    'display-raw-online-boolean-domain-opened' => 'display_requirement_each_raw_boolean_domain_is_closed_even_if_ignored',
    'display-raw-active-boolean-domain-opened' => 'display_requirement_each_raw_boolean_domain_is_closed_even_if_ignored',
    'display-online-admission-removed' => 'display_requirement_each_original_identity_and_liveness_guard_is_independent',
    'display-active-admission-removed' => 'display_requirement_each_original_identity_and_liveness_guard_is_independent',
    'display-vendor-identity-admission-removed' => 'display_requirement_each_original_identity_and_liveness_guard_is_independent',
    'display-product-identity-admission-removed' => 'display_requirement_each_original_identity_and_liveness_guard_is_independent',
    'display-serial-identity-admission-removed' => 'display_requirement_each_original_identity_and_liveness_guard_is_independent',
    'display-identity-vendor-truncated-to-u16' => 'display_requirement_identity_and_display_ids_preserve_zero_and_u32_maximum',
    'display-identity-product-truncated-to-u16' => 'display_requirement_identity_and_display_ids_preserve_zero_and_u32_maximum',
    'display-identity-serial-truncated-to-u16' => 'display_requirement_identity_and_display_ids_preserve_zero_and_u32_maximum',
    'display-zero-id-refused' => 'display_requirement_identity_and_display_ids_preserve_zero_and_u32_maximum',
    'display-optional-topology-still-required' => 'display_requirement_optional_topology_ignores_main_count_and_singleton',
    'display-main-id-admission-removed' => 'display_requirement_sole_main_mismatch_alone_refuses',
    'display-main-id-truncated-to-u16' => 'display_requirement_identity_and_display_ids_preserve_zero_and_u32_maximum',
    'display-singleton-count-widened-to-membership' => 'display_requirement_sole_topology_is_exact_singleton_including_duplicates',
    'display-singleton-count-truncated-to-u32' => 'display_requirement_sole_topology_is_exact_singleton_including_duplicates',
    'display-singleton-id-admission-removed' => 'display_requirement_sole_topology_is_exact_singleton_including_duplicates',
    'display-singleton-id-truncated-to-u16' => 'display_requirement_identity_and_display_ids_preserve_zero_and_u32_maximum',
    'display-source-kind-vendor-restriction-removed' => 'source_kind_frozen_literal_table_selects_only_the_two_owned_products',
    'display-source-kind-phone-product-removed' => 'source_kind_frozen_literal_table_selects_only_the_two_owned_products',
    'display-source-kind-combined-product-removed' => 'source_kind_frozen_literal_table_selects_only_the_two_owned_products',
    'display-source-kind-unknown-product-admitted' => 'source_kind_frozen_literal_table_selects_only_the_two_owned_products',
    'display-ordinary-source-filter-finite-guard-introduced' => 'ordinary_source_preserves_entire_signed_domain_before_any_metadata_guard',
    'display-ordinary-source-clamps-signed-dimensions' => 'ordinary_source_preserves_entire_signed_domain_before_any_metadata_guard',
    'display-owned-logical-width-minimum-tightened-to-three' => 'owned_source_logical_width_and_height_minimum_are_two',
    'display-owned-logical-height-minimum-tightened-to-three' => 'owned_source_logical_width_and_height_minimum_are_two',
    'display-owned-logical-width-maximum-removed' => 'owned_source_logical_width_and_height_maximum_are_32768',
    'display-owned-logical-height-maximum-removed' => 'owned_source_logical_width_and_height_maximum_are_32768',
    'display-owned-filter-width-finite-guard-removed' => 'owned_source_filter_width_must_be_finite',
    'display-owned-filter-height-finite-guard-removed' => 'owned_source_filter_height_must_be_finite',
    'display-owned-scale-lower-bound-tightened' => 'owned_source_scale_includes_one_and_four_and_refuses_actual_double_neighbors',
    'display-owned-scale-upper-bound-exclusive' => 'owned_source_scale_includes_one_and_four_and_refuses_actual_double_neighbors',
    'display-owned-scale-range-removed' => 'owned_source_scale_includes_one_and_four_and_refuses_actual_double_neighbors',
    'display-owned-cg-logical-width-minimum-tightened-to-three' => 'owned_source_core_graphics_logical_minimum_literals_and_exact_snapshot_equality',
    'display-owned-cg-logical-height-minimum-tightened-to-three' => 'owned_source_core_graphics_logical_minimum_literals_and_exact_snapshot_equality',
    'display-owned-pixel-width-minimum-removed' => 'owned_source_pixel_width_and_height_minimum_are_two',
    'display-owned-pixel-height-minimum-removed' => 'owned_source_pixel_width_and_height_minimum_are_two',
    'display-owned-pixel-width-maximum-removed' => 'owned_source_pixel_width_and_height_maximum_are_32768',
    'display-owned-pixel-height-maximum-removed' => 'owned_source_pixel_width_and_height_maximum_are_32768',
    'display-owned-cg-logical-width-equality-removed' => 'owned_source_core_graphics_width_snapshot_mismatch_alone_refuses',
    'display-owned-cg-logical-height-equality-removed' => 'owned_source_core_graphics_height_snapshot_mismatch_alone_refuses',
    'display-owned-filter-width-half-pixel-exclusive' => 'owned_source_filter_width_half_pixel_boundary_is_inclusive_both_directions',
    'display-owned-filter-height-half-pixel-exclusive' => 'owned_source_filter_height_half_pixel_boundary_is_inclusive_both_directions',
    'display-owned-filter-width-half-pixel-widened-to-one' => 'owned_source_filter_width_half_pixel_boundary_is_inclusive_both_directions',
    'display-owned-filter-height-half-pixel-widened-to-one' => 'owned_source_filter_height_half_pixel_boundary_is_inclusive_both_directions',
    'display-owned-refusal-mislabeled-invalid-bridge' => 'source_dimensions_invalid_bridge_is_distinct_from_legitimate_owned_absence',
    'display-owned-refusal-retains-nonzero-payload' => 'source_dimensions_invalid_bridge_is_distinct_from_legitimate_owned_absence',
    'display-owned-pixels-replaced-with-logical' => 'owned_source_returns_current_framebuffer_independent_of_scale_ratio_or_rounding',
    'display-owned-pixels-encoder-rounded-prematurely' => 'owned_source_returns_current_framebuffer_independent_of_scale_ratio_or_rounding',
    'display-stability-width-equality-removed' => 'source_stability_requires_both_dimensions_exactly_equal_without_sanity_limits',
    'display-stability-height-equality-removed' => 'source_stability_requires_both_dimensions_exactly_equal_without_sanity_limits',
    'display-stability-unrequested-dimension-sanity-introduced' => 'source_stability_requires_both_dimensions_exactly_equal_without_sanity_limits',
    'display-source-kind-vendor-truncated-to-u16' => 'source_kind_and_dimensions_high_bit_identity_aliases_remain_ordinary',
    'display-source-kind-product-truncated-to-u16' => 'source_kind_and_dimensions_high_bit_identity_aliases_remain_ordinary',
    'output-source-width-minimum-weakened' => 'output_each_original_signed_guard_refuses_before_arithmetic',
    'output-source-height-minimum-weakened' => 'output_each_original_signed_guard_refuses_before_arithmetic',
    'output-maximum-width-minimum-weakened' => 'output_each_original_signed_guard_refuses_before_arithmetic',
    'output-width-cap-discarded' => 'output_width_cap_is_a_minimum_without_upscaling',
    'output-width-upscaled-to-cap' => 'output_width_cap_is_a_minimum_without_upscaling',
    'output-even-width-adjustment-removed' => 'output_even_width_is_chosen_before_scaling',
    'output-nearest-rounding-truncated' => 'output_positive_half_ties_round_away_before_even_height',
    'output-nearest-rounding-to-even' => 'output_positive_half_ties_round_away_before_even_height',
    'output-nearest-rounding-ceiling' => 'output_non_ties_keep_nearest_not_floor_or_ceil',
    'output-float-math-replaced-by-integer-ratio' => 'output_float_multiply_then_divide_is_not_integer_ratio',
    'output-height-chroma-adjustment-removed' => 'output_height_chroma_adjustment_rounds_down_after_nearest',
    'output-two-pixel-height-floor-removed' => 'output_height_floor_keeps_two_when_scaled_rounds_to_zero_or_one',
    'output-source-width-narrowed-to-u16' => 'output_full_signed_projection_does_not_narrow_source_or_cap',
    'output-height-narrowed-to-u32' => 'output_full_signed_projection_does_not_narrow_source_or_cap',
    'output-maximum-width-narrowed-to-u16' => 'output_full_signed_projection_does_not_narrow_source_or_cap',
    'output-upper-exclusive-conversion-boundary-weakened' => 'output_two_to_sixty_three_is_distinct_refusal_not_saturation_or_dimensions',
    'output-malformed-envelope-classified-as-legitimate' => 'output_malformed_envelope_is_not_a_legitimate_dimension_error',
    'output-unknown-version-admitted' => 'output_malformed_envelope_is_not_a_legitimate_dimension_error',
    'output-nonzero-reserved-admitted' => 'output_malformed_envelope_is_not_a_legitimate_dimension_error',
    "ice-grace-discarded" => "ice_grace_acceleration_advances_epoch_and_coalesces_attempts",
    "ice-grace-not-accelerated" => "ice_grace_acceleration_advances_epoch_and_coalesces_attempts",
    "ice-start-epoch-subtracts" => "ice_epoch_wrap_zero_is_a_current_workflow",
    "ice-task-cancellation-ignored" => "ice_task_cancellation_admission_stops_but_finish_is_epoch_only",
    "ice-terminal-signal-guard-removed" => "ice_direct_cancel_repeats_but_cancelled_ice_signals_do_not",
    "ice-finish-stale-epoch-ignored" => "ice_stale_finish_cannot_release_replacement_task",
    "ice-finish-wrongly-requires-current-task" => "ice_task_cancellation_admission_stops_but_finish_is_epoch_only",
    "ice-first-attempt-skipped" => "ice_zero_grace_starts_attempting_without_grace_effect",
    "ice-retries-reset-count" => "ice_success_wait_retry_then_exactly_once_exhaustion",
    "ice-failed-restart-waits" => "ice_failed_restart_consumes_attempt_and_skips_timeout",
    "ice-failed-sleep-continues" => "ice_each_failed_sleep_stops_then_same_epoch_finish_resets_idle",
    "ice-exhaustion-not-committed" => "ice_success_wait_retry_then_exactly_once_exhaustion",
    "ice-nonfinal-attempt-exhausts" => "ice_failed_restart_consumes_attempt_and_skips_timeout",
    "ice-cancel-erases-delivery" => "ice_cancel_retains_delivered_flag_but_clears_attempts",
    "ice-config-zero-accepted" => "ice_initializer_refuses_nonpositive_reserved_and_noncanonical",
    "ice-event-boolean-two-accepted" => "ice_event_envelope_rejects_alias_boolean_reserved_and_unused_fields",
    "ice-state-abi-not-checked" => "ice_state_envelope_rejects_every_closed_field_corruption",
    "ice-current-wait-kind-ignored" => "ice_current_wait_kind_and_program_counter_are_exact",
    "ice-before-copy-corrupted" => "ice_success_wait_retry_then_exactly_once_exhaustion",
    "ice-event-copy-corrupted" => "ice_success_wait_retry_then_exactly_once_exhaustion",
    "liveness-intentional-cover-state-replaced" => "screen_liveness::tests::cover_before_track_before_initial_and_reset_evidence",
    "liveness-other-covers-ignored" => "screen_liveness::tests::cover_before_track_before_initial_and_reset_evidence",
    "liveness-track-guard-ignored" => "screen_liveness::tests::missing_track_precedes_initial_and_render_evidence",
    "liveness-reset-awaiting-ignored" => "screen_liveness::tests::each_single_counter_regression_clears_all_six_deltas_and_recent_clock",
    "liveness-initial-floor-forgotten" => "screen_liveness::tests::cover_before_track_before_initial_and_reset_evidence",
    "liveness-generation-change-ignored" => "screen_liveness::tests::generation_inequality_wins_over_regression_including_max_to_zero",
    "liveness-regression-counter-0-ignored" => "screen_liveness::tests::each_single_counter_regression_clears_all_six_deltas_and_recent_clock",
    "liveness-regression-counter-1-ignored" => "screen_liveness::tests::each_single_counter_regression_clears_all_six_deltas_and_recent_clock",
    "liveness-regression-counter-2-ignored" => "screen_liveness::tests::each_single_counter_regression_clears_all_six_deltas_and_recent_clock",
    "liveness-regression-counter-3-ignored" => "screen_liveness::tests::each_single_counter_regression_clears_all_six_deltas_and_recent_clock",
    "liveness-regression-counter-4-ignored" => "screen_liveness::tests::each_single_counter_regression_clears_all_six_deltas_and_recent_clock",
    "liveness-regression-counter-5-ignored" => "screen_liveness::tests::each_single_counter_regression_clears_all_six_deltas_and_recent_clock",
    "liveness-reset-retains-recent-change" => "screen_liveness::tests::each_single_counter_regression_clears_all_six_deltas_and_recent_clock",
    "liveness-positive-change-clock-is-not-current" => "screen_liveness::tests::covered_samples_still_advance_floor_and_change_clock",
    "liveness-last-change-forgotten-without-new-change" => "screen_liveness::tests::advancing_unchanged_frame_ignores_recent_content_clock_then_retained_frame_uses_it",
    "liveness-covered-floor-not-committed" => "screen_liveness::tests::covered_samples_still_advance_floor_and_change_clock",
    "liveness-missing-track-floor-not-committed" => "screen_liveness::tests::missing_track_samples_still_advance_floor_and_change_clock",
    "liveness-counter-u32-truncation" => "screen_liveness::tests::full_width_counters_are_neither_truncated_rounded_nor_wrapped",
    "liveness-counter-f64-rounding" => "screen_liveness::tests::full_width_counters_are_neither_truncated_rounded_nor_wrapped",
    "liveness-absent-counter-is-zero" => "screen_liveness::tests::optional_counter_holes_only_break_adjacent_comparison",
    "liveness-age-ceil-replaces-floor" => "screen_liveness::tests::presentation_floor_milliseconds_and_content_exact_nanoseconds_remain_distinct",
    "liveness-presentation-freshness-exclusive" => "screen_liveness::tests::presentation_floor_milliseconds_and_content_exact_nanoseconds_remain_distinct",
    "liveness-content-freshness-exclusive" => "screen_liveness::tests::presentation_floor_milliseconds_and_content_exact_nanoseconds_remain_distinct",
    "liveness-future-content-change-is-fresh" => "screen_liveness::tests::future_presentation_is_zero_age_but_future_content_change_is_not_fresh",
    "liveness-future-presentation-age-not-zero" => "screen_liveness::tests::future_presentation_is_zero_age_but_future_content_change_is_not_fresh",
    "liveness-age-saturation-removed" => "screen_liveness::tests::presentation_age_saturates_after_safe_full_width_subtraction",
    "liveness-presented-progress-ignored" => "screen_liveness::tests::presented_progress_precedes_stale_age_and_inbound_decode_stalls",
    "liveness-advancing-unchanged-frame-uses-recent-clock" => "screen_liveness::tests::advancing_unchanged_frame_ignores_recent_content_clock_then_retained_frame_uses_it",
    "liveness-fresh-presentation-zero-content-is-enough" => "screen_liveness::tests::fresh_presentation_still_requires_positive_content_samples",
    "liveness-zero-inbound-precedence-removed" => "screen_liveness::tests::zero_inbound_precedes_decoded_progress_and_optional_positive_order_is_original",
    "liveness-missing-decoded-evidence-is-presentation-stall" => "screen_liveness::tests::zero_inbound_precedes_decoded_progress_and_optional_positive_order_is_original",
    "liveness-dimension-one-rejected" => "screen_liveness::tests::dimensions_choose_each_axis_independently_with_inclusive_original_bounds",
    "liveness-dimension-32768-rejected" => "screen_liveness::tests::dimensions_choose_each_axis_independently_with_inclusive_original_bounds",
    "liveness-dimension-u32-alias-admitted" => "screen_liveness::tests::dimensions_choose_each_axis_independently_with_inclusive_original_bounds",
    "liveness-render-width-fallback-erased" => "screen_liveness::tests::dimensions_choose_each_axis_independently_with_inclusive_original_bounds",
    "liveness-fps-zero-rejected" => "screen_liveness::tests::fps_option_preserves_raw_bits_and_filters_only_original_finite_range",
    "liveness-fps-1000-rejected" => "screen_liveness::tests::fps_option_preserves_raw_bits_and_filters_only_original_finite_range",
    "liveness-inbound-record-presence-erased" => "screen_liveness::tests::metadata_only_inbound_record_presence_is_not_fabricated_or_erased",
    "liveness-generation-u32-truncation" => "screen_liveness::tests::full_width_counters_are_neither_truncated_rounded_nor_wrapped",
    "liveness-raw-fps-payload-normalized" => "screen_liveness::tests::fps_option_preserves_raw_bits_and_filters_only_original_finite_range",
    "liveness-raw-abi-zero-is-admitted" => "screen_liveness::tests::unknown_zero_and_full_width_abi_refuse_complete_copied_state",
    "liveness-raw-abi-max-is-admitted" => "screen_liveness::tests::unknown_zero_and_full_width_abi_refuse_complete_copied_state",
    "liveness-absent-inbound-payload-is-admitted" => "screen_liveness::tests::absent_inbound_record_rejects_each_nonzero_optional_payload_unchanged",
    "liveness-malformed-change-option-is-admitted" => "screen_liveness::tests::malformed_recent_change_option_refuses_complete_before_state_unchanged",
    "liveness-absent-before-payload-is-admitted" => "screen_liveness::tests::absent_previous_sample_and_change_payloads_refuse_complete_before_state_unchanged",
    "UO-M01" => "updater_operation_malformed_abi_state_and_reserved_preserve_exact_old_state_deny_all",
    "UO-M02" => "updater_operation_malformed_event_domains_unknown_opcodes_and_unused_facts_preserve_state",
    "UO-M03" => "updater_operation_malformed_event_domains_unknown_opcodes_and_unused_facts_preserve_state",
    "UO-M04" => "updater_operation_malformed_event_domains_unknown_opcodes_and_unused_facts_preserve_state",
    "UO-M05" => "updater_operation_malformed_abi_state_and_reserved_preserve_exact_old_state_deny_all",
    "UO-M06" => "updater_operation_malformed_abi_state_and_reserved_preserve_exact_old_state_deny_all",
    "UO-M07" => "updater_operation_malformed_abi_state_and_reserved_preserve_exact_old_state_deny_all",
    "UO-M08" => "updater_operation_malformed_abi_state_and_reserved_preserve_exact_old_state_deny_all",
    "UO-M09" => "updater_operation_malformed_abi_state_and_reserved_preserve_exact_old_state_deny_all",
    "UO-B01-1" => "updater_operation_literal_broker_binding_is_once_prepared_and_exact",
    "UO-B01-2" => "updater_operation_literal_broker_binding_is_once_prepared_and_exact",
    "UO-B01-3" => "updater_operation_literal_broker_binding_is_once_prepared_and_exact",
    "UO-B02-1" => "updater_operation_literal_broker_binding_is_once_prepared_and_exact",
    "UO-B02-2" => "updater_operation_literal_broker_binding_is_once_prepared_and_exact",
    "UO-B02-3" => "updater_operation_literal_broker_binding_is_once_prepared_and_exact",
    "UO-C01-1" => "updater_operation_literal_candidate_requires_exact_new_artifact_and_early_stage",
    "UO-C01-2" => "updater_operation_literal_candidate_requires_exact_new_artifact_and_early_stage",
    "UO-C02-1" => "updater_operation_literal_candidate_requires_exact_new_artifact_and_early_stage",
    "UO-C03-1" => "updater_operation_literal_candidate_requires_exact_new_artifact_and_early_stage",
    "UO-C03-2" => "updater_operation_literal_candidate_requires_exact_new_artifact_and_early_stage",
    "UO-C03-3" => "updater_operation_literal_candidate_requires_exact_new_artifact_and_early_stage",
    "UO-A01-1" => "updater_operation_literal_arming_requires_exact_binding_and_bound_broker",
    "UO-A01-2" => "updater_operation_literal_arming_requires_exact_binding_and_bound_broker",
    "UO-A01-3" => "updater_operation_literal_arming_requires_exact_binding_and_bound_broker",
    "UO-I01-1" => "updater_operation_literal_install_requires_exact_candidate_broker_and_nonfresh_completion",
    "UO-I01-2" => "updater_operation_literal_install_requires_exact_candidate_broker_and_nonfresh_completion",
    "UO-I01-3" => "updater_operation_literal_install_requires_exact_candidate_broker_and_nonfresh_completion",
    "UO-I02-1" => "updater_operation_literal_install_requires_exact_candidate_broker_and_nonfresh_completion",
    "UO-I02-2" => "updater_operation_literal_install_requires_exact_candidate_broker_and_nonfresh_completion",
    "UO-I02-3" => "updater_operation_literal_install_requires_exact_candidate_broker_and_nonfresh_completion",
    "UO-I03" => "updater_operation_literal_complete_accepted_trace_is_not_runtime_authority",
    "UO-I04" => "updater_operation_literal_install_clears_only_ephemeral_readiness_and_challenge",
    "UO-I05" => "updater_operation_literal_install_clears_only_ephemeral_readiness_and_challenge",
    "UO-H01a-1" => "updater_operation_literal_challenge_requires_fresh_nonready_unissued_candidate_and_all_nonce_guards",
    "UO-H01a-2" => "updater_operation_literal_challenge_requires_fresh_nonready_unissued_candidate_and_all_nonce_guards",
    "UO-H01b-1" => "updater_operation_literal_challenge_requires_fresh_nonready_unissued_candidate_and_all_nonce_guards",
    "UO-H01b-2" => "updater_operation_literal_challenge_requires_fresh_nonready_unissued_candidate_and_all_nonce_guards",
    "UO-H02a-1" => "updater_operation_literal_challenge_requires_fresh_nonready_unissued_candidate_and_all_nonce_guards",
    "UO-H02a-2" => "updater_operation_literal_challenge_requires_fresh_nonready_unissued_candidate_and_all_nonce_guards",
    "UO-H02a-3" => "updater_operation_literal_challenge_requires_fresh_nonready_unissued_candidate_and_all_nonce_guards",
    "UO-H02b-1" => "updater_operation_literal_challenge_requires_fresh_nonready_unissued_candidate_and_all_nonce_guards",
    "UO-H02b-2" => "updater_operation_literal_challenge_requires_fresh_nonready_unissued_candidate_and_all_nonce_guards",
    "UO-H02c-1" => "updater_operation_literal_challenge_requires_fresh_nonready_unissued_candidate_and_all_nonce_guards",
    "UO-R01-1" => "updater_operation_literal_readiness_commit_requires_all_matches_and_bounded_encoding",
    "UO-R01-2" => "updater_operation_literal_readiness_commit_requires_all_matches_and_bounded_encoding",
    "UO-R01-3" => "updater_operation_literal_readiness_commit_requires_all_matches_and_bounded_encoding",
    "UO-R02" => "updater_operation_literal_readiness_commit_requires_all_matches_and_bounded_encoding",
    "UO-R03" => "updater_operation_literal_readiness_commit_requires_all_matches_and_bounded_encoding",
    "UO-R04" => "updater_operation_literal_readiness_commit_requires_all_matches_and_bounded_encoding",
    "UO-R05" => "updater_operation_literal_readiness_commit_requires_all_matches_and_bounded_encoding",
    "UO-R06" => "updater_operation_literal_readiness_commit_requires_all_matches_and_bounded_encoding",
    "UO-R07" => "updater_operation_literal_readiness_commit_requires_all_matches_and_bounded_encoding",
    "UO-R08" => "updater_operation_literal_readiness_preflight_changes_no_state_before_encoding",
    "UO-R09" => "updater_operation_literal_readiness_commit_requires_all_matches_and_bounded_encoding",
    "UO-R10" => "updater_operation_literal_readiness_commit_requires_all_matches_and_bounded_encoding",
    "UO-R11" => "updater_operation_literal_readiness_commit_requires_all_matches_and_bounded_encoding",
    "UO-F01" => "updater_operation_literal_failure_revokes_only_ephemeral_proof_and_challenge",
    "UO-F02" => "updater_operation_literal_failure_revokes_only_ephemeral_proof_and_challenge",
    "UO-F03" => "updater_operation_literal_failure_revokes_only_ephemeral_proof_and_challenge",
    "UO-Q01" => "updater_operation_literal_runtime_never_activates_and_armed_getter_is_stage_only",
    "UO-Q02-1" => "updater_operation_literal_release_requires_broker_terminal_and_both_fresh_proofs",
    "UO-Q02-2" => "updater_operation_literal_release_requires_broker_terminal_and_both_fresh_proofs",
    "UO-Q03-1" => "updater_operation_literal_release_requires_broker_terminal_and_both_fresh_proofs",
    "UO-Q03-2" => "updater_operation_literal_release_requires_broker_terminal_and_both_fresh_proofs",
    "UO-Q04" => "updater_operation_literal_runtime_never_activates_and_armed_getter_is_stage_only",
    "UO-S01" => "updater_operation_literal_broker_binding_is_once_prepared_and_exact",
    "UO-S02" => "updater_operation_literal_candidate_requires_exact_new_artifact_and_early_stage",
    "UO-S03" => "updater_operation_literal_arming_requires_exact_binding_and_bound_broker",
    "UO-S04" => "updater_operation_literal_install_requires_exact_candidate_broker_and_nonfresh_completion",
    "UO-S05" => "updater_operation_literal_challenge_requires_fresh_nonready_unissued_candidate_and_all_nonce_guards",
    "UO-S06" => "updater_operation_literal_readiness_commit_requires_all_matches_and_bounded_encoding",
    "UO-S07" => "updater_operation_literal_cancellation_and_idle_never_release_fresh_or_armed_state",
    "UO-S08" => "updater_operation_literal_cancellation_and_idle_never_release_fresh_or_armed_state",
    "UO-S09" => "updater_operation_literal_restored_terminal_needs_fresh_proof_but_retains_recorded_stage",
    "UO-S10" => "updater_operation_literal_restored_terminal_needs_fresh_proof_but_retains_recorded_stage",
    'PQ-THRESHOLD-SOFT' => 'packet_send_queue_literal_thresholds_and_adjacent_ieee_values',
    'PQ-THRESHOLD-IMMEDIATE' => 'packet_send_queue_literal_thresholds_and_adjacent_ieee_values',
    'PQ-THRESHOLD-UPGRADE' => 'packet_send_queue_literal_thresholds_and_adjacent_ieee_values',
    'PQ-LEASE-ONE-ATTOSECOND' => 'packet_send_queue_soft_lease_is_exactly_closed_zero_through_one_point_five_seconds',
    'PQ-NO-PACKETS-RENEWAL' => 'packet_send_queue_no_packets_never_renew_low_or_soft_stamps',
    'PQ-TIER-BASELINE-LOSS' => 'packet_send_queue_tier_reset_retains_raw_baseline_and_path_reset_clears_it',
    'PQ-SOFT-COUNT-LOSS' => 'packet_send_queue_soft_pressure_requires_two_reports_and_stamps_each_measurement',
    'PQ-CAPACITY-CONTAMINATION' => 'packet_send_queue_capacity_never_accumulates_or_retires_ordinary_pressure',
    'RTT-BOOTSTRAP-MEDIAN' => 'rtt_evidence_legacy_three_sample_bootstrap_uses_sorted_median',
    'RTT-INFLATION-INCLUSIVE' => 'rtt_evidence_literal_inflation_thresholds_and_ieee_neighbors_are_unchanged',
    'RTT-BASELINE-FALL' => 'rtt_evidence_baseline_falls_at_most_ten_milliseconds_and_never_rises',
    'RTT-LEASE-ONE-ATTOSECOND' => 'rtt_evidence_cached_healthy_lease_is_closed_at_four_seconds_without_quantization',
    'RTT-DUPLICATE-CLOCK-RENEWAL' => 'rtt_evidence_cached_watermark_never_renews_clock_or_repeats_inflation_pressure',
    'RTT-DISTINCT-REFERENCE-COUNT' => 'rtt_evidence_native_three_distinct_healthy_references_saturate_without_cached_credit',
    'RTT-INITIAL-PRIVILEGE-BYPASS' => 'rtt_evidence_disabled_initial_privilege_requires_seed_then_distinct_advancement',
    'RTT-FAST-PRESSURE-CONSUMPTION' => 'rtt_evidence_fast_pressure_preserves_watermark_for_one_ordinary_pressure_decision',
    'RTT-FAST-REFERENCE-CONTAMINATION' => 'rtt_evidence_fast_positive_commits_only_fence_never_ordinary_reference_or_clock',
    'RTT-FENCE-SCALAR-CONTRADICTION' => 'rtt_evidence_fast_fence_scalar_contradiction_cannot_be_reinterpreted_as_ordinary_advancement',
    'TD-BASIS-HIGH' => 'tier_demand_all_eight_literal_fifty_megabit_profiles_preserve_distinct_fields',
    'TD-BASELINE-DEMAND' => 'tier_demand_basis_points_and_calibrated_baselines_do_not_follow_configured_ceiling',
    'TD-RESERVE' => 'tier_demand_configured_video_budget_reserve_floor_and_tiny_cap_are_literal',
    'TD-BUDGET-FLOOR' => 'tier_demand_configured_video_budget_reserve_floor_and_tiny_cap_are_literal',
    'TD-INTEGER-QUOTIENT' => 'tier_demand_full_width_scaling_divides_as_integers_before_conversion',
    'TD-RTP-CEILING' => 'tier_demand_binary64_total_rtp_ceiling_artifacts_are_not_algebraically_removed',
    'TD-INITIAL-SURVIVAL-FLOOR' => 'tier_demand_initial_tier_is_no_better_than_survival_even_at_full_capacity',
    'TD-SUSTAINABLE-INCLUSIVE' => 'tier_demand_sustainable_admission_is_inclusive_at_every_literal_ieee_neighbor',
    'TD-SUSTAINABLE-CAP' => 'tier_demand_sustainable_quality_cannot_bypass_configured_cap_with_huge_bandwidth',
    'TD-UPGRADE-MARGIN' => 'tier_demand_upgrade_margin_is_independent_and_inclusive_at_ieee_neighbors',
    'TD-UPGRADE-INCLUSIVE' => 'tier_demand_upgrade_margin_is_independent_and_inclusive_at_ieee_neighbors',
    'TD-UPGRADE-CAP-ADMISSION' => 'tier_demand_upgrade_threshold_saturates_at_cap_without_admitting_over_cap_demand',
    "MCG-LIFECYCLE-OPEN" => "media_command_gate_initial_closed_state_refuses_all_queries_without_fault",
    "MCG-LIFECYCLE-ID" => "media_command_gate_lifecycle_query_ignores_command_epoch",
    "MCG-CAPTURE-OPEN" => "media_command_gate_capture_uses_only_open_and_native_membership_fact",
    "MCG-CAPTURE-MEMBERSHIP" => "media_command_gate_capture_uses_only_open_and_native_membership_fact",
    "MCG-ADMIT-OPEN" => "media_command_gate_admission_requires_all_four_original_conditions",
    "MCG-ADMIT-LIFECYCLE" => "media_command_gate_admission_requires_all_four_original_conditions",
    "MCG-ADMIT-EPOCH" => "media_command_gate_admission_requires_all_four_original_conditions",
    "MCG-ADMIT-MEMBERSHIP" => "media_command_gate_admission_requires_all_four_original_conditions",
    "MCG-OPEN-LIFECYCLE-WRAP" => "media_command_gate_open_wraps_each_full_uint64_counter_independently",
    "MCG-OPEN-EPOCH-WRAP" => "media_command_gate_open_wraps_each_full_uint64_counter_independently",
    "MCG-CLOSE-LIFECYCLE-WRAP" => "media_command_gate_close_wraps_each_full_uint64_counter_independently",
    "MCG-CLOSE-EPOCH-WRAP" => "media_command_gate_close_wraps_each_full_uint64_counter_independently",
    "MCG-INVALIDATE-EPOCH-WRAP" => "media_command_gate_invalidate_wraps_without_rotating_lifecycle_or_open",
    "MCG-INVALIDATE-LIFECYCLE" => "media_command_gate_invalidation_changes_only_command_epoch",
    "MCG-STATE-ABI" => "media_command_gate_invalid_state_abi_and_boolean_tags_are_canonical_denial",
    "MCG-STATE-BOOLEAN" => "media_command_gate_invalid_state_abi_and_boolean_tags_are_canonical_denial",
    "MCG-EVENT-BOOLEAN" => "media_command_gate_unknown_opcode_reserved_and_membership_tags_are_denied",
    "MCG-EVENT-RESERVED0" => "media_command_gate_unknown_opcode_reserved_and_membership_tags_are_denied",
    "MCG-EVENT-RESERVED1" => "media_command_gate_unknown_opcode_reserved_and_membership_tags_are_denied",
    "MCG-MUTATING-PAYLOAD" => "media_command_gate_each_opcode_rejects_noncanonical_unused_payload",
    "MCG-LIFECYCLE-PAYLOAD" => "media_command_gate_each_opcode_rejects_noncanonical_unused_payload",
    "MCG-CAPTURE-PAYLOAD" => "media_command_gate_each_opcode_rejects_noncanonical_unused_payload",
    "MCG-UNKNOWN-OPCODE" => "media_command_gate_unknown_opcode_reserved_and_membership_tags_are_denied",
    "MCG-VERIFIER-DENIAL" => "media_command_gate_canonical_denial_cannot_be_validated_as_a_reset",
    "MCG-VERIFIER-COMPLETE" => "media_command_gate_verifier_rejects_each_of_all_forty_copied_bytes",
    "MCG-LIFECYCLE-QUERY-STATE" => "media_command_gate_accepted_queries_leave_every_state_word_unchanged",
    "MCG-CAPTURE-QUERY-STATE" => "media_command_gate_accepted_queries_leave_every_state_word_unchanged",
    "MCG-ADMIT-QUERY-STATE" => "media_command_gate_accepted_queries_leave_every_state_word_unchanged",
    'SS-INACTIVE-INCLUSIVE' => 'screen_suspension_inactive_inclusive_visibility_and_each_foreign_axis_remain_exact',
    'SS-INACTIVE-REBIND' => 'screen_suspension_inactive_first_partial_none_action_publishes_rebinding_and_rejects_stale_cover',
    'SS-STALE-COVER' => 'screen_suspension_inactive_first_partial_none_action_publishes_rebinding_and_rejects_stale_cover',
    'SS-EARLY-JOIN' => 'screen_suspension_cover_first_then_inactive_joins_and_rebinds_entire_scalar_state',
    'SS-ZERO-SKIP' => 'screen_suspension_begin_wraps_full_uint64_and_skips_only_zero',
    'SS-RETIRE-COUNTER' => 'screen_suspension_retire_every_phase_preserves_full_generator',
    'SS-ABORT-PRIOR' => 'screen_suspension_abort_restores_prior_with_or_without_cover_but_not_after_inactive',
    'SS-COMPLETED-CUSTODY' => 'screen_suspension_exact_resume_sequence_preserves_full_state_and_final_mask_sixty_nine',
    'SS-STALE-CANCEL' => 'screen_suspension_stale_cleanup_cannot_retire_or_suspend_any_foreign_binding',
    'SS-PROOF-ORDER' => 'screen_suspension_every_out_of_order_proof_and_stale_binding_is_ordinary_refusal',
    'SS-FULL-NATIVE-FACT' => 'screen_suspension_each_resume_fact_is_required_independently_not_only_notice_pairs',
    'SS-QUERY-NONMUTATING' => 'screen_suspension_owns_and_authorizes_are_exact_nonmutating_full_state_queries',
    'SS-VERIFIER-BYPASS' => 'screen_suspension_verifier_rejects_every_one_of_all_128_copied_result_bytes',
    'SS-DENIAL-NOT-RESET' => 'screen_suspension_unknown_operations_and_denial_never_validate_as_reset_or_grant',
    'PC-header-schema-removed' => 'phone_catalog_header_schema_host_capacity_precedence',
    'PC-duplicate-before-full-removed' => 'phone_catalog_add_duplicate_precedes_full_capacity',
    'PC-capacity-seven' => 'phone_catalog_add_duplicate_precedes_full_capacity',
    'PC-token-foreign-admitted' => 'phone_catalog_token_all_operations_missing_foreign_stale',
    'PC-binding-removed' => 'phone_catalog_binding_precedes_counter_and_phase_regressions',
    'PC-outbound-signed' => 'phone_catalog_both_full_u64_counters_all_boundaries',
    'PC-accepted-counter-removed' => 'phone_catalog_both_full_u64_counters_all_boundaries',
    'PC-issued-rank-wrong' => 'phone_catalog_phase_rank_original_four_tags',
    'PC-invalid-recovery-removed' => 'phone_catalog_recovery_invalid_bridge_precedes_retention',
    'PC-resend-retention-removed' => 'phone_catalog_recovery_same_phase_exact_resend_retention',
    'PC-select-unknown-admitted' => 'phone_catalog_select_nil_member_and_unknown_every_count',
    'PC-add-implicit-selection' => 'phone_catalog_plan_add_complete_append_no_implicit_selection',
    'PC-update-candidate-map-removed' => 'phone_catalog_plan_update_exact_target_and_siblings_all_slots',
    'PC-forget-selection-reindex-removed' => 'phone_catalog_plan_forget_survivor_order_selection_reindex_original_target',
    'PC-target-remapped' => 'phone_catalog_plan_forget_survivor_order_selection_reindex_original_target',
    'PC-noop-uses-candidate-map' => 'phone_catalog_finish_noop_original_sources_before_maximum',
    'PC-exhaustion-before-noop' => 'phone_catalog_finish_noop_original_sources_before_maximum',
    'PC-revision-no-increment' => 'phone_catalog_finish_all_operations_exact_single_successor',
    'PC-unused-input-admitted' => 'phone_catalog_every_unused_input_field_is_rejected',
    'PC-malformed-status-verified' => 'phone_catalog_verifier_malformed_status0_never_valid_business_denials_valid',
    'PC-verifier-ignores-output' => 'phone_catalog_verifier_rejects_every_output_byte_after_actual_c',
    'OC-REVISION' => 'network_adaptation_owner_clocked_events_tests::product_owner_clocked_202_initial_stop_retains_revision_and_full_owner_tail',
    'OC-ROUTE' => 'network_adaptation_owner_clocked_events_tests::product_owner_clocked_212_route_invalidation_advances_and_clears_evidence_not_fast_applied',
    'OC-REFUSAL-PUBLICATION' => 'network_adaptation_owner_clocked_events_tests::product_owner_clocked_every_lazy_callback_failure_refuses_whole_tuple',
    'OC-READ-CORRELATION' => 'network_adaptation_owner_clocked_events_tests::product_owner_clocked_reply_correlation_and_native_range_refuse_each_read',
    'OC-TIME-MASK' => 'network_adaptation_owner_clocked_events_tests::product_owner_clocked_202_initial_stop_retains_revision_and_full_owner_tail',
    'OC-CLOSED-OPERATION' => 'network_adaptation_owner_clocked_events_tests::product_owner_clocked_policy_only_vote_is_closed_before_decode_or_provider',
    'OP-ENTRY-REVISION' => 'network_adaptation_owner_prepare_events_tests::product_owner_prepare_zero_read_entry_none',
    'OP-REFUSAL-PUBLICATION' => 'network_adaptation_owner_prepare_events_tests::product_owner_prepare_provider_denial_all_seven_outputs_untouched',
    'OP-READ-TRANSCRIPT' => 'network_adaptation_owner_prepare_events_tests::product_owner_prepare_late_none_preserves_real_read_transcript',
    'OP-TIME-JOURNAL' => 'network_adaptation_owner_prepare_events_tests::product_owner_prepare_expiry_full222_literal_tail_and_journals',
    'OI-EXPECTED-REVISION' => 'network_adaptation_owner_inactive_events_tests::product_owner_inactive_expected_revision_not_applying_and_wrap_once',
    'OI-PREPARED-ORIGIN' => 'network_adaptation_owner_inactive_events_tests::product_owner_inactive_equal_coordinates_import_all_nine_prepared_origins',
    'OI-REFUSAL-PUBLICATION' => 'network_adaptation_owner_inactive_events_tests::product_owner_inactive_each_provider_and_reply_denial_refuses_seven_outputs',
    'OI-SUSPENSION-COUNTER' => 'network_adaptation_owner_inactive_events_tests::product_owner_inactive_healthy_L_read_adopts_or_requests_resume',
    'OA-RESOURCE-GATE' => 'network_adaptation_owner_begin_active_events_tests::active_begin_raw_each_missing_resource_returns_before_attempt_consumption',
    'OA-FAULT-PREFIX' => 'network_adaptation_owner_begin_active_events_tests::active_begin_raw_fault_retains_before_resource_return_without_positive_adoption',
    'OA-ATTEMPT-CONSUMPTION' => 'network_adaptation_owner_begin_active_events_tests::active_begin_raw_attempt_only_changes_negative_fields_and_applying_revision',
    'OA-PROVIDER-STATUS' => 'network_adaptation_owner_begin_active_events_tests::active_begin_raw_same_peer_Q_success_and_all_five_new_peer_denial_prefixes',
    'OA-PREPARED-BODY' => 'network_adaptation_owner_begin_active_events_tests::active_begin_raw_no_native_apply_skips_resources_but_changed_forces_return',
    'OA-REFUSAL-PUBLICATION' => 'network_adaptation_owner_begin_active_events_tests::active_begin_raw_callback_correlation_and_unrepresentable_time_leave_all_nine_outputs',
    'OA-JOURNAL-CLEAR' => 'network_adaptation_owner_begin_active_events_tests::active_begin_raw_attempt_only_changes_negative_fields_and_applying_revision',
    'OA-OWNER-TAIL' => 'network_adaptation_owner_begin_active_events_tests::active_begin_raw_no_invented_revision_peer_or_active_fence_and_exact222',
    'OCV-STALE' => 'network_adaptation_owner_completion_events_tests::active_completion_validated_stale_same_fps_and_missing_thunks_are_explicit',
    'OCV-SAMEFPS' => 'network_adaptation_owner_completion_events_tests::active_completion_validated_stale_same_fps_and_missing_thunks_are_explicit',
    'OCV-RETURN' => 'network_adaptation_owner_completion_events_tests::active_completion_validated_only_one_accepts_and_denial_never_effects_or_writes',
    'OCV-HEADER-FIRST' => 'network_adaptation_owner_completion_events_tests::active_completion_validated_only_one_accepts_and_denial_never_effects_or_writes',
    'OCV-INVOCATION' => 'network_adaptation_owner_completion_events_tests::active_completion_validated_int32_and_invocation_correlation_are_pre_effect',
    'OCV-FPS-FIRST' => 'network_adaptation_owner_completion_events_tests::active_completion_validated_private_full_bundle_precedes_fps_and_all_publication',
    'OC-FRESH-FENCE' => 'network_adaptation_owner_completion_events_tests::active_completion_raw_all_eleven_success_fences_rollback_without_effect_or_import',
    'OC-EFFECT-ORDER' => 'network_adaptation_owner_completion_events_tests::active_completion_raw_callback_carries_exact_invocation_and_fps_before_every_output_write',
    'OC-LATE-CONVERSION' => 'network_adaptation_owner_completion_events_tests::active_completion_raw_int32_conversion_is_only_for_reachable_changed_fps_effect',
    'OC-APPLIED-PUBLICATION' => 'network_adaptation_owner_completion_events_tests::active_completion_raw_current_success_records_only_applied_without_policy_revision_or_import',
    'OC-FINAL-FRESH' => 'network_adaptation_owner_completion_events_tests::active_completion_raw_final_adopt_three_stale_fences_preserve_every_owner_word',
    'OC-FINAL-OPAQUE' => 'network_adaptation_owner_completion_events_tests::active_completion_raw_final_adopt_wraps_once_and_preserves_opaque_applied_ieee_tail',
    'OF-PREFIX-DISCARD' => 'network_adaptation_owner_failure_events_tests::active_failure_raw_FQ_denials_keep_live_pre_Q_prefix_and_success_alone_finishes_cleanup',
    'OF-ERROR-REVISION' => 'network_adaptation_owner_failure_events_tests::active_failure_raw_revision_wrap_waits_for_complete_retention_and_absent_timestamp_stays_absent',
    'OF-ACCEPTED-ATTEMPT' => 'network_adaptation_owner_failure_events_tests::active_failure_raw_second_rejected_cut_keeps_one_accepted_F_and_exact_pre_Q_state',
    'OF-PROVIDER-STATUS' => 'network_adaptation_owner_failure_events_tests::active_failure_raw_provider_denial_correlation_and_bad_coordinate_publish_not_discard_F_prefix',
    'OF-JOURNAL-CLEAR' => 'network_adaptation_owner_failure_events_tests::active_failure_raw_ordinary_uses_applying_and_retains_only_negative_prefix_without_clocks',
    'OF-REFUSAL-PUBLICATION' => 'network_adaptation_owner_failure_events_tests::active_failure_raw_strict_request_headers_and_all401_atoms_reject_before_any_semantic_prefix',
    'MIC-RETRY-BUDGET' => 'eligibility_preserves_absence_fault_and_strict_budget_boundary',
    'MIC-RETRY-ADMISSION' => 'all_eleven_native_failure_categories_have_literal_retry_votes',
    'MIC-RETRY-ABSENT' => 'retry_failure_never_creates_history_or_reopens_a_consumed_budget',
    'MIC-RETRY-CONSUME' => 'recording_sets_one_or_increments_and_always_consumes_retry_permission',
    'MIC-RETRY-ABSENT-EXHAUST' => 'exhaust_absent_history_retains_redrive_but_existing_history_clears_it',
    'MIC-RETRY-CORRELATION' => 'result_correlation_rejects_every_coherent_or_malformed_changed_field',
    'MIC-RETRY-CLEANUP-CORRELATION' => 'result_correlation_rejects_every_coherent_or_malformed_changed_field',
    'UA-M01' => 'malformed_abi_and_each_unknown_flag_fail_closed',
    'UA-M02' => 'malformed_abi_and_each_unknown_flag_fail_closed',
    'UA-M03' => 'each_owned_activity_and_missing_teardown_or_interactivity_denies_admission',
    'UA-M04' => 'each_owned_activity_and_missing_teardown_or_interactivity_denies_admission',
    'UA-M05' => 'each_owned_activity_and_missing_teardown_or_interactivity_denies_admission',
    'UA-M06' => 'each_owned_activity_and_missing_teardown_or_interactivity_denies_admission',
    'UA-M07' => 'each_owned_activity_and_missing_teardown_or_interactivity_denies_admission',
    'UA-M08' => 'release_progress_and_menu_precedence_are_independent_of_admission',
    'UA-M09' => 'release_progress_and_menu_precedence_are_independent_of_admission',
    'UA-M10' => 'release_progress_and_menu_precedence_are_independent_of_admission',
    'UA-M11' => 'release_progress_and_menu_precedence_are_independent_of_admission',
    'UA-M12' => 'release_progress_and_menu_precedence_are_independent_of_admission',
    'UA-M13' => 'every_result_field_corruption_is_rejected_for_every_valid_request',
    'UA-M14' => 'release_progress_and_menu_precedence_are_independent_of_admission',
    'UA-M15' => 'release_progress_and_menu_precedence_are_independent_of_admission',
    'UA-M16' => 'release_progress_and_menu_precedence_are_independent_of_admission',
    'UA-M17' => 'release_progress_and_menu_precedence_are_independent_of_admission',
    'USA-M01' => 'malformed_abi_phase_and_each_phase_specific_unknown_flag_fail_closed',
    'USA-M02' => 'malformed_abi_phase_and_each_phase_specific_unknown_flag_fail_closed',
    'USA-M03' => 'malformed_abi_phase_and_each_phase_specific_unknown_flag_fail_closed',
    'USA-M04' => 'malformed_abi_phase_and_each_phase_specific_unknown_flag_fail_closed',
    'USA-M05' => 'each_original_guard_preserves_error_precedence_and_phase_actions',
    'USA-M06' => 'each_original_guard_preserves_error_precedence_and_phase_actions',
    'USA-M07' => 'each_original_guard_preserves_error_precedence_and_phase_actions',
    'USA-M08' => 'each_original_guard_preserves_error_precedence_and_phase_actions',
    'USA-M09' => 'each_original_guard_preserves_error_precedence_and_phase_actions',
    'USA-M10' => 'each_original_guard_preserves_error_precedence_and_phase_actions',
    'USA-M11' => 'each_original_guard_preserves_error_precedence_and_phase_actions',
    'USA-M12' => 'malformed_abi_phase_and_each_phase_specific_unknown_flag_fail_closed',
    'USA-M13' => 'malformed_abi_phase_and_each_phase_specific_unknown_flag_fail_closed',
    'USA-M14' => 'all_twelve_valid_carriers_match_literal_original_swift_guards',
    'USA-M15' => 'every_result_field_corruption_is_rejected_for_all_valid_requests',
    'USA-M16' => 'malformed_abi_phase_and_each_phase_specific_unknown_flag_fail_closed',
    'USA-M17' => 'all_twelve_valid_carriers_match_literal_original_swift_guards',
    'prepare-rate-ceiling-widened' => 'preparation_scalar_edges_and_nonfinite_values_match_frozen_swift',
    'match-rate-equality-bypassed' => 'changed_rate_duration_and_all_nonfinite_match_words_match_frozen_swift',
    'mac-drift-widened' => 'exact_mac_one_second_and_phone_two_second_limits_are_inclusive_and_distinct',
    'phone-drift-widened' => 'exact_mac_one_second_and_phone_two_second_limits_are_inclusive_and_distinct',
    'expiry-inclusive' => 'page_millisecond_clock_zero_and_exclusive_thirty_second_edges_keep_original_domain',
    'page-clock-wrong-unit' => 'page_millisecond_clock_zero_and_exclusive_thirty_second_edges_keep_original_domain',
    'prepare-position-presence-ignored' => 'every_native_flag_combination_preserves_missing_and_identity_refusals',
    'match-duration-presence-ignored' => 'every_native_flag_combination_preserves_missing_and_identity_refusals',
    'continuity-identity-ignored' => 'every_native_flag_combination_preserves_missing_and_identity_refusals',
    'video-identity-ignored' => 'every_native_flag_combination_preserves_missing_and_identity_refusals',
    'prepare-NaN-duration-accepted' => 'preparation_scalar_edges_and_nonfinite_values_match_frozen_swift',
    'match-NaN-position-accepted' => 'changed_rate_duration_and_all_nonfinite_match_words_match_frozen_swift',
    'actual-c-prepare-bypassed' => 'actual_c_exports_and_validators_preserve_votes_and_malformed_refusal',
    'actual-c-matches-bypassed' => 'actual_c_exports_and_validators_preserve_votes_and_malformed_refusal',
    'actual-c-prepare-validator-bypassed' => 'actual_c_exports_and_validators_preserve_votes_and_malformed_refusal',
    'actual-c-matches-validator-bypassed' => 'actual_c_exports_and_validators_preserve_votes_and_malformed_refusal',
    'MIC-INPUT-ACQUIRE-BUDGET' => 'input_lease_acquisition_budget_preserves_literal_one_and_three_caps',
    'MIC-INPUT-ACQUIRED' => 'input_lease_acquisition_native_outcomes_have_three_literal_actions',
    'MIC-INPUT-RELEASE-BUDGET' => 'input_lease_release_continuation_requires_retryable_and_strict_budget',
    'MIC-INPUT-FALLBACK' => 'input_lease_release_outcome_preserves_native_fallback_and_external_result',
    'MIC-INPUT-CLOSED-WIRE' => 'input_lease_closed_wire_rejects_all_unused_and_negative_domains',
    'MIC-INPUT-WHOLE-RESULT' => 'input_lease_verifier_rejects_each_field_and_coherent_cross_operation_results',
    'MIC-INPUT-C-PRODUCER' => 'input_lease_actual_c_exports_correlate_accepted_and_refused_results',
    'MIC-INPUT-C-VERIFIER' => 'input_lease_actual_c_exports_correlate_accepted_and_refused_results',
    'MIC-OUTPUT-FORMAT-CLOSED-WIRE' => 'output_format_malformed_wire_is_not_an_ordinary_policy_rejection',
    'MIC-OUTPUT-FORMAT-FIRST-GUARD' => 'output_format_every_simultaneous_error_pair_preserves_first_guard',
    'MIC-OUTPUT-FORMAT-RATE-EXACT' => 'output_format_rates_use_numeric_equality_but_rejections_keep_original_bits',
    'MIC-OUTPUT-FORMAT-SIGNED-STATUS' => 'output_format_four_signed_statuses_preserve_negative_and_extreme_values',
    'MIC-OUTPUT-FORMAT-FULL-U32' => 'output_format_integer_fields_are_exact_not_masks_ranges_or_truncated_values',
    'MIC-OUTPUT-FORMAT-WHOLE-RESULT' => 'output_format_authoritative_verifier_rejects_corruption_of_every_result_field',
    'MIC-OUTPUT-FORMAT-C-PRODUCER' => 'output_format_actual_c_exports_correlate_success_rejection_and_refusal',
    'MIC-OUTPUT-FORMAT-C-VERIFIER' => 'output_format_actual_c_exports_correlate_success_rejection_and_refusal',
  }.freeze
  BELUGA_CORE_MUTANTS = BELUGA_CORE_MUTANT_TESTS.keys.freeze
  UPDATER_OPERATION_RUST_PINNED = BELUGA_CORE_PINNED.drop(321).first(18).freeze
  UPDATER_OPERATION_MUTANT_TESTS = BELUGA_CORE_MUTANT_TESTS.to_a.drop(306).first(75).to_h.freeze
  UPDATER_OPERATION_NATIVE_PINNED = MAC_PINNED.drop(239).first(76).freeze
  PACKET_SEND_QUEUE_RUST_PINNED = BELUGA_CORE_PINNED.drop(339).first(32).freeze
  PACKET_SEND_QUEUE_MUTANT_TESTS = BELUGA_CORE_MUTANT_TESTS.to_a.drop(381).first(8).to_h.freeze
  RTT_EVIDENCE_RUST_PINNED = BELUGA_CORE_PINNED.drop(371).first(34).freeze
  RTT_EVIDENCE_MUTANT_TESTS = BELUGA_CORE_MUTANT_TESTS.to_a.drop(389).first(10).to_h.freeze
  TIER_DEMAND_RUST_PINNED = BELUGA_CORE_PINNED.drop(405).first(28).freeze
  TIER_DEMAND_MUTANT_TESTS = BELUGA_CORE_MUTANT_TESTS.to_a.drop(399).first(12).to_h.freeze
  MEDIA_COMMAND_GATE_RUST_PINNED = BELUGA_CORE_PINNED.drop(433).first(21).freeze
  MEDIA_COMMAND_GATE_MUTANT_TESTS = BELUGA_CORE_MUTANT_TESTS.to_a.drop(411).first(28).to_h.freeze
  SCREEN_SUSPENSION_RUST_PINNED = BELUGA_CORE_PINNED.drop(454).first(32).freeze
  SCREEN_SUSPENSION_MUTANT_TESTS = BELUGA_CORE_MUTANT_TESTS.to_a.drop(439).first(14).to_h.freeze
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
    'BelugaCore C display admission ABI PASS: exact layouts, native branch order, signed endpoints and unchanged refusals',
    'BelugaCore Swift display admission import/link PASS: exact layouts, native branch order, signed endpoints and unchanged refusals',
    'BelugaCore C output dimensions ABI PASS: two layouts, twelve offsets, signed projection and distinct conversion refusal',
    'BelugaCore Swift output dimensions import/link PASS: two layouts, twelve offsets, signed projection and distinct conversion refusal',
    "BelugaCore C ICE recovery ABI PASS: five layouts, thirty-one offsets and full-width transactional transitions",
    "BelugaCore Swift ICE recovery import/link PASS: five layouts, thirty-one offsets and full-width transactional transitions",
    "BelugaCore C screen liveness ABI PASS: exact copied layouts, full-width values and unchanged refusal",
    "BelugaCore Swift screen liveness import/link PASS: exact copied layouts, full-width values and unchanged refusal",
    "BelugaCore C update operation ABI PASS: three copied layouts, exact phase plans and unchanged refusal",
    "BelugaCore Swift update operation import/link PASS: three copied layouts, exact phase plans and unchanged refusal",
    'BelugaCore C packet queue ABI PASS: exact layouts, full-width counters and bounded evidence leases',
    'BelugaCore Swift packet queue import/link PASS: exact layouts, full-width counters and bounded evidence leases',
    'BelugaCore C RTT evidence ABI PASS: exact copied layouts, identity and nonrenewable freshness',
    'BelugaCore Swift RTT evidence import/link PASS: exact copied layouts, identity and nonrenewable freshness',
    'BelugaCore C tier demand ABI PASS: exact copied layouts, calibrated budgets and checked projections',
    'BelugaCore Swift tier demand import/link PASS: exact copied layouts, calibrated budgets and checked projections',
    'BelugaCore C media command gate ABI PASS: exact copied layouts, wrapping epochs and checked admission',
    'BelugaCore Swift media command gate import/link PASS: exact copied layouts, wrapping epochs and checked admission',
    'BelugaCore C screen suspension ABI PASS: exact copied layouts, ordered transcript and retained provenance',
    'BelugaCore Swift screen suspension import/link PASS: exact copied layouts, ordered transcript and retained provenance',
    'BelugaCore C phone catalog ABI PASS: every offset, all operations/actions, full maps, 72-byte verifier',
    'BelugaCore Swift phone catalog import/link PASS: every offset, all operations/actions, full maps, 72-byte verifier',
    'BelugaCore C runtime catalog ABI PASS: 58 ordered cuts, every offset, historical grant, 40-byte verifier',
    'BelugaCore Swift runtime catalog import/link PASS: 58 ordered cuts, every offset, historical grant, 40-byte verifier',
    'BelugaCore C adaptation Owner zero-clock PASS: layouts, full179 stop, four untouched denials',
    'BelugaCore Swift adaptation Owner zero-clock PASS: layouts, full179 stop, four untouched denials',
    'BelugaCore C adaptation Owner clocked PASS: layout, two full179 cuts, lazy callback, eight untouched denials',
    'BelugaCore Swift adaptation Owner clocked PASS: layout, two full179 cuts, lazy callback, eight untouched denials',
    'BelugaCore C adaptation Owner prepare PASS: layouts, full179 lazy None, fifteen untouched denials',
    'BelugaCore Swift adaptation Owner prepare PASS: layouts, full179 lazy None, fifteen untouched denials',
    'BelugaCore C adaptation Owner inactive PASS: layouts, full179 adoption/stale, nine origins, twelve untouched denials',
    'BelugaCore Swift adaptation Owner inactive PASS: layouts, full179 adoption/stale, nine origins, twelve untouched denials',
    'BelugaCore C adaptation Owner begin-active PASS: layouts, exact179/222 Return/NoNativeApply, fourteen untouched denials',
    'BelugaCore Swift adaptation Owner begin-active PASS: layouts, exact179/222 Return/NoNativeApply, fourteen untouched denials',
    'BelugaCore C adaptation Owner completion PASS: 702/703/704 layouts, exact179 results, effect-before-publication, untouched denials',
    'BelugaCore Swift adaptation Owner completion PASS: 702/703/704 layouts, exact179 results, untouched denials',
    'BelugaCore C adaptation Owner validated702 PASS: actual private bundle, validator-before-effect, stale/sameFPS, strict denial and missing thunks',
    'BelugaCore Swift adaptation Owner validated702 PASS: actual private bundle, validator-before-effect, stale/sameFPS, strict denial and missing thunks',
    'BelugaCore C microphone evidence ABI PASS: copied layouts, whole results, refusal and conditional NeedsNow',
    'BelugaCore Swift microphone evidence ABI PASS: copied layouts, whole results, refusal and conditional NeedsNow',
    'BelugaCore C microphone result correlation PASS: exact result, coherent corruption, refusal and NeedsNow',
    'BelugaCore Swift microphone result correlation PASS: exact result, coherent corruption, refusal and NeedsNow',
    'BelugaCore C microphone retry ABI PASS: literal layouts/results, all-field correlation, refusal and signed overflow',
    'BelugaCore Swift microphone retry ABI PASS: literal layouts/results, all-field correlation, refusal and signed overflow',
    'BelugaCore C updater admission ABI PASS: exact layouts, 512 parity cases, all-field correlation and refusal',
    'BelugaCore Swift updater admission ABI PASS: exact layouts, 512 parity cases, all-field correlation and refusal',
    'BelugaCore C SDK admission ABI PASS: exact layouts, twelve phases, whole correlation and refusal',
    'BelugaCore Swift SDK admission ABI PASS: exact layouts, twelve phases, whole correlation and refusal',
    'BelugaCore C unarmed completion ABI PASS: copied layouts, six reasons, whole correlation and refusal',
    'BelugaCore Swift unarmed completion ABI PASS: copied layouts, six reasons, whole correlation and refusal',
    'BelugaCore C abort classifier ABI PASS: copied layouts, 64 carriers, whole correlation and refusal',
    'BelugaCore Swift abort classifier ABI PASS: copied layouts, 64 carriers, whole correlation and refusal',
    'BelugaCore C handoff source ABI PASS: exact layouts, timeline/phone boundaries, whole correlation and refusal',
    'BelugaCore Swift handoff source ABI PASS: exact layouts, timeline/phone boundaries, whole correlation and refusal',
    'BelugaCore C input lease ABI PASS: four copied operations, literal layouts, full-width counts and whole refusal',
    'BelugaCore Swift input lease ABI PASS: four copied operations, literal layouts, full-width counts and whole refusal',
    'BelugaCore C output format ABI PASS: literal layouts, sixteen ordered guards, exact observations and whole refusal',
    'BelugaCore Swift output format ABI PASS: literal layouts, sixteen ordered guards, exact observations and whole refusal',
  ].freeze
  UPDATER_OPERATION_RUNTIME_MARKERS = BELUGA_CORE_RUNTIME_MARKERS[38, 2].freeze
  PACKET_SEND_QUEUE_RUNTIME_MARKERS = BELUGA_CORE_RUNTIME_MARKERS[40, 2].freeze
  RTT_EVIDENCE_RUNTIME_MARKERS = BELUGA_CORE_RUNTIME_MARKERS[42, 2].freeze
  TIER_DEMAND_RUNTIME_MARKERS = BELUGA_CORE_RUNTIME_MARKERS[44, 2].freeze
  MEDIA_COMMAND_GATE_RUNTIME_MARKERS = BELUGA_CORE_RUNTIME_MARKERS[46, 2].freeze
  SCREEN_SUSPENSION_RUNTIME_MARKERS = BELUGA_CORE_RUNTIME_MARKERS[48, 2].freeze
  PACKET_SEND_QUEUE_SOURCE_SHA256 = {
    'macOS/Tests/CaptureServerTests/BelugaRustPacketSendQueueTests.swift' => 'b6cc0d148284291782cd006ea23db6b6d9fd34f1f3f4429e87740b8c495af263',
    'macOS/Tests/CaptureServerTests/FrozenPacketSendQueueReference.swift' => '965e5490a7947c325d26e61f1a09fbedd65dd92088382ffb0452973147d8fb64',
    'shared/Rust/BelugaCore/src/lib.rs' => '5a4db763fdef546ccdf9de324256f8b49c4ad9932e664432a93830ec46d55e2d',
    'shared/Rust/BelugaCore/include/beluga_core.h' => '2ea355f72241c8c62d0eb53b5d342784172637a305ffa3570b290814782d2dcd',
    'shared/Rust/BelugaCore/scripts/artifact_support.rb' => 'a39308cec492ff541f33bddbb3e6332400f33aabf37498e350db97684c524cb7',
    'shared/Rust/BelugaCore/scripts/mutation-tests.rb' => '9cafeff860bd35c6090323679ee0b9ca0ec9a2cba2c65c82d2bb2eda986ac6cd',
    'shared/Rust/BelugaCore/tests/c_abi_smoke.c' => '6c2e4b992f8ff15edcacdb4343e8e42a8867a10201710f904dcd1f9cf38dea37',
    'shared/Rust/BelugaCore/tests/swift_import_smoke.swift' => '733731db3cfd6bd7a3114b9edfc474e5df32d5a18acc053a6cf61b808fc887b1',
    'shared/Rust/BelugaCore/src/packet_send_queue.rs' => '0ad9138db7c286d37ef03eee3489874e4af0e4554aae214323251eb1735eef20',
    'shared/Rust/BelugaCore/tests/packet_send_queue.rs' => 'a120b1228a7b983fc117ec0f2adafece7f027c48bcab1a6c2c4a09abb93ba8fe',
    'macOS/Sources/CaptureServer/BelugaRustPacketSendQueue.swift' => 'd440b8597a78bbcd173505d2325ff4b0d37e297a7ef5cbc88976e6aa8481f3a3',
    'macOS/Sources/CaptureServer/WorldwideScreenVideoAdaptationPolicy.swift' => '9e9ce0dd1fd9043081fa956bf4e132558f4d616895759d5ed8da8e358c766dcb',
  }.freeze
  # Preserve the old 40 logical markers; actual stdout is C old20 + new C, then Swift old20 + new Swift.
  PACKET_SEND_QUEUE_NATIVE_FILES = {
    'CaptureServerTests.BelugaRustPacketSendQueueTests' => 'macOS/Tests/CaptureServerTests/BelugaRustPacketSendQueueTests.swift',
  }.freeze
  PACKET_SEND_QUEUE_NATIVE_PINNED = {
    'CaptureServerTests.BelugaRustPacketSendQueueTests' => %w[
      CaptureServerTests.BelugaRustPacketSendQueueTests/testActualCThreeLayoutsAndAllThirtyOneOffsets
      CaptureServerTests.BelugaRustPacketSendQueueTests/testOrdinaryCounterAndPartialBaselineMatrixMatchesFrozenOriginal
      CaptureServerTests.BelugaRustPacketSendQueueTests/testCurrentFloatAndOptionalRejectionsClearWithoutLosingValidSignedZero
      CaptureServerTests.BelugaRustPacketSendQueueTests/testThresholdNeighborsKeepOriginalInclusiveAndExclusiveDecisions
      CaptureServerTests.BelugaRustPacketSendQueueTests/testExactLeaseAgesIncludeBoundaryButNotOneAttosecondBeyondOrBeforeZero
      CaptureServerTests.BelugaRustPacketSendQueueTests/testSoftPressureSaturatesAndFreshRTTDoesNotCountQueuePressureTwice
      CaptureServerTests.BelugaRustPacketSendQueueTests/testCapacityRawBaselineKeepsOriginalNonfiniteAndPartialSemantics
      CaptureServerTests.BelugaRustPacketSendQueueTests/testCapacityCannotStampRenewOrConsumeOrdinaryLeasesAndPressure
      CaptureServerTests.BelugaRustPacketSendQueueTests/testTierResetRetainsCounterBaselineWhilePathResetRetiresIt
      CaptureServerTests.BelugaRustPacketSendQueueTests/testMalformedABIFieldsRejectWithCanonicalEmptyResultForEveryOpcode
      CaptureServerTests.BelugaRustPacketSendQueueTests/testFacadeOrdinarySequencePublishesOnlyActualCStateAndExactNativeStamps
      CaptureServerTests.BelugaRustPacketSendQueueTests/testFacadeResetUsesEmptyEventAfterAdvancingNativeLowOrSoftLease
      CaptureServerTests.BelugaRustPacketSendQueueTests/testFacadeEveryForgedResultWordAfterActualCRejectsAndLatchesClosed
      CaptureServerTests.BelugaRustPacketSendQueueTests/testFacadeFaultCannotResumeByResetCounterRepairOrCapacityFallback
      CaptureServerTests.BelugaRustPacketSendQueueTests/testFacadeCapacityUsesActualTemporaryBaselineAndRejectsForgeryWithoutOrdinaryMutation
    ],
  }.transform_values(&:freeze).freeze
  RTT_EVIDENCE_SOURCE_SHA256 = {
    'macOS/Sources/CaptureServer/WorldwideScreenService.swift' => 'db8a5a28db70cdc419ed3f88e0d1c0da9472d96655b3cc6cce52ce00b3ffb73a',
    'macOS/Tests/CaptureServerTests/BelugaRustRoundTripTimeEvidenceTests.swift' => '5200fee22acd0fed8a81411dd97f305211638eed8d7f3c7bb5d1a2be665d62f9',
    'macOS/Tests/CaptureServerTests/FrozenRoundTripTimeReference.swift' => 'f9e5fc855e429b6df9a7ded4f8a57859b87ba6daf1a1307c2f5b96fe6325dded',
    'macOS/Tests/CaptureServerTests/FrozenRoundTripTimeABIReference.swift' => '134b765444d7dccc8394912cc61271679a75a4cae70a8841bd7662540aa1d743',
    'shared/Rust/BelugaCore/src/lib.rs' => '5a4db763fdef546ccdf9de324256f8b49c4ad9932e664432a93830ec46d55e2d',
    'shared/Rust/BelugaCore/include/beluga_core.h' => '2ea355f72241c8c62d0eb53b5d342784172637a305ffa3570b290814782d2dcd',
    'shared/Rust/BelugaCore/scripts/artifact_support.rb' => 'a39308cec492ff541f33bddbb3e6332400f33aabf37498e350db97684c524cb7',
    'shared/Rust/BelugaCore/scripts/mutation-tests.rb' => '9cafeff860bd35c6090323679ee0b9ca0ec9a2cba2c65c82d2bb2eda986ac6cd',
    'shared/Rust/BelugaCore/tests/c_abi_smoke.c' => '6c2e4b992f8ff15edcacdb4343e8e42a8867a10201710f904dcd1f9cf38dea37',
    'shared/Rust/BelugaCore/tests/swift_import_smoke.swift' => '733731db3cfd6bd7a3114b9edfc474e5df32d5a18acc053a6cf61b808fc887b1',
    'shared/Rust/BelugaCore/src/rtt_evidence.rs' => 'eb6fd6752b78013f18951eb2f710e5c848d8431dc895f1d736de35ca4e990e04',
    'shared/Rust/BelugaCore/tests/rtt_evidence.rs' => '5e50a237dc03b77e5a303b73cc7ea205841724ac00ed922cd337d47c88db4991',
    'macOS/Sources/CaptureServer/BelugaRustRoundTripTimeEvidence.swift' => 'f6e08b3fd1eebc0fd5de9a93392975c5fa23e03c5aeae8c9c80fc78701ed5c2f',
    'macOS/Sources/CaptureServer/WorldwideScreenVideoAdaptationPolicy.swift' => '9e9ce0dd1fd9043081fa956bf4e132558f4d616895759d5ed8da8e358c766dcb',
  }.freeze
  RTT_EVIDENCE_NATIVE_FILES = {
    'CaptureServerTests.BelugaRustRoundTripTimeEvidenceTests' => 'macOS/Tests/CaptureServerTests/BelugaRustRoundTripTimeEvidenceTests.swift',
  }.freeze
  RTT_EVIDENCE_NATIVE_PINNED = {
    'CaptureServerTests.BelugaRustRoundTripTimeEvidenceTests' => %w[
      CaptureServerTests.BelugaRustRoundTripTimeEvidenceTests/testActualCFourLayoutsFiftyOffsetsAndArrayWidths
      CaptureServerTests.BelugaRustRoundTripTimeEvidenceTests/testLegacyBootstrapMissingAndStrictUnavailableKeepOriginalDistinction
      CaptureServerTests.BelugaRustRoundTripTimeEvidenceTests/testNativeDistinctReferenceLearningNeverLearnsDuplicatesOrInflation
      CaptureServerTests.BelugaRustRoundTripTimeEvidenceTests/testInclusiveInflationAndFloatBoundariesPreservePreAndPostLearning
      CaptureServerTests.BelugaRustRoundTripTimeEvidenceTests/testFullCountersAndIndependentAdvancementRetainExactUInt64
      CaptureServerTests.BelugaRustRoundTripTimeEvidenceTests/testInvalidTelemetryAndExplicitFingerprintLengthAreUnknownNotABIRejection
      CaptureServerTests.BelugaRustRoundTripTimeEvidenceTests/testPairABARegressionAndScalarContradictionConsumeIdentityOnce
      CaptureServerTests.BelugaRustRoundTripTimeEvidenceTests/testSignedExactAgeBoundariesAndDuplicateLeasesNeverRenew
      CaptureServerTests.BelugaRustRoundTripTimeEvidenceTests/testLifecycleAndRejectedIdentityOperationsPreserveDistinctOriginalState
      CaptureServerTests.BelugaRustRoundTripTimeEvidenceTests/testFastPositiveAndAdmittedFailedApplyCopyOnlyFenceWithoutRenewal
      CaptureServerTests.BelugaRustRoundTripTimeEvidenceTests/testFastNegativeTombstonesPoisonButFreshPressureRemainsForOrdinaryOnce
      CaptureServerTests.BelugaRustRoundTripTimeEvidenceTests/testFastRouteAndPrimaryLeaseAreEvaluatedBeforeCloneAdvancement
      CaptureServerTests.BelugaRustRoundTripTimeEvidenceTests/testInvalidABIStateAndEventRejectWithExactBeforeStateAndZeroAuthority
      CaptureServerTests.BelugaRustRoundTripTimeEvidenceTests/testEveryCopiedResultWordIsDeniedAndFacadeFaultIsSticky
      CaptureServerTests.BelugaRustRoundTripTimeEvidenceTests/testFacadeNamedClockOperationsFastProjectionAndReplacementMatchActualC
    ],
  }.transform_values(&:freeze).freeze
  TIER_DEMAND_SOURCE_SHA256 = {
    'macOS/Sources/CaptureServer/BelugaRustTierDemand.swift' => 'e152ec38666c9de18213970ac611cb64525c7a396f670b4cded3c60d98478c76',
    'macOS/Sources/CaptureServer/WorldwideScreenVideoAdaptationPolicy.swift' => '9e9ce0dd1fd9043081fa956bf4e132558f4d616895759d5ed8da8e358c766dcb',
    'macOS/Sources/CaptureServer/WorldwideScreenService.swift' => 'db8a5a28db70cdc419ed3f88e0d1c0da9472d96655b3cc6cce52ce00b3ffb73a',
    'macOS/Tests/CaptureServerTests/WorldwideRemoteInputScaleTransitionTests.swift' => '3e823ad07a0d7f6ec529afd2b8cb394a01a30dfa0dff3c0301510e092418b218',
    'macOS/Tests/CaptureServerTests/BelugaRustTierDemandTests.swift' => '3368024b30eb05209b5e1bb8e03e8619a64b258031e9764ee5e61969a0738b0b',
    'macOS/Tests/CaptureServerTests/FrozenTierDemandReference.swift' => '74feb8d6988a116efd7989bcd6f76f67e7d365248b3b425f47ebc9a72dba799c',
    'shared/Rust/BelugaCore/src/lib.rs' => '5a4db763fdef546ccdf9de324256f8b49c4ad9932e664432a93830ec46d55e2d',
    'shared/Rust/BelugaCore/include/beluga_core.h' => '2ea355f72241c8c62d0eb53b5d342784172637a305ffa3570b290814782d2dcd',
    'shared/Rust/BelugaCore/scripts/artifact_support.rb' => 'a39308cec492ff541f33bddbb3e6332400f33aabf37498e350db97684c524cb7',
    'shared/Rust/BelugaCore/scripts/mutation-tests.rb' => '9cafeff860bd35c6090323679ee0b9ca0ec9a2cba2c65c82d2bb2eda986ac6cd',
    'shared/Rust/BelugaCore/tests/c_abi_smoke.c' => '6c2e4b992f8ff15edcacdb4343e8e42a8867a10201710f904dcd1f9cf38dea37',
    'shared/Rust/BelugaCore/tests/swift_import_smoke.swift' => '733731db3cfd6bd7a3114b9edfc474e5df32d5a18acc053a6cf61b808fc887b1',
    'shared/Rust/BelugaCore/src/tier_demand.rs' => 'b0d1e2d1c991a21f444a8f2d551033b441cc507539b1ab5eaa1b6013a06b6ad1',
    'shared/Rust/BelugaCore/tests/tier_demand.rs' => '6892635834e70af3ed7a07b17613ca6e02ca53e2cb4ae1bb16884c98340c8a24',
  }.freeze
  TIER_DEMAND_NATIVE_FILES = {
    'CaptureServerTests.BelugaRustTierDemandTests' => 'macOS/Tests/CaptureServerTests/BelugaRustTierDemandTests.swift',
  }.freeze
  TIER_DEMAND_NATIVE_PINNED = {
    'CaptureServerTests.BelugaRustTierDemandTests' => %w[
      CaptureServerTests.BelugaRustTierDemandTests/testActualCTwoLayoutsAndAllTwentyThreeOffsets
      CaptureServerTests.BelugaRustTierDemandTests/testAbsentBandwidthProfilesMatchFrozenReferenceForAllTiersAndBoundaryCaps
      CaptureServerTests.BelugaRustTierDemandTests/testSustainableTierEveryDemandBoundaryAndAdjacentDoubles
      CaptureServerTests.BelugaRustTierDemandTests/testUpgradeAdmissionEveryMarginAndConfiguredClampBoundary
      CaptureServerTests.BelugaRustTierDemandTests/testConfiguredVideoBudgetFlooringAndFullUInt32CapRange
      CaptureServerTests.BelugaRustTierDemandTests/testLiteralCeilingArtifactsAndCalibratedDemandAreNotRationalized
      CaptureServerTests.BelugaRustTierDemandTests/testInitialTierPreservesSurvivalCeilingAtEveryConfiguredDemandBoundary
      CaptureServerTests.BelugaRustTierDemandTests/testMalformedFactDomainsReturnCanonicalDenialAndVerifierRefusesIt
      CaptureServerTests.BelugaRustTierDemandTests/testEveryCopiedProjectionByteIsRejectedByActualExportedVerifier
      CaptureServerTests.BelugaRustTierDemandTests/testFacadeCachesOnlyVerifiedImmutableProfilesAndUsesOneActualDynamicProjection
      CaptureServerTests.BelugaRustTierDemandTests/testFacadeDynamicFailureIsStickyWithoutFallbackOrFurtherProducerCalls
      CaptureServerTests.BelugaRustTierDemandTests/testPublicPolicyInitializationDenialCannotArmAnySpeculativePermission
      CaptureServerTests.BelugaRustTierDemandTests/testPublicPolicyDynamicDenialRetiresConfirmedProbeAndCannotRearm
      CaptureServerTests.BelugaRustTierDemandTests/testPublicPolicySamePeerFaultCustodyCannotPoisonForeignPeerOrImportPositiveState
    ],
  }.transform_values(&:freeze).freeze
  MEDIA_COMMAND_GATE_SOURCE_SHA256 = {
    'shared/Rust/BelugaCore/src/media_command_gate.rs' => '04d83786419ae463e121a2ccba7b7fd9a89be2e72b05b109d62d218af5e77300',
    'shared/Rust/BelugaCore/tests/media_command_gate.rs' => '4ff0679874f4f9e6f49f14cc6f9f50da5656bf81b551ab09502723cb628ed6bb',
    'shared/Rust/BelugaCore/src/lib.rs' => '5a4db763fdef546ccdf9de324256f8b49c4ad9932e664432a93830ec46d55e2d',
    'shared/Rust/BelugaCore/include/beluga_core.h' => '2ea355f72241c8c62d0eb53b5d342784172637a305ffa3570b290814782d2dcd',
    'shared/Rust/BelugaCore/scripts/artifact_support.rb' => 'a39308cec492ff541f33bddbb3e6332400f33aabf37498e350db97684c524cb7',
    'shared/Rust/BelugaCore/scripts/mutation-tests.rb' => '9cafeff860bd35c6090323679ee0b9ca0ec9a2cba2c65c82d2bb2eda986ac6cd',
    'shared/Rust/BelugaCore/tests/c_abi_smoke.c' => '6c2e4b992f8ff15edcacdb4343e8e42a8867a10201710f904dcd1f9cf38dea37',
    'shared/Rust/BelugaCore/tests/swift_import_smoke.swift' => '733731db3cfd6bd7a3114b9edfc474e5df32d5a18acc053a6cf61b808fc887b1',
    'macOS/Sources/CaptureServer/BelugaRustMediaCommandGate.swift' => '363e81d2ef863c402bef786a48b88ea56951daeb2eefa84e737d3cf8cbb3b137',
    'macOS/Sources/CaptureServer/MacSystemNowPlayingController.swift' => '260fbd1d5464b959ad97044707a1b90a8f82b4af7a6768b50142d968efd2b079',
    'macOS/Tests/CaptureServerTests/BelugaRustMediaCommandGateTests.swift' => '04b1c00745c041d16a9fa3ff1c208154441293e2991a72ffacea133440064221',
    'macOS/Tests/CaptureServerTests/FrozenMediaCommandGateReference.swift' => '5158775469f7532f048cf23fadfbd15aa36f32a25c43720199759582cb80cd6b',
  }.freeze
  MEDIA_COMMAND_GATE_NATIVE_FILES = {
    'CaptureServerTests.BelugaRustMediaCommandGateTests' => 'macOS/Tests/CaptureServerTests/BelugaRustMediaCommandGateTests.swift',
  }.freeze
  MEDIA_COMMAND_GATE_NATIVE_PINNED = {
    'CaptureServerTests.BelugaRustMediaCommandGateTests' => %w[
      CaptureServerTests.BelugaRustMediaCommandGateTests/testActualCThreeLayoutsAndAllFifteenOffsets
      CaptureServerTests.BelugaRustMediaCommandGateTests/testActualCInitialOpenCloseAndRepeatedTransitionsMatchFrozenOriginal
      CaptureServerTests.BelugaRustMediaCommandGateTests/testActualCInvalidationAndNativeRemoveReaddMatchOriginalOwner
      CaptureServerTests.BelugaRustMediaCommandGateTests/testNativeMembershipUsesSwiftEqualityAndPreservesCapturedUTF8Spelling
      CaptureServerTests.BelugaRustMediaCommandGateTests/testActualCFullUInt64WrapAndIndependentCountersMatchFrozenOriginal
      CaptureServerTests.BelugaRustMediaCommandGateTests/testEveryMalformedStateEventAndUnusedWordReturnsCanonicalDenial
      CaptureServerTests.BelugaRustMediaCommandGateTests/testActualVerifierRejectsEveryCopiedResultByteIncludingQueryState
      CaptureServerTests.BelugaRustMediaCommandGateTests/testActualFacadeEveryOpcodeDenialRetainsStateAndLatchesWithoutFurtherCalls
      CaptureServerTests.BelugaRustMediaCommandGateTests/testActualLockedOwnerEveryOpcodeDenialRetainsContextAndNoAuthorityCanResume
      CaptureServerTests.BelugaRustMediaCommandGateTests/testFirstDeniedClosePreservesSetAndLaterFaultedCloseClearsOnlySet
      CaptureServerTests.BelugaRustMediaCommandGateTests/testOrdinaryNativeRefusalAndUnchangedContextAssignmentsNeverFaultOrRotate
      CaptureServerTests.BelugaRustMediaCommandGateTests/testControllerMalformedOpenCannotStartPollingOrGrantPreparedWork
      CaptureServerTests.BelugaRustMediaCommandGateTests/testControllerMalformedCaptureCannotPrepareACommandOrHandoff
      CaptureServerTests.BelugaRustMediaCommandGateTests/testControllerMalformedQueuedOrFinalAdmissionCannotDispatchNativeCommand
      CaptureServerTests.BelugaRustMediaCommandGateTests/testControllerMalformedQueuedOrFinalHandoffAdmissionCannotAttemptNativePause
    ],
  }.transform_values(&:freeze).freeze
  SCREEN_SUSPENSION_SOURCE_SHA256 = {
    'shared/Rust/BelugaCore/src/lib.rs' => '5a4db763fdef546ccdf9de324256f8b49c4ad9932e664432a93830ec46d55e2d',
    'shared/Rust/BelugaCore/include/beluga_core.h' => '2ea355f72241c8c62d0eb53b5d342784172637a305ffa3570b290814782d2dcd',
    'shared/Rust/BelugaCore/scripts/artifact_support.rb' => 'a39308cec492ff541f33bddbb3e6332400f33aabf37498e350db97684c524cb7',
    'shared/Rust/BelugaCore/scripts/mutation-tests.rb' => '9cafeff860bd35c6090323679ee0b9ca0ec9a2cba2c65c82d2bb2eda986ac6cd',
    'shared/Rust/BelugaCore/tests/c_abi_smoke.c' => '6c2e4b992f8ff15edcacdb4343e8e42a8867a10201710f904dcd1f9cf38dea37',
    'shared/Rust/BelugaCore/tests/swift_import_smoke.swift' => '733731db3cfd6bd7a3114b9edfc474e5df32d5a18acc053a6cf61b808fc887b1',
    'shared/Rust/BelugaCore/src/screen_suspension.rs' => '6d12d978d7102fd0afbee943e3b8d1d92f961deddf3b2faa42eaed559619f528',
    'shared/Rust/BelugaCore/tests/screen_suspension.rs' => 'e2d44dc1a45d4dce7d478cc1c6b6adf8ca6ac15d93a481feab099708ad3fac78',
    'macOS/Sources/CaptureServer/BelugaRustScreenSuspension.swift' => '6142cab3c2ccdc53097056a8f746e0746c2afdc1422b5546bcacabeeb6cdbc79',
    'macOS/Sources/CaptureServer/WorldwideScreenMediaSuspensionCoordinator.swift' => 'cb6f1a031b8cc292eae82ffdfb67e9e76e40e177d88b74b5d9b49facf93c832d',
    'macOS/Tests/CaptureServerTests/BelugaRustScreenSuspensionTranscriptTests.swift' => '969f1a47b9f0d3d19215fcf2f85b1e2a0c0d9c5aee990ee2b8a8850c8b9d4115',
    'macOS/Tests/CaptureServerTests/FrozenScreenMediaSuspensionReference.swift' => '3ea81492861f698886be96453e3d717367fe2e2e5050c4a2d3aeae719baafddd',
    'macOS/Tests/CaptureServerTests/WorldwideScreenMediaSuspensionCoordinatorTests.swift' => 'cf3739277153d5a7ceb3174f4ece0092f0b3c78bf4afe16f87088ee2cac64e5b',
    'macOS/Tests/CaptureServerTests/WorldwideScreenAutomaticResumeCommitLatchTests.swift' => 'e445c4d775582b905187c2a23d35aa19a09d9cdc7df7d16c6a0924b555982326',
    'shared/Sources/WebRTCTransport/WebRTCControlProtocol.swift' => '1e6adbce15ed81b570aa1cc121b18c65e8a4f850067c552964b8c8dd5f752f93',
    'shared/Tests/WebRTCTransportTests/ScreenMediaSuspensionProtocolTests.swift' => '1055a2b5c7ced251c46122a25405da41359f4ae37f8298132629a13e587ae8e3',
  }.freeze
  SCREEN_SUSPENSION_NATIVE_FILES = {
    'CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests' => 'macOS/Tests/CaptureServerTests/BelugaRustScreenSuspensionTranscriptTests.swift',
  }.freeze
  SCREEN_SUSPENSION_NATIVE_PINNED = {
    'CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests' => %w[
      CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testActualCLayoutsAndEveryThirtyThreeFieldOffsets
      CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testActualCCompleteNinePhaseTranscriptAndProjection
      CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testActualCBothConfirmationOrdersSameEpochAndRebinding
      CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testActualCUnnegotiatedAndInvalidBindingsPreserveWholeState
      CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testActualCStaleBindingRefusalMatrixAcrossEveryPhase
      CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testActualCWholePhaseEventAdmissionAndRefusalMatrix
      CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testActualCGenerationWrapAndRetireActivateNeverRewind
      CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testActualCAbortRestoresPriorCompletedProvenanceWithOrWithoutCover
      CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testActualCCancelAllOwnedPhasesButNeverOrdinaryActive
      CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testActualCReplacementShowProtectsAgainstStaleCleanupAndRollback
      CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testActualCVerifierRejectsEveryOneHundredTwentyEightCopiedResultBytes
      CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testActualCMalformedStateAndUnusedEventFieldsAreCanonicalDenials
      CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeWholeTranscriptAndDeepCustodyMatchFrozenReference
      CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativePhaseEventRefusalAndFullWidthBindingsMatchFrozenReference
      CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeWholePhaseEventAdmissionAndRefusalMatrix
      CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeFixedSeededChurnUsesFrozenExpectationsWithoutNativeEffects
      CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeBothJoinOrdersPublishPartialNoneActionAndReboundBinding
      CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeProvenanceAbortCancelRollbackAndReplacementIsolation
      CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeMarkerReadyAndExactEchoKeepEntirePayloadDomain
      CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeMarkerPresentationRejectsInvalidReceiverSourceShapeAndDeepEcho
      CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeResumeReadyPreservesSeparateRTPDomainsAndSerialLimits
      CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeResumeRequestAndFinalizationRequireFullNestedEquality
      CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeUnicodeEqualityPreservesIncomingReceiverSpelling
      CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeValueCopiesRemainIndependentAcrossEveryPhase
      CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeDeepCustodyValidatorRejectsForeignUUIDNoticeAndExtraStandaloneProofs
      CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeDeepCustodyValidatorRejectsInvalidNestedLeafAndPriorProvenance
      CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeEveryMutatingOpcodeRejectsCopiedResultWithoutPartialPublication
      CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeBeginRejectsEveryCopiedResultByteAndRetainsGenerator
      CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeNonmutatingQueryDenialNeverPoisonsOwnerOrCopy
      CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeNonmutatingCopiedRefusalCannotForgeAuthorityGrant
      CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeFaultInOneCopyCannotPoisonHealthySiblingOrClearRetainedDiagnostic
      CaptureServerTests.BelugaRustScreenSuspensionTranscriptTests/testNativeInitialProjectionCopiedResultFailureLatchesWithoutGrant
    ],
  }.transform_values(&:freeze).freeze
  PHONE_CATALOG_RUST_PINNED = BELUGA_CORE_PINNED.drop(486).first(27).freeze
  PHONE_CATALOG_MUTANT_TESTS = BELUGA_CORE_MUTANT_TESTS.to_a.drop(453).first(21).to_h.freeze
  PHONE_CATALOG_RUNTIME_MARKERS = BELUGA_CORE_RUNTIME_MARKERS[50, 2].freeze
  PHONE_CATALOG_SOURCE_SHA256 = {
    'shared/Rust/BelugaCore/src/lib.rs' => '5a4db763fdef546ccdf9de324256f8b49c4ad9932e664432a93830ec46d55e2d',
    'shared/Rust/BelugaCore/include/beluga_core.h' => '2ea355f72241c8c62d0eb53b5d342784172637a305ffa3570b290814782d2dcd',
    'shared/Rust/BelugaCore/scripts/artifact_support.rb' => 'a39308cec492ff541f33bddbb3e6332400f33aabf37498e350db97684c524cb7',
    'shared/Rust/BelugaCore/scripts/mutation-tests.rb' => '9cafeff860bd35c6090323679ee0b9ca0ec9a2cba2c65c82d2bb2eda986ac6cd',
    'shared/Rust/BelugaCore/tests/c_abi_smoke.c' => '6c2e4b992f8ff15edcacdb4343e8e42a8867a10201710f904dcd1f9cf38dea37',
    'shared/Rust/BelugaCore/tests/swift_import_smoke.swift' => '733731db3cfd6bd7a3114b9edfc474e5df32d5a18acc053a6cf61b808fc887b1',
    'shared/Rust/BelugaCore/src/phone_catalog.rs' => 'd770ec26c82719ff0fb049c136b06a771f2b82fe084ad0bc6df78e9af232ae77',
    'shared/Rust/BelugaCore/tests/phone_catalog.rs' => '7c601b08b3155fdb09fa0767d8c5e79414c886f5e99bf4c442797cd21a640bf4',
    'macOS/Sources/CaptureServer/BelugaRustPhoneCatalog.swift' => '266922e53f522d2e48ffd255491d5f5ac24203cf9089ef06a46769566d468b42',
    'macOS/Sources/CaptureServer/WorldwidePairedPhoneCatalogStore.swift' => '7c8da7d23a47e2c9c215267b2cc7a90ceff7ec7b66753fb69f92eff93c25e272',
    'macOS/Tests/CaptureServerTests/BelugaRustPhoneCatalogNativeParityTests.swift' => '8323e40ab143ad5a90ea5697d81e12c1e1e16fdcae6bff5d828dbb4764a2f08d',
    'macOS/Tests/CaptureServerTests/FrozenWorldwidePairedPhoneCatalogStore.swift' => 'c9ebcca782d84c77f5b35d41fcec42746005050c3d3f059d1c1c6e62c56a88ee',
    'macOS/Tests/CaptureServerTests/WorldwidePairedPhoneCatalogTests.swift' => '1d556f8ebc7cd85c233d7c513459e6ab3c66702257ab60dc4aff767809e9a31b',
    'macOS/Tests/CaptureServerTests/BelugaRustPairingCatalogCheckpointTests.swift' => '09dda51423b72efbfc5268cc5d3278616dca05c8cc29fe0913e5a8eb1c028d86',
    'macOS/Tests/CaptureServerTests/BelugaPhoneCatalogMenuTests.swift' => '3a07455d1de1f22d269d6f62f7c0592fa5a224019099d97e4403040a35daf213',
    'macOS/Tests/CaptureServerTests/WorldwidePairingCatalogBootstrapTests.swift' => '7c0766fb538152956f367215ae3b1add996420c5ef255c09bb4bce2fcd81cc5d',
  }.freeze
  PHONE_CATALOG_NATIVE_FILES = {
    'CaptureServerTests.BelugaRustPhoneCatalogNativeParityTests' => 'macOS/Tests/CaptureServerTests/BelugaRustPhoneCatalogNativeParityTests.swift',
    'CaptureServerTests.WorldwidePairedPhoneCatalogTests' => 'macOS/Tests/CaptureServerTests/WorldwidePairedPhoneCatalogTests.swift',
    'CaptureServerTests.BelugaRustPairingCatalogCheckpointTests' => 'macOS/Tests/CaptureServerTests/BelugaRustPairingCatalogCheckpointTests.swift',
    'CaptureServerTests.BelugaPhoneCatalogMenuTests' => 'macOS/Tests/CaptureServerTests/BelugaPhoneCatalogMenuTests.swift',
    'CaptureServerTests.WorldwidePairingCatalogBootstrapTests' => 'macOS/Tests/CaptureServerTests/WorldwidePairingCatalogBootstrapTests.swift',
  }.freeze
  PHONE_CATALOG_NATIVE_PINNED = {
    'CaptureServerTests.BelugaRustPhoneCatalogNativeParityTests' => %w[
      CaptureServerTests.BelugaRustPhoneCatalogNativeParityTests/testNativeGoldenAllCountsOccupiedSlotsAndSelectionsPreserveCompleteCustody
      CaptureServerTests.BelugaRustPhoneCatalogNativeParityTests/testNativeMaximumRevisionAllowsExactNoopAndOperationErrorsBeatExhaustion
      CaptureServerTests.BelugaRustPhoneCatalogNativeParityTests/testNativeDualUInt64CountersAndRevisionSuccessorRemainExactAboveSignedRange
      CaptureServerTests.BelugaRustPhoneCatalogNativeParityTests/testNativeActualCryptoRecoveryStatesMatchOriginalTransitionAndCachedCommitRules
      CaptureServerTests.BelugaRustPhoneCatalogNativeParityTests/testNativeDuplicateAxesBeatCapacityAndBindingBeatsBothCounterRegressions
      CaptureServerTests.BelugaRustPhoneCatalogNativeParityTests/testNativeBadCurrentPrecedesStaleTokenAndStaleTokenSuppressesCandidateValidation
      CaptureServerTests.BelugaRustPhoneCatalogNativeParityTests/testNativeLoadedAdmissionOrderingReceiptLifetimeAndDecodeBridgePropagation
      CaptureServerTests.BelugaRustPhoneCatalogNativeParityTests/testNativeBeforeWriteFailureRetainsBytesAndOldTokenCanRetry
      CaptureServerTests.BelugaRustPhoneCatalogNativeParityTests/testNativeWriteThenThrowLeavesDurableSuccessorAndOldTokenRetryIsStale
      CaptureServerTests.BelugaRustPhoneCatalogNativeParityTests/testNativeActualProducerStageTraceKeepsOriginalLazyCuts
      CaptureServerTests.BelugaRustPhoneCatalogNativeParityTests/testNativeEveryByteOfActualCopiedResultRejectsAtEveryUsedStageWithZeroWrites
      CaptureServerTests.BelugaRustPhoneCatalogNativeParityTests/testNativeMalformedInputTagsAndUnusedFieldsCannotBecomeCheckedBusinessResults
      CaptureServerTests.BelugaRustPhoneCatalogNativeParityTests/testNativeConcurrentSameTokenHasExactlyOneWinnerAcrossTwoInstances
    ],
    'CaptureServerTests.WorldwidePairedPhoneCatalogTests' => %w[
      CaptureServerTests.WorldwidePairedPhoneCatalogTests/testMigrationRetainsExactLegacyBytesAndInterruptedCommit
      CaptureServerTests.WorldwidePairedPhoneCatalogTests/testMigrationRetainsBothReconnectCountersAndIgnoresLaterLegacyChanges
      CaptureServerTests.WorldwidePairedPhoneCatalogTests/testEmptyCatalogIsAuthoritativeAndNeverImportsFutureLegacyRecord
      CaptureServerTests.WorldwidePairedPhoneCatalogTests/testIndependentAddExplicitSelectionForgetAndRestart
      CaptureServerTests.WorldwidePairedPhoneCatalogTests/testFirstNewPhoneIsNotSelectedImplicitlyAndSelectionCanBeCleared
      CaptureServerTests.WorldwidePairedPhoneCatalogTests/testStaleTokenRejectsEveryMutationWithoutChangingBytes
      CaptureServerTests.WorldwidePairedPhoneCatalogTests/testUpdateCannotResurrectForgottenPhoneEvenWithFreshToken
      CaptureServerTests.WorldwidePairedPhoneCatalogTests/testCounterAdvanceRetainsSiblingAndSelectionButRegressionFails
      CaptureServerTests.WorldwidePairedPhoneCatalogTests/testPendingCommitProgressAndSamePhaseRecoveryCannotRegress
      CaptureServerTests.WorldwidePairedPhoneCatalogTests/testImmutableBindingCannotBeChangedByUpdate
      CaptureServerTests.WorldwidePairedPhoneCatalogTests/testDuplicateRemoteIDKeyPairAndCommitAreRejected
      CaptureServerTests.WorldwidePairedPhoneCatalogTests/testMaximumEightPhonesNeverEvictsAnExistingRecord
      CaptureServerTests.WorldwidePairedPhoneCatalogTests/testCorruptCurrentCatalogNeverFallsBackOrOverwrites
      CaptureServerTests.WorldwidePairedPhoneCatalogTests/testCorruptWrapperSchemaSelectionAndIdentityFailClosed
      CaptureServerTests.WorldwidePairedPhoneCatalogTests/testPersistedDuplicateRecordsAndMalformedMigrationReceiptFailClosed
      CaptureServerTests.WorldwidePairedPhoneCatalogTests/testNewCatalogRequiresExactCanonicalBytesIncludingNestedRecords
      CaptureServerTests.WorldwidePairedPhoneCatalogTests/testIdentityMissingChangedOrCorruptNeverCreatesCatalog
      CaptureServerTests.WorldwidePairedPhoneCatalogTests/testCorruptOrWrongHostLegacyRecordDoesNotCreateCatalog
      CaptureServerTests.WorldwidePairedPhoneCatalogTests/testStorageFailureLeavesCatalogAndLegacyUnchanged
      CaptureServerTests.WorldwidePairedPhoneCatalogTests/testRevisionExhaustionDoesNotMutateCatalog
      CaptureServerTests.WorldwidePairedPhoneCatalogTests/testConcurrentSameRevisionMutationsHaveOneWinnerAcrossStoreInstances
    ],
    'CaptureServerTests.BelugaRustPairingCatalogCheckpointTests' => %w[
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
    ],
    'CaptureServerTests.BelugaPhoneCatalogMenuTests' => %w[
      CaptureServerTests.BelugaPhoneCatalogMenuTests/testPhoneNamesFlattenWhitespaceAndRemoveControlAndBidiScalars
      CaptureServerTests.BelugaPhoneCatalogMenuTests/testEmptyOrEntirelyInvisiblePhoneNameUsesFixedFallback
      CaptureServerTests.BelugaPhoneCatalogMenuTests/testPhoneNameAndLabelAreBoundedForASCIIEmojiAndCombiningSequences
      CaptureServerTests.BelugaPhoneCatalogMenuTests/testSafeUnicodeAndStableIDSuffixDisambiguateDuplicateNames
      CaptureServerTests.BelugaPhoneCatalogMenuTests/testCatalogDiagnosticDescriptionsDoNotExposeNamesIDsOrTickets
      CaptureServerTests.BelugaPhoneCatalogMenuTests/testCommandsNeedStartedRuntimeInstalledBridgeAndCurrentQuietTicket
      CaptureServerTests.BelugaPhoneCatalogMenuTests/testCommandBridgeInvalidatesObservedMenuWhenQuietPresentationArrivesFirst
      CaptureServerTests.BelugaPhoneCatalogMenuTests/testCommandBridgeBeforeQuietPresentationDoesNotEnablePairingPrematurely
      CaptureServerTests.BelugaPhoneCatalogMenuTests/testExactPresentedTicketAndPhoneIDReachCommandWithoutReplacement
      CaptureServerTests.BelugaPhoneCatalogMenuTests/testPresentedConfirmationTicketIsStaleAfterCatalogRevisionChanges
      CaptureServerTests.BelugaPhoneCatalogMenuTests/testCatalogGenerationAndSelectionEpochChangesAlsoInvalidatePresentedTickets
      CaptureServerTests.BelugaPhoneCatalogMenuTests/testUnknownSelectAndForgetTargetsCannotReachCommand
      CaptureServerTests.BelugaPhoneCatalogMenuTests/testPresentedRemovedTargetCannotBeForgottenEvenWithCurrentTicket
      CaptureServerTests.BelugaPhoneCatalogMenuTests/testCapacityDeniesOnlyPairAnotherWithoutEvictingOrChangingSelection
      CaptureServerTests.BelugaPhoneCatalogMenuTests/testOnlyOnePendingCommandIsAdmittedAndOwnedTaskIsDrained
      CaptureServerTests.BelugaPhoneCatalogMenuTests/testSuccessWaitsForAuthoritativePresentationInsteadOfOptimisticSelection
      CaptureServerTests.BelugaPhoneCatalogMenuTests/testFailureKeepsCatalogAndUsesFixedMessageRatherThanUnderlyingError
      CaptureServerTests.BelugaPhoneCatalogMenuTests/testExplicitNilSelectionIsForwardedWithoutForgettingAnyPhone
      CaptureServerTests.BelugaPhoneCatalogMenuTests/testOlderOrEqualPresentationCannotRestoreSupersededCatalogTicket
      CaptureServerTests.BelugaPhoneCatalogMenuTests/testShutdownRejectsLateCommandBridgeAndActionWithoutChangingStoppedModel
      CaptureServerTests.BelugaPhoneCatalogMenuTests/testShutdownDropsLateSuccessAndFailureFromNonCooperativeCommand
    ],
    'CaptureServerTests.WorldwidePairingCatalogBootstrapTests' => %w[
      CaptureServerTests.WorldwidePairingCatalogBootstrapTests/testStopBeforeHeldCompletionReturnsCannotPersistCompletionSent
    ],
  }.transform_values(&:freeze).freeze
  RUNTIME_CATALOG_RUST_PINNED = BELUGA_CORE_PINNED.drop(513).first(32).freeze
  RUNTIME_CATALOG_RUNTIME_MARKERS = BELUGA_CORE_RUNTIME_MARKERS[52, 2].freeze
  RUNTIME_CATALOG_SOURCE_SHA256 = {
    'shared/Rust/BelugaCore/src/lib.rs' => '5a4db763fdef546ccdf9de324256f8b49c4ad9932e664432a93830ec46d55e2d',
    'shared/Rust/BelugaCore/include/beluga_core.h' => '2ea355f72241c8c62d0eb53b5d342784172637a305ffa3570b290814782d2dcd',
    'shared/Rust/BelugaCore/scripts/artifact_support.rb' => 'a39308cec492ff541f33bddbb3e6332400f33aabf37498e350db97684c524cb7',
    'shared/Rust/BelugaCore/scripts/mutation-tests.rb' => '9cafeff860bd35c6090323679ee0b9ca0ec9a2cba2c65c82d2bb2eda986ac6cd',
    'shared/Rust/BelugaCore/tests/c_abi_smoke.c' => '6c2e4b992f8ff15edcacdb4343e8e42a8867a10201710f904dcd1f9cf38dea37',
    'shared/Rust/BelugaCore/tests/swift_import_smoke.swift' => '733731db3cfd6bd7a3114b9edfc474e5df32d5a18acc053a6cf61b808fc887b1',
    'shared/Rust/BelugaCore/src/runtime_catalog.rs' => '7d1885d86c29871ec798bc29604e102fcfd80ad567ed9e54ba8d8dfdf717e242',
    'shared/Rust/BelugaCore/tests/runtime_catalog.rs' => 'da2312ccea619b95c7ebe210bf32e7b9e2e699320f0a57084c7e1e986832a3e5',
    'macOS/Sources/CaptureServer/BelugaRustRuntimeCatalog.swift' => '2e6530b8ad7e56aee4a91edee27dbc6cbd4bfe6702fd72cee71d290c874445dc',
    'macOS/Sources/CaptureServer/WorldwideHostCoordinator.swift' => 'ed5ae6750f5f5be5946d673fd5049053693c6d5fe2356676d8034acb834fef0f',
    'macOS/Tests/CaptureServerTests/BelugaRustRuntimeCatalogTests.swift' => '3a9565d5068184bb7cbfc7e4353b80eca1435d115f81a399791ec6ca6d639a98',
    'macOS/Tests/CaptureServerTests/FrozenRuntimeCatalogAdmissionReference.swift' => 'b06d3498da1bc8a5fe46d24068ec55f7ead5b1c9134f31cdfdaec91e19dc1e37',
    'macOS/Tests/CaptureServerTests/WorldwideRuntimeCatalogAdmissionActorTests.swift' => '38a01ca9748ddc0858dec60de0fc00c7583ee3667a5f601b460324be07de3feb',
    'macOS/Tests/CaptureServerTests/WorldwideRuntimeCatalogBridgeFaultActorTests.swift' => '07165f801028a6f2a0640cd116950eaa68a1134eaed2a36a8e217950239d0544',
    'macOS/Sources/CaptureServer/WorldwidePairingCatalogCheckpoint.swift' => '0bdde2dd4d9e2229a1015d91cb1b315aee64c52c57fee62399407761b6af2f44',
  }.freeze
  RUNTIME_CATALOG_NATIVE_FILES = {
    'CaptureServerTests.BelugaRustRuntimeCatalogTests' => 'macOS/Tests/CaptureServerTests/BelugaRustRuntimeCatalogTests.swift',
    'CaptureServerTests.WorldwideRuntimeCatalogAdmissionActorTests' => 'macOS/Tests/CaptureServerTests/WorldwideRuntimeCatalogAdmissionActorTests.swift',
    'CaptureServerTests.WorldwideRuntimeCatalogBridgeFaultActorTests' => 'macOS/Tests/CaptureServerTests/WorldwideRuntimeCatalogBridgeFaultActorTests.swift',
  }.freeze
  RUNTIME_CATALOG_NATIVE_PINNED = {
    'CaptureServerTests.BelugaRustRuntimeCatalogTests' => %w[
      CaptureServerTests.BelugaRustRuntimeCatalogTests/testExactLinkedLayoutAndAllNativeStageIDs
      CaptureServerTests.BelugaRustRuntimeCatalogTests/testFirstPairGrantIsHistoricalAndConsumedBeforeBootstrapStop
      CaptureServerTests.BelugaRustRuntimeCatalogTests/testValidRefusalPreservesStateWithoutPoisonAndNativeErrorOrdering
      CaptureServerTests.BelugaRustRuntimeCatalogTests/testMalformedResultCannotInstallStateOrGrantAuthority
      CaptureServerTests.BelugaRustRuntimeCatalogTests/testEveryResultByteBitIsRejectedBeforeNativeStateAdoptionAndPoisonIsSticky
      CaptureServerTests.BelugaRustRuntimeCatalogTests/testMalformedEventEchoCannotBecomeVerifiedSuccess
      CaptureServerTests.BelugaRustRuntimeCatalogTests/testCallerCannotRecreateConsumedFirstPairGrant
      CaptureServerTests.BelugaRustRuntimeCatalogTests/testRevokedCopiedAuthorityAllowsOnlyExactRetainedDrainNotNewAdmission
    ],
    'CaptureServerTests.WorldwideRuntimeCatalogAdmissionActorTests' => %w[
      CaptureServerTests.WorldwideRuntimeCatalogAdmissionActorTests/testFrozenQuietOwnerFreshCatalogTicketOrderingKeepsNativeCallbacksLazy
      CaptureServerTests.WorldwideRuntimeCatalogAdmissionActorTests/testFrozenFirstPairReferenceConsumesIntentOnceAndKeepsReadbackAuthoritySeparate
      CaptureServerTests.WorldwideRuntimeCatalogAdmissionActorTests/testDefaultMutationCapabilityRefusesBeforeRetiringWaitingClient
      CaptureServerTests.WorldwideRuntimeCatalogAdmissionActorTests/testSelectionWaitsForReturnedExactOldCloseAndIndependentlyHeldAvailabilityTask
      CaptureServerTests.WorldwideRuntimeCatalogAdmissionActorTests/testForeignDurableWriteWhileExactOldTaskIsHeldPreventsMutationAndRecovery
      CaptureServerTests.WorldwideRuntimeCatalogAdmissionActorTests/testCancelledSelectStillDrainsThenAppliesOriginalSelectionSemantics
      CaptureServerTests.WorldwideRuntimeCatalogAdmissionActorTests/testCancelledPairAnotherRecoversOnlyAfterExactOldTaskTerminalBoundary
      CaptureServerTests.WorldwideRuntimeCatalogAdmissionActorTests/testStopJoinsRetainedAvailabilityTaskAndPreventsLateSelection
      CaptureServerTests.WorldwideRuntimeCatalogAdmissionActorTests/testPostDrainMutationDenialResumesUnchangedSelectionWithoutGrantingMutationTicket
      CaptureServerTests.WorldwideRuntimeCatalogAdmissionActorTests/testSelectionWriteFailureRecoversOnlyExactUnchangedDurablePredecessor
      CaptureServerTests.WorldwideRuntimeCatalogAdmissionActorTests/testFirstPairSelectionUsesExactActiveReadbackOnlyAfterOwnedBootstrapTeardown
      CaptureServerTests.WorldwideRuntimeCatalogAdmissionActorTests/testFirstPairOwnerAndMutationRevalidationPreserveDistinctPostTeardownCuts
      CaptureServerTests.WorldwideRuntimeCatalogAdmissionActorTests/testFirstPairHeldTeardownRejectsSameTokenDifferentCompleteNativeCheckpoint
      CaptureServerTests.WorldwideRuntimeCatalogAdmissionActorTests/testStoppedFirstPairLateOwnedCallbackCannotSelectIntoFreshCoordinator
    ],
    'CaptureServerTests.WorldwideRuntimeCatalogBridgeFaultActorTests' => %w[
      CaptureServerTests.WorldwideRuntimeCatalogBridgeFaultActorTests/testStartupInstalledFaultRejectsBeforeActorAdoptionAndRemainsSticky
      CaptureServerTests.WorldwideRuntimeCatalogBridgeFaultActorTests/testCorruptFinalEndDeniesSelectSuccessWithoutRollingBackActualDurableWrite
      CaptureServerTests.WorldwideRuntimeCatalogBridgeFaultActorTests/testCorruptFinalEndDeniesForgetSuccessWithoutRestoringDeletedTrust
      CaptureServerTests.WorldwideRuntimeCatalogBridgeFaultActorTests/testCorruptFinalEndDeniesPairInvitationSuccessAndClosesExactBootstrap
      CaptureServerTests.WorldwideRuntimeCatalogBridgeFaultActorTests/testMalformedAdmissionKeepsLiveNativeClientUntilAuthorizedStopAndNeverReproposes
      CaptureServerTests.WorldwideRuntimeCatalogBridgeFaultActorTests/testMalformedWhileRetirementHeldRetainsExactTaskForStopDrainWithoutWriteOrSuccessor
      CaptureServerTests.WorldwideRuntimeCatalogBridgeFaultActorTests/testRetiredGenerationTerminalDoesNotConsumeArmedFaultOrTearDownSuccessor
    ],
  }.transform_values(&:freeze).freeze
  BELUGA_CORE_RUNTIME_MARKER_ORDER = (BELUGA_CORE_RUNTIME_MARKERS.first(15) +
    [BELUGA_CORE_RUNTIME_MARKERS.fetch(30), BELUGA_CORE_RUNTIME_MARKERS.fetch(32), BELUGA_CORE_RUNTIME_MARKERS.fetch(34), BELUGA_CORE_RUNTIME_MARKERS.fetch(36), BELUGA_CORE_RUNTIME_MARKERS.fetch(38), BELUGA_CORE_RUNTIME_MARKERS.fetch(40), BELUGA_CORE_RUNTIME_MARKERS.fetch(42), BELUGA_CORE_RUNTIME_MARKERS.fetch(44), BELUGA_CORE_RUNTIME_MARKERS.fetch(46), BELUGA_CORE_RUNTIME_MARKERS.fetch(48), BELUGA_CORE_RUNTIME_MARKERS.fetch(50), BELUGA_CORE_RUNTIME_MARKERS.fetch(52)] +
    (54...88).step(2).map { |index| BELUGA_CORE_RUNTIME_MARKERS.fetch(index) } +
    BELUGA_CORE_RUNTIME_MARKERS[15, 15] +
    [BELUGA_CORE_RUNTIME_MARKERS.fetch(31), BELUGA_CORE_RUNTIME_MARKERS.fetch(33), BELUGA_CORE_RUNTIME_MARKERS.fetch(35), BELUGA_CORE_RUNTIME_MARKERS.fetch(37), BELUGA_CORE_RUNTIME_MARKERS.fetch(39), BELUGA_CORE_RUNTIME_MARKERS.fetch(41), BELUGA_CORE_RUNTIME_MARKERS.fetch(43), BELUGA_CORE_RUNTIME_MARKERS.fetch(45), BELUGA_CORE_RUNTIME_MARKERS.fetch(47), BELUGA_CORE_RUNTIME_MARKERS.fetch(49), BELUGA_CORE_RUNTIME_MARKERS.fetch(51), BELUGA_CORE_RUNTIME_MARKERS.fetch(53)] +
    (55...88).step(2).map { |index| BELUGA_CORE_RUNTIME_MARKERS.fetch(index) }).freeze

  # Append-only release enrollment. Original ordered policy/case/control prefixes remain intact.
  # These literals were reviewed against the source producers, not inferred from their output.
  BELUGA_CORE_ADDED_MUTATION_ORACLES = [
    [{
    'OC-REVISION' => 'network_adaptation_owner_clocked_events_tests::product_owner_clocked_202_initial_stop_retains_revision_and_full_owner_tail',
    'OC-ROUTE' => 'network_adaptation_owner_clocked_events_tests::product_owner_clocked_212_route_invalidation_advances_and_clears_evidence_not_fast_applied',
    'OC-REFUSAL-PUBLICATION' => 'network_adaptation_owner_clocked_events_tests::product_owner_clocked_every_lazy_callback_failure_refuses_whole_tuple',
    'OC-READ-CORRELATION' => 'network_adaptation_owner_clocked_events_tests::product_owner_clocked_reply_correlation_and_native_range_refuse_each_read',
    'OC-TIME-MASK' => 'network_adaptation_owner_clocked_events_tests::product_owner_clocked_202_initial_stop_retains_revision_and_full_owner_tail',
    'OC-CLOSED-OPERATION' => 'network_adaptation_owner_clocked_events_tests::product_owner_clocked_policy_only_vote_is_closed_before_decode_or_provider',
    }.freeze, BelugaCoreOwnerClockedMutationOracle],
    [{
    'OP-ENTRY-REVISION' => 'network_adaptation_owner_prepare_events_tests::product_owner_prepare_zero_read_entry_none',
    'OP-REFUSAL-PUBLICATION' => 'network_adaptation_owner_prepare_events_tests::product_owner_prepare_provider_denial_all_seven_outputs_untouched',
    'OP-READ-TRANSCRIPT' => 'network_adaptation_owner_prepare_events_tests::product_owner_prepare_late_none_preserves_real_read_transcript',
    'OP-TIME-JOURNAL' => 'network_adaptation_owner_prepare_events_tests::product_owner_prepare_expiry_full222_literal_tail_and_journals',
    }.freeze, BelugaCoreOwnerPrepareMutationOracle],
    [{
    'OI-EXPECTED-REVISION' => 'network_adaptation_owner_inactive_events_tests::product_owner_inactive_expected_revision_not_applying_and_wrap_once',
    'OI-PREPARED-ORIGIN' => 'network_adaptation_owner_inactive_events_tests::product_owner_inactive_equal_coordinates_import_all_nine_prepared_origins',
    'OI-REFUSAL-PUBLICATION' => 'network_adaptation_owner_inactive_events_tests::product_owner_inactive_each_provider_and_reply_denial_refuses_seven_outputs',
    'OI-SUSPENSION-COUNTER' => 'network_adaptation_owner_inactive_events_tests::product_owner_inactive_healthy_L_read_adopts_or_requests_resume',
    }.freeze, BelugaCoreOwnerInactiveMutationOracle],
    [{
    'OA-RESOURCE-GATE' => 'network_adaptation_owner_begin_active_events_tests::active_begin_raw_each_missing_resource_returns_before_attempt_consumption',
    'OA-FAULT-PREFIX' => 'network_adaptation_owner_begin_active_events_tests::active_begin_raw_fault_retains_before_resource_return_without_positive_adoption',
    'OA-ATTEMPT-CONSUMPTION' => 'network_adaptation_owner_begin_active_events_tests::active_begin_raw_attempt_only_changes_negative_fields_and_applying_revision',
    'OA-PROVIDER-STATUS' => 'network_adaptation_owner_begin_active_events_tests::active_begin_raw_same_peer_Q_success_and_all_five_new_peer_denial_prefixes',
    'OA-PREPARED-BODY' => 'network_adaptation_owner_begin_active_events_tests::active_begin_raw_no_native_apply_skips_resources_but_changed_forces_return',
    'OA-REFUSAL-PUBLICATION' => 'network_adaptation_owner_begin_active_events_tests::active_begin_raw_callback_correlation_and_unrepresentable_time_leave_all_nine_outputs',
    'OA-JOURNAL-CLEAR' => 'network_adaptation_owner_begin_active_events_tests::active_begin_raw_attempt_only_changes_negative_fields_and_applying_revision',
    'OA-OWNER-TAIL' => 'network_adaptation_owner_begin_active_events_tests::active_begin_raw_no_invented_revision_peer_or_active_fence_and_exact222',
    }.freeze, BelugaCoreOwnerBeginActiveMutationOracle],
    [{
    'OCV-STALE' => 'network_adaptation_owner_completion_events_tests::active_completion_validated_stale_same_fps_and_missing_thunks_are_explicit',
    'OCV-SAMEFPS' => 'network_adaptation_owner_completion_events_tests::active_completion_validated_stale_same_fps_and_missing_thunks_are_explicit',
    'OCV-RETURN' => 'network_adaptation_owner_completion_events_tests::active_completion_validated_only_one_accepts_and_denial_never_effects_or_writes',
    'OCV-HEADER-FIRST' => 'network_adaptation_owner_completion_events_tests::active_completion_validated_only_one_accepts_and_denial_never_effects_or_writes',
    'OCV-INVOCATION' => 'network_adaptation_owner_completion_events_tests::active_completion_validated_int32_and_invocation_correlation_are_pre_effect',
    'OCV-FPS-FIRST' => 'network_adaptation_owner_completion_events_tests::active_completion_validated_private_full_bundle_precedes_fps_and_all_publication',
    'OC-FRESH-FENCE' => 'network_adaptation_owner_completion_events_tests::active_completion_raw_all_eleven_success_fences_rollback_without_effect_or_import',
    'OC-EFFECT-ORDER' => 'network_adaptation_owner_completion_events_tests::active_completion_raw_callback_carries_exact_invocation_and_fps_before_every_output_write',
    'OC-LATE-CONVERSION' => 'network_adaptation_owner_completion_events_tests::active_completion_raw_int32_conversion_is_only_for_reachable_changed_fps_effect',
    'OC-APPLIED-PUBLICATION' => 'network_adaptation_owner_completion_events_tests::active_completion_raw_current_success_records_only_applied_without_policy_revision_or_import',
    'OC-FINAL-FRESH' => 'network_adaptation_owner_completion_events_tests::active_completion_raw_final_adopt_three_stale_fences_preserve_every_owner_word',
    'OC-FINAL-OPAQUE' => 'network_adaptation_owner_completion_events_tests::active_completion_raw_final_adopt_wraps_once_and_preserves_opaque_applied_ieee_tail',
    'OF-PREFIX-DISCARD' => 'network_adaptation_owner_failure_events_tests::active_failure_raw_FQ_denials_keep_live_pre_Q_prefix_and_success_alone_finishes_cleanup',
    'OF-ERROR-REVISION' => 'network_adaptation_owner_failure_events_tests::active_failure_raw_revision_wrap_waits_for_complete_retention_and_absent_timestamp_stays_absent',
    'OF-ACCEPTED-ATTEMPT' => 'network_adaptation_owner_failure_events_tests::active_failure_raw_second_rejected_cut_keeps_one_accepted_F_and_exact_pre_Q_state',
    'OF-PROVIDER-STATUS' => 'network_adaptation_owner_failure_events_tests::active_failure_raw_provider_denial_correlation_and_bad_coordinate_publish_not_discard_F_prefix',
    'OF-JOURNAL-CLEAR' => 'network_adaptation_owner_failure_events_tests::active_failure_raw_ordinary_uses_applying_and_retains_only_negative_prefix_without_clocks',
    'OF-REFUSAL-PUBLICATION' => 'network_adaptation_owner_failure_events_tests::active_failure_raw_strict_request_headers_and_all401_atoms_reject_before_any_semantic_prefix',
    }.freeze, BelugaCoreOwnerPostAwaitMutationOracle],
    [{
    'MIC-RETRY-BUDGET' => 'eligibility_preserves_absence_fault_and_strict_budget_boundary',
    'MIC-RETRY-ADMISSION' => 'all_eleven_native_failure_categories_have_literal_retry_votes',
    'MIC-RETRY-ABSENT' => 'retry_failure_never_creates_history_or_reopens_a_consumed_budget',
    'MIC-RETRY-CONSUME' => 'recording_sets_one_or_increments_and_always_consumes_retry_permission',
    'MIC-RETRY-ABSENT-EXHAUST' => 'exhaust_absent_history_retains_redrive_but_existing_history_clears_it',
    'MIC-RETRY-CORRELATION' => 'result_correlation_rejects_every_coherent_or_malformed_changed_field',
    'MIC-RETRY-CLEANUP-CORRELATION' => 'result_correlation_rejects_every_coherent_or_malformed_changed_field',
    }.freeze, BelugaCoreMicrophoneRetryMutationOracle],
    [{
    'UA-M01' => 'malformed_abi_and_each_unknown_flag_fail_closed',
    'UA-M02' => 'malformed_abi_and_each_unknown_flag_fail_closed',
    'UA-M03' => 'each_owned_activity_and_missing_teardown_or_interactivity_denies_admission',
    'UA-M04' => 'each_owned_activity_and_missing_teardown_or_interactivity_denies_admission',
    'UA-M05' => 'each_owned_activity_and_missing_teardown_or_interactivity_denies_admission',
    'UA-M06' => 'each_owned_activity_and_missing_teardown_or_interactivity_denies_admission',
    'UA-M07' => 'each_owned_activity_and_missing_teardown_or_interactivity_denies_admission',
    'UA-M08' => 'release_progress_and_menu_precedence_are_independent_of_admission',
    'UA-M09' => 'release_progress_and_menu_precedence_are_independent_of_admission',
    'UA-M10' => 'release_progress_and_menu_precedence_are_independent_of_admission',
    'UA-M11' => 'release_progress_and_menu_precedence_are_independent_of_admission',
    'UA-M12' => 'release_progress_and_menu_precedence_are_independent_of_admission',
    'UA-M13' => 'every_result_field_corruption_is_rejected_for_every_valid_request',
    'UA-M14' => 'release_progress_and_menu_precedence_are_independent_of_admission',
    'UA-M15' => 'release_progress_and_menu_precedence_are_independent_of_admission',
    'UA-M16' => 'release_progress_and_menu_precedence_are_independent_of_admission',
    'UA-M17' => 'release_progress_and_menu_precedence_are_independent_of_admission',
    }.freeze, BelugaCoreUpdateAdmissionMutationOracle],
    [{
    'USA-M01' => 'malformed_abi_phase_and_each_phase_specific_unknown_flag_fail_closed',
    'USA-M02' => 'malformed_abi_phase_and_each_phase_specific_unknown_flag_fail_closed',
    'USA-M03' => 'malformed_abi_phase_and_each_phase_specific_unknown_flag_fail_closed',
    'USA-M04' => 'malformed_abi_phase_and_each_phase_specific_unknown_flag_fail_closed',
    'USA-M05' => 'each_original_guard_preserves_error_precedence_and_phase_actions',
    'USA-M06' => 'each_original_guard_preserves_error_precedence_and_phase_actions',
    'USA-M07' => 'each_original_guard_preserves_error_precedence_and_phase_actions',
    'USA-M08' => 'each_original_guard_preserves_error_precedence_and_phase_actions',
    'USA-M09' => 'each_original_guard_preserves_error_precedence_and_phase_actions',
    'USA-M10' => 'each_original_guard_preserves_error_precedence_and_phase_actions',
    'USA-M11' => 'each_original_guard_preserves_error_precedence_and_phase_actions',
    'USA-M12' => 'malformed_abi_phase_and_each_phase_specific_unknown_flag_fail_closed',
    'USA-M13' => 'malformed_abi_phase_and_each_phase_specific_unknown_flag_fail_closed',
    'USA-M14' => 'all_twelve_valid_carriers_match_literal_original_swift_guards',
    'USA-M15' => 'every_result_field_corruption_is_rejected_for_all_valid_requests',
    'USA-M16' => 'malformed_abi_phase_and_each_phase_specific_unknown_flag_fail_closed',
    'USA-M17' => 'all_twelve_valid_carriers_match_literal_original_swift_guards',
    }.freeze, BelugaCoreUpdateSparkleAdmissionMutationOracle],
    [{
    'prepare-rate-ceiling-widened' => 'preparation_scalar_edges_and_nonfinite_values_match_frozen_swift',
    'match-rate-equality-bypassed' => 'changed_rate_duration_and_all_nonfinite_match_words_match_frozen_swift',
    'mac-drift-widened' => 'exact_mac_one_second_and_phone_two_second_limits_are_inclusive_and_distinct',
    'phone-drift-widened' => 'exact_mac_one_second_and_phone_two_second_limits_are_inclusive_and_distinct',
    'expiry-inclusive' => 'page_millisecond_clock_zero_and_exclusive_thirty_second_edges_keep_original_domain',
    'page-clock-wrong-unit' => 'page_millisecond_clock_zero_and_exclusive_thirty_second_edges_keep_original_domain',
    'prepare-position-presence-ignored' => 'every_native_flag_combination_preserves_missing_and_identity_refusals',
    'match-duration-presence-ignored' => 'every_native_flag_combination_preserves_missing_and_identity_refusals',
    'continuity-identity-ignored' => 'every_native_flag_combination_preserves_missing_and_identity_refusals',
    'video-identity-ignored' => 'every_native_flag_combination_preserves_missing_and_identity_refusals',
    'prepare-NaN-duration-accepted' => 'preparation_scalar_edges_and_nonfinite_values_match_frozen_swift',
    'match-NaN-position-accepted' => 'changed_rate_duration_and_all_nonfinite_match_words_match_frozen_swift',
    'actual-c-prepare-bypassed' => 'actual_c_exports_and_validators_preserve_votes_and_malformed_refusal',
    'actual-c-matches-bypassed' => 'actual_c_exports_and_validators_preserve_votes_and_malformed_refusal',
    'actual-c-prepare-validator-bypassed' => 'actual_c_exports_and_validators_preserve_votes_and_malformed_refusal',
    'actual-c-matches-validator-bypassed' => 'actual_c_exports_and_validators_preserve_votes_and_malformed_refusal',
    }.freeze, BelugaCoreHandoffSourceMutationOracle],
    [{
    'MIC-INPUT-ACQUIRE-BUDGET' => 'input_lease_acquisition_budget_preserves_literal_one_and_three_caps',
    'MIC-INPUT-ACQUIRED' => 'input_lease_acquisition_native_outcomes_have_three_literal_actions',
    'MIC-INPUT-RELEASE-BUDGET' => 'input_lease_release_continuation_requires_retryable_and_strict_budget',
    'MIC-INPUT-FALLBACK' => 'input_lease_release_outcome_preserves_native_fallback_and_external_result',
    'MIC-INPUT-CLOSED-WIRE' => 'input_lease_closed_wire_rejects_all_unused_and_negative_domains',
    'MIC-INPUT-WHOLE-RESULT' => 'input_lease_verifier_rejects_each_field_and_coherent_cross_operation_results',
    'MIC-INPUT-C-PRODUCER' => 'input_lease_actual_c_exports_correlate_accepted_and_refused_results',
    'MIC-INPUT-C-VERIFIER' => 'input_lease_actual_c_exports_correlate_accepted_and_refused_results',
    }.freeze, BelugaCoreMicrophoneInputLeaseMutationOracle],
    [{
    'MIC-OUTPUT-FORMAT-CLOSED-WIRE' => 'output_format_malformed_wire_is_not_an_ordinary_policy_rejection',
    'MIC-OUTPUT-FORMAT-FIRST-GUARD' => 'output_format_every_simultaneous_error_pair_preserves_first_guard',
    'MIC-OUTPUT-FORMAT-RATE-EXACT' => 'output_format_rates_use_numeric_equality_but_rejections_keep_original_bits',
    'MIC-OUTPUT-FORMAT-SIGNED-STATUS' => 'output_format_four_signed_statuses_preserve_negative_and_extreme_values',
    'MIC-OUTPUT-FORMAT-FULL-U32' => 'output_format_integer_fields_are_exact_not_masks_ranges_or_truncated_values',
    'MIC-OUTPUT-FORMAT-WHOLE-RESULT' => 'output_format_authoritative_verifier_rejects_corruption_of_every_result_field',
    'MIC-OUTPUT-FORMAT-C-PRODUCER' => 'output_format_actual_c_exports_correlate_success_rejection_and_refusal',
    'MIC-OUTPUT-FORMAT-C-VERIFIER' => 'output_format_actual_c_exports_correlate_success_rejection_and_refusal',
    }.freeze, BelugaCoreMicrophoneOutputFormatMutationOracle],
  ].map(&:freeze).freeze
  BELUGA_CORE_ADDED_MUTANT_TESTS = BELUGA_CORE_ADDED_MUTATION_ORACLES
    .map(&:first).reduce({}) { |all, cases| all.merge(cases) }.freeze
  BELUGA_CORE_OWNER_MUTANT_TESTS = BELUGA_CORE_ADDED_MUTATION_ORACLES.first(5)
    .map(&:first).reduce({}) { |all, cases| all.merge(cases) }.freeze

  # Existing pinned names are retained for earlier append-only cohort assertions.
  # Their suite authority is now explicit: matching names in different binaries are
  # different cases, but duplicate records within the same binary still fail.
  BELUGA_CORE_REVIEWED_CASE_SUITES = {
    'policy' => BELUGA_CORE_PINNED[0, 7],
    'host_lifecycle' => BELUGA_CORE_PINNED[7, 8],
    'handoff_transactions' => BELUGA_CORE_PINNED[15, 10],
    'handoff_offers' => BELUGA_CORE_PINNED[25, 19],
    'youtube_handoff_operation' => BELUGA_CORE_PINNED[44, 32],
    'invitation_acceptance' => BELUGA_CORE_PINNED[76, 22],
    'replay_policy' => BELUGA_CORE_PINNED[98, 21],
    'pairing_catalog_checkpoint' => BELUGA_CORE_PINNED[119, 8],
    'reconnect_counters' => BELUGA_CORE_PINNED[127, 12],
    'pairing_commit' => BELUGA_CORE_PINNED[139, 20],
    'supported_player_arbitration' => BELUGA_CORE_PINNED[159, 17],
    'availability_retry' => BELUGA_CORE_PINNED[176, 15],
    'safe_output_retry' => BELUGA_CORE_PINNED[191, 11],
    'system_audio_start' => BELUGA_CORE_PINNED[202, 4],
    'hosted_call_policy' => BELUGA_CORE_PINNED[206, 10],
    'display_admission' => BELUGA_CORE_PINNED[216, 35],
    'output_dimensions' => BELUGA_CORE_PINNED[251, 17],
    'ice_recovery' => BELUGA_CORE_PINNED[268, 25],
    'lib' => BELUGA_CORE_PINNED[293, 28],
    'update_operation' => BELUGA_CORE_PINNED[321, 18],
    'packet_send_queue' => BELUGA_CORE_PINNED[339, 32],
    'rtt_evidence' => BELUGA_CORE_PINNED[371, 34],
    'tier_demand' => BELUGA_CORE_PINNED[405, 28],
    'media_command_gate' => BELUGA_CORE_PINNED[433, 21],
    'screen_suspension' => BELUGA_CORE_PINNED[454, 32],
    'phone_catalog' => BELUGA_CORE_PINNED[486, 27],
    'runtime_catalog' => BELUGA_CORE_PINNED[513, 32],
  }.transform_values(&:freeze).freeze
  BELUGA_CORE_ADDED_RUST_BY_SUITE = {
    'microphone_forwarding_retry' => %w[
      wire_sizes_alignments_and_discriminants_are_literal
      eligibility_preserves_absence_fault_and_strict_budget_boundary
      recording_sets_one_or_increments_and_always_consumes_retry_permission
      all_eleven_native_failure_categories_have_literal_retry_votes
      retry_failure_never_creates_history_or_reopens_a_consumed_budget
      exhaust_absent_history_retains_redrive_but_existing_history_clears_it
      default_three_attempt_sequence_exhausts_and_fresh_native_key_starts_independently
      malformed_config_state_and_event_carriers_refuse_with_exact_state_retention
      unrepresentable_increment_refuses_without_saturating_or_wrapping
      result_correlation_rejects_every_coherent_or_malformed_changed_field
    ],
    'update_admission' => %w[
      wire_sizes_offsets_and_literal_constants_are_fixed
      all_512_production_boolean_combinations_match_original_swift
      each_owned_activity_and_missing_teardown_or_interactivity_denies_admission
      release_progress_and_menu_precedence_are_independent_of_admission
      malformed_abi_and_each_unknown_flag_fail_closed
      every_result_field_corruption_is_rejected_for_every_valid_request
      coherent_but_wrong_permission_progress_and_presentation_are_rejected
      denial_for_one_activity_cannot_certify_a_ready_result_from_another_request
    ],
    'update_sparkle_admission' => %w[
      wire_sizes_offsets_and_literal_constants_are_fixed
      all_twelve_valid_carriers_match_literal_original_swift_guards
      each_original_guard_preserves_error_precedence_and_phase_actions
      malformed_abi_phase_and_each_phase_specific_unknown_flag_fail_closed
      every_result_field_corruption_is_rejected_for_all_valid_requests
      coherent_cross_request_results_require_whole_result_correlation
      query_and_admission_results_cannot_cross_the_native_authority_boundary
      valid_denials_remain_distinct_from_invalid_and_do_not_grant_phase_actions
    ],
    'microphone_forwarding_evidence' => %w[
      independent_controls::both_health_readiness_votes_are_independently_required
      independent_controls::full_optional_counter_domain_keeps_independent_and_guarded_votes
      independent_controls::freshness_clock_request_matches_original_short_circuit_predicate
      independent_controls::raw_positive_decisions_cannot_silently_become_false_or_no_change
      result_correlation_controls::readiness_correlation_accepts_literal_true_and_legitimate_false_results
      result_correlation_controls::readiness_correlation_rejects_each_field_coherent_corruption_and_invalid_match
      result_correlation_controls::watermark_correlation_accepts_literal_transition_and_exact_opaque_retention
      result_correlation_controls::watermark_correlation_rejects_all_nested_fields_coherent_noop_and_invalid_match
      result_correlation_controls::freshness_correlation_accepts_literal_fresh_notfresh_and_needsnow
      result_correlation_controls::freshness_correlation_rejects_each_field_coherent_clockplan_and_invalid_match
    ],
    'update_unarmed_completion' => %w[
      wire_layout_offsets_and_closed_literal_values_are_fixed
      all_1572864_valid_carriers_match_the_literal_original_branch_priority
      each_native_reason_path_and_its_blocking_presence_facts_are_exact
      original_found_item_and_candidate_attempt_omissions_are_not_strengthened
      unsupported_abi_failure_kind_and_every_unknown_flag_fail_closed
      every_copied_result_field_requires_whole_request_correlation
      coherent_cross_request_reasons_cannot_mint_a_different_completion
      copied_inputs_and_results_have_no_retained_owner_or_effect_state
    ],
    'update_abort' => %w[
      wire_layout_offsets_and_literal_constants_are_fixed
      all_64_valid_carriers_match_the_literal_original_first_if_else_if
      first_if_mark_abort_wins_even_when_same_no_update_error_is_true
      preserve_else_if_is_not_strengthened_by_unrelated_failure_facts
      unsupported_abi_and_every_unknown_flag_refuse_without_valid_action
      every_result_field_and_coherent_cross_request_action_require_full_correlation
      actual_c_exports_match_the_literal_original_and_refuse_unverified_carriers
    ],
    'handoff_source_position' => %w[
      every_native_flag_combination_preserves_missing_and_identity_refusals
      unknown_bits_wrong_abi_and_reserved_fields_are_malformed_not_business_refusals
      preparation_scalar_edges_and_nonfinite_values_match_frozen_swift
      option_absence_is_a_valid_refusal_and_does_not_invent_payload_authority
      exact_mac_one_second_and_phone_two_second_limits_are_inclusive_and_distinct
      page_millisecond_clock_zero_and_exclusive_thirty_second_edges_keep_original_domain
      changed_rate_duration_and_all_nonfinite_match_words_match_frozen_swift
      signed_zero_raw_bits_and_original_unissuable_match_inputs_are_not_normalized
      copied_results_cannot_forge_allow_refuse_abi_status_or_reserved_fields
      copied_c_layouts_pin_every_word_and_no_pointer_or_native_object
      actual_c_exports_and_validators_preserve_votes_and_malformed_refusal
    ],
    'microphone_input_lease' => %w[
      input_lease_literal_layout_and_field_offsets
      input_lease_acquisition_budget_preserves_literal_one_and_three_caps
      input_lease_acquisition_native_outcomes_have_three_literal_actions
      input_lease_release_continuation_requires_retryable_and_strict_budget
      input_lease_release_outcome_preserves_native_fallback_and_external_result
      input_lease_closed_wire_rejects_all_unused_and_negative_domains
      input_lease_verifier_rejects_each_field_and_coherent_cross_operation_results
      input_lease_actual_c_exports_correlate_accepted_and_refused_results
    ],
    'microphone_output_format' => %w[
      output_format_literal_contract_preserves_signed_and_full_width_fields
      output_format_acceptance_copies_all_twelve_observation_fields
      output_format_each_known_rejection_is_a_valid_projection
      output_format_every_simultaneous_error_pair_preserves_first_guard
      output_format_four_signed_statuses_preserve_negative_and_extreme_values
      output_format_integer_fields_are_exact_not_masks_ranges_or_truncated_values
      output_format_rates_use_numeric_equality_but_rejections_keep_original_bits
      output_format_malformed_wire_is_not_an_ordinary_policy_rejection
      output_format_authoritative_verifier_rejects_corruption_of_every_result_field
      output_format_verifier_rejects_coherent_wrong_success_rejection_and_precedence
      output_format_raw_nan_result_equality_is_reflexive_and_payload_exact
      output_format_actual_c_exports_correlate_success_rejection_and_refusal
    ],
  }.transform_values(&:freeze).freeze
  BELUGA_CORE_QUALIFIED_PINNED = (
    BELUGA_CORE_REVIEWED_CASE_SUITES.flat_map { |suite, ids| ids.map { |id| suite + '/' + id } } +
    BELUGA_CORE_ADDED_RUST_BY_SUITE.to_a.first(4).flat_map { |suite, ids| ids.map { |id| suite + '/' + id } } +
    BELUGA_CORE_OWNER_MUTANT_TESTS.values.uniq.map { |id| 'lib/' + id } +
    BELUGA_CORE_ADDED_RUST_BY_SUITE.fetch('update_unarmed_completion').map { |id| 'update_unarmed_completion/' + id } +
    BELUGA_CORE_ADDED_RUST_BY_SUITE.fetch('update_abort').map { |id| 'update_abort/' + id } +
    BELUGA_CORE_ADDED_RUST_BY_SUITE.fetch('handoff_source_position').map { |id| 'handoff_source_position/' + id } +
    BELUGA_CORE_ADDED_RUST_BY_SUITE.fetch('microphone_input_lease').map { |id| 'microphone_input_lease/' + id } +
    BELUGA_CORE_ADDED_RUST_BY_SUITE.fetch('microphone_output_format').map { |id| 'microphone_output_format/' + id }
  ).freeze
  BELUGA_CORE_CARGO_SUITES = (['lib'] + BELUGA_CORE_SOURCE_FILES.map do |relative|
    /\Atests\/([a-z_]+)\.rs\z/.match(relative)&.[](1)
  end.compact.sort + ['doc']).freeze

  # Exact qualified copied-value completion source companions. Native owner authority
  # remains in the reviewed Swift caller; this map grants no installed/runtime proof.
  UNARMED_COMPLETION_SOURCE_SHA256 = {
    'shared/Rust/BelugaCore/src/update_unarmed_completion.rs' => 'ef616de13b1312a0869f8ca34a953618c5dd9ef9daf0d974562b1c177fa57d79',
    'shared/Rust/BelugaCore/tests/update_unarmed_completion.rs' => 'acead2c85360be7548eb4963384e7c0bfb864ec1c5367e75a59aefd3b545cd2e',
    'macOS/Sources/BelugaUpdateCore/BelugaRustUnarmedCompletion.swift' => 'c43229b13a5fccc5ab1c9a200931a1f68be61003bd9d8664694b96fdc335e352',
    'macOS/Sources/BelugaUpdateDriver/BelugaUpdateSparkleSession.swift' => 'b80412aeed0d4736107ccdb108ea737ef19c647ed3bac83c087a3ba909de0536',
    'macOS/Tests/CaptureServerTests/BelugaRustUnarmedCompletionTests.swift' => '257315325ead8080a3eb39836af14f60906f00f22f446176eb8c17b22b673501',
    'macOS/Tests/CaptureServerTests/BelugaUpdateSparkleFinishedCycleTests.swift' => '20eef056379b91d6f45fac78346e78c8f80ca0a9bd4334b9fb802017dfe136dc',
    'macOS/Tests/CaptureServerTests/BelugaUpdateSparkleSessionTests.swift' => 'e85b590d21b525d95515de65c67bd3095ce01c660c0c8526e3f0ef4868fe9d73',
  }.freeze

  # Source-bound copied abort policy and actual adapter companions only. SDK-originated
  # delivery, installed upgrade and the separately retained controls remain separate proof.
  ABORT_CLASSIFIER_SOURCE_SHA256 = {
    'shared/Rust/BelugaCore/src/update_abort.rs' => 'b8d3ff35dba36ecf41ea77d5b8821f4a8052e22b25010a3cbeec8a994d71820b',
    'shared/Rust/BelugaCore/tests/update_abort.rs' => 'f4229d63e85394c0330c770fb12ca498f80c4fb3354f4c50608df6378dfff145',
    'macOS/Sources/BelugaUpdateCore/BelugaRustUpdateAbort.swift' => '145463a875106b9cf526270ad811fa3210fcfd77c7620b062dd57c690bf168e2',
    'macOS/Sources/BelugaUpdateDriver/BelugaUpdateSparkleSession.swift' => 'b80412aeed0d4736107ccdb108ea737ef19c647ed3bac83c087a3ba909de0536',
    'macOS/Tests/CaptureServerTests/BelugaRustUpdateAbortTests.swift' => '0f859f032d41e3f1eacc3e2f79b5b131a3da8923598fd546f3fcb6916c0da0f2',
    'macOS/Tests/CaptureServerTests/BelugaUpdateSparkleSessionTests.swift' => 'e85b590d21b525d95515de65c67bd3095ce01c660c0c8526e3f0ef4868fe9d73',
  }.freeze

  # Copied input-lease votes and actual native callers only. This source map grants
  # no controller, route, physical-device, installed-app or deployment proof.
  MICROPHONE_INPUT_LEASE_SOURCE_SHA256 = {
    'shared/Rust/BelugaCore/src/microphone_input_lease.rs' => 'ebac130dd424df3d76bb3765ac61bf911989081109842aab7965c53b9d39bb84',
    'shared/Rust/BelugaCore/tests/microphone_input_lease.rs' => 'ef623ed823213e8a238ea408d12a81b3dbaa74cf384a865772d9bfaeed7a69ee',
    'macOS/Sources/CaptureServer/BelugaRustMicrophoneInputLease.swift' => '1d7b8977746c31fbb55e2492cb0ee7d33235cd10605b8440ad462090df24a450',
    'macOS/Tests/CaptureServerTests/BelugaRustMicrophoneInputLeaseTests.swift' => '955bc2f085fd087d2da5f3e9d51c8794b5ec5228513f07d1f27987274c24ea60',
    'macOS/Sources/CaptureServer/WorldwideIPhoneMicrophoneForwardingDriver.swift' => '6383ce54886f701081cd8de20a353df55785b23df9c34cfc6d258bd889b55a9c',
    'macOS/Tests/CaptureServerTests/WorldwideIPhoneMicrophoneForwardingDriverTests.swift' => '9264dbc7b35a94aed679d719b935c570c1334bbc907b57374cf8f704ae60e8ba',
  }.freeze
  MICROPHONE_INPUT_LEASE_NATIVE_FILES = {
    'CaptureServerTests.BelugaRustMicrophoneInputLeaseTests' => 'macOS/Tests/CaptureServerTests/BelugaRustMicrophoneInputLeaseTests.swift',
    'CaptureServerTests.WorldwideIPhoneMicrophoneForwardingDriverTests' => 'macOS/Tests/CaptureServerTests/WorldwideIPhoneMicrophoneForwardingDriverTests.swift',
    'CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests' => 'macOS/Tests/CaptureServerTests/WorldwideIPhoneMicrophoneForwardingDriverTests.swift',
  }.freeze
  MICROPHONE_INPUT_LEASE_NATIVE_COUNTS = {
    'CaptureServerTests.BelugaRustMicrophoneInputLeaseTests' => 4,
    'CaptureServerTests.WorldwideIPhoneMicrophoneForwardingDriverTests' => 47,
    'CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests' => 44,
  }.freeze
  MICROPHONE_INPUT_LEASE_NATIVE_ADDITIONS = MAC_PINNED.drop(520).first(20).freeze

  # Copied output-format decisions only; native reads, queue effects and route ownership
  # remain in their original Swift owner. These pins grant no live/device/release proof.
  MICROPHONE_OUTPUT_FORMAT_SOURCE_SHA256 = {
    'shared/Rust/BelugaCore/src/microphone_output_format.rs' => '47af1d2aaeb2da1c19e08581f819a78e362e51c3fa68b2cbc7ef393468627771',
    'shared/Rust/BelugaCore/tests/microphone_output_format.rs' => 'b5a658e63cc8fdaf8fbc1dc92a31d8486b939934c9dc47e112d293ac2f19c45b',
    'macOS/Sources/CaptureServer/BelugaRustMicrophoneOutputFormat.swift' => '11275fdea52f7a4289ce22763b9c5aeb139dfeb26155702db8f02bcf8954903b',
    'macOS/Sources/CaptureServer/BlackHoleMicrophoneOutputFormatPolicy.swift' => '88c987e240eb2f5caf9b23a554e10291e5fe1dbe6ddb8dacd9e0441d1fba9b2d',
    'macOS/Tests/CaptureServerTests/BelugaRustMicrophoneOutputFormatTests.swift' => 'bbc6a1801d0dc229e12ce8c445635f30d7a00f2ffe5d21bc9d9a611c2077c90e',
    'macOS/Tests/CaptureServerTests/FrozenMicrophoneOutputFormatReference.swift' => '26dcb0ff9dfebcc4f49925cee3a1483595fead1f13ef4efbb09d70a093243ce9',
  }.freeze
  MICROPHONE_OUTPUT_FORMAT_NATIVE_FILES = {
    'CaptureServerTests.BelugaRustMicrophoneOutputFormatTests' => 'macOS/Tests/CaptureServerTests/BelugaRustMicrophoneOutputFormatTests.swift',
  }.freeze
  MICROPHONE_OUTPUT_FORMAT_NATIVE_ADDITIONS = MAC_PINNED.drop(540).first(11).freeze

  UPDATER_MICROPHONE_NATIVE_FILES = {
    'CaptureServerTests.BelugaUpdateControllerTests' => 'macOS/Tests/CaptureServerTests/BelugaUpdateControllerTests.swift',
    'CaptureServerTests.BelugaRustSparkleAdmissionTests' => 'macOS/Tests/CaptureServerTests/BelugaRustSparkleAdmissionTests.swift',
    'CaptureServerTests.BelugaRustUpdateAvailabilityTests' => 'macOS/Tests/CaptureServerTests/BelugaRustUpdateAvailabilityTests.swift',
    'CaptureServerTests.BelugaRustMicrophoneForwardingEvidenceTests' => 'macOS/Tests/CaptureServerTests/BelugaRustMicrophoneForwardingEvidenceTests.swift',
    'CaptureServerTests.BelugaUpdateSparkleSessionTests' => 'macOS/Tests/CaptureServerTests/BelugaUpdateSparkleSessionTests.swift',
    'CaptureServerTests.BelugaRustMicrophoneForwardingRetryTests' => 'macOS/Tests/CaptureServerTests/BelugaRustMicrophoneForwardingRetryTests.swift',
    'CaptureServerTests.BelugaRustUnarmedCompletionTests' => 'macOS/Tests/CaptureServerTests/BelugaRustUnarmedCompletionTests.swift',
    'CaptureServerTests.BelugaUpdateSparkleFinishedCycleTests' => 'macOS/Tests/CaptureServerTests/BelugaUpdateSparkleFinishedCycleTests.swift',
    'CaptureServerTests.BelugaRustUpdateAbortTests' => 'macOS/Tests/CaptureServerTests/BelugaRustUpdateAbortTests.swift',
  }.freeze
  # Preserve each primary-file roster; compound suites enroll exact companions separately.
  UPDATER_MICROPHONE_NATIVE_COMPANIONS = {
    'CaptureServerTests.BelugaRustMicrophoneForwardingEvidenceTests' => {
      path: 'macOS/Tests/CaptureServerTests/FreshnessFaultBetweenPhasesTests.swift',
      methods: %w[
        CaptureServerTests.BelugaRustMicrophoneForwardingEvidenceTests/testFaultBetweenFreshnessPhasesRefusesBeforeProducer
      ].freeze,
    }.freeze,
  }.freeze
  UPDATER_MICROPHONE_NATIVE_SOURCE_SHA256 = {
    'macOS/Tests/CaptureServerTests/BelugaRustMicrophoneForwardingEvidenceTests.swift' => '35afc3bfca4c334263703f0563970ac8c745db8e5915e0ede476deb0d34871a2',
    'macOS/Tests/CaptureServerTests/FreshnessFaultBetweenPhasesTests.swift' => 'c4632508c25a8304f240415e6b09975fe34c65effd1157dbc33ec23e43bbe17e',
    'macOS/Tests/CaptureServerTests/BelugaRustMicrophoneForwardingRetryTests.swift' => '7599acfb740a0ad2c1ca219774ed76be83821800603e14a2e6fa2452a506d9e7',
    'macOS/Tests/CaptureServerTests/BelugaRustUpdateAvailabilityTests.swift' => 'd9c55190429fb28df2e73bdfe9086ebbcd4dee713baaa74c22dfe0e46581b94b',
    'macOS/Tests/CaptureServerTests/BelugaRustSparkleAdmissionTests.swift' => '13cb349aef860872cb692cce6a365ead1db8db9dca3fee561a63a521bae90d8c',
    'macOS/Tests/CaptureServerTests/BelugaUpdateControllerTests.swift' => 'dc2dea3c4ec47fe197f7e41dfe7888ebc4406ecbc4d78fad7364c0d0550488bc',
    'macOS/Tests/CaptureServerTests/BelugaUpdateSparkleSessionTests.swift' => 'e85b590d21b525d95515de65c67bd3095ce01c660c0c8526e3f0ef4868fe9d73',
    'macOS/Tests/CaptureServerTests/BelugaRustUnarmedCompletionTests.swift' => '257315325ead8080a3eb39836af14f60906f00f22f446176eb8c17b22b673501',
    'macOS/Tests/CaptureServerTests/BelugaUpdateSparkleFinishedCycleTests.swift' => '20eef056379b91d6f45fac78346e78c8f80ca0a9bd4334b9fb802017dfe136dc',
    'macOS/Tests/CaptureServerTests/BelugaRustUpdateAbortTests.swift' => '0f859f032d41e3f1eacc3e2f79b5b131a3da8923598fd546f3fcb6916c0da0f2',
  }.freeze
  UPDATER_MICROPHONE_NATIVE_PINNED = {
    'CaptureServerTests.BelugaUpdateControllerTests' => %w[
      CaptureServerTests.BelugaUpdateControllerTests/testIdleCheckIsExplicitSerialAndReenablesOnlyAfterWorkerCompletion
      CaptureServerTests.BelugaUpdateControllerTests/testPendingMarkerBlocksBeforeUIAndReadinessRunsExactlyOnce
      CaptureServerTests.BelugaUpdateControllerTests/testReadinessAndCheckFailureStayBlockedWithoutAutomaticRetry
      CaptureServerTests.BelugaUpdateControllerTests/testActiveMediaPairingSharingAndTeardownDenyCheckWithoutWorker
      CaptureServerTests.BelugaUpdateControllerTests/testActualRustMenuPolicyKeepsCorruptedPlanBlockedAndNeverStartsWorker
      CaptureServerTests.BelugaUpdateControllerTests/testEveryNativeAdmissionCombinationUsesRustWithoutDispatching
      CaptureServerTests.BelugaUpdateControllerTests/testBusyPlanRefusalAfterTaskCreationNeverEntersCheckOrReadinessWorker
    ],
    'CaptureServerTests.BelugaRustSparkleAdmissionTests' => %w[
      CaptureServerTests.BelugaRustSparkleAdmissionTests/testExactLayoutsAndTwelveOriginalGuardCombinationsThroughActualABI
      CaptureServerTests.BelugaRustSparkleAdmissionTests/testUnknownABIPhaseAndEveryPhaseSpecificUnknownFlagRefuse
      CaptureServerTests.BelugaRustSparkleAdmissionTests/testEveryResultFieldAndCoherentWrongActionsAreCorrelatedToActualRequest
      CaptureServerTests.BelugaRustSparkleAdmissionTests/testQueryAndAdmissionCannotCrossVerifiedPhasesAndValidDenialsStayValid
    ],
    'CaptureServerTests.BelugaRustUpdateAvailabilityTests' => %w[
      CaptureServerTests.BelugaRustUpdateAvailabilityTests/testExactCopiedLayoutsAndAll512OriginalPolicyCombinations
      CaptureServerTests.BelugaRustUpdateAvailabilityTests/testUnknownABIAndEveryUnknownFlagDenyWithoutForeignAuthority
      CaptureServerTests.BelugaRustUpdateAvailabilityTests/testEveryCopiedResultFieldIsVerifiedAgainstTheActualRequest
      CaptureServerTests.BelugaRustUpdateAvailabilityTests/testCoherentForeignPlansCannotGrantOrEraseRecoveryAndNoFallbackExists
    ],
    'CaptureServerTests.BelugaRustMicrophoneForwardingEvidenceTests' => %w[
      CaptureServerTests.BelugaRustMicrophoneForwardingEvidenceTests/testReadinessMatchesBothOriginalIndependentVotes
      CaptureServerTests.BelugaRustMicrophoneForwardingEvidenceTests/testWatermarkMatchesOriginalGuardedTransitionAndOptionalHistories
      CaptureServerTests.BelugaRustMicrophoneForwardingEvidenceTests/testFreshnessMatchesOriginalConditionalClockAndExactDeadline
      CaptureServerTests.BelugaRustMicrophoneForwardingEvidenceTests/testReadinessRejectsEveryReturnedByteAndLatchesWithoutFallback
      CaptureServerTests.BelugaRustMicrophoneForwardingEvidenceTests/testWatermarkRejectsEveryReturnedByteWithoutChangingNativeHistory
      CaptureServerTests.BelugaRustMicrophoneForwardingEvidenceTests/testCorruptedFirstFreshnessResultNeverReadsNativeClock
      CaptureServerTests.BelugaRustMicrophoneForwardingEvidenceTests/testCorruptedSecondFreshnessResultReadsOnceButPublishesNoDecision
      CaptureServerTests.BelugaRustMicrophoneForwardingEvidenceTests/testInvalidStatusZeroNeverBecomesLegitimateFalseAcrossFamilies
    ],
    'CaptureServerTests.BelugaUpdateSparkleSessionTests' => %w[
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testInitializationDoesNotConstructOrStartSparkleOrUserInterface
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testExplicitStartupPublishesPreparedAuthorityBeforeExactTargetConstruction
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testMissingOrDeniedPreparedAuthorityNeverConstructsNativeMachinery
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testDuplicateStartupBodyAndFailureAfterStartupCannotStartASecondEngine
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testFactoryReentryCannotConstructEngineOrConfigureAfterAuthorityLoss
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testSDKStartupErrorRetainsOwnedEngineAndCannotRetryStart
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testOnlyExactRequestedManualCheckCanBeAdmittedOnce
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testUpdateAdmissionNeedsManualCycleAndRetainedAuthority
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testCheckPrefixNeverQueriesNativeAuthorityForIneligibleCallbacks
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testAuthorityReentryConsumesFreshRequestAndOuterDenialPreservesNestedCycle
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testAuthorityCompletionReentryReadsFreshRequestWithoutNewStateGuard
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testCopiedPolicyRefusalNeverQueriesOrConsumesPendingNativeRequest
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testCoherentWrongPhaseResultsCannotQueryOrAdmitNativeCycle
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testOuterCopiedRefusalPreservesNestedAdmissionAndConsumedRequest
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testInstallAndRetryUseExactOperationGateBeforeForwarding
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testInstallDenialThrowOrLostOwnershipNeverForwardsInstall
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testExtractionInvariantDetectsMissingInstallGateWithoutExecutingNativeHook
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testTargetTerminationRequiresExactUpdaterAndContinuouslyRetainedBrokerAuthority
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testVerifiedFeedOverridesDefaultsOnlyForExactConstructedUpdaterIdentity
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testResumeAndNonterminalObservationsNeverReleaseAuthorityOrRestartCycle
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testUnexpectedInstallOnQuitIsOnlyStalledAndNeverClaimedCancelled
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testInstalledObservationIsOneUseAndCannotStartAnotherCheckDuringStartupReentry
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testSupportedPublicDelegateSelectorsAreActuallyPresentWithoutInstantiatingSDK
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testActualPrivateBrokerLeaseAndFenceComposeBeforeStartupAndInstallReply
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testMissingTrustedCandidateDeniesAdmissionAndFirstInstallBeforeAuthority
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testSignedHighBuildSingleViewerCandidateIsRejectedBeforeBindingOrInstall
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testBindingFailureOrOwnershipLossCannotForwardInstall
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testSameCandidateBindsOnceAndDifferentCandidateCannotReplaceIt
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testReadyAndRetryCannotSkipSignedFirstInstallEvenAfterCandidateAdmission
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testPairedNativeManualNoUpdateCompletionIsOneUseOnlyInsideRetirementCallback
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testNoUpdateWithoutExplicitOwnerRetirementIsObservationOnly
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testNoUpdateRequiresSameNativeErrorManualCycleAndIdleCurrentSDK
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testWrongOrDuplicateNoUpdateCycleAndForeignCallbacksNeverRetire
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testCandidateResumeArmExtractionAndTerminationContaminateUnarmedCycle
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testNoUpdateRetirementFailureOrCycleObservationReentryKeepsAuthority
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testAcceptedInitialCheckCancelRetiresOnlyAfterActualIdleSDKCycleCompletion
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testSynchronousInitialCheckUIAfterSDKStartupDoesNotPoisonFreshCancel
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testFreshNotDownloadedSkipOrDismissRequiresUIAndExactSDKChoiceThenCleanup
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testDeclineRejectsMissingMismatchedResumedDuplicateOrUncertainNativePair
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testCheckCancelRejectsMissingStaleDownloadCandidateErrorOrLaterUnsafeActivity
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testDeniedInstallConvertedToDismissCannotMasqueradeAsNeverArmedUserDecline
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testDeclineCycleObservationReentryInvalidatesPendingRetirement
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testRepeatedExactCandidateAdmissionCannotCertifyUnarmedDecline
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testActualPrivateControlledBrokerNoUpdateRetiresOnlyAfterDriverPairing
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testNativeFactoryUsesRealSignatureGateWithoutConstructingAnUpdater
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testFreshInitialFeedFailuresNeedAcknowledgementExactAbortAndIdleFinish
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testFailedInitialCheckReasonsOnlyMatchNilDurableCandidate
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testFeedFailureRejectsMissingMismatchedDuplicateOutOfOrderOrUncertainProof
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testSameFeedErrorAfterAnyCandidateAttemptOrUnsafeActivityRemainsFenced
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testInitialFeedFailureCannotClearStartupFailureOrAbsentOwnerAdmission
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testFeedFailureRetirementReentryOrVerifierFailureRetainsAuthority
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testActualPrivateBrokerFeedFailureRequiresExplicitControlledHistory
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testRejectedCandidateDuringFailedCycleObservationInvalidatesMintedProof
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testRejectedCandidateDuringActualCoreVerificationFailsSecondProofAndKeepsFence
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testSignedLookingCachedReplacedOrResumedItemCannotAuthorizeFirstInstall
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testActualPrivateBrokerUnarmedProducerABIControlHasAttributedLeaseWitness
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testActualPrivateBrokerUnarmedVerifierTwoControlHasAttributedLeaseWitness
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testMatchedAbortPreservesNativeNSErrorIdentityAndObservation
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testDuplicateAcknowledgedAbortPoisonsWhileStillDeliveringOriginalEvent
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testActualPrivateBrokerAbortProducerABIControlHasAttributedLeaseWitness
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testActualPrivateBrokerAbortVerifierTwoControlHasAttributedLeaseWitness
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testActualPrivateBrokerAbortCoherentActionControlHasAttributedLeaseWitness
    ],
    'CaptureServerTests.BelugaRustMicrophoneForwardingRetryTests' => %w[
      CaptureServerTests.BelugaRustMicrophoneForwardingRetryTests/testLiteralLayoutsOffsetsAndDiscriminants
      CaptureServerTests.BelugaRustMicrophoneForwardingRetryTests/testEligibilityLiteralAbsencePermissionFaultAndStrictBoundary
      CaptureServerTests.BelugaRustMicrophoneForwardingRetryTests/testRecordLiteralIncrementConsumesPermissionAndRejectsOverflow
      CaptureServerTests.BelugaRustMicrophoneForwardingRetryTests/testAllElevenFailureCategoriesHaveLiteralVotes
      CaptureServerTests.BelugaRustMicrophoneForwardingRetryTests/testRetryFalsePreservesPriorPermissionAndNeverCreatesHistory
      CaptureServerTests.BelugaRustMicrophoneForwardingRetryTests/testLiteralDefaultThreeAndMaximumOneSequences
      CaptureServerTests.BelugaRustMicrophoneForwardingRetryTests/testFixedExhaustAfterRefusalRetainsAbsentRedriveAndClosesPresentPermission
      CaptureServerTests.BelugaRustMicrophoneForwardingRetryTests/testMalformedInputsAndMatchingInvalidStatusZeroNeverBecomeFalseVotes
      CaptureServerTests.BelugaRustMicrophoneForwardingRetryTests/testEveryReturnedByteIsCorrelatedForEveryOperation
      CaptureServerTests.BelugaRustMicrophoneForwardingRetryTests/testAcceptedFalseCorrelationAndCoherentDecisionFlips
    ],
    'CaptureServerTests.BelugaRustUnarmedCompletionTests' => %w[
      CaptureServerTests.BelugaRustUnarmedCompletionTests/testExactLayoutsAndAllSixLiteralReasonsThroughActualCAndPacking
      CaptureServerTests.BelugaRustUnarmedCompletionTests/testEveryBitPackingAndOriginalCandidateAndFoundItemOmissions
      CaptureServerTests.BelugaRustUnarmedCompletionTests/testUnsupportedABISeparateFailureKindAndEveryUnknownFlagRefuse
      CaptureServerTests.BelugaRustUnarmedCompletionTests/testWholeResultAndCoherentCrossRequestReasonsCannotManufactureCompletion
    ],
    'CaptureServerTests.BelugaUpdateSparkleFinishedCycleTests' => %w[
      CaptureServerTests.BelugaUpdateSparkleFinishedCycleTests/testFinishedCycleEarlierEligibilityFailuresSkipSDKGetterAndAuthority
      CaptureServerTests.BelugaUpdateSparkleFinishedCycleTests/testFinishedCycleIdleGetterPrecedesInitialAuthorityAndDenialSkipsLaterQueries
      CaptureServerTests.BelugaUpdateSparkleFinishedCycleTests/testFinishedCycleSuccessfulPairHasExactSDKAuthorityAndRetirementOrder
      CaptureServerTests.BelugaUpdateSparkleFinishedCycleTests/testFinishedCycleSDKGetterReentryCreatesFreshNoUpdateBeforeAuthority
      CaptureServerTests.BelugaUpdateSparkleFinishedCycleTests/testFinishedCycleInitialAuthorityReentrySelectsFreshNoUpdateIdentity
      CaptureServerTests.BelugaUpdateSparkleFinishedCycleTests/testFinishedCycleInitialAuthorityReentrySelectsFreshAcknowledgedAndAbortedFailure
      CaptureServerTests.BelugaUpdateSparkleFinishedCycleTests/testFinishedCycleInitialAuthorityReentrySelectsFreshCancellationAfterPresentation
      CaptureServerTests.BelugaUpdateSparkleFinishedCycleTests/testFinishedCycleInitialAuthorityReentrySelectsFreshDeclineAndExactNativePayload
      CaptureServerTests.BelugaUpdateSparkleFinishedCycleTests/testFinishedCycleNestedObservationClearsOuterProofBeforeRetirement
    ],
    'CaptureServerTests.BelugaRustUpdateAbortTests' => %w[
      CaptureServerTests.BelugaRustUpdateAbortTests/testExactRequestAndResultLayoutsThroughActualC
      CaptureServerTests.BelugaRustUpdateAbortTests/testAllSixFactBitsAndOriginalFirstIfPriorityThroughActualClassify
      CaptureServerTests.BelugaRustUpdateAbortTests/testUnknownABIAndEveryUnknownFlagRefuse
      CaptureServerTests.BelugaRustUpdateAbortTests/testWholeResultFieldsAndCoherentWrongSupportedActionsRefuse
    ],
  }.transform_values(&:freeze).freeze

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
    test_display_admission_source_and_each_actual_rust_case_are_mandatory
    test_display_admission_runtime_markers_and_compiled_controls_are_mandatory
    test_display_admission_native_exact_discovery_and_every_result_are_mandatory
    test_display_admission_native_body_companions_refuse_tamper_missing_and_links
    test_display_admission_native_declaration_drift_and_borrowed_coverage_are_rejected
    test_display_admission_enrollment_preserves_complete_previous_inventory
    test_output_dimensions_sources_and_each_actual_rust_case_are_mandatory
    test_output_dimensions_every_runtime_marker_and_exact_stage_order_are_mandatory
    test_output_dimensions_compiled_controls_refuse_wrong_cases_compiler_panics_and_footers
    test_output_dimensions_actual_native_discovery_and_each_result_are_mandatory
    test_output_dimensions_full_receiving_bodies_refuse_tamper_missing_links_nodes_and_rehash
    test_output_dimensions_declaration_drift_and_borrowed_native_coverage_are_refused
    test_output_dimensions_enrollment_preserves_complete_display_predecessor
    test_ice_recovery_exact_source_rust_and_preserved_output_enrollment
    test_ice_recovery_actual_c_and_swift_markers_preserve_complete_stage_order
    test_ice_recovery_twenty_compiled_controls_require_their_actual_assertion_case
    test_ice_recovery_each_shared_host_and_viewer_method_has_exact_body_discovery_and_result
    test_ice_recovery_original_six_swift_testing_discovery_cannot_be_xctest_or_borrowed
    test_ice_recovery_shared_phase_requires_independent_original_results_after_rehash
    test_ice_recovery_reviewed_body_changes_missing_links_and_rehash_cannot_pass
    test_ice_recovery_four_native_controls_are_exact_root_execution_obligations
    test_ice_recovery_preserves_complete_output_predecessor_and_physical_exclusions
    test_screen_liveness_source_inventory_and_exact_scoped_rust_declarations_are_mandatory
    test_screen_liveness_actual_c_and_swift_markers_require_exact_stage_order
    test_screen_liveness_mutation_unit_routing_and_actual_assertion_are_mandatory
    test_screen_liveness_each_original_shared_and_caller_native_method_is_exact
    test_screen_liveness_reviewed_bodies_and_native_control_anchors_refuse_tamper_missing_links_and_rehash
    test_screen_liveness_native_result_and_discovery_cannot_be_borrowed
    test_screen_liveness_enrollment_preserves_complete_ice_predecessor
    test_updater_operation_additive_source_rust_and_mutation_enrollment_is_exact
    test_updater_operation_c_and_swift_markers_preserve_language_and_stage_order
    test_updater_operation_every_mutant_requires_its_restored_singleton_before_the_next_control
    test_updater_operation_restored_decoder_refuses_wrong_case_status_process_and_footer
    test_updater_operation_native_inventory_keeps_all_discovered_tests_and_existing_76_minimum
    test_updater_operation_enrollment_preserves_complete_liveness_predecessor
    test_packet_send_queue_additive_source_rust_and_native_enrollment_is_exact
    test_packet_send_queue_source_and_discovery_refuse_missing_tampered_or_unbound_bodies
    test_packet_send_queue_actual_link_markers_keep_exact_language_and_stage_order
    test_packet_send_queue_mutations_require_exact_compiled_singleton_and_restored_pair
    test_packet_send_queue_native_results_cannot_be_omitted_skipped_or_borrowed
    test_packet_send_queue_enrollment_preserves_complete_updater_predecessor
    test_rtt_evidence_additive_source_rust_and_native_enrollment_is_exact
    test_rtt_evidence_source_and_discovery_refuse_missing_tampered_or_unbound_bodies
    test_rtt_evidence_actual_link_markers_keep_exact_language_and_stage_order
    test_rtt_evidence_mutations_require_exact_compiled_singleton_and_restored_pair
    test_rtt_evidence_native_results_cannot_be_omitted_skipped_or_borrowed
    test_rtt_evidence_enrollment_preserves_complete_queue_predecessor
    test_tier_demand_additive_source_rust_and_native_enrollment_is_exact
    test_tier_demand_source_and_discovery_refuse_missing_tampered_or_unbound_bodies
    test_tier_demand_actual_link_markers_keep_exact_language_and_stage_order
    test_tier_demand_mutations_require_exact_compiled_singleton_and_restored_pair
    test_tier_demand_native_results_cannot_be_omitted_skipped_or_borrowed
    test_tier_demand_enrollment_preserves_complete_rtt_predecessor
    test_media_command_gate_additive_source_rust_and_native_enrollment_is_exact
    test_media_command_gate_source_and_discovery_refuse_missing_tampered_or_unbound_bodies
    test_media_command_gate_actual_link_markers_keep_exact_language_and_stage_order
    test_media_command_gate_mutations_require_exact_compiled_singleton_and_restored_pair
    test_media_command_gate_native_results_cannot_be_omitted_skipped_or_borrowed
    test_media_command_gate_enrollment_preserves_complete_tier_predecessor
    test_screen_suspension_additive_source_rust_and_native_enrollment_is_exact
    test_screen_suspension_source_and_discovery_refuse_missing_tampered_or_unbound_bodies
    test_screen_suspension_actual_link_markers_keep_exact_language_and_stage_order
    test_screen_suspension_mutations_require_exact_compiled_singleton_and_restored_pair
    test_screen_suspension_native_results_cannot_be_omitted_skipped_or_borrowed
    test_screen_suspension_enrollment_preserves_complete_media_gate_predecessor
    test_phone_catalog_additive_source_rust_and_native_enrollment_is_exact
    test_phone_catalog_source_and_discovery_refuse_missing_tampered_or_unbound_bodies
    test_phone_catalog_actual_link_markers_keep_exact_language_and_stage_order
    test_phone_catalog_mutations_require_exact_compiled_singleton_and_restored_pair
    test_phone_catalog_native_results_cannot_be_omitted_skipped_or_borrowed
    test_phone_catalog_startup_selection_and_exact_methods_are_mandatory
    test_phone_catalog_enrollment_preserves_complete_screen_suspension_predecessor
    test_pairing_executor_post_kill_transient_eperm_requires_actual_esrch
    test_pairing_executor_post_kill_persistent_eperm_is_bounded_and_has_no_proof
    test_pairing_executor_pending_mode_requires_successful_kill_of_captured_group
    test_pairing_executor_final_eperm_cannot_mint_success_proof
    test_pairing_executor_pending_wait_interruption_cannot_mint_success_proof
    test_runtime_catalog_additive_source_rust_and_native_enrollment_is_exact
    test_runtime_catalog_source_pins_refuse_tamper_missing_symlink_and_invalid_encoding
    test_runtime_catalog_exact_declarations_refuse_missing_duplicate_extra_renamed_or_malformed
    test_runtime_catalog_native_and_rust_discovery_are_exact_without_borrowed_or_extra_ids
    test_runtime_catalog_native_and_rust_results_refuse_missing_duplicate_failed_skipped_and_wrong_totals
    test_runtime_catalog_actual_link_markers_preserve_entire_old_order_and_new_language_order
    test_runtime_catalog_enrollment_preserves_all_complete_predecessor_vectors_and_new_totals
    test_runtime_catalog_startup_keeps_exact_29_86_prefixes_and_32_115_full_inventory
    test_runtime_catalog_receipt_rechecks_exact_native_and_rust_discovery_at_both_admission_sites
    test_release_enrollment_all_sources_are_exact_112_without_changing_68_prefix
    test_release_enrollment_cross_suite_equal_names_are_distinct_discovery_and_results
    test_release_enrollment_same_suite_duplicate_discovery_is_never_accepted
    test_release_enrollment_same_suite_duplicate_results_are_never_accepted
    test_release_enrollment_unframed_unknown_and_mismatched_suite_records_are_refused
    test_release_enrollment_cross_suite_swap_cannot_borrow_critical_coverage
    test_release_enrollment_every_new_exact_rust_case_is_required_in_its_actual_suite
    test_release_enrollment_each_suite_count_footer_and_non_skipping_boundary_is_exact
    test_release_enrollment_compiled_boundary_utf8_and_complete_suite_census_are_required
    test_release_enrollment_added_controls_map_exactly_and_do_not_change_474_prefix
    test_release_enrollment_all_81_named_rejections_and_exact_restorations_retain_strict_decoders
    test_release_enrollment_whole_mutation_frames_require_every_added_restoration
    test_release_enrollment_owner269_is_exact_and_old259_or_arbitrary_count_is_not_accepted
    test_release_enrollment_24_added_runtime_markers_keep_exact_full_order_and_old_prefix
    test_release_enrollment_new_native_classes_and_source_cases_are_not_silently_filtered
    test_release_enrollment_four_producer_modules_and_all_23_named_cases_are_mandatory
    test_release_enrollment_combined_owner269_source_has_all_eight_exact_mutation_pins
    test_unarmed_release_enrollment_exact_literal_cases_and_frozen_predecessor_prefixes
    test_unarmed_release_enrollment_each_new_rust_case_and_compiled_cohort_refuses_omission_duplicate_or_foreign
    test_unarmed_release_enrollment_each_new_rust_source_and_closed_source_manifest_is_required
    test_unarmed_release_enrollment_markers_keep_two_language_lanes_and_refuse_missing_duplicate_foreign_or_misorder
    test_unarmed_release_enrollment_each_new_swift_case_refuses_missing_duplicate_foreign_or_wrong_class
    test_unarmed_release_enrollment_every_exact_source_companion_and_same_file_probe_bytes_are_required
    test_unarmed_release_enrollment_only_reviewed_shared_epoch_and_session_pin_change
    test_abort_release_enrollment_exact_literal_cases_and_preserved_predecessor_vectors
    test_abort_release_enrollment_each_rust_case_and_new_suite_refuse_missing_duplicate_failed_ignored_or_foreign
    test_abort_release_enrollment_source_pair_and_closed_manifest_cannot_be_omitted_or_rehashed
    test_abort_release_enrollment_two_markers_preserve_entire_old_language_order_and_refuse_forgery
    test_abort_release_enrollment_each_swift_case_cannot_be_omitted_duplicated_failed_skipped_or_borrowed
    test_abort_release_enrollment_exact_companions_and_authored_native_order_are_required
    test_abort_release_enrollment_only_reviewed_shared_epoch_and_adapter_prefix_change
    test_handoff_source_release_enrollment_exact_append_only_vectors_and_closed_source_pair
    test_handoff_source_release_enrollment_each_rust_case_requires_exact_suite_and_non_skipping_result
    test_handoff_source_release_enrollment_each_native_case_requires_exact_class_and_non_skipping_result
    test_handoff_source_release_enrollment_markers_require_full_language_order_and_exact_literals
    test_handoff_source_mutation_enrollment_preserves_555_prefix_and_exact_16_controls
    test_handoff_source_mutation_enrollment_all_six_singleton_decoders_reject_false_evidence
    test_handoff_source_mutation_enrollment_gate_requires_every_rejection_and_restoration
    test_input_lease_release_enrollment_exact_append_only_vectors_and_closed_source_pair
    test_input_lease_release_enrollment_source_pins_and_exact_authored_declarations_cannot_be_borrowed
    test_input_lease_release_enrollment_each_rust_case_requires_exact_suite_and_non_skipping_result
    test_input_lease_release_enrollment_each_native_case_requires_exact_source_class_and_non_skipping_result
    test_input_lease_release_enrollment_markers_preserve_42_per_language_and_add_exact_43rd_pair
    test_input_lease_mutation_enrollment_preserves_571_prefix_and_exact_eight_literal_controls
    test_input_lease_mutation_enrollment_all_seven_singleton_decoders_reject_false_evidence
    test_input_lease_mutation_enrollment_requires_every_singleton_rejection_and_fresh_restoration
    test_output_format_release_enrollment_exact_append_only_vectors_and_closed_source_pair
    test_output_format_release_enrollment_source_pins_and_exact_authored_declarations_cannot_be_borrowed
    test_output_format_release_enrollment_each_rust_case_requires_exact_suite_and_non_skipping_result
    test_output_format_release_enrollment_each_native_case_requires_exact_source_class_and_non_skipping_result
    test_output_format_release_enrollment_markers_preserve_43_per_language_and_add_exact_44th_pair
    test_output_format_mutation_enrollment_preserves_579_prefix_and_exact_eight_literal_controls
    test_output_format_mutation_enrollment_all_seven_singleton_decoders_reject_false_evidence
    test_output_format_mutation_enrollment_requires_every_singleton_rejection_and_fresh_restoration
    test_rendered_menu_release_gate_exact_append_only_roster_and_real_declarations
    test_rendered_menu_release_gate_each_method_requires_exact_discovery
    test_rendered_menu_release_gate_each_method_requires_passing_runtime_result
    test_rendered_menu_release_gate_package_pin_is_exact_test_only_successor
    test_freshness_companion_enrollment_preserves_base8_and_complete_predecessor_rosters
    test_freshness_companion_source_requires_exact_extension_hash_and_single_method
    test_freshness_companion_requires_exact_discovery_filter_and_non_skipping_execution
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
    'macOS/Sources/CaptureServer/WorldwideHostCoordinator.swift' => 'ed5ae6750f5f5be5946d673fd5049053693c6d5fe2356676d8034acb834fef0f',
    'macOS/Sources/CaptureServer/WorldwidePairedPhoneCatalogStore.swift' => '7c8da7d23a47e2c9c215267b2cc7a90ceff7ec7b66753fb69f92eff93c25e272',
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
                            WebRTCTransportTests.BelugaRustHandoffOffersTests
    WebRTCTransportTests.BelugaRustICERecoveryTests
    WebRTCTransportTests.WorldwideScreenLivenessClassifierTests
    WebRTCTransportTests.BelugaRustScreenLivenessTests
  ].freeze
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
    WebRTCTransportTests.BelugaRustICERecoveryTests/testRawCFullWidthStateAndEveryEnvelopeField
    WebRTCTransportTests.BelugaRustICERecoveryTests/testActualCFirstRejectsEveryMalformedCopiedResultTransactionally
    WebRTCTransportTests.BelugaRustICERecoveryTests/testRawEnvelopeCannotBorrowForgedSuccessfulFinishOrInitializer
    WebRTCTransportTests.BelugaRustICERecoveryTests/testExternalCopiedResultsCannotReviveReplaceOrSuppressCancellation
    WebRTCTransportTests.BelugaRustICERecoveryTests/testMalformedInitializerReportsFailureWithoutInventedState
    WebRTCTransportTests.BelugaRustICERecoveryTests/testCallerFaultCancelsNativeOwnershipAndCannotGrantAnyRecoveryEffect
    WebRTCTransportTests.BelugaRustICERecoveryTests/testFaultAfterSuspendedRestartCompletesBeforeNegativeAssertions
    WebRTCTransportTests.BelugaRustICERecoveryTests/testWrongWaitSelectorIsRejectedBeforeWrongNativeDuration
    WebRTCTransportTests.BelugaRustICERecoveryTests/testExhaustEffectWithoutCommittedDeliveredStateIsRejected
    WebRTCTransportTests.BelugaRustICERecoveryTests/testStaleFinishCannotReviveCancelledCoordinatorThroughCorruptCandidate
    WebRTCTransportTests.BelugaRustICERecoveryTests/testGraceAccelerationAndCoalescingMatchFrozenOriginal
    WebRTCTransportTests.BelugaRustICERecoveryTests/testZeroAndTinyExactDurationsMatchFrozenOriginal
    WebRTCTransportTests.BelugaRustICERecoveryTests/testEveryNonCancellationSleepFailureStopsAndAllowsFreshWorkflow
    WebRTCTransportTests.BelugaRustICERecoveryTests/testThrownCancellationErrorWithoutTaskCancellationConsumesAttempts
    WebRTCTransportTests.BelugaRustICERecoveryTests/testLateSuccessfulAndThrowingRestartCannotActAfterConnectionOrCancel
    WebRTCTransportTests.BelugaRustICERecoveryTests/testLateNonCooperativeSleepCannotAdvanceAfterReset
    WebRTCTransportTests.BelugaRustICERecoveryTests/testSuspendedExhaustionCompletionCannotClearNewWorkflow
    WebRTCTransportTests.BelugaRustICERecoveryTests/testRepeatedDirectCancelVersusIgnoredTerminalIceSignals
    WebRTCTransportTests.WorldwideScreenLivenessClassifierTests/testCoverTrackAndAwaitingBranchesHaveClosedEvidenceStates
    WebRTCTransportTests.WorldwideScreenLivenessClassifierTests/testInboundDecodeAndPresentationStallBranchesUseOrderedCounterEvidence
    WebRTCTransportTests.WorldwideScreenLivenessClassifierTests/testPresentedFramesDistinguishUnchangedContentFromChangingContent
    WebRTCTransportTests.WorldwideScreenLivenessClassifierTests/testFreshPresentationSurvivesAnInterleavedStatisticsOnlyObservation
    WebRTCTransportTests.WorldwideScreenLivenessClassifierTests/testGenerationChangeResetsEveryDeltaBeforeNewEvidenceIsCompared
    WebRTCTransportTests.WorldwideScreenLivenessClassifierTests/testCounterRegressionResetsTheWholeComparisonFloorWithoutUnsignedWrap
    WebRTCTransportTests.WorldwideScreenLivenessClassifierTests/testSnapshotBoundsAgeDimensionsAndFrameRateWithoutContentIdentity
    WebRTCTransportTests.WorldwideScreenLivenessClassifierTests/testAllClassifierStatesAreCoveredByDeterministicBranchFixtures
    WebRTCTransportTests.BelugaRustScreenLivenessTests/testFractionalPresentationAndExactContentFreshnessHaveLiteralDifferentEdges
    WebRTCTransportTests.BelugaRustScreenLivenessTests/testAllCoversPrecedeAbsentTrackAndEveryResetReason
    WebRTCTransportTests.BelugaRustScreenLivenessTests/testCoveredAndMissingTrackObservationsStillAdvanceBothHistorySlots
    WebRTCTransportTests.BelugaRustScreenLivenessTests/testEachSingleRegressionClearsAllDeltasAndGenerationWinsPrecedence
    WebRTCTransportTests.BelugaRustScreenLivenessTests/testOptionalCounterHolesAndMetadataOnlyInboundAreNotZero
    WebRTCTransportTests.BelugaRustScreenLivenessTests/testDimensionFallbackIsPerAxisAndFPSRawNaNPayloadDoesNotBecomeAConstraint
    WebRTCTransportTests.BelugaRustScreenLivenessTests/testFuturePresentationClockReversalAndFullWidthAgePreserveOriginalSemantics
    WebRTCTransportTests.BelugaRustScreenLivenessTests/testFullWidthCountersAndValueCopiesPreserveExactDeltas
    WebRTCTransportTests.BelugaRustScreenLivenessTests/testTypedProjectionCallsActualCFirstAndPreservesEveryInputAndBothStateSlots
    WebRTCTransportTests.BelugaRustScreenLivenessTests/testTypedProjectionPreservesAbsentMetadataPresenceAllCoversAndSignedZeroFPS
    WebRTCTransportTests.BelugaRustScreenLivenessTests/testCopiedResultCorruptionThrowsAndCannotAdvanceEitherHistorySlot
    WebRTCTransportTests.BelugaRustScreenLivenessTests/testTypedProjectionOptionalFieldsAndTrackInboundRenderPresenceRemainIndependent
  ].freeze
  # Frozen current ICE source/test enrollment. Native mutation rows are root-only execution obligations.
  ICE_RECOVERY_SHARED_SUITE = "WebRTCTransportTests.BelugaRustICERecoveryTests".freeze
  ICE_RECOVERY_ORIGINAL_SUITE = "WebRTCTransportTests.ICERecoveryCoordinatorTests".freeze
  ICE_RECOVERY_ORIGINAL_FILE = "shared/Tests/WebRTCTransportTests/ICERecoveryCoordinatorTests.swift".freeze
  ICE_RECOVERY_ORIGINAL_PINNED = [
    "WebRTCTransportTests.ICERecoveryCoordinatorTests/connectedDuringGraceCancelsRecovery()",
    "WebRTCTransportTests.ICERecoveryCoordinatorTests/immediateRequestAcceleratesGraceAndCoalescesDuplicates()",
    "WebRTCTransportTests.ICERecoveryCoordinatorTests/timeoutsRetryThenExhaustExactlyOnce()",
    "WebRTCTransportTests.ICERecoveryCoordinatorTests/connectedDuringSuspendedRestartInvalidatesItsCompletion()",
    "WebRTCTransportTests.ICERecoveryCoordinatorTests/thrownRestartConsumesAttemptAndUsesRetryDelay()",
    "WebRTCTransportTests.ICERecoveryCoordinatorTests/cancelIsTerminalAndSuppressesLaterSignals()",
  ].freeze
  ICE_RECOVERY_SIMULATOR_CLASSES = ["WorldwideICERecoveryPolicyReceiverTests", "WorldwideICERecoveryPolicyChainTests"].freeze
  ICE_RECOVERY_NATIVE_FILES = {
    "WebRTCTransportTests.BelugaRustICERecoveryTests" => "shared/Tests/WebRTCTransportTests/BelugaRustICERecoveryTests.swift",
    "CaptureServerTests.WorldwideICERecoveryPolicyReceiverTests" => "macOS/Tests/CaptureServerTests/WorldwideICERecoveryPolicyReceiverTests.swift",
    "WorldwideICERecoveryPolicyReceiverTests" => "iOS/opensteamer/Tests/WorldwideICERecoveryPolicyReceiverTests.swift",
    "CaptureServerTests.WorldwideICERecoveryPolicyChainTests" => "macOS/Tests/CaptureServerTests/WorldwideICERecoveryPolicyChainTests.swift",
    "WorldwideICERecoveryPolicyChainTests" => "iOS/opensteamer/Tests/WorldwideICERecoveryPolicyChainTests.swift",
  }.freeze
  ICE_RECOVERY_NATIVE_PINNED = {
    "WebRTCTransportTests.BelugaRustICERecoveryTests" => ["WebRTCTransportTests.BelugaRustICERecoveryTests/testRawCFullWidthStateAndEveryEnvelopeField", "WebRTCTransportTests.BelugaRustICERecoveryTests/testActualCFirstRejectsEveryMalformedCopiedResultTransactionally", "WebRTCTransportTests.BelugaRustICERecoveryTests/testRawEnvelopeCannotBorrowForgedSuccessfulFinishOrInitializer", "WebRTCTransportTests.BelugaRustICERecoveryTests/testExternalCopiedResultsCannotReviveReplaceOrSuppressCancellation", "WebRTCTransportTests.BelugaRustICERecoveryTests/testMalformedInitializerReportsFailureWithoutInventedState", "WebRTCTransportTests.BelugaRustICERecoveryTests/testCallerFaultCancelsNativeOwnershipAndCannotGrantAnyRecoveryEffect", "WebRTCTransportTests.BelugaRustICERecoveryTests/testFaultAfterSuspendedRestartCompletesBeforeNegativeAssertions", "WebRTCTransportTests.BelugaRustICERecoveryTests/testWrongWaitSelectorIsRejectedBeforeWrongNativeDuration", "WebRTCTransportTests.BelugaRustICERecoveryTests/testExhaustEffectWithoutCommittedDeliveredStateIsRejected", "WebRTCTransportTests.BelugaRustICERecoveryTests/testStaleFinishCannotReviveCancelledCoordinatorThroughCorruptCandidate", "WebRTCTransportTests.BelugaRustICERecoveryTests/testGraceAccelerationAndCoalescingMatchFrozenOriginal", "WebRTCTransportTests.BelugaRustICERecoveryTests/testZeroAndTinyExactDurationsMatchFrozenOriginal", "WebRTCTransportTests.BelugaRustICERecoveryTests/testEveryNonCancellationSleepFailureStopsAndAllowsFreshWorkflow", "WebRTCTransportTests.BelugaRustICERecoveryTests/testThrownCancellationErrorWithoutTaskCancellationConsumesAttempts", "WebRTCTransportTests.BelugaRustICERecoveryTests/testLateSuccessfulAndThrowingRestartCannotActAfterConnectionOrCancel", "WebRTCTransportTests.BelugaRustICERecoveryTests/testLateNonCooperativeSleepCannotAdvanceAfterReset", "WebRTCTransportTests.BelugaRustICERecoveryTests/testSuspendedExhaustionCompletionCannotClearNewWorkflow", "WebRTCTransportTests.BelugaRustICERecoveryTests/testRepeatedDirectCancelVersusIgnoredTerminalIceSignals"],
    "CaptureServerTests.WorldwideICERecoveryPolicyReceiverTests" => ["CaptureServerTests.WorldwideICERecoveryPolicyReceiverTests/testCurrentPolicyFaultStopsActualInertServiceAndJoinsCleanup", "CaptureServerTests.WorldwideICERecoveryPolicyReceiverTests/testCapturedOldPolicyFaultCannotStopReplacementInertGeneration"],
    "WorldwideICERecoveryPolicyReceiverTests" => ["WorldwideICERecoveryPolicyReceiverTests/testCurrentPolicyFaultClearsActualViewerAndJoinsNativeRetirement", "WorldwideICERecoveryPolicyReceiverTests/testCapturedOldPolicyFaultCannotCloseReplacementViewer"],
    "CaptureServerTests.WorldwideICERecoveryPolicyChainTests" => ["CaptureServerTests.WorldwideICERecoveryPolicyChainTests/testActualCorruptCheckingCResultStopsMatchingHostThroughInstalledCallbackOnce", "CaptureServerTests.WorldwideICERecoveryPolicyChainTests/testDelayedActualCPolicyFaultCannotStopReplacementHostCoordinator"],
    "WorldwideICERecoveryPolicyChainTests" => ["WorldwideICERecoveryPolicyChainTests/testActualCorruptCheckingCResultRetiresMatchingViewerThroughInstalledCallbackOnce", "WorldwideICERecoveryPolicyChainTests/testDelayedActualCPolicyFaultCannotRetireReplacementViewerCoordinator"],
  }.freeze
  ICE_RECOVERY_SOURCE_SHA256 = {
    "Package.swift" => "944f1b409c8018dc5b637958ac96d8b016cc152e8f000ea687855e0d3a93e715",
    "iOS/opensteamer/Sources/ViewModels/WorldwideSessionViewModel.swift" => "ae016e0bf643c5ecc5cfe48905ad8cb999e9a945b4b227acb39911b3771b7e74",
    "iOS/opensteamer/Tests/WorldwideICERecoveryPolicyChainTests.swift" => "b0b129bd5e4f7b4fed321e9af88c91003e9b2aff206e5909a0195053b08c39d4",
    "iOS/opensteamer/Tests/WorldwideICERecoveryPolicyReceiverTests.swift" => "64da8993a24fd265ccfd0c7a3e91aec7f4f9b10ebf484ca263000644df60cf63",
    "macOS/Sources/CaptureServer/WorldwideScreenService.swift" => "db8a5a28db70cdc419ed3f88e0d1c0da9472d96655b3cc6cce52ce00b3ffb73a",
    "macOS/Tests/CaptureServerTests/WorldwideICERecoveryPolicyChainTests.swift" => "192497db49974f1e04f095b92192187f53ba3cec90afc7e8e8eeba5651de677e",
    "macOS/Tests/CaptureServerTests/WorldwideICERecoveryPolicyReceiverTests.swift" => "5b052bdeed8dc96533af9c584c4fa41eda2d404a1ee3fee16cad8fee8346e50a",
    "shared/Rust/BelugaCore/include/beluga_core.h" => "2ea355f72241c8c62d0eb53b5d342784172637a305ffa3570b290814782d2dcd",
    "shared/Rust/BelugaCore/src/ice_recovery.rs" => "c2dd576e3e4687d72fe132ea0380e2fcec8dfe3a84be1ecff6009200df64e05a",
    "shared/Rust/BelugaCore/src/lib.rs" => "5a4db763fdef546ccdf9de324256f8b49c4ad9932e664432a93830ec46d55e2d",
    "shared/Rust/BelugaCore/tests/ice_recovery.rs" => "e46d94c8d002860575fad0ec5ee26686e1f11b34f5c109a0e9d61e0685a4c2be",
    "shared/Sources/WebRTCTransport/BelugaRustICERecovery.swift" => "a50519997ac91a80317152f31bd5e5a998f3b7a8be120da819adfeabb00bd5f1",
    "shared/Sources/WebRTCTransport/ICERecoveryCoordinator.swift" => "b8f681b087d598b26ed31423ab0d9e35cba570fdeb7c44c5468bcce0dabc6590",
    "shared/Tests/WebRTCTransportTests/BelugaRustICERecoveryTests.swift" => "8ddcc1d95a9466e7076a2dd1d338f17083480ac5850672f0e688fec1bdde2853",
    "shared/Tests/WebRTCTransportTests/ICERecoveryOriginalReference.swift" => "61536efdf4957dca646837f3cf9e4b04330bcaaf6614eafb228970ffe1395570",
    "shared/Tests/WebRTCTransportTests/ICERecoveryCoordinatorTests.swift" => "ff5bc748c43e5cc0f8120d28bd4f1a25a852d2ba499dd4698515cbb7451dff01",
  }.freeze
  ICE_RECOVERY_NATIVE_CONTROLS = [
    {"name"=>"ice-native-wait-selector-not-bound", "path"=>"shared/Sources/WebRTCTransport/BelugaRustICERecovery.swift", "old"=>"&& event.wait_kind == waitKind(before.phase) && output.effect == event.wait_kind + 6", "new"=>"&& event.wait_kind == waitKind(before.phase) && (7...9).contains(output.effect)", "selector"=>"WebRTCTransportTests.BelugaRustICERecoveryTests/testWrongWaitSelectorIsRejectedBeforeWrongNativeDuration"},
    {"name"=>"ice-native-exhaust-commit-not-bound", "path"=>"shared/Sources/WebRTCTransport/BelugaRustICERecovery.swift", "old"=>"return before.cursor == 7 && before.attempts == before.maximum_attempts\n                && before.exhaustion_delivered == 0 && after.phase == 5 && after.cursor == 8\n                && after.exhaustion_delivered == 1 && output.effect == 12", "new"=>"return before.cursor == 7 && output.effect == 12", "selector"=>"WebRTCTransportTests.BelugaRustICERecoveryTests/testExhaustEffectWithoutCommittedDeliveredStateIsRejected"},
    {"name"=>"ice-native-external-admission-not-bound", "path"=>"shared/Sources/WebRTCTransport/BelugaRustICERecovery.swift", "old"=>"guard output.flags == (mustAdvance ? 1 : 0) else { return false }", "new"=>"_ = mustAdvance", "selector"=>"WebRTCTransportTests.BelugaRustICERecoveryTests/testExternalCopiedResultsCannotReviveReplaceOrSuppressCancellation"},
    {"name"=>"ice-native-event-envelope-not-bound", "path"=>"shared/Sources/WebRTCTransport/BelugaRustICERecovery.swift", "old"=>"isClosed(after), eventIsClosed(event), output.abi_version", "new"=>"isClosed(after), output.abi_version", "selector"=>"WebRTCTransportTests.BelugaRustICERecoveryTests/testRawEnvelopeCannotBorrowForgedSuccessfulFinishOrInitializer"},
  ].freeze

  SCREEN_LIVENESS_RUST_PINNED = [
    "screen_liveness::tests::cover_before_track_before_initial_and_reset_evidence",
    "screen_liveness::tests::missing_track_precedes_initial_and_render_evidence",
    "screen_liveness::tests::covered_samples_still_advance_floor_and_change_clock",
    "screen_liveness::tests::missing_track_samples_still_advance_floor_and_change_clock",
    "screen_liveness::tests::presented_progress_precedes_stale_age_and_inbound_decode_stalls",
    "screen_liveness::tests::advancing_unchanged_frame_ignores_recent_content_clock_then_retained_frame_uses_it",
    "screen_liveness::tests::presentation_floor_milliseconds_and_content_exact_nanoseconds_remain_distinct",
    "screen_liveness::tests::future_presentation_is_zero_age_but_future_content_change_is_not_fresh",
    "screen_liveness::tests::each_single_counter_regression_clears_all_six_deltas_and_recent_clock",
    "screen_liveness::tests::generation_inequality_wins_over_regression_including_max_to_zero",
    "screen_liveness::tests::optional_counter_holes_only_break_adjacent_comparison",
    "screen_liveness::tests::renderer_hole_discards_render_deltas_without_erasing_recent_change",
    "screen_liveness::tests::zero_inbound_precedes_decoded_progress_and_optional_positive_order_is_original",
    "screen_liveness::tests::full_width_counters_are_neither_truncated_rounded_nor_wrapped",
    "screen_liveness::tests::dimensions_choose_each_axis_independently_with_inclusive_original_bounds",
    "screen_liveness::tests::fps_option_preserves_raw_bits_and_filters_only_original_finite_range",
    "screen_liveness::tests::metadata_only_inbound_record_presence_is_not_fabricated_or_erased",
    "screen_liveness::tests::presentation_age_saturates_after_safe_full_width_subtraction",
    "screen_liveness::tests::zeroed_reset_state_clears_both_history_slots",
    "screen_liveness::tests::malformed_raw_shape_and_abi_are_rejected_without_state_mutation",
    "screen_liveness::tests::copied_states_remain_independent_floors",
    "screen_liveness::tests::fresh_presentation_still_requires_positive_content_samples",
    "screen_liveness::tests::exact_all_copied_layout_sizes_alignments_and_field_offsets",
    "screen_liveness::tests::bounded_seeded_native_value_traces_match_frozen_original_at_every_event",
    "screen_liveness::tests::unknown_zero_and_full_width_abi_refuse_complete_copied_state",
    "screen_liveness::tests::absent_inbound_record_rejects_each_nonzero_optional_payload_unchanged",
    "screen_liveness::tests::malformed_recent_change_option_refuses_complete_before_state_unchanged",
    "screen_liveness::tests::absent_previous_sample_and_change_payloads_refuse_complete_before_state_unchanged",
  ].freeze

  SCREEN_LIVENESS_RUNTIME_MARKERS = [
    "BelugaCore C screen liveness ABI PASS: exact copied layouts, full-width values and unchanged refusal",
    "BelugaCore Swift screen liveness import/link PASS: exact copied layouts, full-width values and unchanged refusal",
  ].freeze

  SCREEN_LIVENESS_MUTANT_TESTS = {
    "liveness-intentional-cover-state-replaced" => "screen_liveness::tests::cover_before_track_before_initial_and_reset_evidence",
    "liveness-other-covers-ignored" => "screen_liveness::tests::cover_before_track_before_initial_and_reset_evidence",
    "liveness-track-guard-ignored" => "screen_liveness::tests::missing_track_precedes_initial_and_render_evidence",
    "liveness-reset-awaiting-ignored" => "screen_liveness::tests::each_single_counter_regression_clears_all_six_deltas_and_recent_clock",
    "liveness-initial-floor-forgotten" => "screen_liveness::tests::cover_before_track_before_initial_and_reset_evidence",
    "liveness-generation-change-ignored" => "screen_liveness::tests::generation_inequality_wins_over_regression_including_max_to_zero",
    "liveness-regression-counter-0-ignored" => "screen_liveness::tests::each_single_counter_regression_clears_all_six_deltas_and_recent_clock",
    "liveness-regression-counter-1-ignored" => "screen_liveness::tests::each_single_counter_regression_clears_all_six_deltas_and_recent_clock",
    "liveness-regression-counter-2-ignored" => "screen_liveness::tests::each_single_counter_regression_clears_all_six_deltas_and_recent_clock",
    "liveness-regression-counter-3-ignored" => "screen_liveness::tests::each_single_counter_regression_clears_all_six_deltas_and_recent_clock",
    "liveness-regression-counter-4-ignored" => "screen_liveness::tests::each_single_counter_regression_clears_all_six_deltas_and_recent_clock",
    "liveness-regression-counter-5-ignored" => "screen_liveness::tests::each_single_counter_regression_clears_all_six_deltas_and_recent_clock",
    "liveness-reset-retains-recent-change" => "screen_liveness::tests::each_single_counter_regression_clears_all_six_deltas_and_recent_clock",
    "liveness-positive-change-clock-is-not-current" => "screen_liveness::tests::covered_samples_still_advance_floor_and_change_clock",
    "liveness-last-change-forgotten-without-new-change" => "screen_liveness::tests::advancing_unchanged_frame_ignores_recent_content_clock_then_retained_frame_uses_it",
    "liveness-covered-floor-not-committed" => "screen_liveness::tests::covered_samples_still_advance_floor_and_change_clock",
    "liveness-missing-track-floor-not-committed" => "screen_liveness::tests::missing_track_samples_still_advance_floor_and_change_clock",
    "liveness-counter-u32-truncation" => "screen_liveness::tests::full_width_counters_are_neither_truncated_rounded_nor_wrapped",
    "liveness-counter-f64-rounding" => "screen_liveness::tests::full_width_counters_are_neither_truncated_rounded_nor_wrapped",
    "liveness-absent-counter-is-zero" => "screen_liveness::tests::optional_counter_holes_only_break_adjacent_comparison",
    "liveness-age-ceil-replaces-floor" => "screen_liveness::tests::presentation_floor_milliseconds_and_content_exact_nanoseconds_remain_distinct",
    "liveness-presentation-freshness-exclusive" => "screen_liveness::tests::presentation_floor_milliseconds_and_content_exact_nanoseconds_remain_distinct",
    "liveness-content-freshness-exclusive" => "screen_liveness::tests::presentation_floor_milliseconds_and_content_exact_nanoseconds_remain_distinct",
    "liveness-future-content-change-is-fresh" => "screen_liveness::tests::future_presentation_is_zero_age_but_future_content_change_is_not_fresh",
    "liveness-future-presentation-age-not-zero" => "screen_liveness::tests::future_presentation_is_zero_age_but_future_content_change_is_not_fresh",
    "liveness-age-saturation-removed" => "screen_liveness::tests::presentation_age_saturates_after_safe_full_width_subtraction",
    "liveness-presented-progress-ignored" => "screen_liveness::tests::presented_progress_precedes_stale_age_and_inbound_decode_stalls",
    "liveness-advancing-unchanged-frame-uses-recent-clock" => "screen_liveness::tests::advancing_unchanged_frame_ignores_recent_content_clock_then_retained_frame_uses_it",
    "liveness-fresh-presentation-zero-content-is-enough" => "screen_liveness::tests::fresh_presentation_still_requires_positive_content_samples",
    "liveness-zero-inbound-precedence-removed" => "screen_liveness::tests::zero_inbound_precedes_decoded_progress_and_optional_positive_order_is_original",
    "liveness-missing-decoded-evidence-is-presentation-stall" => "screen_liveness::tests::zero_inbound_precedes_decoded_progress_and_optional_positive_order_is_original",
    "liveness-dimension-one-rejected" => "screen_liveness::tests::dimensions_choose_each_axis_independently_with_inclusive_original_bounds",
    "liveness-dimension-32768-rejected" => "screen_liveness::tests::dimensions_choose_each_axis_independently_with_inclusive_original_bounds",
    "liveness-dimension-u32-alias-admitted" => "screen_liveness::tests::dimensions_choose_each_axis_independently_with_inclusive_original_bounds",
    "liveness-render-width-fallback-erased" => "screen_liveness::tests::dimensions_choose_each_axis_independently_with_inclusive_original_bounds",
    "liveness-fps-zero-rejected" => "screen_liveness::tests::fps_option_preserves_raw_bits_and_filters_only_original_finite_range",
    "liveness-fps-1000-rejected" => "screen_liveness::tests::fps_option_preserves_raw_bits_and_filters_only_original_finite_range",
    "liveness-inbound-record-presence-erased" => "screen_liveness::tests::metadata_only_inbound_record_presence_is_not_fabricated_or_erased",
    "liveness-generation-u32-truncation" => "screen_liveness::tests::full_width_counters_are_neither_truncated_rounded_nor_wrapped",
    "liveness-raw-fps-payload-normalized" => "screen_liveness::tests::fps_option_preserves_raw_bits_and_filters_only_original_finite_range",
    "liveness-raw-abi-zero-is-admitted" => "screen_liveness::tests::unknown_zero_and_full_width_abi_refuse_complete_copied_state",
    "liveness-raw-abi-max-is-admitted" => "screen_liveness::tests::unknown_zero_and_full_width_abi_refuse_complete_copied_state",
    "liveness-absent-inbound-payload-is-admitted" => "screen_liveness::tests::absent_inbound_record_rejects_each_nonzero_optional_payload_unchanged",
    "liveness-malformed-change-option-is-admitted" => "screen_liveness::tests::malformed_recent_change_option_refuses_complete_before_state_unchanged",
    "liveness-absent-before-payload-is-admitted" => "screen_liveness::tests::absent_previous_sample_and_change_payloads_refuse_complete_before_state_unchanged",
  }.freeze

  SCREEN_LIVENESS_SIMULATOR_CLASSES = [
    "WorldwideScreenLivenessBridgeCustodyTests",
  ].freeze

  SCREEN_LIVENESS_NATIVE_FILES = {
    "WebRTCTransportTests.WorldwideScreenLivenessClassifierTests" => "shared/Tests/WebRTCTransportTests/WorldwideScreenLivenessClassifierTests.swift",
    "WebRTCTransportTests.BelugaRustScreenLivenessTests" => "shared/Tests/WebRTCTransportTests/BelugaRustScreenLivenessTests.swift",
    "WorldwideScreenLivenessBridgeCustodyTests" => "iOS/opensteamer/Tests/WorldwideScreenLivenessBridgeCustodyTests.swift",
  }.freeze

  SCREEN_LIVENESS_NATIVE_PINNED = {
    "WebRTCTransportTests.WorldwideScreenLivenessClassifierTests" => ["WebRTCTransportTests.WorldwideScreenLivenessClassifierTests/testCoverTrackAndAwaitingBranchesHaveClosedEvidenceStates", "WebRTCTransportTests.WorldwideScreenLivenessClassifierTests/testInboundDecodeAndPresentationStallBranchesUseOrderedCounterEvidence", "WebRTCTransportTests.WorldwideScreenLivenessClassifierTests/testPresentedFramesDistinguishUnchangedContentFromChangingContent", "WebRTCTransportTests.WorldwideScreenLivenessClassifierTests/testFreshPresentationSurvivesAnInterleavedStatisticsOnlyObservation", "WebRTCTransportTests.WorldwideScreenLivenessClassifierTests/testGenerationChangeResetsEveryDeltaBeforeNewEvidenceIsCompared", "WebRTCTransportTests.WorldwideScreenLivenessClassifierTests/testCounterRegressionResetsTheWholeComparisonFloorWithoutUnsignedWrap", "WebRTCTransportTests.WorldwideScreenLivenessClassifierTests/testSnapshotBoundsAgeDimensionsAndFrameRateWithoutContentIdentity", "WebRTCTransportTests.WorldwideScreenLivenessClassifierTests/testAllClassifierStatesAreCoveredByDeterministicBranchFixtures"],
    "WebRTCTransportTests.BelugaRustScreenLivenessTests" => ["WebRTCTransportTests.BelugaRustScreenLivenessTests/testFractionalPresentationAndExactContentFreshnessHaveLiteralDifferentEdges", "WebRTCTransportTests.BelugaRustScreenLivenessTests/testAllCoversPrecedeAbsentTrackAndEveryResetReason", "WebRTCTransportTests.BelugaRustScreenLivenessTests/testCoveredAndMissingTrackObservationsStillAdvanceBothHistorySlots", "WebRTCTransportTests.BelugaRustScreenLivenessTests/testEachSingleRegressionClearsAllDeltasAndGenerationWinsPrecedence", "WebRTCTransportTests.BelugaRustScreenLivenessTests/testOptionalCounterHolesAndMetadataOnlyInboundAreNotZero", "WebRTCTransportTests.BelugaRustScreenLivenessTests/testDimensionFallbackIsPerAxisAndFPSRawNaNPayloadDoesNotBecomeAConstraint", "WebRTCTransportTests.BelugaRustScreenLivenessTests/testFuturePresentationClockReversalAndFullWidthAgePreserveOriginalSemantics", "WebRTCTransportTests.BelugaRustScreenLivenessTests/testFullWidthCountersAndValueCopiesPreserveExactDeltas", "WebRTCTransportTests.BelugaRustScreenLivenessTests/testTypedProjectionCallsActualCFirstAndPreservesEveryInputAndBothStateSlots", "WebRTCTransportTests.BelugaRustScreenLivenessTests/testTypedProjectionPreservesAbsentMetadataPresenceAllCoversAndSignedZeroFPS", "WebRTCTransportTests.BelugaRustScreenLivenessTests/testCopiedResultCorruptionThrowsAndCannotAdvanceEitherHistorySlot", "WebRTCTransportTests.BelugaRustScreenLivenessTests/testTypedProjectionOptionalFieldsAndTrackInboundRenderPresenceRemainIndependent"],
    "WorldwideScreenLivenessBridgeCustodyTests" => ["WorldwideScreenLivenessBridgeCustodyTests/testBridgeFaultRetainsExplicitlyStaleEvidenceRefusesHeartbeatAndSuccessfulObservationRecovers", "WorldwideScreenLivenessBridgeCustodyTests/testBridgeFaultDuringNegotiationCannotReportRetainedSnapshotOrBurnSequence", "WorldwideScreenLivenessBridgeCustodyTests/testLaterFaultCannotTurnAcceptedSendCompletionIntoCurrentEvidenceStatus", "WorldwideScreenLivenessBridgeCustodyTests/testBridgeFaultDuringFalseNegotiationRetainsUnavailableStatusWithoutSendOrSequence", "WorldwideScreenLivenessBridgeCustodyTests/testLaterFaultCannotTurnThrowingSendCompletionIntoHeartbeatUnavailableStatus"],
  }.freeze

  SCREEN_LIVENESS_SOURCE_SHA256 = {
    "Package.swift" => "944f1b409c8018dc5b637958ac96d8b016cc152e8f000ea687855e0d3a93e715",
    "iOS/opensteamer/Sources/ViewModels/WorldwideSessionViewModel.swift" => "ae016e0bf643c5ecc5cfe48905ad8cb999e9a945b4b227acb39911b3771b7e74",
    "iOS/opensteamer/Sources/Views/DiagnosticsView.swift" => "9d8812bf37c9916546981f499afc2657c05f237ed62bc2135d4cf5732726ebf1",
    "iOS/opensteamer/Sources/Views/WorldwideScreenViewerView.swift" => "90195a6714d1c4775481bf29d22a9a0c3b2eb608e50b38ba38bf0b422307ce65",
    "iOS/opensteamer/Tests/WorldwideScreenLivenessBridgeCustodyTests.swift" => "5fab3c2d7aaeaac3b6f4ebb25171c05bb709f7833a384013731634a50a141406",
    "shared/Rust/BelugaCore/include/beluga_core.h" => "2ea355f72241c8c62d0eb53b5d342784172637a305ffa3570b290814782d2dcd",
    "shared/Rust/BelugaCore/scripts/artifact_support.rb" => "a39308cec492ff541f33bddbb3e6332400f33aabf37498e350db97684c524cb7",
    "shared/Rust/BelugaCore/scripts/mutation-tests.rb" => "9cafeff860bd35c6090323679ee0b9ca0ec9a2cba2c65c82d2bb2eda986ac6cd",
    "shared/Rust/BelugaCore/src/lib.rs" => "5a4db763fdef546ccdf9de324256f8b49c4ad9932e664432a93830ec46d55e2d",
    "shared/Rust/BelugaCore/src/screen_liveness.rs" => "802b8c2686a174c54a0d3f213f198b9789bfcbc074809e489a3a63db3830bcb3",
    "shared/Rust/BelugaCore/src/screen_liveness_tests.rs" => "917f069ceb252a216067276dcee5b7e06edd8592d7b91a197c2f99920320e43d",
    "shared/Rust/BelugaCore/tests/c_abi_smoke.c" => "6c2e4b992f8ff15edcacdb4343e8e42a8867a10201710f904dcd1f9cf38dea37",
    "shared/Rust/BelugaCore/tests/swift_import_smoke.swift" => "733731db3cfd6bd7a3114b9edfc474e5df32d5a18acc053a6cf61b808fc887b1",
    "shared/Sources/WebRTCTransport/BelugaRustScreenLiveness.swift" => "2155000fbe70184f4fd0a62ad3a4461b0b7cc748e853e29d07d16875903bdb50",
    "shared/Sources/WebRTCTransport/WorldwideScreenLiveness.swift" => "3e6e2e7359ae49354e8b6781e31ec6721a94c69c32a15868438942e57960a5a4",
    "shared/Tests/WebRTCTransportTests/BelugaRustScreenLivenessTests.swift" => "019b127fc5cf2823674205f6e392d33a7934cb629a50df0e75e887e0268a3f60",
    "shared/Tests/WebRTCTransportTests/ScreenLivenessOriginalReference.swift" => "472039d57ef90120d8c9d5022eb5b971281c14225614f948d0c08274276f7ec5",
    "shared/Tests/WebRTCTransportTests/WorldwideScreenLivenessClassifierTests.swift" => "bff02a53fded0e6e514527f15bd0ab3435c47f79dd1061d04b1023f00ab91b55",
  }.freeze

  SCREEN_LIVENESS_NATIVE_CONTROLS = [
    {"name"=>"liveness-malformed-output-committed", "path"=>"shared/Sources/WebRTCTransport/WorldwideScreenLiveness.swift", "old"=>"throw WorldwideScreenLivenessBridgeError.invalidBridge", "new"=>"state = output.state\n            throw WorldwideScreenLivenessBridgeError.invalidBridge", "selector"=>"WebRTCTransportTests.BelugaRustScreenLivenessTests/testCopiedResultCorruptionThrowsAndCannotAdvanceEitherHistorySlot"},
    {"name"=>"liveness-initial-bridge-fault-guard-removed", "path"=>"iOS/opensteamer/Sources/ViewModels/WorldwideSessionViewModel.swift", "old"=>"        guard screenLivenessBridgeError == nil else {\n            screenClientDiagnosticsDeliveryText = \"Local evidence unavailable\"\n            return\n        }\n        guard nextScreenClientDiagnosticsSequence", "new"=>"        guard nextScreenClientDiagnosticsSequence", "selector"=>"WorldwideScreenLivenessBridgeCustodyTests/testBridgeFaultRetainsExplicitlyStaleEvidenceRefusesHeartbeatAndSuccessfulObservationRecovers"},
    {"name"=>"liveness-post-negotiation-bridge-fault-guard-removed", "path"=>"iOS/opensteamer/Sources/ViewModels/WorldwideSessionViewModel.swift", "old"=>"        guard screenLivenessBridgeError == nil else {\n            screenClientDiagnosticsDeliveryText = \"Local evidence unavailable\"\n            return\n        }\n        guard isNegotiated else", "new"=>"        guard isNegotiated else", "selector"=>"WorldwideScreenLivenessBridgeCustodyTests/testBridgeFaultDuringNegotiationCannotReportRetainedSnapshotOrBurnSequence"},
    {"name"=>"liveness-faulted-completion-reports-current", "path"=>"iOS/opensteamer/Sources/ViewModels/WorldwideSessionViewModel.swift", "old"=>"                  activeScreenRequestID == screenRequestID,\n                  screenLivenessBridgeError == nil else { return }\n            screenClientDiagnosticsDeliveryText = \"Reporting to Mac\"", "new"=>"                  activeScreenRequestID == screenRequestID else { return }\n            screenClientDiagnosticsDeliveryText = \"Reporting to Mac\"", "selector"=>"WorldwideScreenLivenessBridgeCustodyTests/testLaterFaultCannotTurnAcceptedSendCompletionIntoCurrentEvidenceStatus"},
    {"name"=>"liveness-false-negotiation-overwrites-bridge-fault", "path"=>"iOS/opensteamer/Sources/ViewModels/WorldwideSessionViewModel.swift", "old"=>"        guard screenLivenessBridgeError == nil else {\n            screenClientDiagnosticsDeliveryText = \"Local evidence unavailable\"\n            return\n        }\n        guard isNegotiated else {\n            screenClientDiagnosticsDeliveryText = \"Local only\"\n            return\n        }\n\n        let snapshot = screenLivenessDiagnosticSnapshot", "new"=>"        guard isNegotiated else {\n            screenClientDiagnosticsDeliveryText = \"Local only\"\n            return\n        }\n\n        guard screenLivenessBridgeError == nil else {\n            screenClientDiagnosticsDeliveryText = \"Local evidence unavailable\"\n            return\n        }\n        let snapshot = screenLivenessDiagnosticSnapshot", "selector"=>"WorldwideScreenLivenessBridgeCustodyTests/testBridgeFaultDuringFalseNegotiationRetainsUnavailableStatusWithoutSendOrSequence"},
    {"name"=>"liveness-faulted-throwing-completion-reports-heartbeat-unavailable", "path"=>"iOS/opensteamer/Sources/ViewModels/WorldwideSessionViewModel.swift", "old"=>"                  activeScreenRequestID == screenRequestID,\n                  screenLivenessBridgeError == nil else { return }\n            // This best-effort lane never changes the user-visible media or control state.\n            screenClientDiagnosticsDeliveryText = \"Heartbeat unavailable\"", "new"=>"                  activeScreenRequestID == screenRequestID else { return }\n            // This best-effort lane never changes the user-visible media or control state.\n            screenClientDiagnosticsDeliveryText = \"Heartbeat unavailable\"", "selector"=>"WorldwideScreenLivenessBridgeCustodyTests/testLaterFaultCannotTurnThrowingSendCompletionIntoHeartbeatUnavailableStatus"},
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
    ice_recovery_simulator_source_inventory(root)
    screen_liveness_simulator_source_inventory(root)
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


  def self.validate_microphone_input_lease_sources(root)
    MICROPHONE_INPUT_LEASE_SOURCE_SHA256.each do |relative, expected|
      path = File.join(root, relative)
      require!(File.exist?(path), 'input lease reviewed source is missing: ' + relative)
      stat = regular!(path)
      require!(File.realpath(path) == path && stat.size <= 2 * 1024 * 1024 && sha(path) == expected,
               'input lease reviewed source changed: ' + relative)
      utf8_text(File.binread(path), 'input lease reviewed source')
    end
    source = utf8_text(File.binread(File.join(root, BELUGA_CORE_CRATE, 'tests/microphone_input_lease.rs')),
                       'input lease Rust test source')
    declarations = source.scan(/^#\[test\]\r?\nfn (input_lease_\w+)[ \t]*\(/).flatten
    require!(source.scan(/^#\[test\]/).length == 8 && declarations.uniq.length == 8 &&
             declarations == BELUGA_CORE_ADDED_RUST_BY_SUITE.fetch('microphone_input_lease'),
             'input lease exact Rust declarations differ')
    nil
  end

  def self.microphone_input_lease_native_source_inventory(root)
    validate_microphone_input_lease_sources(root)
    MICROPHONE_INPUT_LEASE_NATIVE_FILES.to_h do |suite, relative|
      source = utf8_text(File.binread(File.join(root, relative)), 'input lease native test source')
      name = suite.split('.').last
      classes = []
      source.to_enum(:scan, /^[ \t]*final class (\w+)[ \t]*:[ \t\r\n]*XCTestCase[ \t\r\n]*\{/).each do
        match = Regexp.last_match
        classes << [match[1], match.end(0)]
      end
      expected_classes = MICROPHONE_INPUT_LEASE_NATIVE_FILES.select { |_, path| path == relative }.keys.map { |id| id.split('.').last }
      require!(classes.map(&:first) == expected_classes, 'input lease native class boundaries differ: ' + relative)
      index = classes.index { |entry| entry.first == name }
      require!(!index.nil?, 'input lease native class is missing: ' + suite)
      ending = index + 1 < classes.length ? classes[index + 1][1] : source.length
      methods = source[classes[index][1]...ending].scan(/^[ \t]*func (test\w+)[ \t]*\(/).flatten
      ids = methods.map { |method| suite + '/' + method }
      required = MICROPHONE_INPUT_LEASE_NATIVE_ADDITIONS.select { |id| id.start_with?(suite + '/') }
      require!(ids.length == MICROPHONE_INPUT_LEASE_NATIVE_COUNTS.fetch(suite) &&
               ids.uniq.length == ids.length && (required - ids).empty? &&
               ids.select { |id| required.include?(id) } == required,
               'input lease exact native declarations differ: ' + suite)
      [suite, ids.sort]
    end
  end

  def self.microphone_input_lease_native_inventory(root, text)
    source = microphone_input_lease_native_source_inventory(root)
    lines = utf8_text(text, 'input lease native discovery').lines.map(&:strip)
    source.to_h do |suite, expected|
      ids = lines.select { |line| line.start_with?(suite + '/') }
      require!(ids.uniq.length == ids.length &&
               ids.all? { |id| id.match?(/\A#{Regexp.escape(suite)}\/test\w+\z/) } &&
               ids.sort == expected, 'input lease exact native discovery differs: ' + suite)
      [suite, ids.sort]
    end
  end

  def self.validate_microphone_output_format_sources(root)
    MICROPHONE_OUTPUT_FORMAT_SOURCE_SHA256.each do |relative, expected|
      path = File.join(root, relative)
      require!(File.exist?(path), 'output format reviewed source is missing: ' + relative)
      stat = regular!(path)
      require!(File.realpath(path) == path && stat.size <= 2 * 1024 * 1024 && sha(path) == expected,
               'output format reviewed source changed: ' + relative)
      utf8_text(File.binread(path), 'output format reviewed source')
    end
    source = utf8_text(File.binread(File.join(root, BELUGA_CORE_CRATE, 'tests/microphone_output_format.rs')),
                       'output format Rust test source')
    declarations = source.scan(/^#\[test\]\r?\nfn (output_format_\w+)[ \t]*\(/).flatten
    require!(source.scan(/^#\[test\]/).length == 12 && declarations.uniq.length == 12 &&
             declarations == BELUGA_CORE_ADDED_RUST_BY_SUITE.fetch('microphone_output_format'),
             'output format exact Rust declarations differ')
    nil
  end

  def self.microphone_output_format_native_source_inventory(root)
    validate_microphone_output_format_sources(root)
    MICROPHONE_OUTPUT_FORMAT_NATIVE_FILES.to_h do |suite, relative|
      source = utf8_text(File.binread(File.join(root, relative)), 'output format native test source')
      name = suite.split('.').last
      classes = source.scan(/^[ \t]*final class (\w+)[ \t]*:[ \t\r\n]*XCTestCase[ \t\r\n]*\{/).flatten
      require!(classes == [name], 'output format native class boundaries differ: ' + relative)
      methods = source.scan(/^[ \t]*func (test\w+)[ \t]*\(/).flatten
      ids = methods.map { |method| suite + '/' + method }
      required = MICROPHONE_OUTPUT_FORMAT_NATIVE_ADDITIONS.select { |id| id.start_with?(suite + '/') }
      require!(ids.length == 11 && ids.uniq.length == 11 && ids == required,
               'output format exact native declarations differ: ' + suite)
      [suite, ids.sort]
    end
  end

  def self.microphone_output_format_native_inventory(root, text)
    source = microphone_output_format_native_source_inventory(root)
    lines = utf8_text(text, 'output format native discovery').lines.map(&:strip)
    source.to_h do |suite, expected|
      ids = lines.select { |line| line.start_with?(suite + '/') }
      require!(ids.uniq.length == ids.length &&
               ids.all? { |id| id.match?(/\A#{Regexp.escape(suite)}\/test\w+\z/) } &&
               ids.sort == expected, 'output format exact native discovery differs: ' + suite)
      [suite, ids.sort]
    end
  end

  def self.updater_microphone_native_required_map
    UPDATER_MICROPHONE_NATIVE_PINNED.to_h do |suite, ids|
      companion = UPDATER_MICROPHONE_NATIVE_COMPANIONS[suite]
      [suite, ids + (companion ? companion.fetch(:methods) : [])]
    end
  end

  def self.updater_microphone_native_source_inventory(root)
    (UNARMED_COMPLETION_SOURCE_SHA256.to_a + ABORT_CLASSIFIER_SOURCE_SHA256.to_a + UPDATER_MICROPHONE_NATIVE_SOURCE_SHA256.to_a).each do |relative, expected|
      path = File.join(root, relative)
      stat = regular!(path)
      require!(File.realpath(path) == path && stat.size <= 2 * 1024 * 1024 && sha(path) == expected,
               'updater/microphone reviewed native source changed: ' + relative)
    end
    UPDATER_MICROPHONE_NATIVE_FILES.to_h do |suite, relative|
      source = utf8_text(File.binread(File.join(root, relative)), 'updater/microphone native source')
      name = suite.split('.').last
      classes = source.scan(/\bclass[ \t]+(\w+)[ \t]*:[^{]*\bXCTestCase\b[^{]*\{/).flatten
      methods = source.scan(/^[ \t]*(?:@MainActor[ \t]+)?func (test\w+)[ \t]*\(/).flatten
      ids = methods.map { |method| suite + '/' + method }
      require!(classes == [name] &&
               source.scan(/^[ \t]*final class #{Regexp.escape(name)}[ \t]*:[ \t]*XCTestCase[ \t]*\{/).length == 1 &&
               ids.uniq.length == ids.length && ids == UPDATER_MICROPHONE_NATIVE_PINNED.fetch(suite),
               'updater/microphone exact native source inventory differs: ' + suite)
      if (companion = UPDATER_MICROPHONE_NATIVE_COMPANIONS[suite])
        relative = companion.fetch(:path)
        require!(UPDATER_MICROPHONE_NATIVE_SOURCE_SHA256.key?(relative),
                 'updater/microphone native companion is not source-pinned: ' + suite)
        source = utf8_text(File.binread(File.join(root, relative)), 'updater/microphone native companion')
        classes = source.scan(/\bclass[ \t]+(\w+)/).flatten
        extensions = source.scan(/\bextension[ \t]+(\w+)[ \t]*[^{]*\{/).flatten
        methods = source.scan(/^[ \t]*(?:@MainActor[ \t]+)?func (test\w+)[ \t]*\(/).flatten
        companion_ids = methods.map { |method| suite + '/' + method }
        require!(classes.empty? && extensions == [name] &&
                 source.scan(/^[ \t]*extension #{Regexp.escape(name)}[ \t]*\{/).length == 1 &&
                 companion_ids.uniq.length == companion_ids.length && companion_ids == companion.fetch(:methods),
                 'updater/microphone exact native companion inventory differs: ' + suite)
        ids += companion_ids
      end
      require!(ids.uniq.length == ids.length && ids == updater_microphone_native_required_map.fetch(suite),
               'updater/microphone exact compound native inventory differs: ' + suite)
      [suite, ids.sort]
    end
  end

  def self.updater_microphone_native_inventory(root, text)
    source = updater_microphone_native_source_inventory(root)
    lines = utf8_text(text, 'updater/microphone native discovery').lines.map(&:strip)
    source.to_h do |suite, expected|
      ids = lines.select { |line| line.start_with?(suite + '/') }
      require!(ids.uniq.length == ids.length &&
               ids.all? { |id| id.match?(/\A#{Regexp.escape(suite)}\/test\w+\z/) } &&
               ids.sort == expected, 'updater/microphone exact native discovery differs: ' + suite)
      [suite, ids.sort]
    end
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

  def self.validate_screen_liveness_sources(root)
    SCREEN_LIVENESS_SOURCE_SHA256.each do |relative, expected|
      path = File.join(root, relative)
      require!(File.exist?(path), 'screen liveness source companion is missing: ' + relative)
      stat = regular!(path)
      require!(File.realpath(path) == path && stat.size <= 2 * 1024 * 1024 && sha(path) == expected,
               'screen liveness reviewed source/reference body changed: ' + relative)
      utf8_text(File.binread(path), 'screen liveness source companion')
    end
    SCREEN_LIVENESS_NATIVE_CONTROLS.each do |control|
      body = utf8_text(File.binread(File.join(root, control.fetch('path'))), 'screen liveness native control source')
      require!(body.scan(control.fetch('old')).length == 1 && control.fetch('old') != control.fetch('new') &&
               SCREEN_LIVENESS_NATIVE_PINNED.values.flatten.include?(control.fetch('selector')),
               'screen liveness native control anchor or witness differs: ' + control.fetch('name'))
    end
    screen_liveness_rust_source_inventory(root)
    nil
  end

  def self.screen_liveness_rust_source_inventory(root)
    relative = BELUGA_CORE_CRATE + '/src/screen_liveness_tests.rs'
    source = utf8_text(File.binread(File.join(root, relative)), 'screen liveness Rust test source')
    methods = source.scan(/^#\[test\][ \t]*\nfn (\w+)[ \t]*\(/).flatten
    ids = methods.map { |method| 'screen_liveness::tests::' + method }
    require!(source.scan(/^#\[test\]/).length == 28 && ids.uniq.length == ids.length &&
             ids == SCREEN_LIVENESS_RUST_PINNED,
             'screen liveness exact scoped Rust declarations differ')
    routing = utf8_text(File.binread(File.join(root, BELUGA_CORE_CRATE, 'src/screen_liveness.rs')),
                        'screen liveness Rust production test routing')
    require!(routing.scan("#[cfg(test)]\n#[path = \"screen_liveness_tests.rs\"]\nmod tests;").length == 1,
             'screen liveness Rust unit-suite routing differs')
    ids
  end

  def self.screen_liveness_native_source_inventory(root)
    validate_screen_liveness_sources(root)
    SCREEN_LIVENESS_NATIVE_FILES.map do |suite, relative|
      source = utf8_text(File.binread(File.join(root, relative)), 'screen liveness native test source')
      name = suite.split('.').last
      methods = source.scan(/^[ \t]*func (test\w+)[ \t]*\(/).flatten
      ids = methods.map { |method| suite + '/' + method }
      require!(source.scan(/^[ \t]*final class #{Regexp.escape(name)}[ \t]*:[ \t]*XCTestCase[ \t]*\{/).length == 1 &&
               ids.uniq.length == ids.length && ids == SCREEN_LIVENESS_NATIVE_PINNED.fetch(suite),
               'screen liveness native source inventory is incomplete, malformed or duplicated: ' + suite)
      [suite, ids.sort]
    end.to_h
  end

  def self.screen_liveness_native_inventory(root, text)
    source = screen_liveness_native_source_inventory(root)
    lines = utf8_text(text, 'screen liveness native discovery').lines.map(&:strip)
    source.select { |suite, _| suite.include?('.') }.each do |suite, expected|
      methods = lines.select { |line| line.start_with?(suite + '/') }
      require!(methods.uniq.length == methods.length && methods.sort == expected &&
               methods.all? { |id| id.match?(/\A#{Regexp.escape(suite)}\/test\w+\z/) },
               'screen liveness native discovery differs from exact source inventory: ' + suite)
    end
    source
  end

  def self.screen_liveness_simulator_source_inventory(root)
    source = screen_liveness_native_source_inventory(root).reject { |suite, _| suite.include?('.') }
    require!(source.keys == SCREEN_LIVENESS_SIMULATOR_CLASSES,
             'screen liveness Simulator classes differ from reviewed enrollment')
    source.values.flatten.sort
  end

  def self.validate_ice_recovery_sources(root)
    ICE_RECOVERY_SOURCE_SHA256.each do |relative, expected|
      path = File.join(root, relative)
      require!(File.exist?(path), 'ICE recovery source companion is missing: ' + relative)
      stat = regular!(path)
      require!(File.realpath(path) == path && stat.size <= 2 * 1024 * 1024 && sha(path) == expected,
               'ICE recovery reviewed source/reference body changed: ' + relative)
      utf8_text(File.binread(path), 'ICE recovery source companion')
    end
    ICE_RECOVERY_NATIVE_CONTROLS.each do |control|
      body = utf8_text(File.binread(File.join(root, control.fetch('path'))), 'ICE native control source')
      require!(body.scan(control.fetch('old')).length == 1 && control.fetch('old') != control.fetch('new') &&
               ICE_RECOVERY_NATIVE_PINNED.fetch(ICE_RECOVERY_SHARED_SUITE).include?(control.fetch('selector')),
               'ICE recovery native control anchor or witness differs: ' + control.fetch('name'))
    end
    nil
  end

  def self.ice_recovery_native_source_inventory(root)
    validate_ice_recovery_sources(root)
    ICE_RECOVERY_NATIVE_FILES.map do |suite, relative|
      source = utf8_text(File.binread(File.join(root, relative)), 'ICE recovery native test source')
      name = suite.split('.').last
      methods = source.scan(/^[ \t]*func (test\w+)[ \t]*\(/).flatten
      ids = methods.map { |method| suite + '/' + method }
      require!(source.scan(/^[ \t]*final class #{Regexp.escape(name)}[ \t]*:[ \t]*XCTestCase[ \t]*\{/).length == 1 &&
               ids.uniq.length == ids.length && ids.sort == ICE_RECOVERY_NATIVE_PINNED.fetch(suite).sort,
               'ICE recovery native source inventory is incomplete, malformed or duplicated: ' + suite)
      [suite, ids.sort]
    end.to_h
  end

  def self.ice_recovery_original_source_inventory(root)
    validate_ice_recovery_sources(root)
    source = utf8_text(File.binread(File.join(root, ICE_RECOVERY_ORIGINAL_FILE)), 'ICE original Swift Testing source')
    methods = source.scan(/^[ \t]*@Test[ \t]+func (\w+)[ \t]*\(/).flatten
    ids = methods.map { |method| ICE_RECOVERY_ORIGINAL_SUITE + '/' + method + '()' }
    require!(source.scan(/^[ \t]*struct ICERecoveryCoordinatorTests[ \t]*\{/).length == 1 &&
             source.scan(/^[ \t]*@Test\b/).length == 6 && ids.uniq.length == ids.length &&
             ids.sort == ICE_RECOVERY_ORIGINAL_PINNED.sort,
             'ICE recovery original Swift Testing source inventory differs')
    ids.sort
  end

  def self.ice_recovery_native_inventory(root, text)
    source = ice_recovery_native_source_inventory(root)
    lines = utf8_text(text, 'ICE recovery native discovery').lines.map(&:strip)
    source.select { |suite, _| suite.include?('.') }.each do |suite, expected|
      methods = lines.select { |line| line.start_with?(suite + '/') }
      require!(methods.uniq.length == methods.length && methods.sort == expected &&
               methods.all? { |id| id.match?(/\A#{Regexp.escape(suite)}\/test\w+\z/) },
               'ICE recovery native discovery differs from exact source inventory: ' + suite)
    end
    expected = ice_recovery_original_source_inventory(root)
    methods = lines.select { |line| line.start_with?(ICE_RECOVERY_ORIGINAL_SUITE + '/') }
    require!(methods.uniq.length == methods.length && methods.sort == expected &&
             methods.all? { |id| id.match?(/\A#{Regexp.escape(ICE_RECOVERY_ORIGINAL_SUITE)}\/\w+\(\)\z/) },
             'ICE recovery original Swift Testing discovery differs')
    source
  end

  def self.ice_recovery_simulator_source_inventory(root)
    source = ice_recovery_native_source_inventory(root).reject { |suite, _| suite.include?('.') }
    require!(source.keys == ICE_RECOVERY_SIMULATOR_CLASSES,
             'ICE recovery Simulator classes differ from reviewed enrollment')
    source.values.flatten.sort
  end

  # This is the six original Swift Testing methods, not the separate XCTest count.
  def self.validate_ice_recovery_original_results(text)
    text = utf8_text(text, 'ICE original Swift Testing results')
    require!(text.bytesize <= 16 * 1024 * 1024, 'ICE original result exceeds byte bound')
    all_lines = text.lines.map(&:chomp)
    run_indices = all_lines.each_index.select { |index| all_lines[index] == '◇ Test run started.' }
    require!(run_indices.length == 1, 'ICE original Swift Testing run is absent or duplicated')
    lines = all_lines.drop(run_indices.first)
    require!(lines.length <= 4096, 'ICE original result exceeds line bound')
    suite_starts = []; suite_passes = []; footers = []; starts = {}; passes = {}
    lines.each_with_index do |line, index|
      if line == '◇ Test run started.'
        require!(index == 0, 'ICE original Swift Testing run is duplicated')
      elsif line == '◇ Suite ICERecoveryCoordinatorTests started.'
        suite_starts << index
      elsif line.match?(/\A✔ Suite ICERecoveryCoordinatorTests passed after \d+(?:\.\d+)? seconds\.\z/)
        suite_passes << index
      elsif (match = /\A✔ Test run with (\d+) tests in (\d+) suite passed after \d+(?:\.\d+)? seconds\.\z/.match(line))
        footers << [index, match[1].to_i, match[2].to_i]
      elsif (match = /\A◇ Test (\w+\(\)) started\.\z/.match(line))
        id = ICE_RECOVERY_ORIGINAL_SUITE + '/' + match[1]
        require!(ICE_RECOVERY_ORIGINAL_PINNED.include?(id) && !starts.key?(id),
                 'ICE original start is unexpected or duplicated')
        starts[id] = index
      elsif (match = /\A✔ Test (\w+\(\)) passed after \d+(?:\.\d+)? seconds\.\z/.match(line))
        id = ICE_RECOVERY_ORIGINAL_SUITE + '/' + match[1]
        require!(ICE_RECOVERY_ORIGINAL_PINNED.include?(id) && starts.key?(id) && starts[id] < index && !passes.key?(id),
                 'ICE original pass is unexpected, duplicated or lacks matching start')
        passes[id] = index
      else
        require!(!line.match?(/\A\s*(?:\S+\s+)?(?:Test|Suite)\b/),
                 'ICE original result is malformed, failed, skipped or belongs to another suite')
      end
    end
    require!(suite_starts.length == 1 && suite_passes.length == 1 && footers.length == 1 &&
             0 < suite_starts.first && suite_starts.first < suite_passes.first &&
             suite_passes.first < footers.first[0] && footers.first.drop(1) == [6, 1],
             'ICE original suite/run footer is missing, duplicated, out of order or disagrees')
    require!(starts.keys.sort == ICE_RECOVERY_ORIGINAL_PINNED.sort && passes.keys.sort == ICE_RECOVERY_ORIGINAL_PINNED.sort &&
             (starts.values + passes.values).all? { |index| index > suite_starts.first && index < suite_passes.first },
             'ICE original cases are missing or outside exact Swift Testing suite')
    ICE_RECOVERY_ORIGINAL_PINNED.sort
  end

  # Swift Testing appends a source-location component to runtime IDs. XCTest IDs
  # remain exact; the six original IDs permit only that component boundary.
  def self.shared_handoff_filter(handoff_methods)
    native = handoff_methods.map { |id| Regexp.escape(id) }.join('|')
    original = ICE_RECOVERY_ORIGINAL_PINNED.map { |id| Regexp.escape(id) }.join('|')
    '^(?:(?:' + native + ')$|(?:' + original + ')(?:/|$))'
  end
  def self.validate_output_dimensions_sources(root)
    OUTPUT_DIMENSIONS_SOURCE_SHA256.each do |relative, expected|
      path = File.join(root, relative)
      require!(File.exist?(path), 'output dimensions source companion is missing: ' + relative)
      stat = regular!(path)
      require!(File.realpath(path) == path && stat.size <= 2 * 1024 * 1024 && sha(path) == expected,
               'output dimensions reviewed source/reference body changed: ' + relative)
      utf8_text(File.binread(path), 'output dimensions source companion')
    end
    nil
  end

  def self.output_dimensions_native_source_inventory(root)
    validate_output_dimensions_sources(root)
    OUTPUT_DIMENSIONS_NATIVE_FILES.map do |suite, relative|
      source = utf8_text(File.binread(File.join(root, relative)), 'output dimensions native test source')
      name = suite.split('.').last
      methods = source.scan(/^[ \t]*func (test\w+)[ \t]*\(/).flatten
      ids = methods.map { |method| suite + '/' + method }
      require!(source.scan(/^[ \t]*final class #{Regexp.escape(name)}[ \t]*:[ \t]*XCTestCase[ \t]*\{/).length == 1 &&
               ids.uniq.length == ids.length && ids.sort == OUTPUT_DIMENSIONS_NATIVE_PINNED.fetch(suite).sort,
               'output dimensions native source inventory is incomplete, malformed or duplicated: ' + suite)
      [suite, ids.sort]
    end.to_h
  end

  def self.output_dimensions_native_inventory(root, text)
    source = output_dimensions_native_source_inventory(root)
    lines = utf8_text(text, 'output dimensions native discovery').lines.map(&:strip)
    source.map do |suite, expected|
      methods = lines.select { |line| line.start_with?(suite + '/') }
      require!(methods.uniq.length == methods.length &&
               methods.all? { |id| id.match?(/\A#{Regexp.escape(suite)}\/test\w+\z/) } &&
               methods.sort == expected,
               'output dimensions native discovery differs from exact source inventory: ' + suite)
      [suite, methods.sort]
    end.to_h
  end

  def self.validate_packet_send_queue_sources(root)
    PACKET_SEND_QUEUE_SOURCE_SHA256.each do |relative, expected|
      path = File.join(root, relative)
      require!(File.exist?(path), 'packet send queue source companion is missing: ' + relative)
      stat = regular!(path)
      require!(File.realpath(path) == path && stat.size <= 2 * 1024 * 1024 && sha(path) == expected,
               'packet send queue reviewed source/reference body changed: ' + relative)
      utf8_text(File.binread(path), 'packet send queue source companion')
    end
    source = utf8_text(File.binread(File.join(root, BELUGA_CORE_CRATE, 'tests/packet_send_queue.rs')),
                       'packet send queue Rust test source')
    ids = source.scan(/^#\[test\][ \t]*\nfn (\w+)[ \t]*\(/).flatten
    require!(source.scan(/^#\[test\]/).length == 32 && ids.uniq.length == ids.length &&
             ids == PACKET_SEND_QUEUE_RUST_PINNED &&
             source.scan('use beluga_core::beluga_core_packet_send_queue_step as transition;').length == 1,
             'packet send queue exact scoped Rust declarations or actual export routing differ')
    nil
  end

  def self.packet_send_queue_native_source_inventory(root)
    validate_packet_send_queue_sources(root)
    PACKET_SEND_QUEUE_NATIVE_FILES.map do |suite, relative|
      source = utf8_text(File.binread(File.join(root, relative)), 'packet send queue native source')
      name = suite.split('.').last
      ids = source.scan(/^[ \t]*func (test\w+)[ \t]*\(/).flatten.map { |method| suite + '/' + method }
      require!(source.scan(/^[ \t]*final class #{Regexp.escape(name)}[ \t]*:[ \t]*XCTestCase[ \t]*\{/).length == 1 &&
               ids.uniq.length == ids.length && ids == PACKET_SEND_QUEUE_NATIVE_PINNED.fetch(suite),
               'packet send queue exact native source inventory differs: ' + suite)
      [suite, ids.sort]
    end.to_h
  end

  def self.packet_send_queue_native_inventory(root, text)
    source = packet_send_queue_native_source_inventory(root)
    lines = utf8_text(text, 'packet send queue native discovery').lines.map(&:strip)
    source.map do |suite, expected|
      ids = lines.select { |line| line.start_with?(suite + '/') }
      require!(ids.uniq.length == ids.length && ids.sort == expected,
               'packet send queue exact native discovery differs: ' + suite)
      [suite, ids.sort]
    end.to_h
  end

  def self.validate_rtt_evidence_sources(root)
    RTT_EVIDENCE_SOURCE_SHA256.each do |relative, expected|
      path = File.join(root, relative)
      require!(File.exist?(path), 'RTT evidence source companion is missing: ' + relative)
      stat = regular!(path)
      require!(File.realpath(path) == path && stat.size <= 2 * 1024 * 1024 && sha(path) == expected,
               'RTT evidence reviewed source/reference body changed: ' + relative)
      utf8_text(File.binread(path), 'RTT evidence source companion')
    end
    source = utf8_text(File.binread(File.join(root, BELUGA_CORE_CRATE, 'tests/rtt_evidence.rs')),
                       'RTT evidence Rust test source')
    ids = source.scan(/^#\[test\][ \t]*\nfn (\w+)[ \t]*\(/).flatten
    require!(source.scan(/^#\[test\]/).length == 34 && ids.uniq.length == ids.length &&
             ids == RTT_EVIDENCE_RUST_PINNED &&
             source.scan("use beluga_core::{beluga_core_rtt_evidence_step as step,\n    beluga_core_rtt_evidence_result_is_valid as verify};").length == 1,
             'RTT evidence exact scoped Rust declarations or actual export routing differ')
    nil
  end

  def self.rtt_evidence_native_source_inventory(root)
    validate_rtt_evidence_sources(root)
    RTT_EVIDENCE_NATIVE_FILES.map do |suite, relative|
      source = utf8_text(File.binread(File.join(root, relative)), 'RTT evidence native source')
      name = suite.split('.').last
      ids = source.scan(/^[ \t]*func (test\w+)[ \t]*\(/).flatten.map { |method| suite + '/' + method }
      require!(source.scan(/^[ \t]*final class #{Regexp.escape(name)}[ \t]*:[ \t]*XCTestCase[ \t]*\{/).length == 1 &&
               ids.uniq.length == ids.length && ids == RTT_EVIDENCE_NATIVE_PINNED.fetch(suite),
               'RTT evidence exact native source inventory differs: ' + suite)
      [suite, ids.sort]
    end.to_h
  end

  def self.rtt_evidence_native_inventory(root, text)
    source = rtt_evidence_native_source_inventory(root)
    lines = utf8_text(text, 'RTT evidence native discovery').lines.map(&:strip)
    source.map do |suite, expected|
      ids = lines.select { |line| line.start_with?(suite + '/') }
      require!(ids.uniq.length == ids.length && ids.sort == expected,
               'RTT evidence exact native discovery differs: ' + suite)
      [suite, ids.sort]
    end.to_h
  end

  def self.validate_tier_demand_sources(root)
    TIER_DEMAND_SOURCE_SHA256.each do |relative, expected|
      path = File.join(root, relative)
      require!(File.exist?(path), 'tier demand source companion is missing: ' + relative)
      stat = regular!(path)
      require!(File.realpath(path) == path && stat.size <= 2 * 1024 * 1024 && sha(path) == expected,
               'tier demand reviewed source/reference body changed: ' + relative)
      utf8_text(File.binread(path), 'tier demand source companion')
    end
    source = utf8_text(File.binread(File.join(root, BELUGA_CORE_CRATE, 'tests/tier_demand.rs')),
                       'tier demand Rust test source')
    ids = source.scan(/^#\[test\][ \t]*\nfn (\w+)[ \t]*\(/).flatten
    require!(source.scan(/^#\[test\]/).length == 28 && ids.uniq.length == ids.length &&
             ids == TIER_DEMAND_RUST_PINNED &&
             source.scan("use beluga_core::{beluga_core_tier_demand_project as project,\n    beluga_core_tier_demand_projection_is_valid as verify};").length == 1,
             'tier demand exact scoped Rust declarations or actual export routing differ')
    adapter = utf8_text(File.binread(File.join(root, 'macOS/Sources/CaptureServer/BelugaRustTierDemand.swift')), 'tier demand actual adapter')
    policy = utf8_text(File.binread(File.join(root, 'macOS/Sources/CaptureServer/WorldwideScreenVideoAdaptationPolicy.swift')), 'tier demand production policy')
    require!(adapter.scan('beluga_core_tier_demand_project(').length == 1 &&
             adapter.scan('beluga_core_tier_demand_projection_is_valid(').length == 2 &&
            policy.scan('tierDemand.selection(for: currentTier,').length == 1 &&
            policy.scan('tierDemand.profile(for:').length == 6 &&
             !policy.match?(/bitrateBasisPoints|baselineReferenceMaximumVideoBitrateBps|baselineReferenceVideoBitrateBps|downgradeHeadroomMultiplier|upgradeMarginMultiplier|totalRTPHeadroomMultiplier|private func sustainableTier|private func highestQualifiedUpgradeTier/),
             'tier demand production adapter routing or removed native business helpers differ')
    nil
  end

  def self.tier_demand_native_source_inventory(root)
    validate_tier_demand_sources(root)
    TIER_DEMAND_NATIVE_FILES.map do |suite, relative|
      source = utf8_text(File.binread(File.join(root, relative)), 'tier demand native source')
      name = suite.split('.').last
      ids = source.scan(/^[ \t]*func (test\w+)[ \t]*\(/).flatten.map { |method| suite + '/' + method }
      require!(source.scan(/^[ \t]*final class #{Regexp.escape(name)}[ \t]*:[ \t]*XCTestCase[ \t]*\{/).length == 1 &&
               ids.uniq.length == ids.length && ids == TIER_DEMAND_NATIVE_PINNED.fetch(suite),
               'tier demand exact native source inventory differs: ' + suite)
      [suite, ids.sort]
    end.to_h
  end

  def self.tier_demand_native_inventory(root, text)
    source = tier_demand_native_source_inventory(root)
    lines = utf8_text(text, 'tier demand native discovery').lines.map(&:strip)
    source.map do |suite, expected|
      ids = lines.select { |line| line.start_with?(suite + '/') }
      require!(ids.uniq.length == ids.length && ids.sort == expected,
               'tier demand exact native discovery differs: ' + suite)
      [suite, ids.sort]
    end.to_h
  end

  def self.validate_media_command_gate_sources(root)
    MEDIA_COMMAND_GATE_SOURCE_SHA256.each do |relative, expected|
      path = File.join(root, relative)
      require!(File.exist?(path), 'media command gate source companion is missing: ' + relative)
      stat = regular!(path)
      require!(File.realpath(path) == path && stat.size <= 2 * 1024 * 1024 && sha(path) == expected,
               'media command gate reviewed source/reference body changed: ' + relative)
      utf8_text(File.binread(path), 'media command gate source companion')
    end
    source = utf8_text(File.binread(File.join(root, BELUGA_CORE_CRATE, 'tests/media_command_gate.rs')),
                       'media command gate Rust test source')
    ids = source.scan(/^#\[test\][ \t]*\nfn (\w+)[ \t]*\(/).flatten
    require!(source.scan(/^#\[test\]/).length == 21 && ids.uniq.length == ids.length &&
             ids == MEDIA_COMMAND_GATE_RUST_PINNED &&
             source.scan("use beluga_core::{beluga_core_media_command_gate_step as step,\n    beluga_core_media_command_gate_result_is_valid as verify};").length == 1,
             'media command gate exact scoped Rust declarations or actual export routing differ')
    adapter = utf8_text(File.binread(File.join(root, 'macOS/Sources/CaptureServer/BelugaRustMediaCommandGate.swift')), 'media command gate actual adapter')
    controller = utf8_text(File.binread(File.join(root, 'macOS/Sources/CaptureServer/MacSystemNowPlayingController.swift')), 'media command gate production controller')
    require!(adapter.scan('beluga_core_media_command_gate_step(').length == 1 &&
             adapter.scan('beluga_core_media_command_gate_result_is_valid(').length == 1 &&
             adapter.scan('let result = resultMutation?(before, event, actual) ?? actual').length == 1 &&
             adapter.scan('rawState = result.state').length == 1 &&
             adapter.scan('guard !hasNativeFault else { return nil }').length == 1 &&
             !adapter.match?(/wrapping_add|&=|fallback/i),
             'media command gate actual producer/verifier or sticky no-fallback routing differ')
    owner = controller[/^final class MacRemoteMediaCommandGate:.*?^}/m]
    require!(owner && owner.scan('private let lock = NSLock()').length == 1 &&
             owner.scan('private var policy: BelugaRustMediaCommandGate').length == 1 &&
             owner.scan('private var contextIDs: Set<String> = []').length == 1 &&
             %w[open close invalidateCommands lifecycleIsCurrent capture admits].all? { |name| owner.scan('policy.' + name + '(').length == 1 } &&
             owner.scan('let wasFaulted = policy.hasNativeFault').length == 1 &&
             owner.scan('if policy.close() || wasFaulted').length == 1 &&
             !owner.match?(/private var lifecycle|private var commandEpoch|&=|isOpen &&/),
             'media command gate locked native membership or removed scalar fallback differs')
    exports = utf8_text(File.binread(File.join(root, BELUGA_CORE_CRATE, 'src/lib.rs')), 'media command gate actual exports')
    header = utf8_text(File.binread(File.join(root, BELUGA_CORE_CRATE, 'include/beluga_core.h')), 'media command gate copied header')
    require!(exports.scan('pub mod media_command_gate;').length == 1 &&
             exports.scan('pub extern "C" fn beluga_core_media_command_gate_step(').length == 1 &&
             exports.scan('pub extern "C" fn beluga_core_media_command_gate_result_is_valid(').length == 1 &&
             header.scan('} beluga_core_media_command_gate_state_t;').length == 1 &&
             header.scan('} beluga_core_media_command_gate_event_t;').length == 1 &&
             header.scan('} beluga_core_media_command_gate_result_t;').length == 1 &&
             header.scan('beluga_core_media_command_gate_step(').length == 1 &&
             header.scan('beluga_core_media_command_gate_result_is_valid(').length == 1,
             'media command gate public copied ABI or actual exports differ')
    nil
  end

  def self.media_command_gate_native_source_inventory(root)
    validate_media_command_gate_sources(root)
    MEDIA_COMMAND_GATE_NATIVE_FILES.map do |suite, relative|
      source = utf8_text(File.binread(File.join(root, relative)), 'media command gate native source')
      name = suite.split('.').last
      ids = source.scan(/^[ \t]*func (test\w+)[ \t]*\(/).flatten.map { |method| suite + '/' + method }
      require!(source.scan(/^[ \t]*final class #{Regexp.escape(name)}[ \t]*:[ \t]*XCTestCase[ \t]*\{/).length == 1 &&
               ids.uniq.length == ids.length && ids == MEDIA_COMMAND_GATE_NATIVE_PINNED.fetch(suite),
               'media command gate exact native source inventory differs: ' + suite)
      [suite, ids.sort]
    end.to_h
  end

  def self.media_command_gate_native_inventory(root, text)
    source = media_command_gate_native_source_inventory(root)
    lines = utf8_text(text, 'media command gate native discovery').lines.map(&:strip)
    source.map do |suite, expected|
      ids = lines.select { |line| line.start_with?(suite + '/') }
      require!(ids.uniq.length == ids.length && ids.sort == expected,
               'media command gate exact native discovery differs: ' + suite)
      [suite, ids.sort]
    end.to_h
  end
  def self.validate_screen_suspension_sources(root)
    SCREEN_SUSPENSION_SOURCE_SHA256.each do |relative, expected|
      path = File.join(root, relative)
      require!(File.exist?(path), 'screen suspension source companion is missing: ' + relative)
      stat = regular!(path)
      require!(File.realpath(path) == path && stat.size <= 2 * 1024 * 1024 && sha(path) == expected,
               'screen suspension reviewed source/reference body changed: ' + relative)
      utf8_text(File.binread(path), 'screen suspension source companion')
    end
    source = utf8_text(File.binread(File.join(root, BELUGA_CORE_CRATE, 'tests/screen_suspension.rs')),
                       'screen suspension Rust test source')
    ids = source.scan(/^#\[test\][ \t]*\nfn (\w+)[ \t]*\(/).flatten
    require!(source.scan(/^#\[test\]/).length == 32 && ids.uniq.length == ids.length &&
             ids == SCREEN_SUSPENSION_RUST_PINNED &&
             source.scan("use beluga_core::{beluga_core_screen_suspension_step as step,\n    beluga_core_screen_suspension_result_is_valid as verify};").length == 1,
             'screen suspension exact scoped Rust declarations or actual export routing differ')
    adapter = utf8_text(File.binread(File.join(root, 'macOS/Sources/CaptureServer/BelugaRustScreenSuspension.swift')), 'screen suspension actual adapter')
    owner = utf8_text(File.binread(File.join(root, 'macOS/Sources/CaptureServer/WorldwideScreenMediaSuspensionCoordinator.swift')), 'screen suspension production owner')
    require!(adapter.scan('struct BelugaRustScreenSuspension: Equatable, Sendable').length == 1 &&
             adapter.scan('beluga_core_screen_suspension_step(').length == 2 &&
             adapter.scan('beluga_core_screen_suspension_result_is_valid(').length == 3 &&
             adapter.scan('let result = resultMutation?(before, event, actual) ?? actual').length == 1 &&
             adapter.scan('rawState = step.result.state').length == 1 &&
             adapter.scan('queryFlags = step.result.query_flags').length == 1 &&
             adapter.scan('guard !hasNativeFault, Self.layoutIsExact').length == 2 &&
             adapter.scan('.offset(of:').length == 33 &&
             adapter.scan('hasNativeFault = true').length == 3 &&
             !adapter.match?(/wrapping_add|&\+=|fallback|func reset|var stateSeed/i),
             'screen suspension actual producer/verifier, layouts or sticky no-reset routing differ')
    require!(owner.scan('struct WorldwideScreenMediaSuspensionCoordinator: Equatable, Sendable').length == 1 &&
             owner.scan('private var core: BelugaRustScreenSuspension').length == 1 &&
             owner.scan('private var custody = NativeCustody()').length == 1 &&
             owner.scan('core = BelugaRustScreenSuspension(resultMutation: resultMutation)').length == 1 &&
             owner.scan('core = proposedCore').length == 1 &&
             owner.scan('custody = proposedCustody').length == 1 &&
             owner.scan('Self.custodyIsConsistent(').length == 4 &&
             owner.scan('core.latchFault()').length == 2 &&
             owner.scan('guard !core.hasNativeFault').length == 2 &&
             owner.scan('func owns(_ binding: Binding) -> Bool').length == 1 &&
             owner.scan('func authorizesFinalization(of request: WebRTCScreenMediaResumeRequest,').length == 1 &&
             owner.scan('step.result.custody_action == 0').length == 1 &&
             owner.scan('BelugaRustScreenSuspension.statesEqual(step.result.state, core.rawState)').length == 1 &&
             owner.scan('step.result.query_flags == core.queryFlags').length == 1 &&
             !owner.match?(/private (?:var|enum) (?:phase|nextGeneration)|&\+=|NSLock|func reset|ObjectIdentifier|hashValue|Hasher/),
             'screen suspension by-value owner, atomic custody or nonmutating denied-query contract differs')
    require!(owner.scan('custody.markerReady.map { presentation.isExactEcho(of: $0) }').length == 1 &&
             owner.scan('custody.markerPresentation == ready.markerPresentation').length == 1 &&
             owner.scan('custody.resumeReady == ready').length == 1 &&
             owner.scan('custody.resumeRequest == request').length == 2 &&
             owner.scan('ready.belongs(to: notice) && ready.attemptID == attempt').length == 1 &&
             owner.scan('guard presentation.isValid, belongs(presentation.markerReady)').length == 1 &&
             owner.scan('guard ready.isValid, belongs(ready.markerPresentation.markerReady)').length == 1 &&
             owner.scan('belongs(request.presentation.resumeReady.markerPresentation.markerReady)').length == 1 &&
             owner.scan('custody.presenceMask == state.custody_mask').length == 1,
             'screen suspension complete native receiver/protocol proof domain or presence custody differs')
    exports = utf8_text(File.binread(File.join(root, BELUGA_CORE_CRATE, 'src/lib.rs')), 'screen suspension actual exports')
    header = utf8_text(File.binread(File.join(root, BELUGA_CORE_CRATE, 'include/beluga_core.h')), 'screen suspension copied header')
    require!(exports.scan('pub mod screen_suspension;').length == 1 &&
             exports.scan('pub extern "C" fn beluga_core_screen_suspension_step(').length == 1 &&
             exports.scan('pub extern "C" fn beluga_core_screen_suspension_result_is_valid(').length == 1 &&
             header.scan('} beluga_core_screen_suspension_state_t;').length == 1 &&
             header.scan('} beluga_core_screen_suspension_event_t;').length == 1 &&
             header.scan('} beluga_core_screen_suspension_result_t;').length == 1 &&
             header.scan('beluga_core_screen_suspension_step(').length == 1 &&
             header.scan('beluga_core_screen_suspension_result_is_valid(').length == 1,
             'screen suspension public copied ABI or actual exports differ')
    nil
  end

  def self.screen_suspension_native_source_inventory(root)
    validate_screen_suspension_sources(root)
    SCREEN_SUSPENSION_NATIVE_FILES.map do |suite, relative|
      source = utf8_text(File.binread(File.join(root, relative)), 'screen suspension native source')
      name = suite.split('.').last
      ids = source.scan(/^[ \t]*func (test\w+)[ \t]*\(/).flatten.map { |method| suite + '/' + method }
      require!(source.scan(/^[ \t]*final class #{Regexp.escape(name)}[ \t]*:[ \t]*XCTestCase[ \t]*\{/).length == 1 &&
               ids.uniq.length == ids.length && ids == SCREEN_SUSPENSION_NATIVE_PINNED.fetch(suite),
               'screen suspension exact native source inventory differs: ' + suite)
      [suite, ids.sort]
    end.to_h
  end

  def self.screen_suspension_native_inventory(root, text)
    source = screen_suspension_native_source_inventory(root)
    lines = utf8_text(text, 'screen suspension native discovery').lines.map(&:strip)
    source.map do |suite, expected|
      ids = lines.select { |line| line.start_with?(suite + '/') }
      require!(ids.uniq.length == ids.length && ids.sort == expected,
               'screen suspension exact native discovery differs: ' + suite)
      [suite, ids.sort]
    end.to_h
  end
  def self.validate_phone_catalog_sources(root)
    PHONE_CATALOG_SOURCE_SHA256.each do |relative, expected|
      path = File.join(root, relative)
      require!(File.exist?(path), 'phone catalog source companion is missing: ' + relative)
      stat = regular!(path)
      require!(File.realpath(path) == path && stat.size <= 2 * 1024 * 1024 && sha(path) == expected,
               'phone catalog reviewed source/reference body changed: ' + relative)
      utf8_text(File.binread(path), 'phone catalog source companion')
    end
    source = utf8_text(File.binread(File.join(root, BELUGA_CORE_CRATE, 'tests/phone_catalog.rs')),
                       'phone catalog Rust test source')
    ids = source.scan(/^#\[test\][ \t]*\nfn (\w+)[ \t]*\(/).flatten
    require!(source.scan(/^#\[test\]/).length == 27 && ids.uniq.length == ids.length &&
             ids == PHONE_CATALOG_RUST_PINNED &&
             source.scan('use beluga_core::{beluga_core_phone_catalog_decide as call, beluga_core_phone_catalog_result_is_valid as verify};').length == 1,
             'phone catalog exact scoped Rust declarations or actual export routing differ')
    adapter = utf8_text(File.binread(File.join(root, 'macOS/Sources/CaptureServer/BelugaRustPhoneCatalog.swift')),
                        'phone catalog actual adapter')
    owner = utf8_text(File.binread(File.join(root, 'macOS/Sources/CaptureServer/WorldwidePairedPhoneCatalogStore.swift')),
                      'phone catalog production owner')
    require!(adapter.scan('struct BelugaRustPhoneCatalog: Sendable').length == 1 &&
             adapter.scan('beluga_core_phone_catalog_decide(').length == 1 &&
             adapter.scan('beluga_core_phone_catalog_result_is_valid(').length == 1 &&
             adapter.scan('let result = resultMutation?(input, actual) ?? actual').length == 1 &&
             adapter.scan('guard beluga_core_phone_catalog_result_is_valid(input, result) == 1 else').length == 1 &&
             adapter.scan('.offset(of:').length == 37 &&
             adapter.scan('MemoryLayout<Input>.size == 104').length == 1 &&
             adapter.scan('MemoryLayout<Result>.size == 72').length == 1 &&
             adapter.scan('case 10: throw RemoteSessionCoreError.invalidPairingCommitBridge').length == 1 &&
             !adapter.match?(/NSLock|private var|fallback|hasNativeFault|func reset|ObjectIdentifier|hashValue|Hasher/),
             'phone catalog actual producer/verifier, copied layouts or operation-local routing differ')
    require!(owner.scan('private static let serializationLock = NSLock()').length == 1 &&
             owner.scan('private let policy: BelugaRustPhoneCatalog').length == 1 &&
             owner.scan('self.policy = BelugaRustPhoneCatalog(resultMutation: resultMutation)').length == 1 &&
             owner.scan('let plan = try policy.checked(planInput)').length == 1 &&
             owner.scan('let result = try policy.checked(finish)').length == 1 &&
             owner.scan('finish.flags = Self.flag(temporary == previous)').length == 1 &&
             owner.scan('try persist(proposed, for: identity)').length == 1 &&
             owner.scan('return previous.snapshot').length == 1 &&
             owner.scan('proposed.records == temporary.records').length == 1 &&
             owner.scan('proposed.legacyImportReceipt == previous.legacyImportReceipt').length == 1 &&
             owner.scan('slots.dropFirst(Int(plan.count)).allSatisfy({ $0 == 9 })').length == 1 &&
             !owner.match?(/func phaseRank|revision \+=|&\+=|private var policy|hasNativeFault|ObjectIdentifier|hashValue|Hasher/),
             'phone catalog complete staged owner, full native custody or unchanged shared lock differs')
    exports = utf8_text(File.binread(File.join(root, BELUGA_CORE_CRATE, 'src/lib.rs')), 'phone catalog actual exports')
    header = utf8_text(File.binread(File.join(root, BELUGA_CORE_CRATE, 'include/beluga_core.h')), 'phone catalog copied header')
    require!(exports.scan('pub mod phone_catalog;').length == 1 &&
             exports.scan('pub extern "C" fn beluga_core_phone_catalog_decide(').length == 1 &&
             exports.scan('pub extern "C" fn beluga_core_phone_catalog_result_is_valid(').length == 1 &&
             header.scan('} beluga_core_phone_catalog_input_t;').length == 1 &&
             header.scan('} beluga_core_phone_catalog_result_t;').length == 1 &&
             header.scan('beluga_core_phone_catalog_decide(').length == 1 &&
             header.scan('beluga_core_phone_catalog_result_is_valid(').length == 1,
             'phone catalog public copied ABI or actual exports differ')
    require!(BelugaCorePhoneCatalogMutationOracle::CONTROLS.length == 21 &&
             BelugaCorePhoneCatalogMutationOracle::CONTROLS.to_h { |name, _, _, _, _, test| [name, test] } == PHONE_CATALOG_MUTANT_TESTS,
             'phone catalog exact strict mutation recipes differ')
    nil
  end

  def self.phone_catalog_native_source_inventory(root)
    validate_phone_catalog_sources(root)
    PHONE_CATALOG_NATIVE_FILES.map do |suite, relative|
      source = utf8_text(File.binread(File.join(root, relative)), 'phone catalog native source')
      name = suite.split('.').last
      ids = source.scan(/^[ \t]*func (test\w+)[ \t]*\(/).flatten.map { |method| suite + '/' + method }
      require!(source.scan(/^[ \t]*final class #{Regexp.escape(name)}[ \t]*:[ \t]*XCTestCase[ \t]*\{/).length == 1 &&
               ids.uniq.length == ids.length && ids == PHONE_CATALOG_NATIVE_PINNED.fetch(suite),
               'phone catalog exact native source inventory differs: ' + suite)
      [suite, ids.sort]
    end.to_h
  end

  def self.phone_catalog_native_inventory(root, text)
    source = phone_catalog_native_source_inventory(root)
    lines = utf8_text(text, 'phone catalog native discovery').lines.map(&:strip)
    source.map do |suite, expected|
      ids = lines.select { |line| line.start_with?(suite + '/') }
      require!(ids.uniq.length == ids.length && ids.sort == expected,
               'phone catalog exact native discovery differs: ' + suite)
      [suite, ids.sort]
    end.to_h
  end

  def self.validate_runtime_catalog_sources(root)
    require!(RUNTIME_CATALOG_SOURCE_SHA256.length == 15, 'runtime catalog exact reviewed source companion count differs')
    RUNTIME_CATALOG_SOURCE_SHA256.each do |relative, expected|
      path = File.join(root, relative)
      require!(File.exist?(path), 'runtime catalog source companion is missing: ' + relative)
      stat = regular!(path)
      require!(File.realpath(path) == path && stat.size <= 2 * 1024 * 1024 && sha(path) == expected,
               'runtime catalog reviewed source/reference body changed: ' + relative)
      utf8_text(File.binread(path), 'runtime catalog source companion')
    end
    source = utf8_text(File.binread(File.join(root, BELUGA_CORE_CRATE, 'tests/runtime_catalog.rs')),
                       'runtime catalog Rust test source')
    ids = source.scan(/^#\[test\][ \t]*\nfn (\w+)[ \t]*\(/).flatten
    require!(source.scan(/^#\[test\]/).length == 32 && ids.uniq.length == ids.length &&
             ids == RUNTIME_CATALOG_RUST_PINNED &&
             source.scan("use beluga_core::{beluga_core_runtime_catalog_step as call,\n    beluga_core_runtime_catalog_result_is_valid as verify};").length == 1,
             'runtime catalog exact scoped Rust declarations or actual export routing differ')
    policy = utf8_text(File.binread(File.join(root, BELUGA_CORE_CRATE, 'src/runtime_catalog.rs')),
                       'runtime catalog pure Rust policy')
    adapter = utf8_text(File.binread(File.join(root, 'macOS/Sources/CaptureServer/BelugaRustRuntimeCatalog.swift')),
                        'runtime catalog actual adapter')
    owner = utf8_text(File.binread(File.join(root, 'macOS/Sources/CaptureServer/WorldwideHostCoordinator.swift')),
                      'runtime catalog production owner')
    checkpoint = utf8_text(File.binread(File.join(root, 'macOS/Sources/CaptureServer/WorldwidePairingCatalogCheckpoint.swift')),
                           'runtime catalog typed error and quiet-boundary dependency')
    exports = utf8_text(File.binread(File.join(root, BELUGA_CORE_CRATE, 'src/lib.rs')), 'runtime catalog actual exports')
    header = utf8_text(File.binread(File.join(root, BELUGA_CORE_CRATE, 'include/beluga_core.h')), 'runtime catalog copied header')
    c_smoke = utf8_text(File.binread(File.join(root, BELUGA_CORE_CRATE, 'tests/c_abi_smoke.c')), 'runtime catalog actual C smoke')
    swift_smoke = utf8_text(File.binread(File.join(root, BELUGA_CORE_CRATE, 'tests/swift_import_smoke.swift')),
                            'runtime catalog actual Swift smoke')
    layouts = {
      'State' => ['RawRuntimeCatalogState', 'beluga_core_runtime_catalog_state_t', 24,
                  [['abi_version', 'u32', 0], ['phase', 'u32', 4], ['operation', 'u32', 8],
                   ['eligible', 'u32', 12], ['intent', 'u32', 16], ['first_grant', 'u32', 20]]],
      'Event' => ['RawRuntimeCatalogEvent', 'beluga_core_runtime_catalog_event_t', 16,
                  [['opcode', 'u32', 0], ['operation', 'u32', 4], ['facts', 'u32', 8], ['reserved', 'u32', 12]]],
      'Result' => ['RawRuntimeCatalogResult', 'beluga_core_runtime_catalog_result_t', 40,
                   [['state', 'RawRuntimeCatalogState', 0], ['status', 'u32', 24], ['decision', 'u32', 28],
                    ['effect', 'u32', 32], ['value', 'u32', 36]]]
    }
    require!(policy.scan(/^#\[repr\(C\)\]/).length == 3 && !policy.match?(/\b(?:unsafe|static|Vec|Box|String|HashMap|BTreeMap)\b/),
             'runtime catalog pure copied policy layout or custody differs')
    layouts.each do |name, (rust_type, c_type, size, fields)|
      rust_bodies = policy.scan(/^pub struct #{Regexp.escape(rust_type)} \{\n([^}]+)\}/).flatten
      rust_fields = rust_bodies.first.to_s.scan(/^[ \t]*pub (\w+): (\w+),$/)
      c_bodies = header.scan(/typedef struct \{\s*((?:(?:uint32_t|beluga_core_runtime_catalog_state_t)\s+\w+;\s*)+)\}\s*#{Regexp.escape(c_type)};/).flatten
      c_fields = c_bodies.first.to_s.scan(/(uint32_t|beluga_core_runtime_catalog_state_t)\s+(\w+);/)
      require!(rust_bodies.length == 1 && rust_fields == fields.map { |field, type, _| [field, type] } &&
               rust_bodies.first.to_s.gsub(/\s+/, '') == fields.map { |field, type, _| "pub#{field}:#{type}," }.join &&
               c_bodies.length == 1 && c_fields == fields.map { |field, type, _| [type == 'u32' ? 'uint32_t' : 'beluga_core_runtime_catalog_state_t', field] },
               'runtime catalog exact copied fields differ: ' + name)
      ["MemoryLayout<#{name}>.size == #{size}", "MemoryLayout<#{name}>.stride == #{size}",
       "MemoryLayout<#{name}>.alignment == 4"].each do |marker|
        require!(adapter.scan(marker).length == 1, 'runtime catalog native layout differs: ' + marker)
      end
      require!(c_smoke.scan("sizeof(#{c_type}) == #{size}").length == 1 &&
               c_smoke.scan("_Alignof(#{c_type}) == 4").length == 1 &&
               swift_smoke.scan("MemoryLayout<#{c_type}>.size == #{size}").length == 1 &&
               swift_smoke.scan("MemoryLayout<#{c_type}>.alignment == 4").length == 1,
               'runtime catalog actual-language layout smoke differs: ' + name)
      fields.each do |field, _, offset|
        native_marker = "MemoryLayout<#{name}>.offset(of: \\.#{field}) == #{offset}"
        swift_marker = "MemoryLayout<#{c_type}>.offset(of: \\.#{field}) == #{offset}"
        require!(adapter.scan(native_marker).length == 1 && swift_smoke.scan(swift_marker).length == 1 &&
                 c_smoke.scan("offsetof(#{c_type}, #{field}) == #{offset}").length == 1,
                 'runtime catalog exact field offset differs: ' + name + '.' + field)
      end
    end
    rust_stages = policy[/enum Stage \{\n([^}]+)\}/, 1].to_s.split(',').map(&:strip).reject(&:empty?)
    native_stages = adapter[/enum Stage: UInt32, CaseIterable, Sendable \{\n([^}]+)\}/, 1].to_s
                           .gsub(/\bcase[ \t]+/, '').sub('startupGuard = 0', 'startupGuard')
                           .split(/[,\s]+/).reject(&:empty?)
    require!(rust_stages.length == 58 && rust_stages.uniq.length == 58 &&
             native_stages == rust_stages.map { |stage| stage[0].downcase + stage[1..] } &&
             adapter.scan('.offset(of:').length == 15,
             'runtime catalog exact ordered native stages or full layout offsets differ')
    require!(adapter.scan('struct BelugaRustRuntimeCatalog: Sendable').length == 1 &&
             adapter.scan('private(set) var isPoisoned = false').length == 1 &&
             adapter.scan('guard !isPoisoned, Self.layoutIsExact else').length == 1 &&
             adapter.scan('beluga_core_runtime_catalog_step(').length == 1 &&
             adapter.scan('beluga_core_runtime_catalog_result_is_valid(').length == 1 &&
             adapter.scan('let actual = beluga_core_runtime_catalog_step(state, event)').length == 1 &&
             adapter.scan('let result = resultMutation?(state, event, actual) ?? actual').length == 1 &&
             adapter.scan("guard beluga_core_runtime_catalog_result_is_valid(state, event, result) == 1 else {\n            isPoisoned = true\n            throw WorldwidePhoneCatalogRuntimeError.invalidRuntimeCatalogBridge\n        }\n        state = result.state").length == 1 &&
             adapter.scan('state = result.state').length == 1 &&
             adapter.scan('mutating func revoke() { _ = try? decide(.revoke) }').length == 1 &&
             adapter.scan('guard !isPoisoned else { throw WorldwidePhoneCatalogRuntimeError.invalidRuntimeCatalogBridge }').length == 1 &&
             !adapter.match?(/NSLock|fallback|func reset|ObjectIdentifier|hashValue|Hasher|UUID\(/),
             'runtime catalog actual producer/verifier, sticky denial or retained copied state differs')
    require!(owner.scan('private var runtimeCatalog: BelugaRustRuntimeCatalog').length == 1 &&
             owner.scan('runtimeCatalog = BelugaRustRuntimeCatalog(resultMutation: runtimeCatalogResultMutation)').length == 1 &&
             checkpoint.scan('case invalidRuntimeCatalogBridge').length == 1 &&
             checkpoint.scan('func worldwidePhoneCatalogHasQuietBoundary(').length == 1,
             'runtime catalog production owner or typed quiet/error dependency differs')
    require!(exports.scan('pub mod runtime_catalog;').length == 1 &&
             exports.scan('pub extern "C" fn beluga_core_runtime_catalog_step(').length == 1 &&
             exports.scan('pub extern "C" fn beluga_core_runtime_catalog_result_is_valid(').length == 1 &&
             exports.scan('runtime_catalog::step(state, event)').length == 1 &&
             exports.scan('runtime_catalog::result_is_valid(state, event, result)').length == 1 &&
             header.scan('beluga_core_runtime_catalog_step(').length == 1 &&
             header.scan('beluga_core_runtime_catalog_result_is_valid(').length == 1 &&
             policy.scan("if supplied.status != 1 { return 0; }\n    let expected = step(state, event);\n    u32::from(expected.status == 1 && supplied == expected)").length == 1,
             'runtime catalog public copied ABI, actual exports or hardwired verifier differ')
    require!(c_smoke.scan('    runtime_catalog_smoke();').length == 1 &&
             swift_smoke.scan(/^runtimeCatalogSmoke\(\)$/).length == 1 &&
             c_smoke.scan(RUNTIME_CATALOG_RUNTIME_MARKERS.fetch(0)).length == 1 &&
             swift_smoke.scan(RUNTIME_CATALOG_RUNTIME_MARKERS.fetch(1)).length == 1,
             'runtime catalog actual linked C/Swift smoke routing or marker differs')
    nil
  end

  def self.runtime_catalog_native_source_inventory(root)
    validate_runtime_catalog_sources(root)
    RUNTIME_CATALOG_NATIVE_FILES.map do |suite, relative|
      source = utf8_text(File.binread(File.join(root, relative)), 'runtime catalog native source')
      name = suite.split('.').last
      classes = source.scan(/\bclass[ \t]+(\w+)[ \t]*:[^{]*\bXCTestCase\b[^{]*\{/).flatten
      ids = source.scan(/^[ \t]*func (test\w+)[ \t]*\(/).flatten.map { |method| suite + '/' + method }
      require!(classes == [name] &&
               source.scan(/^[ \t]*final class #{Regexp.escape(name)}[ \t]*:[ \t]*XCTestCase[ \t]*\{/).length == 1 &&
               ids.uniq.length == ids.length && ids == RUNTIME_CATALOG_NATIVE_PINNED.fetch(suite),
               'runtime catalog exact native source inventory differs: ' + suite)
      [suite, ids.sort]
    end.to_h
  end

  def self.runtime_catalog_native_inventory(root, text)
    source = runtime_catalog_native_source_inventory(root)
    lines = utf8_text(text, 'runtime catalog native discovery').lines.map(&:strip)
    source.map do |suite, expected|
      ids = lines.select { |line| line.start_with?(suite) }
      require!(ids.uniq.length == ids.length && ids.sort == expected,
               'runtime catalog exact native discovery differs: ' + suite)
      [suite, ids.sort]
    end.to_h
  end

  def self.runtime_catalog_rust_inventory(text)
    lines = utf8_text(text, 'runtime catalog Rust discovery').lines.select do |line|
      line.match?(/\A\s*(?:\w+::)*runtime_catalog(?:\b|_)/)
    end
    matches = lines.map { |line| /\A(runtime_catalog_\w+): test\s*\z/.match(line) }
    require!(matches.all? && matches.length == 32,
             'runtime catalog exact Rust discovery is missing, malformed or has extra cases')
    ids = matches.map { |match| match[1] }
    require!(ids.uniq.length == ids.length && ids.sort == RUNTIME_CATALOG_RUST_PINNED.sort,
             'runtime catalog exact Rust discovery differs')
    ids.sort
  end

  def self.validate_display_admission_native_sources(root)
    DISPLAY_ADMISSION_NATIVE_SOURCE_SHA256.each do |relative, expected|
      path = File.join(root, relative)
      require!(File.exist?(path), 'display admission native source companion is missing: ' + relative)
      stat = regular!(path)
      require!(File.realpath(path) == path && stat.size <= 2 * 1024 * 1024 && sha(path) == expected,
               'display admission reviewed native/reference source changed: ' + relative)
      utf8_text(File.binread(path), 'display admission native source companion')
    end
    nil
  end

  def self.display_admission_native_source_inventory(root)
    validate_display_admission_native_sources(root)
    DISPLAY_ADMISSION_NATIVE_FILES.map do |suite, relative|
      source = utf8_text(File.binread(File.join(root, relative)), 'display admission native test source')
      name = suite.split('.').last
      methods = source.scan(/^[ \t]*func (test\w+)[ \t]*\(/).flatten
      ids = methods.map { |method| suite + '/' + method }
      require!(source.scan(/^[ \t]*final class #{Regexp.escape(name)}[ \t]*:[ \t]*XCTestCase[ \t]*\{/).length == 1 &&
               ids.uniq.length == ids.length && ids.sort == DISPLAY_ADMISSION_NATIVE_PINNED.fetch(suite).sort,
               'display admission native source inventory is incomplete, malformed or duplicated: ' + suite)
      [suite, ids.sort]
    end.to_h
  end

  def self.display_admission_native_inventory(root, text)
    source = display_admission_native_source_inventory(root)
    lines = utf8_text(text, 'display admission native discovery').lines.map(&:strip)
    source.map do |suite, expected|
      methods = lines.select { |line| line.start_with?(suite + '/') }
      require!(methods.uniq.length == methods.length &&
               methods.all? { |id| id.match?(/\A#{Regexp.escape(suite)}\/test\w+\z/) } &&
               methods.sort == expected,
               'display admission native discovery differs from exact source inventory: ' + suite)
      [suite, methods.sort]
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


  # Executor merges stdout/stderr onto one descriptor. A case's authority is its
  # exact serial Cargo suite frame; no unqualified-name fallback is accepted.
  def self.beluga_core_rust_frames(text, mode)
    require!(mode == :discovery || mode == :results, 'unknown Beluga core Rust parser mode')
    lines = utf8_text(text, 'Beluga core Rust ' + mode.to_s).lines.map(&:chomp)
    frames = {}
    current = nil
    finished = []
    lines.each do |line|
      if line.match?(/\A\s*Finished\b/)
        require!(line.match?(/\A\s*Finished `test` profile \[[^\r\n]+\] target\(s\) in (?:\d+(?:\.\d+)?s|[1-9]\d*m [0-5]?\ds)\z/),
                 'malformed Beluga core Rust compiled header')
        require!(finished.empty? && frames.empty? && !current,
                 'Beluga core Rust compiled boundary is duplicated or after a suite')
        finished << line
        next
      end
      suite = nil
      if line.match?(/\A\s*Running unittests src\/lib\.rs \((?:[^\r\n()]+\/)?beluga_core-[0-9a-f]+\)\z/)
        suite = 'lib'
      elsif (match = /\A\s*Running tests\/([a-z_]+)\.rs \((?:[^\r\n()]+\/)?([a-z_]+)-[0-9a-f]+\)\z/.match(line))
        require!(match[1] == match[2], 'Beluga core Rust suite/binary identity differs')
        suite = match[1]
      elsif line == '   Doc-tests beluga_core'
        suite = 'doc'
      end
      if suite
        require!(finished.length == 1, 'Beluga core Rust suite precedes compiled boundary')
        require!(!current && BELUGA_CORE_CARGO_SUITES.include?(suite) && !frames.key?(suite),
                 'duplicate, unknown or unclosed Beluga core Rust suite')
        current = { 'suite' => suite, 'cases' => [], 'declared' => nil }
        frames[suite] = current
        next
      end
      require!(!line.match?(/\A\s*(?:Running|Doc-tests)\b/), 'malformed Beluga core Rust suite header')
      if mode == :discovery
        if (match = /\A([\w:]+): test\s*\z/.match(line))
          require!(current && current.fetch('suite') != 'doc' &&
                   !current.fetch('cases').include?(match[1]), 'out-of-suite or duplicate Beluga core discovery')
          current.fetch('cases') << match[1]
        elsif (match = /\A(\d+) tests?, (\d+) benchmarks?\z/.match(line))
          require!(current && match[2].to_i == 0 && match[1].to_i == current.fetch('cases').length &&
                   (current.fetch('suite') != 'doc' || match[1].to_i == 0),
                   'Beluga core discovery suite footer disagrees or contains benchmarks')
          current = nil
        else
          require!(!line.match?(/\A[\w:]+: (?:test|benchmark)\b/), 'malformed Beluga core discovery record')
        end
      else
        if (match = /\Arunning (\d+) tests?\z/.match(line))
          require!(current && current.fetch('declared').nil?, 'out-of-suite or duplicate Beluga core run count')
          current['declared'] = match[1].to_i
        elsif (match = /\Atest ([\w:]+) \.\.\. (ok|FAILED|ignored)\s*\z/.match(line))
          require!(current && !current.fetch('declared').nil? && current.fetch('suite') != 'doc' &&
                   match[2] == 'ok' && !current.fetch('cases').include?(match[1]),
                   'out-of-suite, duplicate, failed or ignored Beluga core result')
          current.fetch('cases') << match[1]
        elsif (match = /\Atest result: ok\. (\d+) passed; (\d+) failed; (\d+) ignored; (\d+) measured; (\d+) filtered out; finished in \d+(?:\.\d+)?s\z/.match(line))
          require!(current && match.captures.drop(1).all? { |number| number.to_i == 0 } &&
                   match[1].to_i == current.fetch('cases').length && current.fetch('declared') == match[1].to_i &&
                   (current.fetch('suite') != 'doc' || match[1].to_i == 0),
                   'Beluga core result suite footer disagrees or contains ignored coverage')
          current = nil
        else
          require!(!line.start_with?('running ', 'test '), 'malformed or failed Beluga core result record')
        end
      end
      require!(!line.start_with?('error') && !line.include?('could not compile'),
               'Beluga core compile/error text is not coverage')
    end
    require!(finished.length == 1 && !current && frames.keys.sort == BELUGA_CORE_CARGO_SUITES.sort,
             'Beluga core Rust suites or compiled boundary are incomplete, duplicated or unclosed')
    frames.transform_values { |frame| frame.fetch('cases').freeze }.freeze
  end

  def self.beluga_core_inventory(text)
    frames = beluga_core_rust_frames(text, :discovery)
    methods = frames.flat_map { |suite, cases| cases.map { |id| suite + '/' + id } }
    require!(!methods.empty? && methods.uniq.length == methods.length, 'empty or duplicate Beluga core discovery')
    BELUGA_CORE_QUALIFIED_PINNED.each { |id| require!(methods.include?(id), "missing critical Beluga core test: #{id}") }
    BELUGA_CORE_ADDED_RUST_BY_SUITE.each do |suite, expected|
      require!(frames.fetch(suite).sort == expected.sort, 'new exact Beluga core Rust cohort differs: ' + suite)
    end
    runtime_catalog_rust_inventory(text)
    methods.sort
  end

  def self.validate_beluga_core_rust(text, expected)
    frames = beluga_core_rust_frames(text, :results)
    observed = frames.flat_map { |suite, cases| cases.map { |id| suite + '/' + id } }
    require!(!observed.empty? && observed.uniq.length == observed.length &&
             expected.uniq.length == expected.length && observed.sort == expected.sort,
             'missing, duplicate, wrong-suite or zero Beluga core Rust results')
    expected
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
    handoff_filter = shared_handoff_filter(handoff_methods)
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
    source = %w[test-validate-microphone-regressions.rb release-gate-enrollment-parser-tests.rb].map do |name|
      utf8_text(File.binread(File.join(root, 'scripts', name)), 'Gate behavioral source')
    end.join("\n")
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
    test_owner_symbol_surface_accepts_exact_names_and_preserves_nm_argv_environment
    test_owner_symbol_surface_rejects_missing_or_duplicate_official_definition
    test_owner_symbol_surface_rejects_each_of_the_seven_exact_private_definitions
    test_owner_symbol_surface_never_pools_arm64_and_x86_64_definitions
    test_owner_symbol_surface_propagates_real_capture_failure_without_retry_or_fallback
    test_owner_symbol_artifact_smoke_false_still_checks_all_four_advertised_architectures
    test_owner_symbol_artifact_smoke_false_rejects_missing_and_private_last_architecture
    test_owner_symbol_artifact_inputs_keep_source_tool_copy_and_archive_guards_real
    test_owner_native_archive_census_accepts_manual_thin_fat_and_bounded_index_padding
    test_owner_native_archive_census_rejects_raw_bitcode_unknown_nested_and_wrong_native_kind
    test_owner_native_archive_census_rejects_malformed_member_and_load_command_ranges
    test_owner_native_archive_census_rejects_missing_duplicate_and_unbound_bsd_index
    test_owner_symbol_artifact_smoke_false_rejects_non_native_members_before_nm_or_pinned_tools
    test_owner_native_archive_census_rejects_fat_subtype_alignment_overlap_and_wrong_inner_cpu
    test_microphone_retry_mutation_decoder_requires_compiled_named_assertion_and_restoration
    test_microphone_retry_mutation_decoder_rejects_compile_signal_timeout_missing_or_wrong_cases
    test_microphone_retry_mutation_anchors_are_unique_and_tests_exist_without_editing_them
    test_update_admission_mutation_decoder_requires_compiled_named_assertion_and_restoration
    test_update_admission_mutation_decoder_rejects_compile_signal_timeout_missing_or_wrong_cases
    test_update_admission_mutation_anchors_are_unique_and_eight_ordinary_tests_remain_intact
    test_update_sparkle_admission_mutation_decoder_requires_compiled_named_assertion_and_restoration
    test_update_sparkle_admission_mutation_decoder_rejects_compile_signal_timeout_missing_or_wrong_cases
    test_update_sparkle_admission_mutation_anchors_are_unique_full_lines_and_eight_ordinary_tests_remain_intact
  ].freeze

  def self.mac_producer_inventory(root)
    source = %w[verify-beluga-mac-client-tests.rb retained-beluga-mac-client-tests.rb update-trial-artifact-tests.rb update-trial-package-tests.rb
      artifact-owner-symbol-tests.rb microphone-retry-mutation-tests.rb update-admission-mutation-tests.rb
      update-sparkle-admission-mutation-tests.rb].map do |name|
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
    markers = BELUGA_CORE_RUNTIME_MARKER_ORDER + ['BELUGA_CORE_LINK_SMOKE_PASS'] +
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
    BELUGA_CORE_ADDED_MUTATION_ORACLES.each do |mapping, oracle|
      require!(oracle::CONTROLS.map { |control| [control.first, control.last] } == mapping.to_a &&
               oracle::NAMES == mapping.keys && oracle::TESTS == mapping.values.uniq,
               'new reviewed Beluga core mutation mapping differs from producer')
    end
    restored_controls = UPDATER_OPERATION_MUTANT_TESTS.merge(PACKET_SEND_QUEUE_MUTANT_TESTS).merge(RTT_EVIDENCE_MUTANT_TESTS).merge(TIER_DEMAND_MUTANT_TESTS).merge(MEDIA_COMMAND_GATE_MUTANT_TESTS).merge(SCREEN_SUSPENSION_MUTANT_TESTS).merge(PHONE_CATALOG_MUTANT_TESTS).merge(BELUGA_CORE_ADDED_MUTANT_TESTS)
    restoration_markers = restored_controls.keys.map do |name|
      'BELUGA_CORE_MUTANT_RESTORED ' + name + ' baseline-passed'
    end
    expected_frames = BELUGA_CORE_MUTANTS.flat_map do |name|
      rejected = 'BELUGA_CORE_MUTANT_REJECTED ' + name + ' assertion-failed'
      restored_controls.key?(name) ?
        [rejected, 'BELUGA_CORE_MUTANT_RESTORED ' + name + ' baseline-passed'] : [rejected]
    end
    require!(lines.select { |line| line.start_with?('BELUGA_CORE_MUTANT_REJECTED', 'BELUGA_CORE_MUTANT_RESTORED') } == expected_frames,
             'Beluga core mutation oracle is incomplete: restored markers are missing, duplicate, wrong or out of order')
    footer = 'BELUGA_CORE_MUTATIONS_PASS cases=' + BELUGA_CORE_MUTANTS.length.to_s
    # Preserve Array#index's first occurrence; the unchanged frame checks reject duplicates.
    marker_indices = (expected + restoration_markers + [footer]).to_h { |marker| [marker, nil] }
    lines.each_with_index do |line, index|
      marker_indices[line] = index if marker_indices.key?(line) && marker_indices[line].nil?
    end
    require!(observed == expected && lines.count(footer) == 1 &&
             lines.select { |line| line.start_with?('BELUGA_CORE_MUTATIONS_PASS') } == [footer] &&
             (expected + restoration_markers).all? { |line| marker_indices.fetch(line) < marker_indices.fetch(footer) },
             'Beluga core assertion-failing mutation oracle is incomplete, duplicate or out of order')
    # Each marker must close a fresh compiled, exact single-case assertion
    # failure. A compile error, unrelated failing test or summary alone cannot
    # substitute for the producer's source-bound exit-101 behavioral oracle.
    offset = 0
    BELUGA_CORE_MUTANT_TESTS.each do |name, test|
      marker = 'BELUGA_CORE_MUTANT_REJECTED ' + name + ' assertion-failed'
      finish = marker_indices.fetch(marker)
      segment = lines[offset...finish]
      compiled = segment.select { |line| line.match?(/\A\s*Finished\b/) }
      cases = segment.select { |line| line.match?(/\Atest \S+ \.\.\. /) }
      panics = segment.select { |line| line.start_with?("thread '") && line.include?(' panicked at ') }
      assertions = segment.select { |line| line.start_with?('assertion ') }
      results = segment.select { |line| line.start_with?('test result:') }
      errors = segment.select { |line| line.start_with?('error') }
      rerun = test.start_with?('screen_liveness::tests::') || BELUGA_CORE_OWNER_MUTANT_TESTS.key?(name) ?
        /\Aerror: test failed, to rerun pass `--lib`\z/ :
        /\Aerror: test failed, to rerun pass `--test [a-z_]+`\z/
      require!(compiled.length == 1 && compiled.first.match?(/\A\s*Finished `test` profile \[[^\r\n]+\] target\(s\) in [^\r\n]+\z/) &&
               segment.select { |line| line.start_with?('running ') } == ['running 1 test'] &&
               cases == ['test ' + test + ' ... FAILED'] &&
               panics.length == 1 && panics.first.match?(/\Athread '#{Regexp.escape(test)}'(?: \(\d+\))? panicked at [^\r\n]+\z/) &&
               assertions.length == 1 && assertions.first.match?(/\Aassertion `left == right` failed(?:: [^\r\n]*)?\z/) &&
               results.length == 1 && results.first.match?(/\Atest result: FAILED\. 0 passed; 1 failed; 0 ignored; 0 measured; \d+ filtered out; finished in [^\r\n]+\z/) &&
               errors.length == 1 && errors.first.match?(rerun) &&
               segment.none? { |line| line.include?('could not compile') },
               'Beluga core assertion-failing mutation oracle is incomplete: missing compiled intended assertion for ' + name)
      offset = finish + 1
      added = BELUGA_CORE_ADDED_MUTATION_ORACLES.find { |mapping, _| mapping.key?(name) }
      if added
        begin
          oracle = added.last
          oracle.validate!(segment.join("\n") + "\n", test, passed: false,
            exitstatus: 101, termsig: nil, timed_out: false)
          restored = 'BELUGA_CORE_MUTANT_RESTORED ' + name + ' baseline-passed'
          restored_finish = marker_indices.fetch(restored)
          oracle.validate!(lines[offset...restored_finish].join("\n") + "\n", test, passed: true,
            exitstatus: 0, termsig: nil, timed_out: false)
          offset = restored_finish + 1
        rescue RuntimeError => error
          raise RuntimeError, 'Beluga core mutation oracle is incomplete: ' + error.message + ' for ' + name
        end
      elsif UPDATER_OPERATION_MUTANT_TESTS.key?(name)
        begin
          BelugaCoreUpdaterMutationOracle.validate_rejected!(segment.join("\n") + "\n", test)
          restored = 'BELUGA_CORE_MUTANT_RESTORED ' + name + ' baseline-passed'
          restored_finish = marker_indices.fetch(restored)
          BelugaCoreUpdaterMutationOracle.validate_restored!(lines[offset...restored_finish].join("\n") + "\n", test)
          offset = restored_finish + 1
        rescue RuntimeError => error
          raise RuntimeError, 'Beluga core mutation oracle is incomplete: ' + error.message + ' for ' + name
        end
      elsif PACKET_SEND_QUEUE_MUTANT_TESTS.key?(name)
        begin
          BelugaCorePacketQueueMutationOracle.validate!(segment.join("\n") + "\n", test, passed: false)
          restored = 'BELUGA_CORE_MUTANT_RESTORED ' + name + ' baseline-passed'
          restored_finish = marker_indices.fetch(restored)
          BelugaCorePacketQueueMutationOracle.validate!(lines[offset...restored_finish].join("\n") + "\n", test, passed: true)
          offset = restored_finish + 1
        rescue RuntimeError => error
          raise RuntimeError, 'Beluga core mutation oracle is incomplete: ' + error.message + ' for ' + name
        end
      elsif RTT_EVIDENCE_MUTANT_TESTS.key?(name)
        begin
          BelugaCoreRTTEvidenceMutationOracle.validate!(segment.join("\n") + "\n", test, passed: false)
          restored = 'BELUGA_CORE_MUTANT_RESTORED ' + name + ' baseline-passed'
          restored_finish = marker_indices.fetch(restored)
          BelugaCoreRTTEvidenceMutationOracle.validate!(lines[offset...restored_finish].join("\n") + "\n", test, passed: true)
          offset = restored_finish + 1
        rescue RuntimeError => error
          raise RuntimeError, 'Beluga core mutation oracle is incomplete: ' + error.message + ' for ' + name
        end
      elsif TIER_DEMAND_MUTANT_TESTS.key?(name)
        begin
          BelugaCoreTierDemandMutationOracle.validate!(segment.join("\n") + "\n", test, passed: false)
          restored = 'BELUGA_CORE_MUTANT_RESTORED ' + name + ' baseline-passed'
          restored_finish = marker_indices.fetch(restored)
          BelugaCoreTierDemandMutationOracle.validate!(lines[offset...restored_finish].join("\n") + "\n", test, passed: true)
          offset = restored_finish + 1
        rescue RuntimeError => error
          raise RuntimeError, 'Beluga core mutation oracle is incomplete: ' + error.message + ' for ' + name
        end
      elsif MEDIA_COMMAND_GATE_MUTANT_TESTS.key?(name)
        begin
          BelugaCoreMediaCommandGateMutationOracle.validate!(segment.join("\n") + "\n", test, passed: false)
          restored = 'BELUGA_CORE_MUTANT_RESTORED ' + name + ' baseline-passed'
          restored_finish = marker_indices.fetch(restored)
          BelugaCoreMediaCommandGateMutationOracle.validate!(lines[offset...restored_finish].join("\n") + "\n", test, passed: true)
          offset = restored_finish + 1
        rescue RuntimeError => error
          raise RuntimeError, 'Beluga core mutation oracle is incomplete: ' + error.message + ' for ' + name
        end
      elsif PHONE_CATALOG_MUTANT_TESTS.key?(name)
        begin
          BelugaCorePhoneCatalogMutationOracle.validate!(segment.join("\n") + "\n", test, passed: false, exitstatus: 101, termsig: nil, timed_out: false)
          restored = 'BELUGA_CORE_MUTANT_RESTORED ' + name + ' baseline-passed'
          restored_finish = marker_indices.fetch(restored)
          BelugaCorePhoneCatalogMutationOracle.validate!(lines[offset...restored_finish].join("\n") + "\n", test, passed: true, exitstatus: 0, termsig: nil, timed_out: false)
          offset = restored_finish + 1
        rescue RuntimeError => error
          raise RuntimeError, 'Beluga core mutation oracle is incomplete: ' + error.message + ' for ' + name
        end
      elsif SCREEN_SUSPENSION_MUTANT_TESTS.key?(name)
        begin
          BelugaCoreScreenSuspensionMutationOracle.validate!(segment.join("\n") + "\n", test, passed: false)
          restored = 'BELUGA_CORE_MUTANT_RESTORED ' + name + ' baseline-passed'
          restored_finish = marker_indices.fetch(restored)
          BelugaCoreScreenSuspensionMutationOracle.validate!(lines[offset...restored_finish].join("\n") + "\n", test, passed: true)
          offset = restored_finish + 1
        rescue RuntimeError => error
          raise RuntimeError, 'Beluga core mutation oracle is incomplete: ' + error.message + ' for ' + name
        end
      end
    end
    require!(lines[offset..-1].none? do |line|
      line.match?(/\A\s*Finished\b/) || line.start_with?('running ', 'test ', "thread '", 'assertion ', 'error') ||
        line.include?('could not compile')
    end, 'Beluga core assertion-failing mutation oracle is incomplete: unframed trailing result')
  end

  # New pairing phases alone use retained-PGID teardown. Do not change the
  # existing phase executor's behavior as part of this additive seam.
  class PairingExecutor
    class GroupPresenceIndeterminate < RuntimeError; end

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
      raise GroupPresenceIndeterminate, 'pairing owned process group cannot be proven absent: EPERM'
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

    def await_absence(pid, pgid, seconds, can_reap = true, after_kill: false)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
      loop do
        reap_leader(pid) if can_reap
        begin
          return true unless group_present?(pgid)
        rescue GroupPresenceIndeterminate => error
          # Darwin may briefly retain an exited descendant's process group.
          # EPERM is never absence: only poll within the existing post-KILL
          # deadline, after successfully signalling this exact captured group.
          raise unless after_kill && @kill_sent == true && pgid == @last_pgid
          raise error if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        end
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
            MicrophoneRegressionGate.require!(await_absence(pid, pgid, 2.0, !reap_error, after_kill: true), 'pairing owned process group survived bounded teardown')
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
      MicrophoneRegressionGate.display_admission_native_inventory(@root, mac_discovery)
      MicrophoneRegressionGate.output_dimensions_native_inventory(@root, mac_discovery)
      MicrophoneRegressionGate.packet_send_queue_native_inventory(@root, mac_discovery)
      MicrophoneRegressionGate.rtt_evidence_native_inventory(@root, mac_discovery)
      MicrophoneRegressionGate.tier_demand_native_inventory(@root, mac_discovery)
      MicrophoneRegressionGate.media_command_gate_native_inventory(@root, mac_discovery)
      MicrophoneRegressionGate.screen_suspension_native_inventory(@root, mac_discovery)
      MicrophoneRegressionGate.phone_catalog_native_inventory(@root, mac_discovery)
      MicrophoneRegressionGate.runtime_catalog_native_inventory(@root, mac_discovery)
      MicrophoneRegressionGate.updater_microphone_native_inventory(@root, mac_discovery)
      MicrophoneRegressionGate.microphone_input_lease_native_inventory(@root, mac_discovery)
      MicrophoneRegressionGate.microphone_output_format_native_inventory(@root, mac_discovery)
      MicrophoneRegressionGate.ice_recovery_native_inventory(@root, mac_discovery)
      MicrophoneRegressionGate.screen_liveness_native_inventory(@root, mac_discovery)
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
      handoff_filter = MicrophoneRegressionGate.shared_handoff_filter(handoff_methods)
      handoff_log = phase('shared-handoff-tests', swift_base + ['--skip-build', '--filter', handoff_filter])
      MicrophoneRegressionGate.validate_mac_log(handoff_log, handoff_methods)
      MicrophoneRegressionGate.validate_ice_recovery_original_results(handoff_log)
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
      MicrophoneRegressionGate.validate_beluga_core_rust(phase('beluga-core-tests', core_base + ['--test-threads=1']), core_methods)
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
    display_admission_native_inventory(root, read_phase.call('mac-discovery'))
    output_dimensions_native_inventory(root, read_phase.call('mac-discovery'))
    packet_send_queue_native_inventory(root, read_phase.call('mac-discovery'))
    rtt_evidence_native_inventory(root, read_phase.call('mac-discovery'))
    tier_demand_native_inventory(root, read_phase.call('mac-discovery'))
    media_command_gate_native_inventory(root, read_phase.call('mac-discovery'))
    screen_suspension_native_inventory(root, read_phase.call('mac-discovery'))
    phone_catalog_native_inventory(root, read_phase.call('mac-discovery'))
    runtime_catalog_native_inventory(root, read_phase.call('mac-discovery'))
    updater_microphone_native_inventory(root, read_phase.call('mac-discovery'))
    microphone_input_lease_native_inventory(root, read_phase.call('mac-discovery'))
    microphone_output_format_native_inventory(root, read_phase.call('mac-discovery'))
    ice_recovery_native_inventory(root, read_phase.call('mac-discovery'))
    screen_liveness_native_inventory(root, read_phase.call('mac-discovery'))
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
    validate_ice_recovery_original_results(read_phase.call('shared-handoff-tests'))
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
    validate_beluga_core_rust(read_phase.call('beluga-core-tests'), core)
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
