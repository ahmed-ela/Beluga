//! One-shot root staging, never HAL publication or service/audio operations.
//! The caller must be an independently OS-pinned native image and supply three
//! independently pinned digests. User-owned requests/manifests are crosslinks,
//! not authority. A partial namespace is deliberately retained and never reused.
use super::*;
use super::proof::{Json, Parser};
use std::ffi::CString;
use std::fs::File;
use std::io::Write;
use std::os::fd::{AsRawFd, FromRawFd};
use std::path::PathBuf;
use std::time::{Duration, Instant};

const BASE: &str = "/Library/Application Support/opensteamer";
const EXEC_BASE: &str = "/Library/Application Support/opensteamer/microphone-v9-executables";
const PRODUCT: &str = "/Volumes/t7/beluga-quality-step.idpzQO/source";
const OBSERVERS: &str = "/Users/ahmed/Library/Application Support/opensteamer/paired-host-updates-v90/paired-v90-update-1790273646-83304-497866f7-25e2-4701-b155-442ca77d541c/pinned-v86-observer-tools";
const MAX_MANIFEST: usize = 1_048_576;
const MAX_FILE: usize = 16 * 1024 * 1024;
const MAX_TOTAL: usize = 256 * 1024 * 1024;
const DIRECTORY: i32 = 0x0010_0000;
const CLOEXEC: i32 = 0x0100_0000;
const CREATE: i32 = 0x0200;
const EXCLUSIVE: i32 = 0x0800;

unsafe extern "C" {
    fn getuid() -> u32;
    fn geteuid() -> u32;
    fn mkdirat(fd: i32, name: *const i8, mode: u16) -> i32;
    fn openat(fd: i32, name: *const i8, flags: i32, ...) -> i32;
    fn fchmod(fd: i32, mode: u16) -> i32;
    fn fchown(fd: i32, owner: u32, group: u32) -> i32;
}

const INPUTS: &[(&str, &str, &str, &str, u32)] = &[
    ("tools/opensteamer-microphone-v9-host-gate.rb", "host_gate_sha256", "tooling", "macOS/scripts/opensteamer-microphone-v9-host-gate.rb", 0o444),
    ("tools/product/opensteamer-host-v91-cutover-controller.rb", "controller_sha256", "product", "macOS/scripts/opensteamer-host-v91-cutover-controller.rb", 0o444),
    ("tools/product/opensteamer-host-successor-inputs.rb", "inputs_sha256", "product", "macOS/scripts/opensteamer-host-successor-inputs.rb", 0o444),
    ("tools/product/opensteamer-host-successor-contract.rb", "contract_sha256", "product", "macOS/scripts/opensteamer-host-successor-contract.rb", 0o444),
    ("tools/product/verify-v91-secondary-viewer-readiness.sh", "readiness_sha256", "product", "macOS/scripts/verify-v91-secondary-viewer-readiness.sh", 0o444),
    ("tools/observers/SwitchAudioSource", "switch_audio_sha256", "observers", "SwitchAudioSource", 0o555),
    ("tools/observers/probe-worldwide-lock-v23", "lock_sha256", "observers", "probe-worldwide-lock-v23", 0o555),
    ("tools/observers/verify-live-display-topology-v23", "topology_sha256", "observers", "verify-live-display-topology-v23", 0o555),
];
const PRODUCT_PINS: &[(&str, &str)] = &[
    ("controller_sha256", "d390402ae8a7f824ec9e98c46dc09458dc860818e39d773c3cc16aba1c914a74"),
    ("inputs_sha256", "22dd757c4465118b2129275134ac136b4a0e8869190d5f90892e4dfe81cc39e0"),
    ("contract_sha256", "a5ee8c492257f4869bbc48ad8f30d06f13ac2c59faaf7e982a33eaaaa8a76bfb"),
    ("readiness_sha256", "b1de7e579df9087ce1d8ed761539e4c74522f3f23c02d95e6f0385fb66c2e14d"),
    ("switch_audio_sha256", "9a29148a58b91c6ac13281b3cc1915922bdadd00ab09b3267271e5925d52fb64"),
    ("lock_sha256", "602c4578dcaec75629126d799056591dd0cea80c2f1ccaae5d91b0c341867e4f"),
    ("topology_sha256", "1502e07358f2316f4dee1fb12ce380cc5e9588cd6393ea3f34656ab80e9db292"),
];
const TOOLS: &[(&str, &str, &str, &str)] = &[
    ("worker", "worker", "transaction", "worker_sha256"),
    ("idleHelper", "idle-helper", "idle-helper", "idle_helper_sha256"),
    ("bothOrderProbe", "both-order-probe", "public-proof", "both_order_probe_sha256"),
    ("routeGuardian", "route-guardian", "route-guardian", "route_guardian_sha256"),
];
const CANDIDATE_NODES: &[(&str, u32, bool)] = &[
    (".", 0o755, true), ("Contents", 0o755, true), ("Contents/Info.plist", 0o644, false),
    ("Contents/MacOS", 0o755, true), ("Contents/MacOS/OpensteamerVirtualMicrophone", 0o755, false),
    ("Contents/Resources", 0o755, true), ("Contents/Resources/APPLE_SAMPLE_LICENSE.txt", 0o644, false),
    ("Contents/Resources/en.lproj", 0o755, true), ("Contents/Resources/en.lproj/Localizable.strings", 0o644, false),
    ("Contents/_CodeSignature", 0o755, true), ("Contents/_CodeSignature/CodeResources", 0o644, false),
];
const ARTIFACT_RECORDS: &[(&str, &str)] = &[
    ("candidate-manifest.txt", "5080e24749071cdff797bf3eabcf39e6f3537591072d8104c663f5d899729bce"),
    ("microphone-binding.json", "4a24017dd968c0c0ca09484475e6c53fd24a4e76fe02ba7cdefd3b61a802ec4e"),
    ("candidate-entry-inputs.json", "bc150676896f9099512c6ac152c86295f2850d6176fe9063e80fb32f6076d9bb"),
    ("candidate-inputs.json", "e7cda45a34741ce93df979274f8d557ce2fcf65412ba00c509ff83a8b8997b63"),
    ("binding-request.json", "413f081de312d55063bf8ec0807ff9c901609de67625f6b659bb59a5e847984e"),
    ("build-invocation.json", "def0d216ca58ce52b17778ec2311da3b975faf2f54875953d54f22af88f75794"),
    ("build-stdout.txt", "868353d94128d084de43e7d9deb31bb0607ee0cee7c0498d55dbecea9d16cf37"),
    ("build-stderr.txt", "7ea6cca8eb1eaf71615ade1c91ddbca711fbe784438eef462c6cc94ff46d4c02"),
    ("notary-result.json", "b257223d6e423c141f760651abff810dab447c4b1bfa5f2dbbf88b58ec5cb58b"),
    ("verification.txt", "7f61bdeab8b3df5734e78346efc55891c3cce8d9900530da8e0d558fffd42c49"),
    ("OpensteamerVirtualMicrophone-v9.pkg", "dc5344c6b259d9739a07e2f7d61e2edd976ffe79e2a8d3eda8db234a2788841e"),
];

/// All three values must come from the trusted OS dispatch, not request fields.
pub(super) struct TrustedPins<'a> {
    pub(super) request_sha256: &'a str,
    pub(super) manifest_sha256: &'a str,
    pub(super) worker_sha256: &'a str,
}
pub(super) struct SealedAttempt {
    pub(super) state: PathBuf,
    pub(super) executables: PathBuf,
    pub(super) authority_sha256: String,
}

fn require(value: bool, message: &str) -> Result<()> { if value { Ok(()) } else { Err(message.into()) } }
fn object(value: &Json) -> Result<&BTreeMap<String, Json>> {
    if let Json::Object(value) = value { Ok(value) } else { Err("seal manifest object refused".into()) }
}
fn exact<'a>(value: &'a Json, keys: &[&str]) -> Result<&'a BTreeMap<String, Json>> {
    let value = object(value)?;
    require(value.len() == keys.len() && keys.iter().all(|key| value.contains_key(*key)), "seal manifest exact fields differ")?;
    Ok(value)
}
fn text<'a>(value: &'a BTreeMap<String, Json>, key: &str) -> Result<&'a str> {
    if let Some(Json::Text(value)) = value.get(key) { Ok(value) } else { Err("seal manifest text type refused".into()) }
}
fn number(value: &Json) -> Result<i128> {
    if let Json::Number(value) = value {
        let parsed: i128 = value.parse().map_err(|_| "seal manifest integer overflow")?;
        require(parsed.to_string() == *value, "seal manifest noncanonical integer")?; Ok(parsed)
    } else { Err("seal manifest integer type refused".into()) }
}
fn identity_values(value: &Identity) -> [i128; 11] {
    [value.device as i128, value.inode as i128, value.uid as i128, value.gid as i128, value.mode as i128,
     value.links as i128, value.size as i128, value.mtime as i128, value.mtime_nsec as i128,
     value.ctime as i128, value.ctime_nsec as i128]
}
#[derive(Clone)]
struct SourceRecord { path: PathBuf, digest: String, identity: [i128; 11] }
impl SourceRecord {
    fn parse(value: &Json) -> Result<Self> {
        let fields = exact(value, &["path", "sha256", "identity"])?;
        let path = text(fields, "path")?; let digest = text(fields, "sha256")?;
        require(canonical_path(path) && path.is_ascii() && !path.bytes().any(|b| b < 32 || b == 127), "seal source path refused")?;
        require(hex(digest, 64), "seal source digest refused")?;
        let values = match fields.get("identity") { Some(Json::Array(value)) if value.len() == 11 => value, _ => return Err("seal source identity extent refused".into()) };
        let mut identity = [0; 11]; for (slot, value) in identity.iter_mut().zip(values) { *slot = number(value)?; }
        require(identity[0] > 0 && identity[0] <= u64::MAX as i128 && identity[1] > 0 && identity[1] <= u64::MAX as i128 &&
                identity[2] == 501 && identity[3] >= 0 && identity[3] <= u32::MAX as i128 &&
                identity[4] >= 0 && identity[4] <= u32::MAX as i128 && identity[4] & 0o170000 == 0o100000 && identity[4] & 0o7022 == 0 && identity[5] == 1 &&
                identity[6] >= 0 && identity[6] <= 256 * 1024 * 1024 && (0..1_000_000_000).contains(&identity[8]) &&
                (0..1_000_000_000).contains(&identity[10]) && identity[7] >= i64::MIN as i128 && identity[7] <= i64::MAX as i128 &&
                identity[9] >= i64::MIN as i128 && identity[9] <= i64::MAX as i128, "seal source identity policy refused")?;
        Ok(Self { path: path.into(), digest: digest.into(), identity })
    }
}

struct CapturedSource { file: File, path: PathBuf, identity: Identity, bytes: Vec<u8> }
impl CapturedSource {
    fn read(path: &Path, digest: &str, record: Option<&SourceRecord>, budget: &mut Budget) -> Result<Self> {
        budget.check()?;
        require(hex(digest,64) && fs::canonicalize(path).map_err(|_| "seal source canonical path unavailable")? == path, "seal source alias refused")?;
        let before = fs::symlink_metadata(path).map_err(|_| "seal source metadata unavailable")?;
        require(before.is_file() && before.uid() == 501 && before.nlink() == 1 && before.mode() & 0o7022 == 0 && before.len() <= MAX_FILE as u64, "seal source metadata policy refused")?;
        let identity = Identity::of(&before);
        if let Some(record) = record { require(record.path == path && identity_values(&identity) == record.identity, "seal source manifest identity differs")?; }
        let mut file = OpenOptions::new().read(true).custom_flags(NOFOLLOW | CLOEXEC).open(path).map_err(|_| "seal source nofollow open failed")?;
        sealed_fs::no_acl(&file)?;
        require(identity == Identity::of(&file.metadata().map_err(|_| "seal source descriptor metadata failed")?), "seal source changed at open")?;
        let mut bytes = Vec::new(); let mut chunk = [0u8; 65_536];
        loop { budget.check()?; let count = file.read(&mut chunk).map_err(|_| "seal source read failed")?; if count == 0 { break; }
            require(bytes.len() + count <= MAX_FILE, "seal source extent exceeded")?; budget.consume(count)?; bytes.extend_from_slice(&chunk[..count]); }
        require(bytes.len() as u64 == identity.size && sha256(&bytes) == digest, "seal source digest or extent differs")?;
        let value = Self { file, path: path.into(), identity, bytes }; value.revalidate()?; Ok(value)
    }
    fn revalidate(&self) -> Result<()> {
        require(self.identity == Identity::of(&self.file.metadata().map_err(|_| "held seal source metadata failed")?) &&
                self.identity == Identity::of(&fs::symlink_metadata(&self.path).map_err(|_| "held seal source disappeared")?), "held seal source changed")?;
        sealed_fs::no_acl(&self.file)
    }
}
struct Budget { deadline: Instant, consumed: usize }
impl Budget {
    fn new() -> Self { Self { deadline: Instant::now() + Duration::from_secs(30), consumed: 0 } }
    fn check(&self) -> Result<()> { self.check_supervision(os::supervisor_check) }
    fn check_supervision(&self, poll:impl FnOnce()->Result<()>) -> Result<()> {
        poll()?; require(Instant::now() < self.deadline, "seal monotonic deadline exceeded")
    }
    fn consume(&mut self, bytes: usize) -> Result<()> { self.consumed = self.consumed.checked_add(bytes).ok_or("seal byte budget overflow")?; require(self.consumed <= MAX_TOTAL, "seal total byte budget exceeded") }
}

struct Plan { staged: BTreeMap<String, (CapturedSource, u32)>, held: Vec<CapturedSource>, manifest: CapturedSource }
fn gate_inputs(bytes: &[u8], records: &BTreeMap<String, SourceRecord>) -> Result<()> {
    let mut expected = String::from("schema=opensteamer.microphone-v9-gate-inputs.v1\n");
    for (destination, key, _, _, _) in INPUTS { expected.push_str(&format!("{key}={}\n", records[*destination].digest)); }
    require(bytes == expected.as_bytes(), "seal gate input exact crosslinks differ")
}
fn parse_manifest(bytes: &[u8], request: &Request, build: &Path) -> Result<(BTreeMap<String, SourceRecord>, Vec<SourceRecord>)> {
    require(bytes.len() <= MAX_MANIFEST, "seal manifest extent refused")?;
    let value = Parser::parse(bytes)?;
    let fields = exact(&value, &["schema", "productCommit", "productTree", "guardToolingCommit", "guardToolingTree", "deploymentAuthority", "liveQueriesPerformed", "sources", "swiftCompiler", "rustCompiler", "sdkSettings", "commands", "sealedInputs", "tools"])?;
    for (key, expected) in [("schema", "opensteamer.microphone-v9.native-guard-build.v1"), ("productCommit", request.get("product_commit")),
        ("productTree", request.get("product_tree")), ("guardToolingCommit", request.get("guard_tooling_commit")), ("guardToolingTree", request.get("guard_tooling_tree"))] {
        require(text(fields,key)? == expected, "seal manifest source provenance differs")?;
    }
    require(fields["deploymentAuthority"] == Json::Bool(false) && fields["liveQueriesPerformed"] == Json::Bool(false), "seal manifest claims deployment or live activity")?;
    let inputs = object(&fields["sealedInputs"])?; require(inputs.len() == INPUTS.len()+1 && inputs.contains_key("tools/gate_inputs.txt"), "seal dependency role set differs")?;
    let mut staged = BTreeMap::new();
    for (destination, key, origin, relative, _) in INPUTS {
        let record = SourceRecord::parse(inputs.get(*destination).ok_or("seal dependency missing")?)?;
        let root = match *origin { "tooling" => TOOLING, "product" => PRODUCT, "observers" => OBSERVERS, _ => unreachable!() };
        require(record.path == Path::new(root).join(relative), "seal dependency source is not its fixed role")?;
        if let Some((_, digest)) = PRODUCT_PINS.iter().find(|(item,_)| item == key) { require(record.digest == *digest, "seal immutable observer/product byte pin differs")?; }
        staged.insert(destination.to_string(), record);
    }
    let record = SourceRecord::parse(&inputs["tools/gate_inputs.txt"])?;
    require(record.path == build.join("gate_inputs.txt"), "seal gate inputs source differs")?; staged.insert("tools/gate_inputs.txt".into(), record);
    let tools = exact(&fields["tools"], &["worker", "idleHelper", "bothOrderProbe", "routeGuardian"])?;
    for (role, destination, basename, key) in TOOLS {
        let record = SourceRecord::parse(&tools[*role])?;
        require(record.path == build.join(basename) && record.digest == request.get(key), "seal compiled tool role/request pin differs")?;
        staged.insert(destination.to_string(),record);
    }
    let sources = object(&fields["sources"])?; require(!sources.is_empty() && sources.len() <= 32, "seal source proof count refused")?;
    let mut retained = Vec::new();
    for (path, value) in sources {
        let record = SourceRecord::parse(value)?;
        require(path == record.path.to_str().ok_or("source path UTF-8 refused")? &&
                (path.starts_with(&format!("{TOOLING}/macOS/scripts/")) || path == &format!("{TOOLING}/iOS/opensteamer/scripts/physical-blackhole-microphone-probe.swift") ||
                 path == &format!("{PRODUCT}/macOS/Sources/CaptureServer/WorldwideVirtualMicrophoneDriverIdle.swift") ||
                 path == &format!("{PRODUCT}/macOS/scripts/opensteamer-v91-coreaudio-route-monitor.swift") ||
                 path == &build.join("public/main.swift").to_string_lossy() ||
                 INPUTS.iter().any(|(_,_,origin,rel,_)| *origin == "product" && path == &format!("{PRODUCT}/{rel}"))), "seal source proof path refused")?;
        retained.push(record);
    }
    let public=format!("{TOOLING}/iOS/opensteamer/scripts/physical-blackhole-microphone-probe.swift");
    let main=build.join("public/main.swift"); let main=main.to_str().ok_or("derived public source path UTF-8 refused")?;
    let public_record=SourceRecord::parse(sources.get(&public).ok_or("reviewed public source proof missing")?)?;
    let main_record=SourceRecord::parse(sources.get(main).ok_or("derived public main proof missing")?)?;
    require(main_record.digest==public_record.digest,"derived public source differs from reviewed original bytes")?;
    for key in ["swiftCompiler", "rustCompiler", "sdkSettings"] { retained.push(SourceRecord::parse(&fields[key])?); }
    let commands = match &fields["commands"] { Json::Array(values) if !values.is_empty() && values.len() <= 64 => values, _ => return Err("seal build commands extent/type refused".into()) };
    for command in commands {
        let command = exact(command, &["argv", "pid", "exitStatus", "termSignal", "timedOutOrLogBound", "stdout", "stderr"])?;
        require(number(&command["pid"])? > 0 && number(&command["pid"])? <= i32::MAX as i128 && number(&command["exitStatus"])? == 0 && command["termSignal"] == Json::Null && command["timedOutOrLogBound"] == Json::Bool(false), "seal build command is non-green")?;
        let argv = match &command["argv"] { Json::Array(values) if !values.is_empty() && values.len() <= 64 => values, _ => return Err("seal build argv extent/type refused".into()) };
        for argument in argv { require(matches!(argument, Json::Text(value) if !value.is_empty() && !value.contains('\0') && value.len() <= 4096), "seal build argv bytes refused")?; }
        for channel in ["stdout", "stderr"] { let record = SourceRecord::parse(&command[channel])?;
            require(record.path.parent() == Some(build.join("commands").as_path()), "seal build log path escaped owned build")?; retained.push(record); }
    }
    Ok((staged, retained))
}

fn capture_candidate(request: &Request, budget: &mut Budget) -> Result<(BTreeMap<String,(CapturedSource,u32)>,Vec<sealed_fs::HeldDirectory>)> {
    let root = Path::new(ARTIFACT).join("OpensteamerVirtualMicrophone.driver");
    let mut directories = Vec::new(); let mut captured = BTreeMap::new(); let mut canonical = Vec::new(); let mut hashes = BTreeMap::new();
    for (relative, mode, directory) in CANDIDATE_NODES {
        budget.check()?; let path = if *relative == "." { root.clone() } else { root.join(relative) };
        if *directory {
            let metadata=fs::symlink_metadata(&path).map_err(|_| "candidate directory metadata unavailable")?;
            let held=sealed_fs::HeldDirectory::capture(&path,501,metadata.gid(),*mode)?;
            let mut expected=CANDIDATE_NODES.iter().filter_map(|(child,_,_)| {
                if *child == "." { return None; } let item=Path::new(child); let parent=item.parent()?.to_str()?;
                if parent == if *relative == "." { "" } else { relative } { item.file_name()?.to_str().map(str::to_string) } else { None }
            }).collect::<Vec<_>>();
            let mut actual=Vec::new();
            for child in fs::read_dir(&path).map_err(|_| "candidate directory layout unavailable")? {
                budget.check()?; require(actual.len()<expected.len(),"candidate directory contains extra nodes")?;
                let child=child.map_err(|_|"candidate child unavailable")?;
                actual.push(child.file_name().into_string().map_err(|_|"candidate child UTF-8 refused")?);
            }
            actual.sort(); expected.sort(); require(actual==expected,"candidate exact eleven-node layout differs")?; directories.push(held);
        } else {
            let metadata=fs::symlink_metadata(&path).map_err(|_| "candidate file metadata unavailable")?;
            require(metadata.mode()&0o7777==*mode,"candidate file mode differs")?;
            // The immutable whole-tree digest independently pins each captured
            // file; no digest is selected by a live root command or path.
            let expected=sha256(&read_candidate_bytes(&path,budget)?);
            let file=CapturedSource::read(&path,&expected,None,budget)?; hashes.insert(*relative,sha256(&file.bytes)); captured.insert(relative.to_string(),(file,*mode));
        }
        canonical.extend_from_slice(format!("{}|{mode:o}|{relative}\0",if *directory {"Directory"} else {"Regular File"}).as_bytes());
    }
    for (relative,_,directory) in CANDIDATE_NODES { if !directory { canonical.extend_from_slice(format!("{relative}\0{}\0",hashes[relative]).as_bytes()); } }
    require(sha256(&canonical)==request.get("driver_tree_sha256") && hashes["Contents/MacOS/OpensteamerVirtualMicrophone"]==request.get("driver_executable_sha256"),"candidate exact immutable tree/executable differs")?;
    for directory in &directories { directory.revalidate()?; } Ok((captured,directories))
}
fn read_candidate_bytes(path:&Path,budget:&mut Budget)->Result<Vec<u8>> {
    budget.check()?; let mut file=OpenOptions::new().read(true).custom_flags(NOFOLLOW|CLOEXEC).open(path).map_err(|_| "candidate initial nofollow read failed")?;
    let metadata=file.metadata().map_err(|_|"candidate initial metadata failed")?;
    require(metadata.is_file()&&metadata.uid()==501&&metadata.nlink()==1&&metadata.len()<=MAX_FILE as u64,"candidate initial extent/type refused")?;
    let mut bytes=Vec::new(); let mut chunk=[0;65_536]; loop { budget.check()?; let count=file.read(&mut chunk).map_err(|_|"candidate initial read failed")?; if count==0 {break;} require(bytes.len()+count<=MAX_FILE,"candidate initial extent exceeded")?; budget.consume(count)?; bytes.extend_from_slice(&chunk[..count]); }
    Ok(bytes)
}

fn simple_name(name:&str)->Result<CString>{ require(!name.is_empty()&&name!="."&&name!=".."&&!name.contains('/')&&name.len()<=255,"seal relative name refused")?; CString::new(name).map_err(|_|"seal relative name NUL refused".into()) }
fn absent(parent:&sealed_fs::HeldDirectory,name:&str)->Result<()> {
    parent.revalidate()?;
    require(matches!(fs::symlink_metadata(parent_path(parent)?.join(name)),Err(error) if error.kind()==std::io::ErrorKind::NotFound),"seal namespace already exists or absence is unproved")
}
// The small mapping avoids introducing request-selectable root destinations.
fn parent_path(parent:&sealed_fs::HeldDirectory)->Result<PathBuf>{
    let fd=parent.descriptor().as_raw_fd();
    unsafe extern "C" { fn fcntl(fd:i32,command:i32,...)->i32; }
    let mut bytes=[0u8;1024]; require(unsafe{fcntl(fd,50,bytes.as_mut_ptr())}==0,"seal held directory path unavailable")?;
    let count=bytes.iter().position(|b|*b==0).ok_or("seal held directory path extent refused")?;
    let value=std::str::from_utf8(&bytes[..count]).map_err(|_|"seal directory path UTF-8 refused")?; require(canonical_path(value)||value=="/","seal directory path malformed")?; Ok(value.into())
}
fn mkdir(parent:&sealed_fs::HeldDirectory,name:&str,mode:u32)->Result<sealed_fs::HeldDirectory> {
    os::supervisor_check()?;
    parent.revalidate()?; let path=parent_path(parent)?.join(name); let name=simple_name(name)?;
    os::supervisor_check()?;
    require(unsafe{mkdirat(parent.descriptor().as_raw_fd(),name.as_ptr(),mode as u16)}==0,"seal exclusive directory creation failed")?;
    let fd=unsafe{openat(parent.descriptor().as_raw_fd(),name.as_ptr(),NOFOLLOW|DIRECTORY|CLOEXEC)};
    require(fd>=0,"seal new directory descriptor unavailable")?; let file=unsafe{File::from_raw_fd(fd)};
    require(unsafe{fchown(fd,0,0)}==0&&unsafe{fchmod(fd,mode as u16)}==0,"seal new directory owner/mode setup failed")?;
    sealed_fs::no_acl(&file)?; os::supervisor_check()?;
    file.sync_all().map_err(|_|"seal new directory sync failed")?; parent.descriptor().sync_all().map_err(|_|"seal directory parent sync failed")?;
    os::supervisor_check()?;
    parent.revalidate()?; sealed_fs::HeldDirectory::capture(&path,0,0,mode)
}
fn write(parent:&sealed_fs::HeldDirectory,name:&str,bytes:&[u8],mode:u32)->Result<Identity> {
    os::supervisor_check()?;
    require(bytes.len()<=MAX_FILE&&matches!(mode,0o400|0o444|0o555|0o644|0o755),"seal write extent/mode refused")?;
    parent.revalidate()?; let name=simple_name(name)?;
    os::supervisor_check()?;
    let fd=unsafe{openat(parent.descriptor().as_raw_fd(),name.as_ptr(),1|CREATE|EXCLUSIVE|NOFOLLOW|CLOEXEC,0o600u32)};
    require(fd>=0,"seal exclusive file creation failed")?; let mut file=unsafe{File::from_raw_fd(fd)};
    require(unsafe{fchown(fd,0,0)}==0,"seal file owner setup failed")?; sealed_fs::no_acl(&file)?;
    os::supervisor_check()?;
    file.write_all(bytes).map_err(|_|"seal file write failed")?; require(unsafe{fchmod(fd,mode as u16)}==0,"seal file mode setup failed")?;
    os::supervisor_check()?;
    file.sync_all().map_err(|_|"seal file durable sync failed")?; parent.descriptor().sync_all().map_err(|_|"seal file parent durable sync failed")?;
    let identity=Identity::of(&file.metadata().map_err(|_|"sealed file stat unavailable")?);
    require(identity.uid==0&&identity.gid==0&&identity.mode&0o7777==mode&&identity.links==1&&identity.size==bytes.len() as u64,"sealed file metadata differs")?;
    let path=parent_path(parent)?.join(name.to_str().map_err(|_|"seal name UTF-8 refused")?);
    require(Identity::of(&fs::symlink_metadata(&path).map_err(|_|"sealed file path disappeared")?)==identity,"sealed file descriptor/path differs")?;
    os::supervisor_check()?;
    let readback=read_pinned(&path,&sha256(bytes),0,mode,MAX_FILE)?; require(readback==bytes,"sealed file readback differs")?; parent.revalidate()?;
    os::supervisor_check()?; Ok(identity)
}
fn static_parent(base:&sealed_fs::HeldDirectory,name:&str,mode:u32)->Result<sealed_fs::HeldDirectory> {
    let path=Path::new(BASE).join(name);
    match fs::symlink_metadata(&path) {
        Ok(_)=>sealed_fs::HeldDirectory::capture(&path,0,0,mode),
        Err(error) if error.kind()==std::io::ErrorKind::NotFound=>mkdir(base,name,mode),
        Err(_)=>Err("seal static parent absence unproved".into()),
    }
}

struct HeldBootstrap{directories:Vec<sealed_fs::HeldDirectory>,file:File,path:PathBuf,identity:Identity}
impl HeldBootstrap{
    fn revalidate(&self)->Result<()>{
        for directory in &self.directories{directory.revalidate()?;}
        require(Identity::of(&self.file.metadata().map_err(|_|"held bootstrap descriptor metadata failed")?)==self.identity&&
                Identity::of(&fs::symlink_metadata(&self.path).map_err(|_|"held bootstrap path disappeared")?)==self.identity,"held bootstrap executable changed")?;
        sealed_fs::no_acl(&self.file)
    }
}
fn held_bootstrap(request:&Request,worker_sha:&str)->Result<HeldBootstrap> {
    let directory=Path::new(BASE).join(format!("microphone-v9-bootstrap-{}",request.get("nonce")));
    let worker=directory.join("worker");
    require(env::current_exe().map_err(|_|"sealer current image path unavailable")?==worker,"sealer was not executed from exact trusted bootstrap role")?;
    let held=sealed_fs::root_ancestry_path(&directory,0o711)?;
    let mut names=Vec::new();
    for child in fs::read_dir(&directory).map_err(|_|"bootstrap layout unavailable")? {
        require(names.is_empty(),"bootstrap contains more than the one worker node")?;
        names.push(child.map_err(|_|"bootstrap child unavailable")?.file_name());
    }
    require(names==vec![std::ffi::OsString::from("worker")],"bootstrap exact worker layout differs")?;
    let metadata=fs::symlink_metadata(&worker).map_err(|_|"bootstrap worker metadata unavailable")?;
    require(metadata.is_file()&&metadata.uid()==0&&metadata.gid()==0&&metadata.mode()&0o7777==0o555&&metadata.nlink()==1,"bootstrap worker owner/type/mode refused")?;
    let file=OpenOptions::new().read(true).custom_flags(NOFOLLOW|CLOEXEC).open(&worker).map_err(|_|"bootstrap worker nofollow descriptor unavailable")?;
    sealed_fs::no_acl(&file)?;
    read_pinned(&worker,worker_sha,0,0o555,MAX_FILE)?;
    require(Identity::of(&file.metadata().map_err(|_|"bootstrap worker after-stat unavailable")?)==Identity::of(&metadata),"bootstrap worker changed during admission")?;
    let bootstrap=HeldBootstrap{directories:held,file,path:worker,identity:Identity::of(&metadata)};bootstrap.revalidate()?;Ok(bootstrap)
}

/// Stages fixed files only. Does not make a deployment/readiness claim.
/// The trusted OS caller must also own a bounded supervisor for this process:
/// cooperative monotonic checks cannot cancel an indefinitely blocked syscall.
pub(super) fn seal_original_uid_inputs(request_path:&Path,manifest_path:&Path,pins:TrustedPins<'_>)->Result<SealedAttempt> {
    require(unsafe{getuid()}==0&&unsafe{geteuid()}==0,"sealing requires independently pinned root dispatch")?;
    require(hex(pins.request_sha256,64)&&hex(pins.manifest_sha256,64)&&hex(pins.worker_sha256,64),"external seal trust pins malformed")?;
    let mut budget=Budget::new();
    let request_source=CapturedSource::read(request_path,pins.request_sha256,None,&mut budget)?;
    require(request_source.identity.mode&0o7777==0o600&&request_source.bytes.len()<=MAX_REQUEST,"original-UID request metadata refused")?;
    let request=Request::parse(&request_source.bytes,pins.request_sha256)?;
    require(request.get("worker_sha256")==pins.worker_sha256,"external worker pin differs from request crosslink")?;
    let bootstrap=held_bootstrap(&request,pins.worker_sha256)?;
    require(manifest_path.file_name()==Some(std::ffi::OsStr::new("build-proof.json")),"seal build manifest basename differs")?;
    let build=manifest_path.parent().ok_or("seal build directory absent")?;
    require(build.parent()==Some(Path::new("/private/tmp"))&&build.file_name().and_then(|name|name.to_str()).is_some_and(|name|name.starts_with("beluga-microphone-v9-guards.")&&name.len()<=128),"seal build is not exact owned build namespace")?;
    let build_meta=fs::symlink_metadata(build).map_err(|_|"seal build directory metadata unavailable")?;
    let build_directory=sealed_fs::HeldDirectory::capture(build,501,build_meta.gid(),0o700)?;
    let manifest=CapturedSource::read(manifest_path,pins.manifest_sha256,None,&mut budget)?;
    require(manifest.identity.mode&0o7777==0o600,"seal build manifest mode differs")?;
    // Source/toolchain/command records are typed, duplicate-rejecting data in
    // the independently pinned manifest. The original-UID dispatch revalidates
    // those records; root reads only bytes it actually stages plus fixed
    // producer records. This is not a second privileged build audit.
    let (records,_retained)=parse_manifest(&manifest.bytes,&request,build)?;
    let mut plan=Plan{staged:BTreeMap::new(),held:vec![request_source],manifest};
    for (destination,record) in &records { let source=CapturedSource::read(&record.path,&record.digest,Some(record),&mut budget)?;
        require(!source.bytes.is_empty(),"sealed executable/dependency role is empty")?;
        let mode=if let Some((_,_,_,_,mode))=INPUTS.iter().find(|(relative,_,_,_,_)|*relative==destination){*mode}else if destination=="tools/gate_inputs.txt"{0o444}else{0o555};
        plan.staged.insert(destination.clone(),(source,mode)); }
    gate_inputs(&plan.staged["tools/gate_inputs.txt"].0.bytes,&records)?;
    for (name,digest) in ARTIFACT_RECORDS { plan.held.push(CapturedSource::read(&Path::new(ARTIFACT).join(name),digest,None,&mut budget)?); }
    let (candidate,candidate_directories)=capture_candidate(&request,&mut budget)?;
    build_directory.revalidate()?;
    for source in plan.held.iter().chain(plan.staged.values().map(|(file,_)|file)).chain(candidate.values().map(|(file,_)|file)).chain(std::iter::once(&plan.manifest)){source.revalidate()?;}
    budget.check()?;
    let ancestors=sealed_fs::root_ancestry_path(Path::new(BASE),0o755)?; let base=ancestors.last().ok_or("seal fixed base not held")?;
    let states=static_parent(base,"microphone-v9-transactions",0o700)?;
    let controller_lock=sealed_fs::RootLock::acquire(&states)?;
    let executables=static_parent(base,"microphone-v9-executables",0o711)?;
    absent(&states,request.get("namespace"))?; absent(&executables,request.get("namespace"))?;
    let state=mkdir(&states,request.get("namespace"),0o700)?;
    let marker=format!("schema=opensteamer.microphone-v9-sealing.v1\nnamespace={}\nnonce={}\nrequest_sha256={}\nbuild_manifest_sha256={}\nworker_sha256={}\n",request.get("namespace"),request.get("nonce"),pins.request_sha256,pins.manifest_sha256,pins.worker_sha256);
    write(&state,"SEALING_INCOMPLETE",marker.as_bytes(),0o400)?;
    let exec=mkdir(&executables,request.get("namespace"),0o711)?;
    let tools=mkdir(&exec,"tools",0o711)?; let product=mkdir(&tools,"product",0o711)?; let observers=mkdir(&tools,"observers",0o711)?;
    for name in ["journal","prior","failed","probes"]{mkdir(&state,name,0o700)?;}
    write(&state,"request.txt",&plan.held[0].bytes,0o400)?; write(&state,"build-manifest.json",&plan.manifest.bytes,0o400)?;
    for (destination,(source,mode)) in &plan.staged { budget.check()?; source.revalidate()?;
        let (parent,name)=if let Some(name)=destination.strip_prefix("tools/product/"){(&product,name)}else if let Some(name)=destination.strip_prefix("tools/observers/"){(&observers,name)}else if let Some(name)=destination.strip_prefix("tools/"){(&tools,name)}else{(&exec,destination.as_str())};
        write(parent,name,&source.bytes,*mode)?;
    }
    let candidate_root=mkdir(&state,"candidate.driver",0o755)?;
    let mut parents=BTreeMap::new(); parents.insert(".".to_string(),candidate_root);
    for (relative,mode,directory) in CANDIDATE_NODES.iter().skip(1) {
        budget.check()?; let path=Path::new(relative); let parent=path.parent().and_then(|value|value.to_str()).ok_or("fixed candidate parent malformed")?;
        let parent=if parent.is_empty(){"."}else{parent}; let name=path.file_name().and_then(|value|value.to_str()).ok_or("fixed candidate basename malformed")?;
        if *directory { let held=mkdir(&parents[parent],name,*mode)?; parents.insert(relative.to_string(),held); }
        else { let source=&candidate[*relative].0; source.revalidate()?; write(&parents[parent],name,&source.bytes,*mode)?; }
    }
    for source in plan.held.iter().chain(plan.staged.values().map(|(file,_)|file)).chain(candidate.values().map(|(file,_)|file)).chain(std::iter::once(&plan.manifest)){source.revalidate()?;}
    for directory in &candidate_directories{directory.revalidate()?;} build_directory.revalidate()?;
    let (root_identity,executable_identity)=backend::verify_bundle(&Path::new(&request.root_path()).join("candidate.driver"),request.get("driver_tree_sha256"),request.get("driver_executable_sha256"),0)?;
    let mut authority=BTreeMap::new(); authority.insert("schema","opensteamer.microphone-v9-root-authority.v1".to_string());
    for key in ["namespace","nonce","guard_tooling_commit","guard_tooling_tree","worker_sha256","idle_helper_sha256","both_order_probe_sha256","route_guardian_sha256"]{authority.insert(key,request.get(key).to_string());}
    authority.insert("request_sha256",pins.request_sha256.to_string()); authority.insert("build_manifest_sha256",pins.manifest_sha256.to_string());
    authority.insert("host_gate_sha256",records["tools/opensteamer-microphone-v9-host-gate.rb"].digest.clone()); authority.insert("gate_inputs_sha256",records["tools/gate_inputs.txt"].digest.clone());
    authority.insert("candidate_root_device",root_identity.device.to_string()); authority.insert("candidate_root_inode",root_identity.inode.to_string()); authority.insert("candidate_executable_inode",executable_identity.inode.to_string());
    let authority=authority.iter().map(|(key,value)|format!("{key}={value}\n")).collect::<String>(); write(&state,"authority.txt",authority.as_bytes(),0o400)?;
    budget.check()?; for held in &ancestors{held.revalidate()?;} bootstrap.revalidate()?;states.revalidate()?;executables.revalidate()?;state.revalidate()?;exec.revalidate()?;controller_lock.revalidate()?;
    write(&state,"SEALING_COMPLETE",marker.as_bytes(),0o400)?;
    Ok(SealedAttempt{state:PathBuf::from(request.root_path()),executables:PathBuf::from(EXEC_BASE).join(request.get("namespace")),authority_sha256:sha256(authority.as_bytes())})
}

#[cfg(test)]mod tests {
    use super::*;
    #[test]fn seal_checkpoint_observes_supervisor_cancellation_without_extending_own_deadline(){
        let budget=Budget::new();let called=std::cell::Cell::new(false);
        assert_eq!(budget.check_supervision(||{called.set(true);Err("SUPERVISOR_ABORT".into())}).unwrap_err(),"SUPERVISOR_ABORT");
        assert!(called.get());assert!(budget.check_supervision(||Ok(())).is_ok());
        let expired=Budget{deadline:Instant::now(),consumed:0};
        assert_eq!(expired.check_supervision(||Ok(())).unwrap_err(),"seal monotonic deadline exceeded");
        // The fixture callback is private test data; it cannot grant root
        // admission or replace the production os::supervisor_check channel.
        assert_eq!(expired.check_supervision(||Err("SUPERVISOR_EOF".into())).unwrap_err(),"SUPERVISOR_EOF");
    }
    fn record(path:&str,digest:&str)->Json {
        Json::Object(BTreeMap::from([
            ("path".into(),Json::Text(path.into())),("sha256".into(),Json::Text(digest.into())),
            ("identity".into(),Json::Array([1,2,501,20,33152,1,8,1,0,1,0].iter().map(|number|Json::Number(number.to_string())).collect())),
        ]))
    }
    fn fixture()->(Request,Json,PathBuf){
        let mut fields=FIELDS.iter().map(|key|(key.to_string(),"a".repeat(64))).collect::<BTreeMap<_,_>>();
        for(key,value)in EXACT_FIELDS{fields.insert(key.to_string(),value.to_string());}
        fields.insert("guard_tooling_commit".into(),"b".repeat(40));fields.insert("guard_tooling_tree".into(),"c".repeat(40));
        let request=Request{fields,sha256:"d".repeat(64)};let build=PathBuf::from("/private/tmp/beluga-microphone-v9-guards.fixture");
        let mut inputs=BTreeMap::new();
        for(destination,key,origin,relative,_)in INPUTS{
            let base=match *origin{"product"=>PRODUCT,"observers"=>OBSERVERS,_=>TOOLING};
            let digest=PRODUCT_PINS.iter().find(|(item,_)|item==key).map(|(_,digest)|digest.to_string()).unwrap_or_else(||"a".repeat(64));
            inputs.insert(destination.to_string(),record(&format!("{base}/{relative}"),&digest));
        }
        inputs.insert("tools/gate_inputs.txt".into(),record(build.join("gate_inputs.txt").to_str().unwrap(),&"a".repeat(64)));
        let tools=TOOLS.iter().map(|(role,_,basename,key)|(role.to_string(),record(build.join(basename).to_str().unwrap(),request.get(key)))).collect();
        let public=format!("{TOOLING}/iOS/opensteamer/scripts/physical-blackhole-microphone-probe.swift");let derived=build.join("public/main.swift").to_str().unwrap().to_string();
        let sources=Json::Object(BTreeMap::from([(public.clone(),record(&public,&"a".repeat(64))),(derived.clone(),record(&derived,&"a".repeat(64)))]));
        let commands=Json::Array(vec![Json::Object(BTreeMap::from([
            ("argv".into(),Json::Array(vec![Json::Text("/usr/bin/git".into()),Json::Text("status".into())])),("pid".into(),Json::Number("1".into())),
            ("exitStatus".into(),Json::Number("0".into())),("termSignal".into(),Json::Null),("timedOutOrLogBound".into(),Json::Bool(false)),
            ("stdout".into(),record(build.join("commands/001.stdout").to_str().unwrap(),&"a".repeat(64))),
            ("stderr".into(),record(build.join("commands/001.stderr").to_str().unwrap(),&"a".repeat(64))),
        ]))]);
        let mut manifest=BTreeMap::new();
        for(key,value)in [("schema","opensteamer.microphone-v9.native-guard-build.v1"),("productCommit",request.get("product_commit")),("productTree",request.get("product_tree")),("guardToolingCommit",request.get("guard_tooling_commit")),("guardToolingTree",request.get("guard_tooling_tree"))]{manifest.insert(key.into(),Json::Text(value.into()));}
        manifest.insert("deploymentAuthority".into(),Json::Bool(false));manifest.insert("liveQueriesPerformed".into(),Json::Bool(false));
        manifest.insert("sources".into(),sources);manifest.insert("commands".into(),commands);manifest.insert("tools".into(),Json::Object(tools));manifest.insert("sealedInputs".into(),Json::Object(inputs));
        for key in ["swiftCompiler","rustCompiler","sdkSettings"]{manifest.insert(key.into(),record(&format!("/fixture/{key}"),&"a".repeat(64)));}
        (request,Json::Object(manifest),build)
    }
    fn dump(value:&Json)->String {
        match value{Json::Null=>"null".into(),Json::Bool(value)=>value.to_string(),Json::Number(value)=>value.clone(),Json::Text(value)=>format!("{value:?}"),
            Json::Array(values)=>format!("[{}]",values.iter().map(dump).collect::<Vec<_>>().join(",")),
            Json::Object(values)=>format!("{{{}}}",values.iter().map(|(key,value)|format!("{key:?}:{}",dump(value))).collect::<Vec<_>>().join(","))}
    }
    fn fields_mut(value:&mut Json)->&mut BTreeMap<String,Json>{if let Json::Object(value)=value{value}else{panic!("fixture object")}}
    fn accepted(value:&Json,request:&Request,build:&Path)->bool{parse_manifest(dump(value).as_bytes(),request,build).is_ok()}
    #[test]fn strict_native_build_manifest_binds_producer_product_and_later_guard_generation(){
        let(request,manifest,build)=fixture();assert!(accepted(&manifest,&request,&build));
        let keys=object(&manifest).unwrap().keys().cloned().collect::<Vec<_>>();
        for key in keys{let mut mutant=manifest.clone();fields_mut(&mut mutant).remove(&key);assert!(!accepted(&mutant,&request,&build),"missing {key}");}
        for key in ["schema","productCommit","productTree","guardToolingCommit","guardToolingTree"]{let mut mutant=manifest.clone();fields_mut(&mut mutant).insert(key.into(),Json::Text("incorrect".into()));assert!(!accepted(&mutant,&request,&build));}
        for key in ["deploymentAuthority","liveQueriesPerformed"]{let mut mutant=manifest.clone();fields_mut(&mut mutant).insert(key.into(),Json::Bool(true));assert!(!accepted(&mutant,&request,&build));}
        let mut mutant=manifest.clone();fields_mut(&mut mutant).insert("commandAsRoot".into(),Json::Text("/bin/sh".into()));assert!(!accepted(&mutant,&request,&build));
        let bytes=dump(&manifest);assert!(parse_manifest(bytes.replacen("{","{\"schema\":\"duplicate\",",1).as_bytes(),&request,&build).is_err());
    }
    #[test]fn role_sets_paths_compiled_byte_pins_and_derived_source_are_exact(){
        let(request,manifest,build)=fixture();
        for(role,_,_,_)in TOOLS{
            let mut mutant=manifest.clone();let tools=fields_mut(fields_mut(&mut mutant).get_mut("tools").unwrap());tools.remove(*role);assert!(!accepted(&mutant,&request,&build));
            let mut mutant=manifest.clone();let tools=fields_mut(fields_mut(&mut mutant).get_mut("tools").unwrap());let tool=fields_mut(tools.get_mut(*role).unwrap());tool.insert("sha256".into(),Json::Text("f".repeat(64)));assert!(!accepted(&mutant,&request,&build));
            let mut mutant=manifest.clone();let tools=fields_mut(fields_mut(&mut mutant).get_mut("tools").unwrap());let tool=fields_mut(tools.get_mut(*role).unwrap());tool.insert("path".into(),Json::Text("/private/other/executable".into()));assert!(!accepted(&mutant,&request,&build));
        }
        for(destination,_,_,_,_)in INPUTS{
            let mut mutant=manifest.clone();let inputs=fields_mut(fields_mut(&mut mutant).get_mut("sealedInputs").unwrap());inputs.remove(*destination);assert!(!accepted(&mutant,&request,&build));
            let mut mutant=manifest.clone();let inputs=fields_mut(fields_mut(&mut mutant).get_mut("sealedInputs").unwrap());let record=fields_mut(inputs.get_mut(*destination).unwrap());record.insert("path".into(),Json::Text("/private/other/input".into()));assert!(!accepted(&mutant,&request,&build));
        }
        for(destination,key,_,_,_)in INPUTS.iter().filter(|(_,key,_,_,_)|*key!="host_gate_sha256"){
            let mut mutant=manifest.clone();let inputs=fields_mut(fields_mut(&mut mutant).get_mut("sealedInputs").unwrap());fields_mut(inputs.get_mut(*destination).unwrap()).insert("sha256".into(),Json::Text("f".repeat(64)));assert!(!accepted(&mutant,&request,&build),"wrong {key}");
        }
        let mut mutant=manifest.clone();let sources=fields_mut(fields_mut(&mut mutant).get_mut("sources").unwrap());fields_mut(sources.get_mut(build.join("public/main.swift").to_str().unwrap()).unwrap()).insert("sha256".into(),Json::Text("f".repeat(64)));assert!(!accepted(&mutant,&request,&build));
    }
    #[test]fn exact_dependency_table_and_gate_crosslinks(){
        assert_eq!(INPUTS.len(),8);assert_eq!(TOOLS.len(),4);assert_eq!(CANDIDATE_NODES.len(),11);
        let records=INPUTS.iter().map(|(destination,_,_,_,_)|(destination.to_string(),SourceRecord{path:"/fixture".into(),digest:"a".repeat(64),identity:[0;11]})).collect::<BTreeMap<_,_>>();
        let bytes=String::from("schema=opensteamer.microphone-v9-gate-inputs.v1\n")+&INPUTS.iter().map(|(_,key,_,_,_)|format!("{key}={}\n","a".repeat(64))).collect::<String>();
        assert!(gate_inputs(bytes.as_bytes(),&records).is_ok());
        for mutant in [bytes.clone()+"host_gate_sha256=duplicate\n",bytes.replace("controller_sha256=","unknown_sha256="),bytes.replace('\n',"\r\n"),bytes.trim_end().into(),bytes.replacen(&"a".repeat(64),&"b".repeat(64),1)]{assert!(gate_inputs(mutant.as_bytes(),&records).is_err());}
    }
    #[test]fn source_record_rejects_authority_claims_aliases_and_wrong_types(){
        let bytes=b"{\"path\":\"/private/tmp/fixture\",\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"identity\":[1,2,501,20,33152,1,8,1,0,1,0]}";
        assert!(SourceRecord::parse(&Parser::parse(bytes).unwrap()).is_ok());
        let text=std::str::from_utf8(bytes).unwrap();
        for mutant in [text.replace("501","0"),text.replace("33152","33206"),text.replace("/private/tmp/fixture","/private/tmp/../fixture"),text.replace("\"identity\":[","\"identity\":\""),text.replace("\"path\":","\"authority\":true,\"path\":"),text.replace("[1,2,501","[1,2,\"501\""),text.replace("1,0,1,0]","1,1000000000,1,0]")]{
            assert!(Parser::parse(mutant.as_bytes()).and_then(|value|SourceRecord::parse(&value)).is_err());
        }
        assert!(Parser::parse(text.replace("\"path\":","\"path\":\"duplicate\",\"path\":").as_bytes()).is_err());
    }
    #[test]fn root_sealing_never_admits_original_uid_or_creates_namespace(){
        if unsafe{geteuid()}!=0 {assert!(seal_original_uid_inputs(Path::new("/nonexistent"),Path::new("/nonexistent"),TrustedPins{request_sha256:&"a".repeat(64),manifest_sha256:&"b".repeat(64),worker_sha256:&"c".repeat(64)}).is_err());}
        assert!(simple_name("../unsafe").is_err());assert!(simple_name("/").is_err());assert!(simple_name("").is_err());
    }
    #[test]fn real_original_uid_held_source_rejects_replacement_hardlink_mode_and_bytes(){
        use std::os::unix::fs::{symlink,PermissionsExt};
        // These are owned private fixture files only; no privileged dispatcher,
        // host/route/helper query, root path or actual staging method is called.
        if unsafe{geteuid()}!=501{return;}
        let temporary=std::env::temp_dir().join(format!("beluga-v9-seal-source-test-{}",std::process::id()));
        fs::create_dir(&temporary).unwrap();fs::set_permissions(&temporary,fs::Permissions::from_mode(0o700)).unwrap();
        let directory=fs::canonicalize(&temporary).unwrap();let path=directory.join("source");
        let mut file=OpenOptions::new().write(true).create_new(true).mode(0o600).open(&path).unwrap();file.write_all(b"reviewed fixture").unwrap();file.sync_all().unwrap();drop(file);
        let digest=sha256(b"reviewed fixture");let held=CapturedSource::read(&path,&digest,None,&mut Budget::new()).unwrap();
        let alias=directory.join("alias");symlink(&path,&alias).unwrap();assert!(CapturedSource::read(&alias,&digest,None,&mut Budget::new()).is_err());fs::remove_file(&alias).unwrap();
        fs::hard_link(&path,&alias).unwrap();assert!(CapturedSource::read(&path,&digest,None,&mut Budget::new()).is_err());assert!(held.revalidate().is_err());fs::remove_file(&alias).unwrap();
        fs::set_permissions(&path,fs::Permissions::from_mode(0o666)).unwrap();assert!(CapturedSource::read(&path,&digest,None,&mut Budget::new()).is_err());
        fs::set_permissions(&path,fs::Permissions::from_mode(0o600)).unwrap();fs::write(&path,b"changed fixture!").unwrap();assert!(CapturedSource::read(&path,&digest,None,&mut Budget::new()).is_err());
        fs::remove_file(&path).unwrap();fs::remove_dir(&directory).unwrap();
    }
}
