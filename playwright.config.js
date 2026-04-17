/** @type {import('@playwright/test').PlaywrightTestConfig} */
const config = {
  testDir: './playwright-tests',
  timeout: 15_000,
  // Retry signal-measurement flakes on CI (DSP feedback ramp-up, early-block
  // timing, and browser-worklet startup are inherently non-deterministic).
  // A regression that fails reproducibly will still fail all 3 attempts.
  retries: process.env.CI ? 2 : 0,
  reporter: 'line',
  use: {
    baseURL: 'http://127.0.0.1:8090',
    browserName: 'chromium',
    headless: true,
  },
  webServer: {
    command: "bash -lc 'moon build --target wasm-gc --release && ./playwright-serve.sh 8090'",
    url: 'http://127.0.0.1:8090',
    reuseExistingServer: true,
    timeout: 30_000,
  },
};

module.exports = config;
