import type { AudioActions, AudioView } from "./audio";
import { controlView, cutoffFromInput, cutoffPosition, volumeFromInput, type ControlState } from "./controls";
import { EMPTY_KEYBOARD, updateKeyboard, keyboardView, navigationView, type KeyboardEvent, type NoteAction } from "./keyboard";
import { attempt, type Result } from "./result";
import type { Settings } from "./synth";

interface NoteElement {
  readonly button: HTMLButtonElement;
  readonly midi: number;
  readonly computerKey: string | null;
  readonly name: string;
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
  readonly buttons: readonly HTMLButtonElement[];
  readonly notes: readonly NoteElement[];
}

export type PageSelectors = { readonly [Key in keyof RequiredElements]: string } & {
  readonly noteButtons: string;
  readonly noteName: string;
  readonly editable: string;
};

export interface PageBindings {
  readonly selectors: PageSelectors;
  readonly classes: {
    readonly heldNote: string;
    readonly activeNote: string;
  };
  /** DOMStringMap keys, e.g. computerKey for data-computer-key. */
  readonly data: {
    readonly midi: string;
    readonly computerKey: string;
    readonly phase: string;
    readonly activeNote: string;
  };
}

/** Acquire every required node before registering events or creating audio. */
export function readPage(document: Document, bindings: PageBindings): Result<PageElements> {
  return attempt(() => {
    const { selectors, data } = bindings;
    function required<T extends Element>(selector: string): T {
      const element = document.querySelector<T>(selector);
      if (!element) throw new Error(`Missing required element: ${selector}`);
      return element;
    }
    const window = document.defaultView;
    if (!window) throw new Error("The synth document has no browser window");
    const buttons = Array.from(document.querySelectorAll<HTMLButtonElement>(selectors.noteButtons));
    const notes = buttons.flatMap(button => {
      const midi = Number(button.dataset[data.midi]);
      return Number.isInteger(midi) ? [{
        button,
        midi,
        computerKey: button.dataset[data.computerKey]?.toLowerCase() ?? null,
        name: button.querySelector(selectors.noteName)?.textContent ?? "—",
      }] : [];
    });
    return {
      document, window, buttons, notes,
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
      keyboard: required<HTMLElement>(selectors.keyboard),
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
  const { selectors, classes, data } = bindings;
  const noteElements = new Map(e.notes.map(note => [note.midi, note]));
  const keyToMidi = new Map(e.notes.flatMap(note => note.computerKey ? [[note.computerKey, note.midi] as const] : []));
  const pointerNotes = new Map<number, { readonly id: string; readonly button: HTMLButtonElement }>();
  let keyboard = EMPTY_KEYBOARD;
  let controls: ControlState = { phase: "idle", errorText: "" };

  function renderControls(): void {
    const text = controlView(controls);
    e.status.textContent = text.status;
    e.status.dataset[data.phase] = controls.phase;
    e.errorPanel.hidden = !text.errorVisible;
    e.errorMessage.textContent = controls.errorText;
    e.powerButton.disabled = text.powerDisabled;
    e.powerButton.dataset[data.phase] = controls.phase;
    e.powerLabel.textContent = text.label;
    e.powerButton.setAttribute("aria-label", text.name);
    e.powerButton.setAttribute("aria-busy", String(text.busy));
    e.volumeInput.disabled = text.inputsDisabled;
    e.cutoffInput.disabled = text.inputsDisabled;
  }

  function renderKeyboard(): void {
    const state = keyboardView(keyboard);
    for (const button of e.buttons) button.disabled = !keyboard.enabled;
    for (const [midi, { button }] of noteElements) {
      const held = state.heldMidis.has(midi);
      const active = state.activeMidi === midi;
      button.classList.toggle(classes.heldNote, held);
      button.classList.toggle(classes.activeNote, active);
      button.setAttribute("aria-pressed", String(held));
      button.setAttribute("aria-description", active ? "Active note" : held ? "Held; another note is active" : "Hold to play");
    }
    e.activeNoteDisplay.dataset[data.activeNote] = String(state.activeMidi !== null);
    e.activeNoteOutput.textContent = state.activeMidi === null ? "—" : noteElements.get(state.activeMidi)?.name ?? "—";
  }

  function transition(event: KeyboardEvent): NoteAction | null {
    const next = updateKeyboard(keyboard, event);
    keyboard = next.state;
    renderKeyboard();
    return next.action;
  }

  function releaseCapture(button: HTMLButtonElement, pointerId: number): void {
    try {
      if (button.hasPointerCapture(pointerId)) button.releasePointerCapture(pointerId);
    } catch {
      // Capture may already be gone during page teardown.
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
        transition({ type: "enable", enabled: state.phase === "running" });
      },
      clearNotes() {
        for (const [pointerId, note] of pointerNotes) releaseCapture(note.button, pointerId);
        pointerNotes.clear();
        transition({ type: "clear" });
      },
    },
    connect(actions) {
      function dispatch(event: KeyboardEvent): void {
        const action = transition(event);
        if (action?.type === "press") actions.press(action.midi);
        else if (action?.type === "release") actions.release(action.nextMidi);
      }
      function release(id: string): void {
        dispatch({ type: "release", id });
      }

      e.volumeInput.addEventListener("input", () => actions.volumeChanged(updateVolume()));
      e.cutoffInput.addEventListener("input", () => actions.cutoffChanged(updateCutoff()));
      e.powerButton.addEventListener("click", () => {
        if (controlView(controls).powerAction === "on") actions.powerOn();
        else actions.powerOff();
      });

      e.window.addEventListener("keydown", event => {
        if (event.repeat || event.altKey || event.ctrlKey || event.metaKey) return;
        if (event.target instanceof HTMLElement && event.target.closest(selectors.editable)) return;
        const key = event.key.toLowerCase();
        const midi = keyToMidi.get(key);
        if (midi === undefined || !keyboard.enabled) return;
        event.preventDefault();
        dispatch({ type: "press", id: `keyboard:${key}`, midi });
      });
      e.window.addEventListener("keyup", event => {
        const key = event.key.toLowerCase();
        if (keyToMidi.has(key)) release(`keyboard:${key}`);
      });
      for (const [midi, { button }] of noteElements) {
        button.addEventListener("keydown", event => {
          if (event.key !== " " && event.key !== "Enter") return;
          event.preventDefault();
          if (!event.repeat) dispatch({ type: "press", id: `focus:${midi}`, midi });
        });
        button.addEventListener("keyup", event => {
          if (event.key !== " " && event.key !== "Enter") return;
          event.preventDefault();
          release(`focus:${midi}`);
        });
        button.addEventListener("blur", () => release(`focus:${midi}`));
        button.addEventListener("click", event => {
          if (event.detail !== 0) return;
          const id = `activation:${midi}`;
          dispatch({ type: "press", id, midi });
          e.window.setTimeout(() => release(id), 150);
        });
        button.addEventListener("pointerdown", event => {
          if (event.button !== 0 || !keyboard.enabled) return;
          event.preventDefault();
          const existing = pointerNotes.get(event.pointerId);
          if (existing) release(existing.id);
          const id = `pointer:${event.pointerId}`;
          pointerNotes.set(event.pointerId, { id, button });
          try { button.setPointerCapture(event.pointerId); } catch {
            // Browsers without capture still deliver pointerup/cancel.
          }
          dispatch({ type: "press", id, midi });
        });
        const finishPointer = (event: PointerEvent) => {
          const note = pointerNotes.get(event.pointerId);
          if (!note) return;
          pointerNotes.delete(event.pointerId);
          releaseCapture(note.button, event.pointerId);
          release(note.id);
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
