// Functional core for the note grid: where a phrase's notes, rests, and resize
// edges are drawn, what lies under a point, and the SVG that shows them.
import type { NotationEvent, NotationNode, NotationProjection } from "./notation-structure";
import type { Step } from "./pattern-controls";
import { midiValue } from "./pitch";
import { ROW_H, TIME_H, W, type PlotScale } from "./score-geometry";
import type { SvgNode } from "./svg-patch";

export function noteMidi(value: string): number | null { return midiValue(value.split("@")[0])?.midi ?? null; }
export function pitchName(midi: number): string {
  const names = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"];
  return `${names[midi % 12]}${Math.floor(midi / 12) - 1}`;
}
export function displayPitch(value: string): string { return value.replaceAll("#", "♯").replaceAll("b", "♭"); }

export type GridPhrase = Readonly<{
  steps: readonly Step[];
  structure: NotationProjection;
  /** Chord tones are shown, not edited: they have no rests or edges to grab. */
  notationKind: "note" | "chord";
}>;
type Box = Readonly<{ x: number; y: number; width: number; height: number }>;
/** A grip that resizes a note against its neighbour by moving their shared weight boundary. */
export type GridEdge = Readonly<{
  side: "left" | "right";
  leftNode: number;
  rightNode: number;
  /** The notation time the two notes span together. */
  pairStart: number;
  pairEnd: number;
  ratio: number;
  hit: Box;
  markX: number;
}>;
export type GridNote = Readonly<{
  key: string;
  node: number;
  index: number;
  step: Step;
  start: number;
  /** The end inside the phrase. */
  end: number;
  midi: number | null;
  block: Box;
  label: string | null;
  labelX: number;
  edges: readonly GridEdge[];
}>;
/** A rest's time interval, where a pointer chooses the pitch of a new note. */
export type GridRest = Readonly<{ key: string; node: number; start: number; end: number; x: number; width: number }>;
export type GridLayout = Readonly<{ notes: readonly GridNote[]; rests: readonly GridRest[] }>;
export const EMPTY_GRID: GridLayout = { notes: [], rests: [] };

/** The drawn rectangle of a note from `start` to `end` on the row centred at `y`. */
export function noteBlock(scale: PlotScale, start: number, end: number, y: number): Box {
  const width = scale.time(end) - scale.time(start);
  return {
    x: scale.time(start) + Math.min(scale.px(1.5), width / 4),
    y: y - ROW_H / 2 + 2,
    width: Math.max(scale.px(1), width - scale.px(3)),
    height: ROW_H - 4,
  };
}

/** A note with at most a weight, which a boundary move can resize. */
function plainAtom(node: NotationNode | undefined): boolean {
  return node?.kind === "atom" && node.modifiers.length <= 1 && node.modifiers.every(modifier => modifier.kind === "weight");
}

/** Whether every occurrence of `node` plays in source order, so its edges match its weights. */
function linear(structure: NotationProjection, node: NotationNode): boolean {
  for (let ancestor = node.parent; ancestor !== null; ancestor = structure.nodes[ancestor].parent) {
    const parent = structure.nodes[ancestor];
    if (parent.kind === "parallel" || (parent.kind === "group" && parent.modifiers.some(modifier => modifier.kind !== "repeat"))) return false;
  }
  return true;
}

function edgesOf(structure: NotationProjection, event: NotationEvent, end: number, block: Box, scale: PlotScale): GridEdge[] {
  const node = structure.nodes[event.node];
  if (!plainAtom(node) || !linear(structure, node)) return [];
  const parent = node.parent === null ? null : structure.nodes[node.parent];
  const siblings = parent?.kind === "sequence" ? parent.children : [];
  const at = siblings.indexOf(event.node);
  const width = scale.time(end) - scale.time(event.start);
  const edges: GridEdge[] = [];
  for (const side of ["left", "right"] as const) {
    const neighbor = siblings[at + (side === "left" ? -1 : 1)];
    if (neighbor === undefined || !plainAtom(structure.nodes[neighbor])) continue;
    const adjacent = [...structure.events, ...structure.rests].find(item => item.node === neighbor &&
      Math.abs(side === "left" ? item.end - event.start : item.start - event.end) < 1e-7);
    if (!adjacent) continue;
    const leftNode = side === "left" ? neighbor : event.node;
    const rightNode = side === "left" ? event.node : neighbor;
    const leftWeight = structure.nodes[leftNode].weight, rightWeight = structure.nodes[rightNode].weight;
    const center = scale.time(side === "left" ? event.start : event.end);
    edges.push({
      side, leftNode, rightNode,
      pairStart: side === "left" ? adjacent.start : event.start,
      pairEnd: side === "left" ? event.end : adjacent.end,
      ratio: leftWeight / (leftWeight + rightWeight),
      hit: { x: center - Math.min(scale.px(4), width / 4), y: block.y, width: Math.max(1, Math.min(scale.px(8), width / 2)), height: block.height },
      // The grip sits just inside the note so it never reads as a stray tick.
      markX: center + (side === "left" ? 1 : -1) * Math.min(scale.px(5), width / 4),
    });
  }
  return edges;
}

export function gridLayout(phrase: GridPhrase, scale: PlotScale): GridLayout {
  const { steps, structure } = phrase;
  const editable = phrase.notationKind === "note";
  const stepByNode = new Map(steps.map((step, index) => [step.node, { step, index }]));
  const rests: GridRest[] = [];
  if (editable) {
    for (const rest of structure.rests) {
      const start = Math.max(0, rest.start), end = Math.min(rest.end, structure.span);
      if (!stepByNode.get(rest.node)?.step.rest || !(end > start)) continue;
      const x = scale.time(start);
      rests.push({ key: `${rest.node}:${rest.start}`, node: rest.node, start: rest.start, end: rest.end, x, width: Math.max(scale.px(4), scale.time(end) - x) });
    }
  }
  const notes: GridNote[] = [];
  const seen = new Map<string, number>();
  for (const event of structure.events) {
    const source = stepByNode.get(event.node);
    if (!source || source.step.rest) continue;
    const { step, index } = source;
    const midi = event.pitch ?? (editable ? noteMidi(step.value) : null);
    const end = Math.min(event.end, structure.span);
    const block = noteBlock(scale, event.start, end, scale.y(midi ?? 60));
    const width = scale.time(end) - scale.time(event.start);
    const base = `${event.node}:${event.start}:${midi}`;
    const repeat = seen.get(base) ?? 0;
    seen.set(base, repeat + 1);
    notes.push({
      key: repeat ? `${base}:${repeat}` : base, node: event.node, index, step, start: event.start, end, midi, block,
      label: width / scale.px(1) >= 30 ? (midi === null ? step.value : displayPitch(pitchName(midi))) : null,
      labelX: scale.time((event.start + end) / 2),
      edges: editable ? edgesOf(structure, event, end, block, scale) : [],
    });
  }
  return { notes, rests };
}

function inside(box: Box, x: number, y: number): boolean {
  return x >= box.x && x <= box.x + box.width && y >= box.y && y <= box.y + box.height;
}

export type GridHit =
  | Readonly<{ kind: "edge"; note: GridNote; edge: GridEdge }>
  | Readonly<{ kind: "note"; note: GridNote }>
  | Readonly<{ kind: "rest"; rest: GridRest }>
  | Readonly<{ kind: "empty" }>;

/** What a pointer at viewBox (`x`, `y`) touches: the topmost drawn edge, note, or rest. */
export function hitGrid(layout: GridLayout, x: number, y: number): GridHit {
  for (let index = layout.notes.length - 1; index >= 0; index--) {
    const note = layout.notes[index];
    for (let side = note.edges.length - 1; side >= 0; side--) {
      if (inside(note.edges[side].hit, x, y)) return { kind: "edge", note, edge: note.edges[side] };
    }
    if (inside(note.block, x, y)) return { kind: "note", note };
  }
  for (let index = layout.rests.length - 1; index >= 0; index--) {
    const rest = layout.rests[index];
    if (x >= rest.x && x <= rest.x + rest.width) return { kind: "rest", rest };
  }
  return { kind: "empty" };
}

/** The one source node sounding at `time` nearest `pitch`, or null when two are equally near. */
export function nodeAt(structure: NotationProjection, time: number, pitch: number): number | null {
  const at = Math.min(structure.span - Number.EPSILON * Math.max(1, structure.span), time);
  let best: number | null = null, distance = Infinity;
  for (const event of [...structure.events, ...structure.rests]) {
    if (event.start > at || at >= event.end) continue;
    const next = event.pitch === null ? 128 : Math.abs(event.pitch - pitch);
    if (next < distance) { best = event.node; distance = next; }
    else if (next === distance && best !== event.node) best = null;
  }
  return best;
}

function rect(box: Box): Record<string, string> {
  return { x: String(box.x), y: String(box.y), width: String(box.width), height: String(box.height) };
}

/** Pitch rows, keys, and time lines behind the notes, and the ruler's labels. */
export function bandNodes(scale: PlotScale, span: number, pulse: boolean): { bands: SvgNode[]; ruler: SvgNode[] } {
  const { geometry } = scale;
  const bands: SvgNode[] = [];
  const ruler: SvgNode[] = [];
  for (let midi = geometry.viewHigh; midi >= geometry.viewLow; midi--) {
    const y = scale.y(midi), sharp = [1, 3, 6, 8, 10].includes(midi % 12);
    bands.push(
      { key: `${midi}`, tag: "rect", className: "moving-score__lane", flags: { "is-sharp": sharp },
        attrs: { x: String(geometry.plotLeft), y: String(y - ROW_H / 2), width: String(W - geometry.plotLeft), height: String(ROW_H), "data-pitch": String(midi) } },
      { key: `${midi}`, tag: "rect", className: "moving-score__key", flags: { "is-sharp": sharp },
        attrs: { x: "0", y: String(y - ROW_H / 2), width: String(geometry.plotLeft - scale.px(4)), height: String(ROW_H) } },
      { key: `${midi}`, tag: "text", className: "moving-score__pitch-label", flags: { "is-sharp": sharp, "is-octave": midi % 12 === 0 },
        attrs: { x: String(geometry.plotLeft - scale.px(10)), y: String(y), "dominant-baseline": "central" }, text: displayPitch(pitchName(midi)) },
    );
  }
  const shown = Math.max(1, span);
  const divisions = pulse ? shown * 4 : 4;
  for (let tick = 0; tick <= divisions; tick++) {
    const time = shown * tick / divisions, x = scale.time(time);
    bands.push({ key: `${tick}`, tag: "path", className: "moving-score__time-line", flags: { "is-cycle": Number.isInteger(time) },
      attrs: { d: `M${x} ${TIME_H}V${geometry.plotHeight}` } });
    if (divisions > 8 && tick % 4 !== 0) continue;
    ruler.push({
      key: `${tick}`, tag: "text", className: "moving-score__time-label",
      attrs: { x: String(x), y: "14", "data-time": String(time), "text-anchor": tick === 0 ? "start" : tick === divisions ? "end" : "middle" },
      text: pulse
        ? tick === divisions ? "Next" : `${Math.floor(tick / 4) + 1}.${tick % 4 + 1}`
        : shown === 1 ? ["0", "1/4", "1/2", "3/4", "1"][tick] : String(Number(time.toFixed(2))),
    });
  }
  return { bands, ruler };
}

export type NoteState = Readonly<{
  selected(node: number): boolean;
  /** The source a move drags, drawn faded under its preview. */
  moving: number | null;
  /** The phrase literal's content, which playback highlights match. */
  contentFrom: number;
  contentTo: number;
}>;

export function restNodes(layout: GridLayout, plotHeight: number): SvgNode[] {
  return layout.rests.map(rest => ({
    key: rest.key, tag: "g", className: "moving-score__rest-hit",
    attrs: {
      "data-node": String(rest.node), "data-start": String(rest.start), "data-end": String(rest.end), role: "button", tabindex: "-1",
      "aria-label": `Source rest interval, occurrence at ${rest.start}–${rest.end}; click a pitch row to enter a note`,
    },
    children: [{ key: "area", tag: "rect", className: "moving-score__rest-hit-area",
      attrs: rect({ x: rest.x, y: TIME_H, width: rest.width, height: plotHeight - TIME_H }) }],
  }));
}

export function noteNodes(layout: GridLayout, phrase: GridPhrase, state: NoteState, scale: PlotScale): SvgNode[] {
  return layout.notes.map((note): SvgNode => {
    const { step, midi } = note;
    const selected = state.selected(note.node);
    const tone = phrase.notationKind === "chord" && midi !== null ? `, ${pitchName(midi)}` : "";
    const y = note.block.y + note.block.height / 2;
    return {
      key: note.key, tag: "g", className: "moving-score__note",
      flags: { "is-selected": selected, "is-editing": state.moving === note.node },
      attrs: {
        "data-node": String(note.node), "data-index": String(note.index), "data-start": String(note.start),
        "data-from": String(step.from), "data-to": String(step.to),
        "data-literal-from": String(state.contentFrom), "data-literal-to": String(state.contentTo), "data-pitch": String(midi),
        tabindex: "-1", role: "button", "aria-pressed": String(selected),
        "aria-label": `Select source step ${note.index + 1}, occurrence at ${note.start}, ${step.value}${tone}`,
      },
      children: [
        { key: "title", tag: "title", text: `${midi === null ? step.value : pitchName(midi)} · ${note.start}–${note.end} cycles · source ${step.value}` },
        { key: "block", tag: "rect", className: "moving-score__note-block", attrs: { ...rect(note.block), rx: String(scale.px(2)), ry: "2" } },
        ...(note.label === null ? [] : [{ key: "label", tag: "text", className: "moving-score__note-label",
          attrs: { x: String(note.labelX), y: String(y), "dominant-baseline": "central" }, text: note.label } satisfies SvgNode]),
        ...note.edges.flatMap((edge): SvgNode[] => [
          { key: edge.side, tag: "rect", className: "moving-score__note-edge", attrs: { ...rect(edge.hit), "data-edge": edge.side, "aria-hidden": "true" } },
          { key: edge.side, tag: "path", className: "moving-score__note-edge-mark",
            attrs: { d: `M${edge.markX} ${y - ROW_H / 2 + 6}V${y + ROW_H / 2 - 6}`, "pointer-events": "none" } },
        ]),
      ],
    };
  });
}

/** A note an unfinished edit would draw; context blocks show other notes it moves. */
export type PreviewBlock = Readonly<{ start: number; end: number; midi: number; context: boolean }>;

export function previewNodes(blocks: readonly PreviewBlock[], scale: PlotScale): SvgNode[] {
  return blocks.map((block, index) => ({
    key: String(index), tag: "rect",
    className: block.context ? "moving-score__context-preview" : "moving-score__preview-block",
    attrs: { ...rect(noteBlock(scale, block.start, block.end, scale.y(block.midi))), rx: String(scale.px(2)), ry: "2" },
  }));
}
