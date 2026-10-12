import { AudioShareListener, readAndClearLink } from "./core.js";

const link = readAndClearLink(window.location, window.history);
const status = document.querySelector("#status");
const time = document.querySelector("#time");
const button = document.querySelector("#listen");
const audio = document.querySelector("#audio");
const labels = { connecting: "Connecting…", waiting: "Waiting for Mac audio…", listening: "Listening live",
  unavailable: "This audio link is unavailable.", expired: "This audio link has expired.", ended: "The audio share has ended." };
let listener = null;
let clock = null;
audio.addEventListener("playing", () => listener?.setPlaybackActive(true));
for (const event of ["waiting", "stalled", "pause", "ended"]) {
  audio.addEventListener(event, () => listener?.setPlaybackActive(false));
}

const stopAudio = () => {
  audio.pause();
  audio.srcObject?.getTracks().forEach((track) => track.stop());
  audio.srcObject = null;
  clearInterval(clock);
  time.textContent = "";
  button.disabled = true;
};

if (!link) {
  status.textContent = "This audio link is invalid or missing.";
  button.disabled = true;
} else {
  listener = new AudioShareListener(link, window.location.origin, {
    status(state) { status.textContent = labels[state] ?? labels.unavailable; },
    track(track) {
      audio.srcObject = new MediaStream([track]);
      audio.play().catch(() => { button.disabled = false; button.textContent = "Play audio"; });
    },
    stop: stopAudio,
  });
  button.addEventListener("click", () => {
    button.disabled = true;
    if (listener.started) { audio.play().catch(() => { button.disabled = false; }); return; }
    listener.start();
    clock = setInterval(() => {
      const seconds = listener.remainingSeconds();
      if (seconds === null) return;
      time.textContent = `${Math.floor(seconds / 3_600)}:${String(Math.floor(seconds / 60) % 60).padStart(2, "0")}:${String(seconds % 60).padStart(2, "0")} remaining`;
    }, 1_000);
  });
  window.addEventListener("pagehide", () => listener.stop());
}
