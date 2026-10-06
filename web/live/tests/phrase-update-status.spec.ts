import { expect, test } from "@playwright/test";
import type { PlaybackView } from "../src/playback";
import { phraseUpdateFeedback } from "../src/phrase-update-status";
import { replaceCode } from "./editor-helpers";

function playback(overrides: Partial<PlaybackView> = {}): PlaybackView {
  return {
    status: { kind: "running" }, state: "Playing", currentSource: 'note("60")',
    acceptedVersion: [1, 2], draftVersion: [1, 2], inFlightVersions: [], draftStatus: "accepted",
    tempoText: "120", samplePosition: 0, mode: "pattern", cyclePosition: 0,
    pendingCount: 0, skippedCount: 0, feedback: null, diagnostic: null,
    ...overrides,
  };
}

test("phrase feedback distinguishes accepted pending materials from current audible content", () => {
  const pending = phraseUpdateFeedback(playback({ pendingCount: 1 }));
  expect(pending).toMatchObject({ scope: "score", tone: "neutral" });
  expect(phraseUpdateFeedback(playback())).toBeNull();
});

test("older acceptance cannot settle a newer draft; rejection scope is score-wide", () => {
  const newer = phraseUpdateFeedback(playback({ draftStatus: "accepted", acceptedVersion: [1, 1], draftVersion: [1, 2] }));
  expect(newer).toMatchObject({ scope: "phrase", tone: "neutral" });
  const rejected = phraseUpdateFeedback(playback({ draftStatus: "rejected", state: "Paused" }));
  expect(rejected).toMatchObject({ scope: "score", tone: "error" });
});

test("phrase feedback survives closing controls and clears only after pending material activates", async ({ page }) => {
  await page.goto("/");
  await replaceCode(page, 'note("60").slow(8)');
  await page.locator("#start").click();
  await expect(page.locator("#status")).toHaveText("Playing");
  await page.locator(".moving-score__note-block").click();
  await page.locator(".moving-score__canvas").press("ArrowUp");
  const update = page.locator(".score-pattern .phrase-update[role=status]");
  await expect(update).toBeVisible();
  await expect(update).toHaveAttribute("data-scope", "score");
  await page.locator("#source-toggle").click();
  await replaceCode(page, 'note("62").slow(8)');
  await page.locator("#source-toggle").click();
  await expect(update).toBeVisible();
  await expect(update).toHaveAttribute("data-scope", "score");
  await expect(update).toBeHidden({ timeout: 25000 });
  await expect(page.locator("#status")).toHaveText("Playing");
});
