// Real-browser check for the built-in bank's recordings (ADR-0026): each one
// loads through web/sample-bank.js as web/live/src/audio.ts sends it, plays
// through s("…") and note("…").s("…"), and sounds at the right pitch.
//
// Pitch is measured by shifting log-frequency spectra against each other, so
// it does not depend on which partial is loudest:
// - s("name") against the decoded file itself, which must not shift: the
//   sample plays unshifted;
// - note(root - 5) and note(root + 7) against s("name"), which must shift
//   by -500 and +700 cents, so notes transpose from the root the engine
//   registers (@score.Sample::root_pitch, copied in BANK below).
// Neither measures the root itself: that the recordings sound at those
// roots is the measurement recorded in web/live/public/samples/vcsl/SOURCE.md.
// A second run makes one recording fail to download, and checks that the
// status channel reports every recording loading, then that one failed, and
// that it plays silence while the others play.
//
// npm --prefix web/live run sync:assets
// NODE_PATH=web/live/node_modules node scripts/bench-sample-copy/bank-check.cjs [chromium|firefox|webkit|safari]
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
// Safari runs through safaridriver on a Mac (safari-driver.cjs); the rest through Playwright.
const pw = process.argv[2] === 'safari' ? require('./safari-driver.cjs') : require('playwright');

const root = path.resolve(__dirname, '../../web/live/public');
const bankModule = path.resolve(__dirname, '../../web/sample-bank.js');
const types = { '.js': 'text/javascript', '.wasm': 'application/wasm' };
const browserName = process.argv[2] ?? 'chromium';

// Name and root (MIDI), as in @score.Sample::root_pitch.
const BANK = [
  ['piano_c2', 36], ['piano_c4', 60], ['piano_c6', 84], ['upright_a4', 69],
  ['mbira_e3', 52], ['mbira_b4', 71], ['mbira_fs5', 78], ['kalimba_cs5', 73], ['kalimba_g5', 79],
];
const FAILING = 'kalimba_g5';
/** Cents a measured shift may differ from the expected one. Silence has energy 0. */
const TOLERANCE = 10;

const SUBCLASS = `
const SKIP = 2400;    // 50 ms after the onset, past the attack
const LENGTH = 16384; // 0.34 s at 48 kHz
class CaptureProcessor extends MoonDspSchedulerProcessor {
  constructor(options) {
    super(options);
    this.capture = new Float32Array(LENGTH);
    this.seen = -1;
    this.energy = 0;
    const handle = this.port.onmessage;
    this.port.onmessage = event => {
      if (event.data?.type === 'capture') { this.seen = 0; this.energy = 0; return; }
      handle(event);
    };
  }
  process(inputs, outputs, parameters) {
    const result = super.process(inputs, outputs, parameters);
    if (this.seen >= 0) {
      const out = outputs[0][0];
      for (let i = 0; i < out.length; i++, this.seen++) {
        this.energy += out[i] * out[i];
        const at = this.seen - SKIP;
        if (at >= 0 && at < LENGTH) this.capture[at] = out[i];
      }
      if (this.seen >= SKIP + LENGTH) {
        this.seen = -1;
        this.port.postMessage({ type: 'captured', data: this.capture.slice(), energy: this.energy });
      }
    }
    return result;
  }
}
registerProcessor('capture-moondsp-scheduler', CaptureProcessor);
`;

let failing = null;
const server = http.createServer((req, res) => {
  const name = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  if (name === '/') { res.writeHead(200, { 'content-type': 'text/html' }).end('<!doctype html>'); return; }
  if (failing !== null && name === `/samples/vcsl/${failing}.flac`) { res.writeHead(404).end(); return; }
  const file = name === '/sample-bank.js' ? bankModule : path.join(root, name);
  if (!file.startsWith(root + path.sep) && file !== bankModule) { res.writeHead(404).end(); return; }
  if (!fs.existsSync(file)) { res.writeHead(404).end(); return; }
  res.writeHead(200, { 'content-type': types[path.extname(file)] ?? 'application/octet-stream' }).end(fs.readFileSync(file));
});

// Runs in the page: Safari's driver sends it as source, so it holds every helper.
async function run({ subclass, bank, scores }) {
  const SKIP = 2400, LENGTH = 16384, SIZE = 1 << 17, RATE = 48000;
  const LOW = 40, CENTS = 1200 * Math.log2(8000 / LOW), MAX_SHIFT = 1400;
  function fft(re, im) {
    const n = re.length;
    for (let i = 1, j = 0; i < n; i++) {
      let bit = n >> 1;
      for (; j & bit; bit >>= 1) j ^= bit;
      j ^= bit;
      if (i < j) { [re[i], re[j]] = [re[j], re[i]]; [im[i], im[j]] = [im[j], im[i]]; }
    }
    for (let len = 2; len <= n; len <<= 1) {
      const angle = -2 * Math.PI / len;
      for (let i = 0; i < n; i += len) {
        for (let k = 0; k < len / 2; k++) {
          const wr = Math.cos(angle * k), wi = Math.sin(angle * k);
          const a = i + k, b = a + len / 2;
          const tr = re[b] * wr - im[b] * wi, ti = re[b] * wi + im[b] * wr;
          re[b] = re[a] - tr; im[b] = im[a] - ti; re[a] += tr; im[a] += ti;
        }
      }
    }
  }
  /** Square-rooted magnitude on a 1-cent grid from 40 Hz, normalized. */
  function logSpectrum(samples) {
    const re = new Float64Array(SIZE), im = new Float64Array(SIZE);
    for (let i = 0; i < LENGTH; i++) re[i] = samples[i] * (0.5 - 0.5 * Math.cos(2 * Math.PI * i / (LENGTH - 1)));
    fft(re, im);
    const grid = new Float64Array(Math.ceil(CENTS));
    let norm = 0;
    for (let c = 0; c < grid.length; c++) {
      const bin = LOW * 2 ** (c / 1200) * SIZE / RATE;
      const k = Math.floor(bin), f = bin - k;
      const m = (1 - f) * Math.hypot(re[k], im[k]) + f * Math.hypot(re[k + 1], im[k + 1]);
      grid[c] = Math.sqrt(m);
      norm += grid[c] * grid[c];
    }
    for (let c = 0; c < grid.length; c++) grid[c] /= Math.sqrt(norm) || 1;
    return grid;
  }
  /** The shift in cents that best maps `from` onto `to`. */
  function shift(from, to) {
    let best = 0, score = -Infinity;
    for (let s = -MAX_SHIFT; s <= MAX_SHIFT; s++) {
      let sum = 0;
      for (let c = Math.max(0, -s); c < from.length && c + s < to.length; c++) sum += from[c] * to[c + s];
      if (sum > score) { score = sum; best = s; }
    }
    return best;
  }

  const base = location.origin;
  const source = (await (await fetch('/scheduler-processor.js')).text())
    .replace(/from "\.\/([a-z-]+\.js)"/g, (_, file) => `from "${base}/${file}"`);
  const url = URL.createObjectURL(new Blob([source + subclass], { type: 'text/javascript' }));
  const { sendSampleBank } = await import('/sample-bank.js');
  const wasmModule = await WebAssembly.compile(await (await fetch('/moonbit_dsp.wasm')).arrayBuffer());
  const ctx = new AudioContext({ sampleRate: RATE });
  await ctx.audioWorklet.addModule(url);
  const node = new AudioWorkletNode(ctx, 'capture-moondsp-scheduler', {
    numberOfInputs: 0, numberOfOutputs: 1, outputChannelCount: [2], processorOptions: { wasmModule },
  });
  const waiters = [];
  const statuses = [];
  node.port.onmessage = ({ data }) => {
    if (data.type === 'error') for (const w of waiters.splice(0)) w.reject(new Error(data.message));
    if (data.type === 'sample-status') statuses.push({ at: ctx.currentTime, ...data });
    for (const w of [...waiters]) if (w.test(data)) { waiters.splice(waiters.indexOf(w), 1); w.resolve(data); }
  };
  const wait = test => new Promise((resolve, reject) => {
    waiters.push({ test, resolve, reject });
    setTimeout(() => reject(new Error('timed out')), 30000);
  });
  const ready = wait(d => d.type === 'ready');
  node.connect(ctx.destination);
  await ctx.resume();
  await ready;
  const started = performance.now();
  // ping and burst can finish copying before the worklet takes the
  // recordings' sample-pending, so only an empty status after one that lists
  // every recording loading means the bank has loaded.
  let announced = false;
  const loaded = wait(d => d.type === 'sample-status' &&
    (announced ||= bank.every(([name]) => d.loading.includes(name))) && d.loading.length === 0);
  await sendSampleBank(ctx, node.port);
  await loaded;
  const loadMs = Math.round(performance.now() - started);
  let id = 0;
  async function play(text) {
    node.port.postMessage({ type: 'capture' });
    const captured = wait(d => d.type === 'captured');
    node.port.postMessage({ type: 'player-restart', id: ++id, input: JSON.stringify({ schema: 1, kind: 'text', text }) });
    const receipt = await wait(d => d.type === 'player-receipt' && d.id === id);
    if (!receipt.accepted) throw new Error(`${text}: ${receipt.message}`);
    const result = await captured;
    node.port.postMessage({ type: 'player-pause', id: ++id });
    await wait(d => d.type === 'player-receipt' && d.id === id);
    return result;
  }
  const rows = [];
  for (const [name, root] of bank) {
    const row = { name, root };
    rows.push(row);
    const plain = await play(`s("${name}").slow(4)`);
    row.energy = +plain.energy.toFixed(3);
    if (!scores) continue;
    const file = await ctx.decodeAudioData(await (await fetch(`/samples/vcsl/${name}.flac`)).arrayBuffer());
    const recorded = logSpectrum(file.getChannelData(0).subarray(SKIP, SKIP + LENGTH));
    const atRoot = logSpectrum(plain.data);
    row['s() vs file'] = shift(recorded, atRoot);
    for (const step of [-5, 7]) {
      const note = await play(`note("${root + step}").slow(4).s("${name}")`);
      row[`note(root${step < 0 ? '' : '+'}${step})`] = shift(atRoot, logSpectrum(note.data));
    }
  }
  await ctx.close();
  return { rows, statuses, loadMs, ua: navigator.userAgent };
}

server.listen(0, '127.0.0.1', async () => {
  const browser = await pw[browserName].launch(browserName === 'chromium'
    ? { args: ['--autoplay-policy=no-user-gesture-required'] }
    : browserName === 'firefox'
      ? { firefoxUserPrefs: { 'media.autoplay.default': 0, 'media.autoplay.blocking_policy': 0 } } : {});
  try {
    const page = await browser.newPage();
    await page.goto(`http://127.0.0.1:${server.address().port}/`);
    const names = BANK.map(([name]) => name);

    const pitch = await page.evaluate(run, { subclass: SUBCLASS, bank: BANK, scores: true });
    const pitchChecks = {
      allLoaded: ['failed', 'overLimit', 'unknown'].every(field => pitch.statuses.at(-1)[field].length === 0),
      reportedAllLoading: pitch.statuses.some(status => names.every(name => status.loading.includes(name))),
    };
    for (const row of pitch.rows) {
      pitchChecks[`${row.name} plays`] = row.energy > 0.1;
      pitchChecks[`${row.name} s() at recorded pitch`] = Math.abs(row['s() vs file']) <= TOLERANCE;
      pitchChecks[`${row.name} note(root-5)`] = Math.abs(row['note(root-5)'] + 500) <= TOLERANCE;
      pitchChecks[`${row.name} note(root+7)`] = Math.abs(row['note(root+7)'] - 700) <= TOLERANCE;
    }

    failing = FAILING;
    const broken = await page.evaluate(run, { subclass: SUBCLASS, bank: BANK, scores: false });
    const last = broken.statuses.at(-1);
    const failure = last.failed.find(entry => entry.name === FAILING);
    const failureChecks = {
      reportedAllLoading: broken.statuses.some(status => names.every(name => status.loading.includes(name))),
      failedReported: last.failed.length === 1 && failure !== undefined && failure.reason.includes('404'),
      failedSilent: broken.rows.find(row => row.name === FAILING).energy === 0,
      othersPlay: broken.rows.filter(row => row.name !== FAILING).every(row => row.energy > 0.1),
    };

    const checks = { ...pitchChecks, ...Object.fromEntries(Object.entries(failureChecks).map(([k, v]) => [`failure: ${k}`, v])) };
    console.log(JSON.stringify({ browser: browserName, ua: pitch.ua, loadMs: pitch.loadMs }));
    console.table(pitch.rows);
    console.log(JSON.stringify({ failureStatuses: broken.statuses.map(({ loading, failed }) => ({ loading: loading.length, failed })) }));
    const failed = Object.entries(checks).filter(([, ok]) => !ok).map(([name]) => name);
    console.log(failed.length === 0 ? `all ${Object.keys(checks).length} checks passed` : `FAILED: ${failed.join(', ')}`);
    if (failed.length) process.exitCode = 1;
  } finally {
    await browser.close();
    server.close();
  }
});
