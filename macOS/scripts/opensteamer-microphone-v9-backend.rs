//! Narrow root-sealed OS adapter components. Not wired to live CLI admission
//! until the complete transaction and independent whole-path review pass.
use super::*;
use std::fs::File;
use std::os::fd::AsRawFd;
use std::os::unix::fs::FileExt;
use std::path::PathBuf;
use std::time::Duration;
use std::time::Instant;

const EXECUTABLES:&str="/Library/Application Support/opensteamer/microphone-v9-executables";
const DRIVER_NAME:&str="OpensteamerVirtualMicrophone.driver";
const DRIVER_EXE:&str="Contents/MacOS/OpensteamerVirtualMicrophone";
const DRIVER_HOST_ID:&str="com.apple.audio.Core-Audio-Driver-Service.helper";
const DRIVER_HOST_BUNDLE:&str="/System/Library/Frameworks/CoreAudio.framework/Versions/A/XPCServices/com.apple.audio.Core-Audio-Driver-Service.helper.xpc";
const DRIVER_HOST_EXE:&str="/System/Library/Frameworks/CoreAudio.framework/Versions/A/XPCServices/com.apple.audio.Core-Audio-Driver-Service.helper.xpc/Contents/MacOS/com.apple.audio.Core-Audio-Driver-Service.helper";
const DRIVER_HOST_DISPLAY:&str="Core Audio Driver (OpensteamerVirtualMicrophone.driver)";
const DRIVER_HOST_LSOF:&str="Core Audio Driver (OpensteamerV";
pub(super) const RECONCILE_011_WORKER:&str="/Library/Application Support/opensteamer/microphone-v9-reconcile-011/worker";
const CONTINUE_011_WORKER:&str="/Library/Application Support/opensteamer/microphone-v9-reconcile-011-continuation-001/worker";
const CONTINUE_011_002_WORKER:&str="/Library/Application Support/opensteamer/microphone-v9-reconcile-011-continuation-002/worker";
const FAILED_011_NAMESPACE:&str="driver-microphone-v9-151f574a1c3c354b";
const FAILED_011_NONCE:&str="0c6553bf7c2322bc87fc0b1580b739e2db7820fd8405ad4b8c9e33f6d0f8f0d5";
const FAILED_011_REQUEST:&str="18c655bff4dd81a3fd9435aae9940fbc15fd92d6b6975a5fdb4245e3e7507178";
const FAILED_011_AUTHORITY:&str="afebc8d84640a8ac3155a70f51d8bc06c24b4f40ec0488ad2998cfa4bba560c7";
const FAILED_011_WORKER:&str="d91091c850d22ec315cc08ca4add458efb5dfb3e29b26080ba0665dea9af5613";
const FAILURE_TERMINAL:&str="FAILED_NO_EFFECTS_RECONCILED";
const CONTINUATION_TERMINAL:&str="FAILED_NO_EFFECTS_RECONCILED_CONTINUATION_001";
const CONTINUATION_002_TERMINAL:&str="FAILED_NO_EFFECTS_RECONCILED_CONTINUATION_002";
const CONSUMED_011_RECONCILER:&str="86423d013e9d0790d09d715e6052ec0cf6dc2451d0827eb310a82d1540cfc983";
const CONSUMED_011_CONTINUATION:&str="a7b31b495d0719f27991920606a1728ad4b15a4d366cbe57fc59180fc7dcd165";
const CONSUMED_011_CONTINUATION_FENCE:&str="2153c1bbc602d60f531856aa26e21f95bcf9f63237995a784fac8569a1ae907c";
const CONSUMED_011_CONTINUATION_OWNER:&str="94114";
const CONSUMED_011_CONTINUATION_METADATA:&str="5340ac78e0339d6d095ed3c227fd10f3471424660f4608fa51ec9b7673c13cab";
const HISTORICAL_011_FENCE:&str="7dade8d5ab2eaa0681cff8886e6702f9118ed65b27608ed1536e9d89b602d0e6";
const HISTORICAL_011_APPENDS:&[&str]=&["child-active-002","child-clean-002"];
const CONTINUATION_011_APPENDS:&[&str]=&["child-active-003","child-clean-003","gate-metadata-003.txt","gate-metadata-004.txt","continuation-001-host-before.txt","continuation-001-host-after.txt"];
const CONSUMED_CONTINUATION_011_APPENDS:&[&str]=&["child-active-003","child-clean-003","gate-metadata-003.txt"];
const CONTINUATION_002_APPENDS:&[&str]=&["child-active-004","child-clean-004","gate-metadata-004.txt","gate-metadata-005.txt","continuation-002-host-before.txt","continuation-002-host-after.txt"];
const FAILED_011_TOP:&[&str]=&["SEALING_COMPLETE","SEALING_INCOMPLETE","authority.txt","build-manifest.json","candidate.driver","child-active-001","child-clean-001","core-baseline.txt","driver-host-baseline.txt","failed","gate-metadata-001.txt","gate-metadata-002.txt","guardian-1.events","host-baseline.txt","journal","prior","probes","recovery-refusal.txt","request.txt"];
const RECONCILIATION_APPENDS:&[&str]=&["child-active-002","child-clean-002","gate-metadata-003.txt","gate-metadata-004.txt","reconciliation-host-before.txt","reconciliation-host-after.txt"];
const FAILED_011_PINS:&[(&str,&str)]=&[
    ("request.txt",FAILED_011_REQUEST),("authority.txt",FAILED_011_AUTHORITY),("build-manifest.json","ee5509a4aee0ecf18934091124b5ab499ddc7902e3e5f5b17eb1baa76648059d"),
    ("SEALING_COMPLETE","4b5bfcaa5e441d1067c86e9b176b00e937cd34393e2f6ba90ccc816a547d43d9"),("SEALING_INCOMPLETE","4b5bfcaa5e441d1067c86e9b176b00e937cd34393e2f6ba90ccc816a547d43d9"),
    ("child-active-001","dfda4cfedfba2e7b06a291e2e21c07e79a542fa2be75e880ddcb98352c76cc92"),("child-clean-001","dfda4cfedfba2e7b06a291e2e21c07e79a542fa2be75e880ddcb98352c76cc92"),
    ("core-baseline.txt","3a201dc331b2a2f4b9daaa152739aaa8f481baa426489517c3b893ed40d87e4a"),("driver-host-baseline.txt","c073cf4c8795f04736241a197a860f645d6360057b7c4c507dd0bfcb962a2128"),
    ("host-baseline.txt","fa1d6bf9a46ffe1bcac28b48918b1c7049bfeeeade02f4e990addcee7a3cc91b"),("gate-metadata-001.txt","5c262d8143c1fc958fd4c7524387b5486c88107a72bf427b95eae1420d6afdb3"),
    ("gate-metadata-002.txt","176132c4a84ee3f5d932f0adc1f832942d3528893f595f9ee73aadb5d149e720"),("recovery-refusal.txt","ccd9cd0d1eca61d6195aa829c47da5941574778a6cb27ce2fc174f7ad0e7ab6b"),
    ("guardian-1.events","e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),("journal/journal-001","514a6dfc6fdd8e6cea34a3a8fea3ecc4e9ea3d6374fe985d93b5eadff9e55fec")];
const FAILURE_TERMINAL_FIELDS:&[&str]=&["schema","terminal","namespace","nonce","request_sha256","authority_sha256","original_worker_sha256","reconciler_worker_sha256","original_inventory_sha256","final_inventory_sha256","reconciliation_child_fence_sha256","host_before_sha256","host_after_sha256","core_generation_sha256","driver_host_generation_sha256","observed_at_unix_ms","normal_restarts","rollback_restarts","original_cause","original_guardian_teardown","guardian_coverage_proven","deployment_verified","pcm_verified"];
const CONTINUATION_TERMINAL_FIELDS:&[&str]=&["schema","terminal","namespace","nonce","request_sha256","authority_sha256","original_worker_sha256","consumed_reconciler_worker_sha256","reconciler_worker_sha256","original_inventory_sha256","input_inventory_sha256","final_inventory_sha256","original_child_fence_sha256","historical_child_fence_sha256","reconciliation_child_fence_sha256","gate_before_sha256","gate_after_sha256","host_before_sha256","host_after_sha256","core_generation_sha256","driver_host_generation_sha256","observed_at_unix_ms","normal_restarts","rollback_restarts","original_cause","original_guardian_teardown","guardian_coverage_proven","deployment_verified","pcm_verified"];
const CONTINUATION_002_TERMINAL_FIELDS:&[&str]=&["schema","terminal","namespace","nonce","request_sha256","authority_sha256","original_worker_sha256","consumed_reconciler_worker_sha256","consumed_continuation_worker_sha256","reconciler_worker_sha256","original_inventory_sha256","input_inventory_sha256","final_inventory_sha256","original_child_fence_sha256","historical_child_fence_sha256","consumed_continuation_child_fence_sha256","consumed_continuation_gate_metadata_sha256","reconciliation_child_fence_sha256","gate_before_sha256","gate_after_sha256","host_before_sha256","host_after_sha256","core_generation_sha256","driver_host_generation_sha256","observed_at_unix_ms","normal_restarts","rollback_restarts","original_cause","original_guardian_teardown","guardian_coverage_proven","deployment_verified","pcm_verified"];
const HOST_EXE:&str="/Applications/opensteamer Host.app/Contents/MacOS/CaptureServer";
const HOST_FRAMEWORK:&str="/Applications/opensteamer Host.app/Contents/Frameworks/LiveKitWebRTC.framework/Versions/A/LiveKitWebRTC";
const HOST_INFO:&str="/Applications/opensteamer Host.app/Contents/Info.plist";
const HOST_PLIST:&str="/Users/ahmed/Library/LaunchAgents/org.example.opensteamer.worldwide.plist";
// Enabled after focused native tests and independent whole-path review. Root
// ownership, sealed authority, global containment and fresh gates still apply.
pub(super) const LIVE_ADMISSION:bool=true;
const GATE_FIELDS:&[&str]=&["schema","mode","namespace","nonce","observed_at_unix_ms","host_present","host_pid","host_launchd_runs",
    "host_start_identity_sha256","host_nonce","host_lock_device","host_lock_inode","host_display_identity_sha256","display_headless","readiness",
    "manager_generation","host_executable_sha256","host_framework_sha256","host_info_plist_sha256","host_launch_plist_sha256","input_uid","output_uid",
    "system_output_uid","routes_identity_sha256","session_quiescent","session_log_device","session_log_inode","session_log_size","session_log_reset_offset","session_log_sha256","session_log_tail_sha256","committed_host_terminal"];

const AUTHORITY_FIELDS:&[&str]=&["schema","namespace","nonce","request_sha256","guard_tooling_commit","guard_tooling_tree",
    "worker_sha256","idle_helper_sha256","both_order_probe_sha256","route_guardian_sha256","host_gate_sha256","gate_inputs_sha256",
    "build_manifest_sha256","candidate_root_device","candidate_root_inode","candidate_executable_inode"];
const CLEANUP_FIELDS:&[&str]=&["schema","namespace","nonce","request_sha256","group","uid","reason","detail_sha256"];
const CHILD_FENCE_FIELDS:&[&str]=&["schema","namespace","nonce","request_sha256","sequence","owner_pid"];
const GATE_METADATA_SCHEMA:&str="opensteamer.microphone-v9-root-gate-metadata.v1";
const GATE_METADATA_ROLES:&[&str]=&["prefix_identity","namespace_identity","tools_identity","product_identity","observers_identity"];
const GATE_METADATA_FIELDS:&[&str]=&["schema","namespace","nonce","request_sha256","worker_sha256","host_gate_sha256","mode","observed_at_unix_ms","sequence","acl_absent","xattrs_empty","prefix_identity","namespace_identity","tools_identity","product_identity","observers_identity"];

fn gate_identity_text(identity:&Identity)->Result<String>{
    if identity.device==0||identity.inode==0||identity.uid!=0||identity.gid!=0||identity.mode!=0o40711||identity.links==0||
        identity.mtime<0||identity.ctime<0||!(0..1_000_000_000).contains(&identity.mtime_nsec)||!(0..1_000_000_000).contains(&identity.ctime_nsec){return Err("gate directory full identity policy differs".into());}
    Ok(format!("{},{},{},{},{},{},{},{},{},{},{}",identity.device,identity.inode,identity.uid,identity.gid,identity.mode,identity.links,identity.size,identity.mtime,identity.mtime_nsec,identity.ctime,identity.ctime_nsec))
}
fn gate_identity_parse(value:&str)->Result<Identity>{
    let values=value.split(',').map(|value|if value=="0"{Ok(0)}else{positive(value)}).collect::<Result<Vec<_>>>()?;
    if values.len()!=11{return Err("gate directory identity field extent differs".into());}
    let identity=Identity{device:values[0],inode:values[1],uid:values[2].try_into().map_err(|_|"gate identity UID overflow")?,gid:values[3].try_into().map_err(|_|"gate identity GID overflow")?,mode:values[4].try_into().map_err(|_|"gate identity mode overflow")?,links:values[5],size:values[6],
        mtime:values[7].try_into().map_err(|_|"gate identity timestamp overflow")?,mtime_nsec:values[8].try_into().map_err(|_|"gate identity nanosecond overflow")?,ctime:values[9].try_into().map_err(|_|"gate identity timestamp overflow")?,ctime_nsec:values[10].try_into().map_err(|_|"gate identity nanosecond overflow")?};
    if gate_identity_text(&identity)?!=value{return Err("gate directory identity is not canonical".into());}Ok(identity)
}
fn validate_gate_metadata(bytes:&[u8],request:&Request,host_gate_sha:&str,sequence:usize,mode:Option<&str>)->Result<BTreeMap<String,String>>{
    let fields=strict_flat(bytes,GATE_METADATA_FIELDS,MAX_REQUEST)?;
    if !(1..=64).contains(&sequence)||!hex(host_gate_sha,64)||fields["schema"]!=GATE_METADATA_SCHEMA||fields["namespace"]!=request.get("namespace")||fields["nonce"]!=request.get("nonce")||fields["request_sha256"]!=request.sha256||fields["worker_sha256"]!=request.get("worker_sha256")||fields["host_gate_sha256"]!=host_gate_sha||
        positive(&fields["sequence"])?!=sequence as u64||fields["acl_absent"]!="true"||fields["xattrs_empty"]!="true"||!matches!(fields["mode"].as_str(),"candidate-present"|"host-absent"|"host-ready")||mode.is_some_and(|mode|fields["mode"]!=mode){return Err("root gate metadata crosslinks differ".into());}
    positive(&fields["observed_at_unix_ms"])?;
    let identities=GATE_METADATA_ROLES.iter().map(|role|gate_identity_parse(&fields[*role])).collect::<Result<Vec<_>>>()?;
    if identities.iter().any(|identity|identity.device!=identities[0].device)||identities.iter().enumerate().any(|(index,identity)|identities[..index].iter().any(|prior|(prior.device,prior.inode)==(identity.device,identity.inode))){return Err("root gate metadata directory roles alias or cross volumes".into());}
    Ok(fields)
}
fn gate_metadata_bytes(request:&Request,host_gate_sha:&str,mode:&str,observed:u64,sequence:usize,identities:&[Identity])->Result<Vec<u8>>{
    if identities.len()!=5{return Err("root gate metadata exact role count differs".into());}
    let mut fields=BTreeMap::new();
    for(key,value)in [("schema",GATE_METADATA_SCHEMA),("namespace",request.get("namespace")),("nonce",request.get("nonce")),("request_sha256",request.sha256.as_str()),("worker_sha256",request.get("worker_sha256")),("host_gate_sha256",host_gate_sha),("mode",mode),("acl_absent","true"),("xattrs_empty","true")]{fields.insert(key,value.to_string());}
    fields.insert("observed_at_unix_ms",observed.to_string());fields.insert("sequence",sequence.to_string());
    for(role,identity)in GATE_METADATA_ROLES.iter().zip(identities){fields.insert(role,gate_identity_text(identity)?);}
    let bytes=GATE_METADATA_FIELDS.iter().map(|key|format!("{key}={}\n",fields[key])).collect::<String>().into_bytes();
    validate_gate_metadata(&bytes,request,host_gate_sha,sequence,Some(mode))?;Ok(bytes)
}
fn gate_metadata_paths(namespace:&str)->[PathBuf;5]{
    let prefix=PathBuf::from(EXECUTABLES);let attempt=prefix.join(namespace);let tools=attempt.join("tools");
    [prefix,attempt,tools.clone(),tools.join("product"),tools.join("observers")]
}
struct GateDirectory{file:File,path:PathBuf,identity:Identity}
impl GateDirectory{
    fn capture(path:&Path)->Result<Self>{Self::capture_owned(path,0,0)}
    fn capture_owned(path:&Path,owner:u32,group:u32)->Result<Self>{
        if fs::canonicalize(path).map_err(|_|"gate directory canonical path unavailable")?!=path{return Err("gate directory alias refused".into());}
        let before=fs::symlink_metadata(path).map_err(|_|"gate directory path stat unavailable")?;
        if !before.is_dir()||before.uid()!=owner||before.gid()!=group||before.mode()!=0o40711{return Err("gate directory owner/type/mode refused".into());}
        let file=OpenOptions::new().read(true).custom_flags(NOFOLLOW|0x0010_0000).open(path).map_err(|_|"gate directory nofollow descriptor unavailable")?;
        let identity=Identity::of(&before);let held=Self{file,path:path.to_path_buf(),identity};held.revalidate()?;Ok(held)
    }
    fn revalidate(&self)->Result<()>{
        if fs::canonicalize(&self.path).map_err(|_|"gate directory canonical path disappeared")?!=self.path||Identity::of(&self.file.metadata().map_err(|_|"gate directory descriptor stat unavailable")?)!=self.identity||Identity::of(&fs::symlink_metadata(&self.path).map_err(|_|"gate directory path disappeared")?)!=self.identity{return Err("gate directory full descriptor/path identity changed".into());}
        sealed_fs::clean_gate_metadata(&self.file)?;
        if Identity::of(&self.file.metadata().map_err(|_|"gate directory descriptor after-stat unavailable")?)!=self.identity||Identity::of(&fs::symlink_metadata(&self.path).map_err(|_|"gate directory after-path disappeared")?)!=self.identity{return Err("gate directory changed during clean metadata inspection".into());}Ok(())
    }
}
struct GateMetadataFile{file:File,path:PathBuf,identity:Identity,bytes:Vec<u8>,digest:String}
impl GateMetadataFile{
    fn open(path:&Path,bytes:&[u8])->Result<Self>{Self::open_owned(path,bytes,0,0)}
    fn open_owned(path:&Path,bytes:&[u8],owner:u32,group:u32)->Result<Self>{
        if bytes.is_empty()||bytes.len()>MAX_REQUEST||fs::canonicalize(path).map_err(|_|"gate metadata proof canonical path unavailable")?!=path{return Err("gate metadata proof path/extent refused".into());}
        let before=fs::symlink_metadata(path).map_err(|_|"gate metadata proof path stat unavailable")?;
        if !before.is_file()||before.uid()!=owner||before.gid()!=group||before.mode()!=0o100400||before.nlink()!=1||before.len()!=bytes.len() as u64{return Err("gate metadata proof owner/type/mode/links/extent refused".into());}
        let file=OpenOptions::new().read(true).custom_flags(NOFOLLOW).open(path).map_err(|_|"gate metadata proof nofollow read-only open unavailable")?;
        let proof=Self{file,path:path.to_path_buf(),identity:Identity::of(&before),bytes:bytes.to_vec(),digest:sha256(bytes)};proof.revalidate()?;Ok(proof)
    }
    fn revalidate(&self)->Result<()>{
        unsafe extern "C"{fn fcntl(fd:i32,command:i32,...)->i32;}
        let flags=unsafe{fcntl(self.file.as_raw_fd(),3)};
        if flags<0||flags&3!=0||Identity::of(&self.file.metadata().map_err(|_|"gate metadata proof descriptor stat unavailable")?)!=self.identity||Identity::of(&fs::symlink_metadata(&self.path).map_err(|_|"gate metadata proof path disappeared")?)!=self.identity{return Err("gate metadata proof descriptor/path/access changed".into());}
        sealed_fs::clean_gate_metadata(&self.file)?;
        let mut actual=vec![0u8;self.bytes.len()+1];let count=self.file.read_at(&mut actual,0).map_err(|_|"gate metadata proof bounded read failed")?;
        if actual[..count]!=self.bytes||sha256(&actual[..count])!=self.digest||Identity::of(&self.file.metadata().map_err(|_|"gate metadata proof after-stat unavailable")?)!=self.identity||Identity::of(&fs::symlink_metadata(&self.path).map_err(|_|"gate metadata proof after-path disappeared")?)!=self.identity{return Err("gate metadata proof exact bytes/full identity changed".into());}Ok(())
    }
}
struct RootGateMetadata{directories:Vec<GateDirectory>,proof:GateMetadataFile}
impl RootGateMetadata{
    fn revalidate(&self)->Result<()>{
        // Attempt every retained check, including on a failed/aborted child.
        let mut errors=Vec::new();for directory in &self.directories{if let Err(error)=directory.revalidate(){errors.push(error);}}
        if let Err(error)=self.proof.revalidate(){errors.push(error);}if errors.is_empty(){Ok(())}else{Err(errors.join("; "))}
    }
}
fn gate_metadata_sequence(name:&str)->Result<Option<usize>>{
    if !name.starts_with("gate-metadata"){return Ok(None);}
    let number=name.strip_prefix("gate-metadata-").and_then(|number|number.strip_suffix(".txt")).ok_or("gate metadata proof filename malformed")?;
    if number.len()!=3||!number.bytes().all(|byte|byte.is_ascii_digit()){return Err("gate metadata proof filename sequence malformed".into());}
    let sequence=number.parse::<usize>().map_err(|_|"gate metadata proof sequence overflow")?;if !(1..=64).contains(&sequence){return Err("gate metadata proof sequence bound exceeded".into());}Ok(Some(sequence))
}
fn next_gate_metadata(path:&Path,request:&Request,host_gate_sha:&str)->Result<usize>{
    next_gate_metadata_owned(path,request,host_gate_sha,0,0)
}
fn next_gate_metadata_owned(path:&Path,request:&Request,host_gate_sha:&str,owner:u32,group:u32)->Result<usize>{
    let mut sequences=Vec::new();
    for(count,entry)in fs::read_dir(path).map_err(|_|"gate metadata proof inventory unavailable")?.enumerate(){
        if count>=256{return Err("gate metadata proof inventory bound exceeded".into());}let entry=entry.map_err(|_|"gate metadata proof inventory entry unavailable")?;let name=entry.file_name().into_string().map_err(|_|"gate metadata proof filename encoding differs")?;
        if let Some(sequence)=gate_metadata_sequence(&name)?{let bytes=read_owned(&entry.path(),owner,group,0o400,MAX_REQUEST)?;let proof=GateMetadataFile::open_owned(&entry.path(),&bytes,owner,group)?;validate_gate_metadata(&proof.bytes,request,host_gate_sha,sequence,None)?;sequences.push(sequence);}
    }
    sequences.sort();if sequences!=(1..=sequences.len()).collect::<Vec<_>>()||sequences.len()>=64{return Err("gate metadata proof sequence gap/exhaustion refused".into());}Ok(sequences.len()+1)
}
fn validate_initial_gate_metadata(name:&str,bytes:&[u8],request:&Request,host_gate_sha:&str)->Result<()>{
    if gate_metadata_sequence(name)?!=Some(1){return Err("pre-effect refusal has later gate metadata observations".into());}
    validate_gate_metadata(bytes,request,host_gate_sha,1,Some("candidate-present"))?;Ok(())
}
fn gate_metadata_result<T>(child:Result<T>,metadata:Result<()>)->Result<T>{
    match(child,metadata){(Ok(value),Ok(()))=>Ok(value),(Err(reason),Ok(()))=>Err(reason),(Ok(_),Err(error))=>Err(error),(Err(reason),Err(error))=>Err(format!("{reason}; gate metadata post-check refused: {error}"))}
}

fn child_fence_bytes(request:&Request,sequence:usize)->Result<Vec<u8>>{
    if !(1..=64).contains(&sequence){return Err("child containment fence bound exceeded".into());}
    Ok(format!("schema=opensteamer.microphone-v9-child-containment.v1\nnamespace={}\nnonce={}\nrequest_sha256={}\nsequence={}\nowner_pid={}\n",request.get("namespace"),request.get("nonce"),request.sha256,sequence,std::process::id()).into_bytes())
}
fn child_fence_validate(bytes:&[u8],request:&Request,sequence:usize)->Result<()>{
    let fields=strict_flat(bytes,CHILD_FENCE_FIELDS,8192)?;
    if fields["schema"]!="opensteamer.microphone-v9-child-containment.v1"||fields["namespace"]!=request.get("namespace")||fields["nonce"]!=request.get("nonce")||fields["request_sha256"]!=request.sha256||positive(&fields["sequence"])?!=sequence as u64||positive(&fields["owner_pid"])?<=1{return Err("child containment fence crosslinks differ".into());}Ok(())
}
fn next_child_fence(path:&Path,request:&Request)->Result<usize>{
    next_child_fence_owned(path,request,0,0)
}
fn next_child_fence_owned(path:&Path,request:&Request,owner:u32,group:u32)->Result<usize>{
    let mut active=Vec::new();let mut clean=Vec::new();let mut count=0;
    for entry in fs::read_dir(path).map_err(|_|"child containment inventory unavailable")?{
        count+=1;if count>256{return Err("child containment inventory bound exceeded".into());}
        let entry=entry.map_err(|_|"child containment entry unavailable")?;let name=entry.file_name().into_string().map_err(|_|"child fence name encoding differs")?;
        let role=if let Some(number)=name.strip_prefix("child-active-"){Some((true,number))}else{name.strip_prefix("child-clean-").map(|number|(false,number))};
        let Some((is_active,number))=role else{continue;};
        if number.len()!=3||!number.bytes().all(|byte|byte.is_ascii_digit()){return Err("child containment fence name malformed".into());}
        let sequence=number.parse::<usize>().map_err(|_|"child containment sequence malformed")?;
        if !(1..=64).contains(&sequence){return Err("child containment fence bound exceeded".into());}
        if is_active{active.push(sequence);}else{clean.push(sequence);}
    }
    active.sort();clean.sort();let next=validate_child_fence_set(&active,&clean)?;
    for sequence in &active{
        let prior=read_owned(&path.join(format!("child-active-{sequence:03}")),owner,group,0o400,8192)?;
        child_fence_validate(&prior,request,*sequence)?;
        if read_owned(&path.join(format!("child-clean-{sequence:03}")),owner,group,0o400,8192)?!=prior{return Err("owned child clean fence differs from exact active owner".into());}
    }
    Ok(next)
}
fn validate_child_fence_set(active:&[usize],clean:&[usize])->Result<usize>{
    if active.len()>=64||active!=(1..=active.len()).collect::<Vec<_>>()||active!=clean{return Err("unresolved pre-effect child containment fence forbids fresh resume".into());}Ok(active.len()+1)
}

// Called only while the global controller lock is held. A fresh namespace is
// not a way around a killed earlier worker's delayed launchctl/helper effects.
fn cross_namespace_clear(root:&Path,current:&Request,owner:u32,group:u32)->Result<()>{
    let parent=sealed_fs::HeldDirectory::capture(root,owner,group,0o700)?;let mut count=0;
    for entry in fs::read_dir(root).map_err(|_|"global transaction inventory unavailable")?{
        let entry=entry.map_err(|_|"global transaction entry unavailable")?;count+=1;
        if count>65{return Err("global transaction namespace bound exceeded".into());}
        let name=entry.file_name().into_string().map_err(|_|"global transaction name encoding differs")?;
        if name==".controller.lock"{
            let file=OpenOptions::new().read(true).custom_flags(NOFOLLOW).open(entry.path()).map_err(|_|"global lock file unavailable")?;let metadata=file.metadata().map_err(|_|"global lock stat unavailable")?;
            if !metadata.is_file()||metadata.uid()!=owner||metadata.gid()!=group||metadata.mode()&0o7777!=0o600||metadata.nlink()!=1||metadata.len()!=0{return Err("global lock metadata differs".into());}sealed_fs::no_acl(&file)?;continue;
        }
        let namespace=sealed_fs::HeldDirectory::capture(&entry.path(),owner,group,0o700)?;
        if name==current.get("namespace"){namespace.revalidate()?;continue;}
        let bytes=read_owned(&entry.path().join("request.txt"),owner,group,0o400,MAX_REQUEST)?;
        let prior=Request::parse(&bytes,&sha256(&bytes))?;
        if prior.get("namespace")!=name{return Err("global transaction namespace/request differs".into());}
        match fs::symlink_metadata(entry.path().join("UNRESOLVED_CHILD")){
            Ok(_)=>{let marker=read_owned(&entry.path().join("UNRESOLVED_CHILD"),owner,group,0o400,8192)?;validate_cleanup_marker(&marker,&prior)?;return Err("another namespace has an unresolved owned child".into());},
            Err(error)if error.kind()==std::io::ErrorKind::NotFound=>{},Err(_)=>return Err("other namespace unresolved marker absence unproved".into()),
        }
        next_child_fence_owned(&entry.path(),&prior,owner,group)?;
        let journal_path=entry.path().join("journal");let journal=sealed_fs::HeldDirectory::capture(&journal_path,owner,group,0o700)?;let mut sequences=Vec::new();
        for row in fs::read_dir(&journal_path).map_err(|_|"other namespace journal inventory unavailable")?{
            let row=row.map_err(|_|"other namespace journal row unavailable")?;let value=row.file_name().into_string().map_err(|_|"other journal name encoding differs")?;
            let number=value.strip_prefix("journal-").ok_or("other namespace has unresolved/unknown journal outcome")?;
            if number.len()!=3||!number.bytes().all(|byte|byte.is_ascii_digit()){return Err("other journal sequence malformed".into());}
            let sequence=number.parse::<usize>().map_err(|_|"other journal sequence malformed")?;if !(1..=64).contains(&sequence)||sequences.len()>=64{return Err("other journal bound exceeded".into());}sequences.push(sequence);
        }
        sequences.sort();if sequences!=(1..=sequences.len()).collect::<Vec<_>>(){return Err("other journal sequence gap refused".into());}
        if !sequences.is_empty(){
            let last=journal.load_journal(&prior,sequences.len())?.last().ok_or("other namespace journal lacks terminal")?;
            if !matches!(last,State::Committed|State::RolledBack){
                if owner!=0||group!=0||name!=FAILED_011_NAMESPACE||sequences.len()!=1||last!=State::Prepared{return Err("another namespace has an incomplete/unverified transaction outcome".into());}
                failed_011_terminal_clear(&entry.path(),&prior)?;
            }
        }
        namespace.revalidate()?;journal.revalidate()?;
    }
    parent.revalidate()
}

fn cleanup_record(request:&Request,group:u32,uid:u32,detail:&str)->Result<Vec<u8>>{
    if group<=1||!matches!(uid,0|501){return Err("unresolved cleanup identity differs".into());}
    Ok(format!("schema=opensteamer.microphone-v9-unresolved-child.v1\nnamespace={}\nnonce={}\nrequest_sha256={}\ngroup={}\nuid={}\nreason=OWNED_CHILD_CONTAINMENT_UNRESOLVED\ndetail_sha256={}\n",request.get("namespace"),request.get("nonce"),request.sha256,group,uid,sha256(detail.as_bytes())).into_bytes())
}
fn validate_cleanup_marker(bytes:&[u8],request:&Request)->Result<()> {
    let fields=strict_flat(bytes,CLEANUP_FIELDS,8192)?;
    if fields["schema"]!="opensteamer.microphone-v9-unresolved-child.v1"||fields["namespace"]!=request.get("namespace")||fields["nonce"]!=request.get("nonce")||fields["request_sha256"]!=request.sha256||
        positive(&fields["group"])?<=1||!matches!(fields["uid"].as_str(),"0"|"501")||fields["reason"]!="OWNED_CHILD_CONTAINMENT_UNRESOLVED"||!hex(&fields["detail_sha256"],64){return Err("unresolved cleanup marker crosslinks differ".into());}Ok(())
}

fn strict_flat(bytes:&[u8],keys:&[&str],maximum:usize)->Result<BTreeMap<String,String>>{
    if bytes.is_empty()||bytes.len()>maximum||!bytes.ends_with(b"\n"){return Err("flat proof extent/torn tail refused".into());}
    let text=std::str::from_utf8(bytes).map_err(|_|"flat proof UTF-8 refused")?;let mut fields=BTreeMap::new();
    for line in text.split_terminator('\n'){
        if !line.is_ascii()||line.bytes().any(|b|b<32||b==127){return Err("flat proof byte syntax refused".into());}
        let (key,value)=line.split_once('=').ok_or("flat proof separator absent")?;
        if !keys.contains(&key)||value.is_empty()||value.contains('=')||fields.insert(key.into(),value.into()).is_some(){return Err("flat proof duplicate/unknown/empty field refused".into());}
    }
    if fields.len()!=keys.len(){return Err("flat proof field set differs".into());}Ok(fields)
}

pub(super) struct Authority{pub(super) fields:BTreeMap<String,String>,pub(super) candidate_root:Identity,pub(super) candidate_executable:Identity}
impl Authority{
    fn get(&self,key:&str)->&str{&self.fields[key]}
    pub(super) fn load(request:&Request,state:&Path,exec:&Path)->Result<Self>{
        let authority_path=state.join("authority.txt");
        let bytes=read_owned(&authority_path,0,0,0o400,MAX_REQUEST)?;
        let fields=strict_flat(&bytes,AUTHORITY_FIELDS,MAX_REQUEST)?;
        if fields["schema"]!="opensteamer.microphone-v9-root-authority.v1"||fields["request_sha256"]!=request.sha256{return Err("root authority request/schema differs".into());}
        for key in ["namespace","nonce","guard_tooling_commit","guard_tooling_tree","worker_sha256","idle_helper_sha256","both_order_probe_sha256","route_guardian_sha256"]{
            if fields[key]!=request.get(key){return Err(format!("root authority {key} crosslink differs"));}
        }
        for key in ["host_gate_sha256","gate_inputs_sha256","build_manifest_sha256"]{if !hex(&fields[key],64){return Err("root authority extra role digest differs".into());}}
        for key in ["candidate_root_device","candidate_root_inode","candidate_executable_inode"]{positive(&fields[key])?;}
        let marker=format!("schema=opensteamer.microphone-v9-sealing.v1\nnamespace={}\nnonce={}\nrequest_sha256={}\nbuild_manifest_sha256={}\nworker_sha256={}\n",request.get("namespace"),request.get("nonce"),request.sha256,fields["build_manifest_sha256"],request.get("worker_sha256"));
        for name in ["SEALING_INCOMPLETE","SEALING_COMPLETE"]{if read_owned(&state.join(name),0,0,0o400,8192)?!=marker.as_bytes(){return Err("root sealing completion/original intent crosslinks differ".into());}}
        let sealed_request=read_pinned(&state.join("request.txt"),&request.sha256,0,0o400,MAX_REQUEST)?;
        Request::parse(&sealed_request,&request.sha256)?;
        read_pinned(&state.join("build-manifest.json"),&fields["build_manifest_sha256"],0,0o400,8*1024*1024)?;
        read_pinned(&exec.join("tools/gate_inputs.txt"),&fields["gate_inputs_sha256"],0,0o444,MAX_REQUEST)?;
        read_pinned(&exec.join("tools/opensteamer-microphone-v9-host-gate.rb"),&fields["host_gate_sha256"],0,0o444,MAX_REQUEST)?;
        let mut candidates=Vec::new();
        for path in [state.join("candidate.driver"),PathBuf::from(DRIVER),state.join("failed").join(DRIVER_NAME)]{
            if let Ok(candidate)=verify_bundle(&path,request.get("driver_tree_sha256"),request.get("driver_executable_sha256"),0){candidates.push(candidate);}
        }
        if candidates.len()!=1{return Err("sealed candidate unique inode location is unproved".into());}
        let candidate=candidates.pop().unwrap();
        if candidate.0.device!=fields["candidate_root_device"].parse::<u64>().unwrap()||candidate.0.inode!=fields["candidate_root_inode"].parse::<u64>().unwrap()||
            candidate.1.inode!=fields["candidate_executable_inode"].parse::<u64>().unwrap(){return Err("root authority sealed candidate inode differs".into());}
        Ok(Self{fields,candidate_root:candidate.0,candidate_executable:candidate.1})
    }
}

fn read_owned(path:&Path,owner:u32,group:u32,mode:u32,maximum:usize)->Result<Vec<u8>>{
    if fs::canonicalize(path).map_err(|_|"owned record canonical path unavailable")?!=path{return Err("owned record alias refused".into());}
    let mut file=OpenOptions::new().read(true).custom_flags(NOFOLLOW).open(path).map_err(|_|"owned record open failed")?;
    let metadata=file.metadata().map_err(|_|"owned record metadata unavailable")?;
    if !metadata.is_file()||metadata.uid()!=owner||metadata.gid()!=group||metadata.mode()&0o7777!=mode||metadata.nlink()!=1||metadata.len()>maximum as u64{return Err("owned record owner/type/mode/extent refused".into());}
    sealed_fs::no_acl(&file)?;
    let before=Identity::of(&metadata);let mut bytes=Vec::new();Read::by_ref(&mut file).take(maximum as u64+1).read_to_end(&mut bytes).map_err(|_|"owned record read failed")?;
    if bytes.len() as u64!=before.size||before!=Identity::of(&file.metadata().map_err(|_|"owned record restat failed")?)||before!=Identity::of(&fs::symlink_metadata(path).map_err(|_|"owned record path disappeared")?){return Err("owned record changed during read".into());}
    Ok(bytes)
}

const NODES:&[(&str,u32,&str)]=&[
    ("Directory",0o755,"."),("Directory",0o755,"Contents"),("Regular File",0o644,"Contents/Info.plist"),
    ("Directory",0o755,"Contents/MacOS"),("Regular File",0o755,DRIVER_EXE),("Directory",0o755,"Contents/Resources"),
    ("Regular File",0o644,"Contents/Resources/APPLE_SAMPLE_LICENSE.txt"),("Directory",0o755,"Contents/Resources/en.lproj"),
    ("Regular File",0o644,"Contents/Resources/en.lproj/Localizable.strings"),("Directory",0o755,"Contents/_CodeSignature"),
    ("Regular File",0o644,"Contents/_CodeSignature/CodeResources")];
const FILES:&[&str]=&["Contents/Info.plist",DRIVER_EXE,"Contents/Resources/APPLE_SAMPLE_LICENSE.txt","Contents/Resources/en.lproj/Localizable.strings","Contents/_CodeSignature/CodeResources"];

// Byte-for-byte parity with the reviewed producer/verifier C-locale format:
// stat type|octal-mode|relative NUL, then each exact regular path NUL SHA NUL.
fn bundle_digest(path:&Path,owner:u32)->Result<(String,Identity,Identity)>{
    if fs::canonicalize(path).map_err(|_|"driver canonical path unavailable")?!=path{return Err("driver path alias refused".into());}
    let mut names=Vec::new();let mut directories=vec![path.to_path_buf()];let mut canonical=Vec::new();let mut hashes=BTreeMap::new();
    let mut root=None;let mut executable=None;
    while let Some(directory)=directories.pop(){
        for child in fs::read_dir(directory).map_err(|_|"driver layout read failed")?{
            let child=child.map_err(|_|"driver child unavailable")?;let relative=child.path().strip_prefix(path).map_err(|_|"driver node escaped root")?.to_str().ok_or("driver node is not UTF-8")?.to_owned();
            let metadata=fs::symlink_metadata(child.path()).map_err(|_|"driver node stat failed")?;
            if metadata.is_dir(){directories.push(child.path());}else if !metadata.is_file(){return Err("driver symlink/special node refused".into());}
            names.push(relative);
        }
    }
    names.push(".".into());names.sort();
    let expected:Vec<_>=NODES.iter().map(|(_,_,name)|name.to_string()).collect();if names!=expected{return Err("driver exact eleven-node layout differs".into());}
    for (kind,mode,relative) in NODES{
        let node=if *relative=="."{path.to_path_buf()}else{path.join(relative)};
        let metadata=fs::symlink_metadata(&node).map_err(|_|"driver exact node metadata unavailable")?;let identity=Identity::of(&metadata);
        if metadata.uid()!=owner||metadata.gid()!=if owner==0{0}else{20}||metadata.mode()&0o7777!=*mode||(*kind=="Directory")!=metadata.is_dir()||(*kind=="Regular File"&&metadata.nlink()!=1){return Err("driver node owner/group/mode/type differs".into());}
        let descriptor=OpenOptions::new().read(true).custom_flags(NOFOLLOW).open(&node).map_err(|_|"driver node nofollow open failed")?;sealed_fs::no_acl(&descriptor)?;
        if identity!=Identity::of(&descriptor.metadata().map_err(|_|"driver descriptor stat failed")?){return Err("driver node changed at open".into());}
        canonical.extend_from_slice(format!("{kind}|{mode:o}|{relative}\0").as_bytes());
        if *kind=="Regular File"{let bytes=read_owned(&node,owner,if owner==0{0}else{20},*mode,16*1024*1024)?;hashes.insert(*relative,sha256(&bytes));}
        if *relative=="."{root=Some(identity.clone());}if *relative==DRIVER_EXE{executable=Some(identity);}
    }
    for relative in FILES{canonical.extend_from_slice(format!("{relative}\0{}\0",hashes[relative]).as_bytes());}
    Ok((sha256(&canonical),root.unwrap(),executable.unwrap()))
}
pub(super) fn verify_bundle(path:&Path,tree:&str,executable:&str,owner:u32)->Result<(Identity,Identity)>{
    if !hex(tree,64)||!hex(executable,64){return Err("driver byte pin malformed".into());}
    let (digest,root,exe)=bundle_digest(path,owner)?;
    if digest!=tree||sha256(&read_owned(&path.join(DRIVER_EXE),owner,if owner==0{0}else{20},0o755,16*1024*1024)?)!=executable{return Err("driver tree/executable differs from reviewed pin".into());}
    Ok((root,exe))
}

fn load_durable_journal(request:&Request)->Result<Journal>{
    let root=PathBuf::from(request.root_path()).join("journal");let held=sealed_fs::HeldDirectory::capture(&root,0,0,0o700)?;
    held.reconcile_journal(request)
}
fn empty_pre_effect_journal(held:&sealed_fs::HeldDirectory,path:&Path,request:&Request)->Result<Journal>{
    held.revalidate()?;
    let before=Identity::of(&held.descriptor().metadata().map_err(|_|"pre-effect journal descriptor metadata unavailable")?);
    if fs::canonicalize(path).map_err(|_|"pre-effect journal canonical path unavailable")?!=path||
        Identity::of(&fs::symlink_metadata(path).map_err(|_|"pre-effect journal path unavailable")?)!=before{
        return Err("pre-effect journal descriptor/path differs".into());
    }
    // Do not reconcile or adopt pending generations: any entry is an effect
    // boundary, while resume still requires an actual durable journal.
    if fs::read_dir(path).map_err(|_|"pre-effect journal inventory unavailable")?.next().is_some(){
        return Err("pre-effect refusal has durable/pending/unknown journal evidence".into());
    }
    held.revalidate()?;
    if Identity::of(&held.descriptor().metadata().map_err(|_|"pre-effect journal after-stat unavailable")?)!=before||
        Identity::of(&fs::symlink_metadata(path).map_err(|_|"pre-effect journal path disappeared")?)!=before{
        return Err("pre-effect journal changed during empty inventory".into());
    }
    Ok(Journal::new(request))
}
fn load_pre_effect_empty_journal(request:&Request)->Result<Journal>{
    let root=PathBuf::from(request.root_path()).join("journal");let held=sealed_fs::HeldDirectory::capture(&root,0,0,0o700)?;
    empty_pre_effect_journal(&held,&root,request)
}

fn failed_011_request(request:&Request)->Result<()>{
    if request.get("namespace")!=FAILED_011_NAMESPACE||request.get("nonce")!=FAILED_011_NONCE||request.sha256!=FAILED_011_REQUEST||request.get("worker_sha256")!=FAILED_011_WORKER{return Err("failure reconciliation accepts only the exact consumed 011 request".into());}Ok(())
}
fn exact_reconciliation_names(path:&Path,expected:&[String])->Result<()>{
    let mut names=Vec::new();for(count,entry)in fs::read_dir(path).map_err(|_|"failure reconciliation directory inventory unavailable")?.enumerate(){
        if count>=64{return Err("failure reconciliation directory inventory exceeds bound".into());}
        names.push(entry.map_err(|_|"failure reconciliation directory entry unavailable")?.file_name().into_string().map_err(|_|"failure reconciliation name encoding differs")?);
    }let mut expected=expected.to_vec();names.sort();expected.sort();if names!=expected{return Err("failure reconciliation exact directory roles differ; no pending/unknown adoption".into());}Ok(())
}
struct ReconciliationNode{file:File,path:PathBuf,identity:Identity,digest:String,directory:bool}
impl ReconciliationNode{
    fn capture(path:&Path,owner:u32,group:u32,mode:u32,directory:bool)->Result<Self>{
        if fs::canonicalize(path).map_err(|_|"failure reconciliation canonical node unavailable")?!=path{return Err("failure reconciliation node alias refused".into());}
        let file=OpenOptions::new().read(true).custom_flags(NOFOLLOW).open(path).map_err(|_|"failure reconciliation nofollow node unavailable")?;
        let metadata=file.metadata().map_err(|_|"failure reconciliation node metadata unavailable")?;
        if metadata.uid()!=owner||metadata.gid()!=group||metadata.mode()&0o7777!=mode||metadata.is_dir()!=directory||(!directory&&(!metadata.is_file()||metadata.nlink()!=1||metadata.len()>16*1024*1024)){return Err("failure reconciliation node owner/type/mode/links/extent differs".into());}
        let mut node=Self{file,path:path.to_path_buf(),identity:Identity::of(&metadata),digest:String::new(),directory};
        if !directory{node.digest=sha256(&node.bytes()?);}node.revalidate()?;Ok(node)
    }
    fn bytes(&self)->Result<Vec<u8>>{
        if self.directory||self.identity.size>16*1024*1024{return Err("failure reconciliation file role/extent differs".into());}
        let mut bytes=vec![0u8;self.identity.size as usize+1];let mut count=0;
        while count<bytes.len(){let read=self.file.read_at(&mut bytes[count..],count as u64).map_err(|_|"failure reconciliation bounded descriptor read failed")?;if read==0{break;}count+=read;}
        if count as u64!=self.identity.size{return Err("failure reconciliation descriptor extent changed".into());}bytes.truncate(count);Ok(bytes)
    }
    fn revalidate(&self)->Result<()>{
        if Identity::of(&self.file.metadata().map_err(|_|"failure reconciliation held stat unavailable")?)!=self.identity||Identity::of(&fs::symlink_metadata(&self.path).map_err(|_|"failure reconciliation path disappeared")?)!=self.identity{return Err("failure reconciliation full node identity changed".into());}
        sealed_fs::clean_gate_metadata(&self.file)?;
        if !self.directory&&sha256(&self.bytes()?)!=self.digest{return Err("failure reconciliation immutable file bytes changed".into());}
        if Identity::of(&self.file.metadata().map_err(|_|"failure reconciliation after-stat unavailable")?)!=self.identity||Identity::of(&fs::symlink_metadata(&self.path).map_err(|_|"failure reconciliation path disappeared after read")?)!=self.identity{return Err("failure reconciliation node changed during inspection".into());}Ok(())
    }
}
struct ReconciliationInventory{state:PathBuf,nodes:BTreeMap<String,ReconciliationNode>,extras:Vec<String>}
fn reconciliation_layout(state:&Path)->Result<()>{
    for name in ["prior","probes","failed"]{exact_reconciliation_names(&state.join(name),&[])?;}exact_reconciliation_names(&state.join("journal"),&["journal-001".into()])?;
    for(_,_,relative)in NODES.iter().filter(|(kind,_,_)|*kind=="Directory"){
        let directory=if *relative=="."{state.join("candidate.driver")}else{state.join("candidate.driver").join(relative)};
        let children=NODES.iter().filter_map(|(_,_,name)|{if *name=="."{return None;}let path=Path::new(name);let parent=path.parent()?.to_str()?;let parent=if parent.is_empty(){"."}else{parent};(parent==*relative).then(||path.file_name().unwrap().to_str().unwrap().to_string())}).collect::<Vec<_>>();exact_reconciliation_names(&directory,&children)?;
    }Ok(())
}
fn prepared_only_reconciliation_journal(bytes:&[u8],request:&Request)->Result<()>{
    let journal=Journal::parse(bytes,request)?;if journal.records.len()!=1||journal.last()!=Some(State::Prepared){return Err("failure reconciliation requires only the original PREPARED journal".into());}Ok(())
}
impl ReconciliationInventory{
    fn capture(state:&Path,extras:&[&str],owner:u32,group:u32)->Result<Self>{
        if extras.iter().any(|name|!RECONCILIATION_APPENDS.contains(name)&&*name!=FAILURE_TERMINAL){return Err("failure reconciliation append role refused".into());}
        Self::capture_exact(state,extras,owner,group)
    }
    fn capture_continuation(state:&Path,extras:&[&str],owner:u32,group:u32)->Result<Self>{
        if extras.iter().any(|name|!HISTORICAL_011_APPENDS.contains(name)&&!CONTINUATION_011_APPENDS.contains(name)&&*name!=CONTINUATION_TERMINAL){return Err("exact 011 continuation append role refused".into());}
        Self::capture_exact(state,extras,owner,group)
    }
    fn capture_continuation_002(state:&Path,extras:&[&str],owner:u32,group:u32)->Result<Self>{
        if extras.iter().any(|name|!HISTORICAL_011_APPENDS.contains(name)&&!CONSUMED_CONTINUATION_011_APPENDS.contains(name)&&!CONTINUATION_002_APPENDS.contains(name)&&*name!=CONTINUATION_002_TERMINAL){return Err("exact 011 continuation002 append role refused".into());}
        Self::capture_exact(state,extras,owner,group)
    }
    fn capture_exact(state:&Path,extras:&[&str],owner:u32,group:u32)->Result<Self>{
        let top=FAILED_011_TOP.iter().chain(extras).map(|name|name.to_string()).collect::<Vec<_>>();exact_reconciliation_names(state,&top)?;
        reconciliation_layout(state)?;
        let mut nodes=BTreeMap::new();
        for name in &top{os::supervisor_check()?;let directory=["candidate.driver","journal","prior","probes","failed"].contains(&name.as_str());let mode=if name=="candidate.driver"{0o755}else if directory{0o700}else if name=="guardian-1.events"{0o600}else{0o400};nodes.insert(name.clone(),ReconciliationNode::capture(&state.join(name),owner,group,mode,directory)?);}
        for(kind,mode,relative)in NODES.iter().filter(|(_,_,relative)|*relative!="."){let name=format!("candidate.driver/{relative}");nodes.insert(name.clone(),ReconciliationNode::capture(&state.join(&name),owner,group,*mode,*kind=="Directory")?);}
        nodes.insert("journal/journal-001".into(),ReconciliationNode::capture(&state.join("journal/journal-001"),owner,group,0o400,false)?);
        let inventory=Self{state:state.to_path_buf(),nodes,extras:extras.iter().map(|name|name.to_string()).collect()};inventory.revalidate()?;Ok(inventory)
    }
    fn revalidate(&self)->Result<()>{
        let expected=FAILED_011_TOP.iter().map(|name|name.to_string()).chain(self.extras.clone()).collect::<Vec<_>>();exact_reconciliation_names(&self.state,&expected)?;
        self.revalidate_nodes()
    }
    fn revalidate_nodes(&self)->Result<()>{
        reconciliation_layout(&self.state)?;
        for node in self.nodes.values(){os::supervisor_check()?;node.revalidate()?;}reconciliation_layout(&self.state)
    }
    fn digest(&self,original:bool)->String{
        let bytes=self.nodes.iter().filter(|(name,_)|name.as_str()!=FAILURE_TERMINAL&&(!original||!RECONCILIATION_APPENDS.contains(&name.as_str()))).map(|(name,node)|format!("{name}\0{:?}\0{}\0",node.identity,node.digest)).collect::<String>();sha256(bytes.as_bytes())
    }
    fn continuation_digest(&self,projection:ContinuationProjection)->String{
        let bytes=self.nodes.iter().filter(|(name,_)|{
            name.as_str()!=CONTINUATION_TERMINAL&&match projection{
                ContinuationProjection::Original=>!HISTORICAL_011_APPENDS.contains(&name.as_str())&&!CONTINUATION_011_APPENDS.contains(&name.as_str()),
                ContinuationProjection::Input=>!CONTINUATION_011_APPENDS.contains(&name.as_str()),
                ContinuationProjection::Final=>true,
            }
        }).map(|(name,node)|format!("{name}\0{:?}\0{}\0",node.identity,node.digest)).collect::<String>();sha256(bytes.as_bytes())
    }
    fn continuation_002_digest(&self,projection:ContinuationProjection)->String{
        let bytes=self.nodes.iter().filter(|(name,_)|{
            name.as_str()!=CONTINUATION_002_TERMINAL&&match projection{
                ContinuationProjection::Original=>!HISTORICAL_011_APPENDS.contains(&name.as_str())&&!CONSUMED_CONTINUATION_011_APPENDS.contains(&name.as_str())&&!CONTINUATION_002_APPENDS.contains(&name.as_str()),
                ContinuationProjection::Input=>!CONTINUATION_002_APPENDS.contains(&name.as_str()),
                ContinuationProjection::Final=>true,
            }
        }).map(|(name,node)|format!("{name}\0{:?}\0{}\0",node.identity,node.digest)).collect::<String>();sha256(bytes.as_bytes())
    }
    fn bytes(&self,name:&str)->Result<Vec<u8>>{self.nodes.get(name).ok_or("failure reconciliation exact record missing")?.bytes()}
    fn verify_original(&self,request:&Request)->Result<()>{
        failed_011_request(request)?;
        for(name,pin)in FAILED_011_PINS{if self.nodes.get(*name).ok_or("failure reconciliation original role missing")?.digest!=*pin{return Err(format!("failure reconciliation original {name} byte pin differs"));}}
        prepared_only_reconciliation_journal(&self.bytes("journal/journal-001")?,request)?;
        child_fence_validate(&self.bytes("child-active-001")?,request,1)?;
        if self.bytes("child-active-001")?!=self.bytes("child-clean-001")?{return Err("failure reconciliation original child containment differs".into());}
        self.revalidate()
    }
}
#[derive(Clone,Copy)]
enum ContinuationProjection{Original,Input,Final}
fn historical_011_containment(inventory:&ReconciliationInventory,request:&Request)->Result<()>{
    let active=inventory.bytes("child-active-002")?;let clean=inventory.bytes("child-clean-002")?;
    if active!=clean||sha256(&active)!=HISTORICAL_011_FENCE{return Err("exact 011 historical finalized containment byte pin differs".into());}
    child_fence_validate(&active,request,2)?;let fields=strict_flat(&active,CHILD_FENCE_FIELDS,8192)?;
    if fields["owner_pid"]!="61441"{return Err("exact 011 historical native owner differs".into());}Ok(())
}
fn consumed_continuation_011_containment(inventory:&ReconciliationInventory,request:&Request)->Result<()>{
    historical_011_containment(inventory,request)?;
    let active=inventory.bytes("child-active-003")?;let clean=inventory.bytes("child-clean-003")?;
    if active!=clean||sha256(&active)!=CONSUMED_011_CONTINUATION_FENCE{return Err("consumed continuation001 exact finalized003 pin differs".into());}
    child_fence_validate(&active,request,3)?;let fields=strict_flat(&active,CHILD_FENCE_FIELDS,8192)?;
    if fields["owner_pid"]!=CONSUMED_011_CONTINUATION_OWNER{return Err("consumed continuation001 native003 owner differs".into());}
    let metadata=inventory.bytes("gate-metadata-003.txt")?;
    if sha256(&metadata)!=CONSUMED_011_CONTINUATION_METADATA{return Err("consumed continuation001 exact metadata003 pin differs".into());}
    validate_gate_metadata(&metadata,request,"91166013846d8579af6f94f647e6af3508b49427e83bff36c11d564380578a87",3,Some("candidate-present"))?;Ok(())
}

fn failure_terminal_validate(bytes:&[u8],request:&Request)->Result<BTreeMap<String,String>>{
    failed_011_request(request)?;let fields=strict_flat(bytes,FAILURE_TERMINAL_FIELDS,MAX_REQUEST)?;
    for(key,value)in [("schema","opensteamer.microphone-v9-failed-no-effects-reconciled.v1"),("terminal",FAILURE_TERMINAL),("namespace",FAILED_011_NAMESPACE),("nonce",FAILED_011_NONCE),("request_sha256",FAILED_011_REQUEST),("authority_sha256",FAILED_011_AUTHORITY),("original_worker_sha256",FAILED_011_WORKER),("normal_restarts","0"),("rollback_restarts","0"),("original_cause","UNKNOWN"),("original_guardian_teardown","UNKNOWN"),("guardian_coverage_proven","false"),("deployment_verified","false"),("pcm_verified","false")]{if fields[key]!=value{return Err("failure-only terminal identity/authority/unknown-cause policy differs".into());}}
    for key in ["reconciler_worker_sha256","original_inventory_sha256","final_inventory_sha256","reconciliation_child_fence_sha256","host_before_sha256","host_after_sha256","core_generation_sha256","driver_host_generation_sha256"]{if !hex(&fields[key],64){return Err("failure-only terminal digest role differs".into());}}positive(&fields["observed_at_unix_ms"])?;Ok(fields)
}
fn failure_host_gate(bytes:&[u8],request:&Request)->Result<HostGate>{
    let gate=HostGate::validate_baseline(bytes,request)?;
    for key in ["host_launchd_runs","host_executable_sha256","host_framework_sha256","host_info_plist_sha256","host_launch_plist_sha256","input_uid","output_uid","system_output_uid"]{if gate.fields[key]!=request.get(key){return Err("failure reconciliation historical host source/routes differ".into());}}
    for(key,value)in [("host_present","true"),("readiness","true"),("display_headless","false")]{if gate.fields[key]!=value{return Err("failure reconciliation historical host admission differs".into());}}
    let routes=sha256(format!("{}\0{}\0{}",request.get("input_uid"),request.get("output_uid"),request.get("system_output_uid")).as_bytes());
    if gate.fields["routes_identity_sha256"]!=routes||!hex(&gate.fields["session_log_tail_sha256"],64){return Err("failure reconciliation historical route/tail digests differ".into());}
    positive(&gate.fields["observed_at_unix_ms"])?;if gate.fields["manager_generation"]!="0"{positive(&gate.fields["manager_generation"])?;}
    let reset=if gate.fields["session_log_reset_offset"]=="0"{0}else{positive(&gate.fields["session_log_reset_offset"])?};if reset>=positive(&gate.fields["session_log_size"])?{return Err("failure reconciliation historical session reset differs".into());}Ok(gate)
}
fn failure_event_owner(output:&os::Captured,pid:u32,fd:i32,identity:&Identity,path:&Path)->Result<()>{
    if output.code!=0||!output.stderr.is_empty()||output.stdout.is_empty()||output.stdout.len()>65536||!output.stdout.ends_with(b"\0\n"){return Err(inspector_summary("failed_011_event_owner",output));}
    let rows=output.stdout.split(|byte|*byte==b'\n').collect::<Vec<_>>();if rows.len()!=3||!rows[2].is_empty(){return Err("failed guardian event has other live owners or malformed rows".into());}
    let parse=|row:&[u8],keys:&[u8]|->Result<BTreeMap<u8,String>>{
        if !row.ends_with(&[0]){return Err("failed guardian event row lacks NUL framing".into());}let mut fields=BTreeMap::new();
        for field in row[..row.len()-1].split(|byte|*byte==0){if field.len()<2||!keys.contains(&field[0]){return Err("failed guardian event unknown/empty field".into());}let value=std::str::from_utf8(&field[1..]).map_err(|_|"failed guardian event encoding differs")?;if value.bytes().any(|byte|byte<32||byte==127)||fields.insert(field[0],value.to_string()).is_some(){return Err("failed guardian event duplicate/control field".into());}}
        if fields.len()!=keys.len(){return Err("failed guardian event field set differs".into());}Ok(fields)
    };
    if rows[0].first()!=Some(&b'p')||rows[1].first()!=Some(&b'f'){return Err("failed guardian event process/file ordering differs".into());}
    let process=parse(rows[0],b"pc")?;let file=parse(rows[1],b"fDain")?;
    if positive(&process[&b'p'])?!=pid as u64||process[&b'c'].len()>256||file[&b'f']!=fd.to_string()||file[&b'a']!="r"||file[&b'D']!=format!("0x{:x}",identity.device)||positive(&file[&b'i'])?!=identity.inode||file[&b'n']!=path.to_str().ok_or("failed event path encoding differs")?{return Err("failed guardian event is not exclusively this held read-only inspection descriptor".into());}Ok(())
}
fn failed_011_empty_mapping(output:&os::Captured)->Result<()>{
    if matches!(output.code,0|1)&&output.stdout.is_empty()&&output.stderr.is_empty(){return Ok(());}
    Err(inspector_summary("failed_011_executable_owner",output))
}
fn failed_011_mapping_fence(output:Result<os::Captured>,checked:Result<()>)->Result<()>{
    match(output,checked){
        (Ok(output),Ok(()))=>failed_011_empty_mapping(&output),
        (Err(reason),Ok(()))=>Err(reason),
        (Ok(_),Err(reason))=>Err(reason),
        (Err(reason),Err(fence))=>Err(format!("{reason} held_image_fence_error_sha256={}",sha256(fence.as_bytes()))),
    }
}
fn failed_011_absence(owners:&[u32],old_worker:&os::SealedExecutable,helpers:[&os::SealedExecutable;3],reconciler:Option<&os::SealedExecutable>)->Result<()>{
    if !matches!((owners.len(),reconciler.is_some()),(1,false)|(2,true)){return Err("failed 011 owner/image role set differs".into());}
    failed_011_absence_roles(owners,old_worker,helpers,reconciler,None)
}
fn failed_011_absence_roles(owners:&[u32],old_worker:&os::SealedExecutable,helpers:[&os::SealedExecutable;3],reconciler:Option<&os::SealedExecutable>,continuation:Option<&os::SealedExecutable>)->Result<()>{
    failed_011_absence_role_count(owners.len(),reconciler.is_some(),continuation.is_some())?;
    use os::Failed011ExecutableRole as Role;
    let mut images=vec![(old_worker,Role::OriginalWorker),(helpers[0],Role::IdleHelper),(helpers[1],Role::BothOrderProbe),(helpers[2],Role::RouteGuardian)];
    if let Some(reconciler)=reconciler{images.push((reconciler,Role::ConsumedReconciler));}
    if let Some(continuation)=continuation{images.push((continuation,Role::ContinuationReconciler));}
    // Fixed held-inode searches do not require reconstructing unrelated live
    // executable paths. Two finite sweeps are observations, not atomic absence.
    for _ in 0..2{
        for(image,_)in &images{image.reconcile_revalidate()?;}
        let before=os::failed_011_process_inventory(owners)?;
        for(image,role)in &images{
            image.reconcile_revalidate()?;
            let output=(||inspector_capture("failed_011_executable_owner",os::OwnedChild::failed_011_executable_owners(image,*role)?,65536))();
            failed_011_mapping_fence(output,image.reconcile_revalidate())?;
        }
        let after=os::failed_011_process_inventory(owners)?;
        os::failed_011_processes_unchanged(&before,&after)?;
        for(image,_)in &images{image.reconcile_revalidate()?;}
    }Ok(())
}
fn failed_011_absence_role_count(owners:usize,consumed:bool,continuation:bool)->Result<()>{
    if !matches!((owners,consumed,continuation),(1,false,false)|(2,true,false)|(3,true,true)){return Err("failed 011 exact continuation owner/image role set differs".into());}Ok(())
}
fn failed_011_continuation_002_absence(owners:&[u32],old_worker:&os::SealedExecutable,helpers:[&os::SealedExecutable;3],consumed:&os::SealedExecutable,consumed_continuation:&os::SealedExecutable,current_completed:Option<&os::SealedExecutable>)->Result<()>{
    if owners.len()!=if current_completed.is_some(){4}else{3}{return Err("continuation002 exact historical/current owner role count differs".into());}
    use os::Failed011ExecutableRole as Role;
    let mut images=vec![(old_worker,Role::OriginalWorker),(helpers[0],Role::IdleHelper),(helpers[1],Role::BothOrderProbe),(helpers[2],Role::RouteGuardian),(consumed,Role::ConsumedReconciler),(consumed_continuation,Role::ContinuationReconciler)];
    if let Some(image)=current_completed{images.push((image,Role::Continuation002Reconciler));}
    for _ in 0..2{
        for(image,_)in &images{image.reconcile_revalidate()?;}
        let before=os::failed_011_continuation_002_process_inventory(owners)?;
        for(image,role)in &images{image.reconcile_revalidate()?;let output=(||inspector_capture("failed_011_executable_owner",os::OwnedChild::failed_011_executable_owners(image,*role)?,65536))();failed_011_mapping_fence(output,image.reconcile_revalidate())?;}
        let after=os::failed_011_continuation_002_process_inventory(owners)?;os::failed_011_processes_unchanged(&before,&after)?;
        for(image,_)in &images{image.reconcile_revalidate()?;}
    }Ok(())
}
fn failure_reconciliation_record(request:&Request,worker_sha:&str,original:&ReconciliationInventory,final_inventory:&ReconciliationInventory,observed:u64)->Result<Vec<u8>>{
    let mut fields=BTreeMap::new();
    for(key,value)in [("schema","opensteamer.microphone-v9-failed-no-effects-reconciled.v1"),("terminal",FAILURE_TERMINAL),("namespace",FAILED_011_NAMESPACE),("nonce",FAILED_011_NONCE),("request_sha256",FAILED_011_REQUEST),("authority_sha256",FAILED_011_AUTHORITY),("original_worker_sha256",FAILED_011_WORKER),("reconciler_worker_sha256",worker_sha),("normal_restarts","0"),("rollback_restarts","0"),("original_cause","UNKNOWN"),("original_guardian_teardown","UNKNOWN"),("guardian_coverage_proven","false"),("deployment_verified","false"),("pcm_verified","false")]{fields.insert(key,value.to_string());}
    fields.insert("original_inventory_sha256",original.digest(true));fields.insert("final_inventory_sha256",final_inventory.digest(false));fields.insert("observed_at_unix_ms",observed.to_string());
    for(key,name)in [("reconciliation_child_fence_sha256","child-clean-002"),("host_before_sha256","reconciliation-host-before.txt"),("host_after_sha256","reconciliation-host-after.txt"),("core_generation_sha256","core-baseline.txt"),("driver_host_generation_sha256","driver-host-baseline.txt")]{fields.insert(key,sha256(&final_inventory.bytes(name)?));}
    let bytes=FAILURE_TERMINAL_FIELDS.iter().map(|key|format!("{key}={}\n",fields[key])).collect::<String>().into_bytes();failure_terminal_validate(&bytes,request)?;Ok(bytes)
}
fn validate_reconciliation_evidence(inventory:&ReconciliationInventory,request:&Request,bytes:&[u8])->Result<BTreeMap<String,String>>{
    inventory.verify_original(request)?;let fields=failure_terminal_validate(bytes,request)?;
    validate_reconciliation_crosslinks(inventory,request,&fields)?;Ok(fields)
}
fn validate_reconciliation_crosslinks(inventory:&ReconciliationInventory,request:&Request,fields:&BTreeMap<String,String>)->Result<()>{
    // Production reaches this only after immutable original011 pins and the
    // exact failure terminal schema. The private seam permits finite synthetic
    // offline evidence mutants without pretending they are original authority.
    inventory.revalidate()?;
    if fields["original_inventory_sha256"]!=inventory.digest(true)||fields["final_inventory_sha256"]!=inventory.digest(false){return Err("reconciled immutable whole-inventory identities/bytes differ".into());}
    child_fence_validate(&inventory.bytes("child-active-002")?,request,2)?;
    if inventory.bytes("child-active-002")?!=inventory.bytes("child-clean-002")?||fields["reconciliation_child_fence_sha256"]!=sha256(&inventory.bytes("child-clean-002")?){return Err("reconciliation containment is not exactly finalized".into());}
    let baseline=failure_host_gate(&inventory.bytes("host-baseline.txt")?,request)?;
    for(key,name)in [("host_before_sha256","reconciliation-host-before.txt"),("host_after_sha256","reconciliation-host-after.txt"),("core_generation_sha256","core-baseline.txt"),("driver_host_generation_sha256","driver-host-baseline.txt")]{if fields[key]!=sha256(&inventory.bytes(name)?){return Err("failure reconciliation evidence byte crosslink differs".into());}}
    let mut last_observed=positive(&baseline.fields["observed_at_unix_ms"])?;let mut prior=baseline;
    for(index,name)in ["reconciliation-host-before.txt","reconciliation-host-after.txt"].iter().enumerate(){
        let gate=failure_host_gate(&inventory.bytes(name)?,request)?;
        for key in ["host_launchd_runs","host_executable_sha256","host_framework_sha256","host_info_plist_sha256","host_launch_plist_sha256","input_uid","output_uid","system_output_uid","routes_identity_sha256","manager_generation","session_log_device","session_log_inode","session_log_reset_offset"]{if gate.fields[key]!=prior.fields[key]{return Err("reconciliation host/session/display/default routes changed".into());}}
        if positive(&gate.fields["session_log_size"])?<positive(&prior.fields["session_log_size"])?{return Err("reconciliation session log regressed".into());}
        let previous_observed=last_observed;let observed=positive(&gate.fields["observed_at_unix_ms"])?;if observed<previous_observed{return Err("reconciliation host observations regressed".into());}last_observed=observed;
        let metadata=validate_gate_metadata(&inventory.bytes(&format!("gate-metadata-{:03}.txt",index+3))?,request,"91166013846d8579af6f94f647e6af3508b49427e83bff36c11d564380578a87",index+3,Some("candidate-present"))?;
        let metadata_time=positive(&metadata["observed_at_unix_ms"])?;if metadata_time<previous_observed||metadata_time>observed||observed-metadata_time>20000{return Err("reconciliation host proof is not bound to its imminent metadata observation".into());}prior=gate;
    }
    let terminal_time=positive(&fields["observed_at_unix_ms"])?;if terminal_time<last_observed||terminal_time-last_observed>5000{return Err("reconciliation terminal was not bound to a fresh final observation".into());}Ok(())
}
fn validate_reconciled_inventory(inventory:&ReconciliationInventory,request:&Request)->Result<BTreeMap<String,String>>{
    validate_reconciliation_evidence(inventory,request,&inventory.bytes(FAILURE_TERMINAL)?)
}
fn continuation_terminal_validate(bytes:&[u8],request:&Request)->Result<BTreeMap<String,String>>{
    failed_011_request(request)?;let fields=strict_flat(bytes,CONTINUATION_TERMINAL_FIELDS,MAX_REQUEST)?;
    for(key,value)in [("schema","opensteamer.microphone-v9-failed-no-effects-reconciled.v2"),("terminal",CONTINUATION_TERMINAL),("namespace",FAILED_011_NAMESPACE),("nonce",FAILED_011_NONCE),("request_sha256",FAILED_011_REQUEST),("authority_sha256",FAILED_011_AUTHORITY),("original_worker_sha256",FAILED_011_WORKER),("consumed_reconciler_worker_sha256",CONSUMED_011_RECONCILER),("original_child_fence_sha256",FAILED_011_PINS.iter().find(|(name,_)|*name=="child-clean-001").unwrap().1),("historical_child_fence_sha256",HISTORICAL_011_FENCE),("normal_restarts","0"),("rollback_restarts","0"),("original_cause","UNKNOWN"),("original_guardian_teardown","UNKNOWN"),("guardian_coverage_proven","false"),("deployment_verified","false"),("pcm_verified","false")]{if fields[key]!=value{return Err("exact 011 continuation terminal identity/authority/unknown-cause policy differs".into());}}
    for key in ["reconciler_worker_sha256","original_inventory_sha256","input_inventory_sha256","final_inventory_sha256","reconciliation_child_fence_sha256","gate_before_sha256","gate_after_sha256","host_before_sha256","host_after_sha256","core_generation_sha256","driver_host_generation_sha256"]{if !hex(&fields[key],64){return Err("exact 011 continuation terminal digest role differs".into());}}
    if [FAILED_011_WORKER,CONSUMED_011_RECONCILER].contains(&fields["reconciler_worker_sha256"].as_str()){return Err("continuation worker cannot relabel an original/consumed image".into());}positive(&fields["observed_at_unix_ms"])?;Ok(fields)
}
fn continuation_reconciliation_record(request:&Request,worker_sha:&str,original:&ReconciliationInventory,final_inventory:&ReconciliationInventory,observed:u64)->Result<Vec<u8>>{
    let mut fields=BTreeMap::new();
    for(key,value)in [("schema","opensteamer.microphone-v9-failed-no-effects-reconciled.v2"),("terminal",CONTINUATION_TERMINAL),("namespace",FAILED_011_NAMESPACE),("nonce",FAILED_011_NONCE),("request_sha256",FAILED_011_REQUEST),("authority_sha256",FAILED_011_AUTHORITY),("original_worker_sha256",FAILED_011_WORKER),("consumed_reconciler_worker_sha256",CONSUMED_011_RECONCILER),("reconciler_worker_sha256",worker_sha),("normal_restarts","0"),("rollback_restarts","0"),("original_cause","UNKNOWN"),("original_guardian_teardown","UNKNOWN"),("guardian_coverage_proven","false"),("deployment_verified","false"),("pcm_verified","false")]{fields.insert(key,value.to_string());}
    fields.insert("original_inventory_sha256",original.continuation_digest(ContinuationProjection::Original));fields.insert("input_inventory_sha256",original.continuation_digest(ContinuationProjection::Input));fields.insert("final_inventory_sha256",final_inventory.continuation_digest(ContinuationProjection::Final));fields.insert("observed_at_unix_ms",observed.to_string());
    for(key,name)in [("original_child_fence_sha256","child-clean-001"),("historical_child_fence_sha256","child-clean-002"),("reconciliation_child_fence_sha256","child-clean-003"),("gate_before_sha256","gate-metadata-003.txt"),("gate_after_sha256","gate-metadata-004.txt"),("host_before_sha256","continuation-001-host-before.txt"),("host_after_sha256","continuation-001-host-after.txt"),("core_generation_sha256","core-baseline.txt"),("driver_host_generation_sha256","driver-host-baseline.txt")]{fields.insert(key,sha256(&final_inventory.bytes(name)?));}
    let bytes=CONTINUATION_TERMINAL_FIELDS.iter().map(|key|format!("{key}={}\n",fields[key])).collect::<String>().into_bytes();continuation_terminal_validate(&bytes,request)?;Ok(bytes)
}
fn validate_continuation_evidence(inventory:&ReconciliationInventory,request:&Request,bytes:&[u8])->Result<BTreeMap<String,String>>{
    inventory.verify_original(request)?;historical_011_containment(inventory,request)?;let fields=continuation_terminal_validate(bytes,request)?;
    validate_continuation_crosslinks(inventory,request,&fields)?;Ok(fields)
}
fn validate_continuation_crosslinks(inventory:&ReconciliationInventory,request:&Request,fields:&BTreeMap<String,String>)->Result<()>{
    inventory.revalidate()?;historical_011_containment(inventory,request)?;
    for(key,projection)in [("original_inventory_sha256",ContinuationProjection::Original),("input_inventory_sha256",ContinuationProjection::Input),("final_inventory_sha256",ContinuationProjection::Final)]{if fields[key]!=inventory.continuation_digest(projection){return Err("exact 011 continuation whole-inventory crosslink differs".into());}}
    for(sequence,key)in [(1,"original_child_fence_sha256"),(2,"historical_child_fence_sha256"),(3,"reconciliation_child_fence_sha256")]{
        let active=inventory.bytes(&format!("child-active-{sequence:03}"))?;let clean=inventory.bytes(&format!("child-clean-{sequence:03}"))?;child_fence_validate(&active,request,sequence)?;
        if active!=clean||fields[key]!=sha256(&clean){return Err("exact 011 continuation containment is not fully finalized/crosslinked".into());}
    }
    let baseline=failure_host_gate(&inventory.bytes("host-baseline.txt")?,request)?;
    for(key,name)in [("gate_before_sha256","gate-metadata-003.txt"),("gate_after_sha256","gate-metadata-004.txt"),("host_before_sha256","continuation-001-host-before.txt"),("host_after_sha256","continuation-001-host-after.txt"),("core_generation_sha256","core-baseline.txt"),("driver_host_generation_sha256","driver-host-baseline.txt")]{if fields[key]!=sha256(&inventory.bytes(name)?){return Err("exact 011 continuation observation byte crosslink differs".into());}}
    let mut last_observed=positive(&baseline.fields["observed_at_unix_ms"])?;let mut prior=baseline;
    for(index,name)in ["continuation-001-host-before.txt","continuation-001-host-after.txt"].iter().enumerate(){
        let gate=failure_host_gate(&inventory.bytes(name)?,request)?;
        for key in ["host_launchd_runs","host_executable_sha256","host_framework_sha256","host_info_plist_sha256","host_launch_plist_sha256","input_uid","output_uid","system_output_uid","routes_identity_sha256","manager_generation","session_log_device","session_log_inode","session_log_reset_offset"]{if gate.fields[key]!=prior.fields[key]{return Err("continuation host/session/display/default routes changed".into());}}
        if positive(&gate.fields["session_log_size"])?<positive(&prior.fields["session_log_size"])?{return Err("continuation session log regressed".into());}
        let previous=last_observed;let observed=positive(&gate.fields["observed_at_unix_ms"])?;if observed<previous{return Err("continuation host observations regressed".into());}last_observed=observed;
        let metadata=validate_gate_metadata(&inventory.bytes(&format!("gate-metadata-{:03}.txt",index+3))?,request,"91166013846d8579af6f94f647e6af3508b49427e83bff36c11d564380578a87",index+3,Some("candidate-present"))?;
        let metadata_time=positive(&metadata["observed_at_unix_ms"])?;if metadata_time<previous||metadata_time>observed||observed-metadata_time>20000{return Err("continuation host proof is not bound to imminent metadata observation".into());}prior=gate;
    }
    let observed=positive(&fields["observed_at_unix_ms"])?;if observed<last_observed||observed-last_observed>5000{return Err("continuation terminal is not bound to a fresh final observation".into());}Ok(())
}
fn continuation_002_terminal_validate(bytes:&[u8],request:&Request)->Result<BTreeMap<String,String>>{
    failed_011_request(request)?;let fields=strict_flat(bytes,CONTINUATION_002_TERMINAL_FIELDS,MAX_REQUEST)?;
    for(key,value)in [("schema","opensteamer.microphone-v9-failed-no-effects-reconciled.v3"),("terminal",CONTINUATION_002_TERMINAL),("namespace",FAILED_011_NAMESPACE),("nonce",FAILED_011_NONCE),("request_sha256",FAILED_011_REQUEST),("authority_sha256",FAILED_011_AUTHORITY),("original_worker_sha256",FAILED_011_WORKER),("consumed_reconciler_worker_sha256",CONSUMED_011_RECONCILER),("consumed_continuation_worker_sha256",CONSUMED_011_CONTINUATION),("original_child_fence_sha256",FAILED_011_PINS.iter().find(|(name,_)|*name=="child-clean-001").unwrap().1),("historical_child_fence_sha256",HISTORICAL_011_FENCE),("consumed_continuation_child_fence_sha256",CONSUMED_011_CONTINUATION_FENCE),("consumed_continuation_gate_metadata_sha256",CONSUMED_011_CONTINUATION_METADATA),("normal_restarts","0"),("rollback_restarts","0"),("original_cause","UNKNOWN"),("original_guardian_teardown","UNKNOWN"),("guardian_coverage_proven","false"),("deployment_verified","false"),("pcm_verified","false")]{if fields[key]!=value{return Err("continuation002 terminal exact authority/history/unknown-cause policy differs".into());}}
    for key in ["reconciler_worker_sha256","original_inventory_sha256","input_inventory_sha256","final_inventory_sha256","reconciliation_child_fence_sha256","gate_before_sha256","gate_after_sha256","host_before_sha256","host_after_sha256","core_generation_sha256","driver_host_generation_sha256"]{if !hex(&fields[key],64){return Err("continuation002 terminal digest role differs".into());}}
    if [FAILED_011_WORKER,CONSUMED_011_RECONCILER,CONSUMED_011_CONTINUATION].contains(&fields["reconciler_worker_sha256"].as_str()){return Err("continuation002 cannot relabel an original/consumed image".into());}positive(&fields["observed_at_unix_ms"])?;Ok(fields)
}
fn continuation_002_record_fields(request:&Request,worker_sha:&str,original:&ReconciliationInventory,final_inventory:&ReconciliationInventory,observed:u64)->Result<BTreeMap<String,String>>{
    failed_011_request(request)?;let mut fields:BTreeMap<String,String>=BTreeMap::new();
    for(key,value)in [("schema","opensteamer.microphone-v9-failed-no-effects-reconciled.v3"),("terminal",CONTINUATION_002_TERMINAL),("namespace",FAILED_011_NAMESPACE),("nonce",FAILED_011_NONCE),("request_sha256",FAILED_011_REQUEST),("authority_sha256",FAILED_011_AUTHORITY),("original_worker_sha256",FAILED_011_WORKER),("consumed_reconciler_worker_sha256",CONSUMED_011_RECONCILER),("consumed_continuation_worker_sha256",CONSUMED_011_CONTINUATION),("reconciler_worker_sha256",worker_sha),("normal_restarts","0"),("rollback_restarts","0"),("original_cause","UNKNOWN"),("original_guardian_teardown","UNKNOWN"),("guardian_coverage_proven","false"),("deployment_verified","false"),("pcm_verified","false")]{fields.insert(key.into(),value.to_string());}
    fields.insert("original_inventory_sha256".into(),original.continuation_002_digest(ContinuationProjection::Original));fields.insert("input_inventory_sha256".into(),original.continuation_002_digest(ContinuationProjection::Input));fields.insert("final_inventory_sha256".into(),final_inventory.continuation_002_digest(ContinuationProjection::Final));fields.insert("observed_at_unix_ms".into(),observed.to_string());
    for(key,name)in [("original_child_fence_sha256","child-clean-001"),("historical_child_fence_sha256","child-clean-002"),("consumed_continuation_child_fence_sha256","child-clean-003"),("consumed_continuation_gate_metadata_sha256","gate-metadata-003.txt"),("reconciliation_child_fence_sha256","child-clean-004"),("gate_before_sha256","gate-metadata-004.txt"),("gate_after_sha256","gate-metadata-005.txt"),("host_before_sha256","continuation-002-host-before.txt"),("host_after_sha256","continuation-002-host-after.txt"),("core_generation_sha256","core-baseline.txt"),("driver_host_generation_sha256","driver-host-baseline.txt")]{fields.insert(key.into(),sha256(&final_inventory.bytes(name)?));}Ok(fields)
}
fn continuation_002_reconciliation_record(request:&Request,worker_sha:&str,original:&ReconciliationInventory,final_inventory:&ReconciliationInventory,observed:u64)->Result<Vec<u8>>{
    let fields=continuation_002_record_fields(request,worker_sha,original,final_inventory,observed)?;let bytes=CONTINUATION_002_TERMINAL_FIELDS.iter().map(|key|format!("{key}={}\n",fields[*key])).collect::<String>().into_bytes();continuation_002_terminal_validate(&bytes,request)?;Ok(bytes)
}
fn recovery_quiet_transition(prior:&HostGate,next:&HostGate,historical:bool)->Result<()>{
    for key in ["host_present","host_pid","host_launchd_runs","host_start_identity_sha256","host_nonce","host_lock_device","host_lock_inode","host_display_identity_sha256","display_headless","readiness","host_executable_sha256","host_framework_sha256","host_info_plist_sha256","host_launch_plist_sha256","input_uid","output_uid","system_output_uid","routes_identity_sha256","manager_generation","session_log_device","session_log_inode"]{if next.fields[key]!=prior.fields[key]{return Err("continuation002 host/source/display/routes/manager/log identity changed".into());}}
    let prior_size=positive(&prior.fields["session_log_size"])?;let next_size=positive(&next.fields["session_log_size"])?;
    let prior_reset=prior.fields["session_log_reset_offset"].parse::<u64>().map_err(|_|"historical reset offset malformed")?;let next_reset=next.fields["session_log_reset_offset"].parse::<u64>().map_err(|_|"fresh reset offset malformed")?;
    if next_size<prior_size{return Err("continuation002 session log extent regressed".into());}
    if historical{if next_reset!=prior_reset&&next_reset<prior_size{return Err("continuation002 new quiet boundary overlaps/regresses immutable historical extent".into());}}
    else if next_reset!=prior_reset{return Err("continuation002 quiet boundary changed after first fresh receipt".into());}
    if next_size==prior_size&&(next.fields["session_log_sha256"]!=prior.fields["session_log_sha256"]||next.fields["session_log_tail_sha256"]!=prior.fields["session_log_tail_sha256"]){return Err("continuation002 same-extent prefix/tail digest changed".into());}
    if positive(&next.fields["observed_at_unix_ms"])?<positive(&prior.fields["observed_at_unix_ms"])?{return Err("continuation002 observation time regressed".into());}Ok(())
}
fn validate_continuation_002_crosslinks(inventory:&ReconciliationInventory,request:&Request,fields:&BTreeMap<String,String>)->Result<()>{
    inventory.revalidate()?;historical_011_containment(inventory,request)?;
    for(key,projection)in [("original_inventory_sha256",ContinuationProjection::Original),("input_inventory_sha256",ContinuationProjection::Input),("final_inventory_sha256",ContinuationProjection::Final)]{if fields[key]!=inventory.continuation_002_digest(projection){return Err("continuation002 immutable whole-inventory crosslink differs".into());}}
    for(sequence,key)in [(1,"original_child_fence_sha256"),(2,"historical_child_fence_sha256"),(3,"consumed_continuation_child_fence_sha256"),(4,"reconciliation_child_fence_sha256")]{let active=inventory.bytes(&format!("child-active-{sequence:03}"))?;let clean=inventory.bytes(&format!("child-clean-{sequence:03}"))?;child_fence_validate(&active,request,sequence)?;if active!=clean||fields[key]!=sha256(&clean){return Err("continuation002 finalized containment crosslink differs".into());}}
    for(key,name)in [("consumed_continuation_gate_metadata_sha256","gate-metadata-003.txt"),("gate_before_sha256","gate-metadata-004.txt"),("gate_after_sha256","gate-metadata-005.txt"),("host_before_sha256","continuation-002-host-before.txt"),("host_after_sha256","continuation-002-host-after.txt"),("core_generation_sha256","core-baseline.txt"),("driver_host_generation_sha256","driver-host-baseline.txt")]{if fields[key]!=sha256(&inventory.bytes(name)?){return Err("continuation002 observation byte crosslink differs".into());}}
    let mut prior=failure_host_gate(&inventory.bytes("host-baseline.txt")?,request)?;
    let consumed_metadata=validate_gate_metadata(&inventory.bytes("gate-metadata-003.txt")?,request,"91166013846d8579af6f94f647e6af3508b49427e83bff36c11d564380578a87",3,Some("candidate-present"))?;
    let mut previous=positive(&prior.fields["observed_at_unix_ms"])?.max(positive(&consumed_metadata["observed_at_unix_ms"])?);
    for(index,name)in ["continuation-002-host-before.txt","continuation-002-host-after.txt"].iter().enumerate(){
        let next=failure_host_gate(&inventory.bytes(name)?,request)?;recovery_quiet_transition(&prior,&next,index==0)?;
        let observed=positive(&next.fields["observed_at_unix_ms"])?;if observed<previous{return Err("continuation002 fresh receipt precedes retained history".into());}
        let sequence=index+4;let metadata=validate_gate_metadata(&inventory.bytes(&format!("gate-metadata-{sequence:03}.txt"))?,request,"91166013846d8579af6f94f647e6af3508b49427e83bff36c11d564380578a87",sequence,Some("candidate-present"))?;
        let metadata_time=positive(&metadata["observed_at_unix_ms"])?;if metadata_time<previous||metadata_time>observed||observed-metadata_time>20000{return Err("continuation002 fresh receipt is not bound to imminent metadata".into());}previous=observed;prior=next;
    }
    let observed=positive(&fields["observed_at_unix_ms"])?;if observed<previous||observed-previous>5000{return Err("continuation002 terminal not bound to fresh final observation".into());}Ok(())
}
fn validate_continuation_002_evidence(inventory:&ReconciliationInventory,request:&Request,bytes:&[u8])->Result<BTreeMap<String,String>>{
    inventory.verify_original(request)?;consumed_continuation_011_containment(inventory,request)?;let fields=continuation_002_terminal_validate(bytes,request)?;validate_continuation_002_crosslinks(inventory,request,&fields)?;Ok(fields)
}
fn failed_011_terminal_clear(state:&Path,request:&Request)->Result<()>{
    match fs::symlink_metadata(state.join(CONTINUATION_002_TERMINAL)){
        Ok(_)=>return failed_011_continuation_002_terminal_clear(state,request),
        Err(error)if error.kind()==std::io::ErrorKind::NotFound=>{},
        Err(_)=>return Err("exact 011 continuation002 terminal presence unproved".into()),
    }
    match fs::symlink_metadata(state.join(CONTINUATION_TERMINAL)){
        Ok(_)=>failed_011_continuation_terminal_clear(state,request),
        Err(error)if error.kind()==std::io::ErrorKind::NotFound=>failed_011_v1_terminal_clear(state,request),
        Err(_)=>Err("exact 011 continuation terminal presence unproved".into()),
    }
}
fn failed_011_v1_terminal_clear(state:&Path,request:&Request)->Result<()>{
    failed_011_request(request)?;let ancestry=sealed_fs::root_ancestry(request)?;
    let extras=RECONCILIATION_APPENDS.iter().copied().chain([FAILURE_TERMINAL]).collect::<Vec<_>>();let inventory=ReconciliationInventory::capture(state,&extras,0,0)?;let fields=validate_reconciled_inventory(&inventory,request)?;
    let exec=PathBuf::from(EXECUTABLES).join(FAILED_011_NAMESPACE);let exec_ancestry=sealed_fs::root_ancestry_path(&exec,0o711)?;
    // Historical terminal admission does not reinterpret another attempt's
    // installed image as 011's candidate; only its unchanged staged inode.
    let authority=strict_flat(&inventory.bytes("authority.txt")?,AUTHORITY_FIELDS,MAX_REQUEST)?;
    for key in ["namespace","nonce","guard_tooling_commit","guard_tooling_tree","worker_sha256","idle_helper_sha256","both_order_probe_sha256","route_guardian_sha256"]{if authority[key]!=request.get(key){return Err("reconciled historical authority crosslink changed".into());}}
    let candidate=verify_bundle(&state.join("candidate.driver"),request.get("driver_tree_sha256"),request.get("driver_executable_sha256"),0)?;
    if candidate.0.device!=positive(&authority["candidate_root_device"])?||candidate.0.inode!=positive(&authority["candidate_root_inode"])?||candidate.1.inode!=positive(&authority["candidate_executable_inode"])?{return Err("reconciled original staged candidate inode changed".into());}
    read_pinned(&exec.join("tools/gate_inputs.txt"),&authority["gate_inputs_sha256"],0,0o444,MAX_REQUEST)?;read_pinned(&exec.join("tools/opensteamer-microphone-v9-host-gate.rb"),&authority["host_gate_sha256"],0,0o444,MAX_REQUEST)?;
    let helpers=[("idle-helper","idle_helper_sha256"),("both-order-probe","both_order_probe_sha256"),("route-guardian","route_guardian_sha256")].iter().map(|(role,pin)|os::SealedExecutable::open(&exec.join(role),request.get(pin))).collect::<Result<Vec<_>>>()?;
    let old_worker=os::SealedExecutable::open(&exec.join("worker"),FAILED_011_WORKER)?;
    let reconciler_ancestry=sealed_fs::root_ancestry_path(Path::new(RECONCILE_011_WORKER).parent().unwrap(),0o711)?;let reconciler_directory=GateDirectory::capture(Path::new(RECONCILE_011_WORKER).parent().unwrap())?;let reconciler=os::SealedExecutable::open(Path::new(RECONCILE_011_WORKER),&fields["reconciler_worker_sha256"])?;
    let old_owner=strict_flat(&inventory.bytes("child-active-001")?,CHILD_FENCE_FIELDS,8192)?;let new_owner=strict_flat(&inventory.bytes("child-active-002")?,CHILD_FENCE_FIELDS,8192)?;
    failed_011_absence(&[positive(&old_owner["owner_pid"])?.try_into().map_err(|_|"old owner PID overflow")?,positive(&new_owner["owner_pid"])?.try_into().map_err(|_|"reconciler owner PID overflow")?],&old_worker,[&helpers[0],&helpers[1],&helpers[2]],Some(&reconciler))?;
    old_worker.reconcile_revalidate()?;reconciler.reconcile_revalidate()?;reconciler_directory.revalidate()?;for helper in &helpers{helper.reconcile_revalidate()?;}for held in ancestry.iter().chain(exec_ancestry.iter()).chain(reconciler_ancestry.iter()){held.revalidate()?;}inventory.revalidate()
}
fn failed_011_continuation_terminal_clear(state:&Path,request:&Request)->Result<()>{
    failed_011_request(request)?;let ancestry=sealed_fs::root_ancestry(request)?;
    let extras=HISTORICAL_011_APPENDS.iter().chain(CONTINUATION_011_APPENDS).copied().chain([CONTINUATION_TERMINAL]).collect::<Vec<_>>();
    let inventory=ReconciliationInventory::capture_continuation(state,&extras,0,0)?;let fields=validate_continuation_evidence(&inventory,request,&inventory.bytes(CONTINUATION_TERMINAL)?)?;
    let exec=PathBuf::from(EXECUTABLES).join(FAILED_011_NAMESPACE);let exec_ancestry=sealed_fs::root_ancestry_path(&exec,0o711)?;
    let authority=strict_flat(&inventory.bytes("authority.txt")?,AUTHORITY_FIELDS,MAX_REQUEST)?;
    for key in ["namespace","nonce","guard_tooling_commit","guard_tooling_tree","worker_sha256","idle_helper_sha256","both_order_probe_sha256","route_guardian_sha256"]{if authority[key]!=request.get(key){return Err("continued historical authority crosslink changed".into());}}
    let candidate=verify_bundle(&state.join("candidate.driver"),request.get("driver_tree_sha256"),request.get("driver_executable_sha256"),0)?;
    if candidate.0.device!=positive(&authority["candidate_root_device"])?||candidate.0.inode!=positive(&authority["candidate_root_inode"])?||candidate.1.inode!=positive(&authority["candidate_executable_inode"])?{return Err("continued original staged candidate inode changed".into());}
    read_pinned(&exec.join("tools/gate_inputs.txt"),&authority["gate_inputs_sha256"],0,0o444,MAX_REQUEST)?;read_pinned(&exec.join("tools/opensteamer-microphone-v9-host-gate.rb"),&authority["host_gate_sha256"],0,0o444,MAX_REQUEST)?;
    let helpers=[("idle-helper","idle_helper_sha256"),("both-order-probe","both_order_probe_sha256"),("route-guardian","route_guardian_sha256")].iter().map(|(role,pin)|os::SealedExecutable::open(&exec.join(role),request.get(pin))).collect::<Result<Vec<_>>>()?;
    let old_worker=os::SealedExecutable::open(&exec.join("worker"),FAILED_011_WORKER)?;
    let consumed_ancestry=sealed_fs::root_ancestry_path(Path::new(RECONCILE_011_WORKER).parent().unwrap(),0o711)?;let consumed_directory=GateDirectory::capture(Path::new(RECONCILE_011_WORKER).parent().unwrap())?;let consumed=os::SealedExecutable::open(Path::new(RECONCILE_011_WORKER),CONSUMED_011_RECONCILER)?;
    let continuation_ancestry=sealed_fs::root_ancestry_path(Path::new(CONTINUE_011_WORKER).parent().unwrap(),0o711)?;let continuation_directory=GateDirectory::capture(Path::new(CONTINUE_011_WORKER).parent().unwrap())?;let continuation=os::SealedExecutable::open(Path::new(CONTINUE_011_WORKER),&fields["reconciler_worker_sha256"])?;
    let owners=[1,2,3].iter().map(|sequence|{let fields=strict_flat(&inventory.bytes(&format!("child-active-{sequence:03}"))?,CHILD_FENCE_FIELDS,8192)?;positive(&fields["owner_pid"])?.try_into().map_err(|_|"continued owner PID overflow".into())}).collect::<Result<Vec<u32>>>()?;
    failed_011_absence_roles(&owners,&old_worker,[&helpers[0],&helpers[1],&helpers[2]],Some(&consumed),Some(&continuation))?;
    old_worker.reconcile_revalidate()?;consumed.reconcile_revalidate()?;continuation.reconcile_revalidate()?;consumed_directory.revalidate()?;continuation_directory.revalidate()?;for helper in &helpers{helper.reconcile_revalidate()?;}
    for held in ancestry.iter().chain(exec_ancestry.iter()).chain(consumed_ancestry.iter()).chain(continuation_ancestry.iter()){held.revalidate()?;}inventory.revalidate()
}
fn failed_011_continuation_002_terminal_clear(state:&Path,request:&Request)->Result<()>{
    failed_011_request(request)?;let ancestry=sealed_fs::root_ancestry(request)?;
    let extras=HISTORICAL_011_APPENDS.iter().chain(CONSUMED_CONTINUATION_011_APPENDS).chain(CONTINUATION_002_APPENDS).copied().chain([CONTINUATION_002_TERMINAL]).collect::<Vec<_>>();
    let inventory=ReconciliationInventory::capture_continuation_002(state,&extras,0,0)?;let fields=validate_continuation_002_evidence(&inventory,request,&inventory.bytes(CONTINUATION_002_TERMINAL)?)?;
    let exec=PathBuf::from(EXECUTABLES).join(FAILED_011_NAMESPACE);let exec_ancestry=sealed_fs::root_ancestry_path(&exec,0o711)?;
    let authority=strict_flat(&inventory.bytes("authority.txt")?,AUTHORITY_FIELDS,MAX_REQUEST)?;
    for key in ["namespace","nonce","guard_tooling_commit","guard_tooling_tree","worker_sha256","idle_helper_sha256","both_order_probe_sha256","route_guardian_sha256"]{if authority[key]!=request.get(key){return Err("continuation002 original authority crosslink changed".into());}}
    let candidate=verify_bundle(&state.join("candidate.driver"),request.get("driver_tree_sha256"),request.get("driver_executable_sha256"),0)?;
    if candidate.0.device!=positive(&authority["candidate_root_device"])?||candidate.0.inode!=positive(&authority["candidate_root_inode"])?||candidate.1.inode!=positive(&authority["candidate_executable_inode"])?{return Err("continuation002 original staged candidate inode changed".into());}
    read_pinned(&exec.join("tools/gate_inputs.txt"),&authority["gate_inputs_sha256"],0,0o444,MAX_REQUEST)?;read_pinned(&exec.join("tools/opensteamer-microphone-v9-host-gate.rb"),&authority["host_gate_sha256"],0,0o444,MAX_REQUEST)?;
    let helpers=[("idle-helper","idle_helper_sha256"),("both-order-probe","both_order_probe_sha256"),("route-guardian","route_guardian_sha256")].iter().map(|(role,pin)|os::SealedExecutable::open(&exec.join(role),request.get(pin))).collect::<Result<Vec<_>>>()?;
    let old_worker=os::SealedExecutable::open(&exec.join("worker"),FAILED_011_WORKER)?;
    let paths=[RECONCILE_011_WORKER,CONTINUE_011_WORKER,CONTINUE_011_002_WORKER];let pins=[CONSUMED_011_RECONCILER,CONSUMED_011_CONTINUATION,fields["reconciler_worker_sha256"].as_str()];
    let mut role_ancestries=Vec::new();let mut directories=Vec::new();let mut workers=Vec::new();
    for(path,pin)in paths.iter().zip(pins){let parent=Path::new(path).parent().unwrap();role_ancestries.extend(sealed_fs::root_ancestry_path(parent,0o711)?);directories.push(GateDirectory::capture(parent)?);workers.push(os::SealedExecutable::open(Path::new(path),pin)?);}
    let owners=[1,2,3,4].iter().map(|sequence|{let fields=strict_flat(&inventory.bytes(&format!("child-active-{sequence:03}"))?,CHILD_FENCE_FIELDS,8192)?;positive(&fields["owner_pid"])?.try_into().map_err(|_|"continuation002 owner PID overflow".into())}).collect::<Result<Vec<u32>>>()?;
    failed_011_continuation_002_absence(&owners,&old_worker,[&helpers[0],&helpers[1],&helpers[2]],&workers[0],&workers[1],Some(&workers[2]))?;
    // Historical prefix proof is not a fresh live quiescence or guardian claim.
    continuation_002_saved_log_prefixes(&inventory,request)?;
    old_worker.reconcile_revalidate()?;for worker in &workers{worker.reconcile_revalidate()?;}for directory in &directories{directory.revalidate()?;}for helper in &helpers{helper.reconcile_revalidate()?;}
    for held in ancestry.iter().chain(exec_ancestry.iter()).chain(role_ancestries.iter()){held.revalidate()?;}inventory.revalidate()
}

pub(super) fn reconcile_failed_no_effects_011(request:&Request,worker_sha:&str)->Result<String>{
    if !os::OwnedChild::root_identity()||!hex(worker_sha,64)||env::current_exe().map_err(|_|"reconciler image path unavailable")?!=Path::new(RECONCILE_011_WORKER){return Err("failure-only reconciler exact root image role differs".into());}
    let worker_ancestry=sealed_fs::root_ancestry_path(Path::new(RECONCILE_011_WORKER).parent().unwrap(),0o711)?;let worker_directory=GateDirectory::capture(Path::new(RECONCILE_011_WORKER).parent().unwrap())?;let worker=os::SealedExecutable::open(Path::new(RECONCILE_011_WORKER),worker_sha)?;
    worker.reconcile_revalidate()?;let(mut context,original,old_worker)=RootContext::open_failed_011(request)?;old_worker.reconcile_revalidate()?;
    let old_owner=strict_flat(&original.bytes("child-active-001")?,CHILD_FENCE_FIELDS,8192)?;let old_pid=positive(&old_owner["owner_pid"])?.try_into().map_err(|_|"original owner PID overflow")?;
    let event=original.nodes.get("guardian-1.events").ok_or("original guardian event descriptor missing")?;
    let absence=||->Result<()>{failed_011_absence(&[old_pid],&old_worker,[&context.idle,&context.probe,&context.guardian],None)?;let output=inspector_capture("failed_011_event_owner",os::OwnedChild::failed_011_event_owners()?,65536)?;failure_event_owner(&output,std::process::id(),event.file.as_raw_fd(),&event.identity,&event.path)?;event.revalidate()};
    // Every passive inspector is covered by fresh child-active-002. This is
    // absence now, never a retrospective guardian teardown/coverage proof.
    absence()?;let before=context.gate("--candidate-present")?;context.record("reconciliation-host-before.txt",&before.bytes)?;
    let core=context.core_record("core-baseline.txt")?.ok_or("original CoreAudio baseline missing")?;let host=context.driver_host_record("driver-host-baseline.txt")?.ok_or("original driver host baseline missing")?;
    let images=context.image_paths()?;let prior=context.prior_identity()?;
    if read_core()?!=core||context.bound_driver_host(&core)?!=(host.clone(),LoadedDriver::Prior){return Err("failure reconciliation does not match original loaded V8/CoreAudio/helper generation".into());}
    original.revalidate_nodes()?;old_worker.reconcile_revalidate()?;absence()?;
    let after=context.gate("--candidate-present")?;context.record("reconciliation-host-after.txt",&after.bytes)?;
    if read_core()?!=core||context.bound_driver_host(&core)?!=(host,LoadedDriver::Prior)||context.image_paths()?!=images||context.prior_identity()?!=prior{return Err("failure reconciliation loaded/installed original V8 generation changed".into());}
    absence()?;context.revalidate()?;original.revalidate_nodes()?;old_worker.reconcile_revalidate()?;worker.reconcile_revalidate()?;for held in &worker_ancestry{held.revalidate()?;}
    let authority=Authority::load(request,&context.state,&context.executables)?;if authority.fields!=context.authority.fields||authority.candidate_root!=context.authority.candidate_root||authority.candidate_executable!=context.authority.candidate_executable{return Err("original sealed candidate/authority changed during reconciliation".into());}
    context.close_child_fence()?;
    let final_inventory=ReconciliationInventory::capture(&context.state,RECONCILIATION_APPENDS,0,0)?;final_inventory.verify_original(request)?;
    if final_inventory.digest(true)!=original.digest(true){return Err("reconciliation changed original held inventory".into());}
    let observed:u64=std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_err(|_|"reconciliation clock unavailable")?.as_millis().try_into().map_err(|_|"reconciliation clock overflow")?;
    let last_observed=positive(&after.fields["observed_at_unix_ms"])?;if observed<last_observed||observed-last_observed>5000{return Err("reconciliation final host observation stale/future".into());}
    let bytes=failure_reconciliation_record(request,worker_sha,&original,&final_inventory,observed)?;
    validate_reconciliation_evidence(&final_inventory,request,&bytes)?;final_inventory.revalidate()?;original.revalidate_nodes()?;worker_directory.revalidate()?;
    context.record(FAILURE_TERMINAL,&bytes)?;
    let extras=RECONCILIATION_APPENDS.iter().copied().chain([FAILURE_TERMINAL]).collect::<Vec<_>>();let completed=ReconciliationInventory::capture(&context.state,&extras,0,0)?;validate_reconciled_inventory(&completed,request)?;
    original.revalidate_nodes()?;final_inventory.revalidate_nodes()?;context.revalidate()?;worker.reconcile_revalidate()?;worker_directory.revalidate()?;old_worker.reconcile_revalidate()?;for held in &worker_ancestry{held.revalidate()?;}
    Ok(format!("schema=opensteamer.microphone-v9-failure-reconciliation-outcome.v1\nnamespace={}\nnonce={}\nrequest_sha256={}\nauthority_sha256={}\noriginal_worker_sha256={}\nreconciler_worker_sha256={}\nterminal={}\nnormal_restarts=0\nrollback_restarts=0\noriginal_cause=UNKNOWN\noriginal_guardian_teardown=UNKNOWN\nguardian_coverage_proven=false\ndeployment_verified=false\npcm_verified=false\nreconciliation_record_sha256={}\nreason=FAILED_ATTEMPT_ONLY_NOT_DEPLOYMENT_AUTHORITY\n",FAILED_011_NAMESPACE,FAILED_011_NONCE,FAILED_011_REQUEST,FAILED_011_AUTHORITY,FAILED_011_WORKER,worker_sha,FAILURE_TERMINAL,sha256(&bytes)))
}
pub(super) fn reconcile_failed_no_effects_011_continuation_001(request:&Request,worker_sha:&str)->Result<String>{
    if !os::OwnedChild::root_identity()||!hex(worker_sha,64)||[FAILED_011_WORKER,CONSUMED_011_RECONCILER].contains(&worker_sha)||env::current_exe().map_err(|_|"continuation image path unavailable")?!=Path::new(CONTINUE_011_WORKER){return Err("exact 011 continuation root image role/pin differs".into());}
    let worker_ancestry=sealed_fs::root_ancestry_path(Path::new(CONTINUE_011_WORKER).parent().unwrap(),0o711)?;let worker_directory=GateDirectory::capture(Path::new(CONTINUE_011_WORKER).parent().unwrap())?;let worker=os::SealedExecutable::open(Path::new(CONTINUE_011_WORKER),worker_sha)?;
    let consumed_ancestry=sealed_fs::root_ancestry_path(Path::new(RECONCILE_011_WORKER).parent().unwrap(),0o711)?;let consumed_directory=GateDirectory::capture(Path::new(RECONCILE_011_WORKER).parent().unwrap())?;let consumed=os::SealedExecutable::open(Path::new(RECONCILE_011_WORKER),CONSUMED_011_RECONCILER)?;
    worker.reconcile_revalidate()?;consumed.reconcile_revalidate()?;let(mut context,original,old_worker)=RootContext::open_failed_011_continuation(request)?;old_worker.reconcile_revalidate()?;
    let old_owner=strict_flat(&original.bytes("child-active-001")?,CHILD_FENCE_FIELDS,8192)?;let old_pid=positive(&old_owner["owner_pid"])?.try_into().map_err(|_|"original owner PID overflow")?;
    let event=original.nodes.get("guardian-1.events").ok_or("original guardian event descriptor missing")?;
    let absence=||->Result<()>{failed_011_absence_roles(&[old_pid,61441],&old_worker,[&context.idle,&context.probe,&context.guardian],Some(&consumed),None)?;let output=inspector_capture("failed_011_event_owner",os::OwnedChild::failed_011_event_owners()?,65536)?;failure_event_owner(&output,std::process::id(),event.file.as_raw_fd(),&event.identity,&event.path)?;event.revalidate()};
    // Fresh owned003 covers only new passive observations. Neither002 nor the
    // orphan guardian event is rewritten or retrospectively called clean.
    absence()?;let before=context.gate("--candidate-present")?;context.record("continuation-001-host-before.txt",&before.bytes)?;
    let core=context.core_record("core-baseline.txt")?.ok_or("original CoreAudio baseline missing")?;let host=context.driver_host_record("driver-host-baseline.txt")?.ok_or("original driver host baseline missing")?;
    let images=context.image_paths()?;let prior=context.prior_identity()?;
    if read_core()?!=core||context.bound_driver_host(&core)?!=(host.clone(),LoadedDriver::Prior){return Err("continuation does not match original loaded V8/CoreAudio/helper generation".into());}
    original.revalidate_nodes()?;old_worker.reconcile_revalidate()?;consumed.reconcile_revalidate()?;absence()?;
    let after=context.gate("--candidate-present")?;context.record("continuation-001-host-after.txt",&after.bytes)?;
    if read_core()?!=core||context.bound_driver_host(&core)?!=(host,LoadedDriver::Prior)||context.image_paths()?!=images||context.prior_identity()?!=prior{return Err("continuation loaded/installed original V8 generation changed".into());}
    absence()?;context.revalidate()?;original.revalidate_nodes()?;old_worker.reconcile_revalidate()?;worker.reconcile_revalidate()?;consumed.reconcile_revalidate()?;worker_directory.revalidate()?;consumed_directory.revalidate()?;for held in worker_ancestry.iter().chain(consumed_ancestry.iter()){held.revalidate()?;}
    let authority=Authority::load(request,&context.state,&context.executables)?;if authority.fields!=context.authority.fields||authority.candidate_root!=context.authority.candidate_root||authority.candidate_executable!=context.authority.candidate_executable{return Err("original sealed candidate/authority changed during continuation".into());}
    context.close_child_fence()?;
    let extras=HISTORICAL_011_APPENDS.iter().chain(CONTINUATION_011_APPENDS).copied().collect::<Vec<_>>();let final_inventory=ReconciliationInventory::capture_continuation(&context.state,&extras,0,0)?;final_inventory.verify_original(request)?;historical_011_containment(&final_inventory,request)?;
    if final_inventory.continuation_digest(ContinuationProjection::Input)!=original.continuation_digest(ContinuationProjection::Input){return Err("continuation changed immutable original19/historical002 input inventory".into());}
    let observed:u64=std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_err(|_|"continuation clock unavailable")?.as_millis().try_into().map_err(|_|"continuation clock overflow")?;
    let bytes=continuation_reconciliation_record(request,worker_sha,&original,&final_inventory,observed)?;validate_continuation_evidence(&final_inventory,request,&bytes)?;
    final_inventory.revalidate()?;original.revalidate_nodes()?;worker.reconcile_revalidate()?;consumed.reconcile_revalidate()?;worker_directory.revalidate()?;consumed_directory.revalidate()?;
    context.record(CONTINUATION_TERMINAL,&bytes)?;
    let extras=extras.into_iter().chain([CONTINUATION_TERMINAL]).collect::<Vec<_>>();let completed=ReconciliationInventory::capture_continuation(&context.state,&extras,0,0)?;validate_continuation_evidence(&completed,request,&completed.bytes(CONTINUATION_TERMINAL)?)?;
    original.revalidate_nodes()?;final_inventory.revalidate_nodes()?;context.revalidate()?;old_worker.reconcile_revalidate()?;worker.reconcile_revalidate()?;consumed.reconcile_revalidate()?;worker_directory.revalidate()?;consumed_directory.revalidate()?;for held in worker_ancestry.iter().chain(consumed_ancestry.iter()){held.revalidate()?;}
    Ok(format!("schema=opensteamer.microphone-v9-failure-reconciliation-outcome.v2\nnamespace={}\nnonce={}\nrequest_sha256={}\nauthority_sha256={}\noriginal_worker_sha256={}\nconsumed_reconciler_worker_sha256={}\nreconciler_worker_sha256={}\nhistorical_child_fence_sha256={}\nterminal={}\nnormal_restarts=0\nrollback_restarts=0\noriginal_cause=UNKNOWN\noriginal_guardian_teardown=UNKNOWN\nguardian_coverage_proven=false\ndeployment_verified=false\npcm_verified=false\nreconciliation_record_sha256={}\nreason=FAILED_ATTEMPT_ONLY_NOT_DEPLOYMENT_AUTHORITY\n",FAILED_011_NAMESPACE,FAILED_011_NONCE,FAILED_011_REQUEST,FAILED_011_AUTHORITY,FAILED_011_WORKER,CONSUMED_011_RECONCILER,worker_sha,HISTORICAL_011_FENCE,CONTINUATION_TERMINAL,sha256(&bytes)))
}
pub(super) fn reconcile_failed_no_effects_011_continuation_002(request:&Request,worker_sha:&str)->Result<String>{
    if !os::OwnedChild::root_identity()||!hex(worker_sha,64)||[FAILED_011_WORKER,CONSUMED_011_RECONCILER,CONSUMED_011_CONTINUATION].contains(&worker_sha)||env::current_exe().map_err(|_|"continuation002 image path unavailable")?!=Path::new(CONTINUE_011_002_WORKER){return Err("continuation002 exact root image role/pin differs".into());}
    let paths=[RECONCILE_011_WORKER,CONTINUE_011_WORKER,CONTINUE_011_002_WORKER];let pins=[CONSUMED_011_RECONCILER,CONSUMED_011_CONTINUATION,worker_sha];
    let mut role_ancestries=Vec::new();let mut directories=Vec::new();let mut workers=Vec::new();
    for(path,pin)in paths.iter().zip(pins){let parent=Path::new(path).parent().unwrap();role_ancestries.extend(sealed_fs::root_ancestry_path(parent,0o711)?);directories.push(GateDirectory::capture(parent)?);let worker=os::SealedExecutable::open(Path::new(path),pin)?;worker.reconcile_revalidate()?;workers.push(worker);}
    let(mut context,original,old_worker)=RootContext::open_failed_011_continuation_002(request)?;old_worker.reconcile_revalidate()?;
    let owners=[1,2,3].iter().map(|sequence|{let fields=strict_flat(&original.bytes(&format!("child-active-{sequence:03}"))?,CHILD_FENCE_FIELDS,8192)?;positive(&fields["owner_pid"])?.try_into().map_err(|_|"continuation002 historical native owner overflow".into())}).collect::<Result<Vec<u32>>>()?;
    let event=original.nodes.get("guardian-1.events").ok_or("original guardian event descriptor missing")?;
    let absence=||->Result<()>{failed_011_continuation_002_absence(&owners,&old_worker,[&context.idle,&context.probe,&context.guardian],&workers[0],&workers[1],None)?;let output=inspector_capture("failed_011_event_owner",os::OwnedChild::failed_011_event_owners()?,65536)?;failure_event_owner(&output,std::process::id(),event.file.as_raw_fd(),&event.identity,&event.path)?;event.revalidate()};
    absence()?;let before=context.recovery_quiet_gate(None)?;context.record("continuation-002-host-before.txt",&before.bytes)?;
    let core=context.core_record("core-baseline.txt")?.ok_or("original CoreAudio baseline missing")?;let host=context.driver_host_record("driver-host-baseline.txt")?.ok_or("original driver host baseline missing")?;
    let images=context.image_paths()?;let prior=context.prior_identity()?;
    if read_core()?!=core||context.bound_driver_host(&core)?!=(host.clone(),LoadedDriver::Prior){return Err("continuation002 original loaded V8/CoreAudio/helper generation differs".into());}
    original.revalidate_nodes()?;old_worker.reconcile_revalidate()?;for worker in &workers{worker.reconcile_revalidate()?;}absence()?;
    let after=context.recovery_quiet_gate(Some(&before))?;context.record("continuation-002-host-after.txt",&after.bytes)?;
    if read_core()?!=core||context.bound_driver_host(&core)?!=(host,LoadedDriver::Prior)||context.image_paths()?!=images||context.prior_identity()?!=prior{return Err("continuation002 installed/loaded original V8 generation changed".into());}
    absence()?;context.revalidate()?;original.revalidate_nodes()?;old_worker.reconcile_revalidate()?;for worker in &workers{worker.reconcile_revalidate()?;}for directory in &directories{directory.revalidate()?;}for held in &role_ancestries{held.revalidate()?;}
    let authority=Authority::load(request,&context.state,&context.executables)?;if authority.fields!=context.authority.fields||authority.candidate_root!=context.authority.candidate_root||authority.candidate_executable!=context.authority.candidate_executable{return Err("continuation002 original sealed candidate/authority changed".into());}
    context.close_child_fence()?;
    let extras=HISTORICAL_011_APPENDS.iter().chain(CONSUMED_CONTINUATION_011_APPENDS).chain(CONTINUATION_002_APPENDS).copied().collect::<Vec<_>>();let final_inventory=ReconciliationInventory::capture_continuation_002(&context.state,&extras,0,0)?;final_inventory.verify_original(request)?;consumed_continuation_011_containment(&final_inventory,request)?;
    if final_inventory.continuation_002_digest(ContinuationProjection::Input)!=original.continuation_002_digest(ContinuationProjection::Input){return Err("continuation002 immutable original19/historical002/consumed003 input changed".into());}
    let observed:u64=std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_err(|_|"continuation002 clock unavailable")?.as_millis().try_into().map_err(|_|"continuation002 clock overflow")?;
    let bytes=continuation_002_reconciliation_record(request,worker_sha,&original,&final_inventory,observed)?;validate_continuation_002_evidence(&final_inventory,request,&bytes)?;
    final_inventory.revalidate()?;original.revalidate_nodes()?;for worker in &workers{worker.reconcile_revalidate()?;}for directory in &directories{directory.revalidate()?;}
    context.record(CONTINUATION_002_TERMINAL,&bytes)?;
    let extras=extras.into_iter().chain([CONTINUATION_002_TERMINAL]).collect::<Vec<_>>();let completed=ReconciliationInventory::capture_continuation_002(&context.state,&extras,0,0)?;validate_continuation_002_evidence(&completed,request,&completed.bytes(CONTINUATION_002_TERMINAL)?)?;
    original.revalidate_nodes()?;final_inventory.revalidate_nodes()?;context.revalidate()?;old_worker.reconcile_revalidate()?;for worker in &workers{worker.reconcile_revalidate()?;}for directory in &directories{directory.revalidate()?;}for held in &role_ancestries{held.revalidate()?;}
    Ok(format!("schema=opensteamer.microphone-v9-failure-reconciliation-outcome.v3\nnamespace={}\nnonce={}\nrequest_sha256={}\nauthority_sha256={}\noriginal_worker_sha256={}\nconsumed_reconciler_worker_sha256={}\nconsumed_continuation_worker_sha256={}\nreconciler_worker_sha256={}\nhistorical_child_fence_sha256={}\nconsumed_continuation_child_fence_sha256={}\nconsumed_continuation_gate_metadata_sha256={}\nterminal={}\nnormal_restarts=0\nrollback_restarts=0\noriginal_cause=UNKNOWN\noriginal_guardian_teardown=UNKNOWN\nguardian_coverage_proven=false\ndeployment_verified=false\npcm_verified=false\nreconciliation_record_sha256={}\nreason=FAILED_ATTEMPT_ONLY_NOT_DEPLOYMENT_AUTHORITY\n",FAILED_011_NAMESPACE,FAILED_011_NONCE,FAILED_011_REQUEST,FAILED_011_AUTHORITY,FAILED_011_WORKER,CONSUMED_011_RECONCILER,CONSUMED_011_CONTINUATION,worker_sha,HISTORICAL_011_FENCE,CONSUMED_011_CONTINUATION_FENCE,CONSUMED_011_CONTINUATION_METADATA,CONTINUATION_002_TERMINAL,sha256(&bytes)))
}

pub(super) struct RootContext{
    request:Request, state:PathBuf, executables:PathBuf,
    state_ancestry:Vec<sealed_fs::HeldDirectory>,exec_ancestry:Vec<sealed_fs::HeldDirectory>,hal_ancestry:Vec<sealed_fs::HeldDirectory>,
    authority:Authority, idle:os::SealedExecutable,probe:os::SealedExecutable,guardian:os::SealedExecutable,
    // Retaining the independently sealed original request descriptor is needed
    // for gate FD3. It cannot be recreated from a user-writable path later.
    request_file:File,
    log_file:File,
    controller_lock:sealed_fs::RootLock,
    child_fence:Vec<u8>,child_sequence:usize,child_clean:bool,
}
#[derive(Clone,Debug)]
pub(super) struct HostGate{pub(super) fields:BTreeMap<String,String>,pub(super) bytes:Vec<u8>}
impl HostGate{
    fn validate(bytes:&[u8],request:&Request,mode:&str)->Result<Self>{
        let fields=strict_flat(bytes,GATE_FIELDS,MAX_REQUEST)?;
        if fields["schema"]!="opensteamer.microphone-v9-host-gate.v1"||fields["mode"]!=mode.strip_prefix("--").ok_or("gate CLI mode differs")?||fields["namespace"]!=request.get("namespace")||fields["nonce"]!=request.get("nonce")||
            fields["session_quiescent"]!="true"||fields["committed_host_terminal"]!="COMMITTED_CANDIDATE"{return Err("fresh gate mode/session/commit identity differs".into());}
        for key in ["host_executable_sha256","host_framework_sha256","host_info_plist_sha256","host_launch_plist_sha256","input_uid","output_uid","system_output_uid"]{
            if fields[key]!=request.get(key){return Err(format!("fresh gate {key} differs"));}
        }
        let observed=positive(&fields["observed_at_unix_ms"])?;
        let now=std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_err(|_|"clock unavailable")?.as_millis();
        if observed as u128>now||now-observed as u128>5000{return Err("gate observation is stale or future".into());}
        for key in ["routes_identity_sha256","session_log_sha256","session_log_tail_sha256"]{if !hex(&fields[key],64){return Err("gate digest malformed".into());}}
        let routes=sha256(format!("{}\0{}\0{}",request.get("input_uid"),request.get("output_uid"),request.get("system_output_uid")).as_bytes());
        if fields["routes_identity_sha256"]!=routes{return Err("gate default-route fingerprint differs".into());}
        for key in ["session_log_device","session_log_inode"]{positive(&fields[key])?;}
        for key in ["session_log_size","session_log_reset_offset"]{
            let value=&fields[key];if value!="0"{positive(value)?;}
        }
        if fields["session_log_reset_offset"].parse::<u64>().unwrap()>=fields["session_log_size"].parse::<u64>().unwrap(){return Err("session reset extent differs".into());}
        if mode=="--host-absent"{
            for key in ["host_pid","host_launchd_runs","host_lock_device","host_lock_inode"]{if fields[key]!="0"{return Err("absent gate includes a live generation".into());}}
            for key in ["host_start_identity_sha256","host_nonce","host_display_identity_sha256","manager_generation"]{if fields[key]!="none"{return Err("absent generation sentinel differs".into());}}
            if fields["host_present"]!="false"||fields["readiness"]!="false"||fields["display_headless"]!="true"{return Err("absent topology/readiness differs".into());}
        }else{
            for key in ["host_pid","host_launchd_runs","host_lock_device","host_lock_inode"]{positive(&fields[key])?;}
            if fields["manager_generation"]!="0"{positive(&fields["manager_generation"])?;}
            for key in ["host_start_identity_sha256","host_nonce","host_display_identity_sha256"]{if !hex(&fields[key],64){return Err("live generation digest malformed".into());}}
            if fields["host_present"]!="true"||fields["readiness"]!="true"||fields["display_headless"]!="false"{return Err("live topology/readiness differs".into());}
            if mode=="--candidate-present"{
                for key in ["host_pid","host_launchd_runs","host_start_identity_sha256","host_nonce","host_lock_device","host_lock_inode","host_display_identity_sha256"]{
                    if fields[key]!=request.get(key){return Err("original matching host generation differs".into());}
                }
            }else if mode=="--host-ready"{
                if fields["host_pid"]==request.get("host_pid")||fields["host_nonce"]==request.get("host_nonce")||fields["host_launchd_runs"]!="1"||fields["host_display_identity_sha256"]!=request.get("host_display_identity_sha256"){
                    return Err("restarted matching host is not a fresh exact generation/display".into());
                }
            }else{return Err("unknown host gate mode".into());}
        }
        Ok(Self{fields,bytes:bytes.to_vec()})
    }
}
impl RootContext{
    fn open_failed_011_continuation_002(request:&Request)->Result<(Self,ReconciliationInventory,os::SealedExecutable)>{
        failed_011_request(request)?;let state=PathBuf::from(request.root_path());let executables=PathBuf::from(EXECUTABLES).join(FAILED_011_NAMESPACE);
        let state_ancestry=sealed_fs::root_ancestry(request)?;let exec_ancestry=sealed_fs::root_ancestry_path(&executables,0o711)?;let hal_ancestry=sealed_fs::root_ancestry_path(Path::new("/Library/Audio/Plug-Ins/HAL"),0o755)?;
        let lock_parent=sealed_fs::HeldDirectory::capture(Path::new(ROOT_TRANSACTIONS),0,0,0o700)?;let controller_lock=sealed_fs::RootLock::acquire(&lock_parent)?;
        let extras=HISTORICAL_011_APPENDS.iter().chain(CONSUMED_CONTINUATION_011_APPENDS).copied().collect::<Vec<_>>();let original=ReconciliationInventory::capture_continuation_002(&state,&extras,0,0)?;original.verify_original(request)?;consumed_continuation_011_containment(&original,request)?;
        if next_child_fence(&state,request)?!=4{return Err("continuation002 accepts only immutable finalized001/002/003".into());}
        for(sequence,name)in [(1,"gate-metadata-001.txt"),(2,"gate-metadata-002.txt"),(3,"gate-metadata-003.txt")]{validate_gate_metadata(&original.bytes(name)?,request,"91166013846d8579af6f94f647e6af3508b49427e83bff36c11d564380578a87",sequence,Some("candidate-present"))?;}
        let authority=Authority::load(request,&state,&executables)?;let old_worker=os::SealedExecutable::open(&executables.join("worker"),FAILED_011_WORKER)?;
        let idle=os::SealedExecutable::open(&executables.join("idle-helper"),request.get("idle_helper_sha256"))?;let probe=os::SealedExecutable::open(&executables.join("both-order-probe"),request.get("both_order_probe_sha256"))?;let guardian=os::SealedExecutable::open(&executables.join("route-guardian"),request.get("route_guardian_sha256"))?;
        let request_file=OpenOptions::new().read(true).custom_flags(NOFOLLOW).open(state.join("request.txt")).map_err(|_|"continuation002 original sealed request descriptor unavailable")?;
        let log_file=OpenOptions::new().read(true).custom_flags(NOFOLLOW).open("/var/tmp/opensteamer-worldwide-host.log").map_err(|_|"continuation002 fixed held session log unavailable")?;let stat=log_file.metadata().map_err(|_|"continuation002 held log metadata unavailable")?;
        if !stat.is_file()||stat.uid()!=501||stat.nlink()!=1{return Err("continuation002 held log owner/type/links differ".into());}
        original.revalidate()?;controller_lock.revalidate()?;let child_fence=child_fence_bytes(request,4)?;state_ancestry.last().unwrap().write_record("child-active-004",&child_fence,0o400)?;
        let context=Self{request:request.clone(),state,executables,state_ancestry,exec_ancestry,hal_ancestry,authority,idle,probe,guardian,request_file,log_file,controller_lock,child_fence,child_sequence:4,child_clean:false};context.revalidate()?;original.revalidate_nodes()?;Ok((context,original,old_worker))
    }
    fn open_failed_011(request:&Request)->Result<(Self,ReconciliationInventory,os::SealedExecutable)>{
        Self::open_failed_011_exact(request,false)
    }
    fn open_failed_011_continuation(request:&Request)->Result<(Self,ReconciliationInventory,os::SealedExecutable)>{
        Self::open_failed_011_exact(request,true)
    }
    fn open_failed_011_exact(request:&Request,continuation:bool)->Result<(Self,ReconciliationInventory,os::SealedExecutable)>{
        // A separate read-only constructor: never adopt the old worker, call
        // normal admission/resume, repair an orphan slot or create a namespace.
        failed_011_request(request)?;let state=PathBuf::from(request.root_path());let executables=PathBuf::from(EXECUTABLES).join(FAILED_011_NAMESPACE);
        let state_ancestry=sealed_fs::root_ancestry(request)?;let exec_ancestry=sealed_fs::root_ancestry_path(&executables,0o711)?;let hal_ancestry=sealed_fs::root_ancestry_path(Path::new("/Library/Audio/Plug-Ins/HAL"),0o755)?;
        let lock_parent=sealed_fs::HeldDirectory::capture(Path::new(ROOT_TRANSACTIONS),0,0,0o700)?;let controller_lock=sealed_fs::RootLock::acquire(&lock_parent)?;
        let original=if continuation{ReconciliationInventory::capture_continuation(&state,HISTORICAL_011_APPENDS,0,0)?}else{ReconciliationInventory::capture(&state,&[],0,0)?};original.verify_original(request)?;
        if continuation{historical_011_containment(&original,request)?;}
        let child_sequence=if continuation{3}else{2};
        if next_child_fence(&state,request)?!=child_sequence{return Err(if continuation{"reconciliation exact original/historical finalized child sequence differs"}else{"reconciliation accepts only original finalized child fence 001"}.into());}
        for(sequence,name)in [(1,"gate-metadata-001.txt"),(2,"gate-metadata-002.txt")]{validate_gate_metadata(&original.bytes(name)?,request,"91166013846d8579af6f94f647e6af3508b49427e83bff36c11d564380578a87",sequence,Some("candidate-present"))?;}
        let authority=Authority::load(request,&state,&executables)?;let old_worker=os::SealedExecutable::open(&executables.join("worker"),FAILED_011_WORKER)?;
        let idle=os::SealedExecutable::open(&executables.join("idle-helper"),request.get("idle_helper_sha256"))?;let probe=os::SealedExecutable::open(&executables.join("both-order-probe"),request.get("both_order_probe_sha256"))?;let guardian=os::SealedExecutable::open(&executables.join("route-guardian"),request.get("route_guardian_sha256"))?;
        let request_file=OpenOptions::new().read(true).custom_flags(NOFOLLOW).open(state.join("request.txt")).map_err(|_|"reconciliation sealed request descriptor unavailable")?;
        let log_file=OpenOptions::new().read(true).custom_flags(NOFOLLOW).open("/var/tmp/opensteamer-worldwide-host.log").map_err(|_|"reconciliation fixed session log descriptor unavailable")?;let stat=log_file.metadata().map_err(|_|"reconciliation session log metadata unavailable")?;
        if !stat.is_file()||stat.uid()!=501||stat.nlink()!=1{return Err("reconciliation session log owner/type/links differ".into());}
        original.revalidate()?;controller_lock.revalidate()?;
        let child_fence=child_fence_bytes(request,child_sequence)?;
        state_ancestry.last().unwrap().write_record(&format!("child-active-{child_sequence:03}"),&child_fence,0o400)?;
        let context=Self{request:request.clone(),state,executables,state_ancestry,exec_ancestry,hal_ancestry,authority,idle,probe,guardian,request_file,log_file,controller_lock,child_fence,child_sequence,child_clean:false};
        context.revalidate()?;original.revalidate_nodes()?;Ok((context,original,old_worker))
    }
    pub(super) fn open(request:&Request)->Result<Self>{
        let state=PathBuf::from(request.root_path());let executables=PathBuf::from(EXECUTABLES).join(request.get("namespace"));
        let state_ancestry=sealed_fs::root_ancestry(request)?;let exec_ancestry=sealed_fs::root_ancestry_path(&executables,0o711)?;
        let lock_parent=sealed_fs::HeldDirectory::capture(Path::new(ROOT_TRANSACTIONS),0,0,0o700)?;
        let controller_lock=sealed_fs::RootLock::acquire(&lock_parent)?;
        cross_namespace_clear(Path::new(ROOT_TRANSACTIONS),request,0,0)?;
        match fs::symlink_metadata(state.join("UNRESOLVED_CHILD")){
            Ok(_)=>{let bytes=read_owned(&state.join("UNRESOLVED_CHILD"),0,0,0o400,8192)?;validate_cleanup_marker(&bytes,request)?;return Err("durable unresolved owned child requires separate exact containment reconciliation; no automatic resume".into());},
            Err(error)if error.kind()==std::io::ErrorKind::NotFound=>{},Err(_)=>return Err("unresolved-child marker absence is unproved".into()),
        }
        let hal_ancestry=sealed_fs::root_ancestry_path(Path::new("/Library/Audio/Plug-Ins/HAL"),0o755)?;
        let authority=Authority::load(request,&state,&executables)?;
        let worker=executables.join("worker");if env::current_exe().map_err(|_|"worker self path unavailable")?!=worker{return Err("worker not executed from exact sealed role".into());}
        read_pinned(&worker,request.get("worker_sha256"),0,0o555,16*1024*1024)?;
        let idle=os::SealedExecutable::open(&executables.join("idle-helper"),request.get("idle_helper_sha256"))?;
        let probe=os::SealedExecutable::open(&executables.join("both-order-probe"),request.get("both_order_probe_sha256"))?;
        let guardian=os::SealedExecutable::open(&executables.join("route-guardian"),request.get("route_guardian_sha256"))?;
        let request_file=OpenOptions::new().read(true).custom_flags(NOFOLLOW).open(state.join("request.txt")).map_err(|_|"sealed request descriptor unavailable")?;
        let log_file=OpenOptions::new().read(true).custom_flags(NOFOLLOW).open("/var/tmp/opensteamer-worldwide-host.log").map_err(|_|"fixed session log descriptor unavailable")?;
        let log_stat=log_file.metadata().map_err(|_|"fixed session log descriptor stat unavailable")?;
        if !log_stat.is_file()||log_stat.uid()!=501||log_stat.nlink()!=1{return Err("fixed session log descriptor ownership/type/links differ".into());}
        // Persist before the first owned launchctl/inspector/helper can exist.
        // A crash or failed cleanup cannot lose this admission fence merely
        // because its in-memory latch disappeared with the worker.
        let child_sequence=next_child_fence(&state,request)?;let child_fence=child_fence_bytes(request,child_sequence)?;
        sealed_fs::HeldDirectory::capture(&state,0,0,0o700)?.write_record(&format!("child-active-{child_sequence:03}"),&child_fence,0o400)?;
        let context=Self{request:request.clone(),state,executables,state_ancestry,exec_ancestry,hal_ancestry,authority,idle,probe,guardian,request_file,log_file,controller_lock,child_fence,child_sequence,child_clean:false};
        context.revalidate()?;Ok(context)
    }
    fn revalidate(&self)->Result<()>{
        os::supervisor_check()?;
        for held in self.state_ancestry.iter().chain(self.exec_ancestry.iter()).chain(self.hal_ancestry.iter()){held.revalidate()?;}
        self.controller_lock.revalidate()?;
        read_pinned(&self.state.join("request.txt"),&self.request.sha256,0,0o400,MAX_REQUEST)?;
        read_pinned(&self.executables.join("tools/gate_inputs.txt"),self.authority.get("gate_inputs_sha256"),0,0o444,MAX_REQUEST)?;
        Ok(())
    }
    fn close_child_fence(&mut self)->Result<()>{
        if self.child_clean{return Err("duplicate owned child fence completion refused".into());}
        if os::unresolved_cleanup()?.is_some(){return Err("owned child cleanup remains unresolved".into());}
        self.controller_lock.revalidate()?;for held in &self.state_ancestry{held.revalidate()?;}
        let active=self.state.join(format!("child-active-{:03}",self.child_sequence));
        if read_owned(&active,0,0,0o400,8192)?!=self.child_fence{return Err("own active child containment fence changed".into());}
        let name=format!("child-clean-{:03}",self.child_sequence);
        sealed_fs::HeldDirectory::capture(&self.state,0,0,0o700)?.write_record(&name,&self.child_fence,0o400)?;
        if read_owned(&self.state.join(name),0,0,0o400,8192)?!=self.child_fence{return Err("own clean child fence readback differs".into());}
        self.child_clean=true;Ok(())
    }
    fn host_bytes(&self)->Result<()>{
        read_pinned(Path::new(HOST_EXE),self.request.get("host_executable_sha256"),501,0o755,128*1024*1024)?;
        read_pinned(Path::new(HOST_FRAMEWORK),self.request.get("host_framework_sha256"),501,0o755,128*1024*1024)?;
        read_pinned(Path::new(HOST_INFO),self.request.get("host_info_plist_sha256"),501,0o644,MAX_REQUEST)?;
        read_pinned(Path::new(HOST_PLIST),self.request.get("host_launch_plist_sha256"),501,0o600,MAX_REQUEST)?;
        self.revalidate()
    }
    fn gate_metadata(&self,mode:&str)->Result<RootGateMetadata>{
        self.revalidate()?;
        let mode=mode.strip_prefix("--").filter(|mode|matches!(*mode,"candidate-present"|"host-absent"|"host-ready")).ok_or("root gate metadata mode refused")?;
        let sequence=next_gate_metadata(&self.state,&self.request,self.authority.get("host_gate_sha256"))?;
        let mut directories=Vec::new();for path in gate_metadata_paths(self.request.get("namespace")){os::supervisor_check()?;directories.push(GateDirectory::capture(&path)?);}
        let identities=directories.iter().map(|directory|directory.identity.clone()).collect::<Vec<_>>();
        let observed=std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_err(|_|"gate metadata clock unavailable")?.as_millis().try_into().map_err(|_|"gate metadata clock overflow")?;
        let bytes=gate_metadata_bytes(&self.request,self.authority.get("host_gate_sha256"),mode,observed,sequence,&identities)?;
        let name=format!("gate-metadata-{sequence:03}.txt");self.record(&name,&bytes)?;
        let metadata=RootGateMetadata{directories,proof:GateMetadataFile::open(&self.state.join(name),&bytes)?};metadata.revalidate()?;Ok(metadata)
    }
    fn recovery_quiet_gate(&self,first:Option<&HostGate>)->Result<HostGate>{
        failed_011_request(&self.request)?;if self.child_sequence!=4{return Err("recovery quiet gate is private to exact continuation002".into());}
        self.host_bytes()?;let baseline_path=self.state.join("host-baseline.txt");let original=failure_host_gate(&read_owned(&baseline_path,0,0,0o400,MAX_REQUEST)?,&self.request)?;
        let baseline=OpenOptions::new().read(true).custom_flags(NOFOLLOW).open(&baseline_path).map_err(|_|"recovery original baseline descriptor unavailable")?;
        self.log_prefix(&original)?;
        let prior=first.unwrap_or(&original);self.log_prefix(prior)?;
        // Hash the held historical/fresh-before prefix before the next Ruby
        // observation, not inside its five-second freshness window.
        let checkpoints=if first.is_some(){vec![&original,prior]}else{vec![&original]};recovery_stream_prefixes(&self.log_file,Path::new("/var/tmp/opensteamer-worldwide-host.log"),&checkpoints,Instant::now()+Duration::from_secs(20))?;
        let sequence=if first.is_some(){5}else{4};if next_gate_metadata(&self.state,&self.request,self.authority.get("host_gate_sha256"))?!=sequence{return Err("continuation002 imminent gate sequence differs".into());}
        let script=self.executables.join("tools/opensteamer-microphone-v9-host-gate.rb");read_pinned(&script,self.authority.get("host_gate_sha256"),0,0o444,MAX_REQUEST)?;
        let metadata=self.gate_metadata("--candidate-present")?;
        let captured=(||{let captured=os::OwnedChild::ruby_gate(&script,"--candidate-present",&self.request.sha256,&self.request_file,Some(&baseline),None,&metadata.proof.file,&metadata.proof.digest)?.finish(Duration::from_secs(20),MAX_REQUEST)?;if captured.code!=0||!captured.stderr.is_empty(){return Err(host_gate_failure(captured.code,&captured.stdout,&captured.stderr));}Ok(captured)})();
        let captured=gate_metadata_result(captured,metadata.revalidate())?;let gate=HostGate::validate(&captured.stdout,&self.request,"--candidate-present")?;
        self.host_bytes()?;self.log_prefix(&gate)?;self.log_prefix(&original)?;self.log_prefix(prior)?;recovery_quiet_transition(prior,&gate,first.is_none())?;Ok(gate)
    }
    pub(super) fn gate(&self,mode:&str)->Result<HostGate>{
        self.host_bytes()?;
        let baseline_path=self.state.join("host-baseline.txt");
        let baseline=match fs::symlink_metadata(&baseline_path){
            Ok(_)=>{read_owned(&baseline_path,0,0,0o400,MAX_REQUEST)?;Some(OpenOptions::new().read(true).custom_flags(NOFOLLOW).open(&baseline_path).map_err(|_|"baseline descriptor unavailable")?)},
            Err(error)if error.kind()==std::io::ErrorKind::NotFound=>None,
            Err(_)=>return Err("baseline metadata unavailable".into()),
        };
        if mode!="--candidate-present"&&baseline.is_none(){return Err("original root baseline missing".into());}
        let ready_name=if mode=="--candidate-present"{None}else if self.optional_record("rollback-host-ready.txt")?.is_some(){Some("rollback-host-ready.txt")}else if self.optional_record("host-ready.txt")?.is_some(){Some("host-ready.txt")}else{None};
        let ready=ready_name.map(|name|OpenOptions::new().read(true).custom_flags(NOFOLLOW).open(self.state.join(name)).map_err(|_|"ready generation descriptor unavailable")).transpose()?;
        let script=self.executables.join("tools/opensteamer-microphone-v9-host-gate.rb");
        read_pinned(&script,self.authority.get("host_gate_sha256"),0,0o444,MAX_REQUEST)?;
        // Initial absent-host admission fails above (no baseline), without
        // creating a proof. Only an actual imminent Ruby child gets one.
        let metadata=self.gate_metadata(mode)?;
        let captured=(||{let captured=os::OwnedChild::ruby_gate(&script,mode,&self.request.sha256,&self.request_file,baseline.as_ref(),ready.as_ref(),&metadata.proof.file,&metadata.proof.digest)?.finish(Duration::from_secs(20),MAX_REQUEST)?;
            if captured.code!=0||!captured.stderr.is_empty(){return Err(host_gate_failure(captured.code,&captured.stdout,&captured.stderr));}Ok(captured)})();
        let captured=gate_metadata_result(captured,metadata.revalidate())?;
        let gate=HostGate::validate(&captured.stdout,&self.request,mode)?;self.host_bytes()?;self.log_prefix(&gate)?;
        if let Some(bytes)=self.optional_record("host-baseline.txt")?{
            let original=HostGate::validate_baseline(&bytes,&self.request)?;self.log_prefix(&original)?;
            if gate.fields["session_log_device"]!=original.fields["session_log_device"]||gate.fields["session_log_inode"]!=original.fields["session_log_inode"]||
                gate.fields["session_log_size"].parse::<u64>().unwrap()<original.fields["session_log_size"].parse::<u64>().unwrap(){return Err("original session log inode/prefix differs".into());}
            if mode=="--host-ready"{
                if gate.fields["session_log_reset_offset"].parse::<u64>().unwrap()<original.fields["session_log_size"].parse::<u64>().unwrap(){return Err("restarted host reset does not follow original log extent".into());}
            }else if ready_name.is_none()&&gate.fields["session_log_reset_offset"]!=original.fields["session_log_reset_offset"]{return Err("original host reset offset changed".into());}
        }
        if let Some(name)=ready_name{
            let pinned=HostGate::validate_ready(&self.optional_record(name)?.ok_or("ready generation record disappeared")?,&self.request)?;self.log_prefix(&pinned)?;
            if gate.fields["session_log_device"]!=pinned.fields["session_log_device"]||gate.fields["session_log_inode"]!=pinned.fields["session_log_inode"]||gate.fields["session_log_size"].parse::<u64>().unwrap()<pinned.fields["session_log_size"].parse::<u64>().unwrap(){return Err("owned ready session prefix changed".into());}
            if mode=="--host-absent"||gate.fields["host_pid"]==pinned.fields["host_pid"]{
                if gate.fields["session_log_reset_offset"]!=pinned.fields["session_log_reset_offset"]{return Err("owned ready reset identity changed".into());}
            }else if mode=="--host-ready"{
                if gate.fields["host_nonce"]==pinned.fields["host_nonce"]||gate.fields["session_log_reset_offset"].parse::<u64>().unwrap()<pinned.fields["session_log_size"].parse::<u64>().unwrap(){return Err("replacement ready host is not newer than owned ready generation".into());}
            }else{return Err("ready generation proof used outside stopped/restarted host boundary".into());}
        }
        if baseline.is_none(){self.state_ancestry.last().unwrap().write_record("host-baseline.txt",&gate.bytes,0o400)?;}
        Ok(gate)
    }
    pub(super) fn stop_host(&self)->Result<HostGate>{
        if self.optional_record("host-ready.txt")?.is_some()||self.optional_record("rollback-host-ready.txt")?.is_some(){self.gate("--host-ready")?;}else{self.gate("--candidate-present")?;}
        let captured=os::OwnedChild::stop_host()?.finish(Duration::from_secs(20),8192)?;
        if captured.code!=0||!captured.stdout.is_empty()||!captured.stderr.is_empty(){return Err("exact original-UID launchctl stop failed".into());}
        self.gate("--host-absent")
    }
    pub(super) fn verify_idle_before(&self)->Result<proof::IdleReceipt>{
        self.revalidate()?;
        let args=["--verify-idle","--phase","before-publish","--schema","1","--nonce",self.request.get("nonce"),"--expected-instance",self.request.get("predecessor_driver_instance")].iter().map(|value|value.to_string()).collect::<Vec<_>>();
        let captured=os::OwnedChild::native(&self.idle,&args,None,&[])?.finish(Duration::from_secs(20),MAX_REQUEST)?;
        if !captured.stderr.is_empty(){return Err("idle proof wrote stderr".into());}
        let receipt=proof::verify_idle(&captured.stdout,proof::IdleExpected{phase:"before-publish",schema:1,nonce:self.request.get("nonce"),instance:Some(self.request.number("predecessor_driver_instance")),exit_code:captured.code})?;
        if receipt.progress!=proof::IdleProgress::IdleAccepted{return Err("prior mirrored idle is not accepted".into());}self.revalidate()?;Ok(receipt)
    }
    fn held_parents(&self)->Result<(sealed_fs::HeldDirectory,sealed_fs::HeldDirectory,sealed_fs::HeldDirectory)>{
        self.revalidate()?;
        Ok((sealed_fs::HeldDirectory::capture(Path::new("/Library/Audio/Plug-Ins/HAL"),0,0,0o755)?,
            sealed_fs::HeldDirectory::capture(&self.state.join("prior"),0,0,0o700)?,
            sealed_fs::HeldDirectory::capture(&self.state.join("failed"),0,0,0o700)?))
    }
    pub(super) fn retain_prior(&self)->Result<()>{
        self.gate("--host-absent")?;self.verify_idle_before()?;let (hal,prior,_)=self.held_parents()?;
        let identity=verify_bundle(Path::new(DRIVER),self.request.get("predecessor_driver_tree_sha256"),self.request.get("predecessor_driver_executable_sha256"),0)?.0;
        if identity.device!=self.request.number("predecessor_driver_device")||identity.inode!=self.request.number("predecessor_driver_inode"){return Err("predecessor exact root inode differs".into());}
        hal.exclusive_retain(DRIVER_NAME,&prior,DRIVER_NAME,&identity)?;self.revalidate()
    }
    pub(super) fn publish(&self)->Result<()>{
        self.gate("--host-absent")?;self.verify_idle_before()?;let (hal,_,_)=self.held_parents()?;
        let identity=verify_bundle(&self.state.join("candidate.driver"),self.request.get("driver_tree_sha256"),self.request.get("driver_executable_sha256"),0)?.0;
        if identity.device!=self.authority.candidate_root.device||identity.inode!=self.authority.candidate_root.inode{return Err("sealed candidate root inode changed".into());}
        self.state_ancestry.last().unwrap().exclusive_retain("candidate.driver",&hal,DRIVER_NAME,&identity)?;
        verify_bundle(Path::new(DRIVER),self.request.get("driver_tree_sha256"),self.request.get("driver_executable_sha256"),0)?;self.revalidate()
    }
    pub(super) fn retire_candidate(&self)->Result<()>{
        self.gate("--host-absent")?;let (hal,_,failed)=self.held_parents()?;let identity=verify_bundle(Path::new(DRIVER),self.request.get("driver_tree_sha256"),self.request.get("driver_executable_sha256"),0)?.0;
        if identity.inode!=self.authority.candidate_root.inode{return Err("candidate canonical inode differs".into());}
        hal.exclusive_retain(DRIVER_NAME,&failed,DRIVER_NAME,&identity)?;self.revalidate()
    }
    pub(super) fn restore_prior(&self)->Result<()>{
        self.gate("--host-absent")?;let (hal,prior,_)=self.held_parents()?;let path=self.state.join("prior").join(DRIVER_NAME);
        let identity=verify_bundle(&path,self.request.get("predecessor_driver_tree_sha256"),self.request.get("predecessor_driver_executable_sha256"),0)?.0;
        if identity.device!=self.request.number("predecessor_driver_device")||identity.inode!=self.request.number("predecessor_driver_inode"){return Err("retained predecessor exact inode differs".into());}
        prior.exclusive_retain(DRIVER_NAME,&hal,DRIVER_NAME,&identity)?;self.revalidate()
    }
}
impl Drop for RootContext{
    fn drop(&mut self){
        let failure=match os::unresolved_cleanup(){Ok(value)=>value,Err(error)=>{eprintln!("ROOT_LOCK_RETAINED_CLEANUP_LATCH_UNAVAILABLE: {error}");loop{std::thread::park_timeout(Duration::from_secs(1));}}};
        let result=(||->Result<()> {
            // This one failure-evidence write must work despite the poisoned
            // supervisor latch. It cannot publish bytes or clear any marker.
            self.controller_lock.revalidate()?;for held in &self.state_ancestry{held.revalidate()?;}
            if failure.is_none(){
                // Every OwnedChild has already proved empty process group,
                // closed pipes and reap; backend explicitly STOPs its guardian
                // before this context/lock can be dropped.
                return if self.child_clean{Ok(())}else{self.close_child_fence()};
            }
            let failure=failure.as_ref().unwrap();
            let bytes=cleanup_record(&self.request,failure.0,failure.1,&failure.2)?;
            let path=self.state.join("UNRESOLVED_CHILD");
            match fs::symlink_metadata(&path){
                Ok(_)=>{if read_owned(&path,0,0,0o400,8192)?!=bytes{return Err("existing unresolved marker differs".into());}},
                Err(error)if error.kind()==std::io::ErrorKind::NotFound=>{sealed_fs::HeldDirectory::capture(&self.state,0,0,0o700)?.write_record("UNRESOLVED_CHILD",&bytes,0o400)?;},
                Err(_)=>return Err("unresolved marker metadata unavailable".into()),
            }
            validate_cleanup_marker(&read_owned(&path,0,0,0o400,8192)?,&self.request)?;
            File::open(&path).map_err(|_|"unresolved marker resync open failed")?.sync_all().map_err(|_|"unresolved marker durable sync failed")?;
            self.state_ancestry.last().ok_or("sealed state descriptor missing")?.descriptor().sync_all().map_err(|_|"unresolved marker parent durable sync failed")?;Ok(())
        })();
        if let Err(error)=result{
            // Never release this exact lock and let a new worker race delayed
            // effects after a storage failure prevented durable refusal. The
            // original-UID supervisor reports RecoveryPending, not completion.
            eprintln!("ROOT_LOCK_RETAINED_UNRESOLVED_CHILD_MARKER_FAILED: {error}");loop{std::thread::park_timeout(Duration::from_secs(1));}
        }
    }
}

impl HostGate{
    fn validate_ready(bytes:&[u8],request:&Request)->Result<Self>{
        let fields=strict_flat(bytes,GATE_FIELDS,MAX_REQUEST)?;
        if fields["schema"]!="opensteamer.microphone-v9-host-gate.v1"||fields["mode"]!="host-ready"||fields["namespace"]!=request.get("namespace")||fields["nonce"]!=request.get("nonce")||fields["session_quiescent"]!="true"||fields["committed_host_terminal"]!="COMMITTED_CANDIDATE"{return Err("root ready pin identity differs".into());}
        for key in ["host_pid","host_lock_device","host_lock_inode","session_log_device","session_log_inode","session_log_size"]{positive(&fields[key])?;}
        for key in ["host_nonce","host_start_identity_sha256","host_display_identity_sha256","session_log_sha256"]{if !hex(&fields[key],64){return Err("root ready pin digest differs".into());}}
        if fields["host_pid"]==request.get("host_pid")||fields["host_nonce"]==request.get("host_nonce"){return Err("root ready pin is not fresh after original host".into());}
        for key in ["host_executable_sha256","host_framework_sha256","host_info_plist_sha256","host_launch_plist_sha256","host_display_identity_sha256","input_uid","output_uid","system_output_uid"]{if fields[key]!=request.get(key){return Err("root ready pin exact source/display/routes differs".into());}}
        Ok(Self{fields,bytes:bytes.to_vec()})
    }
    // A historical original baseline is deliberately not subject to the fresh
    // timestamp test. Its exact root-held bytes and original request generation
    // are checked separately from every new live observation.
    fn validate_baseline(bytes:&[u8],request:&Request)->Result<Self>{
        let fields=strict_flat(bytes,GATE_FIELDS,MAX_REQUEST)?;
        if fields["schema"]!="opensteamer.microphone-v9-host-gate.v1"||fields["mode"]!="candidate-present"||fields["namespace"]!=request.get("namespace")||fields["nonce"]!=request.get("nonce")||fields["session_quiescent"]!="true"||fields["committed_host_terminal"]!="COMMITTED_CANDIDATE"{return Err("root baseline original identity differs".into());}
        for key in ["host_pid","host_start_identity_sha256","host_nonce","host_lock_device","host_lock_inode","host_display_identity_sha256"]{if fields[key]!=request.get(key){return Err("root baseline original generation differs".into());}}
        for key in ["session_log_device","session_log_inode","session_log_size"]{positive(&fields[key])?;}
        if !hex(&fields["session_log_sha256"],64){return Err("root baseline digest malformed".into());}
        Ok(Self{fields,bytes:bytes.to_vec()})
    }
}
impl RootContext{
    fn log_prefix(&self,gate:&HostGate)->Result<()>{
        let path=Path::new("/var/tmp/opensteamer-worldwide-host.log");
        let file=&self.log_file;
        let metadata=file.metadata().map_err(|_|"session log stat unavailable")?;let size=gate.fields["session_log_size"].parse::<u64>().map_err(|_|"session log proof size malformed")?;
        let reset=gate.fields["session_log_reset_offset"].parse::<u64>().map_err(|_|"session log reset malformed")?;
        if !metadata.is_file()||metadata.uid()!=501||metadata.nlink()!=1||metadata.dev()!=gate.fields["session_log_device"].parse::<u64>().unwrap()||metadata.ino()!=gate.fields["session_log_inode"].parse::<u64>().unwrap()||metadata.len()<size||reset>=size||size-reset>32*1024*1024{return Err("session log exact inode/generation-local extent differs".into());}
        // The sealed UID501 adapter preserves the immutable V91 whole-history
        // SessionFence semantics, including every prior-prefix digest. Its
        // bounded forward search is checked against that immutable reference.
        // Independently bind its generation-local bytes on this held fixed FD;
        // do not buffer/hash the multi-gigabyte history or claim to duplicate it.
        use std::os::unix::fs::FileExt;
        let deadline=Instant::now()+Duration::from_secs(20);let before=Identity::of(&metadata);
        let mut bytes=Vec::with_capacity((size-reset) as usize);let mut position=reset;let mut chunk=vec![0u8;1024*1024];
        while position<size{
            if Instant::now()>=deadline{return Err("session log tail read deadline exceeded".into());}
            let count=((size-position)as usize).min(chunk.len());
            let read=file.read_at(&mut chunk[..count],position).map_err(|_|"session log tail pread unavailable")?;
            if read!=count{return Err("session log generation-local short read refused".into());}
            bytes.extend_from_slice(&chunk[..count]);position+=count as u64;
        }
        validate_session_tail(&bytes,gate)?;
        if Instant::now()>=deadline{return Err("session log tail validation deadline exceeded".into());}
        let held=Identity::of(&file.metadata().map_err(|_|"session log restat unavailable")?);let named=Identity::of(&fs::symlink_metadata(path).map_err(|_|"session log disappeared")?);
        if (before.device,before.inode,before.uid,before.links)!=(held.device,held.inode,held.uid,held.links)||(held.device,held.inode,held.uid,held.links)!=(named.device,named.inode,named.uid,named.links)||held.size<size||named.size<size{return Err("session log was replaced/truncated during proof".into());}Ok(())
    }
}

fn contains_bytes(bytes:&[u8],needle:&[u8])->bool{bytes.windows(needle.len()).any(|window|window==needle)}
#[derive(Clone)]
struct RecoveryPrefixHash{state:[u32;8],pending:Vec<u8>,length:u64}
impl RecoveryPrefixHash{
    fn new()->Self{Self{state:[0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19],pending:Vec::with_capacity(64),length:0}}
    fn block(&mut self,chunk:&[u8]){
        const K:[u32;64]=[
            0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
            0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
            0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
            0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
            0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
            0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
            0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
            0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];
        let mut words=[0u32;64];for(index,word)in chunk.chunks_exact(4).enumerate(){words[index]=u32::from_be_bytes(word.try_into().unwrap());}
        for index in 16..64{let a=words[index-15];let b=words[index-2];words[index]=words[index-16].wrapping_add(a.rotate_right(7)^a.rotate_right(18)^(a>>3)).wrapping_add(words[index-7]).wrapping_add(b.rotate_right(17)^b.rotate_right(19)^(b>>10));}
        let[mut a,mut b,mut c,mut d,mut e,mut f,mut g,mut h]=self.state;
        for index in 0..64{let one=h.wrapping_add(e.rotate_right(6)^e.rotate_right(11)^e.rotate_right(25)).wrapping_add((e&f)^(!e&g)).wrapping_add(K[index]).wrapping_add(words[index]);let two=(a.rotate_right(2)^a.rotate_right(13)^a.rotate_right(22)).wrapping_add((a&b)^(a&c)^(b&c));h=g;g=f;f=e;e=d.wrapping_add(one);d=c;c=b;b=a;a=one.wrapping_add(two);}
        for(slot,value)in self.state.iter_mut().zip([a,b,c,d,e,f,g,h]){*slot=slot.wrapping_add(value);}
    }
    fn update(&mut self,mut bytes:&[u8])->Result<()>{
        self.length=self.length.checked_add(bytes.len() as u64).filter(|length|*length<=u64::MAX/8).ok_or("recovery prefix SHA length overflow")?;
        if !self.pending.is_empty(){let count=(64-self.pending.len()).min(bytes.len());self.pending.extend_from_slice(&bytes[..count]);bytes=&bytes[count..];if self.pending.len()==64{let block=self.pending.clone();self.block(&block);self.pending.clear();}}
        while bytes.len()>=64{self.block(&bytes[..64]);bytes=&bytes[64..];}self.pending.extend_from_slice(bytes);Ok(())
    }
    fn finish(mut self)->String{let bits=self.length*8;let mut end=self.pending.clone();end.push(0x80);while end.len()%64!=56{end.push(0);}end.extend_from_slice(&bits.to_be_bytes());for block in end.chunks_exact(64){self.block(block);}self.state.iter().map(|value|format!("{value:08x}")).collect()}
}
#[cfg(test)]
fn recovery_stream_prefix(file:&File,path:&Path,gate:&HostGate,deadline:Instant)->Result<()>{
    recovery_stream_prefixes(file,path,&[gate],deadline)
}
fn recovery_stream_prefixes(file:&File,path:&Path,gates:&[&HostGate],deadline:Instant)->Result<()>{
    unsafe extern "C"{fn fcntl(fd:i32,command:i32,...)->i32;}
    let flags=unsafe{fcntl(file.as_raw_fd(),3)};let metadata=file.metadata().map_err(|_|"recovery prefix held descriptor stat unavailable")?;
    if gates.is_empty()||gates.len()>3||flags<0||flags&3!=0||!metadata.is_file()||metadata.uid()!=501||metadata.nlink()!=1{return Err("recovery prefix exact checkpoint/descriptor/access policy differs".into());}
    let mut checkpoints=Vec::new();for gate in gates{let size=positive(&gate.fields["session_log_size"])?;let reset=gate.fields["session_log_reset_offset"].parse::<u64>().map_err(|_|"recovery prefix reset extent malformed")?;let device=positive(&gate.fields["session_log_device"])?;let inode=positive(&gate.fields["session_log_inode"])?;if metadata.dev()!=device||metadata.ino()!=inode||metadata.len()<size||size>u64::MAX/8||reset>=size||size-reset>32*1024*1024||!hex(&gate.fields["session_log_sha256"],64){return Err("recovery prefix checkpoint inode/extent/digest policy differs".into());}checkpoints.push((size,reset,*gate,Vec::with_capacity((size-reset)as usize)));}checkpoints.sort_by_key(|(size,_,_,_)|*size);
    let size=checkpoints.last().unwrap().0;let before=Identity::of(&metadata);let mut digest=RecoveryPrefixHash::new();let mut position=0u64;let mut chunk=vec![0u8;1024*1024];let mut next=0usize;
    while next<checkpoints.len(){
        os::supervisor_check()?;if Instant::now()>=deadline{return Err("recovery whole-prefix streaming deadline exceeded".into());}
        if position==checkpoints[next].0{let(_,_,gate,tail)=&checkpoints[next];if digest.clone().finish()!=gate.fields["session_log_sha256"]{return Err("recovery held whole-prefix checkpoint digest differs".into());}validate_session_tail(tail,gate)?;next+=1;continue;}
        let count=(checkpoints[next].0-position).min(chunk.len()as u64)as usize;let read=file.read_at(&mut chunk[..count],position).map_err(|_|"recovery prefix positional read failed")?;if read!=count{return Err("recovery whole-prefix short/truncated read refused".into());}digest.update(&chunk[..count])?;
        for(extent,reset,_,tail)in &mut checkpoints{let end=(position+count as u64).min(*extent);let start=position.max(*reset);if end>start{tail.extend_from_slice(&chunk[(start-position)as usize..(end-position)as usize]);}}position+=count as u64;
    }
    if Instant::now()>=deadline{return Err("recovery whole-prefix checkpoint validation deadline exceeded".into());}
    let held=Identity::of(&file.metadata().map_err(|_|"recovery prefix held after-stat unavailable")?);let named=Identity::of(&fs::symlink_metadata(path).map_err(|_|"recovery prefix named after-stat unavailable")?);
    if (before.device,before.inode,before.uid,before.links)!=(held.device,held.inode,held.uid,held.links)||(held.device,held.inode,held.uid,held.links)!=(named.device,named.inode,named.uid,named.links)||held.size<size||named.size<size{return Err("recovery prefix held/named identity replaced or truncated".into());}Ok(())
}
fn continuation_002_saved_log_prefixes(inventory:&ReconciliationInventory,request:&Request)->Result<()>{
    let path=Path::new("/var/tmp/opensteamer-worldwide-host.log");let file=OpenOptions::new().read(true).custom_flags(NOFOLLOW).open(path).map_err(|_|"continuation002 saved prefix descriptor unavailable")?;
    let gates=["host-baseline.txt","continuation-002-host-before.txt","continuation-002-host-after.txt"].iter().map(|name|failure_host_gate(&inventory.bytes(name)?,request)).collect::<Result<Vec<_>>>()?;let refs=gates.iter().collect::<Vec<_>>();recovery_stream_prefixes(&file,path,&refs,Instant::now()+Duration::from_secs(20))
}
fn validate_session_tail(bytes:&[u8],gate:&HostGate)->Result<()>{
    const RESETS:&[&str]=&["Worldwide availability is waiting for the paired iPhone","Worldwide viewer disconnected","Worldwide peer returned to idle","Worldwide media ended; the Mac remains available for the paired iPhone"];
    const UNSAFE:&[&str]=&["Worldwide authenticated media route selected","Starting screen video capture","peerConnected=true","controlOpen=true"];
    if bytes.is_empty()||bytes.len()>32*1024*1024||sha256(bytes)!=gate.fields["session_log_tail_sha256"]{return Err("session log generation-local digest differs".into());}
    if !RESETS.iter().any(|marker|bytes.starts_with(marker.as_bytes()))||
        RESETS.iter().any(|marker|contains_bytes(&bytes[1..],marker.as_bytes())){return Err("session log exact final quiescent reset differs".into());}
    if UNSAFE.iter().any(|marker|contains_bytes(bytes,marker.as_bytes())){return Err("session log active peer/capture after reset refused".into());}
    // A fresh host-ready generation must advertise its exact pid/nonce after
    // the fresh reset. Original and absent fences may legitimately have their
    // online marker before a disconnect reset: V91-equivalent history binds it.
    if gate.fields["mode"]=="host-ready"{
        let online=format!("Worldwide paired-device availability is online pid={} nonce={}",gate.fields["host_pid"],gate.fields["host_nonce"]);
        if !contains_bytes(bytes,online.as_bytes()){return Err("fresh generation lacks exact post-reset online marker".into());}
    }Ok(())
}

#[derive(Clone,Debug,PartialEq,Eq)]
struct CoreGeneration{pid:u32,runs:u64,start_sha:String}
impl CoreGeneration{
    fn fields(&self)->String{format!("pid={}\nruns={}\nstart_sha256={}\n",self.pid,self.runs,self.start_sha)}
    fn successor(&self,next:&Self)->bool{next.pid!=self.pid&&self.runs.checked_add(1)==Some(next.runs)}
}
fn core_launch(bytes:&[u8])->Result<(u32,u64)>{
    let text=std::str::from_utf8(bytes).map_err(|_|"CoreAudio launch output encoding differs")?;
    if !text.is_ascii()||!text.ends_with('\n')||text.contains('\r'){return Err("CoreAudio launch output bytes differ".into());}
    let mut lines=text.split_terminator('\n');if lines.next()!=Some("system/com.apple.audio.coreaudiod = {"){return Err("CoreAudio launch header differs".into());}
    let mut depth=1usize;let mut closed=false;let mut fields=BTreeMap::new();
    for raw in lines{
        let line=raw.trim();if line.is_empty(){continue;}if closed{return Err("CoreAudio launch trailing records refused".into());}
        if line=="}"{if depth==0{return Err("CoreAudio launch depth differs".into());}depth-=1;closed=depth==0;continue;}
        if line.ends_with(" = {"){depth=depth.checked_add(1).ok_or("CoreAudio launch nesting overflow")?;if depth>16{return Err("CoreAudio launch nesting exceeds bound".into());}continue;}
        if depth!=1{continue;}if let Some((key,value))=line.split_once(" = "){
            if ["state","program","domain","username","group","pid","runs"].contains(&key)&&fields.insert(key,value).is_some(){return Err("CoreAudio launch identity duplicate refused".into());}
        }
    }
    for(key,value)in [("state","running"),("program","/usr/sbin/coreaudiod"),("domain","system"),("username","_coreaudiod"),("group","_coreaudiod")]{if fields.get(key)!=Some(&value){return Err("CoreAudio launch service identity differs".into());}}
    let pid=positive(fields.get("pid").ok_or("CoreAudio PID missing")?)?;let runs=positive(fields.get("runs").ok_or("CoreAudio runs missing")?)?;
    if !closed||depth!=0||pid>i32::MAX as u64{return Err("CoreAudio launch extent/PID differs".into());}Ok((pid as u32,runs))
}
const INSPECTOR_ROLES:&[&str]=&["core_launch_before","core_process","core_pids","core_start","core_launch_after","driver_selector_before","driver_process_before","driver_procinfo_before","driver_mappings","driver_owners_prior","driver_owners_candidate","driver_process_after","driver_procinfo_after","driver_selector_after","failed_011_event_owner","failed_011_executable_owner"];
fn inspector_role(role:&str)->&str{if INSPECTOR_ROLES.contains(&role){role}else{"unknown_inspector"}}
fn inspector_summary(role:&str,captured:&os::Captured)->String{
    format!("trusted OS identity inspector refused role={} code={} stdout_bytes={} stdout_sha256={} stderr_bytes={} stderr_sha256={}",inspector_role(role),captured.code,captured.stdout.len(),sha256(&captured.stdout),captured.stderr.len(),sha256(&captured.stderr))
}
fn inspector_capture(role:&str,child:os::OwnedChild,maximum:usize)->Result<os::Captured>{
    child.finish(Duration::from_secs(5),maximum).map_err(|reason|format!("trusted OS identity inspector capture refused role={} reason_sha256={}",inspector_role(role),sha256(reason.as_bytes())))
}
fn clean_captured(role:&str,captured:os::Captured)->Result<Vec<u8>>{
    if captured.code!=0||!captured.stderr.is_empty(){return Err(inspector_summary(role,&captured));}Ok(captured.stdout)
}
fn clean_output(role:&str,child:os::OwnedChild,maximum:usize)->Result<Vec<u8>>{
    clean_captured(role,inspector_capture(role,child,maximum)?)
}
fn read_core()->Result<CoreGeneration>{
    let first=core_launch(&clean_output("core_launch_before",os::OwnedChild::core_launch()?,MAX_REQUEST)?)?;
    let pid=first.0;let process=clean_output("core_process",os::OwnedChild::core_process(pid)?,8192)?;
    let fields=std::str::from_utf8(&process).map_err(|_|"CoreAudio process encoding differs")?.split_ascii_whitespace().collect::<Vec<_>>();
    if fields!=[pid.to_string().as_str(),"1","202","202","/usr/sbin/coreaudiod"]{return Err("CoreAudio exact process identity differs".into());}
    let pids=clean_output("core_pids",os::OwnedChild::core_pids()?,8192)?;if pids!=format!("{pid}\n").as_bytes(){return Err("CoreAudio process set is not unique".into());}
    let start=clean_output("core_start",os::OwnedChild::core_start(pid)?,8192)?;let text=std::str::from_utf8(&start).map_err(|_|"CoreAudio start encoding differs")?;
    if text.lines().count()!=1||!text.ends_with('\n')||text.contains('\r')||text.split_ascii_whitespace().count()!=5{return Err("CoreAudio start identity differs".into());}
    let start_sha=sha256(text.split_ascii_whitespace().collect::<Vec<_>>().join(" ").as_bytes());
    if core_launch(&clean_output("core_launch_after",os::OwnedChild::core_launch()?,MAX_REQUEST)?)?!=first{return Err("CoreAudio generation changed during proof".into());}
    Ok(CoreGeneration{pid,runs:first.1,start_sha})
}
fn stable_core()->Result<CoreGeneration>{let first=read_core()?;std::thread::sleep(Duration::from_millis(100));if read_core()?!=first{return Err("CoreAudio generation is unstable".into());}Ok(first)}

#[derive(Clone,Debug,PartialEq,Eq)]
struct DriverHostGeneration{
    core:CoreGeneration,pid:u32,runs:u64,start_sha:String,process_uuid:String,process_version:u64,launch_uuid:String,
    apple_device:u64,apple_inode:u64,apple_stat_sha:String,apple_sha:String,hal_device:u64,hal_inode:u64,
}
impl DriverHostGeneration{
    fn fields(&self)->String{format!("core_pid={}\ncore_runs={}\ncore_start_sha256={}\npid={}\nruns={}\nstart_sha256={}\nprocess_uuid={}\nprocess_version={}\nlaunch_uuid={}\napple_device={}\napple_inode={}\napple_stat_sha256={}\napple_sha256={}\nhal_device={}\nhal_inode={}\n",self.core.pid,self.core.runs,self.core.start_sha,self.pid,self.runs,self.start_sha,self.process_uuid,self.process_version,self.launch_uuid,self.apple_device,self.apple_inode,self.apple_stat_sha,self.apple_sha,self.hal_device,self.hal_inode)}
    fn successor(&self,next:&Self)->bool{
        // A new parameterized one-shot XPC service has its own runs counter;
        // it must be its first run, never daemon-runs+1 or a reused instance.
        self.core.successor(&next.core)&&next.runs==1&&self.pid!=next.pid&&self.process_version!=next.process_version&&self.launch_uuid!=next.launch_uuid&&
            (self.apple_device,self.apple_inode,&self.apple_stat_sha,&self.apple_sha,&self.process_uuid)==(next.apple_device,next.apple_inode,&next.apple_stat_sha,&next.apple_sha,&next.process_uuid)
    }
}
const DRIVER_HOST_FIELDS:&[&str]=&["schema","namespace","nonce","core_pid","core_runs","core_start_sha256","pid","runs","start_sha256","process_uuid","process_version","launch_uuid","apple_device","apple_inode","apple_stat_sha256","apple_sha256","hal_device","hal_inode"];
fn canonical_uuid(value:&str)->bool{value.len()==36&&value.bytes().enumerate().all(|(i,b)|if [8,13,18,23].contains(&i){b==b'-'}else{b.is_ascii_digit()||(b'A'..=b'F').contains(&b)})}
fn driver_selector(bytes:&[u8])->Result<u32>{
    if bytes.len()>8192||!bytes.ends_with(b"\n"){return Err("driver host candidate inventory extent differs".into());}
    let text=std::str::from_utf8(bytes).map_err(|_|"driver host candidate encoding differs")?;let rows=text.split_terminator('\n').collect::<Vec<_>>();
    if rows.len()!=1{return Err("driver host candidate is absent or not unique".into());}let pid=positive(rows[0])?;
    if pid<=1||pid>i32::MAX as u64{return Err("driver host candidate PID differs".into());}Ok(pid as u32)
}
fn driver_process(bytes:&[u8],pid:u32)->Result<(String,String)>{
    if bytes.len()>8192||!bytes.ends_with(b"\n")||bytes.contains(&b'\r'){return Err("driver host process extent differs".into());}
    let text=std::str::from_utf8(bytes).map_err(|_|"driver host process encoding differs")?;let fields=text.split_ascii_whitespace().collect::<Vec<_>>();
    if fields.len()!=13||fields[..4]!=[pid.to_string().as_str(),"1","202","202"]||fields[9..].join(" ")!=DRIVER_HOST_DISPLAY{return Err("driver host exact process identity differs".into());}
    let month=["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"].iter().position(|month|*month==fields[5]).ok_or("driver host start month differs")?+1;
    let day=fields[6].parse::<u8>().map_err(|_|"driver host start day differs")?;
    if !(1..=31).contains(&day)||! ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"].contains(&fields[4])||fields[8].len()!=4||!fields[8].bytes().all(|b|b.is_ascii_digit())||fields[7].len()!=8||!fields[7].bytes().enumerate().all(|(i,b)|if [2,5].contains(&i){b==b':'}else{b.is_ascii_digit()}){return Err("driver host start identity malformed".into());}
    Ok((sha256(fields[4..9].join(" ").as_bytes()),format!("{}-{month:02}-{day:02} {}",fields[8],fields[7])))
}
// Parse the bounded actual launchctl procinfo shape, including its benign Mach
// info diagnostic. Identity-bearing keys/sections may never repeat. The
// display/comm strings are only consistency checks, not service authority.
fn driver_procinfo(bytes:&[u8],core:&CoreGeneration,pid:u32,start:&str)->Result<(u64,String,u64,String)>{
    if bytes.is_empty()||bytes.len()>65536||!bytes.ends_with(b"\n")||!bytes.is_ascii()||bytes.contains(&b'\r'){return Err("driver host procinfo extent/encoding differs".into());}
    let text=std::str::from_utf8(bytes).unwrap();let mut stack=Vec::<String>::new();let mut fields=BTreeMap::new();let mut sections=std::collections::BTreeSet::new();let mut plain=std::collections::BTreeSet::new();let mut service=None;
    for (count,raw)in text.split_terminator('\n').enumerate(){
        if count>=2048{return Err("driver host procinfo line bound exceeded".into());}let line=raw.trim();if line.is_empty(){continue;}
        if line=="}"||line=="};"{if stack.pop().is_none(){return Err("driver host procinfo closing extent differs".into());}continue;}
        if let Some(name)=line.strip_suffix(" = {"){
            let key=if stack.is_empty(){name.to_string()}else{format!("{}/{}",stack.join("/"),name)};
            if !sections.insert(key)||stack.len()>=8{return Err("driver host procinfo duplicate/deep section refused".into());}
            if stack.is_empty()&&name.starts_with("pid/"){if service.replace(name.to_string()).is_some(){return Err("driver host procinfo duplicate service refused".into());}}
            stack.push(name.into());continue;
        }
        if let Some((key,value))=line.split_once(" = ").or_else(||line.split_once(" => ")){
            let name=if stack.is_empty(){key.to_string()}else{format!("{}/{}",stack.join("/"),key)};
            if fields.insert(name,value.to_string()).is_some(){return Err("driver host procinfo duplicate field refused".into());}
        }else if !plain.insert((stack.join("/"),line.to_string())){return Err("driver host procinfo duplicate flag refused".into());}
    }
    if !stack.is_empty(){return Err("driver host procinfo torn section refused".into());}
    let service=service.ok_or("driver host service binding missing")?;let prefix=format!("pid/{}/{DRIVER_HOST_ID}.",core.pid);let uuid=service.strip_prefix(&prefix).ok_or("driver host service core/domain differs")?;
    if !canonical_uuid(uuid){return Err("driver host launch instance UUID differs".into());}
    let expect=|key:&str,value:&str|->Result<()>{if fields.get(key).map(String::as_str)!=Some(value){return Err(format!("driver host procinfo {key} binding differs"));}Ok(())};
    for(key,value)in [("program path",DRIVER_HOST_EXE),("argument count","1"),("argument vector/[0]",DRIVER_HOST_DISPLAY),("responsible path","/usr/sbin/coreaudiod"),("code signing info","valid"),("bsd proc info/ppid","1"),("bsd proc info/uid","202"),("bsd proc info/svuid","202"),("bsd proc info/ruid","202"),("bsd proc info/gid","202"),("bsd proc info/svgid","202"),("bsd proc info/rgid","202"),("bsd proc info/comm name","com.apple.audio"),("bsd proc info/long name",DRIVER_HOST_LSOF),("bsd proc info/start date",start),("unique identifier info/parent id","1"),("entitlements/\"com.apple.private.audio.driver-host\"","true;"),("entitlements/\"com.apple.security.cs.disable-library-validation\"","true;")]{expect(key,value)?;}
    for key in ["bsd proc info/pid","bsd proc info/pgid","unique identifier info/id"]{expect(key,&pid.to_string())?;}
    for key in ["responsible pid","responsible unique pid"]{expect(key,&core.pid.to_string())?;}
    for flag in ["platform binary","entitlements validated","require enforcement"]{if !plain.contains(&(String::new(),flag.into())){return Err("driver host Apple platform signature proof differs".into());}}
    for(key,value)in [("original",DRIVER_HOST_ID),("path",DRIVER_HOST_BUNDLE),("type","XPCService"),("state","running"),("bundle id",DRIVER_HOST_ID),("program",DRIVER_HOST_EXE),("domain",&format!("pid/{} [coreaudiod]",core.pid)),("pid",&pid.to_string()),("environment/LaunchInstanceID",uuid),("environment/XPC_SERVICE_NAME",DRIVER_HOST_ID)]{expect(&format!("{service}/{key}"),value)?;}
    let properties=fields.get(&format!("{service}/properties")).ok_or("driver host service properties missing")?.split(" | ").collect::<Vec<_>>();
    for property in ["xpc bundle","joins host session","system service","one-shot"]{if properties.iter().filter(|value|**value==property).count()!=1{return Err("driver host service ownership properties differ".into());}}
    let process_uuid=fields.get("unique identifier info/uuid").ok_or("driver host executable UUID missing")?;
    if !canonical_uuid(process_uuid){return Err("driver host executable UUID malformed".into());}
    Ok((positive(fields.get(&format!("{service}/runs")).ok_or("driver host runs missing")?)?,process_uuid.clone(),positive(fields.get("unique identifier info/version").ok_or("driver host process version missing")?)?,uuid.into()))
}

// lsof's NUL field mode avoids spaces/newlines in path parsing. The only
// accepted HAL image is bound by actual device/inode, not its displayed name.
fn mapped_images(bytes:&[u8])->Result<Vec<(u32,String,String,u64,u64)>>{
    if bytes.is_empty()||bytes.len()>1024*1024||!bytes.ends_with(b"\n"){return Err("CoreAudio image inventory extent differs".into());}
    let mut process=None;let mut command=None;let mut record=BTreeMap::new();let mut images=Vec::new();let mut processes=std::collections::BTreeSet::new();
    fn finish(record:&mut BTreeMap<u8,String>,images:&mut Vec<(u32,String,String,u64,u64)>,process:Option<u32>,command:Option<&str>)->Result<()>{
        if record.is_empty(){return Ok(());}if record.get(&b'n').is_some_and(|path|path==DRIVER_HOST_EXE||path.ends_with("/Contents/MacOS/OpensteamerVirtualMicrophone")){
            if record.get(&b'f').map(String::as_str)!=Some("txt"){return Err("HAL/Apple image is not an executable text mapping".into());}
            let device=record.get(&b'D').and_then(|value|value.strip_prefix("0x")).ok_or("HAL mapping device missing")?;
            if device.is_empty()||device.len()>16||!device.bytes().all(|byte|byte.is_ascii_hexdigit()){return Err("HAL mapping device malformed".into());}
            let inode=positive(record.get(&b'i').ok_or("HAL mapping inode missing")?)?;
            images.push((process.ok_or("image mapping process missing")?,command.ok_or("image mapping command missing")?.into(),record[&b'n'].clone(),u64::from_str_radix(device,16).map_err(|_|"HAL mapping device overflow")?,inode));
        }record.clear();Ok(())
    }
    for (count,raw)in bytes.split(|byte|*byte==0).enumerate(){if count>32768{return Err("CoreAudio mapping field bound exceeded".into());}let token=raw.strip_prefix(b"\n").unwrap_or(raw);if token.is_empty()||token==b"\n"{continue;}
        let key=token[0];let value=std::str::from_utf8(&token[1..]).map_err(|_|"CoreAudio image field encoding differs")?.to_string();
        match key{
            b'p'=>{finish(&mut record,&mut images,process,command.as_deref())?;let pid=positive(&value)?;if pid<=1||pid>i32::MAX as u64||!processes.insert(pid){return Err("CoreAudio mapping process duplicate/bound differs".into());}process=Some(pid as u32);command=None;},
            b'c'=>{if process.is_none()||command.replace(value).is_some(){return Err("CoreAudio mapping command duplicate/order differs".into());}},
            b'f'=>{finish(&mut record,&mut images,process,command.as_deref())?;record.insert(key,value);},
            b'D'|b'i'|b'n'=>{if record.insert(key,value).is_some(){return Err("CoreAudio mapping field duplicate refused".into());}},
            _=>return Err("CoreAudio mapping unknown field refused".into()),
        }
    }
    finish(&mut record,&mut images,process,command.as_deref())?;Ok(images)
}
fn loaded_mapping(bytes:&[u8],pid:u32,apple:&Identity,prior:&Identity,candidate:&Identity)->Result<LoadedDriver>{
    let images=mapped_images(bytes)?;let apples=images.iter().filter(|image|image.2==DRIVER_HOST_EXE).collect::<Vec<_>>();let hals=images.iter().filter(|image|image.2!=DRIVER_HOST_EXE).collect::<Vec<_>>();
    if images.iter().any(|image|image.0!=pid||image.1!=DRIVER_HOST_LSOF)||apples.len()!=1||hals.len()!=1|| (apples[0].3,apples[0].4)!=(apple.device,apple.inode){return Err("exact Apple driver host and unique HAL image unproved".into());}
    if (hals[0].3,hals[0].4)==(prior.device,prior.inode){Ok(LoadedDriver::Prior)}else if (hals[0].3,hals[0].4)==(candidate.device,candidate.inode){Ok(LoadedDriver::Candidate)}else{Err("CoreAudio loaded HAL image inode differs".into())}
}
fn unique_hal_owner(bytes:&[u8],pid:u32,device:u64,inode:u64)->Result<()>{
    let images=mapped_images(bytes)?;if images.len()!=1||images[0].0!=pid||images[0].1!=DRIVER_HOST_LSOF||(images[0].3,images[0].4)!=(device,inode)||images[0].2==DRIVER_HOST_EXE{return Err("global exact HAL mapping is absent, duplicated or owned by another process".into());}Ok(())
}
// A single fixed-file search may not discard unrelated records or tolerate
// partial NUL framing. Names are only a two-role bound; inode remains authority.
fn selected_hal_owners(bytes:&[u8],selected:&Path,identity:&Identity)->Result<()>{
    if bytes.is_empty()||bytes.len()>1024*1024||!bytes.ends_with(b"\0\n"){return Err("selected HAL owner inventory extent/framing differs".into());}
    let selected=selected.to_str().ok_or("selected HAL image path encoding differs")?;let installed=format!("{DRIVER}/{DRIVER_EXE}");
    let mut process=None;let mut files=0;let mut total=0;let mut processes=std::collections::BTreeSet::new();
    for(count,line)in bytes[..bytes.len()-1].split(|byte|*byte==b'\n').enumerate(){
        if count>=128||line.is_empty()||!line.ends_with(b"\0"){return Err("selected HAL owner record framing/bound differs".into());}
        let fields=line[..line.len()-1].split(|byte|*byte==0).collect::<Vec<_>>();
        if fields.iter().any(|field|field.len()<2||field[1..].iter().any(|byte|*byte<32||*byte==127)){return Err("selected HAL owner field framing differs".into());}
        if fields[0][0]==b'p'{
            if process.is_some()&&files==0{return Err("selected HAL owner has an orphan process".into());}
            if fields.len()!=2||fields[1][0]!=b'c'||&fields[1][1..]!=DRIVER_HOST_LSOF.as_bytes(){return Err("selected HAL owner process fields/command differ".into());}
            let pid=positive(std::str::from_utf8(&fields[0][1..]).map_err(|_|"selected HAL owner PID encoding differs")?)?;
            if pid<=1||pid>i32::MAX as u64||!processes.insert(pid){return Err("selected HAL owner process duplicate/bound differs".into());}process=Some(pid);files=0;
        }else{
            if process.is_none()||fields.len()!=4||fields[0]!=b"ftxt"{return Err("selected HAL owner file/process ordering differs".into());}
            let mut record=BTreeMap::new();for field in fields{if ![b'f',b'D',b'i',b'n'].contains(&field[0])||record.insert(field[0],&field[1..]).is_some(){return Err("selected HAL owner file field set/duplicate differs".into());}}
            if record.len()!=4{return Err("selected HAL owner file field extent differs".into());}
            let device=std::str::from_utf8(record[&b'D']).map_err(|_|"selected HAL device encoding differs")?.strip_prefix("0x").ok_or("selected HAL device prefix differs")?;
            if device.is_empty()||device.len()>16||!device.bytes().all(|byte|byte.is_ascii_hexdigit()){return Err("selected HAL device field differs".into());}
            let inode=positive(std::str::from_utf8(record[&b'i']).map_err(|_|"selected HAL inode encoding differs")?)?;
            let name=std::str::from_utf8(record[&b'n']).map_err(|_|"selected HAL name encoding differs")?;
            if u64::from_str_radix(device,16).map_err(|_|"selected HAL device overflow")?!=identity.device||inode!=identity.inode||(name!=selected&&name!=installed){return Err("selected HAL mapping inode/name role differs".into());}
            files+=1;total+=1;if files>1||total>64{return Err("selected HAL owner mapping duplicate/bound exceeded".into());}
        }
    }
    if process.is_none()||files==0||total==0{return Err("selected HAL owner inventory has no complete mapping".into());}Ok(())
}
#[derive(Debug,PartialEq,Eq)]
enum SelectedOwnerInventory{Positive,Empty}
fn selected_owner_output(role:&str,captured:&os::Captured,path:&Path,identity:&Identity)->Result<SelectedOwnerInventory>{
    if !captured.stderr.is_empty(){return Err(inspector_summary(role,captured));}
    match captured.code{
        // -a -d txt may filter a found, held read FD from display. Empty0
        // and empty1 are equivalent only here; neither proves an owner.
        0|1 if captured.stdout.is_empty()=>Ok(SelectedOwnerInventory::Empty),
        0=>selected_hal_owners(&captured.stdout,path,identity).map(|()|SelectedOwnerInventory::Positive).map_err(|reason|format!("{} parse_error_sha256={}",inspector_summary(role,captured),sha256(reason.as_bytes()))),
        _=>Err(inspector_summary(role,captured)),
    }
}
fn global_hal_owner(prior_output:&os::Captured,candidate_output:&os::Captured,prior_path:&Path,prior:&Identity,candidate_path:&Path,candidate:&Identity,pid:u32,loaded:LoadedDriver)->Result<()>{
    let prior_inventory=selected_owner_output("driver_owners_prior",prior_output,prior_path,prior)?;let candidate_inventory=selected_owner_output("driver_owners_candidate",candidate_output,candidate_path,candidate)?;
    let selected=match(loaded,prior_inventory,candidate_inventory){(LoadedDriver::Prior,SelectedOwnerInventory::Positive,SelectedOwnerInventory::Empty)=>Some((prior_output,prior)),(LoadedDriver::Candidate,SelectedOwnerInventory::Empty,SelectedOwnerInventory::Positive)=>Some((candidate_output,candidate)),_=>None};
    let Some((output,identity))=selected else{return Err(format!("global HAL owner pair/loaded agreement refused; {}; {}",inspector_summary("driver_owners_prior",prior_output),inspector_summary("driver_owners_candidate",candidate_output)));};
    unique_hal_owner(&output.stdout,pid,identity.device,identity.inode).map_err(|reason|format!("{} owner_error_sha256={}",inspector_summary(if loaded==LoadedDriver::Prior{"driver_owners_prior"}else{"driver_owners_candidate"},output),sha256(reason.as_bytes())))
}
struct HeldDriverImage{file:File,path:PathBuf,identity:Identity}
impl HeldDriverImage{
    fn capture(path:&Path,identity:&Identity)->Result<Self>{
        if fs::canonicalize(path).map_err(|_|"selected image canonical path unavailable")?!=path||identity.uid!=0||identity.gid!=0||identity.mode!=0o100755||identity.links!=1{return Err("selected image path/owner/type/mode/links differ".into());}
        let file=OpenOptions::new().read(true).custom_flags(NOFOLLOW).open(path).map_err(|_|"selected image nofollow read-only descriptor unavailable")?;
        let held=Self{file,path:path.to_path_buf(),identity:identity.clone()};held.revalidate()?;Ok(held)
    }
    fn revalidate(&self)->Result<()>{
        if Identity::of(&self.file.metadata().map_err(|_|"selected image descriptor stat unavailable")?)!=self.identity||Identity::of(&fs::symlink_metadata(&self.path).map_err(|_|"selected image path disappeared")?)!=self.identity{return Err("selected image full descriptor/path identity changed".into());}sealed_fs::no_acl(&self.file)
    }
    fn owners(&self,role:&str)->Result<os::Captured>{
        self.revalidate()?;let output=(||inspector_capture(role,os::OwnedChild::driver_image_owner(&self.path)?,1024*1024))();let checked=self.revalidate();
        match(output,checked){(Ok(output),Ok(()))=>Ok(output),(Err(reason),Ok(()))=>Err(reason),(Ok(_),Err(error))=>Err(error),(Err(reason),Err(error))=>Err(format!("{reason} image_fence_error_sha256={}",sha256(error.as_bytes())))}
    }
}
fn completed_restart_budget(base:Option<&CoreGeneration>,normal_intent:Option<&CoreGeneration>,normal_done:Option<&CoreGeneration>,rollback_intent:Option<&CoreGeneration>,rollback_done:Option<&CoreGeneration>)->Result<(u8,u8)>{
    let Some(base)=base else{if normal_intent.is_some()||normal_done.is_some()||rollback_intent.is_some()||rollback_done.is_some(){return Err("restart records without exact baseline refused".into());}return Ok((0,0));};
    let Some(intent)=normal_intent else{if normal_done.is_some()||rollback_intent.is_some()||rollback_done.is_some(){return Err("restart completion without owned intent refused".into());}return Ok((0,0));};
    if intent!=base{return Err("normal restart intent baseline differs".into());}let normal=normal_done.ok_or("durable normal TERM intent unresolved; count is not zero and signal is never repeated")?;
    if !base.successor(normal){return Err("normal daemon completion is not an exact successor".into());}
    if let Some(intent)=rollback_intent{let done=rollback_done.ok_or("durable rollback TERM intent unresolved; count is not zero and signal is never repeated")?;if intent!=normal||!normal.successor(done){return Err("rollback daemon completion/budget differs".into());}Ok((1,1))}
    else{if rollback_done.is_some(){return Err("rollback completion without intent refused".into());}Ok((1,0))}
}
fn admission_refusal_bytes(request:&Request,reason:&str)->Result<Vec<u8>>{
    if reason.is_empty()||reason.len()>2048{return Err("admission refusal diagnostic extent differs".into());}
    let escaped=reason.as_bytes().iter().map(|byte|format!("{byte:02x}")).collect::<String>();
    Ok(format!("schema=opensteamer.microphone-v9-admission-refusal.v1\nnamespace={}\nnonce={}\nrequest_sha256={}\nreason_sha256={}\nreason_utf8_hex={}\n",request.get("namespace"),request.get("nonce"),request.sha256,sha256(reason.as_bytes()),escaped).into_bytes())
}
fn host_gate_failure(code:i32,stdout:&[u8],stderr:&[u8])->String{
    // Only the eventual fatal admission error is retained by the caller. The
    // expected absent-host probe while the host is present writes no record.
    // Never silently truncate diagnostics: large output retains exact extent
    // and SHA; bounded small stderr additionally retains escaped actual bytes.
    let detail=if stderr.len()<=512{stderr.iter().map(|b|format!("{b:02x}")).collect::<String>()}else{"not-inlined-over-512-bytes".into()};
    format!("sealed original-UID host gate failed code={code} stdout_bytes={} stdout_sha256={} stderr_bytes={} stderr_sha256={} stderr_hex={detail}",stdout.len(),sha256(stdout),stderr.len(),sha256(stderr))
}
fn validate_admission_refusal(bytes:&[u8],request:&Request)->Result<()>{
    let fields=strict_flat(bytes,&["schema","namespace","nonce","request_sha256","reason_sha256","reason_utf8_hex"],8192)?;
    let encoded=&fields["reason_utf8_hex"];if fields["schema"]!="opensteamer.microphone-v9-admission-refusal.v1"||fields["namespace"]!=request.get("namespace")||fields["nonce"]!=request.get("nonce")||fields["request_sha256"]!=request.sha256||!hex(&fields["reason_sha256"],64)||encoded.len()>4096||encoded.len()%2!=0||!hex(encoded,encoded.len()){return Err("admission refusal diagnostic crosslinks differ".into());}
    let reason=(0..encoded.len()).step_by(2).map(|i|u8::from_str_radix(&encoded[i..i+2],16).map_err(|_|"refusal hex malformed")).collect::<std::result::Result<Vec<_>,_>>()?;
    let text=std::str::from_utf8(&reason).map_err(|_|"admission refusal UTF-8 differs")?;if admission_refusal_bytes(request,text)?!=bytes{return Err("admission refusal canonical reason/hash differs".into());}Ok(())
}
fn retain_admission_before_pre_effect(request:&Request,reason:&str,prior:Option<&[u8]>,
    retain:impl FnOnce(&[u8])->Result<()>,pre_effect:impl FnOnce()->Result<()>)->Result<()>{
    let bytes=admission_refusal_bytes(request,reason)?;
    if let Some(prior)=prior{if prior!=bytes.as_slice(){return Err("first admission refusal is immutable".into());}validate_admission_refusal(prior,request)?;}
    else{retain(&bytes)?;}
    pre_effect()
}
fn failure_bytes(request:&Request,schema:&str,stage:&str,reason:&str)->Result<Vec<u8>>{
    if !["opensteamer.microphone-v9-forward-failure.v1","opensteamer.microphone-v9-guardian-start-failure.v1"].contains(&schema)||stage.is_empty()||stage.len()>48||!stage.bytes().all(|byte|byte.is_ascii_lowercase()||byte==b'_')||reason.is_empty()||reason.len()>2048{return Err("primary failure diagnostic bounds differ".into());}
    let encoded=reason.as_bytes().iter().map(|byte|format!("{byte:02x}")).collect::<String>();
    Ok(format!("schema={schema}\nnamespace={}\nnonce={}\nrequest_sha256={}\nstage={stage}\nreason_bytes={}\nreason_sha256={}\nreason_utf8_hex={encoded}\n",request.get("namespace"),request.get("nonce"),request.sha256,reason.len(),sha256(reason.as_bytes())).into_bytes())
}
fn retain_first_failure(bytes:&[u8],prior:Option<&[u8]>,retain:impl FnOnce(&[u8])->Result<()>)->Result<()>{
    if let Some(prior)=prior{if prior!=bytes{return Err("first failure diagnostic is immutable; secondary failure cannot replace it".into());}Ok(())}else{retain(bytes)}
}
enum FailureRecord{Forward,GuardianStart(u8)}
impl FailureRecord{
    fn name(&self)->Result<String>{match self{Self::Forward=>Ok("forward-failure.txt".into()),Self::GuardianStart(index)if (1..=5).contains(index)=>Ok(format!("guardian-{index}-start-failure.txt")),Self::GuardianStart(_)=>Err("guardian failure diagnostic index refused".into())}}
}
fn supervised_record(check:impl FnOnce()->Result<()>,write:impl FnOnce()->Result<()>)->Result<()>{check()?;write()}
fn retain_failure_storage(role:FailureRecord,bytes:&[u8],state:&Path,held:&sealed_fs::HeldDirectory,owner:u32,group:u32,guard:impl Fn()->Result<()>)->Result<()>{
    let name=role.name()?;
    if bytes.is_empty()||bytes.len()>16384{return Err("failure storage diagnostic extent refused".into());}
    guard()?;
    let stored=(||{
        let path=state.join(&name);
        let prior=match fs::symlink_metadata(&path){Ok(_)=>Some(read_owned(&path,owner,group,0o400,16384)?),Err(error)if error.kind()==std::io::ErrorKind::NotFound=>None,Err(_)=>return Err("failure storage record metadata unavailable".into())};
        retain_first_failure(bytes,prior.as_deref(),|bytes|held.write_record(&name,bytes,0o400))?;
        if read_owned(&path,owner,group,0o400,16384)?!=bytes{return Err("failure storage immutable readback differs".into());}Ok(())
    })();
    let after=guard();
    match(stored,after){(Ok(()),Ok(()))=>Ok(()),(Err(reason),Ok(()))=>Err(reason),(Ok(()),Err(reason))=>Err(reason),(Err(reason),Err(after))=>Err(format!("{reason}; failure_storage_postcheck_sha256={}",sha256(after.as_bytes())))}
}
fn primary_retention_result(reason:&str,retained:Result<()>)->Result<()>{
    retained.map_err(|retention|format!("{reason}; primary_retention_error_sha256={}",sha256(retention.as_bytes())))
}
fn guardian_slot_absent(state:&Path,index:u8)->Result<()>{
    if !(1..=5).contains(&index){return Err("guardian segment count exceeds restart/recovery bound".into());}
    for name in [format!("guardian-{index}.events"),format!("guardian-{index}.proof"),format!("guardian-{index}-start-failure.txt")]{
        match fs::symlink_metadata(state.join(name)){Err(error)if error.kind()==std::io::ErrorKind::NotFound=>{},Err(_)=>return Err("guardian slot inventory unavailable; never retry".into()),Ok(_)=>return Err("existing unproved guardian slot is immutable; no automatic retry".into())}
    }Ok(())
}
const PRE_EFFECT_RECORDS:&[&str]=&["request.txt","build-manifest.json","authority.txt","SEALING_INCOMPLETE","SEALING_COMPLETE","candidate.driver","journal","prior","failed","probes","host-baseline.txt","admission-refusal.txt","child-active-001","child-clean-001"];
fn refusal_journal_empty(memory:&Journal,durable:&Journal,resumed:bool,sequence:usize)->Result<()>{
    if memory.last().is_some()||durable.last().is_some()||resumed||sequence!=1{return Err("pre-effect refusal has durable/recovered transaction effects".into());}Ok(())
}
fn refusal_containment_finalized(clean:bool,resumed:bool,sequence:usize)->Result<()>{
    if !clean||resumed||sequence!=1{return Err("pre-effect refusal lacks first-attempt finalized containment".into());}Ok(())
}

impl RootContext{
    fn record(&self,name:&str,bytes:&[u8])->Result<()>{supervised_record(||self.revalidate(),||self.state_ancestry.last().unwrap().write_record(name,bytes,0o400))}
    fn retain_failure(&self,role:FailureRecord,bytes:&[u8])->Result<()>{
        // This storage-only path may preserve the original cause after an
        // abort/failed child cleanup. It never polls, clears or bypasses those
        // latches for admission, effects, recovery or successful outcomes.
        retain_failure_storage(role,bytes,&self.state,self.state_ancestry.last().ok_or("failure storage held state missing")?,0,0,||{
            for held in self.state_ancestry.iter().chain(self.exec_ancestry.iter()).chain(self.hal_ancestry.iter()){held.revalidate()?;}
            self.controller_lock.revalidate()?;
            let path=self.state.join("request.txt");let before=Identity::of(&self.request_file.metadata().map_err(|_|"failure storage held request stat unavailable")?);
            if before!=Identity::of(&fs::symlink_metadata(&path).map_err(|_|"failure storage request path unavailable")?){return Err("failure storage held request identity differs".into());}
            sealed_fs::no_acl(&self.request_file)?;
            if sha256(&read_owned(&path,0,0,0o400,MAX_REQUEST)?)!=self.request.sha256{return Err("failure storage request byte pin differs".into());}
            if before!=Identity::of(&self.request_file.metadata().map_err(|_|"failure storage held request restat unavailable")?)||before!=Identity::of(&fs::symlink_metadata(&path).map_err(|_|"failure storage request path disappeared")?){return Err("failure storage held request changed during read".into());}
            if strict_flat(&read_owned(&self.state.join("authority.txt"),0,0,0o400,MAX_REQUEST)?,AUTHORITY_FIELDS,MAX_REQUEST)?!=self.authority.fields{return Err("failure storage sealed authority changed".into());}
            if sha256(&read_owned(&self.executables.join("tools/gate_inputs.txt"),0,0,0o444,MAX_REQUEST)?)!=self.authority.get("gate_inputs_sha256"){return Err("failure storage gate inputs byte pin differs".into());}Ok(())
        })
    }
    fn optional_record(&self,name:&str)->Result<Option<Vec<u8>>>{
        match fs::symlink_metadata(self.state.join(name)){Ok(_)=>read_owned(&self.state.join(name),0,0,0o400,2*1024*1024).map(Some),Err(error)if error.kind()==std::io::ErrorKind::NotFound=>Ok(None),Err(_)=>Err("root record metadata unavailable".into())}
    }
    fn core_record(&self,name:&str)->Result<Option<CoreGeneration>>{
        let Some(bytes)=self.optional_record(name)?else{return Ok(None)};
        let fields=strict_flat(&bytes,&["schema","namespace","nonce","pid","runs","start_sha256"],8192)?;
        if fields["schema"]!="opensteamer.microphone-v9-core-generation.v1"||fields["namespace"]!=self.request.get("namespace")||fields["nonce"]!=self.request.get("nonce")||!hex(&fields["start_sha256"],64){return Err("root CoreAudio generation record identity differs".into());}
        let pid=positive(&fields["pid"])?;if pid>i32::MAX as u64{return Err("root CoreAudio PID bound differs".into());}
        Ok(Some(CoreGeneration{pid:pid as u32,runs:positive(&fields["runs"])?,start_sha:fields["start_sha256"].clone()}))
    }
    fn save_core(&self,name:&str,core:&CoreGeneration)->Result<()>{self.record(name,format!("schema=opensteamer.microphone-v9-core-generation.v1\nnamespace={}\nnonce={}\n{}",self.request.get("namespace"),self.request.get("nonce"),core.fields()).as_bytes())}
    fn driver_host_record(&self,name:&str)->Result<Option<DriverHostGeneration>>{
        let Some(bytes)=self.optional_record(name)?else{return Ok(None)};let fields=strict_flat(&bytes,DRIVER_HOST_FIELDS,8192)?;
        if fields["schema"]!="opensteamer.microphone-v9-driver-host-generation.v1"||fields["namespace"]!=self.request.get("namespace")||fields["nonce"]!=self.request.get("nonce"){return Err("driver host durable record crosslinks differ".into());}
        for key in ["core_start_sha256","start_sha256","apple_stat_sha256","apple_sha256"]{if !hex(&fields[key],64){return Err("driver host record digest malformed".into());}}
        for key in ["process_uuid","launch_uuid"]{if !canonical_uuid(&fields[key]){return Err("driver host record UUID malformed".into());}}
        let pid=positive(&fields["pid"])?;let core_pid=positive(&fields["core_pid"])?;if pid<=1||pid>i32::MAX as u64||core_pid<=1||core_pid>i32::MAX as u64{return Err("driver host record PID bound differs".into());}
        Ok(Some(DriverHostGeneration{core:CoreGeneration{pid:core_pid as u32,runs:positive(&fields["core_runs"])?,start_sha:fields["core_start_sha256"].clone()},pid:pid as u32,runs:positive(&fields["runs"])?,start_sha:fields["start_sha256"].clone(),process_uuid:fields["process_uuid"].clone(),process_version:positive(&fields["process_version"])?,launch_uuid:fields["launch_uuid"].clone(),apple_device:positive(&fields["apple_device"])?,apple_inode:positive(&fields["apple_inode"])?,apple_stat_sha:fields["apple_stat_sha256"].clone(),apple_sha:fields["apple_sha256"].clone(),hal_device:positive(&fields["hal_device"])?,hal_inode:positive(&fields["hal_inode"])?}))
    }
    fn save_driver_host(&self,name:&str,host:&DriverHostGeneration)->Result<()>{self.record(name,format!("schema=opensteamer.microphone-v9-driver-host-generation.v1\nnamespace={}\nnonce={}\n{}",self.request.get("namespace"),self.request.get("nonce"),host.fields()).as_bytes())}
    fn image_paths(&self)->Result<(PathBuf,Identity,PathBuf,Identity)>{
        let mut prior=Vec::new();let mut candidate=Vec::new();
        for path in [PathBuf::from(DRIVER),self.state.join("prior").join(DRIVER_NAME),self.state.join("candidate.driver"),self.state.join("failed").join(DRIVER_NAME)]{
            match fs::symlink_metadata(&path){Err(error)if error.kind()==std::io::ErrorKind::NotFound=>{},Err(_)=>return Err("HAL image location metadata unavailable".into()),Ok(metadata)=>{
                if (metadata.dev(),metadata.ino())==(self.request.number("predecessor_driver_device"),self.request.number("predecessor_driver_inode")){
                    let image=verify_bundle(&path,self.request.get("predecessor_driver_tree_sha256"),self.request.get("predecessor_driver_executable_sha256"),0)?.1;prior.push((path.join(DRIVER_EXE),image));
                }else if (metadata.dev(),metadata.ino())==(self.authority.candidate_root.device,self.authority.candidate_root.inode){
                    let image=verify_bundle(&path,self.request.get("driver_tree_sha256"),self.request.get("driver_executable_sha256"),0)?.1;
                    if image!=self.authority.candidate_executable{return Err("candidate executable full sealed identity changed".into());}candidate.push((path.join(DRIVER_EXE),image));
                }else{return Err("HAL image location is an unknown bundle inode".into());}
            }}
        }
        if prior.len()!=1||candidate.len()!=1{return Err("HAL images lack unique retained/candidate locations".into());}let(p,pi)=prior.pop().unwrap();let(c,ci)=candidate.pop().unwrap();Ok((p,pi,c,ci))
    }
    fn prior_identity(&self)->Result<(Identity,Identity)>{
        let mut exact=Vec::new();for path in [PathBuf::from(DRIVER),self.state.join("prior").join(DRIVER_NAME)]{
            match fs::symlink_metadata(&path){Err(error)if error.kind()==std::io::ErrorKind::NotFound=>{},Err(_)=>return Err("predecessor location metadata unavailable".into()),Ok(metadata)=>{
                if metadata.dev()==self.request.number("predecessor_driver_device")&&metadata.ino()==self.request.number("predecessor_driver_inode"){
                    exact.push(verify_bundle(&path,self.request.get("predecessor_driver_tree_sha256"),self.request.get("predecessor_driver_executable_sha256"),0)?);
                }
            }}
        }if exact.len()!=1{return Err("predecessor unique retained inode unproved".into());}Ok(exact.pop().unwrap())
    }
    fn read_driver_host(&self,core:&CoreGeneration)->Result<(DriverHostGeneration,LoadedDriver)>{
        if read_core()?!=*core{return Err("CoreAudio generation differs before driver-host proof".into());}
        let pid=driver_selector(&clean_output("driver_selector_before",os::OwnedChild::driver_host_pids()?,8192)?)?;
        let process=clean_output("driver_process_before",os::OwnedChild::driver_host_process(pid)?,8192)?;let(start_sha,start)=driver_process(&process,pid)?;
        let info=clean_output("driver_procinfo_before",os::OwnedChild::driver_host_procinfo(pid)?,65536)?;let(runs,process_uuid,process_version,launch_uuid)=driver_procinfo(&info,core,pid,&start)?;
        let apple=Path::new(DRIVER_HOST_EXE);let apple_identity=Identity::of(&fs::symlink_metadata(apple).map_err(|_|"Apple driver host image stat unavailable")?);
        let apple_bytes=read_owned(apple,0,0,0o755,16*1024*1024)?;
        let(prior_path,prior,candidate_path,candidate)=self.image_paths()?;
        let held_prior=HeldDriverImage::capture(&prior_path,&prior)?;let held_candidate=HeldDriverImage::capture(&candidate_path,&candidate)?;
        let bytes=clean_output("driver_mappings",os::OwnedChild::core_mappings(pid)?,1024*1024)?;let loaded=loaded_mapping(&bytes,pid,&apple_identity,&prior,&candidate)?;
        let image=if loaded==LoadedDriver::Prior{&prior}else{&candidate};let(hal_device,hal_inode)=(image.device,image.inode);
        held_prior.revalidate()?;held_candidate.revalidate()?;
        let prior_output=held_prior.owners("driver_owners_prior");let candidate_output=held_candidate.owners("driver_owners_candidate");
        // Always finish both full-stat pair fences, including a failed query.
        let prior_check=held_prior.revalidate();let candidate_check=held_candidate.revalidate();
        prior_check?;candidate_check?;let prior_output=prior_output?;let candidate_output=candidate_output?;
        global_hal_owner(&prior_output,&candidate_output,&prior_path,&prior,&candidate_path,&candidate,pid,loaded)?;
        let after_process=clean_output("driver_process_after",os::OwnedChild::driver_host_process(pid)?,8192)?;let after_identity=driver_process(&after_process,pid)?;
        let after_info=driver_procinfo(&clean_output("driver_procinfo_after",os::OwnedChild::driver_host_procinfo(pid)?,65536)?,core,pid,&after_identity.1)?;
        if after_identity!=(start_sha.clone(),start)||after_info!=(runs,process_uuid.clone(),process_version,launch_uuid.clone())||driver_selector(&clean_output("driver_selector_after",os::OwnedChild::driver_host_pids()?,8192)?)?!=pid||read_core()?!=*core||Identity::of(&fs::symlink_metadata(apple).map_err(|_|"Apple driver host image disappeared")?)!=apple_identity||self.image_paths()?!=(prior_path,prior,candidate_path,candidate){return Err("driver host/core/image generation changed during binding".into());}
        Ok((DriverHostGeneration{core:core.clone(),pid,runs,start_sha,process_uuid,process_version,launch_uuid,apple_device:apple_identity.device,apple_inode:apple_identity.inode,apple_stat_sha:sha256(format!("{apple_identity:?}").as_bytes()),apple_sha:sha256(&apple_bytes),hal_device,hal_inode},loaded))
    }
    fn bound_driver_host(&self,core:&CoreGeneration)->Result<(DriverHostGeneration,LoadedDriver)>{
        let first=self.read_driver_host(core)?;std::thread::sleep(Duration::from_millis(100));if self.read_driver_host(core)?!=first{return Err("driver host composite generation is unstable".into());}Ok(first)
    }
    fn idle_read(&self,action:&str,phase:&str,schema:u64,instance:Option<u64>,name:Option<&str>)->Result<proof::IdleReceipt>{
        self.revalidate()?;
        let mut args=vec![action.to_string(),"--phase".into(),phase.into(),"--schema".into(),schema.to_string(),"--nonce".into(),self.request.get("nonce").into()];
        if let Some(instance)=instance{if instance==0{return Err("idle instance is not positive".into());}args.extend(["--expected-instance".into(),instance.to_string()]);}
        let output=os::OwnedChild::native(&self.idle,&args,None,&[])?.finish(Duration::from_secs(20),1024*1024)?;
        if !output.stderr.is_empty(){return Err("sealed original-UID idle helper wrote stderr".into());}
        let receipt=proof::verify_idle(&output.stdout,proof::IdleExpected{phase,schema,nonce:self.request.get("nonce"),instance,exit_code:output.code})?;
        self.revalidate()?;if let Some(name)=name{self.record(name,&output.stdout)?;}Ok(receipt)
    }
    fn probe(&self,instance:u64,route_hash:&str)->Result<proof::PublicProofReceipt>{
        self.gate("--host-absent")?;self.revalidate()?;
        let parent=sealed_fs::HeldDirectory::capture(&self.state.join("probes"),0,0,0o700)?;
        let directory=parent.private_uid501_directory("public")?;
        let args=vec!["mirror-loopback-v9".into(),"--nonce".into(),self.request.get("nonce").into(),"--expected-instance".into(),instance.to_string(),"--required-headroom-seconds".into(),"60".into(),"--result".into(),"both-order.json".into()];
        let child=os::OwnedChild::native(&self.probe,&args,Some(&directory),&[])?;
        let output=child.finish(Duration::from_secs(120),MAX_REQUEST)?;
        // Console status is not authority; consume the actual root-held result
        // only after the owned child/group and both output pipes have ended.
        if output.code!=0||!output.stderr.is_empty(){return Err("owned nonce public oracle failed".into());}
        let path=self.state.join("probes/public/both-order.json");let bytes=read_owned(&path,501,20,0o600,1024*1024)?;
        let receipt=proof::verify_public(&bytes,self.request.get("nonce"),instance,route_hash)?;
        // Remove original-UID write authority after the complete owned group
        // has ended. Hold and restat the actual result before copying bytes.
        use std::os::fd::AsRawFd;
        unsafe extern "C"{fn fchown(fd:i32,uid:u32,gid:u32)->i32;fn fchmod(fd:i32,mode:u16)->i32;}
        let file=OpenOptions::new().read(true).custom_flags(NOFOLLOW).open(&path).map_err(|_|"public result held descriptor unavailable")?;
        if unsafe{fchown(file.as_raw_fd(),0,0)}!=0||unsafe{fchmod(file.as_raw_fd(),0o400)}!=0||unsafe{fchown(directory.as_raw_fd(),0,0)}!=0{return Err("public result root resealing failed".into());}
        file.sync_all().map_err(|_|"public result root seal sync failed")?;directory.sync_all().map_err(|_|"public directory root seal sync failed")?;
        if read_owned(&path,0,0,0o400,1024*1024)?!=bytes{return Err("root resealed public result bytes differ".into());}
        self.record("public-proof.json",&bytes)?;self.revalidate()?;self.gate("--host-absent")?;Ok(receipt)
    }
}

struct GuardianSegment{child:os::OwnedChild,event:File,index:u8,ready:Vec<u8>}
impl GuardianSegment{
    fn arm(context:&RootContext,index:u8)->Result<Self>{
        if !(1..=5).contains(&index){return Err("guardian segment count exceeds restart/recovery bound".into());}
        let mut stage="context";let mut child=None;
        let ready=format!("READY input={} output={} system={}\n",context.request.get("input_uid"),context.request.get("output_uid"),context.request.get("system_output_uid")).into_bytes();
        let attempt=(||->Result<File>{
            context.revalidate()?;stage="slot";guardian_slot_absent(&context.state,index)?;
            stage="event_create";let path=context.state.join(format!("guardian-{index}.events"));
            let event=OpenOptions::new().read(true).write(true).create_new(true).mode(0o600).custom_flags(NOFOLLOW).open(&path).map_err(|_|"guardian event exclusive creation failed")?;
            stage="event_metadata";let metadata=event.metadata().map_err(|_|"guardian event stat unavailable")?;
            if !metadata.is_file()||metadata.uid()!=0||metadata.gid()!=0||metadata.mode()&0o7777!=0o600||metadata.nlink()!=1||metadata.len()!=0{return Err("guardian root event ownership/mode differs".into());}
            sealed_fs::no_acl(&event)?;stage="event_sync";event.sync_all().map_err(|_|"guardian event sync failed")?;
            stage="descriptor";let inherited=os::OwnedChild::inherited(&event)?;
            let args=vec!["/dev/fd/5".into(),context.request.get("input_uid").into(),context.request.get("output_uid").into(),context.request.get("system_output_uid").into()];
            stage="spawn";child=Some(os::OwnedChild::native(&context.guardian,&args,None,&[(inherited.as_raw_fd(),5)])?);
            stage="ready";child.as_mut().unwrap().ready(&ready,Duration::from_secs(20))?;
            stage="postcheck";context.revalidate()?;Ok(event)
        })();
        match attempt{
            Ok(event)=>Ok(Self{child:child.take().unwrap(),event,index,ready}),
            Err(reason)=>{
                let retained=(||{
                    let mut bytes=failure_bytes(&context.request,"opensteamer.microphone-v9-guardian-start-failure.v1",stage,&reason)?;
                    bytes.extend_from_slice(format!("guardian_index={index}\nexpected_ready_sha256={}\nchild_owned={}\n",sha256(&ready),child.is_some()).as_bytes());
                    if let Some(child)=&child{bytes.extend_from_slice(child.failure_diagnostics().as_bytes());}
                    context.retain_failure(FailureRecord::GuardianStart(index),&bytes)
                })();
                primary_retention_result(&reason,retained)?;
                Err(reason)
            }
        }
    }
    fn healthy(&mut self)->Result<()>{
        let metadata=self.event.metadata().map_err(|_|"held guardian event stat unavailable")?;
        if metadata.uid()!=0||metadata.gid()!=0||metadata.mode()&0o7777!=0o600||metadata.nlink()!=1||metadata.len()!=0{return Err("sticky guardian notification/access evidence changed".into());}
        self.child.healthy(&self.ready)
    }
    fn finish(mut self,context:&RootContext)->Result<()>{
        self.healthy()?;self.child.write_line(b"STOP\n")?;
        let output=self.child.finish(Duration::from_secs(20),8192)?;
        let final_line=format!("RESULT notifications=0 teardown=clean input={} output={} system={}\n",context.request.get("input_uid"),context.request.get("output_uid"),context.request.get("system_output_uid"));
        let expected=[self.ready.as_slice(),final_line.as_bytes()].concat();
        if output.code!=0||!output.stderr.is_empty()||output.stdout!=expected||self.event.metadata().map_err(|_|"guardian final event stat failed")?.len()!=0{return Err("sticky guardian clean zero-notification teardown unproved".into());}
        self.event.sync_all().map_err(|_|"guardian final event sync failed")?;
        context.record(&format!("guardian-{}.proof",self.index),&output.stdout)?;Ok(())
    }
}

// Reviewed fixed-operation adapter. The public CLI requires native sealing,
// immutable namespace admission, owned signal/resume containment and fresh
// runtime proof. This is not an alternate unchecked entry point and has no
// generic privileged command.
pub(super) struct OsBackend{
    context:RootContext,journal:Journal,guardian:Option<GuardianSegment>,next_guardian:u8,
    clean_segments:u8,public:Option<proof::PublicProofReceipt>,idle:Option<proof::IdleReceipt>,
    candidate_instance:Option<u64>,rollback_bootstrap:Option<proof::IdleReceipt>,resumed:bool,primary_failure_unretained:bool,
}
impl Drop for OsBackend{
    fn drop(&mut self){
        // Struct fields otherwise drop context/lock before guardian. Contain
        // the owned monitor first so its failure latch is durably recorded by
        // RootContext::drop while the exact controller lock is still retained.
        if let Some(segment)=self.guardian.take(){if let Err(error)=segment.finish(&self.context){eprintln!("OWNED_GUARDIAN_TERMINAL_CLEANUP_UNVERIFIED: {error}");}}
    }
}
impl OsBackend{
    pub(super) fn open(request:&Request,resume:bool)->Result<Self>{
        let context=RootContext::open(request)?;
        // The shared root controller lock is retained before inspecting or
        // adopting any durable pending journal generation.
        context.controller_lock.revalidate()?;
        let journal=if resume{load_durable_journal(request)?}else{Journal::new(request)};
        let mut backend=Self{context,journal,guardian:None,next_guardian:1,clean_segments:0,public:None,idle:None,candidate_instance:None,rollback_bootstrap:None,resumed:resume,primary_failure_unretained:false};
        if let Some(bytes)=backend.context.optional_record("candidate-bootstrap.json")?{
            let receipt=proof::verify_idle(&bytes,proof::IdleExpected{phase:"after-reload",schema:2,nonce:request.get("nonce"),instance:None,exit_code:75})?;
            if receipt.progress!=proof::IdleProgress::BootstrapRequiresFreshIdleAndPublicProbe{return Err("saved candidate bootstrap progress differs".into());}backend.candidate_instance=Some(receipt.instance);
        }
        if let Some(bytes)=backend.context.optional_record("public-proof.json")?{
            let instance=backend.candidate_instance.ok_or("saved public proof lacks actual candidate instance")?;
            backend.public=Some(proof::verify_public(&bytes,request.get("nonce"),instance,&backend.routes_hash())?);
        }
        if let Some(bytes)=backend.context.optional_record("rollback-bootstrap.json")?{
            let receipt=proof::verify_idle(&bytes,proof::IdleExpected{phase:"after-rollback",schema:1,nonce:request.get("nonce"),instance:None,exit_code:75})?;
            if receipt.progress!=proof::IdleProgress::PriorBootstrapRequiresFreshMirroredIdle{return Err("saved rollback bootstrap progress differs".into());}backend.rollback_bootstrap=Some(receipt);
        }
        for index in 1..=5{
            if let Some(bytes)=backend.context.optional_record(&format!("guardian-{index}.proof"))?{
                let expected=backend.guardian_lines();if bytes!=expected{return Err("saved guardian zero-notification teardown differs".into());}backend.clean_segments+=1;backend.next_guardian=index+1;
            }else if fs::symlink_metadata(backend.context.state.join(format!("guardian-{index}.events"))).is_ok(){
                // A controller interrupted while a monitor was armed cannot
                // convert missing teardown/continuous evidence into clean.
                return Err("unresolved prior owned guardian requires explicit containment, never cached green".into());
            }
        }
        if resume{backend.prepare_resume_observers()?;}
        Ok(backend)
    }
    pub(super) fn journal_snapshot(&self)->Journal{self.journal.clone()}
    pub(super) fn retain_recovery_refusal(&mut self,reason:&str)->Result<()>{
        let bytes=admission_refusal_bytes(&self.context.request,reason)?;let bytes=String::from_utf8(bytes).map_err(|_|"recovery refusal encoding differs")?.replace("opensteamer.microphone-v9-admission-refusal.v1","opensteamer.microphone-v9-recovery-refusal.v1").into_bytes();
        self.context.record("recovery-refusal.txt",&bytes)
    }
    pub(super) fn restart_counts_for(&self,outcome:Terminal)->Result<(u8,u8)>{
        // Counts are durable owned daemon completions, not a second loaded()
        // observation that could mask the original error or create children
        // after final containment. Helper acceptance is a separate authority.
        if outcome==Terminal::Refused{
            self.pre_effect_empty()?;
            refusal_containment_finalized(self.context.child_clean,self.resumed,self.context.child_sequence)?;
            let reason=self.context.optional_record("admission-refusal.txt")?.ok_or("pre-effect refusal original diagnostic missing")?;validate_admission_refusal(&reason,&self.context.request)?;
            return Ok((0,0));
        }
        let base=self.context.core_record("core-baseline.txt")?;let ni=self.context.core_record("normal-restart-intent.txt")?;let nd=self.context.core_record("normal-restart-complete.txt")?;let ri=self.context.core_record("rollback-restart-intent.txt")?;let rd=self.context.core_record("rollback-restart-complete.txt")?;
        completed_restart_budget(base.as_ref(),ni.as_ref(),nd.as_ref(),ri.as_ref(),rd.as_ref())
    }
    fn pre_effect_empty(&self)->Result<()>{
        self.context.controller_lock.revalidate()?;let durable=load_pre_effect_empty_journal(&self.context.request)?;
        refusal_journal_empty(&self.journal,&durable,self.resumed,self.context.child_sequence)?;
        for(count,entry)in fs::read_dir(&self.context.state).map_err(|_|"pre-effect state inventory unavailable")?.enumerate(){
            if count>=64{return Err("pre-effect state inventory bound exceeded".into());}let entry=entry.map_err(|_|"pre-effect state entry unavailable")?;let name=entry.file_name().into_string().map_err(|_|"pre-effect state name differs")?;
            if gate_metadata_sequence(&name)?.is_some(){
                let bytes=read_owned(&entry.path(),0,0,0o400,MAX_REQUEST)?;let proof=GateMetadataFile::open(&entry.path(),&bytes)?;
                validate_initial_gate_metadata(&name,&proof.bytes,&self.context.request,self.context.authority.get("host_gate_sha256"))?;continue;
            }
            if !PRE_EFFECT_RECORDS.contains(&name.as_str()){return Err("pre-effect refusal has effect/baseline/unknown durable evidence".into());}
            if ["prior","failed","probes","journal"].contains(&name.as_str())&&fs::read_dir(entry.path()).map_err(|_|"pre-effect directory inventory unavailable")?.next().is_some(){return Err("pre-effect refusal contains retained effect/pending evidence".into());}
        }Ok(())
    }
    pub(super) fn finalize_containment(&mut self)->Result<()>{
        if self.guardian.is_some(){self.close_guardian()?;}
        self.context.close_child_fence()
    }
    pub(super) fn prepare_recovery(&mut self)->Result<Journal>{
        // This is called once by the still-owning worker after an interrupted
        // forward attempt. It does not authorize recovery from an unknown
        // external controller or an orphaned monitor.
        if self.primary_failure_unretained{return Err("primary forward failure persistence unproved; no automatic recovery".into());}
        if self.guardian.is_none(){guardian_slot_absent(&self.context.state,self.next_guardian)?;}
        os::enter_recovery()?;self.context.revalidate()?;
        self.journal=load_durable_journal(&self.context.request)?;
        self.prepare_resume_observers()?;Ok(self.journal.clone())
    }
    fn prepare_resume_observers(&mut self)->Result<()>{
        self.context.controller_lock.revalidate()?;
        let current=stable_core()?;
        for name in ["normal","rollback"]{
            let intent=self.context.core_record(&format!("{name}-restart-intent.txt"))?;
            if let Some(before)=intent{
                let host_before=self.context.driver_host_record(&format!("{name}-driver-host-intent.txt"))?.ok_or("service intent lacks owned driver-host intent; never repeat TERM")?;
                let expected=self.context.driver_host_record(if name=="normal"{"driver-host-baseline.txt"}else{"normal-driver-host-complete.txt"})?.ok_or("service intent driver-host baseline missing")?;
                if host_before!=expected||host_before.core!=before{return Err("service/driver-host intent generation differs".into());}
                if self.context.core_record(&format!("{name}-restart-complete.txt"))?.is_none(){
                // Daemon completion is independent of helper acceptance. This
                // resolves an owned intent only to a freshly exact successor;
                // it can never authorize another TERM or fabricate a load.
                if !before.successor(&current){return Err("durable service intent has no exact successor; never repeat TERM".into());}
                self.context.save_core(&format!("{name}-restart-complete.txt"),&current)?;
            }}
        }
        let(base,ni,nd,ri,rd)=(self.context.core_record("core-baseline.txt")?,self.context.core_record("normal-restart-intent.txt")?,self.context.core_record("normal-restart-complete.txt")?,self.context.core_record("rollback-restart-intent.txt")?,self.context.core_record("rollback-restart-complete.txt")?);
        let(normal,rollback)=completed_restart_budget(base.as_ref(),ni.as_ref(),nd.as_ref(),ri.as_ref(),rd.as_ref())?;
        if normal==1{
            let name=if rollback==1{"rollback"}else{"normal"};
            if self.context.driver_host_record(&format!("{name}-driver-host-complete.txt"))?.is_none(){
                let(host,loaded)=self.context.bound_driver_host(&current)?;
                let before=self.context.driver_host_record(if rollback==1{"normal-driver-host-complete.txt"}else{"driver-host-baseline.txt"})?.ok_or("interrupted helper binding baseline missing")?;
                if !before.successor(&host){return Err("interrupted service successor has no exact new driver host".into());}
                let observed_name=format!("{name}-driver-host-observed.txt");
                if let Some(observed)=self.context.driver_host_record(&observed_name)?{if observed!=host{return Err("helper changed after failed/interrupted reload observation".into());}}else{self.context.save_driver_host(&observed_name,&host)?;}
                if loaded==if rollback==1{LoadedDriver::Prior}else{LoadedDriver::Candidate}{self.context.save_driver_host(&format!("{name}-driver-host-complete.txt"),&host)?;}
                else if rollback==1||loaded!=LoadedDriver::Prior{return Err("interrupted reload expected HAL image unproved".into());}
            }
        }
        let(_,loaded,normal,rollback)=self.core_facts()?;
        if loaded==LoadedDriver::Candidate&&self.candidate_instance.is_none(){
            if normal!=1||rollback!=0{return Err("recovery candidate bootstrap has no exact owned successor".into());}
            let receipt=self.context.idle_read("--bootstrap-instance","after-reload",2,None,Some("candidate-bootstrap.json"))?;
            if receipt.progress!=proof::IdleProgress::BootstrapRequiresFreshIdleAndPublicProbe{return Err("recovery fresh candidate bootstrap differs".into());}self.candidate_instance=Some(receipt.instance);
        }
        if loaded==LoadedDriver::Prior&&rollback==1&&self.rollback_bootstrap.is_none(){
            let receipt=self.context.idle_read("--bootstrap-prior-instance","after-rollback",1,None,Some("rollback-bootstrap.json"))?;
            if receipt.progress!=proof::IdleProgress::PriorBootstrapRequiresFreshMirroredIdle{return Err("recovery fresh predecessor bootstrap differs".into());}self.rollback_bootstrap=Some(receipt);
        }
        if self.guardian.is_none(){self.arm()?;}else{self.guardian.as_mut().unwrap().healthy()?;}Ok(())
    }
    fn routes_hash(&self)->String{sha256(format!("{}\0{}\0{}",self.context.request.get("input_uid"),self.context.request.get("output_uid"),self.context.request.get("system_output_uid")).as_bytes())}
    fn guardian_lines(&self)->Vec<u8>{format!("READY input={} output={} system={}\nRESULT notifications=0 teardown=clean input={} output={} system={}\n",
        self.context.request.get("input_uid"),self.context.request.get("output_uid"),self.context.request.get("system_output_uid"),
        self.context.request.get("input_uid"),self.context.request.get("output_uid"),self.context.request.get("system_output_uid")).into_bytes()}
    fn arm(&mut self)->Result<()>{
        if self.guardian.is_some(){return Err("duplicate owned guardian refused".into());}
        let segment=GuardianSegment::arm(&self.context,self.next_guardian)?;self.next_guardian+=1;self.guardian=Some(segment);Ok(())
    }
    fn close_guardian(&mut self)->Result<()>{let segment=self.guardian.take().ok_or("owned guardian missing at clean teardown boundary")?;segment.finish(&self.context)?;self.clean_segments+=1;Ok(())}
    fn core_facts(&self)->Result<(CoreGeneration,LoadedDriver,u8,u8)>{
        let core=stable_core()?;let(host,loaded)=self.context.bound_driver_host(&core)?;
        let Some(base)=self.context.core_record("core-baseline.txt")?else{
            if loaded!=LoadedDriver::Prior||self.context.driver_host_record("driver-host-baseline.txt")?.is_some(){return Err("initial exact loaded predecessor/baseline is unproved".into());}
            for name in ["normal-restart-intent.txt","normal-restart-complete.txt","rollback-restart-intent.txt","rollback-restart-complete.txt","normal-driver-host-intent.txt","normal-driver-host-observed.txt","normal-driver-host-complete.txt","rollback-driver-host-intent.txt","rollback-driver-host-observed.txt","rollback-driver-host-complete.txt","normal-reload-unproved.txt","rollback-reload-unproved.txt"]{if self.context.optional_record(name)?.is_some(){return Err("initial observer has orphaned restart/helper evidence".into());}}return Ok((core,loaded,0,0));
        };
        let normal_intent=self.context.core_record("normal-restart-intent.txt")?;
        let normal_done=self.context.core_record("normal-restart-complete.txt")?;
        let rollback_intent=self.context.core_record("rollback-restart-intent.txt")?;
        let rollback_done=self.context.core_record("rollback-restart-complete.txt")?;
        if normal_intent.as_ref().is_some_and(|value|value!=&base){return Err("normal restart intent baseline differs".into());}
        let host_base=self.context.driver_host_record("driver-host-baseline.txt")?.ok_or("CoreAudio baseline lacks driver-host baseline")?;
        if host_base.core!=base{return Err("driver-host/CoreAudio baseline crosslink differs".into());}
        if normal_intent.is_none(){if core!=base||host!=host_base||normal_done.is_some()||rollback_intent.is_some()||rollback_done.is_some(){return Err("unowned CoreAudio/driver-host generation change refused".into());}
            for name in ["normal-driver-host-intent.txt","normal-driver-host-observed.txt","normal-driver-host-complete.txt","rollback-driver-host-intent.txt","rollback-driver-host-observed.txt","rollback-driver-host-complete.txt","normal-reload-unproved.txt","rollback-reload-unproved.txt"]{if self.context.optional_record(name)?.is_some(){return Err("driver-host restart evidence without service intent refused".into());}}return Ok((core,loaded,0,0));}
        if self.context.driver_host_record("normal-driver-host-intent.txt")?.as_ref()!=Some(&host_base){return Err("normal service intent driver-host baseline differs".into());}
        if core==base{return Err("durable TERM intent has no resolved successor; do not repeat signal".into());}
        let normal=normal_done.ok_or("daemon successor completion missing; no helper acceptance or repeat TERM")?;if !base.successor(&normal){return Err("normal restart completion is not exact successor".into());}
        if let Some(before)=rollback_intent{
            if before!=normal{return Err("rollback restart intent baseline differs".into());}
            if core==normal{return Err("durable rollback TERM intent has no resolved successor; do not repeat signal".into());}
            if !normal.successor(&core)||rollback_done.as_ref().is_some_and(|done|done!=&core){return Err("rollback restart generation/budget differs".into());}
            let normal_host=self.context.driver_host_record("normal-driver-host-complete.txt")?.ok_or("rollback lacks proven normal candidate driver host")?;
            let done=self.context.driver_host_record("rollback-driver-host-complete.txt")?.ok_or("rollback driver-host completion missing")?;
            if self.context.driver_host_record("rollback-driver-host-intent.txt")?.as_ref()!=Some(&normal_host)||loaded!=LoadedDriver::Prior||normal_host.core!=normal||!host_base.successor(&normal_host)||!normal_host.successor(&host)||host!=done{return Err("rollback exact driver-host generation/predecessor differs".into());}Ok((core,loaded,1,1))
        }else{
            if rollback_done.is_some()||core!=normal{return Err("CoreAudio changed outside normal restart budget".into());}
            let observed=self.context.driver_host_record("normal-driver-host-observed.txt")?.ok_or("owned daemon successor lacks driver-host observation; reload unproved")?;
            if observed!=host||!host_base.successor(&host){return Err("normal driver-host generation changed or was not newly bound".into());}
            if let Some(done)=self.context.driver_host_record("normal-driver-host-complete.txt")?{if done!=host||loaded!=LoadedDriver::Candidate{return Err("normal candidate driver-host completion differs".into());}}
            else if loaded!=LoadedDriver::Prior{return Err("normal helper acceptance unproved; cannot turn failed boundary green".into());}
            Ok((core,loaded,1,0))
        }
    }
    fn location(&self)->Result<DriverLocation>{
        match fs::symlink_metadata(DRIVER){Err(error)if error.kind()==std::io::ErrorKind::NotFound=>Ok(DriverLocation::CanonicalAbsent),Err(_)=>Err("canonical HAL metadata unavailable".into()),Ok(metadata)=>{
            if metadata.dev()==self.context.request.number("predecessor_driver_device")&&metadata.ino()==self.context.request.number("predecessor_driver_inode"){
                self.context.prior_identity()?;Ok(DriverLocation::PriorCanonical)
            }else if metadata.dev()==self.context.authority.candidate_root.device&&metadata.ino()==self.context.authority.candidate_root.inode{
                verify_bundle(Path::new(DRIVER),self.context.request.get("driver_tree_sha256"),self.context.request.get("driver_executable_sha256"),0)?;Ok(DriverLocation::CandidateCanonical)
            }else{Err("canonical HAL exact inode is unknown".into())}
        }}
    }
    fn host_gate(&self)->Result<HostGate>{
        if let Ok(gate)=self.context.gate("--host-absent"){return Ok(gate);}
        let name=if self.context.optional_record("rollback-host-ready.txt")?.is_some(){Some("rollback-host-ready.txt")}else if self.context.optional_record("host-ready.txt")?.is_some(){Some("host-ready.txt")}else{None};
        if let Some(name)=name{
            let gate=self.context.gate("--host-ready")?;
            let pinned=strict_flat(&self.context.optional_record(name)?.ok_or("ready generation pin disappeared")?,GATE_FIELDS,MAX_REQUEST)?;
            for key in ["host_pid","host_launchd_runs","host_start_identity_sha256","host_nonce","host_lock_device","host_lock_inode","host_display_identity_sha256","manager_generation","session_log_reset_offset"]{
                if gate.fields[key]!=pinned[key]{return Err("restarted host generation changed after owned bootstrap".into());}
            }Ok(gate)
        }else{self.context.gate("--candidate-present")}
    }
    fn reload(&mut self,rollback:bool)->Result<()>{
        self.context.gate("--host-absent")?;let(core,loaded,normal,restored)=self.core_facts()?;
        if rollback{
            if normal!=1||restored!=0||loaded!=LoadedDriver::Candidate||self.location()?!=DriverLocation::PriorCanonical{return Err("conditional rollback restart exact predicates differ".into());}
        }else if normal!=0||restored!=0||loaded!=LoadedDriver::Prior||self.location()?!=DriverLocation::CandidateCanonical{return Err("normal restart exact predicates differ".into());}
        let(before_host,_)=self.context.bound_driver_host(&core)?;self.close_guardian()?;
        let name=if rollback{"rollback"}else{"normal"};
        // No listener can truthfully cover the deliberate service reload gap.
        // Record that gap explicitly, never turn its absence into zero events.
        self.context.record(&format!("{name}-route-monitor-gap.txt"),format!("schema=opensteamer.microphone-v9-intentional-coreaudio-gap.v1\nnonce={}\nbefore_pid={}\nbefore_runs={}\ncoverage=not-claimed-inside-authorized-restart\n",self.context.request.get("nonce"),core.pid,core.runs).as_bytes())?;
        self.context.gate("--host-absent")?;
        if stable_core()?!=core||self.context.bound_driver_host(&core)?.0!=before_host{return Err("CoreAudio/driver-host generation changed before exact TERM".into());}
        let _restart_deferral=os::begin_restart_dispatch()?;
        self.context.save_core(&format!("{name}-restart-intent.txt"),&core)?;
        self.context.save_driver_host(&format!("{name}-driver-host-intent.txt"),&before_host)?;
        let result=(||->Result<()>{
            let output=os::OwnedChild::term_exact_core()?.finish(Duration::from_secs(5),8192)?;
            if output.code!=0||!output.stdout.is_empty()||!output.stderr.is_empty(){return Err("exact service-bound CoreAudio TERM failed; intent is never repeated".into());}
            let deadline=Instant::now()+Duration::from_secs(30);let after=loop{
                if let Ok(next)=stable_core(){if core.successor(&next){break next;}if next!=core{return Err("CoreAudio restart was not exactly one successor".into());}}
                if Instant::now()>=deadline{return Err("CoreAudio restart successor deadline exceeded".into());}std::thread::sleep(Duration::from_millis(100));
            };
            // Durable daemon accounting precedes helper/idle acceptance. An
            // old/unbound helper cannot conceal this consumed service TERM.
            self.context.save_core(&format!("{name}-restart-complete.txt"),&after)?;
            self.context.gate("--host-absent")?;
            let(host,image)=self.context.bound_driver_host(&after)?;
            if !before_host.successor(&host){return Err("service successor did not reload an exact newly bound Apple driver host".into());}
            self.context.save_driver_host(&format!("{name}-driver-host-observed.txt"),&host)?;
            if image!=if rollback{LoadedDriver::Prior}else{LoadedDriver::Candidate}{return Err("new Apple driver host loaded the wrong exact HAL generation".into());}
            self.context.save_driver_host(&format!("{name}-driver-host-complete.txt"),&host)?;
            let bootstrap=if rollback{self.context.idle_read("--bootstrap-prior-instance","after-rollback",1,None,Some("rollback-bootstrap.json"))?}
                else{self.context.idle_read("--bootstrap-instance","after-reload",2,None,Some("candidate-bootstrap.json"))?};
            if rollback{self.rollback_bootstrap=Some(bootstrap);}else{self.candidate_instance=Some(bootstrap.instance);}
            if self.context.bound_driver_host(&after)?!=(host,image){return Err("driver host changed across fresh bootstrap".into());}self.arm()?;Ok(())
        })();
        if let Err(reason)=&result{self.context.record(&format!("{name}-reload-unproved.txt"),format!("schema=opensteamer.microphone-v9-reload-unproved.v1\nnamespace={}\nnonce={}\nrequest_sha256={}\nbefore_pid={}\nbefore_runs={}\nreason_sha256={}\n",self.context.request.get("namespace"),self.context.request.get("nonce"),self.context.request.sha256,core.pid,core.runs,sha256(reason.as_bytes())).as_bytes())?;}result
    }
}
impl Backend for OsBackend{
    // Admission was explicitly enabled only after whole-path source review;
    // actual execution still requires every sealed and fresh runtime predicate.
    fn live_admission(&self)->bool{LIVE_ADMISSION}
    fn retain_forward_failure(&mut self,stage:&str,reason:&str)->Result<()>{
        let retained=(||{let bytes=failure_bytes(&self.context.request,"opensteamer.microphone-v9-forward-failure.v1",stage,reason)?;self.context.retain_failure(FailureRecord::Forward,&bytes)})();
        if retained.is_err(){self.primary_failure_unretained=true;}primary_retention_result(reason,retained)
    }
    fn retain_admission_refusal(&mut self,reason:&str)->Result<()>{
        let prior=self.context.optional_record("admission-refusal.txt")?;
        retain_admission_before_pre_effect(&self.context.request,reason,prior.as_deref(),
            |bytes|self.context.record("admission-refusal.txt",bytes),||self.pre_effect_empty())
    }
    fn persist(&mut self,journal:&Journal)->Result<()>{
        self.context.revalidate()?;let parent=sealed_fs::HeldDirectory::capture(&self.context.state.join("journal"),0,0,0o700)?;parent.persist(journal)?;self.journal=journal.clone();Ok(())
    }
    fn observe(&mut self)->Result<Facts>{
        self.context.revalidate()?;let gate=self.host_gate()?;let(_,loaded,normal,rollback)=self.core_facts()?;let location=self.location()?;
        if let Some(guardian)=self.guardian.as_mut(){guardian.healthy()?;}
        else if !self.journal.last().is_none_or(|state|state.committed()||matches!(state,State::RollbackHostReady|State::RolledBack)){return Err("current guarded route coverage is missing; historical proofs are not live monitoring".into());}
        if loaded==LoadedDriver::Prior&&rollback==0{
            let receipt=self.context.verify_idle_before()?;if receipt.progress!=proof::IdleProgress::IdleAccepted{return Err("actual predecessor mirrored idle proof differs".into());}
        }else if loaded==LoadedDriver::Prior{
            let bootstrap=self.rollback_bootstrap.as_ref().ok_or("rollback actual fresh bootstrap missing")?;
            let idle=self.context.idle_read("--verify-idle","after-rollback",1,Some(bootstrap.instance),None)?;proof::bind_after_rollback(bootstrap,&idle)?;
        }else{
            let instance=self.candidate_instance.ok_or("actual candidate instance missing")?;
            if let Some(public)=self.public.as_ref(){let idle=self.context.idle_read("--verify-idle","after-probe",2,Some(instance),None)?;proof::bind_after_probe(&idle,public)?;self.idle=Some(idle);}
            else{let initial=self.context.idle_read("--observe-initial-idle","after-reload",2,Some(instance),None)?;if initial.progress!=proof::IdleProgress::InitialRequiresPublicProbe{return Err("candidate initial idle is not typed non-green progression".into());}}
        }
        let retained=match fs::symlink_metadata(self.context.state.join("prior").join(DRIVER_NAME)){Ok(_)=>{self.context.prior_identity()?;true},Err(error)if error.kind()==std::io::ErrorKind::NotFound=>false,Err(_)=>return Err("retained predecessor metadata unavailable".into())};
        Ok(Facts{identity_exact:true,fresh_gate:true,root_sealed:true,host_present:gate.fields["host_present"]=="true",host_ready_exact:gate.fields["readiness"]=="true",
            driver:location,prior_retained_exact:retained,loaded,normal_restarts:normal,rollback_restarts:rollback,public_nonce_both_orders:self.public.is_some(),
            complete_v2_idle_with_history:self.idle.is_some(),route_notifications:0,route_teardown_clean:self.clean_segments>0})
    }
    fn effect(&mut self,effect:Effect)->Result<()>{os::supervisor_check()?;match effect{
        Effect::Seal=>{self.context.gate("--candidate-present")?;let core=stable_core()?;let(host,image)=self.context.bound_driver_host(&core)?;if image!=LoadedDriver::Prior{return Err("initial loaded predecessor differs".into());}self.context.save_core("core-baseline.txt",&core)?;self.context.save_driver_host("driver-host-baseline.txt",&host)?;self.arm()},
        Effect::StopHost=>self.context.stop_host().map(|_|()),Effect::RetainPrior=>self.context.retain_prior(),Effect::Publish=>self.context.publish(),
        Effect::NormalRestart=>self.reload(false),Effect::RollbackRestart=>self.reload(true),
        Effect::PublicProbe=>{let instance=self.candidate_instance.ok_or("public probe actual instance absent")?;self.public=Some(self.context.probe(instance,&self.routes_hash())?);Ok(())},
        Effect::IdleProbe=>{let instance=self.candidate_instance.ok_or("idle probe actual instance absent")?;let idle=self.context.idle_read("--verify-idle","after-probe",2,Some(instance),Some("after-probe-idle.json"))?;proof::bind_after_probe(&idle,self.public.as_ref().ok_or("owned public proof absent")?)?;self.idle=Some(idle);Ok(())},
        Effect::StartHost=>{
            self.context.gate("--host-absent")?;self.context.host_bytes()?;
            let output=os::OwnedChild::start_host()?.finish(Duration::from_secs(20),8192)?;
            if output.code!=0||!output.stdout.is_empty()||!output.stderr.is_empty(){return Err("matching original-UID host bootstrap failed".into());}
            let gate=self.context.gate("--host-ready")?;let name=if self.location()?==DriverLocation::PriorCanonical{"rollback-host-ready.txt"}else{"host-ready.txt"};self.context.record(name,&gate.bytes)
        },
        Effect::RetireCandidate=>self.context.retire_candidate(),Effect::RestorePrior=>self.context.restore_prior(),
        Effect::Audit=>{
            self.host_gate()?;self.core_facts()?;self.close_guardian()?;
            if !self.journal.last().is_some_and(|state|state.committed()||matches!(state,State::RollbackHostReady|State::RolledBack)){self.arm()?;}Ok(())
        },
    }}
}

#[cfg(test)]mod tests{
    use super::*;
    use std::io::Write;
    fn failed_011_fixture_request()->Request{
        let mut request=super::super::tests::request();request.fields.insert("namespace".into(),FAILED_011_NAMESPACE.into());request.fields.insert("nonce".into(),FAILED_011_NONCE.into());request.fields.insert("worker_sha256".into(),FAILED_011_WORKER.into());request.sha256=FAILED_011_REQUEST.into();request
    }
    fn failure_terminal_fixture(request:&Request)->Vec<u8>{
        let mut fields=FAILURE_TERMINAL_FIELDS.iter().map(|key|(*key,"a".repeat(64))).collect::<BTreeMap<_,_>>();
        for(key,value)in [("schema","opensteamer.microphone-v9-failed-no-effects-reconciled.v1"),("terminal",FAILURE_TERMINAL),("namespace",FAILED_011_NAMESPACE),("nonce",FAILED_011_NONCE),("request_sha256",FAILED_011_REQUEST),("authority_sha256",FAILED_011_AUTHORITY),("original_worker_sha256",FAILED_011_WORKER),("normal_restarts","0"),("rollback_restarts","0"),("original_cause","UNKNOWN"),("original_guardian_teardown","UNKNOWN"),("guardian_coverage_proven","false"),("deployment_verified","false"),("pcm_verified","false"),("observed_at_unix_ms","1790000000000")]{fields.insert(key,value.into());}
        let bytes=FAILURE_TERMINAL_FIELDS.iter().map(|key|format!("{key}={}\n",fields[key])).collect::<String>().into_bytes();failure_terminal_validate(&bytes,request).unwrap();bytes
    }
    #[test]fn failure_terminal_is_exact_011_unknown_cause_and_never_deployment_authority(){
        let request=failed_011_fixture_request();let bytes=failure_terminal_fixture(&request);let text=String::from_utf8(bytes).unwrap();
        for key in FAILURE_TERMINAL_FIELDS{let line=text.lines().find(|line|line.starts_with(&format!("{key}="))).unwrap();for mutant in [text.replace(&format!("{line}\n"),""),text.clone()+&format!("{line}\n"),text.replace(line,&format!("{key}=wrong"))]{assert!(failure_terminal_validate(mutant.as_bytes(),&request).is_err(),"accepted {key}");}}
        for(key,value)in [("terminal","COMMITTED_V9"),("original_cause","CONFIRMED"),("original_guardian_teardown","CLEAN"),("guardian_coverage_proven","true"),("deployment_verified","true"),("pcm_verified","true"),("normal_restarts","1"),("rollback_restarts","1")]{let line=text.lines().find(|line|line.starts_with(&format!("{key}="))).unwrap();assert!(failure_terminal_validate(text.replace(line,&format!("{key}={value}")).as_bytes(),&request).is_err());}
        assert!(failure_terminal_validate((text.clone()+"deployment_authority=true\n").as_bytes(),&request).is_err());assert!(failure_terminal_validate(text.trim_end().as_bytes(),&request).is_err());
        for key in ["namespace","nonce","worker_sha256"]{let mut mutant=request.clone();mutant.fields.insert(key.into(),"0".into());assert!(failure_terminal_validate(text.as_bytes(),&mutant).is_err());}let mut mutant=request;mutant.sha256="0".repeat(64);assert!(failure_terminal_validate(text.as_bytes(),&mutant).is_err());
    }
    fn reconciliation_inventory_fixture(label:&str)->(PathBuf,sealed_fs::HeldDirectory,u32,u32){
        let(path,held,owner,group)=pre_effect_directory_fixture(label);
        for name in FAILED_011_TOP{
            if ["candidate.driver","journal","prior","probes","failed"].contains(name){fs::create_dir(path.join(name)).unwrap();fs::set_permissions(path.join(name),fs::Permissions::from_mode(if *name=="candidate.driver"{0o755}else{0o700})).unwrap();}
            else if *name=="guardian-1.events"{OpenOptions::new().write(true).create_new(true).mode(0o600).open(path.join(name)).unwrap();}
            else{held.write_record(name,b"fixture immutable original",0o400).unwrap();}
        }
        for(kind,mode,relative)in NODES.iter().filter(|(_,_,relative)|*relative!="."){let node=path.join("candidate.driver").join(relative);if *kind=="Directory"{fs::create_dir(&node).unwrap();}else{fs::write(&node,b"fixture candidate bytes").unwrap();}fs::set_permissions(node,fs::Permissions::from_mode(*mode)).unwrap();}
        fs::write(path.join("journal/journal-001"),Journal::new(&failed_011_fixture_request()).appended(State::Prepared).unwrap().bytes()).unwrap();fs::set_permissions(path.join("journal/journal-001"),fs::Permissions::from_mode(0o400)).unwrap();(path,held,owner,group)
    }
    fn remove_reconciliation_fixture(path:&Path){
        // Exact exclusively-created fixture paths, never production or evidence.
        for(_,_,relative)in NODES.iter().rev().filter(|(_,_,relative)|*relative!="."){let node=path.join("candidate.driver").join(relative);if node.is_dir(){fs::remove_dir(node).unwrap();}else{fs::remove_file(node).unwrap();}}
        fs::remove_file(path.join("journal/journal-001")).unwrap();for name in RECONCILIATION_APPENDS.iter().chain(CONTINUATION_011_APPENDS).chain(CONTINUATION_002_APPENDS).copied().chain([FAILURE_TERMINAL,CONTINUATION_TERMINAL,CONTINUATION_002_TERMINAL]){if path.join(name).exists(){fs::remove_file(path.join(name)).unwrap();}}
        for name in FAILED_011_TOP{let node=path.join(name);if node.is_dir(){fs::remove_dir(node).unwrap();}else{fs::remove_file(node).unwrap();}}fs::remove_dir(path).unwrap();
    }
    #[test]fn failure_reconciliation_inventory_holds_every_original_node_across_only_fixed_appends(){
        let(path,held,owner,group)=reconciliation_inventory_fixture("reconcile-append");let original=ReconciliationInventory::capture(&path,&[],owner,group).unwrap();assert_eq!(original.nodes.len(),30);let digest=original.digest(true);
        for name in RECONCILIATION_APPENDS{held.write_record(name,b"fixture immutable observation",0o400).unwrap();}
        assert!(original.revalidate().is_err(),"initial19-node admission cannot be replayed after an append");original.revalidate_nodes().unwrap();let final_inventory=ReconciliationInventory::capture(&path,RECONCILIATION_APPENDS,owner,group).unwrap();assert_eq!(final_inventory.digest(true),digest);
        held.write_record(FAILURE_TERMINAL,b"fixture failure-only terminal",0o400).unwrap();assert!(held.write_record(FAILURE_TERMINAL,b"replacement",0o400).is_err());assert_eq!(fs::read(path.join(FAILURE_TERMINAL)).unwrap(),b"fixture failure-only terminal");original.revalidate_nodes().unwrap();final_inventory.revalidate_nodes().unwrap();
        assert!(ReconciliationInventory::capture(&path,&[],owner,group).is_err());assert!(ReconciliationInventory::capture(&path,&["public-proof.json"],owner,group).is_err());drop(final_inventory);drop(original);drop(held);remove_reconciliation_fixture(&path);
    }
    #[test]fn failure_reconciliation_inventory_refuses_unknown_pending_effect_and_inode_drift(){
        let(path,held,owner,group)=reconciliation_inventory_fixture("reconcile-mutants");let original=ReconciliationInventory::capture(&path,&[],owner,group).unwrap();
        for name in ["UNRESOLVED_CHILD","normal-restart-intent.txt","guardian-1.proof","child-active-003","unknown"]{held.write_record(name,b"must block",0o400).unwrap();assert!(ReconciliationInventory::capture(&path,&[],owner,group).is_err());fs::remove_file(path.join(name)).unwrap();}
        for directory in ["prior","probes","failed","journal","candidate.driver/Contents"]{let extra=path.join(directory).join("extra-empty");fs::create_dir(&extra).unwrap();assert!(original.revalidate_nodes().is_err());fs::remove_dir(extra).unwrap();}
        let pending=path.join("journal/pending-002");fs::write(&pending,b"pending").unwrap();assert!(ReconciliationInventory::capture(&path,&[],owner,group).is_err());fs::remove_file(pending).unwrap();
        let old=path.join("guardian-1.events");let retained=path.join("retained-fixture-event");fs::rename(&old,&retained).unwrap();fs::write(&old,b"").unwrap();fs::set_permissions(&old,fs::Permissions::from_mode(0o600)).unwrap();assert!(original.revalidate_nodes().is_err());fs::remove_file(old).unwrap();fs::rename(retained,path.join("guardian-1.events")).unwrap();
        drop(original);drop(held);remove_reconciliation_fixture(&path);
    }
    #[test]fn failure_reconciliation_prepared_only_never_adopts_resume_or_restart_journal(){
        let request=failed_011_fixture_request();let empty=Journal::new(&request);let prepared=empty.appended(State::Prepared).unwrap();prepared_only_reconciliation_journal(&prepared.bytes(),&request).unwrap();assert!(prepared_only_reconciliation_journal(&empty.bytes(),&request).is_err());
        for next in [State::Sealed,State::RollbackIntent]{assert!(prepared_only_reconciliation_journal(&prepared.appended(next).unwrap().bytes(),&request).is_err());}
        let mut mutant=prepared.bytes();mutant.extend_from_slice(b"unknown effect\n");assert!(prepared_only_reconciliation_journal(&mutant,&request).is_err());
    }
    #[test]fn failure_reconciliation_record_brackets_all_eleven_metadata_fields_and_nofollow(){
        let(path,held,owner,group)=pre_effect_directory_fixture("reconcile-stat");held.write_record("record",b"exact bytes",0o400).unwrap();let mut node=ReconciliationNode::capture(&path.join("record"),owner,group,0o400,false).unwrap();let identity=node.identity.clone();
        for index in 0..11{let mut changed=identity.clone();match index{0=>changed.device+=1,1=>changed.inode+=1,2=>changed.uid+=1,3=>changed.gid+=1,4=>changed.mode+=1,5=>changed.links+=1,6=>changed.size+=1,7=>changed.mtime+=1,8=>changed.mtime_nsec+=1,9=>changed.ctime+=1,_=>changed.ctime_nsec+=1};node.identity=changed;assert!(node.revalidate().is_err(),"accepted metadata field {index}");}node.identity=identity;node.revalidate().unwrap();
        std::os::unix::fs::symlink(path.join("record"),path.join("alias")).unwrap();assert!(ReconciliationNode::capture(&path.join("alias"),owner,group,0o400,false).is_err());assert!(ReconciliationNode::capture(&path.join("record"),owner+1,group,0o400,false).is_err());assert!(ReconciliationNode::capture(&path.join("record"),owner,group,0o600,false).is_err());
        drop(node);drop(held);fs::remove_file(path.join("alias")).unwrap();fs::remove_file(path.join("record")).unwrap();fs::remove_dir(path).unwrap();
    }
    fn replace_reconciliation_fixture_record(path:&Path,held:&sealed_fs::HeldDirectory,name:&str,bytes:&[u8]){
        // Only our exclusive synthetic fixture; never the retained original011.
        if path.join(name).exists(){fs::remove_file(path.join(name)).unwrap();}held.write_record(name,bytes,0o400).unwrap();
    }
    fn reconciliation_crosslink_fixture(label:&str)->(PathBuf,sealed_fs::HeldDirectory,u32,u32,Request){
        let(path,held,owner,group)=reconciliation_inventory_fixture(label);let request=failed_011_fixture_request();let(_,host)=gate_fixture("candidate-present");let mut fields=strict_flat(&host,GATE_FIELDS,MAX_REQUEST).unwrap();fields.insert("namespace".into(),request.get("namespace").into());fields.insert("nonce".into(),request.get("nonce").into());
        for(offset,name)in [(0,"host-baseline.txt"),(100,"reconciliation-host-before.txt"),(200,"reconciliation-host-after.txt")]{fields.insert("observed_at_unix_ms".into(),(1_790_000_000_000u64+offset).to_string());let bytes=GATE_FIELDS.iter().map(|key|format!("{key}={}\n",fields[*key])).collect::<String>().into_bytes();replace_reconciliation_fixture_record(&path,&held,name,&bytes);}
        let fence=child_fence_bytes(&request,2).unwrap();for name in ["child-active-002","child-clean-002"]{held.write_record(name,&fence,0o400).unwrap();}
        for(sequence,offset)in [(3,50),(4,150)]{let bytes=gate_metadata_bytes(&request,"91166013846d8579af6f94f647e6af3508b49427e83bff36c11d564380578a87","candidate-present",1_790_000_000_000+offset,sequence,&gate_metadata_identities()).unwrap();held.write_record(&format!("gate-metadata-{sequence:03}.txt"),&bytes,0o400).unwrap();}(path,held,owner,group,request)
    }
    fn reconciliation_crosslink_fixture_fields(inventory:&ReconciliationInventory,request:&Request)->BTreeMap<String,String>{
        let bytes=failure_reconciliation_record(request,&"b".repeat(64),inventory,inventory,1_790_000_000_300).unwrap();failure_terminal_validate(&bytes,request).unwrap()
    }
    fn continuation_fixture_fence(request:&Request,sequence:usize,owner:u32)->Vec<u8>{
        String::from_utf8(child_fence_bytes(request,sequence).unwrap()).unwrap().replace(&format!("owner_pid={}",std::process::id()),&format!("owner_pid={owner}")).into_bytes()
    }
    fn continuation_input_fixture(label:&str)->(PathBuf,sealed_fs::HeldDirectory,u32,u32,Request){
        let(path,held,owner,group)=reconciliation_inventory_fixture(label);let request=failed_011_fixture_request();
        let original=continuation_fixture_fence(&request,1,4982);assert_eq!(sha256(&original),FAILED_011_PINS.iter().find(|(name,_)|*name=="child-active-001").unwrap().1);
        for name in ["child-active-001","child-clean-001"]{replace_reconciliation_fixture_record(&path,&held,name,&original);}
        let historical=continuation_fixture_fence(&request,2,61441);assert_eq!(sha256(&historical),HISTORICAL_011_FENCE);for name in HISTORICAL_011_APPENDS{held.write_record(name,&historical,0o400).unwrap();}
        let(_,host)=gate_fixture("candidate-present");let mut fields=strict_flat(&host,GATE_FIELDS,MAX_REQUEST).unwrap();fields.insert("namespace".into(),FAILED_011_NAMESPACE.into());fields.insert("nonce".into(),FAILED_011_NONCE.into());fields.insert("observed_at_unix_ms".into(),"1790000000000".into());let baseline=GATE_FIELDS.iter().map(|key|format!("{key}={}\n",fields[*key])).collect::<String>().into_bytes();replace_reconciliation_fixture_record(&path,&held,"host-baseline.txt",&baseline);
        (path,held,owner,group,request)
    }
    fn append_continuation_fixture(path:&Path,held:&sealed_fs::HeldDirectory,request:&Request){
        let(_,host)=gate_fixture("candidate-present");let mut fields=strict_flat(&host,GATE_FIELDS,MAX_REQUEST).unwrap();fields.insert("namespace".into(),request.get("namespace").into());fields.insert("nonce".into(),request.get("nonce").into());
        for(offset,name)in [(100,"continuation-001-host-before.txt"),(200,"continuation-001-host-after.txt")]{fields.insert("observed_at_unix_ms".into(),(1_790_000_000_000u64+offset).to_string());let bytes=GATE_FIELDS.iter().map(|key|format!("{key}={}\n",fields[*key])).collect::<String>().into_bytes();replace_reconciliation_fixture_record(path,held,name,&bytes);}
        let fence=continuation_fixture_fence(request,3,70505);for name in ["child-active-003","child-clean-003"]{held.write_record(name,&fence,0o400).unwrap();}
        for(sequence,offset)in [(3,50),(4,150)]{let bytes=gate_metadata_bytes(request,"91166013846d8579af6f94f647e6af3508b49427e83bff36c11d564380578a87","candidate-present",1_790_000_000_000+offset,sequence,&gate_metadata_identities()).unwrap();held.write_record(&format!("gate-metadata-{sequence:03}.txt"),&bytes,0o400).unwrap();}
    }
    fn continuation_fixture_fields(input:&ReconciliationInventory,final_inventory:&ReconciliationInventory,request:&Request)->BTreeMap<String,String>{
        let bytes=continuation_reconciliation_record(request,&"b".repeat(64),input,final_inventory,1_790_000_000_300).unwrap();continuation_terminal_validate(&bytes,request).unwrap()
    }
    #[test]fn exact_continuation_input_pins_finalized002_and_never_replays_original_v1(){
        let(path,held,owner,group,request)=continuation_input_fixture("continuation-input");let input=ReconciliationInventory::capture_continuation(&path,HISTORICAL_011_APPENDS,owner,group).unwrap();assert_eq!(input.nodes.len(),32);historical_011_containment(&input,&request).unwrap();
        assert!(ReconciliationInventory::capture(&path,&[],owner,group).is_err());assert_eq!(next_child_fence_owned(&path,&request,owner,group).unwrap(),3);
        let original=input.continuation_digest(ContinuationProjection::Original);let input_digest=input.continuation_digest(ContinuationProjection::Input);assert_ne!(original,input_digest);
        for name in ["child-active-003","UNRESOLVED_CHILD",FAILURE_TERMINAL,"continuation-001-host-before.txt"]{held.write_record(name,b"unapproved partial state",0o400).unwrap();assert!(ReconciliationInventory::capture_continuation(&path,HISTORICAL_011_APPENDS,owner,group).is_err());fs::remove_file(path.join(name)).unwrap();}
        let historical=input.bytes("child-clean-002").unwrap();drop(input);
        for mutant in [continuation_fixture_fence(&request,2,61442),continuation_fixture_fence(&request,3,61441),b"unknown finalized fence".to_vec()]{replace_reconciliation_fixture_record(&path,&held,"child-clean-002",&mutant);let bad=ReconciliationInventory::capture_continuation(&path,HISTORICAL_011_APPENDS,owner,group).unwrap();assert!(historical_011_containment(&bad,&request).is_err());drop(bad);}
        replace_reconciliation_fixture_record(&path,&held,"child-clean-002",&historical);fs::remove_file(path.join("child-clean-002")).unwrap();assert!(ReconciliationInventory::capture_continuation(&path,HISTORICAL_011_APPENDS,owner,group).is_err());held.write_record("child-clean-002",&historical,0o400).unwrap();drop(held);remove_reconciliation_fixture(&path);
    }
    #[test]fn continuation_terminal_has_closed_v2_schema_and_never_relabels_consumed_worker(){
        let(path,held,owner,group,request)=continuation_input_fixture("continuation-schema");
        let input=ReconciliationInventory::capture_continuation(&path,HISTORICAL_011_APPENDS,owner,group).unwrap();append_continuation_fixture(&path,&held,&request);
        let extras=HISTORICAL_011_APPENDS.iter().chain(CONTINUATION_011_APPENDS).copied().collect::<Vec<_>>();let final_inventory=ReconciliationInventory::capture_continuation(&path,&extras,owner,group).unwrap();let fields=continuation_fixture_fields(&input,&final_inventory,&request);let text=CONTINUATION_TERMINAL_FIELDS.iter().map(|key|format!("{key}={}\n",fields[*key])).collect::<String>();assert_eq!(fields.len(),29);
        input.revalidate_nodes().unwrap();assert_eq!(input.continuation_digest(ContinuationProjection::Input),final_inventory.continuation_digest(ContinuationProjection::Input));validate_continuation_crosslinks(&final_inventory,&request,&fields).unwrap();
        for key in CONTINUATION_TERMINAL_FIELDS{let line=text.lines().find(|line|line.starts_with(&format!("{key}="))).unwrap();for mutant in [text.replace(&format!("{line}\n"),""),text.clone()+&format!("{line}\n"),text.replace(line,&format!("{key}=wrong"))]{assert!(continuation_terminal_validate(mutant.as_bytes(),&request).is_err(),"accepted {key}");}}
        for(key,value)in [("reconciler_worker_sha256",CONSUMED_011_RECONCILER),("reconciler_worker_sha256",FAILED_011_WORKER),("deployment_verified","true"),("guardian_coverage_proven","true"),("original_guardian_teardown","CLEAN"),("normal_restarts","1")]{let line=text.lines().find(|line|line.starts_with(&format!("{key}="))).unwrap();assert!(continuation_terminal_validate(text.replace(line,&format!("{key}={value}")).as_bytes(),&request).is_err());}
        assert!(failure_terminal_validate(text.as_bytes(),&request).is_err());assert!(continuation_terminal_validate(&failure_terminal_fixture(&request),&request).is_err());assert!(ReconciliationInventory::capture(&path,RECONCILIATION_APPENDS,owner,group).is_err());assert!(final_inventory.verify_original(&request).is_err(),"synthetic original records are never original011 authority");
        drop(final_inventory);drop(input);drop(held);remove_reconciliation_fixture(&path);
    }
    #[test]fn continuation_consumer_crosslinks_all_projections_fences_and_immutable_observations(){
        let(path,held,owner,group,request)=continuation_input_fixture("continuation-crosslinks");append_continuation_fixture(&path,&held,&request);
        let extras=HISTORICAL_011_APPENDS.iter().chain(CONTINUATION_011_APPENDS).copied().collect::<Vec<_>>();let inventory=ReconciliationInventory::capture_continuation(&path,&extras,owner,group).unwrap();let fields=continuation_fixture_fields(&inventory,&inventory,&request);validate_continuation_crosslinks(&inventory,&request,&fields).unwrap();assert_eq!(inventory.nodes.len(),38);
        for key in ["original_inventory_sha256","input_inventory_sha256","final_inventory_sha256","original_child_fence_sha256","historical_child_fence_sha256","reconciliation_child_fence_sha256","gate_before_sha256","gate_after_sha256","host_before_sha256","host_after_sha256","core_generation_sha256","driver_host_generation_sha256"]{let mut mutant=fields.clone();mutant.insert(key.into(),"0".repeat(64));assert!(validate_continuation_crosslinks(&inventory,&request,&mutant).is_err(),"accepted {key}");}
        assert_ne!(fields["original_inventory_sha256"],fields["input_inventory_sha256"]);assert_ne!(fields["input_inventory_sha256"],fields["final_inventory_sha256"]);assert!(inventory.verify_original(&request).is_err());
        let terminal=CONTINUATION_TERMINAL_FIELDS.iter().map(|key|format!("{key}={}\n",fields[*key])).collect::<String>();held.write_record(CONTINUATION_TERMINAL,terminal.as_bytes(),0o400).unwrap();assert!(held.write_record(CONTINUATION_TERMINAL,b"overwrite",0o400).is_err());let full=extras.iter().copied().chain([CONTINUATION_TERMINAL]).collect::<Vec<_>>();let completed=ReconciliationInventory::capture_continuation(&path,&full,owner,group).unwrap();assert_eq!(completed.continuation_digest(ContinuationProjection::Final),fields["final_inventory_sha256"]);assert!(validate_continuation_evidence(&completed,&request,terminal.as_bytes()).is_err(),"original pin validation remains first and unconditional");drop(completed);fs::remove_file(path.join(CONTINUATION_TERMINAL)).unwrap();
        fs::remove_file(path.join("child-clean-003")).unwrap();assert!(validate_continuation_crosslinks(&inventory,&request,&fields).is_err());drop(inventory);
        held.write_record("child-clean-003",&continuation_fixture_fence(&request,3,70506),0o400).unwrap();let bad=ReconciliationInventory::capture_continuation(&path,&extras,owner,group).unwrap();let fields=continuation_fixture_fields(&bad,&bad,&request);assert!(validate_continuation_crosslinks(&bad,&request,&fields).is_err());drop(bad);drop(held);remove_reconciliation_fixture(&path);
    }
    #[test]fn continuation_consumer_rejects_structured_host_display_and_metadata_mutants(){
        let(path,held,owner,group,request)=continuation_input_fixture("continuation-receipts");append_continuation_fixture(&path,&held,&request);let extras=HISTORICAL_011_APPENDS.iter().chain(CONTINUATION_011_APPENDS).copied().collect::<Vec<_>>();
        for name in ["gate-metadata-003.txt","gate-metadata-004.txt","continuation-001-host-before.txt","continuation-001-host-after.txt"]{
            let bytes=fs::read(path.join(name)).unwrap();let text=String::from_utf8(bytes.clone()).unwrap();let metadata=name.starts_with("gate-metadata");
            let keys=if metadata{vec![("sequence","2".into()),("request_sha256","0".repeat(64)),("worker_sha256",CONSUMED_011_RECONCILER.into()),("observed_at_unix_ms","1790000000201".into())]}else{vec![("session_log_inode","3".into()),("manager_generation","1".into()),("host_display_identity_sha256","0".repeat(64)),("input_uid","unexpected".into()),("observed_at_unix_ms","1789999999999".into())]};
            for(key,value)in keys{let line=text.lines().find(|line|line.starts_with(&format!("{key}="))).unwrap();let mutant=text.replace(line,&format!("{key}={value}"));assert_ne!(mutant,text);replace_reconciliation_fixture_record(&path,&held,name,mutant.as_bytes());let inventory=ReconciliationInventory::capture_continuation(&path,&extras,owner,group).unwrap();let fields=continuation_fixture_fields(&inventory,&inventory,&request);assert!(validate_continuation_crosslinks(&inventory,&request,&fields).is_err(),"accepted {name} {key}");drop(inventory);}
            replace_reconciliation_fixture_record(&path,&held,name,&bytes);
        }
        drop(held);remove_reconciliation_fixture(&path);
    }
    #[test]fn continuation_absence_requires_exact_owner_and_held_image_role_counts(){
        for owners in 0..=4{for consumed in [false,true]{for continuation in [false,true]{let expected=matches!((owners,consumed,continuation),(1,false,false)|(2,true,false)|(3,true,true));assert_eq!(failed_011_absence_role_count(owners,consumed,continuation).is_ok(),expected);}}}
    }
    const CONSUMED_METADATA_003_FIXTURE:&[u8]=b"schema=opensteamer.microphone-v9-root-gate-metadata.v1\nnamespace=driver-microphone-v9-151f574a1c3c354b\nnonce=0c6553bf7c2322bc87fc0b1580b739e2db7820fd8405ad4b8c9e33f6d0f8f0d5\nrequest_sha256=18c655bff4dd81a3fd9435aae9940fbc15fd92d6b6975a5fdb4245e3e7507178\nworker_sha256=d91091c850d22ec315cc08ca4add458efb5dfb3e29b26080ba0665dea9af5613\nhost_gate_sha256=91166013846d8579af6f94f647e6af3508b49427e83bff36c11d564380578a87\nmode=candidate-present\nobserved_at_unix_ms=1790951263407\nsequence=3\nacl_absent=true\nxattrs_empty=true\nprefix_identity=16777232,37808072,0,0,16841,9,288,1790940184,67270496,1790940184,67270496\nnamespace_identity=16777232,37859055,0,0,16841,7,224,1790940184,185283797,1790940184,185283797\ntools_identity=16777232,37859056,0,0,16841,6,192,1790940184,152836943,1790940184,152836943\nproduct_identity=16777232,37859057,0,0,16841,6,192,1790940184,180192915,1790940184,180192915\nobservers_identity=16777232,37859058,0,0,16841,5,160,1790940184,148649653,1790940184,148649653\n";
    fn continuation_002_input_fixture(label:&str)->(PathBuf,sealed_fs::HeldDirectory,u32,u32,Request){
        let(path,held,owner,group,request)=continuation_input_fixture(label);let fence=continuation_fixture_fence(&request,3,94114);assert_eq!(sha256(&fence),CONSUMED_011_CONTINUATION_FENCE);
        for name in ["child-active-003","child-clean-003"]{held.write_record(name,&fence,0o400).unwrap();}assert_eq!(sha256(CONSUMED_METADATA_003_FIXTURE),CONSUMED_011_CONTINUATION_METADATA);held.write_record("gate-metadata-003.txt",CONSUMED_METADATA_003_FIXTURE,0o400).unwrap();
        let mut baseline=strict_flat(&fs::read(path.join("host-baseline.txt")).unwrap(),GATE_FIELDS,MAX_REQUEST).unwrap();baseline.insert("observed_at_unix_ms".into(),"1790951263000".into());let bytes=GATE_FIELDS.iter().map(|key|format!("{key}={}\n",baseline[*key])).collect::<String>().into_bytes();replace_reconciliation_fixture_record(&path,&held,"host-baseline.txt",&bytes);(path,held,owner,group,request)
    }
    fn continuation_002_extras()->Vec<&'static str>{HISTORICAL_011_APPENDS.iter().chain(CONSUMED_CONTINUATION_011_APPENDS).chain(CONTINUATION_002_APPENDS).copied().collect()}
    fn append_continuation_002_fixture(path:&Path,held:&sealed_fs::HeldDirectory,request:&Request,new_quiet:bool){
        let mut fields=strict_flat(&fs::read(path.join("host-baseline.txt")).unwrap(),GATE_FIELDS,MAX_REQUEST).unwrap();
        if new_quiet{fields.insert("session_log_reset_offset".into(),"120".into());fields.insert("session_log_size".into(),"200".into());}
        for(offset,name)in [(1000,"continuation-002-host-before.txt"),(2000,"continuation-002-host-after.txt")]{fields.insert("observed_at_unix_ms".into(),(1_790_951_263_000u64+offset).to_string());let bytes=GATE_FIELDS.iter().map(|key|format!("{key}={}\n",fields[*key])).collect::<String>().into_bytes();replace_reconciliation_fixture_record(path,held,name,&bytes);}
        let fence=continuation_fixture_fence(request,4,94116);for name in ["child-active-004","child-clean-004"]{held.write_record(name,&fence,0o400).unwrap();}
        for(sequence,offset)in [(4,900),(5,1900)]{let bytes=gate_metadata_bytes(request,"91166013846d8579af6f94f647e6af3508b49427e83bff36c11d564380578a87","candidate-present",1_790_951_263_000+offset,sequence,&gate_metadata_identities()).unwrap();held.write_record(&format!("gate-metadata-{sequence:03}.txt"),&bytes,0o400).unwrap();}
    }
    fn continuation_002_fixture_fields(input:&ReconciliationInventory,final_inventory:&ReconciliationInventory,request:&Request)->BTreeMap<String,String>{
        let bytes=continuation_002_reconciliation_record(request,&"b".repeat(64),input,final_inventory,1_790_951_265_300).unwrap();continuation_002_terminal_validate(&bytes,request).unwrap()
    }
    #[test]fn continuation002_input_retains_exact_consumed003_and_rejects_bootstrap_owner_or_partial_retry(){
        let(path,held,owner,group,request)=continuation_002_input_fixture("continuation002-input");let extras=HISTORICAL_011_APPENDS.iter().chain(CONSUMED_CONTINUATION_011_APPENDS).copied().collect::<Vec<_>>();let input=ReconciliationInventory::capture_continuation_002(&path,&extras,owner,group).unwrap();consumed_continuation_011_containment(&input,&request).unwrap();assert_eq!(input.nodes.len(),35);assert_eq!(next_child_fence_owned(&path,&request,owner,group).unwrap(),4);
        assert!(input.verify_original(&request).is_err(),"synthetic original records never become original011 authority");assert!(ReconciliationInventory::capture_continuation(&path,HISTORICAL_011_APPENDS,owner,group).is_err());
        for name in ["child-active-004","gate-metadata-004.txt","continuation-001-host-before.txt",CONTINUATION_TERMINAL,CONTINUATION_002_TERMINAL,"UNRESOLVED_CHILD"]{held.write_record(name,b"unapproved partial state",0o400).unwrap();assert!(ReconciliationInventory::capture_continuation_002(&path,&extras,owner,group).is_err());fs::remove_file(path.join(name)).unwrap();}
        drop(input);let actual=continuation_fixture_fence(&request,3,94114);
        for mutant in [continuation_fixture_fence(&request,3,94112),continuation_fixture_fence(&request,4,94114),b"unknown003".to_vec()]{replace_reconciliation_fixture_record(&path,&held,"child-clean-003",&mutant);let bad=ReconciliationInventory::capture_continuation_002(&path,&extras,owner,group).unwrap();assert!(consumed_continuation_011_containment(&bad,&request).is_err());}
        replace_reconciliation_fixture_record(&path,&held,"child-clean-003",&actual);let text=String::from_utf8(CONSUMED_METADATA_003_FIXTURE.to_vec()).unwrap();replace_reconciliation_fixture_record(&path,&held,"gate-metadata-003.txt",text.replace("sequence=3","sequence=4").as_bytes());let bad=ReconciliationInventory::capture_continuation_002(&path,&extras,owner,group).unwrap();assert!(consumed_continuation_011_containment(&bad,&request).is_err());drop(bad);drop(held);remove_reconciliation_fixture(&path);
    }
    #[test]fn continuation002_v3_schema_is_closed_and_never_relabels_old_roles_or_guardian(){
        let(path,held,owner,group,request)=continuation_002_input_fixture("continuation002-schema");let input_extras=HISTORICAL_011_APPENDS.iter().chain(CONSUMED_CONTINUATION_011_APPENDS).copied().collect::<Vec<_>>();let input=ReconciliationInventory::capture_continuation_002(&path,&input_extras,owner,group).unwrap();append_continuation_002_fixture(&path,&held,&request,true);let final_inventory=ReconciliationInventory::capture_continuation_002(&path,&continuation_002_extras(),owner,group).unwrap();let fields=continuation_002_fixture_fields(&input,&final_inventory,&request);let text=CONTINUATION_002_TERMINAL_FIELDS.iter().map(|key|format!("{key}={}\n",fields[*key])).collect::<String>();assert_eq!(fields.len(),32);validate_continuation_002_crosslinks(&final_inventory,&request,&fields).unwrap();
        for key in CONTINUATION_002_TERMINAL_FIELDS{let line=text.lines().find(|line|line.starts_with(&format!("{key}="))).unwrap();for mutant in [text.replace(&format!("{line}\n"),""),text.clone()+&format!("{line}\n"),text.replace(line,&format!("{key}=wrong"))]{assert!(continuation_002_terminal_validate(mutant.as_bytes(),&request).is_err(),"accepted {key}");}}
        for(key,value)in [("reconciler_worker_sha256",FAILED_011_WORKER),("reconciler_worker_sha256",CONSUMED_011_RECONCILER),("reconciler_worker_sha256",CONSUMED_011_CONTINUATION),("deployment_verified","true"),("pcm_verified","true"),("guardian_coverage_proven","true"),("original_guardian_teardown","CLEAN"),("normal_restarts","1")]{let line=text.lines().find(|line|line.starts_with(&format!("{key}="))).unwrap();assert!(continuation_002_terminal_validate(text.replace(line,&format!("{key}={value}")).as_bytes(),&request).is_err());}
        assert!(continuation_terminal_validate(text.as_bytes(),&request).is_err());assert!(failure_terminal_validate(text.as_bytes(),&request).is_err());assert!(validate_continuation_002_evidence(&final_inventory,&request,text.as_bytes()).is_err());input.revalidate_nodes().unwrap();drop(final_inventory);drop(input);drop(held);remove_reconciliation_fixture(&path);
    }
    #[test]fn continuation002_accepts_natural_new_quiet_boundary_then_requires_exact_fresh_boundary(){
        for new_quiet in [false,true]{let(path,held,owner,group,request)=continuation_002_input_fixture("continuation002-quiet");append_continuation_002_fixture(&path,&held,&request,new_quiet);let inventory=ReconciliationInventory::capture_continuation_002(&path,&continuation_002_extras(),owner,group).unwrap();let fields=continuation_002_fixture_fields(&inventory,&inventory,&request);validate_continuation_002_crosslinks(&inventory,&request,&fields).unwrap();assert_eq!(inventory.nodes.len(),41);assert_ne!(fields["original_inventory_sha256"],fields["input_inventory_sha256"]);assert_ne!(fields["input_inventory_sha256"],fields["final_inventory_sha256"]);drop(inventory);drop(held);remove_reconciliation_fixture(&path);}
    }
    #[test]fn continuation002_rejects_inside_extent_reset_or_regression_and_all_identity_changes(){
        let(request,bytes)=gate_fixture("candidate-present");let mut original=HostGate::validate(&bytes,&request,"--candidate-present").unwrap();let mut fresh=original.clone();fresh.fields.insert("session_log_size".into(),"200".into());fresh.fields.insert("session_log_reset_offset".into(),"120".into());recovery_quiet_transition(&original,&fresh,true).unwrap();
        let mut exact_boundary=fresh.clone();exact_boundary.fields.insert("session_log_reset_offset".into(),original.fields["session_log_size"].clone());recovery_quiet_transition(&original,&exact_boundary,true).unwrap();
        let mut growing_suffix=fresh.clone();growing_suffix.fields.insert("session_log_size".into(),"201".into());recovery_quiet_transition(&fresh,&growing_suffix,false).unwrap();
        for reset in ["1","50","99"]{let mut bad=fresh.clone();bad.fields.insert("session_log_reset_offset".into(),reset.into());assert!(recovery_quiet_transition(&original,&bad,true).is_err());}original.fields.insert("session_log_reset_offset".into(),"50".into());let mut bad=fresh.clone();bad.fields.insert("session_log_reset_offset".into(),"0".into());assert!(recovery_quiet_transition(&original,&bad,true).is_err());
        for key in ["host_pid","host_launchd_runs","host_start_identity_sha256","host_nonce","host_lock_device","host_lock_inode","host_display_identity_sha256","host_executable_sha256","host_framework_sha256","host_info_plist_sha256","host_launch_plist_sha256","input_uid","output_uid","system_output_uid","routes_identity_sha256","manager_generation","session_log_device","session_log_inode"]{let mut bad=fresh.clone();bad.fields.insert(key.into(),"changed".into());assert!(recovery_quiet_transition(&original,&bad,true).is_err(),"accepted {key}");}
        for(key,value)in [("session_log_size","99"),("observed_at_unix_ms","1")]{let mut bad=fresh.clone();bad.fields.insert(key.into(),value.into());assert!(recovery_quiet_transition(&original,&bad,true).is_err());}
        for(key,value)in [("session_log_reset_offset","150"),("manager_generation","1"),("session_log_sha256","0"),("session_log_tail_sha256","0")]{let mut bad=fresh.clone();bad.fields.insert(key.into(),value.into());assert!(recovery_quiet_transition(&fresh,&bad,false).is_err(),"accepted after-fresh {key}");}
    }
    #[test]fn continuation002_consumer_rejects_new_reset_stale_metadata_and_rebound_host_receipts(){
        let(path,held,owner,group,request)=continuation_002_input_fixture("continuation002-receipts");append_continuation_002_fixture(&path,&held,&request,true);let extras=continuation_002_extras();
        for(name,mutants)in [("continuation-002-host-before.txt",vec![("session_log_reset_offset","99"),("manager_generation","1"),("session_log_inode","3"),("session_quiescent","false"),("display_headless","true")]),("continuation-002-host-after.txt",vec![("session_log_reset_offset","150"),("session_log_size","199"),("session_log_sha256","0000000000000000000000000000000000000000000000000000000000000000"),("session_log_tail_sha256","0000000000000000000000000000000000000000000000000000000000000000")]),("gate-metadata-004.txt",vec![("sequence","3"),("observed_at_unix_ms","1790951263000"),("observed_at_unix_ms","1790951264100")]),("gate-metadata-005.txt",vec![("observed_at_unix_ms","1790951263999"),("observed_at_unix_ms","1790951265100")])]{
            let bytes=fs::read(path.join(name)).unwrap();let text=String::from_utf8(bytes.clone()).unwrap();for(key,value)in mutants{let line=text.lines().find(|line|line.starts_with(&format!("{key}="))).unwrap();let mutant=text.replace(line,&format!("{key}={value}"));assert_ne!(mutant,text);replace_reconciliation_fixture_record(&path,&held,name,mutant.as_bytes());let inventory=ReconciliationInventory::capture_continuation_002(&path,&extras,owner,group).unwrap();let fields=continuation_002_fixture_fields(&inventory,&inventory,&request);assert!(validate_continuation_002_crosslinks(&inventory,&request,&fields).is_err(),"accepted {name} {key}");drop(inventory);}replace_reconciliation_fixture_record(&path,&held,name,&bytes);
        }
        let inventory=ReconciliationInventory::capture_continuation_002(&path,&extras,owner,group).unwrap();let fields=continuation_002_fixture_fields(&inventory,&inventory,&request);for key in ["original_inventory_sha256","input_inventory_sha256","final_inventory_sha256","original_child_fence_sha256","historical_child_fence_sha256","consumed_continuation_child_fence_sha256","consumed_continuation_gate_metadata_sha256","reconciliation_child_fence_sha256","gate_before_sha256","gate_after_sha256","host_before_sha256","host_after_sha256","core_generation_sha256","driver_host_generation_sha256"]{let mut bad=fields.clone();bad.insert(key.into(),"0".repeat(64));assert!(validate_continuation_002_crosslinks(&inventory,&request,&bad).is_err(),"accepted {key}");}for observed in ["1790951264999","1790951270301"]{let mut bad=fields.clone();bad.insert("observed_at_unix_ms".into(),observed.into());assert!(validate_continuation_002_crosslinks(&inventory,&request,&bad).is_err());}drop(inventory);drop(held);remove_reconciliation_fixture(&path);
    }
    #[test]fn recovery_streaming_sha_matches_known_vectors_and_arbitrary_chunk_boundaries(){
        for(bytes,expected)in [(b"".as_slice(),"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),(b"abc".as_slice(),"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")]{let mut hash=RecoveryPrefixHash::new();for byte in bytes{hash.update(&[*byte]).unwrap();}assert_eq!(hash.finish(),expected);}
        for extent in [1,55,56,63,64,65,127,128,1024,1024*1024+63]{let bytes=(0..extent).map(|index|(index%251)as u8).collect::<Vec<_>>();let expected=sha256(&bytes);for count in [1,7,63,64,65,4096,1024*1024]{let mut hash=RecoveryPrefixHash::new();for chunk in bytes.chunks(count){hash.update(chunk).unwrap();assert!(hash.pending.len()<64);}assert_eq!(hash.finish(),expected);}}
    }
    #[test]fn recovery_streaming_sha_bounded_128mib_throughput_sample(){
        let chunk=(0..1024*1024).map(|index|(index%251)as u8).collect::<Vec<_>>();let mut hash=RecoveryPrefixHash::new();let began=Instant::now();for _ in 0..128{hash.update(&chunk).unwrap();}let digest=hash.finish();let seconds=began.elapsed().as_secs_f64();assert!(hex(&digest,64));assert!(seconds>0.0);println!("recovery_prefix_benchmark bytes=134217728 seconds={seconds:.6} mib_per_second={:.6} estimated_2724000472_bytes_seconds={:.6}",128.0/seconds,seconds*2724000472.0/134217728.0);
    }
    #[test]fn recovery_streaming_held_prefix_rejects_tamper_tail_truncation_deadline_and_named_replacement(){
        let(path,held,_,_)=pre_effect_directory_fixture("recovery-prefix");let log=path.join("private-log");let prefix=b"nonsecret historical fixture\n";let tail=b"Worldwide viewer disconnected\nordinary idle log\n";let bytes=[prefix.as_slice(),tail.as_slice()].concat();let mut writer=OpenOptions::new().write(true).create_new(true).mode(0o600).open(&log).unwrap();writer.write_all(&bytes).unwrap();writer.sync_all().unwrap();let file=OpenOptions::new().read(true).custom_flags(NOFOLLOW).open(&log).unwrap();let(request,wire)=gate_fixture("candidate-present");let mut gate=HostGate::validate(&wire,&request,"--candidate-present").unwrap();let metadata=file.metadata().unwrap();assert_eq!(metadata.uid(),501,"private prefix fixture runs only as original UID501");for(key,value)in [("session_log_device",metadata.dev().to_string()),("session_log_inode",metadata.ino().to_string()),("session_log_size",bytes.len().to_string()),("session_log_reset_offset",prefix.len().to_string()),("session_log_sha256",sha256(&bytes)),("session_log_tail_sha256",sha256(tail))]{gate.fields.insert(key.into(),value);}
        recovery_stream_prefix(&file,&log,&gate,Instant::now()+Duration::from_secs(2)).unwrap();assert!(recovery_stream_prefix(&file,&log,&gate,Instant::now()).is_err());writer.write_all(b"append outside retained snapshot\n").unwrap();recovery_stream_prefix(&file,&log,&gate,Instant::now()+Duration::from_secs(2)).unwrap();
        writer.write_at(b"X",0).unwrap();assert!(recovery_stream_prefix(&file,&log,&gate,Instant::now()+Duration::from_secs(2)).is_err());writer.write_at(&bytes,0).unwrap();let mut bad=gate.clone();bad.fields.insert("session_log_tail_sha256".into(),"0".repeat(64));assert!(recovery_stream_prefix(&file,&log,&bad,Instant::now()+Duration::from_secs(2)).is_err());
        for marker in ["Starting screen video capture","Worldwide authenticated media route selected","peerConnected=true","controlOpen=true"]{let unsafe_tail=format!("Worldwide viewer disconnected\n{marker}\n").into_bytes();writer.set_len(0).unwrap();writer.write_at(&unsafe_tail,0).unwrap();let mut bad=gate.clone();bad.fields.insert("session_log_size".into(),unsafe_tail.len().to_string());bad.fields.insert("session_log_reset_offset".into(),"0".into());bad.fields.insert("session_log_sha256".into(),sha256(&unsafe_tail));bad.fields.insert("session_log_tail_sha256".into(),sha256(&unsafe_tail));assert!(recovery_stream_prefix(&file,&log,&bad,Instant::now()+Duration::from_secs(2)).is_err(),"valid digests never excuse {marker}");}
        writer.set_len(1).unwrap();assert!(recovery_stream_prefix(&file,&log,&gate,Instant::now()+Duration::from_secs(2)).is_err());writer.write_at(&bytes,0).unwrap();writer.set_len(bytes.len()as u64).unwrap();let retained=path.join("retained-private-log");fs::rename(&log,&retained).unwrap();fs::write(&log,&bytes).unwrap();assert!(recovery_stream_prefix(&file,&log,&gate,Instant::now()+Duration::from_secs(2)).is_err());drop(file);drop(writer);fs::remove_file(log).unwrap();fs::remove_file(retained).unwrap();drop(held);fs::remove_dir(path).unwrap();
    }
    #[test]fn recovery_streaming_checkpoints_reprove_original_prefix_even_when_fresh_digest_is_rebound(){
        let(path,held,_,_)=pre_effect_directory_fixture("recovery-checkpoints");let log=path.join("private-log");let original=b"nonsecret historical header\nWorldwide viewer disconnected\n";let next_reset=b"Worldwide peer returned to idle\n";let before=[original.as_slice(),b"ordinary old session\n",next_reset.as_slice()].concat();let after=[before.as_slice(),b"ordinary fresh idle suffix\n"].concat();let mut writer=OpenOptions::new().write(true).create_new(true).mode(0o600).open(&log).unwrap();writer.write_all(&after).unwrap();let file=OpenOptions::new().read(true).custom_flags(NOFOLLOW).open(&log).unwrap();let(request,wire)=gate_fixture("candidate-present");let base=HostGate::validate(&wire,&request,"--candidate-present").unwrap();let metadata=file.metadata().unwrap();assert_eq!(metadata.uid(),501);
        let gate=|bytes:&[u8],reset:usize|{let mut gate=base.clone();for(key,value)in [("session_log_device",metadata.dev().to_string()),("session_log_inode",metadata.ino().to_string()),("session_log_size",bytes.len().to_string()),("session_log_reset_offset",reset.to_string()),("session_log_sha256",sha256(bytes)),("session_log_tail_sha256",sha256(&bytes[reset..]))]{gate.fields.insert(key.into(),value);}gate};
        let original_gate=gate(original,b"nonsecret historical header\n".len());let before_gate=gate(&before,before.len()-next_reset.len());let after_gate=gate(&after,before.len()-next_reset.len());recovery_stream_prefixes(&file,&log,&[&after_gate,&original_gate,&before_gate],Instant::now()+Duration::from_secs(2)).unwrap();recovery_stream_prefixes(&file,&log,&[&before_gate,&before_gate],Instant::now()+Duration::from_secs(2)).unwrap();
        writer.write_at(b"X",0).unwrap();let mut changed_before=before.clone();changed_before[0]=b'X';let rebound=gate(&changed_before,before.len()-next_reset.len());recovery_stream_prefixes(&file,&log,&[&rebound],Instant::now()+Duration::from_secs(2)).unwrap();assert!(recovery_stream_prefixes(&file,&log,&[&original_gate,&rebound],Instant::now()+Duration::from_secs(2)).is_err(),"fresh whole-prefix must not hide historical-prefix mutation");assert!(recovery_stream_prefixes(&file,&log,&[],Instant::now()+Duration::from_secs(2)).is_err());assert!(recovery_stream_prefixes(&file,&log,&[&original_gate,&before_gate,&after_gate,&after_gate],Instant::now()+Duration::from_secs(2)).is_err());drop(file);drop(writer);fs::remove_file(log).unwrap();drop(held);fs::remove_dir(path).unwrap();
    }
    #[test]fn failure_reconciliation_consumer_rejects_valid_hex_crosslink_and_finalized_containment_mutants(){
        let(path,held,owner,group,request)=reconciliation_crosslink_fixture("reconcile-crosslinks");let inventory=ReconciliationInventory::capture(&path,RECONCILIATION_APPENDS,owner,group).unwrap();let fields=reconciliation_crosslink_fixture_fields(&inventory,&request);validate_reconciliation_crosslinks(&inventory,&request,&fields).unwrap();
        // This positive fixture proves the production post-original seam only;
        // it never satisfies/short-circuits the real immutable original pin gate.
        assert!(inventory.verify_original(&request).is_err());
        for key in ["original_inventory_sha256","final_inventory_sha256","reconciliation_child_fence_sha256","host_before_sha256","host_after_sha256","core_generation_sha256","driver_host_generation_sha256"]{let mut mutant=fields.clone();mutant.insert(key.into(),"0".repeat(64));assert!(validate_reconciliation_crosslinks(&inventory,&request,&mutant).is_err(),"accepted {key}");}
        fs::remove_file(path.join("child-clean-002")).unwrap();assert!(validate_reconciliation_crosslinks(&inventory,&request,&fields).is_err());assert!(ReconciliationInventory::capture(&path,RECONCILIATION_APPENDS,owner,group).is_err());drop(inventory);
        let text=String::from_utf8(child_fence_bytes(&request,2).unwrap()).unwrap().replace("sequence=2","sequence=3");held.write_record("child-clean-002",text.as_bytes(),0o400).unwrap();let mutant=ReconciliationInventory::capture(&path,RECONCILIATION_APPENDS,owner,group).unwrap();let fields=reconciliation_crosslink_fixture_fields(&mutant,&request);assert!(validate_reconciliation_crosslinks(&mutant,&request,&fields).is_err());drop(mutant);drop(held);remove_reconciliation_fixture(&path);
    }
    #[test]fn failure_reconciliation_consumer_structured_host_and_metadata_crosslinks_are_exact(){
        let(path,held,owner,group,request)=reconciliation_crosslink_fixture("reconcile-receipts");
        for name in ["gate-metadata-003.txt","gate-metadata-004.txt","reconciliation-host-before.txt","reconciliation-host-after.txt"]{
            let bytes=fs::read(path.join(name)).unwrap();let text=String::from_utf8(bytes.clone()).unwrap();let metadata=name.starts_with("gate-metadata");
            let mutants=if metadata{vec![text.replace("sequence=3","sequence=4").replace("sequence=4","sequence=2"),text.replace(&format!("request_sha256={FAILED_011_REQUEST}"),&format!("request_sha256={}","0".repeat(64))),text.replace("observed_at_unix_ms=1790000000050","observed_at_unix_ms=1790000000201").replace("observed_at_unix_ms=1790000000150","observed_at_unix_ms=1790000000201"),text.replace("observed_at_unix_ms=1790000000050","observed_at_unix_ms=1789999900000").replace("observed_at_unix_ms=1790000000150","observed_at_unix_ms=1789999900000")]}else{vec![text.replace("session_log_inode=2","session_log_inode=3"),text.replace("session_log_reset_offset=0","session_log_reset_offset=1"),text.replace("input_uid=BlackHole2ch_UID","input_uid=unexpected"),text.replace("manager_generation=0","manager_generation=1"),text.replace("observed_at_unix_ms=1790000000100","observed_at_unix_ms=1789999999999").replace("observed_at_unix_ms=1790000000200","observed_at_unix_ms=1790000000099")]};
            for mutant in mutants{assert_ne!(mutant,text,"fixture mutant must change {name}");replace_reconciliation_fixture_record(&path,&held,name,mutant.as_bytes());let inventory=ReconciliationInventory::capture(&path,RECONCILIATION_APPENDS,owner,group).unwrap();let fields=reconciliation_crosslink_fixture_fields(&inventory,&request);assert!(validate_reconciliation_crosslinks(&inventory,&request,&fields).is_err(),"accepted {name} mutant");drop(inventory);}
            replace_reconciliation_fixture_record(&path,&held,name,&bytes);
        }
        let inventory=ReconciliationInventory::capture(&path,RECONCILIATION_APPENDS,owner,group).unwrap();let mut fields=reconciliation_crosslink_fixture_fields(&inventory,&request);fields.insert("observed_at_unix_ms".into(),"1790000010000".into());assert!(validate_reconciliation_crosslinks(&inventory,&request,&fields).is_err());fields.insert("observed_at_unix_ms".into(),"1790000000199".into());assert!(validate_reconciliation_crosslinks(&inventory,&request,&fields).is_err());drop(inventory);drop(held);remove_reconciliation_fixture(&path);
    }
    #[test]fn failed_guardian_event_owner_requires_exact_single_held_readonly_fd_and_complete_nul_rows(){
        let identity=Identity{device:0x1000010,inode:123,uid:0,gid:0,mode:0o100600,links:1,size:0,mtime:1,mtime_nsec:2,ctime:3,ctime_nsec:4};let path=Path::new("/private/tmp/exclusive-fixture-event");
        let bytes=b"p456\0cworker\0\nf37\0ar\0D0x1000010\0i123\0n/private/tmp/exclusive-fixture-event\0\n".to_vec();let output=|code,stdout,stderr|os::Captured{code,stdout,stderr};failure_event_owner(&output(0,bytes.clone(),vec![]),456,37,&identity,path).unwrap();
        let text=String::from_utf8(bytes.clone()).unwrap();for mutant in [text.replace("p456","p457"),text.replace("f37","f38"),text.replace("ar\0","aw\0"),text.replace("i123","i124"),text.replace("D0x1000010","D0x1000011"),text.replace("exclusive-fixture-event","other-event"),text.replace("f37\0","f37\0f37\0"),text.replace("\0", ""),text.replace("ar\0", ""),text.clone()+"p999\0cunknown\0\nf40\0ar\0D0x1000010\0i123\0n/private/tmp/exclusive-fixture-event\0\n",text.clone()+"f38\0ar\0D0x1000010\0i123\0n/private/tmp/exclusive-fixture-event\0\n"]{assert!(failure_event_owner(&output(0,mutant.into_bytes(),vec![]),456,37,&identity,path).is_err());}
        for(code,stdout,stderr)in [(1,bytes.clone(),vec![]),(1,vec![],vec![]),(0,vec![],vec![]),(0,bytes,vec![b'!'])]{assert!(failure_event_owner(&output(code,stdout,stderr),456,37,&identity,path).is_err());}
    }
    #[test]fn failed_helper_mapping_absence_accepts_only_two_byte_empty_statuses(){
        let output=|code,stdout:Vec<u8>,stderr:Vec<u8>|os::Captured{code,stdout,stderr};
        for code in [0,1]{failed_011_empty_mapping(&output(code,vec![],vec![])).unwrap();}
        for code in [-1,2,64,78,128,143]{assert!(failed_011_empty_mapping(&output(code,vec![],vec![])).is_err());}
        let mappings=[b"p456\0canything\0\nftxt\0D0x1000010\0i123\0n/fixed/held/worker\0\n".as_slice(),b"p456\0canything\0\n",b"p456",b"\0\n",b"\n"];
        for code in [0,1]{
            for bytes in mappings{assert!(failed_011_empty_mapping(&output(code,bytes.to_vec(),vec![])).is_err());}
            for bytes in [b"warning".as_slice(),b"\n",b"\0"]{assert!(failed_011_empty_mapping(&output(code,vec![],bytes.to_vec())).is_err());}
        }
        let reason=failed_011_empty_mapping(&output(1,b"partial".to_vec(),vec![])).unwrap_err();
        assert!(reason.contains("role=failed_011_executable_owner")&&reason.contains("code=1")&&reason.contains("stdout_bytes=7")&&reason.contains(&sha256(b"partial")));
    }
    #[test]fn failed_helper_mapping_requires_post_query_held_identity_even_on_error(){
        for code in [0,1]{
            let empty=||os::Captured{code,stdout:vec![],stderr:vec![]};
            failed_011_mapping_fence(Ok(empty()),Ok(())).unwrap();
            assert!(failed_011_mapping_fence(Ok(empty()),Err("held inode changed".into())).is_err());
        }
        assert_eq!(failed_011_mapping_fence(Err("query unavailable".into()),Ok(())).unwrap_err(),"query unavailable");
        let reason=failed_011_mapping_fence(Err("query unavailable".into()),Err("held inode changed".into())).unwrap_err();
        assert!(reason.starts_with("query unavailable")&&reason.contains(&sha256(b"held inode changed")));
        let positive=os::Captured{code:0,stdout:b"live forbidden inode".to_vec(),stderr:vec![]};
        assert!(failed_011_mapping_fence(Ok(positive),Ok(())).is_err());
    }
    fn gate_metadata_identities()->Vec<Identity>{
        (1..=5).map(|inode|Identity{device:2,inode,uid:0,gid:0,mode:0o40711,links:1,size:128,mtime:10,mtime_nsec:1,ctime:20,ctime_nsec:2}).collect()
    }
    fn gate_metadata_fixture_bytes(sequence:usize,mode:&str)->Vec<u8>{
        gate_metadata_bytes(&super::super::tests::request(),&"e".repeat(64),mode,1_790_000_000_000,sequence,&gate_metadata_identities()).unwrap()
    }
    #[test]fn root_gate_metadata_exact_schema_crosslinks_and_full_role_identities(){
        let request=super::super::tests::request();let pin="e".repeat(64);let bytes=gate_metadata_fixture_bytes(1,"candidate-present");
        validate_gate_metadata(&bytes,&request,&pin,1,Some("candidate-present")).unwrap();
        let text=String::from_utf8(bytes.clone()).unwrap();
        for key in GATE_METADATA_FIELDS{
            let original=text.lines().find(|line|line.starts_with(&format!("{key}="))).unwrap();
            for mutant in [text.replace(&format!("{original}\n"),""),text.clone()+&format!("{original}\n"),text.replace(original,&format!("{key}=wrong"))]{assert!(validate_gate_metadata(mutant.as_bytes(),&request,&pin,1,None).is_err(),"accepted {key}");}
        }
        assert!(validate_gate_metadata((text.clone()+"unknown=true\n").as_bytes(),&request,&pin,1,None).is_err());
        assert!(validate_gate_metadata(&bytes,&request,&"f".repeat(64),1,None).is_err());assert!(validate_gate_metadata(&bytes,&request,&pin,2,None).is_err());assert!(validate_gate_metadata(&bytes,&request,&pin,1,Some("host-absent")).is_err());
        let identity=gate_metadata_identities()[0].clone();let original=gate_identity_text(&identity).unwrap();
        for value in [original.clone()+",0",original.replacen("2,","02,",1),original.replace(",0,0,",",501,0,"),original.replace(&format!(",{},",identity.mode),",16877,"),original.replace(",10,1,20,2",",10,1000000000,20,2"),original.replace(",10,1,20,2",",-10,1,20,2")]{assert!(gate_identity_parse(&value).is_err());}
        assert_eq!(gate_identity_parse(&original).unwrap(),identity);
        let mut identities=gate_metadata_identities();identities[1]=identities[0].clone();assert!(gate_metadata_bytes(&request,&pin,"candidate-present",1,1,&identities).is_err());
        let mut identities=gate_metadata_identities();identities[1].device=3;assert!(gate_metadata_bytes(&request,&pin,"candidate-present",1,1,&identities).is_err());
        assert!(gate_metadata_bytes(&request,&pin,"candidate-present",1,1,&identities[..4]).is_err());
    }
    #[test]fn gate_metadata_initial_observation_is_only_exact_001_candidate_present(){
        let request=super::super::tests::request();let pin="e".repeat(64);let bytes=gate_metadata_fixture_bytes(1,"candidate-present");
        validate_initial_gate_metadata("gate-metadata-001.txt",&bytes,&request,&pin).unwrap();
        for name in ["gate-metadata-000.txt","gate-metadata-002.txt","gate-metadata-065.txt","gate-metadata-01.txt","gate-metadata-001","gate-metadata-001.txt.extra","gate-metadata-alias"]{assert!(validate_initial_gate_metadata(name,&bytes,&request,&pin).is_err());}
        for mode in ["host-absent","host-ready"]{assert!(validate_initial_gate_metadata("gate-metadata-001.txt",&gate_metadata_fixture_bytes(1,mode),&request,&pin).is_err());}
        assert_eq!(gate_metadata_sequence("request.txt").unwrap(),None);assert_eq!(gate_metadata_sequence("gate-metadata-064.txt").unwrap(),Some(64));
        for name in ["core-baseline.txt","normal-restart-intent.txt","pending-001","recovery-refusal.txt"]{assert!(!PRE_EFFECT_RECORDS.contains(&name));}
    }
    #[test]fn private_directory_fd_xattrs_flags_and_full_snapshot_are_required(){
        unsafe extern "C"{fn fsetxattr(fd:i32,name:*const std::ffi::c_char,value:*const std::ffi::c_void,size:usize,position:u32,options:i32)->i32;fn fremovexattr(fd:i32,name:*const std::ffi::c_char,options:i32)->i32;fn fchflags(fd:i32,flags:u32)->i32;}
        let(path,base,owner,group)=pre_effect_directory_fixture("gate-directory");let child=path.join("owned");fs::create_dir(&child).unwrap();fs::set_permissions(&child,fs::Permissions::from_mode(0o711)).unwrap();
        let held=GateDirectory::capture_owned(&child,owner,group).unwrap();held.revalidate().unwrap();assert!(GateDirectory::capture(&child).is_err());
        let attribute=std::ffi::CString::new("com.opensteamer.microphone-v9.fixture").unwrap();
        assert_eq!(unsafe{fsetxattr(held.file.as_raw_fd(),attribute.as_ptr(),b"1".as_ptr().cast(),1,0,0)},0);
        assert!(sealed_fs::clean_gate_metadata(&held.file).is_err());assert!(held.revalidate().is_err());assert_eq!(unsafe{fremovexattr(held.file.as_raw_fd(),attribute.as_ptr(),0)},0);
        assert_eq!(unsafe{fchflags(held.file.as_raw_fd(),1)},0);assert!(sealed_fs::clean_gate_metadata(&held.file).is_err());assert_eq!(unsafe{fchflags(held.file.as_raw_fd(),0)},0);
        drop(held);let held=GateDirectory::capture_owned(&child,owner,group).unwrap();
        fs::write(child.join("extent-change"),b"fixture").unwrap();assert!(held.revalidate().is_err());fs::remove_file(child.join("extent-change")).unwrap();drop(held);
        let held=GateDirectory::capture_owned(&child,owner,group).unwrap();fs::set_permissions(&child,fs::Permissions::from_mode(0o755)).unwrap();assert!(held.revalidate().is_err());fs::set_permissions(&child,fs::Permissions::from_mode(0o711)).unwrap();drop(held);
        let held=GateDirectory::capture_owned(&child,owner,group).unwrap();let retained=path.join("retained");fs::rename(&child,&retained).unwrap();fs::create_dir(&child).unwrap();fs::set_permissions(&child,fs::Permissions::from_mode(0o711)).unwrap();assert!(held.revalidate().is_err());drop(held);
        fs::remove_dir(child).unwrap();fs::remove_dir(retained).unwrap();drop(base);fs::remove_dir(path).unwrap();
    }
    #[test]fn gate_directory_snapshot_rejects_every_split_stat_field_drift(){
        let(path,base,owner,group)=pre_effect_directory_fixture("gate-stat");let child=path.join("owned");fs::create_dir(&child).unwrap();fs::set_permissions(&child,fs::Permissions::from_mode(0o711)).unwrap();
        let mut held=GateDirectory::capture_owned(&child,owner,group).unwrap();let original=held.identity.clone();
        for index in 0..11{let mut changed=original.clone();match index{0=>changed.device+=1,1=>changed.inode+=1,2=>changed.uid+=1,3=>changed.gid+=1,4=>changed.mode+=1,5=>changed.links+=1,6=>changed.size+=1,7=>changed.mtime+=1,8=>changed.mtime_nsec+=1,9=>changed.ctime+=1,_=>changed.ctime_nsec+=1};held.identity=changed;assert!(held.revalidate().is_err(),"accepted stat field {index}");}
        held.identity=original;held.revalidate().unwrap();drop(held);fs::remove_dir(child).unwrap();drop(base);fs::remove_dir(path).unwrap();
    }
    #[test]fn gate_metadata_proof_file_is_immutable_nofollow_readonly_and_exact_bytes(){
        let(path,base,owner,group)=pre_effect_directory_fixture("gate-proof");let bytes=gate_metadata_fixture_bytes(1,"candidate-present");let file=path.join("gate-metadata-001.txt");base.write_record("gate-metadata-001.txt",&bytes,0o400).unwrap();
        assert!(GateMetadataFile::open(&file,&bytes).is_err());let mut proof=GateMetadataFile::open_owned(&file,&bytes,owner,group).unwrap();proof.revalidate().unwrap();
        proof.bytes[0]=b'x';assert!(proof.revalidate().is_err());proof.bytes=bytes.clone();proof.revalidate().unwrap();
        let second=path.join("alias");fs::hard_link(&file,&second).unwrap();assert!(proof.revalidate().is_err());assert!(GateMetadataFile::open_owned(&file,&bytes,owner,group).is_err());fs::remove_file(second).unwrap();drop(proof);
        let mut proof=GateMetadataFile::open_owned(&file,&bytes,owner,group).unwrap();fs::set_permissions(&file,fs::Permissions::from_mode(0o600)).unwrap();let writable=OpenOptions::new().read(true).write(true).open(&file).unwrap();fs::set_permissions(&file,fs::Permissions::from_mode(0o400)).unwrap();proof.identity=Identity::of(&fs::metadata(&file).unwrap());proof.file=writable;assert!(proof.revalidate().is_err());drop(proof);
        let proof=GateMetadataFile::open_owned(&file,&bytes,owner,group).unwrap();let retained=path.join("old");fs::rename(&file,&retained).unwrap();base.write_record("gate-metadata-001.txt",&bytes,0o400).unwrap();assert!(proof.revalidate().is_err());drop(proof);
        fs::remove_file(&file).unwrap();std::os::unix::fs::symlink(&retained,&file).unwrap();assert!(GateMetadataFile::open_owned(&file,&bytes,owner,group).is_err());fs::remove_file(file).unwrap();fs::remove_file(retained).unwrap();drop(base);fs::remove_dir(path).unwrap();
    }
    #[test]fn gate_metadata_inventory_is_contiguous_bounded_and_never_resets_on_resume(){
        let request=super::super::tests::request();let pin="e".repeat(64);let(path,held,owner,group)=pre_effect_directory_fixture("gate-inventory");
        assert_eq!(next_gate_metadata_owned(&path,&request,&pin,owner,group).unwrap(),1);
        held.write_record("gate-metadata-002.txt",&gate_metadata_fixture_bytes(2,"host-absent"),0o400).unwrap();assert!(next_gate_metadata_owned(&path,&request,&pin,owner,group).is_err());fs::remove_file(path.join("gate-metadata-002.txt")).unwrap();
        for sequence in 1..=64{held.write_record(&format!("gate-metadata-{sequence:03}.txt"),&gate_metadata_fixture_bytes(sequence,if sequence==1{"candidate-present"}else{"host-absent"}),0o400).unwrap();if matches!(sequence,1|63){assert_eq!(next_gate_metadata_owned(&path,&request,&pin,owner,group).unwrap(),sequence+1);}}
        assert!(next_gate_metadata_owned(&path,&request,&pin,owner,group).is_err());
        for sequence in 1..=64{fs::remove_file(path.join(format!("gate-metadata-{sequence:03}.txt"))).unwrap();}
        held.write_record("gate-metadata-001.txt",&gate_metadata_fixture_bytes(2,"candidate-present"),0o400).unwrap();assert!(next_gate_metadata_owned(&path,&request,&pin,owner,group).is_err());fs::remove_file(path.join("gate-metadata-001.txt")).unwrap();
        held.write_record("gate-metadata-alias",b"unknown",0o400).unwrap();assert!(next_gate_metadata_owned(&path,&request,&pin,owner,group).is_err());fs::remove_file(path.join("gate-metadata-alias")).unwrap();drop(held);fs::remove_dir(path).unwrap();
    }
    #[test]fn root_metadata_postcheck_is_attempted_for_all_roles_even_after_child_refusal(){
        let(path,held,owner,group)=pre_effect_directory_fixture("gate-post");let mut directories=Vec::new();
        for index in 0..5{let directory=path.join(format!("role-{index}"));fs::create_dir(&directory).unwrap();fs::set_permissions(&directory,fs::Permissions::from_mode(0o711)).unwrap();directories.push(GateDirectory::capture_owned(&directory,owner,group).unwrap());}
        held.write_record("proof",b"fixture",0o400).unwrap();let proof=GateMetadataFile::open_owned(&path.join("proof"),b"fixture",owner,group).unwrap();let metadata=RootGateMetadata{directories,proof};metadata.revalidate().unwrap();
        fs::write(path.join("role-0/changed"),b"fixture").unwrap();fs::set_permissions(path.join("proof"),fs::Permissions::from_mode(0o600)).unwrap();
        let error=gate_metadata_result::<u8>(Err("original child refusal".into()),metadata.revalidate()).unwrap_err();assert!(error.contains("original child refusal"));assert!(error.contains("gate directory full descriptor/path identity changed"));assert!(error.contains("gate metadata proof descriptor/path/access changed"));
        assert_eq!(gate_metadata_result(Ok(7),Ok(())).unwrap(),7);assert!(gate_metadata_result(Ok(7),Err("metadata refused".into())).is_err());
        drop(metadata);fs::remove_file(path.join("role-0/changed")).unwrap();for index in 0..5{fs::remove_dir(path.join(format!("role-{index}"))).unwrap();}fs::remove_file(path.join("proof")).unwrap();drop(held);fs::remove_dir(path).unwrap();
    }
    // Literal retained read-only inspection; no runtime query in these tests.
    const DRIVER_PROCINFO_FIXTURE:&str=r#"program path = /System/Library/Frameworks/CoreAudio.framework/Versions/A/XPCServices/com.apple.audio.Core-Audio-Driver-Service.helper.xpc/Contents/MacOS/com.apple.audio.Core-Audio-Driver-Service.helper
Could not print Mach info for pid 309: 0x5
argument count = 1
argument vector = {
	[0] = Core Audio Driver (OpensteamerVirtualMicrophone.driver)
}
environment vector = {
}
bsd proc info = {
	pid = 309
	ppid = 1
	pgid = 309
	status = stopped
	xstatus = 0x00000000
	flags = 64-bit|session leader
	uid = 202
	svuid = 202
	ruid = 202
	gid = 202
	svgid = 202
	rgid = 202
	comm name = com.apple.audio
	long name = Core Audio Driver (OpensteamerV
	controlling tty devnode = 0xffffffff
	controlling tty pgid = 0
	start date = 2026-09-06 18:47:05
}
unique identifier info = {
	uuid = 9CF4BB51-DDE9-3A76-B5E9-BC99AF522B58
	id = 309
	parent id = 1
	version = 693
	orig parent version = 7
}
audit info
	session id = 100001
	uid = 4294967295
	success mask = 0x0
	failure mask = 0x0
	flags = is_initial
sandboxed = no
container = (no container)

responsible pid = 178
responsible unique pid = 178
responsible path = /usr/sbin/coreaudiod

pressured exit info = {
	dirty state tracked = 1
	dirty = 1
	pressured-exit capable = 1
}

jetsam priority = 40
jetsam memory limit = 15
jetsam state = tracked,idle-exit,dirty

entitlements = {
	"com.apple.private.audio.driver-host" = true;
	"com.apple.security.cs.disable-library-validation" = true;
};

code signing info = valid
	refuse invalid pages
	kill on invalid pages
	restrict
	require enforcement
	allowed mach-o
	platform dyld
	entitlements validated
	platform binary

pid/178/com.apple.audio.Core-Audio-Driver-Service.helper.5E2741F7-BA88-4661-B3F2-9DCC814E6CFA = {
	original = com.apple.audio.Core-Audio-Driver-Service.helper
	active count = 2
	path = /System/Library/Frameworks/CoreAudio.framework/Versions/A/XPCServices/com.apple.audio.Core-Audio-Driver-Service.helper.xpc
	type = XPCService
	state = running
	bundle id = com.apple.audio.Core-Audio-Driver-Service.helper

	program = /System/Library/Frameworks/CoreAudio.framework/Versions/A/XPCServices/com.apple.audio.Core-Audio-Driver-Service.helper.xpc/Contents/MacOS/com.apple.audio.Core-Audio-Driver-Service.helper
	inherited environment = {
		PATH => /usr/bin:/bin:/usr/sbin:/sbin
		HOME => /var/empty
		TMPDIR => /var/folders/zz/zyxvpxvq6csfxvn_n00000s800006_/T/
	}

	default environment = {
		PATH => /usr/bin:/bin:/usr/sbin:/sbin
	}

	environment = {
		LaunchInstanceID => 5E2741F7-BA88-4661-B3F2-9DCC814E6CFA
		XPC_SERVICE_NAME => com.apple.audio.Core-Audio-Driver-Service.helper
		MallocSpaceEfficient => 0
		OSLogRateLimit => 64
		MallocNanoZone => 0
	}

	domain = pid/178 [coreaudiod]
	asid = 100001
	minimum runtime = 10
	base minimum runtime = 10
	exit timeout = 5
	runs = 1
	pid = 309
	immediate reason = ipc (mach)
	forks = 0
	execs = 1
	initialized = 1
	trampolined = 1
	started suspended = 0
	proxy started suspended = 0
	checked allocations = 0 (queried = 1)
	checked allocations reason = inherited
	checked allocations flags = 0x0
	last exit code = (never exited)

	instance-specific endpoints = {
		"com.apple.audio.Core-Audio-Driver-Service.helper" = {
			port = 0x3ea03
			active = 1
			managed = 1
			reset = 0
			hide = 0
			watching = 0
		}
	}

	spawn type = adaptive (6)
	jetsam priority = 40
	jetsam memory limit (active, soft) = 15 MB
	jetsam memory limit (inactive, soft) = 15 MB
	jetsamproperties category = xpcservice
	jetsam thread limit = 32
	cpumon = default
	exponential throttling grace limit = 10

	properties = xpc bundle | supports transactions | supports pressured exit | joins host session | parameterized sandbox | is copy | system service | one-shot | exponential throttling | tle system | no EXC_RESOURCE during audio
}

"#;
    use std::os::unix::fs::PermissionsExt;
    fn identity(device:u64,inode:u64)->Identity{Identity{device,inode,uid:0,gid:0,mode:0o100755,links:1,size:1,mtime:1,mtime_nsec:0,ctime:1,ctime_nsec:0}}
    fn gate_fixture(mode:&str)->(Request,Vec<u8>){
        let request=super::super::tests::request();let mut fields:BTreeMap<String,String>=GATE_FIELDS.iter().map(|key|(key.to_string(),"0".into())).collect();
        for key in ["namespace","nonce","host_pid","host_launchd_runs","host_start_identity_sha256","host_nonce","host_lock_device","host_lock_inode","host_display_identity_sha256","host_executable_sha256","host_framework_sha256","host_info_plist_sha256","host_launch_plist_sha256","input_uid","output_uid","system_output_uid"]{fields.insert(key.into(),request.get(key).into());}
        for(key,value)in [("schema","opensteamer.microphone-v9-host-gate.v1"),("mode",mode),("host_present","true"),("readiness","true"),("display_headless","false"),("session_quiescent","true"),("session_log_device","1"),("session_log_inode","2"),("session_log_size","100"),("session_log_reset_offset","0"),("committed_host_terminal","COMMITTED_CANDIDATE")]{fields.insert(key.into(),value.into());}
        fields.insert("observed_at_unix_ms".into(),std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_millis().to_string());
        fields.insert("session_log_sha256".into(),"e".repeat(64));fields.insert("session_log_tail_sha256".into(),"f".repeat(64));fields.insert("routes_identity_sha256".into(),sha256(format!("{}\0{}\0{}",request.get("input_uid"),request.get("output_uid"),request.get("system_output_uid")).as_bytes()));
        if mode=="host-absent"{for key in ["host_pid","host_launchd_runs","host_lock_device","host_lock_inode"]{fields.insert(key.into(),"0".into());}for key in ["host_nonce","host_start_identity_sha256","host_display_identity_sha256","manager_generation"]{fields.insert(key.into(),"none".into());}fields.insert("host_present".into(),"false".into());fields.insert("readiness".into(),"false".into());fields.insert("display_headless".into(),"true".into());}
        (request,GATE_FIELDS.iter().map(|key|format!("{key}={}\n",fields[*key])).collect::<String>().into_bytes())
    }
    #[test]fn actual_gate_wire_spelling_zero_generation_absent_none_and_routes(){
        for (mode,cli)in [("candidate-present","--candidate-present"),("host-absent","--host-absent")]{
            let(request,bytes)=gate_fixture(mode);assert!(HostGate::validate(&bytes,&request,cli).is_ok());
            let text=String::from_utf8(bytes).unwrap();
            for mutant in [text.replace(&format!("mode={mode}"),&format!("mode={cli}")),text.replace("manager_generation=0","manager_generation=0.0").replace("manager_generation=none","manager_generation=0"),text.replace("manager_generation=0","manager_generation=00").replace("manager_generation=none","manager_generation=1"),text.replace("routes_identity_sha256=",&format!("routes_identity_sha256={}","0".repeat(64))),text.replace("session_log_reset_offset=0","session_log_reset_offset=100")]{assert!(HostGate::validate(mutant.as_bytes(),&request,cli).is_err());}
        }
    }
    #[test]fn generation_local_tail_binds_digest_reset_peer_and_fresh_online(){
        let(request,bytes)=gate_fixture("candidate-present");let mut gate=HostGate::validate(&bytes,&request,"--candidate-present").unwrap();
        let tail=b"Worldwide viewer disconnected\nordinary idle log\n";
        gate.fields.insert("session_log_tail_sha256".into(),sha256(tail));assert!(validate_session_tail(tail,&gate).is_ok());
        // An original online marker may precede a later disconnect reset.
        gate.fields.insert("mode".into(),"host-absent".into());assert!(validate_session_tail(tail,&gate).is_ok());
        gate.fields.insert("mode".into(),"host-ready".into());assert!(validate_session_tail(tail,&gate).is_err());
        let online=format!("Worldwide viewer disconnected\nWorldwide paired-device availability is online pid={} nonce={}\n",gate.fields["host_pid"],gate.fields["host_nonce"]);
        gate.fields.insert("session_log_tail_sha256".into(),sha256(online.as_bytes()));assert!(validate_session_tail(online.as_bytes(),&gate).is_ok());
        let corrupted=online.replace("availability","availab1lity");assert!(validate_session_tail(corrupted.as_bytes(),&gate).is_err());
        for extra in ["peerConnected=true","controlOpen=true","Starting screen video capture","Worldwide authenticated media route selected","Worldwide peer returned to idle"]{
            let mutant=format!("{online}{extra}\n");gate.fields.insert("session_log_tail_sha256".into(),sha256(mutant.as_bytes()));assert!(validate_session_tail(mutant.as_bytes(),&gate).is_err());
        }
        let wrong=online.replace(&format!("pid={}",gate.fields["host_pid"]),"pid=999");gate.fields.insert("session_log_tail_sha256".into(),sha256(wrong.as_bytes()));assert!(validate_session_tail(wrong.as_bytes(),&gate).is_err());
    }
    #[test]fn core_service_identity_duplicates_namespace_and_budget_are_strict(){
        let text="system/com.apple.audio.coreaudiod = {\n\tstate = running\n\tprogram = /usr/sbin/coreaudiod\n\tdomain = system\n\tusername = _coreaudiod\n\tgroup = _coreaudiod\n\truns = 9\n\tpid = 456\n}\n";
        assert_eq!(core_launch(text.as_bytes()).unwrap(),(456,9));
        for mutant in [text.replace("pid = 456","pid = 456\n\tpid = 456"),text.replace("domain = system","domain = gui/501"),text.replace("runs = 9","runs = 09"),text.replace("state = running","state = waiting"),format!("{text}trailing\n"),text.replace('\n',"\r\n")]{assert!(core_launch(mutant.as_bytes()).is_err());}
        let before=CoreGeneration{pid:456,runs:9,start_sha:"a".repeat(64)};let after=CoreGeneration{pid:457,runs:10,start_sha:"a".repeat(64)};
        assert!(before.successor(&after));assert!(!before.successor(&CoreGeneration{runs:11,..after.clone()}));assert!(!before.successor(&CoreGeneration{pid:456,..after}));
    }
    #[test]fn loaded_hal_is_exact_device_inode_not_name_or_new_path_bytes(){
        let prior=identity(16777232,12);let candidate=identity(16777232,13);let apple=identity(16777232,1152921500312151036);
        let make=|inode|format!("p309\0c{DRIVER_HOST_LSOF}\0\nftxt\0D0x1000010\0i1152921500312151036\0n{DRIVER_HOST_EXE}\0\nftxt\0D0x1000010\0i32520560\0n/Library/Preferences/Logging/.plist-cache.EbOgNKJs\0\nftxt\0D0x1000010\0i1152921500312573277\0n/usr/lib/dyld\0\nftxt\0D0x1000010\0i{inode}\0n{DRIVER}/{DRIVER_EXE}\0\n").into_bytes();
        assert_eq!(loaded_mapping(&make(12),309,&apple,&prior,&candidate).unwrap(),LoadedDriver::Prior);assert_eq!(loaded_mapping(&make(13),309,&apple,&prior,&candidate).unwrap(),LoadedDriver::Candidate);
        for mutant in [make(14),make(12).iter().copied().chain(make(13)).collect(),String::from_utf8(make(12)).unwrap().replace("D0x1000010","D0x1000011").into_bytes(),String::from_utf8(make(12)).unwrap().replace("p309","p310").into_bytes(),String::from_utf8(make(12)).unwrap().replace("i12","i12\0i12").into_bytes(),String::from_utf8(make(12)).unwrap().replace("i1152921500312151036","i1152921500312151037").into_bytes()]{assert!(loaded_mapping(&mutant,309,&apple,&prior,&candidate).is_err());}
        let daemon=format!("p178\0ccoreaudiod\0\nftxt\0D0x1000010\0i12\0n{DRIVER}/{DRIVER_EXE}\0\n");assert!(loaded_mapping(daemon.as_bytes(),178,&apple,&prior,&candidate).is_err());
        let no_hal=format!("p309\0c{DRIVER_HOST_LSOF}\0\nftxt\0D0x1000010\0i1152921500312151036\0n{DRIVER_HOST_EXE}\0\n");assert!(loaded_mapping(no_hal.as_bytes(),309,&apple,&prior,&candidate).is_err());
    }
    #[test]fn driver_host_selector_process_and_actual_procinfo_are_independent_authorities(){
        let core=CoreGeneration{pid:178,runs:1,start_sha:"a".repeat(64)};
        assert_eq!(driver_selector(b"309\n").unwrap(),309);for mutant in [b"".as_slice(),b"309\n310\n",b"0309\n",b"1\n",b"309\r\n"]{assert!(driver_selector(mutant).is_err());}
        let process=b"  309 1 202 202 Sun Sep  6 18:47:05 2026 Core Audio Driver (OpensteamerVirtualMicrophone.driver)\n";
        let(_,start)=driver_process(process,309).unwrap();assert_eq!(start,"2026-09-06 18:47:05");
        for mutant in [String::from_utf8(process.to_vec()).unwrap().replace("202 202","501 501"),String::from_utf8(process.to_vec()).unwrap().replace("309 1","309 178"),String::from_utf8(process.to_vec()).unwrap().replace(".driver)",".driver) --spoof")]{assert!(driver_process(mutant.as_bytes(),309).is_err());}
        let proof=driver_procinfo(DRIVER_PROCINFO_FIXTURE.as_bytes(),&core,309,&start).unwrap();assert_eq!(proof.0,1);assert_eq!(proof.2,693);
        for mutant in [DRIVER_PROCINFO_FIXTURE.replace("responsible pid = 178","responsible pid = 179"),DRIVER_PROCINFO_FIXTURE.replace("responsible path = /usr/sbin/coreaudiod","responsible path = /tmp/coreaudiod"),DRIVER_PROCINFO_FIXTURE.replace("domain = pid/178 [coreaudiod]","domain = pid/179 [coreaudiod]"),DRIVER_PROCINFO_FIXTURE.replace("pid/178/com.apple.audio","pid/179/com.apple.audio"),DRIVER_PROCINFO_FIXTURE.replace(DRIVER_HOST_EXE,"/tmp/driver-helper"),DRIVER_PROCINFO_FIXTURE.replace("uid = 202","uid = 501"),DRIVER_PROCINFO_FIXTURE.replace("start date = 2026-09-06 18:47:05","start date = 2026-09-06 18:47:06"),DRIVER_PROCINFO_FIXTURE.replace("program path = ",&format!("program path = {DRIVER_HOST_EXE}\nprogram path = ")),DRIVER_PROCINFO_FIXTURE.replace("type = XPCService","type = LaunchDaemon"),DRIVER_PROCINFO_FIXTURE.replace("platform binary","not platform binary"),DRIVER_PROCINFO_FIXTURE.replace("joins host session","not joined"),DRIVER_PROCINFO_FIXTURE.replace("LaunchInstanceID => 5E2741F7","LaunchInstanceID => 6E2741F7"),format!("{DRIVER_PROCINFO_FIXTURE}}}\n")]{assert!(driver_procinfo(mutant.as_bytes(),&core,309,&start).is_err());}
        // Counters are not generation authority. Every identity still binds.
        let benign=DRIVER_PROCINFO_FIXTURE.replace("active count = 2","active count = 3").replace("port = 0x3ea03","port = 0x3ea04");assert_eq!(driver_procinfo(benign.as_bytes(),&core,309,&start).unwrap(),proof);
    }
    #[test]fn driver_host_global_mapping_rejects_other_duplicate_and_daemon_owners(){
        let make=|pid,command:&str,inode|format!("p{pid}\0c{command}\0\nftxt\0D0x1000010\0i{inode}\0n{DRIVER}/{DRIVER_EXE}\0\n");
        let exact=make(309,DRIVER_HOST_LSOF,29974734);unique_hal_owner(exact.as_bytes(),309,16777232,29974734).unwrap();
        for mutant in [make(310,DRIVER_HOST_LSOF,29974734),make(178,"coreaudiod",29974734),make(309,DRIVER_HOST_LSOF,29974735),format!("{exact}{}",make(310,DRIVER_HOST_LSOF,29974734)),format!("{exact}{}",make(310,DRIVER_HOST_LSOF,29974735))]{assert!(unique_hal_owner(mutant.as_bytes(),309,16777232,29974734).is_err());}
    }
    // Exact saved009 single-prior stdout; the dual search returned these same
    // bytes with code1 because its second, sealed candidate was unopened.
    const SINGLE_PRIOR_OWNER_FIXTURE:&[u8]=b"p309\0cCore Audio Driver (OpensteamerV\0\nftxt\0D0x1000010\0i29974734\0n/Library/Audio/Plug-Ins/HAL/OpensteamerVirtualMicrophone.driver/Contents/MacOS/OpensteamerVirtualMicrophone\0\n";
    fn owner_output(code:i32,stdout:&[u8],stderr:&[u8])->os::Captured{os::Captured{code,stdout:stdout.to_vec(),stderr:stderr.to_vec()}}
    fn owner_paths()->(PathBuf,PathBuf){(PathBuf::from(format!("{DRIVER}/{DRIVER_EXE}")),PathBuf::from(format!("{ROOT_TRANSACTIONS}/driver-microphone-v9-fixture/candidate.driver/{DRIVER_EXE}")))}
    fn owner_mapping(pid:u32,inode:u64,path:&Path)->Vec<u8>{format!("p{pid}\0c{DRIVER_HOST_LSOF}\0\nftxt\0D0x1000010\0i{inode}\0n{}\0\n",path.to_str().unwrap()).into_bytes()}
    #[test]fn single_image_expected_positive_and_empty_negative_preserve_global_owner(){
        assert_eq!(sha256(SINGLE_PRIOR_OWNER_FIXTURE),"82a9f7432868d986bfc58a757bbf8f36643d5d91877e1b59960edf2f6af52835");
        let(prior_path,candidate_path)=owner_paths();let prior=identity(16777232,29974734);let candidate=identity(16777232,29974735);
        let prior_positive=owner_output(0,SINGLE_PRIOR_OWNER_FIXTURE,b"");let negative=owner_output(1,b"",b"");let filtered_empty=owner_output(0,b"",b"");let candidate_positive=owner_output(0,&owner_mapping(309,candidate.inode,&candidate_path),b"");
        for empty in [&negative,&filtered_empty]{
            assert_eq!(selected_owner_output("driver_owners_prior",empty,&prior_path,&prior).unwrap(),SelectedOwnerInventory::Empty);
            global_hal_owner(&prior_positive,empty,&prior_path,&prior,&candidate_path,&candidate,309,LoadedDriver::Prior).unwrap();
            global_hal_owner(empty,&candidate_positive,&prior_path,&prior,&candidate_path,&candidate,309,LoadedDriver::Candidate).unwrap();
            for other_empty in [&negative,&filtered_empty]{assert!(global_hal_owner(empty,other_empty,&prior_path,&prior,&candidate_path,&candidate,309,LoadedDriver::Prior).is_err());assert!(global_hal_owner(empty,other_empty,&prior_path,&prior,&candidate_path,&candidate,309,LoadedDriver::Candidate).is_err());}
        }
        assert_eq!(selected_owner_output("driver_owners_prior",&prior_positive,&prior_path,&prior).unwrap(),SelectedOwnerInventory::Positive);
        // The actual dual-file partial1 is NEVER a valid single-image negative.
        assert!(selected_owner_output("driver_owners_prior",&owner_output(1,SINGLE_PRIOR_OWNER_FIXTURE,b""),&prior_path,&prior).is_err());
        for(first,second,loaded)in [(&prior_positive,&candidate_positive,LoadedDriver::Prior),(&negative,&negative,LoadedDriver::Prior),(&prior_positive,&negative,LoadedDriver::Candidate),(&prior_positive,&negative,LoadedDriver::Unknown)]{
            assert!(global_hal_owner(first,second,&prior_path,&prior,&candidate_path,&candidate,309,loaded).is_err());
        }
        assert!(global_hal_owner(&prior_positive,&negative,&prior_path,&prior,&candidate_path,&candidate,310,LoadedDriver::Prior).is_err());
        let duplicate=owner_output(0,&[SINGLE_PRIOR_OWNER_FIXTURE,owner_mapping(310,prior.inode,&prior_path).as_slice()].concat(),b"");
        assert!(global_hal_owner(&duplicate,&negative,&prior_path,&prior,&candidate_path,&candidate,309,LoadedDriver::Prior).is_err());
    }
    #[test]fn single_image_exit_stderr_and_arbitrary_failures_are_not_absence(){
        let(path,_)=owner_paths();let prior=identity(16777232,29974734);
        for(code,stdout,stderr)in [(1,SINGLE_PRIOR_OWNER_FIXTURE,b"".as_slice()),(0,SINGLE_PRIOR_OWNER_FIXTURE,b"warning"),(0,b"",b"permission denied"),(1,b"",b"permission denied"),(2,b"",b""),(75,b"",b""),(78,b"",b""),(-1,b"",b"")]{
            assert!(selected_owner_output("driver_owners_prior",&owner_output(code,stdout,stderr),&path,&prior).is_err(),"accepted status {code}");
        }
        for bytes in [b" ".as_slice(),b"\n",b"\0",b"\0\n",b"p309\0",b"p309\0\n",b"ftxt\0D0x1000010\0i29974734\0",b"partial"]{
            for code in [0,1]{assert!(selected_owner_output("driver_owners_prior",&owner_output(code,bytes,b""),&path,&prior).is_err(),"accepted nonempty malformed output with status {code}");}
        }
        // Other trusted inspectors still require strict exit0, even empty1.
        assert!(clean_captured("driver_procinfo_before",owner_output(1,b"",b"")).is_err());
    }
    #[test]fn single_image_nul_inventory_rejects_unaccounted_or_partial_records(){
        let(path,_)=owner_paths();let prior=identity(16777232,29974734);let text=String::from_utf8(SINGLE_PRIOR_OWNER_FIXTURE.to_vec()).unwrap();
        selected_hal_owners(SINGLE_PRIOR_OWNER_FIXTURE,&path,&prior).unwrap();
        let file=text.split_once('\n').unwrap().1;
        let mutants=vec![
            text.replace("p309\0", "p0309\0"),text.replace("p309\0", "p1\0"),text.replace("p309\0", "p2147483648\0"),
            text.replace(&format!("c{DRIVER_HOST_LSOF}\0"),"ccoreaudiod\0"),text.replace("p309\0", "p309\0p309\0"),
            text.replace("ftxt\0", "ftxt\0D0x1000010\0"),text.replace("ftxt\0", "ftxt\0xunknown\0"),text.replace("ftxt\0", "fmem\0"),
            text.replace("D0x1000010\0", ""),text.replace("D0x1000010\0", "D16777232\0"),text.replace("D0x1000010\0", "D0x1000011\0"),
            text.replace("i29974734\0", "i029974734\0"),text.replace("i29974734\0", "i29974735\0"),text.replace("\0\n", "\n"),
            text.trim_end_matches('\n').to_string(),text.replace("\0\n", "\0\r\n"),text.replace("\0\n", "\0\n\n"),
            file.to_string(),format!("p309\0c{DRIVER_HOST_LSOF}\0\n"),format!("{text}p310\0c{DRIVER_HOST_LSOF}\0\n"),
            format!("{text}{file}"),format!("{text}{text}"),text.replace("ftxt\0D0x1000010", "D0x1000010\0ftxt"),
            format!("{text}ftxt\0D0x1000010\0i29974734\0n/usr/lib/dyld\0\n"),
        ];
        for(mutant_index,mutant)in mutants.iter().enumerate(){assert!(selected_hal_owners(mutant.as_bytes(),&path,&prior).is_err(),"accepted framing mutant {mutant_index}");}
    }
    #[test]fn single_image_names_only_allow_selected_role_or_installed_opening_alias(){
        let installed=PathBuf::from(format!("{DRIVER}/{DRIVER_EXE}"));let retained=PathBuf::from(format!("{ROOT_TRANSACTIONS}/driver-microphone-v9-fixture/prior/{DRIVER_NAME}/{DRIVER_EXE}"));let prior=identity(16777232,29974734);
        // A retained inode may be reported under its literal current role OR
        // the fixed installed opening name; this is not a Darwin rename claim.
        selected_hal_owners(&owner_mapping(309,prior.inode,&retained),&retained,&prior).unwrap();
        selected_hal_owners(SINGLE_PRIOR_OWNER_FIXTURE,&retained,&prior).unwrap();
        for name in [format!("{ROOT_TRANSACTIONS}/driver-microphone-v9-other/prior/{DRIVER_NAME}/{DRIVER_EXE}"),format!("{ROOT_TRANSACTIONS}/driver-microphone-v9-fixture/candidate.driver/{DRIVER_EXE}"),format!("{} (deleted)",installed.display()),format!("{} (deleted)",retained.display()),DRIVER_HOST_EXE.into(),"/tmp/OpensteamerVirtualMicrophone".into()]{
            assert!(selected_hal_owners(&owner_mapping(309,prior.inode,Path::new(&name)),&retained,&prior).is_err());
        }
        assert!(selected_hal_owners(&owner_mapping(309,prior.inode+1,&installed),&retained,&prior).is_err());
    }
    #[test]fn trusted_inspector_diagnostics_record_only_fixed_roles_extent_exit_and_hashes(){
        let stdout=b"private /secret/path stdout";let stderr=b"private credential stderr";let captured=owner_output(1,stdout,stderr);let reason=inspector_summary("driver_owners_prior",&captured);
        for value in ["role=driver_owners_prior".to_string(),"code=1".into(),format!("stdout_bytes={}",stdout.len()),format!("stdout_sha256={}",sha256(stdout)),format!("stderr_bytes={}",stderr.len()),format!("stderr_sha256={}",sha256(stderr))]{assert!(reason.contains(&value));}
        assert!(!reason.contains("private"));assert!(!reason.contains("/secret/path"));assert!(!reason.contains("credential"));
        let unknown=inspector_summary("untrusted/path\nsecret",&captured);assert!(unknown.contains("role=unknown_inspector"));assert!(!unknown.contains("untrusted"));
        assert!(selected_owner_output("driver_owners_prior",&captured,Path::new("/secret/path"),&identity(2,3)).unwrap_err().len()<512);
    }
    #[test]fn selected_image_held_fd_and_path_reject_full_stat_drift_and_replacement(){
        let(path,base,_,_)=pre_effect_directory_fixture("selected-image");let file=path.join("image");fs::write(&file,b"fixture").unwrap();fs::set_permissions(&file,fs::Permissions::from_mode(0o755)).unwrap();
        let descriptor=OpenOptions::new().read(true).custom_flags(NOFOLLOW).open(&file).unwrap();let original=Identity::of(&descriptor.metadata().unwrap());
        assert!(HeldDriverImage::capture(&file,&original).is_err()); // UID501 is not production root authority.
        let mut held=HeldDriverImage{file:descriptor,path:file.clone(),identity:original.clone()};held.revalidate().unwrap();
        for index in 0..11{let mut changed=original.clone();match index{0=>changed.device+=1,1=>changed.inode+=1,2=>changed.uid+=1,3=>changed.gid+=1,4=>changed.mode+=1,5=>changed.links+=1,6=>changed.size+=1,7=>changed.mtime+=1,8=>changed.mtime_nsec+=1,9=>changed.ctime+=1,_=>changed.ctime_nsec+=1};held.identity=changed;assert!(held.revalidate().is_err(),"accepted image stat field {index}");}
        held.identity=original;held.revalidate().unwrap();fs::write(&file,b"fixture-expanded").unwrap();assert!(held.revalidate().is_err());drop(held);
        let descriptor=File::open(&file).unwrap();let identity=Identity::of(&descriptor.metadata().unwrap());let held=HeldDriverImage{file:descriptor,path:file.clone(),identity};
        let retained=path.join("retained");fs::rename(&file,&retained).unwrap();fs::write(&file,b"fixture-expanded").unwrap();fs::set_permissions(&file,fs::Permissions::from_mode(0o755)).unwrap();assert!(held.revalidate().is_err());drop(held);
        fs::remove_file(&file).unwrap();std::os::unix::fs::symlink(&retained,&file).unwrap();let identity=Identity::of(&fs::metadata(&retained).unwrap());assert!(HeldDriverImage::capture(&file,&identity).is_err());
        fs::remove_file(file).unwrap();fs::remove_file(retained).unwrap();drop(base);fs::remove_dir(path).unwrap();
    }
    fn driver_generation()->DriverHostGeneration{DriverHostGeneration{core:CoreGeneration{pid:178,runs:1,start_sha:"a".repeat(64)},pid:309,runs:1,start_sha:"b".repeat(64),process_uuid:"9CF4BB51-DDE9-3A76-B5E9-BC99AF522B58".into(),process_version:693,launch_uuid:"5E2741F7-BA88-4661-B3F2-9DCC814E6CFA".into(),apple_device:16777232,apple_inode:1152921500312151036,apple_stat_sha:"c".repeat(64),apple_sha:"d".repeat(64),hal_device:16777232,hal_inode:29974734}}
    #[test]fn driver_host_successor_requires_fresh_one_shot_under_exact_daemon_successor(){
        let before=driver_generation();let next=DriverHostGeneration{core:CoreGeneration{pid:179,runs:2,start_sha:"e".repeat(64)},pid:310,process_version:694,launch_uuid:"6E2741F7-BA88-4661-B3F2-9DCC814E6CFA".into(),start_sha:"f".repeat(64),hal_inode:29974735,..before.clone()};assert!(before.successor(&next));
        for mutant in [DriverHostGeneration{pid:309,..next.clone()},DriverHostGeneration{process_version:693,..next.clone()},DriverHostGeneration{launch_uuid:before.launch_uuid.clone(),..next.clone()},DriverHostGeneration{core:before.core.clone(),..next.clone()},DriverHostGeneration{core:CoreGeneration{runs:3,..next.core.clone()},..next.clone()},DriverHostGeneration{runs:2,..next.clone()},DriverHostGeneration{apple_inode:1152921500312151037,..next.clone()},DriverHostGeneration{apple_sha:"0".repeat(64),..next.clone()},DriverHostGeneration{apple_stat_sha:"0".repeat(64),..next.clone()},DriverHostGeneration{process_uuid:"0CF4BB51-DDE9-3A76-B5E9-BC99AF522B58".into(),..next.clone()}]{assert!(!before.successor(&mutant));}
    }
    #[test]fn durable_daemon_budget_cannot_hide_failed_helper_or_repeat_unresolved_intent(){
        let base=driver_generation().core;let normal=CoreGeneration{pid:179,runs:2,start_sha:"e".repeat(64)};let rollback=CoreGeneration{pid:180,runs:3,start_sha:"f".repeat(64)};
        assert_eq!(completed_restart_budget(None,None,None,None,None).unwrap(),(0,0));assert_eq!(completed_restart_budget(Some(&base),None,None,None,None).unwrap(),(0,0));
        // This count is true even when helper acceptance failed: the pure
        // budget function has no loaded()/OS inspector dependency at all.
        assert_eq!(completed_restart_budget(Some(&base),Some(&base),Some(&normal),None,None).unwrap(),(1,0));assert_eq!(completed_restart_budget(Some(&base),Some(&base),Some(&normal),Some(&normal),Some(&rollback)).unwrap(),(1,1));
        for args in [(None,Some(&base),Some(&normal),None,None),(Some(&base),Some(&base),None,None,None),(Some(&base),None,Some(&normal),None,None),(Some(&base),Some(&normal),Some(&normal),None,None),(Some(&base),Some(&base),Some(&rollback),None,None),(Some(&base),Some(&base),Some(&normal),Some(&normal),None),(Some(&base),Some(&base),Some(&normal),Some(&base),Some(&rollback)),(Some(&base),Some(&base),Some(&normal),None,Some(&rollback))]{assert!(completed_restart_budget(args.0,args.1,args.2,args.3,args.4).is_err());}
    }
    #[test]fn pre_effect_refusal_needs_empty_durable_journal_exact_reason_and_final_containment(){
        let request=super::super::tests::request();let empty=Journal::new(&request);let pending=empty.appended(State::Prepared).unwrap();
        refusal_journal_empty(&empty,&empty,false,1).unwrap();refusal_containment_finalized(true,false,1).unwrap();
        for(memory,durable,resumed,sequence)in [(&empty,&pending,false,1),(&pending,&empty,false,1),(&empty,&empty,true,1),(&empty,&empty,false,2)]{assert!(refusal_journal_empty(memory,durable,resumed,sequence).is_err());}
        for(clean,resumed,sequence)in [(false,false,1),(true,true,1),(true,false,2)]{assert!(refusal_containment_finalized(clean,resumed,sequence).is_err());}
        assert!(PRE_EFFECT_RECORDS.contains(&"host-baseline.txt"));for name in ["core-baseline.txt","driver-host-baseline.txt","normal-restart-intent.txt","normal-restart-complete.txt","normal-driver-host-complete.txt","normal-reload-unproved.txt","rollback-restart-intent.txt","recovery-refusal.txt","unknown-effect"]{assert!(!PRE_EFFECT_RECORDS.contains(&name));}
        let bytes=admission_refusal_bytes(&request,"original cause = bounded\nprivate UTF-8 ✓").unwrap();validate_admission_refusal(&bytes,&request).unwrap();
        let text=String::from_utf8(bytes).unwrap();for mutant in [text.replace("namespace=","namespace=0"),text.replace("reason_sha256=","reason_sha256=0"),text.replace("reason_utf8_hex=","reason_utf8_hex=00"),text.clone()+"reason_sha256=duplicate\n"]{assert!(validate_admission_refusal(mutant.as_bytes(),&request).is_err());}assert!(admission_refusal_bytes(&request,&"x".repeat(2049)).is_err());
    }
    fn pre_effect_directory_fixture(label:&str)->(PathBuf,sealed_fs::HeldDirectory,u32,u32){
        assert!(!os::OwnedChild::root_identity(),"pre-effect fixtures must never run as root");
        let stamp=std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos();
        let path=std::env::temp_dir().join(format!("beluga-v9-pre-effect-{label}-{}-{stamp}",std::process::id()));
        fs::create_dir(&path).unwrap();fs::set_permissions(&path,fs::Permissions::from_mode(0o700)).unwrap();
        let path=fs::canonicalize(path).unwrap();let metadata=fs::metadata(&path).unwrap();let(owner,group)=(metadata.uid(),metadata.gid());
        let held=sealed_fs::HeldDirectory::capture(&path,owner,group,0o700).unwrap();(path,held,owner,group)
    }
    #[test]fn primary_failure_record_is_request_stage_bound_and_immutable_across_secondary_errors(){
        let request=super::super::tests::request();let(path,held,owner,group)=pre_effect_directory_fixture("primary-failure");
        let first=failure_bytes(&request,"opensteamer.microphone-v9-forward-failure.v1","seal_guardian","first ready failure\nactual bounded detail").unwrap();
        retain_first_failure(&first,None,|bytes|held.write_record("forward-failure.txt",bytes,0o400)).unwrap();let file=path.join("forward-failure.txt");let original=read_owned(&file,owner,group,0o400,8192).unwrap();let identity=Identity::of(&fs::symlink_metadata(&file).unwrap());
        retain_first_failure(&first,Some(&original),|_|panic!("same first record rewritten")).unwrap();
        let second=failure_bytes(&request,"opensteamer.microphone-v9-forward-failure.v1","stop_host","secondary exclusive event creation failed").unwrap();assert!(retain_first_failure(&second,Some(&original),|_|panic!("secondary replaced original")).is_err());
        assert_eq!(read_owned(&file,owner,group,0o400,8192).unwrap(),first);assert_eq!(Identity::of(&fs::symlink_metadata(&file).unwrap()),identity);
        let text=String::from_utf8(first).unwrap();assert!(text.contains(&format!("namespace={}\nnonce={}\nrequest_sha256={}\nstage=seal_guardian\n",request.get("namespace"),request.get("nonce"),request.sha256)));assert!(!text.contains("actual bounded detail"));
        for(stage,reason)in [("bad\nstage","reason"),("ready","")]{assert!(failure_bytes(&request,"opensteamer.microphone-v9-forward-failure.v1",stage,reason).is_err());}
        assert!(failure_bytes(&request,"wrong","ready","reason").is_err());assert!(failure_bytes(&request,"opensteamer.microphone-v9-forward-failure.v1","ready",&"x".repeat(2049)).is_err());
        fs::remove_file(file).unwrap();drop(held);fs::remove_dir(path).unwrap();
    }
    #[test]fn fixed_failure_storage_survives_isolated_poison_without_admitting_ordinary_records(){
        let request=super::super::tests::request();
        for poison in ["OWNED_CLEANUP_UNRESOLVED","SUPERVISOR_ABORT"]{
            let(path,held,owner,group)=pre_effect_directory_fixture("failure-poison");let lock=sealed_fs::RootLock::acquire_fixture(&held).unwrap();
            let poisoned=std::cell::Cell::new(true);let checks=std::cell::Cell::new(0);
            let guard=||{checks.set(checks.get()+1);held.revalidate()?;lock.revalidate()};
            let supervision=||if poisoned.get(){Err(poison.to_string())}else{Ok(())};
            for name in ["admission-refusal.txt","guardian-1.proof","normal-restart-intent.txt","child-clean-001"]{
                assert_eq!(supervised_record(supervision,||held.write_record(name,b"never authorized",0o400)).unwrap_err(),poison);assert!(!path.join(name).exists());
            }
            let first=failure_bytes(&request,"opensteamer.microphone-v9-forward-failure.v1","seal_guardian","first ready cause").unwrap();
            retain_failure_storage(FailureRecord::Forward,&first,&path,&held,owner,group,guard).unwrap();assert_eq!(checks.get(),2);
            let file=path.join("forward-failure.txt");let original=Identity::of(&fs::symlink_metadata(&file).unwrap());
            retain_failure_storage(FailureRecord::Forward,&first,&path,&held,owner,group,guard).unwrap();assert_eq!(checks.get(),4);assert_eq!(Identity::of(&fs::symlink_metadata(&file).unwrap()),original);
            let second=failure_bytes(&request,"opensteamer.microphone-v9-forward-failure.v1","stop_host","secondary failure").unwrap();
            assert!(retain_failure_storage(FailureRecord::Forward,&second,&path,&held,owner,group,guard).is_err());assert_eq!(checks.get(),6);assert_eq!(read_owned(&file,owner,group,0o400,16384).unwrap(),first);
            let guardian=failure_bytes(&request,"opensteamer.microphone-v9-guardian-start-failure.v1","ready","first guardian cause").unwrap();
            retain_failure_storage(FailureRecord::GuardianStart(1),&guardian,&path,&held,owner,group,guard).unwrap();assert_eq!(checks.get(),8);assert!(guardian_slot_absent(&path,1).is_err());
            for index in [0,6]{assert!(retain_failure_storage(FailureRecord::GuardianStart(index),&guardian,&path,&held,owner,group,guard).is_err());}assert_eq!(checks.get(),8);
            assert!(poisoned.get());assert_eq!(supervised_record(supervision,||panic!("poisoned recovery/effect storage ran")).unwrap_err(),poison);
            for name in ["forward-failure.txt","guardian-1-start-failure.txt"]{assert!(!PRE_EFFECT_RECORDS.contains(&name));fs::remove_file(path.join(name)).unwrap();}
            drop(lock);fs::remove_file(path.join(".controller.lock")).unwrap();drop(held);fs::remove_dir(path).unwrap();
        }
    }
    #[test]fn failure_storage_guards_unsafe_nodes_and_retention_errors_preserve_original_reason(){
        let request=super::super::tests::request();let(path,held,owner,group)=pre_effect_directory_fixture("failure-guards");
        let bytes=failure_bytes(&request,"opensteamer.microphone-v9-forward-failure.v1","seal_guardian","original primary cause").unwrap();let file=path.join("forward-failure.txt");
        assert!(retain_failure_storage(FailureRecord::Forward,&bytes,&path,&held,owner,group,||Err("held guard failed".into())).is_err());assert!(!file.exists());
        for malformed in [b"".as_slice(),&vec![b'x';16385]]{assert!(retain_failure_storage(FailureRecord::Forward,malformed,&path,&held,owner,group,||panic!("extent refusal must precede storage")).is_err());}
        std::os::unix::fs::symlink(path.join("missing"),&file).unwrap();
        let error=retain_failure_storage(FailureRecord::Forward,&bytes,&path,&held,owner,group,||held.revalidate()).unwrap_err();
        assert!(fs::symlink_metadata(&file).unwrap().file_type().is_symlink());assert_eq!(primary_retention_result("original primary cause",Err(error.clone())).unwrap_err(),format!("original primary cause; primary_retention_error_sha256={}",sha256(error.as_bytes())));fs::remove_file(&file).unwrap();
        held.write_record("forward-failure.txt",b"unsafe mode",0o600).unwrap();let unsafe_identity=Identity::of(&fs::symlink_metadata(&file).unwrap());
        assert!(retain_failure_storage(FailureRecord::Forward,&bytes,&path,&held,owner,group,||held.revalidate()).is_err());assert_eq!(Identity::of(&fs::symlink_metadata(&file).unwrap()),unsafe_identity);fs::remove_file(&file).unwrap();
        let checks=std::cell::Cell::new(0);
        assert!(retain_failure_storage(FailureRecord::Forward,&bytes,&path,&held,owner,group,||{checks.set(checks.get()+1);held.revalidate()?;if checks.get()==2{Err("post-storage guard failed".into())}else{Ok(())}}).is_err());
        assert_eq!(checks.get(),2);assert_eq!(read_owned(&file,owner,group,0o400,16384).unwrap(),bytes);
        let original="x".repeat(2049);let retained=failure_bytes(&request,"opensteamer.microphone-v9-guardian-start-failure.v1","ready",&original).map(|_|());
        assert!(primary_retention_result(&original,retained).unwrap_err().starts_with(&format!("{original}; primary_retention_error_sha256=")));
        fs::remove_file(file).unwrap();drop(held);fs::remove_dir(path).unwrap();
    }
    #[test]fn unproved_guardian_slot_is_never_retried_removed_or_permission_repaired(){
        let(path,held,owner,group)=pre_effect_directory_fixture("guardian-slot");guardian_slot_absent(&path,1).unwrap();
        for name in ["guardian-1.events","guardian-1.proof","guardian-1-start-failure.txt"]{
            held.write_record(name,b"retained",if name.ends_with("events"){0o600}else{0o400}).unwrap();let before=Identity::of(&fs::symlink_metadata(path.join(name)).unwrap());
            assert!(guardian_slot_absent(&path,1).is_err());assert_eq!(Identity::of(&fs::symlink_metadata(path.join(name)).unwrap()),before);assert_eq!(read_owned(&path.join(name),owner,group,if name.ends_with("events"){0o600}else{0o400},8192).unwrap(),b"retained");fs::remove_file(path.join(name)).unwrap();
        }
        std::os::unix::fs::symlink(path.join("missing"),path.join("guardian-1.events")).unwrap();assert!(guardian_slot_absent(&path,1).is_err());fs::remove_file(path.join("guardian-1.events")).unwrap();
        for index in [0,6]{assert!(guardian_slot_absent(&path,index).is_err());}guardian_slot_absent(&path,1).unwrap();drop(held);fs::remove_dir(path).unwrap();
    }
    #[test]fn actual_empty_held_journal_allows_only_pre_effect_proof_not_resume(){
        let request=super::super::tests::request();let(path,held,_,_)=pre_effect_directory_fixture("empty");
        let before=Identity::of(&fs::symlink_metadata(&path).unwrap());
        let empty=empty_pre_effect_journal(&held,&path,&request).unwrap();assert!(empty.last().is_none());
        refusal_journal_empty(&Journal::new(&request),&empty,false,1).unwrap();
        assert_eq!(held.reconcile_journal(&request).unwrap_err(),"resume requires an actual durable journal");
        assert!(fs::read_dir(&path).unwrap().next().is_none());assert_eq!(Identity::of(&fs::symlink_metadata(&path).unwrap()),before);
        drop(held);fs::remove_dir(path).unwrap();
    }
    #[test]fn pre_effect_held_journal_never_adopts_pending_published_or_unknown_entries(){
        let request=super::super::tests::request();let prepared=Journal::new(&request).appended(State::Prepared).unwrap().bytes();
        for kind in ["pending","published","torn","unknown","directory","symlink","hardlink"]{
            let(path,held,owner,group)=pre_effect_directory_fixture(kind);
            let name=if kind=="published"{"journal-001"}else if kind=="unknown"{"unknown-effect"}else{"pending-001"};let target=path.join(name);
            if kind=="directory"{fs::create_dir(&target).unwrap();}
            else if kind=="symlink"{std::os::unix::fs::symlink(path.join("missing-target"),&target).unwrap();}
            else{held.write_record(name,if kind=="torn"{b"torn"}else{&prepared},0o400).unwrap();}
            if kind=="hardlink"{fs::hard_link(&target,path.join("second-link")).unwrap();}
            let before=Identity::of(&fs::symlink_metadata(&target).unwrap());
            let original=if matches!(kind,"pending"|"published"|"torn"|"unknown"){Some(read_owned(&target,owner,group,0o400,MAX_REQUEST).unwrap())}else{None};
            for _ in 0..2{assert!(empty_pre_effect_journal(&held,&path,&request).is_err());}
            assert_eq!(Identity::of(&fs::symlink_metadata(&target).unwrap()),before);
            if let Some(bytes)=original{assert_eq!(read_owned(&target,owner,group,0o400,MAX_REQUEST).unwrap(),bytes);}
            if kind!="published"{assert!(!path.join("journal-001").exists());}
            if kind=="hardlink"{fs::remove_file(path.join("second-link")).unwrap();}
            if kind=="directory"{fs::remove_dir(target).unwrap();}else{fs::remove_file(target).unwrap();}
            drop(held);fs::remove_dir(path).unwrap();
        }
    }
    #[test]fn pre_effect_empty_inventory_refuses_replaced_held_directory(){
        let request=super::super::tests::request();let(path,held,_,_)=pre_effect_directory_fixture("replaced");
        let retained=path.with_extension("retained");assert!(!retained.exists());fs::rename(&path,&retained).unwrap();
        fs::create_dir(&path).unwrap();fs::set_permissions(&path,fs::Permissions::from_mode(0o700)).unwrap();
        assert!(empty_pre_effect_journal(&held,&path,&request).is_err());assert!(fs::read_dir(&path).unwrap().next().is_none());
        drop(held);fs::remove_dir(path).unwrap();fs::remove_dir(retained).unwrap();
    }
    #[test]fn first_admission_diagnostic_survives_real_pending_failure_and_is_immutable(){
        let request=super::super::tests::request();let(state,held,owner,group)=pre_effect_directory_fixture("reason");
        let journal_path=state.join("journal");fs::create_dir(&journal_path).unwrap();fs::set_permissions(&journal_path,fs::Permissions::from_mode(0o700)).unwrap();
        let journal=sealed_fs::HeldDirectory::capture(&journal_path,owner,group,0o700).unwrap();
        let reason=host_gate_failure(78,b"","host-gate: REFUSED original cause ✓\n".as_bytes());
        retain_admission_before_pre_effect(&request,&reason,None,|bytes|held.write_record("admission-refusal.txt",bytes,0o400),
            ||empty_pre_effect_journal(&journal,&journal_path,&request).map(|_|())).unwrap();
        let path=state.join("admission-refusal.txt");let first=read_owned(&path,owner,group,0o400,8192).unwrap();let before=Identity::of(&fs::symlink_metadata(&path).unwrap());
        assert_eq!(first,admission_refusal_bytes(&request,&reason).unwrap());validate_admission_refusal(&first,&request).unwrap();
        retain_admission_before_pre_effect(&request,&reason,Some(&first),|_|panic!("same reason must not rewrite"),
            ||empty_pre_effect_journal(&journal,&journal_path,&request).map(|_|())).unwrap();
        assert_eq!(Identity::of(&fs::symlink_metadata(&path).unwrap()),before);assert_eq!(read_owned(&path,owner,group,0o400,8192).unwrap(),first);
        let checked=std::cell::Cell::new(false);
        assert!(retain_admission_before_pre_effect(&request,"later masked cause",Some(&first),|_|panic!("first reason must never overwrite"),
            ||{checked.set(true);Ok(())}).is_err());assert!(!checked.get());
        fs::remove_file(&path).unwrap();let pending=Journal::new(&request).appended(State::Prepared).unwrap().bytes();journal.write_record("pending-001",&pending,0o400).unwrap();
        assert!(retain_admission_before_pre_effect(&request,&reason,None,|bytes|held.write_record("admission-refusal.txt",bytes,0o400),
            ||empty_pre_effect_journal(&journal,&journal_path,&request).map(|_|())).is_err());
        assert_eq!(read_owned(&path,owner,group,0o400,8192).unwrap(),first);validate_admission_refusal(&first,&request).unwrap();
        assert_eq!(read_owned(&journal_path.join("pending-001"),owner,group,0o400,MAX_REQUEST).unwrap(),pending);assert!(!journal_path.join("journal-001").exists());
        let retained=Identity::of(&fs::symlink_metadata(&path).unwrap());
        assert!(retain_admission_before_pre_effect(&request,&reason,Some(&first),|_|panic!("pending failure must not rewrite"),
            ||empty_pre_effect_journal(&journal,&journal_path,&request).map(|_|())).is_err());
        assert_eq!(Identity::of(&fs::symlink_metadata(&path).unwrap()),retained);
        fs::remove_file(path).unwrap();fs::remove_file(journal_path.join("pending-001")).unwrap();drop(journal);fs::remove_dir(journal_path).unwrap();drop(held);fs::remove_dir(state).unwrap();
    }
    #[test]fn fatal_host_gate_error_retains_exact_code_stderr_without_silent_truncation(){
        let stderr=b"host-gate: REFUSED exact source refusal\n";let reason=host_gate_failure(78,b"",stderr);assert!(reason.contains("code=78"));assert!(reason.contains(&format!("stderr_sha256={}",sha256(stderr))));assert!(reason.contains("stderr_hex=686f73742d67617465"));
        let large=vec![b'x';513];let reason=host_gate_failure(78,b"non-authority",&large);assert!(reason.contains("stderr_bytes=513"));assert!(reason.contains(&format!("stderr_sha256={}",sha256(&large))));assert!(reason.contains("stderr_hex=not-inlined-over-512-bytes"));assert!(reason.len()<2048);
    }
    #[test]fn authority_parser_refuses_control_duplicates_and_unknown_authority(){
        let text=AUTHORITY_FIELDS.iter().map(|key|format!("{key}=fixture\n")).collect::<String>();
        assert!(strict_flat(text.as_bytes(),AUTHORITY_FIELDS,MAX_REQUEST).is_ok());
        for mutant in [text.clone()+"nonce=repeat\n",text.replace("schema=fixture","command=/bin/sh"),text.replace('\n',"\r\n"),text.replace("nonce=fixture","nonce=fixture=more"),text.trim_end().into()]{assert!(strict_flat(mutant.as_bytes(),AUTHORITY_FIELDS,MAX_REQUEST).is_err());}
    }
    #[test]fn durable_unresolved_child_marker_binds_exact_namespace_group_and_uid(){
        let request=super::super::tests::request();let bytes=cleanup_record(&request,456,501,"owned pipe remained").unwrap();assert!(validate_cleanup_marker(&bytes,&request).is_ok());
        let text=String::from_utf8(bytes).unwrap();for mutant in [text.replace("group=456","group=0456"),text.replace("uid=501","uid=502"),text.replace("nonce=","nonce=0"),text.replace("reason=OWNED_CHILD_CONTAINMENT_UNRESOLVED","reason=NONE"),text.clone()+"group=456\n",text.replace('\n',"\r\n")]{assert!(validate_cleanup_marker(mutant.as_bytes(),&request).is_err());}
        assert!(cleanup_record(&request,1,501,"unproved").is_err());assert!(cleanup_record(&request,456,502,"unproved").is_err());
    }
    #[test]fn pre_effect_durable_child_fence_without_exact_clean_owner_never_resumes(){
        let request=super::super::tests::request();let bytes=child_fence_bytes(&request,1).unwrap();child_fence_validate(&bytes,&request,1).unwrap();
        assert_eq!(validate_child_fence_set(&[],&[]).unwrap(),1);assert_eq!(validate_child_fence_set(&[1,2],&[1,2]).unwrap(),3);
        for(active,clean)in [(vec![1],vec![]),(vec![1,2],vec![1]),(vec![1],vec![1,2]),(vec![2],vec![2]),((1..=64).collect(),(1..=64).collect())]{assert!(validate_child_fence_set(&active,&clean).is_err());}
        let text=String::from_utf8(bytes).unwrap();for mutant in [text.replace("sequence=1","sequence=2"),text.replace("owner_pid=","owner_pid=0"),text.replace("nonce=","nonce=0"),text.clone()+"owner_pid=123\n"]{assert!(child_fence_validate(mutant.as_bytes(),&request,1).is_err());}
    }
    #[test]fn unresolved_old_namespace_blocks_fresh_namespace_before_dispatch(){
        assert!(!os::OwnedChild::root_identity(),"fixture must never stage as root");
        let fixture=std::env::temp_dir().join(format!("beluga-v9-cross-namespace-{}",std::process::id()));
        fs::create_dir(&fixture).unwrap();fs::set_permissions(&fixture,fs::Permissions::from_mode(0o700)).unwrap();let root=fs::canonicalize(&fixture).unwrap();
        let metadata=fs::metadata(&root).unwrap();let(owner,group)=(metadata.uid(),metadata.gid());
        let make_request=|namespace:&str|{let mut fields=super::super::tests::request().fields;fields.insert("namespace".into(),namespace.into());let bytes=FIELDS.iter().map(|key|format!("{key}={}\n",fields[*key])).collect::<String>().into_bytes();Request::parse(&bytes,&sha256(&bytes)).unwrap()};
        let old=make_request("driver-microphone-v9-old");let fresh=make_request("driver-microphone-v9-fresh");
        let prior=root.join(old.get("namespace"));let current=root.join(fresh.get("namespace"));
        for path in [&prior,&current]{fs::create_dir(path).unwrap();fs::set_permissions(path,fs::Permissions::from_mode(0o700)).unwrap();}
        let held=sealed_fs::HeldDirectory::capture(&prior,owner,group,0o700).unwrap();let request_bytes=FIELDS.iter().map(|key|format!("{key}={}\n",old.get(key))).collect::<String>().into_bytes();held.write_record("request.txt",&request_bytes,0o400).unwrap();
        let journal_path=prior.join("journal");fs::create_dir(&journal_path).unwrap();fs::set_permissions(&journal_path,fs::Permissions::from_mode(0o700)).unwrap();
        let active=child_fence_bytes(&old,1).unwrap();held.write_record("child-active-001",&active,0o400).unwrap();
        assert!(cross_namespace_clear(&root,&fresh,owner,group).is_err(),"new namespace must not bypass an old unmatched fence");
        held.write_record("child-clean-001",&active,0o400).unwrap();assert!(cross_namespace_clear(&root,&fresh,owner,group).is_ok());
        held.write_record("UNRESOLVED_CHILD",&cleanup_record(&old,456,501,"fixture unresolved").unwrap(),0o400).unwrap();assert!(cross_namespace_clear(&root,&fresh,owner,group).is_err());fs::remove_file(prior.join("UNRESOLVED_CHILD")).unwrap();
        fs::remove_file(prior.join("child-clean-001")).unwrap();let mutant=String::from_utf8(active.clone()).unwrap().replace("owner_pid=","owner_pid=0");held.write_record("child-clean-001",mutant.as_bytes(),0o400).unwrap();assert!(cross_namespace_clear(&root,&fresh,owner,group).is_err());fs::remove_file(prior.join("child-clean-001")).unwrap();held.write_record("child-clean-001",&active,0o400).unwrap();
        let journal=sealed_fs::HeldDirectory::capture(&journal_path,owner,group,0o700).unwrap();journal.persist(&Journal::new(&old).appended(State::Prepared).unwrap()).unwrap();assert!(cross_namespace_clear(&root,&fresh,owner,group).is_err(),"an incomplete prior outcome must remain unresolved");
        for name in ["request.txt","child-active-001","child-clean-001"]{fs::remove_file(prior.join(name)).unwrap();}fs::remove_file(journal_path.join("journal-001")).unwrap();fs::remove_dir(journal_path).unwrap();fs::remove_dir(prior).unwrap();fs::remove_dir(current).unwrap();fs::remove_dir(root).unwrap();
    }
    #[test]fn exact_native_tree_format_matches_pinned_producer_artifact(){
        // Read-only retained candidate, no rebuild/signing/runtime operation.
        let path=Path::new(ARTIFACT).join(DRIVER_NAME);
        let result=verify_bundle(&path,"82e2f5c6e71f182020cdf6c002843d1bf68710a7ae9e94481ef4c5ec23f99dcb","6e18a5309200082c5fac9d6bf4130880e09aee25984a6a934a8adcd70dd1fd54",501);
        assert!(result.is_ok(),"{result:?}");
    }
}
