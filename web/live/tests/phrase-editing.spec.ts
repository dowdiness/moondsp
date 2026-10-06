import { expect, test, type Locator } from "@playwright/test";
import { readCode, replaceCode } from "./editor-helpers";

async function center(locator: Locator): Promise<{ x: number; y: number }> {
  let point = { x: 0, y: 0 };
  await expect.poll(async () => {
    const box = await locator.boundingBox();
    if (!box || box.width <= 0 || box.height <= 0) return false;
    point = { x: box.x + box.width / 2, y: box.y + box.height / 2 };
    return true;
  }).toBe(true);
  return point;
}

test("a selected phrase moves and transposes as a unit, survives Redo, and duplicates independently", async ({ page }) => {
  await page.goto("/");
  const source = 'note("C4@2  Eb4 G4 A4").slow(2).gain(.2)';
  await replaceCode(page, source);
  await page.locator(".moving-score__note-block").first().click();
  await page.getByRole("button", { name: "Select", exact: true }).click();
  const grid = page.locator(".moving-score__canvas");
  await grid.press("ArrowRight");
  await expect(page.locator(".moving-score__note.is-selected")).toHaveCount(2);
  await grid.press("ArrowLeft");
  await expect(page.locator(".moving-score__note.is-selected")).toHaveCount(1);
  await grid.press("ArrowRight");
  await grid.press("Escape");
  await grid.press("ArrowUp");
  const raised = source.replace("C4@2  Eb4", "C#4@2  E4");
  await expect.poll(() => readCode(page)).toBe(raised);
  await grid.press("Alt+ArrowRight");
  const moved = source.replace("C4@2  Eb4 G4", "G4  C#4@2 E4");
  await expect.poll(() => readCode(page)).toBe(moved);
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(raised);
  await page.locator("#redo").click();
  await expect.poll(() => readCode(page)).toBe(moved);
  await expect(page.locator(".moving-score__note.is-selected")).toHaveCount(2);
  await page.getByRole("button", { name: "Duplicate", exact: true }).click();
  const copied = moved.replace("C#4@2 E4", "C#4@2 E4 C#4@2 E4");
  await expect.poll(() => readCode(page)).toBe(copied);
  await grid.press("ArrowDown");
  await expect.poll(() => readCode(page)).toBe(moved.replace("C#4@2 E4", "C#4@2 E4 C4@2 D#4"));
  await grid.press("Delete");
  await expect.poll(() => readCode(page)).toBe(moved.replace("C#4@2 E4", "C#4@2 E4 ~@2 ~"));
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(moved.replace("C#4@2 E4", "C#4@2 E4 C4@2 D#4"));
});

test("pointer range movement previews displaced neighbors, cancels, and commits one source edit", async ({ page }) => {
  await page.goto("/");
  const source = 'note("C4 E4 G4 A4").gain(.2)';
  await replaceCode(page, source);
  await page.getByRole("button", { name: "Select", exact: true }).click();
  const first = await center(page.locator(".moving-score__note-block").nth(0));
  const second = await center(page.locator(".moving-score__note-block").nth(1));
  await page.mouse.move(first.x, first.y);
  await page.mouse.down();
  await page.mouse.move(second.x, second.y);
  await page.mouse.up();
  await expect(page.locator(".moving-score__note.is-selected")).toHaveCount(2);
  await page.getByRole("button", { name: "Select", exact: true }).click();
  await page.mouse.move(first.x, first.y);
  await page.mouse.down();
  await page.mouse.move(second.x, first.y);
  await expect(page.locator(".moving-score__context-preview")).toHaveCount(1);
  expect(await readCode(page)).toBe(source);
  await page.keyboard.press("Escape");
  await page.mouse.up();
  expect(await readCode(page)).toBe(source);
  await page.getByRole("button", { name: "Select", exact: true }).click();
  await page.locator(".moving-score__canvas").press("ArrowRight");
  await page.locator(".moving-score__canvas").press("Escape");
  await page.mouse.move(first.x, first.y);
  await page.mouse.down();
  await page.mouse.move(second.x, first.y);
  await page.mouse.up();
  await expect.poll(() => readCode(page)).toBe(source.replace("C4 E4 G4", "G4 C4 E4"));
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(source);
});

test.describe("touch phrase selection", () => {
  test.use({ hasTouch: true, isMobile: true, viewport: { width: 390, height: 844 } });
  test("touch selects a source range without painting pitches and moves it together", async ({ page }) => {
    await page.goto("/");
    const source = 'note("C4 E4 G4 A4").gain(.2)';
    await replaceCode(page, source);
    await page.getByRole("button", { name: "Select", exact: true }).tap();
    const first = await center(page.locator(".moving-score__note-block").nth(0));
    const second = await center(page.locator(".moving-score__note-block").nth(1));
    const cdp = await page.context().newCDPSession(page);
    await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [first] });
    await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [second] });
    await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    await expect(page.locator(".moving-score__note.is-selected")).toHaveCount(2);
    expect(await readCode(page)).toBe(source);
    await page.getByRole("button", { name: "Select", exact: true }).tap();
    await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [first] });
    await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ x: second.x, y: first.y }] });
    await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    await expect.poll(() => readCode(page)).toBe(source.replace("C4 E4 G4", "G4 C4 E4"));
    await page.locator("#undo").tap();
    await expect.poll(() => readCode(page)).toBe(source);
    await cdp.detach();
  });
});

test("code-selected inner notes and a repeated group retain their source scope", async ({ page }) => {
  await page.goto("/");
  const source = 'note("[C4 E4]*2 G4").gain(.2)';
  await replaceCode(page, source);
  const editor = page.locator(".cm-content");
  await editor.press("Control+Home");
  for (let i = 0; i < 7; i++) await editor.press("ArrowRight");
  for (let i = 0; i < 5; i++) await editor.press("Shift+ArrowRight");
  await expect(page.locator(".moving-score__note.is-selected")).toHaveCount(4);
  const grid = page.locator(".moving-score__canvas");
  await grid.focus();
  await grid.press("ArrowUp");
  const raised = source.replace("C4 E4", "C#4 F4");
  await expect.poll(() => readCode(page)).toBe(raised);
  await page.locator(".moving-score__structure-details > summary").click();
  await page.locator(".moving-score__group").click();
  await grid.focus();
  await grid.press("Alt+ArrowRight");
  const moved = raised.replace("[C#4 F4]*2 G4", "G4 [C#4 F4]*2");
  await expect.poll(() => readCode(page)).toBe(moved);
  await page.getByRole("button", { name: "Rest", exact: true }).click();
  await expect.poll(() => readCode(page)).toBe(moved.replace("C#4 F4", "~ ~"));
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(moved);
});
