// Real-browser check for ADR-0026 stages 4 and 5: built-in samples play
// through s("…") and .s("…"), .lpf and .gain shape them, and begin, end and
// speed slice and pace them. It runs the production
// scheduler-processor.js from web/live/public in a realtime AudioContext,
// sends the bank exactly as web/live/src/audio.ts does (web/sample-bank.js),
// waits for the status channel to report it loaded, then plays each score
// and measures the energy of 1.5 s of output.
//
// npm --prefix web/live run sync:assets
// NODE_PATH=web/live/node_modules node scripts/bench-sample-copy/play-check.cjs [chromium|firefox|webkit|safari]
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
// Safari runs through safaridriver on a Mac (safari-driver.cjs); the rest through Playwright.
const pw = process.argv[2] === 'safari' ? require('./safari-driver.cjs') : require('playwright');

const root = path.resolve(__dirname, '../../web/live/public');
const web = path.resolve(__dirname, '../../web');
const types = { '.js': 'text/javascript', '.wasm': 'application/wasm' };
const browserName = process.argv[2] ?? 'chromium';

const SCORES = [
  ['silence', 'silence()'],
  ['s("ping")', 's("ping").slow(4)'],
  ['note("69").s("ping")', 'note("69").slow(4).s("ping")'],
  ['note("57").s("ping")', 'note("57").slow(4).s("ping")'],
  ['s("ping").gain(0.25)', 's("ping").slow(4).gain(0.25)'],
  ['s("ping").lpf(200)', 's("ping").slow(4).lpf(200)'],
  ['note("69").s("ping").lpf(200)', 'note("69").slow(4).s("ping").lpf(200)'],
  ['s("burst")', 's("burst").slow(4)'],
  ['s("ping").end(0.25)', 's("ping").slow(4).end(0.25)'],
  ['s("ping").begin(0.5)', 's("ping").slow(4).begin(0.5)'],
  ['s("ping").speed(-1)', 's("ping").slow(4).speed(-1)'],
  ['s("ping").speed(2)', 's("ping").slow(4).speed(2)'],
  ['s("ping").begin(0.5).end(0.25)', 's("ping").slow(4).begin(0.5).end(0.25)'],
  ['s("bd")', 's("bd").slow(4)'],
];

const SUBCLASS = `
const HEAD_BLOCKS = 37; // 0.1 s at 48 kHz
class EnergyProcessor extends MoonDspSchedulerProcessor {
  constructor(options) {
    super(options);
    this.energy = 0;
    this.blocks = -1;
    const handle = this.port.onmessage;
    this.port.onmessage = event => {
      if (event.data?.type === 'measure') { this.energy = 0; this.blocks = event.data.blocks; this.total = event.data.blocks; this.head = 0; return; }
      handle(event);
    };
  }
  process(inputs, outputs, parameters) {
    const result = super.process(inputs, outputs, parameters);
    if (this.blocks > 0) {
      const out = outputs[0][0];
      for (let i = 0; i < out.length; i++) {
        const x = out[i];
        this.energy += x * x;
        if (this.total - this.blocks < HEAD_BLOCKS) this.head += x * x;
      }
      if (--this.blocks === 0) this.port.postMessage({ type: 'energy', energy: this.energy, head: this.head });
    }
    return result;
  }
}
registerProcessor('energy-moondsp-scheduler', EnergyProcessor);
`;

const server = http.createServer((req, res) => {
  const name = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  if (name === '/') { res.writeHead(200, { 'content-type': 'text/html' }).end('<!doctype html>'); return; }
  const file = name === '/sample-bank.js' ? path.join(web, 'sample-bank.js') : path.join(root, name);
  if (!file.startsWith(root) && file !== path.join(web, 'sample-bank.js')) { res.writeHead(404).end(); return; }
  if (!fs.existsSync(file)) { res.writeHead(404).end(); return; }
  res.writeHead(200, { 'content-type': types[path.extname(file)] ?? 'application/octet-stream' }).end(fs.readFileSync(file));
});

server.listen(0, '127.0.0.1', async () => {
  const browser = await pw[browserName].launch(browserName === 'chromium'
    ? { args: ['--autoplay-policy=no-user-gesture-required'] }
    : browserName === 'firefox'
      ? { firefoxUserPrefs: { 'media.autoplay.default': 0, 'media.autoplay.blocking_policy': 0 } } : {});
  try {
    const page = await browser.newPage();
    await page.goto(`http://127.0.0.1:${server.address().port}/`);
    const result = await page.evaluate(async ({ subclass, scores }) => {
      const base = location.origin;
      const source = (await (await fetch('/scheduler-processor.js')).text())
        .replace(/from "\.\/([a-z-]+\.js)"/g, (_, file) => `from "${base}/${file}"`);
      const url = URL.createObjectURL(new Blob([source + subclass], { type: 'text/javascript' }));
      const { sampleBank } = await import('/sample-bank.js');
      const wasmModule = await WebAssembly.compile(await (await fetch('/moonbit_dsp.wasm')).arrayBuffer());
      const ctx = new AudioContext({ sampleRate: 48000 });
      await ctx.audioWorklet.addModule(url);
      const node = new AudioWorkletNode(ctx, 'energy-moondsp-scheduler', {
        numberOfInputs: 0, numberOfOutputs: 1, outputChannelCount: [2], processorOptions: { wasmModule },
      });
      const waiters = [];
      const statuses = [];
      const seen = [];
      node.port.onmessage = ({ data }) => {
        seen.push(data.type);
        if (data.type === 'error') for (const w of waiters.splice(0)) w.reject(new Error(data.message));
        if (data.type === 'sample-status') statuses.push(data);
        for (const w of [...waiters]) if (w.test(data)) { waiters.splice(waiters.indexOf(w), 1); w.resolve(data); }
      };
      const wait = test => new Promise((resolve, reject) => {
        waiters.push({ test, resolve, reject });
        setTimeout(() => reject(new Error(`timed out; messages seen: ${seen.join(', ') || 'none'}`)), 30000);
      });
      // Wait for `ready` before resuming: the worklet may send it before
      // `resume()` settles, as the editor's `waitForReady` also allows.
      const ready = wait(d => d.type === 'ready');
      node.connect(ctx.destination);
      await ctx.resume();
      await ready;
      for (const load of sampleBank(ctx.sampleRate)) node.port.postMessage(load, [load.data.buffer]);
      await wait(d => d.type === 'sample-status' && d.loading.length === 0);
      const energies = {};
      const heads = {};
      let id = 0;
      for (const [label, text] of scores) {
        const wire = JSON.stringify({ schema: 1, kind: 'text', text });
        // A restart starts playing at cycle 0 in the block that handles it.
        // Arm the window first, in message order on the audio thread, so it
        // holds the first onset however long the receipt takes to return.
        node.port.postMessage({ type: 'measure', blocks: Math.round(1.5 * 48000 / 128) });
        const measured = wait(d => d.type === 'energy');
        node.port.postMessage({ type: 'player-restart', id: ++id, input: wire });
        const receipt = await wait(d => d.type === 'player-receipt' && d.id === id);
        if (!receipt.accepted) throw new Error(`${label}: ${receipt.message}`);
        if (receipt.state !== 'Playing') throw new Error(`${label}: restart left the player ${receipt.state}`);
        const result = await measured;
        energies[label] = result.energy;
        heads[label] = result.head;
        node.port.postMessage({ type: 'player-pause', id: ++id });
        await wait(d => d.type === 'player-receipt' && d.id === id);
      }
      await ctx.close();
      return { energies, heads, statuses, ua: navigator.userAgent };
    }, { subclass: SUBCLASS, scores: SCORES });
    const e = result.energies;
    const h = result.heads;
    const checks = {
      sPlaysSample: e['s("ping")'] > 1,
      dotSPlaysSampleAtRoot: Math.abs(e['note("69").s("ping")'] / e['s("ping")'] - 1) < 0.05,
      gainQuarters: Math.abs(e['s("ping").gain(0.25)'] / e['s("ping")'] - 0.0625) < 0.01,
      lpfCuts: e['s("ping").lpf(200)'] < 0.1 * e['s("ping")'],
      lpfCutsDotS: e['note("69").s("ping").lpf(200)'] < 0.1 * e['note("69").s("ping")'],
      burstPlays: e['s("burst")'] > 1,
      silenceSilent: e.silence === 0,
      // ping decays, so its first quarter holds most of its energy and its
      // second half little.
      endKeepsHead: e['s("ping").end(0.25)'] < e['s("ping")'] && e['s("ping").end(0.25)'] > 0.8 * e['s("ping")'],
      beginSkipsHead: e['s("ping").begin(0.5)'] > 0 && e['s("ping").begin(0.5)'] < 0.1 * e['s("ping")'],
      // Backwards, ping starts from its decayed tail, so the first 0.1 s
      // holds a small share of what it holds forwards; total energy alone
      // cannot tell the directions apart.
      backwardsPlays: e['s("ping").speed(-1)'] > 0.1 * e['s("ping")'] &&
        h['s("ping").speed(-1)'] < 0.1 * h['s("ping")'],
      // Twice as fast, the whole decay plays in half the time.
      doubleSpeedHalves: Math.abs(e['s("ping").speed(2)'] / e['s("ping")'] - 0.5) < 0.02,
      emptySliceSilent: e['s("ping").begin(0.5).end(0.25)'] === 0,
    };
    console.log(JSON.stringify({ browser: browserName, ua: result.ua, energies: e, heads: result.heads, checks,
      statuses: result.statuses.map(s => ({ loading: s.loading, failed: s.failed, overLimit: s.overLimit, unknown: s.unknown })) }));
    if (!Object.values(checks).every(Boolean)) process.exitCode = 1;
  } finally {
    await browser.close();
    server.close();
  }
});
