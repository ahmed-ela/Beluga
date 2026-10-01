//! Narrow root-sealed OS adapter components. Not wired to live CLI admission
//! until the complete transaction and independent whole-path review pass.
use super::*;
use std::fs::File;
use std::path::PathBuf;
use std::time::Duration;
use std::time::Instant;

const EXECUTABLES:&str="/Library/Application Support/opensteamer/microphone-v9-executables";
const DRIVER_NAME:&str="OpensteamerVirtualMicrophone.driver";
const DRIVER_EXE:&str="Contents/MacOS/OpensteamerVirtualMicrophone";
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
        let captured=os::OwnedChild::ruby_gate(&script,mode,&self.request.sha256,&self.request_file,baseline.as_ref(),ready.as_ref())?.finish(Duration::from_secs(20),MAX_REQUEST)?;
        if captured.code!=0||!captured.stderr.is_empty(){return Err("sealed original-UID host gate failed".into());}
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
fn clean_output(child:os::OwnedChild,maximum:usize)->Result<Vec<u8>>{
    let captured=child.finish(Duration::from_secs(5),maximum)?;
    if captured.code!=0||!captured.stderr.is_empty(){return Err("trusted OS identity inspector failed".into());}Ok(captured.stdout)
}
fn read_core()->Result<CoreGeneration>{
    let first=core_launch(&clean_output(os::OwnedChild::core_launch()?,MAX_REQUEST)?)?;
    let pid=first.0;let process=clean_output(os::OwnedChild::core_process(pid)?,8192)?;
    let fields=std::str::from_utf8(&process).map_err(|_|"CoreAudio process encoding differs")?.split_ascii_whitespace().collect::<Vec<_>>();
    if fields!=[pid.to_string().as_str(),"1","202","202","/usr/sbin/coreaudiod"]{return Err("CoreAudio exact process identity differs".into());}
    let pids=clean_output(os::OwnedChild::core_pids()?,8192)?;if pids!=format!("{pid}\n").as_bytes(){return Err("CoreAudio process set is not unique".into());}
    let start=clean_output(os::OwnedChild::core_start(pid)?,8192)?;let text=std::str::from_utf8(&start).map_err(|_|"CoreAudio start encoding differs")?;
    if text.lines().count()!=1||!text.ends_with('\n')||text.contains('\r')||text.split_ascii_whitespace().count()!=5{return Err("CoreAudio start identity differs".into());}
    let start_sha=sha256(text.split_ascii_whitespace().collect::<Vec<_>>().join(" ").as_bytes());
    if core_launch(&clean_output(os::OwnedChild::core_launch()?,MAX_REQUEST)?)?!=first{return Err("CoreAudio generation changed during proof".into());}
    Ok(CoreGeneration{pid,runs:first.1,start_sha})
}
fn stable_core()->Result<CoreGeneration>{let first=read_core()?;std::thread::sleep(Duration::from_millis(100));if read_core()?!=first{return Err("CoreAudio generation is unstable".into());}Ok(first)}

// lsof's NUL field mode avoids spaces/newlines in path parsing. The only
// accepted HAL image is bound by actual device/inode, not its displayed name.
fn loaded_mapping(bytes:&[u8],pid:u32,prior:&Identity,candidate:&Identity)->Result<LoadedDriver>{
    if bytes.len()>1024*1024||!bytes.ends_with(b"\n"){return Err("CoreAudio image inventory extent differs".into());}
    let mut process_seen=false;let mut command_seen=false;let mut record=BTreeMap::new();let mut images=Vec::new();
    fn finish(record:&mut BTreeMap<u8,String>,images:&mut Vec<(u64,u64)>)->Result<()>{
        if record.is_empty(){return Ok(());}if record.get(&b'n').is_some_and(|path|path.ends_with("/Contents/MacOS/OpensteamerVirtualMicrophone")){
            if record.get(&b'f').map(String::as_str)!=Some("txt"){return Err("HAL image is not an executable text mapping".into());}
            let device=record.get(&b'D').and_then(|value|value.strip_prefix("0x")).ok_or("HAL mapping device missing")?;
            if device.is_empty()||device.len()>16||!device.bytes().all(|byte|byte.is_ascii_hexdigit()){return Err("HAL mapping device malformed".into());}
            let inode=positive(record.get(&b'i').ok_or("HAL mapping inode missing")?)?;
            images.push((u64::from_str_radix(device,16).map_err(|_|"HAL mapping device overflow")?,inode));
        }record.clear();Ok(())
    }
    for raw in bytes.split(|byte|*byte==0){let token=raw.strip_prefix(b"\n").unwrap_or(raw);if token.is_empty()||token==b"\n"{continue;}
        let key=token[0];let value=std::str::from_utf8(&token[1..]).map_err(|_|"CoreAudio image field encoding differs")?.to_string();
        match key{
            b'p'=>{finish(&mut record,&mut images)?;if process_seen||value!=pid.to_string(){return Err("CoreAudio mapping process differs".into());}process_seen=true;},
            b'c'=>{if command_seen||value!="coreaudiod"{return Err("CoreAudio mapping command differs".into());}command_seen=true;},
            b'f'=>{finish(&mut record,&mut images)?;record.insert(key,value);},
            b'D'|b'i'|b'n'=>{if record.insert(key,value).is_some(){return Err("CoreAudio mapping field duplicate refused".into());}},
            _=>return Err("CoreAudio mapping unknown field refused".into()),
        }
    }
    finish(&mut record,&mut images)?;
    if !process_seen||!command_seen||images.len()!=1{return Err("CoreAudio exact unique HAL image unproved".into());}
    if images[0]==(prior.device,prior.inode){Ok(LoadedDriver::Prior)}else if images[0]==(candidate.device,candidate.inode){Ok(LoadedDriver::Candidate)}else{Err("CoreAudio loaded HAL image inode differs".into())}
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
    fn prior_identity(&self)->Result<(Identity,Identity)>{
        let mut exact=Vec::new();for path in [PathBuf::from(DRIVER),self.state.join("prior").join(DRIVER_NAME)]{
            match fs::symlink_metadata(&path){Err(error)if error.kind()==std::io::ErrorKind::NotFound=>{},Err(_)=>return Err("predecessor location metadata unavailable".into()),Ok(metadata)=>{
                if metadata.dev()==self.request.number("predecessor_driver_device")&&metadata.ino()==self.request.number("predecessor_driver_inode"){
                    exact.push(verify_bundle(&path,self.request.get("predecessor_driver_tree_sha256"),self.request.get("predecessor_driver_executable_sha256"),0)?);
                }
            }}
        }if exact.len()!=1{return Err("predecessor unique retained inode unproved".into());}Ok(exact.pop().unwrap())
    }
    fn loaded(&self,core:&CoreGeneration)->Result<LoadedDriver>{
        let prior=self.prior_identity()?.1;
        let bytes=clean_output(os::OwnedChild::core_mappings(core.pid)?,1024*1024)?;
        let loaded=loaded_mapping(&bytes,core.pid,&prior,&self.authority.candidate_executable)?;
        if read_core()?!=*core{return Err("CoreAudio generation changed while binding HAL image".into());}Ok(loaded)
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
    candidate_instance:Option<u64>,rollback_bootstrap:Option<proof::IdleReceipt>,
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
        let mut backend=Self{context,journal,guardian:None,next_guardian:1,clean_segments:0,public:None,idle:None,candidate_instance:None,rollback_bootstrap:None};
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
    pub(super) fn restart_counts(&self)->Result<(u8,u8)>{let(_,_,normal,rollback)=self.core_facts()?;Ok((normal,rollback))}
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
        let(core,loaded,normal,rollback)=self.core_facts()?;
        if normal==1&&rollback==0&&self.context.core_record("normal-restart-complete.txt")?.is_none(){
            // A real exact successor may have appeared before interruption
            // prevented its completion record. Pin that freshly observed
            // generation before any conditional second restart; do not guess
            // a historic PID or repeat the original TERM.
            if loaded!=LoadedDriver::Candidate{return Err("interrupted normal completion lacks exact candidate load".into());}
            self.context.save_core("normal-restart-complete.txt",&core)?;
        }
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
        let core=stable_core()?;let loaded=self.context.loaded(&core)?;
        let Some(base)=self.context.core_record("core-baseline.txt")?else{
            if loaded!=LoadedDriver::Prior{return Err("initial exact loaded predecessor is unproved".into());}return Ok((core,loaded,0,0));
        };
        let normal_intent=self.context.core_record("normal-restart-intent.txt")?;
        let normal_done=self.context.core_record("normal-restart-complete.txt")?;
        let rollback_intent=self.context.core_record("rollback-restart-intent.txt")?;
        let rollback_done=self.context.core_record("rollback-restart-complete.txt")?;
        if normal_intent.as_ref().is_some_and(|value|value!=&base){return Err("normal restart intent baseline differs".into());}
        if normal_intent.is_none(){if core!=base||normal_done.is_some()||rollback_intent.is_some()||rollback_done.is_some(){return Err("unowned CoreAudio generation change refused".into());}return Ok((core,loaded,0,0));}
        if core==base{return Err("durable TERM intent has no resolved successor; do not repeat signal".into());}
        let normal=if let Some(value)=normal_done{if !base.successor(&value){return Err("normal restart completion is not exact successor".into());}value}else{
            if !base.successor(&core)||rollback_intent.is_some(){return Err("unresolved normal restart cannot bind rollback generation".into());}core.clone()
        };
        if let Some(before)=rollback_intent{
            if before!=normal{return Err("rollback restart intent baseline differs".into());}
            if core==normal{return Err("durable rollback TERM intent has no resolved successor; do not repeat signal".into());}
            if !normal.successor(&core)||rollback_done.as_ref().is_some_and(|done|done!=&core){return Err("rollback restart generation/budget differs".into());}
            if loaded!=LoadedDriver::Prior{return Err("rollback exact loaded predecessor differs".into());}Ok((core,loaded,1,1))
        }else{
            if rollback_done.is_some()||core!=normal{return Err("CoreAudio changed outside normal restart budget".into());}
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
        self.close_guardian()?;
        let name=if rollback{"rollback"}else{"normal"};
        // No listener can truthfully cover the deliberate service reload gap.
        // Record that gap explicitly, never turn its absence into zero events.
        self.context.record(&format!("{name}-route-monitor-gap.txt"),format!("schema=opensteamer.microphone-v9-intentional-coreaudio-gap.v1\nnonce={}\nbefore_pid={}\nbefore_runs={}\ncoverage=not-claimed-inside-authorized-restart\n",self.context.request.get("nonce"),core.pid,core.runs).as_bytes())?;
        self.context.gate("--host-absent")?;
        if stable_core()?!=core{return Err("CoreAudio generation changed before exact TERM".into());}
        let _restart_deferral=os::begin_restart_dispatch()?;
        self.context.save_core(&format!("{name}-restart-intent.txt"),&core)?;
        let output=os::OwnedChild::term_exact_core()?.finish(Duration::from_secs(5),8192)?;
        if output.code!=0||!output.stdout.is_empty()||!output.stderr.is_empty(){return Err("exact service-bound CoreAudio TERM failed; intent is never repeated".into());}
        let deadline=Instant::now()+Duration::from_secs(30);let after=loop{
            if let Ok(next)=stable_core(){if core.successor(&next){break next;}if next!=core{return Err("CoreAudio restart was not exactly one successor".into());}}
            if Instant::now()>=deadline{return Err("CoreAudio restart successor deadline exceeded".into());}std::thread::sleep(Duration::from_millis(100));
        };
        self.context.gate("--host-absent")?;
        let bootstrap=if rollback{self.context.idle_read("--bootstrap-prior-instance","after-rollback",1,None,Some("rollback-bootstrap.json"))?}
            else{self.context.idle_read("--bootstrap-instance","after-reload",2,None,Some("candidate-bootstrap.json"))?};
        if rollback{self.rollback_bootstrap=Some(bootstrap);}else{self.candidate_instance=Some(bootstrap.instance);}
        if self.context.loaded(&after)?!=if rollback{LoadedDriver::Prior}else{LoadedDriver::Candidate}{return Err("fresh bootstrap does not bind exact loaded HAL image".into());}
        self.context.save_core(&format!("{name}-restart-complete.txt"),&after)?;self.arm()?;Ok(())
    }
}
impl Backend for OsBackend{
    // Admission was explicitly enabled only after whole-path source review;
    // actual execution still requires every sealed and fresh runtime predicate.
    fn live_admission(&self)->bool{LIVE_ADMISSION}
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
        Effect::Seal=>{self.context.gate("--candidate-present")?;let core=stable_core()?;if self.context.loaded(&core)?!=LoadedDriver::Prior{return Err("initial loaded predecessor differs".into());}self.context.save_core("core-baseline.txt",&core)?;self.arm()},
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
        let prior=identity(16777232,12);let candidate=identity(16777232,13);
        let make=|inode|format!("p456\0ccoreaudiod\0\nftxt\0D0x1000010\0i{inode}\0n{DRIVER}/{DRIVER_EXE}\0\n").into_bytes();
        assert_eq!(loaded_mapping(&make(12),456,&prior,&candidate).unwrap(),LoadedDriver::Prior);assert_eq!(loaded_mapping(&make(13),456,&prior,&candidate).unwrap(),LoadedDriver::Candidate);
        for mutant in [make(14),make(12).iter().copied().chain(make(13)).collect(),String::from_utf8(make(12)).unwrap().replace("D0x1000010","D0x1000011").into_bytes(),String::from_utf8(make(12)).unwrap().replace("p456","p457").into_bytes(),String::from_utf8(make(12)).unwrap().replace("i12","i12\0i12").into_bytes()]{assert!(loaded_mapping(&mutant,456,&prior,&candidate).is_err());}
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
