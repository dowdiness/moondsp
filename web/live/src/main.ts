// moondsp · live · phase A
//
// CodeMirror 6 + Canopy CM6Adapter wired to the AudioWorklet engine.
// TextEdit intents → debounced setPatternText → wasm parse → hot-swap.
// Parse failures keep the last good pattern playing; the error message
// surfaces in the footer panel.

import { Compartment, EditorState } from "@codemirror/state";
import { EditorView, keymap, lineNumbers, highlightActiveLine } from "@codemirror/view";
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import { bracketMatching } from "@codemirror/language";

import { CM6Adapter } from "./canopy";
import type { Diagnostic, UserIntent } from "./canopy";
import { AudioEngine } from "./audio";
import type { AudioStatus, WorkletReply } from "./audio";

const INITIAL = `s("bd sd hh sd").fast(2)`;
const DEBOUNCE_MS = 200;
const DEFAULT_BPM = 120;
const DEFAULT_GAIN = 0.6;

// ── DOM ─────────────────────────────────────────────────────

const editorEl = document.getElementById("editor") as HTMLElement;
const logEl = document.getElementById("log") as HTMLElement;
const statusEl = document.getElementById("status") as HTMLElement;
const startBtn = document.getElementById("start") as HTMLButtonElement;

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
      history(),
      keymap.of([...defaultKeymap, ...historyKeymap]),
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

// Empty sentinel — nothing has been sent to the worklet yet, so the first
// evalNow call must go through even if the doc still equals INITIAL.
let lastGood = "";
let pending: number | null = null;

// Revision tagging guards diagnostic application against stale worklet
// replies: if the user has typed since we sent text v=N, the v=N reply
// is silently discarded so we don't paint a squiggle at positions that
// no longer line up with the current document.
let revCounter = 0;
let latestSentRev = 0;
let latestSentText = "";

function setLog(message: string, kind: "ok" | "error" | "info" = "info"): void {
  logEl.textContent = message;
  logEl.classList.toggle("error", kind === "error");
  logEl.classList.toggle("ok", kind === "ok");
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
      lastGood = "";
      latestSentText = "";
      adapter.applyPatches([{ type: "SetDiagnostics", diagnostics: [] }]);
      break;
  }
}

engine.onStatus(applyStatus);

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

engine.onReply((reply: WorkletReply) => {
  if (reply.type === "pattern-updated" || reply.type === "pattern-error") {
    // Drop replies for older submissions — a newer eval is in flight
    // (or already landed) and its reply will carry the right state.
    const rev = typeof reply.revision === "number" ? reply.revision : undefined;
    if (rev !== undefined && rev !== latestSentRev) return;
    // Drop replies whose submitted text no longer matches the current
    // document. The user typed during the in-flight eval; the next
    // debounced send will produce a reply that does match.
    if (latestSentText !== view.state.doc.toString()) return;
  }

  if (reply.type === "pattern-updated") {
    setLog(`✓ pattern updated`, "ok");
    adapter.applyPatches([{ type: "SetDiagnostics", diagnostics: [] }]);
  } else if (reply.type === "pattern-error") {
    const msg = String(reply.message ?? "parse error");
    setLog(`✗ ${msg} (kept last good)`, "error");
    const diag = diagnosticFromError(msg, view.state.doc.length);
    adapter.applyPatches([{ type: "SetDiagnostics", diagnostics: [diag] }]);
  }
  // Ignore other worklet messages (telemetry, hot-swap acks, etc.) for now.
});

function evalNow(text: string): void {
  if (engine.getStatus().kind !== "running") return;
  if (text === lastGood) return;
  const rev = ++revCounter;
  latestSentRev = rev;
  latestSentText = text;
  engine.setPatternText(text, rev);
  lastGood = text; // worklet keeps last graph on error, so this is safe
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
      lastGood = "";
      latestSentText = "";
      setLog("stopped", "info");
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      setLog(`✗ stop failed: ${msg}`, "error");
    }
    return;
  }

  try {
    await engine.start();
    engine.setBpm(DEFAULT_BPM);
    engine.setGain(DEFAULT_GAIN);
    // Send the current document to bring up the initial pattern.
    evalNow(view.state.doc.toString());
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    setLog(`✗ start failed: ${msg}`, "error");
  }
});

// eslint-disable-next-line no-console
console.info("[moondsp/live] ready — click Start to bring up audio");
