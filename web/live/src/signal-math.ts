// Functional core for measured signal views: canvas backing-store sizing and the
// statistics the output scope and horizon act on. DOM measurement, drawing, and
// subscriptions stay in the calling shells.

export const SIGNAL_FLOOR = 0.0015;

export type CanvasPixels = { width: number; height: number; dpr: number };

/** Backing-store size for a canvas measured at `cssWidth` × `cssHeight` CSS pixels. */
export function canvasPixels(
  cssWidth: number, cssHeight: number, devicePixelRatio: number,
  limits: { maxDpr: number; maxWidth?: number; maxHeight?: number },
): CanvasPixels {
  const dpr = Math.min(devicePixelRatio || 1, limits.maxDpr);
  const width = Math.max(1, Math.min(limits.maxWidth ?? Infinity, Math.round(cssWidth * dpr)));
  const height = Math.max(1, Math.min(limits.maxHeight ?? Infinity, Math.round(cssHeight * dpr)));
  return { width, height, dpr };
}

export type SignalStats = { rms: number; peak: number; live: boolean };

/** RMS and peak of the first `count` samples; `live` when the peak clears the noise floor. */
export function signalStats(samples: ArrayLike<number>, count = samples.length): SignalStats {
  let sum = 0;
  let peak = 0;
  for (let i = 0; i < count; i++) {
    const value = samples[i];
    sum += value * value;
    if (Math.abs(value) > peak) peak = Math.abs(value);
  }
  const live = peak > SIGNAL_FLOOR;
  return { rms: live && count > 0 ? Math.sqrt(sum / count) : 0, peak, live };
}

/** First rising zero crossing that leaves `visible` samples to draw, or 0. */
export function triggerOffset(samples: ArrayLike<number>, visible: number): number {
  const limit = samples.length - visible;
  for (let i = 1; i < limit; i++) if (samples[i - 1] <= 0 && samples[i] > 0) return i;
  return 0;
}
