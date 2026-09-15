import { expect, test } from "@playwright/test";
import { readFileSync } from "node:fs";
import { buildParser } from "@lezer/generator";

const grammar = readFileSync(
  new URL("../src/lang/minilive.grammar", import.meta.url),
  "utf8",
);
const parser = buildParser(grammar);

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

test("MiniLive keeps number highlighting while the sign is edited", async ({ page }) => {
  const source = 'note("E4").pan(-0.45) + note("G4").pan(0.45)';
  await page.goto("/");
  const editor = page.locator(".cm-content");
  await editor.fill(source);
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
  await expect(editor).toHaveText(source.replace("-0.45", "0.45"));
  await expect.poll(numberTokens).toEqual([
    ["0.45", initialTokens[0][1]],
    ["0.45", initialTokens[0][1]],
  ]);

  await editor.pressSequentially("-");
  await expect(editor).toHaveText(source);
  await expect.poll(numberTokens).toEqual(initialTokens);

  await editor.pressSequentially("-");
  await expect(editor).toHaveText(source.replace("-0.45", "--0.45"));
  await editor.press("Backspace");
  await expect(editor).toHaveText(source);
  await expect.poll(numberTokens).toEqual(initialTokens);
});

test("MiniLive completes filters with cutoff and resonance arguments", async ({ page }) => {
  await page.goto("/");
  const editor = page.locator(".cm-content");
  await editor.fill('note("C4").');
  await editor.press("Control+Space");

  const labels = page.locator(".cm-completionLabel");
  await expect(labels.filter({ hasText: /^gain$/ })).toBeVisible();
  await expect(labels.filter({ hasText: /^lpf$/ })).toBeVisible();
  await expect(labels.filter({ hasText: /^hpf$/ })).toBeVisible();
  await labels.filter({ hasText: /^lpf$/ }).click();
  await expect(editor).toHaveText('note("C4").lpf(hz, resonance)');
});
