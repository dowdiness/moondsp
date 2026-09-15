/** @type {import('@playwright/test').PlaywrightTestConfig} */

const port = Number(process.env.MOONDSP_PLAYWRIGHT_PORT ?? 8090);
if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error('MOONDSP_PLAYWRIGHT_PORT must be an integer from 1 through 65535');
}
const baseURL = `http://127.0.0.1:${port}`;
const config = {
  testDir: './playwright-tests',
  timeout: 15_000,
  // Retry signal-measurement flakes on CI (DSP feedback ramp-up, early-block
  // timing, and browser-worklet startup are inherently non-deterministic).
  // A regression that fails reproducibly will still fail all 3 attempts.
  retries: process.env.CI ? 2 : 0,
  reporter: 'line',
  use: {
    baseURL,
    browserName: 'chromium',
    headless: true,
  },
  webServer: {
    command: `bash -lc 'moon build --target wasm-gc --release && ./playwright-serve.sh ${port}'`,
    url: baseURL,
    // Never accept assets from a server launched in another checkout.
    reuseExistingServer: false,
    timeout: 30_000,
  },
};

module.exports = config;
