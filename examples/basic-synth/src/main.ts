import { createAudio } from "./audio";
import { readPage, createDomConnection, reportStartupFailure, type PageElements, type PageBindings } from "./dom";
import { andThen, attempt, type Result } from "./result";
import { DEFAULT_SETTINGS } from "./synth";
import "./style.css";

// Page-specific names live at the composition root, not inside DOM actions.
const PAGE_BINDINGS: PageBindings = {
  selectors: {
    powerButton: "#power-audio",
    powerLabel: "#power-label",
    status: "#audio-status",
    errorPanel: "#audio-error",
    errorMessage: "#error-message",
    volumeInput: "#volume",
    volumeValue: "#volume-value",
    cutoffInput: "#cutoff",
    cutoffValue: "#cutoff-value",
    activeNoteDisplay: "#active-note-display",
    activeNoteOutput: "#active-note",
    keyboardScroll: "#piano-scroll",
    keyboardNavigation: "#keyboard-navigation",
    lowerNotesButton: "#lower-notes",
    higherNotesButton: "#higher-notes",
    keyboard: ".keyboard",
    noteButtons: ".key[data-midi]",
    noteName: ".note-name",
    editable: "input, select, textarea, [contenteditable=\"true\"]",
  },
  classes: {
    heldNote: "is-held",
    activeNote: "is-active",
  },
  data: {
    midi: "midi",
    computerKey: "computerKey",
    phase: "state",
    activeNote: "active",
  },
};

function startApplication(elements: PageElements, bindings: PageBindings): Result<void> {
  return attempt(() => {
    const dom = createDomConnection(elements, DEFAULT_SETTINGS, bindings);
    const audio = createAudio(dom.view, dom.settings);
    dom.connect(audio);
  });
}

// A failed acquisition skips every subsequent action, including audio creation.
const started = andThen(readPage(document, PAGE_BINDINGS), elements => startApplication(elements, PAGE_BINDINGS));
if (!started.ok) reportStartupFailure(document, started.error, PAGE_BINDINGS.selectors);
