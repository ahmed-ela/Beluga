package com.elamin.beluga.protocol;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/** Bounded full-host SDP admission. No native, microphone, or rendered-frame authority. */
final class WebRtcViewerSdp {
    static final int MAXIMUM_BYTES = 40_000;
    enum CandidateFailureCode {
        ICE_SDP_MID_UNKNOWN, ICE_SDP_INDEX_UNKNOWN, ICE_SDP_LOCATOR_CONFLICT, ICE_SDP_LOCATOR_MISSING,
        ICE_SDP_CANDIDATE_BOUNDS, ICE_SDP_TOKEN_COUNT, ICE_SDP_TOKEN_CHARACTERS,
        ICE_SDP_UFRAG_DUPLICATE, ICE_SDP_UFRAG_MISSING_VALUE, ICE_SDP_UFRAG_INVALID_TOKEN,
        ICE_SDP_UFRAG_CONFLICT, ICE_SDP_UFRAG_REQUIRED, ICE_SDP_UFRAG_MISMATCH, ICE_SDP_PAYLOAD_INVALID
    }
    static final class CandidateFailure extends IllegalArgumentException {
        private static final long serialVersionUID = 1L;
        final CandidateFailureCode code;
        CandidateFailure(CandidateFailureCode code) { super("Beluga native SDP refused"); this.code = code; }
    }
    static final class Section {
        final int index;
        final String kind, mid, ufrag, direction, track;
        final List<String> lines;
        Section(int index, String kind, String mid, String ufrag, String direction, String track,
                List<String> lines) {
            this.index = index; this.kind = kind; this.mid = mid; this.ufrag = ufrag;
            this.direction = direction; this.track = track;
            this.lines = Collections.unmodifiableList(new ArrayList<>(lines));
        }
        boolean receivesMedia() { return "system-audio".equals(track) || "screen-video".equals(track); }
    }
    static final class Description {
        final String text;
        final List<Section> sections;
        final Section audio, video;
        Description(String text, List<Section> sections, Section audio, Section video) {
            this.text = text; this.sections = Collections.unmodifiableList(new ArrayList<>(sections));
            this.audio = audio; this.video = video;
        }
        Section locate(String mid, Integer index) {
            Section byMID = null, byIndex = null;
            if (mid != null) for (Section section : sections) if (mid.equals(section.mid)) byMID = section;
            if (index != null && index >= 0 && index < sections.size()) byIndex = sections.get(index);
            if (mid != null && byMID == null) throw new CandidateFailure(CandidateFailureCode.ICE_SDP_MID_UNKNOWN);
            if (index != null && byIndex == null) throw new CandidateFailure(CandidateFailureCode.ICE_SDP_INDEX_UNKNOWN);
            if (byMID != null && byIndex != null && byMID != byIndex)
                throw new CandidateFailure(CandidateFailureCode.ICE_SDP_LOCATOR_CONFLICT);
            Section result = byMID != null ? byMID : byIndex;
            if (result == null) throw new CandidateFailure(CandidateFailureCode.ICE_SDP_LOCATOR_MISSING);
            return result;
        }
    }

    static Description offer(String text) {
        List<List<String>> grouped = grouped(text);
        List<Section> sections = parse(grouped);
        Section audio = null, video = null;
        int silentAudio = 0, application = 0;
        for (Section section : sections) {
            if ("audio".equals(section.kind) && "sendonly".equals(section.direction)
                    && "system-audio".equals(section.track)) {
                if (audio != null || opus(section.lines).isEmpty()) throw malformed();
                audio = section;
            } else if ("video".equals(section.kind) && "sendonly".equals(section.direction)
                    && "screen-video".equals(section.track)) {
                if (video != null || !hasCodec(section.lines, "h264/90000")) throw malformed();
                video = section;
            } else if ("audio".equals(section.kind) && "recvonly".equals(section.direction)
                    && section.track == null) {
                if (++silentAudio > 1) throw malformed();
            } else if ("application".equals(section.kind) && section.track == null) {
                if (++application > 1) throw malformed();
            } else throw malformed();
        }
        if (audio == null || video == null || application != 1 || sections.size() > 4) throw malformed();
        return new Description(text, sections, audio, video);
    }

    /** Local answer only: refuse sending sections and require the offered stereo preference. */
    static Description stereoAnswer(String text, Description offer) {
        List<List<String>> grouped = grouped(text);
        List<Section> before = parse(grouped);
        if (before.size() != offer.sections.size()) throw malformed();
        for (Section section : before) {
            Section offered = offer.sections.get(section.index);
            if (!section.kind.equals(offered.kind) || !section.mid.equals(offered.mid)) throw malformed();
            if (offered.receivesMedia()) {
                if (!"recvonly".equals(section.direction)) throw malformed();
            } else if (!"application".equals(section.kind) && !"inactive".equals(section.direction)) throw malformed();
        }
        List<String> payloads = opus(before.get(offer.audio.index).lines);
        if (payloads.isEmpty()) throw malformed();
        List<String> target = grouped.get(offer.audio.index + 1);
        for (String payload : payloads) {
            if (!offeredStereo(offer.audio.lines, payload)) throw malformed();
            String prefix = "a=fmtp:" + payload + " ";
            int found = -1;
            for (int i = 0; i < target.size(); i++) if (target.get(i).startsWith(prefix)) {
                if (found != -1) throw malformed();
                found = i;
            }
            List<String> retained = new ArrayList<>();
            if (found != -1) for (String parameter : target.get(found).substring(prefix.length()).split(";")) {
                String part = parameter.trim();
                String name = part.split("=", 2)[0].trim().toLowerCase(Locale.ROOT);
                if (!"stereo".equals(name) && !"sprop-stereo".equals(name) && !"maxaveragebitrate".equals(name)
                        && !part.isEmpty()) retained.add(part);
            }
            retained.add("stereo=1"); retained.add("sprop-stereo=1"); retained.add("maxaveragebitrate=192000");
            StringBuilder parameters = new StringBuilder();
            for (String parameter : retained) {
                if (parameters.length() != 0) parameters.append(';');
                parameters.append(parameter);
            }
            String replacement = prefix + parameters;
            if (found == -1) target.add(replacement); else target.set(found, replacement);
        }
        StringBuilder output = new StringBuilder();
        for (List<String> group : grouped) for (String line : group) output.append(line).append("\r\n");
        String answer = output.toString();
        List<Section> after = parse(grouped(answer));
        return new Description(answer, after, after.get(offer.audio.index), after.get(offer.video.index));
    }

    static String candidateFragment(String candidate) {
        if (candidate == null || candidate.length() == 0 || candidate.length() > 8_192)
            throw new CandidateFailure(CandidateFailureCode.ICE_SDP_CANDIDATE_BOUNDS);
        String[] words = candidate.trim().split(" +");
        if (words.length > 128) throw new CandidateFailure(CandidateFailureCode.ICE_SDP_TOKEN_COUNT);
        String fragment = null;
        for (int i = 0; i < words.length; i++) {
            String word = words[i];
            for (int c = 0; c < word.length(); c++) if (word.charAt(c) < 0x21 || word.charAt(c) > 0x7e)
                throw new CandidateFailure(CandidateFailureCode.ICE_SDP_TOKEN_CHARACTERS);
            if ("ufrag".equals(word)) {
                if (fragment != null) throw new CandidateFailure(CandidateFailureCode.ICE_SDP_UFRAG_DUPLICATE);
                if (i + 1 == words.length) throw new CandidateFailure(CandidateFailureCode.ICE_SDP_UFRAG_MISSING_VALUE);
                try { fragment = token(words[++i], 256); }
                catch (IllegalArgumentException ignored) { throw new CandidateFailure(CandidateFailureCode.ICE_SDP_UFRAG_INVALID_TOKEN); }
            }
        }
        return fragment;
    }
    static MediaSignalPayload.Candidate candidate(Description description, MediaSignalPayload.Candidate value,
            boolean requireExplicitFragment) {
        Section section = description.locate(value.sdpMid(), value.sdpMLineIndex());
        String embedded = candidateFragment(value.sdp());
        String explicit = value.usernameFragment();
        if (embedded != null && explicit != null && !embedded.equals(explicit))
            throw new CandidateFailure(CandidateFailureCode.ICE_SDP_UFRAG_CONFLICT);
        String fragment = explicit != null ? explicit : embedded;
        if (requireExplicitFragment && fragment == null) throw new CandidateFailure(CandidateFailureCode.ICE_SDP_UFRAG_REQUIRED);
        if (fragment != null && !section.ufrag.equals(fragment)) throw new CandidateFailure(CandidateFailureCode.ICE_SDP_UFRAG_MISMATCH);
        try { return new MediaSignalPayload.Candidate(value.sdp(), section.mid, section.index, section.ufrag); }
        catch (IllegalArgumentException ignored) { throw new CandidateFailure(CandidateFailureCode.ICE_SDP_PAYLOAD_INVALID); }
    }
    private static List<List<String>> grouped(String text) {
        if (text == null || text.isEmpty() || text.length() > MAXIMUM_BYTES) throw malformed();
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            if (c > 0x7e || (c < 0x20 && c != '\r' && c != '\n' && c != '\t')) throw malformed();
            if (c == '\r' && (i + 1 == text.length() || text.charAt(i + 1) != '\n')) throw malformed();
        }
        String[] lines = text.replace("\r\n", "\n").split("\n", -1);
        if (lines.length > 512) throw malformed();
        List<List<String>> result = new ArrayList<>();
        List<String> current = new ArrayList<>(); result.add(current);
        for (int i = 0; i < lines.length; i++) {
            String line = lines[i];
            if (line.isEmpty() && i == lines.length - 1) continue;
            if (line.isEmpty() || line.length() > 4_096) throw malformed();
            if (line.startsWith("m=")) {
                if (result.size() == 9) throw malformed();
                current = new ArrayList<>(); result.add(current);
            }
            current.add(line);
        }
        if (result.size() < 2 || result.get(0).isEmpty() || !"v=0".equals(result.get(0).get(0))) throw malformed();
        return result;
    }
    private static List<Section> parse(List<List<String>> grouped) {
        String sessionFragment = attribute(grouped.get(0), "a=ice-ufrag:", false);
        List<Section> result = new ArrayList<>(); Set<String> mids = new HashSet<>();
        for (int i = 1; i < grouped.size(); i++) {
            List<String> lines = grouped.get(i);
            String[] media = lines.get(0).substring(2).split(" +");
            if (media.length < 4 || !("audio".equals(media[0]) || "video".equals(media[0]) || "application".equals(media[0]))) throw malformed();
            if (!media[1].matches("0|[1-9][0-9]{0,4}") || Integer.parseInt(media[1]) > 65_535) throw malformed();
            boolean rejected = "0".equals(media[1]);
            if (!("application".equals(media[0]) ? "UDP/DTLS/SCTP".equals(media[2]) : "UDP/TLS/RTP/SAVPF".equals(media[2]))) throw malformed();
            String mid = attribute(lines, "a=mid:", true);
            if (!mids.add(mid)) throw malformed();
            String fragment = attribute(lines, "a=ice-ufrag:", false);
            if (fragment == null) fragment = sessionFragment;
            if (fragment == null) throw malformed();
            String direction = null, track = null;
            for (String line : lines) {
                if (line.equals("a=sendonly") || line.equals("a=recvonly") || line.equals("a=sendrecv") || line.equals("a=inactive")) {
                    if (direction != null) throw malformed(); direction = line.substring(2);
                }
                if (line.startsWith("a=msid:")) {
                    String[] fields = line.substring(7).split(" +");
                    if (fields.length != 2) throw malformed();
                    String candidate = token(fields[1], 256);
                    if (track != null && !track.equals(candidate)) throw malformed(); track = candidate;
                }
            }
            if (rejected) direction = "inactive";
            if (direction == null) direction = "sendrecv";
            result.add(new Section(i - 1, media[0], mid, fragment, direction, track, lines));
        }
        return result;
    }
    private static String attribute(List<String> lines, String prefix, boolean required) {
        String result = null;
        for (String line : lines) if (line.startsWith(prefix)) {
            if (result != null) throw malformed(); result = token(line.substring(prefix.length()), 256);
        }
        if (required && result == null) throw malformed(); return result;
    }
    private static String token(String value, int bound) {
        if (value.isEmpty() || value.length() > bound) throw malformed();
        for (int i = 0; i < value.length(); i++) if (value.charAt(i) < 0x21 || value.charAt(i) > 0x7e) throw malformed();
        return value;
    }
    private static List<String> opus(List<String> lines) {
        List<String> result = new ArrayList<>();
        for (String line : lines) if (line.startsWith("a=rtpmap:")) {
            String[] fields = line.substring(9).split(" +");
            if (fields.length == 2 && "opus/48000/2".equalsIgnoreCase(fields[1])) result.add(token(fields[0], 3));
        }
        return result;
    }
    private static boolean hasCodec(List<String> lines, String codec) {
        for (String line : lines) if (line.startsWith("a=rtpmap:")) {
            String[] fields = line.substring(9).split(" +");
            if (fields.length == 2 && codec.equalsIgnoreCase(fields[1])) return true;
        }
        return false;
    }
    private static boolean offeredStereo(List<String> lines, String payload) {
        String prefix = "a=fmtp:" + payload + " ";
        Map<String, String> parameters = new HashMap<>();
        for (String line : lines) if (line.startsWith(prefix)) for (String part : line.substring(prefix.length()).split(";")) {
            String[] pair = part.trim().split("=", 2);
            if (pair.length == 2 && parameters.put(pair[0].trim().toLowerCase(Locale.ROOT), pair[1].trim()) != null) throw malformed();
        }
        return "1".equals(parameters.get("stereo")) && "1".equals(parameters.get("sprop-stereo"));
    }
    private static IllegalArgumentException malformed() { return new IllegalArgumentException("Beluga native SDP refused"); }
    private WebRtcViewerSdp() { }
}
