// node scripts/measure-playback-api.cjs [URL] [--worklet]
// Default: page-local WASM. --worklet: the actual AudioWorklet with isolated instrumentation.
const { chromium } = require('@playwright/test');
const fs = require('node:fs/promises');
const path = require('node:path');
const lengths = [12, 12, 24, 48, 24, 23, 1, 24, 24, 24, 12, 12];
const body = 'stack(note("E4 G4 A4").slow(3),note("D5 A4 G4 E5").slow(4).jux(rev),chord("Cmaj9 Am7 Fmaj9 G6").slow(48),note("C2 A1 F2 G2").slow(48),s("bd"),s("hh(5,8)").slow(4).degradeBy(0.12),s("cp(2,4,1)").slow(4))';
const workload = {
  lengths,
  text: 'song(bpm(120),' + lengths.map((length, i) => `section("s${i}",${length},${body})`).concat(lengths.map((_, i) => `part("p${i}","s${i}")`)).join(',') + ')',
};

async function measureWorklet(page) {
  const sourceUrl = new URL('/scheduler-processor.js', page.url()).href;
  const response = await page.request.get(sourceUrl);
  if (!response.ok()) throw new Error(`Cannot load actual processor: ${response.status()}`);
  const instrumentation = await fs.readFile(path.join(__dirname, 'measure-playback-worklet.js'), 'utf8');
  const source = await response.text();
  const controllerUrl = new URL('./playback-controller.js', sourceUrl).href;
  const imported = source.replace('from "./playback-controller.js"', `from ${JSON.stringify(controllerUrl)}`);
  if (imported === source) throw new Error('Cannot resolve the processor controller import');
  return page.evaluate(async ({ text, moduleSource }) => {
    const context = new AudioContext({ sampleRate: 48000 });
    let node;
    let moduleUrl;
    const waiters = new Map();
    let nextId = 0;
    const delay = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
    function waitFor(type, id = '') {
      return new Promise((resolve, reject) => {
        const key = `${type}:${id}`;
        const timeout = setTimeout(() => {
          waiters.delete(key);
          reject(new Error(`Timed out waiting for ${key}`));
        }, 10000);
        waiters.set(key, {
          resolve(value) { clearTimeout(timeout); resolve(value); },
          reject(error) { clearTimeout(timeout); reject(error); },
        });
      });
    }
    function fail(error) {
      for (const waiter of waiters.values()) waiter.reject(error);
      waiters.clear();
    }
    async function command(type, data = {}, replyType = 'player-receipt') {
      const id = ++nextId;
      const reply = waitFor(replyType, id);
      node.port.postMessage({ type, id, ...data });
      const result = await reply;
      if (replyType === 'player-receipt' && !result.accepted) {
        throw new Error(result.message);
      }
      return result;
    }
    function stats(samples) {
      if (samples.length === 0) throw new Error('No timing samples collected');
      const sorted = [...samples].sort((a, b) => a - b);
      return { count: samples.length,
        mean_ms: samples.reduce((a, b) => a + b, 0) / samples.length,
        p50_ms: sorted[Math.floor(sorted.length * 0.5)],
        p95_ms: sorted[Math.floor(sorted.length * 0.95)], max_ms: sorted.at(-1) };
    }
    function summarize(report) {
      if (report.overflow) throw new Error('Worklet measurement storage overflowed');
      return { render: stats(report.blocks), callback_interarrival: stats(report.gaps),
        owner_update: report.updates.length ? stats(report.updates) : null };
    }
    try {
      const wasmModule = await WebAssembly.compile(await (await fetch('/moonbit_dsp.wasm')).arrayBuffer());
      moduleUrl = URL.createObjectURL(new Blob([moduleSource], { type: 'application/javascript' }));
      await context.audioWorklet.addModule(moduleUrl);
      node = new AudioWorkletNode(context, 'measured-moondsp-scheduler', {
        processorOptions: { wasmModule }, numberOfInputs: 0, outputChannelCount: [2],
      });
      node.port.onmessage = ({ data }) => {
        if (data.type === 'error') { fail(new Error(data.message)); return; }
        const key = `${data.type}:${data.id ?? ''}`;
        const waiter = waiters.get(key);
        if (waiter) { waiters.delete(key); waiter.resolve(data); }
      };
      node.onprocessorerror = () => fail(new Error('AudioWorklet processorerror'));
      const muted = context.createGain();
      muted.gain.value = 0;
      node.connect(muted).connect(context.destination);
      const ready = waitFor('ready');
      await context.resume();
      await ready;
      const input = JSON.stringify({ schema: 1, kind: 'text', text });
      await command('player-restart', { input });
      for (let i = 0; i < 10; i++) await command('player-update', { input });
      await delay(300);
      await command('measurement-start', {}, 'measurement-started');
      await delay(1000);
      const baseline = await command('measurement-report', {}, 'measurement-report');
      await command('measurement-start', {}, 'measurement-started');
      const roundTrips = [];
      for (let i = 0; i < 40; i++) {
        const started = performance.now();
        await command('player-update', {
          input: JSON.stringify({ schema: 1, kind: 'text', text: i % 2 ? text : text.replace('bpm(120)', 'bpm(121)') }),
        });
        roundTrips.push(performance.now() - started);
        await delay(20);
      }
      const edited = await command('measurement-report', {}, 'measurement-report');
      if (edited.updates.length !== 40) throw new Error('Missing owner update timings');
      return { mode: 'audio-worklet', workload: 'orbit-like 12-section score with alternating 120/121 BPM edits',
        characters: text.length, iterations: 40, warmup_updates: 10,
        sample_rate: edited.sampleRate, block_size: edited.blockSize,
        block_budget_ms: edited.blockSize / edited.sampleRate * 1000,
        worklet_clock: 'Date.now, integer milliseconds; sub-millisecond values are unresolved',
        baseline: summarize(baseline), edited: summarize(edited),
        receipt_roundtrip: stats(roundTrips),
        conditions: { headless: true, output_muted: true, cross_origin_isolated: crossOriginIsolated,
          baseline_window_ms: 1000, delay_between_edits_ms: 20, user_agent: navigator.userAgent },
        interpretation: 'Instrumented callback timings and wall-clock interarrival gaps; not an audible-dropout or real-time deadline guarantee. Buffered callback bursts can exceed one quantum even at baseline.' };
    } finally {
      node?.disconnect();
      node?.port.close();
      fail(new Error('Measurement closed'));
      if (moduleUrl) URL.revokeObjectURL(moduleUrl);
      await context.close();
    }
  }, { text: workload.text, moduleSource: imported + '\n' + instrumentation });
}

(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--autoplay-policy=no-user-gesture-required'] });
  try {
    const page = await browser.newPage();
    await page.goto(process.argv.slice(2).find(argument => !argument.startsWith('--')) || 'http://127.0.0.1:5181');
    const result = process.argv.includes('--worklet') ? await measureWorklet(page) : await page.evaluate(async ({ text, lengths }) => {
      const bytes = await (await fetch('/moonbit_dsp.wasm')).arrayBuffer();
      const { instance } = await WebAssembly.instantiate(bytes, {
        spectest: { print_char() {} },
        'moonbit:ffi': { make_closure(fn, closure) { return fn.bind(null, closure); } },
      });
      const w = instance.exports;
      if (!w.init_scheduler_graph(48000, 128)) throw new Error('graph init failed');
      const input = JSON.stringify({ schema: 1, kind: 'text', text });
      function fill() {
        w.clear_playback_input();
        for (let i = 0; i < input.length; i++) w.push_playback_char(input.charCodeAt(i));
      }
      function update() {
        fill();
        const start = performance.now();
        if (w.player_update_input() !== 0) throw new Error('update failed');
        return performance.now() - start;
      }
      function restart() {
        fill();
        const start = performance.now();
        if (w.player_restart_input() !== 0) throw new Error('restart failed');
        return performance.now() - start;
      }
      function render() {
        if (!w.process_scheduler_block()) throw new Error('render failed');
      }
      restart();
      render();
      for (let i = 0; i < 10; i++) {
        update(); render();
        restart(); render();
      }
      const updateAcceptance = [];
      const followingUpdateRender = [];
      const steadyRender = [];
      const restartAcceptance = [];
      const followingRestartRender = [];
      for (let i = 0; i < 60; i++) {
        updateAcceptance.push(update());
        let start = performance.now();
        render();
        followingUpdateRender.push(performance.now() - start);
        start = performance.now();
        for (let j = 0; j < 750; j++) render();
        steadyRender.push((performance.now() - start) / 750);
      }
      for (let i = 0; i < 60; i++) {
        restartAcceptance.push(restart());
        const start = performance.now();
        render();
        followingRestartRender.push(performance.now() - start);
      }
      function stats(samples) {
        const sorted = [...samples].sort((a, b) => a - b);
        return { mean_ms: samples.reduce((a, b) => a + b, 0) / samples.length,
          p50_ms: sorted[Math.floor(sorted.length * 0.5)],
          p95_ms: sorted[Math.floor(sorted.length * 0.95)], max_ms: sorted.at(-1) };
      }
      return { workload: 'orbit-like 12-section score', sections: lengths.length,
        cycles: lengths.reduce((a, b) => a + b, 0), characters: text.length,
        sample_rate: 48000, block_size: 128, block_budget_ms: 128 / 48,
        iterations: 60, warmup_operations_per_kind: 10, steady_blocks_per_batch: 750,
        update_acceptance: stats(updateAcceptance), following_update_render: stats(followingUpdateRender),
        steady_render: stats(steadyRender), restart_acceptance: stats(restartAcceptance),
        following_restart_render: stats(followingRestartRender), user_agent: navigator.userAgent };
    }, workload);
    process.stdout.write(JSON.stringify(result, null, 2) + '\n');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
