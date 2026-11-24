// Real-browser check for ADR-0026 stage 4: built-in samples play through
// s("…") and .s("…"), and .lpf and .gain shape them. It runs the production
// scheduler-processor.js from web/live/public in a realtime AudioContext,
// sends the bank exactly as web/live/src/audio.ts does (web/sample-bank.js),
// waits for the status channel to report it loaded, then plays each score
// and measures the energy of 1.5 s of output.
//
// npm --prefix web/live run sync:assets
// NODE_PATH=web/live/node_modules node scripts/bench-sample-copy/play-check.cjs [chromium|firefox|webkit]
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const pw = require('playwright');

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
  ['s("bd")', 's("bd").slow(4)'],
];

const SUBCLASS = `
class EnergyProcessor extends MoonDspSchedulerProcessor {
  constructor(options) {
    super(options);
    this.energy = 0;
    this.blocks = -1;
    const handle = this.port.onmessage;
    this.port.onmessage = event => {
      if (event.data?.type === 'measure') { this.energy = 0; this.blocks = event.data.blocks; return; }
      handle(event);
    };
  }
  process(inputs, outputs, parameters) {
    const result = super.process(inputs, outputs, parameters);
    if (this.blocks > 0) {
      for (const x of outputs[0][0]) this.energy += x * x;
      if (--this.blocks === 0) this.port.postMessage({ type: 'energy', energy: this.energy });
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
      node.port.onmessage = ({ data }) => {
        if (data.type === 'sample-status') statuses.push(data);
        for (const w of [...waiters]) if (w.test(data)) { waiters.splice(waiters.indexOf(w), 1); w.resolve(data); }
      };
      const wait = test => new Promise((resolve, reject) => {
        waiters.push({ test, resolve });
        setTimeout(() => reject(new Error('timed out')), 10000);
      });
      node.connect(ctx.destination);
      await ctx.resume();
      await wait(d => d.type === 'ready');
      for (const load of sampleBank(ctx.sampleRate)) node.port.postMessage(load, [load.data.buffer]);
      await wait(d => d.type === 'sample-status' && d.loading.length === 0);
      const energies = {};
      let id = 0;
      for (const [label, text] of scores) {
        const wire = JSON.stringify({ schema: 1, kind: 'text', text });
        node.port.postMessage({ type: 'player-restart', id: ++id, input: wire });
        const receipt = await wait(d => d.type === 'player-receipt' && d.id === id);
        if (!receipt.accepted) throw new Error(`${label}: ${receipt.message}`);
        node.port.postMessage({ type: 'player-play', id: ++id });
        await wait(d => d.type === 'player-receipt' && d.id === id);
        node.port.postMessage({ type: 'measure', blocks: Math.round(1.5 * 48000 / 128) });
        energies[label] = (await wait(d => d.type === 'energy')).energy;
        node.port.postMessage({ type: 'player-pause', id: ++id });
        await wait(d => d.type === 'player-receipt' && d.id === id);
      }
      await ctx.close();
      return { energies, statuses, ua: navigator.userAgent };
    }, { subclass: SUBCLASS, scores: SCORES });
    const e = result.energies;
    const checks = {
      sPlaysSample: e['s("ping")'] > 1,
      dotSPlaysSampleAtRoot: Math.abs(e['note("69").s("ping")'] / e['s("ping")'] - 1) < 0.05,
      gainQuarters: Math.abs(e['s("ping").gain(0.25)'] / e['s("ping")'] - 0.0625) < 0.01,
      lpfCuts: e['s("ping").lpf(200)'] < 0.1 * e['s("ping")'],
      lpfCutsDotS: e['note("69").s("ping").lpf(200)'] < 0.1 * e['note("69").s("ping")'],
      burstPlays: e['s("burst")'] > 1,
      silenceSilent: e.silence === 0,
    };
    console.log(JSON.stringify({ browser: browserName, ua: result.ua, energies: e, checks,
      statuses: result.statuses.map(s => ({ loading: s.loading, overLimit: s.overLimit, unknown: s.unknown })) }));
    if (!Object.values(checks).every(Boolean)) process.exitCode = 1;
  } finally {
    await browser.close();
    server.close();
  }
});
