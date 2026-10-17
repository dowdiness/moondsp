import type { DraftVersion } from "./draft-version";
import type { PlaybackView } from "./playback";

// Functional core for the transport and change status: every word, flag, and
// data attribute the status surface shows is decided here from the playback
// view alone. main.ts writes the result to the DOM.

export type StatusInput = Pick<PlaybackView,
  | "state" | "currentSource" | "acceptedVersion" | "draftVersion" | "inFlightVersions" | "draftStatus"
  | "tempoText" | "samplePosition" | "mode" | "cyclePosition" | "pendingCount" | "skippedCount">;

export type StatusTone = "error" | "ok" | "neutral";

export type StatusView = Readonly<{
  /** Transport label and whether the transport is moving. */
  label: string;
  playing: boolean;
  /** The engine's sample clock and tempo, exposed as data attributes for observation. */
  samplePosition: string;
  tempoValue: string;
  position: string;
  tempo: string;
  action: "play" | "pause";
  actionLabel: "Play" | "Pause";
  restoreHidden: boolean;
  tone: StatusTone;
  draftState: string;
  draftVersion: string;
  headline: string;
  help: string;
  helpHidden: boolean;
  versions: string;
  materials: string;
  timing: string;
  timingHidden: boolean;
}>;

export function versionLabel(version: DraftVersion): string {
  return `${version[0]}:${version[1]}`;
}

function changeMessage(state: StatusInput): readonly [string, string] {
  if (state.state === "Fault") return ["Audio stopped", "Check the error below before starting playback again."];
  const retained = state.currentSource === null ? "Fix the error below, then press Play."
    : state.state === "Playing" ? "Playback continues with accepted code. Check the error below."
    : "Your previously accepted code is unchanged. Check the error below.";
  switch (state.draftStatus) {
    case "invalid": return ["Check your code", retained];
    case "rejected": return ["Changes weren't accepted", retained];
    case "queued": return ["Waiting to send changes", "Your latest edit will be sent automatically."];
    case "submitting": return ["Sending changes…", "Waiting for the audio engine to accept this version."];
    case "unsubmitted":
      return state.state === "Starting" ? ["Starting audio…", "Your code will be submitted when audio is ready."]
        : state.currentSource === null ? ["Not sent to audio yet", "Press Play to hear your code."]
        : ["Changes not sent", "Restart to play the current code from the beginning."];
    case "accepted":
      if (state.state === "Paused") return ["Changes accepted", "Playback is paused. Press Play to continue."];
      if (state.state === "Ready" || state.state === "Ended") {
        return ["Code accepted", "Press Play to start the accepted code from the beginning."];
      }
      return state.pendingCount || state.skippedCount
        ? ["Changes accepted", "Each part updates at its own entry point."]
        : ["Code is up to date", "No changes waiting to switch."];
  }
}

/** Pure: the status surface for one playback view. */
export function statusView(state: StatusInput): StatusView {
  const draftFailed = state.draftStatus === "invalid" || state.draftStatus === "rejected";
  const fault = state.state === "Fault";
  const moving = state.state === "Playing" || state.state === "Starting";
  const settled = state.pendingCount === 0 && state.skippedCount === 0;
  const [headline, help] = changeMessage(state);

  const accepted = state.acceptedVersion !== null
    ? `Accepted ${versionLabel(state.acceptedVersion)}`
    : state.currentSource !== null ? "Accepted untracked input" : "No accepted draft";
  const sending = state.inFlightVersions.length === 0 ? ""
    : ` · Sending ${state.inFlightVersions.map(version => version === null ? "untracked input" : versionLabel(version)).join(", ")}`;

  const materials = state.pendingCount === 1 ? "1 material awaiting entry"
    : `${state.pendingCount} materials awaiting entry`;
  const skipped = state.skippedCount ? ` · ${state.skippedCount} skipped` : "";
  const waiting = state.pendingCount === 1 ? "1 part is waiting to switch."
    : state.pendingCount > 1 ? `${state.pendingCount} parts are waiting to switch.` : "";
  const skippedChanges = state.skippedCount === 1 ? "1 change was skipped in this pass."
    : state.skippedCount > 1 ? `${state.skippedCount} changes were skipped in this pass.` : "";

  return {
    label: state.state === "Empty" ? "Ready" : state.state,
    playing: state.state === "Playing",
    samplePosition: String(state.samplePosition),
    tempoValue: state.tempoText,
    position: `Position: ${state.cyclePosition.toFixed(2)} cycles`,
    tempo: state.mode === "none" ? "" : `${state.tempoText} BPM`,
    action: moving ? "pause" : "play",
    actionLabel: moving ? "Pause" : "Play",
    restoreHidden: state.currentSource === null || !draftFailed,
    tone: fault || draftFailed ? "error" : state.draftStatus === "accepted" && settled ? "ok" : "neutral",
    draftState: state.draftStatus,
    draftVersion: versionLabel(state.draftVersion),
    headline,
    help,
    helpHidden: !draftFailed && !fault,
    versions: accepted + sending,
    materials: state.currentSource === null ? "No accepted score"
      : (state.pendingCount ? materials : "No pending transitions") + skipped,
    timing: [waiting, skippedChanges].filter(Boolean).join(" "),
    timingHidden: state.currentSource === null || settled,
  };
}

/**
 * Score tools load after the editor paints. "starting" is the first half second,
 * which shows no notice so a quick load does not flash one; "loading" follows.
 */
export type AuthoringPhase = "starting" | "loading" | "ready" | "failed";

export type ControlView = Readonly<{ disabled: boolean; busy: boolean; title: string }>;

export type AuthoringView = Readonly<{
  /** body data-authoring. */
  authoring: "loading" | "ready" | "failed";
  start: ControlView;
  restart: ControlView;
  sourceToggle: ControlView;
  changeStatusHidden: boolean;
  /** The readiness notice, or null when hidden. */
  readiness: string | null;
  /** What replaces the transport and change status once playback cannot load. */
  unavailable: Readonly<{ transport: string; draftStatus: string; draftVersion: string }> | null;
}>;

const START_TITLE = "Play or pause · Ctrl/⌘ + Enter";
const RESTART_TITLE = "Restart from the beginning · Ctrl/⌘ + Shift + Enter";
const TOOLS_TITLE = "Show controls for the phrase at your cursor";
const PLAYBACK_UNAVAILABLE = "Playback unavailable. Reload to try again; code remains editable.";
const TOOLS_UNAVAILABLE = "Score tools unavailable. Reload to try again; code remains editable.";

/** Pure: the controls for one authoring phase. Playing waits for score tools. */
export function authoringView(phase: AuthoringPhase): AuthoringView {
  switch (phase) {
    case "starting":
    case "loading":
      return {
        authoring: "loading",
        start: { disabled: true, busy: true, title: START_TITLE },
        restart: { disabled: true, busy: false, title: RESTART_TITLE },
        sourceToggle: { disabled: true, busy: true, title: TOOLS_TITLE },
        changeStatusHidden: true,
        readiness: phase === "loading" ? "Code is editable. Loading score tools…" : null,
        unavailable: null,
      };
    case "ready":
      return {
        authoring: "ready",
        start: { disabled: false, busy: false, title: START_TITLE },
        restart: { disabled: false, busy: false, title: RESTART_TITLE },
        sourceToggle: { disabled: false, busy: false, title: TOOLS_TITLE },
        changeStatusHidden: false,
        readiness: null,
        unavailable: null,
      };
    case "failed":
      return {
        authoring: "failed",
        start: { disabled: true, busy: false, title: PLAYBACK_UNAVAILABLE },
        restart: { disabled: true, busy: false, title: PLAYBACK_UNAVAILABLE },
        sourceToggle: { disabled: true, busy: false, title: TOOLS_UNAVAILABLE },
        changeStatusHidden: false,
        readiness: "Code is editable. Score tools unavailable.",
        unavailable: { transport: "Playback unavailable", draftStatus: "Playback unavailable", draftVersion: "Unavailable" },
      };
  }
}
