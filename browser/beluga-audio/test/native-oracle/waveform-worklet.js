// Reads decoded remote PCM, emits scalar evidence, and outputs ZERO samples.
class WaveformProbe extends AudioWorkletProcessor {
  constructor(options) {
    super(); this.count = 0; this.energy = [0, 0]; this.tone = [[0, 0, 0, 0], [0, 0, 0, 0]];
    this.leftHz = options?.processorOptions?.challenge?.leftHz ?? 440;
    this.rightHz = options?.processorOptions?.challenge?.rightHz ?? 880;
    if (![this.leftHz, this.rightHz].every((value) => Number.isInteger(value) && value >= 200 && value <= 4000) ||
        this.leftHz === this.rightHz) throw new Error("invalid_challenge");
  }
  process(inputs, outputs) {
    for (const output of outputs) for (const channel of output) channel.fill(0);
    const input = inputs[0];
    if (input.length !== 2) return true;
    for (let frame = 0; frame < input[0].length; frame++) {
      const time = this.count / sampleRate;
      for (let channel = 0; channel < 2; channel++) {
        const value = input[channel][frame]; this.energy[channel] += value * value;
        this.tone[channel][0] += value * Math.sin(2 * Math.PI * this.leftHz * time);
        this.tone[channel][1] += value * Math.cos(2 * Math.PI * this.leftHz * time);
        this.tone[channel][2] += value * Math.sin(2 * Math.PI * this.rightHz * time);
        this.tone[channel][3] += value * Math.cos(2 * Math.PI * this.rightHz * time);
      }
      this.count++;
    }
    if (this.count >= sampleRate) {
      const magnitude = (channel, offset) => Math.hypot(this.tone[channel][offset], this.tone[channel][offset + 1]);
      this.port.postMessage({ rmsLeft: Math.sqrt(this.energy[0] / this.count), rmsRight: Math.sqrt(this.energy[1] / this.count),
        leftRatio: Math.min(999_999, magnitude(0, 0) / Math.max(1e-6, magnitude(0, 2))),
        rightRatio: Math.min(999_999, magnitude(1, 2) / Math.max(1e-6, magnitude(1, 0))), sampleRate });
      this.count = 0; this.energy = [0, 0]; this.tone = [[0, 0, 0, 0], [0, 0, 0, 0]];
    }
    return true;
  }
}
registerProcessor("beluga-waveform-probe", WaveformProbe);
