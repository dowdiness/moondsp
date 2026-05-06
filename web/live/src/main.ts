// moondsp · live · phase A bootstrap
//
// Mounts a CodeMirror 6 editor and wires it through Canopy's CM6Adapter.
// No engine yet — TextEdit intents are logged to the footer panel.
// Next commit: debounce → wasm parse → graph hot-swap → last-good fallback.

import { Compartment, EditorState } from "@codemirror/state";
import { EditorView, keymap, lineNumbers, highlightActiveLine } from "@codemirror/view";
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import { bracketMatching } from "@codemirror/language";

import { CM6Adapter } from "./canopy";
import type { UserIntent } from "./canopy";

const INITIAL = `s("bd sd hh sd").fast(2)`;

const editorEl = document.getElementById("editor") as HTMLElement;
const logEl = document.getElementById("log") as HTMLElement;

// Compartment lets us inject the adapter's updateListener after the view exists.
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

adapter.onIntent((intent: UserIntent) => {
  // Bootstrap: just log. Next commit replaces this with debounce + engine call.
  if (intent.type === "TextEdit") {
    logEl.textContent = `TextEdit @${intent.from}-${intent.to}: "${intent.insert.replace(/\n/g, "\\n")}"`;
  } else if (intent.type === "SetCursor") {
    logEl.textContent = `cursor @${intent.position}`;
  } else {
    logEl.textContent = intent.type;
  }
});

// eslint-disable-next-line no-console
console.info("[moondsp/live] CM6 + CM6Adapter mounted; engine wiring pending");
