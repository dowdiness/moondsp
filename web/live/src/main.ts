// Editor intents feed the Player's debounced source updates.
// Current song and sounding material versions remain owned by the audio engine.

import { Compartment, EditorState, Prec } from "@codemirror/state";
import { EditorView, keymap, lineNumbers, highlightActiveLine } from "@codemirror/view";
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import { bracketMatching } from "@codemirror/language";
import { closeBrackets, closeBracketsKeymap, acceptCompletion } from "@codemirror/autocomplete";

import envelopeComparison from "../../../examples/envelope-comparison.mini?raw";
import roomOfLight from "../../../examples/room-of-light.mini?raw";
import lightOrbit from "../../../examples/light-orbit.mini?raw";
import sharedRoomComparison from "../../../examples/shared-room-comparison.mini?raw";
import sharedRoomAfterglow from "../../../examples/shared-room-afterglow.mini?raw";
import overlayGroove from "../../../examples/overlay-groove.mini?raw";
import overlayGrouping from "../../../examples/overlay-grouping.mini?raw";
import restsAndGates from "../../../examples/rests-and-gates.mini?raw";

import { minilive } from "./lang/minilive";
import { CM6Adapter } from "./canopy";
import type { UserIntent, Diagnostic } from "./canopy";
import { AudioEngine } from "./audio";
import type { AudioEngineMode, CompiledSession } from "./audio";
import { Player } from "./playback";
import type { PlaybackView } from "./playback";

const INITIAL = `$: s("bd(3,8), hh*16?, sd(2,8,2)").jux(rev)
$: note("48(3,8) 60(2,8,2) 67(3,8) 60(2,8,3)").slow(3)`;

// ── DOM ─────────────────────────────────────────────────────

const editorEl = document.getElementById("editor") as HTMLElement;
const logEl = document.getElementById("log") as HTMLElement;
const statusEl = document.getElementById("status") as HTMLElement;
const startBtn = document.getElementById("start") as HTMLButtonElement;
const cheatEl = document.getElementById("cheat") as HTMLElement;
const cheatToggle = document.getElementById("cheat-toggle") as HTMLButtonElement;
const workspaceEl = document.querySelector("main.workspace") as HTMLElement;

// ── Editor ──────────────────────────────────────────────────

const listenerCompartment = new Compartment();

const view = new EditorView({
  parent: editorEl,
  state: EditorState.create({
    doc: INITIAL,
    extensions: [
      lineNumbers(),
      highlightActiveLine(),
      bracketMatching(),
      closeBrackets(),
      history(),
      minilive(),
      // Tab → accept the highlighted completion when the popup is open.
      // CM6's default completion keymap only binds Enter; most editors
      // (VS Code, Strudel) use Tab as the primary accept key. The
      // `autocompletion()` extension registers its own Tab binding for
      // snippet-field navigation at Prec.highest, so we have to match
      // that precedence to win. When no popup is open `acceptCompletion`
      // returns false and falls through to the snippet keymap below
      // (which advances the active snippet field if any) and then to
      // the default Tab handling.
      Prec.highest(keymap.of([{ key: "Tab", run: acceptCompletion }])),
      keymap.of([...defaultKeymap, ...historyKeymap, ...closeBracketsKeymap]),
      ...CM6Adapter.extensions(),
      listenerCompartment.of([]),
    ],
  }),
});

const adapter = new CM6Adapter(view);

view.dispatch({
  effects: listenerCompartment.reconfigure(adapter.createUpdateListener()),
});

// ── Engine ──────────────────────────────────────────────────

const urlParams = new URLSearchParams(window.location.search);
const schedulerTimingEnabled = urlParams.get("schedulerTiming") === "1" ||
  urlParams.get("schedulerTiming") === "true";
const telemetryEnabled = urlParams.get("telemetry") === "1" ||
  urlParams.get("telemetry") === "true";
const schedulerTimingBatchParam = Number.parseInt(
  urlParams.get("schedulerTimingBatch") ?? "128",
  10,
);
const schedulerTimingBatchSize = Number.isFinite(schedulerTimingBatchParam) &&
  schedulerTimingBatchParam > 0
  ? schedulerTimingBatchParam
  : undefined;
const nativeSampleRate = urlParams.get("nativeSampleRate") === "1" ||
  urlParams.get("nativeSampleRate") === "true";
const sampleRateParam = Number.parseInt(urlParams.get("sampleRate") ?? "48000", 10);
const audioSampleRate = nativeSampleRate
  ? undefined
  : Number.isFinite(sampleRateParam) && sampleRateParam > 0
    ? sampleRateParam
    : 48000;
const latencyHintParam = urlParams.get("latencyHint");
const latencyHint = latencyHintParam === "interactive" ||
  latencyHintParam === "balanced" ||
  latencyHintParam === "playback"
  ? latencyHintParam
  : undefined;
const modeParam = urlParams.get("audioMode");
const audioMode: AudioEngineMode = modeParam === "compiled" ? "compiled" : "scheduler";
const engine = new AudioEngine("/processor.js", "/moonbit_dsp.wasm", {
  enableTelemetry: telemetryEnabled,
  enableSchedulerTiming: schedulerTimingEnabled,
  schedulerTimingBatchSize,
  sampleRate: audioSampleRate,
  latencyHint,
  mode: audioMode,
});

if (audioMode !== "scheduler") {
  console.info(`[moondsp/live] audioMode=${audioMode}; pattern editor updates are ignored in this mode`);
}

if (schedulerTimingEnabled) {
  console.info(
    "[moondsp/live] scheduler timing enabled; inspect scheduler-timing messages in DevTools",
  );
}


function setLog(message: string, kind: "ok" | "error" | "info" = "info"): void {
  logEl.textContent = message;
  logEl.classList.toggle("error", kind === "error");
  logEl.classList.toggle("ok", kind === "ok");
}


function applyStatus(state: PlaybackView): void {
  const stateName = state.state === "Empty" ? "Ready" : state.state;
  const pending = state.pendingCount ? ` · ${state.pendingCount} pending` : "";
  const skipped = state.skippedCount ? ` · ${state.skippedCount} skipped` : "";
  statusEl.textContent = `${stateName}${pending}${skipped}`;
  statusEl.dataset.samplePosition = String(state.samplePosition);
  statusEl.dataset.tempo = state.tempoText;
  startBtn.disabled = false;
  startBtn.textContent = state.state === "Playing" || state.state === "Starting" ? "Pause" : "Play";
  startBtn.dataset.action = state.state === "Playing" || state.state === "Starting" ? "pause" : "play";
}
function diagnosticFromError(raw: string, docLength: number): Diagnostic {
  const match = /^position (\d+):\s*(.*)$/.exec(raw);
  const position = match ? Math.min(Number.parseInt(match[1], 10), docLength) : 0;
  return { from: Math.max(0, position - (position === docLength ? 1 : 0)), to: Math.max(1, Math.min(docLength, position + 1)), severity: "error", message: match?.[2] || raw };
}
let renderedPlayback: PlaybackView | undefined;

function renderPlayback(state: PlaybackView): void {
  applyStatus(state);
  if (state.feedback !== renderedPlayback?.feedback) {
    setLog(state.feedback?.message ?? "", state.feedback?.kind ?? "info");
  }
  if (state.diagnostic !== renderedPlayback?.diagnostic) {
    const diagnostic = state.diagnostic;
    adapter.applyPatches([{ type: "SetDiagnostics", diagnostics: diagnostic ? [diagnosticFromError(diagnostic.message, diagnostic.documentLength)] : [] }]);
  }
  renderedPlayback = state;
}
const playback = new Player(engine, { text: view.state.doc.toString() }, renderPlayback);
let compiledSession: CompiledSession | undefined;
async function toggleCompiled(): Promise<void> {
  startBtn.disabled = true;
  try {
    if (compiledSession) {
      await compiledSession.close();
      compiledSession = undefined;
      statusEl.textContent = "Ready";
      startBtn.textContent = "Play";
    } else {
      const opened = await engine.openSession(event => {
        if (event.kind === "failed") {
          compiledSession = undefined;
          statusEl.textContent = "Fault";
          startBtn.textContent = "Play";
          setLog(event.message, "error");
        }
      });
      if (opened.kind !== "opened") throw new Error(opened.kind === "failed" ? opened.message : "Audio owner is busy");
      if (opened.session.kind !== "compiled") throw new Error("Expected compiled audio session");
      compiledSession = opened.session;
      compiledSession.fadeIn();
      statusEl.textContent = "Playing";
      startBtn.textContent = "Stop";
    }
  } catch (error) {
    setLog(error instanceof Error ? error.message : String(error), "error");
  } finally {
    startBtn.disabled = false;
  }
}
if (audioMode === "compiled") document.getElementById("restart")!.hidden = true;


adapter.onIntent((intent: UserIntent) => {
  if (intent.type === "TextEdit" && audioMode === "scheduler") {
    playback.edit(view.state.doc.toString());
  }
});

startBtn.addEventListener("click", () => {
  if (audioMode === "compiled") { void toggleCompiled(); return; }
  const state = playback.view().state;
  void (state === "Playing" || state === "Starting" ? playback.pause() : playback.play()).catch(error => playback.report(error));
});

document.getElementById("restart")!.addEventListener("click", () => {
  void playback.restart(view.state.doc.toString()).catch(error => playback.report(error));
});

// ── Cheatsheet ──────────────────────────────────────────────
(document.getElementById("room-of-light-example") as HTMLButtonElement).dataset.example = roomOfLight;
(document.getElementById("envelope-compare-example") as HTMLButtonElement).dataset.example = envelopeComparison;
(document.getElementById("shared-room-example") as HTMLButtonElement).dataset.example = sharedRoomComparison;
(document.getElementById("shared-room-afterglow-example") as HTMLButtonElement).dataset.example = sharedRoomAfterglow;
(document.getElementById("overlay-groove-example") as HTMLButtonElement).dataset.example = `bpm(96);\n${overlayGroove}`;
(document.getElementById("light-orbit-example") as HTMLButtonElement).dataset.example = `bpm(120);\n${lightOrbit}`;
(document.getElementById("overlay-grouping-example") as HTMLButtonElement).dataset.example = overlayGrouping;
(document.getElementById("rests-and-gates-example") as HTMLButtonElement).dataset.example = `bpm(96);\n${restsAndGates}`;

cheatToggle.addEventListener("click", () => {
  const collapsed = workspaceEl.classList.toggle("cheat-collapsed");
  cheatToggle.setAttribute("aria-expanded", String(!collapsed));
  cheatToggle.textContent = collapsed ? "Show help" : "Hide help";
});

cheatEl.addEventListener("click", (ev) => {
  const target = ev.target as HTMLElement;
  const example = target.closest<HTMLElement>(".example");
  if (!example) return;
  const text = example.dataset.example;
  if (!text) return;
  view.dispatch({
    changes: { from: 0, to: view.state.doc.length, insert: text },
  });
  view.focus();
});

// Test hook: exposes the engine so smoke tests can inject synthetic
// worklet replies (specifically the runtime-error path that's
// otherwise unreachable from the live REPL UI). Harmless to ship —
// the only public method beyond the normal API is `_testInjectReply`.
declare global {
  interface Window {
    __moondspEngine?: AudioEngine;
  }
}
window.__moondspEngine = engine;

// eslint-disable-next-line no-console
console.info("[moondsp/live] ready — click Play to bring up audio");
