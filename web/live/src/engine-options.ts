import type { AudioEngineOptions } from "./audio";

// Functional core for the page's URL switches: developer and test options for
// the audio engine, decided from the query string alone.

function positiveInteger(params: URLSearchParams, name: string, fallback: string): number | undefined {
  const value = Number.parseInt(params.get(name) ?? fallback, 10);
  return Number.isFinite(value) && value > 0 ? value : undefined;
}

export function engineOptions(params: URLSearchParams): AudioEngineOptions {
  const latencyHint = params.get("latencyHint");
  const native = params.get("nativeSampleRate");
  return {
    sampleRate: native === "1" || native === "true" ? undefined : positiveInteger(params, "sampleRate", "48000") ?? 48000,
    latencyHint: latencyHint === "interactive" || latencyHint === "balanced" || latencyHint === "playback" ? latencyHint : undefined,
    enableOnsets: params.get("onsets") !== "0",
  };
}
