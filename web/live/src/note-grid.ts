import type { EditorView } from "@codemirror/view";
import type { Pattern, Step } from "./pattern-controls";
import { BOUNDARY_STEP, applySourceChanges, boundaryInfo, boundaryRatio, clampBoundary, duplicateRange, extendSourceRange, keepingSelection,
  mapPosition, moveBoundary, moveRange, projectNotation, relocateNode, sourceRangeNodes, transposeRange,
  type Edit, type NotationEvent, type NotationProjection, type SourceEdit } from "./notation-structure";
import { EMPTY_GRID, bandNodes, gridLayout, hitGrid, isPhraseRange, moveTargets, nearestNode, nodeAt, noteMidi, noteNodes, pitchName,
  previewNodes, rangeSibling, restNodes, soundingNodes, strokePitches,
  type GridLayout, type PreviewBlock } from "./note-grid-layout";
import { dispatchPatternEdit } from "./pattern-edit";
import { PLOT_LEFT_PX, ROW_H, TIME_H, W, boundedPitch, isDrag, midiAtY, plotPoint, plotScale, revealScrollTop, scoreGeometry, viewBoxPoint,
  type PlotScale } from "./score-geometry";
import type { SourceElements } from "./source-elements";
import { patchSvg } from "./svg-patch";
import type { InteractionLock } from "./moving-score";

const MOVE_REFUSED = "This note cannot move to that source step.";
const EDGE_REFUSED = "This note boundary has no representable adjacent weight.";

/** A phrase whose every step can be drawn. */
export type EditablePhrase = Pattern & { steps: Step[]; structure: NotationProjection };
type Point = { x: number; y: number };

// `origin` is the client position a drag starts from; it moves nothing until it leaves a 4 px radius.
type DrawGesture = { to: number; lastPitch: number; lastTime: number; pitches: Map<number, number>; dirty: boolean };
type RestGesture = { to: number; occurrence: NotationEvent; midi: number };
type MoveGesture = { pointer: number; origin: Point; source: number; target: number; pitch: number; initialPitch: number; dirty: boolean; range: number[] };
type EdgeGesture = { pointer: number; node: number; leftNode: number; rightNode: number; pairStart: number; pairEnd: number; ratio: number; previewKey?: string };
type SelectionGesture = { pointer: number; anchor: number; focus: number; nodes: number[] };
// Pointer interactions hold a captured pointer; keyboard interactions preview
// an edit until Enter or Escape. The widget is rebuilt or updated on every
// document change, which cancels any interaction, so an interaction always
// applies to the document it began on.
type Interaction =
  | (DrawGesture & { kind: "draw"; pointer: number; origin: Point })
  | (DrawGesture & { kind: "keyboard-draw" })
  | (RestGesture & { kind: "rest"; pointer: number })
  | (RestGesture & { kind: "keyboard-rest" })
  | (MoveGesture & { kind: "move" })
  | (EdgeGesture & { kind: "edge" })
  | (SelectionGesture & { kind: "selection" });
type InteractionOf<K extends Interaction["kind"]> = Extract<Interaction, { kind: K }>;
// Grabbing a note, edge, or rest, or dragging a selection, locks touch
// scrolling. Elsewhere a vertical swipe still scrolls the pitch rows.
const SCROLL_LOCKING: ReadonlySet<Interaction["kind"]> = new Set(["move", "edge", "rest", "selection"]);
const NS = "http://www.w3.org/2000/svg";

function svgGroup(className: string, hidden = false): SVGGElement {
  const group = document.createElementNS(NS, "g");
  group.setAttribute("class", className);
  if (hidden) group.setAttribute("aria-hidden", "true");
  return group;
}

/**
 * Mount the note grid. Notes can be drawn, dragged, resized, and entered into
 * rests; chord tones are shown and select their chord.
 */
export function mountNoteGrid(
  before: Element,
  view: EditorView,
  notationKind: "note" | "chord",
  tools: HTMLElement,
  controls: Readonly<{
    select(index: number): void;
    selectNode(node: number): void;
    /** Select a source node, step or group. */
    selectSource(node: number): void;
    clear(): void;
    setMessage(text: string): void;
    /** The node the grid shows as selected, after each render. */
    shown(node: number | null): void;
    lock: InteractionLock;
    tonesOpen: boolean;
    tonesChanged(open: boolean): void;
    /** Where the note blocks are shown as they are drawn. */
    sources: SourceElements;
  }>,
): {
  update(phrase: EditablePhrase | null, docChanged: boolean): void;
  render(width: number): void;
  stageHeight(): number;
  /** The selected step, or -1 when a group is selected. */
  selectedStep(): number;
  interaction(): Interaction["kind"] | null;
  cancel(): void;
  /** Leave selection mode; false when it was not on. */
  stopSelecting(): boolean;
  keydown(event: KeyboardEvent): void;
  dispose(): void;
} {
  const editable = notationKind === "note";
  const heading = document.createElement("div");
  heading.className = "moving-score__heading";
  const eventLabel = document.createElement("div");
  eventLabel.className = "moving-score__event-label";
  eventLabel.textContent = "Notation events";
  const rulerLabel = document.createElement("label");
  rulerLabel.className = "moving-score__time-view";
  const rulerSelect = document.createElement("select");
  rulerSelect.setAttribute("aria-label", "Notation ruler");
  for (const [value, text] of [["cycle", "Cycle"], ["pulse", "4 divisions"]]) rulerSelect.add(new Option(text, value));
  rulerLabel.append("Ruler ", rulerSelect);
  heading.append(eventLabel, rulerLabel);
  const ruler = document.createElementNS(NS, "svg");
  ruler.setAttribute("class", "moving-score__ruler");
  ruler.setAttribute("viewBox", `0 0 ${W} ${TIME_H}`);
  ruler.setAttribute("preserveAspectRatio", "none");
  ruler.setAttribute("aria-hidden", "true");
  const stage = document.createElement("div");
  stage.className = "moving-score__stage";
  const svg = document.createElementNS(NS, "svg");
  svg.setAttribute("class", "moving-score__canvas");
  svg.setAttribute("preserveAspectRatio", "none");
  svg.setAttribute("role", "application");
  svg.setAttribute("tabindex", "0");
  svg.setAttribute("aria-label", editable
    ? "Note grid. Drag notes to change pitch and source order; drag an edge to resize. Click an empty source interval to enter a note. Arrows select steps and change pitch; Alt with Left or Right moves a step, Shift with Left or Right resizes its end, and Delete clears it. Enter previews editing; Escape cancels and returns to code."
    : "Chord tone preview. Left and Right select whole chords. Edit root and type above; individual tones cannot be dragged.");
  const bands = svgGroup("moving-score__bands", true);
  const restMarks = svgGroup("moving-score__rests");
  const notes = svgGroup("moving-score__notes");
  const shownNotes = controls.sources.slot();
  const preview = svgGroup("moving-score__preview", true);
  svg.append(bands, restMarks, notes, preview);
  stage.append(svg);
  let tones: HTMLDetailsElement | null = null;
  if (editable) before.before(heading, ruler, stage);
  else {
    tones = document.createElement("details");
    tones.className = "moving-score__tone-details";
    tones.open = controls.tonesOpen;
    const summary = document.createElement("summary");
    summary.textContent = "View chord tones";
    const hint = document.createElement("p");
    hint.className = "moving-score__tone-hint";
    hint.textContent = "Tone preview — edit the whole chord above, not individual notes.";
    tones.append(summary, hint, heading, ruler, stage);
    tones.addEventListener("toggle", () => controls.tonesChanged(tones!.open));
    before.before(tones);
  }
  const selectButton = document.createElement("button");
  selectButton.type = "button";
  selectButton.className = "moving-score__select";
  selectButton.setAttribute("aria-pressed", "false");
  selectButton.title = "Select a source range by dragging, or extend it with Left/Right";
  selectButton.textContent = "Select";
  const duplicateButton = document.createElement("button");
  duplicateButton.type = "button";
  duplicateButton.className = "moving-score__duplicate";
  duplicateButton.title = "Make an independent copy of the selected source; Repeat keeps occurrences linked";
  duplicateButton.textContent = "Duplicate";
  if (editable) tools.append(selectButton, duplicateButton);

  let active: EditablePhrase | null = null;
  let width = 0;
  let scale: PlotScale = plotScale(scoreGeometry(0, []), 1);
  let layout: GridLayout = EMPTY_GRID;
  let previewBlocks: readonly PreviewBlock[] = [];
  let visibleSelection = "";
  let interaction: Interaction | null = null;
  let selecting = false;
  let selectionAnchor: number | null = null;
  let selectionFocus: number | null = null;
  const { setMessage } = controls;

  function ongoing<K extends Interaction["kind"]>(kind: K): InteractionOf<K> | null {
    return interaction?.kind === kind ? interaction as InteractionOf<K> : null;
  }
  function begin(next: Interaction): void {
    interaction = next;
    controls.lock.holder = "grid";
  }
  /** The pitch a rest entry is choosing, by pointer or keyboard. */
  function restMidi(): number | undefined {
    return interaction?.kind === "rest" || interaction?.kind === "keyboard-rest" ? interaction.midi : undefined;
  }
  function stepFor(node: number): number { return active?.steps.findIndex(step => step.node === node) ?? -1; }
  /** The selected source node: the editor's selection, or the step a keyboard drawing is on. */
  function sourceNode(): number | null {
    const drawing = ongoing("keyboard-draw");
    return drawing && active ? active.steps[drawing.to].node : active?.selectedNode ?? null;
  }
  function selectedStep(): number {
    const node = sourceNode();
    return node === null ? -1 : stepFor(node);
  }
  function selectedSources(): number[] {
    if (!active) return [];
    const selection = ongoing("selection");
    if (selection) return selection.nodes;
    if (active.selectionTo > active.selectionFrom) {
      return sourceRangeNodes(active.structure, active.selectionFrom - active.contentFrom, active.selectionTo - active.contentFrom);
    }
    const node = sourceNode();
    return node === null ? [] : [node];
  }
  function selectRange(nodes: number[]): void {
    if (!active || !nodes.length) return;
    const from = active.structure.nodes[nodes[0]].from + active.contentFrom;
    const to = active.structure.nodes[nodes.at(-1)!].end + active.contentFrom;
    view.dispatch({ selection: { anchor: from, head: to } });
  }

  function sourceIsSelected(node: number): boolean {
    const selected = selectedSources();
    for (let current: number | null = node; current !== null; current = active?.structure.nodes[current]?.parent ?? null) {
      if (selected.includes(current)) return true;
    }
    return false;
  }
  function content(phrase: EditablePhrase): string { return view.state.doc.sliceString(phrase.contentFrom, phrase.contentTo); }
  function dispatchSourceEdit(edit: SourceEdit): void {
    if (active) dispatchPatternEdit(view, edit, active.contentFrom);
  }
  /** Applies `edit`, or shows `refused` (or the edit's own reason) when the notation cannot take it. */
  function applyEdit(edit: Edit<SourceEdit>, refused?: string): boolean {
    if (!edit.ok) { setMessage(refused ?? edit.reason); return false; }
    dispatchSourceEdit(edit.value);
    setMessage("");
    return true;
  }
  function boundaryEdit(phrase: EditablePhrase, leftNode: number, ratio: number, selected: number): Edit<SourceEdit> {
    const changes = moveBoundary(content(phrase), phrase.structure, leftNode, ratio);
    return changes.ok ? { ok: true, value: keepingSelection(phrase.structure, selected, changes.value) } : changes;
  }
  function renderTimeLabel(phrase: EditablePhrase): void {
    const label = editable ? "Notes" : "Chord tones";
    const span = phrase.structure.span;
    eventLabel.textContent = `${label} · ${span} local ${span === 1 ? "cycle" : "cycles"}`;
    eventLabel.title = "Notation time, before outer speed, gate, envelope, or song placement. Four divisions are not a time-signature claim.";
  }
  function showPreview(blocks: readonly PreviewBlock[]): void {
    previewBlocks = blocks;
    patchSvg(preview, previewNodes(blocks, scale));
  }
  function render(): void {
    const phrase = active;
    const pitches = phrase ? [
      ...phrase.steps.flatMap(step => {
        const midi = step.rest || !editable ? null : noteMidi(step.value);
        return midi === null ? [] : [midi];
      }),
      ...phrase.structure.events.flatMap(event => event.pitch === null ? [] : [event.pitch]),
      ...(ongoing("keyboard-draw")?.pitches.values() ?? []),
      ...(restMidi() === undefined ? [] : [restMidi()!]),
    ] : [];
    const geometry = scoreGeometry(width, pitches);
    scale = plotScale(geometry, phrase?.structure.span ?? 1);
    svg.setAttribute("viewBox", `0 ${TIME_H} ${W} ${geometry.plotHeight - TIME_H}`);
    svg.style.height = `${geometry.plotHeight - TIME_H}px`;
    svg.style.setProperty("--text-aspect", String(scale.px(1)));
    ruler.style.setProperty("--text-aspect", String(scale.px(1)));
    const background = bandNodes(scale, phrase?.structure.span ?? 1, rulerSelect.value === "pulse");
    patchSvg(bands, background.bands);
    patchSvg(ruler, background.ruler);
    heading.hidden = stage.hidden = !phrase;
    ruler.toggleAttribute("hidden", !phrase);
    selectButton.hidden = duplicateButton.hidden = !phrase;
    duplicateButton.disabled = selectedSources().length === 0;
    if (!phrase) {
      layout = EMPTY_GRID;
      patchSvg(restMarks, []); patchSvg(notes, []); showPreview([]);
      shownNotes.show([]);
      controls.shown(null);
      return;
    }
    renderTimeLabel(phrase);
    const drawn = { steps: phrase.steps, structure: phrase.structure, notationKind };
    layout = gridLayout(drawn, scale);
    patchSvg(restMarks, restNodes(layout, geometry.plotHeight));
    const noteElements = patchSvg(notes, noteNodes(layout, drawn, {
      selected: sourceIsSelected, moving: ongoing("move")?.source ?? null,
    }, scale));
    shownNotes.show(layout.notes.map((note, index) => ({
      element: noteElements[index], from: note.step.from, to: note.step.to, hint: true,
      note: { literalFrom: phrase.contentFrom, literalTo: phrase.contentTo, start: note.start, pitch: note.midi },
    })));
    // Only source selection can scroll the grid, never playback highlighting.
    const keyboardDraw = ongoing("keyboard-draw");
    const selectedPitch = restMidi() ??
      keyboardDraw?.pitches.get(phrase.steps[keyboardDraw.to].node) ??
      phrase.structure.events.find(event => sourceIsSelected(event.node) && event.pitch !== null)?.pitch;
    const selectionKey = `${sourceNode()}:${selectedPitch}:${geometry.viewLow}:${geometry.viewHigh}`;
    const stageHeight = stage.clientHeight;
    if (stageHeight && selectionKey !== visibleSelection) {
      if (selectedPitch !== null && selectedPitch !== undefined) {
        const top = revealScrollTop(scale.y(selectedPitch) - TIME_H, ROW_H, stage.scrollTop, stageHeight);
        if (top !== null) stage.scrollTop = top;
      }
      visibleSelection = selectionKey;
    }
    showPreview(interaction && interaction.kind !== "selection" ? previewBlocks : []);
    controls.shown(sourceNode());
  }
  function pointerOffset(event: PointerEvent): { offsetX: number; offsetY: number; rect: DOMRect } {
    const rect = svg.getBoundingClientRect();
    return { offsetX: event.clientX - rect.left, offsetY: event.clientY - rect.top, rect };
  }
  function canvasPoint(event: PointerEvent): Point {
    const { offsetX, offsetY, rect } = pointerOffset(event);
    return plotPoint(scale.geometry, offsetX, offsetY, rect.width, rect.height);
  }
  function drawPreview(phrase: EditablePhrase, drawing: Pick<DrawGesture, "pitches">): void {
    showPreview(phrase.structure.events.flatMap(event => {
      const midi = drawing.pitches.get(event.node);
      return midi === undefined || phrase.steps[stepFor(event.node)]?.rest ? []
        : [{ start: event.start, end: Math.min(event.end, phrase.structure.span), midi, context: false }];
    }));
  }
  function restPreview(phrase: EditablePhrase, drawing: RestGesture): void {
    showPreview([{ start: drawing.occurrence.start, end: Math.min(drawing.occurrence.end, phrase.structure.span), midi: drawing.midi, context: false }]);
  }
  /** The blocks an edit's result draws: the edited notes, and others only where they change. */
  function projectionPreview(phrase: EditablePhrase, projection: NotationProjection, selected: (node: number) => boolean): void {
    showPreview(projection.events.flatMap(event => {
      const midi = event.pitch ?? noteMidi(projection.nodes[event.node]?.value ?? "");
      if (midi === null) return [];
      const isSelected = selected(event.node);
      const unchanged = phrase.structure.events.some(old => old.pitch === event.pitch && old.start === event.start && old.end === event.end);
      return isSelected || !unchanged ? [{ start: event.start, end: Math.min(event.end, projection.span), midi, context: !isSelected }] : [];
    }));
  }
  function noteMoveEdit(phrase: EditablePhrase, drawing: MoveGesture): Edit<SourceEdit> {
    const source = content(phrase);
    if (isPhraseRange(phrase.structure, drawing.range)) {
      const parent = phrase.structure.nodes[drawing.range[0]].parent;
      const siblings = parent === null ? [] : phrase.structure.nodes[parent].children;
      const steps = siblings.indexOf(drawing.target) - siblings.indexOf(drawing.source);
      return moveRange(source, phrase.structure, drawing.range, steps, drawing.pitch - drawing.initialPitch);
    }
    const value = drawing.pitch === drawing.initialPitch ? undefined : pitchName(drawing.pitch);
    return relocateNode(source, phrase.structure, drawing.source, drawing.target, value);
  }
  function previewMove(phrase: EditablePhrase, drawing: MoveGesture): void {
    showPreview([]);
    const edit = noteMoveEdit(phrase, drawing);
    if (!edit.ok) { setMessage(MOVE_REFUSED); return; }
    const { changes, selection } = edit.value;
    const projection = projectNotation("note", applySourceChanges(content(phrase), changes));
    if (projection.error) return;
    projectionPreview(phrase, projection, index => {
      const node = projection.nodes[index];
      return node.from >= selection.from && node.baseTo <= selection.to;
    });
  }
  /** Previews an edge drag, redrawing only when the edited text changes. */
  function previewEdge(phrase: EditablePhrase, drawing: EdgeGesture): void {
    const source = content(phrase);
    const changes = moveBoundary(source, phrase.structure, drawing.leftNode, drawing.ratio);
    if (!changes.ok) {
      drawing.previewKey = undefined;
      showPreview([]);
      setMessage(EDGE_REFUSED);
      return;
    }
    const next = applySourceChanges(source, changes.value);
    if (next === drawing.previewKey) return;
    drawing.previewKey = next;
    showPreview([]);
    const projection = projectNotation("note", next);
    if (projection.error) return;
    projectionPreview(phrase, projection, node => node === drawing.leftNode || node === drawing.rightNode);
  }
  function commitMove(phrase: EditablePhrase, drawing: MoveGesture): void {
    if (drawing.dirty) applyEdit(noteMoveEdit(phrase, drawing), MOVE_REFUSED);
  }
  function commitEdge(phrase: EditablePhrase, drawing: EdgeGesture): void {
    const edit = boundaryEdit(phrase, drawing.leftNode, drawing.ratio, drawing.node);
    // An edge released where it started changes nothing, not even the selection.
    if (edit.ok && !edit.value.changes.length) setMessage("");
    else applyEdit(edit, EDGE_REFUSED);
  }
  function commitRest(phrase: EditablePhrase, drawing: RestGesture): void {
    const step = phrase.steps[drawing.to];
    dispatchPatternEdit(view, { changes: [{ from: step.from, to: step.to, insert: pitchName(drawing.midi) }], selection: { from: step.from, to: step.from } });
    setMessage("");
  }
  function commitDraw(phrase: EditablePhrase, drawing: DrawGesture): void {
    setMessage("");
    const changes: { from: number; to: number; insert: string }[] = [];
    for (const [node, midi] of drawing.pitches) {
      const step = phrase.steps.find(item => item.node === node);
      if (step && !step.rest) {
        const replacement = pitchName(midi);
        if (step.value !== replacement) changes.push({ from: step.from, to: step.to, insert: replacement });
      }
    }
    if (!drawing.dirty || !changes.length) return;
    changes.sort((left, right) => left.from - right.from);
    const cursor = mapPosition(changes, phrase.steps[drawing.to].from, -1);
    dispatchPatternEdit(view, { changes, selection: { from: cursor, to: cursor } });
  }
  function beginPointer(event: PointerEvent): void {
    const phrase = active;
    if (controls.lock.holder || !phrase || event.button !== 0) return;
    const { offsetX, offsetY, rect } = pointerOffset(event);
    // The pitch-label column edits nothing.
    if (offsetX < PLOT_LEFT_PX) return;
    const p = canvasPoint(event);
    const capture = (next: Interaction): void => {
      begin(next);
      svg.setPointerCapture(event.pointerId);
      event.preventDefault();
    };
    if (selecting && editable) {
      const node = nodeAt(phrase.structure, scale.timeAt(p.x), midiAtY(scale.geometry, p.y));
      if (node === null) return;
      selectionAnchor = node;
      capture({ kind: "selection", pointer: event.pointerId, anchor: node, focus: node, nodes: [node] });
      render(); svg.focus({ preventScroll: true });
      return;
    }
    const at = viewBoxPoint(scale.geometry, offsetX, offsetY, rect.width, rect.height);
    const hit = hitGrid(layout, at.x, at.y);
    if (hit.kind === "edge") {
      const { edge, note } = hit;
      capture({
        kind: "edge", pointer: event.pointerId, node: note.node, leftNode: edge.leftNode, rightNode: edge.rightNode,
        pairStart: edge.pairStart, pairEnd: edge.pairEnd, ratio: edge.ratio,
      });
      controls.selectSource(note.node); svg.focus({ preventScroll: true });
      return;
    }
    const time = scale.timeAt(p.x);
    if (hit.kind === "rest") {
      const node = hit.rest.node;
      const overlapping = phrase.structure.rests.filter(item => item.start <= time && time < item.end);
      if (new Set(overlapping.map(item => item.node)).size > 1) { setMessage("Select this rest in the source steps to add a note."); return; }
      const occurrence = overlapping.find(item => item.node === node && item.start === hit.rest.start) ?? overlapping.find(item => item.node === node);
      const index = stepFor(node);
      if (!occurrence || index < 0 || !phrase.steps[index].rest) return;
      controls.selectSource(node);
      svg.focus({ preventScroll: true });
      const rest: InteractionOf<"rest"> = { kind: "rest", pointer: event.pointerId, to: index, occurrence, midi: midiAtY(scale.geometry, p.y) };
      capture(rest);
      restPreview(phrase, rest);
      return;
    }
    const note = hit.kind === "note" ? hit.note : null;
    let node: number;
    if (note) node = note.node;
    else {
      // Over no note, the one source sounding at that time is drawn into.
      const sounding = soundingNodes(phrase.structure.events, phrase.structure.span, time);
      if (sounding.size !== 1) return;
      node = sounding.values().next().value!;
    }
    const index = stepFor(node);
    if (index < 0) return;
    const previousRange = selectedSources();
    const keepRange = !!note && !event.shiftKey && sourceIsSelected(node) && isPhraseRange(phrase.structure, previousRange);
    if (!keepRange) controls.selectSource(node);
    if (!editable) { event.preventDefault(); return; }
    const origin = { x: event.clientX, y: event.clientY };
    svg.focus({ preventScroll: true });
    if (note && !event.shiftKey) {
      if (note.midi === null) return;
      const moved = keepRange ? rangeSibling(phrase.structure, node, previousRange) ?? node : node;
      capture({
        kind: "move", pointer: event.pointerId, origin, source: moved, target: moved,
        pitch: note.midi, initialPitch: note.midi, dirty: false, range: keepRange ? previousRange : [node],
      });
      render();
    } else {
      const pitch = midiAtY(scale.geometry, p.y);
      capture({ kind: "draw", pointer: event.pointerId, origin, to: index, lastPitch: pitch, lastTime: time, pitches: new Map([[node, pitch]]), dirty: false });
    }
  }
  function movePointer(event: PointerEvent): void {
    const current = interaction;
    if (!current || !("pointer" in current) || current.pointer !== event.pointerId || !active) return;
    switch (current.kind) {
      case "selection": {
        const p = canvasPoint(event);
        const node = nodeAt(active.structure, scale.timeAt(p.x), midiAtY(scale.geometry, p.y));
        if (node !== null) {
          const range = extendSourceRange(active.structure, current.anchor, node);
          if (range.length) { current.nodes = range; current.focus = node; render(); }
        }
        return;
      }
      case "edge": {
        const time = scale.timeAt(canvasPoint(event).x);
        current.ratio = boundaryRatio(time, current.pairStart, current.pairEnd);
        previewEdge(active, current);
        return;
      }
      case "move": return moveNote(active, current, event);
      case "rest":
        current.midi = midiAtY(scale.geometry, canvasPoint(event).y);
        restPreview(active, current);
        return;
      case "draw": return drawContour(active, current, event);
    }
  }
  function moveNote(phrase: EditablePhrase, move: InteractionOf<"move">, event: PointerEvent): void {
    if (!move.dirty && !isDrag(event.clientX - move.origin.x, event.clientY - move.origin.y)) return;
    const point = canvasPoint(event), time = scale.timeAt(point.x);
    let nextTarget = move.source, nextPitch = midiAtY(scale.geometry, point.y);
    if (isDrag(event.clientX - move.origin.x, 0)) {
      const targets = moveTargets(phrase.structure, move.source, move.range, time);
      if (targets.size === 1) {
        nextTarget = targets.values().next().value!;
        setMessage("");
      } else {
        nextPitch = move.initialPitch;
        setMessage(targets.size ? "Choose an unambiguous source step to move this note."
          : "This note can only move within its own source sequence.");
      }
    } else setMessage("");
    if (nextTarget !== move.target || nextPitch !== move.pitch) {
      move.target = nextTarget;
      move.pitch = nextPitch;
      move.dirty = nextTarget !== move.source || nextPitch !== move.initialPitch;
      if (move.dirty) previewMove(phrase, move);
      else showPreview([]);
    }
  }
  function drawContour(phrase: EditablePhrase, draw: InteractionOf<"draw">, event: PointerEvent): void {
    if (!draw.dirty && !isDrag(event.clientX - draw.origin.x, event.clientY - draw.origin.y)) return;
    const p = canvasPoint(event);
    const { geometry } = scale;
    const { span, events } = phrase.structure;
    const time = Math.max(0, Math.min(span, scale.timeAt(p.x)));
    const nextMidi = midiAtY(geometry, p.y);
    // Pointer coordinates may round to device pixels while SVG centers do not.
    const tolerance = span / Math.max(1, svg.clientWidth);
    const stroke = strokePitches(events, span, phrase.steps[draw.to].node,
      { time: draw.lastTime, pitch: draw.lastPitch }, { time, pitch: nextMidi }, tolerance, geometry.viewLow, geometry.viewHigh);
    for (const [node, pitch] of stroke) draw.pitches.set(node, pitch);
    const nearest = nearestNode(events, span, time, node => stepFor(node) >= 0);
    if (nearest !== null) draw.to = stepFor(nearest);
    draw.lastPitch = nextMidi;
    draw.lastTime = time;
    draw.dirty = true;
    drawPreview(phrase, draw);
  }
  function commitInteraction(phrase: EditablePhrase, current: Interaction): void {
    switch (current.kind) {
      case "edge": return commitEdge(phrase, current);
      case "move": return commitMove(phrase, current);
      case "selection": selectionFocus = current.focus; selectRange(current.nodes); return;
      case "draw": case "keyboard-draw": return commitDraw(phrase, current);
      case "rest": case "keyboard-rest": return commitRest(phrase, current);
    }
  }
  /** Ends the running interaction, applying its edit when `commit` is set. */
  function finish(commit: boolean): void {
    const current = interaction;
    if (!current) return;
    interaction = null;
    controls.lock.holder = null;
    previewBlocks = [];
    if ("pointer" in current && svg.hasPointerCapture(current.pointer)) svg.releasePointerCapture(current.pointer);
    if (commit && active) commitInteraction(active, current);
    render();
  }
  function endPointer(event: PointerEvent): void {
    if (interaction && "pointer" in interaction && interaction.pointer === event.pointerId) finish(event.type === "pointerup");
  }
  function cancel(): void {
    if (!interaction) return;
    finish(false);
    setMessage("");
  }
  /** Keys on the canvas itself. */
  function keydown(event: KeyboardEvent): void {
    const phrase = active;
    if (event.target !== svg || !phrase) return;
    const idle = !interaction && !controls.lock.holder;
    const horizontal = event.key === "ArrowLeft" || event.key === "ArrowRight";
    const vertical = event.key === "ArrowUp" || event.key === "ArrowDown";
    if (idle) {
      const range = selectedSources();
      if (!range.length && (vertical || horizontal && (event.altKey || event.shiftKey) ||
          ["Enter", "Delete", "Backspace"].includes(event.key))) {
        setMessage("Select complete source steps within one sequence.");
        event.preventDefault(); return;
      }
      if (selecting && horizontal && !event.altKey) {
        const anchor = selectionAnchor ?? range[0];
        const end = selectionFocus ?? range.at(-1);
        const parent = end === undefined ? null : phrase.structure.nodes[end].parent;
        const siblings = parent === null ? [] : phrase.structure.nodes[parent].children;
        const next = end === undefined ? undefined : siblings[siblings.indexOf(end) + (event.key === "ArrowRight" ? 1 : -1)];
        if (anchor !== undefined && next !== undefined) {
          selectionAnchor = anchor; selectionFocus = next;
          selectRange(extendSourceRange(phrase.structure, anchor, next));
        }
        event.preventDefault(); return;
      }
      if (isPhraseRange(phrase.structure, range) && (vertical || horizontal && event.altKey)) {
        const direction = event.key === "ArrowUp" || event.key === "ArrowRight" ? 1 : -1;
        applyEdit(vertical ? transposeRange(content(phrase), phrase.structure, range, direction)
          : moveRange(content(phrase), phrase.structure, range, direction));
        event.preventDefault(); return;
      }
      if (isPhraseRange(phrase.structure, range) && horizontal && event.shiftKey) {
        setMessage("Resize a single note edge; moving a phrase preserves its source weights.");
        event.preventDefault(); return;
      }
      if (editable && horizontal && (event.altKey || event.shiftKey) && moveOrResize(phrase, event.key === "ArrowRight" ? 1 : -1, event.altKey)) {
        event.preventDefault(); return;
      }
      if (event.key === "Delete" || event.key === "Backspace") {
        controls.clear(); event.preventDefault(); return;
      }
    }
    const keyboardRest = ongoing("keyboard-rest");
    if (keyboardRest) {
      if (event.key === "Enter") { finish(true); event.preventDefault(); return; }
      if (vertical) {
        keyboardRest.midi = boundedPitch(keyboardRest.midi + (event.key === "ArrowUp" ? 1 : -1));
        render(); restPreview(phrase, keyboardRest); event.preventDefault();
      }
      return;
    }
    const stepIndex = selectedStep();
    const step = phrase.steps[stepIndex];
    if (event.key === "Enter" && idle && editable && step) {
      if (step.rest) startRestEntry(phrase, stepIndex);
      else {
        const midi = noteMidi(step.value) ?? 60;
        const firstEvent = phrase.structure.events.find(item => item.node === step.node);
        const draw: InteractionOf<"keyboard-draw"> = { kind: "keyboard-draw", to: stepIndex, lastPitch: midi, lastTime: firstEvent?.start ?? 0, pitches: new Map([[step.node, midi]]), dirty: false };
        begin(draw);
        drawPreview(phrase, draw);
        setMessage("Drawing · Left/Right extends · Up/Down changes pitch · Enter applies · Escape cancels");
      }
      event.preventDefault(); return;
    }
    const keyboardDraw = ongoing("keyboard-draw");
    if (keyboardDraw) {
      if (event.key === "Enter") { finish(true); event.preventDefault(); return; }
      if (!horizontal && !vertical) return;
      if (horizontal) {
        keyboardDraw.to = Math.max(0, Math.min(phrase.steps.length - 1, keyboardDraw.to + (event.key === "ArrowRight" ? 1 : -1)));
      }
      const drawn = phrase.steps[keyboardDraw.to];
      const midi = keyboardDraw.pitches.get(drawn.node) ?? noteMidi(drawn.value) ?? keyboardDraw.lastPitch;
      const next = vertical ? boundedPitch(midi + (event.key === "ArrowUp" ? 1 : -1)) : midi;
      keyboardDraw.pitches.set(drawn.node, next);
      keyboardDraw.lastPitch = next;
      keyboardDraw.dirty = true;
      render(); drawPreview(phrase, keyboardDraw); event.preventDefault();
      return;
    }
    if (interaction) return;
    if (horizontal) {
      // From a selected group, the arrows start at its first step.
      const node = sourceNode();
      const group = node === null ? null : phrase.structure.nodes[node];
      const next = stepIndex >= 0
        ? Math.max(0, Math.min(phrase.steps.length - 1, stepIndex + (event.key === "ArrowRight" ? 1 : -1)))
        : Math.max(0, phrase.steps.findIndex(item => item.from >= phrase.contentFrom + (group?.from ?? 0)));
      setMessage(""); controls.select(next); event.preventDefault();
    } else if (vertical && editable && step && !step.rest) {
      const result = pitchName(boundedPitch((noteMidi(step.value) ?? 60) + (event.key === "ArrowUp" ? 1 : -1)));
      dispatchPatternEdit(view, { changes: [{ from: step.from, to: step.to, insert: result }] }); event.preventDefault();
    }
  }
  function startRestEntry(phrase: EditablePhrase, stepIndex: number): void {
    const step = phrase.steps[stepIndex];
    const occurrence = phrase.structure.rests.find(item => item.node === step.node);
    if (!occurrence) { setMessage("Select this rest in the source steps to add a note."); return; }
    // A new note starts at the nearest drawn pitch.
    let initialPitch = 60;
    for (let distance = 1; distance < phrase.steps.length; distance++) {
      const before = phrase.steps[stepIndex - distance];
      const after = phrase.steps[stepIndex + distance];
      const midi = before && !before.rest ? noteMidi(before.value) : after && !after.rest ? noteMidi(after.value) : null;
      if (midi !== null) { initialPitch = midi; break; }
    }
    const rest: InteractionOf<"keyboard-rest"> = { kind: "keyboard-rest", to: stepIndex, occurrence, midi: initialPitch };
    begin(rest);
    restPreview(phrase, rest);
    setMessage("Rest entry · Up/Down changes pitch · Enter applies · Escape cancels");
  }
  /** Alt moves the selected note one step within its sequence; Shift moves its right edge. False when no note is selected. */
  function moveOrResize(phrase: EditablePhrase, direction: 1 | -1, move: boolean): boolean {
    const nodeIndex = sourceNode();
    const node = nodeIndex === null ? undefined : phrase.structure.nodes[nodeIndex];
    const step = nodeIndex === null ? undefined : phrase.steps[stepFor(nodeIndex)];
    if (nodeIndex === null || node?.kind !== "atom" || !step || step.rest) return false;
    if (move) {
      const parent = node.parent === null ? null : phrase.structure.nodes[node.parent];
      const siblings = parent?.kind === "sequence" ? parent.children : [];
      const target = siblings[siblings.indexOf(nodeIndex) + direction];
      if (target === undefined) setMessage("No adjacent note in this source sequence.");
      else applyEdit(relocateNode(content(phrase), phrase.structure, nodeIndex, target), "This note cannot move outside its source sequence.");
      return true;
    }
    const info = boundaryInfo(phrase.structure, nodeIndex);
    if (!info) { setMessage("This note has no right boundary to resize."); return true; }
    const edit = boundaryEdit(phrase, nodeIndex, clampBoundary(info.ratio + direction * BOUNDARY_STEP), nodeIndex);
    if (edit.ok && !edit.value.changes.length) setMessage("This note boundary cannot move further.");
    else applyEdit(edit, EDGE_REFUSED);
    return true;
  }
  const preventGestureScroll = (event: TouchEvent): void => {
    if (event.cancelable && interaction && SCROLL_LOCKING.has(interaction.kind)) event.preventDefault();
  };

  rulerSelect.addEventListener("change", () => render());
  selectButton.addEventListener("click", () => {
    cancel();
    selecting = !selecting;
    const range = selectedSources();
    selectionAnchor = range[0] ?? sourceNode(); selectionFocus = range.at(-1) ?? selectionAnchor;
    selectButton.setAttribute("aria-pressed", String(selecting));
    setMessage(selecting ? "Drag across source notes, or use Left/Right to extend. Escape finishes selection." : "");
    svg.focus({ preventScroll: true });
  });
  duplicateButton.addEventListener("click", () => {
    if (active && applyEdit(duplicateRange(content(active), active.structure, selectedSources()))) svg.focus({ preventScroll: true });
  });
  svg.addEventListener("pointerdown", beginPointer);
  svg.addEventListener("pointermove", movePointer);
  svg.addEventListener("pointerup", endPointer);
  svg.addEventListener("pointercancel", endPointer);
  svg.addEventListener("touchstart", preventGestureScroll, { passive: false });

  return {
    update(phrase, docChanged) {
      if (docChanged) { selectionAnchor = null; selectionFocus = null; }
      active = phrase;
    },
    render(nextWidth) {
      width = nextWidth;
      render();
    },
    stageHeight: () => stage.clientHeight,
    selectedStep,
    interaction: () => interaction?.kind ?? null,
    cancel,
    stopSelecting() {
      if (!selecting) return false;
      selecting = false;
      selectButton.setAttribute("aria-pressed", "false");
      return true;
    },
    keydown,
    dispose() {
      cancel();
      shownNotes.dispose();
      svg.removeEventListener("pointerdown", beginPointer);
      svg.removeEventListener("pointermove", movePointer);
      svg.removeEventListener("pointerup", endPointer);
      svg.removeEventListener("pointercancel", endPointer);
      svg.removeEventListener("touchstart", preventGestureScroll);
    },
  };
}
