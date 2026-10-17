// Functional core for the note grid's coordinate system: which pitch rows are
// shown, where the plot sits in the fixed-width viewBox, and how measured sizes
// and pointer positions map into it. moving-score measures and draws.

/** The note grid's viewBox width; measured widths only scale text and hit areas. */
export const W = 960;
export const ROW_H = 20;
export const TIME_H = 24;
/** The pitch-label column left of the plot, in CSS pixels; pointers there edit nothing. */
export const PLOT_LEFT_PX = 48;

export type ScoreGeometry = Readonly<{
  /** viewBox units per CSS pixel. */
  pixelsToX: number;
  plotLeft: number;
  plotRight: number;
  viewLow: number;
  viewHigh: number;
  plotHeight: number;
}>;

export function boundedPitch(midi: number, low = 0, high = 127): number {
  return Math.max(low, Math.min(high, Math.round(midi)));
}

/**
 * The grid for a canvas measured at `measuredWidth` CSS pixels (0 before layout)
 * showing `pitches`: at least an octave of rows with two rows of headroom on
 * each side, inside the MIDI range.
 */
export function scoreGeometry(measuredWidth: number, pitches: readonly number[]): ScoreGeometry {
  const pixelsToX = W / (measuredWidth || W);
  const lowest = pitches.length ? Math.min(...pitches) : 60;
  const highest = pitches.length ? Math.max(...pitches) : 67;
  const viewLow = Math.max(0, Math.min(116, lowest - 2));
  const viewHigh = Math.min(127, Math.max(viewLow + 11, highest + 2));
  return {
    pixelsToX,
    plotLeft: PLOT_LEFT_PX * pixelsToX,
    plotRight: W - 8 * pixelsToX,
    viewLow,
    viewHigh,
    plotHeight: TIME_H + (viewHigh - viewLow + 1) * ROW_H,
  };
}

/** The pitch row under viewBox `y`, clamped to the visible rows. */
export function midiAtY(geometry: ScoreGeometry, y: number): number {
  return boundedPitch(geometry.viewHigh - Math.floor((y - TIME_H) / ROW_H), geometry.viewLow, geometry.viewHigh);
}

/**
 * A pointer offset (`offsetX`, `offsetY` CSS pixels from the canvas's top left,
 * which measured `width` × `height`) mapped into the plot and clamped to it.
 */
export function plotPoint(
  geometry: ScoreGeometry, offsetX: number, offsetY: number, width: number, height: number,
): { x: number; y: number } {
  const { plotLeft, plotRight, plotHeight } = geometry;
  return {
    x: Math.max(plotLeft, Math.min(plotRight, offsetX * W / Math.max(1, width))),
    y: Math.max(TIME_H, Math.min(plotHeight - 1, TIME_H + offsetY * (plotHeight - TIME_H) / Math.max(1, height))),
  };
}

export type GridSize = Readonly<{ width: number; stageHeight: number }>;

/**
 * Whether a measured resize needs a full re-render: only a width change alters
 * the projection, and the first non-zero stage height enables selection scrolling.
 * Height changes caused by the render itself need nothing.
 */
export function needsResizeRender(measured: GridSize, rendered: GridSize): boolean {
  return measured.width !== rendered.width || (rendered.stageHeight === 0 && measured.stageHeight > 0);
}
