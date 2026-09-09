import { test, expect, type Page } from "@playwright/test";

async function replaceText(page: Page, text: string) {
  await page.locator(".cm-content").fill(text);
}

async function lastReply(page: Page) {
  return page.evaluate(() => (window as any).__liveReplies.at(-1));
}

// Waiting for a new revision prevents the previous edit's reply from passing
// the next assertion while its debounced evaluation is still pending.
async function edit(page: Page, text: string) {
  const previous = (await lastReply(page)).revision;
  await replaceText(page, text);
  await expect.poll(async () => (await lastReply(page)).revision).toBeGreaterThan(previous);
  return lastReply(page);
}

async function play(page: Page) {
  const previous = (await lastReply(page))?.revision ?? 0;
  await page.getByRole("button", { name: "Play", exact: true }).click();
  await expect.poll(async () => (await lastReply(page))?.revision ?? 0).toBeGreaterThan(previous);
  return lastReply(page);
}

async function start(page: Page, text: string) {
  await replaceText(page, text);
  const reply = await play(page);
  expect(reply).toMatchObject({ operation: "restart", appliedAtSample: 0 });
  return reply;
}

async function expectStopped(page: Page) {
  await expect(page.getByRole("button", { name: "Play", exact: true })).toBeEnabled();
  expect(await page.evaluate(() => (window as any).__audioContext.state)).toBe("suspended");
}

async function stop(page: Page) {
  await page.getByRole("button", { name: "Stop", exact: true }).click();
  await expectStopped(page);
}

test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    (window as any).__liveReplies = [];
    const Original = window.AudioWorkletNode;
    window.AudioWorkletNode = class extends Original {
      constructor(context: BaseAudioContext, name: string, options?: AudioWorkletNodeOptions) {
        super(context, name, options);
        (window as any).__audioContext = context;
        this.port.addEventListener("message", ({ data }) => {
          if (/^((pattern|song)-(updated|error)|playback-(restarted|error))$/.test(data.type)) {
            (window as any).__liveReplies.push(data);
          }
        });
        this.port.start();
      }
    };
  });
  await page.goto("/");
});

test("editing and recovering from a parse error preserve transport", async ({ page }) => {
  await start(page, 'note("60").slow(8)');
  const updated = await edit(page, 'note("72").slow(8)');
  expect(updated).toMatchObject({ type: "pattern-updated", operation: "update" });
  expect(updated.appliedAtSample).toBeGreaterThan(0);
  expect(await edit(page, 'note(')).toMatchObject({ type: "pattern-error" });
  const recovered = await edit(page, 'note("67").slow(8)');
  expect(recovered).toMatchObject({ type: "pattern-updated", operation: "update" });
  expect(recovered.appliedAtSample).toBeGreaterThan(updated.appliedAtSample);
});

test("song content edits continue, and Stop then Play applies a new layout", async ({ page }) => {
  await page.locator("#mode-song").click();
  await start(page, 'song(section("a",8,note("60")),part("a1","a"))');
  const updated = await edit(page, 'song(section("a",8,note("72")),part("a1","a"))');
  expect(updated).toMatchObject({ type: "song-updated", operation: "update" });
  expect(updated.appliedAtSample).toBeGreaterThan(0);
  const rejected = await edit(page, 'song(section("a",9,note("72")),part("a1","a"))');
  expect(rejected).toMatchObject({ type: "song-error" });
  expect(rejected.message).toContain("restart required");
  await expect(page.locator("#log")).toContainText("Press Stop, then Play");
  await stop(page);
  expect(await play(page)).toMatchObject({
    type: "song-updated", operation: "restart", appliedAtSample: 0,
  });
});

test("editing song tempo continues playback without requiring Stop", async ({ page }) => {
  await page.locator("#mode-song").click();
  await start(page, 'song(bpm(120),section("a",8,note("60").slow(8)),part("a1","a"))');
  const updated = await edit(page, 'song(bpm(90.125),section("a",8,note("60").slow(8)),part("a1","a"))');
  expect(updated).toMatchObject({ type: "song-updated", operation: "update" });
  expect(updated.appliedAtSample).toBeGreaterThan(0);
  await expect(page.getByRole("button", { name: "Stop", exact: true })).toBeEnabled();
});

test("named song definitions update in place and a bad reference preserves the applied score", async ({ page }) => {
  await page.locator("#mode-song").click();
  const song = 'song(section("a",8,groove),section("b",8,groove),part("a1","a"),part("b1","b"))';
  const source = (note: string) => `let melody = note("${note}"); let groove = stack(melody,s("bd")); ${song}`;
  await start(page, source("60"));
  const updated = await edit(page, source("72"));
  expect(updated).toMatchObject({ type: "song-updated", operation: "update" });
  expect(updated.appliedAtSample).toBeGreaterThan(0);
  const error = await edit(page, 'let groove = missing; ' + song);
  expect(error).toMatchObject({ type: "song-error", phase: "prepare" });
  expect(error.message).toContain("undefined pattern 'missing'");
  const recovered = await edit(page, source("67"));
  expect(recovered).toMatchObject({ type: "song-updated", operation: "update" });
  expect(recovered.appliedAtSample).toBeGreaterThan(updated.appliedAtSample);
});

test("failed first Play stays stopped and explains how to retry", async ({ page }) => {
  await replaceText(page, "note(");
  expect(await play(page)).toMatchObject({ type: "pattern-error" });
  await expectStopped(page);
  await expect(page.locator("#log")).toContainText("Fix the code, then press Play");
});

for (const { mode, valid, invalid } of [
  { mode: "pattern", valid: 'note("60*16")', invalid: "note(" },
  { mode: "song", valid: 'song(section("a",8,note("60*16")),part("a1","a"))', invalid: "song(" },
]) {
  test.describe(mode, () => {
    test.beforeEach(async ({ page }) => {
      await page.locator(`#mode-${mode}`).click();
      await start(page, valid);
      await stop(page);
    });

    test("failed Play keeps the previous score stopped; a valid retry starts at zero", async ({ page }) => {
      await replaceText(page, invalid);
      expect(await play(page)).toMatchObject({ type: `${mode}-error` });
      await expectStopped(page);
      await start(page, valid);
    });

    test("empty Play keeps the previous score stopped", async ({ page }) => {
      await replaceText(page, "");
      await page.getByRole("button", { name: "Play", exact: true }).click();
      await expect(page.locator("#log")).toContainText("Enter code, then press Play");
      await expectStopped(page);
    });
  });
}
