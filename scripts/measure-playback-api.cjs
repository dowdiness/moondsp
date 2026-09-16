// Run against a built live preview: node scripts/measure-playback-api.cjs [URL]
// Reports page-local WASM timings, not AudioWorklet deadline/GC guarantees.
const { chromium } = require('@playwright/test');
(async () => {
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage();
    await page.goto(process.argv[2] || 'http://127.0.0.1:5181');
    const result = await page.evaluate(async () => {
      const bytes = await (await fetch('/moonbit_dsp.wasm')).arrayBuffer();
      const { instance } = await WebAssembly.instantiate(bytes, {
        spectest: { print_char() {} },
        'moonbit:ffi': { make_closure(fn, closure) { return fn.bind(null, closure); } },
      });
      const w = instance.exports;
      if (!w.init_scheduler_graph(48000, 128)) throw new Error('graph init failed');
      const lengths = [12, 12, 24, 48, 24, 23, 1, 24, 24, 24, 12, 12];
      const body = 'stack(note("E4 G4 A4").slow(3),note("D5 A4 G4 E5").slow(4).jux(rev),chord("Cmaj9 Am7 Fmaj9 G6").slow(48),note("C2 A1 F2 G2").slow(48),s("bd"),s("hh(5,8)").slow(4).degradeBy(0.12),s("cp(2,4,1)").slow(4))';
      const text = 'song(bpm(120),' + lengths.map((length, i) => `section("s${i}",${length},${body})`).concat(lengths.map((_, i) => `part("p${i}","s${i}")`)).join(',') + ')';
      function fill() {
        w.clear_playback_input();
        for (let i = 0; i < text.length; i++) w.push_playback_char(text.charCodeAt(i));
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
    });
    process.stdout.write(JSON.stringify(result, null, 2) + '\n');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
