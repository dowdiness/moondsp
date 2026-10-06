import { expect, test } from "@playwright/test";
import { readFile } from "node:fs/promises";
import type * as OnsetTransport from "../../playback-onsets.js";

// Static Node imports treat this directly served worklet ES module as CommonJS.
const moduleSource = await readFile(new URL("../../playback-onsets.js", import.meta.url));
const { OnsetRing, ONSET_BYTES, ONSET_CAPACITY } = await import(
  `data:text/javascript;base64,${moduleSource.toString("base64")}`
) as typeof OnsetTransport;

// A producer adapter gives the real bounded transport a sequence of distinct
// source identities; these assertions cover overflow and playback-run isolation.
function producer(start: number, count: number) {
  return {
    player_onset_count: () => count,
    player_onset_field(index: number, field: number): number {
      if (field === 0) return index;
      if (field === 1) return 1;
      if (field === 2) return start + index;
      if (field === 4 || field === 5) return -1;
      return 0;
    },
    player_onset_clear() {},
    player_onset_dropped: () => 0,
  };
}

test("bounded onset observations retain newest identities and retire previous runs", () => {
  const buffer = new SharedArrayBuffer(ONSET_BYTES);
  const writer = new OnsetRing(buffer), reader = new OnsetRing(buffer);
  writer.write(producer(1, ONSET_CAPACITY + 17), 0, 10, 48000, 1);
  const current = reader.read(1).map(row => row[2]).sort((a, b) => a - b);
  expect(current).toEqual(Array.from({ length: ONSET_CAPACITY }, (_, index) => index + 18));
  expect(reader.statistics().overwritten).toBe(17);
  writer.write(producer(1000, 2), 0, 20, 48000, 1);
  writer.write(producer(2000, 2), 0, 30, 48000, 2);
  expect(reader.read(2).map(row => row[2]).sort((a, b) => a - b)).toEqual([2000, 2001]);
  expect(reader.read(1)).toEqual([]);
});
