import { defineConfig } from "@playwright/test";

const port = Number(process.env.MOONDSP_LIVE_PLAYWRIGHT_PORT ?? 5181);
if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error("MOONDSP_LIVE_PLAYWRIGHT_PORT must be an integer from 1 through 65535");
}
const baseURL = `http://127.0.0.1:${port}`;

export default defineConfig({
  testDir: "./tests",
  timeout: 15_000,
  fullyParallel: false,
  retries: process.env.CI ? 2 : 0,
  reporter: "line",
  use: {
    baseURL,
    browserName: "chromium",
    headless: true,
    // Virtual output keeps real AudioWorklet/WASM rendering without a device.
    // Opt in for automation; leave unset for hardware/listening checks.
    launchOptions: {
      args: process.env.MOONDSP_VIRTUAL_AUDIO === "1" ? ["--disable-audio-output"] : [],
    },
  },
  webServer: {
    // `vite preview` serves the production build deterministically.
    // Test runs assume `npm run build` has already produced dist/.
    // --host pins the bind address so `127.0.0.1` resolves on CI runners
    // where vite's default `localhost` can race with IPv6 preferences.
    command: `npm run preview -- --port ${port} --strictPort --host 127.0.0.1`,
    url: baseURL,
    // Never accept assets from a preview launched in another checkout.
    reuseExistingServer: false,
    timeout: 60_000,
    stdout: "pipe",
    stderr: "pipe",
  },
});
