// Independent, synthetic TRANSPORT fixtures. No fixture is a captured native owner,
// runnable RTT admission, effect capability, or completed product integration.
// Include this file from a new ordinary integration test. All semantic stored fields
// and wire atoms below are literal; only private invocation journals use their fresh
// snapshot default. Do not replace these literals with the production encoder.
use beluga_core::network_adaptation_candidate as candidate;
use candidate::*;
use candidate::state_codec::*;
use beluga_core::rtt_evidence::{RawMeasurement, RawState};

const fn atom(kind: u32, present: u32, high: i64, low: u64) -> Atom {
    Atom { kind, present, high, low }
}

// Independent index ledger: comments name the corresponding typed field. Required
// boolean container tags use present=1 even when their boolean payload is false.
const GOLDEN_POLICY_ATOMS: [Atom; 168] = [
    atom(2,1,0,1000), // 0 configured_cap
    atom(2,1,0,1001), // 1 maximum_tier_video
    atom(2,1,0,1002), // 2 base_fps
    atom(1,1,0,10003), // 3 peer
    atom(7,1,0,5), // 4 tier Survival
    atom(2,1,0,1005), // 5 healthy_upgrades
    atom(2,1,0,1006), // 6 bandwidth_downgrades
    atom(2,1,0,1007), // 7 unavailable_samples
    atom(2,1,0,1008), // 8 positive_bootstrap
    atom(2,1,0,1009), // 9 limited_upgrades
    atom(2,1,0,1010), // 10 probe_healthy
    atom(2,1,0,1011), // 11 probe_grace
    atom(10,1,0,1000012), // 12 probe_deadline
    atom(2,1,0,1013), // 13 probe_cooldown
    atom(2,1,0,1014), // 14 probe_failures
    atom(4,1,0,1), // 15 below_reserve_disproved
    atom(4,1,0,1), // 16 resume_restoration container
    atom(4,1,0,0), // 17 restoration.disproved
    atom(2,1,0,1018), // 18 restoration.cooldown
    atom(2,1,0,1019), // 19 restoration.failures
    atom(7,1,0,3), // 20 probe_origin Constrained
    atom(7,1,0,4), // 21 probe_best Critical
    atom(7,1,0,6), // 22 probe_confirmed Emergency
    atom(10,1,0,1000023), // 23 probe_qualification_at
    atom(2,1,0,1024), // 24 probe_maximum
    atom(4,1,0,1), // 25 promotion container
    atom(7,1,0,1), // 26 promotion.tier High
    atom(2,1,0,1027), // 27 promotion.maximum_total
    atom(10,1,0,1000028), // 28 promotion.deadline
    atom(2,1,0,1029), // 29 suspension_pressure
    atom(2,1,0,1030), // 30 stable_resume
    atom(2,1,0,1031), // 31 maximum_resume
    atom(4,1,0,0), // 32 bandwidth_unavailable
    atom(4,1,0,1), // 33 last_latency_pressure
    atom(4,1,0,0), // 34 last_positive_suspension_pressure
    atom(3,1,0,0x7ff8_0000_0000_0023), // 35 last_average_delay
    atom(1,1,0,10036), // 36 queue.packets
    atom(3,1,0,0x7ff8_0000_0000_0025), // 37 queue.delay_bits
    atom(2,1,0,1038), // 38 queue.pressure_count
    atom(10,1,0,1000039), // 39 queue.low_observation
    atom(10,1,0,1000040), // 40 queue.soft_observation
    atom(4,1,0,1), // 41 queue.faulted
    atom(6,1,0,20042), // 42 rtt.raw.abi_version (opaque)
    atom(6,1,0,20043), // 43 reserved
    atom(6,1,0,20044), // 44 baseline_present
    atom(6,1,0,20045), // 45 bootstrap_count
    atom(6,1,0,20046), // 46 disposition
    atom(6,1,0,20047), // 47 health
    atom(6,1,0,20048), // 48 uses_native
    atom(6,1,0,20049), // 49 provisional
    atom(6,1,0,20050), // 50 permits_initial
    atom(6,1,0,20051), // 51 distinct_count
    atom(6,1,0,20052), // 52 last_measured_present
    atom(6,1,0,20053), // 53 advancement_present
    atom(6,1,0,20054), // 54 age_present
    atom(6,1,0,20055), // 55 watermark_present
    atom(6,1,0,20056), // 56 fence_present
    atom(6,1,0,20057), // 57 fence_current_present
    atom(6,1,0,20058), // 58 reserved2
    atom(6,1,0,20059), // 59 reserved3
    atom(3,1,0,0x7ff8_0000_0000_003c), // 60 baseline_bits
    atom(3,1,0,0x7ff8_0000_0000_003d), // 61 last_measured_bits
    atom(3,1,0,0x7ff8_0000_0000_003e), // 62 bootstrap_bits[0]
    atom(3,1,0,0x7ff8_0000_0000_003f), // 63 bootstrap_bits[1]
    atom(3,1,0,0x7ff8_0000_0000_0040), // 64 bootstrap_bits[2]
    atom(2,1,0,1065), // 65 age_seconds
    atom(2,1,0,1066), // 66 age_attoseconds
    atom(1,1,0,10067), // 67 watermark.fingerprint_words[0]
    atom(1,1,0,10068),
    atom(1,1,0,10069),
    atom(1,1,0,10070),
    atom(1,1,0,10071),
    atom(1,1,0,10072),
    atom(1,1,0,10073),
    atom(1,1,0,10074), // 74 watermark.fingerprint_words[7]
    atom(3,1,0,0x7ff8_0000_0000_004b), // 75 watermark.total_bits
    atom(1,1,0,10076), // 76 watermark.responses
    atom(1,1,0,10077), // 77 fence.fingerprint_words[0]
    atom(1,1,0,10078),
    atom(1,1,0,10079),
    atom(1,1,0,10080),
    atom(1,1,0,10081),
    atom(1,1,0,10082),
    atom(1,1,0,10083),
    atom(1,1,0,10084), // 84 fence.fingerprint_words[7]
    atom(3,1,0,0x7ff8_0000_0000_0055), // 85 fence.total_bits
    atom(1,1,0,10086), // 86 fence.responses
    atom(3,1,0,0x7ff8_0000_0000_0057), // 87 fence_current_bits
    atom(10,1,0,1000088), // 88 rtt.last_advancement
    atom(4,1,0,0), // 89 rtt.faulted
    atom(6,1,0,20090), // 90 demand.configured_cap
    atom(2,1,0,1091), // 91 profile[0].baseline_video
    atom(2,1,0,1092),
    atom(2,1,0,1093),
    atom(2,1,0,1094),
    atom(3,1,0,0x7ff8_0000_0000_005f),
    atom(2,1,0,1096), // 96 profile[0].next_direct
    atom(2,1,0,1097), // 97 profile[1].baseline_video
    atom(2,1,0,1098),
    atom(2,1,0,1099),
    atom(2,1,0,1100),
    atom(3,1,0,0x7ff8_0000_0000_0065),
    atom(2,1,0,1102),
    atom(2,1,0,1103), // 103 profile[2].baseline_video
    atom(2,1,0,1104),
    atom(2,1,0,1105),
    atom(2,1,0,1106),
    atom(3,1,0,0x7ff8_0000_0000_006b),
    atom(2,1,0,1108),
    atom(2,1,0,1109), // 109 profile[3].baseline_video
    atom(2,1,0,1110),
    atom(2,1,0,1111),
    atom(2,1,0,1112),
    atom(3,1,0,0x7ff8_0000_0000_0071),
    atom(2,1,0,1114),
    atom(2,1,0,1115), // 115 profile[4].baseline_video
    atom(2,1,0,1116),
    atom(2,1,0,1117),
    atom(2,1,0,1118),
    atom(3,1,0,0x7ff8_0000_0000_0077),
    atom(2,1,0,1120),
    atom(2,1,0,1121), // 121 profile[5].baseline_video
    atom(2,1,0,1122),
    atom(2,1,0,1123),
    atom(2,1,0,1124),
    atom(3,1,0,0x7ff8_0000_0000_007d),
    atom(2,1,0,1126),
    atom(2,1,0,1127), // 127 profile[6].baseline_video
    atom(2,1,0,1128),
    atom(2,1,0,1129),
    atom(2,1,0,1130),
    atom(3,1,0,0x7ff8_0000_0000_0083),
    atom(2,1,0,1132),
    atom(2,1,0,1133), // 133 profile[7].baseline_video
    atom(2,1,0,1134),
    atom(2,1,0,1135),
    atom(2,1,0,1136),
    atom(3,1,0,0x7ff8_0000_0000_0089),
    atom(2,1,0,1138),
    atom(5,1,0,250), // 139 profiles_count (opaque u8)
    atom(4,1,0,1), // 140 demand.faulted
    atom(5,1,0,251), // 141 demand.initial (opaque u8)
    atom(2,1,0,1142), // 142 demand.maximum_video
    atom(1,1,0,10143), // 143 consumed_sequence
    atom(4,1,0,0), // 144 route_present
    atom(4,1,0,1), // 145 capacity_sample container
    atom(1,1,0,10146), // 146 capacity_sample.packets
    atom(3,1,0,0x7ff8_0000_0000_0093), // 147 capacity_sample.delay
    atom(3,1,0,0x7ff8_0000_0000_0094), // 148 capacity_bandwidth_high
    atom(3,1,0,0x7ff8_0000_0000_0095), // 149 capacity_timestamp
    atom(1,1,0,10150), // 150 capacity_sequence
    atom(4,1,0,1), // 151 capacity_growth_veto
    atom(1,1,0,10152), // 152 floor_show
    atom(4,1,0,0), // 153 floor_reserved
    atom(4,1,0,1), // 154 floor_active
    atom(4,1,0,0), // 155 floor_attempt_consumed
    atom(4,1,0,1), // 156 floor_probe_cancelled
    atom(3,1,0,0x7ff8_0000_0000_009d), // 157 floor_seed
    atom(4,1,0,1), // 158 floor_first_witness container
    atom(10,1,0,1000159), // 159 witness.observed_at
    atom(3,1,0,0x7ff8_0000_0000_00a0), // 160 witness.bandwidth
    atom(1,1,0,10161), // 161 floor_regular_sequence
    atom(3,1,0,0x7ff8_0000_0000_00a2), // 162 floor_regular_timestamp
    atom(10,1,0,1000163), // 163 floor_cooldown_at
    atom(1,1,0,10164), // 164 startup_peer
    atom(1,1,0,10165), // 165 startup_show
    atom(4,1,0,0), // 166 startup_disproved
    atom(10,1,0,1000167), // 167 startup_sparse_deadline
];
const GOLDEN_OWNER_TAIL: [Atom; 11] = [
    atom(1,1,0,10168), // 168 revision
    atom(4,1,0,1), // 169 fast_statistics_available
    atom(8,1,0,1), // 170 evidence_lane OrdinaryFallback
    atom(10,1,0,1000171), // 171 last_evidence
    atom(1,1,0,10172), // 172 freshness.minimum
    atom(4,1,0,1), // 173 applied container
    atom(7,1,0,2), // 174 applied.tier Balanced
    atom(2,1,0,1175), // 175 applied.maximum_video
    atom(2,1,0,1176), // 176 applied.maximum_total
    atom(2,1,0,1177), // 177 applied.fps
    atom(3,1,0,0x7ff8_0000_0000_00b2), // 178 applied.scale
];
const GOLDEN_CADENCE_ATOMS: [Atom; 5] = [
    atom(10,1,0,2000000), atom(10,1,0,2000001), atom(4,1,0,1),
    atom(9,1,0,1), atom(10,1,0,2000004),
];

fn literal_policy() -> Wire {
    Wire { header: Header { abi: 1, domain: 1, phase: 1, count: 168 }, atoms: GOLDEN_POLICY_ATOMS.to_vec() }
}
fn literal_owner() -> Wire {
    let mut atoms = GOLDEN_POLICY_ATOMS.to_vec();
    atoms.extend_from_slice(&GOLDEN_OWNER_TAIL);
    Wire { header: Header { abi: 1, domain: 2, phase: 1, count: 179 }, atoms }
}
fn literal_cadence() -> Wire {
    Wire { header: Header { abi: 1, domain: 3, phase: 1, count: 5 }, atoms: GOLDEN_CADENCE_ATOMS.to_vec() }
}

fn sentinel_owner() -> Owner {
    Owner {
        times: Default::default(),
        policy: Policy {
            times: Default::default(), configured_cap: 1000, maximum_tier_video: 1001, base_fps: 1002,
            peer: Some(10003), tier: Tier::Survival, healthy_upgrades: 1005,
            bandwidth_downgrades: 1006, unavailable_samples: 1007, positive_bootstrap: 1008,
            limited_upgrades: 1009, probe_healthy: 1010, probe_grace: 1011,
            probe_deadline: Some(1000012), probe_cooldown: 1013, probe_failures: 1014,
            below_reserve_disproved: true,
            resume_restoration: Some(Restoration { disproved: false, cooldown: 1018, failures: 1019 }),
            probe_origin: Some(Tier::Constrained), probe_best: Some(Tier::Critical),
            probe_confirmed: Some(Tier::Emergency), probe_qualification_at: Some(1000023),
            probe_maximum: Some(1024),
            promotion: Some(Promotion { tier: Tier::High, maximum_total: 1027, deadline: 1000028 }),
            suspension_pressure: 1029, stable_resume: 1030, maximum_resume: 1031,
            bandwidth_unavailable: false, last_latency_pressure: true,
            last_positive_suspension_pressure: false, last_average_delay: Some(Scalar(0x7ff8_0000_0000_0023)),
            queue: PacketQueue {
                times: Default::default(), packets: Some(10036), delay_bits: Some(0x7ff8_0000_0000_0025),
                pressure_count: 1038, low_observation: Some(1000039), soft_observation: Some(1000040), faulted: true,
            },
            rtt: RoundTripTime {
                times: Default::default(),
                raw: RawState {
                    abi_version: 20042, reserved: 20043, baseline_present: 20044, bootstrap_count: 20045,
                    disposition: 20046, health: 20047, uses_native: 20048, provisional: 20049,
                    permits_initial: 20050, distinct_count: 20051, last_measured_present: 20052,
                    advancement_present: 20053, age_present: 20054, watermark_present: 20055,
                    fence_present: 20056, fence_current_present: 20057, reserved2: 20058, reserved3: 20059,
                    baseline_bits: 0x7ff8_0000_0000_003c, last_measured_bits: 0x7ff8_0000_0000_003d,
                    bootstrap_bits: [0x7ff8_0000_0000_003e,0x7ff8_0000_0000_003f,0x7ff8_0000_0000_0040],
                    age_seconds: 1065, age_attoseconds: 1066,
                    watermark: RawMeasurement {
                        fingerprint_words: [10067,10068,10069,10070,10071,10072,10073,10074],
                        total_bits: 0x7ff8_0000_0000_004b, responses: 10076,
                    },
                    fence: RawMeasurement {
                        fingerprint_words: [10077,10078,10079,10080,10081,10082,10083,10084],
                        total_bits: 0x7ff8_0000_0000_0055, responses: 10086,
                    },
                    fence_current_bits: 0x7ff8_0000_0000_0057,
                },
                last_advancement: Some(1000088), faulted: false,
            },
            demand: TierDemand {
                configured_cap: 20090,
                profiles: [
                    Profile { baseline_video:1091,maximum_video:1092,maximum_total:1093,minimum_sustainable:1094,required:Scalar(0x7ff8_0000_0000_005f),next_direct:Some(1096) },
                    Profile { baseline_video:1097,maximum_video:1098,maximum_total:1099,minimum_sustainable:1100,required:Scalar(0x7ff8_0000_0000_0065),next_direct:Some(1102) },
                    Profile { baseline_video:1103,maximum_video:1104,maximum_total:1105,minimum_sustainable:1106,required:Scalar(0x7ff8_0000_0000_006b),next_direct:Some(1108) },
                    Profile { baseline_video:1109,maximum_video:1110,maximum_total:1111,minimum_sustainable:1112,required:Scalar(0x7ff8_0000_0000_0071),next_direct:Some(1114) },
                    Profile { baseline_video:1115,maximum_video:1116,maximum_total:1117,minimum_sustainable:1118,required:Scalar(0x7ff8_0000_0000_0077),next_direct:Some(1120) },
                    Profile { baseline_video:1121,maximum_video:1122,maximum_total:1123,minimum_sustainable:1124,required:Scalar(0x7ff8_0000_0000_007d),next_direct:Some(1126) },
                    Profile { baseline_video:1127,maximum_video:1128,maximum_total:1129,minimum_sustainable:1130,required:Scalar(0x7ff8_0000_0000_0083),next_direct:Some(1132) },
                    Profile { baseline_video:1133,maximum_video:1134,maximum_total:1135,minimum_sustainable:1136,required:Scalar(0x7ff8_0000_0000_0089),next_direct:Some(1138) },
                ], profiles_count: 250, faulted: true, initial: 251, maximum_video: 1142,
            },
            consumed_sequence: Some(10143), route_present: false,
            capacity_sample: Some(CapacitySample { packets: Some(10146), delay: Some(Scalar(0x7ff8_0000_0000_0093)) }),
            capacity_bandwidth_high: Some(Scalar(0x7ff8_0000_0000_0094)), capacity_timestamp: Some(Scalar(0x7ff8_0000_0000_0095)),
            capacity_sequence: Some(10150), capacity_growth_veto: true, floor_show: Some(10152),
            floor_reserved: false, floor_active: true, floor_attempt_consumed: false, floor_probe_cancelled: true,
            floor_seed: Some(Scalar(0x7ff8_0000_0000_009d)),
            floor_first_witness: Some(FloorWitness { observed_at: 1000159, bandwidth: Scalar(0x7ff8_0000_0000_00a0) }),
            floor_regular_sequence: Some(10161), floor_regular_timestamp: Some(Scalar(0x7ff8_0000_0000_00a2)),
            floor_cooldown_at: Some(1000163), startup_peer: Some(10164), startup_show: Some(10165),
            startup_disproved: false, startup_sparse_deadline: Some(1000167),
        },
        revision: 10168, fast_statistics_available: true, evidence_lane: Some(EvidenceLane::OrdinaryFallback),
        last_evidence: Some(1000171), freshness: Freshness { minimum: Some(10172) },
        applied: Some(Recommendation { tier: Tier::Balanced, maximum_video: 1175, maximum_total: 1176,
            fps: 1177, scale: Scalar(0x7ff8_0000_0000_00b2) }),
    }
}
fn sentinel_cadence() -> Cadence {
    Cadence { times: Default::default(), next_regular: 2000000, next_capacity: Some(2000001),
        capacity_enabled: true, in_flight: Some(Sample::CapacityOnly), latest: 2000004 }
}

fn assert_owner_wire(owner: Owner, expected: &Wire, label: &str) {
    assert_eq!(encode_owner_snapshot(owner).expect("fresh literal owner"), *expected, "{label}: owner encoding");
    let decoded = decode_owner_snapshot(expected.header, &expected.atoms).expect("literal owner decoding");
    assert_eq!(encode_owner_snapshot(decoded).expect("decoded fresh owner"), *expected, "{label}: decoded owner encoding");
}
fn assert_cadence_wire(cadence: Cadence, expected: &Wire, label: &str) {
    assert_eq!(encode_cadence_snapshot(cadence).expect("fresh literal cadence"), *expected, "{label}: cadence encoding");
    let decoded = decode_cadence_snapshot(expected.header, &expected.atoms).expect("literal cadence decoding");
    assert_eq!(encode_cadence_snapshot(decoded).expect("decoded fresh cadence"), *expected, "{label}: decoded cadence encoding");
}

#[test]
fn golden_exhaustive_owner_policy_and_cadence_match_independent_literal_atoms() {
    assert_eq!(GOLDEN_POLICY_ATOMS.len(),168);
    assert_eq!(GOLDEN_OWNER_TAIL.len(),11);
    assert_eq!(encode_policy_snapshot(sentinel_owner().policy).unwrap(),literal_policy());
    assert_owner_wire(sentinel_owner(),&literal_owner(),"all179");
    assert_cadence_wire(sentinel_cadence(),&literal_cadence(),"all5");
}

#[test]
fn golden_literal_decode_has_named_fields_not_paired_swap_or_omission_credit() {
    let wire=literal_owner();let owner=decode_owner_snapshot(wire.header,&wire.atoms).unwrap();let p=owner.policy;
    assert_eq!((p.configured_cap,p.maximum_tier_video,p.base_fps),(1000,1001,1002));
    assert_eq!((p.peer,p.tier),(Some(10003),Tier::Survival));
    assert_eq!((p.healthy_upgrades,p.bandwidth_downgrades,p.unavailable_samples,p.positive_bootstrap),(1005,1006,1007,1008));
    assert_eq!((p.limited_upgrades,p.probe_healthy,p.probe_grace,p.probe_cooldown,p.probe_failures),(1009,1010,1011,1013,1014));
    assert_eq!((p.probe_origin,p.probe_best,p.probe_confirmed),(Some(Tier::Constrained),Some(Tier::Critical),Some(Tier::Emergency)));
    assert_eq!(p.probe_maximum, Some(1024), "named decode probe maximum");
    assert_eq!(p.resume_restoration,Some(Restoration{disproved:false,cooldown:1018,failures:1019}));
    assert_eq!(p.promotion,Some(Promotion{tier:Tier::High,maximum_total:1027,deadline:1000028}));
    assert_eq!((p.suspension_pressure,p.stable_resume,p.maximum_resume),(1029,1030,1031));
    assert_eq!((p.below_reserve_disproved,p.bandwidth_unavailable,p.last_latency_pressure,p.last_positive_suspension_pressure),(true,false,true,false));
    assert_eq!((p.queue.packets,p.queue.delay_bits,p.queue.pressure_count,p.queue.faulted),(Some(10036),Some(0x7ff8_0000_0000_0025),1038,true));
    assert_eq!((p.consumed_sequence,p.capacity_sequence,p.floor_show,p.floor_regular_sequence),(Some(10143),Some(10150),Some(10152),Some(10161)));
    assert_eq!((p.route_present,p.capacity_growth_veto,p.floor_reserved,p.floor_active,p.floor_attempt_consumed,p.floor_probe_cancelled,p.startup_disproved),(false,true,false,true,false,true,false));
    assert_eq!((p.startup_peer,p.startup_show),(Some(10164),Some(10165)),"same-typed startup fields must not swap");
    assert_eq!(p.capacity_sample.unwrap().packets,Some(10146));
    assert_eq!(p.capacity_sample.unwrap().delay.unwrap().0,0x7ff8_0000_0000_0093);
    assert_eq!(p.floor_first_witness.unwrap().bandwidth.0,0x7ff8_0000_0000_00a0);
    assert_eq!((p.last_average_delay.unwrap().0,p.capacity_bandwidth_high.unwrap().0,p.capacity_timestamp.unwrap().0,p.floor_seed.unwrap().0,p.floor_regular_timestamp.unwrap().0),
        (0x7ff8_0000_0000_0023,0x7ff8_0000_0000_0094,0x7ff8_0000_0000_0095,0x7ff8_0000_0000_009d,0x7ff8_0000_0000_00a2));
    assert_eq!((p.probe_deadline,p.probe_qualification_at,p.floor_cooldown_at,p.startup_sparse_deadline),(Some(1000012),Some(1000023),Some(1000163),Some(1000167)));
    assert_eq!((p.queue.low_observation,p.queue.soft_observation,p.rtt.last_advancement),(Some(1000039),Some(1000040),Some(1000088)));
    assert_eq!(p.floor_first_witness.unwrap().observed_at,1000159);
    assert_eq!((owner.revision,owner.fast_statistics_available,owner.evidence_lane,owner.last_evidence,owner.freshness.minimum),
        (10168,true,Some(EvidenceLane::OrdinaryFallback),Some(1000171),Some(10172)));
    let applied=owner.applied.unwrap();
    assert_eq!((applied.tier,applied.maximum_video,applied.maximum_total,applied.fps,applied.scale.0),
        (Tier::Balanced,1175,1176,1177,0x7ff8_0000_0000_00b2));
    // Raw DTO equality is bitwise and includes every opaque reserved/presence/body word.
    assert_eq!(p.rtt.raw,sentinel_owner().policy.rtt.raw);
    assert!(!p.rtt.faulted);
    assert_eq!((p.demand.configured_cap,p.demand.profiles_count,p.demand.faulted,p.demand.initial,p.demand.maximum_video),(20090,250,true,251,1142));
    let cadence_wire=literal_cadence();let c=decode_cadence_snapshot(cadence_wire.header,&cadence_wire.atoms).unwrap();
    assert_eq!((c.next_regular,c.next_capacity,c.capacity_enabled,c.in_flight,c.latest),(2000000,Some(2000001),true,Some(Sample::CapacityOnly),2000004));
}

// All typed Options with ancestors present: Policy24 + sample2 + profiles8 +
// Queue4 + RTT1 + Owner4 + Cadence2 =45. Composite containers are boolean words;
// their payload children have explicit absent atoms when the container is false.
const OPTION_NAMES: [&str;45]=[
    "peer","probe_deadline","restoration","origin","best","confirmed","qualification","maximum","promotion","average",
    "consumed_sequence","capacity_sample","capacity_bandwidth","capacity_timestamp","capacity_sequence","floor_show","floor_seed","witness","floor_sequence","floor_timestamp","floor_cooldown","startup_peer","startup_show","sparse",
    "sample.packets","sample.delay","profile0.next","profile1.next","profile2.next","profile3.next","profile4.next","profile5.next","profile6.next","profile7.next",
    "queue.packets","queue.delay","queue.low","queue.soft","rtt.advancement","evidence_lane","evidence_time","freshness","applied","cadence.capacity","cadence.in_flight",
];
const OPTION_INDEX: [usize;45]=[3,12,16,20,21,22,23,24,25,35,143,145,148,149,150,152,157,158,161,162,163,164,165,167,146,147,96,102,108,114,120,126,132,138,36,37,39,40,88,170,171,172,173,1,3];
fn set_option(owner:&mut Owner,cadence:&mut Cadence,case:usize,present:bool) {
    let p=&mut owner.policy;
    match case {
        0=>p.peer=present.then_some(0),1=>p.probe_deadline=present.then_some(0),
        2=>p.resume_restoration=present.then_some(Restoration{disproved:false,cooldown:0,failures:0}),
        3=>p.probe_origin=present.then_some(Tier::Full),4=>p.probe_best=present.then_some(Tier::Full),5=>p.probe_confirmed=present.then_some(Tier::Full),
        6=>p.probe_qualification_at=present.then_some(0),7=>p.probe_maximum=present.then_some(0),
        8=>p.promotion=present.then_some(Promotion{tier:Tier::Full,maximum_total:0,deadline:0}),
        9=>p.last_average_delay=present.then_some(Scalar(0)),10=>p.consumed_sequence=present.then_some(0),
        11=>p.capacity_sample=present.then_some(CapacitySample{packets:Some(0),delay:Some(Scalar(0))}),
        12=>p.capacity_bandwidth_high=present.then_some(Scalar(0)),13=>p.capacity_timestamp=present.then_some(Scalar(0)),
        14=>p.capacity_sequence=present.then_some(0),15=>p.floor_show=present.then_some(0),16=>p.floor_seed=present.then_some(Scalar(0)),
        17=>p.floor_first_witness=present.then_some(FloorWitness{observed_at:0,bandwidth:Scalar(0)}),
        18=>p.floor_regular_sequence=present.then_some(0),19=>p.floor_regular_timestamp=present.then_some(Scalar(0)),
        20=>p.floor_cooldown_at=present.then_some(0),21=>p.startup_peer=present.then_some(0),22=>p.startup_show=present.then_some(0),23=>p.startup_sparse_deadline=present.then_some(0),
        24=>p.capacity_sample.as_mut().unwrap().packets=present.then_some(0),25=>p.capacity_sample.as_mut().unwrap().delay=present.then_some(Scalar(0)),
        26..=33=>p.demand.profiles[case-26].next_direct=present.then_some(0),
        34=>p.queue.packets=present.then_some(0),35=>p.queue.delay_bits=present.then_some(0),36=>p.queue.low_observation=present.then_some(0),37=>p.queue.soft_observation=present.then_some(0),38=>p.rtt.last_advancement=present.then_some(0),
        39=>owner.evidence_lane=present.then_some(EvidenceLane::FastSender),40=>owner.last_evidence=present.then_some(0),41=>owner.freshness.minimum=present.then_some(0),
        42=>owner.applied=present.then_some(Recommendation{tier:Tier::Full,maximum_video:0,maximum_total:0,fps:0,scale:Scalar(0)}),
        43=>cadence.next_capacity=present.then_some(0),44=>cadence.in_flight=present.then_some(Sample::Regular),
        _=>panic!("closed option case"),
    }
}
fn option_present(owner:&Owner,cadence:&Cadence,case:usize)->bool {
    let p=&owner.policy;
    match case {
        0=>p.peer.is_some(),1=>p.probe_deadline.is_some(),2=>p.resume_restoration.is_some(),3=>p.probe_origin.is_some(),4=>p.probe_best.is_some(),5=>p.probe_confirmed.is_some(),
        6=>p.probe_qualification_at.is_some(),7=>p.probe_maximum.is_some(),8=>p.promotion.is_some(),9=>p.last_average_delay.is_some(),10=>p.consumed_sequence.is_some(),11=>p.capacity_sample.is_some(),
        12=>p.capacity_bandwidth_high.is_some(),13=>p.capacity_timestamp.is_some(),14=>p.capacity_sequence.is_some(),15=>p.floor_show.is_some(),16=>p.floor_seed.is_some(),17=>p.floor_first_witness.is_some(),
        18=>p.floor_regular_sequence.is_some(),19=>p.floor_regular_timestamp.is_some(),20=>p.floor_cooldown_at.is_some(),21=>p.startup_peer.is_some(),22=>p.startup_show.is_some(),23=>p.startup_sparse_deadline.is_some(),
        24=>p.capacity_sample.unwrap().packets.is_some(),25=>p.capacity_sample.unwrap().delay.is_some(),26..=33=>p.demand.profiles[case-26].next_direct.is_some(),
        34=>p.queue.packets.is_some(),35=>p.queue.delay_bits.is_some(),36=>p.queue.low_observation.is_some(),37=>p.queue.soft_observation.is_some(),38=>p.rtt.last_advancement.is_some(),
        39=>owner.evidence_lane.is_some(),40=>owner.last_evidence.is_some(),41=>owner.freshness.minimum.is_some(),42=>owner.applied.is_some(),43=>cadence.next_capacity.is_some(),44=>cadence.in_flight.is_some(),_=>panic!("closed option case"),
    }
}
fn composite_children(index:usize)->Option<&'static[usize]> {
    match index {16=>Some(&[17,18,19]),25=>Some(&[26,27,28]),145=>Some(&[146,147]),158=>Some(&[159,160]),173=>Some(&[174,175,176,177,178]),_=>None}
}
fn literal_option(wire:&mut Wire,index:usize,present:bool) {
    if let Some(children)=composite_children(index) {
        wire.atoms[index].low=present as u64;
        for &child in children { wire.atoms[child].present=present as u32;wire.atoms[child].high=0;wire.atoms[child].low=0; }
    } else {
        wire.atoms[index].present=present as u32;wire.atoms[index].high=0;wire.atoms[index].low=0;
    }
}

#[test]
fn golden_all_45_options_distinguish_none_some_zero_and_original_nonzero() {
    assert_eq!(OPTION_NAMES.len(),45);assert_eq!(OPTION_INDEX.len(),45);
    for case in 0..45 {
        assert!(option_present(&sentinel_owner(),&sentinel_cadence(),case),"original {}",OPTION_NAMES[case]);
        for present in [false,true] {
            let mut owner=sentinel_owner();let mut cadence=sentinel_cadence();
            set_option(&mut owner,&mut cadence,case,present);
            if case<43 {
                let mut expected=literal_owner();literal_option(&mut expected,OPTION_INDEX[case],present);
                assert_owner_wire(owner,&expected,OPTION_NAMES[case]);
                let decoded=decode_owner_snapshot(expected.header,&expected.atoms).unwrap();
                assert_eq!(option_present(&decoded,&cadence,case),present,"decoded {}",OPTION_NAMES[case]);
            } else {
                let mut expected=literal_cadence();literal_option(&mut expected,OPTION_INDEX[case],present);
                assert_cadence_wire(cadence,&expected,OPTION_NAMES[case]);
                let decoded=decode_cadence_snapshot(expected.header,&expected.atoms).unwrap();
                assert_eq!(option_present(&owner,&decoded,case),present,"decoded {}",OPTION_NAMES[case]);
            }
        }
    }
}

#[test]
fn golden_present_empty_capacity_sample_is_not_absence() {
    let mut owner=sentinel_owner();owner.policy.capacity_sample=Some(CapacitySample{packets:None,delay:None});
    let mut wire=literal_owner();wire.atoms[146]=atom(1,0,0,0);wire.atoms[147]=atom(3,0,0,0);
    assert_owner_wire(owner,&wire,"present empty sample");
    let decoded=decode_owner_snapshot(wire.header,&wire.atoms).unwrap();
    let sample=decoded.policy.capacity_sample.expect("container survives empty children");
    assert_eq!(sample.packets,None);assert!(sample.delay.is_none());assert_eq!(wire.atoms[145],atom(4,1,0,1));
}

const BOOL_INDEX:[usize;17]=[15,17,32,33,34,41,89,140,144,151,153,154,155,156,166,169,2];
fn set_bool(owner:&mut Owner,cadence:&mut Cadence,case:usize,value:bool) {
    let p=&mut owner.policy;
    match case {0=>p.below_reserve_disproved=value,1=>p.resume_restoration.as_mut().unwrap().disproved=value,
        2=>p.bandwidth_unavailable=value,3=>p.last_latency_pressure=value,4=>p.last_positive_suspension_pressure=value,
        5=>p.queue.faulted=value,6=>p.rtt.faulted=value,7=>p.demand.faulted=value,8=>p.route_present=value,
        9=>p.capacity_growth_veto=value,10=>p.floor_reserved=value,11=>p.floor_active=value,
        12=>p.floor_attempt_consumed=value,13=>p.floor_probe_cancelled=value,14=>p.startup_disproved=value,
        15=>owner.fast_statistics_available=value,16=>cadence.capacity_enabled=value,_=>panic!("closed boolean case")}
}
fn bool_value(owner:&Owner,cadence:&Cadence,case:usize)->bool {
    let p=&owner.policy;
    match case {0=>p.below_reserve_disproved,1=>p.resume_restoration.unwrap().disproved,2=>p.bandwidth_unavailable,
        3=>p.last_latency_pressure,4=>p.last_positive_suspension_pressure,5=>p.queue.faulted,6=>p.rtt.faulted,
        7=>p.demand.faulted,8=>p.route_present,9=>p.capacity_growth_veto,10=>p.floor_reserved,11=>p.floor_active,
        12=>p.floor_attempt_consumed,13=>p.floor_probe_cancelled,14=>p.startup_disproved,15=>owner.fast_statistics_available,
        16=>cadence.capacity_enabled,_=>panic!("closed boolean case")}
}

#[test]
fn golden_all_17_boolean_fields_have_independent_one_hot_and_one_cold_positions() {
    // Limited-domain fields cannot all have unique simultaneous payloads. Basis
    // fixtures give each same-typed boolean a distinct independently named position.
    for background in [false,true] {for changed in 0..17 {
        let mut owner=sentinel_owner();let mut cadence=sentinel_cadence();
        let mut owner_wire=literal_owner();let mut cadence_wire=literal_cadence();
        for case in 0..17 {
            let value=if case==changed{!background}else{background};
            set_bool(&mut owner,&mut cadence,case,value);
            if case<16{owner_wire.atoms[BOOL_INDEX[case]].low=value as u64;}
            else{cadence_wire.atoms[BOOL_INDEX[case]].low=value as u64;}
        }
        assert_owner_wire(owner,&owner_wire,"boolean basis");assert_cadence_wire(cadence,&cadence_wire,"boolean basis");
        let o=decode_owner_snapshot(owner_wire.header,&owner_wire.atoms).unwrap();
        let c=decode_cadence_snapshot(cadence_wire.header,&cadence_wire.atoms).unwrap();
        for case in 0..17{assert_eq!(bool_value(&o,&c,case),if case==changed{!background}else{background},"boolean {case}, changed {changed}");}
    }}
}

const FLOAT_INDEX:[usize;25]=[35,37,60,61,62,63,64,75,85,87,95,101,107,113,119,125,131,137,147,148,149,157,160,162,178];
const FLOAT_VARIANTS:[u64;10]=[0,0x8000_0000_0000_0000,1,0x7fef_ffff_ffff_ffff,0x7ff0_0000_0000_0000,0xfff0_0000_0000_0000,
    0x7ff8_0000_0000_0001,0x7ff8_0000_0000_0123,0x7ff0_0000_0000_0001,0xfff8_0000_0000_0456];
fn set_float(owner:&mut Owner,case:usize,bits:u64) {
    let p=&mut owner.policy;
    match case {
        0=>p.last_average_delay=Some(Scalar(bits)),1=>p.queue.delay_bits=Some(bits),2=>p.rtt.raw.baseline_bits=bits,3=>p.rtt.raw.last_measured_bits=bits,
        4..=6=>p.rtt.raw.bootstrap_bits[case-4]=bits,7=>p.rtt.raw.watermark.total_bits=bits,8=>p.rtt.raw.fence.total_bits=bits,9=>p.rtt.raw.fence_current_bits=bits,
        10..=17=>p.demand.profiles[case-10].required=Scalar(bits),18=>p.capacity_sample.as_mut().unwrap().delay=Some(Scalar(bits)),
        19=>p.capacity_bandwidth_high=Some(Scalar(bits)),20=>p.capacity_timestamp=Some(Scalar(bits)),21=>p.floor_seed=Some(Scalar(bits)),
        22=>p.floor_first_witness.as_mut().unwrap().bandwidth=Scalar(bits),23=>p.floor_regular_timestamp=Some(Scalar(bits)),24=>owner.applied.as_mut().unwrap().scale=Scalar(bits),_=>panic!("closed scalar case"),
    }
}
fn float_bits(owner:&Owner,case:usize)->u64 {
    let p=&owner.policy;
    match case {
        0=>p.last_average_delay.unwrap().0,1=>p.queue.delay_bits.unwrap(),2=>p.rtt.raw.baseline_bits,3=>p.rtt.raw.last_measured_bits,
        4..=6=>p.rtt.raw.bootstrap_bits[case-4],7=>p.rtt.raw.watermark.total_bits,8=>p.rtt.raw.fence.total_bits,9=>p.rtt.raw.fence_current_bits,
        10..=17=>p.demand.profiles[case-10].required.0,18=>p.capacity_sample.unwrap().delay.unwrap().0,19=>p.capacity_bandwidth_high.unwrap().0,
        20=>p.capacity_timestamp.unwrap().0,21=>p.floor_seed.unwrap().0,22=>p.floor_first_witness.unwrap().bandwidth.0,23=>p.floor_regular_timestamp.unwrap().0,24=>owner.applied.unwrap().scale.0,_=>panic!("closed scalar case"),
    }
}

#[test]
fn golden_all_25_ieee_locations_preserve_signed_zero_and_nan_payloads() {
    assert_eq!(FLOAT_INDEX.len(),25);
    for case in 0..25 { for bits in FLOAT_VARIANTS {
        let mut owner=sentinel_owner();set_float(&mut owner,case,bits);
        let mut wire=literal_owner();wire.atoms[FLOAT_INDEX[case]].low=bits;
        assert_owner_wire(owner,&wire,"IEEE bit matrix");
        let decoded=decode_owner_snapshot(wire.header,&wire.atoms).unwrap();
        assert_eq!(float_bits(&decoded,case),bits,"float slot {case}");
    } }
}

#[test]
fn golden_all_eight_profiles_remain_distinct_even_when_inactive() {
    let tuples:[(i64,i64,i64,i64,u64,Option<i64>);8]=[
        (1091,1092,1093,1094,0x7ff8_0000_0000_005f,Some(1096)),(1097,1098,1099,1100,0x7ff8_0000_0000_0065,Some(1102)),
        (1103,1104,1105,1106,0x7ff8_0000_0000_006b,Some(1108)),(1109,1110,1111,1112,0x7ff8_0000_0000_0071,Some(1114)),
        (1115,1116,1117,1118,0x7ff8_0000_0000_0077,Some(1120)),(1121,1122,1123,1124,0x7ff8_0000_0000_007d,Some(1126)),
        (1127,1128,1129,1130,0x7ff8_0000_0000_0083,Some(1132)),(1133,1134,1135,1136,0x7ff8_0000_0000_0089,Some(1138)),
    ];
    for count in [0,8,250] {
        let mut owner=sentinel_owner();owner.policy.demand.profiles_count=count;
        let mut wire=literal_owner();wire.atoms[139].low=count as u64;
        assert_owner_wire(owner,&wire,"all profile storage");
        let decoded=decode_owner_snapshot(wire.header,&wire.atoms).unwrap();
        for (index,expected) in tuples.into_iter().enumerate() {
            let p=decoded.policy.demand.profiles[index];
            assert_eq!((p.baseline_video,p.maximum_video,p.maximum_total,p.minimum_sustainable,p.required.0,p.next_direct),expected,"profile {index}");
        }
    }
}

// Literal limbs were calculated independently with integer arithmetic, not codec
// helpers. The endpoints are native Duration component-domain codec fixtures,
// not assertions that actual ContinuousClock Instants were captured there.
const TIME_VARIANTS:[(i128,i64,u64);7]=[
    (0,0,0),(1,0,1),(-1,-1,u64::MAX),
    (18446744073709551623,1,7),(-18446744073709551623,-2,18446744073709551609),
    (9223372036854775807999999999999999999,499999999999999999,u64::MAX),
    (-9223372036854775808999999999999999999,-500000000000000001,17446744073709551617),
];
const TIME_INDEX:[usize;13]=[12,23,28,159,163,167,39,40,88,171,0,1,4];
fn set_time(owner:&mut Owner,cadence:&mut Cadence,case:usize,value:i128) {
    let p=&mut owner.policy;
    match case {0=>p.probe_deadline=Some(value),1=>p.probe_qualification_at=Some(value),2=>p.promotion.as_mut().unwrap().deadline=value,
        3=>p.floor_first_witness.as_mut().unwrap().observed_at=value,4=>p.floor_cooldown_at=Some(value),5=>p.startup_sparse_deadline=Some(value),
        6=>p.queue.low_observation=Some(value),7=>p.queue.soft_observation=Some(value),8=>p.rtt.last_advancement=Some(value),9=>owner.last_evidence=Some(value),
        10=>cadence.next_regular=value,11=>cadence.next_capacity=Some(value),12=>cadence.latest=value,_=>panic!("closed time case")}
}
fn time_value(owner:&Owner,cadence:&Cadence,case:usize)->i128 {
    let p=&owner.policy;
    match case {0=>p.probe_deadline.unwrap(),1=>p.probe_qualification_at.unwrap(),2=>p.promotion.unwrap().deadline,3=>p.floor_first_witness.unwrap().observed_at,
        4=>p.floor_cooldown_at.unwrap(),5=>p.startup_sparse_deadline.unwrap(),6=>p.queue.low_observation.unwrap(),7=>p.queue.soft_observation.unwrap(),
        8=>p.rtt.last_advancement.unwrap(),9=>owner.last_evidence.unwrap(),10=>cadence.next_regular,11=>cadence.next_capacity.unwrap(),12=>cadence.latest,_=>panic!("closed time case")}
}

#[test]
fn golden_all_13_times_preserve_literal_limbs_and_native_domain_extrema() {
    for case in 0..13 {for (value,high,low) in TIME_VARIANTS {
        let mut owner=sentinel_owner();let mut cadence=sentinel_cadence();set_time(&mut owner,&mut cadence,case,value);
        if case<10 {
            let mut wire=literal_owner();wire.atoms[TIME_INDEX[case]]=atom(10,1,high,low);
            assert_owner_wire(owner,&wire,"13 time matrix");let decoded=decode_owner_snapshot(wire.header,&wire.atoms).unwrap();
            assert_eq!(time_value(&decoded,&cadence,case),value,"time {case}");
        } else {
            let mut wire=literal_cadence();wire.atoms[TIME_INDEX[case]]=atom(10,1,high,low);
            assert_cadence_wire(cadence,&wire,"13 time matrix");let decoded=decode_cadence_snapshot(wire.header,&wire.atoms).unwrap();
            assert_eq!(time_value(&owner,&decoded,case),value,"time {case}");
        }
    }}
}

#[test]
fn golden_all_13_times_reject_one_attosecond_outside_native_domain() {
    for case in 0..13 {for (value,high,low) in [
        (9223372036854775808000000000000000000i128,500000000000000000,0u64),
        (-9223372036854775809000000000000000000i128,-500000000000000001,17446744073709551616u64),
    ] {
        let mut owner=sentinel_owner();let mut cadence=sentinel_cadence();set_time(&mut owner,&mut cadence,case,value);
        if case<10 {
            assert_eq!(encode_owner_snapshot(owner),Err(Error::Time),"time {case} encoder");
            let mut wire=literal_owner();wire.atoms[TIME_INDEX[case]]=atom(10,1,high,low);
            assert!(matches!(decode_owner_snapshot(wire.header,&wire.atoms),Err(Error::Time)),"time {case} decoder");
        } else {
            assert_eq!(encode_cadence_snapshot(cadence),Err(Error::Time),"time {case} encoder");
            let mut wire=literal_cadence();wire.atoms[TIME_INDEX[case]]=atom(10,1,high,low);
            assert!(matches!(decode_cadence_snapshot(wire.header,&wire.atoms),Err(Error::Time)),"time {case} decoder");
        }
    }}
}

fn decode_is_error(wire:&Wire,error:Error)->bool {
    match wire.header.domain {1=>matches!(decode_policy_snapshot(wire.header,&wire.atoms),Err(e) if e==error),
        2=>matches!(decode_owner_snapshot(wire.header,&wire.atoms),Err(e) if e==error),
        3=>matches!(decode_cadence_snapshot(wire.header,&wire.atoms),Err(e) if e==error),_=>false}
}
fn assert_denied(wire:Wire,error:Error,label:&str) {
    let original=wire.clone();assert!(decode_is_error(&wire,error),"{label}: expected {error:?}");
    assert_eq!(wire,original,"pure decoder input changed: {label}");
}
const OPTIONAL_OWNER_ATOMS:[usize;38]=[3,12,20,21,22,23,24,35,36,37,39,40,88,96,102,108,114,120,126,132,138,143,146,147,148,149,150,152,157,161,162,163,164,165,167,170,171,172];

#[test]
fn golden_every_atom_denies_wrong_kind_presence_high_width_and_required_absence() {
    for base in [literal_policy(),literal_owner(),literal_cadence()] {
        for index in 0..base.atoms.len() {
            let mut wire=base.clone();wire.atoms[index].kind=11;assert_denied(wire,Error::Kind,"every kind");
            let mut wire=base.clone();wire.atoms[index].present=2;assert_denied(wire,Error::Presence,"every presence");
            let mut wire=base.clone();wire.atoms[index].high=if wire.atoms[index].kind==10{i64::MAX}else{1};
            let error=if wire.atoms[index].kind==10{Error::Time}else{Error::Payload};assert_denied(wire,error,"every high");
            let overflow=match base.atoms[index].kind{4=>Some(2),5=>Some(256),6=>Some(4294967296),7=>Some(8),8|9=>Some(2),_=>None};
            if let Some(low)=overflow {let mut wire=base.clone();wire.atoms[index].low=low;assert_denied(wire,Error::Width,"every width");}
            let optional=if base.header.domain==3{[1,3].contains(&index)}else{OPTIONAL_OWNER_ATOMS.contains(&index)};
            if !optional {let mut wire=base.clone();wire.atoms[index].present=0;wire.atoms[index].high=0;wire.atoms[index].low=0;assert_denied(wire,Error::Presence,"required absent");}
        }
    }
}

#[test]
fn golden_every_optional_atom_denies_nonzero_absent_payload() {
    for index in OPTIONAL_OWNER_ATOMS {
        for high in [false,true] {
            let mut wire=literal_owner();wire.atoms[index].present=0;
            wire.atoms[index].high=if high{1}else{0};wire.atoms[index].low=if high{0}else{1};
            assert_denied(wire,Error::Payload,"optional absent payload");
        }
    }
    for index in [1,3] {for high in [false,true] {
        let mut wire=literal_cadence();wire.atoms[index].present=0;
        wire.atoms[index].high=if high{1}else{0};wire.atoms[index].low=if high{0}else{1};
        assert_denied(wire,Error::Payload,"cadence absent payload");
    }}
}

#[test]
fn golden_all_15_absent_composite_children_deny_hidden_payload_or_presence() {
    let mut children_seen=0;
    for container in [16,25,145,158,173] {
        let mut base=literal_owner();literal_option(&mut base,container,false);
        assert!(decode_owner_snapshot(base.header,&base.atoms).is_ok(),"canonical absent container");
        for &child in composite_children(container).unwrap() {
            children_seen+=1;
            let mut wire=base.clone();wire.atoms[child].present=1;assert_denied(wire,Error::Presence,"hidden present child");
            let mut wire=base.clone();wire.atoms[child].low=1;assert_denied(wire,Error::Payload,"hidden low child");
            let mut wire=base.clone();wire.atoms[child].high=1;assert_denied(wire,Error::Payload,"hidden high child");
            let mut wire=base.clone();wire.atoms[child].kind=11;assert_denied(wire,Error::Kind,"hidden kind child");
            let mut wire=base.clone();wire.atoms[child].present=2;assert_denied(wire,Error::Presence,"hidden tag child");
        }
    }
    assert_eq!(children_seen,15);
}

#[test]
fn golden_header_domains_counts_lengths_and_result_replay_are_closed() {
    for base in [literal_policy(),literal_owner(),literal_cadence()] {
        for field in 0..4 {
            let mut wire=base.clone();match field {0=>wire.header.abi=2,1=>wire.header.domain=99,2=>wire.header.phase=0,3=>wire.header.count+=1,_=>unreachable!()}
            // Choose the original domain's decoder; an unknown domain is itself denied.
            let denied=match base.header.domain {1=>matches!(decode_policy_snapshot(wire.header,&wire.atoms),Err(Error::Header)),
                2=>matches!(decode_owner_snapshot(wire.header,&wire.atoms),Err(Error::Header)),3=>matches!(decode_cadence_snapshot(wire.header,&wire.atoms),Err(Error::Header)),_=>false};
            assert!(denied,"header field {field}");
        }
        let mut short=base.clone();short.atoms.pop();assert_denied(short,Error::Length,"short atoms");
        let mut long=base.clone();long.atoms.push(atom(1,1,0,444));assert_denied(long,Error::Length,"long atoms");
        let mut result=base.clone();result.header.phase=2;
        assert_eq!(validate_result(result.header,&result.atoms),Ok(()),"valid result framing");
        assert_denied(result,Error::Header,"result is not entry snapshot");
        assert_eq!(validate_result(base.header,&base.atoms),Err(Error::Header),"snapshot is not result");
    }
    assert_eq!(count(0),None);assert_eq!(count(99),None);
}

#[test]
fn golden_all_five_nonpristine_and_sticky_invalid_journals_are_rejected() {
    for journal in 0..5 {
        for invalid in [false,true] {
            let mut owner=sentinel_owner();let mut cadence=sentinel_cadence();
            // Do not rebase: losing invalidity inside this frame must not rescue it.
            match journal {
                0=>{if invalid{owner.times.set(TimeSlot::EvidenceTime,0i128,None);}owner.times.clear::<i128>(TimeSlot::EvidenceTime);},
                1=>{if invalid{owner.policy.times.set(TimeSlot::ProbeDeadline,0i128,None);}owner.policy.times.clear::<i128>(TimeSlot::ProbeDeadline);},
                2=>{if invalid{owner.policy.queue.times.set(TimeSlot::QueueLow,0i128,None);}owner.policy.queue.times.clear::<i128>(TimeSlot::QueueLow);},
                3=>{if invalid{owner.policy.rtt.times.set(TimeSlot::RttAdvancement,0i128,None);}owner.policy.rtt.times.clear::<i128>(TimeSlot::RttAdvancement);},
                4=>{if invalid{cadence.times.set(TimeSlot::CadenceLatest,0i128,None);}cadence.times.clear::<i128>(TimeSlot::CadenceLatest);},_=>unreachable!(),
            }
            if journal==4 {assert_eq!(encode_cadence_snapshot(cadence),Err(Error::Journal));}
            else {assert_eq!(encode_owner_snapshot(owner),Err(Error::Journal));if journal!=0{assert_eq!(encode_policy_snapshot(owner.policy),Err(Error::Journal));}}
        }
    }
    let mut owner=sentinel_owner();owner.policy.times.import_prepared(TimeSlot::ProbeDeadline,Some(1000012i128));
    assert_eq!(encode_owner_snapshot(owner),Err(Error::Journal),"equal prepared assignment is not pristine");
}

#[test]
fn golden_equal_current_time_set_is_not_an_inactive_snapshot_journal() {
    for journal in 0..5 {
        let mut owner=sentinel_owner();let mut cadence=sentinel_cadence();
        let slot=match journal{0=>TimeSlot::EvidenceTime,1=>TimeSlot::ProbeDeadline,2=>TimeSlot::QueueLow,3=>TimeSlot::RttAdvancement,4=>TimeSlot::CadenceLatest,_=>unreachable!()};
        let origin=Some(Origin{source:TimeSource::CurrentInput(slot),delta:0});
        match journal {
            0=>{owner.times.set(slot,1000171i128,origin);},1=>{owner.policy.times.set(slot,1000012i128,origin);},
            2=>{owner.policy.queue.times.set(slot,1000039i128,origin);},3=>{owner.policy.rtt.times.set(slot,1000088i128,origin);},
            4=>{cadence.times.set(slot,2000004i128,origin);},_=>unreachable!(),
        }
        if journal==4{assert_eq!(encode_cadence_snapshot(cadence),Err(Error::Journal));}
        else{assert_eq!(encode_owner_snapshot(owner),Err(Error::Journal));}
    }
}

#[test]
fn golden_opaque_u8_u32_words_preserve_full_width_without_policy_revalidation() {
    for index in 0..179 {
        let base=literal_owner();let kind=base.atoms[index].kind;
        let values=match kind{5=>[0,255],6=>[0,4294967295],_=>continue};
        for low in values {
            let mut wire=base.clone();wire.atoms[index].low=low;
            let decoded=decode_owner_snapshot(wire.header,&wire.atoms).unwrap();
            assert_eq!(encode_owner_snapshot(decoded).unwrap(),wire,"opaque width at {index}");
        }
    }
    let mut owner=sentinel_owner();owner.policy.rtt.raw.reserved=u32::MAX;
    owner.policy.rtt.raw.baseline_present=u32::MAX;owner.policy.rtt.raw.reserved2=u32::MAX;
    let mut wire=literal_owner();wire.atoms[43].low=4294967295;wire.atoms[44].low=4294967295;wire.atoms[58].low=4294967295;
    assert_owner_wire(owner,&wire,"typed opaque raw DTO");
    let decoded=decode_owner_snapshot(wire.header,&wire.atoms).unwrap();
    assert_eq!((decoded.policy.rtt.raw.reserved,decoded.policy.rtt.raw.baseline_present,decoded.policy.rtt.raw.reserved2),(u32::MAX,u32::MAX,u32::MAX));
}

#[test]
fn golden_signed_integer_and_unsigned_counter_extrema_survive_without_clamping() {
    // Every kind2 position includes named outer counters, nested restoration,
    // promotion, profiles and applied Recommendation plus opaque RTT age parts.
    for base in [literal_policy(),literal_owner()] {
        for index in 0..base.atoms.len() {
            if base.atoms[index].kind==2 {
                for bits in [0u64,0x8000_0000_0000_0000,0x7fff_ffff_ffff_ffff,u64::MAX] {
                    let mut wire=base.clone();wire.atoms[index].low=bits;
                    if base.header.domain==1 {let decoded=decode_policy_snapshot(wire.header,&wire.atoms).unwrap();assert_eq!(encode_policy_snapshot(decoded).unwrap(),wire,"i64 index {index}");}
                    else {let decoded=decode_owner_snapshot(wire.header,&wire.atoms).unwrap();assert_eq!(encode_owner_snapshot(decoded).unwrap(),wire,"i64 index {index}");}
                }
            }
            if base.atoms[index].kind==1 {
                let mut wire=base.clone();wire.atoms[index].low=u64::MAX;
                if base.header.domain==1 {let decoded=decode_policy_snapshot(wire.header,&wire.atoms).unwrap();assert_eq!(encode_policy_snapshot(decoded).unwrap(),wire,"u64 index {index}");}
                else {let decoded=decode_owner_snapshot(wire.header,&wire.atoms).unwrap();assert_eq!(encode_owner_snapshot(decoded).unwrap(),wire,"u64 index {index}");}
            }
        }
    }
    let mut owner=sentinel_owner();owner.policy.configured_cap=i64::MIN;owner.policy.maximum_tier_video=i64::MAX;owner.policy.base_fps=-1;owner.revision=u64::MAX;
    let mut wire=literal_owner();wire.atoms[0].low=0x8000_0000_0000_0000;wire.atoms[1].low=0x7fff_ffff_ffff_ffff;wire.atoms[2].low=u64::MAX;wire.atoms[168].low=u64::MAX;
    assert_owner_wire(owner,&wire,"typed extrema not reconstructed by new");
}

struct NoClock;
impl ClockFacts for NoClock {fn cut(&mut self,_:ClockSite)->i128{panic!("same peer must not read clock")}}
#[test]
fn golden_decoded_max_revision_wraps_only_on_actual_same_peer_owner_bind() {
    let mut wire=literal_owner();wire.atoms[168].low=u64::MAX;
    let mut owner=decode_owner_snapshot(wire.header,&wire.atoms).unwrap();
    assert_eq!(owner.revision,u64::MAX);assert_eq!(owner.policy.peer,Some(10003));
    let mut clock=NoClock;
    assert_eq!(owner.try_bind_native_peer(10003,&mut clock,Dependencies::default()).unwrap(),RouteAction::Retain);
    assert_eq!(owner.revision,0,"actual wrapping_add, not codec normalization");
    assert!(!owner.fast_statistics_available);assert!(owner.evidence_lane.is_none());assert!(owner.last_evidence.is_none());assert!(owner.freshness.minimum.is_none());assert!(owner.applied.is_none());
    assert_eq!(owner.policy.startup_peer,Some(10164));assert_eq!(owner.policy.startup_show,Some(10165));
}
