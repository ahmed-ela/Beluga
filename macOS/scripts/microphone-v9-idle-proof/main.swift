import CoreAudio
import Darwin
import Foundation

// No fixtures, alternate input files, skip modes, actors, or mutable profile
// path are accepted by the production helper. The root controller must execute
// its sealed native copy as original UID/EUID 501 in a root-held result channel.
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
do {
    let request = try BelugaMicrophoneIdleRequest(arguments: Array(CommandLine.arguments.dropFirst()))
    guard getuid() == 501, geteuid() == 501 else { throw BelugaMicrophoneIdleFailure.callerIdentity }
    let proof = BelugaMicrophoneIdleProof(
        readProperty: { device, address, size, value in
            var address = address
            return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        },
        hostTicks: { mach_absolute_time() },
        resolveEndpoints: { try BelugaMicrophoneLiveEndpoints.resolve() },
        betweenReads: { usleep(50_000) }
    )
    let result = try proof.collect(request, effectiveUID: geteuid())
    FileHandle.standardOutput.write(try encoder.encode(result) + Data([10]))
    exit(result.exitCode)
} catch {
    let failure = error as? BelugaMicrophoneIdleFailure
    let code = failure?.code ?? "UNEXPECTED_FAILURE"
    // Bounded fixed error classification; never emit an idle result on error.
    let output: [String: Any] = ["contract": "beluga.microphone.passive-idle.v1", "kind": "REFUSED",
                                 "idleAcceptance": false, "error": code]
    if let bytes = try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]) {
        FileHandle.standardOutput.write(bytes + Data([10]))
    }
    exit(failure == .arguments ? 64 : 65)
}
