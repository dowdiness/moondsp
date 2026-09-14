import { required } from "./dom";

interface HeldNote {
  readonly id: string;
  readonly midi: number;
  readonly order: number;
}

interface PointerNote {
  readonly id: string;
  readonly button: HTMLButtonElement;
}

interface NoteActions {
  press(midi: number): void;
  release(nextMidi: number | null): void;
}

/** Owns input priority and key feedback; the caller decides how notes sound. */
export function createKeyboard(actions: NoteActions) {
  const activeNoteDisplay = required<HTMLElement>("#active-note-display");
  const activeNoteOutput = required<HTMLOutputElement>("#active-note");
  const keyboardScroll = required<HTMLElement>("#piano-scroll");
  const keyboardNavigation = required<HTMLElement>("#keyboard-navigation");
  const lowerNotesButton = required<HTMLButtonElement>("#lower-notes");
  const higherNotesButton = required<HTMLButtonElement>("#higher-notes");
  const buttons = Array.from(document.querySelectorAll<HTMLButtonElement>(".key[data-midi]"));
  const noteButtons = new Map<number, HTMLButtonElement>();
  const keyToMidi = new Map<string, number>();
  const heldNotes = new Map<string, HeldNote>();
  const pointerNotes = new Map<number, PointerNote>();
  let enabled = false;
  let pressOrder = 0;
  let activeHeldId: string | null = null;

  for (const button of buttons) {
    const midi = Number(button.dataset.midi);
    if (!Number.isInteger(midi)) continue;
    noteButtons.set(midi, button);
    const key = button.dataset.computerKey;
    if (key) keyToMidi.set(key.toLowerCase(), midi);
  }

  function render(): void {
    const heldMidis = new Set<number>();
    for (const note of heldNotes.values()) heldMidis.add(note.midi);
    const activeNote = enabled && activeHeldId !== null ? heldNotes.get(activeHeldId) : undefined;
    for (const [midi, button] of noteButtons) {
      const held = heldMidis.has(midi);
      const active = activeNote?.midi === midi;
      button.classList.toggle("is-held", held);
      button.classList.toggle("is-active", active);
      button.setAttribute("aria-pressed", String(held));
      button.setAttribute("aria-description", active ? "Active note" : held ? "Held; another note is active" : "Hold to play");
    }
    activeNoteDisplay.dataset.active = String(activeNote !== undefined);
    activeNoteOutput.textContent = activeNote === undefined
      ? "—"
      : noteButtons.get(activeNote.midi)?.querySelector(".note-name")?.textContent ?? "—";
  }

  function pressHeld(id: string, midi: number): void {
    if (!enabled || heldNotes.has(id)) return;
    heldNotes.set(id, { id, midi, order: ++pressOrder });
    activeHeldId = id;
    render();
    actions.press(midi);
  }

  function releaseHeld(id: string): void {
    if (!heldNotes.has(id)) return;
    heldNotes.delete(id);
    if (activeHeldId !== id) {
      render();
      return;
    }
    let next: HeldNote | undefined;
    for (const candidate of heldNotes.values()) {
      if (!next || candidate.order > next.order) next = candidate;
    }
    activeHeldId = next?.id ?? null;
    render();
    actions.release(next?.midi ?? null);
  }

  function releasePointerCapture(note: PointerNote, pointerId: number): void {
    try {
      if (note.button.hasPointerCapture(pointerId)) note.button.releasePointerCapture(pointerId);
    } catch {
      // Pointer capture may already be gone during page teardown.
    }
  }

  function clear(): void {
    for (const [pointerId, note] of pointerNotes) releasePointerCapture(note, pointerId);
    pointerNotes.clear();
    heldNotes.clear();
    activeHeldId = null;
    render();
  }

  function setEnabled(value: boolean): void {
    enabled = value;
    for (const button of buttons) button.disabled = !value;
    render();
  }

  // Computer letters and focused Space/Enter keys are independent hold sources.
  window.addEventListener("keydown", (event) => {
    if (event.repeat || event.altKey || event.ctrlKey || event.metaKey) return;
    if (event.target instanceof HTMLElement && event.target.closest("input, select, textarea, [contenteditable=\"true\"]")) return;
    const midi = keyToMidi.get(event.key.toLowerCase());
    if (midi === undefined || !enabled) return;
    event.preventDefault();
    pressHeld(`keyboard:${event.key.toLowerCase()}`, midi);
  });
  window.addEventListener("keyup", (event) => {
    const key = event.key.toLowerCase();
    if (keyToMidi.has(key)) releaseHeld(`keyboard:${key}`);
  });

  for (const [midi, button] of noteButtons) {
    button.addEventListener("keydown", (event) => {
      if (event.key !== " " && event.key !== "Enter") return;
      event.preventDefault();
      if (!event.repeat) pressHeld(`focus:${midi}`, midi);
    });
    button.addEventListener("keyup", (event) => {
      if (event.key !== " " && event.key !== "Enter") return;
      event.preventDefault();
      releaseHeld(`focus:${midi}`);
    });
    button.addEventListener("blur", () => releaseHeld(`focus:${midi}`));
    button.addEventListener("click", (event) => {
      // Assistive technology can activate a button without a key/pointer event.
      if (event.detail !== 0) return;
      const id = `activation:${midi}`;
      pressHeld(id, midi);
      window.setTimeout(() => releaseHeld(id), 150);
    });
    button.addEventListener("pointerdown", (event) => {
      if (event.button !== 0 || !enabled) return;
      event.preventDefault();
      const existing = pointerNotes.get(event.pointerId);
      if (existing) releaseHeld(existing.id);
      const id = `pointer:${event.pointerId}`;
      pointerNotes.set(event.pointerId, { id, button });
      try {
        button.setPointerCapture(event.pointerId);
      } catch {
        // Browsers without pointer capture still deliver pointerup/cancel.
      }
      pressHeld(id, midi);
    });
    const finishPointer = (event: PointerEvent) => {
      const note = pointerNotes.get(event.pointerId);
      if (!note) return;
      pointerNotes.delete(event.pointerId);
      releasePointerCapture(note, event.pointerId);
      releaseHeld(note.id);
    };
    button.addEventListener("pointerup", finishPointer);
    button.addEventListener("pointercancel", finishPointer);
    button.addEventListener("lostpointercapture", finishPointer);
  }

  function updateNavigation(): void {
    const maximum = keyboardScroll.scrollWidth - keyboardScroll.clientWidth;
    keyboardNavigation.hidden = maximum <= 1;
    lowerNotesButton.disabled = keyboardScroll.scrollLeft <= 1;
    higherNotesButton.disabled = keyboardScroll.scrollLeft >= maximum - 1;
  }

  lowerNotesButton.addEventListener("click", () => {
    keyboardScroll.scrollBy({ left: -keyboardScroll.clientWidth * 0.8, behavior: "auto" });
  });
  higherNotesButton.addEventListener("click", () => {
    keyboardScroll.scrollBy({ left: keyboardScroll.clientWidth * 0.8, behavior: "auto" });
  });
  keyboardScroll.addEventListener("scroll", updateNavigation, { passive: true });
  const resizeObserver = new ResizeObserver(updateNavigation);
  resizeObserver.observe(keyboardScroll);
  resizeObserver.observe(required<HTMLElement>(".keyboard"));
  updateNavigation();
  setEnabled(false);

  return { clear, setEnabled };
}
