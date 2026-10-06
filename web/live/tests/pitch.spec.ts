import { expect, test } from "@playwright/test";
import { midiValue, transposePitch } from "../src/pitch";

test("midiValue parses numeric and chromatic pitches at MIDI boundaries", () => {
  expect(midiValue("60")).toEqual({ midi: 60, numeric: true, flat: false });
  expect(midiValue("60.5")?.midi).toBe(60.5);
  expect(midiValue("G4")?.midi).toBe(67);
  expect(midiValue("Bb4")).toEqual({ midi: 70, numeric: false, flat: true });
  expect(midiValue("B#4")?.midi).toBe(72);
  expect(midiValue("Cb4")?.midi).toBe(59);
  expect(midiValue("C")?.midi).toBe(60);
  expect(midiValue("C-1")?.midi).toBe(0);
  expect(midiValue("G9")?.midi).toBe(127);
});

test("midiValue rejects invalid pitches and values outside the conventional MIDI key range", () => {
  for (const pitch of ["~", "", "H4", "C#b4", "128", "-1", "127.1", "C-2", "G#9"]) {
    expect(midiValue(pitch), pitch).toBeNull();
  }
});

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
