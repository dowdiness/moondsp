import { expect, test } from "@playwright/test";
import { replaceCode } from "./editor-helpers";

test("an invalid initial editor cannot start playback", async ({ page }) => {
  await page.goto("/");
  await replaceCode(page, "note(");
  await page.locator("#start").click();
  await expect(page.locator("#log")).toHaveClass(/error/);
  await expect(page.locator("#start")).toHaveText("Play");
  await expect(page.locator("#status")).toHaveAttribute("data-sample-position", "0");
});
