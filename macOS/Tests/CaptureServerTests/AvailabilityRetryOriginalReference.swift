// PRIVATE: the original two stored values and operations, frozen independently of Rust/decoding.
struct AvailabilityRetryOriginalReference: Equatable {
    var nextDelaySeconds = 1
    var hasValidatedConnection = false

    mutating func observedValidAvailabilityState() -> Bool {
        let becameValidated = !hasValidatedConnection
        hasValidatedConnection = true
        nextDelaySeconds = 1
        return becameValidated
    }

    mutating func delayAfterFailure() -> Int {
        let delay = nextDelaySeconds
        nextDelaySeconds = min(nextDelaySeconds * 2, 30)
        hasValidatedConnection = false
        return delay
    }
}
