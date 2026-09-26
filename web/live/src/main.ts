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
import sectionComposition from "../../../examples/section-composition.mini?raw";

import { minilive } from "./lang/minilive";
import { CM6Adapter } from "./canopy";
import type { Diagnostic } from "./canopy";
import { AudioEngine } from "./audio";
import type { AudioEngineMode, CompiledSession } from "./audio";
import { Draft, type DraftVersion } from "./authoring";
import { Player } from "./playback";
import type { PlaybackView } from "./playback";

const INITIAL = `$: s("bd(3,8), hh*16?, sd(2,8,2)").jux(rev)
$: note("48(3,8) 60(2,8,2) 67(3,8) 60(2,8,3)").slow(3)`;

// ── DOM ─────────────────────────────────────────────────────

const editorEl = document.getElementById("editor") as HTMLElement;
const logEl = document.getElementById("log") as HTMLElement;
const statusEl = document.getElementById("status") as HTMLElement;
const playbackDetailsEl = document.getElementById("playback-details") as HTMLElement;
const positionEl = document.getElementById("playback-position") as HTMLElement;
const tempoEl = document.getElementById("playback-tempo") as HTMLElement;
const draftStatusEl = document.getElementById("draft-status") as HTMLElement;
const changeStatusEl = document.getElementById("change-status") as HTMLElement;
const changeHelpEl = document.getElementById("change-help") as HTMLElement;
const changeTimingEl = document.getElementById("change-timing") as HTMLElement;
const draftVersionEl = document.getElementById("draft-version") as HTMLElement;
const draftVersionsEl = document.getElementById("draft-versions") as HTMLElement;
const materialStatusEl = document.getElementById("material-status") as HTMLElement;
const startBtn = document.getElementById("start") as HTMLButtonElement;
const cheatEl = document.getElementById("cheat") as HTMLElement;
const cheatToggle = document.getElementById("cheat-toggle") as HTMLButtonElement;
const workspaceEl = document.querySelector("main.workspace") as HTMLElement;
const rangePreviewEl = document.getElementById("range-preview") as HTMLElement;
const sectionListEl = document.getElementById("section-list") as HTMLElement;
const rangeStartEl = document.getElementById("range-start") as HTMLInputElement;
const rangeEndEl = document.getElementById("range-end") as HTMLInputElement;
const loopStatusEl = document.getElementById("loop-status") as HTMLElement;
const loopRangeBtn = document.getElementById("loop-range") as HTMLButtonElement;
const wholeSongBtn = document.getElementById("whole-song") as HTMLButtonElement;

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


function setText(element: HTMLElement, text: string): void {
  if (element.textContent !== text) element.textContent = text;
}

function versionLabel(version: DraftVersion): string {
  return `${version[0]}:${version[1]}`;
}

function changeMessage(state: PlaybackView): readonly [string, string] {
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
        : state.currentSource === null ? ["Ready to play", "Press Play to hear your code."]
        : ["Changes not sent", "Restart to play the current code from the beginning."];
    case "accepted":
      if (state.state === "Paused") return ["Changes accepted", "Playback is paused. Press Play to continue."];
      if (state.state === "Ready" || state.state === "Ended") {
        return ["Ready to play", "Press Play to start the accepted code from the beginning."];
      }
      return state.pendingCount || state.skippedCount
        ? ["Changes accepted", "Each part updates at its own entry point."]
        : ["Code is up to date", "No changes waiting to switch."];
  }
}

let shownSections: PlaybackView["sections"];
function cycleMilli(text: string): number | null {
  const value = Number(text);
  const milli = value * 1000;
  return text.trim() !== "" && Number.isFinite(milli) && Number.isSafeInteger(milli) &&
    milli >= 0 && milli <= 2147483647 ? milli : null;
}

function renderSections(state: PlaybackView): void {
  const sections = state.sections ?? [];
  rangePreviewEl.hidden = state.mode !== "song" || state.currentSource === null;
  if (rangePreviewEl.hidden) return;
  if (sections !== shownSections) {
    shownSections = sections;
    sectionListEl.replaceChildren();
    for (const [index, section] of sections.entries()) {
      const row = document.createElement("div");
      row.className = "section-row";
      const label = document.createElement("span");
      label.textContent = `${section.label} [${section.start}, ${section.end})`;
      const start = document.createElement("button");
      start.type = "button";
      start.textContent = "Play from here";
      start.addEventListener("click", () => {
        void playback.seekSection(index).catch(error => playback.report(error));
      });
      const loop = document.createElement("button");
      loop.type = "button";
      loop.textContent = "Loop section";
      loop.addEventListener("click", () => {
        rangeStartEl.value = String(section.start);
        rangeEndEl.value = String(section.end);
        void playback.loopSection(index).catch(error => playback.report(error));
      });
      row.append(label, start, loop);
      sectionListEl.append(row);
    }
  }
  const usable = state.state === "Playing" || state.state === "Paused" || state.state === "Ended";
  for (const row of sectionListEl.children) {
    const [from, to] = (row as HTMLElement).querySelectorAll("button");
    from.disabled = !usable;
    to.disabled = !usable;
  }
  loopRangeBtn.disabled = !usable;
  wholeSongBtn.disabled = !usable;
  setText(loopStatusEl, state.loopRange
    ? `Loop [${state.loopRange.begin}, ${state.loopRange.end}) · position ${state.cyclePosition.toFixed(2)} cycles`
    : `Whole song · position ${state.cyclePosition.toFixed(2)} cycles`);
}

function requestRangeLoop(): void {
  const begin = cycleMilli(rangeStartEl.value);
  const end = cycleMilli(rangeEndEl.value);
  if (begin === null || end === null || end <= begin) {
    playback.report(new Error("Enter a valid range: start before end, in 0.001-cycle steps."));
    return;
  }
  void playback.loop(begin, end).catch(error => playback.report(error));
}


function applyStatus(state: PlaybackView): void {
  if (audioMode !== "scheduler") return;
  setText(statusEl, state.state === "Empty" ? "Ready" : state.state);
  statusEl.dataset.samplePosition = String(state.samplePosition);
  statusEl.dataset.cyclePosition = String(state.cyclePosition);
  statusEl.dataset.tempo = state.tempoText;
  statusEl.dataset.mode = state.mode;
  setText(positionEl, `Position: ${state.cyclePosition.toFixed(2)} cycles`);
  setText(tempoEl, state.mode === "none" ? "Not playing yet"
    : `${state.tempoText} BPM · ${state.mode === "pattern" ? "Pattern" : "Song"}`);
  draftStatusEl.dataset.state = state.draftStatus;
  draftStatusEl.dataset.version = versionLabel(state.draftVersion);
  const [headline, help] = changeMessage(state);
  setText(draftStatusEl, headline);
  setText(changeHelpEl, help);
  changeStatusEl.dataset.tone = state.state === "Fault" || state.draftStatus === "invalid" || state.draftStatus === "rejected"
    ? "error" : state.draftStatus === "accepted" && state.pendingCount === 0 && state.skippedCount === 0 ? "ok" : "neutral";
  setText(draftVersionEl, versionLabel(state.draftVersion));
  const accepted = state.acceptedVersion !== null
    ? `Accepted ${versionLabel(state.acceptedVersion)}`
    : state.currentSource !== null ? "Accepted untracked input" : "No accepted draft";
  const sending = state.inFlightVersions.length === 0 ? ""
    : ` · Sending ${state.inFlightVersions.map(version => version === null ? "untracked input" : versionLabel(version)).join(", ")}`;
  setText(draftVersionsEl, accepted + sending);
  materialStatusEl.dataset.pendingCount = String(state.pendingCount);
  materialStatusEl.dataset.skippedCount = String(state.skippedCount);
  const materials = state.pendingCount === 1 ? "1 material awaiting entry"
    : `${state.pendingCount} materials awaiting entry`;
  const skipped = state.skippedCount ? ` · ${state.skippedCount} skipped` : "";
  setText(materialStatusEl, state.currentSource === null ? "No accepted score"
    : (state.pendingCount ? materials : "No pending transitions") + skipped);
  const waiting = state.pendingCount === 1 ? "1 part is waiting to switch."
    : state.pendingCount > 1 ? `${state.pendingCount} parts are waiting to switch.` : "";
  const skippedChanges = state.skippedCount === 1 ? "1 change was skipped in this pass."
    : state.skippedCount > 1 ? `${state.skippedCount} changes were skipped in this pass.` : "";
  setText(changeTimingEl, [waiting, skippedChanges].filter(Boolean).join(" "));
  changeTimingEl.hidden = state.currentSource === null || (state.pendingCount === 0 && state.skippedCount === 0);
  startBtn.disabled = false;
  startBtn.textContent = state.state === "Playing" || state.state === "Starting" ? "Pause" : "Play";
  renderSections(state);
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
const draft = new Draft(INITIAL);
const playback = new Player(engine, { draft }, renderPlayback);
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
playbackDetailsEl.hidden = audioMode !== "scheduler";
loopRangeBtn.addEventListener("click", requestRangeLoop);
wholeSongBtn.addEventListener("click", () => {
  void playback.whole().catch(error => playback.report(error));
});


view.dispatch({
  effects: listenerCompartment.reconfigure([
    adapter.createUpdateListener(),
    EditorView.updateListener.of(update => {
      if (!update.docChanged || audioMode !== "scheduler") return;
      try {
        // Preserve each transaction's causality; composing a replace and undo
        // into one text diff would incorrectly revive retired source identities.
        for (const transaction of update.transactions) {
          if (!transaction.docChanged) continue;
          const edits: { from: number; to: number; inserted: string }[] = [];
          transaction.changes.iterChanges((from, to, _newFrom, _newTo, inserted) => {
            edits.push({ from, to, inserted: inserted.toString() });
          }, true);
          draft.edit({ base: draft.state().version, edits });
        }
        // Diagnostic decoration dispatch must happen outside CM's update turn.
        queueMicrotask(() => playback.editDraft());
      } catch (error) {
        queueMicrotask(() => playback.reportDraftFailure(error));
      }
    }),
  ]),
});

startBtn.addEventListener("click", () => {
  if (audioMode === "compiled") { void toggleCompiled(); return; }
  const state = playback.view().state;
  void (state === "Playing" || state === "Starting" ? playback.pause() : playback.play()).catch(error => playback.report(error));
});

document.getElementById("restart")!.addEventListener("click", () => {
  try {
    void playback.restart(draft.prepare()).catch(error => playback.report(error));
  } catch (error) {
    playback.reportDraftFailure(error);
  }
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
(document.getElementById("section-composition-example") as HTMLButtonElement).dataset.example = sectionComposition;

cheatToggle.addEventListener("click", () => {
  const collapsed = workspaceEl.classList.toggle("cheat-collapsed");
  cheatToggle.setAttribute("aria-expanded", String(!collapsed));
  cheatToggle.textContent = collapsed ? "Show help" : "Hide help";
});

cheatEl.addEventListener("click", (ev) => {
  const target = ev.target as HTMLElement;
  const link = target.closest<HTMLAnchorElement>('a[href^="#"]');
  if (link) {
    const destination = document.getElementById(link.hash.slice(1));
    if (!destination || !cheatEl.contains(destination)) return;
    ev.preventDefault();
    for (let ancestor: HTMLElement | null = destination; ancestor && ancestor !== cheatEl; ancestor = ancestor.parentElement) {
      if (ancestor instanceof HTMLDetailsElement) ancestor.open = true;
    }
    const focusTarget = destination instanceof HTMLDetailsElement
      ? destination.querySelector<HTMLElement>("summary") : destination;
    if (focusTarget) {
      if (focusTarget.tagName !== "SUMMARY") focusTarget.tabIndex = -1;
      focusTarget.focus({ preventScroll: true });
    }
    destination.scrollIntoView({ block: "start" });
    return;
  }
  const example = target.closest<HTMLElement>(".example");
  if (!example) return;
  const text = example.dataset.recipe
    ? document.getElementById(`${example.dataset.recipe}-code`)?.textContent
    : example.dataset.example;
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
