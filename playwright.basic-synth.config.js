/** @type {import('@playwright/test').PlaywrightTestConfig} */
module.exports = {
  testDir: './examples/basic-synth/tests',
  timeout: 15_000,
  reporter: 'line',
  use: {
    baseURL: 'http://127.0.0.1:4187',
    browserName: 'chromium',
    headless: true,
    launchOptions: { args: ['--disable-audio-output', '--autoplay-policy=user-gesture-required'] },
  },
  webServer: {
    command: 'npm --prefix examples/basic-synth run dev -- --host 127.0.0.1 --port 4187 --strictPort',
    url: 'http://127.0.0.1:4187',
    reuseExistingServer: !process.env.CI,
    timeout: 30_000,
  },
};
