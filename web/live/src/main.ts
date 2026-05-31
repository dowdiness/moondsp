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

import { minilive } from "./lang/minilive";
import { CM6Adapter } from "./canopy";
import type { Diagnostic, UserIntent } from "./canopy";
import { AudioEngine } from "./audio";
import type { AudioStatus, WorkletReply } from "./audio";

type PlaybackMode = "pattern" | "song";

const INITIAL = `$: s("bd(3,8), hh*16?, sd(2,8,2)").jux(rev)
$: note("48(3,8) 60(2,8,2) 67(3,8) 60(2,8,3)").slow(3)`;
const DEBOUNCE_MS = 200;
const DEFAULT_BPM = 60;
const DEFAULT_GAIN = 0.6;

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

const engine = new AudioEngine();

// Empty sentinels — nothing has been sent to the worklet yet, so the first
// evalNow call must go through even if the doc still equals INITIAL.
let playbackMode: PlaybackMode = "pattern";
let activeMode: PlaybackMode | null = null;
let lastGoodByMode: Record<PlaybackMode, string> = { pattern: "", song: "" };
let globalBpm = DEFAULT_BPM;
let pending: number | null = null;

// Revision tagging guards diagnostic application against stale worklet
// replies: if the user has typed since we sent text v=N, the v=N reply
// is silently discarded so we don't paint a squiggle at positions that
// no longer line up with the current document.
let revCounter = 0;
let latestSentRev = 0;
let latestSentMode: PlaybackMode = "pattern";
let latestSentText = "";

function setLog(message: string, kind: "ok" | "error" | "info" = "info"): void {
  logEl.textContent = message;
  logEl.classList.toggle("error", kind === "error");
  logEl.classList.toggle("ok", kind === "ok");
}

function modeLabel(mode: PlaybackMode): string {
  return mode === "pattern" ? "pattern" : "song";
}

function sanitizeBpm(value: number): number {
  if (!Number.isFinite(value) || value < 1.0) return 1.0;
  return value;
}

function setGlobalBpm(value: number, sendToEngine = true): void {
  globalBpm = sanitizeBpm(value);
  bpmInput.value = String(globalBpm);
  if (sendToEngine && engine.getStatus().kind === "running") {
    engine.setBpm(globalBpm);
  }
}

function applyBpmInput(): void {
  const parsed = Number.parseFloat(bpmInput.value);
  if (!Number.isFinite(parsed)) {
    bpmInput.value = String(globalBpm);
    return;
  }
  setGlobalBpm(parsed);
  setLog(`BPM ${globalBpm}`, "info");
}

function embeddedBpm(text: string): number | null {
  const match = /\bbpm\s*\(\s*([0-9]+(?:\.[0-9]+)?)\s*\)/.exec(text);
  if (!match) return null;
  const value = Number.parseFloat(match[1]);
  return Number.isFinite(value) ? value : null;
}

function setPlaybackMode(mode: PlaybackMode, evaluateCurrent = true): void {
  playbackMode = mode;
  modePatternBtn.classList.toggle("active", mode === "pattern");
  modeSongBtn.classList.toggle("active", mode === "song");
  modePatternBtn.setAttribute("aria-pressed", String(mode === "pattern"));
  modeSongBtn.setAttribute("aria-pressed", String(mode === "song"));
  if (evaluateCurrent) {
    setLog(`${modeLabel(mode)} mode selected`, "info");
    evalNow(view.state.doc.toString());
  }
}

function resetPlaybackDedupe(): void {
  activeMode = null;
  lastGoodByMode = { pattern: "", song: "" };
  latestSentText = "";
}

function applyStatus(s: AudioStatus): void {
  switch (s.kind) {
    case "idle":
      statusEl.textContent = "idle — click Start";
      startBtn.disabled = false;
      startBtn.textContent = "Start audio";
      startBtn.dataset.action = "start";
      break;
    case "starting":
      statusEl.textContent = "starting…";
      startBtn.disabled = true;
      startBtn.textContent = "Starting…";
      startBtn.dataset.action = "start";
      break;
    case "running":
      statusEl.textContent = "running · 48 kHz · 128 frames";
      startBtn.disabled = false;
      startBtn.textContent = "Stop audio";
      startBtn.dataset.action = "stop";
      break;
    case "error":
      statusEl.textContent = `error: ${s.message}`;
      startBtn.disabled = false;
      startBtn.textContent = "Retry";
      startBtn.dataset.action = "start";
      // Engine torn itself down — drop any in-flight debounce and reset
      // last-good so Retry will re-send the current document.
      if (pending !== null) {
        window.clearTimeout(pending);
        pending = null;
      }
      resetPlaybackDedupe();
      adapter.applyPatches([{ type: "SetDiagnostics", diagnostics: [] }]);
      break;
  }
}

engine.onStatus(applyStatus);

setPlaybackMode("pattern", false);
setGlobalBpm(DEFAULT_BPM, false);
modePatternBtn.addEventListener("click", () => setPlaybackMode("pattern"));
modeSongBtn.addEventListener("click", () => setPlaybackMode("song"));
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

function replyPlaybackMode(reply: WorkletReply): PlaybackMode | null {
  if (reply.type === "pattern-updated" || reply.type === "pattern-error") return "pattern";
  if (reply.type === "song-updated" || reply.type === "song-error") return "song";
  return null;
}

engine.onReply((reply: WorkletReply) => {
  const replyMode = replyPlaybackMode(reply);
  if (replyMode !== null) {
    // Drop replies for older submissions — a newer eval is in flight
    // (or already landed) and its reply will carry the right state.
    const rev = "revision" in reply && typeof reply.revision === "number" ? reply.revision : undefined;
    if (rev !== undefined && rev !== latestSentRev) return;
    if (replyMode !== latestSentMode) return;
    // Drop replies whose submitted text no longer matches the current
    // document. The user typed during the in-flight eval; the next
    // debounced send will produce a reply that does match.
    if (latestSentText !== view.state.doc.toString()) return;
  }

  if (reply.type === "pattern-updated" || reply.type === "song-updated") {
    const mode: PlaybackMode = reply.type === "pattern-updated" ? "pattern" : "song";
    // Only commit lastGood on a confirmed success. If we updated it
    // optimistically in evalNow, a parse error would persist as lastGood —
    // and re-typing the same bad text after clearing could short-circuit
    // before re-painting the squiggle.
    activeMode = mode;
    lastGoodByMode[mode] = latestSentText;
    if (mode === "song") {
      const bpm = embeddedBpm(latestSentText);
      if (bpm !== null) setGlobalBpm(bpm, false);
    }
    setLog(`✓ ${modeLabel(mode)} updated`, "ok");
    adapter.applyPatches([{ type: "SetDiagnostics", diagnostics: [] }]);
  } else if (reply.type === "pattern-error" || reply.type === "song-error") {
    const msg = String(reply.message ?? "parse error");
    setLog(`✗ ${msg} (kept last good)`, "error");
    const diag = diagnosticFromError(msg, view.state.doc.length);
    adapter.applyPatches([{ type: "SetDiagnostics", diagnostics: [diag] }]);
  }
  // Ignore other worklet messages (telemetry, hot-swap acks, etc.) for now.
});

function evalNow(text: string): void {
  if (engine.getStatus().kind !== "running") return;
  const mode = playbackMode;
  if (mode === activeMode && text === lastGoodByMode[mode]) return;
  if (text.trim() === "") {
    // Empty input: skip the wasm round trip entirely. The parser would
    // synthesize an "empty input" error with no position, which the
    // adapter would clamp to a 0..0 range and drop on an empty doc —
    // leaving the user with a footer error and no inline marker.
    // Treat as a soft no-op: clear any existing diagnostic, surface a
    // hint, and let the worklet keep playing the last good graph.
    latestSentText = "";
    adapter.applyPatches([{ type: "SetDiagnostics", diagnostics: [] }]);
    setLog("(empty — keeping previous playback)", "info");
    return;
  }
  const rev = ++revCounter;
  latestSentRev = rev;
  latestSentMode = mode;
  latestSentText = text;
  if (mode === "pattern") {
    engine.setPatternText(text, rev);
  } else {
    engine.setSongText(text, rev);
  }
  // lastGood is committed by the *-updated reply handler — not here —
  // so an in-flight parse error doesn't poison the dedupe.
}

function scheduleEval(text: string): void {
  if (pending !== null) window.clearTimeout(pending);
  pending = window.setTimeout(() => {
    pending = null;
    evalNow(text);
  }, DEBOUNCE_MS);
}

adapter.onIntent((intent: UserIntent) => {
  if (intent.type === "TextEdit") {
    scheduleEval(view.state.doc.toString());
  }
});

// ── Start handler ───────────────────────────────────────────

startBtn.addEventListener("click", async () => {
  if (startBtn.dataset.action === "stop") {
    try {
      await engine.stop();
      // Cancel any pending debounced eval so it doesn't fire post-stop.
      if (pending !== null) {
        window.clearTimeout(pending);
        pending = null;
      }
      resetPlaybackDedupe();
      setLog("stopped", "info");
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      setLog(`✗ stop failed: ${msg}`, "error");
    }
    return;
  }

  try {
    await engine.start();
    engine.setBpm(globalBpm);
    engine.setGain(DEFAULT_GAIN);
    // Send the current document to bring up the initial pattern.
    evalNow(view.state.doc.toString());
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    setLog(`✗ start failed: ${msg}`, "error");
  }
});

// ── Cheatsheet ──────────────────────────────────────────────

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
  if (bpm) setGlobalBpm(Number.parseFloat(bpm));
  setPlaybackMode(mode, false);
  view.dispatch({
    changes: { from: 0, to: view.state.doc.length, insert: text },
  });
  scheduleEval(text);
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
