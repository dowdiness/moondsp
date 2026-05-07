// Smoke tests for moondsp · live (phase A).
//
// Two layers:
//   • UI smoke — no audio device required; passes in plain headless Chromium.
//   • Audio path — gated on wasm assets being present in the build. If
//     processor.js / moonbit_dsp.wasm are missing, the audio block is
//     skipped (not failed) so CI without a moon build still runs the
//     UI layer.

import { test, expect } from "@playwright/test";
import { existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

const INITIAL_PATTERN = `s("bd sd hh sd").fast(2)`;

test.describe("UI smoke (no audio)", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/");
  });

  test("page mounts with editor and Start button", async ({ page }) => {
    await expect(page.locator("h1")).toHaveText("moondsp · live");
    await expect(page.locator("#start")).toHaveText("Start audio");
    await expect(page.locator("#status")).toContainText("idle");
    await expect(page.locator("#log")).toContainText("edit the pattern");
  });

  test("CodeMirror renders the initial pattern", async ({ page }) => {
    // CM6 renders the doc into .cm-content; line content is in .cm-line.
    const content = page.locator(".cm-content");
    await expect(content).toBeVisible();
    await expect(content).toContainText(INITIAL_PATTERN);
  });

  test("editor accepts keyboard input", async ({ page }) => {
    const editor = page.locator(".cm-content");
    await editor.click();
    // Move to end of doc and append a method chain.
    await page.keyboard.press("Control+End");
    await page.keyboard.type(".rev()");
    await expect(editor).toContainText(`${INITIAL_PATTERN}.rev()`);
  });

  test("Start button is enabled and clickable", async ({ page }) => {
    const btn = page.locator("#start");
    await expect(btn).toBeEnabled();
    await expect(btn).toHaveAttribute("data-action", "start");
  });
});

test.describe("Audio path", () => {
  // Gate audio tests on the wasm asset being present in dist/.
  // `npm run sync:assets` (run by prebuild) copies it from web/ — if the
  // upstream moonbit build hasn't run, the file won't exist and we skip.
  const wasmPath = resolve(__dirname, "..", "dist", "moonbit_dsp.wasm");
  const processorPath = resolve(__dirname, "..", "dist", "processor.js");
  const assetsAvailable = existsSync(wasmPath) && existsSync(processorPath);

  test.skip(!assetsAvailable, "wasm assets not in dist/ — run `moon build browser --target wasm-gc --release` then `npm run build`");

  test("Start → running → Stop toggle", async ({ page }) => {
    await page.goto("/");

    const btn = page.locator("#start");
    const status = page.locator("#status");
    const log = page.locator("#log");

    await btn.click();

    // Worklet init may take several seconds (wasm compile + scheduler init).
    await expect(status).toContainText("running", { timeout: 10_000 });
    await expect(btn).toHaveText("Stop audio");
    await expect(btn).toHaveAttribute("data-action", "stop");

    // Initial pattern should evaluate within a few hundred ms after running.
    await expect(log).toContainText("pattern updated", { timeout: 5_000 });

    // Toggle off.
    await btn.click();
    await expect(status).toContainText("idle");
    await expect(btn).toHaveText("Start audio");
    await expect(btn).toHaveAttribute("data-action", "start");
  });

  test("editing the pattern triggers debounced eval", async ({ page }) => {
    await page.goto("/");
    await page.locator("#start").click();
    await expect(page.locator("#status")).toContainText("running", { timeout: 10_000 });

    const editor = page.locator(".cm-content");
    await editor.click();
    await page.keyboard.press("Control+End");
    await page.keyboard.type(".rev()");

    // Debounce is 200ms; allow generous margin for eval + worklet round-trip.
    await expect(page.locator("#log")).toContainText("pattern updated", { timeout: 3_000 });
  });

  test("invalid pattern surfaces error and keeps last good", async ({ page }) => {
    await page.goto("/");
    await page.locator("#start").click();
    await expect(page.locator("#status")).toContainText("running", { timeout: 10_000 });

    // Wait for initial pattern to settle.
    await expect(page.locator("#log")).toContainText("pattern updated", { timeout: 5_000 });

    const editor = page.locator(".cm-content");
    await editor.click();
    await page.keyboard.press("Control+A");
    await page.keyboard.type(`s("bogus_drum")`);

    const log = page.locator("#log");
    await expect(log).toContainText("kept last good", { timeout: 3_000 });
    // Verify the rich error string crossed the wasm-gc boundary — the
    // worklet's char-by-char readback should preserve the parser's
    // "position N: unknown drum name 'bogus_drum'" message, not the
    // legacy generic "parse error" fallback.
    await expect(log).toContainText("bogus_drum");
    await expect(log).toContainText("position");
    // Status stays running — engine kept playing the previous graph.
    await expect(page.locator("#status")).toContainText("running");

    // Inline diagnostic squiggle is rendered via the canopy adapter's
    // SetDiagnostics path. The mark carries the parser's message in its
    // title attribute; severity classifier appears in data-severity.
    const diagnostic = page.locator(".cm-diagnostic-error").first();
    await expect(diagnostic).toBeVisible();
    await expect(diagnostic).toHaveAttribute("data-severity", "error");
    const title = await diagnostic.getAttribute("title");
    expect(title).toContain("bogus_drum");

    // Recovery clears the diagnostic.
    await page.keyboard.press("Control+A");
    await page.keyboard.type(`s("bd sd")`);
    await expect(log).toContainText("pattern updated", { timeout: 3_000 });
    await expect(page.locator(".cm-diagnostic-error")).toHaveCount(0);
  });
});
