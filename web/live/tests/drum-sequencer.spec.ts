import { expect, test } from "@playwright/test";
import { readCode, replaceCode } from "./editor-helpers";

test("percussion cells change a rest to a hit and back while preserving postfixes and shared Undo", async ({ page }) => {
  await page.goto("/");
  const source = 's("~@2  bd*2@3")';
  await replaceCode(page, source);
  await page.getByRole("button", { name: "Set Kick at source step 1", exact: true }).click();
  await expect.poll(() => readCode(page)).toBe('s("bd@2  bd*2@3")');
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(source);

  await page.getByRole("button", { name: "Set Kick at source step 1", exact: true }).click();
  await page.getByRole("button", { name: "Clear Kick at source step 1", exact: true }).click();
  await expect.poll(() => readCode(page)).toBe(source);
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe('s("bd@2  bd*2@3")');
});

test("hi-hat and open hat are separate sounds and source edits refresh the matrix", async ({ page }) => {
  await page.goto("/");
  await replaceCode(page, 's("hh oh")');
  const hiHat = page.getByRole("button", { name: "Clear Hi-hat at source step 1", exact: true });
  const openHat = page.getByRole("button", { name: "Clear Open hat at source step 2", exact: true });
  await expect(hiHat).toHaveAttribute("aria-pressed", "true");
  await expect(openHat).toHaveAttribute("aria-pressed", "true");
  await replaceCode(page, 's("oh hh")');
  await expect(page.getByRole("button", { name: "Clear Open hat at source step 1", exact: true })).toHaveAttribute("aria-pressed", "true");
  await expect(page.getByRole("button", { name: "Clear Hi-hat at source step 2", exact: true })).toHaveAttribute("aria-pressed", "true");
});

test("matrix arrow navigation, edit focus, and Escape return to code", async ({ page }) => {
  await page.goto("/");
  await replaceCode(page, 's("~ ~")');
  const kick = page.getByRole("button", { name: "Set Kick at source step 1", exact: true });
  await kick.focus();
  await kick.press("ArrowDown");
  const snare = page.getByRole("button", { name: "Set Snare at source step 1", exact: true });
  await expect(snare).toBeFocused();
  await snare.press("Enter");
  await expect.poll(() => readCode(page)).toBe('s("sd ~")');
  await expect(page.getByRole("button", { name: "Clear Snare at source step 1", exact: true })).toBeFocused();
  await page.keyboard.press("Escape");
  await expect(page.locator(".cm-content")).toBeFocused();
});

test("editing a repeated hit updates its source and clears retired playback indication", async ({ page }) => {
  await page.goto("/");
  const source = 'bpm(120); s("[bd ~]*2").slow(4)';
  await replaceCode(page, source);
  await page.getByRole("button", { name: "Set Snare at source step 1", exact: true }).click();
  await expect.poll(() => readCode(page)).toBe(source.replace("bd", "sd"));
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(source);
  await page.locator("#start").click();
  const hit = page.getByRole("button", { name: "Clear Kick at source step 1", exact: true });
  await expect(hit).toHaveClass(/is-playing/);
  await hit.click();
  await expect.poll(() => readCode(page)).toBe(source.replace("bd", "~"));
  await expect(page.locator(".drum-sequencer__cell.is-playing")).toHaveCount(0);
  await page.locator("#start").click();
});
test("narrow percussion matrix scrolls internally with touch-sized cells", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/");
  await replaceCode(page, 's("~ ~ ~ ~ ~ ~ ~ ~ ~ ~")');
  const viewport = page.locator(".drum-sequencer__viewport");
  const dimensions = await viewport.evaluate(element => ({
    clientWidth: element.clientWidth,
    scrollWidth: element.scrollWidth,
    cellWidth: element.querySelector(".drum-sequencer__cell")!.getBoundingClientRect().width,
    pageWidth: document.documentElement.scrollWidth,
    viewportWidth: window.innerWidth,
  }));
  expect(dimensions.scrollWidth).toBeGreaterThan(dimensions.clientWidth);
  expect(dimensions.cellWidth).toBeGreaterThanOrEqual(44);
  expect(dimensions.pageWidth).toBeLessThanOrEqual(dimensions.viewportWidth);
});
