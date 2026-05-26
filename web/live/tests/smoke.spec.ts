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

const INITIAL_PATTERN = `$: s("bd(3,8), hh*16?, sd(2,8,2)").jux(rev)
$: note("48(3,8) 60(2,8,2) 67(3,8) 60(2,8,3)").slow(3)`;
const INITIAL_PATTERN_RENDERED = INITIAL_PATTERN.replace("\n", "");

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
    await expect(content).toContainText(INITIAL_PATTERN_RENDERED);
  });

  test("editor accepts keyboard input", async ({ page }) => {
    const editor = page.locator(".cm-content");
    await editor.click();
    // Move to end of doc and append a method chain.
    await page.keyboard.press("Control+End");
    await page.keyboard.type(".rev()");
    await expect(editor).toContainText(`${INITIAL_PATTERN_RENDERED}.rev()`);
  });

  test("Start button is enabled and clickable", async ({ page }) => {
    const btn = page.locator("#start");
    await expect(btn).toBeEnabled();
    await expect(btn).toHaveAttribute("data-action", "start");
  });

  test("autocomplete offers method names after `.` and accepting expands snippet", async ({ page }) => {
    // Two assertions in one test: that the popup is populated correctly
    // (covers context #2 in miniliveCompletion), and that accepting a
    // completion actually expands the snippet into the doc. Acceptance
    // here goes through the click code path rather than Enter — the
    // keyboard path races the autocomplete view's filter pass during
    // sequential runs, while click delegates directly to CM6's
    // applyCompletion. Both paths exercise the same snippet-expansion
    // logic, so this still guards against breakage in the snippet
    // wiring (snippetCompletion vs plain Completion, label-text format).
    const editor = page.locator(".cm-content");
    await editor.click();
    await page.keyboard.press("Control+End");
    await page.keyboard.type(".");
    const tooltip = page.locator(".cm-tooltip-autocomplete");
    await expect(tooltip).toBeVisible({ timeout: 2_000 });
    for (const m of ["fast", "slow", "rev", "degradeBy", "every", "jux"]) {
      await expect(tooltip).toContainText(m);
    }
    // The completion-list item carrying the label `fast` (exact match
    // to avoid `degradeBy`-style substring hits, though no overlap
    // exists in the current vocabulary).
    await tooltip.getByText("fast", { exact: true }).first().click();
    await expect(tooltip).toBeHidden({ timeout: 2_000 });
    // Snippet expansion places the cursor at `${n}`; the expansion
    // itself is what we're verifying — `.fast(` must appear in the doc.
    await expect(editor).toContainText(`${INITIAL_PATTERN_RENDERED}.fast(`);
  });

  test("Tab accepts the highlighted autocomplete option", async ({ page }) => {
    // Tab is bound to acceptCompletion in main.ts at Prec.highest so it
    // wins over the snippet-field navigation Tab binding registered by
    // autocompletion(). CM6 default keymap binds Enter only; Tab is what
    // most live-coding editors (Strudel, VS Code) use as the primary
    // accept key.
    //
    // The 120ms wait clears CM6's `interactionDelay` (default 75ms) —
    // an anti-typo guard that rejects acceptCompletion calls landing
    // within that window after the popup opens. Real users typing on
    // a keyboard exceed 75ms between keystrokes naturally; Playwright
    // doesn't, so the wait makes the test mimic real usage.
    const editor = page.locator(".cm-content");
    await editor.click();
    await page.keyboard.press("Control+End");
    await page.keyboard.type(".fa");
    const tooltip = page.locator(".cm-tooltip-autocomplete");
    await expect(tooltip).toBeVisible({ timeout: 2_000 });
    await expect(tooltip.locator('[aria-selected="true"]')).toContainText("fast");
    await page.waitForTimeout(120);
    await page.keyboard.press("Tab");
    await expect(tooltip).toBeHidden({ timeout: 2_000 });
    await expect(editor).toContainText(`${INITIAL_PATTERN_RENDERED}.fast(`);
  });

  test("autocomplete in every() arg 1 ignores commas inside nested calls", async ({ page }) => {
    // Regression: `pastFirstComma` originally treated any `,` between
    // the opening `(` and the cursor as a slot separator, which made
    // the cursor in `every(stack(a,b)|` look like slot 2 and surfaced
    // callback completions (rev/fast/slow) where they don't belong.
    // The bracket-depth scan now only counts top-level commas — so this
    // position must NOT offer callbacks. Top-level identifiers are
    // still expected since the slot accepts any expression.
    const editor = page.locator(".cm-content");
    await editor.click();
    await page.keyboard.press("Control+A");
    // closeBrackets auto-pairs `(` `[` `"`, so typing only the openers
    // (and stepping over auto-closes) lands the cursor between the
    // inner `stack(...)` close and the outer `every(...)` close.
    await page.keyboard.type(`s("bd").every(stack(s("bd"),s("sd"))`);
    await page.keyboard.press("Control+Space");
    const tooltip = page.locator(".cm-tooltip-autocomplete");
    await expect(tooltip).toBeVisible({ timeout: 2_000 });
    // Callbacks must not appear here — this is still slot 1.
    await expect(tooltip).not.toContainText("rev");
    // But top-level expression completions should be available.
    await expect(tooltip).toContainText("stack");
  });

  test("autocomplete offers drum names inside s(\"…\")", async ({ page }) => {
    // Inside a string whose enclosing call is s(...), the popup should
    // surface the synthesized drum vocabulary — not method names.
    const editor = page.locator(".cm-content");
    await editor.click();
    await page.keyboard.press("Control+A");
    await page.keyboard.type('s("b');
    // Wait for parser to settle so the syntax-tree lookup sees a String.
    const tooltip = page.locator(".cm-tooltip-autocomplete");
    await expect(tooltip).toBeVisible({ timeout: 2_000 });
    await expect(tooltip).toContainText("bd");
    // Method names must not bleed into the string-context popup.
    await expect(tooltip).not.toContainText("degradeBy");
  });

  test("cheatsheet advertises dollar stack lines under Layers", async ({ page }) => {
    // Strudel-style `$:` lines are the discoverable path for combining
    // s(...) drum patterns with note(...) melodies in one live buffer.
    const layersDl = page.locator("#cheat dl").first();
    await expect(layersDl.locator("dt")).toContainText(["s(", "note(", "$:"]);
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

  test("clearing the editor is a soft no-op (no inline error)", async ({ page }) => {
    await page.goto("/");
    await page.locator("#start").click();
    await expect(page.locator("#status")).toContainText("running", { timeout: 10_000 });
    await expect(page.locator("#log")).toContainText("pattern updated", { timeout: 5_000 });

    const editor = page.locator(".cm-content");
    await editor.click();
    await page.keyboard.press("Control+A");
    await page.keyboard.press("Delete");

    // Empty input must NOT route through the parser ("empty input" with
    // no position would otherwise paint a clamped, invisible diagnostic
    // and a useless footer error). Instead the UI surfaces a hint and
    // the engine keeps playing the previous graph.
    const log = page.locator("#log");
    await expect(log).toContainText("keeping previous", { timeout: 2_000 });
    await expect(page.locator(".cm-diagnostic-error")).toHaveCount(0);
    await expect(page.locator("#status")).toContainText("running");

    // Typing again resumes normal eval.
    await page.keyboard.type(`s("bd")`);
    await expect(log).toContainText("pattern updated", { timeout: 3_000 });
  });

  test("re-typing the same invalid pattern after clear re-paints the squiggle", async ({ page }) => {
    await page.goto("/");
    await page.locator("#start").click();
    await expect(page.locator("#status")).toContainText("running", { timeout: 10_000 });
    await expect(page.locator("#log")).toContainText("pattern updated", { timeout: 5_000 });

    const editor = page.locator(".cm-content");
    await editor.click();

    // First parse error → squiggle.
    await page.keyboard.press("Control+A");
    await page.keyboard.type(`s("bogus_drum")`);
    await expect(page.locator(".cm-diagnostic-error")).toBeVisible({ timeout: 3_000 });

    // Clear → soft no-op, squiggle clears.
    await page.keyboard.press("Control+A");
    await page.keyboard.press("Delete");
    await expect(page.locator(".cm-diagnostic-error")).toHaveCount(0, { timeout: 2_000 });

    // Re-type the *same* invalid pattern. Without the lastGood/latestSentText
    // reset in the empty-input branch this would short-circuit on
    // text === lastGood and the squiggle would never come back.
    await page.keyboard.type(`s("bogus_drum")`);
    await expect(page.locator(".cm-diagnostic-error")).toBeVisible({ timeout: 3_000 });
  });

  test("runtime worklet error tears down graph; Retry rebuilds cleanly", async ({ page }) => {
    await page.goto("/");
    await page.locator("#start").click();
    await expect(page.locator("#status")).toContainText("running", { timeout: 10_000 });
    await expect(page.locator("#log")).toContainText("pattern updated", { timeout: 5_000 });

    // Make the editor produce a parse error so a diagnostic squiggle is
    // visible, giving us a positive signal that the error transition
    // actually clears it.
    const editor = page.locator(".cm-content");
    await editor.click();
    await page.keyboard.press("Control+A");
    await page.keyboard.type(`s("bogus")`);
    await expect(page.locator(".cm-diagnostic-error")).toBeVisible({ timeout: 3_000 });

    // Inject a synthetic runtime worklet error. This goes through the
    // same AudioEngine.dispatchReply path the worklet uses for real
    // {type:"error"} messages — exercising teardownGraph() + the
    // status=error transition that the start-failure test can't reach
    // (start-failure throws before this.ctx/this.node are set).
    await page.evaluate(() => {
      window.__moondspEngine?._testInjectReply({
        type: "error",
        message: "synthetic runtime worklet failure",
      });
    });

    const status = page.locator("#status");
    const btn = page.locator("#start");
    await expect(status).toContainText("error: synthetic runtime worklet failure", { timeout: 2_000 });
    await expect(btn).toHaveText("Retry");
    await expect(btn).toHaveAttribute("data-action", "start");
    // applyStatus("error") should have cleared the diagnostic too.
    await expect(page.locator(".cm-diagnostic-error")).toHaveCount(0);

    // Type something else into the editor while engine is down, to
    // verify Retry-then-edit also flows correctly through the
    // rebuilt context.
    await page.keyboard.press("Control+A");
    await page.keyboard.type(`s("bd sd")`);

    // Retry rebuilds: a real start() runs, including evalNow on the
    // current doc. The "pattern updated" reply is the load-bearing
    // assertion — it proves the new ctx + node are actually live and
    // the wasm parse round-trip survived a teardown.
    await btn.click();
    await expect(status).toContainText("running", { timeout: 10_000 });
    await expect(page.locator("#log")).toContainText("pattern updated", { timeout: 5_000 });

    // Stop cleanly.
    await btn.click();
    await expect(status).toContainText("idle");
  });

  test("s(\"cp oh\") routes through new drum pools without diagnostic", async ({ page }) => {
    // Locks in the cp (clap, MIDI 39) + oh (open hi-hat, MIDI 46) drums
    // and their per-sound routing in process_scheduler_block. Before this
    // change the cheatsheet advertised both names but typing them
    // produced "unknown drum name" — a UI/runtime drift bug.
    await page.goto("/");
    await page.locator("#start").click();
    await expect(page.locator("#status")).toContainText("running", { timeout: 10_000 });
    await expect(page.locator("#log")).toContainText("pattern updated", { timeout: 5_000 });

    const editor = page.locator(".cm-content");
    await editor.click();
    await page.keyboard.press("Control+A");
    await page.keyboard.type(`s("cp oh")`);

    await expect(page.locator("#log")).toContainText("pattern updated", { timeout: 3_000 });
    await expect(page.locator(".cm-diagnostic-error")).toHaveCount(0);
    await expect(page.locator("#status")).toContainText("running");
  });

  test("dollar stack cross-source pattern evaluates end-to-end", async ({ page }) => {
    // Top-level `$:` stack lines let a single pattern produce events for
    // two different routing keys (s → drum pools by MIDI number, note →
    // synth pool). This test proves the new grammar survives the wasm-gc
    // boundary in the worklet parser AND that mixed-key events route
    // without producing a diagnostic. Unit tests cover parser correctness;
    // this is the integration anchor.
    await page.goto("/");
    await page.locator("#start").click();
    await expect(page.locator("#status")).toContainText("running", { timeout: 10_000 });
    await expect(page.locator("#log")).toContainText("pattern updated", { timeout: 5_000 });

    const editor = page.locator(".cm-content");
    await editor.click();
    await page.keyboard.press("Control+A");
    await page.keyboard.type(`$: s("bd sd")\n$: note("60 64")`);

    // pattern updated re-fires after debounce → proves the worklet's parse
    // accepted `$:` stack lines and the engine swapped patterns successfully.
    await expect(page.locator("#log")).toContainText("pattern updated", { timeout: 3_000 });
    // No diagnostic squiggle: the new grammar must parse cleanly.
    await expect(page.locator(".cm-diagnostic-error")).toHaveCount(0);
    // Status stays running through the swap.
    await expect(page.locator("#status")).toContainText("running");
  });

  test("stack() with no args surfaces a parse diagnostic", async ({ page }) => {
    // Empty stack() must fail parse with a position-tagged message.
    // Verifies the rich error string crosses the wasm-gc boundary the
    // same way other parse errors do (see "invalid pattern" test).
    await page.goto("/");
    await page.locator("#start").click();
    await expect(page.locator("#status")).toContainText("running", { timeout: 10_000 });
    await expect(page.locator("#log")).toContainText("pattern updated", { timeout: 5_000 });

    const editor = page.locator(".cm-content");
    await editor.click();
    await page.keyboard.press("Control+A");
    await page.keyboard.type(`stack()`);

    const log = page.locator("#log");
    await expect(log).toContainText("kept last good", { timeout: 3_000 });
    await expect(log).toContainText("stack()");
    await expect(log).toContainText("position");
    await expect(page.locator(".cm-diagnostic-error")).toBeVisible();
    // Engine keeps playing the previous graph.
    await expect(page.locator("#status")).toContainText("running");
  });

  test("Retry after engine error rebuilds and re-sends pattern", async ({ page }) => {
    // Force the wasm fetch to 404 so AudioEngine.start() throws and
    // status flips to "error". The UI should then show "Retry" and
    // clear lastGood / latestSentText so a successful retry actually
    // re-sends the editor doc instead of short-circuiting.
    let blockWasm = true;
    await page.route("**/moonbit_dsp.wasm", async (route) => {
      if (blockWasm) {
        await route.fulfill({ status: 404, body: "blocked by test" });
      } else {
        await route.continue();
      }
    });

    await page.goto("/");

    const btn = page.locator("#start");
    const status = page.locator("#status");
    const log = page.locator("#log");

    // First attempt fails on wasm fetch.
    await btn.click();
    await expect(status).toContainText("error", { timeout: 10_000 });
    await expect(btn).toHaveText("Retry");
    await expect(btn).toHaveAttribute("data-action", "start");

    // Unblock the wasm and retry.
    blockWasm = false;
    await btn.click();
    await expect(status).toContainText("running", { timeout: 10_000 });
    await expect(btn).toHaveText("Stop audio");

    // Crucial: the initial pattern must evaluate after retry — proves
    // lastGood was cleared on the error→Retry transition. If it weren't,
    // evalNow would short-circuit (text === lastGood) and "pattern
    // updated" would never appear.
    await expect(log).toContainText("pattern updated", { timeout: 5_000 });

    // Clean stop after retry confirms no leaked context state.
    await btn.click();
    await expect(status).toContainText("idle");
    await expect(btn).toHaveText("Start audio");
  });
});
