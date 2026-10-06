import { expect, test, type Page } from "@playwright/test";
import { readCode, replaceCode } from "./editor-helpers";

const root = (page: Page) => page.getByRole("combobox", { name: "Chord root", exact: true, includeHidden: true });
const quality = (page: Page) => page.getByRole("combobox", { name: "Chord type", exact: true, includeHidden: true });
async function choose(page: Page, field: "root" | "quality", value: string) {
  const input = field === "root" ? root(page) : quality(page);
  if (!await input.isVisible()) await page.locator(".chord-controls__named > summary").click();
  await input.selectOption(value);
}

test("chord edits retain weighted repeated source and restore the target through shared history", async ({ page }) => {
  await page.goto("/");
  const source = 'chord("[C@2 Dm]*2 G7").slow(2).gain(.2)';
  await replaceCode(page, source);
  await page.locator(".step-pad").nth(1).click();
  await choose(page, "root", "Bb");
  const rooted = source.replace("Dm", "Bbm");
  await expect.poll(() => readCode(page)).toBe(rooted);
  await choose(page, "quality", "maj7");
  const edited = source.replace("Dm", "Bbmaj7");
  await expect.poll(() => readCode(page)).toBe(edited);
  await expect(page.locator(".chord-controls__tones")).toHaveText("Bb4 · D5 · F5 · A5");
  await expect(quality(page)).toHaveValue("maj7");
  await expect(page.locator(".moving-score__note.is-selected")).toHaveCount(8);
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(rooted);
  await page.locator("#redo").click();
  await expect.poll(() => readCode(page)).toBe(edited);
  await choose(page, "root", "F");
  await expect.poll(() => readCode(page)).toBe(source.replace("Dm", "Fmaj7"));
  await expect(page.locator("#status")).toHaveText("Ready");
});

test("root editing preserves quality aliases and registers without confusing sus or octave digits", async ({ page }) => {
  await page.goto("/");
  const source = 'chord("Dbmin73@2 Csus4 C+7 Cmaj77")';
  await replaceCode(page, source);
  await page.locator(".step-pad").first().click();
  await expect(quality(page)).toHaveValue("min7");
  await choose(page, "quality", "m7");
  await expect.poll(() => readCode(page)).toBe(source);
  await choose(page, "root", "F");
  await expect.poll(() => readCode(page)).toBe(source.replace("Dbmin73", "Fmin73"));
  await expect(page.locator(".chord-controls__tones")).toHaveText("F3 · G#3 · C4 · D#4");
  await page.locator(".step-pad").nth(1).click();
  await expect(root(page)).toHaveValue("C");
  await expect(quality(page)).toHaveValue("sus4");
  await choose(page, "root", "Db");
  await expect.poll(() => readCode(page)).toBe(source.replace("Dbmin73", "Fmin73").replace("Csus4", "Dbsus4"));
  await page.locator(".step-pad").nth(2).click();
  await choose(page, "root", "G");
  await expect.poll(() => readCode(page)).toContain("G+7");
  await page.locator(".step-pad").nth(3).click();
  await choose(page, "quality", "");
  await expect.poll(() => readCode(page)).toContain("C07");
  await expect(page.locator(".chord-controls__tones")).toHaveText("C7 · E7 · G7");
  await choose(page, "quality", "m7");
  await expect(page.locator(".chord-controls__tones")).toHaveText("C7 · D#7 · G7 · A#7");
});

test("code edits refresh chord controls and partial source selections cannot change an unrelated chord", async ({ page }) => {
  await page.goto("/");
  const source = 'chord("Cmaj7 Dm")';
  await replaceCode(page, source);
  const editor = page.locator(".cm-content");
  await editor.press("Control+Home");
  for (let i = 0; i < source.indexOf("maj7"); i++) await editor.press("ArrowRight");
  await editor.press("Shift+ArrowRight");
  await expect(page.locator(".chord-controls")).toBeHidden();
  await page.locator(".step-pad").nth(1).click();
  await choose(page, "root", "E");
  await expect.poll(() => readCode(page)).toBe(source.replace("Dm", "Em"));
  await replaceCode(page, 'chord("Fsus2")');
  await expect(root(page)).toHaveValue("F");
  await expect(quality(page)).toHaveValue("sus2");
  await expect(page.locator(".chord-controls__tones")).toHaveText("F4 · G4 · C5");
});

test("a chord chosen in a rest preserves its repetitions and can be cleared and undone", async ({ page }) => {
  await page.goto("/");
  const source = 'chord("~@2*2 ~").gate(.4)';
  await replaceCode(page, source);
  await page.locator(".step-pad").first().click();
  await choose(page, "quality", "m7");
  const edited = source.replace("~@2", "Cm7@2");
  await expect.poll(() => readCode(page)).toBe(edited);
  await expect(page.locator(".moving-score__note.is-selected")).toHaveCount(8);
  await page.getByRole("button", { name: "Rest", exact: true }).click();
  await expect.poll(() => readCode(page)).toBe(source);
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(edited);
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(source);
});

test("a denser chord cannot exceed the notation projection boundary or leave stale controls", async ({ page }) => {
  await page.goto("/");
  const source = `chord("${Array(85).fill("C").join(" ")}")`;
  await replaceCode(page, source);
  await page.locator(".step-pad").first().click();
  await choose(page, "quality", "maj9");
  await expect.poll(() => readCode(page)).toBe(source);
  await expect(quality(page)).toHaveValue("");
  await expect(page.locator(".note-properties > .step-feedback")).toBeVisible();
  await choose(page, "root", "F");
  await expect.poll(() => readCode(page)).toBe(source.replace('"C ', '"F '));
  await expect(page.locator(".chord-controls__tones")).toHaveText("F4 · A4 · C5");
});

test.describe("touch chord editing", () => {
  test.use({ hasTouch: true, isMobile: true, viewport: { width: 390, height: 844 } });
  test("a selected chord changes all its tones and survives a saved reload", async ({ page }) => {
    await page.goto("/");
    const source = 'bpm(120); chord("C Am").gain(.2)';
    await replaceCode(page, source);
    await page.locator(".step-pad").nth(1).tap();
    await choose(page, "root", "Db");
    await choose(page, "quality", "sus4");
    const edited = source.replace("Am", "Dbsus4");
    await expect.poll(() => readCode(page)).toBe(edited);
    await expect(page.locator(".chord-controls__tones")).toHaveText("Db4 · Gb4 · Ab4");
    await page.locator("#start").tap();
    await expect(page.locator("#status")).toHaveText("Playing");
    await expect(page.locator(".moving-score__canvas")).toBeHidden();
    await expect(page.locator(".step-pad").nth(1)).toHaveClass(/is-playing/);
    await page.locator(".moving-score__tone-details > summary").tap();
    await expect(page.locator(".moving-score__canvas")).toBeVisible();
    await expect.poll(() => page.locator('.moving-score__note.is-playing[data-index="1"]').count()).toBe(3);
    await choose(page, "root", "F");
    await expect(page.locator(".moving-score__canvas")).toBeVisible();
    await page.locator("#undo").tap();
    await expect.poll(() => readCode(page)).toBe(edited);
    await page.locator("#start").tap();
    await expect(page.locator("#save-status")).toHaveText("Saved locally");
    await page.reload();
    await expect.poll(() => readCode(page)).toBe(edited);
    await expect(page.locator("#status")).toHaveText("Ready");
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  });
});
