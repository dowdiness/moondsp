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
import type { UserIntent } from "./canopy";
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

let lastGood = INITIAL;
let pending: number | null = null;

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
      break;
    case "starting":
      statusEl.textContent = "starting…";
      startBtn.disabled = true;
      break;
    case "running":
      statusEl.textContent = "running · 48 kHz · 128 frames";
      startBtn.disabled = true;
      break;
    case "error":
      statusEl.textContent = `error: ${s.message}`;
      startBtn.disabled = false;
      startBtn.textContent = "Retry";
      break;
  }
}

engine.onStatus(applyStatus);

engine.onReply((reply: WorkletReply) => {
  if (reply.type === "pattern-updated") {
    setLog(`✓ pattern updated`, "ok");
  } else if (reply.type === "pattern-error") {
    const msg = String(reply.message ?? "parse error");
    setLog(`✗ ${msg} (kept last good)`, "error");
  }
  // Ignore other worklet messages (telemetry, hot-swap acks, etc.) for now.
});

function evalNow(text: string): void {
  if (engine.getStatus().kind !== "running") return;
  if (text === lastGood) return;
  // Optimistic: update lastGood only after the worklet confirms,
  // but track the most recent submitted text so we don't double-send.
  engine.setPatternText(text);
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
