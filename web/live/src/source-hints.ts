import type { Extension } from "@codemirror/state";
import { EditorView, ViewPlugin, type ViewUpdate } from "@codemirror/view";

// Hovering a source atom in code hints its notes or pads in the phrase GUI, and
// hovering a note or pad hints its atom in code. Hints are transient pointer
// feedback: they never select, edit, dispatch a transaction, or start audio.
// The code side uses the CSS Custom Highlight API.

const HINTED = "is-hinted";
const HIGHLIGHT = "source-hint";
const SOURCES = ".moving-score__note[data-from][data-to], .drum-sequencer__cell[data-from][data-to], .step-pad[data-from][data-to]";

type Span = { from: number; to: number };

/** The source span under `pos` among `spans`, preferring the narrowest. */
export function spanAt(spans: readonly Span[], pos: number): Span | null {
  let best: Span | null = null;
  for (const span of spans)
    if (span.from <= pos && pos < span.to && (!best || span.to - span.from < best.to - best.from)) best = span;
  return best;
}

class SourceHints {
  private hinted: Element[] = [];
  private span: Span | null = null;

  constructor(private readonly view: EditorView) {
    view.contentDOM.addEventListener("pointermove", this.onMove);
    view.contentDOM.addEventListener("pointerleave", this.clear);
  }

  update(update: ViewUpdate): void {
    if (update.docChanged || update.viewportChanged) { this.clear(); return; }
    // Playback highlights and GUI refreshes redraw the hinted nodes; paint again afterwards.
    if (this.span) this.view.requestMeasure({ read: () => null, write: () => this.paint() });
  }

  destroy(): void {
    this.view.contentDOM.removeEventListener("pointermove", this.onMove);
    this.view.contentDOM.removeEventListener("pointerleave", this.clear);
    this.clear();
  }

  private readonly onMove = (event: PointerEvent): void => {
    if (event.pointerType !== "mouse" || event.buttons !== 0) { this.clear(); return; }
    const target = event.target instanceof Element ? event.target : null;
    const widget = target?.closest(".cm-score-pattern");
    if (widget) {
      const source = target?.closest<HTMLElement | SVGElement>(SOURCES);
      if (!source) { this.clear(); return; }
      this.show({ from: Number(source.dataset.from), to: Number(source.dataset.to) });
      return;
    }
    const pos = this.view.posAtCoords({ x: event.clientX, y: event.clientY }, false);
    const spans = [...this.view.contentDOM.querySelectorAll<HTMLElement | SVGElement>(SOURCES)]
      .map(element => ({ from: Number(element.dataset.from), to: Number(element.dataset.to) }));
    const span = spanAt(spans, pos);
    // posAtCoords snaps to the nearest caret; require the pointer to sit over the atom's glyphs.
    if (span) {
      const start = this.view.coordsAtPos(span.from, 1);
      const end = this.view.coordsAtPos(span.to, -1);
      if (start && end && event.clientX >= start.left && event.clientX <= end.right &&
        event.clientY >= start.top && event.clientY <= end.bottom) { this.show(span); return; }
    }
    this.clear();
  };

  private show(span: Span): void {
    if (this.span && this.span.from === span.from && this.span.to === span.to) return;
    this.clear();
    this.span = span;
    this.paint();
  }

  private paint(): void {
    const span = this.span;
    if (!span) return;
    for (const element of this.hinted) element.classList.remove(HINTED);
    this.hinted = [];
    for (const element of this.view.contentDOM.querySelectorAll<HTMLElement | SVGElement>(SOURCES)) {
      if (element.dataset.from !== String(span.from) || element.dataset.to !== String(span.to)) continue;
      element.classList.add(HINTED);
      this.hinted.push(element);
    }
    const start = this.view.domAtPos(span.from, 1);
    const end = this.view.domAtPos(span.to, -1);
    const range = new Range();
    range.setStart(start.node, start.offset);
    range.setEnd(end.node, end.offset);
    CSS.highlights.set(HIGHLIGHT, new Highlight(range));
  }

  private readonly clear = (): void => {
    for (const element of this.hinted) element.classList.remove(HINTED);
    this.hinted = [];
    this.span = null;
    CSS.highlights.delete(HIGHLIGHT);
  };
}

export function sourceHints(): Extension {
  return ViewPlugin.fromClass(SourceHints);
}
