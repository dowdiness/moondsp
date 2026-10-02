import { expect, test } from "@playwright/test";
import { readCode, replaceCode } from "./editor-helpers";

declare global {
  interface Window {
    releaseFile?: () => void;
  }
}

const imported = '// 日本語のスケッチ\nbpm(84);\nnote("C4 Eb4 G4").gain(0.2)';

test("pattern edits preserve multiline source and undo; nested syntax stays in code", async ({ page }) => {
  await page.goto("/");
  const source = '// 日本語\nlet melody = note("C4 ~\nG4 Eb4").gain(0.2);\nmelody';
  await replaceCode(page, source);
  const editor = page.locator(".cm-content");
  await editor.press("Control+Home");
  await editor.press("ArrowDown");
  const pitch = page.getByRole("button", { name: "Set D4", exact: true });
  await page.locator(".step-pad").first().focus();
  await pitch.click();
  await expect.poll(() => readCode(page)).toBe(source.replace("C4", "D4"));
  await expect(pitch).toBeFocused();
  await pitch.press("Control+z");
  await expect.poll(() => readCode(page)).toBe(source);
  await replaceCode(page, 'note("[C4 E4] G4")');
  await expect(page.locator(".step-pad")).toHaveCount(0);
  expect(await readCode(page)).toBe('note("[C4 E4] G4")');
});

test("code cursor selects the note that pitch controls change, including the lowest octave", async ({ page }) => {
  await page.goto("/");
  await replaceCode(page, 'note("C4 E4 G4")');
  const editor = page.locator(".cm-content");
  await editor.press("Home");
  for (let index = 0; index < 9; index++) await editor.press("ArrowRight");
  await page.getByRole("button", { name: "Set F4", exact: true }).click();
  await expect.poll(() => readCode(page)).toBe('note("C4 F4 G4")');
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe('note("C4 E4 G4")');
  await replaceCode(page, 'note("C0")');
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
  await expect(page.locator(".step-rest")).toHaveAttribute("aria-pressed", "true");
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(source.replace("G4", "F#4"));
  // The restored note must not retain the rest's preview announcement.
  await expect(page.locator(".step-feedback")).toBeEmpty();
  await page.locator(".step-pad").nth(2).focus();
  await expect(page.getByRole("button", { name: "Set G#9", exact: true })).toBeDisabled();
  await page.getByRole("button", { name: "Set F#9", exact: true }).click();
  await expect.poll(() => readCode(page)).toBe(source.replace("G4", "F#4").replace("127", "126"));
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(source.replace("G4", "F#4"));
});

test("rest remains keyboard accessible beside octave controls and within drum choices with shared history", async ({ page }) => {
  await page.goto("/");
  for (const { source, atom, groupSelector } of [
    { source: 'note("C4 E4")', atom: "C4", groupSelector: ".pitch-keyboard" },
    { source: 's("bd sd")', atom: "bd", groupSelector: ".drum-choices" },
  ]) {
    await replaceCode(page, source);
    const group = page.locator(groupSelector);
    await group.locator("button").first().focus();
    await page.keyboard.press(groupSelector === ".pitch-keyboard" ? "Shift+Tab" : "End");
    const rest = page.locator(".score-pattern").getByRole("button", { name: "Rest", exact: true });
    await expect(rest).toBeFocused();
    expect(await readCode(page)).toBe(source);
    await rest.press("Space");
    await expect.poll(() => readCode(page)).toBe(source.replace(atom, "~"));
    await expect(rest).toHaveAttribute("aria-pressed", "true");
    await expect(group.locator("button[aria-pressed='true']")).toHaveCount(groupSelector === ".pitch-keyboard" ? 0 : 1);
    await rest.press(groupSelector === ".pitch-keyboard" ? "Tab" : "Home");
    await expect(group.locator("button").first()).toBeFocused();
    await page.keyboard.press("Space");
    await expect.poll(() => readCode(page)).toBe(source);
    await expect(rest).toHaveAttribute("aria-pressed", "false");
    await page.locator("#undo").click();
    await expect.poll(() => readCode(page)).toBe(source.replace(atom, "~"));
    await page.locator("#undo").click();
    await expect.poll(() => readCode(page)).toBe(source);
  }
});

test("listening is bounded, does not start the score, and survives change–undo–listen", async ({ page }) => {
  await page.goto("/");
  const source = 'note("G4 E4").gain(0.2)';
  await replaceCode(page, source);
  const controls = page.locator(".score-pattern");
  await page.locator(".step-pad").first().click();
  await expect(controls).toHaveAttribute("data-preview", "playing");
  expect(await readCode(page)).toBe(source);
  await expect(page.locator("#status")).toHaveText("Ready");
  await expect(controls).toHaveAttribute("data-preview", "idle");
  await page.getByRole("button", { name: "Set G#4", exact: true }).click();
  await expect.poll(() => readCode(page)).toBe(source.replace("G4", "G#4"));
  await expect(controls).toHaveAttribute("data-preview", "playing");
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(source);
  await page.locator(".step-pad").first().click();
  await expect(controls).toHaveAttribute("data-preview", "playing");
  await page.locator("#start").click();
  await expect(controls).toHaveAttribute("data-preview", "idle");
  await expect(page.locator("#status")).toHaveText("Playing");
  await expect.poll(async () => Number(await page.locator("#status").getAttribute("data-cycle-position"))).toBeGreaterThan(0);
  await page.getByRole("button", { name: "Set G#4", exact: true }).click();
  await expect.poll(() => readCode(page)).toBe(source.replace("G4", "G#4"));
  await expect(controls).toHaveAttribute("data-preview", "idle");
  await page.locator("#start").click();
  await expect(page.locator("#status")).toHaveText("Paused");
  const pausedPosition = await page.locator("#status").getAttribute("data-cycle-position");
  await page.locator(".step-pad").first().click();
  await expect(controls).toHaveAttribute("data-preview", "playing");
  await page.locator("#source-toggle").click();
  await expect(page.locator(".score-pattern")).toHaveCount(0);
  await expect(page.locator("#status")).toHaveText("Paused");
  await expect(page.locator("#status")).toHaveAttribute("data-cycle-position", pausedPosition!);
});

test("mobile Help contains keyboard focus, closes on Escape and yields to a chosen score", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/");
  const original = await readCode(page);
  const trigger = page.getByRole("button", { name: "Show help", exact: true });
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
