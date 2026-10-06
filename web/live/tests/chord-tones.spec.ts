import { expect, test, type Locator, type Page } from "@playwright/test";
import { readCode, replaceCode } from "./editor-helpers";

const tone = (page: Page, pitch: number) => page.locator(`.chord-tones__tone[data-pitch="${pitch}"]`);
async function center(locator: Locator) {
  await locator.scrollIntoViewIfNeeded();
  return locator.evaluate(element => {
    const box = element.getBoundingClientRect();
    return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
  });
}
async function drag(page: Page, locator: Locator, semitones: number, cancel = false) {
  const point = await center(locator);
  await page.mouse.move(point.x, point.y);
  await page.mouse.down();
  await page.mouse.move(point.x, point.y - semitones * 24, { steps: 4 });
  if (cancel) await page.keyboard.press("Escape");
  await page.mouse.up();
}

test("tone drag changes harmony in one history step and keeps linked source timing", async ({ page }) => {
  await page.goto("/");
  const source = 'chord("[C@2 F]*2 ~").slow(2).gain(.2)';
  await replaceCode(page, source);
  await drag(page, tone(page, 64), -1, true);
  expect(await readCode(page)).toBe(source);
  await drag(page, tone(page, 64), -1);
  await expect.poll(() => readCode(page)).toBe(source.replace("C@2", "Cm@2"));
  await expect(tone(page, 63)).toBeVisible();
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(source);
  await page.locator("#redo").click();
  await expect.poll(() => readCode(page)).toBe(source.replace("C@2", "Cm@2"));
  await drag(page, page.getByRole("button", { name: "Move chord", exact: true }), 2);
  await expect.poll(() => readCode(page)).toBe(source.replace("C@2", "Dm@2"));
});

test("arbitrary voicings can add and remove tones through the final rest", async ({ page }) => {
  await page.goto("/");
  const source = 'chord("{60}@2*2 F")';
  await replaceCode(page, source);
  await page.locator('.chord-tones__lane[data-pitch="61"]').click({ position: { x: 100, y: 12 } });
  await expect.poll(() => readCode(page)).toBe(source.replace("{60}", "{60,61}"));
  await tone(page, 60).click();
  await page.getByRole("button", { name: "Remove tone", exact: true }).click();
  await expect.poll(() => readCode(page)).toBe(source.replace("{60}", "{61}"));
  await tone(page, 61).click();
  await page.locator(".chord-tones__canvas").press("Delete");
  await expect.poll(() => readCode(page)).toBe(source.replace("{60}", "~"));
  await page.getByRole("button", { name: "Add tone", exact: true }).focus();
  await page.keyboard.press("Enter");
  await expect.poll(() => readCode(page)).toBe(source);
  await page.locator(".chord-tones__canvas").press("ArrowUp");
  await expect.poll(() => readCode(page)).toBe(source.replace("{60}", "{61}"));
  await page.locator(".chord-tones__canvas").press("Delete");
  await expect.poll(() => readCode(page)).toBe(source.replace("{60}", "~"));
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(source.replace("{60}", "{61}"));
});

test("pitch collisions and MIDI boundaries do not discard tones", async ({ page }) => {
  await page.goto("/");
  await replaceCode(page, 'chord("{60,61}")');
  await tone(page, 60).click();
  await page.locator(".chord-tones__canvas").press("ArrowUp");
  expect(await readCode(page)).toBe('chord("{60,61}")');
  await expect(page.locator(".chord-tones__message")).toBeVisible();
  await replaceCode(page, 'chord("{0,127}")');
  await page.getByRole("button", { name: "Move chord", exact: true }).focus();
  await page.keyboard.press("ArrowUp");
  expect(await readCode(page)).toBe('chord("{0,127}")');
  await expect(page.locator('.chord-tones__tone')).toHaveCount(2);
});

test("a source replacement cancels an unfinished tone drag", async ({ page }) => {
  await page.goto("/");
  await replaceCode(page, 'chord("C")');
  const point = await center(tone(page, 64));
  await page.mouse.move(point.x, point.y);
  await page.mouse.down();
  await page.mouse.move(point.x, point.y + 24);
  expect(await readCode(page)).toBe('chord("C")');
  await replaceCode(page, 'chord("F")');
  await page.mouse.up();
  await expect.poll(() => readCode(page)).toBe('chord("F")');
  await expect(tone(page, 65)).toBeVisible();
});

test.describe("touch chord tones", () => {
  test.use({ hasTouch: true, isMobile: true, viewport: { width: 390, height: 844 } });
  test("native touch writes custom tones and plays the saved source", async ({ page }) => {
    await page.goto("/");
    const source = 'bpm(120); chord("C@2 F").gain(.2)';
    await replaceCode(page, source);
    const client = await page.context().newCDPSession(page);
    for (const [pitch, delta] of [[64, -1], [67, 1]]) {
      const point = await center(tone(page, pitch));
      await client.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ ...point }] });
      await client.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ x: point.x, y: point.y - delta * 24 }] });
      await client.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    }
    const edited = source.replace("C@2", "{60,63,68}@2");
    await expect.poll(() => readCode(page)).toBe(edited);
    await page.locator("#start").tap();
    await expect(page.locator("#status")).toHaveText("Playing");
    await expect(page.locator(".chord-tones")).toHaveClass(/is-playing/);
    await expect.poll(() => page.evaluate(() => {
      const samples = new Float32Array(2048);
      window.__moondspEngine!.readWaveform(samples);
      return Math.max(...samples.map(Math.abs));
    })).toBeGreaterThan(.001);
    await page.locator("#start").tap();
    await expect(page.locator("#save-status")).toHaveText("Saved locally");
    await page.reload();
    await expect.poll(() => readCode(page)).toBe(edited);
    await expect(tone(page, 68)).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  });
});
