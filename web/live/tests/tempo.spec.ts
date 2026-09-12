import { expect, test } from "@playwright/test";
import {
  commitTempo,
  committedTempo,
  editTempo,
  receiveTempo,
  Tempo,
  tempoText,
} from "../src/tempo";

test("Tempo decodes the runtime range rather than the manual input minimum", () => {
  expect(Tempo.decode(72.5)?.value).toBe(72.5);
  expect(Tempo.decode(0.001)?.value).toBe(0.001);
  expect(Tempo.decode(1000)?.value).toBe(1000);
  expect(Tempo.decode(0.0009)).toBeNull();
  expect(Tempo.decode(1001)).toBeNull();
  expect(Tempo.decode(0)).toBeNull();
  expect(Tempo.decode(Number.NaN)).toBeNull();
  expect(Tempo.decode(Number.POSITIVE_INFINITY)).toBeNull();
  expect(Tempo.decode("72.5")).toBeNull();
});

test("Tempo input parses the full decimal and normalizes below-minimum values", () => {
  expect(Tempo.parseInput(" 72.5 ")).toMatchObject({ kind: "parsed", tempo: { value: 72.5 } });
  expect(Tempo.parseInput("0.5")).toMatchObject({ kind: "parsed", tempo: { value: 1 } });
  expect(Tempo.parseInput("-20")).toMatchObject({ kind: "parsed", tempo: { value: 1 } });
  expect(Tempo.parseInput(" ")).toEqual({ kind: "empty" });
});

test("Tempo input rejects suffixes, non-finite values, overflow, and non-decimal notation", () => {
  for (const text of ["72bpm", "NaN", "Infinity", "1e309", "-1e309", "0x40", "1001"]) {
    expect(Tempo.parseInput(text)).toMatchObject({ kind: "invalid" });
  }
});

test("tempo fields preserve drafts for same-value receipts and sync changed values", () => {
  const initial: { kind: "displaying"; tempo: Tempo } = { kind: "displaying", tempo: Tempo.DEFAULT };
  const draft = editTempo(initial, "72.");
  expect(committedTempo(draft).value).toBe(Tempo.DEFAULT.value);
  expect(tempoText(draft)).toBe("72.");
  const repeated = receiveTempo(draft, Tempo.DEFAULT);
  expect(tempoText(repeated)).toBe("72.");
  expect(committedTempo(repeated).value).toBe(Tempo.DEFAULT.value);

  const changed = Tempo.decode(72.5);
  if (changed === null) throw new Error("test fixture should decode");
  const synchronized = receiveTempo(draft, changed);
  expect(tempoText(synchronized)).toBe("72.5");
  expect(committedTempo(synchronized).value).toBe(72.5);
});

test("tempo commits accept parsed values and restore the committed value on failure", () => {
  const initial: { kind: "displaying"; tempo: Tempo } = { kind: "displaying", tempo: Tempo.DEFAULT };

  expect(commitTempo(editTempo(initial, "72.5"))).toMatchObject({
    kind: "committed",
    tempo: { value: 72.5 },
    field: { kind: "displaying", tempo: { value: 72.5 } },
  });
  expect(commitTempo(editTempo(initial, "0"))).toMatchObject({
    kind: "committed",
    tempo: { value: 1 },
  });
  expect(commitTempo(editTempo(initial, ""))).toMatchObject({
    kind: "restored",
    field: { kind: "displaying", tempo: Tempo.DEFAULT },
    reason: "empty",
  });
  expect(commitTempo(editTempo(initial, "72bpm"))).toMatchObject({
    kind: "restored",
    field: { kind: "displaying", tempo: Tempo.DEFAULT },
    reason: "invalid",
  });
});
