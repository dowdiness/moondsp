import { expect, test } from "@playwright/test";
import { chordParts, chordPitches, spellChord } from "../src/chord-model";

test("lowering a chord third spells the exact minor chord", () => {
  expect(chordPitches("C")).toEqual([60, 64, 67]);
  expect(spellChord([60, 63, 67], "C")).toBe("Cm");
});


test("explicit pitch atoms compile exactly and malformed atoms are rejected", () => {
  expect(chordPitches("{60,63,67}")).toEqual([60, 63, 67]);
  for (const atom of ["{}", "{60, 63}", "{60,60}", "{67,60}", "{128}"]) {
    expect(chordPitches(atom), atom).toBeNull();
  }
});
test("unmatched inversions and spreads remain explicit pitch sets", () => {
  expect(spellChord([64, 67, 72], "C")).toBe("{64,67,72}");
  expect(spellChord([60, 67, 76], "C")).toBe("{60,67,76}");
});

test("no-op edits retain the original quality alias and spelling", () => {
  const pitches = chordPitches("Dbmin73");
  expect(pitches).not.toBeNull();
  expect(spellChord(pitches!, "Dbmin73")).toBe("Dbmin73");
});

test("whole-chord transposition preserves a quality alias and prefers original flats", () => {
  const pitches = chordPitches("Dbmin73");
  expect(pitches).not.toBeNull();
  expect(spellChord(pitches!.map(pitch => pitch + 2), "Dbmin73")).toBe("Ebmin73");
  expect(spellChord([63, 66, 70, 73], "Dbmin704")).toBe("Ebmin74");
});

test("register spelling includes octave zero and the upper MIDI boundary", () => {
  expect(spellChord([12, 16, 19], "C4")).toBe("C0");
  expect(spellChord([120, 124, 127], "C4")).toBe("C09");
  expect(spellChord([0, 4, 7], "C4")).toBe("{0,4,7}");
  expect(spellChord([0], "C4")).toBe("{0}");
  expect(spellChord([127], "C4")).toBe("{127}");
});

test("removing the final chord tone yields a rest", () => {
  expect(spellChord([], "C")).toBe("~");
  expect(chordPitches("~")).toEqual([]);
});

test("invalid and duplicate edited pitches are rejected", () => {
  for (const pitches of [[-1], [128], [60.5], [60, 60]]) {
    expect(() => spellChord(pitches, "C")).toThrow(RangeError);
  }
});

test("explicit pitch atoms do not expose named-chord parts", () => {
  expect(chordParts("{60,63,67}")).toBeNull();
});
