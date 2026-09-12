import { test, expect } from "@playwright/test";

test("score replies preserve an uncommitted BPM input", async ({ page }) => {
  await page.clock.install({ time: new Date("2026-01-01T00:00:00Z") });
  await page.goto("/");
  const editor = page.locator(".cm-content");
  const bpm = page.locator("#global-bpm");
  const log = page.locator("#log");
  await editor.fill('note("60")');
  await page.getByRole("button", { name: "Play", exact: true }).click();
  await expect(log).toContainText("pattern updated");

  // Hold the edit debounce until the user has started typing the new tempo.
  // AudioWorklet replies still run on the real audio clock.
  await page.clock.pauseAt(new Date("2026-01-01T01:00:00Z"));
  await editor.fill('note("72")');
  await bpm.fill("120");
  await page.clock.runFor(250);
  await expect(log).toContainText("edit queued");
  await expect(bpm).toBeFocused();
  await expect(bpm).toHaveValue("120");

  await bpm.press("Enter");
  await expect(bpm).toHaveValue("120");
  await expect(log).toContainText("BPM 120");
  await page.clock.resume();
  await page.getByRole("button", { name: "Stop", exact: true }).click();
});

test("BPM commits normalize inputs even when the committed tempo is unchanged", async ({ page }) => {
  await page.goto("/");
  const bpm = page.locator("#global-bpm");
  await bpm.fill("1");
  await bpm.press("Enter");
  await expect(bpm).toHaveValue("1");

  await bpm.fill("0");
  await bpm.press("Enter");
  await expect(bpm).toHaveValue("1");

  await bpm.fill("0");
  await bpm.press("Tab");
  await expect(bpm).toHaveValue("1");

  await bpm.fill("");
  await bpm.press("Enter");
  await expect(bpm).toHaveValue("1");
});

test("song acceptance reports runtime tempo below the manual input minimum", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("button", { name: "Song", exact: true }).click();
  await page.locator(".cm-content").fill('song(bpm(0.5),section("a",1,note("60")),part("a","a"))');
  await page.getByRole("button", { name: "Play", exact: true }).click();
  await expect(page.locator("#log")).toContainText("song updated");
  await expect(page.locator("#global-bpm")).toHaveValue("0.5");
  await page.getByRole("button", { name: "Stop", exact: true }).click();
});

test("malformed worklet acceptance fails visibly instead of disappearing", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("button", { name: "Play", exact: true }).click();
  await expect(page.locator("#log")).toContainText("pattern updated");
  await page.evaluate(() => {
    window.__moondspEngine?._testInjectReply({ type: "pattern-updated", revision: 1 });
  });
  await expect(page.getByRole("button", { name: "Retry", exact: true })).toBeEnabled();
  await expect(page.locator("#status")).toContainText("error:");
  await page.getByRole("button", { name: "Retry", exact: true }).click();
  await expect(page.locator("#log")).toContainText("pattern updated");
  await page.getByRole("button", { name: "Stop", exact: true }).click();
});

test("contextually rejected tempo restores runtime BPM while playback continues", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("button", { name: "Song", exact: true }).click();
  await page.locator(".cm-content").fill(
    'song(bpm(0.001),section("a",1,note("60").fast(10000019).fast(100000003).slow(100000000)),part("r","a"))',
  );
  await page.getByRole("button", { name: "Play", exact: true }).click();
  await expect(page.locator("#log")).toContainText("song updated");
  const bpm = page.locator("#global-bpm");
  await bpm.fill("1000");
  await bpm.press("Enter");
  await expect(bpm).toHaveValue("0.001");
  await expect(page.locator("#log")).toHaveClass(/error/);
  await expect(page.locator("#status")).toContainText("running");
  await page.getByRole("button", { name: "Stop", exact: true }).click();
});
