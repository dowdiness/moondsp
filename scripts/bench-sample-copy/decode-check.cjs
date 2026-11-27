// Decodes each recording of the built-in bank with decodeAudioData in a real
// browser, at 48 kHz and 44.1 kHz, and compares the 48 kHz result with
// ffmpeg's decode of the same file (docs/performance/2026-11-27-bank-decoding.md).
//
// REFS=$(mktemp -d); for f in web/live/public/samples/vcsl/*.flac; do
//   ffmpeg -v error -i "$f" -f f32le -acodec pcm_f32le "$REFS/$(basename "$f" .flac).f32"; done
// NODE_PATH=web/live/node_modules node scripts/bench-sample-copy/decode-check.cjs "$REFS" [chromium|firefox|webkit|safari]
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const pw = process.argv[3] === 'safari' ? require('./safari-driver.cjs') : require('playwright');

const samples = path.resolve(__dirname, '../../web/live/public/samples/vcsl');
const refs = path.resolve(process.argv[2]);
const browserName = process.argv[3] ?? 'chromium';
const NAMES = ['piano_c2', 'piano_c4', 'piano_c6', 'upright_a4', 'mbira_e3', 'mbira_b4', 'mbira_fs5', 'kalimba_cs5', 'kalimba_g5'];

const server = http.createServer((req, res) => {
  const name = path.basename(decodeURIComponent(new URL(req.url, 'http://x').pathname));
  if (name === '') { res.writeHead(200, { 'content-type': 'text/html' }).end('<!doctype html><body></body>'); return; }
  const file = path.join(name.endsWith('.flac') ? samples : refs, name);
  if (!fs.existsSync(file)) { res.writeHead(404).end(); return; }
  res.writeHead(200, { 'content-type': name.endsWith('.flac') ? 'audio/flac' : 'application/octet-stream' }).end(fs.readFileSync(file));
});

// Runs in the page: Safari's driver sends it as source.
async function run(names) {
  const rows = [];
  for (const name of names) {
    const bytes = await (await fetch(`/${name}.flac`)).arrayBuffer();
    const reference = new Float32Array(await (await fetch(`/${name}.f32`)).arrayBuffer());
    const row = { name };
    for (const rate of [48000, 44100]) {
      const buffer = await new OfflineAudioContext(1, 1, rate).decodeAudioData(bytes.slice(0));
      const data = buffer.getChannelData(0);
      let peak = 0, diff = 0;
      for (let i = 0; i < data.length; i++) {
        peak = Math.max(peak, Math.abs(data[i]));
        if (rate === 48000 && i < reference.length) diff = Math.max(diff, Math.abs(data[i] - reference[i]));
      }
      row[`length ${rate}`] = data.length;
      row[`peak ${rate}`] = +peak.toFixed(4);
      if (rate === 48000) { row.channels = buffer.numberOfChannels; row['reference length'] = reference.length; row['max diff'] = diff; }
    }
    rows.push(row);
  }
  return { rows, ua: navigator.userAgent };
}

server.listen(0, '127.0.0.1', async () => {
  const browser = await pw[browserName].launch();
  try {
    const page = await browser.newPage();
    await page.goto(`http://127.0.0.1:${server.address().port}/`);
    const { rows, ua } = await page.evaluate(run, NAMES);
    console.log(ua);
    console.table(rows);
    // Exact to within half a 16-bit step, the full length at 48 kHz, and the
    // same duration at 44.1 kHz.
    const ok = rows.every(row => row.channels === 1 && row['length 48000'] === row['reference length'] &&
      row['max diff'] <= 0.5 / 32767 && Math.abs(row['length 44100'] - row['length 48000'] * 44100 / 48000) <= 1);
    console.log(ok ? 'all recordings decode as expected' : 'FAILED');
    if (!ok) process.exitCode = 1;
  } finally {
    await browser.close();
    server.close();
  }
});
