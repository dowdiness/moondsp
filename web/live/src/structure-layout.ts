// Functional core for the structure strip: a phrase's source steps, groups,
// and weight boundaries laid out in rows, what a pointer selects there, and
// the SVG that shows them.
import { BOUNDARY_MAX, BOUNDARY_MIN, boundaryInfo, layoutNodes, type NotationProjection } from "./notation-structure";
import type { Step } from "./pattern-controls";
import type { PlotScale } from "./score-geometry";
import type { SvgNode } from "./svg-patch";

/** The height of one strip row in viewBox units. */
export const STRIP_ROW = 32;

export type StripPhrase = Readonly<{ steps: readonly Step[]; structure: NotationProjection }>;
type Span = Readonly<{ x: number; width: number }>;
export type StripSource = Readonly<{ node: number; index: number; step: Step; left: number; right: number; hit: Span; label: string | null }>;
export type StripGroup = Readonly<{ node: number; depth: number; value: string; left: number; right: number; hit: Span }>;
export type StripBoundary = Readonly<{
  /** The node left of the boundary, which names it. */
  node: number;
  depth: number;
  ratio: number;
  x: number;
  /** Where the pair the boundary divides starts and ends. */
  start: number;
  end: number;
  hit: Span;
  label: string;
}>;
export type StripLayout = Readonly<{ rows: number; sourceRow: number; sources: readonly StripSource[]; groups: readonly StripGroup[]; boundaries: readonly StripBoundary[] }>;

/** A target at least `width` wide, centred on `center` and kept inside the plot. */
function target(scale: PlotScale, center: number, width: number): Span {
  const { plotLeft, plotRight } = scale.geometry;
  return { x: Math.max(plotLeft, Math.min(plotRight - width, center - width / 2)), width };
}

/**
 * Groups take a row per nesting depth above the source row. `rowPixels` is a
 * row's CSS height, which decides whether a source label fits.
 */
export function stripLayout(phrase: StripPhrase, scale: PlotScale, rowPixels: number): StripLayout {
  const { steps, structure } = phrase;
  const layout = layoutNodes(structure);
  const groupDepths = layout.flatMap(item => structure.nodes[item.node].kind === "group" ? [item.depth] : []);
  const sourceRow = groupDepths.length ? Math.max(...groupDepths) + 1 : 0;
  const minimum = Math.min(scale.geometry.plotRight - scale.geometry.plotLeft, scale.px(44));
  const sources: StripSource[] = [];
  const groups: StripGroup[] = [];
  for (const item of layout) {
    const node = structure.nodes[item.node];
    const left = scale.fraction(item.start), right = scale.fraction(item.end);
    if (node.kind === "atom") {
      const index = steps.findIndex(step => step.node === item.node);
      const step = steps[index];
      const width = Math.max(1, right - left);
      const text = step.rest ? "Rest" : step.value;
      const fits = width / scale.px(1) >= Math.max(36, text.length * 7.5 * rowPixels / STRIP_ROW + 8);
      sources.push({ node: item.node, index, step, left, right, hit: target(scale, (left + right) / 2, Math.max(width, minimum)), label: fits ? text : null });
    } else if (node.kind === "group") {
      groups.push({ node: item.node, depth: item.depth, value: node.value, left, right, hit: target(scale, (left + right) / 2, Math.max(right - left, minimum)) });
    }
  }
  const byNode = new Map(layout.map(item => [item.node, item]));
  const boundaries: StripBoundary[] = [];
  structure.nodes.forEach((node, index) => {
    if (node.kind !== "atom" && node.kind !== "group") return;
    const info = boundaryInfo(structure, index);
    const left = byNode.get(index), right = info && byNode.get(info.right);
    if (!info || !left || !right) return;
    const x = scale.fraction(left.end);
    boundaries.push({
      node: index, depth: left.depth, ratio: info.ratio, x,
      start: scale.fraction(left.start), end: scale.fraction(right.end),
      hit: target(scale, x, Math.max(44, minimum)),
      label: node.kind === "group" ? "Weight boundary after notation group"
        : `Weight boundary after source step ${steps.findIndex(step => step.node === index) + 1}`,
    });
  });
  return { rows: sourceRow + 1, sourceRow, sources, groups, boundaries };
}

/** The x of a boundary that divides its pair at `ratio`. */
export function boundaryX(boundary: StripBoundary, ratio: number): number {
  return boundary.start + (boundary.end - boundary.start) * ratio;
}

function within(span: Span, x: number): boolean { return x >= span.x && x <= span.x + span.width; }
/** The last match: the target drawn on top. */
function topmost<T>(items: readonly T[], match: (item: T) => boolean): T | undefined {
  for (let index = items.length - 1; index >= 0; index--) if (match(items[index])) return items[index];
  return undefined;
}

/** The item centred nearest `x`, keeping `preferred` on a tie. */
function nearest<T>(items: readonly T[], center: (item: T) => number, x: number, preferred: T): T {
  let best = preferred, distance = Math.abs(center(preferred) - x);
  for (const item of items) {
    const next = Math.abs(center(item) - x);
    if (next < distance) { best = item; distance = next; }
  }
  return best;
}

export type StripHit =
  | Readonly<{ kind: "boundary"; boundary: StripBoundary }>
  | Readonly<{ kind: "select"; node: number }>;

/**
 * What a pointer at viewBox (`x`, `y`) grabs. Targets are at least 44 px wide,
 * so neighbours overlap; touching any target picks the item of its kind
 * centred nearest the pointer. Boundaries lie over source steps.
 */
export function hitStrip(layout: StripLayout, x: number, y: number): StripHit | null {
  const row = Math.floor(y / STRIP_ROW);
  if (row === layout.sourceRow) {
    const boundary = topmost(layout.boundaries, item => within(item.hit, x));
    if (boundary) {
      const peers = layout.boundaries.filter(item => item.depth === boundary.depth);
      return { kind: "boundary", boundary: nearest(peers, item => item.x, x, boundary) };
    }
    const source = topmost(layout.sources, item => within(item.hit, x));
    return source ? { kind: "select", node: nearest(layout.sources, item => (item.left + item.right) / 2, x, source).node } : null;
  }
  const group = topmost(layout.groups, item => item.depth === row && within(item.hit, x));
  if (!group) return null;
  const peers = layout.groups.filter(item => item.depth === group.depth);
  return { kind: "select", node: nearest(peers, item => (item.left + item.right) / 2, x, group).node };
}

export type StripState = Readonly<{
  selected: number | null;
  /** A boundary being dragged, drawn at its unapplied ratio. */
  dragging: Readonly<{ node: number; ratio: number }> | null;
}>;

export function stripNodes(layout: StripLayout, structure: NotationProjection, state: StripState): { items: SvgNode[]; hits: SvgNode[]; boundaries: SvgNode[] } {
  const context = new Set<number>();
  for (let parent = state.selected === null ? null : structure.nodes[state.selected]?.parent ?? null; parent !== null;
    parent = structure.nodes[parent]?.parent ?? null) {
    if (structure.nodes[parent]?.kind === "group") context.add(parent);
  }
  const top = layout.sourceRow * STRIP_ROW;
  const items: SvgNode[] = [];
  const sourceByNode = new Map(layout.sources.map(source => [source.node, source]));
  const groupByNode = new Map(layout.groups.map(group => [group.node, group]));
  // Layout order keeps each source's label right after its box, which styles it.
  for (const item of layoutNodes(structure)) {
    const source = sourceByNode.get(item.node), group = groupByNode.get(item.node);
    const selected = item.node === state.selected;
    if (source) {
      items.push({
        key: String(source.node), tag: "rect", className: "moving-score__source", flags: { "is-selected": selected },
        attrs: { x: String(source.left), y: String(top), width: String(Math.max(1, source.right - source.left)), height: String(STRIP_ROW),
          "data-node": String(source.node), "data-from": String(source.step.from), "data-to": String(source.step.to) },
      });
      if (source.label !== null) items.push({
        key: String(source.node), tag: "text", className: "moving-score__source-label", flags: { "is-selected": selected },
        attrs: { x: String((source.left + source.right) / 2), y: String(top + STRIP_ROW / 2), "dominant-baseline": "central", "aria-hidden": "true" },
        text: source.label,
      });
    } else if (group) {
      const y = group.depth * STRIP_ROW + 5;
      items.push({
        key: String(group.node), tag: "g", className: "moving-score__group",
        flags: { "is-selected": selected, "is-context": !selected && context.has(group.node) },
        attrs: { tabindex: "0", role: "button", "data-node": String(group.node), "aria-label": `Select group ${group.value || "notation"}` },
        children: [
          { key: "hit", tag: "rect", className: "moving-score__group-hit",
            attrs: { x: String(group.hit.x), y: String(group.depth * STRIP_ROW), width: String(group.hit.width), height: String(STRIP_ROW) } },
          { key: "bracket", tag: "path", className: "moving-score__bracket", attrs: { d: `M${group.left} ${y + 4}V${y}H${group.right}V${y + 4}` } },
        ],
      });
    }
  }
  const hits: SvgNode[] = layout.sources.map(source => ({
    key: String(source.node), tag: "rect", className: "moving-score__source-hit", flags: { "is-selected": source.node === state.selected },
    attrs: {
      x: String(source.hit.x), y: String(top), width: String(source.hit.width), height: String(STRIP_ROW),
      tabindex: "0", role: "button", "data-node": String(source.node),
      "data-from": String(source.step.from), "data-to": String(source.step.to),
      "aria-label": `Select source step ${source.index + 1}${source.step.rest ? ", rest" : `, ${source.step.value}`}`,
    },
  }));
  const boundaries: SvgNode[] = layout.boundaries.map((boundary): SvgNode => {
    const dragged = state.dragging?.node === boundary.node ? state.dragging.ratio : null;
    const ratio = dragged ?? boundary.ratio;
    const x = dragged === null ? boundary.x : boundaryX(boundary, dragged);
    return {
      key: String(boundary.node), tag: "g", className: "moving-score__boundary",
      attrs: {
        tabindex: "0", role: "slider", "aria-orientation": "horizontal", "data-node": String(boundary.node),
        "aria-valuemin": String(BOUNDARY_MIN), "aria-valuemax": String(BOUNDARY_MAX), "aria-valuenow": String(ratio),
        "aria-label": boundary.label,
      },
      children: [
        { key: "hit", tag: "rect", className: "moving-score__boundary-hit",
          attrs: { x: String(boundary.hit.x), y: String(top), width: String(boundary.hit.width), height: String(STRIP_ROW) } },
        { key: "mark", tag: "path", className: "moving-score__boundary-mark", attrs: { d: `M${x} ${top + 4}V${top + STRIP_ROW - 4}` } },
      ],
    };
  });
  return { items, hits, boundaries };
}
