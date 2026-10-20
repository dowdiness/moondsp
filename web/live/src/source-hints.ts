import type { Extension } from "@codemirror/state";
import { EditorView, ViewPlugin, type ViewUpdate } from "@codemirror/view";
import type { SourceElement, SourceElements } from "./source-elements";

// Hovering a source atom in code hints its notes or pads in the phrase GUI, and
// hovering a note or pad hints its atom in code. Hints are transient pointer
// feedback: they never select, edit, dispatch a transaction, or start audio.
// The code side uses the CSS Custom Highlight API. The decisions are the pure
// functions below; the plugin reads the pointer, measures, and paints.

const HINTED = "is-hinted";
const HIGHLIGHT = "source-hint";

type Span = Readonly<{ from: number; to: number }>;
type Box = Readonly<{ left: number; right: number; top: number; bottom: number }>;

/** The source span under `pos` among `spans`, preferring the narrowest. */
export function spanAt(spans: readonly Span[], pos: number): Span | null {
  let best: Span | null = null;
  for (const span of spans)
    if (span.from <= pos && pos < span.to && (!best || span.to - span.from < best.to - best.from)) best = span;
  return best;
}

/** Whether the point lies over an atom drawn from the `start` box of its first glyph to the `end` box of its last. */
export function overGlyphs(x: number, y: number, start: Box, end: Box): boolean {
  return x >= start.left && x <= end.right && y >= start.top && y <= end.bottom;
}

class SourceHints {
  private readonly unsubscribe: () => void;
  private hinted: readonly SourceElement[] = [];
  private span: Span | null = null;

  constructor(private readonly view: EditorView, private readonly sources: SourceElements) {
    // A redraw can replace the hinted elements; paint the new ones once the view settles.
    this.unsubscribe = this.sources.subscribe(() => {
      if (this.span) view.requestMeasure({ key: this, read: () => null, write: () => this.paint() });
    });
    view.contentDOM.addEventListener("pointermove", this.onMove);
    view.contentDOM.addEventListener("pointerleave", this.clear);
  }

  update(update: ViewUpdate): void {
    if (update.docChanged || update.viewportChanged) this.clear();
  }

  destroy(): void {
    this.unsubscribe();
    this.view.contentDOM.removeEventListener("pointermove", this.onMove);
    this.view.contentDOM.removeEventListener("pointerleave", this.clear);
    this.clear();
  }

  private readonly onMove = (event: PointerEvent): void => {
    if (event.pointerType !== "mouse" || event.buttons !== 0) { this.clear(); return; }
    const hints = this.sources.all().filter(source => source.hint);
    const target = event.target instanceof Node ? event.target : null;
    const drawn = target && hints.find(source => source.element.contains(target));
    if (drawn) { this.show(drawn); return; }
    // posAtCoords snaps to the nearest caret; the pointer must also sit over the atom's glyphs.
    const span = spanAt(hints, this.view.posAtCoords({ x: event.clientX, y: event.clientY }, false));
    const start = span && this.view.coordsAtPos(span.from, 1);
    const end = span && this.view.coordsAtPos(span.to, -1);
    if (span && start && end && overGlyphs(event.clientX, event.clientY, start, end)) this.show(span);
    else this.clear();
  };

  private show(span: Span): void {
    if (this.span && this.span.from === span.from && this.span.to === span.to) return;
    this.clear();
    this.span = { from: span.from, to: span.to };
    this.paint();
  }

  private paint(): void {
    const span = this.span;
    if (!span) return;
    for (const source of this.hinted) source.element.classList.remove(HINTED);
    this.hinted = this.sources.all().filter(source => source.hint && source.from === span.from && source.to === span.to);
    for (const source of this.hinted) source.element.classList.add(HINTED);
    const start = this.view.domAtPos(span.from, 1);
    const end = this.view.domAtPos(span.to, -1);
    const range = new Range();
    range.setStart(start.node, start.offset);
    range.setEnd(end.node, end.offset);
    CSS.highlights.set(HIGHLIGHT, new Highlight(range));
  }

  private readonly clear = (): void => {
    for (const source of this.hinted) source.element.classList.remove(HINTED);
    this.hinted = [];
    this.span = null;
    CSS.highlights.delete(HIGHLIGHT);
  };
}

/** Hints in code the source of a hovered element shown in `sources`. */
export function sourceHints(sources: SourceElements): Extension {
  return ViewPlugin.define(view => new SourceHints(view, sources));
}
