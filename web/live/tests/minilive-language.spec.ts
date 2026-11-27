import { expect, test } from "@playwright/test";
import { readFileSync } from "node:fs";
import { buildParser } from "@lezer/generator";
import { CompletionContext, type CompletionResult } from "@codemirror/autocomplete";
import { ensureSyntaxTree, LRLanguage } from "@codemirror/language";
import { EditorState } from "@codemirror/state";
import { Draft, methodsAfter, vocabulary } from "../src/authoring";
import { scoreCompletion, type ScoreLanguage } from "../src/lang/minilive-completion";
import { platformKeys, replaceCode, readCode } from "./editor-helpers";

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
    expect(draft.state().problem).toBeNull();
    expect(draft.prepare().source).toBe(source);
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
    expect(new Draft(source).state().problem).not.toBeNull();
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
  const { mod } = await platformKeys(page);
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

  await editor.press(`${mod}+Home`);
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

test("MiniLive completes filters with their required cutoff argument", async ({ page }) => {
  await page.goto("/");
  // Methods come from the score language, which loads with the score tools.
  await expect(page.locator("body")).toHaveAttribute("data-authoring", "ready");
  const editor = page.locator(".cm-content");
  await replaceCode(page, 'note("C4").');
  await editor.press("Control+Space");

  const labels = page.locator(".cm-completionLabel");
  await expect(labels.filter({ hasText: /^gain$/ })).toBeVisible();
  await expect(labels.filter({ hasText: /^lpf$/ })).toBeVisible();
  await expect(labels.filter({ hasText: /^hpf$/ })).toBeVisible();
  await labels.filter({ hasText: /^lpf$/ }).click();
  await expect.poll(() => readCode(page)).toBe('note("C4").lpf(cutoff)');
});

test("MiniLive completes signals inside control arguments and their methods", async ({ page }) => {
  await page.goto("/");
  // Methods come from the score language, which loads with the score tools.
  await expect(page.locator("body")).toHaveAttribute("data-authoring", "ready");
  const editor = page.locator(".cm-content");
  const labels = page.locator(".cm-completionLabel");
  await replaceCode(page, 'note("C4").lpf(sa');
  await editor.press("Control+Space");
  await expect(labels.filter({ hasText: /^saw$/ })).toBeVisible();
  await labels.filter({ hasText: /^saw$/ }).click();
  await expect.poll(() => readCode(page)).toBe('note("C4").lpf(saw');

  await replaceCode(page, 'note("C4").lpf(saw.');
  await editor.press("Control+Space");
  await expect(labels.filter({ hasText: /^range$/ })).toBeVisible();
  await expect(labels.filter({ hasText: /^gain$/ })).toHaveCount(0);
  await labels.filter({ hasText: /^range$/ }).click();
  await expect.poll(() => readCode(page)).toBe('note("C4").lpf(saw.range(from, to)');

  // A pattern's own chain still offers pattern methods.
  await replaceCode(page, 'note("C4").');
  await editor.press("Control+Space");
  await expect(labels.filter({ hasText: /^gain$/ })).toBeVisible();
  await expect(labels.filter({ hasText: /^range$/ })).toHaveCount(0);

  // A binding named like a signal is a pattern outside control arguments.
  await replaceCode(page, 'let sine = s("bd");\nnote("C4").lpf(sine.');
  await editor.press("Control+Space");
  await expect(labels.filter({ hasText: /^range$/ })).toBeVisible();
  await replaceCode(page, 'let sine = s("bd");\nsine.');
  await editor.press("Control+Space");
  await expect(labels.filter({ hasText: /^gain$/ })).toBeVisible();
  await expect(labels.filter({ hasText: /^range$/ })).toHaveCount(0);
});

test("MiniLive completes instrument names in .s and offers .s only on receivers without drums", async ({ page }) => {
  await page.goto("/");
  // The score language decides, so its completion arrives with the score tools.
  await expect(page.locator("body")).toHaveAttribute("data-authoring", "ready");
  const editor = page.locator(".cm-content");
  const labels = page.locator(".cm-completionLabel");
  for (const [receiver, offered] of [
    ['note("C4")', true],
    ['s("bd") + note("C4")', true],
    ['silence()', true],
    ['let lead = note("C4"); lead.fast(2)', true],
    ['s("bd")', false],
    ['stack(s("bd"), note("C4"))', false],
    ['(s("bd") + note("C4")).fast(2)', false],
    ['let beat = s("bd"); beat', false],
    ['let beat = s("bd"); let both = stack(beat, note("C4")); both', false],
  ] as const) {
    await replaceCode(page, `${receiver}.`);
    await editor.press("Control+Space");
    await expect(labels.filter({ hasText: /^gain$/ }), receiver).toBeVisible();
    await expect(labels.filter({ hasText: /^s$/ }), receiver).toHaveCount(offered ? 1 : 0);
    await editor.press("Escape");
  }
  // After a song, its own methods until it repeats; inside a section, the pattern's.
  const song = 'song(section("a", 4, s("bd")), part("p", "a"))';
  await replaceCode(page, `${song}.`);
  await editor.press("Control+Space");
  await expect(labels).toHaveText(["repeat"]);
  await editor.press("Escape");
  await replaceCode(page, `${song}.repeat().`);
  await editor.press("Control+Space");
  await expect(labels).toHaveCount(0);
  await replaceCode(page, 'song(section("a", 4, note("C4").');
  await editor.press("Control+Space");
  await expect(labels.filter({ hasText: /^s$/ })).toHaveCount(1);
  await expect(labels.filter({ hasText: /^repeat$/ })).toHaveCount(0);
  await editor.press("Escape");
  await replaceCode(page, 'note("C4").s("');
  await editor.press("Control+Space");
  await expect(labels).toHaveText(["bass", "burst", "pad", "ping", "pluck", "sawtooth", "triangle"]);
  await expect(page.locator(".cm-completionDetail").filter({ hasText: "(default)" })).toHaveText(["soft triangle tone (default)"]);
  await labels.filter({ hasText: /^pad$/ }).click();
  await expect.poll(() => readCode(page)).toBe('note("C4").s("pad');
  await replaceCode(page, 's("');
  await editor.press("Control+Space");
  await expect(labels).toHaveText(["bd", "burst", "cp", "hh", "oh", "ping", "sd"]);
  await expect(page.locator(".cm-completionDetail").filter({ hasText: "kick drum" })).toHaveCount(1);
});

const miniliveLanguage = LRLanguage.define({ parser });

// The labels completion offers at `|` in `source`, as if requested explicitly.
function offered(source: string, language: ScoreLanguage | null): string[] | null {
  const pos = source.indexOf("|");
  const state = EditorState.create({ doc: source.replace("|", ""), extensions: [miniliveLanguage] });
  ensureSyntaxTree(state, state.doc.length, 5000);
  const result = scoreCompletion(language)(new CompletionContext(state, pos, true)) as CompletionResult | null;
  return result ? result.options.map(option => option.label) : null;
}

test("completion offers each position's names from the vocabulary", () => {
  const language = { vocabulary: vocabulary(), methodsAfter };
  const patterns = ["s", "note", "chord", "silence", "stack"];
  for (const [source, expected] of [
    ["|", ["let", "$:", "bpm", "song", ...patterns]],
    ['let beat = s("bd");\n|', ["beat", "let", "$:", "bpm", "song", ...patterns]],
    ['let beat = s("bd");\nstack(|', ["beat", ...patterns]],
    ['$: (|', patterns],
    ["song(|", ["bpm", "section", "part", "part_id", "fill"]],
    ['song(section("a", 4, |', patterns],
    ['note("C4").jux(|', ["fast", "slow", "rev"]],
    ['note("C4").every(2, |', ["fast", "slow", "rev"]],
    ['note("C4").every(|', null],
    ['note("C4").pan(|', ["ramp", "sine", "cosine", "saw", "isaw", "tri", "square"]],
    ['note("C4").lpf(200, |', ["ramp", "sine", "cosine", "saw", "isaw", "tri", "square"]],
    ['note("C4").lpf(sine.range(0, |', null],
    ['note("C4").fast(|', null],
    ['s("|', ["bd", "sd", "cp", "hh", "oh", "ping", "burst"]],
    ['note("C4").s("|', ["triangle", "bass", "pad", "pluck", "sawtooth", "ping", "burst"]],
    ['note("|', null],
    ['note("C4").|', ["fast", "slow", "fadeIn", "fadeOut", "gate", "rev", "degradeBy", "lpf", "hpf", "attack", "hold", "release", "gain", "pan", "room", "begin", "end", "speed", "every", "jux", "s"]],
  ] as const) {
    expect(offered(source, language), source).toEqual(expected);
  }
});

test("completion inside a sound string continues across underscores and digits", () => {
  const language = { vocabulary: vocabulary(), methodsAfter };
  for (const source of ['s("piano_c|', 's("bd mbira_fs|', 'note("C4").s("kalimba_cs5|']) {
    const pos = source.indexOf("|");
    const state = EditorState.create({ doc: source.replace("|", ""), extensions: [miniliveLanguage] });
    ensureSyntaxTree(state, state.doc.length, 5000);
    const result = scoreCompletion(language)(new CompletionContext(state, pos, false)) as CompletionResult | null;
    const word = source.slice(0, pos).match(/[a-z][a-z0-9_]*$/)![0];
    expect(result?.from, source).toBe(pos - word.length);
    expect(result?.validFor instanceof RegExp && result.validFor.test(`${word}x`), source).toBe(true);
  }
});

test("before the score tools load, completion offers only bindings, let, and $:", () => {
  for (const [source, expected] of [
    ["|", ["let", "$:"]],
    ['let beat = s("bd");\n|', ["beat", "let", "$:"]],
    // Which call owns an argument is in the vocabulary.
    ['let beat = s("bd");\nstack(|', null],
    ['note("C4").|', null],
    ['s("|', null],
    ['note("C4").jux(|', null],
  ] as const) {
    expect(offered(source, null), source).toEqual(expected);
  }
});

test("a call snippet fills in its required arguments, quoting strings, and a declaration ends with ;", async ({ page }) => {
  await page.goto("/");
  await expect(page.locator("body")).toHaveAttribute("data-authoring", "ready");
  const editor = page.locator(".cm-content");
  const labels = page.locator(".cm-completionLabel");
  await replaceCode(page, "no");
  await editor.press("Control+Space");
  await labels.filter({ hasText: /^note$/ }).click();
  await expect.poll(() => readCode(page)).toBe('note("notes")');
  await replaceCode(page, 'note("C4").ev');
  await editor.press("Control+Space");
  await labels.filter({ hasText: /^every$/ }).click();
  await expect.poll(() => readCode(page)).toBe('note("C4").every(n, f)');
  await replaceCode(page, "bp");
  await editor.press("Control+Space");
  await labels.filter({ hasText: /^bpm$/ }).click();
  await expect.poll(() => readCode(page)).toBe("bpm(tempo);");
});
