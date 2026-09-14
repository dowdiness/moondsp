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

export interface PageElements {
  readonly document: Document;
  readonly window: Window;
  readonly startButton: HTMLButtonElement;
  readonly startLabel: HTMLSpanElement;
  readonly stopButton: HTMLButtonElement;
  readonly disposeButton: HTMLButtonElement;
  readonly retryButton: HTMLButtonElement;
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
  readonly buttons: readonly HTMLButtonElement[];
  readonly notes: readonly NoteElement[];
}

/** Acquire every required node before registering events or creating audio. */
export function readPage(document: Document): Result<PageElements> {
  return attempt(() => {
    function required<T extends Element>(selector: string): T {
      const element = document.querySelector<T>(selector);
      if (!element) throw new Error(`Missing required element: ${selector}`);
      return element;
    }
    const window = document.defaultView;
    if (!window) throw new Error("The synth document has no browser window");
    const buttons = Array.from(document.querySelectorAll<HTMLButtonElement>(".key[data-midi]"));
    const notes = buttons.flatMap(button => {
      const midi = Number(button.dataset.midi);
      return Number.isInteger(midi) ? [{
        button,
        midi,
        computerKey: button.dataset.computerKey?.toLowerCase() ?? null,
        name: button.querySelector(".note-name")?.textContent ?? "—",
      }] : [];
    });
    return {
      document, window, buttons, notes,
      startButton: required<HTMLButtonElement>("#start-audio"),
      startLabel: required<HTMLSpanElement>("#start-label"),
      stopButton: required<HTMLButtonElement>("#stop-notes"),
      disposeButton: required<HTMLButtonElement>("#dispose-audio"),
      retryButton: required<HTMLButtonElement>("#retry-audio"),
      status: required<HTMLParagraphElement>("#audio-status"),
      errorPanel: required<HTMLElement>("#audio-error"),
      errorMessage: required<HTMLParagraphElement>("#error-message"),
      volumeInput: required<HTMLInputElement>("#volume"),
      volumeValue: required<HTMLOutputElement>("#volume-value"),
      cutoffInput: required<HTMLInputElement>("#cutoff"),
      cutoffValue: required<HTMLOutputElement>("#cutoff-value"),
      activeNoteDisplay: required<HTMLElement>("#active-note-display"),
      activeNoteOutput: required<HTMLOutputElement>("#active-note"),
      keyboardScroll: required<HTMLElement>("#piano-scroll"),
      keyboardNavigation: required<HTMLElement>("#keyboard-navigation"),
      lowerNotesButton: required<HTMLButtonElement>("#lower-notes"),
      higherNotesButton: required<HTMLButtonElement>("#higher-notes"),
      keyboard: required<HTMLElement>(".keyboard"),
    };
  });
}

export interface DomConnection {
  readonly view: AudioView;
  readonly settings: Settings;
  connect(actions: AudioActions): void;
}

/** Interpret projections and gestures; all DOM reads, writes, and listeners stay here. */
export function createDomConnection(elements: PageElements, defaults: Settings): DomConnection {
  const e = elements;
  const noteElements = new Map(e.notes.map(note => [note.midi, note]));
  const keyToMidi = new Map(e.notes.flatMap(note => note.computerKey ? [[note.computerKey, note.midi] as const] : []));
  const pointerNotes = new Map<number, { readonly id: string; readonly button: HTMLButtonElement }>();
  let keyboard = EMPTY_KEYBOARD;
  let controls: ControlState = { phase: "idle", errorText: "", hasContext: false, canControl: false };
  let notesHeld = false;

  function renderControls(): void {
    const text = controlView(controls, notesHeld);
    e.status.textContent = text.status;
    e.status.dataset.state = controls.phase;
    e.errorPanel.hidden = !text.errorVisible;
    e.errorMessage.textContent = controls.errorText;
    e.startButton.disabled = text.startDisabled;
    e.startButton.dataset.state = controls.phase;
    e.startLabel.textContent = text.label;
    e.startButton.setAttribute("aria-label", text.name);
    e.startButton.setAttribute("aria-busy", String(text.busy));
    e.disposeButton.disabled = text.powerOffDisabled;
    e.volumeInput.disabled = text.inputsDisabled;
    e.cutoffInput.disabled = text.inputsDisabled;
    e.stopButton.disabled = text.stopDisabled;
  }

  function renderKeyboard(): void {
    const state = keyboardView(keyboard);
    for (const button of e.buttons) button.disabled = !keyboard.enabled;
    for (const [midi, { button }] of noteElements) {
      const held = state.heldMidis.has(midi);
      const active = state.activeMidi === midi;
      button.classList.toggle("is-held", held);
      button.classList.toggle("is-active", active);
      button.setAttribute("aria-pressed", String(held));
      button.setAttribute("aria-description", active ? "Active note" : held ? "Held; another note is active" : "Hold to play");
    }
    e.activeNoteDisplay.dataset.active = String(state.activeMidi !== null);
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
        transition({ type: "enable", enabled: state.phase === "running" && state.canControl });
      },
      setNotesHeld(held) {
        notesHeld = held;
        renderControls();
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
      e.startButton.addEventListener("click", actions.start);
      e.retryButton.addEventListener("click", actions.initialize);
      e.stopButton.addEventListener("click", actions.stopNotes);
      e.disposeButton.addEventListener("click", actions.powerOff);

      e.window.addEventListener("keydown", event => {
        if (event.repeat || event.altKey || event.ctrlKey || event.metaKey) return;
        if (event.target instanceof HTMLElement && event.target.closest("input, select, textarea, [contenteditable=\"true\"]")) return;
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
export function reportStartupFailure(document: Document, error: Error): void {
  const panel = document.querySelector<HTMLElement>("#audio-error");
  const message = document.querySelector<HTMLElement>("#error-message");
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
