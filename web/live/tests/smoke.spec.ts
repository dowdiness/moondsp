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

test("a mistake marks its place in the code; a score too large to play marks none", async ({ page }) => {
  await page.goto("/");
  // Inside quoted notation the mark falls on the unknown note, not near the string's start.
  await replaceCode(page, 'note("c4 ?? e4")');
  await expect(page.locator(".cm-diagnostic")).toHaveText("?");
  await expect(page.locator("#draft-status")).toHaveAttribute("data-state", "invalid");
  const layered = `song(section("a",4,s("bd*256")),${Array.from({ length: 96 }, (_, i) => `part("p${i}","a",0)`).join(",")})`;
  await replaceCode(page, layered);
  await page.locator("#start").click();
  await expect(page.locator("#draft-status")).toHaveAttribute("data-state", "over-limit");
  await expect(page.locator("#draft-status")).toHaveText("Score is too large to play");
  await expect(page.locator("#log")).toHaveText("playback arrangement exceeds the query expansion limit");
  await expect(page.locator(".cm-diagnostic")).toHaveCount(0);
});
