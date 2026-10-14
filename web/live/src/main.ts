// Editor intents feed the Player's debounced source updates.
// Current song and sounding material versions remain owned by the audio engine.

import { Compartment, EditorState, Prec } from "@codemirror/state";
import { EditorView, keymap, lineNumbers, highlightActiveLine } from "@codemirror/view";
import { defaultKeymap, historyKeymap, undo, redo, undoDepth, redoDepth, isolateHistory } from "@codemirror/commands";
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

import { minilive, miniliveLanguage } from "./lang/minilive";
import { inlineControls } from "./inline-controls";
import type * as PatternControls from "./pattern-controls";
import { loadScore, mountScoreSession } from "./score-session";
import { CM6Adapter } from "./canopy";
import type { Diagnostic } from "./canopy";
import { AudioEngine } from "./audio";
import type { AudioEngineMode, CompiledSession } from "./audio";
import type { Draft } from "./authoring";
import type { DraftVersion } from "./draft-version";
import type { Player, PlaybackView } from "./playback";
import { mountOutputScope } from "./output-scope";
import { mountScoreLink } from "./score-link";
import { playbackHighlights } from "./playback-highlights";
import { mountPlaybackObservation } from "./playback-observation";
import { phraseUpdateStatus, renderPhraseUpdateStatus } from "./phrase-update-status";
import "./phrase-update-status.css";

const STARTERS = {
  "first-light": {
    name: "First light",
    source: `bpm(96);

$: s("bd ~ sd ~ bd bd sd ~").slow(4)
$: s("hh hh hh hh hh hh hh hh").slow(4)
$: note("C4 ~ Eb4 G4 Bb4 ~ G4 Eb4").slow(4).gain(0.25).lpf(1800)`,
  },
  offbeat: {
    name: "Offbeat",
    source: `bpm(112);

$: s("bd ~ ~ bd sd ~ bd ~").slow(4)
$: s("~ hh ~ hh ~ hh ~ oh").slow(4)
$: note("C3 ~ C3 Eb3 ~ G3 Bb3 ~").slow(4).gain(0.3).lpf(1200)`,
  },
  moonrise: {
    name: "Moonrise",
    source: `bpm(104);

$: s("bd ~ ~ bd sd ~ bd ~, hh*8").slow(4)
$: note("A2 ~ A2 C3 ~ E3 G2 ~").slow(4).gain(0.3).lpf(900)
$: chord("Am7 Fmaj7 Cmaj7 G").slow(16).gain(0.12).lpf(1400)
$: note("E5 ~ C5 D5 ~ B4 G4 A4").slow(8).gain(0.16).lpf(3200)`,
  },
  "slow-drift": {
    name: "Slow drift",
    source: `bpm(72);

$: s("bd ~ ~ ~ sd ~ ~ ~").slow(4)
$: note("C4 ~ G4 ~ Eb4 ~ Bb4 ~").slow(4).gain(0.2).lpf(2400)
$: chord("Cm7 Abmaj7").slow(8).gain(0.12).lpf(900)`,
  },
} as const;
const INITIAL = loadScore(STARTERS["first-light"].source);
let patternTools: typeof PatternControls | undefined;

function initialCursor(source: string): number {
  let firstNote: number | undefined;
  miniliveLanguage.parser.parse(source).iterate({ enter(ref) {
    if (firstNote !== undefined || ref.name !== "Chain") return;
    const call = ref.node.getChild("Call");
    const name = call?.getChild("CallName");
    if (!name || !call?.getChild("Args")?.getChild("String")) return;
    if (["note", "chord"].includes(source.slice(name.from, name.to))) firstNote = ref.from;
  } });
  return firstNote ?? Math.max(0, source.indexOf("$:"));
}

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
const cheatEl = document.getElementById("cheat") as HTMLDialogElement;
const cheatToggle = document.getElementById("cheat-toggle") as HTMLButtonElement;
const workspaceEl = document.querySelector("main.workspace") as HTMLElement;
const readinessEl = document.getElementById("score-readiness") as HTMLElement;

// ── Editor ──────────────────────────────────────────────────

const listenerCompartment = new Compartment();
const controlsCompartment = new Compartment();
const patternCompartment = new Compartment();
const contentAttributesCompartment = new Compartment();
let draft: Draft | undefined;
let playback: Player | undefined;
let disposed = false;

const view = new EditorView({
  parent: editorEl,
  state: EditorState.create({
    doc: INITIAL,
    selection: { anchor: initialCursor(INITIAL) },
    extensions: [
      lineNumbers(),
      highlightActiveLine(),
      bracketMatching(),
      closeBrackets(),
      inlineControls(),
      patternCompartment.of([]),
      phraseUpdateStatus(),
      playbackHighlights(),
      controlsCompartment.of([]),
      EditorView.lineWrapping,
      contentAttributesCompartment.of(EditorView.contentAttributes.of({
        "aria-label": "Music code", spellcheck: "false",
      })),
      keymap.of([
        { key: "Mod-Enter", scope: "editor pattern-control", run: () => { startBtn.click(); return true; } },
        { key: "Mod-Shift-Enter", scope: "editor pattern-control", run: () => { document.getElementById("restart")!.click(); return true; } },
      ]),
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
const scoreSession = mountScoreSession(view);
const undoBtn = document.getElementById("undo") as HTMLButtonElement;
const redoBtn = document.getElementById("redo") as HTMLButtonElement;
const sourceToggle = document.getElementById("source-toggle") as HTMLButtonElement;

function refreshEditorChrome(): void {
  undoBtn.disabled = undoDepth(view.state) === 0;
  redoBtn.disabled = redoDepth(view.state) === 0;
  const head = view.state.selection.main.head;
  const line = view.state.doc.lineAt(head);
  setText(document.getElementById("cursor-position")!, `Ln ${line.number}, Col ${head - line.from + 1}`);
  const text = view.state.doc.toString();
  const starter = Object.entries(STARTERS).find(([, value]) => value.source === text);
  setText(document.getElementById("score-title")!, starter?.[1].name ?? "Your score");
  document.querySelectorAll<HTMLButtonElement>("[data-scene]").forEach(button =>
    button.setAttribute("aria-pressed", String(button.dataset.scene === starter?.[0])));
}

function replaceScore(source: string): void {
  view.dispatch({
    changes: { from: 0, to: view.state.doc.length, insert: source },
    selection: { anchor: initialCursor(source) },
    annotations: isolateHistory.of("full"),
  });
  view.focus();
}

undoBtn.addEventListener("click", () => { undo(view); view.focus(); });
redoBtn.addEventListener("click", () => { redo(view); view.focus(); });
sourceToggle.addEventListener("click", () => {
  const enabled = sourceToggle.getAttribute("aria-pressed") !== "true";
  sourceToggle.setAttribute("aria-pressed", String(enabled));
  if (patternTools) {
    view.dispatch({ effects: controlsCompartment.reconfigure(patternTools.patternControlsVisible.of(enabled)) });
  }
});
refreshEditorChrome();


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
  enableOnsets: urlParams.get("onsets") !== "0",
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
  logEl.hidden = message.length === 0;
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

function applyStatus(state: PlaybackView): void {
  if (audioMode !== "scheduler") return;
  setText(statusEl, state.state === "Empty" ? "Ready" : state.state);
  document.body.dataset.playback = state.state.toLowerCase();
  const progress = document.getElementById("cycle-progress")!;
  progress.style.transform = `scaleX(${state.cyclePosition - Math.floor(state.cyclePosition)})`;
  document.getElementById("restore-score")!.hidden = state.currentSource === null ||
    (state.draftStatus !== "invalid" && state.draftStatus !== "rejected");
  statusEl.dataset.samplePosition = String(state.samplePosition);
  statusEl.dataset.cyclePosition = String(state.cyclePosition);
  statusEl.dataset.tempo = state.tempoText;
  statusEl.dataset.mode = state.mode;
  setText(positionEl, `Position: ${state.cyclePosition.toFixed(2)} cycles`);
  setText(tempoEl, state.mode === "none" ? ""
    : `${state.tempoText} BPM · ${state.mode === "pattern" ? "Pattern" : "Song"}`);
  draftStatusEl.dataset.state = state.draftStatus;
  draftStatusEl.dataset.version = versionLabel(state.draftVersion);
  const [headline, help] = changeMessage(state);
  setText(draftStatusEl, headline);
  setText(changeHelpEl, help);
  changeHelpEl.hidden = state.draftStatus !== "invalid" && state.draftStatus !== "rejected" && state.state !== "Fault";
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
  startBtn.dataset.action = state.state === "Playing" || state.state === "Starting" ? "pause" : "play";
}
function diagnosticFromError(raw: string, docLength: number): Diagnostic {
  const match = /^position (\d+):\s*(.*)$/.exec(raw);
  const position = match ? Math.min(Number.parseInt(match[1], 10), docLength) : 0;
  return { from: Math.max(0, position - (position === docLength ? 1 : 0)), to: Math.max(1, Math.min(docLength, position + 1)), severity: "error", message: match?.[2] || raw };
}
let renderedPlayback: PlaybackView | undefined;

let playbackObservation: ReturnType<typeof mountPlaybackObservation> | undefined;
function renderPlayback(state: PlaybackView): void {
  renderPhraseUpdateStatus(view, state);
  applyStatus(state);
  playbackObservation?.setPlaying(audioMode === "scheduler" && state.state === "Playing");
  if (state.feedback !== renderedPlayback?.feedback) {
    setLog(state.feedback?.message ?? "", state.feedback?.kind ?? "info");
  }
  if (state.diagnostic !== renderedPlayback?.diagnostic) {
    const diagnostic = state.diagnostic;
    adapter.applyPatches([{ type: "SetDiagnostics", diagnostics: diagnostic ? [diagnosticFromError(diagnostic.message, diagnostic.documentLength)] : [] }]);
  }
  renderedPlayback = state;
}
let compiledSession: CompiledSession | undefined;
const outputScope = mountOutputScope(document.getElementById("output-scope")!, {
  readWaveform: target => engine.readWaveform(target),
});
const scoreLink = mountScoreLink(view, document.getElementById("share-score") as HTMLButtonElement | null);
if (import.meta.hot) import.meta.hot.dispose(() => {
  disposed = true;
  cancelAnimationFrame(startupFrame);
  clearTimeout(startupTimer);
  clearTimeout(readinessNoticeTimer);
  playbackObservation?.dispose();
  view.destroy();
  outputScope.dispose();
  scoreLink.dispose();
  scoreSession.dispose();
});
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


view.dispatch({
  effects: listenerCompartment.reconfigure([
    adapter.createUpdateListener(),
    EditorView.updateListener.of(update => {
      if (update.docChanged) scoreSession.changed();
      if (update.docChanged || update.selectionSet) refreshEditorChrome();
      if (!update.docChanged || audioMode !== "scheduler" || !draft || !playback) return;
      const activeDraft = draft;
      const activePlayback = playback;
      try {
        // Preserve each transaction's causality; composing a replace and undo
        // into one text diff would incorrectly revive retired source identities.
        for (const transaction of update.transactions) {
          if (!transaction.docChanged) continue;
          const edits: { from: number; to: number; inserted: string }[] = [];
          transaction.changes.iterChanges((from, to, _newFrom, _newTo, inserted) => {
            edits.push({ from, to, inserted: inserted.toString() });
          }, true);
          activeDraft.edit({ base: activeDraft.state().version, edits });
        }
        playbackObservation?.edited();
        // Diagnostic decoration dispatch must happen outside CM's update turn.
        queueMicrotask(() => activePlayback.editDraft());
      } catch (error) {
        queueMicrotask(() => activePlayback.reportDraftFailure(error));
      }
    }),
  ]),
});

startBtn.addEventListener("click", () => {
  if (audioMode === "compiled") { void toggleCompiled(); return; }
  if (!playback) return;
  const activePlayback = playback;
  const state = activePlayback.view().state;
  void (state === "Playing" || state === "Starting" ? activePlayback.pause() : activePlayback.play()).catch(error => activePlayback.report(error));
});

document.getElementById("restart")!.addEventListener("click", () => {
  if (!playback || !draft) return;
  const activePlayback = playback;
  try {
    void activePlayback.restart(draft.prepare()).catch(error => activePlayback.report(error));
  } catch (error) {
    activePlayback.reportDraftFailure(error);
  }
});

document.getElementById("restore-score")!.addEventListener("click", () => {
  const source = playback?.view().currentSource ?? null;
  if (source !== null) replaceScore(source);
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

const narrowHelp = window.matchMedia("(max-width: 760px)");
function setHelp(open: boolean): void {
  workspaceEl.classList.toggle("cheat-collapsed", !open);
  cheatEl.inert = !open;
  cheatToggle.setAttribute("aria-expanded", String(open));
  if (open && !cheatEl.open) {
    if (narrowHelp.matches) cheatEl.showModal();
    else cheatEl.show();
  } else if (!open && cheatEl.open) {
    cheatEl.close();
    cheatToggle.focus();
  }
}
cheatToggle.addEventListener("click", () => setHelp(!cheatEl.open));
document.getElementById("close-help")!.addEventListener("click", () => setHelp(false));
cheatEl.addEventListener("cancel", event => { event.preventDefault(); setHelp(false); });
cheatEl.addEventListener("keydown", event => {
  if (event.key === "Escape") { event.preventDefault(); setHelp(false); }
});
narrowHelp.addEventListener("change", () => {
  if (!cheatEl.open) return;
  cheatEl.close();
  setHelp(true);
});

document.querySelectorAll<HTMLButtonElement>("[data-scene]").forEach(button => {
  button.addEventListener("click", () => {
    const starter = STARTERS[button.dataset.scene as keyof typeof STARTERS];
    if (!starter) return;
    if (narrowHelp.matches) setHelp(false);
    replaceScore(starter.source);
    if (audioMode !== "scheduler" || !playback || !draft) return;
    const activePlayback = playback;
    try {
      void activePlayback.restart(draft.prepare()).catch(error => activePlayback.report(error));
    } catch (error) {
      activePlayback.reportDraftFailure(error);
    }
  });
});

cheatEl.addEventListener("click", (ev) => {
  const target = ev.target as HTMLElement;
  const example = target.closest<HTMLElement>(".example");
  if (!example) return;
  const text = example.dataset.example;
  if (!text) return;
  if (narrowHelp.matches) setHelp(false);
  replaceScore(text);
});

// Keep editing and saving independent of the compiler's network/evaluation time.
const restartBtn = document.getElementById("restart") as HTMLButtonElement;
document.body.dataset.authoring = "loading";
sourceToggle.disabled = true;
restartBtn.disabled = true;
if (audioMode === "scheduler") {
  startBtn.disabled = true;
  startBtn.setAttribute("aria-busy", "true");
}
sourceToggle.setAttribute("aria-busy", "true");
changeStatusEl.hidden = true;

function showReadiness(message: string): void {
  setText(readinessEl, message);
  readinessEl.hidden = false;
  view.dispatch({
    effects: contentAttributesCompartment.reconfigure(EditorView.contentAttributes.of({
      "aria-label": "Music code", "aria-describedby": "score-readiness", spellcheck: "false",
    })),
  });
}

// Short startup should not flash loading labels; editing remains available.
const readinessNoticeTimer = window.setTimeout(() => {
  if (!disposed && document.body.dataset.authoring === "loading") {
    showReadiness("Code is editable. Loading score tools…");
  }
}, 500);

async function prepareAuthoring(): Promise<void> {
  let createdDraft: Draft | undefined;
  try {
    const [authoring, player, controls] = await Promise.all([
      import("./authoring"),
      import("./playback"),
      import("./pattern-controls"),
    ]);
    if (disposed) return;
    // No await between reading the document and installing its edit listener.
    createdDraft = new authoring.Draft(view.state.doc.toString());
    draft = createdDraft;
    playback = new player.Player(engine, { draft }, renderPlayback);
    playbackObservation = mountPlaybackObservation(view, draft, engine, error => {
      setLog(`Playback highlighting: ${error instanceof Error ? error.message : String(error)}`, "error");
    });
    patternTools = controls;
    view.dispatch({
      // Adding notation must not move the user's selection to a startup phrase.
      effects: [
        view.scrollSnapshot(),
        patternCompartment.reconfigure(controls.patternControls()),
        controlsCompartment.reconfigure(controls.patternControlsVisible.of(sourceToggle.getAttribute("aria-pressed") === "true")),
        contentAttributesCompartment.reconfigure(EditorView.contentAttributes.of({
          "aria-label": "Music code", spellcheck: "false",
        })),
      ],
    });
    document.body.dataset.authoring = "ready";
    clearTimeout(readinessNoticeTimer);
    sourceToggle.disabled = false;
    restartBtn.disabled = false;
    readinessEl.hidden = true;
    changeStatusEl.hidden = false;
    sourceToggle.removeAttribute("aria-busy");
    sourceToggle.title = "Show controls for the phrase at your cursor";
    startBtn.removeAttribute("aria-busy");
    startBtn.title = "Play or pause · Ctrl/⌘ + Enter";
    restartBtn.title = "Restart the current score from the beginning";
    refreshEditorChrome();
  } catch (error) {
    if (disposed) { createdDraft?.dispose(); return; }
    playbackObservation?.dispose();
    playbackObservation = undefined;
    createdDraft?.dispose();
    draft = undefined;
    playback = undefined;
    patternTools = undefined;
    document.body.dataset.authoring = "failed";
    clearTimeout(readinessNoticeTimer);
    sourceToggle.disabled = true;
    restartBtn.disabled = true;
    if (audioMode === "scheduler") {
      startBtn.disabled = true;
      startBtn.textContent = "Play";
      startBtn.dataset.action = "play";
      setText(statusEl, "Playback unavailable");
      startBtn.title = "Playback unavailable. Reload to try again; code remains editable.";
      restartBtn.title = startBtn.title;
    }
    startBtn.removeAttribute("aria-busy");
    sourceToggle.removeAttribute("aria-busy");
    sourceToggle.title = "Score tools unavailable. Reload to try again; code remains editable.";
    showReadiness("Code is editable. Score tools unavailable.");
    changeStatusEl.hidden = false;
    setText(draftStatusEl, "Playback unavailable");
    setText(draftVersionEl, "Unavailable");
    setLog(`Could not load score tools. Reload to try again. ${error instanceof Error ? error.message : String(error)}`, "error");
    refreshEditorChrome();
  }
}

// A task after the first animation frame lets the basic editor paint first.
let startupTimer: number | undefined;
const startupFrame = requestAnimationFrame(() => {
  startupTimer = window.setTimeout(() => { if (!disposed) void prepareAuthoring(); }, 0);
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
console.info("[moondsp/live] basic editor ready — preparing score tools");
