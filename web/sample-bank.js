// The built-in sample bank (ADR-0026). `ping` and `burst` are generated in
// code at the context's sample rate. The others are recordings, served as
// 48 kHz mono FLAC files under /samples/vcsl/ (see SOURCE.md there), which
// `decodeAudioData` decodes and resamples to the context's rate. Each name is
// one from `@score.Sample`; the engine knows each sample's root pitch
// (`@score.Sample::root_pitch`).

/** The recorded bank samples, each served as `/samples/vcsl/<name>.flac`. */
const RECORDINGS = [
  "piano_c2", "piano_c4", "piano_c6", "upright_a4",
  "mbira_e3", "mbira_b4", "mbira_fs5", "kalimba_cs5", "kalimba_g5",
];

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

/** One recording, fetched and decoded in `ctx`, as a `sample-load` message. */
async function recording(ctx, name, signal) {
  const url = `/samples/vcsl/${name}.flac`;
  const response = await fetch(url, { signal });
  if (!response.ok) throw new Error(`fetch ${url}: ${response.status}`);
  const decoded = await ctx.decodeAudioData(await response.arrayBuffer());
  const data = new Float32Array(decoded.length);
  decoded.copyFromChannel(data, 0);
  return { type: "sample-load", name, data };
}

/**
 * Sends the bank to the scheduler worklet's `port`. The generated samples go
 * at once. Each recording is first announced as `sample-pending`, so the
 * status channel shows it loading while it downloads and decodes, then sent
 * as `sample-load`, or as `sample-failed` with the reason. Resolves once every
 * recording is sent or has failed. Aborting `signal` stops the downloads.
 */
export function sendSampleBank(ctx, port, signal) {
  const post = load => port.postMessage(load, [load.data.buffer]);
  post({ type: "sample-load", name: "ping", data: ping(ctx.sampleRate) });
  post({ type: "sample-load", name: "burst", data: burst(ctx.sampleRate) });
  for (const name of RECORDINGS) port.postMessage({ type: "sample-pending", name });
  return Promise.all(RECORDINGS.map(name => recording(ctx, name, signal).then(post, error => {
    port.postMessage({ type: "sample-failed", name, reason: error instanceof Error ? error.message : String(error) });
  })));
}
