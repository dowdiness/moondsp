import type { AudioEngineMode, AudioEngineOptions } from "./audio";

// Functional core for the page's URL switches: developer and test options for
// the audio engine, decided from the query string alone.

export type EngineOptions = AudioEngineOptions & { mode: AudioEngineMode };

function flag(params: URLSearchParams, name: string): boolean {
  const value = params.get(name);
  return value === "1" || value === "true";
}

function positiveInteger(params: URLSearchParams, name: string, fallback: string): number | undefined {
  const value = Number.parseInt(params.get(name) ?? fallback, 10);
  return Number.isFinite(value) && value > 0 ? value : undefined;
}

export function engineOptions(params: URLSearchParams): EngineOptions {
  const latencyHint = params.get("latencyHint");
  return {
    enableTelemetry: flag(params, "telemetry"),
    enableSchedulerTiming: flag(params, "schedulerTiming"),
    schedulerTimingBatchSize: positiveInteger(params, "schedulerTimingBatch", "128"),
    sampleRate: flag(params, "nativeSampleRate") ? undefined : positiveInteger(params, "sampleRate", "48000") ?? 48000,
    latencyHint: latencyHint === "interactive" || latencyHint === "balanced" || latencyHint === "playback" ? latencyHint : undefined,
    mode: params.get("audioMode") === "compiled" ? "compiled" : "scheduler",
    enableOnsets: params.get("onsets") !== "0",
  };
}
