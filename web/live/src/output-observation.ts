import type { AudioEngine } from "./audio";
import type { Disposable } from "./scope";
import { analyseOutput, outputCadence, type OutputAnalysis, type OutputCadence } from "./signal-math";

// Imperative shell for watching the audio output: one clock reads the engine's
// post-master samples once per reading and hands the same analysed frame to
// every meter on screen. Meters only draw; when and how often to read is decided
// here, by outputCadence, from what the meters on screen need.

const SAMPLE_COUNT = 1024;
const READING_INTERVAL_MS: Readonly<Record<Exclude<OutputCadence, "stopped" | "frame">, number>> = {
  interval: 250,
  rest: 200,
};

/** One reading of the audio output. Its samples are reused by the next reading. */
export type OutputFrame = OutputAnalysis & Readonly<{
  /** The latest post-master samples; silence while the engine is not running. */
  samples: Float32Array;
  /** When the samples were read, in milliseconds of the page's clock. */
  time: number;
}>;

export type OutputMeter = Readonly<{
  /** Whether the meter is on screen; a meter off screen is not drawn. */
  onScreen(): boolean;
  /** Whether nothing the meter shows moves between readings, so they can slow down. */
  resting(): boolean;
  draw(frame: OutputFrame): void;
}>;

export type OutputObservation = Disposable & {
  /** Starts drawing `meter` with every reading; disposing the result stops it. */
  watch(meter: OutputMeter): Disposable;
  /** Reads and draws now, then re-decides how often to read: after a meter resizes, recolours, or comes on or off screen. */
  refresh(): void;
  /** Re-decides how often to read, after a meter may have started or stopped resting. */
  reconsider(): void;
};

export type OutputObservationHost = Readonly<{
  /** The window whose clock paces readings and whose page visibility pauses them. */
  page: Window;
  reducedMotion: MediaQueryList;
}>;

type PendingReading = Readonly<{ cadence: OutputCadence; cancel(): void }>;

export function mountOutputObservation(host: OutputObservationHost, engine: Pick<AudioEngine, "readWaveform">): OutputObservation {
  const { page, reducedMotion } = host;
  const samples = new Float32Array(SAMPLE_COUNT);
  const meters = new Set<OutputMeter>();
  let pending: PendingReading | null = null;

  const metersOnScreen = (): OutputMeter[] =>
    page.document.visibilityState === "visible" ? [...meters].filter(meter => meter.onScreen()) : [];

  function read(): OutputFrame {
    const sampleRate = engine.readWaveform(samples);
    return { samples, time: page.performance.now(), ...analyseOutput(samples, sampleRate) };
  }

  function readNow(): void {
    const onScreen = metersOnScreen();
    if (!onScreen.length) return;
    const frame = read();
    for (const meter of onScreen) meter.draw(frame);
  }

  function scheduledReading(): void {
    pending = null;
    readNow();
    scheduleNextReading();
  }

  function scheduleNextReading(): void {
    const onScreen = metersOnScreen();
    const cadence = outputCadence(onScreen.length, reducedMotion.matches, onScreen.every(meter => meter.resting()));
    if (pending?.cadence === cadence) return;
    pending?.cancel();
    pending = null;
    if (cadence === "stopped") return;
    if (cadence === "frame") {
      const id = page.requestAnimationFrame(scheduledReading);
      pending = { cadence, cancel: () => page.cancelAnimationFrame(id) };
    } else {
      const id = page.setTimeout(scheduledReading, READING_INTERVAL_MS[cadence]);
      pending = { cadence, cancel: () => page.clearTimeout(id) };
    }
  }

  function refresh(): void {
    readNow();
    scheduleNextReading();
  }

  page.document.addEventListener("visibilitychange", scheduleNextReading);
  reducedMotion.addEventListener("change", scheduleNextReading);

  return {
    watch(meter) {
      meters.add(meter);
      refresh();
      return {
        dispose() {
          meters.delete(meter);
          scheduleNextReading();
        },
      };
    },
    refresh,
    reconsider: scheduleNextReading,
    dispose() {
      meters.clear();
      pending?.cancel();
      pending = null;
      page.document.removeEventListener("visibilitychange", scheduleNextReading);
      reducedMotion.removeEventListener("change", scheduleNextReading);
    },
  };
}
