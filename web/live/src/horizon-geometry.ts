// Functional core for the signal horizon's bar grid: where each bar and cycle
// tick goes and how strongly it is drawn, from canvas size and levels alone.

const BAR_PX = 3;
const GAP_PX = 2;
const TICK_SPACE_PX = 10;
// Enough bars for an 8K-wide canvas; callers size their level arrays to this.
export const MAX_BARS = 2048;

export type HorizonLayout = {
  center: number;
  reach: number;
  minHalf: number;
  barWidth: number;
  pitch: number;
  bars: number;
  offsetX: number;
};

/** Bar grid for a horizon canvas of `width` × `height` device pixels. */
export function horizonLayout(width: number, height: number, dpr: number): HorizonLayout {
  const center = (height - TICK_SPACE_PX * dpr) / 2;
  const pitch = (BAR_PX + GAP_PX) * dpr;
  const bars = Math.max(1, Math.min(MAX_BARS, Math.floor(width / pitch)));
  return {
    center,
    // Headroom keeps the loudest bars off the masthead above.
    reach: center - 6 * dpr,
    minHalf: 0.75 * dpr,
    barWidth: BAR_PX * dpr,
    pitch,
    bars,
    offsetX: width - bars * pitch + GAP_PX * dpr,
  };
}

/** Half-height and opacity of bar `bar` (0 = oldest) showing `level` in [0, 1]. */
export function barShape(
  layout: Pick<HorizonLayout, "bars" | "reach" | "minHalf">, level: number, bar: number, frozen: boolean,
): { half: number; alpha: number } {
  const { bars, reach, minHalf } = layout;
  const age = (bar + 1) / bars;
  return {
    half: minHalf + Math.pow(level, 1.15) * (reach - minHalf),
    alpha: (0.22 + 0.78 * Math.pow(age, 0.8)) * (0.5 + 0.5 * level) * (frozen ? 0.55 : 1),
  };
}

/** Cycle tick height and opacity; tick 2 marks every fourth cycle. */
export function tickShape(tick: number, frozen: boolean, dpr: number): { height: number; alpha: number } {
  const group = tick === 2;
  return { height: (group ? 7 : 4) * dpr, alpha: (group ? 0.9 : 0.4) * (frozen ? 0.6 : 1) };
}

/** Number of tone colours a horizon ramp provides. */
export const TONE_STEPS = 16;

/**
 * `TONE_STEPS` colours from `low` to `high` (`#rrggbb`), each as an opaque
 * `rgb()` and a softened `rgba()` for bar tips.
 */
export function toneRamp(low: string, high: string): { solid: string; soft: string }[] {
  const parse = (hex: string): number[] => {
    const value = parseInt(hex.slice(1), 16);
    return [value >> 16 & 255, value >> 8 & 255, value & 255];
  };
  const a = parse(low);
  const b = parse(high);
  return Array.from({ length: TONE_STEPS }, (_, step) => {
    const t = step / (TONE_STEPS - 1);
    const [r, g, bl] = a.map((channel, i) => Math.round(channel + (b[i] - channel) * t));
    return { solid: `rgb(${r}, ${g}, ${bl})`, soft: `rgba(${r}, ${g}, ${bl}, 0.6)` };
  });
}

/**
 * Ramp index for a tone in [0, 1]. A smoothstep pushes material toward either
 * end, so mixed passages commit to dark or bright instead of a muddy middle.
 */
export function toneStep(tone: number): number {
  const t = Math.max(0, Math.min(1, tone));
  const committed = t * t * (3 - 2 * t);
  return Math.round(committed * (TONE_STEPS - 1));
}
