import type { HelpExamplesHost } from "./help-examples";
import type { OutputScopeHost } from "./output-scope";
import type { ScoreLinkElements } from "./score-link";
import type { ScoreSessionElements } from "./score-session";
import type { SignalHorizonHost } from "./signal-horizon";
import type { TransportElements } from "./transport-status";

// The workspace's only DOM lookup. main.ts calls it once at startup, after
// index.html has been parsed. Elements are grouped by the shell that owns them,
// in the host shape that shell declares; every element is required.

function required<T extends Element>(doc: Document, id: string, type: abstract new (...args: never[]) => T): T {
  const element = doc.getElementById(id);
  if (!(element instanceof type)) throw new Error(`moondsp workspace is missing #${id}`);
  return element;
}

export type WorkspaceDom = ReturnType<typeof queryWorkspaceDom>;

export function queryWorkspaceDom(doc: Document) {
  const view = doc.defaultView!;
  const workspace = doc.querySelector("main.workspace");
  if (!(workspace instanceof HTMLElement)) throw new Error("moondsp workspace is missing main.workspace");
  const reducedMotion = view.matchMedia("(prefers-reduced-motion: reduce)");
  const button = (id: string): HTMLButtonElement => required(doc, id, HTMLButtonElement);
  const element = (id: string): HTMLElement => required(doc, id, HTMLElement);

  const transport: TransportElements = {
    body: doc.body,
    start: button("start"),
    restart: button("restart"),
    sourceToggle: button("source-toggle"),
    status: element("status"),
    tempo: element("playback-tempo"),
    position: element("playback-position"),
    restoreScore: button("restore-score"),
    readiness: element("score-readiness"),
    changeStatus: element("change-status"),
    draftStatus: element("draft-status"),
    changeHelp: element("change-help"),
    changeTiming: element("change-timing"),
    draftVersion: element("draft-version"),
    draftVersions: element("draft-versions"),
    materialStatus: element("material-status"),
  };
  const horizon: SignalHorizonHost = {
    root: element("signal-horizon"),
    visibility: doc,
    reducedMotion,
    colorScheme: view.matchMedia("(prefers-color-scheme: dark)"),
  };
  const outputScope: OutputScopeHost = { root: element("output-scope"), visibility: doc, reducedMotion };
  const session: ScoreSessionElements = {
    saveStatus: element("save-status"),
    saveButton: button("save-score"),
    openButton: button("open-score"),
    fileInput: required(doc, "score-file", HTMLInputElement),
    recoveryPanel: required(doc, "saved-drafts", HTMLDetailsElement),
    recoverySummary: element("saved-drafts-summary"),
    recoveryList: element("saved-draft-list"),
    page: view,
  };
  const share: ScoreLinkElements = { button: button("share-score"), page: view };
  const examples: HelpExamplesHost = {
    sounds: element("starting-sounds"),
    featured: element("examples"),
    more: element("more-examples"),
  };

  return {
    /** The window, for shells that watch the page itself rather than an element. */
    page: view,
    editor: element("editor"),
    transport,
    horizon,
    outputScope,
    session,
    share,
    sessionMessage: element("session-message"),
    log: element("log"),
    edit: {
      undo: button("undo"),
      redo: button("redo"),
      cursorPosition: element("cursor-position"),
    },
    help: {
      workspace,
      dialog: required(doc, "cheat", HTMLDialogElement),
      toggle: button("cheat-toggle"),
      close: button("close-help"),
      narrow: view.matchMedia("(max-width: 760px)"),
      examples,
    },
  };
}
