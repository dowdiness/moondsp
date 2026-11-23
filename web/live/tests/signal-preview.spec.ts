import { expect, test } from "@playwright/test";
import { insertText, replaceCode } from "./editor-helpers";

test("a graph sits before each signal at text size and follows transforms around its control", async ({ page }) => {
  await page.goto("/");
  // slow(4) applies after the filter and before the gain.
  await replaceCode(page, '$: note("C2").lpf(saw.range(200, 4000)).slow(4).gain(isaw.range(0, 1))\n$: silence()');
  const graphs = page.locator(".cm-signal-preview");
  await expect(graphs).toHaveCount(2);
  const layout = await page.locator(".cm-content").evaluate(editor => {
    const lines = [...editor.querySelectorAll(".cm-line")];
    return {
      heights: lines.map(line => line.getBoundingClientRect().height),
      after: [...editor.querySelectorAll(".cm-signal-preview")].map(widget => {
        const range = document.createRange();
        range.selectNodeContents(widget.closest(".cm-line")!);
        range.setStartAfter(widget);
        return range.toString().slice(0, 4);
      }),
    };
  });
  expect(layout.heights[0]).toBeCloseTo(layout.heights[1], 1);
  expect(layout.after).toEqual(["saw.", "isaw"]);
  await expect(graphs.first()).toHaveAttribute("aria-label", "Signal graph. Over 4 cycles, then repeats. Start 200 → end 4000 · low 200 · high 4000");
  await graphs.nth(1).hover();
  await expect(page.locator(".cm-signal-hint").nth(1)).toBeVisible();
  await expect(page.locator(".cm-signal-hint").nth(1)).toHaveText("Over 1 cycle, then repeats\nStart 1 → end 0 · low 0 · high 1");
});

test.describe("touch signal graphs", () => {
  test.use({ hasTouch: true, isMobile: true, viewport: { width: 390, height: 844 } });
  test.skip(({ browserName }) => browserName === "firefox", "Firefox has no mobile emulation");
  test("a tap opens a graph's summary, and a second tap or one on the code closes it", async ({ page }) => {
    await page.goto("/");
    await replaceCode(page, '$: note("C2").gain(saw.range(1, 0))');
    const graph = page.locator(".cm-signal-preview");
    const hint = page.locator(".cm-signal-hint");
    await expect(hint).toBeHidden();
    await graph.tap();
    await expect(hint).toBeVisible();
    await expect(hint).toHaveText("Over 1 cycle, then repeats\nStart 1 → end 0 · low 0 · high 1");
    await graph.tap();
    await expect(hint).toBeHidden();
    await graph.tap();
    await expect(hint).toBeVisible();
    await page.locator(".cm-line").first().tap();
    await expect(hint).toBeHidden();
    await expect(page.locator(".cm-content")).toBeFocused();
  });
});

test("a song graph shows where its section plays on the song timeline", async ({ page }) => {
  await page.goto("/");
  await replaceCode(page, 'song(section("a", 4, note("C2")),\n  section("b", 4, note("C2").gain(saw.range(1, 0).slow(8))),\n  part("p1", "a"), part("p2", "b"))');
  await expect(page.locator(".cm-signal-preview")).toHaveAttribute("aria-label",
    "Signal graph. Song: 8 cycles. Plays in cycles 4–8. Start 1 → end 0.5 · low 0.5 · high 1");
});

test("graphs stay with their signals while the draft does not parse, until their own text changes", async ({ page }) => {
  await page.goto("/");
  const source = 'note("C2").lpf(saw.range(200, 4000)).pan(sine)';
  await replaceCode(page, source);
  const graphs = page.locator(".cm-signal-preview");
  await expect(graphs).toHaveCount(2);
  const editor = page.locator(".cm-content");
  // An unfinished method call elsewhere: both graphs stay.
  await editor.press("End");
  await insertText(page, ".gain(");
  await expect(page.locator(".cm-diagnostic")).toHaveCount(1);
  await expect(graphs).toHaveCount(2);
  // Editing the filter's signal while the draft still does not parse removes only its graph.
  await page.locator(".cm-content span", { hasText: /^4000$/ }).dblclick();
  await insertText(page, "8000");
  await expect(graphs).toHaveCount(1);
  await expect(graphs).toHaveAttribute("aria-label", /Start 0\.5/);
  // Once the draft parses again, the Draft draws every graph afresh.
  await editor.press("End");
  await insertText(page, "0.5)");
  await expect(graphs).toHaveCount(2);
  await expect(graphs.first()).toHaveAttribute("aria-label", /end 8000/);
});
