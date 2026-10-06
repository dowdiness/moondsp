import { expect, test, type Page } from "@playwright/test";
import { readCode, replaceCode } from "./editor-helpers";

async function collectOccurrences(page: Page): Promise<{ occurrences: string[]; mismatches: string[]; peak: number; references: string[] }> {
  return page.evaluate(() => {
    const { promise, resolve } = Promise.withResolvers<{ occurrences: string[]; mismatches: string[]; peak: number; references: string[] }>();
    const occurrences = new Set<string>();
    const mismatches = new Set<string>();
    const references = new Set<string>();
    const samples = new Float32Array(1024);
    const deadline = performance.now() + 6500;
    let peak = 0;
    function frame() {
      const atoms = [...document.querySelectorAll(".cm-playback-atom")].map(element => element.textContent);
      for (const reference of document.querySelectorAll(".cm-playback-reference")) references.add(reference.textContent ?? "");
      const notes = [...document.querySelectorAll<SVGElement>(".moving-score__note.is-playing")];
      for (const note of notes) {
        const pitch = Number(note.dataset.pitch);
        const atom = pitch === 60 ? "C4" : pitch === 64 ? "E4" : `unexpected:${pitch}`;
        occurrences.add(`${atom}:${note.dataset.start}`);
        if (!atoms.includes(atom)) mismatches.add(`${atom} has no code onset`);
      }
      if (notes.length > 1) mismatches.add("Sequential repeated occurrences lit together");
      window.__moondspEngine!.readWaveform(samples);
      for (const sample of samples) peak = Math.max(peak, Math.abs(sample));
      if (occurrences.size === 4 || performance.now() > deadline) {
        resolve({ occurrences: [...occurrences].sort(), mismatches: [...mismatches], peak, references: [...references] });
      } else requestAnimationFrame(frame);
    }
    requestAnimationFrame(frame);
    return promise;
  });
}

for (const mode of ["pattern", "song"] as const) {
  test(`${mode} actual onsets link source and individual repeated notes without changing code`, async ({ page }) => {
    await page.goto("/");
    const source = mode === "pattern"
      ? 'bpm(120); note("[C4 E4]*2").gain(.2)'
      : 'let motif = note("[C4 E4]*2").gain(.2);\nsong(bpm(120), section("A", 1, motif), part("loop", "A")).repeat()';
    await replaceCode(page, source);
    // Inline notation follows the cursor's source line, not the Song layout.
    await page.locator(".cm-content").press("Control+Home");
    await page.locator("#start").click();
    await expect(page.locator("#status")).toHaveText("Playing");
    const result = await collectOccurrences(page);
    expect(result.occurrences).toEqual(["C4:0", "C4:0.5", "E4:0.25", "E4:0.75"]);
    expect(result.mismatches).toEqual([]);
    expect(result.peak).toBeGreaterThan(0.001);
    if (mode === "song") expect(result.references).toContain("motif");
    expect(await readCode(page)).toBe(source);
    await page.locator("#start").click();
    await expect(page.locator(".cm-playback-atom, .moving-score__note.is-playing")).toHaveCount(0);
  });
}

test("mobile source and diagram onsets survive editing, saving and restoration", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/");
  const source = 'bpm(120); note("[C4 E4]*2").gain(.2)';
  await replaceCode(page, source);
  await page.locator("#start").click();
  await expect(page.locator("#status")).toHaveText("Playing");
  expect((await collectOccurrences(page)).occurrences).toEqual(["C4:0", "C4:0.5", "E4:0.25", "E4:0.75"]);
  // Insert before the source without replacing the atoms: their identities move.
  const editor = page.locator(".cm-content");
  await editor.focus();
  await editor.press("Control+Home");
  await page.keyboard.insertText("// shifted while playing\n");
  const edited = `// shifted while playing\n${source}`;
  await expect.poll(() => readCode(page)).toBe(edited);
  const moved = await collectOccurrences(page);
  expect(moved.occurrences).toEqual(["C4:0", "C4:0.5", "E4:0.25", "E4:0.75"]);
  expect(moved.mismatches).toEqual([]);
  await page.locator("#start").click();
  await expect(page.locator(".cm-playback-atom, .moving-score__note.is-playing")).toHaveCount(0);
  await expect.poll(() => page.evaluate(() => Object.values(localStorage).some(value => String(value).includes("shifted while playing")))).toBe(true);
  await page.reload();
  await expect.poll(() => readCode(page)).toBe(edited);
  await editor.focus();
  await editor.press("Control+Home");
  await editor.press("ArrowDown");
  await page.locator("#start").click();
  const restored = await collectOccurrences(page);
  expect(restored.occurrences).toEqual(["C4:0", "C4:0.5", "E4:0.25", "E4:0.75"]);
  expect(restored.mismatches).toEqual([]);
});

test("invalid drafts retain unchanged origins but Undo reinsertion cannot inherit retired onsets", async ({ page }) => {
  await page.goto("/");
  const source = 'bpm(240); note("C4").fast(2)';
  await replaceCode(page, source);
  await page.locator("#start").click();
  await expect(page.locator(".cm-playback-atom")).toHaveText("C4");
  const editor = page.locator(".cm-content");
  await editor.focus();
  await editor.press("Control+End");
  await page.keyboard.insertText("\n???");
  const invalid = `${source}\n???`;
  await expect.poll(() => readCode(page)).toBe(invalid);
  await expect(page.locator(".cm-playback-atom")).toHaveText("C4");
  await editor.press("Control+Home");
  for (let i = 0; i < source.indexOf("C4"); i++) await editor.press("ArrowRight");
  await editor.press("Shift+ArrowRight");
  await editor.press("Shift+ArrowRight");
  await editor.press("Backspace");
  await editor.press("Control+z");
  await expect.poll(() => readCode(page)).toBe(invalid);
  const retired = await page.evaluate(() => {
    const { promise, resolve } = Promise.withResolvers<{ events: number; falselyHighlighted: boolean }>();
    const initial = window.__moondspEngine!.onsetStatistics()!.written;
    const deadline = performance.now() + 3000;
    let falselyHighlighted = false;
    function frame() {
      falselyHighlighted ||= document.querySelector(".cm-playback-atom, .moving-score__note.is-playing") !== null;
      const events = window.__moondspEngine!.onsetStatistics()!.written - initial;
      if (events >= 6 || performance.now() > deadline) resolve({ events, falselyHighlighted });
      else requestAnimationFrame(frame);
    }
    requestAnimationFrame(frame);
    return promise;
  });
  expect(retired.events).toBeGreaterThanOrEqual(6);
  expect(retired.falselyHighlighted).toBe(false);
});

for (const phrase of [
  { expression: 'note("C4 ~ E4 ~")', atoms: ["C4", "E4"], voices: 1 },
  { expression: 'chord("C ~ Dm ~")', atoms: ["C", "Dm"], voices: 3 },
]) {
  test(`${phrase.expression} holds through rests until the next onset group`, async ({ page }) => {
    await page.goto("/");
    await replaceCode(page, `bpm(120); ${phrase.expression}.slow(4).gain(.2)`);
    await page.locator("#start").click();
    const result = await page.evaluate(() => {
      const { promise, resolve } = Promise.withResolvers<{
        groups: { atom: string; starts: string[]; first: number; last: number }[];
        gaps: boolean;
      }>();
      const groups: { atom: string; starts: string[]; first: number; last: number }[] = [];
      const deadline = performance.now() + 6500;
      let gaps = false;
      function frame(now: number) {
        const atom = [...document.querySelectorAll(".cm-playback-atom")].map(node => node.textContent).join(",");
        const starts = [...document.querySelectorAll<SVGElement>(".moving-score__note.is-playing")].map(node => node.dataset.start!);
        const previous = groups.at(-1);
        if (!atom || !starts.length) {
          if (previous) gaps = true;
        } else if (previous?.atom === atom && previous.starts.join(",") === starts.join(",")) {
          previous.last = now;
        } else {
          groups.push({ atom, starts, first: now, last: now });
        }
        if (groups.length >= 3 || now > deadline) resolve({ groups, gaps });
        else requestAnimationFrame(frame);
      }
      requestAnimationFrame(frame);
      return promise;
    });
    expect(result.gaps).toBe(false);
    expect(result.groups.map(group => group.atom)).toEqual([...phrase.atoms, phrase.atoms[0]]);
    expect(result.groups.map(group => group.starts)).toEqual([
      Array(phrase.voices).fill("0"),
      Array(phrase.voices).fill("0.5"),
      Array(phrase.voices).fill("0"),
    ]);
    for (const group of result.groups.slice(0, 2)) expect(group.last - group.first).toBeGreaterThan(350);
    await page.locator("#start").click();
    await expect(page.locator(".cm-playback-atom, .moving-score__note.is-playing")).toHaveCount(0);
  });
}
