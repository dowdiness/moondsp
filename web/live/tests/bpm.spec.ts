import { expect, test } from "@playwright/test";

test("paused source tempo edits are accepted without moving the transport", async ({ page }) => {
  await page.goto("/");
  await page.locator(".cm-content").fill('bpm(90); note("60").slow(8)');
  await page.locator("#start").click();
  await expect(page.locator("#status")).toHaveText("Playing");
  await page.locator("#start").click();
  await expect(page.locator("#status")).toHaveText("Paused");
  const position = await page.locator("#status").getAttribute("data-sample-position");
  await page.locator(".cm-content").fill('bpm(72); note("60").slow(8)');
  await expect(page.locator("#status")).toHaveAttribute("data-tempo", "72");
  await expect(page.locator("#status")).toHaveAttribute("data-sample-position", position!);
  await page.locator(".cm-content").fill('note("60").slow(8)');
  await expect(page.locator("#status")).toHaveAttribute("data-tempo", "60");
  await expect(page.locator("#status")).toHaveAttribute("data-sample-position", position!);
});
