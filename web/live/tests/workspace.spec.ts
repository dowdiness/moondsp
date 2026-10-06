import { expect, test } from "@playwright/test";
import { openPitchControls, readCode, replaceCode } from "./editor-helpers";

declare global {
  interface Window {
    releaseFile?: () => void;
  }
}

const imported = '// 日本語のスケッチ\nbpm(84);\nnote("C4 Eb4 G4").gain(0.2)';

test("pattern edits preserve multiline and nested source through shared Undo", async ({ page }) => {
  await page.goto("/");
  const source = '// 日本語\nlet melody = note("C4 ~\nG4 Eb4").gain(0.2);\nmelody';
  await replaceCode(page, source);
  const editor = page.locator(".cm-content");
  await editor.press("Control+Home");
  await editor.press("ArrowDown");
  await openPitchControls(page);
  const pitch = page.getByRole("button", { name: "Set D4", exact: true });
  await page.locator(".step-pad").first().focus();
  await pitch.click();
  await expect.poll(() => readCode(page)).toBe(source.replace("C4", "D4"));
  await expect(pitch).toBeFocused();
  await pitch.press("Control+z");
  await expect.poll(() => readCode(page)).toBe(source);
  await replaceCode(page, 'note("[C4 E4] G4")');
  await page.locator(".moving-score__note-block").first().click();
  await openPitchControls(page);
  await page.getByRole("button", { name: "Set D4", exact: true }).click();
  await expect.poll(() => readCode(page)).toBe('note("[D4 E4] G4")');
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe('note("[C4 E4] G4")');
});

test("code cursor selects the note that pitch controls change, including the lowest octave", async ({ page }) => {
  await page.goto("/");
  await replaceCode(page, 'note("C4 E4 G4")');
  const editor = page.locator(".cm-content");
  await editor.press("Home");
  for (let index = 0; index < 9; index++) await editor.press("ArrowRight");
  await openPitchControls(page);
  await page.getByRole("button", { name: "Set F4", exact: true }).click();
  await expect.poll(() => readCode(page)).toBe('note("C4 F4 G4")');
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe('note("C4 E4 G4")');
  await replaceCode(page, 'note("C0")');
  await openPitchControls(page);
  await page.locator(".step-pad").press("Shift+ArrowDown");
  await expect.poll(() => readCode(page)).toBe('note("C-1")');
  await expect(page.locator(".octave-down")).toBeDisabled();
  await expect(page.getByRole("button", { name: "Set C#-1", exact: true })).toBeEnabled();
  await page.locator(".step-pad").press("Control+z");
  await expect.poll(() => readCode(page)).toBe('note("C0")');
});

test("pitch key navigation and history preserve the source selection on return to typing", async ({ page }) => {
  await page.goto("/");
  const source = 'note("C4 E4 G4").gain(0.2)';
  await replaceCode(page, source);
  const editor = page.locator(".cm-content");
  await editor.press("Home");
  for (let index = 0; index < 9; index++) await editor.press("ArrowRight");
  await editor.press("Shift+ArrowRight");
  await editor.press("Shift+ArrowRight");
  await openPitchControls(page);
  await page.locator(".step-pad").first().focus();
  await page.getByRole("button", { name: "Set C4", exact: true }).focus();
  await page.keyboard.press("ArrowRight");
  const pitch = page.getByRole("button", { name: "Set C#4", exact: true });
  await expect(pitch).toBeFocused();
  expect(await readCode(page)).toBe(source);
  await pitch.press("Space");
  const changed = 'note("C#4 E4 G4").gain(0.2)';
  await expect.poll(() => readCode(page)).toBe(changed);
  await expect(pitch).toBeFocused();
  await pitch.press("Control+z");
  await expect.poll(() => readCode(page)).toBe(source);
  await pitch.press("Control+Shift+Z");
  await expect.poll(() => readCode(page)).toBe(changed);
  await pitch.press("Escape");
  await expect(editor).toBeFocused();
  expect(await page.evaluate(() => window.getSelection()?.toString())).toBe("E4");
  await page.keyboard.insertText("F4");
  await expect.poll(() => readCode(page)).toBe('note("C#4 F4 G4").gain(0.2)');
  await editor.press("Control+z");
  await expect.poll(() => readCode(page)).toBe(changed);
});

test("keyboard and pointer switching keeps one Tab stop and accidental keys reachable", async ({ page }) => {
  await page.goto("/");
  const source = 'note("C4").gain(0.2)';
  await replaceCode(page, source);
  await openPitchControls(page);
  const natural = page.getByRole("button", { name: "Set C4", exact: true });
  const sharp = page.getByRole("button", { name: "Set C#4", exact: true });
  await natural.focus();
  await natural.press("ArrowRight");
  await expect(sharp).toBeFocused();
  await natural.click();
  await natural.press("Tab");
  expect(await page.locator(".pitch-keyboard").evaluate(element => element.contains(document.activeElement))).toBe(false);
  expect(await readCode(page)).toBe(source);
  await natural.focus();
  await natural.press("ArrowRight");
  await sharp.press("ArrowLeft");
  await expect(natural).toBeFocused();
  const box = (await sharp.boundingBox())!;
  // Click the visible part that overlaps the focused natural key, not its centre.
  await sharp.click({ position: { x: box.width * 0.2, y: box.height / 2 } });
  await expect.poll(() => readCode(page)).toBe('note("C#4").gain(0.2)');
});

test("choosing a pitch and activating a step return to the selected source without consuming text keys", async ({ page }) => {
  await page.goto("/");
  await replaceCode(page, 'note("C4 E4 G4")');
  const editor = page.locator(".cm-content");
  await editor.press("Home");
  for (let index = 0; index < 6; index++) await editor.press("ArrowRight");
  await editor.press("Shift+ArrowRight");
  await editor.press("Shift+ArrowRight");
  await openPitchControls(page);
  await page.locator(".step-pad").nth(1).focus();
  const pitch = page.getByRole("button", { name: "Set F#4", exact: true });
  await pitch.click();
  await pitch.press("Escape");
  await expect(editor).toBeFocused();
  expect(await page.evaluate(() => window.getSelection()?.toString())).toBe("C4");
  await page.keyboard.insertText("D4");
  await expect.poll(() => readCode(page)).toBe('note("D4 F#4 G4")');
  const step = page.locator(".step-pad").first();
  await step.focus();
  await step.press("Space");
  await expect.poll(() => readCode(page)).toBe('note("D4 F#4 G4")');
  await step.press("Control+z");
  await expect.poll(() => readCode(page)).toBe('note("C4 F#4 G4")');
  await step.press("Control+Shift+Z");
  await expect.poll(() => readCode(page)).toBe('note("D4 F#4 G4")');
  await step.press("Escape");
  await expect(editor).toBeFocused();
  await editor.press("ArrowRight");
  await page.keyboard.insertText(" ");
  await expect.poll(() => readCode(page)).toBe('note("D4  F#4 G4")');
});

test("pattern controls retain play, pause and restart shortcuts without editing the score", async ({ page }) => {
  await page.goto("/");
  const source = 'note("C4").gain(0.2)';
  await replaceCode(page, source);
  await openPitchControls(page);
  const pitch = page.getByRole("button", { name: "Set C4", exact: true });
  await pitch.focus();
  await pitch.press("Control+Enter");
  await expect(page.locator("#status")).toHaveText("Playing");
  await expect(pitch).toBeFocused();
  await pitch.press("Control+Enter");
  await expect(page.locator("#status")).toHaveText("Paused");
  const step = page.locator(".step-pad");
  await step.focus();
  await step.press("Control+Shift+Enter");
  await expect(page.locator("#status")).toHaveText("Playing");
  await expect(step).toBeFocused();
  expect(await readCode(page)).toBe(source);
  await step.press("Control+Enter");
  await expect(page.locator("#status")).toHaveText("Paused");
  await step.press("Escape");
  await expect(page.locator(".cm-content")).toBeFocused();
});

test("musical adjustments and rest replacement share exact source undo without losing a note", async ({ page }) => {
  await page.goto("/");
  const source = '// 保持\nnote("G4 Eb4 127 ~").gain(0.2)';
  await replaceCode(page, source);
  await openPitchControls(page);
  const pitch = page.locator(".step-pad").first();
  await pitch.focus();
  await page.getByRole("button", { name: "Set F#4", exact: true }).click();
  await expect.poll(() => readCode(page)).toBe(source.replace("G4", "F#4"));
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(source);
  await page.locator("#redo").click();
  await expect.poll(() => readCode(page)).toBe(source.replace("G4", "F#4"));
  await page.locator(".step-rest").click();
  await expect.poll(() => readCode(page)).toBe(source.replace("G4", "~"));
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(source.replace("G4", "F#4"));
  await page.locator(".step-pad").nth(2).focus();
  await expect(page.getByRole("button", { name: "Set G#9", exact: true })).toBeDisabled();
  await page.getByRole("button", { name: "Set F#9", exact: true }).click();
  await expect.poll(() => readCode(page)).toBe(source.replace("G4", "F#4").replace("127", "126"));
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(source.replace("G4", "F#4"));
});


test("numbered note buttons select without listening or starting the score", async ({ page }) => {
  await page.goto("/");
  const source = 'note("G4 E4").gain(0.2)';
  await replaceCode(page, source);
  await openPitchControls(page);
  const select = page.getByRole("button", { name: "Select G4, Melody, step 1", exact: true });
  await select.click();
  await expect(select).toHaveAttribute("aria-pressed", "true");
  expect(await readCode(page)).toBe(source);
  await expect(page.locator("#status")).toHaveText("Ready");
  await page.getByRole("button", { name: "Set G#4", exact: true }).click();
  await expect.poll(() => readCode(page)).toBe(source.replace("G4", "G#4"));
  await expect(page.locator("#status")).toHaveText("Ready");
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(source);
  await expect(page.locator("#status")).toHaveText("Ready");
});

test("mobile Help contains keyboard focus, closes on Escape and yields to a chosen score", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/");
  const original = await readCode(page);
  const trigger = page.getByRole("button", { name: "Help", exact: true });
  const help = page.getByRole("dialog", { name: "Help & sounds" });
  await trigger.click();
  await expect(page.getByRole("button", { name: "Close help", exact: true })).toBeFocused();
  await page.keyboard.press("Shift+Tab");
  expect(await help.evaluate(element => element.contains(document.activeElement))).toBe(true);
  await page.keyboard.press("Escape");
  await expect(help).not.toBeVisible();
  await expect(trigger).toBeFocused();
  await trigger.click();
  await page.locator('[data-starter="slow-drift"]').click();
  await expect(help).not.toBeVisible();
  await expect(page.locator(".cm-content")).toBeFocused();
  expect(await readCode(page)).toContain("bpm(72)");
  await page.locator("#undo").click();
  expect(await readCode(page)).toBe(original);
  await trigger.click();
  await page.setViewportSize({ width: 1440, height: 1000 });
  await expect(help).toBeVisible();
  // Resizing an open modal to a sidebar must release the editor, not leave it inert.
  await replaceCode(page, 'note("D4")');
  expect(await readCode(page)).toBe('note("D4")');
});

test("UTF-8 import is undoable, downloads exact text, and survives reload", async ({ page }) => {
  await page.goto("/");
  const original = await readCode(page);
  const chooserReady = page.waitForEvent("filechooser");
  await page.locator("#open-score").click();
  await (await chooserReady).setFiles({ name: "sketch.mini", mimeType: "text/plain", buffer: Buffer.from(imported) });
  await expect.poll(() => readCode(page)).toBe(imported);
  await page.locator("#undo").click();
  expect(await readCode(page)).toBe(original);
  await page.locator("#redo").click();
  await expect.poll(() => page.evaluate(() => localStorage.getItem("moondsp.live.score.v1"))).toBe(imported);
  await page.reload();
  await expect.poll(() => readCode(page)).toBe(imported);
  const downloadReady = page.waitForEvent("download");
  await page.locator("#save-score").click();
  const stream = await (await downloadReady).createReadStream();
  const chunks: Buffer[] = [];
  for await (const chunk of stream!) chunks.push(Buffer.from(chunk));
  expect(Buffer.concat(chunks).toString("utf8")).toBe(imported);
  await replaceCode(page, "");
  await expect.poll(() => page.evaluate(() => localStorage.getItem("moondsp.live.score.v1"))).toBe("");
  await page.reload();
  await expect.poll(() => readCode(page)).toBe("");
});

test("an untouched stale tab cannot overwrite a newer saved score on exit", async ({ page, context }) => {
  await page.goto("/");
  await replaceCode(page, 'note("C4")');
  await expect(page.locator("#save-status")).toHaveText("Saved locally");
  const stale = await context.newPage();
  await stale.goto("/");
  await expect.poll(() => readCode(stale)).toBe('note("C4")');

  const latest = 'note("G4").gain(0.2)';
  await replaceCode(page, latest);
  await expect(page.locator("#save-status")).toHaveText("Saved locally");
  await page.goto("about:blank");
  await stale.goto("about:blank");
  await page.goto("/");
  await expect.poll(() => readCode(page)).toBe(latest);
  await stale.close();
});

test("conflicting tab edits remain downloadable without replacing the newer saved score", async ({ page, context }) => {
  await page.goto("/");
  await replaceCode(page, 'note("C4")');
  await expect(page.locator("#save-status")).toHaveText("Saved locally");
  const stale = await context.newPage();
  await stale.goto("/");
  await expect.poll(() => readCode(stale)).toBe('note("C4")');

  const latest = 'note("G4").gain(0.2)';
  await replaceCode(page, latest);
  await expect(page.locator("#save-status")).toHaveText("Saved locally");
  await replaceCode(stale, imported);
  await expect(stale.locator("#save-status")).toHaveText("Not saved");
  await expect(stale.locator("#session-message")).toContainText("another tab");
  expect(await readCode(stale)).toBe(imported);
  const downloadReady = stale.waitForEvent("download");
  await stale.locator("#save-score").click();
  const stream = await (await downloadReady).createReadStream();
  const chunks: Buffer[] = [];
  for await (const chunk of stream!) chunks.push(Buffer.from(chunk));
  expect(Buffer.concat(chunks).toString("utf8")).toBe(imported);
  await page.goto("about:blank");
  await stale.goto("about:blank");
  await page.goto("/");
  await expect.poll(() => readCode(page)).toBe(latest);
  await stale.close();
});

test("overlapping tab saves remain recoverable after both tabs leave", async ({ page, context }) => {
  await page.goto("/");
  const original = await readCode(page);
  const other = await context.newPage();
  await other.goto("/");
  await expect.poll(() => readCode(other)).toBe(original);
  // Hold B's storage view at the value both tabs read before either writes.
  // This deterministically exercises the permitted cross-agent read/write race,
  // without depending on two 350 ms timers happening to overlap.
  await other.evaluate(() => {
    const read = Storage.prototype.getItem;
    const base = localStorage.getItem("moondsp.live.score.v1");
    Storage.prototype.getItem = function (key: string) {
      return key === "moondsp.live.score.v1" ? base : read.call(this, key);
    };
  });
  const first = '// first tab\nnote("D4")';
  const second = '// second tab\nnote("G4")';
  await replaceCode(page, first);
  await page.goto("about:blank");
  await replaceCode(other, second);
  await other.goto("about:blank");
  await page.goto("/");
  await expect.poll(() => readCode(page)).toBe(second);
  await page.getByText("Saved drafts", { exact: true }).click();
  const recovery = page.locator(".saved-draft").filter({ hasText: first });
  await recovery.getByRole("button", { name: "Restore", exact: true }).click();
  await expect.poll(() => readCode(page)).toBe(first);
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(second);
  await other.close();
});

test("a failed recovery write preserves the shared score and leaves the edit downloadable", async ({ page }) => {
  await page.goto("/");
  const original = await readCode(page);
  await page.evaluate(() => {
    const write = Storage.prototype.setItem;
    Storage.prototype.setItem = function (key: string, value: string) {
      if (key.startsWith("moondsp.live.draft.v1.")) throw new DOMException("Full", "QuotaExceededError");
      write.call(this, key, value);
    };
  });
  await replaceCode(page, imported);
  await expect(page.locator("#save-status")).toHaveText("Not saved");
  const downloadReady = page.waitForEvent("download");
  await page.locator("#save-score").click();
  const stream = await (await downloadReady).createReadStream();
  const chunks: Buffer[] = [];
  for await (const chunk of stream!) chunks.push(Buffer.from(chunk));
  expect(Buffer.concat(chunks).toString("utf8")).toBe(imported);
  await page.reload();
  await expect.poll(() => readCode(page)).toBe(original);
});

test("deleting an older displayed draft cannot delete a newer checkpoint from that tab", async ({ page, context }) => {
  await page.goto("/");
  const first = 'note("D4")';
  const latest = '// 保持\nnote("F4")';
  await replaceCode(page, first);
  await expect(page.locator("#save-status")).toHaveText("Saved locally");
  const other = await context.newPage();
  await other.goto("/");
  await other.getByText("Saved drafts", { exact: true }).click();
  const oldDraft = other.locator(".saved-draft").filter({ hasText: first });
  await oldDraft.getByRole("button", { name: "Restore", exact: true }).focus();
  await replaceCode(page, latest);
  await expect(page.locator("#save-status")).toHaveText("Saved locally");
  await expect(oldDraft.getByRole("button", { name: "Restore", exact: true })).toBeFocused();
  other.once("dialog", dialog => dialog.accept());
  await oldDraft.getByRole("button", { name: "Delete saved draft", exact: true }).click();
  await page.goto("about:blank");
  await replaceCode(other, 'note("A4")');
  await other.locator(".saved-draft").filter({ hasText: latest })
    .getByRole("button", { name: "Restore", exact: true }).click();
  await expect.poll(() => readCode(other)).toBe(latest);
  await other.close();
});

test("an asynchronous import never overwrites newer typing", async ({ page }) => {
  await page.addInitScript(() => {
    const read = File.prototype.text;
    File.prototype.text = async function () {
      const source = await read.call(this);
      await new Promise<void>(resolve => { window.releaseFile = resolve; });
      return source;
    };
  });
  await page.goto("/");
  const chooserReady = page.waitForEvent("filechooser");
  await page.locator("#open-score").click();
  await (await chooserReady).setFiles({ name: "sketch.mini", mimeType: "text/plain", buffer: Buffer.from(imported) });
  await page.waitForFunction(() => typeof window.releaseFile === "function");
  await replaceCode(page, 'note("D4")');
  await page.evaluate(() => window.releaseFile?.());
  await expect(page.locator("#session-message")).toContainText("text changed");
  expect(await readCode(page)).toBe('note("D4")');
});

test("denied local storage leaves edits and file export usable", async ({ page }) => {
  await page.addInitScript(() => {
    Storage.prototype.setItem = () => { throw new DOMException("Denied", "SecurityError"); };
  });
  await page.goto("/");
  await expect(page.locator("#session-message")).toContainText("Local storage is unavailable");
  await replaceCode(page, imported);
  const downloadReady = page.waitForEvent("download");
  await page.locator("#save-score").click();
  const stream = await (await downloadReady).createReadStream();
  const chunks: Buffer[] = [];
  for await (const chunk of stream!) chunks.push(Buffer.from(chunk));
  expect(Buffer.concat(chunks).toString("utf8")).toBe(imported);
  expect(await readCode(page)).toBe(imported);
});

for (const phrase of [
  { kind: "note", source: 'note("D4 ~@2*2 G4").slow(2)', value: "D4", action: "Add note" },
  { kind: "chord", source: 'chord("Dm ~@2 C").gate(.4)', value: "Dm", action: "Add chord" },
]) {
  test(`a selected ${phrase.kind} rest can take its neighboring sound without losing timing or history`, async ({ page }) => {
    await page.goto("/");
    await replaceCode(page, phrase.source);
    if (phrase.kind === "note") await openPitchControls(page);
    await page.locator(".step-pad").nth(1).click();
    await page.getByRole("button", { name: phrase.action, exact: true }).click();
    await expect.poll(() => readCode(page)).toBe(phrase.source.replace("~", phrase.value));
    await expect(page.locator("#status")).toHaveText("Ready");
    await page.locator("#undo").click();
    await expect.poll(() => readCode(page)).toBe(phrase.source);
    await page.locator("#redo").click();
    await expect.poll(() => readCode(page)).toBe(phrase.source.replace("~", phrase.value));
  });
}
