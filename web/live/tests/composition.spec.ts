import { expect, test } from "@playwright/test";
import { readCode, replaceCode } from "./editor-helpers";

const source = 'bpm(120);\n$: s("bd ~ sd ~").slow(4)\n$: note("C4  Eb4 F4 G4").slow(4).gain(0.2)';

test("selected note weight and Rest preserve exact source and share Undo", async ({ page }) => {
  await page.goto("/");
  await replaceCode(page, source);
  await page.locator(".score-pattern[data-kind='note'] .moving-score__note-block").first().click();
  await page.locator(".structure-timing > summary").click();
  const row = page.locator(".note-properties");
  const length = row.getByRole("spinbutton", { name: "Relative weight" });
  await length.fill("2");
  await length.press("Tab");
  const lengthEdited = source.replace("C4  ", "C4@2  ");
  await expect.poll(() => readCode(page)).toBe(lengthEdited);
  await row.getByRole("button", { name: "Rest", exact: true }).click();
  const rested = lengthEdited.replace("C4", "~");
  await expect.poll(() => readCode(page)).toBe(rested);
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(lengthEdited);
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(source);
});

test("note weight cannot exceed the total 256-unit notation limit", async ({ page }) => {
  await page.goto("/");
  const boundary = `note("${Array(15).fill("C4@16").join(" ")} D4@15 E4")`;
  await replaceCode(page, boundary);
  await page.locator(".moving-score__note-block").last().click();
  await page.locator(".structure-timing > summary").click();
  const row = page.locator(".note-properties");
  const length = row.getByRole("spinbutton", { name: "Relative weight" });
  await length.fill("2");
  await length.press("Tab");
  expect(await readCode(page)).toBe(boundary);
  await expect(length).toHaveValue("1");
});
