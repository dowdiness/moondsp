import { expect, test } from "@playwright/test";
import { openPitchControls, readCode, replaceCode } from "./editor-helpers";

test("subdivision and group repetition preserve suffixes and share source history", async ({ page }) => {
  await page.goto("/");
  const source = '// nested phrase\nnote("C4*2@2  D4 E4").fast(1.5).gain(.2)';
  await replaceCode(page, source);
  await page.locator(".moving-score__note-block").first().click();
  await page.locator(".moving-score__structure-details > summary").click();
  await page.getByRole("button", { name: "Split", exact: true }).click();
  const split = source.replace("C4*2@2", "[C4 C4]*2@2");
  await expect.poll(() => readCode(page)).toBe(split);
  await page.locator(".moving-score__group").first().click();
  const repeat = page.getByRole("spinbutton", { name: "Repeat selected source" });
  await expect(page.locator(".moving-score__note.is-selected")).toHaveCount(4);
  await repeat.fill("3");
  await repeat.press("Tab");
  await expect.poll(() => readCode(page)).toBe(split.replace("*2", "*3"));
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(split);
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(source);
});

test("repeated occurrences edit one source atom without flattening its group", async ({ page }) => {
  await page.goto("/");
  const source = 'note("[C4  Eb4]*2 G4").rev().gain(.2)';
  await replaceCode(page, source);
  await page.locator(".moving-score__note-block").first().click();
  await openPitchControls(page);
  await page.getByRole("button", { name: "Set D4", exact: true }).click();
  await expect.poll(() => readCode(page)).toBe(source.replace("C4", "D4"));
  await expect(page.locator(".moving-score__note.is-selected")).toHaveCount(2);
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(source);
});

test("a keyboard boundary edit preserves the following onset and is one Undo", async ({ page }) => {
  await page.goto("/");
  const source = 'note("C4  D4 E4").gain(.2)';
  await replaceCode(page, source);
  await page.locator(".moving-score__structure-details > summary").click();
  const boundary = page.locator(".moving-score__boundary").first();
  await boundary.evaluate(element => (element as SVGElement).focus());
  await boundary.press("ArrowRight");
  await expect.poll(() => readCode(page)).toBe(source.replace("C4  D4 E4", "C4@11  D4@9 E4@10"));
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(source);
});

test("fractional phrase stretch and gate retain outer transforms and produce real audio", async ({ page }) => {
  await page.goto("/");
  const source = 'bpm(120); note("[C4 Eb4]*2 G4").fast(1.5).gain(.2)';
  await replaceCode(page, source);
  await page.locator(".structure-timing > summary").click();
  const stretch = page.getByRole("spinbutton", { name: "Phrase stretch factor" });
  await stretch.fill("0.5");
  await stretch.press("Tab");
  const stretched = `${source}.slow(0.5)`;
  await expect.poll(() => readCode(page)).toBe(stretched);
  const gate = page.getByRole("spinbutton", { name: "Phrase gate fraction" });
  await gate.fill("0.25");
  await gate.press("Tab");
  await expect.poll(() => readCode(page)).toBe(`${stretched}.gate(0.25)`);
  await page.locator("#start").click();
  await expect(page.locator("#status")).toHaveText("Playing");
  await expect.poll(() => page.evaluate(() => {
    const samples = new Float32Array(2048);
    window.__moondspEngine!.readWaveform(samples);
    return samples.reduce((peak, sample) => Math.max(peak, Math.abs(sample)), 0);
  })).toBeGreaterThan(0.001);
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(stretched);
  await expect(page.locator("#status")).toHaveText("Playing");
});
