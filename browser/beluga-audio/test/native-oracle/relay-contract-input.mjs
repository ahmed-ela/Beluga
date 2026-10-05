// Node-only credential admission. No credential issuance, logging or persistence.
import { normalizeCloudflareIceServers } from "../../../../services/RendezvousWorker/src/ice.js";
export const RELAY_INPUT_MAX_BYTES = 65_536;
export function admitRelayIce(bytes, now, runMilliseconds) {
  try {
    if (!(bytes instanceof Uint8Array) || bytes.byteLength === 0 || bytes.byteLength > RELAY_INPUT_MAX_BYTES ||
        !Number.isSafeInteger(now) || !Number.isInteger(runMilliseconds) || runMilliseconds < 45_000 || runMilliseconds > 90_000)
      throw new Error();
    const text = new TextDecoder("utf-8", { fatal: true }).decode(bytes).trim();
    const value = JSON.parse(text);
    // Canonical single JSON prevents duplicate/escaped-key ambiguity without a second parser.
    if (JSON.stringify(value) !== text || !value || Array.isArray(value) ||
        Object.keys(value).sort().join(",") !== "expiresAt,iceServers" || !Number.isSafeInteger(value.expiresAt) ||
        value.expiresAt - now < runMilliseconds + 30_000 || value.expiresAt - now > 300_000) throw new Error();
    return { iceServers: normalizeCloudflareIceServers({ iceServers: value.iceServers }), expiresAt: value.expiresAt };
  } catch { throw new Error("relay_credentials_refused"); }
}
export function readRelayIce(input, { privatePipe, runMilliseconds, now = Date.now, timeoutMilliseconds = 5_000, signal }) {
  if (privatePipe !== true || input.isTTY || !Number.isInteger(timeoutMilliseconds) ||
      timeoutMilliseconds < 1 || timeoutMilliseconds > 5_000 || signal?.aborted)
    return Promise.reject(new Error("relay_credentials_refused"));
  return new Promise((resolve, reject) => {
    const chunks = []; let size = 0, finished = false;
    const finish = (error) => {
      if (finished) return; finished = true; clearTimeout(timer);
      input.pause(); input.removeListener("data", data); input.removeListener("end", end);
      input.removeListener("error", failed); input.removeListener("close", failed);
      signal?.removeEventListener("abort", failed);
      let bytes;
      try {
        if (error) throw error;
        bytes = Buffer.concat(chunks); resolve(admitRelayIce(bytes, now(), runMilliseconds));
      } catch { reject(new Error("relay_credentials_refused")); }
      finally { bytes?.fill(0); for (const chunk of chunks) chunk.fill(0); chunks.length = 0; }
    };
    const data = (chunk) => {
      if (!(chunk instanceof Uint8Array)) { finish(new Error()); return; }
      size += chunk.byteLength;
      if (size > RELAY_INPUT_MAX_BYTES) { finish(new Error()); return; }
      chunks.push(Buffer.from(chunk));
    };
    const end = () => finish();
    const failed = () => finish(new Error());
    const timer = setTimeout(failed, timeoutMilliseconds);
    input.on("data", data); input.once("end", end); input.once("error", failed); input.once("close", failed);
    signal?.addEventListener("abort", failed, { once: true });
    input.resume();
  });
}
