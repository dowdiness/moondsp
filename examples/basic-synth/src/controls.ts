export type Phase = "idle" | "loading" | "suspended" | "resuming" | "running" | "error" | "disposing" | "disposed";

export interface ControlState {
  readonly phase: Phase;
  readonly errorText: string;
  readonly hasContext: boolean;
  readonly canControl: boolean;
}

const PHASE_TEXT = {
  idle: { status: "Loading…", label: "Power on", name: "Power on audio" },
  loading: { status: "Loading…", label: "Loading…", name: "Loading audio" },
  suspended: { status: "Ready", label: "Start", name: "Start audio" },
  resuming: { status: "Starting…", label: "Starting…", name: "Starting audio" },
  running: { status: "Audio on", label: "On", name: "Audio on" },
  error: { status: "Unavailable", label: "Retry", name: "Retry audio" },
  disposing: { status: "Turning off…", label: "Turning off…", name: "Turning off audio" },
  disposed: { status: "Audio off", label: "Power on", name: "Power on audio" },
} satisfies Record<Phase, { status: string; label: string; name: string }>;

export function controlView(state: ControlState, notesHeld: boolean) {
  const busy = state.phase === "loading" || state.phase === "resuming" || state.phase === "disposing";
  return {
    ...PHASE_TEXT[state.phase],
    busy,
    startDisabled: busy || state.phase === "running",
    powerOffDisabled: !state.hasContext || state.phase === "disposing" || state.phase === "disposed",
    stopDisabled: state.phase !== "running" || !notesHeld,
    inputsDisabled: !state.canControl,
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
    ? `${detail} Use a browser with AudioWorklet and WebAssembly support, then retry.`
    : `${detail} Check that this example is served by Vite with its package assets, then retry.`;
}
