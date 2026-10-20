import { expect, test } from "@playwright/test";
import type { Page } from "@playwright/test";
import { readCode, replaceCode, insertText } from "./editor-helpers";

const authoringAsset = /\/assets\/authoring-[^/]+\.js$/;
const gatedControls = ["#start", "#restart", "#source-toggle"];

function gateAuthoringRequest() {
  let release!: () => void;
  let markIntercepted!: () => void;
  const barrier = new Promise<void>(resolve => { release = resolve; });
  const intercepted = new Promise<void>(resolve => { markIntercepted = resolve; });
  return { barrier, intercepted, markIntercepted, release };
}
async function selectPhrase(page: Page, phrase: string): Promise<void> {
  await page.locator(".cm-content").evaluate((content, text) => {
    const walker = document.createTreeWalker(content, NodeFilter.SHOW_TEXT);
    let node: Node | null;
    while ((node = walker.nextNode())) {
      const offset = node.textContent!.indexOf(text);
      if (offset >= 0) {
        const selection = window.getSelection()!;
        selection.setBaseAndExtent(node, offset, node, offset + text.length);
        return;
      }
    }
    throw new Error(`Could not find phrase in editor: ${text}`);
  }, phrase);
}

async function settledSelectionState(page: Page) {
  await page.evaluate(() => new Promise<void>(resolve =>
    requestAnimationFrame(() => requestAnimationFrame(() => resolve())),
  ));
  return page.evaluate(() => {
    const selection = window.getSelection()!;
    const caret = document.createRange();
    caret.setStart(selection.focusNode!, selection.focusOffset);
    caret.collapse(true);
    return {
      selected: selection.toString(),
      focused: document.activeElement?.classList.contains("cm-content"),
      caret: (() => {
        const rect = caret.getBoundingClientRect();
        return { x: rect.x, y: rect.y };
      })(),
      scrollTop: document.querySelector<HTMLElement>(".cm-scroller")!.scrollTop,
    };
  });
}

function longSource(): string {
  return [
    'note("C4 E4").gain(0.2);',
    ...Array.from({ length: 36 }, (_, index) => `// source remains editable while tools load ${index}`),
    'note("A4 B4 G4").gain(0.2);',
  ].join("\n");
}

test("short authoring startup never shows a loading notice", async ({ page }) => {
  // The installed clock runs until paused, so pause at a time it has not reached yet.
  await page.clock.install({ time: new Date("2026-01-01T00:00:00Z") });
  await page.clock.pauseAt(new Date("2026-01-01T00:01:00Z"));
  const gate = gateAuthoringRequest();
  await page.route(authoringAsset, async route => {
    gate.markIntercepted();
    await gate.barrier;
    await route.continue();
  });

  try {
    await page.goto("/", { waitUntil: "domcontentloaded" });
    await expect(page.locator("body")).toHaveAttribute("data-authoring", "loading");
    await page.clock.runFor(32);
    await gate.intercepted;
    await expect(page.locator("#score-readiness")).toBeHidden();
    await expect(page.locator("#start")).toHaveText("Play");
    await expect(page.getByRole("textbox", { name: "Music code" })).not.toHaveAttribute("aria-describedby");

    gate.release();
    await expect(page.locator("body")).toHaveAttribute("data-authoring", "ready");
    await page.clock.runFor(1000);
    await expect(page.locator("#score-readiness")).toBeHidden();
    await expect(page.locator("#start")).toBeEnabled();
  } finally {
    gate.release();
    await page.unroute(authoringAsset);
  }
});

test("editing and Undo stay live while authoring loads, then the latest note is playable", async ({ page }) => {
  const gate = gateAuthoringRequest();
  await page.route(authoringAsset, async route => {
    gate.markIntercepted();
    await gate.barrier;
    await route.continue();
  });

  try {
    await page.goto("/", { waitUntil: "domcontentloaded" });
    await gate.intercepted;
    await expect(page.locator("body")).toHaveAttribute("data-authoring", "loading");
    await expect(page.locator("#score-readiness")).toBeVisible();
    await expect(page.getByRole("textbox", { name: "Music code" })).toHaveAccessibleDescription(/code is editable/i);
    await expect(page.locator("#start")).toHaveText("Play");
    for (const selector of gatedControls) await expect(page.locator(selector)).toBeDisabled();

    const beforeUndo = 'note("C4 E4").gain(0.2)';
    await replaceCode(page, beforeUndo);
    await replaceCode(page, 'note("A4 B4").gain(0.2)');
    await page.locator("#undo").click();
    await expect.poll(() => readCode(page)).toBe(beforeUndo);

    const latest = 'bpm(120); note("F4 G4").gain(0.2)';
    await replaceCode(page, latest);
    await expect.poll(() => readCode(page)).toBe(latest);

    gate.release();
    await expect(page.locator("body")).toHaveAttribute("data-authoring", "ready");
    await expect(page.locator("#score-readiness")).toBeHidden();
    await expect.poll(() => readCode(page)).toBe(latest);
    await expect(page.locator(".moving-score__note-label")).toHaveText(["F4", "G4"]);
    await page.locator("#undo").click();
    await expect.poll(() => readCode(page)).toBe(beforeUndo);
    await page.locator("#redo").click();
    await expect.poll(() => readCode(page)).toBe(latest);

    await page.locator("#start").click();
    await expect(page.locator("#status")).toHaveText("Playing");
    await expect(page.locator("#log")).not.toHaveClass(/error/);
  } finally {
    gate.release();
    await page.unroute(authoringAsset);
  }
});

for (const viewport of [{ name: "desktop", width: 1280, height: 800 }, { name: "mobile", width: 390, height: 844 }]) {
  test(`late authoring preserves selected phrase, caret, and editor scroll on ${viewport.name}`, async ({ page }) => {
    await page.setViewportSize({ width: viewport.width, height: viewport.height });
    const gate = gateAuthoringRequest();
    await page.route(authoringAsset, async route => {
      gate.markIntercepted();
      await gate.barrier;
      await route.continue();
    });

    try {
      await page.goto("/", { waitUntil: "domcontentloaded" });
      await gate.intercepted;
      await expect(page.locator("body")).toHaveAttribute("data-authoring", "loading");
      await expect(page.locator("#score-readiness")).toHaveText("Code is editable. Loading score tools…");
      const source = longSource();
      await replaceCode(page, source);
      const editor = page.locator(".cm-content");
      await editor.evaluate((content, phrase) => {
        const line = [...content.querySelectorAll<HTMLElement>(".cm-line")]
          .find(element => element.textContent?.includes(phrase));
        if (!line) throw new Error(`Could not find editor line: ${phrase}`);
        line.scrollIntoView({ block: "center" });
      }, 'note("A4 B4 G4")');
      await selectPhrase(page, "A4 B4 G4");
      await expect.poll(() => page.evaluate(() => document.querySelector<HTMLElement>(".cm-scroller")!.scrollTop))
        .toBeGreaterThan(0);
      const before = await settledSelectionState(page);
      expect(before.selected).toBe("A4 B4 G4");
      expect(before.focused).toBe(true);

      gate.release();
      await expect(page.locator("body")).toHaveAttribute("data-authoring", "ready");
      await expect(page.locator("#score-readiness")).toBeHidden();
      const after = await settledSelectionState(page);
      expect(after.selected).toBe(before.selected);
      expect(after.focused).toBe(true);
      expect(Math.abs(after.caret.x - before.caret.x)).toBeLessThanOrEqual(2);
      expect(Math.abs(after.caret.y - before.caret.y)).toBeLessThanOrEqual(2);
      expect(after.scrollTop).toBe(before.scrollTop);
      await expect(page.locator(".moving-score__note-label")).toHaveText(["A4", "B4", "G4"]);
      expect(await readCode(page)).toBe(source);

      await insertText(page, "D4");
      const edited = source.replace("A4 B4 G4", "D4");
      await expect.poll(() => readCode(page)).toBe(edited);
      await expect(page.locator(".moving-score__note-label")).toHaveText(["D4"]);
      await page.locator("#undo").click();
      await expect.poll(() => readCode(page)).toBe(source);
      await expect(page.locator(".moving-score__note-label")).toHaveText(["A4", "B4", "G4"]);
      await page.locator("#redo").click();
      await expect.poll(() => readCode(page)).toBe(edited);
      await expect(page.locator(".moving-score__note-label")).toHaveText(["D4"]);
    } finally {
      gate.release();
      await page.unroute(authoringAsset);
    }
  });
}

test("an aborted authoring import reports recovery advice without disabling the editor", async ({ page }) => {
  let markIntercepted!: () => void;
  const intercepted = new Promise<void>(resolve => { markIntercepted = resolve; });
  await page.route(authoringAsset, async route => {
    markIntercepted();
    await route.abort();
  });

  try {
    await page.goto("/", { waitUntil: "domcontentloaded" });
    await intercepted;
    await expect(page.locator("body")).toHaveAttribute("data-authoring", "failed");
    await expect(page.locator("#score-readiness")).toHaveText("Code is editable. Score tools unavailable.");
    await expect(page.locator("#score-readiness")).toBeVisible();
    await expect(page.locator("#log")).toBeVisible();
    await expect(page.locator("#log")).toContainText(/reload/i);
    for (const selector of gatedControls) await expect(page.locator(selector)).toBeDisabled();

    const editable = 'note("D4 F4").gain(0.2)';
    await replaceCode(page, editable);
    await expect.poll(() => readCode(page)).toBe(editable);
  } finally {
    await page.unroute(authoringAsset);
  }
});
