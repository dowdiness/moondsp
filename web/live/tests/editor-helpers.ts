import type { Page } from "@playwright/test";

// Use the editor's Select All command, not a native DOM range spanning widgets.
export async function replaceCode(page: Page, source: string): Promise<void> {
  const editor = page.locator(".cm-content");
  await editor.focus();
  // CodeMirror uses the page platform, which keyboard-history tests also emulate.
  const selectAll = await page.evaluate(() => /Mac/.test(navigator.platform) ? "Meta+a" : "Control+a");
  await editor.press(selectAll);
  await page.keyboard.insertText(source);
}

export async function readCode(page: Page): Promise<string> {
  return page.locator(".cm-line").evaluateAll(lines => lines.map(line => {
    const copy = line.cloneNode(true) as HTMLElement;
    copy.querySelectorAll(".cm-inline-control").forEach(widget => widget.remove());
    return copy.textContent;
  }).join("\n"));
}
