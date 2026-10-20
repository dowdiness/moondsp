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

/** RMS and peak of `samples`; `live` when the peak clears the noise floor. */
export function signalStats(samples: ArrayLike<number>): SignalStats {
  let sum = 0;
  let peak = 0;
  for (let i = 0; i < samples.length; i++) {
    const value = samples[i];
    sum += value * value;
    if (Math.abs(value) > peak) peak = Math.abs(value);
  }
  const live = peak > SIGNAL_FLOOR;
  return { rms: live ? Math.sqrt(sum / samples.length) : 0, peak, live };
}

/** First rising zero crossing that leaves `visible` samples to draw, or 0. */
export function triggerOffset(samples: ArrayLike<number>, visible: number): number {
  const limit = samples.length - visible;
  for (let i = 1; i < limit; i++) if (samples[i - 1] <= 0 && samples[i] > 0) return i;
  return 0;
}

/**
 * Tone colour of `samples` at `sampleRate` in [0, 1]: 0 is dark (low), 1 is
 * bright (high). One-pole low-passes at 150 Hz, 600 Hz, and 2.4 kHz split the
 * signal into four rough bands; the result is their energy-weighted mean band.
 * Energy weighting lets a loud kick under a quiet hi-hat stay dark. Silence
 * reads as 0.
 */
export function brightness(samples: ArrayLike<number>, sampleRate: number): number {
  const [a1, a2, a3] = [150, 600, 2400].map(hz => 1 - Math.exp(-2 * Math.PI * hz / sampleRate));
  let y1 = 0, y2 = 0, y3 = 0;
  let e0 = 0, e1 = 0, e2 = 0, e3 = 0;
  for (let i = 0; i < samples.length; i++) {
    const x = samples[i];
    y1 += a1 * (x - y1);
    y2 += a2 * (x - y2);
    y3 += a3 * (x - y3);
    const b1 = y2 - y1, b2 = y3 - y2, b3 = x - y3;
    e0 += y1 * y1; e1 += b1 * b1; e2 += b2 * b2; e3 += b3 * b3;
  }
  const total = e0 + e1 + e2 + e3;
  if (total <= 1e-12) return 0;
  return (e1 + 2 * e2 + 3 * e3) / (3 * total);
}

/** What one reading of the audio output shows: its level and its tone colour. */
export type OutputAnalysis = Readonly<{ stats: SignalStats; tone: number }>;

/**
 * Analyses post-master `samples` read at `sampleRate`. The sample rate is null
 * when the engine was not running, and the samples are then silence.
 */
export function analyseOutput(samples: ArrayLike<number>, sampleRate: number | null): OutputAnalysis {
  const stats = signalStats(samples);
  const sounding = stats.live && sampleRate !== null;
  return { stats, tone: sounding ? brightness(samples, sampleRate) : 0 };
}

export type OutputCadence = "stopped" | "interval" | "rest" | "frame";

/**
 * How often the audio output is read: never while no meter is on screen, at
 * the slow `interval` under reduced motion, at the `rest` rate while every meter
 * on screen is resting, and otherwise every animation frame.
 */
export function outputCadence(metersOnScreen: number, reducedMotion: boolean, allResting: boolean): OutputCadence {
  if (metersOnScreen === 0) return "stopped";
  if (reducedMotion) return "interval";
  return allResting ? "rest" : "frame";
}

/** Whether the horizon can rest between readings: its history is quiet, or frozen with nothing sounding. */
export function horizonResting(quiet: boolean, playing: boolean, live: boolean): boolean {
  return quiet || (!playing && !live);
}
