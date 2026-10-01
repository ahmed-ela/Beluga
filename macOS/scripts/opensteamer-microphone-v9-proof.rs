//! Pure native consumption of root-held, bounded child result bytes.
//! This module performs no I/O, process launch, route query, or privileged action.
//! Passing a receipt does not attest its provenance: the caller must own and pin
//! the exact child binary, invocation, deadline, output descriptor and generation.
use std::collections::BTreeMap;

type Result<T> = std::result::Result<T, String>;
pub const VISIBLE: &str = "com.elamin.opensteamer.virtual-microphone.input";
pub const HIDDEN: &str = "com.elamin.opensteamer.virtual-microphone.writer";
const MODEL: &str = "com.elamin.opensteamer.virtual-microphone.model";
const ORDERS: [&str; 2] = ["visible-first", "hidden-first"];
const PHASES: [&str; 5] = [
    "before-start",
    "first-started",
    "both-started",
    "proof-complete",
    "drained",
];
const MAX_BYTES: usize = 1_048_576;

#[derive(Clone, Debug, PartialEq)]
pub(crate) enum Json {
    Null,
    Bool(bool),
    Number(String),
    Text(String),
    Array(Vec<Json>),
    Object(BTreeMap<String, Json>),
}
type Object = BTreeMap<String, Json>;

pub(crate) struct Parser<'a> {
    bytes: &'a [u8],
    index: usize,
    nodes: usize,
}
impl<'a> Parser<'a> {
    pub(crate) fn parse(bytes: &'a [u8]) -> Result<Json> {
        require(
            !bytes.is_empty() && bytes.len() <= MAX_BYTES,
            "JSON byte bound",
        )?;
        let mut parser = Self {
            bytes,
            index: 0,
            nodes: 0,
        };
        let value = parser.value(0)?;
        parser.space();
        require(parser.index == bytes.len(), "JSON trailing bytes")?;
        Ok(value)
    }
    fn space(&mut self) {
        while self
            .bytes
            .get(self.index)
            .is_some_and(|b| matches!(b, b' ' | b'\n' | b'\r' | b'\t'))
        {
            self.index += 1;
        }
    }
    fn literal(&mut self, bytes: &[u8]) -> Result<()> {
        require(
            self.bytes.get(self.index..self.index + bytes.len()) == Some(bytes),
            "JSON literal",
        )?;
        self.index += bytes.len();
        Ok(())
    }
    fn value(&mut self, depth: usize) -> Result<Json> {
        self.space();
        self.nodes += 1;
        require(depth <= 16 && self.nodes <= 16_384, "JSON depth/node bound")?;
        match self.bytes.get(self.index) {
            Some(b'n') => {
                self.literal(b"null")?;
                Ok(Json::Null)
            }
            Some(b't') => {
                self.literal(b"true")?;
                Ok(Json::Bool(true))
            }
            Some(b'f') => {
                self.literal(b"false")?;
                Ok(Json::Bool(false))
            }
            Some(b'"') => Ok(Json::Text(self.string()?)),
            Some(b'-' | b'0'..=b'9') => Ok(Json::Number(self.number()?)),
            Some(b'[') => {
                self.index += 1;
                self.space();
                let mut values = Vec::new();
                if self.bytes.get(self.index) == Some(&b']') {
                    self.index += 1;
                    return Ok(Json::Array(values));
                }
                loop {
                    values.push(self.value(depth + 1)?);
                    self.space();
                    match self.bytes.get(self.index) {
                        Some(b',') => self.index += 1,
                        Some(b']') => {
                            self.index += 1;
                            break;
                        }
                        _ => return Err("JSON array delimiter".into()),
                    }
                }
                Ok(Json::Array(values))
            }
            Some(b'{') => {
                self.index += 1;
                self.space();
                let mut fields = Object::new();
                if self.bytes.get(self.index) == Some(&b'}') {
                    self.index += 1;
                    return Ok(Json::Object(fields));
                }
                loop {
                    self.space();
                    let key = self.string()?;
                    self.space();
                    self.literal(b":")?;
                    let value = self.value(depth + 1)?;
                    require(fields.insert(key, value).is_none(), "JSON duplicate key")?;
                    self.space();
                    match self.bytes.get(self.index) {
                        Some(b',') => self.index += 1,
                        Some(b'}') => {
                            self.index += 1;
                            break;
                        }
                        _ => return Err("JSON object delimiter".into()),
                    }
                }
                Ok(Json::Object(fields))
            }
            _ => Err("JSON invalid token".into()),
        }
    }
    fn string(&mut self) -> Result<String> {
        self.literal(b"\"")?;
        let mut bytes = Vec::new();
        loop {
            let byte = *self.bytes.get(self.index).ok_or("JSON truncated string")?;
            self.index += 1;
            match byte {
                b'"' => break,
                0..=31 => return Err("JSON control byte".into()),
                b'\\' => {
                    let escaped = *self.bytes.get(self.index).ok_or("JSON truncated escape")?;
                    self.index += 1;
                    match escaped {
                        b'"' | b'\\' | b'/' => bytes.push(escaped),
                        b'b' => bytes.push(8),
                        b'f' => bytes.push(12),
                        b'n' => bytes.push(10),
                        b'r' => bytes.push(13),
                        b't' => bytes.push(9),
                        b'u' => {
                            let digits = self
                                .bytes
                                .get(self.index..self.index + 4)
                                .ok_or("JSON truncated Unicode")?;
                            require(
                                digits.iter().all(u8::is_ascii_hexdigit),
                                "JSON Unicode digits",
                            )?;
                            let digits =
                                std::str::from_utf8(digits).map_err(|_| "JSON Unicode ASCII")?;
                            let scalar = u32::from_str_radix(digits, 16)
                                .map_err(|_| "JSON Unicode digits")?;
                            let scalar =
                                char::from_u32(scalar).ok_or("JSON surrogate/non-scalar")?;
                            self.index += 4;
                            let mut encoded = [0; 4];
                            bytes.extend_from_slice(scalar.encode_utf8(&mut encoded).as_bytes());
                        }
                        _ => return Err("JSON invalid escape".into()),
                    }
                }
                _ => bytes.push(byte),
            }
            require(bytes.len() <= 65_536, "JSON string bound")?;
        }
        String::from_utf8(bytes).map_err(|_| "JSON invalid UTF-8".into())
    }
    fn number(&mut self) -> Result<String> {
        let start = self.index;
        if self.bytes.get(self.index) == Some(&b'-') {
            self.index += 1;
        }
        match self.bytes.get(self.index) {
            Some(b'0') => self.index += 1,
            Some(b'1'..=b'9') => {
                self.index += 1;
                while self.bytes.get(self.index).is_some_and(u8::is_ascii_digit) {
                    self.index += 1;
                }
            }
            _ => return Err("JSON integer token".into()),
        }
        if self.bytes.get(self.index) == Some(&b'.') {
            self.index += 1;
            let begin = self.index;
            while self.bytes.get(self.index).is_some_and(u8::is_ascii_digit) {
                self.index += 1;
            }
            require(self.index > begin, "JSON fraction")?;
        }
        if self
            .bytes
            .get(self.index)
            .is_some_and(|b| matches!(b, b'e' | b'E'))
        {
            self.index += 1;
            if self
                .bytes
                .get(self.index)
                .is_some_and(|b| matches!(b, b'+' | b'-'))
            {
                self.index += 1;
            }
            let begin = self.index;
            while self.bytes.get(self.index).is_some_and(u8::is_ascii_digit) {
                self.index += 1;
            }
            require(self.index > begin, "JSON exponent")?;
        }
        std::str::from_utf8(&self.bytes[start..self.index])
            .map(str::to_owned)
            .map_err(|_| "JSON number ASCII".into())
    }
}

fn require(condition: bool, message: &str) -> Result<()> {
    if condition {
        Ok(())
    } else {
        Err(message.into())
    }
}
fn object(value: &Json) -> Result<&Object> {
    if let Json::Object(value) = value {
        Ok(value)
    } else {
        Err("object type".into())
    }
}
fn fields<'a>(value: &'a Json, expected: &str) -> Result<&'a Object> {
    let value = object(value)?;
    let expected: Vec<_> = expected.split_whitespace().collect();
    require(
        value.len() == expected.len() && expected.iter().all(|key| value.contains_key(*key)),
        "exact field set",
    )?;
    Ok(value)
}
fn field<'a>(value: &'a Object, key: &str) -> Result<&'a Json> {
    value.get(key).ok_or_else(|| format!("missing field {key}"))
}
fn text<'a>(value: &'a Object, key: &str) -> Result<&'a str> {
    if let Json::Text(value) = field(value, key)? {
        Ok(value)
    } else {
        Err(format!("text type {key}"))
    }
}
fn str_is(value: &Object, key: &str, expected: &str) -> Result<()> {
    require(text(value, key)? == expected, key)
}
fn boolean(value: &Object, key: &str) -> Result<bool> {
    if let Json::Bool(value) = field(value, key)? {
        Ok(*value)
    } else {
        Err(format!("bool type {key}"))
    }
}
fn bool_is(value: &Object, key: &str, expected: bool) -> Result<()> {
    require(boolean(value, key)? == expected, key)
}
fn uint(value: &Object, key: &str) -> Result<u64> {
    if let Json::Number(value) = field(value, key)? {
        require(
            !value.is_empty()
                && value.bytes().all(|b| b.is_ascii_digit())
                && (value == "0" || !value.starts_with('0')),
            "unsigned integer type",
        )?;
        value.parse().map_err(|_| format!("u64 overflow {key}"))
    } else {
        Err(format!("integer type {key}"))
    }
}
fn positive(value: &Object, key: &str) -> Result<u64> {
    let value = uint(value, key)?;
    require(value > 0, key)?;
    Ok(value)
}
fn uis(value: &Object, key: &str, expected: u64) -> Result<()> {
    require(uint(value, key)? == expected, key)
}
fn number(value: &Object, key: &str) -> Result<f64> {
    if let Json::Number(value) = field(value, key)? {
        let parsed: f64 = value.parse().map_err(|_| "finite number")?;
        require(parsed.is_finite(), "finite number")?;
        Ok(parsed)
    } else {
        Err(format!("number type {key}"))
    }
}
fn nis(value: &Object, key: &str, expected: f64) -> Result<()> {
    require(number(value, key)? == expected, key)
}
fn array<'a>(value: &'a Object, key: &str) -> Result<&'a [Json]> {
    if let Json::Array(value) = field(value, key)? {
        Ok(value)
    } else {
        Err(format!("array type {key}"))
    }
}
fn hex(value: &str) -> bool {
    value.len() == 64
        && value
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}
fn digest(value: &Object, key: &str) -> Result<()> {
    require(hex(text(value, key)?), key)
}
fn bools(value: &Object, keys: &str, expected: bool) -> Result<()> {
    for key in keys.split_whitespace() {
        bool_is(value, key, expected)?;
    }
    Ok(())
}
fn zeros(value: &Object, keys: &str) -> Result<()> {
    for key in keys.split_whitespace() {
        uis(value, key, 0)?;
    }
    Ok(())
}

pub fn sha256(input: &[u8]) -> String {
    const K: [u32; 64] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
        0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
        0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
        0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
        0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
        0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
        0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
        0xc67178f2,
    ];
    let mut h = [
        0x6a09e667u32,
        0xbb67ae85,
        0x3c6ef372,
        0xa54ff53a,
        0x510e527f,
        0x9b05688c,
        0x1f83d9ab,
        0x5be0cd19,
    ];
    let mut bytes = input.to_vec();
    let length = bytes.len() as u64 * 8;
    bytes.push(0x80);
    while bytes.len() % 64 != 56 {
        bytes.push(0);
    }
    bytes.extend_from_slice(&length.to_be_bytes());
    for chunk in bytes.chunks_exact(64) {
        let mut w = [0u32; 64];
        for (i, word) in chunk.chunks_exact(4).enumerate() {
            w[i] = u32::from_be_bytes(word.try_into().unwrap());
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16]
                .wrapping_add(s0)
                .wrapping_add(w[i - 7])
                .wrapping_add(s1);
        }
        let [mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut z] = h;
        for i in 0..64 {
            let t1 = z
                .wrapping_add(e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25))
                .wrapping_add((e & f) ^ (!e & g))
                .wrapping_add(K[i])
                .wrapping_add(w[i]);
            let t2 = (a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22))
                .wrapping_add((a & b) ^ (a & c) ^ (b & c));
            z = g;
            g = f;
            f = e;
            e = d.wrapping_add(t1);
            d = c;
            c = b;
            b = a;
            a = t1.wrapping_add(t2);
        }
        for (slot, value) in h.iter_mut().zip([a, b, c, d, e, f, g, z]) {
            *slot = slot.wrapping_add(value);
        }
    }
    h.iter().map(|v| format!("{v:08x}")).collect()
}

fn challenge_hash(nonce: &str) -> String {
    let mut seed = 14_695_981_039_346_656_037u64;
    for byte in format!("{nonce}:mirror:mono").bytes() {
        seed = (seed ^ u64::from(byte)).wrapping_mul(1_099_511_628_211);
    }
    seed ^= 0xA5A5D3C47E291B6F;
    if seed == 0 {
        seed = 0xD1B54A32D192ED03;
    }
    let mut pcm = Vec::with_capacity(192_000);
    for frame in 0..96_000 {
        let sample: i16 = if frame < 256 {
            (12_000 + (frame * 257 + 73) % 8_001) as i16
        } else {
            seed = seed.wrapping_add(0x9E3779B97F4A7C15);
            let mut value = seed;
            value = (value ^ (value >> 30)).wrapping_mul(0xBF58476D1CE4E5B9);
            value = (value ^ (value >> 27)).wrapping_mul(0x94D049BB133111EB);
            let sample = ((value ^ (value >> 31)) % 48_001) as i32 - 24_000;
            if sample == 0 {
                1
            } else {
                sample as i16
            }
        };
        pcm.extend_from_slice(&sample.to_le_bytes());
    }
    sha256(&pcm)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PublicProofReceipt {
    pub source_sha256: String,
    pub instance: u64,
    pub visible_device: u32,
    pub hidden_device: u32,
    pub last_sequence: u64,
    pub last_captured_ticks: u64,
    pub last_issued_seed: u64,
    pub last_issued_session: u64,
    pub driver_lifecycle: u64,
    pub core_lifecycle: u64,
}

fn endpoint(value: &Json, uid: &str, hidden: bool) -> Result<u32> {
    let value=fields(value,"alive clockDomain expectedUID hidden inputChannels modelUIDFingerprint modelUIDMatchesExpected nominalSampleRate objectID outputChannels resolvedUID translatedByExactUID")?;
    str_is(value, "expectedUID", uid)?;
    str_is(value, "resolvedUID", uid)?;
    bools(
        value,
        "alive modelUIDMatchesExpected translatedByExactUID",
        true,
    )?;
    bool_is(value, "hidden", hidden)?;
    uis(value, "inputChannels", u64::from(!hidden))?;
    uis(value, "outputChannels", u64::from(hidden))?;
    nis(value, "nominalSampleRate", 48_000.0)?;
    uis(value, "clockDomain", 0x6f73564d)?;
    str_is(value, "modelUIDFingerprint", &sha256(MODEL.as_bytes()))?;
    u32::try_from(positive(value, "objectID")?).map_err(|_| "device ID overflow".into())
}
fn format(value: &Json, float: bool) -> Result<()> {
    let value=fields(value,"bitsPerChannel bytesPerFrame bytesPerPacket channelsPerFrame floatingPoint formatFlags formatID framesPerPacket interleaved nativeEndian packed reserved sampleRate signedInteger")?;
    nis(value, "sampleRate", 48_000.0)?;
    str_is(value, "formatID", "lpcm")?;
    uis(value, "formatFlags", if float { 9 } else { 12 })?;
    bool_is(value, "floatingPoint", float)?;
    bool_is(value, "signedInteger", !float)?;
    bools(value, "packed nativeEndian interleaved", true)?;
    uis(value, "channelsPerFrame", 1)?;
    uis(value, "bitsPerChannel", if float { 32 } else { 16 })?;
    uis(value, "bytesPerFrame", if float { 4 } else { 2 })?;
    uis(value, "bytesPerPacket", if float { 4 } else { 2 })?;
    uis(value, "framesPerPacket", 1)?;
    uis(value, "reserved", 0)
}

fn waveform(value: &Json, nonce: &str, routes: &str) -> Result<[u32; 2]> {
    let value=fields(value,"schema status mode realQueuePathImplemented challenge endpointPair queueContract pcm timestamps defaults lifecycle teardown failureCode failureReasons")?;
    str_is(
        value,
        "schema",
        "opensteamer.virtual-microphone-mirror-loopback.v2",
    )?;
    str_is(value, "status", "passed")?;
    str_is(value, "mode", "real-dual-audioqueue")?;
    bool_is(value, "realQueuePathImplemented", true)?;
    str_is(value, "failureCode", "none")?;
    require(
        array(value, "failureReasons")?.is_empty(),
        "waveform failure reasons",
    )?;
    let challenge=fields(field(value,"challenge")?,"algorithm version nonceFingerprint frameCount sampleCount sentinelFrameCount expectedPCMHash capturedAlignedPCMHash")?;
    str_is(
        challenge,
        "algorithm",
        "nonce-splitmix64-mono-sentinel-prbs",
    )?;
    uis(challenge, "version", 2)?;
    str_is(challenge, "nonceFingerprint", &sha256(nonce.as_bytes()))?;
    uis(challenge, "frameCount", 96_000)?;
    uis(challenge, "sampleCount", 96_000)?;
    uis(challenge, "sentinelFrameCount", 256)?;
    let hash = challenge_hash(nonce);
    str_is(challenge, "expectedPCMHash", &hash)?;
    str_is(challenge, "capturedAlignedPCMHash", &hash)?;
    let pair=fields(field(value,"endpointPair")?,"clockDomainsMatch deviceChangeNotificationCount hidden modelUIDsMatch objectIDsDistinct visible")?;
    bools(
        pair,
        "clockDomainsMatch modelUIDsMatch objectIDsDistinct",
        true,
    )?;
    uis(pair, "deviceChangeNotificationCount", 0)?;
    let ids = [
        endpoint(field(pair, "visible")?, VISIBLE, false)?,
        endpoint(field(pair, "hidden")?, HIDDEN, true)?,
    ];
    require(ids[0] != ids[1], "distinct endpoint IDs")?;
    let queue=fields(field(value,"queueContract")?,"captureDeviceFormatMatches captureDevicePhysicalFormat captureDeviceVirtualFormat captureFormatMatches captureQueueUIDMatches captureQueueUIDReadback captureReadbackFormat hiddenOutputMuted hiddenOutputVolumeScalar requestedFormat signalControlsMatch visibleInputMuted visibleInputVolumeScalar writerCallbackCount writerChallengeFullySubmitted writerDeviceFormatMatches writerDevicePhysicalFormat writerDeviceVirtualFormat writerFormatMatches writerPrimingFrameCount writerQueueUIDMatches writerQueueUIDReadback writerQueueVolumeMatches writerQueueVolumeScalar writerReadbackFormat writerSubmittedChallengeFrameCount")?;
    str_is(queue, "captureQueueUIDReadback", VISIBLE)?;
    str_is(queue, "writerQueueUIDReadback", HIDDEN)?;
    bools(queue,"captureDeviceFormatMatches captureFormatMatches captureQueueUIDMatches signalControlsMatch writerChallengeFullySubmitted writerDeviceFormatMatches writerFormatMatches writerQueueUIDMatches writerQueueVolumeMatches",true)?;
    bools(queue, "visibleInputMuted hiddenOutputMuted", false)?;
    for key in [
        "visibleInputVolumeScalar",
        "hiddenOutputVolumeScalar",
        "writerQueueVolumeScalar",
    ] {
        nis(queue, key, 1.0)?;
    }
    uis(queue, "writerSubmittedChallengeFrameCount", 96_000)?;
    positive(queue, "writerCallbackCount")?;
    require(
        uint(queue, "writerPrimingFrameCount")? >= 1920,
        "writer priming readiness",
    )?;
    for key in [
        "requestedFormat",
        "captureReadbackFormat",
        "writerReadbackFormat",
        "captureDeviceVirtualFormat",
        "captureDevicePhysicalFormat",
        "writerDeviceVirtualFormat",
        "writerDevicePhysicalFormat",
    ] {
        format(field(queue, key)?, key.contains("Device"))?;
    }
    let pcm=fields(field(value,"pcm")?,"absolutePeak alignedStartFrame alignmentCount capturedOverflow capturedPostRollFrameCount capturedSampleCount comparedFrameCount comparisonAvailable exactPCMMatches matchedFrameCount mismatchSampleCount missingFrameCount nonzeroSampleCount postRollAbsolutePeak postRollNonzeroSampleCount postRollSilenceMatches rawCaptureCallbackCount requiredPostRollFrameCount retainedPCMHash retainedSampleLimit rootMeanSquare signedInt16Compatible totalObservedSampleCount unexpectedTrailingFrameCount")?;
    bools(
        pcm,
        "comparisonAvailable exactPCMMatches postRollSilenceMatches signedInt16Compatible",
        true,
    )?;
    bool_is(pcm, "capturedOverflow", false)?;
    uis(pcm, "alignmentCount", 1)?;
    let offset = uint(pcm, "alignedStartFrame")?;
    require(offset <= 48_000, "PCM alignment bound")?;
    for key in ["comparedFrameCount", "matchedFrameCount"] {
        uis(pcm, key, 96_000)?;
    }
    zeros(pcm,"mismatchSampleCount missingFrameCount postRollAbsolutePeak postRollNonzeroSampleCount unexpectedTrailingFrameCount")?;
    uis(pcm, "requiredPostRollFrameCount", 1920)?;
    uis(pcm, "capturedPostRollFrameCount", 1920)?;
    uis(pcm, "retainedSampleLimit", 145_920)?;
    let samples = uint(pcm, "capturedSampleCount")?;
    require(
        samples >= offset + 96_000 + 1920 && samples <= 145_920,
        "complete captured PCM extent",
    )?;
    uis(pcm, "totalObservedSampleCount", samples)?;
    require(
        uint(pcm, "rawCaptureCallbackCount")? >= 2,
        "actual input readiness callbacks",
    )?;
    digest(pcm, "retainedPCMHash")?;
    require(
        uint(pcm, "nonzeroSampleCount")? >= 96_000 && uint(pcm, "nonzeroSampleCount")? <= samples,
        "PCM nonzero extent",
    )?;
    require(
        number(pcm, "rootMeanSquare")? > 0.0 && number(pcm, "rootMeanSquare")? <= 32768.0,
        "PCM RMS bound",
    )?;
    require(
        uint(pcm, "absolutePeak")? >= 12_000 && uint(pcm, "absolutePeak")? <= 32768,
        "PCM signed peak bound",
    )?;
    let defaults=fields(field(value,"defaults")?,"afterFingerprint beforeFingerprint hiddenEndpointNeverDefault inputBeforeAfterEqual mutated notificationCount outputBeforeAfterEqual systemOutputBeforeAfterEqual virtualEndpointsNeverOutputDefault")?;
    str_is(defaults, "beforeFingerprint", routes)?;
    str_is(defaults, "afterFingerprint", routes)?;
    bool_is(defaults, "mutated", false)?;
    uis(defaults, "notificationCount", 0)?;
    bools(defaults,"hiddenEndpointNeverDefault inputBeforeAfterEqual outputBeforeAfterEqual systemOutputBeforeAfterEqual virtualEndpointsNeverOutputDefault",true)?;
    let teardown=fields(field(value,"teardown")?,"callbackGatesDrained cleanupEvidenceComplete contextsReleased defaultListenerInstalled deviceListenerInstalled inputDisposeStatus inputStopStatus listenersRemoved outputDisposeStatus outputStopStatus postCloseCallbackCount queuesOpened runningStateRestored")?;
    bools(teardown,"callbackGatesDrained cleanupEvidenceComplete contextsReleased defaultListenerInstalled deviceListenerInstalled listenersRemoved queuesOpened runningStateRestored",true)?;
    zeros(
        teardown,
        "inputDisposeStatus inputStopStatus outputDisposeStatus outputStopStatus",
    )?;
    uint(teardown, "postCloseCallbackCount")?;
    let lifecycle = fields(
        field(value, "lifecycle")?,
        "cycles requiredStartOrders seedChangeClaimed zeroTimestampSeedObservableViaPublicAPI",
    )?;
    require(
        array(lifecycle, "requiredStartOrders")?
            == [Json::Text(ORDERS[0].into()), Json::Text(ORDERS[1].into())],
        "both clock orders",
    )?;
    bools(
        lifecycle,
        "seedChangeClaimed zeroTimestampSeedObservableViaPublicAPI",
        false,
    )?;
    let cycles = array(lifecycle, "cycles")?;
    require(cycles.len() == 2, "complete clock cycles")?;
    for (cycle, order) in cycles.iter().zip(ORDERS) {
        let cycle=fields(cycle,"finalHiddenSampleFrame finalVisibleSampleFrame initialHiddenSampleFrame initialVisibleSampleFrame nearZeroSharedClock queuesStoppedAndDisposed quiescentAfter quiescentBefore startOrder timelinesAdvanced")?;
        str_is(cycle, "startOrder", order)?;
        bools(cycle,"nearZeroSharedClock queuesStoppedAndDisposed quiescentAfter quiescentBefore timelinesAdvanced",true)?;
        for role in ["Visible", "Hidden"] {
            let start = uint(cycle, &format!("initial{role}SampleFrame"))?;
            let end = uint(cycle, &format!("final{role}SampleFrame"))?;
            require(start <= 48_000 && end > start, "clock advancement")?;
        }
    }
    let timestamps=fields(field(value,"timestamps")?,"alignedEvidenceAvailable callbackCount deviceTimeHostFlagMissingCount deviceTimePairCount deviceTimeRateMismatchCount deviceTimeSampleFlagMissingCount firstRawSampleFrame hostDeltaMismatchCount hostTimeMissingCount hostTimeValidCount lastRawSampleFrame lastRawSampleFrameExclusive maximumHostDeltaErrorNs measuredSourceSampleRate mirrorDeviceTimeMismatchCount nonAdvancingDeviceTimeCount nonIntegralDeviceSampleTimeCount nonIntegralSampleTimeCount nonMonotonicHostTimeCount nonMonotonicSampleTimeCount projection rawCaptureCallbackCount rawCapturedFrameCount sampleFrameDiscontinuityCount sampleTimeMissingCount sampleTimeValidCount sourceSampleRateMatches timestampFrameCount")?;
    zeros(timestamps,"deviceTimeHostFlagMissingCount deviceTimeRateMismatchCount deviceTimeSampleFlagMissingCount hostTimeMissingCount mirrorDeviceTimeMismatchCount nonAdvancingDeviceTimeCount nonIntegralDeviceSampleTimeCount nonIntegralSampleTimeCount nonMonotonicHostTimeCount nonMonotonicSampleTimeCount sampleFrameDiscontinuityCount sampleTimeMissingCount")?;
    bools(
        timestamps,
        "alignedEvidenceAvailable sourceSampleRateMatches",
        true,
    )?;
    uis(timestamps, "timestampFrameCount", 96_000)?;
    let callbacks = positive(timestamps, "callbackCount")?;
    uis(timestamps, "sampleTimeValidCount", callbacks)?;
    uis(timestamps, "hostTimeValidCount", callbacks)?;
    // Callback host cadence residuals are delivery telemetry, not the existing
    // oracle's clock verdict. Preserve that distinction rather than tightening
    // a live gate from synthetic fixture values.
    uis(timestamps, "deviceTimePairCount", 2)?;
    uint(timestamps, "maximumHostDeltaErrorNs")?;
    uint(timestamps, "hostDeltaMismatchCount")?;
    require(
        (number(timestamps, "measuredSourceSampleRate")? - 48_000.0).abs() <= 1.0,
        "measured source rate",
    )?;
    uis(
        timestamps,
        "rawCaptureCallbackCount",
        uint(pcm, "rawCaptureCallbackCount")?,
    )?;
    uis(timestamps, "rawCapturedFrameCount", samples)?;
    let first = uint(timestamps, "firstRawSampleFrame")?;
    let last = uint(timestamps, "lastRawSampleFrame")?;
    require(last > first && last < u64::MAX, "raw clock extent")?;
    uis(timestamps, "lastRawSampleFrameExclusive", last + 1)?;
    let projection=fields(field(timestamps,"projection")?,"claimMatchesCalculation claimedProjectedLastFrame consumerSampleRate headroomSatisfied projectedFirstFrame projectedLastFrame ratioDenominator ratioNumerator remainingHeadroomFrames requiredHeadroomFrames requiredHeadroomSeconds rounding schema signed32Compatible signedMaximum signedMinimum sourceSampleRate")?;
    str_is(
        projection,
        "schema",
        "opensteamer.facetime-timestamp-projection.v1",
    )?;
    str_is(projection, "rounding", "conservative-ceiling")?;
    bools(
        projection,
        "claimMatchesCalculation headroomSatisfied signed32Compatible",
        true,
    )?;
    require(
        field(projection, "signedMinimum")? == &Json::Number("-2147483648".into()),
        "signed minimum",
    )?;
    uis(projection, "signedMaximum", 2_147_483_647)?;
    nis(projection, "sourceSampleRate", 48_000.0)?;
    nis(projection, "consumerSampleRate", 24_000.0)?;
    uis(projection, "ratioNumerator", 1)?;
    uis(projection, "ratioDenominator", 2)?;
    uis(projection, "projectedFirstFrame", first / 2 + first % 2)?;
    let projected = last / 2 + last % 2;
    uis(projection, "projectedLastFrame", projected)?;
    uis(projection, "claimedProjectedLastFrame", projected)?;
    nis(projection, "requiredHeadroomSeconds", 60.0)?;
    uis(projection, "requiredHeadroomFrames", 1_440_000)?;
    require(
        projected <= 2_147_483_647 - 1_440_000,
        "independent signed clock headroom",
    )?;
    uis(
        projection,
        "remainingHeadroomFrames",
        2_147_483_647 - projected,
    )?;
    Ok(ids)
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct Epoch {
    values: Vec<u64>,
    idle: bool,
}
impl Epoch {
    fn read(value: &Object) -> Result<Self> {
        let names = [
            "instance",
            "driverLifecycle",
            "coreLifecycle",
            "timelineSeed",
            "seedGeneration",
            "anchorHostTicks",
            "lastIssuedSeed",
            "lastIssuedSessionID",
            "active",
            "visible",
            "hidden",
            "activeCore",
            "started",
            "visibleStarted",
            "hiddenStarted",
        ];
        let values = names
            .iter()
            .map(|key| uint(value, key))
            .collect::<Result<Vec<_>>>()?;
        require(
            values[0] > 0 && values[1] > 0 && values[2] % 2 == 0,
            "epoch identity/lifecycle",
        )?;
        Ok(Self {
            values,
            idle: boolean(value, "idle")?,
        })
    }
    fn idle(&self) -> bool {
        self.idle && self.values[3..6] == [0, 0, 0] && self.values[8..] == [0, 0, 0, 0, 0, 0, 0]
    }
    fn roles(&self, visible: u64, hidden: u64) -> bool {
        self.values[8..]
            == [
                visible + hidden,
                visible,
                hidden,
                visible + hidden,
                visible + hidden,
                visible,
                hidden,
            ]
    }
}

pub fn verify_public(
    bytes: &[u8],
    nonce: &str,
    instance: u64,
    routes_fingerprint: &str,
) -> Result<PublicProofReceipt> {
    require(
        hex(nonce) && hex(routes_fingerprint) && instance > 0,
        "independent invocation binding",
    )?;
    let parsed = Parser::parse(bytes)?;
    let root = fields(
        &parsed,
        "schema nonce expectedInstance effectiveUID status failureCode orders",
    )?;
    str_is(root, "schema", "beluga.microphone.public-both-order.v1")?;
    str_is(root, "nonce", nonce)?;
    uis(root, "expectedInstance", instance)?;
    uis(root, "effectiveUID", 501)?;
    str_is(root, "status", "passed")?;
    str_is(root, "failureCode", "")?;
    let orders = array(root, "orders")?;
    require(orders.len() == 2, "both actual PCM orders")?;
    let mut previous: Option<(u64, u64, Epoch)> = None;
    let mut endpoint_ids = None;
    for (order, index) in orders.iter().zip(0..2) {
        let order = fields(order, "order nonce waveform epochs")?;
        str_is(order, "order", ORDERS[index])?;
        let order_nonce = format!("{nonce}:{}", ORDERS[index]);
        str_is(order, "nonce", &order_nonce)?;
        let ids = waveform(field(order, "waveform")?, &order_nonce, routes_fingerprint)?;
        require(
            endpoint_ids.is_none_or(|previous| previous == ids),
            "endpoint identity changed between orders",
        )?;
        endpoint_ids = Some(ids);
        let observations = array(order, "epochs")?;
        require(
            observations.len() == 10,
            "complete fresh phase observations",
        )?;
        let mut epochs = Vec::new();
        for (sample, index) in observations.iter().zip(0..10) {
            let sample=fields(sample,"phase deviceUID deviceID schema sequence capturedHostTicks instance driverLifecycle coreLifecycle timelineSeed seedGeneration anchorHostTicks lastIssuedSeed lastIssuedSessionID idle active visible hidden activeCore started visibleStarted hiddenStarted")?;
            str_is(sample, "phase", PHASES[index / 2])?;
            str_is(
                sample,
                "deviceUID",
                if index % 2 == 0 { VISIBLE } else { HIDDEN },
            )?;
            uis(sample, "deviceID", u64::from(ids[index % 2]))?;
            uis(sample, "schema", 2)?;
            uis(sample, "instance", instance)?;
            let sequence = positive(sample, "sequence")?;
            let ticks = positive(sample, "capturedHostTicks")?;
            let epoch = Epoch::read(sample)?;
            if let Some((previous_sequence, previous_ticks, previous_epoch)) = &previous {
                require(
                    sequence > *previous_sequence && ticks > *previous_ticks,
                    "fresh advancing diagnostic samples",
                )?;
                require(
                    epoch.values[6] >= previous_epoch.values[6]
                        && epoch.values[7] >= previous_epoch.values[7]
                        && epoch.values[1] >= previous_epoch.values[1]
                        && epoch.values[2] >= previous_epoch.values[2],
                    "issued seed/session/lifecycle history regressed",
                )?;
            }
            previous = Some((sequence, ticks, epoch.clone()));
            epochs.push(epoch);
        }
        for pair in epochs.chunks_exact(2) {
            require(pair[0] == pair[1], "complete mirrored epoch/role identity")?;
        }
        let baseline = &epochs[0];
        let first = &epochs[2];
        let drain = &epochs[8];
        require(baseline.idle() && drain.idle(), "cleared baseline/drain")?;
        require(
            first.values[3] > baseline.values[6]
                && first.values[4] == first.values[3]
                && first.values[5] > 0,
            "fresh first-client seed",
        )?;
        require(
            first.roles(u64::from(index == 0), u64::from(index == 1)),
            "actual intended first-client role",
        )?;
        for epoch in &epochs[2..8] {
            require(
                !epoch.idle && epoch.values[3..6] == first.values[3..6],
                "same seed/anchor through join/proof",
            )?;
        }
        require(
            epochs[4].roles(1, 1) && epochs[6].roles(1, 1),
            "exact owned role join/proof",
        )?;
        require(
            drain.values[6] == first.values[3]
                && drain.values[7] > baseline.values[7]
                && drain.values[1] > baseline.values[1]
                && drain.values[2] > baseline.values[2],
            "real final drain/history",
        )?;
    }
    let (last_sequence, last_captured_ticks, epoch) =
        previous.ok_or("missing diagnostic result")?;
    let ids = endpoint_ids.ok_or("missing endpoints")?;
    Ok(PublicProofReceipt {
        source_sha256: sha256(bytes),
        instance,
        visible_device: ids[0],
        hidden_device: ids[1],
        last_sequence,
        last_captured_ticks,
        last_issued_seed: epoch.values[6],
        last_issued_session: epoch.values[7],
        driver_lifecycle: epoch.values[1],
        core_lifecycle: epoch.values[2],
    })
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum IdleProgress {
    BootstrapRequiresFreshIdleAndPublicProbe,
    PriorBootstrapRequiresFreshMirroredIdle,
    InitialRequiresPublicProbe,
    IdleAccepted,
}
pub struct IdleExpected<'a> {
    pub phase: &'a str,
    pub schema: u64,
    pub nonce: &'a str,
    pub instance: Option<u64>,
    pub exit_code: i32,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct IdleReceipt {
    pub source_sha256: String,
    pub progress: IdleProgress,
    pub phase: String,
    pub schema: u64,
    pub instance: u64,
    pub visible_device: u32,
    pub hidden_device: u32,
    pub visible_stream: u32,
    pub hidden_stream: u32,
    pub first_sequence: u64,
    pub first_captured_ticks: u64,
    pub last_sequence: u64,
    pub last_captured_ticks: u64,
    pub last_issued_seed: u64,
    pub last_issued_session: u64,
    pub driver_lifecycle: u64,
    pub core_lifecycle: u64,
}

pub fn verify_idle(bytes: &[u8], expected: IdleExpected<'_>) -> Result<IdleReceipt> {
    require(hex(expected.nonce), "idle invocation nonce")?;
    let bootstrap = expected.instance.is_none();
    require(
        matches!(
            (expected.phase, expected.schema),
            ("before-publish", 1)
                | ("after-reload", 2)
                | ("after-probe", 2)
                | ("after-rollback", 1)
        ) && (!bootstrap || matches!(expected.phase, "after-reload" | "after-rollback")),
        "idle invocation phase/schema",
    )?;
    let parsed = Parser::parse(bytes)?;
    let root=fields(&parsed,"contract kind idleAcceptance requiresPublicProbe requiresFreshMirroredIdle initialPristine phase schema nonce effectiveUID expectedInstance visibleUID writerUID visibleDeviceID writerDeviceID endpointContract visibleStreamID writerStreamID observations")?;
    str_is(root, "contract", "beluga.microphone.passive-idle.v1")?;
    str_is(root, "phase", expected.phase)?;
    uis(root, "schema", expected.schema)?;
    str_is(root, "nonce", expected.nonce)?;
    uis(root, "effectiveUID", 501)?;
    str_is(root, "visibleUID", VISIBLE)?;
    str_is(root, "writerUID", HIDDEN)?;
    str_is(
        root,
        "endpointContract",
        "exact-product-model-role-native-f32-mono-48000-clock-6f73564d.v1",
    )?;
    let instance = positive(root, "expectedInstance")?;
    if let Some(pinned) = expected.instance {
        require(pinned > 0 && instance == pinned, "idle pinned instance")?;
    }
    let initial = expected.phase == "after-reload";
    let prior_bootstrap = bootstrap && expected.phase == "after-rollback";
    let progress = if prior_bootstrap {
        IdleProgress::PriorBootstrapRequiresFreshMirroredIdle
    } else if bootstrap {
        IdleProgress::BootstrapRequiresFreshIdleAndPublicProbe
    } else if initial {
        IdleProgress::InitialRequiresPublicProbe
    } else {
        IdleProgress::IdleAccepted
    };
    let kind = if prior_bootstrap {
        "PRIOR_INSTANCE_REQUIRES_FRESH_MIRRORED_IDLE"
    } else if bootstrap {
        "BOOTSTRAP_INSTANCE_REQUIRES_FRESH_IDLE_AND_PUBLIC_PROBE"
    } else if initial {
        "INITIAL_COMPLETE_IDLE_REQUIRES_PUBLIC_PROBE"
    } else {
        "NORMAL_IDLE"
    };
    str_is(root, "kind", kind)?;
    bool_is(root, "idleAcceptance", !initial && !prior_bootstrap)?;
    bool_is(root, "requiresPublicProbe", initial)?;
    bool_is(root, "requiresFreshMirroredIdle", bootstrap)?;
    let pristine = boolean(root, "initialPristine")?;
    require(!pristine || initial, "pristine classification phase")?;
    require(
        expected.exit_code == if initial || prior_bootstrap { 75 } else { 0 },
        "idle exit code/progression",
    )?;
    let ids = [
        positive(root, "visibleDeviceID")?,
        positive(root, "writerDeviceID")?,
    ];
    let streams = [
        positive(root, "visibleStreamID")?,
        positive(root, "writerStreamID")?,
    ];
    require(
        ids[0] != ids[1]
            && streams[0] != streams[1]
            && ids
                .iter()
                .chain(streams.iter())
                .all(|id| *id <= u32::MAX as u64),
        "idle endpoint IDs",
    )?;
    let observations = array(root, "observations")?;
    require(
        observations.len() == if bootstrap { 1 } else { 4 },
        "idle observation count",
    )?;
    let mut first: Option<(u64, u64)> = None;
    let mut previous: Option<(u64, u64, Vec<u64>, u64, Option<u64>)> = None;
    for (index, observation) in observations.iter().enumerate() {
        let keys = if expected.schema == 2 {
            "deviceUID deviceID selector sequence capturedHostTicks beforeHostTicks afterHostTicks byteCount payloadSHA256 registeredCount registryRevision epoch"
        } else {
            "deviceUID deviceID selector sequence capturedHostTicks beforeHostTicks afterHostTicks byteCount payloadSHA256 registeredCount epoch"
        };
        let observation = fields(observation, keys)?;
        str_is(
            observation,
            "deviceUID",
            if index % 2 == 0 { VISIBLE } else { HIDDEN },
        )?;
        uis(observation, "deviceID", ids[index % 2])?;
        str_is(
            observation,
            "selector",
            if expected.schema == 2 { "osD2" } else { "osDS" },
        )?;
        let sequence = positive(observation, "sequence")?;
        let ticks = positive(observation, "capturedHostTicks")?;
        first.get_or_insert((sequence, ticks));
        require(
            positive(observation, "beforeHostTicks")? <= ticks
                && ticks <= positive(observation, "afterHostTicks")?,
            "actual capture freshness window",
        )?;
        digest(observation, "payloadSHA256")?;
        let registered = uint(observation, "registeredCount")?;
        let revision = if expected.schema == 2 {
            Some(uint(observation, "registryRevision")?)
        } else {
            None
        };
        let bytes = uint(observation, "byteCount")?;
        require(
            if expected.schema == 1 {
                registered <= 64 && bytes == 8_608
            } else {
                registered <= (1_048_576 - 3_504) / 88 && bytes == 3_504 + registered * 88
            },
            "complete diagnostic extent",
        )?;
        let epoch=fields(field(observation,"epoch")?,"instance driverLifecycle coreLifecycle timelineSeed seedGeneration anchorHostTicks lastIssuedSeed lastIssuedSessionID")?;
        let epoch = [
            "instance",
            "driverLifecycle",
            "coreLifecycle",
            "timelineSeed",
            "seedGeneration",
            "anchorHostTicks",
            "lastIssuedSeed",
            "lastIssuedSessionID",
        ]
        .iter()
        .map(|key| uint(epoch, key))
        .collect::<Result<Vec<_>>>()?;
        require(
            epoch[0] == instance && epoch[1] > 0 && epoch[2] % 2 == 0 && epoch[3..6] == [0, 0, 0],
            "complete idle epoch",
        )?;
        if pristine {
            require(
                registered == 0
                    && bytes == 3504
                    && epoch[1] == 1
                    && epoch[2..] == [0, 0, 0, 0, 0, 0],
                "initialized pristine metadata contradicted",
            )?;
        }
        if expected.phase == "after-probe" {
            require(
                epoch[1] > 1 && epoch[2] > 0 && epoch[6] > 0 && epoch[7] > 0,
                "owned public history still required",
            )?;
        }
        if let Some((prev_seq, prev_ticks, prev_epoch, prev_registered, prev_revision)) = &previous
        {
            require(
                sequence > *prev_seq
                    && ticks > *prev_ticks
                    && epoch == *prev_epoch
                    && registered == *prev_registered
                    && revision == *prev_revision,
                "four stable advancing mirrored idle observations",
            )?;
        }
        previous = Some((sequence, ticks, epoch, registered, revision));
    }
    let (last_sequence, last_captured_ticks, epoch, _, _) =
        previous.ok_or("idle observation missing")?;
    let (first_sequence, first_captured_ticks) = first.ok_or("idle observation missing")?;
    Ok(IdleReceipt {
        source_sha256: sha256(bytes),
        progress,
        phase: expected.phase.into(),
        schema: expected.schema,
        instance,
        visible_device: ids[0] as u32,
        hidden_device: ids[1] as u32,
        visible_stream: streams[0] as u32,
        hidden_stream: streams[1] as u32,
        first_sequence,
        first_captured_ticks,
        last_sequence,
        last_captured_ticks,
        last_issued_seed: epoch[6],
        last_issued_session: epoch[7],
        driver_lifecycle: epoch[1],
        core_lifecycle: epoch[2],
    })
}

/// The after-probe helper is passive; positive history alone is not the owned
/// public probe. Require the fresh receipt to retain that exact final epoch.
pub fn bind_after_probe(idle: &IdleReceipt, public: &PublicProofReceipt) -> Result<()> {
    require(
        idle.progress == IdleProgress::IdleAccepted
            && idle.phase == "after-probe"
            && idle.schema == 2
            && idle.instance == public.instance
            && idle.visible_device == public.visible_device
            && idle.hidden_device == public.hidden_device
            && idle.first_sequence > public.last_sequence
            && idle.first_captured_ticks > public.last_captured_ticks
            && idle.last_issued_seed == public.last_issued_seed
            && idle.last_issued_session == public.last_issued_session
            && idle.driver_lifecycle >= public.driver_lifecycle
            && idle.core_lifecycle >= public.core_lifecycle,
        "after-probe idle is not bound to the owned both-order public proof",
    )
}

/// A recovery bootstrap only identifies the freshly loaded prior instance. The
/// caller must independently prove prior protected bytes and the new CoreAudio
/// generation; this binding then requires all four later mirrored-v1 reads.
pub fn bind_after_rollback(bootstrap: &IdleReceipt, idle: &IdleReceipt) -> Result<()> {
    require(
        bootstrap.progress == IdleProgress::PriorBootstrapRequiresFreshMirroredIdle
            && bootstrap.phase == "after-rollback"
            && bootstrap.schema == 1
            && idle.progress == IdleProgress::IdleAccepted
            && idle.phase == "after-rollback"
            && idle.schema == 1
            && idle.instance == bootstrap.instance
            && idle.visible_device == bootstrap.visible_device
            && idle.hidden_device == bootstrap.hidden_device
            && idle.visible_stream == bootstrap.visible_stream
            && idle.hidden_stream == bootstrap.hidden_stream
            && idle.first_sequence > bootstrap.last_sequence
            && idle.first_captured_ticks > bootstrap.last_captured_ticks
            && idle.last_issued_seed >= bootstrap.last_issued_seed
            && idle.last_issued_session >= bootstrap.last_issued_session
            && idle.driver_lifecycle >= bootstrap.driver_lifecycle
            && idle.core_lifecycle >= bootstrap.core_lifecycle,
        "after-rollback idle is not bound to the fresh prior-instance bootstrap",
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    const NONCE: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    fn routes() -> String {
        sha256(format!("{VISIBLE}\0BuiltInSpeakerDevice\0BuiltInSpeakerDevice").as_bytes())
    }
    fn fixture() -> Json {
        Parser::parse(include_bytes!(
            "microphone-v9-idle-proof/offline-public-fixture.json"
        ))
        .unwrap()
    }
    fn encode(value: &Json) -> String {
        match value {
            Json::Null => "null".into(),
            Json::Bool(v) => v.to_string(),
            Json::Number(v) => v.clone(),
            Json::Text(v) => format!("\"{}\"", v.replace('\\', "\\\\").replace('"', "\\\"")),
            Json::Array(v) => format!("[{}]", v.iter().map(encode).collect::<Vec<_>>().join(",")),
            Json::Object(v) => format!(
                "{{{}}}",
                v.iter()
                    .map(|(k, v)| format!("{}:{}", encode(&Json::Text(k.clone())), encode(v)))
                    .collect::<Vec<_>>()
                    .join(",")
            ),
        }
    }
    fn node<'a>(value: &'a mut Json, path: &[&str]) -> &'a mut Json {
        if path.is_empty() {
            return value;
        }
        let next = match value {
            Json::Object(v) => v.get_mut(path[0]).unwrap(),
            Json::Array(v) => &mut v[path[0].parse::<usize>().unwrap()],
            _ => panic!("fixture path"),
        };
        node(next, &path[1..])
    }
    fn change(value: &mut Json, path: &[&str], replacement: Json) {
        *node(value, path) = replacement;
    }
    fn n(v: u64) -> Json {
        Json::Number(v.to_string())
    }
    fn verify(value: &Json) -> Result<PublicProofReceipt> {
        verify_public(encode(value).as_bytes(), NONCE, 42, &routes())
    }
    fn idle_fixture(phase: &str, schema: u64, bootstrap: bool, registered: u64) -> Json {
        let count = if bootstrap { 1 } else { 4 };
        let observations=(0..count).map(|i|format!(r#"{{"deviceUID":"{}","deviceID":{},"selector":"{}","sequence":{},"capturedHostTicks":{},"beforeHostTicks":{},"afterHostTicks":{},"byteCount":{},"payloadSHA256":"{}","registeredCount":{},{}"epoch":{{"instance":42,"driverLifecycle":27,"coreLifecycle":38,"timelineSeed":0,"seedGeneration":0,"anchorHostTicks":0,"lastIssuedSeed":11,"lastIssuedSessionID":15}}}}"#,
            if i%2==0{VISIBLE}else{HIDDEN},if i%2==0{101}else{202},if schema==2{"osD2"}else{"osDS"},100+i,200+i,199+i,201+i,
            if schema==2{3504+registered*88}else{8608},"b".repeat(64),registered,if schema==2{"\"registryRevision\":20,"}else{""})).collect::<Vec<_>>().join(",");
        let initial = phase == "after-reload";
        let kind = if bootstrap && phase == "after-rollback" {
            "PRIOR_INSTANCE_REQUIRES_FRESH_MIRRORED_IDLE"
        } else if bootstrap {
            "BOOTSTRAP_INSTANCE_REQUIRES_FRESH_IDLE_AND_PUBLIC_PROBE"
        } else if initial {
            "INITIAL_COMPLETE_IDLE_REQUIRES_PUBLIC_PROBE"
        } else {
            "NORMAL_IDLE"
        };
        let bytes = format!(
            r#"{{"contract":"beluga.microphone.passive-idle.v1","kind":"{kind}","idleAcceptance":{},"requiresPublicProbe":{initial},"requiresFreshMirroredIdle":{bootstrap},"initialPristine":false,"phase":"{phase}","schema":{schema},"nonce":"{NONCE}","effectiveUID":501,"expectedInstance":42,"visibleUID":"{VISIBLE}","writerUID":"{HIDDEN}","visibleDeviceID":101,"writerDeviceID":202,"endpointContract":"exact-product-model-role-native-f32-mono-48000-clock-6f73564d.v1","visibleStreamID":303,"writerStreamID":404,"observations":[{observations}]}}"#,
            !initial && !bootstrap
        );
        Parser::parse(bytes.as_bytes()).unwrap()
    }
    fn idle(
        value: &Json,
        phase: &str,
        schema: u64,
        bootstrap: bool,
        exit_code: i32,
    ) -> Result<IdleReceipt> {
        verify_idle(
            encode(value).as_bytes(),
            IdleExpected {
                phase,
                schema,
                nonce: NONCE,
                instance: if bootstrap { None } else { Some(42) },
                exit_code,
            },
        )
    }

    #[test]
    fn sha_and_nonce_hash_known_vectors() {
        assert_eq!(
            sha256(b""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
        assert_eq!(
            sha256(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
        assert_eq!(
            challenge_hash(&format!("{NONCE}:visible-first")),
            "20949d9c8c4e6d5f235225acf61a47d31d99396bfeca6f651c3f18ba12f42388"
        );
        assert_ne!(
            challenge_hash(&format!("{NONCE}:visible-first")),
            challenge_hash(&format!("{NONCE}:hidden-first"))
        );
    }
    #[test]
    fn complete_explicit_offline_both_order_receipt() {
        // This is a parser fixture built from offline synthetic waveform output.
        // It is not a captured live receipt and does not claim deployment.
        let receipt = verify(&fixture()).unwrap();
        assert_eq!(receipt.last_issued_seed, 11);
        assert_eq!(receipt.last_issued_session, 15);
    }
    #[test]
    fn strict_json_duplicate_extent_encoding_and_token_refusals() {
        for bytes in [
            b"{\"x\":1,\"x\":2}".as_slice(),
            b"{\"x\":1,\"\\u0078\":2}",
            b"[1,]",
            b"{\"x\":01}",
            b"{\"x\":NaN}",
            b"{\"x\":1} true",
            b"\"\\ud800\"",
            b"\"\xff\"",
        ] {
            assert!(Parser::parse(bytes).is_err(), "{bytes:?}");
        }
        assert!(Parser::parse(&vec![b' '; MAX_BYTES + 1]).is_err());
        assert!(
            Parser::parse(format!("{}0{}", "[".repeat(18), "]".repeat(18)).as_bytes()).is_err()
        );
        assert!(Parser::parse(b"{\"x\":-0}").is_ok()); // Valid JSON; typed uint rejects it.
    }
    #[test]
    fn integer_identity_cannot_be_float_exponent_bool_string_or_overflow() {
        for path in [
            vec!["expectedInstance"],
            vec!["effectiveUID"],
            vec!["orders", "0", "epochs", "0", "schema"],
            vec!["orders", "0", "epochs", "0", "deviceID"],
            vec!["orders", "0", "epochs", "0", "active"],
        ] {
            for replacement in [
                Json::Number("42.0".into()),
                Json::Number("42e0".into()),
                Json::Bool(true),
                Json::Text("42".into()),
                Json::Number("18446744073709551616".into()),
                Json::Number("-0".into()),
            ] {
                let mut value = fixture();
                change(&mut value, &path, replacement);
                assert!(verify(&value).is_err(), "{path:?}");
            }
        }
    }
    #[test]
    fn exact_fields_at_every_nested_contract_boundary() {
        for path in [
            vec![],
            vec!["orders", "0"],
            vec!["orders", "0", "waveform"],
            vec!["orders", "0", "waveform", "queueContract"],
            vec!["orders", "0", "waveform", "pcm"],
            vec!["orders", "0", "waveform", "timestamps", "projection"],
            vec!["orders", "0", "epochs", "0"],
        ] {
            let mut value = fixture();
            if let Json::Object(v) = node(&mut value, &path) {
                v.insert("unreviewed".into(), Json::Bool(true));
            }
            assert!(verify(&value).is_err());
        }
    }
    #[test]
    fn actual_first_role_and_both_role_counts_all_mandatory() {
        for order in ["0", "1"] {
            for sample in ["0", "2", "4", "6", "8"] {
                for key in [
                    "active",
                    "visible",
                    "hidden",
                    "activeCore",
                    "started",
                    "visibleStarted",
                    "hiddenStarted",
                ] {
                    let mut value = fixture();
                    change(&mut value, &["orders", order, "epochs", sample, key], n(7));
                    assert!(verify(&value).is_err(), "{order}/{sample}/{key}");
                }
            }
        }
    }
    #[test]
    fn owned_nonce_full_pcm_not_assertion_only_status() {
        for path in [
            vec!["orders", "0", "nonce"],
            vec!["orders", "0", "waveform", "challenge", "expectedPCMHash"],
            vec![
                "orders",
                "0",
                "waveform",
                "challenge",
                "capturedAlignedPCMHash",
            ],
            vec!["orders", "1", "waveform", "challenge", "nonceFingerprint"],
        ] {
            let mut value = fixture();
            change(&mut value, &path, Json::Text("f".repeat(64)));
            assert!(verify(&value).is_err());
        }
        let mut value = fixture();
        change(
            &mut value,
            &["orders", "0", "waveform", "mode"],
            Json::Text("synthetic-self-test".into()),
        );
        assert!(verify(&value).is_err());
        for key in [
            "matchedFrameCount",
            "comparedFrameCount",
            "capturedPostRollFrameCount",
        ] {
            let mut value = fixture();
            change(&mut value, &["orders", "0", "waveform", "pcm", key], n(1));
            assert!(verify(&value).is_err());
        }
    }
    #[test]
    fn route_teardown_format_and_timestamp_failure_mutants() {
        for path in [
            vec!["orders", "0", "waveform", "defaults", "notificationCount"],
            vec!["orders", "1", "waveform", "teardown", "inputDisposeStatus"],
            vec![
                "orders",
                "0",
                "waveform",
                "queueContract",
                "writerDevicePhysicalFormat",
                "formatFlags",
            ],
            vec![
                "orders",
                "0",
                "waveform",
                "timestamps",
                "nonAdvancingDeviceTimeCount",
            ],
            vec![
                "orders",
                "0",
                "waveform",
                "timestamps",
                "projection",
                "claimedProjectedLastFrame",
            ],
        ] {
            let mut value = fixture();
            change(&mut value, &path, n(1));
            assert!(verify(&value).is_err(), "{path:?}");
        }
        let mut value = fixture();
        change(
            &mut value,
            &["orders", "1", "waveform", "teardown", "listenersRemoved"],
            Json::Bool(false),
        );
        assert!(verify(&value).is_err());
    }
    #[test]
    fn phase_freshness_mirroring_join_drain_and_history_refusals() {
        for (order, sample, key) in [
            ("0", "2", "timelineSeed"),
            ("0", "4", "anchorHostTicks"),
            ("0", "8", "coreLifecycle"),
            ("0", "3", "lastIssuedSessionID"),
            ("1", "0", "sequence"),
            ("1", "0", "capturedHostTicks"),
            ("1", "0", "lastIssuedSeed"),
            ("1", "0", "lastIssuedSessionID"),
            ("1", "0", "driverLifecycle"),
            ("1", "0", "coreLifecycle"),
        ] {
            let mut value = fixture();
            change(&mut value, &["orders", order, "epochs", sample, key], n(0));
            assert!(verify(&value).is_err(), "{key}");
        }
    }
    #[test]
    fn callback_delivery_residual_remains_telemetry_not_new_gate() {
        let mut value = fixture();
        change(
            &mut value,
            &[
                "orders",
                "0",
                "waveform",
                "timestamps",
                "hostDeltaMismatchCount",
            ],
            n(4),
        );
        change(
            &mut value,
            &[
                "orders",
                "0",
                "waveform",
                "timestamps",
                "maximumHostDeltaErrorNs",
            ],
            n(2_000_000),
        );
        assert!(verify(&value).is_ok());
    }
    #[test]
    fn idle_full_v1_64_and_v2_70_registrations_are_allowed() {
        assert_eq!(
            idle(
                &idle_fixture("before-publish", 1, false, 64),
                "before-publish",
                1,
                false,
                0
            )
            .unwrap()
            .progress,
            IdleProgress::IdleAccepted
        );
        assert_eq!(
            idle(
                &idle_fixture("after-probe", 2, false, 70),
                "after-probe",
                2,
                false,
                0
            )
            .unwrap()
            .progress,
            IdleProgress::IdleAccepted
        );
    }
    #[test]
    fn bootstrap_and_initial_have_non_green_typed_progress_only() {
        for bootstrap in [false, true] {
            let value = idle_fixture("after-reload", 2, bootstrap, 70);
            let receipt = idle(&value, "after-reload", 2, bootstrap, 75).unwrap();
            assert_ne!(receipt.progress, IdleProgress::IdleAccepted);
            assert!(idle(&value, "after-reload", 2, bootstrap, 0).is_err());
        }
        let mut pristine = idle_fixture("after-reload", 2, true, 0);
        change(&mut pristine, &["initialPristine"], Json::Bool(true));
        change(
            &mut pristine,
            &["observations", "0", "registryRevision"],
            n(0),
        );
        for (key, value) in [
            ("driverLifecycle", 1),
            ("coreLifecycle", 0),
            ("lastIssuedSeed", 0),
            ("lastIssuedSessionID", 0),
        ] {
            change(
                &mut pristine,
                &["observations", "0", "epoch", key],
                n(value),
            );
        }
        assert!(idle(&pristine, "after-reload", 2, true, 75).is_ok());
        change(
            &mut pristine,
            &["observations", "0", "epoch", "lastIssuedSeed"],
            n(1),
        );
        assert!(idle(&pristine, "after-reload", 2, true, 75).is_err());
    }
    #[test]
    fn fresh_prior_rollback_bootstrap_is_not_candidate_pcm_or_idle_success() {
        for bootstrap in [true, false] {
            let mut value = idle_fixture("after-rollback", 1, bootstrap, 64);
            for index in 0..if bootstrap { 1 } else { 4 } {
                let index = index.to_string();
                for (key, v) in [
                    ("driverLifecycle", 1),
                    ("coreLifecycle", 0),
                    ("lastIssuedSeed", 0),
                    ("lastIssuedSessionID", 0),
                ] {
                    change(&mut value, &["observations", &index, "epoch", key], n(v));
                }
            }
            let exit_code = if bootstrap { 75 } else { 0 };
            let receipt = idle(&value, "after-rollback", 1, bootstrap, exit_code).unwrap();
            assert_eq!(
                receipt.progress,
                if bootstrap {
                    IdleProgress::PriorBootstrapRequiresFreshMirroredIdle
                } else {
                    IdleProgress::IdleAccepted
                }
            );
            assert!(idle(
                &value,
                "after-rollback",
                1,
                bootstrap,
                if bootstrap { 0 } else { 75 }
            )
            .is_err());
            assert!(bind_after_probe(&receipt, &verify(&fixture()).unwrap()).is_err());
            assert!(idle(&value, "before-publish", 1, bootstrap, exit_code).is_err());
        }
    }
    #[test]
    fn prior_recovery_binding_requires_all_four_later_reads_and_same_instance() {
        let bootstrap = idle(
            &idle_fixture("after-rollback", 1, true, 64),
            "after-rollback",
            1,
            true,
            75,
        )
        .unwrap();
        let mut value = idle_fixture("after-rollback", 1, false, 64);
        for index in 0..4 {
            let index_text = index.to_string();
            for (key, v) in [
                ("sequence", 101 + index),
                ("capturedHostTicks", 201 + index),
                ("beforeHostTicks", 200 + index),
                ("afterHostTicks", 202 + index),
            ] {
                change(&mut value, &["observations", &index_text, key], n(v));
            }
        }
        let receipt = idle(&value, "after-rollback", 1, false, 0).unwrap();
        assert!(bind_after_rollback(&bootstrap, &receipt).is_ok());
        assert!(bind_after_rollback(&bootstrap, &bootstrap).is_err());
        let cached = idle(
            &idle_fixture("after-rollback", 1, false, 64),
            "after-rollback",
            1,
            false,
            0,
        )
        .unwrap();
        assert!(cached.last_sequence > bootstrap.last_sequence);
        assert!(bind_after_rollback(&bootstrap, &cached).is_err());
        for key in 0..10 {
            let mut changed = receipt.clone();
            match key {
                0 => changed.instance += 1,
                1 => changed.visible_device += 1,
                2 => changed.hidden_device += 1,
                3 => changed.visible_stream += 1,
                4 => changed.hidden_stream += 1,
                5 => changed.first_captured_ticks = bootstrap.last_captured_ticks,
                6 => changed.last_issued_seed = bootstrap.last_issued_seed - 1,
                7 => changed.last_issued_session = bootstrap.last_issued_session - 1,
                8 => changed.driver_lifecycle = bootstrap.driver_lifecycle - 1,
                9 => changed.core_lifecycle = bootstrap.core_lifecycle - 1,
                _ => unreachable!(),
            }
            assert!(bind_after_rollback(&bootstrap, &changed).is_err(), "{key}");
        }
        let candidate = idle(
            &idle_fixture("after-reload", 2, true, 64),
            "after-reload",
            2,
            true,
            75,
        )
        .unwrap();
        assert!(bind_after_rollback(&candidate, &receipt).is_err());
    }
    #[test]
    fn idle_extent_schema_instance_churn_and_freshness_refusals() {
        for path in [
            vec!["expectedInstance"],
            vec!["observations", "0", "byteCount"],
            vec!["observations", "1", "sequence"],
            vec!["observations", "1", "capturedHostTicks"],
            vec!["observations", "1", "epoch", "instance"],
            vec!["observations", "1", "epoch", "driverLifecycle"],
            vec!["observations", "1", "epoch", "timelineSeed"],
            vec!["observations", "1", "registeredCount"],
        ] {
            let mut value = idle_fixture("after-probe", 2, false, 70);
            change(&mut value, &path, n(1));
            assert!(
                idle(&value, "after-probe", 2, false, 0).is_err(),
                "{path:?}"
            );
        }
        let mut value = idle_fixture("after-probe", 2, false, 70);
        change(
            &mut value,
            &["observations", "0", "selector"],
            Json::Text("osDS".into()),
        );
        assert!(idle(&value, "after-probe", 2, false, 0).is_err());
    }
    #[test]
    fn idle_history_is_not_owned_public_pcm_and_binding_is_required() {
        let public = verify(&fixture()).unwrap();
        let value = idle_fixture("after-probe", 2, false, 70);
        let mut idle_receipt = idle(&value, "after-probe", 2, false, 0).unwrap();
        assert!(bind_after_probe(&idle_receipt, &public).is_ok());
        let mut overlap = idle_receipt.clone();
        overlap.first_sequence = public.last_sequence;
        assert!(overlap.last_sequence > public.last_sequence);
        assert!(bind_after_probe(&overlap, &public).is_err());
        overlap = idle_receipt.clone();
        overlap.first_captured_ticks = public.last_captured_ticks;
        assert!(bind_after_probe(&overlap, &public).is_err());
        idle_receipt.last_issued_seed += 1;
        assert!(bind_after_probe(&idle_receipt, &public).is_err());
        let initial = idle(
            &idle_fixture("after-reload", 2, false, 70),
            "after-reload",
            2,
            false,
            75,
        )
        .unwrap();
        assert!(bind_after_probe(&initial, &public).is_err());
    }
    #[test]
    fn malformed_unknown_refused_receipts_never_accept() {
        assert!(verify_idle(b"{\"contract\":\"beluga.microphone.passive-idle.v1\",\"kind\":\"REFUSED\",\"idleAcceptance\":false,\"error\":\"PROPERTY_READ\"}",IdleExpected{phase:"after-reload",schema:2,nonce:NONCE,instance:None,exit_code:65}).is_err());
        assert!(verify_public(b"{\"status\":\"passed\"}", NONCE, 42, &routes()).is_err());
    }
}
