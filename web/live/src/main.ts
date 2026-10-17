// Editor intents feed the Player's debounced source updates.
// Current song and sounding material versions remain owned by the audio engine.

import { Compartment, EditorState, Prec } from "@codemirror/state";
import { EditorView, keymap, lineNumbers, highlightActiveLine, placeholder } from "@codemirror/view";
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
import type { Draft } from "./authoring";
import type { Player, PlaybackView } from "./playback";
import { mountOutputScope } from "./output-scope";
import { mountSignalHorizon } from "./signal-horizon";
import { mountScoreLink } from "./score-link";
import { queryWorkspaceDom } from "./workspace-dom";
import { authoringView, statusView, type AuthoringPhase } from "./status-view";
import { setText, writeAuthoring, writeStatus } from "./transport-status";
import { engineOptions } from "./engine-options";
import { mountNotice } from "./notice";
import { createScope } from "./scope";
import { playbackHighlights } from "./playback-highlights";
import { mountPlaybackObservation } from "./playback-observation";
import { playbackChanged } from "./phrase-update-status";
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

// The only DOM lookup: every shell below receives resolved elements.
const dom = queryWorkspaceDom(document);
// Everything mounted below is owned here and released newest first.
const scope = createScope();
const notice = scope.own(mountNotice(dom.sessionMessage));

// ── Editor ──────────────────────────────────────────────────

const listenerCompartment = new Compartment();
const controlsCompartment = new Compartment();
const patternCompartment = new Compartment();
const contentAttributesCompartment = new Compartment();
/** Score tools: the draft, its player, and the score controls, present together once they load. */
type Tools = Readonly<{ draft: Draft; playback: Player; observation: ReturnType<typeof mountPlaybackObservation>; controls: typeof PatternControls }>;
let tools: Tools | null = null;
let disposed = false;

const view = new EditorView({
  parent: dom.editor,
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
      playbackHighlights(),
      controlsCompartment.of([]),
      EditorView.lineWrapping,
      placeholder('s("bd ~ sd ~")'),
      contentAttributesCompartment.of(EditorView.contentAttributes.of({
        "aria-label": "Music code", spellcheck: "false",
      })),
      keymap.of([
        { key: "Mod-Enter", scope: "editor pattern-control", run: () => { dom.transport.start.click(); return true; } },
        { key: "Mod-Shift-Enter", scope: "editor pattern-control", run: () => { dom.transport.restart.click(); return true; } },
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
scope.own({ dispose: () => view.destroy() });

const adapter = new CM6Adapter(view);
const scoreSession = scope.own(mountScoreSession(dom.session, { view, notice }));

function refreshEditorChrome(): void {
  dom.edit.undo.disabled = undoDepth(view.state) === 0;
  dom.edit.redo.disabled = redoDepth(view.state) === 0;
  const head = view.state.selection.main.head;
  const line = view.state.doc.lineAt(head);
  setText(dom.edit.cursorPosition, `Ln ${line.number}, Col ${head - line.from + 1}`);
  const text = view.state.doc.toString();
  const starter = Object.entries(STARTERS).find(([, value]) => value.source === text);
  dom.help.sceneButtons.forEach(button =>
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

dom.edit.undo.addEventListener("click", () => { undo(view); view.focus(); });
dom.edit.redo.addEventListener("click", () => { redo(view); view.focus(); });
dom.transport.sourceToggle.addEventListener("click", () => {
  const enabled = dom.transport.sourceToggle.getAttribute("aria-pressed") !== "true";
  dom.transport.sourceToggle.setAttribute("aria-pressed", String(enabled));
  if (tools) view.dispatch({ effects: controlsCompartment.reconfigure(tools.controls.patternControlsVisible.of(enabled)) });
});
refreshEditorChrome();


// ── Engine ──────────────────────────────────────────────────

const options = engineOptions(new URLSearchParams(window.location.search));
const engine = new AudioEngine("/moonbit_dsp.wasm", options);


function setLog(message: string, kind: "ok" | "error" | "info" = "info"): void {
  dom.log.textContent = message;
  dom.log.hidden = message.length === 0;
  dom.log.classList.toggle("error", kind === "error");
  dom.log.classList.toggle("ok", kind === "ok");
}


function applyStatus(state: PlaybackView): void {
  const status = statusView(state);
  writeStatus(dom.transport, status);
  signalHorizon.setCycle(state.cyclePosition, status.playing);
}
function diagnosticFromError(raw: string, docLength: number): Diagnostic {
  const match = /^position (\d+):\s*(.*)$/.exec(raw);
  const position = match ? Math.min(Number.parseInt(match[1], 10), docLength) : 0;
  return { from: Math.max(0, position - (position === docLength ? 1 : 0)), to: Math.max(1, Math.min(docLength, position + 1)), severity: "error", message: match?.[2] || raw };
}
let renderedPlayback: PlaybackView | undefined;

function renderPlayback(state: PlaybackView): void {
  view.dispatch({ effects: playbackChanged.of(state) });
  applyStatus(state);
  tools?.observation.setPlaying(state.state === "Playing");
  if (state.feedback !== renderedPlayback?.feedback) {
    setLog(state.feedback?.message ?? "", state.feedback?.kind ?? "info");
  }
  if (state.diagnostic !== renderedPlayback?.diagnostic) {
    const diagnostic = state.diagnostic;
    adapter.applyPatches([{ type: "SetDiagnostics", diagnostics: diagnostic ? [diagnosticFromError(diagnostic.message, diagnostic.documentLength)] : [] }]);
  }
  renderedPlayback = state;
}
scope.own(mountOutputScope(dom.outputScope, engine));
const signalHorizon = scope.own(mountSignalHorizon(dom.horizon, engine));
scope.own(mountScoreLink(dom.share, { view, notice }));
if (import.meta.hot) import.meta.hot.dispose(() => {
  disposed = true;
  scope.dispose();
});


view.dispatch({
  effects: listenerCompartment.reconfigure([
    adapter.createUpdateListener(),
    EditorView.updateListener.of(update => {
      if (update.docChanged) scoreSession.changed();
      if (update.docChanged || update.selectionSet) refreshEditorChrome();
      if (!update.docChanged || !tools) return;
      const { draft: activeDraft, playback: activePlayback, observation } = tools;
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
        observation.edited();
        // Diagnostic decoration dispatch must happen outside CM's update turn.
        queueMicrotask(() => activePlayback.editDraft());
      } catch (error) {
        queueMicrotask(() => activePlayback.reportDraftFailure(error));
      }
    }),
  ]),
});

/** Play the editor's score from the beginning. */
function restart({ draft, playback }: Tools): void {
  try {
    void playback.restart(draft.prepare()).catch(error => playback.report(error));
  } catch (error) {
    playback.reportDraftFailure(error);
  }
}

dom.transport.start.addEventListener("click", () => {
  if (!tools) return;
  const { playback } = tools;
  const state = playback.view().state;
  void (state === "Playing" || state === "Starting" ? playback.pause() : playback.play()).catch(error => playback.report(error));
});

dom.transport.restart.addEventListener("click", () => { if (tools) restart(tools); });

dom.transport.restoreScore.addEventListener("click", () => {
  const source = tools?.playback.view().currentSource ?? null;
  if (source !== null) replaceScore(source);
});

// ── Cheatsheet ──────────────────────────────────────────────
dom.help.examples.roomOfLight.dataset.example = roomOfLight;
dom.help.examples.envelopeCompare.dataset.example = envelopeComparison;
dom.help.examples.sharedRoom.dataset.example = sharedRoomComparison;
dom.help.examples.sharedRoomAfterglow.dataset.example = sharedRoomAfterglow;
dom.help.examples.overlayGroove.dataset.example = `bpm(96);\n${overlayGroove}`;
dom.help.examples.lightOrbit.dataset.example = `bpm(120);\n${lightOrbit}`;
dom.help.examples.overlayGrouping.dataset.example = overlayGrouping;
dom.help.examples.restsAndGates.dataset.example = `bpm(96);\n${restsAndGates}`;

function setHelp(open: boolean): void {
  dom.help.workspace.classList.toggle("cheat-collapsed", !open);
  dom.help.dialog.inert = !open;
  dom.help.toggle.setAttribute("aria-expanded", String(open));
  if (open && !dom.help.dialog.open) {
    if (dom.help.narrow.matches) dom.help.dialog.showModal();
    else dom.help.dialog.show();
  } else if (!open && dom.help.dialog.open) {
    dom.help.dialog.close();
    dom.help.toggle.focus();
  }
}
dom.help.toggle.addEventListener("click", () => setHelp(!dom.help.dialog.open));
dom.help.close.addEventListener("click", () => setHelp(false));
dom.help.dialog.addEventListener("cancel", event => { event.preventDefault(); setHelp(false); });
dom.help.dialog.addEventListener("keydown", event => {
  if (event.key === "Escape") { event.preventDefault(); setHelp(false); }
});
dom.help.narrow.addEventListener("change", () => {
  if (!dom.help.dialog.open) return;
  dom.help.dialog.close();
  setHelp(true);
});

dom.help.sceneButtons.forEach(button => {
  button.addEventListener("click", () => {
    const starter = STARTERS[button.dataset.scene as keyof typeof STARTERS];
    if (!starter) return;
    if (dom.help.narrow.matches) setHelp(false);
    replaceScore(starter.source);
    if (tools) restart(tools);
  });
});

dom.help.dialog.addEventListener("click", (ev) => {
  const target = ev.target as HTMLElement;
  const example = target.closest<HTMLElement>(".example");
  if (!example) return;
  const text = example.dataset.example;
  if (!text) return;
  if (dom.help.narrow.matches) setHelp(false);
  replaceScore(text);
});

// Keep editing and saving independent of the compiler's network/evaluation time.
let authoringPhase: AuthoringPhase = "starting";
function setAuthoring(phase: AuthoringPhase): void {
  authoringPhase = phase;
  const authoring = authoringView(phase);
  writeAuthoring(dom.transport, authoring);
  // The editor names the readiness notice while it is shown.
  view.dispatch({
    effects: contentAttributesCompartment.reconfigure(EditorView.contentAttributes.of({
      "aria-label": "Music code", spellcheck: "false",
      ...(authoring.readiness !== null ? { "aria-describedby": "score-readiness" } : {}),
    })),
  });
}
setAuthoring("starting");

// Short startup should not flash loading labels; editing remains available.
const readinessNoticeTimer = window.setTimeout(() => {
  if (authoringPhase === "starting") setAuthoring("loading");
}, 500);
scope.own({ dispose: () => clearTimeout(readinessNoticeTimer) });

async function prepareAuthoring(): Promise<void> {
  let createdDraft: Draft | undefined;
  let observation: Tools["observation"] | undefined;
  try {
    const [authoring, player, controls] = await Promise.all([
      import("./authoring"),
      import("./playback"),
      import("./pattern-controls"),
    ]);
    if (disposed) return;
    // No await between reading the document and installing its edit listener.
    const draft = createdDraft = new authoring.Draft(view.state.doc.toString());
    const playback = new player.Player(engine, { draft }, renderPlayback);
    observation = scope.own(mountPlaybackObservation(view, draft, engine, error => {
      setLog(`Playback highlighting: ${error instanceof Error ? error.message : String(error)}`, "error");
    }));
    tools = { draft, playback, observation, controls };
    view.dispatch({
      // Adding notation must not move the user's selection to a startup phrase.
      effects: [
        view.scrollSnapshot(),
        patternCompartment.reconfigure(controls.patternControls()),
        controlsCompartment.reconfigure(controls.patternControlsVisible.of(dom.transport.sourceToggle.getAttribute("aria-pressed") === "true")),
      ],
    });
    setAuthoring("ready");
    refreshEditorChrome();
  } catch (error) {
    if (disposed) { createdDraft?.dispose(); return; }
    observation?.dispose();
    createdDraft?.dispose();
    tools = null;
    setAuthoring("failed");
    setLog(`Could not load score tools. Reload to try again. ${error instanceof Error ? error.message : String(error)}`, "error");
    refreshEditorChrome();
  }
}

// A task after the first animation frame lets the basic editor paint first.
let startupTimer: number | undefined;
const startupFrame = requestAnimationFrame(() => {
  startupTimer = window.setTimeout(() => { void prepareAuthoring(); }, 0);
});
scope.own({ dispose: () => { cancelAnimationFrame(startupFrame); clearTimeout(startupTimer); } });

// End-to-end builds (`npm run build:e2e`) expose the engine so tests can drive
// its lifecycle and inject worklet faults the page cannot cause. Production
// builds drop this branch.
declare global {
  interface Window {
    __moondspEngine?: AudioEngine;
  }
}
if (import.meta.env.MODE === "e2e") window.__moondspEngine = engine;

// eslint-disable-next-line no-console
console.info("[moondsp/live] basic editor ready — preparing score tools");
