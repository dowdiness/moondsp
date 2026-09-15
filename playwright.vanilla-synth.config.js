/** @type {import('@playwright/test').PlaywrightTestConfig} */

const port = Number(process.env.MOONDSP_VANILLA_SYNTH_PLAYWRIGHT_PORT ?? 4187);
if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error('MOONDSP_VANILLA_SYNTH_PLAYWRIGHT_PORT must be an integer from 1 through 65535');
}
const baseURL = `http://127.0.0.1:${port}`;
module.exports = {
  testDir: './examples/vanilla-synth/tests',
  timeout: 15_000,
  reporter: 'line',
  use: {
    baseURL,
    browserName: 'chromium',
    headless: true,
    launchOptions: { args: ['--disable-audio-output', '--autoplay-policy=user-gesture-required'] },
  },
  webServer: {
    command: `npm --prefix examples/vanilla-synth run dev -- --host 127.0.0.1 --port ${port} --strictPort`,
    url: baseURL,
    // Never accept assets from a dev server launched in another checkout.
    reuseExistingServer: false,
    timeout: 30_000,
  },
};
