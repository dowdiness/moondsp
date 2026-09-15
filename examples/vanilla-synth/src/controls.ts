export type Phase = "idle" | "loading" | "suspended" | "resuming" | "running" | "error" | "disposing" | "disposed";

export interface ControlState {
  readonly phase: Phase;
  readonly errorText: string;
}

const PHASE_TEXT = {
  idle: "Audio off",
  loading: "Loading…",
  suspended: "Audio paused",
  resuming: "Resuming…",
  running: "Audio on",
  error: "Unavailable",
  disposing: "Turning off…",
  disposed: "Audio off",
} satisfies Record<Phase, string>;

export function controlView(state: ControlState) {
  const busy = state.phase === "loading" || state.phase === "resuming" || state.phase === "disposing";
  const powered = busy || state.phase === "running";
  return {
    status: PHASE_TEXT[state.phase],
    label: powered ? "Power off" : "Power on",
    name: powered ? "Power off audio" : "Power on audio",
    powerAction: powered ? "off" : "on",
    busy,
    powerDisabled: state.phase === "disposing",
    inputsDisabled: state.phase !== "running",
    errorVisible: state.phase === "error",
  };
}

const CUTOFF_MIN_HZ = 120;
const CUTOFF_MAX_HZ = 12_000;

export function volumeFromInput(value: number): number {
  return Math.min(1, Math.max(0, value));
}

export function cutoffFromInput(value: number): number {
  return CUTOFF_MIN_HZ * (CUTOFF_MAX_HZ / CUTOFF_MIN_HZ) ** volumeFromInput(value);
}

export function cutoffPosition(value: number): number {
  return Math.log(value / CUTOFF_MIN_HZ) / Math.log(CUTOFF_MAX_HZ / CUTOFF_MIN_HZ);
}

export function errorMessage(detail: string): string {
  return /AudioContext|AudioWorklet|Wasm|wasm/i.test(detail)
    ? `${detail} Use a browser with AudioWorklet and WebAssembly support, then choose Power on to retry.`
    : `${detail} Check that this example is served by Vite with its package assets, then choose Power on to retry.`;
}
