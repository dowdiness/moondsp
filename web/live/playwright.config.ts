import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./tests",
  timeout: 15_000,
  fullyParallel: false,
  retries: process.env.CI ? 2 : 0,
  reporter: "line",
  use: {
    baseURL: "http://127.0.0.1:5181",
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
    command: "npm run preview -- --port 5181 --strictPort --host 127.0.0.1",
    url: "http://127.0.0.1:5181",
    reuseExistingServer: !process.env.CI,
    timeout: 60_000,
    stdout: "pipe",
    stderr: "pipe",
  },
});
