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
    // AudioWorklet + cross-origin isolation: not strictly needed for the
    // smoke pass (no SharedArrayBuffer), but harmless if added.
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
