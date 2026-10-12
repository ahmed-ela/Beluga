//! PRIVATE setter-only native-cut bookkeeping; not a guarded native effect transaction.
//! Original Swift retains exact identity/resource checks, handles, awaits and actual effects.
//! These constructible copied events are neither native capabilities nor an approved ABI.
use super::dependencies::Scalar;
use super::policy::Recommendation;
use super::service::Owner;

/// Exact native encoding values for the temporary ten-FPS resume probe. This deliberately
/// is not a policy Recommendation: its temporary FPS must never become an accepted tier.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ResumeProbeLimits {
    pub maximum_video: i64,
    pub fps: i64,
    pub scale: Scalar,
}

/// Copied recommendation captured at original3497, before the native apply await.
/// `limits == None` preserves original FPS >=10 skip; it does not clear applied state.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ResumeProbePlan {
    pub captured_recommendation: Recommendation,
    pub limits: Option<ResumeProbeLimits>,
}

/// Setter-only cuts after the explicitly documented original native predecessor actions.
/// No event mints custody, verifies a callback lifetime, or invokes an effect. In particular
/// no opaque accepted token is manufactured to stand in for the original native guards.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum NativeBookkeepingCut {
    /// Original1788: BOTH startStatistics and peer.start successfully returned. No new guard.
    PeerStartReturned,
    /// Original3534: exact postapply guard and actual ten-FPS capturer output already ran.
    ResumeProbeOutputReturned,
    /// Original4171: missing-resource path already ran epoch reset, then native context clear.
    ResumeMissingResourcesContextCleared,
    /// Original4211: exact final-restoration guard and actual capturer output already ran.
    /// The value is original4164's captured recommendation, NOT current policy recomputation.
    ResumeRestorationOutputReturned { captured_recommendation: Recommendation },
    /// Original4223: catch's optional matching-context epoch/reset has already been handled.
    /// This clear remains unconditional, including a missing or foreign current context.
    ResumeRestorationCatchContextHandled,
    /// Original7671–7672: exact native startup fence passed. This cut comes BEFORE geometry
    /// assignments/input bounds/capturer output. A swallowed apply error means false and
    /// retains previous applied state; it does not turn startup output into apply success.
    StartupSenderFencePassedBeforeGeometry {
        captured_recommendation: Recommendation,
        native_update_returned: bool,
    },
}

/// Pure bookkeeping observation, not a permission to apply limits, output frames or resume.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BookkeepingChange {
    FastAvailabilityCleared,
    AppliedCleared,
    AppliedStored,
    AppliedRetained,
}

impl Owner {
    /// Original3497–3502's complete temporary-probe numeric branch, with no state mutation.
    /// Swift's original3480–3489 native ownership/resource guard precedes this projection.
    pub fn resume_probe_plan(&self) -> ResumeProbePlan {
        let captured_recommendation = self.policy.current_recommendation();
        let limits = (captured_recommendation.fps < 10).then_some(ResumeProbeLimits {
            maximum_video: captured_recommendation.maximum_video,
            fps: 10,
            scale: captured_recommendation.scale,
        });
        ResumeProbePlan { captured_recommendation, limits }
    }

    /// Every arm changes ONLY its explicitly assigned original bookkeeping field. Revision,
    /// accepted policy, freshness, evidence lane/time and all route/clock state remain exact.
    /// `begin_post_resume_epoch` is a DISTINCT existing stage at original3642–3654: callers
    /// must preserve its BEFORE/AFTER placement, native context clear and original clock cuts.
    pub fn apply_native_bookkeeping_cut(&mut self, cut: NativeBookkeepingCut) -> BookkeepingChange {
        match cut {
            NativeBookkeepingCut::PeerStartReturned => {
                self.fast_statistics_available = false;
                BookkeepingChange::FastAvailabilityCleared
            }
            NativeBookkeepingCut::ResumeProbeOutputReturned
            | NativeBookkeepingCut::ResumeMissingResourcesContextCleared
            | NativeBookkeepingCut::ResumeRestorationCatchContextHandled => {
                self.applied = None;
                BookkeepingChange::AppliedCleared
            }
            NativeBookkeepingCut::ResumeRestorationOutputReturned { captured_recommendation } => {
                self.applied = Some(captured_recommendation);
                BookkeepingChange::AppliedStored
            }
            NativeBookkeepingCut::StartupSenderFencePassedBeforeGeometry {
                captured_recommendation, native_update_returned,
            } => {
                if native_update_returned {
                    self.applied = Some(captured_recommendation);
                    BookkeepingChange::AppliedStored
                } else {
                    BookkeepingChange::AppliedRetained
                }
            }
        }
    }
}
