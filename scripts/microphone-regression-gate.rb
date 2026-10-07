#!/usr/bin/ruby
# Offline contributor evidence only. No physical destination or installed HAL probe is used.
require 'digest'
require 'fileutils'
require 'find'
require 'json'
require 'open3'
require 'rexml/document'
require 'set'
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
                               src/lib.rs src/host_lifecycle.rs src/handoff_transactions.rs src/handoff_offers.rs src/youtube_handoff_operation.rs include/beluga_core.h include/module.modulemap
                               tests/policy.rs tests/host_lifecycle.rs tests/handoff_transactions.rs tests/handoff_offers.rs tests/youtube_handoff_operation.rs tests/c_abi_smoke.c tests/swift_import_smoke.swift
                               scripts/artifact_support.rb scripts/build-xcframework.rb scripts/verify-xcframework.rb
                               scripts/mutation-tests.rb].freeze
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
    CaptureServerTests.WorldwideHostLifecycleTests
    CaptureServerTests.WorldwidePairingCatalogBootstrapTests
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
    'phone-pending-failure-keeps-reservation' => 'every_pending_failure_retains_proof_but_becomes_unknown_terminal'
  }.freeze
  BELUGA_CORE_MUTANTS = BELUGA_CORE_MUTANT_TESTS.keys.freeze
  BELUGA_CORE_RUNTIME_MARKERS = [
    'BelugaCore C ABI PASS: 4096 flags and unknown ABI',
    'BelugaCore C lifecycle ABI PASS: reconnect ownership and invalid ABI',
    'BelugaCore C transaction ABI PASS: exact identity, cached reply, revocation and unknown outcome',
    'BelugaCore C offers ABI PASS: independent owners, sequence burn, consuming rejection and exact layouts',
    'BelugaCore C phone operation ABI PASS: exact layouts, original ordering, immutable proof and honest pause outcomes',
    'BelugaCore Swift import/link PASS: 4096 flags and unknown ABI',
    'BelugaCore Swift lifecycle import/link PASS: reconnect ownership and invalid ABI',
    'BelugaCore Swift transaction import/link PASS: exact identity, cached reply, revocation and unknown outcome',
    'BelugaCore Swift offers import/link PASS: independent owners, sequence burn, consuming rejection and exact layouts',
    'BelugaCore Swift phone operation import/link PASS: exact layouts, original ordering, immutable proof and honest pause outcomes'
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
  PHASES = %w[gate-self-tests simulator-signing-self-tests release-hook-self-tests host-release-hook-self-tests mac-producer-contract-tests product-identity product-identity-mutations rust-artifact-validation beluga-core-artifact-validation beluga-core-link beluga-core-mutations mac-discovery mac-tests shared-signaling-tests shared-handoff-tests simulator-tests simulator-summary simulator-results simulator-signature
              simulator-entitlements rust-discovery rust-tests beluga-core-discovery beluga-core-tests driver-tests driver-sanitizers driver-diagnostic-reader driver-build-1
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
    }
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

    def initialize(root, options, executor = Executor.new)
      @root = File.realpath(root)
      @options = options
      @executor = executor
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
      log = File.join(@evidence, name + '.log')
      puts "microphone-regressions: #{name}; deadline #{@options.fetch(:timeout)}s; log #{log}"
      text = @executor.run(argv, environment, root, log, @options.fetch(:timeout))
      check_source
      check_tools
      @phases << { 'name' => name, 'argv' => argv, 'log' => File.basename(log), 'sha256' => MicrophoneRegressionGate.sha(log) }
      text
    end

    def artifact(name, path)
      { 'name' => name, 'path' => path.delete_prefix(@evidence + '/'), 'sha256' => File.directory?(path) ? MicrophoneRegressionGate.tree_identity(path) : MicrophoneRegressionGate.sha(path), 'tree' => File.directory?(path) }
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
      shared_methods = MicrophoneRegressionGate.shared_signaling_inventory(mac_discovery)
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
      artifacts << artifact('simulator-app', app)
      artifacts << artifact('mac-xunit', mac_xml) if File.file?(mac_xml)
      receipt = { 'schema' => SCHEMA, 'status' => 'passed', 'scope' => 'offline-source-only', 'root' => @root,
                  'created_at' => Time.now.to_i, 'source' => @source, 'tools' => @tools, 'simulator' => simulator,
                  'invocation' => { 'developer_directory' => developer, 'scratch' => scratch, 'swift_scratch' => @swift_scratch, 'timeout_seconds' => @options.fetch(:timeout) },
                  'mac_format' => mac_format, 'phases' => @phases, 'artifacts' => artifacts,
                  'coverage' => { 'mac' => mac_methods, 'simulator' => sim_methods, 'intentional_simulator_skips' => SIMULATOR_SKIPS,
                                  'rust' => rust_methods, 'beluga_core' => core_methods, 'shared_handoff' => handoff_methods, 'c' => c_methods } }
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
    exact_keys!(receipt, %w[schema status scope root created_at source tools simulator invocation mac_format phases artifacts coverage], 'receipt')
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
    required_artifacts = %w[simulator-result driver-bundle-1 driver-bundle-2 simulator-app]
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
    exact_keys!(coverage, %w[mac simulator intentional_simulator_skips rust beluga_core shared_handoff c], 'coverage')
    mac = mac_inventory(read_phase.call('mac-discovery'))
    shared = shared_signaling_inventory(read_phase.call('mac-discovery'))
    handoff = shared_handoff_inventory(read_phase.call('mac-discovery'))
    require!(coverage['mac'] == mac, 'Mac coverage differs from discovery')
    require!(coverage['shared_handoff'] == handoff, 'shared handoff coverage differs from discovery')
    expected_commands = commands(root, directory, receipt['invocation'], tools, receipt['simulator'], mac, handoff)
    phases.each { |entry| require!(entry['argv'] == expected_commands.fetch(entry['name']), 'phase command does not match canonical offline invocation: ' + entry['name']) }
    if receipt['mac_format'] == 'xunit'
      xml = artifacts.find { |entry| entry['name'] == 'mac-xunit' }
      validate_xunit(File.read(File.join(directory, xml['path'])), mac)
    else
      require!(receipt['mac_format'] == 'darwin-xctest-log', 'unrecognized Mac result format')
      validate_mac_log(read_phase.call('mac-tests'), mac)
    end
    validate_shared_signaling(read_phase.call('shared-signaling-tests'), shared)
    validate_mac_log(read_phase.call('shared-handoff-tests'), handoff)
    sim = simulator_inventory(root)
    require!(coverage['simulator'] == sim && coverage['intentional_simulator_skips'] == SIMULATOR_SKIPS, 'Simulator coverage or skip contract changed')
    validate_simulator(parse_json(read_phase.call('simulator-summary'), 'Simulator summary'), parse_json(read_phase.call('simulator-results'), 'Simulator results'), sim, receipt['simulator'])
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
    # Recollection invokes read-only tools. Fence the complete invocation again,
    # not just the main executable/Info bytes observed inside the collector.
    PHASES.each { |name| read_phase.call(name) }
    check_artifacts.call
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
