import { expect, test } from "@playwright/test";
import { readFileSync } from "node:fs";
import { buildParser } from "@lezer/generator";
import { Draft } from "../src/authoring";
import { replaceCode, readCode } from "./editor-helpers";

const grammar = readFileSync(
  new URL("../src/lang/minilive.grammar", import.meta.url),
  "utf8",
);
const parser = buildParser(grammar);

// One corpus exercises both the production MoonBit parser and editor token boundaries.
for (const [name, source] of [
  ["consecutive comment stars", '/* 🎹 .gain(.1) **/ note("C3").gain(.6) /* end */'],
  ["long star runs", '/****/ note("C3").gain(.6) /* .lpf(99) *****/'],
  ["multiline string", '/* 🎹 */ note("C3\nE3").gain(.6).lpf(1800, .7)'],
  ["opaque string content", 'song(section("a .gain(.1)",1,note("C3").gain(.6)),part("p","a .gain(.1)"))'],
  ["literal backslash before quote", String.raw`song(section("a\",1,note("C3").gain(.6)),part("p","a\"))`],
] as const) {
  test(`source and editor agree on ${name}`, async ({ page }) => {
    const draft = new Draft(source);
    try {
      expect(draft.state().diagnostic).toBeNull();
      expect(draft.prepare().source).toBe(source);
    } finally { draft.dispose(); }
    const numbers: string[] = [];
    parser.parse(source).iterate({ enter(node) {
      if (node.name === "Number" && node.node.parent?.parent?.name === "MemberCall") numbers.push(source.slice(node.from, node.to));
    } });
    expect(numbers).toEqual(name === "multiline string" ? [".6", "1800", ".7"] : [".6"]);
    await page.goto("/");
    await replaceCode(page, source);
    await expect(page.locator(".cm-inline-control")).toHaveCount(numbers.length);
    await page.getByRole("slider", { name: "Adjust Gain", exact: true }).press("Enter");
    const input = page.getByRole("textbox", { name: "Gain", exact: true });
    await input.fill(".8");
    await input.press("Enter");
    const actual = await readCode(page);
    expect(actual).toBe(source.replace('.gain(.6)', '.gain(.8)'));
  });
}

test("unfinished lexical tokens never expose modifier-looking content", async ({ page }) => {
  await page.goto("/");
  for (const source of ['note("C3\n.gain(.6).lpf(1800)', '/* 🎹 ** .gain(.6) note("C3").lpf(1800)']) {
    const draft = new Draft(source);
    try { expect(draft.state().diagnostic).not.toBeNull(); } finally { draft.dispose(); }
    await replaceCode(page, source);
    await expect(page.locator(".cm-inline-control")).toHaveCount(0);
  }
});

function parseFacts(source: string) {
  const numbers: string[] = [];
  const chains: string[] = [];
  let errors = 0;
  parser.parse(source).iterate({
    enter(node) {
      if (node.name === "Number") numbers.push(source.slice(node.from, node.to));
      if (node.name === "Chain") chains.push(source.slice(node.from, node.to));
      if (node.type.isError) errors += 1;
    },
  });
  return { numbers, chains, errors };
}

test("MiniLive parses signed numbers without weakening malformed-sign errors", () => {
  expect(parseFacts('note("E4").pan(-1)')).toMatchObject({
    numbers: ["-1"],
    errors: 0,
  });

  const overlay = 'note("E4").pan(-0.45) + note("G4").pan(0.45)';
  expect(parseFacts(overlay)).toEqual({
    numbers: ["-0.45", "0.45"],
    chains: ['note("E4").pan(-0.45)', 'note("G4").pan(0.45)'],
    errors: 0,
  });

  expect(parseFacts('(note("E4").pan(0.45) + note("G4")).slow(2)')).toMatchObject({
    numbers: ["0.45", "2"],
    errors: 0,
  });
  for (const source of ['note("E4").pan(-)', 'note("E4").pan(--0.45)']) {
    expect(parseFacts(source).errors).toBeGreaterThan(0);
  }
});

test("MiniLive accepts source declarations, comments, and repeated arrangements", () => {
  const source = '// tempo belongs to source\nbpm(72); let pad = note("E4");\n/* section */ song(section("a",1/100,pad),part("first","a")).repeat()';
  expect(parseFacts(source)).toMatchObject({ numbers: ["72", "1", "100"], errors: 0 });
});

test("MiniLive keeps number highlighting while the sign is edited", async ({ page }) => {
  const source = 'note("E4").pan(-0.45) + note("G4").pan(0.45)';
  await page.goto("/");
  const editor = page.locator(".cm-content");
  await replaceCode(page, source);
  const numberTokens = () => editor.locator("span").evaluateAll((spans) =>
    spans
      .filter((span) => span.textContent?.endsWith("0.45"))
      .map((span) => [span.textContent, span.className]),
  );

  const initialTokens = await numberTokens();
  expect(initialTokens.map((token) => token[0])).toEqual(["-0.45", "0.45"]);
  expect(initialTokens[0][1]).not.toBe("");
  expect(initialTokens[0][1]).toBe(initialTokens[1][1]);

  await editor.press("Control+Home");
  for (let pos = 0; pos < source.indexOf("-"); pos += 1) {
    await editor.press("ArrowRight");
  }
  await editor.press("Delete");
  await expect.poll(numberTokens).toEqual([
    ["0.45", initialTokens[0][1]],
    ["0.45", initialTokens[0][1]],
  ]);

  await editor.pressSequentially("-");
  await expect.poll(numberTokens).toEqual(initialTokens);

  await editor.pressSequentially("-");
  await editor.press("Backspace");
  await expect.poll(numberTokens).toEqual(initialTokens);
});

test("MiniLive completes filters with cutoff and resonance arguments", async ({ page }) => {
  await page.goto("/");
  const editor = page.locator(".cm-content");
  await replaceCode(page, 'note("C4").');
  await editor.press("Control+Space");

  const labels = page.locator(".cm-completionLabel");
  await expect(labels.filter({ hasText: /^gain$/ })).toBeVisible();
  await expect(labels.filter({ hasText: /^lpf$/ })).toBeVisible();
  await expect(labels.filter({ hasText: /^hpf$/ })).toBeVisible();
  await labels.filter({ hasText: /^lpf$/ }).click();
  await expect.poll(() => readCode(page)).toBe('note("C4").lpf(hz, resonance)');
});
