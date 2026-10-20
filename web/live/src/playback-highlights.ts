import { StateEffect, StateField, Transaction, type Extension, type Range } from "@codemirror/state";
import { Decoration, EditorView, ViewPlugin, type DecorationSet } from "@codemirror/view";
import type { SourceElement, SourceElements } from "./source-elements";

export type PlaybackHighlight = Readonly<{
  from: number;
  to: number;
  references: readonly Readonly<{ from: number; to: number }>[];
  notation: Readonly<{ from: number; to: number; start: number; pitch: number | null }> | null;
}>;

const setPulses = StateEffect.define<readonly PlaybackHighlight[]>();
type PulseState = { pulses: readonly PlaybackHighlight[]; decorations: DecorationSet };

const pulseField = StateField.define<PulseState>({
  create: () => ({ pulses: [], decorations: Decoration.none }),
  update(value, transaction) {
    if (transaction.docChanged) return { pulses: [], decorations: Decoration.none };
    let pulses = value.pulses;
    for (const effect of transaction.effects) if (effect.is(setPulses)) pulses = effect.value;
    if (pulses === value.pulses) return value;
    const docLength = transaction.state.doc.length;
    const ranges: Range<Decoration>[] = [];
    const seen = new Set<string>();
    const mark = (className: string, from: number, to: number): void => {
      const key = `${className}:${from}:${to}`;
      if (seen.has(key)) return;
      seen.add(key);
      ranges.push(Decoration.mark({ class: className }).range(from, to));
    };
    for (const pulse of pulses) {
      if (pulse.from < 0 || pulse.to <= pulse.from || pulse.to > docLength) continue;
      // Drum events carry no pitch; their atoms take the percussion colour.
      const percussion = pulse.notation !== null && pulse.notation.pitch === null;
      mark(percussion ? "cm-playback-atom cm-playback-percussion" : "cm-playback-atom", pulse.from, pulse.to);
      for (const ref of pulse.references)
        if (ref.from >= 0 && ref.to > ref.from && ref.to <= docLength)
          mark("cm-playback-reference", ref.from, ref.to);
    }
    ranges.sort((a, b) => a.from - b.from || a.to - b.to);
    return { pulses, decorations: ranges.length ? Decoration.set(ranges, true) : Decoration.none };
  },
  provide: field => EditorView.decorations.from(field, value => value.decorations),
});

/**
 * Whether a drawn source shows one of `pulses`: the same source span and, for a
 * note block, the same literal and onset.
 */
export function sourceIsPlaying(source: Pick<SourceElement, "from" | "to" | "note">, pulses: readonly PlaybackHighlight[]): boolean {
  const { note } = source;
  return pulses.some(pulse => pulse.from === source.from && pulse.to === source.to && (note === null ||
    (pulse.notation !== null && pulse.notation.from === note.literalFrom && pulse.notation.to === note.literalTo &&
      pulse.notation.start === note.start && pulse.notation.pitch === note.pitch)));
}

// Marks the drawn sources that are sounding, whenever the pulses change or a
// drawing shows newly drawn sources.
class PulseDOM {
  private readonly unsubscribe: () => void;
  private lastPulses: readonly PlaybackHighlight[] | null = null;
  constructor(private view: EditorView, private readonly sources: SourceElements) {
    this.unsubscribe = this.sources.subscribe(() => this.apply());
    this.apply();
  }
  update(): void {
    if (this.pulses() !== this.lastPulses) this.apply();
  }
  destroy(): void { this.unsubscribe(); }
  private pulses(): readonly PlaybackHighlight[] { return this.view.state.field(pulseField).pulses; }
  private apply(): void {
    const pulses = this.pulses();
    this.lastPulses = pulses;
    for (const source of this.sources.all()) source.element.classList.toggle("is-playing", sourceIsPlaying(source, pulses));
  }
}

/** Marks the elements shown in `sources` while their source is sounding. */
export function playbackHighlights(sources: SourceElements): Extension {
  return [pulseField, ViewPlugin.define(view => new PulseDOM(view, sources))];
}

export function setPlaybackHighlights(view: EditorView, pulses: readonly PlaybackHighlight[]): void {
  if (view.state.field(pulseField, false) === undefined) throw new Error("playbackHighlights() is not installed");
  const current = view.state.field(pulseField).pulses;
  const next = pulses;
  let unchanged = current.length === next.length;
  for (let index = 0; unchanged && index < current.length; index++) {
    const before = current[index], after = next[index];
    unchanged = before.from === after.from && before.to === after.to &&
      before.references.length === after.references.length &&
      before.references.every((ref, refIndex) => ref.from === after.references[refIndex].from && ref.to === after.references[refIndex].to) &&
      (before.notation === null ? after.notation === null : after.notation !== null &&
        before.notation.from === after.notation.from && before.notation.to === after.notation.to &&
        before.notation.start === after.notation.start && before.notation.pitch === after.notation.pitch);
  }
  if (unchanged) return;
  view.dispatch({ effects: setPulses.of(next), annotations: Transaction.addToHistory.of(false) });
}
