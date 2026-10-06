import { expect, test } from "@playwright/test";
import { openPitchControls, readCode, replaceCode } from "./editor-helpers";

test("output trace follows real audio, pause, and failure without retaining old samples", async ({ page }) => {
  await page.goto("/");
  await replaceCode(page, 'bpm(120); note("C4").gain(0.2)');
  await page.locator("#start").click();
  await expect(page.locator("#status")).toHaveText("Playing");
  const peak = () => page.evaluate(() => {
    const samples = new Float32Array(2048);
    window.__moondspEngine!.readWaveform(samples);
    return samples.reduce((value, sample) => Math.max(value, Math.abs(sample)), 0);
  });
  await expect.poll(peak).toBeGreaterThan(0.001);
  await page.locator("#start").click();
  await expect(page.locator("#status")).toHaveText("Paused");
  await expect.poll(peak).toBeLessThan(0.00001);
  await page.locator("#start").click();
  await expect.poll(peak).toBeGreaterThan(0.001);
  const retired = await page.evaluate(() => {
    window.__moondspEngine!._testInjectReply({ type: "error", message: "trace lifetime regression" });
    const samples = new Float32Array(2048).fill(1);
    const active = window.__moondspEngine!.readWaveform(samples);
    return { active, max: Math.max(...samples) };
  });
  expect(retired).toEqual({ active: false, max: 0 });
});

test("drawing and pitch edits do not start audio; main Play outputs sound and Undo leaves playback running", async ({ page }) => {
  await page.addInitScript(() => {
    const NativeContext = window.AudioContext;
    let created = 0;
    Object.defineProperty(window, "__createdContexts", { get: () => created });
    window.AudioContext = class extends NativeContext {
      constructor(options?: AudioContextOptions) { super(options); created++; }
    };
  });
  await page.goto("/");
  const source = 'note("C4 E4 G4").gain(0.2)';
  await replaceCode(page, source);
  const geometry = await page.waitForFunction(() => {
    const note = document.querySelector(".moving-score__note-block")?.getBoundingClientRect();
    const row = document.querySelector('.moving-score__lane[data-pitch="62"]')?.getBoundingClientRect();
    if (!note?.width || !note.height || !row?.height) return null;
    return { x: note.x + note.width / 2, from: note.y + note.height / 2, to: row.y + row.height / 2 };
  });
  const point = (await geometry.jsonValue())!;
  await geometry.dispose();
  await page.mouse.move(point.x, point.from);
  await page.mouse.down();
  await page.mouse.move(point.x, point.to);
  await page.mouse.up();
  await expect.poll(() => readCode(page)).toBe(source.replace("C4", "D4"));
  await expect(page.locator("#status")).toHaveText("Ready");
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(source);
  await openPitchControls(page);
  await page.getByRole("button", { name: "Set C#4", exact: true }).click();
  await expect.poll(() => readCode(page)).toBe(source.replace("C4", "C#4"));
  await expect(page.locator("#status")).toHaveText("Ready");
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(source);
  const peak = () => page.evaluate(() => {
    const samples = new Float32Array(2048);
    window.__moondspEngine!.readWaveform(samples);
    return samples.reduce((value, sample) => Math.max(value, Math.abs(sample)), 0);
  });
  await page.locator("#start").click();
  await expect(page.locator("#status")).toHaveText("Playing");
  await expect.poll(peak).toBeGreaterThan(0.001);
  await page.getByRole("button", { name: "Set C#4", exact: true }).click();
  await expect.poll(() => readCode(page)).toBe(source.replace("C4", "C#4"));
  await expect(page.locator("#status")).toHaveText("Playing");
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(source);
  await expect(page.locator("#status")).toHaveText("Playing");
  await expect.poll(peak).toBeGreaterThan(0.001);
  expect(await page.evaluate(() => Reflect.get(window, "__createdContexts"))).toBe(1);
});

test("Help can explore a new sound and Undo retains the previous composition", async ({ page }) => {
  await page.goto("/");
  const source = '// My phrase\nnote("D4 F4 A4").gain(0.2)';
  await replaceCode(page, source);
  await page.getByRole("button", { name: "Help", exact: true }).click();
  await page.getByRole("button", { name: "Explore Slow drift", exact: true }).click();
  await expect(page.locator("#status")).toHaveText("Playing");
  await expect(page.locator("#status")).toHaveAttribute("data-tempo", "72");
  await expect.poll(() => readCode(page)).toContain('chord("Cm7 Abmaj7")');
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(source);
});

test("drawn contours preserve intermediate bends and formatting as one undo step", async ({ page }) => {
  await page.goto("/");
  const source = '// 曲線\nbpm(96);\n$: note("C4  C4\nC4 C4").gain(0.2)';
  await replaceCode(page, source);
  const surface = page.locator(".moving-score__canvas");
  const centers = await page.locator(".moving-score__note-block").evaluateAll(notes =>
    notes.map(note => { const rect = note.getBoundingClientRect(); return rect.x + rect.width / 2; }));
  const point = async (index: number, pitch: number) => {
    const row = (await page.locator(`.moving-score__lane[data-pitch="${pitch}"]`).boundingBox())!;
    return { x: centers[index], y: row.y + row.height / 2 };
  };
  const first = await point(0, 67), middle = await point(1, 60), third = await point(2, 64), last = await point(3, 67);
  await page.mouse.move(first.x, first.y);
  await page.mouse.down();
  await page.mouse.move(middle.x, middle.y);
  await page.mouse.move(third.x, third.y);
  await page.mouse.move(last.x, last.y);
  expect(await readCode(page)).toBe(source);
  await page.mouse.up();
  await expect.poll(() => readCode(page)).toBe(source.replace("C4  C4\nC4 C4", "G4  C4\nE4 G4"));
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(source);
  await surface.evaluate(element => (element as SVGSVGElement).focus());
  await surface.press("Enter");
  await surface.press("ArrowUp");
  await surface.press("Escape");
  expect(await readCode(page)).toBe(source);
});


test("a note click preserves chromatic pitch while a drag from that note edits and undoes", async ({ page }) => {
  await page.goto("/");
  const source = '$: note("C#4 D4 Eb4 F4").gain(0.2)';
  await replaceCode(page, source);
  const note = page.locator(".moving-score__note-block").first();
  await note.click();
  expect(await readCode(page)).toBe(source);
  const box = (await note.boundingBox())!;
  const row = (await page.locator('.moving-score__lane[data-pitch="66"]').boundingBox())!;
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.down();
  await page.mouse.move(box.x + box.width / 2, row.y + row.height / 2, { steps: 5 });
  await page.mouse.up();
  await expect.poll(() => readCode(page)).toBe(source.replace("C#4", "F#4"));
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(source);
});

test("inline drawing shares the selected note with pitch controls and typing", async ({ page }) => {
  await page.goto("/");
  const source = 'note("C4 E4 G4").gain(0.2)';
  await replaceCode(page, source);
  const surface = page.locator("#editor .moving-score__canvas");
  await page.locator("#editor .moving-score__note-block").nth(1).click();
  await expect(page.locator(".step-pad").nth(1)).toHaveAttribute("aria-pressed", "true");
  await openPitchControls(page);
  await page.getByRole("button", { name: "Set F4", exact: true }).click();
  await expect.poll(() => readCode(page)).toBe(source.replace("E4", "F4"));
  await expect(page.locator(".moving-score__note.is-selected text").first()).toHaveText("F4");
  await surface.evaluate(element => (element as SVGSVGElement).focus());
  await surface.press("ArrowRight");
  await surface.press("ArrowUp");
  await expect.poll(() => readCode(page)).toBe(source.replace("E4 G4", "F4 Ab4"));
  await surface.press("Control+z");
  await expect.poll(() => readCode(page)).toBe(source.replace("E4", "F4"));
  await surface.press("Control+Shift+Z");
  await expect.poll(() => readCode(page)).toBe(source.replace("E4 G4", "F4 Ab4"));
  await surface.press("Escape");
  const editor = page.locator(".cm-content");
  await expect(editor).toBeFocused();
  await editor.press("Shift+ArrowRight");
  await editor.press("Shift+ArrowRight");
  await editor.press("Shift+ArrowRight");
  await page.keyboard.insertText("A4");
  await expect.poll(() => readCode(page)).toBe(source.replace("E4 G4", "F4 A4"));
  await expect(page.locator(".moving-score__note.is-selected text").first()).toHaveText("A4");
});

test("hiding controls cancels a pending contour without writing it", async ({ page }) => {
  await page.goto("/");
  const source = 'note("C4 E4 G4").gain(0.2)';
  await replaceCode(page, source);
  const surface = page.locator(".moving-score__canvas");
  await surface.evaluate(element => (element as SVGSVGElement).focus());
  await surface.press("Enter");
  await surface.press("ArrowUp");
  await page.locator("#source-toggle").click();
  await expect(surface).toHaveCount(0);
  await expect.poll(() => readCode(page)).toBe(source);
  await page.locator("#source-toggle").click();
  await expect(surface).toBeVisible();
  await expect(page.locator(".moving-score__note-label").first()).toHaveText("C4");
  await expect.poll(() => readCode(page)).toBe(source);
});

test("adding a melody preserves a chord-only stack and rejects song programs", async ({ page }) => {
  await page.goto("/");
  const chords = '$: chord("Cm7 Abmaj7").slow(8).gain(0.1)';
  await replaceCode(page, chords);
  await page.getByRole("button", { name: "Add melody", exact: true }).click();
  await expect.poll(async () => (await readCode(page)).split("\n")[0]).toBe(chords);
  await expect(page.locator(".moving-score__canvas")).toBeVisible();
  await page.locator("#start").click();
  await expect(page.locator("#status")).toHaveText("Playing");
  await page.locator("#start").click();
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(chords);
  const song = 'song(section("a", 4, note("C4 E4")), part("melody", "a"))';
  await replaceCode(page, song);
  await expect(page.getByRole("button", { name: "Add melody", exact: true })).toBeDisabled();
  await expect.poll(() => readCode(page)).toBe(song);
});

test("closing pitch controls retains edits and history", async ({ page }) => {
  await page.goto("/");
  const source = 'note("C4 E4").gain(0.2)';
  await replaceCode(page, source);
  const details = page.locator(".pattern-pitch-editor");
  const summary = details.locator("summary");
  await expect(page.locator(".pitch-keyboard")).not.toBeVisible();
  await summary.focus();
  await summary.press("Enter");
  await page.getByRole("button", { name: "Set C#4", exact: true }).click();
  await expect.poll(() => readCode(page)).toBe(source.replace("C4", "C#4"));
  await expect(page.locator("#status")).toHaveText("Ready");
  await summary.click();
  await expect.poll(() => readCode(page)).toBe(source.replace("C4", "C#4"));
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(source);
  await openPitchControls(page);
  await expect(page.getByRole("button", { name: "Set C4", exact: true })).toHaveAttribute("aria-pressed", "true");
  await page.locator("#source-toggle").click();
  await page.locator("#source-toggle").click();
  await expect(page.locator(".pitch-keyboard")).toBeVisible();
  await expect.poll(() => readCode(page)).toBe(source);
});
test("direct rest entry preserves weighted repeated source identity and one-step Undo", async ({ page }) => {
  await page.goto("/");
  const source = 'note("[~@3 C4]*2 D4").gain(0.2)';
  await replaceCode(page, source);
  const rests = page.locator(".moving-score__rest-hit");
  await expect(rests).toHaveCount(2);
  const slot = (await rests.first().boundingBox())!;
  const row = (await page.locator('.moving-score__lane[data-pitch="61"]').boundingBox())!;
  await page.mouse.move(slot.x + slot.width / 2, row.y + row.height / 2);
  await page.mouse.down();
  expect(await readCode(page)).toBe(source);
  await expect(page.locator(".moving-score__preview-block")).toBeVisible();
  await page.mouse.up();
  const entered = source.replace("~@3", "C#4@3");
  await expect.poll(() => readCode(page)).toBe(entered);
  await page.locator("#undo").click();
  await expect.poll(() => readCode(page)).toBe(source);
});

test("clicks in a degraded silent gap do not select a neighboring note", async ({ page }) => {
  await page.goto("/");
  const notation = Array.from({ length: 32 }, () => "C4?").join(" ");
  const source = `note("${notation}").gain(0.2)`;
  await replaceCode(page, source);
  const point = await page.locator(".moving-score__canvas").evaluate(element => {
    const svg = element as SVGSVGElement;
    const starts = [...svg.querySelectorAll<SVGGElement>(".moving-score__note")].map(note => Number(note.dataset.start));
    const missing = Array.from({ length: 32 }, (_, index) => index)
      .find(index => !starts.some(start => Math.abs(start - index / 32) < 1e-6));
    if (missing === undefined) return null;
    const rect = svg.getBoundingClientRect();
    const row = svg.querySelector<SVGRectElement>('.moving-score__lane[data-pitch="60"]')!.getBoundingClientRect();
    return { x: rect.left + 48 + (rect.width - 56) * (missing + .5) / 32, y: row.top + row.height / 2 };
  });
  expect(point).not.toBeNull();
  const selected = await page.locator(".moving-score__source-hit.is-selected").getAttribute("data-node");
  await page.mouse.click(point!.x, point!.y);
  expect(await readCode(page)).toBe(source);
  await expect(page.locator(".moving-score__source-hit.is-selected")).toHaveAttribute("data-node", selected!);
});

test("Escape cancels a pending rest click without changing source", async ({ page }) => {
  await page.goto("/");
  const source = 'note("C4 ~@2 D4").gain(0.2)';
  await replaceCode(page, source);
  const slot = (await page.locator(".moving-score__rest-hit").boundingBox())!;
  const row = (await page.locator('.moving-score__lane[data-pitch="65"]').boundingBox())!;
  await page.mouse.move(slot.x + slot.width / 2, row.y + row.height / 2);
  await page.mouse.down();
  await page.keyboard.press("Escape");
  await page.mouse.up();
  expect(await readCode(page)).toBe(source);
});

test("all-rest patterns support keyboard pitch preview, cancellation, and entry", async ({ page }) => {
  await page.goto("/");
  const source = 'note("~@2 [~]*2").gain(0.2)';
  await replaceCode(page, source);
  await expect(page.locator(".moving-score__rest-hit").first()).toBeVisible();
  const surface = page.locator(".moving-score__canvas");
  await page.locator(".moving-score__structure-details > summary").click();
  await page.locator(".moving-score__source-hit").first().focus();
  await page.locator(".moving-score__source-hit").first().press("Enter");
  await surface.focus();
  await surface.press("Enter");
  await surface.press("ArrowUp");
  await surface.press("Escape");
  expect(await readCode(page)).toBe(source);
  await surface.focus();
  await surface.press("Enter");
  await surface.press("ArrowUp");
  await surface.press("Enter");
  await expect.poll(() => readCode(page)).toBe(source.replace("~@2", "C#4@2"));
});
