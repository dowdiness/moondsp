import { StateEffect, StateField, Transaction, type Extension, type Range } from "@codemirror/state";
import { Decoration, EditorView, ViewPlugin, type DecorationSet, type ViewUpdate } from "@codemirror/view";

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
      mark("cm-playback-atom", pulse.from, pulse.to);
      for (const ref of pulse.references)
        if (ref.from >= 0 && ref.to > ref.from && ref.to <= docLength)
          mark("cm-playback-reference", ref.from, ref.to);
    }
    ranges.sort((a, b) => a.from - b.from || a.to - b.to);
    return { pulses, decorations: ranges.length ? Decoration.set(ranges, true) : Decoration.none };
  },
  provide: field => EditorView.decorations.from(field, value => value.decorations),
});

class PulseDOM {
  private lastPulses: readonly PlaybackHighlight[] | null = null;
  constructor(private view: EditorView) { this.apply(); }
  update(update: ViewUpdate): void {
    if (update.docChanged || update.viewportChanged || update.selectionSet || this.pulses() !== this.lastPulses) this.apply();
  }
  // Widgets may be replaced after update(); decorate the new nodes as well.
  docViewUpdate(): void { this.apply(); }
  private pulses(): readonly PlaybackHighlight[] { return this.view.state.field(pulseField).pulses; }
  private apply(): void {
    const pulses = this.pulses();
    this.lastPulses = pulses;
    const pulseKey = (from: number, to: number) => `${from}:${to}`;
    const sourceKeys = new Set(pulses.map(pulse => pulseKey(pulse.from, pulse.to)));
    for (const source of this.view.dom.querySelectorAll<HTMLElement | SVGElement>(".moving-score__source[data-from][data-to], .step-pad[data-from][data-to], .chord-tones[data-from][data-to]")) {
      const active = sourceKeys.has(pulseKey(Number(source.dataset.from), Number(source.dataset.to)));
      source.classList.toggle("is-playing", active);
    }
    const notes = this.view.dom.querySelectorAll<SVGGElement>(".moving-score__note[data-from][data-to]");
    for (const note of notes) {
      const from = Number(note.dataset.from), to = Number(note.dataset.to);
      const start = Number(note.dataset.start), pitch = note.dataset.pitch === "null" ? null : Number(note.dataset.pitch);
      const active = pulses.some(pulse => pulse.from === from && pulse.to === to && pulse.notation !== null &&
        note.dataset.literalFrom === String(pulse.notation.from) && note.dataset.literalTo === String(pulse.notation.to) &&
        pulse.notation.start === start && pulse.notation.pitch === pitch);
      note.classList.toggle("is-playing", active);
    }
    for (const source of this.view.dom.querySelectorAll<SVGElement>(".moving-score__source-hit[data-from][data-to]"))
      source.classList.toggle("is-playing", sourceKeys.has(pulseKey(Number(source.dataset.from), Number(source.dataset.to))));
  }
}

export function playbackHighlights(): Extension {
  return [pulseField, ViewPlugin.fromClass(PulseDOM)];
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
