//! Proposed product-export tests: literal full179 successors and all13 sidecars.
//! Constructor/codec seed inputs and serialize hand-written expected fields only.
//! No expected successor invokes Owner/Policy reducers or the private raw event.
//! Plain Rust source fixtures are not an artifact/native actor/effect proof.
use crate::network_adaptation_owner_events::{
    beluga_core_network_adaptation_owner_zero_clock_event as event, RawOwnerEventRequest,
};
use crate::native_clock_assay::{Edit, Metadata, Reply, Time};
use crate::network_adaptation_candidate::{
    Dependencies, EvidenceLane, Owner, Promotion, Recommendation, Restoration, Scalar, Tier,
};
use crate::network_adaptation_candidate::state_codec::{self as codec, Atom, Header};
use core::{mem::{align_of, offset_of, size_of}, ptr};

const INVOCATION: u64 = 0xfedc_ba98_7654_3210;
const HEADER: Header = Header { abi: 1, domain: 2, phase: 1, count: 179 };
const RESULT: Header = Header { abi: 1, domain: 2, phase: 2, count: 179 };
const NAN: u64 = 0x7ff8_1234_5678_9012;
const NEGATIVE_ZERO: u64 = 0x8000_0000_0000_0000;

fn seed() -> Owner {
    let mut v = Owner::new(50_000_000, 60, Dependencies::default());
    v.revision = u64::MAX; v.fast_statistics_available = true;
    v.evidence_lane = Some(EvidenceLane::OrdinaryFallback); v.last_evidence = Some(-7);
    v.freshness.minimum = Some(u64::MAX);
    v.applied = Some(Recommendation { tier: Tier::Balanced, maximum_video: 1234,
        maximum_total: 2345, fps: 29, scale: Scalar(NAN) });
    v.policy.peer = Some(17); v.policy.floor_show = Some(23);
    v.policy.floor_reserved = true; v.policy.floor_active = false;
    v.policy.startup_peer = Some(17); v.policy.startup_show = Some(23);
    v.policy.startup_sparse_deadline = Some(123); v.policy.route_present = true;
    v.policy.queue.faulted = true; v.policy.rtt.faulted = true;
    v.policy.last_average_delay = Some(Scalar(NEGATIVE_ZERO));
    v.policy.resume_restoration = Some(Restoration { disproved: true, cooldown: 37, failures: 41 });
    v.policy.promotion = Some(Promotion { tier: Tier::Critical, maximum_total: 3456, deadline: 71 });
    v
}
fn snapshot(v: Owner) -> [Atom;179] {
    codec::encode_owner_snapshot(v).unwrap().atoms.try_into().unwrap()
}
fn request(operation: u32) -> RawOwnerEventRequest {
    RawOwnerEventRequest { abi: 1, operation, generation: 0, invocation: INVOCATION,
        show: 0, capture_source_present: 0, resume_context_absent: 0 }
}
#[derive(Clone, Debug, PartialEq, Eq)]
struct Output {
    header: Header, atoms: [Atom;179], metadata: Metadata,
    edits: [Edit;13], coordinates: [Time;13], reads: [Reply;15],
}
impl Output {
    fn sentinel() -> Self { Self {
        header: Header { abi: 701, domain: 702, phase: 703, count: 704 },
        atoms: [Atom { kind: 711, present: 712, high: -713, low: 714 };179],
        metadata: Metadata { abi: 721, operation: 722, scope: 723, read_count: 724,
            invocation: 725, revision: 726, peer: 727, peer_present: 728, bound: 729,
            route: 730, sample: 731, enabled: 732, lease: 733, queue_fault: 734, rtt_fault: 735 },
        edits: [Edit { action: 741, source: 742, index: 743, ordinal: 744, high: -745, low: 746 };13],
        coordinates: [Time { present: 751, reserved: 752, high: -753, low: 754 };13],
        reads: [Reply { abi: 761, status: 762, site: 763, ordinal: 764,
            invocation: 765, high: -766, low: 767, reserved: 768 };15],
    } }
}
#[derive(Clone, Copy)]
struct Args {
    req: *const RawOwnerEventRequest, header: *const Header, atoms: *const Atom, count: u32,
    oh: *mut Header, oa: *mut Atom, oc: u32, meta: *mut Metadata,
    edits: *mut Edit, ec: u32, times: *mut Time, tc: u32, reads: *mut Reply, rc: u32,
}
impl Args {
    fn new(req: &RawOwnerEventRequest, header: &Header, atoms: &[Atom;179], out: &mut Output) -> Self {
        Self { req, header, atoms: atoms.as_ptr(), count: 179, oh: &mut out.header,
            oa: out.atoms.as_mut_ptr(), oc: 179, meta: &mut out.metadata,
            edits: out.edits.as_mut_ptr(), ec: 13, times: out.coordinates.as_mut_ptr(), tc: 13,
            reads: out.reads.as_mut_ptr(), rc: 15 }
    }
    unsafe fn run(self) -> u32 { unsafe { event(self.req, self.header, self.atoms, self.count,
        self.oh, self.oa, self.oc, self.meta, self.edits, self.ec, self.times, self.tc, self.reads, self.rc) } }
}
fn call(v: &[Atom;179], req: &RawOwnerEventRequest) -> (u32, Output) {
    let before = *v; let req_before = *req; let h = HEADER;
    let mut out = Output::sentinel();
    let code = unsafe { Args::new(req, &h, v, &mut out).run() };
    assert_eq!(*v, before, "all179 input atoms unchanged");
    assert_eq!(*req, req_before, "request unchanged"); assert_eq!(h, HEADER);
    (code, out)
}
fn success(input: Owner, req: RawOwnerEventRequest, expected: Owner, owned_clear: Option<usize>, enabled: u32) {
    let atoms = snapshot(input); let want = snapshot(expected);
    let (code, out) = call(&atoms, &req); assert_eq!(code, 1);
    assert_eq!(out.header, RESULT); assert_eq!(out.atoms, want, "manual all179 successor");
    assert_eq!(out.metadata, Metadata { abi: 1, operation: req.operation, scope: 2, read_count: 0,
        invocation: INVOCATION, revision: expected.revision, peer: expected.policy.peer.unwrap_or(0),
        peer_present: expected.policy.peer.is_some() as u32,
        queue_fault: expected.policy.queue.faulted as u32, rtt_fault: expected.policy.rtt.faulted as u32,
        enabled, ..Metadata::default() });
    for i in 0..13 {
        assert_eq!(out.edits[i], if owned_clear == Some(i) {
            Edit { action: 2, ..Edit::default() }
        } else { Edit::default() }, "manual exact time edit slot {i}");
    }
    assert_eq!(out.coordinates, [Time::default();13]);
    assert_eq!(out.reads, [Reply::default();15], "no fabricated/eager reads");
}
fn deny(v: &[Atom;179], req: &RawOwnerEventRequest, mutate: impl FnOnce(&mut Args)) {
    let h = HEADER; let mut out = Output::sentinel(); let before = out.clone();
    let atoms_before = *v; let req_before = *req;
    let mut a = Args::new(req, &h, v, &mut out); mutate(&mut a);
    assert_eq!(unsafe { a.run() }, 2);
    assert_eq!(out, before, "all six denied output objects untouched");
    assert_eq!(*v, atoms_before); assert_eq!(*req, req_before); assert_eq!(h, HEADER);
}

#[test]
fn product_owner_zero_clock_public_request_and_pod_layouts_are_exact() {
    assert_eq!((size_of::<RawOwnerEventRequest>(), align_of::<RawOwnerEventRequest>()), (40, 8));
    assert_eq!((offset_of!(RawOwnerEventRequest, abi), offset_of!(RawOwnerEventRequest, operation),
        offset_of!(RawOwnerEventRequest, generation), offset_of!(RawOwnerEventRequest, invocation),
        offset_of!(RawOwnerEventRequest, show), offset_of!(RawOwnerEventRequest, capture_source_present),
        offset_of!(RawOwnerEventRequest, resume_context_absent)), (0,4,8,16,24,32,36));
    assert_eq!((size_of::<Header>(), align_of::<Header>()), (16,4));
    assert_eq!((size_of::<Atom>(), align_of::<Atom>()), (24,8));
    assert_eq!((size_of::<Edit>(), align_of::<Edit>()), (32,8));
    assert_eq!((size_of::<Time>(), align_of::<Time>()), (24,8));
    assert_eq!((size_of::<Reply>(), align_of::<Reply>()), (48,8));
    assert_eq!((size_of::<Metadata>(), align_of::<Metadata>()), (72,8));
}
#[test]
fn product_owner_zero_clock_stop_sampling_is_separate_and_wraps_once_without_policy_or_applied_loss() {
    for (revision, next) in [(0,1), (u64::MAX-1,u64::MAX), (u64::MAX,0)] {
        for absent in [false,true] {
            let mut input = seed(); input.revision = revision;
            if absent { input.fast_statistics_available = false; input.evidence_lane = None;
                input.last_evidence = None; input.freshness.minimum = None; }
            let mut want = input; want.revision = next; want.fast_statistics_available = false;
            want.evidence_lane = None; want.last_evidence = None; want.freshness.minimum = None;
            success(input, request(105), want, Some(12), 0);
        }
    }
}
#[test]
fn product_owner_zero_clock_activate_retains_three_typed_guards_but_owns_revision_even_when_noop() {
    for guard in 0..4 {
        let mut input = seed(); let mut req = request(106); req.generation = 17; req.show = 23;
        match guard { 1 => req.generation = 18, 2 => req.show = 24,
            3 => input.policy.floor_reserved = false, _ => {} }
        let mut want = input; want.revision = 0;
        if guard == 0 { want.policy.floor_active = true; }
        success(input, req, want, None, 0);
    }
}
#[test]
fn product_owner_zero_clock_resume_two_cuts_preserve_distinct_revision_and_all_opaque_tail_atoms() {
    for (op, revision) in [(107,u64::MAX), (108,0)] {
        for absent in [false,true] {
            let mut input = seed();
            if absent { input.policy.promotion = None; input.policy.resume_restoration = None; }
            let mut want = input; want.policy.promotion = None; want.policy.resume_restoration = None;
            want.revision = revision; success(input, request(op), want, Some(2), 0);
        }
    }
}
#[test]
fn product_owner_zero_clock_collector_truth_table_never_invents_availability_or_changes_revision() {
    for fast in [false,true] { for source in [false,true] { for context_absent in [false,true] {
        let mut input = seed(); input.fast_statistics_available = fast;
        let mut req = request(109); req.capture_source_present = source as u32;
        req.resume_context_absent = context_absent as u32;
        let mut want = input; if !source { want.fast_statistics_available = false; }
        success(input, req, want, None, (source && context_absent) as u32);
    } } }
}
#[test]
fn product_owner_zero_clock_policy_and_clock_operations_are_closed_before_state_decode() {
    let atoms = snapshot(seed());
    for op in [0,1,101,102,103,104,110,202,501,601,u32::MAX] {
        let req = request(op); deny(&atoms, &req, |_| {});
        // Initialized request alone suffices for this deny; no state is read.
        deny(&atoms, &req, |a| { a.header = ptr::null(); a.atoms = ptr::null(); });
    }
}
#[test]
fn product_owner_zero_clock_request_shape_and_all179_malformed_atoms_are_denied_without_writes() {
    let atoms = snapshot(seed());
    for op in 105..=109 {
        for field in 0..6 {
            let mut req = request(op);
            match field { 0 => req.abi = 2, 1 => req.invocation = 0,
                2 => { if op == 106 { continue; } req.generation = 1; },
                3 => { if op == 106 { continue; } req.show = 1; },
                4 => req.capture_source_present = 2, _ => req.resume_context_absent = 2 }
            deny(&atoms, &req, |_| {});
        }
        for i in 0..179 {
            let mut wrong = atoms; wrong[i].kind = u32::MAX;
            deny(&wrong, &request(op), |_| {});
        }
    }
}
#[test]
fn product_owner_zero_clock_bad_headers_and_result_replay_are_denied_without_writes() {
    let atoms = snapshot(seed());
    let mut headers = vec![RESULT];
    for value in [0, 2, u32::MAX] { headers.push(Header { abi: value, ..HEADER }); }
    for value in [0, 1, 3, u32::MAX] { headers.push(Header { domain: value, ..HEADER }); }
    for value in [0, 3, u32::MAX] { headers.push(Header { phase: value, ..HEADER }); }
    for value in [0, 178, 180, u32::MAX] { headers.push(Header { count: value, ..HEADER }); }
    for header in headers {
        for operation in 105..=109 {
            let req = request(operation); let header_before = header;
            let atoms_before = atoms; let req_before = req;
            let mut out = Output::sentinel(); let before = out.clone();
            assert_eq!(unsafe { Args::new(&req, &header, &atoms, &mut out).run() }, 2);
            assert_eq!(out, before, "all six denied output objects untouched");
            assert_eq!(header, header_before, "input header unchanged");
            assert_eq!(atoms, atoms_before, "all179 input atoms unchanged");
            assert_eq!(req, req_before, "input request unchanged");
        }
    }
}
#[test]
fn product_owner_zero_clock_null_alignment_overlap_and_every_count_are_closed() {
    let atoms = snapshot(seed()); let req = request(105);
    for field in 0..9 {
        deny(&atoms, &req, |a| match field {
            0 => a.req = ptr::null(), 1 => a.header = ptr::null(), 2 => a.atoms = ptr::null(),
            3 => a.oh = ptr::null_mut(), 4 => a.oa = ptr::null_mut(), 5 => a.meta = ptr::null_mut(),
            6 => a.edits = ptr::null_mut(), 7 => a.times = ptr::null_mut(), _ => a.reads = ptr::null_mut(),
        });
    }
    for value in [0,1,12,14,16,178,180,u32::MAX] { for field in 0..5 {
        deny(&atoms, &req, |a| match field { 0 => a.count = value, 1 => a.oc = value,
            2 => a.ec = value, 3 => a.tc = value, _ => a.rc = value });
    } }
    deny(&atoms, &req, |a| a.req = (a.req as usize + 1) as *const RawOwnerEventRequest);
    deny(&atoms, &req, |a| a.atoms = (a.atoms as usize + 1) as *const Atom);
    deny(&atoms, &req, |a| a.oa = (a.oa as usize + 1) as *mut Atom);
    deny(&atoms, &req, |a| a.oa = a.atoms.cast_mut());
    deny(&atoms, &req, |a| a.oh = a.header.cast_mut());
    deny(&atoms, &req, |a| a.times = a.edits.cast::<Time>());
}
