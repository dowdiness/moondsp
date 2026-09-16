import { expect, test } from "@playwright/test";

test("invalid Restart preserves a paused song, and Play resumes it without compiling the editor", async ({ page }) => {
  await page.goto("/");
  await page.locator(".cm-content").fill('note("60").slow(8).room(0.5)');
  await page.locator("#start").click();
  await expect(page.locator("#status")).toHaveText("Playing");
  await page.locator("#start").click();
  await expect(page.locator("#status")).toHaveText("Paused");
  const position = await page.locator("#status").getAttribute("data-sample-position");
  await page.locator(".cm-content").fill("note(");
  await expect(page.locator("#log")).toHaveClass(/error/);
  await page.locator("#restart").click();
  await expect(page.locator("#status")).toHaveText("Paused");
  await expect(page.locator("#status")).toHaveAttribute("data-sample-position", position!);
  await page.locator("#start").click();
  await expect(page.locator("#status")).toHaveText("Playing");
  await expect(page.locator("#log")).toHaveClass(/error/);
  await page.locator(".cm-content").fill('note("67").slow(8)');
  await expect(page.locator("#log")).not.toHaveClass(/error/);
});

test("Ended accepts a different song without starting; Play begins its latest version", async ({ page }) => {
  await page.goto("/");
  await page.locator(".cm-content").fill('bpm(1000); song(section("a",1,silence()),part("first","a"))');
  await page.locator("#start").click();
  await expect(page.locator("#status")).toHaveText("Ended");
  const endedPosition = await page.locator("#status").getAttribute("data-sample-position");
  await page.locator(".cm-content").fill('bpm(30); note("67").slow(8)');
  await expect(page.locator("#status")).toHaveAttribute("data-tempo", "30");
  await expect(page.locator("#status")).toHaveText("Ended");
  await expect(page.locator("#status")).toHaveAttribute("data-sample-position", endedPosition!);
  await page.locator("#start").click();
  await expect(page.locator("#status")).toHaveText("Playing");
  await expect(page.locator("#status")).toHaveAttribute("data-tempo", "30");
});
