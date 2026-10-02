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
            if !matches!(last,State::Committed|State::RolledBack){return Err("another namespace has an incomplete/unverified transaction outcome".into());}
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
const INSPECTOR_ROLES:&[&str]=&["core_launch_before","core_process","core_pids","core_start","core_launch_after","driver_selector_before","driver_process_before","driver_procinfo_before","driver_mappings","driver_owners_prior","driver_owners_candidate","driver_process_after","driver_procinfo_after","driver_selector_after"];
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
fn selected_owner_output(role:&str,captured:&os::Captured,path:&Path,identity:&Identity)->Result<()>{
    if !captured.stderr.is_empty(){return Err(inspector_summary(role,captured));}
    match captured.code{
        1 if captured.stdout.is_empty()=>Ok(()),
        0 if !captured.stdout.is_empty()=>selected_hal_owners(&captured.stdout,path,identity).map_err(|reason|format!("{} parse_error_sha256={}",inspector_summary(role,captured),sha256(reason.as_bytes()))),
        _=>Err(inspector_summary(role,captured)),
    }
}
fn global_hal_owner(prior_output:&os::Captured,candidate_output:&os::Captured,prior_path:&Path,prior:&Identity,candidate_path:&Path,candidate:&Identity,pid:u32,loaded:LoadedDriver)->Result<()>{
    selected_owner_output("driver_owners_prior",prior_output,prior_path,prior)?;selected_owner_output("driver_owners_candidate",candidate_output,candidate_path,candidate)?;
    let selected=match(loaded,prior_output.code,candidate_output.code){(LoadedDriver::Prior,0,1)=>Some((prior_output,prior)),(LoadedDriver::Candidate,1,0)=>Some((candidate_output,candidate)),_=>None};
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
const PRE_EFFECT_RECORDS:&[&str]=&["request.txt","build-manifest.json","authority.txt","SEALING_INCOMPLETE","SEALING_COMPLETE","candidate.driver","journal","prior","failed","probes","host-baseline.txt","admission-refusal.txt","child-active-001","child-clean-001"];
fn refusal_journal_empty(memory:&Journal,durable:&Journal,resumed:bool,sequence:usize)->Result<()>{
    if memory.last().is_some()||durable.last().is_some()||resumed||sequence!=1{return Err("pre-effect refusal has durable/recovered transaction effects".into());}Ok(())
}
fn refusal_containment_finalized(clean:bool,resumed:bool,sequence:usize)->Result<()>{
    if !clean||resumed||sequence!=1{return Err("pre-effect refusal lacks first-attempt finalized containment".into());}Ok(())
}

impl RootContext{
    fn record(&self,name:&str,bytes:&[u8])->Result<()>{self.revalidate()?;self.state_ancestry.last().unwrap().write_record(name,bytes,0o400)}
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
        if !(1..=5).contains(&index){return Err("guardian segment count exceeds restart/recovery bound".into());}context.revalidate()?;
        let path=context.state.join(format!("guardian-{index}.events"));
        let event=OpenOptions::new().read(true).write(true).create_new(true).mode(0o600).custom_flags(NOFOLLOW).open(&path).map_err(|_|"guardian event exclusive creation failed")?;
        let metadata=event.metadata().map_err(|_|"guardian event stat unavailable")?;
        if !metadata.is_file()||metadata.uid()!=0||metadata.gid()!=0||metadata.mode()&0o7777!=0o600||metadata.nlink()!=1||metadata.len()!=0{return Err("guardian root event ownership/mode differs".into());}
        sealed_fs::no_acl(&event)?;event.sync_all().map_err(|_|"guardian event sync failed")?;
        let inherited=os::OwnedChild::inherited(&event)?;
        let args=vec!["/dev/fd/5".into(),context.request.get("input_uid").into(),context.request.get("output_uid").into(),context.request.get("system_output_uid").into()];
        use std::os::fd::AsRawFd;
        let mut child=os::OwnedChild::native(&context.guardian,&args,None,&[(inherited.as_raw_fd(),5)])?;
        let ready=format!("READY input={} output={} system={}\n",context.request.get("input_uid"),context.request.get("output_uid"),context.request.get("system_output_uid")).into_bytes();
        child.ready(&ready,Duration::from_secs(20))?;context.revalidate()?;Ok(Self{child,event,index,ready})
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
    candidate_instance:Option<u64>,rollback_bootstrap:Option<proof::IdleReceipt>,resumed:bool,
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
        let mut backend=Self{context,journal,guardian:None,next_guardian:1,clean_segments:0,public:None,idle:None,candidate_instance:None,rollback_bootstrap:None,resumed:resume};
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
        let prior_positive=owner_output(0,SINGLE_PRIOR_OWNER_FIXTURE,b"");let negative=owner_output(1,b"",b"");let candidate_positive=owner_output(0,&owner_mapping(309,candidate.inode,&candidate_path),b"");
        global_hal_owner(&prior_positive,&negative,&prior_path,&prior,&candidate_path,&candidate,309,LoadedDriver::Prior).unwrap();
        global_hal_owner(&negative,&candidate_positive,&prior_path,&prior,&candidate_path,&candidate,309,LoadedDriver::Candidate).unwrap();
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
        for(code,stdout,stderr)in [(0,b"".as_slice(),b"".as_slice()),(1,SINGLE_PRIOR_OWNER_FIXTURE,b""),(0,SINGLE_PRIOR_OWNER_FIXTURE,b"warning"),(1,b"",b"permission denied"),(2,b"",b""),(75,b"",b""),(78,b"",b""),(-1,b"",b"")]{
            assert!(selected_owner_output("driver_owners_prior",&owner_output(code,stdout,stderr),&path,&prior).is_err(),"accepted status {code}");
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
