import { expect, test } from "@playwright/test";
import { openPitchControls, readCode, replaceCode } from "./editor-helpers";

test("real onset decorations preserve editing selection, scroll and shared Undo", async ({ page }) => {
  await page.goto("/");
  const source = 'bpm(120); note("C4 E4 G4").gain(.2)';
  await replaceCode(page, source);
  await page.locator(".moving-score__note-block").nth(2).click();
  await openPitchControls(page);
  await page.getByRole("button", { name: "Set A4", exact: true }).click();
  const edited = source.replace("G4", "A4");
  await expect.poll(() => readCode(page)).toBe(edited);
  await page.locator("#start").click();
  await expect(page.locator("#status")).toHaveText("Playing");
  const editor = page.locator(".cm-content");
  await editor.focus();
  await editor.press("Control+Home");
  for (let i = 0; i < source.indexOf("C4"); i++) await editor.press("ArrowRight");
  await editor.press("Shift+ArrowRight");
  await editor.press("Shift+ArrowRight");
  const before = await page.evaluate(() => ({
    selection: window.getSelection()?.toString(),
    scroll: document.querySelector(".cm-scroller")!.scrollTop,
  }));
  expect(before.selection).toBe("C4");
  await expect(page.locator(".cm-playback-atom").first()).toBeVisible();
  const after = await page.evaluate(() => ({
    selection: window.getSelection()?.toString(),
    scroll: document.querySelector(".cm-scroller")!.scrollTop,
  }));
  expect(after).toEqual(before);
  await expect(editor).toBeFocused();
  expect(await readCode(page)).toBe(edited);
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(source);
});
