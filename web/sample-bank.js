// The built-in sample bank's material, generated in code at the context's
// sample rate. It stands in for recordings until ones with an approved
// licence replace it (ADR-0026). Each entry is what a decoded, resampled,
// mono file would be: a name from `@score.Sample`, the MIDI pitch it was
// recorded at, and its samples.

/** A decaying 440 Hz sine with a little second harmonic, 1.5 s long. */
function ping(sampleRate) {
  const data = new Float32Array(Math.round(sampleRate * 1.5));
  for (let i = 0; i < data.length; i++) {
    const t = i / sampleRate;
    const tone = Math.sin(2 * Math.PI * 440 * t) + 0.25 * Math.sin(2 * Math.PI * 880 * t);
    data[i] = 0.6 * tone * Math.exp(-t * 4) * Math.min(1, t * 2000);
  }
  return data;
}

/** 0.3 s of white noise from a fixed seed, fading out exponentially. */
function burst(sampleRate) {
  const data = new Float32Array(Math.round(sampleRate * 0.3));
  let state = 0x2545f491;
  for (let i = 0; i < data.length; i++) {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    const white = state / 2147483648 - 1;
    data[i] = 0.5 * white * Math.exp(-i / sampleRate * 14);
  }
  return data;
}

/**
 * The bank at `sampleRate`, as `sample-load` messages for the scheduler
 * worklet. Send each with its `data.buffer` in the transfer list.
 */
export function sampleBank(sampleRate) {
  return [
    { type: "sample-load", name: "ping", rootPitch: 69, data: ping(sampleRate) },
    { type: "sample-load", name: "burst", rootPitch: 60, data: burst(sampleRate) },
  ];
}
