import type { AudioActions, AudioView } from "../../core/audio";
import { controlView, cutoffFromInput, cutoffPosition, volumeFromInput, type ControlState } from "../../core/controls";
import {
  EDITABLE_SELECTOR,
  createDeferredReleases,
  createNoteInput,
  createPointerSessions,
  interpretActivationClick,
  interpretComputerKeyDown,
  interpretComputerKeyUp,
  interpretFocusedBlur,
  interpretFocusedKeyDown,
  interpretFocusedKeyUp,
  type Gesture,
} from "../../core/input";
import { navigationView } from "../../core/keyboard";
import { NOTES, activeNoteName, noteAriaLabel, noteDescription, type Note } from "../../core/notes";
import { attempt, type Result } from "../../core/result";
import type { Settings } from "../../core/synth";

interface NoteElement {
  readonly button: HTMLButtonElement;
  readonly note: Note;
}

interface RequiredElements {
  readonly powerButton: HTMLButtonElement;
  readonly powerLabel: HTMLSpanElement;
  readonly status: HTMLParagraphElement;
  readonly errorPanel: HTMLElement;
  readonly errorMessage: HTMLParagraphElement;
  readonly volumeInput: HTMLInputElement;
  readonly volumeValue: HTMLOutputElement;
  readonly cutoffInput: HTMLInputElement;
  readonly cutoffValue: HTMLOutputElement;
  readonly activeNoteDisplay: HTMLElement;
  readonly activeNoteOutput: HTMLOutputElement;
  readonly keyboardScroll: HTMLElement;
  readonly keyboardNavigation: HTMLElement;
  readonly lowerNotesButton: HTMLButtonElement;
  readonly higherNotesButton: HTMLButtonElement;
  readonly keyboard: HTMLElement;
}

export interface PageElements extends RequiredElements {
  readonly document: Document;
  readonly window: Window;
  readonly notes: readonly NoteElement[];
}

export type PageSelectors = { readonly [Key in keyof RequiredElements]: string } & {
  readonly phase: string;
  readonly activeNote: string;
};

export interface PageBindings {
  readonly selectors: PageSelectors;
  readonly classes: {
    readonly heldNote: string;
    readonly activeNote: string;
  };
}

function tryPointerCapture(button: HTMLButtonElement, pointerId: number): void {
  try {
    button.setPointerCapture(pointerId);
  } catch {
    // Browsers without capture still deliver pointerup/cancel.
  }
}

function releasePointerCapture(button: HTMLButtonElement, pointerId: number): void {
  try {
    if (button.hasPointerCapture(pointerId)) button.releasePointerCapture(pointerId);
  } catch {
    // Capture may already be gone during page teardown.
  }
}

function mountNotes(keyboard: HTMLElement): readonly NoteElement[] {
  keyboard.replaceChildren();
  return NOTES.map(note => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `key ${note.black ? "is-black" : "is-natural"}`;
    button.dataset.midi = String(note.midi);
    button.dataset.computerKey = note.computerKey;
    button.setAttribute("aria-label", noteAriaLabel(note));
    button.setAttribute("aria-pressed", "false");
    const name = document.createElement("span");
    name.className = "note-name";
    name.textContent = note.name;
    const kbd = document.createElement("kbd");
    kbd.textContent = note.computerKey;
    const description = document.createElement("span");
    description.id = `note-description-${note.midi}`;
    description.className = "sr-only";
    description.textContent = noteDescription(note.midi, null, new Set());
    button.append(name, kbd, description);
    button.setAttribute("aria-describedby", description.id);
    keyboard.append(button);
    return { button, note };
  });
}

/** Acquire every required node before registering events or creating audio. */
export function readPage(document: Document, bindings: PageBindings): Result<PageElements> {
  return attempt(() => {
    const { selectors } = bindings;
    function required<T extends Element>(selector: string): T {
      const element = document.querySelector<T>(selector);
      if (!element) throw new Error(`Missing required element: ${selector}`);
      return element;
    }
    const window = document.defaultView;
    if (!window) throw new Error("The synth document has no browser window");
    const keyboard = required<HTMLElement>(selectors.keyboard);
    const notes = mountNotes(keyboard);
    return {
      document,
      window,
      notes,
      powerButton: required<HTMLButtonElement>(selectors.powerButton),
      powerLabel: required<HTMLSpanElement>(selectors.powerLabel),
      status: required<HTMLParagraphElement>(selectors.status),
      errorPanel: required<HTMLElement>(selectors.errorPanel),
      errorMessage: required<HTMLParagraphElement>(selectors.errorMessage),
      volumeInput: required<HTMLInputElement>(selectors.volumeInput),
      volumeValue: required<HTMLOutputElement>(selectors.volumeValue),
      cutoffInput: required<HTMLInputElement>(selectors.cutoffInput),
      cutoffValue: required<HTMLOutputElement>(selectors.cutoffValue),
      activeNoteDisplay: required<HTMLElement>(selectors.activeNoteDisplay),
      activeNoteOutput: required<HTMLOutputElement>(selectors.activeNoteOutput),
      keyboardScroll: required<HTMLElement>(selectors.keyboardScroll),
      keyboardNavigation: required<HTMLElement>(selectors.keyboardNavigation),
      lowerNotesButton: required<HTMLButtonElement>(selectors.lowerNotesButton),
      higherNotesButton: required<HTMLButtonElement>(selectors.higherNotesButton),
      keyboard,
    };
  });
}

export interface DomConnection {
  readonly view: AudioView;
  readonly settings: Settings;
  connect(actions: AudioActions): void;
}

/** Interpret projections and gestures; all DOM reads, writes, and listeners stay here. */
export function createDomConnection(elements: PageElements, defaults: Settings, bindings: PageBindings): DomConnection {
  const e = elements;
  const { selectors, classes } = bindings;
  const noteElements = new Map(e.notes.map(note => [note.note.midi, note]));
  let controls: ControlState = { phase: "idle", errorText: "" };
  const pointers = createPointerSessions<HTMLButtonElement>({
    capture: tryPointerCapture,
    releaseCapture: releasePointerCapture,
  });

  const deferredReleases = createDeferredReleases({
    setTimeout: (handler, ms) => e.window.setTimeout(handler, ms),
    clearTimeout: handle => e.window.clearTimeout(handle as number),
  });

  const notes = createNoteInput({
    onChange() {
      renderKeyboard();
    },
    onAction(action) {
      if (!pendingActions) return;
      if (action.type === "press") pendingActions.press(action.midi);
      else pendingActions.release(action.nextMidi);
    },
  });
  let pendingActions: AudioActions | undefined;

  function renderControls(): void {
    const text = controlView(controls);
    e.status.textContent = text.status;
    e.status.dataset[selectors.phase] = controls.phase;
    e.errorPanel.hidden = !text.errorVisible;
    e.errorMessage.textContent = controls.errorText;
    e.powerButton.disabled = text.powerDisabled;
    e.powerButton.dataset[selectors.phase] = controls.phase;
    e.powerLabel.textContent = text.label;
    e.powerButton.setAttribute("aria-label", text.name);
    e.powerButton.setAttribute("aria-busy", String(text.busy));
    e.volumeInput.disabled = text.inputsDisabled;
    e.cutoffInput.disabled = text.inputsDisabled;
  }

  function renderKeyboard(): void {
    const state = notes.view;
    for (const { button, note } of e.notes) {
      button.disabled = !notes.state.enabled;
      const held = state.heldMidis.has(note.midi);
      const active = state.activeMidi === note.midi;
      button.classList.toggle(classes.heldNote, held);
      button.classList.toggle(classes.activeNote, active);
      button.setAttribute("aria-pressed", String(held));
      const description = button.querySelector(`#note-description-${note.midi}`);
      if (description) description.textContent = noteDescription(note.midi, state.activeMidi, state.heldMidis);
    }
    e.activeNoteDisplay.dataset[selectors.activeNote] = String(state.activeMidi !== null);
    e.activeNoteOutput.textContent = activeNoteName(state.activeMidi);
  }

  function handle(gesture: Gesture | null, event?: Event): void {
    if (notes.handle(gesture) && event && "preventDefault" in event) event.preventDefault();
    if (gesture?.releaseAfterMs !== undefined) {
      const release = gesture.events[0];
      if (release?.type === "press") {
        deferredReleases.after(release.id, gesture.releaseAfterMs, () => {
          notes.apply({ type: "release", id: release.id });
        });
      }
    }
  }

  function updateVolume(): number {
    const value = volumeFromInput(Number(e.volumeInput.value));
    e.volumeValue.textContent = `${Math.round(value * 100)}%`;
    e.volumeInput.setAttribute("aria-valuetext", e.volumeValue.textContent);
    return value;
  }

  function updateCutoff(): number {
    const value = cutoffFromInput(Number(e.cutoffInput.value));
    e.cutoffValue.textContent = `${Math.round(value).toLocaleString()} Hz`;
    e.cutoffInput.setAttribute("aria-valuetext", e.cutoffValue.textContent);
    return value;
  }

  function updateNavigation(): void {
    const state = navigationView(e.keyboardScroll.scrollLeft, e.keyboardScroll.scrollWidth, e.keyboardScroll.clientWidth);
    e.keyboardNavigation.hidden = state.hidden;
    e.lowerNotesButton.disabled = state.lowerDisabled;
    e.higherNotesButton.disabled = state.higherDisabled;
  }

  e.volumeInput.value = String(defaults.volume);
  e.cutoffInput.value = cutoffPosition(defaults.cutoff).toFixed(3);
  const settings = { volume: updateVolume(), cutoff: updateCutoff() };

  return {
    settings,
    view: {
      render(state) {
        controls = state;
        renderControls();
        notes.setEnabled(state.phase === "running");
      },
      clearNotes() {
        deferredReleases.clear();
        pointers.clear();
        notes.clear();
      },
    },
    connect(actions) {
      pendingActions = actions;

      e.volumeInput.addEventListener("input", () => actions.volumeChanged(updateVolume()));
      e.cutoffInput.addEventListener("input", () => actions.cutoffChanged(updateCutoff()));
      e.powerButton.addEventListener("click", () => {
        if (controlView(controls).powerAction === "on") actions.powerOn();
        else actions.powerOff();
      });

      e.window.addEventListener("keydown", event => {
        handle(interpretComputerKeyDown({
          key: event.key,
          repeat: event.repeat,
          altKey: event.altKey,
          ctrlKey: event.ctrlKey,
          metaKey: event.metaKey,
          targetIsEditable: event.target instanceof HTMLElement && !!event.target.closest(EDITABLE_SELECTOR),
          enabled: notes.state.enabled,
        }), event);
      });
      e.window.addEventListener("keyup", event => {
        handle(interpretComputerKeyUp(event.key));
      });

      for (const { button, note } of noteElements.values()) {
        button.addEventListener("keydown", event => {
          handle(interpretFocusedKeyDown(event.key, note.midi, event.repeat), event);
        });
        button.addEventListener("keyup", event => {
          handle(interpretFocusedKeyUp(event.key, note.midi), event);
        });
        button.addEventListener("blur", () => handle(interpretFocusedBlur(note.midi)));
        button.addEventListener("click", event => {
          handle(interpretActivationClick(event.detail, note.midi));
        });
        button.addEventListener("pointerdown", event => {
          if (event.button !== 0 || !notes.state.enabled) return;
          event.preventDefault();
          const { replaceId, pressId } = pointers.begin(event.pointerId, button);
          if (replaceId) notes.apply({ type: "release", id: replaceId });
          notes.apply({ type: "press", id: pressId, midi: note.midi });
        });
        const finishPointer = (event: PointerEvent) => {
          const id = pointers.end(event.pointerId);
          if (id) notes.apply({ type: "release", id });
        };
        button.addEventListener("pointerup", finishPointer);
        button.addEventListener("pointercancel", finishPointer);
        button.addEventListener("lostpointercapture", finishPointer);
      }

      e.lowerNotesButton.addEventListener("click", () => {
        e.keyboardScroll.scrollBy({ left: -e.keyboardScroll.clientWidth * 0.8, behavior: "auto" });
      });
      e.higherNotesButton.addEventListener("click", () => {
        e.keyboardScroll.scrollBy({ left: e.keyboardScroll.clientWidth * 0.8, behavior: "auto" });
      });
      e.keyboardScroll.addEventListener("scroll", updateNavigation, { passive: true });
      const resizeObserver = new ResizeObserver(updateNavigation);
      resizeObserver.observe(e.keyboardScroll);
      resizeObserver.observe(e.keyboard);
      e.window.addEventListener("blur", actions.stopNotes);
      e.document.addEventListener("visibilitychange", () => {
        if (e.document.hidden) actions.stopNotes();
      });
      e.window.addEventListener("pagehide", actions.powerOff);
      updateNavigation();
      renderControls();
      renderKeyboard();
    },
  };
}

/** Last-resort startup reporting also stays at the DOM edge. */
export function reportStartupFailure(
  document: Document,
  error: Error,
  selectors: Pick<PageSelectors, "errorPanel" | "errorMessage">,
): void {
  const panel = document.querySelector<HTMLElement>(selectors.errorPanel);
  const message = document.querySelector<HTMLElement>(selectors.errorMessage);
  if (panel && message) {
    panel.hidden = false;
    message.textContent = error.message;
  } else {
    const notice = document.createElement("p");
    notice.setAttribute("role", "alert");
    notice.textContent = error.message;
    document.body.append(notice);
  }
}
