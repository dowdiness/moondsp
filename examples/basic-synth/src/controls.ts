import { required } from "./dom";

export type Phase = "idle" | "loading" | "suspended" | "resuming" | "running" | "error" | "disposing" | "disposed";

interface ControlActions {
  start(): void;
  retry(): void;
  stopNotes(): void;
  powerOff(): void;
  volumeChanged(value: number): void;
  cutoffChanged(value: number): void;
}

interface ControlState {
  phase: Phase;
  errorText: string;
  hasContext: boolean;
  canControl: boolean;
}

const CUTOFF_MIN_HZ = 120;
const CUTOFF_MAX_HZ = 12_000;
const PHASE_TEXT: Record<Phase, { status: string; label: string; name: string }> = {
  idle: { status: "Loading…", label: "Power on", name: "Power on audio" },
  loading: { status: "Loading…", label: "Loading…", name: "Loading audio" },
  suspended: { status: "Ready", label: "Start", name: "Start audio" },
  resuming: { status: "Starting…", label: "Starting…", name: "Starting audio" },
  running: { status: "Audio on", label: "On", name: "Audio on" },
  error: { status: "Unavailable", label: "Retry", name: "Retry audio" },
  disposing: { status: "Turning off…", label: "Turning off…", name: "Turning off audio" },
  disposed: { status: "Audio off", label: "Power on", name: "Power on audio" },
};

/** Page presentation only: no AudioContext or moondsp operations. */
export function createControls(defaults: { volume: number; cutoff: number }, actions: ControlActions) {
  const startButton = required<HTMLButtonElement>("#start-audio");
  const startLabel = required<HTMLSpanElement>("#start-label");
  const stopButton = required<HTMLButtonElement>("#stop-notes");
  const disposeButton = required<HTMLButtonElement>("#dispose-audio");
  const retryButton = required<HTMLButtonElement>("#retry-audio");
  const statusElement = required<HTMLParagraphElement>("#audio-status");
  const errorPanel = required<HTMLElement>("#audio-error");
  const errorMessage = required<HTMLParagraphElement>("#error-message");
  const volumeInput = required<HTMLInputElement>("#volume");
  const volumeValue = required<HTMLOutputElement>("#volume-value");
  const cutoffInput = required<HTMLInputElement>("#cutoff");
  const cutoffValue = required<HTMLOutputElement>("#cutoff-value");
  let phase: Phase = "idle";
  let notesHeld = false;

  function volume(): number {
    return Math.min(1, Math.max(0, Number(volumeInput.value)));
  }

  function cutoff(): number {
    const position = Math.min(1, Math.max(0, Number(cutoffInput.value)));
    return CUTOFF_MIN_HZ * (CUTOFF_MAX_HZ / CUTOFF_MIN_HZ) ** position;
  }

  function updateVolumeLabel(): number {
    const value = volume();
    volumeValue.textContent = `${Math.round(value * 100)}%`;
    volumeInput.setAttribute("aria-valuetext", volumeValue.textContent);
    return value;
  }

  function updateCutoffLabel(): number {
    const value = cutoff();
    cutoffValue.textContent = `${Math.round(value).toLocaleString()} Hz`;
    cutoffInput.setAttribute("aria-valuetext", cutoffValue.textContent);
    return value;
  }

  function setNotesHeld(held: boolean): void {
    notesHeld = held;
    stopButton.disabled = phase !== "running" || !held;
  }

  function render(state: ControlState): void {
    phase = state.phase;
    const text = PHASE_TEXT[phase];
    const busy = phase === "loading" || phase === "resuming" || phase === "disposing";
    statusElement.textContent = text.status;
    statusElement.dataset.state = phase;
    errorPanel.hidden = phase !== "error";
    errorMessage.textContent = state.errorText;
    startButton.disabled = busy || phase === "running";
    startButton.dataset.state = phase;
    startLabel.textContent = text.label;
    startButton.setAttribute("aria-label", text.name);
    startButton.setAttribute("aria-busy", String(busy));
    disposeButton.disabled = !state.hasContext || phase === "disposing" || phase === "disposed";
    volumeInput.disabled = !state.canControl;
    cutoffInput.disabled = !state.canControl;
    setNotesHeld(notesHeld);
  }

  volumeInput.value = String(defaults.volume);
  cutoffInput.value = (Math.log(defaults.cutoff / CUTOFF_MIN_HZ) / Math.log(CUTOFF_MAX_HZ / CUTOFF_MIN_HZ)).toFixed(3);
  updateVolumeLabel();
  updateCutoffLabel();
  volumeInput.addEventListener("input", () => actions.volumeChanged(updateVolumeLabel()));
  cutoffInput.addEventListener("input", () => actions.cutoffChanged(updateCutoffLabel()));
  startButton.addEventListener("click", actions.start);
  retryButton.addEventListener("click", actions.retry);
  stopButton.addEventListener("click", actions.stopNotes);
  disposeButton.addEventListener("click", actions.powerOff);

  return {
    render,
    setNotesHeld,
    get volume() { return volume(); },
    get cutoff() { return cutoff(); },
  };
}
