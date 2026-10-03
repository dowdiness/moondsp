import { expect, test } from "@playwright/test";
import { replaceCode } from "./editor-helpers";

test("paused source tempo edits are accepted without moving the transport", async ({ page }) => {
  await page.goto("/");
  await replaceCode(page, 'bpm(90); note("60").slow(8)');
  await page.locator("#start").click();
  await expect(page.locator("#status")).toHaveText("Playing");
  await page.locator("#start").click();
  await expect(page.locator("#status")).toHaveText("Paused");
  const position = await page.locator("#status").getAttribute("data-sample-position");
  await replaceCode(page, 'bpm(72); note("60").slow(8)');
  await expect(page.locator("#status")).toHaveAttribute("data-tempo", "72");
  await expect(page.locator("#status")).toHaveAttribute("data-sample-position", position!);
  await replaceCode(page, 'note("60").slow(8)');
  await expect(page.locator("#status")).toHaveAttribute("data-tempo", "60");
  await expect(page.locator("#status")).toHaveAttribute("data-sample-position", position!);
});
