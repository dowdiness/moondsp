// moondsp · live · phase A
//
// CodeMirror 6 + Canopy CM6Adapter wired to the AudioWorklet engine.
// TextEdit intents → explicit pattern/song mode → debounced wasm parse.
// Parse failures keep the last good playback source running; the error
// message surfaces in the footer panel.

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

import { minilive } from "./lang/minilive";
import { CM6Adapter } from "./canopy";
import type { Diagnostic, UserIntent } from "./canopy";
import { AudioEngine } from "./audio";
import type { AudioEngineMode, AudioStatus } from "./audio";
import { LivePlayback } from "./playback";
import type { PlaybackView } from "./playback";
import type { PlaybackMode } from "./playback-protocol";

const INITIAL = `$: s("bd(3,8), hh*16?, sd(2,8,2)").jux(rev)
$: note("48(3,8) 60(2,8,2) 67(3,8) 60(2,8,3)").slow(3)`;

// ── DOM ─────────────────────────────────────────────────────

const editorEl = document.getElementById("editor") as HTMLElement;
const logEl = document.getElementById("log") as HTMLElement;
const statusEl = document.getElementById("status") as HTMLElement;
const startBtn = document.getElementById("start") as HTMLButtonElement;
const cheatEl = document.getElementById("cheat") as HTMLElement;
const cheatToggle = document.getElementById("cheat-toggle") as HTMLButtonElement;
const modePatternBtn = document.getElementById("mode-pattern") as HTMLButtonElement;
const modeSongBtn = document.getElementById("mode-song") as HTMLButtonElement;
const bpmInput = document.getElementById("global-bpm") as HTMLInputElement;
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


function applyBpmInput(): void {
  playback.commitBpm(bpmInput.value);
}


function applyStatus(s: AudioStatus): void {
  switch (s.kind) {
    case "idle":
      statusEl.textContent = "idle — click Play";
      startBtn.disabled = false;
      startBtn.textContent = "Play";
      startBtn.dataset.action = "start";
      break;
    case "starting":
      statusEl.textContent = "starting…";
      startBtn.disabled = true;
      startBtn.textContent = "Starting…";
      startBtn.dataset.action = "start";
      break;
    case "stopping":
      statusEl.textContent = "stopping…";
      startBtn.disabled = true;
      startBtn.textContent = "Stopping…";
      break;
    case "running":
      statusEl.textContent = "running · 48 kHz · 128 frames";
      startBtn.disabled = false;
      startBtn.textContent = "Stop";
      startBtn.dataset.action = "stop";
      break;
    case "error":
      statusEl.textContent = `error: ${s.message}`;
      startBtn.disabled = false;
      startBtn.textContent = "Retry";
      startBtn.dataset.action = "start";
      break;
  }
}

let renderedPlayback: PlaybackView | undefined;

function renderPlayback(state: PlaybackView): void {
  applyStatus(state.status);
  modePatternBtn.classList.toggle("active", state.mode === "pattern");
  modeSongBtn.classList.toggle("active", state.mode === "song");
  modePatternBtn.setAttribute("aria-pressed", String(state.mode === "pattern"));
  modeSongBtn.setAttribute("aria-pressed", String(state.mode === "song"));
  if (bpmInput.value !== state.tempoText) bpmInput.value = state.tempoText;
  if (state.feedback && state.feedback !== renderedPlayback?.feedback) {
    setLog(state.feedback.message, state.feedback.kind);
  }
  if (state.diagnostic !== renderedPlayback?.diagnostic) {
    const diagnostic = state.diagnostic;
    adapter.applyPatches([{
      type: "SetDiagnostics",
      diagnostics: diagnostic
        ? [diagnosticFromError(diagnostic.message, diagnostic.documentLength)]
        : [],
    }]);
  }
  renderedPlayback = state;
}

const playback = new LivePlayback(
  engine, { text: view.state.doc.toString() }, renderPlayback,
);

modePatternBtn.addEventListener("click", () => playback.selectMode("pattern"));
modeSongBtn.addEventListener("click", () => playback.selectMode("song"));
bpmInput.addEventListener("input", () => playback.editBpm(bpmInput.value));
bpmInput.addEventListener("change", applyBpmInput);
bpmInput.addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    applyBpmInput();
    bpmInput.blur();
  }
});

// Parses "position N: message" → { from, to, message }. Spans one
// character at the position; if the position is at or past EOF, anchors
// to the last char so the squiggly is always visible.
function diagnosticFromError(raw: string, docLength: number): Diagnostic {
  const m = /^position (\d+):\s*(.*)$/.exec(raw);
  if (!m) {
    return { from: 0, to: Math.max(1, docLength), severity: "error", message: raw };
  }
  const pos = Math.min(Math.max(0, Number.parseInt(m[1], 10)), docLength);
  const from = pos >= docLength ? Math.max(0, docLength - 1) : pos;
  const to = Math.min(docLength, from + 1);
  return { from, to, severity: "error", message: m[2] || raw };
}


adapter.onIntent((intent: UserIntent) => {
  if (intent.type === "TextEdit") {
    playback.edit(view.state.doc.toString());
  }
});

startBtn.addEventListener("click", () => {
  void playback.toggle();
});

// ── Cheatsheet ──────────────────────────────────────────────

// Share the score with parser fixtures and acceptance tests.
(document.getElementById("light-orbit-example") as HTMLButtonElement).dataset.example = lightOrbit;
(document.getElementById("room-of-light-example") as HTMLButtonElement).dataset.example = roomOfLight;
(document.getElementById("envelope-compare-example") as HTMLButtonElement).dataset.example = envelopeComparison;
(document.getElementById("shared-room-example") as HTMLButtonElement).dataset.example = sharedRoomComparison;
(document.getElementById("shared-room-afterglow-example") as HTMLButtonElement).dataset.example = sharedRoomAfterglow;

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
  const mode: PlaybackMode = example.dataset.mode === "song" ? "song" : "pattern";
  const bpm = example.dataset.bpm;
  view.dispatch({
    changes: { from: 0, to: view.state.doc.length, insert: text },
  });
  playback.useExample({ mode, text, bpm });
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
console.info("[moondsp/live] ready — click Start to bring up audio");
