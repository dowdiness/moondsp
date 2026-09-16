import assert from "node:assert/strict";
import test from "node:test";

import {
  ACTIVATION_RELEASE_MS,
  createNoteInput,
  createPointerSessions,
  interpretActivationClick,
  interpretComputerKeyDown,
  interpretComputerKeyUp,
  interpretFocusedBlur,
  interpretFocusedKeyDown,
  interpretFocusedKeyUp,
} from "./input";
import type { NoteAction } from "./keyboard";
import { MIDI_BY_KEY, NOTES, activeNoteName, noteAriaLabel, noteDescription } from "./notes";

test("notes table covers C4 through C5 with unique keys", () => {
  assert.equal(NOTES.length, 13);
  assert.equal(NOTES[0]?.midi, 60);
  assert.equal(NOTES.at(-1)?.midi, 72);
  assert.equal(new Set(NOTES.map(note => note.computerKey.toLowerCase())).size, NOTES.length);
  assert.equal(MIDI_BY_KEY.get("a"), 60);
  assert.equal(MIDI_BY_KEY.get("k"), 72);
});

test("note labels match the accessible keyboard copy", () => {
  assert.equal(noteAriaLabel(NOTES[0]!), "C4, computer key A");
  assert.equal(noteAriaLabel(NOTES[1]!), "C sharp 4, computer key W");
  assert.equal(activeNoteName(null), "—");
  assert.equal(activeNoteName(60), "C4");
  assert.equal(noteDescription(60, 60, new Set([60, 62])), "Active note");
  assert.equal(noteDescription(62, 60, new Set([60, 62])), "Held; another note is active");
  assert.equal(noteDescription(64, 60, new Set([60, 62])), "Hold to play");
});

test("computer-key gestures ignore editable targets and modifiers", () => {
  assert.equal(interpretComputerKeyDown({
    key: "A",
    repeat: false,
    altKey: false,
    ctrlKey: false,
    metaKey: false,
    targetIsEditable: true,
    enabled: true,
  }), null);

  const press = interpretComputerKeyDown({
    key: "A",
    repeat: false,
    altKey: false,
    ctrlKey: false,
    metaKey: false,
    targetIsEditable: false,
    enabled: true,
  });
  assert.deepEqual(press, {
    preventDefault: true,
    events: [{ type: "press", id: "keyboard:a", midi: 60 }],
  });
  assert.deepEqual(interpretComputerKeyUp("A"), {
    events: [{ type: "release", id: "keyboard:a" }],
  });
});

test("focus and activation gestures share stable note ids", () => {
  assert.deepEqual(interpretFocusedKeyDown(" ", 64, false), {
    preventDefault: true,
    events: [{ type: "press", id: "focus:64", midi: 64 }],
  });
  assert.deepEqual(interpretFocusedKeyDown(" ", 64, true), {
    preventDefault: true,
    events: [],
  });
  assert.deepEqual(interpretFocusedKeyUp("Enter", 64), {
    preventDefault: true,
    events: [{ type: "release", id: "focus:64" }],
  });
  assert.deepEqual(interpretFocusedBlur(64), {
    events: [{ type: "release", id: "focus:64" }],
  });
  assert.deepEqual(interpretActivationClick(0, 67), {
    events: [{ type: "press", id: "activation:67", midi: 67 }],
    releaseAfterMs: ACTIVATION_RELEASE_MS,
  });
  assert.equal(interpretActivationClick(1, 67), null);
});

test("note input routes last-held actions and pointer session replacement", () => {
  const actions: NoteAction[] = [];
  const input = createNoteInput({
    onChange() {},
    onAction(action) {
      actions.push(action);
    },
  });

  input.setEnabled(true);
  assert.equal(input.handle({
    events: [{ type: "press", id: "keyboard:a", midi: 60 }],
  }), false);
  assert.deepEqual(actions.at(-1), { type: "press", midi: 60 });

  const captures: Array<[string, number]> = [];
  const releases: Array<[string, number]> = [];
  const pointers = createPointerSessions({
    capture(target: string, pointerId: number) {
      captures.push([target, pointerId]);
    },
    releaseCapture(target: string, pointerId: number) {
      releases.push([target, pointerId]);
    },
  });

  const first = pointers.begin(7, "button-a");
  assert.equal(first.replaceId, null);
  input.apply({ type: "press", id: first.pressId, midi: 62 });
  const replaced = pointers.begin(7, "button-b");
  assert.equal(replaced.replaceId, first.pressId);
  input.apply({ type: "release", id: replaced.replaceId! });
  input.apply({ type: "press", id: replaced.pressId, midi: 64 });
  assert.deepEqual(actions.at(-1), { type: "press", midi: 64 });
  assert.equal(input.view.activeMidi, 64);

  const ended = pointers.end(7);
  assert.equal(ended, replaced.pressId);
  input.apply({ type: "release", id: ended! });
  assert.deepEqual(actions.at(-1), { type: "release", nextMidi: 60 });
  assert.deepEqual(captures, [["button-a", 7], ["button-b", 7]]);
  assert.deepEqual(releases, [["button-b", 7]]);
});
