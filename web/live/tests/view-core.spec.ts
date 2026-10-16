import { expect, test } from "@playwright/test";
import { MAX_BARS, barShape, horizonLayout, tickShape } from "../src/horizon-geometry";
import { canvasPixels, signalStats, triggerOffset } from "../src/signal-math";
import { ROW_H, TIME_H, midiAtY, needsResizeRender, plotPoint, scoreGeometry } from "../src/score-geometry";
import { longLinkNote } from "../src/score-link";

test("canvas backing stores follow the measured size, the capped pixel ratio, and size limits", () => {
  expect(canvasPixels(300.4, 46, 3, { maxDpr: 2 })).toEqual({ width: 601, height: 92, dpr: 2 });
  expect(canvasPixels(800, 52, 2, { maxDpr: 1.5, maxWidth: 640, maxHeight: 128 })).toEqual({ width: 640, height: 78, dpr: 1.5 });
  // A collapsed element still gets a drawable 1 × 1 canvas; a missing ratio counts as 1.
  expect(canvasPixels(0, 0, 0, { maxDpr: 2 })).toEqual({ width: 1, height: 1, dpr: 1 });
});

test("signal statistics report RMS only above the noise floor and triggers find a rising crossing", () => {
  expect(signalStats([0.5, -0.5, 0.5, -0.5])).toEqual({ rms: 0.5, peak: 0.5, live: true });
  expect(signalStats([0.001, -0.001])).toEqual({ rms: 0, peak: 0.001, live: false });
  expect(triggerOffset([0.2, -0.1, -0.3, 0.4, 0.1, -0.2], 2)).toBe(3);
  // A crossing that would leave fewer than `visible` samples is not used.
  expect(triggerOffset([0.2, 0.1, -0.3, 0.4], 2)).toBe(0);
});

test("horizon layout right-aligns whole bars and caps the bar count", () => {
  const layout = horizonLayout(1003, 120, 2);
  expect(layout.pitch).toBe(10);
  expect(layout.bars).toBe(100);
  // The newest bar ends flush with the right edge.
  expect(layout.offsetX + (layout.bars - 1) * layout.pitch + layout.barWidth).toBe(1003);
  expect(layout.center).toBe(50);
  expect(layout.reach).toBe(46);
  expect(horizonLayout(100_000, 40, 1).bars).toBe(MAX_BARS);

  const grid = { bars: 10, reach: 46, minHalf: 1.5 };
  const quiet = barShape(grid, 0, 9, false);
  const loud = barShape(grid, 1, 9, false);
  expect(quiet.half).toBe(1.5);
  expect(loud.half).toBe(46);
  expect(loud.alpha).toBeCloseTo(1, 6);
  expect(barShape(grid, 1, 0, false).alpha).toBeLessThan(loud.alpha);
  expect(barShape(grid, 1, 9, true).alpha).toBeCloseTo(0.55, 6);
  expect(tickShape(2, false, 2)).toEqual({ height: 14, alpha: 0.9 });
  expect(tickShape(1, true, 2)).toEqual({ height: 8, alpha: 0.4 * 0.6 });
});

test("the note grid shows an octave or more of headroom-padded rows inside the MIDI range", () => {
  // Half the viewBox width on screen doubles every pixel-sized margin.
  const wide = scoreGeometry(480, [52, 79]);
  expect(wide).toEqual({ pixelsToX: 2, plotLeft: 96, plotRight: 944, viewLow: 50, viewHigh: 81, plotHeight: TIME_H + 32 * ROW_H });
  // A narrow range still gets twelve rows; with nothing to show the grid centres on C4–G4.
  expect(scoreGeometry(960, [60])).toMatchObject({ viewLow: 58, viewHigh: 69 });
  expect(scoreGeometry(0, [])).toMatchObject({ pixelsToX: 1, viewLow: 58, viewHigh: 69 });
  // Near the top of the MIDI range the window shifts down instead of shrinking.
  expect(scoreGeometry(960, [126])).toMatchObject({ viewLow: 116, viewHigh: 127 });

  const geometry = scoreGeometry(960, [60]);
  expect(midiAtY(geometry, TIME_H + 0.5 * ROW_H)).toBe(69);
  expect(midiAtY(geometry, TIME_H + 3.5 * ROW_H)).toBe(66);
  expect(midiAtY(geometry, 10_000)).toBe(58);
  // A canvas drawn at half size maps pointer offsets back into viewBox units, clamped to the plot.
  expect(plotPoint(geometry, 240, 60, 480, 120)).toEqual({ x: 480, y: TIME_H + 120 });
  expect(plotPoint(geometry, -5, 999, 480, 120)).toEqual({ x: geometry.plotLeft, y: geometry.plotHeight - 1 });
});

test("only a width change or the first stage height re-renders a resized note grid", () => {
  expect(needsResizeRender({ width: 640, stageHeight: 300 }, { width: 640, stageHeight: 280 })).toBe(false);
  expect(needsResizeRender({ width: 600, stageHeight: 300 }, { width: 640, stageHeight: 300 })).toBe(true);
  expect(needsResizeRender({ width: 640, stageHeight: 300 }, { width: 640, stageHeight: 0 })).toBe(true);
  expect(needsResizeRender({ width: 640, stageHeight: 0 }, { width: 640, stageHeight: 0 })).toBe(false);
});

test("long links carry a warning", () => {
  expect(longLinkNote(8000)).toBe("");
  expect(longLinkNote(8001)).toContain("Download is safer");
});
