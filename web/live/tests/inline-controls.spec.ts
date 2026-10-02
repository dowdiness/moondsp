import { expect, test, type Page } from "@playwright/test";

const source = 'note("C3 E3").gain(0.6).lpf(1800, 0.7)';
async function code(page: Page) {
  return page.locator(".cm-line").evaluateAll(lines => lines.map(line => {
    const copy = line.cloneNode(true) as HTMLElement;
    copy.querySelectorAll(".cm-inline-control").forEach(widget => widget.remove());
    return copy.textContent;
  }).join("\n"));
}
async function enter(page: Page, label: string, value: string, index = 0) {
  await page.getByRole("slider", { name: `Adjust ${label}`, exact: true }).nth(index).press("Enter");
  const input = page.getByRole("textbox", { name: label, exact: true });
  await input.fill(value);
  await input.press("Enter");
}
async function dragStart(page: Page, label = "Gain") {
  const handle = page.getByRole("slider", { name: `Adjust ${label}`, exact: true });
  const box = (await handle.boundingBox())!;
  const x = box.x + box.width / 2, y = box.y + box.height / 2;
  await page.mouse.move(x, y);
  await page.mouse.down();
  return { x, y };
}

test("knobs sit before source literals at text size without increasing line height", async ({ page }) => {
  await page.goto("/");
  await page.locator(".cm-content").fill(`$: ${source}\n$: silence()`);
  const layout = await page.locator(".cm-content").evaluate(editor => {
    const lines = [...editor.querySelectorAll(".cm-line")];
    return {
      heights: lines.map(line => line.getBoundingClientRect().height),
      knobs: [...editor.querySelectorAll(".cm-inline-control")].map(widget => {
        const range = document.createRange();
        range.selectNodeContents(widget.closest(".cm-line")!);
        range.setStartAfter(widget);
        return { height: widget.getBoundingClientRect().height, font: parseFloat(getComputedStyle(widget).fontSize), after: range.toString().split(")")[0] };
      }),
    };
  });
  expect(layout.heights[0]).toBeCloseTo(layout.heights[1], 1);
  expect(layout.knobs).toHaveLength(3);
  for (const knob of layout.knobs) expect(knob.height).toBeCloseTo(knob.font, 1);
  expect(layout.knobs.map(knob => knob.after.startsWith("0.6") || knob.after.startsWith("1800") || knob.after.startsWith("0.7"))).toEqual([true, true, true]);
  await page.getByRole("slider", { name: "Adjust Cutoff Hz", exact: true }).focus();
  await expect(page.locator(".cm-knob-hint").filter({ hasText: "Cutoff Hz · 1800" })).toBeVisible();
  await page.getByRole("slider", { name: "Adjust Cutoff Hz", exact: true }).press("Escape");
  await expect(page.locator(".cm-content")).toBeFocused();
});

test("cutoff drag is logarithmic and its visible value and undo stay source-bound", async ({ page }) => {
  await page.goto("/");
  await page.locator(".cm-content").fill(source);
  const { x, y } = await dragStart(page, "Cutoff Hz");
  await page.mouse.move(x, y - 40);
  await page.mouse.up();
  expect(await code(page)).toBe(source.replace("1800", "3600"));
  await expect(page.getByRole("slider", { name: "Adjust Cutoff Hz", exact: true })).toHaveAttribute("aria-valuetext", "3600 Hz");
  await page.locator(".cm-content").press("Control+z");
  expect(await code(page)).toBe(source);
});

test("literal edits preserve duplicate targets, UTF-16, comments and multiline formatting; Draft advances once", async ({ page }) => {
  await page.goto("/");
  const original = '// 日本語 🎹 .gain(0.6)\nlet bass = note("C3")\n .gain(/* keep */ 0.6)\n .lpf(1800, 0.7);\nlet lead = chord("Cm").gain(0.6);\nbass + lead';
  await page.locator(".cm-content").fill(original);
  const version = (await page.locator("#draft-status").getAttribute("data-version"))!.split(":").map(Number);
  await enter(page, "Gain", "0.8");
  const gain = original.replace('/* keep */ 0.6', '/* keep */ 0.8');
  expect(await code(page)).toBe(gain);
  await expect(page.locator("#draft-status")).toHaveAttribute("data-version", `${version[0]}:${version[1] + 1}`);
  await enter(page, "Cutoff Hz", "2400");
  expect(await code(page)).toBe(gain.replace("1800", "2400"));
  await enter(page, "Q", "1.2");
  expect(await code(page)).toBe(gain.replace("1800, 0.7", "2400, 1.2"));
  await enter(page, "Gain", "0.4", 1);
  expect(await code(page)).toBe(gain.replace("1800, 0.7", "2400, 1.2").replace('chord("Cm").gain(0.6)', 'chord("Cm").gain(0.4)'));
});

test("code edits refresh controls; omitted Q and unsupported arguments stay untouched", async ({ page }) => {
  await page.goto("/");
  const editor = page.locator(".cm-content");
  await editor.fill('note("C3").lpf(1800).gain(12)');
  await expect(page.getByRole("slider", { name: "Adjust Q", exact: true })).toHaveCount(0);
  await expect(page.getByRole("slider", { name: "Adjust Gain", exact: true })).toHaveAttribute("aria-valuenow", "12");
  expect(await code(page)).toBe('note("C3").lpf(1800).gain(12)');
  await editor.press("Control+Home");
  for (let i = 0; i < 'note("C3").lpf(1'.length; i++) await editor.press("ArrowRight");
  await editor.press("Delete");
  await editor.pressSequentially("2");
  await expect(page.getByRole("slider", { name: "Adjust Cutoff Hz", exact: true })).toHaveAttribute("aria-valuenow", "1200");
  expect(await code(page)).toBe('note("C3").lpf(1200).gain(12)');
  await editor.fill('// 🎹 shifted\nnote("C3").lpf(1200).gain(0.6)');
  await expect(page.getByRole("slider", { name: "Adjust Cutoff Hz", exact: true })).toHaveAttribute("aria-valuenow", "1200");
  await enter(page, "Gain", "0.8");
  expect(await code(page)).toBe('// 🎹 shifted\nnote("C3").lpf(1200).gain(0.8)');
  for (const unsupported of ['note("C3").gain(1/2)', 'note("C3").gain(', 'note("C3").gain(--0.6)', 'note("C3").gain(value)', 'note("C3").gain(0.6, 1)', 'note("C3").gain(0.6']) {
    await editor.fill(unsupported);
    await expect(page.locator(".cm-inline-control")).toHaveCount(0);
    expect(await code(page)).toBe(unsupported);
  }
});

test("references, groups, stacks and drums expose locally editable literals", async ({ page }) => {
  await page.goto("/");
  for (const receiver of ['let bass = note("C3"); bass', '(note("C3") + chord("Cm"))', 'stack(note("C3"), chord("Cm"))', 's("bd")', 'unknown']) {
    const original = `${receiver}.gain(.6).lpf(1800, 1.)`;
    await page.locator(".cm-content").fill(original);
    await expect(page.locator(".cm-inline-control")).toHaveCount(3);
    await enter(page, "Gain", "-.8");
    await enter(page, "Cutoff Hz", "2400");
    expect(await code(page)).toBe(`${receiver}.gain(-.8).lpf(2400, 1.)`);
    await expect(page.getByRole("slider", { name: "Adjust Gain", exact: true })).toHaveAttribute("aria-description", /drums are unaffected/);
  }
});

test("repeated modifiers expose per-argument overrides without discarding inherited Q", async ({ page }) => {
  await page.goto("/");
  const original = 'note("C3").gain(.6).gain(.8).lpf(1800, .7).lpf(2400)';
  await page.locator(".cm-content").fill(original);
  const gains = page.getByRole("slider", { name: "Adjust Gain", exact: true });
  const cutoffs = page.getByRole("slider", { name: "Adjust Cutoff Hz", exact: true });
  await expect(gains.nth(0)).toHaveAttribute("aria-description", /Overridden/);
  await expect(gains.nth(1)).not.toHaveAttribute("aria-description", /Overridden/);
  await expect(cutoffs.nth(0)).toHaveAttribute("aria-description", /Overridden/);
  await expect(page.getByRole("slider", { name: "Adjust Q", exact: true })).not.toHaveAttribute("aria-description", /Overridden/);
  await enter(page, "Gain", "1.", 0);
  expect(await code(page)).toBe(original.replace('.gain(.6)', '.gain(1.)'));
  await page.locator(".cm-content").press("Control+z");
  expect(await code(page)).toBe(original);
  await page.locator(".cm-content").fill(original + '.lpf(3000, 1.2)');
  await expect(page.getByRole("slider", { name: "Adjust Q", exact: true }).nth(0)).toHaveAttribute("aria-description", /Overridden/);
});

test("a drag with a long pause is one undo/redo, isolated from adjacent typing", async ({ page }) => {
  await page.goto("/");
  const editor = page.locator(".cm-content");
  await editor.fill(source);
  await editor.press("Control+Home");
  await editor.pressSequentially(" ");
  const { x, y } = await dragStart(page);
  await page.mouse.move(x, y - 10);
  await expect(page.getByRole("slider", { name: "Adjust Gain", exact: true })).toHaveAttribute("aria-valuenow", "0.7");
  await page.waitForTimeout(1100);
  await page.mouse.move(x, y - 20);
  await page.mouse.up();
  expect(await code(page)).toBe(" " + source.replace("0.6", "0.8"));
  await editor.press("Control+Home");
  await editor.pressSequentially(" ");
  await editor.press("Control+z");
  expect(await code(page)).toBe(" " + source.replace("0.6", "0.8"));
  await editor.press("Control+z");
  expect(await code(page)).toBe(" " + source);
  await editor.press("Control+y");
  expect(await code(page)).toBe(" " + source.replace("0.6", "0.8"));
  await editor.press("Control+z");
  await editor.press("Control+z");
  expect(await code(page)).toBe(source);
});

test("focused knob routes history shortcuts without refocusing; input keeps native undo", async ({ page }) => {
  await page.goto("/");
  await page.locator(".cm-content").fill(source);
  const gain = page.getByRole("slider", { name: "Adjust Gain", exact: true });
  const { x, y } = await dragStart(page);
  await page.mouse.move(x, y - 10);
  await page.waitForTimeout(1100);
  await page.mouse.move(x, y - 20);
  await page.mouse.up();
  await expect(gain).toBeFocused();
  expect(await code(page)).toBe(source.replace("0.6", "0.8"));
  await page.keyboard.press("Control+z");
  expect(await code(page)).toBe(source);
  await page.keyboard.press("Control+Shift+Z");
  expect(await code(page)).toBe(source.replace("0.6", "0.8"));
  await gain.focus();
  await page.keyboard.press("ArrowUp");
  await page.keyboard.press("Control+z");
  expect(await code(page)).toBe(source.replace("0.6", "0.8"));
  await page.keyboard.press("Control+y");
  expect(await code(page)).toBe(source.replace("0.6", "0.81"));
  await gain.press("Enter");
  const input = page.getByRole("textbox", { name: "Gain", exact: true });
  await page.keyboard.type("0.9");
  await page.keyboard.press("Control+z");
  await expect(input).toHaveValue("0.81");
  expect(await code(page)).toBe(source.replace("0.6", "0.81"));
});

test("external transaction interrupts a captured drag without blur and keeps separate history", async ({ page }) => {
  await page.goto("/");
  await page.locator(".cm-content").fill(source);
  const gain = page.getByRole("slider", { name: "Adjust Gain", exact: true });
  const { x, y } = await dragStart(page);
  await page.mouse.move(x, y - 10);
  // Test-only access to the mounted view; dispatch without focusing the content DOM.
  await page.locator(".cm-content").evaluate(content => {
    const view = (content as HTMLElement & { cmTile: { view: { dispatch: (spec: unknown) => void } } }).cmTile.view;
    view.dispatch({ changes: { from: 0, insert: " " } });
  });
  await expect(gain).toBeFocused();
  await page.mouse.move(x, y - 30);
  await page.mouse.up();
  expect(await code(page)).toBe(" " + source.replace("0.6", "0.7"));
  await page.keyboard.press("Control+z");
  expect(await code(page)).toBe(source.replace("0.6", "0.7"));
  await page.keyboard.press("Control+z");
  expect(await code(page)).toBe(source);
});

for (const platform of ["Win32", "MacIntel", "Linux x86_64"]) {
  test(`knob uses CodeMirror history bindings on ${platform}`, async ({ page }) => {
    await page.addInitScript(platform => Object.defineProperty(navigator, "platform", { value: platform }), platform);
    await page.goto("/");
    await page.locator(".cm-content").fill(source);
    const gain = page.getByRole("slider", { name: "Adjust Gain", exact: true });
    await gain.press("ArrowUp");
    // Synthetic keydowns deliberately have no native browser undo fallback.
    const modifier = platform === "MacIntel" ? { metaKey: true } : { ctrlKey: true };
    await gain.dispatchEvent("keydown", { key: "z", code: "KeyZ", keyCode: 90, ...modifier });
    expect(await code(page)).toBe(source);
    await gain.dispatchEvent("keydown", platform === "MacIntel"
      ? { key: "Z", code: "KeyZ", keyCode: 90, metaKey: true, shiftKey: true }
      : { key: "y", code: "KeyY", keyCode: 89, ctrlKey: true });
    expect(await code(page)).toBe(source.replace("0.6", "0.61"));
  });
}

test("invalid direct input cancels; keyboard adjustment and copy use source only", async ({ page, context }) => {
  await context.grantPermissions(["clipboard-read", "clipboard-write"]);
  await page.goto("/");
  const editor = page.locator(".cm-content");
  await editor.fill(source);
  await enter(page, "Gain", "1e3");
  await expect(page.getByRole("textbox", { name: "Gain", exact: true })).toHaveAttribute("aria-invalid", "true");
  expect(await code(page)).toBe(source);
  await page.getByRole("textbox", { name: "Gain", exact: true }).press("Escape");
  await expect(page.getByRole("slider", { name: "Adjust Gain", exact: true })).toHaveAttribute("aria-valuenow", "0.6");
  await page.getByRole("slider", { name: "Adjust Gain", exact: true }).press("Shift+ArrowUp");
  expect(await code(page)).toBe(source.replace("0.6", "0.601"));
  await editor.press("Control+a");
  await editor.press("Control+c");
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(source.replace("0.6", "0.601"));
});

test("opening, unchanged input and pointer click do not write or clamp source", async ({ page }) => {
  await page.goto("/");
  const original = 'note("C3").gain(0.00001).lpf(25000)';
  await page.locator(".cm-content").fill(original);
  const version = await page.locator("#draft-status").getAttribute("data-version");
  await page.getByRole("slider", { name: "Adjust Gain", exact: true }).click();
  await enter(page, "Cutoff Hz", "25000");
  expect(await code(page)).toBe(original);
  await expect(page.locator("#draft-status")).toHaveAttribute("data-version", version!);
  await page.locator(".cm-content").fill("note(");
  await expect(page.locator("#change-help")).toHaveText("Fix the error below, then press Play.");
});

for (const interruption of ["pointercancel", "blur", "replace"] as const) {
  test(`drag stops on ${interruption} without later writes`, async ({ page }) => {
    await page.goto("/");
    await page.locator(".cm-content").fill(source);
    const { x, y } = await dragStart(page);
    await page.mouse.move(x, y - 10);
    if (interruption === "pointercancel") await page.getByRole("slider", { name: "Adjust Gain", exact: true }).dispatchEvent("pointercancel");
    if (interruption === "blur") await page.evaluate(() => window.dispatchEvent(new Event("blur")));
    if (interruption === "replace") await page.locator(".cm-content").fill('note("D3").gain(0.2)');
    await page.mouse.move(x, y - 20);
    await page.mouse.up();
    expect(await code(page)).toBe(interruption === "replace" ? 'note("D3").gain(0.2)' : source.replace("0.6", "0.7"));
  });
}

test("GUI edits use existing acceptance path; invalid draft preserves playback and recovery", async ({ page }) => {
  await page.goto("/");
  await page.locator(".cm-content").fill(source);
  await page.locator("#start").click();
  await expect(page.locator("#status")).toHaveText("Playing");
  await enter(page, "Gain", "0.8");
  await expect(page.locator("#draft-status")).toHaveAttribute("data-state", "accepted");
  const accepted = await page.locator("#draft-versions").textContent();
  await page.locator(".cm-content").press("Control+End");
  await page.locator(".cm-content").pressSequentially(".lpf(");
  await expect(page.locator("#draft-status")).toHaveAttribute("data-state", "invalid");
  await expect(page.locator("#status")).toHaveText("Playing");
  await expect(page.locator("#draft-versions")).toHaveText(accepted!);
  await expect(page.locator("#change-help")).toContainText("Playback continues with accepted code");
  await expect(page.locator(".cm-inline-control")).toHaveCount(3);
  await enter(page, "Gain", ".9");
  // Typing the opening parenthesis triggers CodeMirror's closing-bracket completion.
  expect(await code(page)).toBe(source.replace("0.6", ".9") + ".lpf()");
  await expect(page.locator("#draft-status")).toHaveAttribute("data-state", "invalid");
  await expect(page.locator("#draft-versions")).toHaveText(accepted!);
  await expect(page.locator("#status")).toHaveText("Playing");
  await page.locator(".cm-content").fill(source);
  await enter(page, "Cutoff Hz", "2400");
  await expect(page.locator("#draft-status")).toHaveAttribute("data-state", "accepted");
  await expect(page.locator("#log")).not.toHaveClass(/error/);
});
