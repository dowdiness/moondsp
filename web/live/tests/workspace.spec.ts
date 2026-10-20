import { expect, test } from "@playwright/test";
import { platformKeys, boxOf, leave, openPitchControls, readCode, replaceCode, insertText } from "./editor-helpers";
import { encodeScoreLink } from "../src/score-link";

declare global {
  interface Window {
    releaseFile?: () => void;
  }
}

const imported = '// 日本語のスケッチ\nbpm(84);\nnote("C4 Eb4 G4").gain(0.2)';

test("pattern edits preserve multiline and nested source through shared Undo", async ({ page }) => {
  await page.goto("/");
  const { mod } = await platformKeys(page);
  const source = '// 日本語\nlet melody = note("C4 ~\nG4 Eb4").gain(0.2);\nmelody';
  await replaceCode(page, source);
  const editor = page.locator(".cm-content");
  await editor.press(`${mod}+Home`);
  await editor.press("ArrowDown");
  await openPitchControls(page);
  const pitch = page.getByRole("button", { name: "Set D4", exact: true });
  await page.locator(".step-pad").first().focus();
  await pitch.click();
  await expect.poll(() => readCode(page)).toBe(source.replace("C4", "D4"));
  await expect(pitch).toBeFocused();
  await pitch.press(`${mod}+z`);
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
  const { mod } = await platformKeys(page);
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
  await page.locator(".step-pad").press(`${mod}+z`);
  await expect.poll(() => readCode(page)).toBe('note("C0")');
});

test("pitch key navigation and history preserve the source selection on return to typing", async ({ page }) => {
  await page.goto("/");
  const { mod } = await platformKeys(page);
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
  await pitch.press(`${mod}+z`);
  await expect.poll(() => readCode(page)).toBe(source);
  await pitch.press(`${mod}+Shift+Z`);
  await expect.poll(() => readCode(page)).toBe(changed);
  await pitch.press("Escape");
  await expect(editor).toBeFocused();
  expect(await page.evaluate(() => window.getSelection()?.toString())).toBe("E4");
  await insertText(page, "F4");
  await expect.poll(() => readCode(page)).toBe('note("C#4 F4 G4").gain(0.2)');
  await editor.press(`${mod}+z`);
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
  // The keyboard is one Tab stop: only the chosen key is in the tab order, and
  // Shift+Tab leaves the keyboard instead of visiting another key. (The keyboard
  // can be the page's last stop, where forward Tab is the browser's to define.)
  expect(await page.locator(".pitch-keyboard button").evaluateAll(keys =>
    keys.filter(key => (key as HTMLElement).tabIndex === 0).map(key => key.getAttribute("aria-label")))).toEqual(["Set C4"]);
  await natural.press("Shift+Tab");
  expect(await page.locator(".pitch-keyboard").evaluate(element => element.contains(document.activeElement))).toBe(false);
  expect(await readCode(page)).toBe(source);
  await natural.focus();
  await natural.press("ArrowRight");
  await sharp.press("ArrowLeft");
  await expect(natural).toBeFocused();
  const box = await boxOf(sharp);
  // Click the visible part that overlaps the focused natural key, not its centre.
  await sharp.click({ position: { x: box.width * 0.2, y: box.height / 2 } });
  await expect.poll(() => readCode(page)).toBe('note("C#4").gain(0.2)');
});

test("choosing a pitch and activating a step return to the selected source without consuming text keys", async ({ page }) => {
  await page.goto("/");
  const { mod } = await platformKeys(page);
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
  await insertText(page, "D4");
  await expect.poll(() => readCode(page)).toBe('note("D4 F#4 G4")');
  const step = page.locator(".step-pad").first();
  await step.focus();
  await step.press("Space");
  await expect.poll(() => readCode(page)).toBe('note("D4 F#4 G4")');
  await step.press(`${mod}+z`);
  await expect.poll(() => readCode(page)).toBe('note("C4 F#4 G4")');
  await step.press(`${mod}+Shift+Z`);
  await expect.poll(() => readCode(page)).toBe('note("D4 F#4 G4")');
  await step.press("Escape");
  await expect(editor).toBeFocused();
  await editor.press("ArrowRight");
  await insertText(page, " ");
  await expect.poll(() => readCode(page)).toBe('note("D4  F#4 G4")');
});

test("pattern controls retain play, pause and restart shortcuts without editing the score", async ({ page }) => {
  await page.goto("/");
  const { mod } = await platformKeys(page);
  const source = 'note("C4").gain(0.2)';
  await replaceCode(page, source);
  await openPitchControls(page);
  const pitch = page.getByRole("button", { name: "Set C4", exact: true });
  await pitch.focus();
  await pitch.press(`${mod}+Enter`);
  await expect(page.locator("#status")).toHaveText("Playing");
  await expect(pitch).toBeFocused();
  await pitch.press(`${mod}+Enter`);
  await expect(page.locator("#status")).toHaveText("Paused");
  const step = page.locator(".step-pad");
  await step.focus();
  await step.press(`${mod}+Shift+Enter`);
  await expect(page.locator("#status")).toHaveText("Playing");
  await expect(step).toBeFocused();
  expect(await readCode(page)).toBe(source);
  await step.press(`${mod}+Enter`);
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
  await page.getByRole("button", { name: "Explore Slow drift", exact: true }).click();
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

test("every Help example loads its own score without playing", async ({ page }) => {
  // One page walks the whole catalogue, so this test is long by design.
  test.slow();
  await page.goto("/");
  await page.getByRole("button", { name: "Help", exact: true }).click();
  await page.locator("#cheat details").evaluateAll(sections => sections.forEach(section => { (section as HTMLDetailsElement).open = true; }));
  const examples = page.locator("#cheat button.example");
  const loaded = new Set([await readCode(page)]);
  for (let index = 0; index < await examples.count(); index++) {
    await examples.nth(index).click();
    const code = await readCode(page);
    expect(loaded.has(code), await examples.nth(index).innerText()).toBe(false);
    loaded.add(code);
  }
  await expect(page.locator("#status")).toHaveText("Ready");
});

test("a Help scene plays the score it loads", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("button", { name: "Help", exact: true }).click();
  const offbeat = page.getByRole("button", { name: "Explore Offbeat", exact: true });
  await offbeat.click();
  await expect(page.locator("#status")).toHaveText("Playing");
  expect(await readCode(page)).toMatch(/^bpm\(112\);/);
  await expect(offbeat).toHaveAttribute("aria-pressed", "true");
  await expect(page.getByRole("button", { name: "Explore First light", exact: true })).toHaveAttribute("aria-pressed", "false");
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

test("a copied score link reopens the exact UTF-8 text as one undoable replacement", async ({ page, context, browserName }) => {
  // Every engine performs the real clipboard write. Only Chromium lets
  // automation grant clipboard-read, so elsewhere the test opens the link the
  // shared encoder produces; score-link.spec covers that encoder in every engine.
  const readable = browserName === "chromium";
  if (!readable) test.info().annotations.push({ type: "clipboard", description: `${browserName} cannot read the clipboard back under automation` });
  if (readable) await context.grantPermissions(["clipboard-read", "clipboard-write"]);
  await page.goto("/");
  await replaceCode(page, imported);
  await page.locator("#share-score").click();
  await expect(page.locator("#session-message")).toContainText("Link copied");
  const link = readable ? await page.evaluate(() => navigator.clipboard.readText())
    : await encodeScoreLink(imported, new URL("/", page.url()).href);
  expect(link).toMatch(/#score=[A-Za-z0-9_-]+$/);
  if (readable) {
    // Sharing again replaces whatever the clipboard held since.
    await page.evaluate(() => navigator.clipboard.writeText("stale"));
    await page.locator("#share-score").click();
    await expect.poll(() => page.evaluate(() => navigator.clipboard.readText())).toBe(link);
  }

  const other = await context.newPage();
  await other.goto("/");
  await replaceCode(other, 's("bd sd")');
  await other.goto(link);
  await expect.poll(() => readCode(other)).toBe(imported);
  await expect(other.locator("#session-message")).toContainText("Opened a shared score");
  expect(await other.evaluate(() => location.hash)).toBe("");
  await other.locator("#undo").click();
  expect(await readCode(other)).toBe('s("bd sd")');
});

for (const [clipboard, refuse] of [
  ["a refused clipboard write", () => {
    navigator.clipboard.write = () => Promise.reject(new DOMException("Denied", "NotAllowedError"));
  }],
  // Plain-HTTP pages expose neither navigator.clipboard nor ClipboardItem.
  ["a page without the Clipboard API", () => {
    Object.defineProperty(Navigator.prototype, "clipboard", { get: () => undefined });
    Object.defineProperty(window, "ClipboardItem", { value: undefined });
  }],
] as const) {
  test(`${clipboard} leaves the score and address unchanged and says so`, async ({ page }) => {
    await page.addInitScript(refuse);
    await page.goto("/");
    await replaceCode(page, 'note("C4 E4")');
    await page.locator("#share-score").click();
    await expect(page.locator("#session-message")).toContainText("Could not copy a link");
    expect(await page.evaluate(() => location.hash)).toBe("");
    expect(await readCode(page)).toBe('note("C4 E4")');
  });
}

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
  await leave(page);
  await leave(stale);
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
  await leave(page);
  await leave(stale);
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
  await leave(page);
  await replaceCode(other, second);
  await leave(other);
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
  await leave(page);
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

test("a long statement breaks by syntax on a narrow screen without changing its source", async ({ page }) => {
  const source = '$: note("C4 ~ Eb4 G4 Bb4 ~ G4 Eb4").slow(4).gain(0.25).lpf(1800)';
  await page.setViewportSize({ width: 320, height: 700 });
  await page.goto("/");
  await replaceCode(page, source);
  // Code columns from the statement start, and rows, of each token's first glyph and
  // of the first knob, and the caret's row.
  const place = (tokens: string[]) => page.locator(".cm-line").first().evaluate((line, tokens) => {
    const glyph = (node: Node, index: number, length = 1) => {
      const range = document.createRange();
      range.setStart(node, index);
      range.setEnd(node, index + length);
      return range.getBoundingClientRect();
    };
    const at = (token: string, length = 1) => {
      const walker = document.createTreeWalker(line, NodeFilter.SHOW_TEXT);
      for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        const index = (node as Text).data.indexOf(token);
        if (index >= 0) return glyph(node, index, length);
      }
      throw new Error(`missing ${token}`);
    };
    // A run of glyphs gives the column width; one glyph's box is not exact in every engine.
    const start = at("$:"), ch = at("$: note", 7).width / 7, pitch = parseFloat(getComputedStyle(line).lineHeight);
    const place = (box: DOMRect) => ({ column: Math.round((box.left - start.left) / ch), row: Math.round((box.top - start.top) / pitch) });
    const knob = line.querySelector(".cm-sound-knob");
    // The caret's row is the number of row breaks before it in the DOM: a row's end and the
    // next row's start are one source position, told apart only by the side of the break.
    const caret = getSelection()!.rangeCount ? getSelection()!.getRangeAt(0) : null;
    return {
      ...Object.fromEntries(tokens.map(token => [token, place(at(token))])),
      knob: knob ? place(knob.getBoundingClientRect()) : null,
      caretRow: caret ? [...line.querySelectorAll(".cm-row-break")].filter(br => caret.comparePoint(br, 0) < 0).length : null,
    };
  }, tokens);
  const narrow = await place(["C4 ~", "slow", "gain", "lpf"]);
  // Arguments (here the phrase, after its quote) sit two columns deeper than the chain,
  // so the chain reads as one level out.
  expect(narrow["C4 ~"].column).toBe(5);
  expect(narrow.slow.column - 1).toBe(2);
  expect(narrow.lpf.column - 1).toBe(2);
  expect(narrow.slow.row).toBeGreaterThan(narrow["C4 ~"].row);
  expect(narrow.gain.row).toBe(narrow.slow.row);
  expect(narrow.lpf.row).toBeGreaterThan(narrow.slow.row);
  expect(await readCode(page)).toBe(source);

  // A row's end and the next row's start are one source position; End and Home keep the caret on its row.
  const click = async (token: string) => {
    const glyph = await page.locator(".cm-line").first().evaluate((line, token) => {
      const walker = document.createTreeWalker(line, NodeFilter.SHOW_TEXT);
      for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        const index = (node as Text).data.indexOf(token);
        if (index < 0) continue;
        const range = document.createRange();
        range.setStart(node, index + 1);
        range.setEnd(node, index + 2);
        const box = range.getBoundingClientRect();
        return { x: box.left + box.width / 2, y: box.top + box.height / 2 };
      }
      throw new Error(`missing ${token}`);
    }, token);
    await page.mouse.click(glyph.x, glyph.y);
  };
  await click("slow");
  // The editor settles the caret's side of the break after the key, so poll.
  await page.keyboard.press("End");
  await expect.poll(async () => (await place([])).caretRow).toBe(narrow.slow.row);
  await page.keyboard.press("Home");
  await expect.poll(async () => (await place([])).caretRow).toBe(narrow.slow.row);
  await expect(page.locator("footer").getByText(/^Ln \d/)).toHaveText(`Ln 1, Col ${source.indexOf(".slow") + 1}`);

  // A knob that starts an argument row is indented with that row.
  await replaceCode(page, '$: note("C4").lpf(1800, 0.7)');
  await page.setViewportSize({ width: 220, height: 700 });
  await expect.poll(async () => (await place([])).knob).toEqual({ column: 4, row: 2 });
  // The row above ends before that knob, not after it.
  await click("lpf");
  await page.keyboard.press("End");
  await expect.poll(async () => (await place([])).caretRow).toBe(1);

  await page.setViewportSize({ width: 1280, height: 800 });
  await expect.poll(async () => (await place([])).knob?.row).toBe(0);
});
