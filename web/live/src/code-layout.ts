import { StateEffect, StateField, type EditorState, type Extension, type Range } from "@codemirror/state";
import { Decoration, EditorView, ViewPlugin, WidgetType, type DecorationSet, type ViewUpdate } from "@codemirror/view";
import type { SyntaxNode } from "@lezer/common";
import { syntaxTree } from "@codemirror/language";
import { KNOB_COLUMNS, controlPositions } from "./inline-controls";

// Display-only layout for statements longer than the editor is wide. Like a
// code formatter, it breaks by syntax rather than wherever the text runs out:
// a call that does not fit breaks after its "(" with its arguments one level in,
// and a chain that does not fit puts its method calls on indented rows, filling
// each row. The code font is monospaced, so the editor width in columns decides
// every break before anything is drawn, and nothing is measured and laid out
// again. Breaks are widgets; the source text never changes. A phrase too long
// for the rest of its row wraps inside a box sized to those columns, so its rows
// stay under its opening quote.

/** A display row break before `pos`, starting the new row `indent` columns from the statement. */
export type Break = { pos: number; indent: number };
/** A phrase too long for the rest of its row, which wraps inside a box `columns` wide. */
export type Box = { from: number; to: number; columns: number };

const CHAIN_INDENT = 2;
const ARG_INDENT = 2;

// East Asian wide and fullwidth characters, which the code font draws from a wider fallback.
const WIDE = /[\u1100-\u115f\u2e80-\u303e\u3041-\u33ff\u3400-\u4dbf\u4e00-\u9fff\ua000-\ua4cf\uac00-\ud7a3\uf900-\ufaff\ufe30-\ufe4f\uff00-\uff60\uffe0-\uffe6]/;

/** Measured code columns: the row width, and how wide a wide character is. */
export type Columns = { row: number; wide: number };

/** CSS pixel widths measured from the editor: a row's text, one code column, a wide character, and a digit. */
export type MeasuredWidths = Readonly<{ rowText: number; column: number; wideGlyph: number; digitGlyph: number }>;

/**
 * The columns those widths give: how many fit in a row, and how many a wide
 * character takes, relative to a digit (to two decimals).
 */
export function measuredColumns({ rowText, column, wideGlyph, digitGlyph }: MeasuredWidths): Columns {
  return { row: Math.floor(rowText / column), wide: Math.round(wideGlyph / digitGlyph * 100) / 100 };
}

/**
 * Columns the UTF-16 code unit at `at` takes, where a wide character takes
 * `wide`. A surrogate pair (emoji, rare ideographs) counts once, as wide.
 */
function codeUnitColumns(source: string, at: number, wide: number): number {
  const code = source.charCodeAt(at);
  const startsPair = code >= 0xd800 && code <= 0xdbff;
  const endsPair = code >= 0xdc00 && code <= 0xdfff;
  if (endsPair) return 0;
  return startsPair || (code >= 0x1100 && WIDE.test(source[at])) ? wide : 1;
}

function sameColumns(a: Columns, b: Columns): boolean {
  return a.row === b.row && a.wide === b.wide;
}

/**
 * Breaks for the top-level expression `node`, given the measured columns and
 * the columns of widgets drawn at source positions (inline knobs). Pure: no DOM.
 */
export function layoutStatement(source: string, node: SyntaxNode, columns: Columns, widgetColumns: ReadonlyMap<number, number>): { breaks: Break[]; boxes: Box[] } {
  const lineStart = source.lastIndexOf("\n", node.from - 1) + 1;
  const breaks: Break[] = [];
  const boxes: Box[] = [];
  // Only single-line statements: a multi-line one is already laid out by its author.
  if (source.slice(lineStart, node.to).includes("\n")) return { breaks, boxes };
  const width = (from: number, to: number) => {
    let total = 0;
    for (let at = from; at < to; at++) total += codeUnitColumns(source, at, columns.wide);
    for (const [pos, widgetWidth] of widgetColumns) if (from <= pos && pos < to) total += widgetWidth;
    return total;
  };
  let pos = node.from;
  let col = width(lineStart, node.from);
  const moveTo = (to: number) => { col += width(pos, to); pos = to; };
  const breakAt = (at: number, indent: number) => { breaks.push({ pos: at, indent }); pos = at; col = indent; };
  const fits = (to: number) => col + width(pos, to) <= columns.row;

  function expression(expr: SyntaxNode, indent: number, end: number): void {
    const chains = expr.getChildren("Chain");
    chains.forEach((item, index) => {
      const last = index === chains.length - 1;
      const itemEnd = last ? end : item.to;
      // A row starts with its "+", so an overlay never reads as one more call on the chain above.
      const plus = item.prevSibling?.name === "+" ? item.prevSibling.from : item.from;
      moveTo(plus);
      if (index > 0 && !fits(itemEnd) && col > indent) breakAt(plus, indent);
      chain(item, indent, itemEnd);
    });
  }

  function chain(node: SyntaxNode, indent: number, end: number): void {
    moveTo(node.from);
    if (fits(end)) { moveTo(node.to); return; }
    const first = node.firstChild!;
    const members = node.getChildren("MemberCall");
    const head = call(first, indent, members.length ? first.to : end);
    members.forEach((member, index) => {
      const memberEnd = index === members.length - 1 ? end : member.to;
      moveTo(member.from);
      // After a broken head the chain starts a row of its own, one level out from the
      // arguments; a head that closed on its own row has already started it.
      if ((index === 0 && head === "broken") || (!fits(memberEnd) && col > indent)) breakAt(member.from, indent);
      call(member, indent, memberEnd);
    });
  }

  /** Lays out a call or group: whole on its row, broken across rows, or broken and closed on a row of its own. */
  function call(node: SyntaxNode, indent: number, end: number): "whole" | "broken" | "closed" {
    moveTo(node.from);
    if (fits(end)) { moveTo(node.to); return "whole"; }
    const open = node.name === "Group" ? node.firstChild : node.getChild("Args")?.firstChild;
    if (!open || open.name !== "(") { moveTo(node.to); return "whole"; }
    const inner = indent + ARG_INDENT;
    const items: SyntaxNode[] = [];
    for (let child = open.nextSibling; child; child = child.nextSibling) {
      // The denominator of a fraction such as 1/2 belongs to its numerator.
      if (child.name === "/") { child = child.nextSibling; if (!child) break; continue; }
      if (!["(", ")", ",", "LineComment", "BlockComment"].includes(child.name)) items.push(child);
    }
    if (!items.length) { moveTo(node.to); return "whole"; }
    moveTo(open.to);
    const before = breaks.length;
    items.forEach((item, index) => {
      // An argument row ends with its "," or, for the last, the closing ")" and whatever follows it.
      const itemEnd = index === items.length - 1 ? Math.max(end, item.to) : item.to + 1;
      moveTo(item.from);
      if (index === 0 || (!fits(itemEnd) && col > inner)) breakAt(item.from, inner);
      if (item.name === "Expression") expression(item, inner, itemEnd);
      // Its "," wraps with it, so the punctuation is never stranded on a row of its own.
      else if (item.name === "String" && !fits(itemEnd)) boxes.push({ from: item.from, to: index === items.length - 1 ? item.to : item.to + 1, columns: columns.row - col });
      moveTo(item.to);
    });
    // Arguments over several rows close on a row of their own, so the call's end is as visible as its start.
    const close = (node.name === "Group" ? node : node.getChild("Args"))?.lastChild;
    const closed = breaks.length - before > 1 && close?.name === ")";
    if (closed) breakAt(close.from, indent);
    // Otherwise the ")" stays with a last phrase that wraps in its box.
    else if (close?.name === ")" && boxes.at(-1)?.to === close.from) boxes.at(-1)!.to = close.to;
    moveTo(node.to);
    return closed ? "closed" : "broken";
  }

  // A Binding's ";" ends the last row too.
  let end = node.to;
  while (source[end] === ";") end++;
  expression(node, CHAIN_INDENT, end);
  return { breaks, boxes };
}

class RowBreak extends WidgetType {
  toDOM(): HTMLElement {
    const dom = document.createElement("span");
    dom.className = "cm-row-break";
    dom.append(document.createElement("br"));
    return dom;
  }
  override ignoreEvent(): boolean { return false; }
}
const rowBreak = new RowBreak();

const setMeasure = StateEffect.define<Columns>();

function decorations(state: EditorState, columns: Columns | null): DecorationSet {
  if (!columns || columns.row <= 0) return Decoration.none;
  const source = state.doc.toString();
  const tree = syntaxTree(state);
  const knobColumns = new Map(controlPositions(tree, source).map(pos => [pos, KNOB_COLUMNS]));
  const ranges: Range<Decoration>[] = [];
  tree.iterate({ enter: ref => {
    if (ref.name !== "Expression") return;
    const { breaks, boxes } = layoutStatement(source, ref.node, columns, knobColumns);
    // The break holds only the line break and the row's indent pads its start, so
    // nothing but text and knobs sits between rows and End and Home reach each
    // row's end and start; the narrow-screen layout test covers both.
    const indents = new Map(breaks.map(({ pos, indent }) => [pos, indent]));
    for (const { pos } of breaks) ranges.push(Decoration.widget({ widget: rowBreak, side: -2 }).range(pos));
    for (const { from, to, columns } of boxes) {
      // A phrase box that starts a row takes the indent outside its width.
      const indent = indents.get(from) ?? 0;
      indents.delete(from);
      ranges.push(Decoration.mark({ class: "cm-wrap-phrase", attributes: {
        style: `max-width: ${columns}ch; margin-left: ${indent}ch`,
      } }).range(from, to));
    }
    for (const [pos, indent] of indents) if (indent > 0)
      ranges.push(Decoration.mark({ inclusiveStart: true, attributes: { style: `padding-left: ${indent}ch` } }).range(pos, pos + 1));
    return false;
  } });
  return Decoration.set(ranges, true);
}

const layout = StateField.define<{ columns: Columns | null; decorations: DecorationSet }>({
  create: state => ({ columns: null, decorations: decorations(state, null) }),
  update(value, transaction) {
    let columns = value.columns;
    for (const effect of transaction.effects) if (effect.is(setMeasure)) columns = effect.value;
    // The tree can also grow after the edit, as parsing completes in the background.
    if (columns === value.columns && syntaxTree(transaction.state) === syntaxTree(transaction.startState)) return value;
    return { columns, decorations: decorations(transaction.state, columns) };
  },
  provide: field => EditorView.decorations.from(field, value => value.decorations),
});

const glyphCanvas = document.createElement("canvas").getContext("2d")!;

/** The width a code row's text gets: the content box minus each line's inset, registered as CSS lengths. */
function rowTextWidth(content: HTMLElement, style: CSSStyleDeclaration): number {
  const lengths = [style.paddingLeft, style.paddingRight, style.getPropertyValue("--line-start"), style.getPropertyValue("--line-end")];
  return content.clientWidth - lengths.reduce((sum, length) => sum + parseFloat(length), 0);
}

/** How wide the code font draws a wide character and a digit, measured on a canvas so the layout is untouched. */
function glyphWidths(style: CSSStyleDeclaration): { wideGlyph: number; digitGlyph: number } {
  glyphCanvas.font = `${style.fontStyle} ${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;
  return { wideGlyph: glyphCanvas.measureText("国").width, digitGlyph: glyphCanvas.measureText("0").width };
}

const measurer = ViewPlugin.fromClass(class {
  constructor(readonly view: EditorView) { this.measure(); }
  update(update: ViewUpdate): void { if (update.geometryChanged) this.measure(); }
  measure(): void {
    this.view.requestMeasure({
      key: this,
      // The content element carries the code font and the line inset.
      read: view => {
        const style = getComputedStyle(view.contentDOM);
        return measuredColumns({
          rowText: rowTextWidth(view.contentDOM, style),
          column: view.defaultCharacterWidth,
          ...glyphWidths(style),
        });
      },
      write: (next, view) => {
        const current = view.state.field(layout).columns;
        if (current && sameColumns(current, next)) return;
        // Updates may not start inside a measure cycle; a microtask still lands before paint.
        queueMicrotask(() => view.dispatch({ effects: setMeasure.of(next) }));
      },
    });
  }
});

export function codeLayout(): Extension {
  return [layout, measurer];
}
