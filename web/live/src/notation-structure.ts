import { transposePitch } from "./pitch";
import { project_notation as projectNotationWire } from "./generated/authoring.js";

export type NotationModifier = Readonly<{
  kind: "repeat" | "slow" | "weight" | "degrade" | "euclid";
  from: number;
  to: number;
  value: number;
  args: number[];
}>;

export type NotationNode = Readonly<{
  kind: "atom" | "group" | "sequence" | "parallel";
  from: number;
  baseTo: number;
  end: number;
  value: string;
  parent: number | null;
  children: number[];
  weight: number;
  modifiers: NotationModifier[];
}>;

export type NotationEvent = Readonly<{ node: number; start: number; end: number; pitch: number | null }>;
export type NotationProjection = Readonly<{
  error: string | null;
  roots: number[];
  nodes: NotationNode[];
  events: NotationEvent[];
  rests: NotationEvent[];
  span: number;
}>;
export type SourceChange = Readonly<{ from: number; to: number; insert: string }>;
export type SourceEdit = Readonly<{ changes: SourceChange[]; selection: { from: number; to: number } }>;

/** Resolve a projected hit to a movable sibling in the source atom's sequence. */
export function relocationTarget(projection: NotationProjection, source: number, hit: number): number | null {
  if (projection.error) return null;
  const sourceNode = projection.nodes[source];
  if (!sourceNode || sourceNode.kind !== "atom" || sourceNode.parent === null) return null;
  const parent = projection.nodes[sourceNode.parent];
  if (!parent || parent.kind !== "sequence" || !parent.children.includes(source)) return null;

  let candidate = projection.nodes[hit];
  if (!candidate) return null;
  while (candidate.parent !== sourceNode.parent) {
    if (candidate.parent === null) return null;
    const ancestor = projection.nodes[candidate.parent];
    if (!ancestor) return null;
    candidate = ancestor;
  }
  const target = projection.nodes.indexOf(candidate);
  if (!parent.children.includes(target) || (candidate.kind !== "atom" && candidate.kind !== "group")) return null;
  return target;
}

/** Rotate complete sibling tokens while leaving their source separators untouched. */
export function relocateNode(
  content: string,
  projection: NotationProjection,
  source: number,
  target: number,
  value?: string,
): SourceEdit {
  const sourceNode = nodeAt(projection, source);
  const resolvedTarget = relocationTarget(projection, source, target);
  if (resolvedTarget === null) throw new Error("Move targets must be siblings in the same sequence");
  target = resolvedTarget;
  const targetNode = nodeAt(projection, target);
  if (sourceNode.kind !== "atom" || sourceNode.parent === null) {
    throw new Error("Select an atom in a sequence to move");
  }
  const parent = nodeAt(projection, sourceNode.parent);
  if (parent.kind !== "sequence" || targetNode.parent !== sourceNode.parent ||
      !parent.children.includes(source) || !parent.children.includes(target) ||
      (targetNode.kind !== "atom" && targetNode.kind !== "group")) {
    throw new Error("Move targets must be siblings in the same sequence");
  }

  const core = content.slice(sourceNode.from, sourceNode.baseTo);
  if (value !== undefined && !value.length) throw new Error("Moved atom value cannot be empty");
  if (source === target) {
    if (value === undefined || value === core) return { changes: [], selection: { from: sourceNode.from, to: sourceNode.baseTo } };
    return {
      changes: [{ from: sourceNode.from, to: sourceNode.baseTo, insert: value }],
      selection: { from: sourceNode.from, to: sourceNode.from + value.length },
    };
  }

  const children = parent.children;
  const sourceSlot = children.indexOf(source);
  const targetSlot = children.indexOf(target);
  if (sourceSlot < 0 || targetSlot < 0) throw new Error("Move targets must be siblings in the same sequence");
  const suffix = content.slice(sourceNode.baseTo, sourceNode.end);
  const movedToken = `${value ?? core}${suffix}`;
  const low = Math.min(sourceSlot, targetSlot);
  const high = Math.max(sourceSlot, targetSlot);
  const changes: SourceChange[] = [];
  for (let slot = low; slot <= high; slot++) {
    const destination = nodeAt(projection, children[slot]);
    let token: string;
    if (slot === targetSlot) {
      token = movedToken;
    } else {
      const originSlot = sourceSlot < targetSlot ? slot + 1 : slot - 1;
      const origin = nodeAt(projection, children[originSlot]);
      token = content.slice(origin.from, origin.end);
    }
    if (content.slice(destination.from, destination.end) !== token)
      changes.push({ from: destination.from, to: destination.end, insert: token });
  }
  let targetStart = targetNode.from;
  for (const change of changes) {
    if (change.from < targetNode.from) targetStart += change.insert.length - (change.to - change.from);
  }
  return {
    changes,
    selection: { from: targetStart, to: targetStart + (value === undefined ? core.length : value.length) },
  };
}


const PROJECTION_CACHE_LIMIT = 16;
const projectionCache = new Map<string, NotationProjection>();

/** Cache the bounded compiler projection, including a rest probe when needed. */
export function projectNotation(kind: "note" | "drum" | "chord", content: string): NotationProjection {
  const key = `${kind}\u0000${content}`;
  const cached = projectionCache.get(key);
  if (cached) return cached;
  let projection: NotationProjection;
  try {
    const parsed: unknown = JSON.parse(projectNotationWire(kind, content));
    projection = decodeProjection(parsed);
  } catch (error) {
    projection = invalidProjection(error instanceof Error ? error.message : "Unable to project notation");
  }
  if (projectionCache.size === PROJECTION_CACHE_LIMIT) {
    const oldest = projectionCache.keys().next().value;
    if (oldest !== undefined) projectionCache.delete(oldest);
  }
  projectionCache.set(key, projection);
  return projection;
}

function invalidProjection(error: string): NotationProjection {
  return Object.freeze({ error, roots: [], nodes: [], events: [], rests: [], span: 1 });
}

function decodeProjection(value: unknown): NotationProjection {
  if (!isRecord(value) || (value.error !== null && typeof value.error !== "string") ||
      !Array.isArray(value.roots) || !Array.isArray(value.nodes) ||
      !Array.isArray(value.events) || !Array.isArray(value.rests) ||
      typeof value.span !== "number" || !Number.isFinite(value.span) || value.span < 1) return invalidProjection("Invalid notation projection");
  const wireError = value.error;
  if (typeof wireError === "string") return invalidProjection(wireError);
  const nodes: NotationNode[] = [];
  for (const raw of value.nodes) {
    if (!isRecord(raw) || !["atom", "group", "sequence", "parallel"].includes(String(raw.kind)) ||
        !isInt(raw.from) || !isInt(raw.baseTo) || !isInt(raw.end) ||
        typeof raw.value !== "string" || !(raw.parent === null || isInt(raw.parent)) ||
        !Array.isArray(raw.children) || !raw.children.every(isInt) ||
        typeof raw.weight !== "number" || !Number.isFinite(raw.weight) ||
        !Array.isArray(raw.modifiers)) return invalidProjection("Invalid notation node");
    const modifiers: NotationModifier[] = [];
    for (const mod of raw.modifiers) {
      if (!isRecord(mod) || !["repeat", "slow", "weight", "degrade", "euclid"].includes(String(mod.kind)) ||
          !isInt(mod.from) || !isInt(mod.to) ||
          typeof mod.value !== "number" || !Number.isFinite(mod.value) ||
          !Array.isArray(mod.args) || !mod.args.every(arg => typeof arg === "number" && Number.isFinite(arg))) return invalidProjection("Invalid notation modifier");
      modifiers.push(Object.freeze({ kind: mod.kind as NotationModifier["kind"], from: mod.from, to: mod.to, value: mod.value, args: [...mod.args] }));
    }
    nodes.push(Object.freeze({ kind: raw.kind as NotationNode["kind"], from: raw.from, baseTo: raw.baseTo, end: raw.end,
      value: raw.value, parent: raw.parent, children: [...raw.children], weight: raw.weight, modifiers }));
  }
  const roots = value.roots.filter(isInt);
  if (roots.length !== value.roots.length) return invalidProjection("Invalid notation roots");
  const events = decodeNotationEvents(value.events);
  const rests = decodeNotationEvents(value.rests);
  if (!events || !rests) return invalidProjection("Invalid notation event");
  return Object.freeze({ error: wireError as string | null, roots, nodes, events, rests, span: value.span });
}

function decodeNotationEvents(value: unknown): NotationEvent[] | null {
  if (!Array.isArray(value)) return null;
  const events: NotationEvent[] = [];
  for (const raw of value) {
    if (!isRecord(raw) || !isInt(raw.node) ||
        typeof raw.start !== "number" || !Number.isFinite(raw.start) ||
        typeof raw.end !== "number" || !Number.isFinite(raw.end) ||
        !(raw.pitch === null || (typeof raw.pitch === "number" && Number.isFinite(raw.pitch)))) return null;
    events.push(Object.freeze({ node: raw.node, start: raw.start, end: raw.end, pitch: raw.pitch }));
  }
  return events;
}

function isRecord(value: unknown): value is Record<string, unknown> { return typeof value === "object" && value !== null; }
function isInt(value: unknown): value is number { return Number.isInteger(value) && (value as number) >= 0; }

function nodeAt(projection: NotationProjection, index: number): NotationNode {
  if (projection.error) throw new Error(projection.error);
  const node = projection.nodes[index];
  if (!node) throw new Error("Notation selection is no longer available");
  return node;
}
function requireAtomOrGroup(node: NotationNode): void {
  if (node.kind !== "atom" && node.kind !== "group") throw new Error("Select an atom or group");
}
function weightModifier(node: NotationNode): NotationModifier | undefined {
  const all = node.modifiers.filter(mod => mod.kind === "weight");
  if (all.length > 1) throw new Error("Cannot edit repeated weight modifiers");
  return all[0];
}
function siblingNodes(projection: NotationProjection, node: NotationNode): { parent: NotationNode; index: number; children: NotationNode[] } {
  if (node.parent === null) throw new Error("This notation has no adjacent sibling");
  const parent = nodeAt(projection, node.parent);
  if (parent.kind !== "sequence") throw new Error("Boundary edits require a sequence");
  const children = parent.children.map(child => nodeAt(projection, child));
  const index = parent.children.indexOf(projection.nodes.indexOf(node));
  if (index < 0 || index + 1 >= children.length ||
      (node.kind !== "atom" && node.kind !== "group") ||
      (children[index + 1].kind !== "atom" && children[index + 1].kind !== "group")) {
    throw new Error("Select adjacent atoms or groups in the same sequence");
  }
  return { parent, index, children };
}
function boundedWeight(value: number): void {
  if (!Number.isInteger(value) || value < 1 || value > 16) throw new Error("Weight must be an integer from 1 to 16");
}
function sourceChange(from: number, to: number, insert: string): SourceChange[] {
  return [{ from, to, insert }];
}
function replaceNumeric(mod: NotationModifier, content: string, value: number): SourceChange {
  const text = content.slice(mod.from, mod.to);
  const match = /\d+/.exec(text);
  if (!match) throw new Error("Cannot safely edit this modifier");
  return { from: mod.from + match.index, to: mod.from + match.index + match[0].length, insert: String(value) };
}

export function splitNode(content: string, projection: NotationProjection, index: number): SourceChange[] {
  const node = nodeAt(projection, index);
  if (node.kind === "group") throw new Error("Groups are already subdivided");
  if (node.kind !== "atom") throw new Error("Select an atom to subdivide");
  return sourceChange(node.from, node.baseTo, `[${content.slice(node.from, node.baseTo)} ${content.slice(node.from, node.baseTo)}]`);
}

export function repeatNode(content: string, projection: NotationProjection, index: number, count: number): SourceChange[] {
  if (!Number.isInteger(count) || count < 1 || count > 16) throw new Error("Repeat count must be an integer from 1 to 16");
  const node = nodeAt(projection, index);
  requireAtomOrGroup(node);
  const repeats = node.modifiers.filter(mod => mod.kind === "repeat");
  if (repeats.length > 1) throw new Error("Cannot edit multiple repeat modifiers");
  if (node.modifiers.some(mod => ["euclid", "slow", "degrade"].includes(mod.kind))) {
    throw new Error("Cannot edit repeat when combined with euclid, slow, or degrade");
  }
  if (repeats.length) {
    if (count === 1) return sourceChange(repeats[0].from, repeats[0].to, "");
    return [replaceNumeric(repeats[0], content, count)];
  }
  if (count === 1) return [];
  return sourceChange(node.end, node.end, `*${count}`);
}

export function weightNode(content: string, projection: NotationProjection, index: number, weight: number): SourceChange[] {
  boundedWeight(weight);
  const node = nodeAt(projection, index);
  requireAtomOrGroup(node);
  const mod = weightModifier(node);
  if (node.parent !== null) {
    const parent = nodeAt(projection, node.parent);
    if (parent.kind === "sequence") {
      const sum = parent.children.reduce((total, childIndex) => {
        const child = nodeAt(projection, childIndex);
        return total + (childIndex === index ? weight : child.weight);
      }, 0);
      if (sum > 256) throw new Error("Sibling weights cannot exceed 256");
    }
  }
  if (mod) return weight === 1
    ? sourceChange(mod.from, mod.to, "")
    : [replaceNumeric(mod, content, weight)];
  if (weight === 1) return [];
  return sourceChange(node.end, node.end, `@${weight}`);
}

export function boundaryInfo(projection: NotationProjection, index: number): { right: number; ratio: number } | null {
  if (projection.error) return null;
  const node = projection.nodes[index];
  if (!node || node.kind !== "atom" && node.kind !== "group" || node.parent === null) return null;
  const parent = projection.nodes[node.parent];
  if (!parent || parent.kind !== "sequence") return null;
  const at = parent.children.indexOf(index);
  if (at < 0 || at + 1 >= parent.children.length) return null;
  const right = projection.nodes[parent.children[at + 1]];
  if (!right || (right.kind !== "atom" && right.kind !== "group")) return null;
  try { weightModifier(node); weightModifier(right); }
  catch { return null; }
  const total = node.weight + right.weight;
  if (!(node.weight > 0) || !(right.weight > 0) || !Number.isFinite(total)) return null;
  return { right: parent.children[at + 1], ratio: node.weight / total };
}

export function moveBoundary(content: string, projection: NotationProjection, index: number, ratio: number): SourceChange[] {
  if (!Number.isFinite(ratio) || ratio <= 0 || ratio >= 1) throw new Error("Boundary ratio must be between 0 and 1");
  const selected = nodeAt(projection, index);
  requireAtomOrGroup(selected);
  const { index: at, children } = siblingNodes(projection, selected);
  const modifiers = children.map(weightModifier);
  const original = children.map(child => child.weight);
  for (let i = 0; i < original.length; i++) {
    if (!Number.isFinite(original[i]) || original[i] <= 0 || original[i] > 16) throw new Error("Cannot edit invalid sibling weights");
  }
  const divisor = original.reduce((common, weight) => greatestCommonDivisor(common, weight));
  const baseline = original.map(weight => weight / divisor);
  const pairSum = baseline[at] + baseline[at + 1];
  const currentRatio = baseline[at] / pairSum;
  if (currentRatio === ratio) return [];
  let best: number[] | null = null;
  let bestError = Infinity;
  // Uniform scaling preserves every sibling boundary except the selected one.
  const maxScale = Math.min(...baseline.map(weight => Math.floor(16 / weight)), Math.floor(256 / baseline.reduce((a, b) => a + b, 0)));
  for (let scale = 1; scale <= maxScale; scale++) {
    const total = pairSum * scale;
    for (let left = 1; left < total; left++) {
      const right = total - left;
      if (left > 16 || right > 16) continue;
      const candidate = baseline.map(weight => weight * scale);
      candidate[at] = left;
      candidate[at + 1] = right;
      if (candidate.reduce((a, b) => a + b, 0) > 256) continue;
      const error = Math.abs(left / total - ratio);
      if (error < bestError - Number.EPSILON || (Math.abs(error - bestError) <= Number.EPSILON && (!best || left < best[at]))) {
        best = candidate;
        bestError = error;
      }
    }
  }
  if (!best) throw new Error("No representable boundary fits the weight limits");
  const changes: SourceChange[] = [];
  for (let i = 0; i < children.length; i++) {
    if (best[i] === original[i]) continue;
    const modifier = modifiers[i];
    if (modifier) changes.push(replaceNumeric(modifier, content, best[i]));
    else changes.push({ from: children[i].end, to: children[i].end, insert: `@${best[i]}` });
  }
  return changes.sort((a, b) => a.from - b.from);
}
function greatestCommonDivisor(left: number, right: number): number {
  while (right !== 0) [left, right] = [right, left % right];
  return left;
}

export function layoutNodes(projection: NotationProjection): Array<{ node: number; start: number; end: number; depth: number }> {
  if (projection.error) return [];
  const layout: Array<{ node: number; start: number; end: number; depth: number }> = [];
  const visit = (index: number, start: number, end: number, depth: number): void => {
    const node = projection.nodes[index];
    if (!node) return;
    layout.push({ node: index, start, end, depth });
    if (node.kind === "group") {
      if (node.children.length === 1) visit(node.children[0], start, end, depth + 1);
      return;
    }
    if (node.kind === "parallel") {
      for (const childIndex of node.children) visit(childIndex, start, end, depth);
      return;
    }
    const children = node.children.map(child => projection.nodes[child]).filter((child): child is NotationNode => !!child);
    const total = children.reduce((sum, child) => sum + child.weight, 0);
    if (!(total > 0)) return;
    let cursor = start;
    node.children.forEach(childIndex => {
      const child = projection.nodes[childIndex];
      if (!child) return;
      const childEnd = cursor + (end - start) * child.weight / total;
      visit(childIndex, cursor, childEnd, depth);
      cursor = childEnd;
    });
  };
  for (const root of projection.roots) visit(root, 0, 1, 0);
  return layout;
}

/** Resolve a source interval to complete top-level tokens, without widening partial tokens. */
export function sourceRangeNodes(projection: NotationProjection, from: number, to: number): number[] {
  if (projection.error || !Number.isInteger(from) || !Number.isInteger(to) || from < 0 || to <= from) return [];
  const candidates: number[] = [];
  for (let index = 0; index < projection.nodes.length; index++) {
    const node = projection.nodes[index];
    if ((node.kind !== "atom" && node.kind !== "group") || node.from < from || node.baseTo > to) continue;
    candidates.push(index);
  }
  const maximal = candidates.filter(index => {
    let parent = projection.nodes[index].parent;
    while (parent !== null) {
      if (candidates.includes(parent)) return false;
      parent = projection.nodes[parent]?.parent ?? null;
    }
    return true;
  });
  if (!maximal.length) return [];
  const parent = projection.nodes[maximal[0]].parent;
  if (parent === null) return maximal.length === 1 && projection.roots.includes(maximal[0]) ? maximal : [];
  const sequence = projection.nodes[parent];
  if (!sequence || sequence.kind !== "sequence" && maximal.length > 1) return [];
  const selected = maximal.map(index => sequence.children.indexOf(index));
  if (selected.some(index => index < 0)) return [];
  selected.sort((a, b) => a - b);
  if (selected.some((slot, index) => slot !== selected[0] + index)) return [];
  // Any selected core intersecting the interval must be represented by one of its maximal tokens.
  for (let index = 0; index < projection.nodes.length; index++) {
    const node = projection.nodes[index];
    if ((node.kind !== "atom" && node.kind !== "group") || node.baseTo <= from || node.from >= to) continue;
    if (node.kind === "group" && maximal.every(candidate => isDescendant(projection, candidate, index))) continue;
    if (!maximal.some(candidate => candidate === index || isDescendant(projection, index, candidate))) return [];
  }
  return selected.map(slot => sequence.children[slot]);
}

/** Return the inclusive sibling block between two source nodes. */
export function extendSourceRange(projection: NotationProjection, anchor: number, focus: number): number[] {
  if (projection.error) return [];
  const left = projection.nodes[anchor];
  const right = projection.nodes[focus];
  if (!left || !right || !["atom", "group"].includes(left.kind) || !["atom", "group"].includes(right.kind)) return [];
  if (anchor === focus) return [anchor];
  if (left.parent === null || left.parent !== right.parent) return [];
  const parent = projection.nodes[left.parent];
  if (!parent || parent.kind !== "sequence") return [];
  const a = parent.children.indexOf(anchor);
  const b = parent.children.indexOf(focus);
  if (a < 0 || b < 0) return [];
  return parent.children.slice(Math.min(a, b), Math.max(a, b) + 1);
}

/** Transpose all note atoms in complete selected tokens while preserving authored syntax. */
export function transposeRange(content: string, projection: NotationProjection, nodes: number[], semitones: number): SourceEdit {
  const checked = checkedRange(projection, nodes);
  if (!Number.isInteger(semitones)) throw new Error("Transpose interval must be an integer");
  const from = projection.nodes[checked[0]].from;
  const to = projection.nodes[checked[checked.length - 1]].end;
  if (semitones === 0) return { changes: [], selection: { from, to } };
  const changes: SourceChange[] = [];
  const visit = (index: number): void => {
    const node = nodeAt(projection, index);
    if (node.kind === "atom" && node.value !== "~") {
      const pitch = transposePitch(node.value, semitones);
      if (pitch === null) throw new Error(`Cannot transpose note ${node.value} by ${semitones} semitones`);
      changes.push({ from: node.from, to: node.baseTo, insert: pitch });
    } else {
      for (const child of node.children) visit(child);
    }
  };
  checked.forEach(visit);
  const result = applySourceChanges(content, changes);
  validateCandidate(result);
  return { changes, selection: { from, to: to + changes.reduce((delta, change) => delta + change.insert.length - (change.to - change.from), 0) } };
}

/** Rotate a complete contiguous block through sibling slots, preserving separators. */
export function moveRange(content: string, projection: NotationProjection, nodes: number[], steps: number, semitones = 0): SourceEdit {
  const checked = checkedRange(projection, nodes);
  if (!Number.isInteger(steps) || !Number.isInteger(semitones)) throw new Error("Move and transpose amounts must be integers");
  if (steps === 0) return transposeRange(content, projection, nodes, semitones);
  const parentIndex = projection.nodes[checked[0]].parent;
  if (parentIndex === null || checked.some(index => projection.nodes[index].parent !== parentIndex)) throw new Error("Selected range must be siblings in one sequence");
  const parent = nodeAt(projection, parentIndex);
  if (parent.kind !== "sequence") throw new Error("Selected range must be siblings in one sequence");
  const slots = checked.map(index => parent.children.indexOf(index));
  const start = slots[0], end = slots[slots.length - 1];
  if (slots.some((slot, i) => slot !== start + i)) throw new Error("Selected nodes must be contiguous siblings");
  const destination = start + steps;
  if (destination < 0 || destination + checked.length > parent.children.length) throw new Error("Move is outside the sibling sequence");
  const low = Math.min(start, destination), high = Math.max(end, destination + checked.length - 1);
  const tokens = parent.children.map(index => {
    const node = nodeAt(projection, index);
    return content.slice(node.from, node.end);
  });
  const moved = tokens.splice(start, checked.length);
  tokens.splice(destination, 0, ...moved);
  const changes: SourceChange[] = [];
  for (let slot = low; slot <= high; slot++) {
    const node = nodeAt(projection, parent.children[slot]);
    let token = tokens[slot];
    if (slot >= destination && slot < destination + checked.length && semitones !== 0) {
      const originalIndex = checked[slot - destination];
      token = transposeToken(content, projection, originalIndex, semitones);
    }
    if (content.slice(node.from, node.end) !== token) changes.push({ from: node.from, to: node.end, insert: token });
  }
  const result = applySourceChanges(content, changes);
  validateCandidate(result);
  const first = nodeAt(projection, parent.children[destination]);
  let selectionFrom = first.from;
  for (const change of changes) if (change.from < first.from) selectionFrom += change.insert.length - (change.to - change.from);
  const selectionEndNode = nodeAt(projection, parent.children[destination + checked.length - 1]);
  const selectionLength = selectionEndNode.end - first.from + changes
    .filter(change => change.from >= first.from && change.from < selectionEndNode.end)
    .reduce((delta, change) => delta + change.insert.length - (change.to - change.from), 0);
  return { changes, selection: { from: selectionFrom, to: selectionFrom + selectionLength } };
}

/** Insert a literal independent copy after the selected token block. */
export function duplicateRange(content: string, projection: NotationProjection, nodes: number[]): SourceEdit {
  const checked = checkedRange(projection, nodes);
  const first = checked[0], last = checked[checked.length - 1];
  const source = content.slice(projection.nodes[first].from, projection.nodes[last].end);
  const insertAt = projection.nodes[last].end;
  const separator = " ";
  const insert = separator + source;
  const changes = [{ from: insertAt, to: insertAt, insert }];
  validateCandidate(applySourceChanges(content, changes));
  const selectionFrom = insertAt + separator.length;
  return { changes, selection: { from: selectionFrom, to: selectionFrom + source.length } };
}

function checkedRange(projection: NotationProjection, nodes: number[]): number[] {
  if (projection.error || !nodes.length) throw new Error("Select a complete source range");
  const unique = [...nodes];
  if (new Set(unique).size !== unique.length) throw new Error("Selected range contains duplicate nodes");
  const first = nodeAt(projection, unique[0]);
  requireAtomOrGroup(first);
  if (unique.some(index => {
    const node = projection.nodes[index];
    return !node || (node.kind !== "atom" && node.kind !== "group") || node.parent !== first.parent;
  })) throw new Error("Selected range must share a parent");
  if (unique.length === 1 && first.parent !== null) return unique;
  if (first.parent !== null) {
    const parent = nodeAt(projection, first.parent);
    if (parent.kind !== "sequence") throw new Error("Selected range must belong to a sequence");
    const slots = unique.map(index => parent.children.indexOf(index));
    if (slots.some((slot, i) => slot < 0 || (i > 0 && slot !== slots[i - 1] + 1))) throw new Error("Selected range must be contiguous");
  } else if (unique.length !== 1 || !projection.roots.includes(unique[0])) {
    throw new Error("Standalone selection must be one root token");
  }
  return unique;
}

function isDescendant(projection: NotationProjection, index: number, ancestor: number): boolean {
  let parent = projection.nodes[index]?.parent ?? null;
  while (parent !== null) {
    if (parent === ancestor) return true;
    parent = projection.nodes[parent]?.parent ?? null;
  }
  return false;
}

function transposeToken(content: string, projection: NotationProjection, index: number, semitones: number): string {
  const node = nodeAt(projection, index);
  const from = node.from;
  const to = node.end;
  const changes: SourceChange[] = [];
  const visit = (childIndex: number): void => {
    const child = nodeAt(projection, childIndex);
    if (child.kind === "atom" && child.value !== "~") {
      const pitch = transposePitch(child.value, semitones);
      if (pitch === null) throw new Error(`Cannot transpose note ${child.value} by ${semitones} semitones`);
      changes.push({ from: child.from, to: child.baseTo, insert: pitch });
    } else child.children.forEach(visit);
  };
  visit(index);
  return applySourceChanges(content.slice(from, to), changes.map(change => ({ ...change, from: change.from - from, to: change.to - from })));
}

function applySourceChanges(content: string, changes: SourceChange[]): string {
  return [...changes].sort((a, b) => b.from - a.from).reduce(
    (source, change) => source.slice(0, change.from) + change.insert + source.slice(change.to), content,
  );
}

function validateCandidate(content: string): void {
  const candidate = projectNotation("note", content);
  if (candidate.error) throw new Error(`Edited notation is invalid: ${candidate.error}`);
}
export function leafNodes(projection: NotationProjection): number[] {
  if (projection.error) return [];
  return projection.nodes.flatMap((node, index) => node.kind === "atom" ? [index] : []).sort((a, b) => projection.nodes[a].from - projection.nodes[b].from);
}
