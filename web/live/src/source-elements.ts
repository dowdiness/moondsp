import type { Disposable } from "./scope";

// The elements the phrase GUI draws for source spans. Each drawing shows them in
// its own slot right after it draws, from the data it drew; playback highlights
// and pointer hints read them here instead of searching the document. The
// editor has one registry, which main.ts creates and passes to each of them.

/** A drawn note's exact literal and onset. */
export type NoteIdentity = Readonly<{ literalFrom: number; literalTo: number; start: number; pitch: number | null }>;

export type SourceElement = Readonly<{
  element: HTMLElement | SVGElement;
  from: number;
  to: number;
  /** Set for a note block, which is highlighted only for its own onset. */
  note: NoteIdentity | null;
  /** Whether hovering it hints its source in code. */
  hint: boolean;
}>;

/** One drawing's place in the registry: the source elements it currently shows. */
export type SourceSlot = Disposable & {
  /** Replaces the elements this drawing shows; an empty list when it shows none. */
  show(elements: readonly SourceElement[]): void;
};

export type SourceElements = {
  /** A slot for one drawing; disposing it removes what the drawing showed. */
  slot(): SourceSlot;
  /** Every element the drawings currently show. */
  all(): readonly SourceElement[];
  /** Calls `listener` whenever what is shown changes; returns the unsubscribe. */
  subscribe(listener: () => void): () => void;
};

export function createSourceElements(): SourceElements {
  const shown = new Map<SourceSlot, readonly SourceElement[]>();
  const listeners = new Set<() => void>();
  let all: readonly SourceElement[] | null = [];
  const changed = (): void => {
    all = null;
    for (const listener of listeners) listener();
  };
  return {
    slot() {
      const slot: SourceSlot = {
        show(elements) {
          const wasShowing = shown.has(slot);
          if (elements.length) shown.set(slot, elements);
          else shown.delete(slot);
          if (wasShowing || elements.length) changed();
        },
        dispose: () => slot.show([]),
      };
      return slot;
    },
    all: () => (all ??= [...shown.values()].flat()),
    subscribe(listener) {
      listeners.add(listener);
      return () => { listeners.delete(listener); };
    },
  };
}
