use std::collections::BTreeMap;
use std::env;
use std::fs::{self, OpenOptions};
use std::io::Read;
use std::os::unix::fs::{MetadataExt, OpenOptionsExt};
use std::path::{Component, Path, PathBuf};

#[cfg(target_os="macos")]
#[path="opensteamer-microphone-v9-os.rs"]
mod os;
#[path="opensteamer-microphone-v9-proof.rs"]
mod proof;
#[cfg(target_os="macos")]
#[path="opensteamer-microphone-v9-backend.rs"]
mod backend;
// Staging is not publicly dispatched until independently audited.
#[cfg(target_os="macos")]
#[allow(dead_code)]
#[path="opensteamer-microphone-v9-seal.rs"]
mod seal;

const SCHEMA: &str = "opensteamer.microphone-v9-transaction-request.v1";
const ARTIFACT: &str = "/Volumes/t7/beluga-microphone-v9-clean-environment.DgmLSM/production-driver-v9";
const TOOLING: &str = "/Users/ahmed/Documents/Codex/opensteamer-diagnostic-v3";
const HOST_PROFILE: &str = "/Volumes/t7/beluga-microphone-matching-host.GVm1ZJ/release-profile.json";
const DRIVER: &str = "/Library/Audio/Plug-Ins/HAL/OpensteamerVirtualMicrophone.driver";
const ROOT_TRANSACTIONS: &str = "/Library/Application Support/opensteamer/microphone-v9-transactions";
const HOST_POINTER: &str = "/Users/ahmed/Library/Application Support/opensteamer/active-paired-host-update-host-microphone-v9-001";
const HOST_EVIDENCE: &str = "/Users/ahmed/Library/Application Support/opensteamer/paired-host-updates-host-microphone-v9-001/";
const MAX_REQUEST: usize = 65_536;
#[cfg(target_os = "macos")]
const NOFOLLOW: i32 = 0x100;
#[cfg(not(target_os = "macos"))]
const NOFOLLOW: i32 = 0x20000;

const FIELDS: &[&str] = &[
    "schema", "namespace", "nonce", "caller_uid", "producer_commit", "producer_tree",
    "product_commit", "product_tree", "artifact_root", "artifact_manifest_sha256",
    "artifact_binding_sha256", "artifact_entry_sha256", "artifact_closure_sha256",
    "producer_request_sha256", "driver_tree_sha256", "driver_executable_sha256", "package_sha256",
    "guard_tooling_root", "guard_tooling_commit", "guard_tooling_tree", "worker_sha256",
    "idle_helper_sha256", "both_order_probe_sha256", "route_guardian_sha256", "fresh_binding_sha256",
    "host_profile_path", "host_profile_sha256", "host_handoff_sha256", "host_payload_sha256",
    "host_executable_sha256", "host_framework_sha256", "host_info_plist_sha256", "host_pid",
    "host_start_identity_sha256", "host_nonce", "host_lock_device", "host_lock_inode",
    "host_launch_plist_sha256", "predecessor_driver_tree_sha256", "predecessor_driver_executable_sha256",
    "predecessor_driver_instance", "predecessor_driver_device", "predecessor_driver_inode",
    "input_uid", "output_uid", "system_output_uid", "normal_restart_budget", "rollback_restart_budget",
    "timeout_seconds", "committed_host_pointer_path", "committed_host_pointer_sha256",
    "committed_host_result_path", "committed_host_result_sha256", "committed_host_readiness_path",
    "committed_host_readiness_sha256", "committed_host_journal_path", "committed_host_journal_sha256",
    "host_launchd_runs", "host_display_identity_sha256",
];

type Result<T> = std::result::Result<T, String>;

fn hex(value: &str, count: usize) -> bool {
    value.len() == count && value.bytes().all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

fn positive(value: &str) -> Result<u64> {
    if value.is_empty() || value.starts_with('0') || !value.bytes().all(|byte| byte.is_ascii_digit()) {
        return Err("noncanonical positive integer".into());
    }
    value.parse().map_err(|_| "integer overflow".into())
}

fn canonical_path(value: &str) -> bool {
    value.starts_with('/') && !value.ends_with('/') && !value.contains("//") &&
        value.split('/').skip(1).all(|part| !part.is_empty() && part != "." && part != "..") &&
        Path::new(value).components().all(|part| !matches!(part, Component::ParentDir | Component::CurDir))
}

fn guard_build_proof_path(value:&str)->bool {
    if !canonical_path(value){return false;}
    let Some(directory)=Path::new(value).parent()else{return false;};
    let Some(name)=directory.file_name().and_then(|value|value.to_str())else{return false;};
    Path::new(value).file_name().and_then(|value|value.to_str())==Some("build-proof.json")&&
        directory.parent()==Some(Path::new("/private/tmp"))&&
        name.strip_prefix("beluga-microphone-v9-guards.").is_some_and(|suffix|!suffix.is_empty()&&suffix.bytes().all(|byte|byte.is_ascii_alphanumeric()||matches!(byte,b'-'|b'_')))
}

fn private_request_path(value:&str)->bool {
    if !canonical_path(value){return false;}
    let path=Path::new(value);
    let Some(directory)=path.parent()else{return false;};
    let Some(name)=directory.file_name().and_then(|value|value.to_str())else{return false;};
    path.file_name().and_then(|value|value.to_str())==Some("native-request.txt")&&
        directory.parent()==Some(Path::new("/private/tmp"))&&
        name.strip_prefix("beluga-microphone-v9-supervisor.").is_some_and(|suffix|!suffix.is_empty()&&suffix.bytes().all(|byte|byte.is_ascii_alphanumeric()||matches!(byte,b'-'|b'_')))
}

#[derive(Clone, Debug)]
struct Request {
    fields: BTreeMap<String, String>,
    sha256: String,
}

const EXACT_FIELDS: &[(&str, &str)] = &[
            ("schema", SCHEMA), ("caller_uid", "501"), ("artifact_root", ARTIFACT),
            ("guard_tooling_root", TOOLING), ("host_profile_path", HOST_PROFILE),
            ("producer_commit", "bc9c9d9a08d8786baf408ed44b35bf3aa3b656e0"),
            ("producer_tree", "8cdd075e7e5d6bc0702bfad19ed9ec27cf69fdc6"),
            ("product_commit", "168036d74e08e7b49aad37907cf9b84b5dcc8456"),
            ("product_tree", "044cce09563a0384597e8529565ddff290bd4a6f"),
            ("artifact_manifest_sha256", "5080e24749071cdff797bf3eabcf39e6f3537591072d8104c663f5d899729bce"),
            ("artifact_binding_sha256", "4a24017dd968c0c0ca09484475e6c53fd24a4e76fe02ba7cdefd3b61a802ec4e"),
            ("artifact_entry_sha256", "bc150676896f9099512c6ac152c86295f2850d6176fe9063e80fb32f6076d9bb"),
            ("artifact_closure_sha256", "e7cda45a34741ce93df979274f8d557ce2fcf65412ba00c509ff83a8b8997b63"),
            ("producer_request_sha256", "413f081de312d55063bf8ec0807ff9c901609de67625f6b659bb59a5e847984e"),
            ("driver_tree_sha256", "82e2f5c6e71f182020cdf6c002843d1bf68710a7ae9e94481ef4c5ec23f99dcb"),
            ("driver_executable_sha256", "6e18a5309200082c5fac9d6bf4130880e09aee25984a6a934a8adcd70dd1fd54"),
            ("package_sha256", "dc5344c6b259d9739a07e2f7d61e2edd976ffe79e2a8d3eda8db234a2788841e"),
            ("predecessor_driver_executable_sha256", "25cd7a39366f0bfcd491cc1509f3f0c79ebe716899342d8feaa8ff9feb57ac4a"),
            ("host_profile_sha256", "3402737c0a228dd5a9485da469620384ccd00a9cef14650577a36f0bcf15d1a7"),
            ("host_handoff_sha256", "3cc0ef8ea8bdc51375cc2caa901b47dc87b5d75f294259cea1645207aaeefe0d"),
            ("host_payload_sha256", "dd5d41037fb1c750d5915d932b6fbf1875774fa8e35d4d785bb55310508b6972"),
            ("host_executable_sha256", "b427aa2fee0807339bf7cd59d3629c8f4110d0170481d0f35a77a7f0c45e4a70"),
            ("host_framework_sha256", "a326b18d2c6730e87dbd8134ab99283f6a0bd4cb3c0e7ab4d22c330134a4e59b"),
            ("host_info_plist_sha256", "9c6568c97ef11321edc1cc53a5fc070c491ea713a872fb6b119f777ce34e8b55"),
            ("host_launch_plist_sha256", "e8242cfa600bb5e62695cd954bcf59ce76a3884c5d4394accef4215ec642ee7a"),
            ("input_uid", "BlackHole2ch_UID"), ("output_uid", "BuiltInSpeakerDevice"),
            ("system_output_uid", "BuiltInSpeakerDevice"), ("normal_restart_budget", "1"),
            ("rollback_restart_budget", "1"), ("committed_host_pointer_path", HOST_POINTER),
];

impl Request {
    fn parse(bytes: &[u8], expected_sha: &str) -> Result<Self> {
        if bytes.is_empty() || bytes.len() > MAX_REQUEST || !bytes.ends_with(b"\n") || !hex(expected_sha, 64) {
            return Err("request extent or external digest is malformed".into());
        }
        if sha256(bytes) != expected_sha {
            return Err("request differs from external digest".into());
        }
        let text = std::str::from_utf8(bytes).map_err(|_| "request is not UTF-8")?;
        let mut fields = BTreeMap::new();
        for line in text.split_terminator('\n') {
            if line.is_empty() || !line.is_ascii() || line.bytes().any(|byte| byte < 32 || byte == 127) {
                return Err("request contains a control or non-ASCII field".into());
            }
            let (key, value) = line.split_once('=').ok_or("request field has no separator")?;
            if !FIELDS.contains(&key) || value.is_empty() || value.contains('=') || fields.insert(key.into(), value.into()).is_some() {
                return Err("request field is unknown, empty or duplicated".into());
            }
        }
        if fields.len() != FIELDS.len() {
            return Err("request field set is incomplete".into());
        }
        let request = Self { fields, sha256: expected_sha.into() };
        request.validate()?;
        Ok(request)
    }

    fn get(&self, key: &str) -> &str { &self.fields[key] }
    fn number(&self, key: &str) -> u64 { self.get(key).parse().expect("validated integer") }

    fn validate(&self) -> Result<()> {
        for (key, value) in EXACT_FIELDS {
            if self.get(key) != *value { return Err(format!("request {key} differs from reviewed scope")); }
        }
        let namespace = self.get("namespace");
        if !namespace.starts_with("driver-microphone-v9-") || namespace.len() > 64 || namespace.contains("--") ||
            namespace.ends_with('-') || !namespace.bytes().all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-') {
            return Err("request namespace is malformed".into());
        }
        for key in FIELDS.iter().filter(|key| key.ends_with("_sha256") || **key == "nonce" || **key == "host_nonce") {
            if !hex(self.get(key), 64) { return Err(format!("request {key} digest/nonce is malformed")); }
        }
        for key in ["guard_tooling_commit", "guard_tooling_tree"] {
            if !hex(self.get(key), 40) { return Err(format!("request {key} is malformed")); }
        }
        if self.get("guard_tooling_commit") == self.get("producer_commit") {
            return Err("current guard provenance must be distinct from immutable producer provenance".into());
        }
        for key in ["host_pid", "host_lock_device", "host_lock_inode", "predecessor_driver_instance",
                    "predecessor_driver_device", "predecessor_driver_inode", "timeout_seconds", "host_launchd_runs"] {
            positive(self.get(key)).map_err(|error| format!("request {key}: {error}"))?;
        }
        if self.number("host_pid") > i32::MAX as u64 || self.number("timeout_seconds") > 180 || self.get("nonce") == self.get("host_nonce") {
            return Err("request deadline, PID or nonce boundary is invalid".into());
        }
        for key in ["committed_host_result_path", "committed_host_readiness_path", "committed_host_journal_path"] {
            let path = self.get(key);
            if !canonical_path(path) || !path.starts_with(HOST_EVIDENCE) || path.contains("/migrations/") || path.contains("AudioStreamer") {
                return Err(format!("request {key} escapes the current-host evidence scope"));
            }
        }
        Ok(())
    }

    fn root_path(&self) -> String { format!("{ROOT_TRANSACTIONS}/{}", self.get("namespace")) }
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct Identity {
    device: u64, inode: u64, uid: u32, gid: u32, mode: u32, links: u64, size: u64,
    mtime: i64, mtime_nsec: i64, ctime: i64, ctime_nsec: i64,
}

impl Identity {
    fn of(metadata: &fs::Metadata) -> Self {
        Self { device: metadata.dev(), inode: metadata.ino(), uid: metadata.uid(), gid: metadata.gid(),
               mode: metadata.mode(), links: metadata.nlink(), size: metadata.size(), mtime: metadata.mtime(),
               mtime_nsec: metadata.mtime_nsec(), ctime: metadata.ctime(), ctime_nsec: metadata.ctime_nsec() }
    }
}

fn read_pinned(path: &Path, expected_sha: &str, owner: u32, mode: u32, maximum: usize) -> Result<Vec<u8>> {
    if !hex(expected_sha, 64) || fs::canonicalize(path).map_err(|_| "pinned file canonical path unavailable")? != path {
        return Err("pinned file alias/digest refused".into());
    }
    let before = fs::symlink_metadata(path).map_err(|_| "pinned file metadata unavailable")?;
    if !before.is_file() || before.uid() != owner || before.mode() & 0o777 != mode || before.nlink() != 1 || before.len() > maximum as u64 {
        return Err("pinned file owner/mode/type/extent refused".into());
    }
    let before = Identity::of(&before);
    let mut file = OpenOptions::new().read(true).custom_flags(NOFOLLOW).open(path).map_err(|_| "pinned file nofollow open failed")?;
    if Identity::of(&file.metadata().map_err(|_| "pinned descriptor metadata unavailable")?) != before {
        return Err("pinned file changed at open".into());
    }
    let mut bytes = Vec::new();
    Read::by_ref(&mut file).take(maximum as u64 + 1).read_to_end(&mut bytes).map_err(|_| "pinned file read failed")?;
    if bytes.len() as u64 != before.size || Identity::of(&file.metadata().map_err(|_| "pinned descriptor metadata unavailable")?) != before ||
        Identity::of(&fs::symlink_metadata(path).map_err(|_| "pinned path metadata unavailable")?) != before || sha256(&bytes) != expected_sha {
        return Err("pinned file changed at read/digest".into());
    }
    Ok(bytes)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum State {
    Prepared, Sealed, StopIntent, HostStopped, RetainIntent, PriorRetained, PublishIntent,
    CandidatePublished, RestartIntent, Reloaded, PublicProof, IdleProof, HostStartIntent,
    HostReady, CommitIntent, Irreversible, Committed, CommittedUnverified, RollbackIntent,
    RetireIntent, CandidateRetired, RestoreIntent, PriorRestored, RollbackRestartIntent,
    RollbackReloaded, RollbackHostStartIntent, RollbackHostReady, RolledBack,
}

impl State {
    fn name(self) -> &'static str {
        match self {
            Self::Prepared => "PREPARED", Self::Sealed => "SEALED", Self::StopIntent => "HOST_STOP_INTENT",
            Self::HostStopped => "HOST_STOPPED", Self::RetainIntent => "DRIVER_RETAIN_INTENT", Self::PriorRetained => "PRIOR_RETAINED",
            Self::PublishIntent => "DRIVER_PUBLISH_INTENT", Self::CandidatePublished => "CANDIDATE_PUBLISHED",
            Self::RestartIntent => "NORMAL_RESTART_INTENT", Self::Reloaded => "NORMAL_RESTART_OBSERVED",
            Self::PublicProof => "PUBLIC_NONCE_PROOF", Self::IdleProof => "AFTER_PROBE_IDLE_PROOF",
            Self::HostStartIntent => "HOST_START_INTENT", Self::HostReady => "HOST_READY", Self::CommitIntent => "COMMIT_INTENT",
            Self::Irreversible => "COMMIT_IRREVERSIBLE", Self::Committed => "COMMITTED_V9",
            Self::CommittedUnverified => "COMMITTED_V9_UNVERIFIED", Self::RollbackIntent => "ROLLBACK_INTENT",
            Self::RetireIntent => "CANDIDATE_RETIRE_INTENT", Self::CandidateRetired => "CANDIDATE_RETIRED",
            Self::RestoreIntent => "PRIOR_RESTORE_INTENT", Self::PriorRestored => "PRIOR_RESTORED",
            Self::RollbackRestartIntent => "ROLLBACK_RESTART_INTENT", Self::RollbackReloaded => "ROLLBACK_RESTART_OBSERVED",
            Self::RollbackHostStartIntent => "ROLLBACK_HOST_START_INTENT", Self::RollbackHostReady => "ROLLBACK_HOST_READY",
            Self::RolledBack => "ROLLED_BACK_EXACT_V8",
        }
    }
    fn parse(text: &str) -> Option<Self> {
        Self::all().iter().copied().find(|state| state.name() == text)
    }
    fn all() -> &'static [Self] {
        &[Self::Prepared, Self::Sealed, Self::StopIntent, Self::HostStopped, Self::RetainIntent,
          Self::PriorRetained, Self::PublishIntent, Self::CandidatePublished, Self::RestartIntent, Self::Reloaded,
          Self::PublicProof, Self::IdleProof, Self::HostStartIntent, Self::HostReady, Self::CommitIntent,
          Self::Irreversible, Self::Committed, Self::CommittedUnverified, Self::RollbackIntent, Self::RetireIntent,
          Self::CandidateRetired, Self::RestoreIntent, Self::PriorRestored, Self::RollbackRestartIntent,
          Self::RollbackReloaded, Self::RollbackHostStartIntent, Self::RollbackHostReady, Self::RolledBack]
    }
    fn committed(self) -> bool { matches!(self, Self::Irreversible | Self::Committed | Self::CommittedUnverified) }
    fn terminal(self) -> bool { matches!(self, Self::Committed | Self::CommittedUnverified | Self::RolledBack) }
}

fn legal(from: State, to: State) -> bool {
    use State::*;
    matches!((from, to), (Prepared, Sealed) | (Sealed, StopIntent) | (StopIntent, HostStopped) |
        (HostStopped, RetainIntent) | (RetainIntent, PriorRetained) | (PriorRetained, PublishIntent) |
        (PublishIntent, CandidatePublished) | (CandidatePublished, RestartIntent) | (RestartIntent, Reloaded) |
        (Reloaded, PublicProof) | (PublicProof, IdleProof) | (IdleProof, HostStartIntent) | (HostStartIntent, HostReady) |
        (HostReady, CommitIntent) | (CommitIntent, Irreversible) | (Irreversible, Committed) | (Irreversible, CommittedUnverified) |
        (RollbackIntent, RetireIntent) | (RetireIntent, CandidateRetired) | (CandidateRetired, RestoreIntent) |
        (RestoreIntent, PriorRestored) | (PriorRestored, RollbackRestartIntent) | (RollbackRestartIntent, RollbackReloaded) |
        (PriorRestored, RollbackHostStartIntent) | (RollbackReloaded, RollbackHostStartIntent) |
        (RollbackHostStartIntent, RollbackHostReady) | (RollbackHostReady, RolledBack)) ||
        (!from.committed() && !from.terminal() && to == RollbackIntent)
}

#[derive(Clone, Debug)]
struct Journal { request_sha: String, records: Vec<State> }

impl Journal {
    fn new(request: &Request) -> Self { Self { request_sha: request.sha256.clone(), records: Vec::new() } }
    fn last(&self) -> Option<State> { self.records.last().copied() }
    fn appended(&self, state: State) -> Result<Self> {
        if self.last().map_or(state != State::Prepared, |prior| !legal(prior, state)) { return Err("illegal journal transition".into()); }
        let mut next = self.clone(); next.records.push(state); Ok(next)
    }
    fn bytes(&self) -> Vec<u8> {
        let mut text = format!("OPENSTEAMER_MICROPHONE_V9_JOURNAL_V1\nrequest_sha256={}\n", self.request_sha);
        let mut previous = sha256(text.as_bytes());
        for (index, state) in self.records.iter().enumerate() {
            let row = format!("sequence={} state={} previous={previous}", index + 1, state.name());
            previous = sha256(row.as_bytes());
            text.push_str(&format!("{row} digest={previous}\n"));
        }
        text.into_bytes()
    }
    fn parse(bytes: &[u8], request: &Request) -> Result<Self> {
        if bytes.len() > MAX_REQUEST || !bytes.ends_with(b"\n") { return Err("journal extent/torn tail refused".into()); }
        let text = std::str::from_utf8(bytes).map_err(|_| "journal UTF-8 refused")?;
        let mut rows = text.lines();
        if rows.next() != Some("OPENSTEAMER_MICROPHONE_V9_JOURNAL_V1") || rows.next() != Some(format!("request_sha256={}", request.sha256).as_str()) {
            return Err("journal request/header differs".into());
        }
        let mut journal = Self::new(request);
        for row in rows {
            let fields: Vec<_> = row.split(' ').collect();
            if fields.len() != 4 { return Err("journal row fields differ".into()); }
            let state = fields[1].strip_prefix("state=").and_then(State::parse).ok_or("journal state unknown")?;
            journal = journal.appended(state)?;
            let canonical = journal.bytes();
            if canonical.split(|byte| *byte == b'\n').rev().nth(1) != Some(row.as_bytes()) { return Err("journal sequence/hash differs".into()); }
        }
        if journal.bytes() != bytes { return Err("journal bytes are not canonical".into()); }
        Ok(journal)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum DriverLocation { PriorCanonical, CandidateCanonical, CanonicalAbsent, Unknown }
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum LoadedDriver { Prior, Candidate, Unknown }

#[derive(Clone, Debug)]
struct Facts {
    identity_exact: bool, fresh_gate: bool, root_sealed: bool, host_present: bool,
    host_ready_exact: bool, driver: DriverLocation, prior_retained_exact: bool,
    loaded: LoadedDriver, normal_restarts: u8, rollback_restarts: u8,
    public_nonce_both_orders: bool, complete_v2_idle_with_history: bool,
    route_notifications: u64, route_teardown_clean: bool,
}

impl Facts {
    fn invariant(&self) -> Result<()> {
        if !self.identity_exact || self.normal_restarts > 1 || self.rollback_restarts > 1 ||
            self.rollback_restarts > self.normal_restarts || self.driver == DriverLocation::Unknown || self.loaded == LoadedDriver::Unknown {
            return Err("ambiguous identity/driver/restart evidence".into());
        }
        Ok(())
    }
    fn committed(&self) -> bool {
        self.invariant().is_ok() && self.fresh_gate && self.root_sealed && self.driver == DriverLocation::CandidateCanonical && self.loaded == LoadedDriver::Candidate &&
            self.normal_restarts == 1 && self.rollback_restarts == 0 && self.host_present && self.host_ready_exact &&
            self.public_nonce_both_orders && self.complete_v2_idle_with_history && self.route_notifications == 0 && self.route_teardown_clean
    }
    fn restored(&self) -> bool {
        self.invariant().is_ok() && self.normal_restarts==self.rollback_restarts && self.fresh_gate && self.driver == DriverLocation::PriorCanonical && self.loaded == LoadedDriver::Prior &&
            self.host_present && self.host_ready_exact && self.route_notifications == 0 && self.route_teardown_clean
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Effect { Seal, StopHost, RetainPrior, Publish, NormalRestart, PublicProbe, IdleProbe, StartHost, RetireCandidate, RestorePrior, RollbackRestart, Audit }

trait Backend {
    fn live_admission(&self) -> bool;
    fn observe(&mut self) -> Result<Facts>;
    fn persist(&mut self, journal: &Journal) -> Result<()>;
    fn effect(&mut self, effect: Effect) -> Result<()>;
    fn retain_admission_refusal(&mut self, _reason: &str) -> Result<()> { Ok(()) }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Terminal { Refused, RecoveryRequired, Committed, CommittedUnverified, RolledBack }
impl Terminal {
    fn name(self) -> &'static str {
        match self { Self::Refused => "REFUSED", Self::RecoveryRequired => "RECOVERY_REQUIRED",
            Self::Committed => "COMMITTED_V9", Self::CommittedUnverified => "COMMITTED_V9_UNVERIFIED", Self::RolledBack => "ROLLED_BACK_EXACT_V8" }
    }
}

struct Transaction<'a, B: Backend> { backend: &'a mut B, journal: Journal }

impl<'a, B: Backend> Transaction<'a, B> {
    fn record(&mut self, state: State) -> Result<()> {
        let next = self.journal.appended(state)?;
        self.backend.persist(&next)?;
        self.journal = next;
        Ok(())
    }
    fn step(&mut self, intent: State, effect: Effect, complete: State) -> Result<()> {
        self.record(intent)?;
        self.guard_effect(effect)?;
        self.backend.effect(effect)?;
        self.record(complete)
    }
    fn guard_effect(&mut self, effect: Effect) -> Result<()> {
        let facts = self.backend.observe()?;
        facts.invariant()?;
        if !facts.root_sealed || !facts.fresh_gate || facts.route_notifications != 0 {
            return Err("fresh sealed identity/quiescence/route gate changed".into());
        }
        let allowed = match effect {
            Effect::StopHost => facts.host_present,
            Effect::RetainPrior => !facts.host_present && facts.driver == DriverLocation::PriorCanonical && !facts.prior_retained_exact,
            Effect::Publish => !facts.host_present && facts.driver == DriverLocation::CanonicalAbsent && facts.prior_retained_exact,
            Effect::NormalRestart => !facts.host_present && facts.driver == DriverLocation::CandidateCanonical &&
                facts.loaded == LoadedDriver::Prior && facts.normal_restarts == 0 && facts.rollback_restarts == 0,
            Effect::PublicProbe => !facts.host_present && facts.driver == DriverLocation::CandidateCanonical &&
                facts.loaded == LoadedDriver::Candidate && facts.normal_restarts == 1 && facts.rollback_restarts == 0,
            Effect::IdleProbe => !facts.host_present && facts.public_nonce_both_orders && facts.driver == DriverLocation::CandidateCanonical &&
                facts.loaded == LoadedDriver::Candidate && facts.normal_restarts == 1 && facts.rollback_restarts == 0,
            Effect::StartHost => !facts.host_present && facts.driver == DriverLocation::CandidateCanonical &&
                facts.loaded == LoadedDriver::Candidate && facts.public_nonce_both_orders && facts.complete_v2_idle_with_history,
            _ => false,
        };
        if allowed { Ok(()) } else { Err("effect preconditions changed at durable intent boundary".into()) }
    }
    fn guard_recovery(&mut self, effect: Effect) -> Result<()> {
        let facts=self.backend.observe()?; facts.invariant()?;
        if !facts.root_sealed || !facts.fresh_gate || facts.route_notifications!=0 {
            return Err("fresh sealed rollback identity/quiescence/route gate changed".into());
        }
        let allowed=match effect {
            Effect::StopHost => facts.host_present,
            Effect::RetireCandidate => !facts.host_present && facts.driver==DriverLocation::CandidateCanonical && facts.prior_retained_exact,
            Effect::RestorePrior => !facts.host_present && facts.driver==DriverLocation::CanonicalAbsent && facts.prior_retained_exact,
            Effect::RollbackRestart => !facts.host_present && facts.driver==DriverLocation::PriorCanonical &&
                facts.loaded==LoadedDriver::Candidate && facts.normal_restarts==1 && facts.rollback_restarts==0,
            Effect::StartHost => !facts.host_present && facts.driver==DriverLocation::PriorCanonical && facts.loaded==LoadedDriver::Prior,
            _ => false,
        };
        if allowed {Ok(())} else {Err("rollback effect preconditions changed at durable intent boundary".into())}
    }
    fn run(&mut self) -> Terminal {
        if !self.backend.live_admission() { return Terminal::Refused; }
        let facts = match self.backend.observe() {
            Ok(value) => value,
            Err(reason) => return if self.backend.retain_admission_refusal(&reason).is_ok() { Terminal::Refused } else { Terminal::RecoveryRequired },
        };
        if !facts.fresh_gate || facts.invariant().is_err() || facts.driver != DriverLocation::PriorCanonical || facts.loaded != LoadedDriver::Prior ||
            !facts.host_present || !facts.host_ready_exact || facts.normal_restarts != 0 || facts.rollback_restarts != 0 || facts.route_notifications != 0 {
            return if self.backend.retain_admission_refusal("initial admission predicates differ").is_ok() { Terminal::Refused } else { Terminal::RecoveryRequired };
        }
        let attempt = (|| -> Result<()> {
            self.record(State::Prepared)?;
            self.backend.effect(Effect::Seal)?;
            self.record(State::Sealed)?;
            self.step(State::StopIntent, Effect::StopHost, State::HostStopped)?;
            self.step(State::RetainIntent, Effect::RetainPrior, State::PriorRetained)?;
            self.step(State::PublishIntent, Effect::Publish, State::CandidatePublished)?;
            self.step(State::RestartIntent, Effect::NormalRestart, State::Reloaded)?;
            self.guard_effect(Effect::PublicProbe)?;
            self.backend.effect(Effect::PublicProbe)?;
            self.record(State::PublicProof)?;
            self.guard_effect(Effect::IdleProbe)?;
            self.backend.effect(Effect::IdleProbe)?;
            self.record(State::IdleProof)?;
            self.step(State::HostStartIntent, Effect::StartHost, State::HostReady)?;
            self.backend.effect(Effect::Audit)?;
            if !self.backend.observe()?.committed() { return Err("precommit facts incomplete".into()); }
            self.record(State::CommitIntent)?;
            self.record(State::Irreversible)?;
            Ok(())
        })();
        if attempt.is_err() {
            // A failed durable append can have committed its bytes. Only a reloaded
            // root journal, not this stale in-memory prefix, can authorize recovery.
            return Terminal::RecoveryRequired;
        }
        self.finish_committed()
    }
    fn finish_committed(&mut self) -> Terminal {
        let success = self.backend.effect(Effect::Audit).is_ok() && self.backend.observe().map(|facts| facts.committed()).unwrap_or(false);
        let state = if success { State::Committed } else { State::CommittedUnverified };
        if self.record(state).is_err() { Terminal::RecoveryRequired }
        else if success { Terminal::Committed } else { Terminal::CommittedUnverified }
    }
    fn resume(&mut self) -> Terminal {
        if !self.backend.live_admission() { return Terminal::Refused; }
        let last = match self.journal.last() { Some(value) => value, None => return Terminal::Refused };
        if last.committed() {
            if last == State::Irreversible { return self.finish_committed(); }
            let audited=self.backend.effect(Effect::Audit).is_ok();
            return if last == State::Committed && audited && self.backend.observe().map(|facts| facts.committed()).unwrap_or(false) {
                Terminal::Committed
            } else { Terminal::CommittedUnverified };
        }
        if last == State::RolledBack {
            return if self.backend.effect(Effect::Audit).is_ok()&&self.backend.observe().map(|facts| facts.restored()).unwrap_or(false) { Terminal::RolledBack } else { Terminal::RecoveryRequired };
        }
        let recovery = (|| -> Result<()> {
            let mut facts = self.backend.observe()?; facts.invariant()?;
            if !matches!(last, State::RollbackIntent | State::RetireIntent | State::CandidateRetired | State::RestoreIntent |
                         State::PriorRestored | State::RollbackRestartIntent | State::RollbackReloaded |
                         State::RollbackHostStartIntent | State::RollbackHostReady) {
                self.record(State::RollbackIntent)?;
            }
            if facts.host_present && matches!(self.journal.last(), Some(State::RollbackIntent | State::RetireIntent |
                State::CandidateRetired | State::RestoreIntent | State::PriorRestored | State::RollbackRestartIntent)) &&
                !(facts.driver == DriverLocation::PriorCanonical && facts.loaded == LoadedDriver::Prior && facts.host_ready_exact) {
                self.guard_recovery(Effect::StopHost)?;
                self.backend.effect(Effect::StopHost)?;
            }
            if matches!(self.journal.last(), Some(State::RollbackIntent | State::RetireIntent)) {
                if self.journal.last() == Some(State::RollbackIntent) { self.record(State::RetireIntent)?; }
                facts = self.backend.observe()?; facts.invariant()?;
                if facts.driver == DriverLocation::CandidateCanonical { self.guard_recovery(Effect::RetireCandidate)?; self.backend.effect(Effect::RetireCandidate)?; }
                self.record(State::CandidateRetired)?;
            }
            if matches!(self.journal.last(), Some(State::CandidateRetired | State::RestoreIntent)) {
                if self.journal.last() == Some(State::CandidateRetired) { self.record(State::RestoreIntent)?; }
                facts = self.backend.observe()?; facts.invariant()?;
                if facts.driver == DriverLocation::CanonicalAbsent {
                    if !facts.prior_retained_exact { return Err("exact retained predecessor unavailable".into()); }
                    self.guard_recovery(Effect::RestorePrior)?;
                    self.backend.effect(Effect::RestorePrior)?;
                }
                if self.backend.observe()?.driver != DriverLocation::PriorCanonical { return Err("predecessor restore is not exact".into()); }
                self.record(State::PriorRestored)?;
            }
            facts = self.backend.observe()?; facts.invariant()?;
            if matches!(self.journal.last(), Some(State::PriorRestored | State::RollbackRestartIntent)) && facts.loaded == LoadedDriver::Candidate {
                if facts.normal_restarts != 1 || facts.rollback_restarts != 0 { return Err("rollback restart budget not available".into()); }
                if self.journal.last() == Some(State::PriorRestored) { self.record(State::RollbackRestartIntent)?; }
                self.guard_recovery(Effect::RollbackRestart)?;
                self.backend.effect(Effect::RollbackRestart)?;
                self.record(State::RollbackReloaded)?;
            } else if self.journal.last() == Some(State::RollbackRestartIntent) && facts.loaded == LoadedDriver::Prior && facts.rollback_restarts == 1 {
                self.record(State::RollbackReloaded)?;
            }
            if matches!(self.journal.last(), Some(State::PriorRestored | State::RollbackReloaded | State::RollbackHostStartIntent)) {
                if self.journal.last() != Some(State::RollbackHostStartIntent) { self.record(State::RollbackHostStartIntent)?; }
                if !self.backend.observe()?.host_present { self.guard_recovery(Effect::StartHost)?; self.backend.effect(Effect::StartHost)?; }
                self.record(State::RollbackHostReady)?;
            }
            self.backend.effect(Effect::Audit)?;
            if !self.backend.observe()?.restored() { return Err("rollback terminal proof incomplete".into()); }
            self.record(State::RolledBack)
        })();
        if recovery.is_ok() { Terminal::RolledBack } else { Terminal::RecoveryRequired }
    }
}

#[cfg(any(target_os = "macos", test))]
fn finalize_restart_report<B, F: FnOnce(&mut B) -> Result<()>, C: FnOnce(&mut B) -> Result<(u8,u8)>>(backend: &mut B, finalize: F, counts: C) -> Result<(u8,u8)> {
    finalize(backend)?;
    counts(backend)
}

struct MissingOsBackend;
impl Backend for MissingOsBackend {
    fn live_admission(&self) -> bool { false }
    fn observe(&mut self) -> Result<Facts> { Err("OS proof adapter is not implemented".into()) }
    fn persist(&mut self, _: &Journal) -> Result<()> { Err("root durable storage adapter is not implemented".into()) }
    fn effect(&mut self, _: Effect) -> Result<()> { Err("privileged effect adapter is not implemented".into()) }
}

// These descriptor primitives are exercised only in private UID501 fixtures.
// They are not a live Backend: process-generation and nonce-PCM proof adapters
// must be implemented and independently reviewed before privileged admission.
#[cfg(target_os = "macos")]
mod sealed_fs {
    use super::*;
    use std::ffi::CString;
    use std::fs::File;
    use std::io::Write;
    use std::os::fd::{AsRawFd, FromRawFd};
    use std::path::PathBuf;

    const DIRECTORY: i32 = 0x0010_0000;
    const CLOEXEC: i32 = 0x0100_0000;
    const CREATE: i32 = 0x0200;
    const EXCLUSIVE: i32 = 0x0800;
    const RENAME_EXCLUSIVE: u32 = 4;

    unsafe extern "C" {
        // Darwin openat is variadic. Declaring a fixed fourth argument corrupts
        // creation modes on arm64 because variadic values use a different ABI.
        fn openat(dir: i32, name: *const i8, flags: i32, ...) -> i32;
        fn renameatx_np(from: i32, old: *const i8, to: i32, new: *const i8, flags: u32) -> i32;
        fn acl_get_fd_np(fd: i32, kind: i32) -> *mut std::ffi::c_void;
        fn acl_get_entry(acl: *mut std::ffi::c_void, entry_id: i32, entry: *mut *mut std::ffi::c_void) -> i32;
        fn acl_free(value: *mut std::ffi::c_void) -> i32;
        fn __error() -> *mut i32;
    }

    fn name(value: &str) -> Result<CString> {
        if value.is_empty() || value == "." || value == ".." || value.contains('/') || value.len() > 255 {
            return Err("descriptor-relative name refused".into());
        }
        CString::new(value).map_err(|_| "descriptor name contains NUL".into())
    }

    pub(super) fn no_acl(file: &File) -> Result<()> {
        unsafe { *__error() = 0; }
        let acl = unsafe { acl_get_fd_np(file.as_raw_fd(), 0x100) };
        let error = unsafe { *__error() };
        if acl.is_null() { return if error == 2 { Ok(()) } else { Err(format!("ACL absence unproved: errno={error}")) }; }
        let mut entry = std::ptr::null_mut();
        let count = unsafe { acl_get_entry(acl, 0, &mut entry) };
        let released = unsafe { acl_free(acl) };
        Err(format!("non-null extended ACL refused: status={count} release={released}"))
    }

    fn node_equal(left: &Identity, right: &Identity) -> bool {
        left.device == right.device && left.inode == right.inode && left.uid == right.uid && left.gid == right.gid &&
            left.mode == right.mode && left.links == right.links && left.size == right.size
    }

    pub(super) struct HeldDirectory { file: File, path: PathBuf, identity: Identity }
    pub(super) struct RootLock{file:File,path:PathBuf,identity:Identity}
    impl RootLock{
        pub(super) fn acquire(parent:&HeldDirectory)->Result<Self>{
            if parent.identity.uid!=0||parent.identity.gid!=0{return Err("controller lock requires exact root-owned parent".into());}
            Self::acquire_inner(parent)
        }
        fn acquire_inner(parent:&HeldDirectory)->Result<Self>{
            unsafe extern "C"{fn flock(fd:i32,operation:i32)->i32;}
            let file=parent.child(".controller.lock",2|CREATE,0o600)?;let metadata=file.metadata().map_err(|_|"controller lock metadata unavailable")?;
            if !metadata.is_file()||metadata.uid()!=parent.identity.uid||metadata.gid()!=parent.identity.gid||metadata.mode()&0o7777!=0o600||metadata.nlink()!=1||metadata.len()!=0{return Err("controller lock owner/type/mode/extent refused".into());}
            no_acl(&file)?;if unsafe{flock(file.as_raw_fd(),2|4)}!=0{return Err("another staging/runtime controller owns the exact lock".into());}
            file.sync_all().map_err(|_|"controller lock sync failed")?;parent.file.sync_all().map_err(|_|"controller lock parent sync failed")?;
            let lock=Self{file,path:parent.path.join(".controller.lock"),identity:Identity::of(&metadata)};lock.revalidate()?;Ok(lock)
        }
        #[cfg(test)]pub(super) fn acquire_fixture(parent:&HeldDirectory)->Result<Self>{Self::acquire_inner(parent)}
        pub(super) fn revalidate(&self)->Result<()>{
            if self.identity!=Identity::of(&self.file.metadata().map_err(|_|"held controller lock stat unavailable")?)||self.identity!=Identity::of(&fs::symlink_metadata(&self.path).map_err(|_|"controller lock path disappeared")?){return Err("held controller lock replaced or modified".into());}no_acl(&self.file)
        }
    }

    impl HeldDirectory {
        pub(super) fn descriptor(&self)->&File{&self.file}
        pub(super) fn private_uid501_directory(&self,value:&str)->Result<File>{
            self.revalidate()?;let child_name=name(value)?;
            unsafe extern "C"{fn mkdirat(fd:i32,path:*const std::ffi::c_char,mode:u16)->i32;fn fchown(fd:i32,uid:u32,gid:u32)->i32;}
            if unsafe{mkdirat(self.file.as_raw_fd(),child_name.as_ptr(),0o700)}!=0{return Err("private proof directory exclusive creation failed".into());}
            let file=self.child(value,DIRECTORY,0)?;
            let metadata=file.metadata().map_err(|_|"private proof directory stat failed")?;
            if !metadata.is_dir()||metadata.uid()!=0||metadata.gid()!=0||metadata.mode()&0o7777!=0o700{return Err("new private proof directory ownership/mode differs".into());}
            no_acl(&file)?;
            if unsafe{fchown(file.as_raw_fd(),501,20)}!=0{return Err("private original-UID proof directory ownership failed".into());}
            file.sync_all().map_err(|_|"private proof directory sync failed")?;self.file.sync_all().map_err(|_|"private proof parent sync failed")?;self.revalidate()?;Ok(file)
        }
        pub(super) fn capture(path: &Path, owner: u32, group: u32, mode: u32) -> Result<Self> {
            if fs::canonicalize(path).map_err(|_| "directory canonical path unavailable")? != path {
                return Err("directory alias refused".into());
            }
            let file = OpenOptions::new().read(true).custom_flags(NOFOLLOW | DIRECTORY | CLOEXEC).open(path)
                .map_err(|_| "directory nofollow descriptor unavailable")?;
            let metadata = file.metadata().map_err(|_| "directory descriptor metadata unavailable")?;
            let identity = Identity::of(&metadata);
            if !metadata.is_dir() || identity.uid != owner || identity.gid != group || identity.mode & 0o7777 != mode {
                return Err("directory owner/group/mode/type refused".into());
            }
            no_acl(&file)?;
            let held = Self { file, path:path.to_path_buf(), identity };
            held.revalidate()?;
            Ok(held)
        }

        pub(super) fn revalidate(&self) -> Result<()> {
            let handle = Identity::of(&self.file.metadata().map_err(|_| "held directory metadata unavailable")?);
            let path = Identity::of(&fs::symlink_metadata(&self.path).map_err(|_| "held directory path disappeared")?);
            // Owned child mutations change directory size/link counts/times;
            // identity, type, access policy and descriptor-path binding may not.
            for actual in [&handle, &path] {
                if actual.device != self.identity.device || actual.inode != self.identity.inode ||
                    actual.uid != self.identity.uid || actual.gid != self.identity.gid || actual.mode != self.identity.mode {
                    return Err("held directory was replaced or access changed".into());
                }
            }
            no_acl(&self.file)
        }

        fn child(&self, value: &str, flags: i32, mode: u32) -> Result<File> {
            self.revalidate()?;
            let value = name(value)?;
            let fd = unsafe { openat(self.file.as_raw_fd(), value.as_ptr(), flags | NOFOLLOW | CLOEXEC, mode) };
            if fd < 0 { return Err(format!("descriptor-relative open failed: {}", std::io::Error::last_os_error())); }
            let file = unsafe { File::from_raw_fd(fd) };
            self.revalidate()?;
            Ok(file)
        }

        fn read(&self, value: &str, expected: &str, maximum: usize) -> Result<Vec<u8>> {
            let mut file = self.child(value, 0, 0)?;
            let before = Identity::of(&file.metadata().map_err(|_| "relative result stat unavailable")?);
            if before.uid != self.identity.uid || before.gid != self.identity.gid || before.mode & 0o7777 != 0o400 ||
                before.mode & 0o170000 != 0o100000 || before.links != 1 || before.size > maximum as u64 {
                return Err("relative result ownership/type/mode/extent refused".into());
            }
            no_acl(&file)?;
            let mut bytes = Vec::new();
            Read::by_ref(&mut file).take(maximum as u64+1).read_to_end(&mut bytes).map_err(|_| "relative result read failed")?;
            if before != Identity::of(&file.metadata().map_err(|_| "relative result after-stat failed")?) || bytes.len() as u64 != before.size || sha256(&bytes) != expected {
                return Err("relative result changed or digest differs".into());
            }
            let path = self.path.join(value);
            if before != Identity::of(&fs::symlink_metadata(path).map_err(|_| "relative result path lost")?) {
                return Err("relative result path replaced".into());
            }
            self.revalidate()?;
            Ok(bytes)
        }

        pub(super) fn exclusive_retain(&self, source: &str, destination: &HeldDirectory, target: &str, expected: &Identity) -> Result<()> {
            self.revalidate()?; destination.revalidate()?;
            if self.identity.device != destination.identity.device || expected.device != self.identity.device {
                return Err("exclusive retention crosses filesystems".into());
            }
            let source_name = name(source)?; let target_name = name(target)?;
            let observed = Identity::of(&fs::symlink_metadata(self.path.join(source)).map_err(|_| "retained source absent")?);
            if observed != *expected || observed.mode & 0o170000 == 0o120000 {
                return Err("retained source identity changed or is symlink".into());
            }
            super::os::supervisor_check()?;
            let status = unsafe { renameatx_np(self.file.as_raw_fd(), source_name.as_ptr(), destination.file.as_raw_fd(), target_name.as_ptr(), RENAME_EXCLUSIVE) };
            if status != 0 { return Err(format!("exclusive retain failed: {}",std::io::Error::last_os_error())); }
            self.file.sync_all().map_err(|_| "source retention parent fsync failed")?;
            destination.file.sync_all().map_err(|_| "destination retention parent fsync failed")?;
            self.revalidate()?; destination.revalidate()?;
            let retained = Identity::of(&fs::symlink_metadata(destination.path.join(target)).map_err(|_| "retained inode disappeared")?);
            let source_absent=matches!(fs::symlink_metadata(self.path.join(source)),Err(error) if error.kind()==std::io::ErrorKind::NotFound);
            if !node_equal(expected,&retained) || !source_absent {
                return Err("retained inode or exclusive absence differs".into());
            }
            Ok(())
        }

        pub(super) fn persist(&self, journal: &Journal) -> Result<()> {
            if journal.records.is_empty() || journal.records.len() > 64 { return Err("journal sequence extent refused".into()); }
            let bytes = journal.bytes();
            let sequence = journal.records.len();
            let pending = format!("pending-{sequence:03}");
            let published = format!("journal-{sequence:03}");
            let mut file = self.child(&pending, 1 | CREATE | EXCLUSIVE, 0o400)?;
            let identity = Identity::of(&file.metadata().map_err(|_| "pending journal stat failed")?);
            if identity.uid != self.identity.uid || identity.gid != self.identity.gid || identity.mode & 0o7777 != 0o400 || identity.links != 1 {
                return Err("pending journal ownership/mode refused".into());
            }
            no_acl(&file)?;
            file.write_all(&bytes).map_err(|_| "pending journal write failed")?;
            file.sync_all().map_err(|_| "pending journal durable sync failed")?;
            let written = Identity::of(&file.metadata().map_err(|_| "pending written journal stat failed")?);
            drop(file);
            if self.read(&pending,&sha256(&bytes),MAX_REQUEST)? != bytes { return Err("pending journal readback differs".into()); }
            self.exclusive_retain(&pending,self,&published,&written)?;
            if self.read(&published,&sha256(&bytes),MAX_REQUEST)? != bytes { return Err("published journal readback differs".into()); }
            Ok(())
        }
        pub(super) fn write_record(&self,value:&str,bytes:&[u8],mode:u32)->Result<()> {
            if bytes.is_empty()||bytes.len()>8*1024*1024||!matches!(mode,0o400|0o600){return Err("sealed record extent/mode refused".into());}
            let mut file=self.child(value,1|CREATE|EXCLUSIVE,mode)?;
            let metadata=file.metadata().map_err(|_|"sealed record metadata unavailable")?;
            if metadata.uid()!=self.identity.uid||metadata.gid()!=self.identity.gid||metadata.mode()&0o7777!=mode||metadata.nlink()!=1{return Err("sealed record ownership/mode refused".into());}
            no_acl(&file)?;file.write_all(bytes).map_err(|_|"sealed record write failed")?;file.sync_all().map_err(|_|"sealed record sync failed")?;
            self.file.sync_all().map_err(|_|"sealed record parent sync failed")?;self.revalidate()
        }

        pub(super) fn load_journal(&self, request: &Request, count: usize) -> Result<Journal> {
            if count == 0 || count > 64 { return Err("journal count refused".into()); }
            let mut previous = Journal::new(request);
            for index in 1..=count {
                let value = format!("journal-{index:03}");
                let mut file = self.child(&value,0,0)?;
                let metadata = file.metadata().map_err(|_| "journal generation metadata unavailable")?;
                if !metadata.is_file() || metadata.uid()!=self.identity.uid || metadata.gid()!=self.identity.gid || metadata.mode()&0o7777!=0o400 || metadata.nlink()!=1 || metadata.len()>MAX_REQUEST as u64 {
                    return Err("journal generation ownership/mode/extent refused".into());
                }
                let mut bytes=Vec::new(); Read::by_ref(&mut file).take(MAX_REQUEST as u64+1).read_to_end(&mut bytes).map_err(|_| "journal generation read unavailable")?;
                self.read(&value,&sha256(&bytes),MAX_REQUEST)?;
                let journal=Journal::parse(&bytes,request)?;
                if journal.records.len()!=index || journal.records[..index-1]!=previous.records { return Err("journal generation prefix changed".into()); }
                previous=journal;
            }
            Ok(previous)
        }
        pub(super) fn reconcile_journal(&self,request:&Request)->Result<Journal>{
            self.revalidate()?;let mut published=Vec::new();let mut pending=Vec::new();
            for entry in fs::read_dir(&self.path).map_err(|_|"journal inventory unavailable")?{
                let entry=entry.map_err(|_|"journal entry unavailable")?;let name=entry.file_name().into_string().map_err(|_|"journal name encoding differs")?;
                let(kind,number)=name.split_once('-').ok_or("unknown journal entry")?;
                if !matches!(kind,"journal"|"pending")||number.len()!=3||!number.bytes().all(|byte|byte.is_ascii_digit()){return Err("unknown journal entry refused".into());}
                let sequence=number.parse::<usize>().map_err(|_|"journal sequence malformed")?;if !(1..=64).contains(&sequence){return Err("journal sequence exceeds bound".into());}
                if kind=="journal"{published.push(sequence);}else{pending.push(sequence);}
            }
            published.sort();pending.sort();if published!=(1..=published.len()).collect::<Vec<_>>()||pending.len()>1{return Err("journal gaps or multiple pending generations refused".into());}
            let mut journal=if published.is_empty(){Journal::new(request)}else{self.load_journal(request,published.len())?};
            if let Some(sequence)=pending.first().copied(){
                if sequence!=published.len()+1{return Err("pending journal is not exact next prefix".into());}
                let name=format!("pending-{sequence:03}");let mut file=self.child(&name,0,0)?;let metadata=file.metadata().map_err(|_|"pending journal metadata unavailable")?;
                if !metadata.is_file()||metadata.uid()!=self.identity.uid||metadata.gid()!=self.identity.gid||metadata.mode()&0o7777!=0o400||metadata.nlink()!=1||metadata.len()>MAX_REQUEST as u64{return Err("pending journal identity/extent refused".into());}
                no_acl(&file)?;let mut bytes=Vec::new();Read::by_ref(&mut file).take(MAX_REQUEST as u64+1).read_to_end(&mut bytes).map_err(|_|"pending journal read unavailable")?;
                self.read(&name,&sha256(&bytes),MAX_REQUEST)?;let next=Journal::parse(&bytes,request)?;
                if next.records.len()!=sequence||next.records[..sequence-1]!=journal.records{return Err("pending journal prefix/extent differs".into());}
                file.sync_all().map_err(|_|"pending journal resync failed")?;
                let identity=Identity::of(&file.metadata().map_err(|_|"pending journal restat unavailable")?);
                self.exclusive_retain(&name,self,&format!("journal-{sequence:03}"),&identity)?;journal=self.load_journal(request,sequence)?;
            }
            if journal.last().is_none(){return Err("resume requires an actual durable journal".into());}Ok(journal)
        }
    }

    // Held all the way to '/', rather than just canonicalizing a leaf. Every
    // ancestor of the fixed root namespace must be root-owned and non-writable.
    pub(super) fn root_ancestry(request: &Request) -> Result<Vec<HeldDirectory>> {
        root_ancestry_path(Path::new(&request.root_path()),0o700)
    }
    pub(super) fn root_ancestry_path(root:&Path,final_mode:u32)->Result<Vec<HeldDirectory>> {
        let mut paths=vec![PathBuf::from("/")];
        let mut cursor=PathBuf::from("/");
        for part in root.components().skip(1) { cursor.push(part.as_os_str()); paths.push(cursor.clone()); }
        let mut held=Vec::new();
        for path in paths {
            let metadata=fs::symlink_metadata(&path).map_err(|_| "root ancestry is not presealed")?;
            let mode=metadata.mode()&0o7777;
            if mode&0o7022!=0 { return Err("root ancestry permits external writes or special permissions".into()); }
            let group=if path==Path::new("/Library/Application Support"){80}else{0};
            held.push(HeldDirectory::capture(&path,0,group,mode)?);
        }
        if held.last().unwrap().identity.mode&0o7777!=final_mode { return Err("root namespace leaf mode differs".into()); }
        for directory in &held { directory.revalidate()?; }
        Ok(held)
    }
}

fn sha256(input: &[u8]) -> String {
    const K: [u32; 64] = [
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
        0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
        0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
        0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
        0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
        0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
        0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];
    let mut h = [0x6a09e667u32,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19];
    let mut bytes = input.to_vec(); let length = (bytes.len() as u64) * 8;
    bytes.push(0x80); while bytes.len() % 64 != 56 { bytes.push(0); } bytes.extend_from_slice(&length.to_be_bytes());
    for chunk in bytes.chunks_exact(64) {
        let mut w = [0u32;64];
        for (i, word) in chunk.chunks_exact(4).enumerate() { w[i] = u32::from_be_bytes(word.try_into().unwrap()); }
        for i in 16..64 {
            let s0 = w[i-15].rotate_right(7) ^ w[i-15].rotate_right(18) ^ (w[i-15] >> 3);
            let s1 = w[i-2].rotate_right(17) ^ w[i-2].rotate_right(19) ^ (w[i-2] >> 10);
            w[i] = w[i-16].wrapping_add(s0).wrapping_add(w[i-7]).wrapping_add(s1);
        }
        let [mut a,mut b,mut c,mut d,mut e,mut f,mut g,mut z] = h;
        for i in 0..64 {
            let t1 = z.wrapping_add(e.rotate_right(6)^e.rotate_right(11)^e.rotate_right(25)).wrapping_add((e&f)^(!e&g)).wrapping_add(K[i]).wrapping_add(w[i]);
            let t2 = (a.rotate_right(2)^a.rotate_right(13)^a.rotate_right(22)).wrapping_add((a&b)^(a&c)^(b&c));
            z=g;g=f;f=e;e=d.wrapping_add(t1);d=c;c=b;b=a;a=t1.wrapping_add(t2);
        }
        for (slot, value) in h.iter_mut().zip([a,b,c,d,e,f,g,z]) { *slot = slot.wrapping_add(value); }
    }
    h.iter().map(|value| format!("{value:08x}")).collect()
}

fn cli(arguments: &[String]) -> i32 {
    #[cfg(target_os="macos")]
    if arguments.first().map(String::as_str)==Some("--seal-authorized-v9-inputs"){
        if arguments.len()!=6||!os::OwnedChild::root_identity(){eprintln!("sealed v9 staging requires exact six arguments and real/effective root identity");return 64;}
        // Source activation is not runtime consent: the exact root bootstrap,
        // external pins and owned bounded supervision remain mandatory.
        const STAGING_ADMISSION:bool=true;
        if !STAGING_ADMISSION { eprintln!("STAGING_ADMISSION_DISABLED_PENDING_WHOLE_PATH_REVIEW");return 78; }
        let result=(||->Result<()> {
            if !private_request_path(&arguments[1]){return Err("staging request path is outside the private internal supervisor role".into());}
            if !guard_build_proof_path(&arguments[3]){return Err("staging build proof is outside its fixed private builder role".into());}
            let request_parents=seal::held_internal_namespace(Path::new(&arguments[1]).parent().ok_or("internal request parent absent")?)?;
            let request_bytes=read_pinned(Path::new(&arguments[1]),&arguments[2],501,0o600,MAX_REQUEST)?;
            for parent in &request_parents{parent.revalidate()?;}
            let request=Request::parse(&request_bytes,&arguments[2])?;
            if request.get("worker_sha256")!=arguments[5]{return Err("independent bootstrap image/request worker crosslink differs".into());}
            let worker=env::current_exe().map_err(|_|"trusted bootstrap worker path unavailable")?;
            let expected=PathBuf::from(format!("/Library/Application Support/opensteamer/microphone-v9-bootstrap-{}",request.get("nonce"))).join("worker");
            if worker!=expected{return Err("bootstrap worker is not in the exact nonce-bound OS-sealed role".into());}
            read_pinned(&worker,&arguments[5],0,0o555,16*1024*1024)?;
            let parent=worker.parent().ok_or("trusted bootstrap worker parent unavailable")?;
            for ancestor in sealed_fs::root_ancestry_path(parent,0o711)?{ancestor.revalidate()?;}
            os::begin_supervision(45)?;
            let staged=seal::seal_original_uid_inputs(Path::new(&arguments[1]),Path::new(&arguments[3]),seal::TrustedPins{request_sha256:&arguments[2],manifest_sha256:&arguments[4],worker_sha256:&arguments[5]})?;
            for parent in &request_parents{parent.revalidate()?;}
            if staged.state!=PathBuf::from(request.root_path())||staged.executables!=PathBuf::from(format!("/Library/Application Support/opensteamer/microphone-v9-executables/{}",request.get("namespace"))){return Err("sealed namespace paths differ from fixed release roles".into());}
            os::supervisor_check()?;
            println!("schema=opensteamer.microphone-v9-seal-outcome.v1\nnamespace={}\nnonce={}\nrequest_sha256={}\nbuild_manifest_sha256={}\nworker_sha256={}\nterminal=SEALED_INPUTS_NOT_INSTALLED\nauthority_sha256={}",request.get("namespace"),request.get("nonce"),request.sha256,arguments[4],arguments[5],staged.authority_sha256);Ok(())
        })();
        return match result{Ok(())=>0,Err(error)=>{eprintln!("staging refused: {error}");65}};
    }
    if arguments.len() != 3 || !matches!(arguments[0].as_str(), "--verify-request" | "--execute-authorized" | "--resume-authorized") {
        eprintln!("usage: opensteamer-microphone-v9-transaction --verify-request|--execute-authorized|--resume-authorized request-path request-sha256");
        return 64;
    }
    let path = Path::new(&arguments[1]);
    #[cfg(target_os="macos")]
    if arguments[0]!="--verify-request"&&os::OwnedChild::root_identity(){
        let result=(||->Result<i32> {
            if !canonical_path(&arguments[1])||!arguments[1].starts_with(&format!("{ROOT_TRANSACTIONS}/"))||!arguments[1].ends_with("/request.txt"){return Err("root execution accepts only the exact presealed request role".into());}
            let bytes=read_pinned(path,&arguments[2],0,0o400,MAX_REQUEST)?;let request=Request::parse(&bytes,&arguments[2])?;
            if path!=Path::new(&request.root_path()).join("request.txt"){return Err("sealed root request namespace differs".into());}
            if !backend::LIVE_ADMISSION {
                println!("schema=opensteamer.microphone-v9-transaction-outcome.v1\nnamespace={}\nrequest_sha256={}\nterminal=REFUSED\nnormal_restarts=0\nrollback_restarts=0\nreason=LIVE_ADMISSION_DISABLED_PENDING_WHOLE_PATH_REVIEW",request.get("namespace"),request.sha256);return Ok(78);
            }
            os::begin_supervision(request.number("timeout_seconds"))?;
            if arguments[0]=="--resume-authorized"{os::enter_recovery()?;}
            let mut backend=backend::OsBackend::open(&request,arguments[0]=="--resume-authorized")?;
            let journal=backend.journal_snapshot();
            let mut transaction=Transaction{backend:&mut backend,journal};
            let mut outcome=if arguments[0]=="--resume-authorized"{transaction.resume()}else{transaction.run()};
            if outcome==Terminal::RecoveryRequired&&arguments[0]=="--execute-authorized"{
                match backend.prepare_recovery(){
                    Ok(journal)=>{let mut recovery=Transaction{backend:&mut backend,journal};outcome=recovery.resume();},
                    Err(reason)=>backend.retain_recovery_refusal(&reason)?,
                }
            }
            let(normal,rollback)=finalize_restart_report(&mut backend,|backend|backend.finalize_containment(),|backend|backend.restart_counts_for(outcome))?;
            let reason=match outcome{Terminal::Committed|Terminal::RolledBack=>"NONE",Terminal::CommittedUnverified=>"POSTCOMMIT_READBACK_UNVERIFIED",Terminal::RecoveryRequired=>"EXACT_RECOVERY_PROOF_INCOMPLETE",Terminal::Refused=>"FRESH_ADMISSION_REFUSED"};
            println!("schema=opensteamer.microphone-v9-transaction-outcome.v1\nnamespace={}\nrequest_sha256={}\nterminal={}\nnormal_restarts={}\nrollback_restarts={}\nreason={}",request.get("namespace"),request.sha256,outcome.name(),normal,rollback,reason);
            Ok(if matches!(outcome,Terminal::Committed|Terminal::RolledBack){0}else{78})
        })();
        return match result{Ok(code)=>code,Err(error)=>{eprintln!("root-sealed transaction unresolved: {error}");78}};
    }
    if !private_request_path(&arguments[1]) {
        eprintln!("request path is outside the private internal supervisor role"); return 65;
    }
    let bytes = match read_pinned(path, &arguments[2], 501, 0o600, MAX_REQUEST) {
        Ok(value) => value, Err(error) => { eprintln!("{error}"); return 65; }
    };
    let request = match Request::parse(&bytes, &arguments[2]) {
        Ok(value) => value, Err(error) => { eprintln!("{error}"); return 65; }
    };
    if arguments[0] == "--verify-request" {
        println!("VERIFIED_REQUEST_SHAPE_NOT_RUNTIME_ADMISSION"); return 0;
    }
    let mut backend = MissingOsBackend;
    let mut transaction = Transaction { backend: &mut backend, journal: Journal::new(&request) };
    let outcome = if arguments[0] == "--resume-authorized" { transaction.resume() } else { transaction.run() };
    println!("schema=opensteamer.microphone-v9-transaction-outcome.v1\nnamespace={}\nrequest_sha256={}\nterminal={}\nnormal_restarts=0\nrollback_restarts=0\nreason=LIVE_OS_BACKEND_NOT_IMPLEMENTED", request.get("namespace"), request.sha256, outcome.name());
    78
}

fn main() { std::process::exit(cli(&env::args().skip(1).collect::<Vec<_>>())); }

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use std::os::unix::fs::PermissionsExt;

    #[test]fn staging_manifest_role_is_exact_and_not_the_artifact_role(){
        assert!(guard_build_proof_path("/private/tmp/beluga-microphone-v9-guards.abCD12/build-proof.json"));
        for path in ["/Volumes/t7/build-proof.json","/private/tmp/beluga-microphone-v9-guards./build-proof.json","/private/tmp/beluga-microphone-v9-guards.good/../build-proof.json","/private/tmp/beluga-microphone-v9-guards.good/other.json","/tmp/beluga-microphone-v9-guards.good/build-proof.json","/private/tmp/beluga-microphone-v9-guards.good/nested/build-proof.json"]{assert!(!guard_build_proof_path(path));}
    }
    #[test]fn internal_request_role_never_accepts_external_or_arbitrary_internal_paths(){
        assert!(private_request_path("/private/tmp/beluga-microphone-v9-supervisor.good-123/native-request.txt"));
        for path in ["/Volumes/t7/beluga-microphone-v9-supervisor.good/native-request.txt","/private/tmp/native-request.txt","/tmp/beluga-microphone-v9-supervisor.good/native-request.txt","/private/tmp/beluga-microphone-v9-supervisor./native-request.txt","/private/tmp/beluga-microphone-v9-supervisor.good/other.txt","/private/tmp/beluga-microphone-v9-supervisor.good/nested/native-request.txt","/private/tmp/beluga-microphone-v9-supervisor.good/../native-request.txt"]{assert!(!private_request_path(path),"{path}");}
    }
    #[cfg(target_os="macos")]
    #[test]fn staging_cli_original_uid_is_refused_before_any_input_or_namespace_write(){
        assert!(!os::OwnedChild::root_identity(),"offline staging test must never run elevated");
        let args=["--seal-authorized-v9-inputs","/Volumes/t7/absent-v9-private-request.txt","aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","/private/tmp/beluga-microphone-v9-guards.absent/build-proof.json","bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"].map(String::from);
        assert_eq!(cli(&args),64);
    }

    pub(super) fn request() -> Request {
        let mut fields: BTreeMap<String,String> = FIELDS.iter().map(|key| (key.to_string(), "a".repeat(64))).collect();
        for key in ["guard_tooling_commit", "guard_tooling_tree"] { fields.insert(key.into(), "b".repeat(40)); }
        for (key,value) in EXACT_FIELDS { fields.insert((*key).into(), (*value).into()); }
        fields.insert("namespace".into(), "driver-microphone-v9-fixture".into());
        fields.insert("nonce".into(), "c".repeat(64)); fields.insert("host_nonce".into(), "d".repeat(64));
        for key in ["host_pid", "host_lock_device", "host_lock_inode", "predecessor_driver_instance", "predecessor_driver_device", "predecessor_driver_inode", "timeout_seconds", "host_launchd_runs"] { fields.insert(key.into(), "1".into()); }
        for key in ["committed_host_result_path", "committed_host_readiness_path", "committed_host_journal_path"] { fields.insert(key.into(), format!("{HOST_EVIDENCE}{key}")); }
        let bytes: Vec<u8> = FIELDS.iter().map(|key| format!("{key}={}\n", fields[*key])).collect::<String>().into_bytes();
        Request::parse(&bytes, &sha256(&bytes)).unwrap()
    }

    #[derive(Clone)]
    struct Model { facts: Facts, durable: Vec<u8>, effects: Vec<Effect>, fail_effect: Option<(Effect,bool)>, fail_persist: Option<(State,bool)>, enabled: bool,
        fail_observe: Option<String>, refuse_diagnostic: bool, refusals: Vec<String> }
    impl Model {
        fn new() -> Self { Self { facts: Facts { identity_exact:true,fresh_gate:true,root_sealed:false,host_present:true,host_ready_exact:true,driver:DriverLocation::PriorCanonical,prior_retained_exact:false,loaded:LoadedDriver::Prior,normal_restarts:0,rollback_restarts:0,public_nonce_both_orders:false,complete_v2_idle_with_history:false,route_notifications:0,route_teardown_clean:false }, durable:Vec::new(), effects:Vec::new(), fail_effect:None, fail_persist:None, enabled:true,
            fail_observe:None, refuse_diagnostic:false, refusals:Vec::new() } }
    }
    impl Backend for Model {
        fn live_admission(&self) -> bool { self.enabled }
        fn observe(&mut self) -> Result<Facts> { match &self.fail_observe { Some(reason) => Err(reason.clone()), None => Ok(self.facts.clone()) } }
        fn retain_admission_refusal(&mut self, reason: &str) -> Result<()> {
            self.refusals.push(reason.to_string());
            if self.refuse_diagnostic { Err("refusal diagnostic persistence failed".into()) } else { Ok(()) }
        }
        fn persist(&mut self, journal: &Journal) -> Result<()> {
            let fail = self.fail_persist.filter(|(state,_)| Some(*state) == journal.last());
            if fail.map(|(_,after)| !after).unwrap_or(false) { self.fail_persist=None; return Err("before durable append".into()); }
            self.durable=journal.bytes();
            if fail.is_some() { self.fail_persist=None; return Err("after durable append".into()); }
            Ok(())
        }
        fn effect(&mut self, effect: Effect) -> Result<()> {
            let fail = self.fail_effect.filter(|(value,_)| *value == effect);
            if fail.map(|(_,after)| !after).unwrap_or(false) { self.fail_effect=None; return Err("before effect".into()); }
            self.effects.push(effect);
            match effect {
                Effect::Seal => self.facts.root_sealed=true,
                Effect::StopHost => {self.facts.host_present=false; self.facts.host_ready_exact=false;},
                Effect::RetainPrior => {assert_eq!(self.facts.driver,DriverLocation::PriorCanonical);self.facts.driver=DriverLocation::CanonicalAbsent;self.facts.prior_retained_exact=true;},
                Effect::Publish => {assert_eq!(self.facts.driver,DriverLocation::CanonicalAbsent);self.facts.driver=DriverLocation::CandidateCanonical;},
                Effect::NormalRestart => {assert_eq!(self.facts.normal_restarts,0);self.facts.normal_restarts=1;self.facts.loaded=LoadedDriver::Candidate;},
                Effect::PublicProbe => self.facts.public_nonce_both_orders=true,
                Effect::IdleProbe => self.facts.complete_v2_idle_with_history=true,
                Effect::StartHost => {self.facts.host_present=true;self.facts.host_ready_exact=true;},
                Effect::RetireCandidate => {assert_eq!(self.facts.driver,DriverLocation::CandidateCanonical);self.facts.driver=DriverLocation::CanonicalAbsent;},
                Effect::RestorePrior => {assert!(self.facts.prior_retained_exact);self.facts.driver=DriverLocation::PriorCanonical;},
                Effect::RollbackRestart => {assert_eq!(self.facts.normal_restarts,1);assert_eq!(self.facts.rollback_restarts,0);self.facts.rollback_restarts=1;self.facts.loaded=LoadedDriver::Prior;},
                Effect::Audit => self.facts.route_teardown_clean=true,
            }
            if fail.is_some() {self.fail_effect=None;return Err("after effect".into());} Ok(())
        }
    }
    fn run(model:&mut Model, req:&Request)->Terminal {Transaction{backend:model,journal:Journal::new(req)}.run()}
    fn resume(model:&mut Model, req:&Request)->Terminal {let journal=Journal::parse(&model.durable,req).unwrap();Transaction{backend:model,journal}.resume()}

    #[test] fn sha256_known_vectors() { assert_eq!(sha256(b""),"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");assert_eq!(sha256(b"abc"),"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"); }
    #[test] fn strict_request_mutants() {
        let req=request();let bytes=FIELDS.iter().map(|key|format!("{key}={}\n",req.get(key))).collect::<String>();
        for mutant in [bytes.clone()+"schema=duplicate\n",bytes.replace("caller_uid=501","caller_uid=0"),bytes.replace("normal_restart_budget=1","normal_restart_budget=2"),bytes.replace("package_sha256=dc","package_sha256=aa"),bytes.replace("predecessor_driver_executable_sha256=25","predecessor_driver_executable_sha256=aa"),bytes.replace("timeout_seconds=1","timeout_seconds=181"),bytes.replace("host_pid=1","host_pid=01"),bytes.replace("input_uid=BlackHole2ch_UID","input_uid=virtual"),bytes.replace("schema=","command=/bin/sh\nschema="),bytes.replace("driver-microphone-v9-fixture","../../Applications"),bytes.replace("driver-microphone-v9-fixture","driver-microphone-v9--fixture"),bytes.replace("host-microphone-v9-001/committed_host_result_path","host-microphone-v9-001/./committed_host_result_path"),bytes.replace("BuiltInSpeakerDevice","BuiltInSpeakerDevice=extra"),bytes.replace("\n", "\r\n")] {assert!(Request::parse(mutant.as_bytes(),&sha256(mutant.as_bytes())).is_err());}
        assert!(Request::parse(bytes.as_bytes(),&"0".repeat(64)).is_err());assert!(Request::parse(bytes.trim_end().as_bytes(),&sha256(bytes.trim_end().as_bytes())).is_err());
        assert_eq!(req.root_path(),format!("{ROOT_TRANSACTIONS}/driver-microphone-v9-fixture"));assert_eq!(DRIVER,"/Library/Audio/Plug-Ins/HAL/OpensteamerVirtualMicrophone.driver");
    }
    #[test] fn one_normal_restart_success() {let req=request();let mut model=Model::new();assert_eq!(run(&mut model,&req),Terminal::Committed);assert_eq!(model.facts.normal_restarts,1);assert_eq!(model.facts.rollback_restarts,0);assert!(model.facts.committed());assert!(Journal::parse(&model.durable,&req).unwrap().last().unwrap().committed());}
    #[test] fn initial_refusal_retains_original_reason_without_effect_or_journal() {
        let req=request();let mut model=Model::new();
        model.fail_observe=Some("sealed original-UID host gate failed".into());
        assert_eq!(run(&mut model,&req),Terminal::Refused);
        assert_eq!(model.refusals,vec!["sealed original-UID host gate failed"]);
        assert!(model.effects.is_empty()&&model.durable.is_empty());
        model.refuse_diagnostic=true;
        assert_eq!(run(&mut model,&req),Terminal::RecoveryRequired);
        assert!(model.effects.is_empty()&&model.durable.is_empty());
    }
    #[test] fn restart_report_finalizes_containment_even_when_counts_are_unproved() {
        let mut finalized=false;
        assert!(finalize_restart_report(&mut (),|_|{finalized=true;Ok(())},|_|Err("loaded image unavailable".into())).is_err());
        assert!(finalized);
        let mut counted=false;
        assert!(finalize_restart_report(&mut (),|_|Err("owned child unresolved".into()),|_|{counted=true;Ok((0,0))}).is_err());
        assert!(!counted);
        assert_eq!(finalize_restart_report(&mut (),|_|Ok(()),|_|Ok((1,0))).unwrap(),(1,0));
    }
    #[test]fn restored_restart_counts_match_exact_wrapper_contract(){
        let mut model=Model::new();model.facts.route_teardown_clean=true;assert!(model.facts.restored());
        model.facts.normal_restarts=1;assert!(!model.facts.restored());model.facts.rollback_restarts=1;assert!(model.facts.restored());
    }
    #[test] fn every_normal_effect_interruption_restores_exact_predecessor() {
        let req=request();for effect in [Effect::Seal,Effect::StopHost,Effect::RetainPrior,Effect::Publish,Effect::NormalRestart,Effect::PublicProbe,Effect::IdleProbe,Effect::StartHost,Effect::Audit] {for after in [false,true] {let mut model=Model::new();model.fail_effect=Some((effect,after));assert_eq!(run(&mut model,&req),Terminal::RecoveryRequired);assert_eq!(resume(&mut model,&req),Terminal::RolledBack,"{effect:?}/{after}");assert!(model.facts.restored());assert_eq!(model.facts.rollback_restarts,model.facts.normal_restarts);}}
    }
    #[test] fn every_durable_append_fault_never_rolls_back_irreversible_commit() {
        let req=request();for state in State::all().iter().copied().take_while(|state|*state!=State::RollbackIntent) {for after in [false,true] {let mut model=Model::new();model.fail_persist=Some((state,after));let outcome=run(&mut model,&req);if outcome!=Terminal::RecoveryRequired {continue;}if model.durable.is_empty() {assert!(model.effects.is_empty());continue;}let durable=Journal::parse(&model.durable,&req).unwrap();let committed=durable.last().unwrap().committed();let result=resume(&mut model,&req);if committed {assert!(matches!(result,Terminal::Committed|Terminal::CommittedUnverified));assert_eq!(model.facts.rollback_restarts,0);assert!(!model.effects.contains(&Effect::RestorePrior));}else {assert_eq!(result,Terminal::RolledBack,"{state:?}/{after}");assert!(model.facts.restored());}}}
    }
    #[test] fn every_rollback_effect_is_resumable_without_duplicate_restart() {
        let req=request();for effect in [Effect::StopHost,Effect::RetireCandidate,Effect::RestorePrior,Effect::RollbackRestart,Effect::StartHost,Effect::Audit] {for after in [false,true] {let mut model=Model::new();model.fail_effect=Some((Effect::Audit,false));assert_eq!(run(&mut model,&req),Terminal::RecoveryRequired);model.fail_effect=Some((effect,after));let first=resume(&mut model,&req);if first==Terminal::RecoveryRequired {assert_eq!(resume(&mut model,&req),Terminal::RolledBack,"{effect:?}/{after}");}else {assert_eq!(first,Terminal::RolledBack);}assert_eq!(model.facts.normal_restarts,1);assert_eq!(model.facts.rollback_restarts,1);}}
    }
    #[test] fn every_rollback_journal_boundary_is_resumable() {
        let req=request();
        for state in [State::RollbackIntent,State::RetireIntent,State::CandidateRetired,State::RestoreIntent,
            State::PriorRestored,State::RollbackRestartIntent,State::RollbackReloaded,State::RollbackHostStartIntent,
            State::RollbackHostReady,State::RolledBack] {
            for after in [false,true] {
                let mut model=Model::new();model.fail_effect=Some((Effect::Audit,false));
                assert_eq!(run(&mut model,&req),Terminal::RecoveryRequired);
                model.fail_persist=Some((state,after));assert_eq!(resume(&mut model,&req),Terminal::RecoveryRequired,"{state:?}/{after}");
                assert_eq!(resume(&mut model,&req),Terminal::RolledBack,"{state:?}/{after}");
                assert_eq!(model.facts.normal_restarts,1);assert_eq!(model.facts.rollback_restarts,1);
            }
        }
    }
    #[test] fn journal_rejects_torn_reordered_forged_and_cross_request_rows() {
        let req=request();let mut model=Model::new();assert_eq!(run(&mut model,&req),Terminal::Committed);let text=String::from_utf8(model.durable.clone()).unwrap();for mutant in [text.trim_end().into(),text.replace("\n","\r\n"),text.replace("NORMAL_RESTART_OBSERVED","COMMIT_IRREVERSIBLE"),text.replace("sequence=2 ","sequence=3 "),text.replace("request_sha256=","request_sha256=0"),text.clone()+"garbage\n"] {assert!(Journal::parse(mutant.as_bytes(),&req).is_err());}let mut other=req.clone();other.sha256="e".repeat(64);assert!(Journal::parse(&model.durable,&other).is_err());
    }
    #[test] fn sticky_route_identity_and_incomplete_proof_never_commit() {
        let req=request();for kind in 0..5 {let mut model=Model::new();match kind {0=>model.facts.route_notifications=1,1=>model.facts.identity_exact=false,2=>model.facts.loaded=LoadedDriver::Unknown,3=>model.facts.loaded=LoadedDriver::Candidate,_=>model.facts.fresh_gate=false};assert_eq!(run(&mut model,&req),Terminal::Refused);assert!(model.effects.is_empty());}let mut facts=Model::new().facts;facts.driver=DriverLocation::CandidateCanonical;facts.loaded=LoadedDriver::Candidate;facts.normal_restarts=1;assert!(!facts.committed());
    }
    #[test] fn unimplemented_live_backend_is_explicitly_refused() {let req=request();let mut backend=MissingOsBackend;let mut tx=Transaction{backend:&mut backend,journal:Journal::new(&req)};assert_eq!(tx.run(),Terminal::Refused);assert_eq!(tx.resume(),Terminal::Refused);assert!(tx.journal.records.is_empty());}
    #[test] fn nofollow_byte_owner_mode_and_replacement_guards() {
        let root=std::env::temp_dir().join(format!("beluga-v9-native-test-{}",std::process::id()));fs::create_dir(&root).unwrap();fs::set_permissions(&root,fs::Permissions::from_mode(0o700)).unwrap();let path=root.join("request");let mut file=OpenOptions::new().write(true).create_new(true).mode(0o600).open(&path).unwrap();file.write_all(b"fixture").unwrap();file.sync_all().unwrap();let canonical=fs::canonicalize(&path).unwrap();let owner=fs::metadata(&canonical).unwrap().uid();assert_eq!(read_pinned(&canonical,&sha256(b"fixture"),owner,0o600,64).unwrap(),b"fixture");assert!(read_pinned(&canonical,&sha256(b"wrong"),owner,0o600,64).is_err());fs::set_permissions(&canonical,fs::Permissions::from_mode(0o644)).unwrap();assert!(read_pinned(&canonical,&sha256(b"fixture"),owner,0o600,64).is_err());let alias=root.join("alias");std::os::unix::fs::symlink(&canonical,&alias).unwrap();assert!(read_pinned(&alias,&sha256(b"fixture"),owner,0o644,64).is_err());fs::remove_file(alias).unwrap();fs::remove_file(canonical).unwrap();fs::remove_dir(root).unwrap();
    }

    #[cfg(target_os="macos")]
    fn private_fixture(label:&str)->std::path::PathBuf {
        let path=std::env::temp_dir().join(format!("beluga-v9-{label}-{}",std::process::id()));
        fs::create_dir(&path).unwrap();fs::set_permissions(&path,fs::Permissions::from_mode(0o700)).unwrap();
        fs::canonicalize(path).unwrap()
    }

    #[cfg(target_os="macos")]
    #[test] fn descriptor_exclusive_retention_preserves_inode_and_refuses_overwrite() {
        let root=private_fixture("retention");let prior=root.join("prior");let mut file=OpenOptions::new().write(true).create_new(true).mode(0o400).open(&prior).unwrap();
        file.write_all(b"exact prior bytes").unwrap();file.sync_all().unwrap();drop(file);
        let metadata=fs::metadata(&root).unwrap();
        let held=sealed_fs::HeldDirectory::capture(&root,metadata.uid(),metadata.gid(),0o700).unwrap();
        let original=Identity::of(&fs::symlink_metadata(&prior).unwrap());
        held.exclusive_retain("prior",&held,"retained",&original).unwrap();
        assert_eq!(fs::symlink_metadata(root.join("retained")).unwrap().ino(),original.inode);
        assert!(!prior.exists());
        let new=root.join("new");fs::write(&new,b"other").unwrap();
        let new_identity=Identity::of(&fs::symlink_metadata(&new).unwrap());
        assert!(held.exclusive_retain("new",&held,"retained",&new_identity).is_err());
        assert_eq!(fs::read(root.join("retained")).unwrap(),b"exact prior bytes");assert!(new.exists());
        for path in [root.join("retained"),new] {fs::remove_file(path).unwrap();}fs::remove_dir(root).unwrap();
    }

    #[cfg(target_os="macos")]
    #[test] fn descriptor_ancestry_replacement_and_acl_are_refused() {
        let root=private_fixture("ancestry");let metadata=fs::metadata(&root).unwrap();
        let held=sealed_fs::HeldDirectory::capture(&root,metadata.uid(),metadata.gid(),0o700).unwrap();
        let renamed=root.with_extension("retained");fs::rename(&root,&renamed).unwrap();
        fs::create_dir(&root).unwrap();fs::set_permissions(&root,fs::Permissions::from_mode(0o700)).unwrap();
        assert!(held.revalidate().is_err());
        fs::remove_dir(root).unwrap();fs::remove_dir(renamed).unwrap();
        assert!(sealed_fs::root_ancestry(&request()).is_err()); // no live root namespace is created
    }

    #[cfg(target_os="macos")]
    #[test] fn descriptor_durable_journal_generations_have_exact_prefix_and_no_overwrite() {
        let root=private_fixture("journal");let metadata=fs::metadata(&root).unwrap();
        let held=sealed_fs::HeldDirectory::capture(&root,metadata.uid(),metadata.gid(),0o700).unwrap();let req=request();
        let first=Journal::new(&req).appended(State::Prepared).unwrap();held.persist(&first).unwrap();
        let second=first.appended(State::Sealed).unwrap();held.persist(&second).unwrap();
        assert_eq!(held.load_journal(&req,2).unwrap().records,second.records);
        assert!(held.persist(&second).is_err());assert_eq!(held.load_journal(&req,2).unwrap().records,second.records);
        // Exact fixed fixture names only; leftover pending evidence is retained
        // until this isolated test's own cleanup, never treated as a live proof.
        for name in ["journal-001","journal-002","pending-002"] {let path=root.join(name);if path.exists(){fs::remove_file(path).unwrap();}}
        fs::remove_dir(root).unwrap();
    }
    #[cfg(target_os="macos")]
    #[test]fn exact_pending_generation_is_adopted_but_torn_multiple_and_wrong_prefix_remain(){
        let req=request();let first=Journal::new(&req).appended(State::Prepared).unwrap();let second=first.appended(State::Sealed).unwrap();
        for kind in ["valid","torn","wrong-prefix","multiple","gap"]{
            let root=private_fixture(kind);let metadata=fs::metadata(&root).unwrap();let held=sealed_fs::HeldDirectory::capture(&root,metadata.uid(),metadata.gid(),0o700).unwrap();held.persist(&first).unwrap();
            let mut bytes=second.bytes();if kind=="torn"{bytes.pop();}if kind=="wrong-prefix"{bytes=first.bytes();}
            held.write_record(if kind=="gap"{"pending-003"}else{"pending-002"},&bytes,0o400).unwrap();
            if kind=="multiple"{held.write_record("pending-003",&bytes,0o400).unwrap();}
            let observed=held.reconcile_journal(&req);
            if kind=="valid"{assert_eq!(observed.unwrap().records,second.records);assert!(!root.join("pending-002").exists());assert_eq!(held.reconcile_journal(&req).unwrap().records,second.records);}
            else{assert!(observed.is_err());assert!(!root.join("journal-002").exists());}
            for name in ["journal-001","journal-002","pending-002","pending-003"]{let path=root.join(name);if path.exists(){fs::remove_file(path).unwrap();}}fs::remove_dir(root).unwrap();
        }
    }
    #[cfg(target_os="macos")]
    #[test]fn shared_controller_lock_refuses_duplicate_and_replaced_owner(){
        let root=private_fixture("lock");let metadata=fs::metadata(&root).unwrap();let held=sealed_fs::HeldDirectory::capture(&root,metadata.uid(),metadata.gid(),0o700).unwrap();
        let lock=sealed_fs::RootLock::acquire_fixture(&held).unwrap();assert!(sealed_fs::RootLock::acquire_fixture(&held).is_err());lock.revalidate().unwrap();
        fs::rename(root.join(".controller.lock"),root.join("retained-lock")).unwrap();let replacement=OpenOptions::new().write(true).create_new(true).mode(0o600).open(root.join(".controller.lock")).unwrap();drop(replacement);assert!(lock.revalidate().is_err());drop(lock);
        for name in [".controller.lock","retained-lock"]{fs::remove_file(root.join(name)).unwrap();}fs::remove_dir(root).unwrap();
    }
}
