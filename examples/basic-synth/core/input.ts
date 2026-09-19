import {
  EMPTY_KEYBOARD,
  keyboardView,
  updateKeyboard,
  type KeyboardEvent as KeyboardTransition,
  type KeyboardState,
  type NoteAction,
} from "./keyboard";
import { MIDI_BY_KEY } from "./notes";

export const EDITABLE_SELECTOR = 'input, select, textarea, [contenteditable="true"]';
export const ACTIVATION_RELEASE_MS = 150;

export type Gesture = {
  readonly preventDefault?: boolean;
  readonly events: readonly KeyboardTransition[];
  readonly releaseAfterMs?: number;
};

export function computerKeyId(key: string): string {
  return `keyboard:${key}`;
}

export function focusNoteId(midi: number): string {
  return `focus:${midi}`;
}

export function activationNoteId(midi: number): string {
  return `activation:${midi}`;
}

export function pointerNoteId(pointerId: number): string {
  return `pointer:${pointerId}`;
}

export function interpretComputerKeyDown(input: {
  readonly key: string;
  readonly repeat: boolean;
  readonly altKey: boolean;
  readonly ctrlKey: boolean;
  readonly metaKey: boolean;
  readonly targetIsEditable: boolean;
  readonly enabled: boolean;
  readonly midiByKey?: ReadonlyMap<string, number>;
}): Gesture | null {
  if (input.repeat || input.altKey || input.ctrlKey || input.metaKey || input.targetIsEditable) return null;
  const key = input.key.toLowerCase();
  const midi = (input.midiByKey ?? MIDI_BY_KEY).get(key);
  if (midi === undefined || !input.enabled) return null;
  return {
    preventDefault: true,
    events: [{ type: "press", id: computerKeyId(key), midi }],
  };
}

export function interpretComputerKeyUp(
  key: string,
  midiByKey: ReadonlyMap<string, number> = MIDI_BY_KEY,
): Gesture | null {
  const normalized = key.toLowerCase();
  if (!midiByKey.has(normalized)) return null;
  return { events: [{ type: "release", id: computerKeyId(normalized) }] };
}

export function interpretFocusedKeyDown(key: string, midi: number, repeat: boolean): Gesture | null {
  if (key !== " " && key !== "Enter") return null;
  if (repeat) return { preventDefault: true, events: [] };
  return {
    preventDefault: true,
    events: [{ type: "press", id: focusNoteId(midi), midi }],
  };
}

export function interpretFocusedKeyUp(key: string, midi: number): Gesture | null {
  if (key !== " " && key !== "Enter") return null;
  return {
    preventDefault: true,
    events: [{ type: "release", id: focusNoteId(midi) }],
  };
}

export function interpretFocusedBlur(midi: number): Gesture {
  return { events: [{ type: "release", id: focusNoteId(midi) }] };
}

export function interpretActivationClick(detail: number, midi: number): Gesture | null {
  if (detail !== 0) return null;
  return {
    events: [{ type: "press", id: activationNoteId(midi), midi }],
    releaseAfterMs: ACTIVATION_RELEASE_MS,
  };
}

/** Tracks pointer-held notes without owning DOM capture details. */
export function createPointerSessions<TTarget>(hooks: {
  capture(target: TTarget, pointerId: number): void;
  releaseCapture(target: TTarget, pointerId: number): void;
}) {
  const sessions = new Map<number, { readonly id: string; readonly target: TTarget }>();

  return {
    begin(pointerId: number, target: TTarget): { readonly replaceId: string | null; readonly pressId: string } {
      const existing = sessions.get(pointerId);
      const pressId = pointerNoteId(pointerId);
      sessions.set(pointerId, { id: pressId, target });
      hooks.capture(target, pointerId);
      return { replaceId: existing?.id ?? null, pressId };
    },
    end(pointerId: number): string | null {
      const session = sessions.get(pointerId);
      if (!session) return null;
      sessions.delete(pointerId);
      hooks.releaseCapture(session.target, pointerId);
      return session.id;
    },
    clear(): void {
      for (const [pointerId, session] of sessions) hooks.releaseCapture(session.target, pointerId);
      sessions.clear();
    },
  };
}

export type DeferredReleaseClock = {
  setTimeout(handler: () => void, ms: number): unknown;
  clearTimeout(handle: unknown): void;
};

/** Schedules id-keyed delayed releases; clear cancels pending work before ids are reused. */
export function createDeferredReleases(clock: DeferredReleaseClock = globalThis) {
  const pending = new Map<string, { handle: unknown; cancelled: boolean }>();

  return {
    after(id: string, ms: number, release: () => void): void {
      const existing = pending.get(id);
      if (existing) {
        existing.cancelled = true;
        clock.clearTimeout(existing.handle);
      }
      const entry = { handle: undefined as unknown, cancelled: false };
      entry.handle = clock.setTimeout(() => {
        pending.delete(id);
        if (entry.cancelled) return;
        release();
      }, ms);
      pending.set(id, entry);
    },
    clear(): void {
      for (const entry of pending.values()) {
        entry.cancelled = true;
        clock.clearTimeout(entry.handle);
      }
      pending.clear();
    },
  };
}

export interface NoteInput {
  readonly state: KeyboardState;
  readonly view: ReturnType<typeof keyboardView>;
  apply(event: KeyboardTransition): NoteAction | null;
  setEnabled(enabled: boolean): void;
  clear(): void;
  handle(gesture: Gesture | null): boolean;
}

/** Owns the pure keyboard reducer and routes note actions to the audio seam. */
export function createNoteInput(options: {
  onChange(state: KeyboardState): void;
  onAction(action: NoteAction): void;
}): NoteInput {
  let state = EMPTY_KEYBOARD;

  function publish(next: KeyboardState): void {
    state = next;
    options.onChange(state);
  }

  function apply(event: KeyboardTransition): NoteAction | null {
    const next = updateKeyboard(state, event);
    publish(next.state);
    if (next.action) options.onAction(next.action);
    return next.action;
  }

  return {
    get state() {
      return state;
    },
    get view() {
      return keyboardView(state);
    },
    apply,
    setEnabled(enabled) {
      apply({ type: "enable", enabled });
    },
    clear() {
      apply({ type: "clear" });
    },
    handle(gesture) {
      if (!gesture) return false;
      for (const event of gesture.events) apply(event);
      return gesture.preventDefault === true;
    },
  };
}

