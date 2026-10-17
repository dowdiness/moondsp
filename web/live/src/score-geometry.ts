// Functional core for the note grid's coordinate system: which pitch rows are
// shown, where the plot sits in the fixed-width viewBox, and how measured sizes
// and pointer positions map into it. The note grid and structure strip measure and draw.

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
 * which measured `width` × `height`) in viewBox units: where the pointer is
 * over the drawing.
 */
export function viewBoxPoint(
  geometry: ScoreGeometry, offsetX: number, offsetY: number, width: number, height: number,
): { x: number; y: number } {
  return {
    x: offsetX * W / Math.max(1, width),
    y: TIME_H + offsetY * (geometry.plotHeight - TIME_H) / Math.max(1, height),
  };
}

/** The pointer offset as `viewBoxPoint` maps it, clamped to the plot: what it edits. */
export function plotPoint(
  geometry: ScoreGeometry, offsetX: number, offsetY: number, width: number, height: number,
): { x: number; y: number } {
  const { x, y } = viewBoxPoint(geometry, offsetX, offsetY, width, height);
  return {
    x: Math.max(geometry.plotLeft, Math.min(geometry.plotRight, x)),
    y: Math.max(TIME_H, Math.min(geometry.plotHeight - 1, y)),
  };
}

/** The grid's scales for a phrase lasting `span` cycles. */
export type PlotScale = Readonly<{
  geometry: ScoreGeometry;
  /** The x of a fraction of the plot's width. */
  fraction(at: number): number;
  /** The x of a notation time, clamped to the phrase. */
  time(at: number): number;
  /** The notation time at `x`. */
  timeAt(x: number): number;
  /** A length of CSS pixels in viewBox x units. */
  px(pixels: number): number;
  /** The centre y of a pitch row. */
  y(midi: number): number;
}>;

export function plotScale(geometry: ScoreGeometry, span: number): PlotScale {
  const width = geometry.plotRight - geometry.plotLeft;
  const fraction = (at: number): number => geometry.plotLeft + width * at;
  const shown = Math.max(1, span);
  return {
    geometry,
    fraction,
    time: at => fraction(Math.max(0, Math.min(shown, at)) / shown),
    timeAt: x => (x - geometry.plotLeft) * span / width,
    px: pixels => pixels * geometry.pixelsToX,
    y: midi => TIME_H + (geometry.viewHigh - midi + .5) * ROW_H,
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
