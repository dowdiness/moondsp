// Real-browser check for ADR-0026 stage 4: a realtime AudioContext keeps
// playing a score while a 10 s sample loads into the scheduler worklet.
// See docs/performance/2026-11-24-sample-copy.md.
//
// npm --prefix web/live run sync:assets
// node scripts/bench-sample-copy/loading-check.cjs [chromium|firefox|webkit|safari] [seconds]
//
// It runs the production scheduler-processor.js twice, with a subclass that
// records every rendered block by engine sample position: once as a control,
// and once posting a 480,000-sample load two seconds in. The scheduler is
// deterministic, so the loading run must render the control's samples
// exactly; it also reports crackle-probe style steps, per-block timings, and,
// in Chromium, the trace's AudioWorklet callback durations.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
// Safari runs through safaridriver on a Mac (safari-driver.cjs); the rest through Playwright.
const pw = process.argv[2] === 'safari' ? require('./safari-driver.cjs') : require('playwright');

const root = path.resolve(__dirname, '../../web/live/public');
const types = { '.js': 'text/javascript', '.wasm': 'application/wasm', '.html': 'text/html' };
const browserName = process.argv[2] ?? 'chromium';
const seconds = Number(process.argv[3] ?? 8);
const TEXT = 'stack(note("60 64 67 71 72 71 67 64"), s("bd sd hh sd"), s("hh*8"))';

const SUBCLASS = `
class CheckedProcessor extends MoonDspSchedulerProcessor {
  constructor(options) {
    super(options);
    const n = options.processorOptions.blocks;
    this.n = n;
    this.out = new Float32Array(n * 128);
    this.recorded = new Uint8Array(n);
    this.loading = new Uint8Array(n);
    this.durations = new Float64Array(n);
    this.calls = 0;
    this.longest = 0;
    this.reported = false;
  }
  process(inputs, outputs, parameters) {
    const started = Date.now();
    const loading = this.samples && this.samples.queue.length > 0;
    const before = this.graphInitialized ? this.wasm.scheduler_sample_position() : -1;
    const result = super.process(inputs, outputs, parameters);
    const took = Date.now() - started;
    // The first render builds the scheduler's voice pools; report it apart.
    if (this.calls === 0) this.first = took;
    else if (took > this.longest) this.longest = took;
    if (before >= 0 && this.wasm.scheduler_sample_position() > before) {
      const block = Math.round(before / 128);
      if (block < this.n) {
        this.out.set(outputs[0][0], block * 128);
        this.recorded[block] = 1;
        this.loading[block] = loading ? 1 : 0;
        this.durations[block] = took;
      }
    }
    this.calls++;
    if (!this.reported && this.calls >= this.n + 400) {
      this.reported = true;
      this.port.postMessage({ type: 'check-report', out: this.out, recorded: this.recorded,
        loading: this.loading, durations: this.durations, calls: this.calls, longest: this.longest, first: this.first,
        loaded: this.wasm.sample_loaded(0) });
    }
    return result;
  }
}
registerProcessor('checked-moondsp-scheduler', CheckedProcessor);
`;

const server = http.createServer((req, res) => {
  const file = path.join(root, decodeURIComponent(new URL(req.url, 'http://x').pathname));
  if (req.url === '/') { res.writeHead(200, { 'content-type': 'text/html' }).end('<!doctype html>'); return; }
  if (!file.startsWith(root) || !fs.existsSync(file)) { res.writeHead(404).end(); return; }
  res.writeHead(200, { 'content-type': types[path.extname(file)] ?? 'application/octet-stream' }).end(fs.readFileSync(file));
});

async function run(page, load) {
  return page.evaluate(async ({ subclass, text, load, seconds }) => {
    const base = location.origin;
    const source = (await (await fetch('/scheduler-processor.js')).text())
      .replace('from "./playback-controller.js"', `from "${base}/playback-controller.js"`)
      .replace('from "./playback-observations.js"', `from "${base}/playback-observations.js"`)
      .replace('from "./sample-loader.js"', `from "${base}/sample-loader.js"`);
    if (source.includes('from "./')) throw new Error('unresolved processor import');
    const url = URL.createObjectURL(new Blob([source + subclass], { type: 'text/javascript' }));
    const wasmModule = await WebAssembly.compile(await (await fetch('/moonbit_dsp.wasm')).arrayBuffer());
    const ctx = new AudioContext({ sampleRate: 48000 });
    await ctx.audioWorklet.addModule(url);
    const blocks = Math.round(seconds * 48000 / 128);
    const node = new AudioWorkletNode(ctx, 'checked-moondsp-scheduler', {
      numberOfInputs: 0, numberOfOutputs: 1, outputChannelCount: [2],
      processorOptions: { wasmModule, blocks },
    });
    const statuses = [];
    let ready;
    const isReady = new Promise(r => { ready = r; });
    const report = new Promise((resolve, reject) => {
      node.port.onmessage = ({ data }) => {
        if (data.type === 'ready') ready();
        else if (data.type === 'sample-status') statuses.push({ at: ctx.currentTime, ...data });
        else if (data.type === 'check-report') resolve(data);
        else if (data.type === 'error') reject(new Error(data.message));
      };
    });
    node.connect(ctx.destination);
    await ctx.resume();
    await isReady;
    const wire = JSON.stringify({ schema: 1, kind: 'text', text });
    node.port.postMessage({ type: 'player-restart', id: 1, input: wire });
    node.port.postMessage({ type: 'player-play', id: 2 });
    const wallStart = performance.now();
    const audioStart = ctx.currentTime;
    if (load) {
      await new Promise(r => setTimeout(r, 2000));
      const data = new Float32Array(480000);
      for (let i = 0; i < data.length; i++) data[i] = 0.5 * Math.sin(i * 0.0576) * Math.exp(-i / 96000);
      node.port.postMessage({ type: 'sample-load', name: 'ping', data }, [data.buffer]);
      // One sample longer than a waveform may be (ADR-0026 Decision 6).
      await new Promise(r => setTimeout(r, 1000));
      const tooLong = new Float32Array(1440001);
      node.port.postMessage({ type: 'sample-load', name: 'burst', data: tooLong }, [tooLong.buffer]);
    }
    const result = await report;
    const wall = (performance.now() - wallStart) / 1000;
    const audio = ctx.currentTime - audioStart;
    await ctx.close();
    return { ...result, out: Array.from(result.out), recorded: Array.from(result.recorded),
      loading: Array.from(result.loading), durations: Array.from(result.durations),
      statuses, wall, audio, ua: navigator.userAgent };
  }, { subclass: SUBCLASS, text: TEXT, load, seconds });
}

// Largest sample-to-sample step inside recorded blocks and across the
// boundary into each, as the crackle probe's maxStep and boundaryStep.
function steps(out, recorded, blocks) {
  let max = 0, boundary = 0;
  for (const b of blocks) {
    for (let i = 1; i < 128; i++) max = Math.max(max, Math.abs(out[b * 128 + i] - out[b * 128 + i - 1]));
    if (b > 0 && recorded[b - 1]) boundary = Math.max(boundary, Math.abs(out[b * 128] - out[b * 128 - 1]));
  }
  return { maxStep: max, boundaryStep: boundary };
}

server.listen(0, '127.0.0.1', async () => {
  const launcher = pw[browserName];
  const browser = await launcher.launch(browserName === 'chromium'
    ? { args: ['--autoplay-policy=no-user-gesture-required'] }
    : browserName === 'webkit' ? {} : { firefoxUserPrefs: { 'media.autoplay.default': 0, 'media.autoplay.blocking_policy': 0 } });
  try {
    const page = await browser.newPage();
    await page.goto(`http://127.0.0.1:${server.address().port}/`);
    const control = await run(page, false);
    let cdp = null;
    const traceEvents = [];
    if (browserName === 'chromium') {
      cdp = await page.context().newCDPSession(page);
      cdp.on('Tracing.dataCollected', ({ value }) => traceEvents.push(...value));
      await cdp.send('Tracing.start', { categories: 'webaudio,disabled-by-default-audio-worklet', transferMode: 'ReportEvents' });
    }
    const loaded = await run(page, true);
    let callbacks = null;
    if (cdp) {
      const done = new Promise(r => cdp.once('Tracing.tracingComplete', r));
      await cdp.send('Tracing.end');
      await done;
      const processEvents = traceEvents.filter(e => e.ph === 'X' && /AudioWorkletProcessor::Process/.test(e.name));
      const t0 = Math.min(...processEvents.map(e => e.ts));
      const late = processEvents.filter(e => e.dur / 1000 > 128 / 48)
        .map(e => ({ name: e.name, atSeconds: +((e.ts - t0) / 1e6).toFixed(3), ms: e.dur / 1000 }));
      const durations = processEvents.map(e => e.dur / 1000).sort((a, b) => a - b);
      const names = [...new Set(traceEvents.map(e => e.name))].filter(n => /udio/.test(n)).slice(0, 12);
      callbacks = durations.length ? {
        count: durations.length, p50: durations[Math.floor(durations.length / 2)],
        p99: durations[Math.floor(durations.length * 0.99)], max: durations.at(-1),
        overQuantum: late,
      } : { count: 0, names };
    }
    const both = [];
    let mismatched = 0, maxDifference = 0;
    for (let b = 0; b < control.recorded.length; b++) {
      if (!control.recorded[b] || !loaded.recorded[b]) continue;
      both.push(b);
      let differs = false;
      for (let i = 0; i < 128; i++) {
        const d = Math.abs(control.out[b * 128 + i] - loaded.out[b * 128 + i]);
        if (d > 0) { differs = true; maxDifference = Math.max(maxDifference, d); }
      }
      if (differs) mismatched++;
    }
    const loadingBlocks = loaded.loading.map((v, b) => v ? b : -1).filter(b => b >= 0);
    const peak = Math.max(...both.map(b => Math.max(...control.out.slice(b * 128, b * 128 + 128).map(Math.abs))));
    console.log(JSON.stringify({
      browser: browserName, ua: loaded.ua,
      blocksCompared: both.length, blocksMismatched: mismatched, maxDifference, peak,
      loadingBlocks: loadingBlocks.length, firstLoadingBlock: loadingBlocks[0], lastLoadingBlock: loadingBlocks.at(-1),
      sampleLoaded: loaded.loaded,
      statuses: loaded.statuses.map(s => ({ at: +s.at.toFixed(3), loading: s.loading, overLimit: s.overLimit })),
      stepsWhileLoading: steps(loaded.out, loaded.recorded, loadingBlocks),
      stepsControlSameBlocks: steps(control.out, control.recorded, loadingBlocks),
      stepsControlAll: steps(control.out, control.recorded, both),
      processMsWhileLoading: { max: Math.max(...loadingBlocks.map(b => loaded.durations[b])) },
      processMsLongest: { control: control.longest, loading: loaded.longest, firstRender: [control.first, loaded.first] },
      audioVsWallSeconds: { control: [control.audio, control.wall], loading: [loaded.audio, loaded.wall] },
      callbacks,
    }));
  } finally {
    await browser.close();
    server.close();
  }
});
