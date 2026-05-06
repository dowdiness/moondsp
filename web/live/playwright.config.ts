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
    command: "npm run preview -- --port 5181 --strictPort",
    url: "http://127.0.0.1:5181",
    reuseExistingServer: !process.env.CI,
    timeout: 30_000,
  },
});
