export interface HeldNote {
  readonly id: string;
  readonly midi: number;
}

export interface KeyboardState {
  readonly enabled: boolean;
  // In press order: the last element owns the monophonic voice.
  readonly held: readonly HeldNote[];
}

export type KeyboardEvent =
  | { readonly type: "press"; readonly id: string; readonly midi: number }
  | { readonly type: "release"; readonly id: string }
  | { readonly type: "clear" }
  | { readonly type: "enable"; readonly enabled: boolean };

export type NoteAction =
  | { readonly type: "press"; readonly midi: number }
  | { readonly type: "release"; readonly nextMidi: number | null };

export const EMPTY_KEYBOARD: KeyboardState = { enabled: false, held: [] };

export function updateKeyboard(state: KeyboardState, event: KeyboardEvent): {
  readonly state: KeyboardState;
  readonly action: NoteAction | null;
} {
  switch (event.type) {
    case "enable":
      return { state: { ...state, enabled: event.enabled }, action: null };
    case "clear":
      return { state: { ...state, held: [] }, action: null };
    case "press": {
      if (!state.enabled || state.held.some(note => note.id === event.id)) return { state, action: null };
      const held = [...state.held, { id: event.id, midi: event.midi }];
      return { state: { ...state, held }, action: { type: "press", midi: event.midi } };
    }
    case "release": {
      const index = state.held.findIndex(note => note.id === event.id);
      if (index < 0) return { state, action: null };
      const held = state.held.filter(note => note.id !== event.id);
      const action: NoteAction | null = index === state.held.length - 1
        ? { type: "release", nextMidi: held.at(-1)?.midi ?? null }
        : null;
      return { state: { ...state, held }, action };
    }
  }
}

export function keyboardView(state: KeyboardState) {
  return {
    activeMidi: state.enabled ? state.held.at(-1)?.midi ?? null : null,
    heldMidis: new Set(state.held.map(note => note.midi)),
  };
}

export function navigationView(scrollLeft: number, scrollWidth: number, clientWidth: number) {
  const maximum = scrollWidth - clientWidth;
  return {
    hidden: maximum <= 1,
    lowerDisabled: scrollLeft <= 1,
    higherDisabled: scrollLeft >= maximum - 1,
  };
}
