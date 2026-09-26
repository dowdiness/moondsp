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

test("accepted composition previews across sections despite a broken draft", async ({ page }) => {
  await page.goto("/");
  await page.locator("#section-composition-example").click();
  await page.locator("#start").click();
  await expect(page.locator("#section-list .section-row")).toHaveCount(4);
  await page.locator("#range-start").fill("31");
  await page.locator("#range-end").fill("65");
  await page.locator("#loop-range").click();
  await expect(page.locator("#loop-status")).toContainText("Loop [31, 65)");
  await page.locator(".cm-content").fill("note(");
  await expect(page.locator("#log")).toHaveClass(/error/);
  await expect(page.locator("#loop-status")).toContainText("Loop [31, 65)");
  await page.locator("#whole-song").click();
  await expect(page.locator("#loop-status")).toContainText("Whole song");
  await expect(page.locator("#status")).toHaveText("Playing");
});
