import { expect, test } from "@playwright/test";
import { MAX_BARS, barShape, horizonLayout, tickShape } from "../src/horizon-geometry";
import { analyseOutput, brightness, canvasPixels, outputCadence, signalStats, triggerOffset } from "../src/signal-math";
import { projectNotation, type NotationProjection } from "../src/notation-structure";
import { gridLayout, hitGrid } from "../src/note-grid-layout";
import { ROW_H, TIME_H, midiAtY, needsResizeRender, plotPoint, plotScale, revealScrollTop, scoreGeometry } from "../src/score-geometry";
import { advanceOnsets, soundingOnsets } from "../src/playback-observation";
import { sourceIsPlaying } from "../src/playback-highlights";
import { hitStrip, stripLayout } from "../src/structure-layout";
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

test("brightness orders tones by energy, so a loud kick under a quiet hi-hat stays dark", () => {
  const sine = (hz: number, gain = 1): number[] => Array.from({ length: 1024 }, (_, i) => gain * Math.sin(2 * Math.PI * hz * i / 48_000));
  const kick = brightness(sine(60), 48_000);
  const middle = brightness(sine(880), 48_000);
  const air = brightness(sine(6000), 48_000);
  expect(kick).toBeLessThan(0.15);
  expect(air).toBeGreaterThan(0.85);
  expect(middle).toBeGreaterThan(kick);
  expect(middle).toBeLessThan(air);
  const kickUnderHat = sine(60).map((value, i) => value + sine(6000, 0.15)[i]);
  expect(brightness(kickUnderHat, 48_000)).toBeLessThan(0.15);
  expect(brightness(new Array(1024).fill(0), 48_000)).toBe(0);
});

test("horizon layout right-aligns whole bars and caps the bar count", () => {
  const layout = horizonLayout(1003, 120, 2);
  expect(layout.pitch).toBe(10);
  expect(layout.bars).toBe(100);
  // The newest bar ends flush with the right edge.
  expect(layout.offsetX + (layout.bars - 1) * layout.pitch + layout.barWidth).toBe(1003);
  expect(layout.center).toBe(50);
  expect(layout.reach).toBe(38);
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

/** A phrase's steps as the editor reads them, in source order. */
function phrase(content: string): { structure: NotationProjection; steps: { from: number; to: number; end: number; value: string; rest: boolean; weight: number; node: number }[] } {
  const structure = projectNotation("note", content);
  const steps = structure.nodes.flatMap((node, index) => node.kind === "atom"
    ? [{ from: node.from, to: node.baseTo, end: node.end, value: node.value, rest: node.value === "~", weight: node.weight, node: index }] : []);
  return { structure, steps };
}

test("a pointer on the note grid takes the topmost edge, note, or rest under it", () => {
  // C4 fills 0–0.2, the rest 0.2–0.4, and D4 0.4–1 of a plot from x 48 to 952.
  const { structure, steps } = phrase("C4 ~ D4@3");
  const [c4, rest, d4] = steps.map(step => step.node);
  const layout = gridLayout({ structure, steps, notationKind: "note" }, plotScale(scoreGeometry(960, [60, 62]), 1));
  const c4Row = TIME_H + 9.5 * ROW_H, d4Row = TIME_H + 7.5 * ROW_H;
  const hit = (x: number, y: number) => {
    const result = hitGrid(layout, x, y);
    return result.kind === "edge" ? { edge: result.edge.side, node: result.note.node }
      : result.kind === "note" ? { note: result.note.node } : result.kind === "rest" ? { rest: result.rest.node } : null;
  };
  expect(hit(100, c4Row)).toEqual({ note: c4 });
  // C4's right grip lies over both its own end and the rest beyond it.
  expect(hit(226, c4Row)).toEqual({ edge: "right", node: c4 });
  expect(hit(231, c4Row)).toEqual({ edge: "right", node: c4 });
  expect(hit(300, TIME_H + 1)).toEqual({ rest });
  // D4's left grip is on D4's row only; elsewhere its column is the rest's.
  expect(hit(407, d4Row)).toEqual({ edge: "left", node: d4 });
  expect(hit(407, c4Row)).toEqual({ rest });
  expect(hit(600, c4Row)).toBeNull();
});

test("a pointer on the structure strip takes a boundary first, then the nearest source or group", () => {
  const { structure, steps } = phrase("C4 [D4 E4]");
  const [c4, d4, e4] = steps.map(step => step.node);
  const wide = stripLayout({ structure, steps }, plotScale(scoreGeometry(960, []), 1), 32);
  // The group takes the top row; sources and boundaries share the row below it.
  expect(wide.sourceRow).toBe(1);
  expect(hitStrip(wide, 510, 48)).toMatchObject({ kind: "boundary", boundary: { node: c4 } });
  expect(hitStrip(wide, 600, 48)).toEqual({ kind: "select", node: d4 });
  expect(hitStrip(wide, 760, 48)).toEqual({ kind: "select", node: e4 });
  expect(hitStrip(wide, 600, 16)).toEqual({ kind: "select", node: structure.nodes.findIndex(node => node.kind === "group") });
  expect(hitStrip(wide, 100, 16)).toBeNull();

  // At 200 px, eight groups are narrower than their 44 px targets, which overlap.
  const narrowPhrase = phrase("[C4] [D4] [E4] [F4] [G4] [A4] [B4] [C5]");
  const groups = narrowPhrase.structure.nodes.flatMap((node, index) => node.kind === "group" ? [index] : []);
  const narrow = stripLayout(narrowPhrase, plotScale(scoreGeometry(200, []), 1), 32);
  // x 480 is inside the third group and under the fourth's target, which is drawn later.
  expect(hitStrip(narrow, 480, 16)).toEqual({ kind: "select", node: groups[2] });
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

test("a late onset batch jumps to its newest due group and holds it until a later onset is due", () => {
  const onset = (audio: number, at: number) => ({ at, fields: [audio] });
  // Arrives out of audio order; 0.5 and 1 are both due, 2 is not yet.
  const { pending, latest } = advanceOnsets([], [onset(1, 10), onset(2, 20), onset(0.5, 5), onset(1, 10)], -Infinity, 12);
  expect(latest).toBe(1);
  expect(pending.map(item => item.fields[0])).toEqual([1, 1, 2]);
  expect(soundingOnsets(pending, latest, 12)).toHaveLength(2);
  expect(soundingOnsets(pending, latest, 19)).toHaveLength(2);
  expect(advanceOnsets(pending, [], latest, 20).latest).toBe(2);
});

test("a note block plays only for its own onset and pitch; a span without a note plays for any onset in it", () => {
  const pulse = { from: 5, to: 20, references: [], notation: { from: 8, to: 12, start: 0.5, pitch: 60 } };
  const note = { literalFrom: 8, literalTo: 12, start: 0.5, pitch: 60 };
  expect(sourceIsPlaying({ from: 5, to: 20, note }, [pulse])).toBe(true);
  expect(sourceIsPlaying({ from: 5, to: 20, note: { ...note, start: 0 } }, [pulse])).toBe(false);
  expect(sourceIsPlaying({ from: 5, to: 20, note: { ...note, pitch: 64 } }, [pulse])).toBe(false);
  expect(sourceIsPlaying({ from: 5, to: 20, note: null }, [pulse])).toBe(true);
  expect(sourceIsPlaying({ from: 5, to: 21, note: null }, [pulse])).toBe(false);
});

test("the score scrolls only when a target leaves its margin, and then centres it", () => {
  expect(revealScrollTop(150, 20, 100, 200)).toBeNull();
  expect(revealScrollTop(119, 20, 100, 200)).toBe(19);
  expect(revealScrollTop(281, 20, 100, 200)).toBe(181);
  expect(revealScrollTop(30, 50, 10, 200)).toBe(0);
});

test("the output is read every frame unless no meter is on screen, motion is reduced, or every meter rests", () => {
  expect(outputCadence(0, false, false)).toBe("stopped");
  expect(outputCadence(0, true, true)).toBe("stopped");
  expect(outputCadence(2, true, false)).toBe("interval");
  expect(outputCadence(2, false, true)).toBe("rest");
  expect(outputCadence(2, false, false)).toBe("frame");
});

test("a stopped engine's silence has no tone, and a sounding output is coloured at its own sample rate", () => {
  expect(analyseOutput(new Float32Array(1024), null)).toEqual({ stats: { rms: 0, peak: 0, live: false }, tone: 0 });
  const air = Array.from({ length: 1024 }, (_, i) => 0.5 * Math.sin(2 * Math.PI * 6000 * i / 48_000));
  const { stats, tone } = analyseOutput(air, 48_000);
  expect(stats.live).toBe(true);
  expect(tone).toBe(brightness(air, 48_000));
  expect(tone).toBeGreaterThan(0.5);
});
