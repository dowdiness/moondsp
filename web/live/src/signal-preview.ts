import { StateEffect, StateField, type Extension } from "@codemirror/state";
import { Decoration, EditorView, ViewPlugin, WidgetType, type DecorationSet, type ViewUpdate } from "@codemirror/view";
import type { SignalCurve, SignalGraph } from "./authoring";
import { layoutWidgets } from "./code-layout";

// A small graph before each control signal argument, such as
// `.lpf(saw.range(200, 4000).slow(4))`, so its direction and values show
// without listening. The Draft computes each graph from the compiled score:
// the curve the voices it controls follow, with every transform around the
// control applied and, in a song, each section placed where it plays. The
// horizontal axis starts at cycle 0 of the pattern or song. While the text
// does not parse, the last graphs stay with their signals, and a graph whose
// own text changes goes away until the Draft can compute it again.

/** Replaces the graphs with the Draft's graphs for the current text. */
export const setSignalGraphs = StateEffect.define<readonly SignalGraph[]>();

/**
 * A value playback is sounding now for the signal whose text starts at
 * `from`, and the material time it was read at: cycles from the start of the
 * pattern, or of the song.
 */
export type SignalPlayhead = Readonly<{ from: number; cycles: number; value: number }>;

/** Replaces the sounding signal values; an empty list shows none. */
export const setSignalPlayheads = StateEffect.define<readonly SignalPlayhead[]>();

/** Where a playhead sits across a graph, from 0 to 1: a pattern graph repeats every window, a song graph does not. */
export function playheadPosition(graph: Pick<SignalGraph, "window" | "song">, cycles: number): number {
  const at = graph.song ? cycles : (cycles % graph.window + graph.window) % graph.window;
  return Math.min(1, Math.max(0, at / graph.window));
}

/** Code columns a signal graph occupies, so long lines can lay out by column count. */
const SIGNAL_COLUMNS = 4;

const defined = (values: readonly (number | null)[]) => values.filter((value): value is number => value !== null);

const show = (value: number | null) => value === null ? "none" : String(Number(value.toPrecision(4)));

/** What the graph shows, in words: its window, and where each curve plays, starts, ends, and peaks. */
export function signalSummary({ window, song, curves }: SignalGraph): string {
  const cycles = (count: number) => `${show(count)} ${show(count) === "1" ? "cycle" : "cycles"}`;
  const lines = [song ? `Song: ${cycles(window)}` : `Over ${cycles(window)}, then repeats`];
  curves.forEach((curve, index) => {
    const label = curves.length > 1 ? `Use ${index + 1}: ` : "";
    if (song) lines.push(`${label ? `${label}plays` : "Plays"} in cycles ${curve.spans.map(([from, to]) => `${show(from)}–${show(to)}`).join(", ")}`);
    lines.push(`${song ? "" : label}Start ${show(curve.first)} → end ${show(curve.last)} · low ${show(Math.min(...defined(curve.lows)))} · high ${show(Math.max(...defined(curve.highs)))}`);
  });
  return lines.join("\n");
}

/**
 * SVG paths for each curve in a `width` × `height` box, and the height of the
 * zero line. Each run of buckets with a value is a band from its lows to its
 * highs, so a smooth curve draws as a line and a fast one as a filled band.
 * The vertical scale always includes zero, so a fade to silence touches it.
 */
export function signalPaths(curves: readonly SignalCurve[], width: number, height: number): { paths: string[]; zero: number } {
  const lows = curves.flatMap(curve => defined(curve.lows));
  const highs = curves.flatMap(curve => defined(curve.highs));
  const bottom = Math.min(0, ...lows);
  const top = Math.max(0, ...highs);
  const y = (value: number) => top === bottom ? height / 2 : height - (value - bottom) / (top - bottom) * height;
  const point = (x: number, value: number) => `${x.toFixed(2)} ${y(value).toFixed(2)}`;
  const paths = curves.map(({ lows, highs }) => {
    const x = (bucket: number) => (bucket + 0.5) / lows.length * width;
    let path = "";
    for (let start = 0; start < lows.length; start++) {
      if (lows[start] === null) continue;
      let end = start;
      while (end + 1 < lows.length && lows[end + 1] !== null) end++;
      const run = Array.from({ length: end - start + 1 }, (_, i) => start + i);
      path += `M${run.map(i => point(x(i), highs[i]!)).join("L")}L${run.reverse().map(i => point(x(i), lows[i]!)).join("L")}Z`;
      start = end;
    }
    return path;
  });
  return { paths, zero: y(0) };
}

const WIDTH = 40, HEIGHT = 10;

class SignalWidget extends WidgetType {
  private readonly key: string;
  constructor(readonly graph: SignalGraph) {
    super();
    this.key = JSON.stringify(graph);
  }
  override eq(other: SignalWidget): boolean { return this.key === other.key; }
  toDOM(view: EditorView): HTMLElement {
    const document = view.dom.ownerDocument;
    const dom = document.createElement("span");
    dom.className = "cm-signal-preview";
    dom.contentEditable = "false";
    const summary = signalSummary(this.graph);
    dom.setAttribute("role", "img");
    dom.setAttribute("aria-label", `Signal graph. ${summary.replaceAll("\n", ". ")}`);
    const { paths, zero } = signalPaths(this.graph.curves, WIDTH, HEIGHT);
    dom.innerHTML = `<svg viewBox="0 -1 ${WIDTH} ${HEIGHT + 2}" preserveAspectRatio="none" aria-hidden="true"><path class="signal-zero" d="M0 ${zero.toFixed(2)}H${WIDTH}"/>${paths.map(path => `<path class="signal-line" d="${path}"/>`).join("")}<path class="signal-playhead"/></svg><span class="cm-signal-value" aria-live="off"></span>`;
    const hint = document.createElement("span");
    hint.className = "cm-signal-hint";
    hint.setAttribute("aria-hidden", "true");
    hint.textContent = summary;
    dom.append(hint);
    // A tap opens the summary and a second tap, or one anywhere else, closes it: hover is not there on touch.
    dom.tabIndex = -1;
    dom.addEventListener("mousedown", event => event.preventDefault());
    dom.addEventListener("click", () => {
      if (document.activeElement === dom) view.focus();
      else dom.focus({ preventScroll: true });
    });
    dom.addEventListener("keydown", event => {
      if (event.key === "Escape") view.focus();
    });
    widgets.set(dom, this.graph);
    return dom;
  }
}

/** Draws `playheads` on a graph's DOM: a marker per playhead and the values they sound, or nothing. */
function drawPlayheads(dom: Element, graph: SignalGraph, playheads: readonly SignalPlayhead[]): void {
  const marker = dom.querySelector(".signal-playhead")!;
  const label = dom.querySelector(".cm-signal-value")!;
  const text = [...new Set(playheads.map(playhead => show(playhead.value)))].join(" / ");
  marker.setAttribute("d", playheads.map(playhead => `M${(playheadPosition(graph, playhead.cycles) * WIDTH).toFixed(2)} -1V${HEIGHT + 1}`).join(""));
  if (label.textContent !== text) label.textContent = text;
  dom.classList.toggle("cm-signal-playing", playheads.length > 0);
}

/** Moves the markers on the graphs already drawn, so a sounding value never rebuilds a graph. */
const playheadPlugin = (field: StateField<readonly SignalPlayhead[]>) => ViewPlugin.fromClass(class {
  constructor(view: EditorView) { this.draw(view); }
  update(update: ViewUpdate): void {
    if (update.startState.field(field) !== update.state.field(field) || update.docChanged || update.viewportChanged ||
        update.transactions.some(transaction => transaction.effects.some(effect => effect.is(setSignalGraphs)))) {
      this.draw(update.view);
    }
  }
  draw(view: EditorView): void {
    const playheads = view.state.field(field);
    for (const dom of view.contentDOM.querySelectorAll(".cm-signal-preview")) {
      const graph = widgets.get(dom);
      if (!graph) continue;
      const from = view.posAtDOM(dom);
      drawPlayheads(dom, graph, playheads.filter(playhead => playhead.from === from));
    }
  }
});

/** The graph each drawn widget shows. */
const widgets = new WeakMap<Element, SignalGraph>();

function decorations(graphs: readonly SignalGraph[]): DecorationSet {
  // Before the signal's name, after the position, as inline knobs sit.
  return Decoration.set(graphs.map(graph => Decoration.widget({ widget: new SignalWidget(graph), side: 1 }).range(graph.from)), true);
}

export function signalPreview(): Extension {
  const playheads = StateField.define<readonly SignalPlayhead[]>({
    create: () => [],
    update(value, transaction) {
      // Playback locates every playhead again each frame, so an edit only drops the old positions.
      if (transaction.docChanged) return [];
      for (const effect of transaction.effects) if (effect.is(setSignalPlayheads)) value = effect.value;
      return value;
    },
  });
  return [
    playheads,
    playheadPlugin(playheads),
    StateField.define<DecorationSet>({
      create: () => Decoration.none,
      update(value, transaction) {
        for (const effect of transaction.effects) if (effect.is(setSignalGraphs)) return decorations(effect.value);
        if (!transaction.docChanged) return value;
        // A graph describes its signal's text; once that text changes, it no longer does.
        return value.update({ filter: (from, _to, decoration) => {
          const { graph } = decoration.spec.widget as SignalWidget;
          return !transaction.changes.touchesRange(from, from + graph.to - graph.from);
        } }).map(transaction.changes);
      },
      provide: field => [EditorView.decorations.from(field), layoutWidgets.from(field, widgets => [widgets, SIGNAL_COLUMNS])],
    }),
    EditorView.baseTheme({
      ".cm-signal-preview": { position: "relative", display: "inline-flex", alignItems: "center", width: `${SIGNAL_COLUMNS}ch`, height: "1em", verticalAlign: "-0.1em", paddingRight: "0.4ch", boxSizing: "border-box" },
      ".cm-signal-preview svg": { width: "100%", height: "100%", overflow: "visible" },
      ".signal-zero": { fill: "none", stroke: "var(--border)", strokeWidth: "1", strokeDasharray: "2 2", vectorEffect: "non-scaling-stroke" },
      ".signal-line": { fill: "var(--accent)", stroke: "var(--accent)", strokeWidth: "1.5", strokeLinejoin: "round", vectorEffect: "non-scaling-stroke" },
      ".cm-signal-hint": { display: "none", position: "absolute", top: "calc(100% + 4px)", left: "0", zIndex: "20", pointerEvents: "none", whiteSpace: "pre", padding: "3px 7px", border: "1px solid var(--border)", borderRadius: "4px", background: "var(--panel)", color: "var(--ink-muted)", font: "12px/1.4 var(--font-body)" },
      ".cm-signal-preview:focus": { outline: "none" },
      ".cm-signal-preview:focus .cm-signal-hint": { display: "block" },
      "@media (hover: hover) and (pointer: fine)": { ".cm-signal-preview:hover .cm-signal-hint": { display: "block" } },
      ".signal-playhead": { fill: "none", stroke: "var(--ink)", strokeWidth: "1.5", vectorEffect: "non-scaling-stroke" },
      // The value sits in the leading between this line's code and the line above, sized by the code, so it never covers code.
      ".cm-signal-value": { display: "none", position: "absolute", bottom: "calc(100% + 0.08em)", left: "0", zIndex: "10", pointerEvents: "none", whiteSpace: "nowrap", padding: "0 0.2em", borderRadius: "3px", background: "var(--panel)", color: "var(--ink)", font: "0.55em/1 var(--font-mono)", fontVariantNumeric: "tabular-nums" },
      ".cm-signal-playing .cm-signal-value": { display: "block" },
    }),
  ];
}
