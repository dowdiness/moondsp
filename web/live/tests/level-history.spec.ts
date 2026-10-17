import { expect, test } from "@playwright/test";
import { HISTORY_SLOTS, SLOT_MS, barLevels, createLevelHistory, markCycle, pushLevel } from "../src/level-history";

function newest(values: Float32Array, head: number, count: number): number[] {
  return Array.from({ length: count }, (_, i) => values[(head - count + i + HISTORY_SLOTS) % HISTORY_SLOTS]);
}

test("level history interpolates missed slots and freezes while the transport is stopped", () => {
  const history = createLevelHistory();
  pushLevel(history, 0, 1000, true);
  pushLevel(history, 1, 1000 + 5 * SLOT_MS, true);
  expect(newest(history.values, history.head, 5).map(value => Number(value.toFixed(3)))).toEqual([0.2, 0.4, 0.6, 0.8, 1]);

  const head = history.head;
  pushLevel(history, 0.5, 5000, false);
  expect(history.head).toBe(head);
  // Resuming after the pause does not backfill the stopped interval.
  pushLevel(history, 0.5, 5000 + SLOT_MS, true);
  expect(history.head).toBe((head + 1) % HISTORY_SLOTS);
});

test("a gap longer than a second is skipped instead of drawn as an interpolated ramp", () => {
  const history = createLevelHistory();
  pushLevel(history, 0, 1000, true);
  pushLevel(history, 0.2, 1000 + SLOT_MS, true);
  const head = history.head;
  // A hidden tab resumes eight seconds later: one slot at the new level, no ramp.
  pushLevel(history, 1, 9000, true);
  expect(history.head).toBe((head + 1) % HISTORY_SLOTS);
  expect(newest(history.values, history.head, 3).map(value => Number(value.toFixed(3)))).toEqual([0, 0.2, 1]);
  pushLevel(history, 1, 9000 + 2 * SLOT_MS, true);
  expect(history.head).toBe((head + 3) % HISTORY_SLOTS);
});

test("reduced-motion redraws every 250 ms fill every slot they span", () => {
  const history = createLevelHistory();
  pushLevel(history, 0.5, 1000, true);
  // Timer jitter puts each redraw just past 250 ms; each still fills 12 or 13 slots.
  for (let draw = 1; draw <= 8; draw++) pushLevel(history, 0.5, 1000 + draw * 250.4, true);
  expect(history.head).toBe(Math.floor(8 * 250.4 / SLOT_MS));
});

test("bar levels map the tracked peak over 30 dB with a short release", () => {
  const silent = createLevelHistory();
  const levels = new Float32Array(10);
  const ticks = new Uint8Array(10);
  expect(barLevels(silent, 10, levels, ticks)).toBe(true);
  expect(Array.from(levels)).toEqual(new Array(10).fill(0));

  // One loud slot, then a quieter level for 40 slots: the newest bars sit at
  // the quiet level relative to the decayed peak, independent of the old hit.
  const history = createLevelHistory();
  pushLevel(history, 0, 1000, true);
  pushLevel(history, 1, 1000 + SLOT_MS, true);
  for (let slot = 2; slot <= 41; slot++) pushLevel(history, 0.1, 1000 + slot * SLOT_MS, true);
  expect(barLevels(history, 10, levels, ticks)).toBe(false);
  const peak = Math.pow(0.5, (40 * SLOT_MS) / 3000);
  const expected = (20 * Math.log10(0.1 / peak) + 30) / 30;
  expect(levels[9]).toBeCloseTo(expected, 4);

  // A single hit followed by silence decays by the per-bar release.
  const hit = createLevelHistory();
  pushLevel(hit, 0, 1000, true);
  for (let slot = 1; slot <= 14; slot++) pushLevel(hit, slot === 7 ? 1 : 0, 1000 + slot * SLOT_MS, true);
  barLevels(hit, 10, levels, ticks);
  const loud = Array.from(levels).findIndex(level => level === 1);
  expect(loud).toBeGreaterThan(0);
  expect(levels[loud + 1]).toBeCloseTo(0.86, 5);
  expect(levels[loud + 2]).toBeCloseTo(0.86 * 0.86, 5);
});

test("cycle boundaries mark the next slot, with every fourth cycle grouped", () => {
  const history = createLevelHistory();
  const levels = new Float32Array(10);
  const ticks = new Uint8Array(10);
  pushLevel(history, 0, 1000, true);
  markCycle(history, 3);
  pushLevel(history, 0.1, 1000 + 2 * SLOT_MS, true);
  markCycle(history, 4);
  pushLevel(history, 0.1, 1000 + 4 * SLOT_MS, true);
  barLevels(history, 10, levels, ticks);
  // Two slots per bar: the cycle-3 boundary lands in bar 8, the group boundary in bar 9.
  expect(Array.from(ticks.subarray(8))).toEqual([1, 2]);
  expect(Array.from(ticks.subarray(0, 8))).toEqual(new Array(8).fill(0));
});
