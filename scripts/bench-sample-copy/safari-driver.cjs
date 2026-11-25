// A minimal stand-in for Playwright's browser launcher that drives real
// Safari through safaridriver (WebDriver), so the sample checks run in Safari
// on a Mac without Playwright. It offers only what the checks use:
// launch() -> { newPage() -> { goto(url), evaluate(fn, arg) }, close() }.
//
// One-time setup on the Mac: `sudo safaridriver --enable`.
const { spawn } = require('node:child_process');

const PORT = 4445;

async function call(method, path, body) {
  const response = await fetch(`http://127.0.0.1:${PORT}${path}`, {
    method,
    headers: { 'content-type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const { value } = await response.json();
  if (!response.ok) throw new Error(`${method} ${path}: ${value?.error}: ${value?.message}`);
  return value;
}

async function launch() {
  const driver = spawn('safaridriver', ['--port', String(PORT)], { stdio: 'ignore' });
  for (let i = 0; ; i++) {
    try { await call('GET', '/status'); break; } catch (error) {
      if (i > 50) throw error;
      await new Promise(r => setTimeout(r, 200));
    }
  }
  const { sessionId } = await call('POST', '/session', { capabilities: { alwaysMatch: { browserName: 'safari' } } });
  const session = `/session/${sessionId}`;
  await call('POST', `${session}/timeouts`, { script: 10 * 60 * 1000, pageLoad: 60 * 1000 });
  return {
    async newPage() {
      return {
        async goto(url) {
          await call('POST', `${session}/url`, { url });
          // Safari starts an AudioContext only after a user gesture on the
          // page, so add a button to click, as a person pressing Play would.
          await call('POST', `${session}/execute/sync`, {
            script: `const b = document.createElement('button'); b.id = 'gesture'; b.textContent = 'start';
              b.onclick = () => { window.__gesture = new AudioContext(); window.__gesture.resume(); };
              document.body.append(b);`,
            args: [],
          });
        },
        async evaluate(fn, arg) {
          // A click lets one later AudioContext start: without a fresh one, a
          // second context's resume() never settles, so click before each.
          const button = await call('POST', `${session}/element`, { using: 'css selector', value: '#gesture' });
          await call('POST', `${session}/element/${Object.values(button)[0]}/click`, {});
          // The result crosses as one JSON string: WebDriver's own encoding
          // of a large array, such as the loading check's 384,000 output
          // samples, stalls Safari.
          const result = JSON.parse(await call('POST', `${session}/execute/async`, {
            script: `const done = arguments[arguments.length - 1];
              (${fn.toString()})(arguments[0]).then(ok => done(JSON.stringify({ ok })),
                e => done(JSON.stringify({ error: String(e?.stack ?? e) })));`,
            args: [arg],
          }));
          if ('error' in result) throw new Error(result.error);
          return result.ok;
        },
      };
    },
    async close() {
      try { await call('DELETE', session); } finally { driver.kill(); }
    },
  };
}

module.exports = { safari: { launch } };
