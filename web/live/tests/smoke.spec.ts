import { expect, test } from "@playwright/test";

test("an invalid initial editor cannot start playback", async ({ page }) => {
  await page.goto("/");
  await page.locator(".cm-content").fill("note(");
  await page.locator("#start").click();
  await expect(page.locator("#log")).toHaveClass(/error/);
  await expect(page.locator("#start")).toHaveText("Play");
  await expect(page.locator("#status")).toHaveAttribute("data-sample-position", "0");
});

test("the independent compiled demo still starts and closes", async ({ page }) => {
  await page.goto("/?audioMode=compiled");
  await page.locator("#start").click();
  await expect(page.locator("#status")).toHaveText("Playing");
  await page.locator("#start").click();
  await expect(page.locator("#status")).toHaveText("Ready");
});
