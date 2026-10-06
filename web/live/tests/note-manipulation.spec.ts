import { expect, test, type Locator, type Page } from "@playwright/test";
import { projectNotation } from "../src/notation-structure";
import { readCode, replaceCode } from "./editor-helpers";

async function center(locator: Locator): Promise<{ x: number; y: number }> {
  await expect(locator).toBeVisible();
  const box = (await locator.boundingBox())!;
  return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
}

async function beginDrag(page: Page, from: { x: number; y: number }, to: { x: number; y: number }): Promise<void> {
  await page.mouse.move(from.x, from.y);
  await page.mouse.down();
  await page.mouse.move(to.x, to.y, { steps: 5 });
}

function projected(source: string) {
  const content = source.match(/note\("([^"]*)"\)/)![1];
  const result = projectNotation("note", content);
  expect(result.error).toBeNull();
  return result;
}

test("body drag moves a weighted note into a rest without painting its neighbors", async ({ page }) => {
  await page.goto("/");
  const source = '// 𠮷のフレーズ\nnote("C4@2  ~ D4").slow(2).gain(.2)';
  await replaceCode(page, source);
  const from = await center(page.locator('.moving-score__note[data-pitch="60"] .moving-score__note-block'));
  const rest = await center(page.locator(".moving-score__rest-hit"));
  await beginDrag(page, from, { x: rest.x, y: from.y });
  expect(await readCode(page)).toBe(source);
  await page.mouse.up();
  const moved = source.replace("C4@2  ~ D4", "~  C4@2 D4");
  await expect.poll(() => readCode(page)).toBe(moved);
  await expect(page.locator("#status")).toHaveText("Ready");
  const next = projected(await readCode(page));
  expect(next.events.find(event => event.pitch === 60)?.start).toBeCloseTo(.25);
  expect(next.events.find(event => event.pitch === 60)?.end).toBeCloseTo(.75);
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(source);
  await page.locator("#redo").click();
  await expect.poll(() => readCode(page)).toBe(moved);
});

test("diagonal body drag reorders occupied steps and changes only the moved pitch in one Undo", async ({ page }) => {
  await page.goto("/");
  const source = 'note("C4  E4 G4").gain(.2)';
  await replaceCode(page, source);
  const from = await center(page.locator(".moving-score__note-block").first());
  const destination = await center(page.locator(".moving-score__note-block").last());
  const pitch = await center(page.locator('.moving-score__lane[data-pitch="62"]'));
  await beginDrag(page, from, { x: destination.x, y: pitch.y });
  expect(await readCode(page)).toBe(source);
  await page.mouse.up();
  const moved = source.replace("C4  E4 G4", "E4  G4 D4");
  await expect.poll(() => readCode(page)).toBe(moved);
  await expect(page.locator(".moving-score__note.is-selected .moving-score__note-label")).toHaveText("D4");
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(source);
  await page.locator("#redo").click();
  await expect.poll(() => readCode(page)).toBe(moved);
  const canvas = page.locator(".moving-score__canvas");
  await canvas.focus();
  await canvas.press("ArrowUp");
  await expect.poll(() => readCode(page)).toBe(source.replace("C4  E4 G4", "E4  G4 Eb4"));
});

test("moving a repeated nested atom updates linked occurrences without crossing its group", async ({ page }) => {
  await page.goto("/");
  const source = 'note("[C4 ~]*2 G4").slow(.5).gain(.2)';
  await replaceCode(page, source);
  const from = await center(page.locator('.moving-score__note[data-pitch="60"] .moving-score__note-block').first());
  const rest = await center(page.locator(".moving-score__rest-hit").first());
  await beginDrag(page, from, { x: rest.x, y: from.y });
  await page.mouse.up();
  await expect.poll(() => readCode(page)).toBe(source.replace("[C4 ~]*2", "[~ C4]*2"));
  const starts = projected(await readCode(page)).events.filter(event => event.pitch === 60).map(event => event.start);
  expect(starts).toEqual([.125, .375]);
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(source);
  const outside = await center(page.locator('.moving-score__note[data-pitch="67"] .moving-score__note-block'));
  await beginDrag(page, from, { x: outside.x, y: from.y });
  await page.mouse.up();
  expect(await readCode(page)).toBe(source);
});

for (const edge of ["left", "right"] as const) {
  test(`${edge} note-edge resize previews without editing and preserves unrelated onsets`, async ({ page }) => {
    await page.goto("/");
    const source = 'note("C4 D4 E4").slow(2).gain(.2)';
    await replaceCode(page, source);
    const node = page.locator(".moving-score__note").nth(edge === "right" ? 0 : 1);
    const handle = node.locator(`.moving-score__note-edge[data-edge="${edge}"]`);
    const from = await center(handle);
    const first = (await page.locator(".moving-score__note-block").first().boundingBox())!;
    const second = (await page.locator(".moving-score__note-block").nth(1).boundingBox())!;
    // Centers of the first two equal source intervals are 1/6 and 1/2 cycle.
    const to = { x: edge === "left" ? first.x + first.width / 2 : second.x + second.width / 2, y: from.y };
    await beginDrag(page, from, to);
    expect(await readCode(page)).toBe(source);
    const previewEdge = await page.locator(".moving-score__preview-block").evaluateAll((blocks, target) => {
      const row = blocks.map(block => block.getBoundingClientRect())
        .find(rect => Math.abs(rect.y + rect.height / 2 - target.y) < 2);
      return row ? target.edge === "left" ? row.left : row.right : null;
    }, { y: from.y, edge });
    expect(previewEdge).not.toBeNull();
    await page.mouse.up();
    await expect.poll(async () => projected(await readCode(page)).events.find(event => event.pitch === 62)!.start)
      .toBeCloseTo(edge === "left" ? 1 / 6 : .5, 2);
    const after = projected(await readCode(page));
    expect(after.events.find(event => event.pitch === 60)?.start).toBe(0);
    expect(after.events.find(event => event.pitch === 64)?.start).toBeCloseTo(2 / 3);
    expect(after.events.find(event => event.pitch === 64)?.end).toBe(1);
    const committed = (await node.locator(".moving-score__note-block").boundingBox())!;
    expect(Math.abs((edge === "left" ? committed.x : committed.x + committed.width) - previewEdge!)).toBeLessThan(2);
    expect((await readCode(page)).endsWith('.slow(2).gain(.2)')).toBe(true);
    await page.locator("#undo").click();
    await expect.poll(() => readCode(page)).toBe(source);
  });
}

test("Escape cancels a pending body move and a pending edge resize", async ({ page }) => {
  await page.goto("/");
  const source = 'note("C4 E4 G4").gain(.2)';
  await replaceCode(page, source);
  const from = await center(page.locator(".moving-score__note-block").first());
  const destination = await center(page.locator(".moving-score__note-block").last());
  await beginDrag(page, from, { x: destination.x, y: from.y });
  await page.keyboard.press("Escape");
  await page.mouse.up();
  expect(await readCode(page)).toBe(source);
  const edge = await center(page.locator('.moving-score__note-edge[data-edge="right"]').first());
  await beginDrag(page, edge, { x: edge.x + 35, y: edge.y });
  await page.keyboard.press("Escape");
  await page.mouse.up();
  expect(await readCode(page)).toBe(source);
});

test("keyboard movement, duration and deletion remain source-linked and undoable", async ({ page }) => {
  await page.goto("/");
  const source = 'note("C4 E4 G4").gain(.2)';
  await replaceCode(page, source);
  await page.locator(".moving-score__note-block").first().click();
  const canvas = page.locator(".moving-score__canvas");
  await canvas.focus();
  await canvas.press("Alt+ArrowRight");
  await expect.poll(() => readCode(page)).toBe(source.replace("C4 E4", "E4 C4"));
  await canvas.press("ArrowUp");
  const pitched = source.replace("C4 E4 G4", "E4 C#4 G4");
  await expect.poll(() => readCode(page)).toBe(pitched);
  await canvas.press("Shift+ArrowRight");
  const resized = await readCode(page);
  const projection = projected(resized);
  expect(projection.events.find(event => event.pitch === 61)!.end).toBeGreaterThan(2 / 3);
  expect(projection.events.find(event => event.pitch === 61)!.start).toBeCloseTo(1 / 3);
  await canvas.press("Delete");
  await expect.poll(() => readCode(page)).toBe(resized.replace("C#4", "~"));
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(resized);
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(pitched);
});

test("moving identical notes follows the destination selection without rewriting the phrase", async ({ page }) => {
  await page.goto("/");
  const source = 'note("C4 C4 C4").gain(.2)';
  await replaceCode(page, source);
  const from = await center(page.locator(".moving-score__note-block").first());
  const to = await center(page.locator(".moving-score__note-block").last());
  await beginDrag(page, from, to);
  await page.mouse.up();
  expect(await readCode(page)).toBe(source);
  const canvas = page.locator(".moving-score__canvas");
  await canvas.focus();
  await canvas.press("ArrowUp");
  await expect.poll(() => readCode(page)).toBe(source.replace("C4 C4 C4", "C4 C4 C#4"));
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(source);
});

test("Shift-drag retains contour drawing rather than relocating the source note", async ({ page }) => {
  await page.goto("/");
  const source = 'note("C4 E4 G4").gain(.2)';
  await replaceCode(page, source);
  const first = await center(page.locator(".moving-score__note-block").first());
  const middle = await center(page.locator(".moving-score__note-block").nth(1));
  const last = await center(page.locator(".moving-score__note-block").last());
  const f = await center(page.locator('.moving-score__lane[data-pitch="65"]'));
  const e = await center(page.locator('.moving-score__lane[data-pitch="64"]'));
  await page.keyboard.down("Shift");
  await beginDrag(page, first, { x: middle.x, y: f.y });
  await page.mouse.move(last.x, e.y);
  await page.mouse.up();
  await page.keyboard.up("Shift");
  await expect.poll(() => readCode(page)).toBe(source.replace("C4 E4 G4", "C4 F4 E4"));
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(source);
});

test("a standalone note still supports vertical body movement", async ({ page }) => {
  await page.goto("/");
  const source = 'note("C4").gain(.2)';
  await replaceCode(page, source);
  const from = await center(page.locator(".moving-score__note-block"));
  const pitch = await center(page.locator('.moving-score__lane[data-pitch="62"]'));
  await beginDrag(page, from, { x: from.x, y: pitch.y });
  await page.mouse.up();
  await expect.poll(() => readCode(page)).toBe(source.replace("C4", "D4"));
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(source);
});

test.describe("touch note manipulation", () => {
  test.use({ hasTouch: true, isMobile: true, viewport: { width: 390, height: 844 } });

  test("a vertical body drag edits pitch instead of starting native grid scrolling", async ({ page }) => {
    await page.goto("/");
    const source = 'note("C4 ~ E4 G4").slow(2).gain(.2)';
    await replaceCode(page, source);
    const from = await center(page.locator('.moving-score__note[data-pitch="60"] .moving-score__note-block'));
    const pitch = await center(page.locator('.moving-score__lane[data-pitch="65"]'));
    const cdp = await page.context().newCDPSession(page);
    await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [from] });
    await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ x: from.x, y: pitch.y }] });
    await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    await expect.poll(() => readCode(page)).toBe(source.replace("C4", "F4"));
    await page.locator("#undo").click();
    await expect.poll(() => readCode(page)).toBe(source);

    const wideRange = 'note("C2 G6").gain(.2)';
    await replaceCode(page, wideRange);
    const stage = page.locator(".moving-score__stage");
    await expect.poll(() => stage.evaluate(element => element.scrollTop)).toBeGreaterThan(0);
    const scrollBefore = await stage.evaluate(element => element.scrollTop);
    const bounds = (await stage.boundingBox())!;
    const gutter = { x: bounds.x + 12, y: bounds.y + 70 };
    await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [gutter] });
    await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ x: gutter.x, y: gutter.y + 100 }] });
    await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    await expect.poll(() => stage.evaluate(element => element.scrollTop)).toBeLessThan(scrollBefore);
    expect(await readCode(page)).toBe(wideRange);
    await cdp.detach();
  });
});
