// Dependency-free signal scope; injected EventEmitter tests never start native resources.
export function createSystemSourceCancellation(signals = process) {
  let interrupted = false, cleaning = false, cleanupPromise;
  let rejectInterruption;
  const interruption = new Promise((_, reject) => { rejectInterruption = reject; });
  // Signals can arrive before the first raced operation or during uninterruptible teardown.
  interruption.catch(() => {});
  const interrupt = () => {
    if (interrupted) return;
    interrupted = true;
    rejectInterruption(new Error("interrupted"));
  };
  signals.on("SIGINT", interrupt); signals.on("SIGTERM", interrupt);
  return {
    get cancelled() { return interrupted || cleaning; },
    throwIfCancelled() { if (interrupted || cleaning) throw new Error(interrupted ? "interrupted" : "runner_cancelled"); },
    async run(operation) {
      // Adopt already-started promises even when cancelled, so late failures are observed.
      if (interrupted || cleaning) {
        Promise.resolve(operation).catch(() => {});
        throw new Error(interrupted ? "interrupted" : "runner_cancelled");
      }
      return Promise.race([operation, interruption]);
    },
    cleanup(operation) {
      cleaning = true;
      // Repeated signals do not cancel, race, or invoke the owned cleanup a second time.
      return cleanupPromise ??= Promise.resolve().then(operation);
    },
    finalize(result, passed) {
      if (interrupted) result.failure = "interrupted";
      result.passed = !interrupted && result.failure === null && passed;
      result.systemAudioVerified = result.passed;
      return result;
    },
    dispose() { signals.removeListener("SIGINT", interrupt); signals.removeListener("SIGTERM", interrupt); },
  };
}
