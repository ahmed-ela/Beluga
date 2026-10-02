// Native process containment for the microphone-v9 transaction. No CLI, no
// generic command-as-root surface, and no live invocation from offline tests.
use super::{hex, sha256, Identity, Result, NOFOLLOW, MAX_REQUEST};
use std::fs::{File, OpenOptions};
use std::io::{Read, Write, Seek, SeekFrom};
use std::os::fd::{AsRawFd, RawFd};
use std::os::fd::FromRawFd;
use std::os::unix::fs::{MetadataExt, OpenOptionsExt};
use std::os::unix::fs::FileTypeExt;
use std::os::unix::process::CommandExt;
use std::path::{Path,PathBuf};
use std::process::{Child, ChildStderr, ChildStdin, ChildStdout, Command, Stdio};
use std::time::{Duration, Instant};
use std::sync::{Mutex,OnceLock};
use std::sync::atomic::{AtomicBool,Ordering};

unsafe extern "C" {
    fn getuid() -> u32;
    fn geteuid() -> u32;
    fn getgid() -> u32;
    fn getegid() -> u32;
    fn setgroups(count: i32, groups: *const u32) -> i32;
    fn setgid(group: u32) -> i32;
    fn setuid(user: u32) -> i32;
    fn fchdir(fd: i32) -> i32;
    fn fcntl(fd: i32, command: i32, ...) -> i32;
    fn dup2(from:i32,to:i32)->i32;
    fn umask(mode:u32)->u32;
    fn kill(pid: i32, signal: i32) -> i32;
    fn waitid(kind:i32,pid:u32,info:*mut SigInfo,options:i32)->i32;
    fn proc_listpids(kind:u32,group:u32,buffer:*mut std::ffi::c_void,size:i32)->i32;
    fn proc_pidinfo(pid:i32,flavor:i32,arg:u64,buffer:*mut std::ffi::c_void,size:i32)->i32;
    fn signal(number:i32,handler:usize)->usize;
}

#[repr(C)]
#[derive(Default)]
struct SigInfo{signo:i32,error:i32,code:i32,pid:i32,uid:u32,status:i32,address:usize,value:usize,band:i64,pad:[usize;7]}
#[repr(C)]
#[derive(Default)]
struct ShortProcess{pid:u32,parent:u32,group:u32,status:u32,command:[u8;16],flags:u32,uid:u32,gid:u32,ruid:u32,rgid:u32,svuid:u32,svgid:u32,reserved:u32}

const CLOEXEC: i32 = 0x0100_0000;
const NONBLOCK: i32 = 4;
const MAX_NATIVE: usize = 16 * 1024 * 1024;
const MAX_OUTPUT: usize = 2 * 1024 * 1024;

// The original-UID supervisor owns this pipe. EOF is an abort, never consent
// to continue after its owner disappears. Once latched, normal operations are
// forbidden; the single bounded recovery phase may only follow the journal.
struct AbortChannel{file:File,bytes:Vec<u8>,reason:Option<&'static str>,deadline:Instant,recovery:bool,restart_deferral:bool}
static SUPERVISOR:OnceLock<Mutex<AbortChannel>>=OnceLock::new();
static SIGNAL_ABORT:AtomicBool=AtomicBool::new(false);
static CLEANUP_UNRESOLVED:OnceLock<Mutex<Option<(u32,u32,String)>>>=OnceLock::new();
extern "C" fn abort_signal(_:i32){SIGNAL_ABORT.store(true,Ordering::SeqCst);}
impl AbortChannel{
    fn poll(&mut self,allow_abort:bool)->Result<()>{
        let mut buffer=[0u8;8];
        loop{
            if Instant::now()>=self.deadline{return Err(if self.recovery{"RECOVERY_DEADLINE_EXCEEDED"}else{"TRANSACTION_DEADLINE_EXCEEDED"}.into());}
            if SIGNAL_ABORT.load(Ordering::SeqCst){self.reason.get_or_insert("SUPERVISOR_SIGNAL");break;}
            match self.file.read(&mut buffer){
            Ok(0)=>{self.reason.get_or_insert("SUPERVISOR_EOF");break;},
            Ok(count)=>{
                if self.bytes.len()+count>6{self.reason.get_or_insert("SUPERVISOR_CHANNEL_INVALID");break;}
                self.bytes.extend_from_slice(&buffer[..count]);
                if !b"ABORT\n".starts_with(&self.bytes){self.reason.get_or_insert("SUPERVISOR_CHANNEL_INVALID");break;}
                if self.bytes==b"ABORT\n"{self.reason.get_or_insert("SUPERVISOR_ABORT");}
            },
            Err(error)if error.kind()==std::io::ErrorKind::WouldBlock=>break,
            Err(error)if error.kind()==std::io::ErrorKind::Interrupted=>{},
            Err(_)=>{self.reason.get_or_insert("SUPERVISOR_CHANNEL_FAILED");break;},
        }}
        if SIGNAL_ABORT.load(Ordering::SeqCst){self.reason.get_or_insert("SUPERVISOR_SIGNAL");}
        if Instant::now()>=self.deadline{return Err(if self.recovery{"RECOVERY_DEADLINE_EXCEEDED"}else{"TRANSACTION_DEADLINE_EXCEEDED"}.into());}
        if !self.recovery&&!allow_abort&&!self.restart_deferral{if let Some(reason)=self.reason{return Err(reason.into());}}Ok(())
    }
}
pub(super) fn begin_supervision(seconds:u64)->Result<()>{
    if !OwnedChild::root_identity()||seconds==0||seconds>180{return Err("native supervisor identity/deadline refused".into());}
    let fd=unsafe{fcntl(0,67,32)};if fd<32{return Err("supervisor channel duplication failed".into());}
    let file=unsafe{File::from_raw_fd(fd)};
    if !file.metadata().map_err(|_|"supervisor channel stat failed")?.file_type().is_fifo(){return Err("supervisor must supply its owned persistent pipe".into());}
    nonblocking(file.as_raw_fd())?;
    if SUPERVISOR.set(Mutex::new(AbortChannel{file,bytes:Vec::new(),reason:None,deadline:Instant::now()+Duration::from_secs(seconds),recovery:false,restart_deferral:false})).is_err(){return Err("duplicate native supervisor refused".into());}
    for number in [1,2,15]{if unsafe{signal(number,abort_signal as *const () as usize)}==usize::MAX{return Err("native supervisor signal latch unavailable".into());}}
    supervisor_check()
}
fn supervision_poll(allow_abort:bool)->Result<()>{
    if let Some(failure)=CLEANUP_UNRESOLVED.get(){if let Some((group,uid,reason))=&*failure.lock().map_err(|_|"owned cleanup latch poisoned")?{return Err(format!("OWNED_CLEANUP_UNRESOLVED group={group} uid={uid}: {reason}"));}}
    if let Some(channel)=SUPERVISOR.get(){channel.lock().map_err(|_|"supervisor channel lock poisoned")?.poll(allow_abort)?;}Ok(())
}
pub(super) fn supervisor_check()->Result<()>{supervision_poll(false)}
pub(super) fn unresolved_cleanup()->Result<Option<(u32,u32,String)>>{
    CLEANUP_UNRESOLVED.get().map(|failure|failure.lock().map(|value|value.clone()).map_err(|_|"owned cleanup latch poisoned".into())).unwrap_or(Ok(None))
}
pub(super) fn enter_recovery()->Result<()>{
    let channel=SUPERVISOR.get().ok_or("native recovery lacks owned supervisor")?;let mut state=channel.lock().map_err(|_|"supervisor channel lock poisoned")?;
    if state.recovery{return Err("duplicate bounded recovery phase refused".into());}
    state.recovery=true;state.deadline=Instant::now()+Duration::from_secs(180);state.poll(true)
}
pub(super) struct RestartDeferral;
pub(super) fn begin_restart_dispatch()->Result<RestartDeferral>{
    let channel=SUPERVISOR.get().ok_or("restart dispatch lacks owned supervisor")?;let mut state=channel.lock().map_err(|_|"supervisor channel lock poisoned")?;
    state.poll(false)?;
    if state.restart_deferral||state.deadline.saturating_duration_since(Instant::now())<Duration::from_secs(60){return Err("restart dispatch lacks bounded recovery headroom".into());}
    // Exactly the already-authorized one-successor restart and its fresh
    // proof are indivisible with respect to ABORT. The latch still records it,
    // and the hard deadline is never deferred. No other effect uses this seam.
    state.restart_deferral=true;Ok(RestartDeferral)
}
impl Drop for RestartDeferral{fn drop(&mut self){if let Some(channel)=SUPERVISOR.get(){if let Ok(mut state)=channel.lock(){state.restart_deferral=false;}}}}

pub(super) struct SealedExecutable { file: File, identity: Identity, digest: String, path:PathBuf }
impl SealedExecutable {
    pub(super) fn open(path: &Path, expected: &str) -> Result<Self> {
        if !hex(expected,64) || std::fs::canonicalize(path).map_err(|_|"sealed executable canonical path unavailable")? != path {
            return Err("sealed executable digest/path refused".into());
        }
        let mut file=OpenOptions::new().read(true).custom_flags(NOFOLLOW|CLOEXEC).open(path).map_err(|_|"sealed executable nofollow open failed")?;
        let metadata=file.metadata().map_err(|_|"sealed executable stat failed")?;
        if !metadata.is_file() || metadata.uid()!=0 || metadata.gid()!=0 || metadata.mode()&0o7777!=0o555 || metadata.nlink()!=1 || metadata.len()==0 || metadata.len()>MAX_NATIVE as u64 {
            return Err("sealed executable root ownership/type/mode/extent refused".into());
        }
        super::sealed_fs::no_acl(&file)?;
        let identity=Identity::of(&metadata);
        let mut bytes=Vec::new();Read::by_ref(&mut file).take(MAX_NATIVE as u64+1).read_to_end(&mut bytes).map_err(|_|"sealed executable read failed")?;
        if sha256(&bytes)!=expected || identity!=Identity::of(&file.metadata().map_err(|_|"sealed executable restat failed")?) ||
            identity!=Identity::of(&std::fs::symlink_metadata(path).map_err(|_|"sealed executable path changed")?) {
            return Err("sealed executable bytes or identity changed".into());
        }
        Ok(Self{file,identity,digest:expected.into(),path:path.to_path_buf()})
    }
    fn revalidate(&self)->Result<()> {
        if Identity::of(&self.file.metadata().map_err(|_|"held executable stat failed")?)!=self.identity ||
            Identity::of(&std::fs::symlink_metadata(&self.path).map_err(|_|"held executable path disappeared")?)!=self.identity || !hex(&self.digest,64) {
            return Err("held executable changed".into());
        }
        Ok(())
    }
}

#[derive(Debug)]
pub(super) struct Captured { pub(super) code:i32, pub(super) stdout:Vec<u8>, pub(super) stderr:Vec<u8> }

fn nonblocking(fd:RawFd)->Result<()> {
    let flags=unsafe{fcntl(fd,3)};
    if flags<0 || unsafe{fcntl(fd,4,flags|NONBLOCK)}<0 { return Err("child channel nonblocking setup failed".into()); }
    Ok(())
}

fn collect<T:Read>(pipe:&mut T, bytes:&mut Vec<u8>, limit:usize)->Result<bool> {
    let mut buffer=[0u8;4096];
    loop {
        match pipe.read(&mut buffer) {
            Ok(0)=>return Ok(true),
            Ok(count)=>{if bytes.len()+count>limit{return Err("owned child output exceeds fixed bound".into());}bytes.extend_from_slice(&buffer[..count]);},
            Err(error) if error.kind()==std::io::ErrorKind::WouldBlock=>return Ok(false),
            Err(error) if error.kind()==std::io::ErrorKind::Interrupted=>{},
            Err(_)=>return Err("owned child channel read failed".into()),
        }
    }
}

fn inherited_channels(inherit:&[(RawFd,RawFd)],ruby_metadata:bool)->Result<()>{
    let mut targets=std::collections::BTreeSet::new();
    for(source,target)in inherit{
        if *source<32||(!(3..=5).contains(target)&&!(ruby_metadata&&*target==6))||!targets.insert(*target){return Err("owned inherited proof channel map refused".into());}
    }
    if ruby_metadata&&(!targets.contains(&3)||!targets.contains(&6)){return Err("Ruby requires request and root metadata proof channels".into());}Ok(())
}

pub(super) struct OwnedChild {
    child:Child, stdin:Option<ChildStdin>, stdout:ChildStdout, stderr:ChildStderr,
    output:Vec<u8>, errors:Vec<u8>, stdout_eof:bool, stderr_eof:bool, reaped:bool, expected_uid:u32, guardian:bool,
}

impl OwnedChild {
    pub(super) fn root_identity()->bool{unsafe{getuid()==0&&geteuid()==0}}
    pub(super) fn inherited(file:&File)->Result<File>{
        let fd=unsafe{fcntl(file.as_raw_fd(),67,32)};
        if fd<32{return Err("owned inherited descriptor duplication failed".into());}
        Ok(unsafe{File::from_raw_fd(fd)})
    }
    pub(super) fn ruby_gate(script:&Path,mode:&str,request_sha:&str,request:&File,baseline:Option<&File>,ready:Option<&File>,metadata:&File,metadata_sha:&str)->Result<Self>{
        if !matches!(mode,"--candidate-present"|"--host-absent"|"--host-ready")||!hex(request_sha,64)||!hex(metadata_sha,64){return Err("gate mode/request/metadata digest refused".into());}
        if mode=="--candidate-present"&&ready.is_some(){return Err("candidate-present may not use a replacement ready generation".into());}
        let proof=metadata.metadata().map_err(|_|"root metadata proof channel stat unavailable")?;let access=unsafe{fcntl(metadata.as_raw_fd(),3)};
        if !proof.is_file()||proof.uid()!=0||proof.gid()!=0||proof.mode()!=0o100400||proof.nlink()!=1||proof.len()==0||proof.len()>MAX_REQUEST as u64||access<0||access&3!=0{return Err("root metadata proof channel owner/type/mode/links/extent/access refused".into());}
        let mut request_copy=Self::inherited(request)?;let mut baseline_copy=baseline.map(Self::inherited).transpose()?;let mut ready_copy=ready.map(Self::inherited).transpose()?;let mut metadata_copy=Self::inherited(metadata)?;
        // dup/fcntl descriptors share file offsets on Darwin. These calls are
        // strictly serial; rewind the held proof channels before each child.
        request_copy.seek(SeekFrom::Start(0)).map_err(|_|"request proof channel rewind failed")?;
        for file in [&mut baseline_copy,&mut ready_copy].into_iter().flatten(){file.seek(SeekFrom::Start(0)).map_err(|_|"historical proof channel rewind failed")?;}
        metadata_copy.seek(SeekFrom::Start(0)).map_err(|_|"root metadata proof channel rewind failed")?;
        let mut mappings=vec![(request_copy.as_raw_fd(),3)];if let Some(file)=&baseline_copy{mappings.push((file.as_raw_fd(),4));}if let Some(file)=&ready_copy{mappings.push((file.as_raw_fd(),5));}mappings.push((metadata_copy.as_raw_fd(),6));
        let mut command=Command::new("/usr/bin/ruby");command.arg(script).args([mode,"/dev/fd/3",request_sha,metadata_sha]);
        Self::dropped_channels(command,None,&mappings,true)
    }
    pub(super) fn stop_host()->Result<Self>{
        let mut command=Command::new("/bin/launchctl");command.args(["bootout","gui/501/org.example.opensteamer.worldwide"]);Self::dropped(command,None,&[])
    }
    pub(super) fn start_host()->Result<Self>{
        let mut command=Command::new("/bin/launchctl");command.args(["bootstrap","gui/501","/Users/ahmed/Library/LaunchAgents/org.example.opensteamer.worldwide.plist"]);Self::dropped(command,None,&[])
    }
    // The privileged surface is limited to read-only, OS-owned inspectors.
    // No request field can select an executable, command, or arbitrary PID.
    pub(super) fn core_launch()->Result<Self>{let mut command=Command::new("/bin/launchctl");command.args(["print","system/com.apple.audio.coreaudiod"]);Self::dropped(command,None,&[])}
    pub(super) fn core_process(pid:u32)->Result<Self>{
        if pid==0||pid>i32::MAX as u32{return Err("CoreAudio PID bound differs".into());}
        let mut command=Command::new("/bin/ps");command.args(["-ww","-p",&pid.to_string(),"-o","pid=","-o","ppid=","-o","uid=","-o","gid=","-o","comm="]);Self::dropped(command,None,&[])
    }
    pub(super) fn core_start(pid:u32)->Result<Self>{
        if pid==0||pid>i32::MAX as u32{return Err("CoreAudio PID bound differs".into());}
        let mut command=Command::new("/bin/ps");command.args(["-p",&pid.to_string(),"-o","lstart="]);Self::dropped(command,None,&[])
    }
    pub(super) fn core_pids()->Result<Self>{let mut command=Command::new("/usr/bin/pgrep");command.args(["-x","coreaudiod"]);Self::dropped(command,None,&[])}
    // This display string only selects candidates. The backend independently
    // binds the Apple image, full process generation and responsible service.
    pub(super) fn driver_host_pids()->Result<Self>{let mut command=Command::new("/usr/bin/pgrep");command.args(["-f","-x",r"Core Audio Driver \(OpensteamerVirtualMicrophone\.driver\)"]);Self::dropped(command,None,&[])}
    pub(super) fn driver_host_process(pid:u32)->Result<Self>{
        if pid<=1||pid>i32::MAX as u32{return Err("driver host PID bound differs".into());}
        let mut command=Command::new("/bin/ps");command.args(["-ww","-p",&pid.to_string(),"-o","pid=","-o","ppid=","-o","uid=","-o","gid=","-o","lstart=","-o","command="]);Self::dropped(command,None,&[])
    }
    pub(super) fn driver_host_procinfo(pid:u32)->Result<Self>{
        if pid<=1||pid>i32::MAX as u32{return Err("driver host PID bound differs".into());}
        let mut command=Command::new("/bin/launchctl");command.args(["procinfo",&pid.to_string()]);Self::root_inspector(command)
    }
    pub(super) fn core_mappings(pid:u32)->Result<Self>{
        if unsafe{getuid()}!=0||unsafe{geteuid()}!=0||pid==0||pid>i32::MAX as u32{return Err("root CoreAudio inspector admission differs".into());}
        let mut command=Command::new("/usr/sbin/lsof");command.args(["-n","-P","-a","-p",&pid.to_string(),"-d","txt","-F0pcDfin"]);
        Self::root_inspector(command)
    }
    pub(super) fn driver_image_owners(prior:&Path,candidate:&Path)->Result<Self>{
        // Fixed HAL roles only, derived from verified root bundle locations;
        // never an arbitrary request-selected root command or pathname.
        for path in [prior,candidate]{
            let text=path.to_str().ok_or("HAL owner path encoding differs")?;
            let canonical=format!("{}/Contents/MacOS/OpensteamerVirtualMicrophone",super::DRIVER);
            if text!=canonical{
                let tail=text.strip_prefix(&format!("{}/",super::ROOT_TRANSACTIONS)).ok_or("HAL owner path escaped fixed roots")?;
                let(namespace,role)=tail.split_once('/').ok_or("HAL owner namespace absent")?;
                if !namespace.starts_with("driver-microphone-v9-")||namespace.len()>96||!namespace.bytes().all(|b|b.is_ascii_alphanumeric()||b==b'-'||b==b'_')||
                    !["candidate.driver/Contents/MacOS/OpensteamerVirtualMicrophone","prior/OpensteamerVirtualMicrophone.driver/Contents/MacOS/OpensteamerVirtualMicrophone","failed/OpensteamerVirtualMicrophone.driver/Contents/MacOS/OpensteamerVirtualMicrophone"].contains(&role){return Err("HAL owner path is not a fixed sealed role".into());}
            }
        }
        let mut command=Command::new("/usr/sbin/lsof");command.args(["-n","-P","-a","-d","txt","-F0pcDfin","--"]).arg(prior).arg(candidate);Self::root_inspector(command)
    }
    fn root_inspector(mut command:Command)->Result<Self>{
        if unsafe{getuid()}!=0||unsafe{geteuid()}!=0{return Err("root OS inspector admission differs".into());}
        command.current_dir("/").env_clear().env("LC_ALL","C").env("PATH","/usr/bin:/bin:/usr/sbin:/sbin")
            .stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped()).process_group(0);Self::spawn(command,0)
    }
    pub(super) fn term_exact_core()->Result<Self>{
        if unsafe{getuid()}!=0||unsafe{geteuid()}!=0{return Err("root CoreAudio TERM identity differs".into());}
        let mut command=Command::new("/bin/launchctl");command.args(["kill","SIGTERM","system/com.apple.audio.coreaudiod"]);
        command.current_dir("/").env_clear().env("LC_ALL","C").env("PATH","/usr/bin:/bin:/usr/sbin:/sbin")
            .stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped()).process_group(0);Self::spawn(command,0)
    }
    fn dropped(command:Command,directory:Option<&File>,inherit:&[(RawFd,RawFd)])->Result<Self>{
        Self::dropped_channels(command,directory,inherit,false)
    }
    fn dropped_channels(mut command:Command,directory:Option<&File>,inherit:&[(RawFd,RawFd)],ruby_metadata:bool)->Result<Self>{
        if unsafe{getuid()}!=0||unsafe{geteuid()}!=0{return Err("UID501 dispatcher requires sealed root context".into());}
        inherited_channels(inherit,ruby_metadata)?;
        let directory_fd=directory.map(AsRawFd::as_raw_fd);let inherited=inherit.to_vec();
        command.current_dir("/").env_clear().env("LC_ALL","C").env("PATH","/usr/bin:/bin:/usr/sbin:/sbin")
            .stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped()).process_group(0);
        unsafe{command.pre_exec(move||{
            umask(0o077);
            for(source,target)in &inherited{if (!(3..=5).contains(target)&&!(ruby_metadata&&*target==6))||*source<32||dup2(*source,*target)!=*target{return Err(std::io::Error::last_os_error());}}
            if let Some(fd)=directory_fd{if fchdir(fd)!=0{return Err(std::io::Error::last_os_error());}}
            if setgroups(0,std::ptr::null())!=0||setgid(20)!=0||setuid(501)!=0||getuid()!=501||geteuid()!=501||getgid()!=20||getegid()!=20{return Err(std::io::Error::last_os_error());}Ok(())
        });}
        Self::spawn(command,501)
    }
    // Helpers use an independently held root-owned 0711 ancestry and pathname.
    // Darwin cannot execute a Mach-O image through /dev/fd/N. fchdir occurs before credentials are dropped so
    // an owned relative JSON writer can use a root-hidden private directory.
    pub(super) fn native(executable:&SealedExecutable,args:&[String],directory:Option<&File>,inherit:&[(RawFd,RawFd)])->Result<Self> {
        if unsafe{getuid()}!=0 || unsafe{geteuid()}!=0{return Err("native dispatcher requires sealed root context".into());}
        executable.revalidate()?;
        let mut command=Command::new(&executable.path);
        command.args(args);let owned=Self::dropped(command,directory,inherit)?;executable.revalidate()?;Ok(owned)
    }

    fn spawn(mut command:Command,expected_uid:u32)->Result<Self> {
        supervisor_check()?;
        let mut child=command.spawn().map_err(|_|"owned child spawn failed")?;
        let stdin=child.stdin.take();let stdout=child.stdout.take().ok_or("owned stdout missing")?;let stderr=child.stderr.take().ok_or("owned stderr missing")?;
        let mut owned=Self{child,stdin,stdout,stderr,output:Vec::new(),errors:Vec::new(),stdout_eof:false,stderr_eof:false,reaped:false,expected_uid,guardian:false};
        if nonblocking(owned.stdout.as_raw_fd()).is_err() || nonblocking(owned.stderr.as_raw_fd()).is_err(){owned.terminate()?;return Err("owned channel setup failed".into());}
        Ok(owned)
    }

    pub(super) fn write_line(&mut self,line:&[u8])->Result<()> {
        if line!=b"STOP\n" {return Err("guardian input other than STOP refused".into());}
        self.stdin.as_mut().ok_or("owned input already closed")?.write_all(line).map_err(|_|"guardian STOP write failed".into())
    }
    pub(super) fn close_input(&mut self){self.stdin.take();}
    pub(super) fn healthy(&mut self,ready:&[u8])->Result<()>{
        supervisor_check()?;
        self.drain(8192)?;
        if self.exit_pending()?||!self.errors.is_empty()||self.output!=ready{return Err("owned guardian is not continuously live/quiet".into());}Ok(())
    }
    fn exit_pending(&self)->Result<bool>{
        let mut info=SigInfo::default();
        // WNOWAIT keeps the leader's PID reserved until all owned descendants
        // and pipes have been contained. A reaped PID cannot fence its group.
        if unsafe{waitid(1,self.child.id(),&mut info,1|4|0x20)}!=0{return Err("owned child nonreaping wait failed".into());}
        Ok(info.pid==self.child.id() as i32)
    }
    fn members(&self)->Result<Vec<i32>>{
        // A member can exit between listpids and pidinfo. Re-inventory under
        // the still-unreaped leader fence; never silently abandon another live
        // descendant because one disappeared in that narrow observation race.
        for attempt in 0..=10{match self.members_once(){Ok(value)=>return Ok(value),Err(error)=>{
            if error!="owned group member generation unproved"||attempt==10{return Err(error);}
            std::thread::sleep(Duration::from_millis(10));
        }}}Err("owned group re-inventory exhausted".into())
    }
    fn members_once(&self)->Result<Vec<i32>>{
        let mut ids=[0i32;4096];let extent=unsafe{proc_listpids(2,self.child.id(),ids.as_mut_ptr().cast(),std::mem::size_of_val(&ids) as i32)};
        if extent<0 || extent as usize>=std::mem::size_of_val(&ids) || extent%4!=0{return Err("owned group inventory unavailable or truncated".into());}
        let mut result=Vec::new();
        for pid in ids[..extent as usize/4].iter().copied().filter(|pid|*pid>0){
            if pid==self.child.id() as i32{continue;} // owned unreaped leader; zombies have no BSDINFO
            let mut info=ShortProcess::default();let actual=unsafe{proc_pidinfo(pid,13,0,(&mut info as *mut ShortProcess).cast(),std::mem::size_of::<ShortProcess>() as i32)};
            if actual!=std::mem::size_of::<ShortProcess>() as i32{return Err("owned group member generation unproved".into());}
            if info.pid!=pid as u32 || info.group!=self.child.id() || info.uid!=self.expected_uid || info.ruid!=self.expected_uid{return Err("owned group membership/UID changed".into());}
            result.push(pid);
        }
        Ok(result)
    }
    fn drain(&mut self,limit:usize)->Result<()> {
        if !self.stdout_eof{self.stdout_eof=collect(&mut self.stdout,&mut self.output,limit)?;}
        if !self.stderr_eof{self.stderr_eof=collect(&mut self.stderr,&mut self.errors,limit)?;}
        Ok(())
    }
    pub(super) fn ready(&mut self,line:&[u8],duration:Duration)->Result<()> {
        if duration>Duration::from_secs(20){return Err("guardian ready deadline exceeds bound".into());}
        let deadline=Instant::now()+duration;
        loop {
            if let Err(error)=supervisor_check(){self.terminate()?;return Err(error);}
            if self.drain(8192).is_err(){self.terminate()?;return Err("guardian ready channel failed".into());}
            if self.output==line && self.errors.is_empty(){self.guardian=true;return Ok(());}
            if !self.errors.is_empty() || self.output.len()>line.len() || Instant::now()>=deadline || self.exit_pending()?{
                self.terminate()?;return Err("guardian ready proof differs or child terminated".into());
            }
            std::thread::sleep(Duration::from_millis(10));
        }
    }
    pub(super) fn finish(mut self,duration:Duration,maximum:usize)->Result<Captured> {
        if duration>Duration::from_secs(180) || maximum>MAX_OUTPUT || maximum==0{self.terminate()?;return Err("child deadline/output bound refused".into());}
        self.close_input();let deadline=Instant::now()+duration;
        loop {
            // A previously ready guardian must be allowed its exact STOP/EOF
            // teardown during abort; that is cleanup, not further mutation.
            if let Err(error)=supervision_poll(self.guardian){self.terminate()?;return Err(error);}
            if self.drain(maximum).is_err(){self.terminate()?;return Err("owned child output refused".into());}
            match self.exit_pending(){
                Ok(true)=>{
                    // A native helper may not leave descendants holding pipes.
                    self.drain(maximum)?;
                    if !self.stdout_eof || !self.stderr_eof || !self.members()?.is_empty(){self.terminate()?;return Err("owned child pipes/descendants outlived its process".into());}
                    let status=self.child.wait().map_err(|_|"owned child final reap failed")?;self.reaped=true;
                    let code=status.code().ok_or("owned child terminated by signal")?;
                    return Ok(Captured{code,stdout:std::mem::take(&mut self.output),stderr:std::mem::take(&mut self.errors)});
                },
                Ok(false)=>{},Err(_)=>{self.terminate()?;return Err("owned child wait failed".into());},
            }
            if Instant::now()>=deadline{self.terminate()?;return Err("owned child monotonic deadline exceeded".into());}
            std::thread::sleep(Duration::from_millis(10));
        }
    }
    fn terminate(&mut self)->Result<()>{
        self.close_input();if self.reaped{return Ok(());}
        let pid=self.child.id() as i32;
        self.members()?; // Never signal an unproved group.
        if self.exit_pending()?&&self.members()?.is_empty(){return self.reap_contained();}
        if unsafe{kill(-pid,15)}!=0{
            let error=std::io::Error::last_os_error().raw_os_error();
            if matches!(error,Some(1|3))&&self.exit_pending()?&&self.members()?.is_empty(){return self.reap_contained();}
            return Err("owned group TERM failed; cleanup unresolved".into());
        }
        let deadline=Instant::now()+Duration::from_millis(250);
        while Instant::now()<deadline{
            if self.exit_pending()?&&self.members()?.is_empty(){return self.reap_contained();}std::thread::sleep(Duration::from_millis(10));
        }
        self.members()?;
        if self.exit_pending()?&&self.members()?.is_empty(){return self.reap_contained();}
        if unsafe{kill(-pid,9)}!=0{
            let error=std::io::Error::last_os_error().raw_os_error();
            if matches!(error,Some(1|3))&&self.exit_pending()?&&self.members()?.is_empty(){return self.reap_contained();}
            return Err("owned group KILL failed; cleanup unresolved".into());
        }
        let deadline=Instant::now()+Duration::from_secs(2);
        loop{
            if self.exit_pending()?&&self.members()?.is_empty(){return self.reap_contained();}
            if Instant::now()>=deadline{return Err("owned descendants survive bounded cleanup; leader remains unreaped".into());}
            std::thread::sleep(Duration::from_millis(10));
        }
    }
    fn reap_contained(&mut self)->Result<()>{
        // Output bounds have already made this child non-green. Drain remaining
        // finite pipe data without appending it, solely to prove no live writer.
        fn discard<T:Read>(pipe:&mut T)->Result<bool>{let mut bytes=0;let mut buffer=[0u8;4096];loop{match pipe.read(&mut buffer){Ok(0)=>return Ok(true),Ok(count)=>{bytes+=count;if bytes>8*MAX_OUTPUT{return Err("cleanup pipe extent exceeds bound".into());}},Err(error)if error.kind()==std::io::ErrorKind::WouldBlock=>return Ok(false),Err(error)if error.kind()==std::io::ErrorKind::Interrupted=>{},Err(_)=>return Err("cleanup pipe read failed".into())}}}
        if !self.stdout_eof{self.stdout_eof=discard(&mut self.stdout)?;}if !self.stderr_eof{self.stderr_eof=discard(&mut self.stderr)?;}
        if !self.stdout_eof||!self.stderr_eof||!self.members()?.is_empty()||!self.exit_pending()?{return Err("owned cleanup pipes/group are not completely closed".into());}
        self.child.wait().map_err(|_|"owned contained leader reap failed")?;self.reaped=true;Ok(())
    }
}
impl Drop for OwnedChild{fn drop(&mut self){
    if let Err(error)=self.terminate(){
        // Root supervision must not continue a rollback while an earlier
        // delayed launchctl/helper or descendant remains uncontained. Keep
        // the exact still-owned group/UID and forbid every later effect/green
        // result; this is distinct from a proven harmless exit/signal race.
        if SUPERVISOR.get().is_some(){
            let latch=CLEANUP_UNRESOLVED.get_or_init(||Mutex::new(None));
            if let Ok(mut value)=latch.lock(){value.get_or_insert((self.child.id(),self.expected_uid,error.clone()));}
            eprintln!("OWNED_CLEANUP_UNRESOLVED group={} uid={}: {}",self.child.id(),self.expected_uid,error);
        }
    }
}}

#[cfg(test)]
mod tests{
    use super::*;
    #[test]fn metadata_fd6_is_ruby_only_mandatory_and_duplicate_targets_are_refused(){
        inherited_channels(&[(32,3),(33,6)],true).unwrap();inherited_channels(&[(32,3),(33,4),(34,5),(35,6)],true).unwrap();
        inherited_channels(&[(32,3),(33,4),(34,5)],false).unwrap();
        for map in [vec![(32,3),(33,6)],vec![(32,6)]]{assert!(inherited_channels(&map,false).is_err());}
        for map in [vec![(32,3)],vec![(32,6)],vec![(31,3),(33,6)],vec![(32,3),(33,6),(34,6)],vec![(32,3),(33,3),(34,6)],vec![(32,3),(33,6),(34,7)],vec![(32,2),(33,6)]]{assert!(inherited_channels(&map,true).is_err());}
    }
    fn fixture(program:&str,args:&[&str])->OwnedChild{
        let mut command=Command::new(program);command.args(args).env_clear().stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped()).process_group(0);
        OwnedChild::spawn(command,unsafe{geteuid()}).unwrap()
    }
    fn abort_fixture()->(AbortChannel,File){
        unsafe extern "C"{fn pipe(fds:*mut i32)->i32;}
        let mut fds=[-1i32;2];assert_eq!(unsafe{pipe(fds.as_mut_ptr())},0);
        let reader=unsafe{File::from_raw_fd(fds[0])};let writer=unsafe{File::from_raw_fd(fds[1])};nonblocking(reader.as_raw_fd()).unwrap();
        (AbortChannel{file:reader,bytes:Vec::new(),reason:None,deadline:Instant::now()+Duration::from_secs(2),recovery:false,restart_deferral:false},writer)
    }
    #[test]fn supervisor_abort_eof_malformed_and_deadline_never_authorize_forward_work(){
        let(mut channel,mut writer)=abort_fixture();writer.write_all(b"AB").unwrap();assert!(channel.poll(false).is_ok());writer.write_all(b"ORT\n").unwrap();assert_eq!(channel.poll(false).unwrap_err(),"SUPERVISOR_ABORT");
        drop(writer);assert!(channel.poll(false).is_err());channel.recovery=true;assert!(channel.poll(false).is_ok());
        channel.deadline=Instant::now();assert_eq!(channel.poll(true).unwrap_err(),"RECOVERY_DEADLINE_EXCEEDED");
        let(mut channel,writer)=abort_fixture();drop(writer);assert_eq!(channel.poll(false).unwrap_err(),"SUPERVISOR_EOF");
        for bytes in [b"RESUME".as_slice(),b"ABORT\r\n".as_slice(),b"ABORT\nABORT\n".as_slice()]{let(mut channel,mut writer)=abort_fixture();writer.write_all(bytes).unwrap();assert_eq!(channel.poll(false).unwrap_err(),"SUPERVISOR_CHANNEL_INVALID");}
        let(mut channel,_writer)=abort_fixture();channel.deadline=Instant::now();assert_eq!(channel.poll(false).unwrap_err(),"TRANSACTION_DEADLINE_EXCEEDED");
    }
    #[test]fn restart_deferral_preserves_abort_latch_but_never_extends_deadline(){
        let(mut channel,mut writer)=abort_fixture();channel.restart_deferral=true;writer.write_all(b"ABORT\n").unwrap();assert!(channel.poll(false).is_ok());assert_eq!(channel.reason,Some("SUPERVISOR_ABORT"));
        channel.restart_deferral=false;assert!(channel.poll(false).is_err());channel.restart_deferral=true;channel.deadline=Instant::now();assert!(channel.poll(true).is_err());
    }
    #[test]fn real_bounded_child_exit_and_deadline(){
        let output=fixture("/usr/bin/true",&[]).finish(Duration::from_secs(1),8192).unwrap();assert_eq!(output.code,0);assert!(output.stdout.is_empty());
        let start=Instant::now();assert!(fixture("/bin/sleep",&["30"]).finish(Duration::from_millis(30),8192).is_err());assert!(start.elapsed()<Duration::from_secs(2));
    }
    #[test]fn real_child_input_is_closed_and_arbitrary_guardian_write_refused(){
        let mut child=fixture("/bin/cat",&[]);assert!(child.write_line(b"arbitrary\n").is_err());child.write_line(b"STOP\n").unwrap();let output=child.finish(Duration::from_secs(1),8192).unwrap();assert_eq!(output.stdout,b"STOP\n");
    }
    #[test]fn real_child_output_limit_and_signal_are_non_green(){
        assert!(fixture("/usr/bin/yes",&[]).finish(Duration::from_secs(1),4096).is_err());
        let child=fixture("/bin/sleep",&["30"]);unsafe{kill(child.child.id() as i32,15);}
        assert!(child.finish(Duration::from_secs(1),8192).is_err());
    }
    #[test]fn early_exited_leader_cannot_leave_live_descendant_or_pipe(){
        let child=fixture("/bin/sh",&["-c","/bin/sleep 30 & exit 0"]);let group=child.child.id();
        assert!(child.finish(Duration::from_secs(1),8192).is_err());
        let deadline=Instant::now()+Duration::from_secs(2);
        loop{
            let mut ids=[0i32;128];let extent=unsafe{proc_listpids(2,group,ids.as_mut_ptr().cast(),std::mem::size_of_val(&ids) as i32)};
            assert!(extent>=0&&(extent as usize)<std::mem::size_of_val(&ids)&&extent%4==0);
            if ids[..extent as usize/4].iter().all(|pid|*pid==0){break;}
            assert!(Instant::now()<deadline,"owned descendant remained after non-green child result");std::thread::sleep(Duration::from_millis(20));
        }
    }
    #[test]fn darwin_descriptor_exec_is_not_a_substitute_for_sealed_ancestry(){
        let executable=File::open("/usr/bin/true").unwrap();let fd=executable.as_raw_fd();
        let mut command=Command::new(format!("/dev/fd/{fd}"));command.env_clear().stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped()).process_group(0);
        unsafe{command.pre_exec(move||{let flags=fcntl(fd,1);if flags<0 || fcntl(fd,2,flags&!1)<0{return Err(std::io::Error::last_os_error());}Ok(())});}
        assert!(OwnedChild::spawn(command,unsafe{geteuid()}).is_err());
    }
}
