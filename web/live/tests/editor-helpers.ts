import { expect, type Locator, type Page } from "@playwright/test";

// Use the editor's Select All command, not a native DOM range spanning widgets.
export async function replaceCode(page: Page, source: string): Promise<void> {
  const editor = page.locator(".cm-content");
  await editor.focus();
  const { mod } = await platformKeys(page);
  await editor.press(`${mod}+a`);
  await insertText(page, source);
}

/**
 * Types `text` over the focused selection as one edit. This is the editing
 * command browsers run for typed and pasted text, so CodeMirror reads it the
 * same way in every engine. Playwright's keyboard.insertText does not: Firefox
 * delivers it as IME composition, which CodeMirror joins to the previous Undo step.
 */
export async function insertText(page: Page, text: string): Promise<void> {
  // Deleting through the DOM leaves a line break behind in Firefox; the editor's
  // own Backspace command removes the selection the same way everywhere.
  if (text === "") await page.keyboard.press("Backspace");
  else await page.evaluate(text => document.execCommand("insertText", false, text), text);
}

export async function openPitchControls(page: Page): Promise<void> {
  // The phrase controls can render a moment after the code changes.
  const pitchEditor = page.locator(".pattern-pitch-editor");
  await expect(pitchEditor).toBeVisible();
  if (!await pitchEditor.evaluate(element => (element as HTMLDetailsElement).open)) await pitchEditor.locator("> summary").click();
  await expect(pitchEditor).toHaveAttribute("open", "");
}

export async function readCode(page: Page): Promise<string> {
  return page.locator(".cm-line").evaluateAll(lines => lines.map(line => {
    const copy = line.cloneNode(true) as HTMLElement;
    copy.querySelectorAll(".cm-inline-control, .cm-placeholder").forEach(widget => widget.remove());
    return copy.textContent;
  }).join("\n"));
}

/**
 * Leaves the page the way following a link does. In Firefox, Playwright's own
 * page.goto often skips the window's first pagehide listener, which here is
 * the save that runs as a tab closes.
 */
export async function leave(page: Page): Promise<void> {
  await Promise.all([page.waitForURL("about:blank"), page.evaluate(() => location.assign("about:blank"))]);
}

type Box = { x: number; y: number; width: number; height: number };

/**
 * The element's box in viewport coordinates, where the mouse acts. An edit
 * settles over the next frame: CodeMirror measures it, and the note grid
 * redraws when the editor's width changes, replacing the element found before.
 * Like Playwright's own actions, this measures once a frame has passed with the
 * element attached and its box unchanged, and finds it again otherwise.
 */
export async function boxOf(locator: Locator): Promise<Box> {
  let box: Box | null = null;
  await expect.poll(async () => {
    box = await locator.evaluate(element => new Promise<Box | null>(resolve => {
      const before = element.getBoundingClientRect();
      requestAnimationFrame(() => requestAnimationFrame(() => {
        const { x, y, width, height } = element.getBoundingClientRect();
        const same = x === before.x && y === before.y && width === before.width && height === before.height;
        resolve(element.isConnected && same ? { x, y, width, height } : null);
      }));
    }));
    return box !== null;
  }, { message: "the element keeps its box for a frame" }).toBe(true);
  return box!;
}

/** The centre of an element, scrolled into view and measured once it holds still. */
export async function centerOf(locator: Locator): Promise<{ x: number; y: number }> {
  await locator.scrollIntoViewIfNeeded();
  const box = await boxOf(locator);
  return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
}

/**
 * Shortcuts as the page's platform defines them. CodeMirror follows
 * navigator.platform, and Playwright's WebKit always reports a Mac, where
 * shortcuts use Command and redo is Command+Shift+Z.
 */
export async function platformKeys(page: Page): Promise<{ mod: "Meta" | "Control"; redo: string }> {
  const mac = await page.evaluate(() => /Mac/.test(navigator.platform));
  return mac ? { mod: "Meta", redo: "Meta+Shift+Z" } : { mod: "Control", redo: "Control+y" };
}
