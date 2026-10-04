import { expect, test } from "@playwright/test";
import { readFileSync } from "node:fs";
import { buildParser } from "@lezer/generator";
import { auditionSource, transposePitch } from "../src/pattern-audition";

const grammar = readFileSync(new URL("../src/lang/minilive.grammar", import.meta.url), "utf8");
const parser = buildParser(grammar);
function audition(doc: string, patternFrom: number, stepFrom: number): string | null {
  return auditionSource(doc, patternFrom, stepFrom, parser.parse(doc));
}

test("transposePitch follows MIDI semitones and preserves numeric spelling", () => {
  expect(transposePitch("60", 2)).toBe("62");
  expect(transposePitch("60.5", -1)).toBe("59.5");
  expect(transposePitch("G4", 2)).toBe("A4");
  expect(transposePitch("Bb4", 1)).toBe("B4");
  expect(transposePitch("C#4", 1)).toBe("D4");
  expect(transposePitch("B#4", 0)).toBe("C5");
  expect(transposePitch("Cb4", 0)).toBe("B3");
  expect(transposePitch("C", 1)).toBe("C#4");
});

test("transposePitch rejects invalid pitches and values outside the conventional MIDI key range", () => {
  for (const pitch of ["~", "", "H4", "C#b4", "128", "-1", "127.1", "C-2"]) {
    expect(transposePitch(pitch, 0), pitch).toBeNull();
  }
  expect(transposePitch("127", 1)).toBeNull();
  expect(transposePitch("C-1", -1)).toBeNull();
  expect(transposePitch("60", 0.5)).toBeNull();
});

test("auditionSource uses UTF-16 source offsets across Unicode comments and multiline strings", () => {
  const doc = '/* 🎹 */\nlet motif = note("C4");\n$: note("C4\nG4").gain(0.4)\n$: note("D4")';
  const from = doc.indexOf('note("C4\nG4")');
  const step = doc.indexOf("G4", from);
  expect(audition(doc, from, step)).toBe('let motif = note("C4");\nnote("G4").gain(0.4)');
});

test("auditionSource also resolves a chain inside a binding at an absolute offset", () => {
  const doc = '/* 🎹 */\nlet melody = note("C4 G4").gain(0.5);\n$: note("D4")';
  const from = doc.indexOf('note("C4 G4")');
  const step = doc.indexOf("G4", from);
  expect(audition(doc, from, step)).toBe('let melody = note("C4 G4").gain(0.5);\nnote("G4").gain(0.5)');
});
test("auditionSource retains ordered declarations and selected chain modifiers only", () => {
  const doc = 'bpm(90);\nlet bass = note("C3").slow(2);\n$: note("C4") + s("bd sd").fast(2).gain(0.5)\n$: note("D4").room(0.7)';
  const from = doc.indexOf('s("bd sd")');
  const step = doc.indexOf("sd", from);
  const result = audition(doc, from, step);
  expect(result).toBe('bpm(90);\nlet bass = note("C3").slow(2);\ns("sd").fast(2).gain(0.5)');
});

test("auditionSource rejects rests, stale offsets, unsupported targets, and malformed selected chains", () => {
  const rest = '$: note("C4 ~ G4")';
  const restFrom = rest.indexOf('note(');
  expect(audition(rest, restFrom, rest.indexOf("~"))).toBeNull();
  expect(audition(rest, restFrom, rest.indexOf("G4") + 1)).toBeNull();

  for (const source of ['$: chord("Cm")', '$: note("C4/2")', '$: s("snare")', '$: note("C4", 60)']) {
    const start = source.indexOf(source.includes("chord") ? "chord(" : source.includes("s(") ? "s(" : "note(");
    const token = source.indexOf('"') + 1;
    expect(audition(source, start, token), source).toBeNull();
  }
  expect(audition('$: note("C4").gain(', 3, 9)).toBeNull();
});
