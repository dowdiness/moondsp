// Times copying 480,000 samples into a wasm-gc waveform, one export call per
// sample, inside a Chromium AudioWorklet. See
// docs/performance/2026-11-24-sample-copy.md.
//
// node scripts/bench-sample-copy/run.cjs <browser_test.wasm> [chunk] [rt]
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');

const [wasmPath, chunkArg = '16384', mode = 'rt'] = process.argv.slice(2);
if (!wasmPath) throw new Error('usage: run.cjs <browser_test.wasm> [chunk] [rt|offline]');
const files = {
  '/index.html': ['text/html', path.join(__dirname, 'index.html')],
  '/processor.js': ['text/javascript', path.join(__dirname, 'processor.js')],
  '/browser_test.wasm': ['application/wasm', wasmPath],
};
const server = http.createServer((req, res) => {
  const file = files[req.url];
  if (!file) { res.writeHead(404).end(); return; }
  res.writeHead(200, { 'content-type': file[0] }).end(fs.readFileSync(file[1]));
});

server.listen(0, '127.0.0.1', async () => {
  const browser = await chromium.launch({ args: ['--autoplay-policy=no-user-gesture-required'] });
  try {
    const page = await browser.newPage();
    await page.goto(`http://127.0.0.1:${server.address().port}/index.html`);
    const r = await page.evaluate(([c, rt]) => window.run(c, rt), [Number(chunkArg), mode === 'rt']);
    const bt = r.blockTimes.slice().sort((a, b) => a - b);
    delete r.blockTimes;
    const sorted = r.full.slice().sort((a, b) => a - b);
    console.log(JSON.stringify({
      ...r,
      fullMedian: sorted[Math.floor(sorted.length / 2)],
      nsPerCallMedian: (sorted[Math.floor(sorted.length / 2)] * 1e6) / 480000,
      blockMax: bt[bt.length - 1],
      realtime: mode === 'rt',
      ua: await page.evaluate(() => navigator.userAgent),
    }));
  } finally {
    await browser.close();
    server.close();
  }
});
