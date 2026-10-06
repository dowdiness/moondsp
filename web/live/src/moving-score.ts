import { isolateHistory, redo, undo } from "@codemirror/commands";
import { EditorView, runScopeHandlers } from "@codemirror/view";
import type { Pattern } from "./pattern-controls";
import { boundaryInfo, layoutNodes, moveBoundary, projectNotation, relocationTarget, relocateNode,
  sourceRangeNodes, extendSourceRange, transposeRange, moveRange, duplicateRange,
  type NotationProjection, type SourceEdit } from "./notation-structure";
import { midiValue } from "./pitch";
import { mountDrumSequencer } from "./drum-sequencer";
import "./moving-score.css";

type Point = { x: number; y: number };
type EditablePhrase = Pattern & { steps: NonNullable<Pattern["steps"]>; structure: NotationProjection };
type DrawGesture = { pointer: number; startDoc: string; node: number; to: number; end: Point; lastTime: number; pitches: Map<number, number>; dirty: boolean };
type RestGesture = { startDoc: string; node: number; to: number; occurrence: EditablePhrase["structure"]["rests"][number]; midi: number };
type PointerRestGesture = RestGesture & { pointer: number };
type BoundaryGesture = { pointer: number; startDoc: string; node: number; initial: number; ratio: number };
type MoveGesture = { pointer: number; startDoc: string; source: number; target: number; pitch: number; initialPitch: number; start: Point; dirty: boolean; range: number[] };
type EdgeGesture = { pointer: number; startDoc: string; node: number; leftNode: number; rightNode: number; pairStart: number; pairEnd: number; initial: number; ratio: number; previewKey?: string };
type SelectionGesture = { pointer: number; startDoc: string; anchor: number; focus: number; nodes: number[] };
const W = 960;
const ROW_H = 20;
const TIME_H = 24;
const STRUCTURE_H = 64;
const NS = "http://www.w3.org/2000/svg";

function svgEl<K extends keyof SVGElementTagNameMap>(tag: K, attrs: Record<string, string> = {}): SVGElementTagNameMap[K] {
  const el = document.createElementNS(NS, tag);
  for (const [key, value] of Object.entries(attrs)) el.setAttribute(key, value);
  return el;
}
function noteMidi(value: string): number | null { return midiValue(value.split("@")[0])?.midi ?? null; }
function boundedPitch(midi: number, low = 0, high = 127): number {
  return Math.max(low, Math.min(high, Math.round(midi)));
}
function pitchName(midi: number): string {
  const names = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"];
  return `${names[midi % 12]}${Math.floor(midi / 12) - 1}`;
}
function displayPitch(value: string): string { return value.replaceAll("#", "♯").replaceAll("b", "♭"); }
function validPhrase(pattern: Pattern): pattern is EditablePhrase {
  return pattern.steps !== null && pattern.steps.length > 0 && pattern.structure !== null &&
    (pattern.kind === "drum" || pattern.notationKind === "chord" ||
      pattern.steps.every(step => step.rest || noteMidi(step.value) !== null));
}

export function mountMovingScore(
  root: HTMLElement,
  view: EditorView,
  pattern: Pattern,
  controls: { select(index: number): void; selectNode(node: number): void; boundary(node: number, ratio: number): void;
    clear(): void; structureOpen: boolean; structureChanged(open: boolean): void;
    tonesOpen: boolean; tonesChanged(open: boolean): void },
): { update(pattern: Pattern, selected: number): void; dispose(): void; selectionTools: HTMLElement; structureTools: HTMLElement } {
  root.classList.add("moving-score");
  root.innerHTML = `
    <div class="moving-score__drums" hidden></div>
    <div class="moving-score__heading"><div class="moving-score__event-label">Notation events</div>
      <label class="moving-score__time-view">Ruler <select aria-label="Notation ruler"><option value="cycle">Cycle</option><option value="pulse">4 divisions</option></select></label></div>
    <svg class="moving-score__ruler" viewBox="0 0 ${W} ${TIME_H}" preserveAspectRatio="none" aria-hidden="true"></svg>
    <div class="moving-score__stage">
      <svg class="moving-score__canvas" preserveAspectRatio="none" role="application" aria-label="Note grid. Drag notes to change pitch and source order; drag an edge to resize. Click an empty source interval to enter a note. Arrows select steps and change pitch; Alt with Left or Right moves a step, Shift with Left or Right resizes its end, and Delete clears it. Enter previews editing; Escape cancels and returns to code." tabindex="0">
        <g class="moving-score__bands" aria-hidden="true"></g>
        <g class="moving-score__rests"></g>
        <g class="moving-score__notes"></g>
        <g class="moving-score__preview" aria-hidden="true"></g>
      </svg>
    </div>
    <div class="moving-score__selection-tools">
      <button type="button" class="moving-score__select" aria-pressed="false" title="Select a source range by dragging, or extend it with Left/Right">Select</button>
      <button type="button" class="moving-score__duplicate" title="Make an independent copy of the selected source; Repeat keeps occurrences linked">Duplicate</button>
    </div>
    <details class="moving-score__structure-details">
      <summary>Structure</summary>
      <div class="moving-score__structure-label">Source steps · linked repetitions</div>
      <svg class="moving-score__structure" viewBox="0 0 ${W} ${STRUCTURE_H}" preserveAspectRatio="none" role="group" aria-label="Selectable source structure and adjacent weight boundaries" tabindex="0">
        <g class="moving-score__structure-items"></g>
        <g class="moving-score__source-hits"></g>
        <g class="moving-score__boundaries"></g>
      </svg>
      <div class="moving-score__structure-tools note-properties"></div>
    </details>
    <div class="moving-score__foot"><span class="moving-score__message" role="status" aria-live="polite"></span></div>
    <p class="moving-score__unsupported" hidden></p>`;
  const svg = root.querySelector<SVGSVGElement>(".moving-score__canvas")!;
  const drumRoot = root.querySelector<HTMLElement>(".moving-score__drums")!;
  const ruler = root.querySelector<SVGSVGElement>(".moving-score__ruler")!;
  const structureSvg = root.querySelector<SVGSVGElement>(".moving-score__structure")!;
  const structureItems = root.querySelector<SVGGElement>(".moving-score__structure-items")!;
  const boundaries = root.querySelector<SVGGElement>(".moving-score__boundaries")!;
  const sourceHits = root.querySelector<SVGGElement>(".moving-score__source-hits")!;
  const bands = root.querySelector<SVGGElement>(".moving-score__bands")!;
  const notes = root.querySelector<SVGGElement>(".moving-score__notes")!;
  const restMarks = root.querySelector<SVGGElement>(".moving-score__rests")!;
  const stage = root.querySelector<HTMLElement>(".moving-score__stage")!;
  const preview = root.querySelector<SVGGElement>(".moving-score__preview")!;
  const message = root.querySelector<HTMLElement>(".moving-score__message")!;
  const unsupported = root.querySelector<HTMLElement>(".moving-score__unsupported")!;
  const structureLabel = root.querySelector<HTMLElement>(".moving-score__structure-label")!;
  const eventLabel = root.querySelector<HTMLElement>(".moving-score__event-label")!;
  const structureDetails = root.querySelector<HTMLDetailsElement>(".moving-score__structure-details")!;
  const selectionTools = root.querySelector<HTMLElement>(".moving-score__selection-tools")!;
  const structureTools = root.querySelector<HTMLElement>(".moving-score__structure-tools")!;
  const selectButton = root.querySelector<HTMLButtonElement>(".moving-score__select")!;
  const duplicateButton = root.querySelector<HTMLButtonElement>(".moving-score__duplicate")!;
  const rulerSelect = root.querySelector<HTMLSelectElement>(".moving-score__time-view select")!;
  if (pattern.notationKind === "chord") {
    const details = document.createElement("details");
    details.className = "moving-score__tone-details";
    details.open = controls.tonesOpen;
    const summary = document.createElement("summary");
    summary.textContent = "View chord tones";
    const hint = document.createElement("p");
    hint.className = "moving-score__tone-hint";
    hint.textContent = "Tone preview — edit the whole chord above, not individual notes.";
    const heading = root.querySelector<HTMLElement>(".moving-score__heading")!;
    heading.before(details);
    details.append(summary, hint, heading, ruler, stage);
    details.addEventListener("toggle", () => {
      if (!details.isConnected) return;
      controls.tonesChanged(details.open);
    });
    svg.setAttribute("aria-label", "Chord tone preview. Left and Right select whole chords. Edit root and type above; individual tones cannot be dragged.");
  }
  structureDetails.open = controls.structureOpen;
  structureDetails.addEventListener("toggle", () => controls.structureChanged(structureDetails.open));
  rulerSelect.addEventListener("change", () => { renderBands(); renderTimeLabel(); });
  selectButton.addEventListener("click", () => {
    cancel(); selecting = !selecting;
    const range = selectedSources();
    selectionAnchor = range[0] ?? sourceNode(); selectionFocus = range.at(-1) ?? selectionAnchor;
    selectButton.setAttribute("aria-pressed", String(selecting));
    setMessage(selecting ? "Drag across source notes, or use Left/Right to extend. Escape finishes selection." : "");
    svg.focus({ preventScroll: true });
  });
  duplicateButton.addEventListener("click", () => {
    if (!active) return;
    try {
      dispatchSourceEdit(duplicateRange(view.state.doc.sliceString(active.contentFrom, active.contentTo), active.structure, selectedSources()));
      setMessage(""); svg.focus({ preventScroll: true });
    } catch (error) { setMessage(error instanceof Error ? error.message : "Cannot duplicate this source range."); }
  });
  let active: EditablePhrase | null = validPhrase(pattern) ? pattern : null;
  let selectedStep = 0;
  let selectedNode: number | null = null;
  let plotLeft = 70;
  let pixelsToX = 1;
  let plotRight = W - 24;
  let plotHeight = 280;
  let visibleSelection = "";
  let gesture: DrawGesture | null = null;
  let keyboardGesture: Omit<DrawGesture, "pointer"> | null = null;
  let boundaryGesture: BoundaryGesture | null = null;
  let restGesture: PointerRestGesture | null = null;
  let moveGesture: MoveGesture | null = null;
  let edgeGesture: EdgeGesture | null = null;
  let keyboardRestGesture: RestGesture | null = null;
  let selecting = false;
  let selectionAnchor: number | null = null;
  let selectionFocus: number | null = null;
  let selectionGesture: SelectionGesture | null = null;
  let pointerBusy = false;
  let focusedBoundary: number | null = null;
  let disposed = false;
  let feedbackText = "";
  let viewLow = 58;
  let viewHigh = 69;
  let drumSequencer: { update(pattern: Pattern, selected: number): void; dispose(): void } | null = null;
  const pointerOrigin: Point = { x: 0, y: 0 };
  function setMessage(text: string): void { feedbackText = text; message.textContent = text; }
  function stepFor(node: number): number { return active?.steps.findIndex(step => step.node === node) ?? -1; }
  function sourceNode(): number | null { return selectedNode ?? active?.steps[selectedStep]?.node ?? null; }
  function selectedSources(): number[] {
    if (!active) return [];
    if (selectionGesture) return selectionGesture.nodes;
    const range = sourceRangeNodes(active.structure, pattern.selectionFrom - active.contentFrom, pattern.selectionTo - active.contentFrom);
    if (pattern.selectionTo > pattern.selectionFrom) return range;
    return sourceNode() === null ? [] : [sourceNode()!];
  }
  function isPhraseRange(nodes: number[]): boolean {
    return nodes.length > 1 || active?.structure.nodes[nodes[0]]?.kind === "group";
  }
  function selectRange(nodes: number[]): void {
    if (!active || !nodes.length) return;
    const from = active.structure.nodes[nodes[0]].from + active.contentFrom;
    const to = active.structure.nodes[nodes.at(-1)!].end + active.contentFrom;
    view.dispatch({ selection: { anchor: from, head: to } });
  }
  function rangeSibling(hit: number, range: number[]): number | null {
    if (!active || !range.length) return null;
    const parent = active.structure.nodes[range[0]].parent;
    if (parent === null) return range.includes(hit) ? hit : null;
    let node = hit;
    while (active.structure.nodes[node]?.parent !== parent) {
      const next = active.structure.nodes[node]?.parent;
      if (next === undefined || next === null) return null;
      node = next;
    }
    return node;
  }
  function sourceIsSelected(node: number): boolean {
    const selected = selectedSources();
    for (let current: number | null = node; current !== null; current = active?.structure.nodes[current]?.parent ?? null) {
      if (selected.includes(current)) return true;
    }
    return false;
  }
  function applyDraft(content: string, changes: SourceEdit["changes"]): string {
    let result = content;
    for (const change of [...changes].sort((a, b) => b.from - a.from))
      result = result.slice(0, change.from) + change.insert + result.slice(change.to);
    return result;
  }
  function dispatchSourceEdit(edit: SourceEdit): void {
    if (!active) return;
    const offset = active.contentFrom;
    const changes = edit.changes.map(change => ({ ...change, from: change.from + offset, to: change.to + offset }));
    const selection = { anchor: edit.selection.from + offset, head: edit.selection.to + offset };
    view.dispatch({ changes, selection, ...(changes.length ? { annotations: isolateHistory.of("full") } : {}) });
    // CodeMirror records the selection before a selection transaction for Redo.
    // Checkpoint the full destination range, not a mapping of its old position.
    if (changes.length) view.dispatch({ selection: view.state.selection });
  }
  function boundaryEdit(leftNode: number, ratio: number, selected: number): SourceEdit {
    const phrase = active!;
    const content = view.state.doc.sliceString(phrase.contentFrom, phrase.contentTo);
    const changes = moveBoundary(content, phrase.structure, leftNode, ratio);
    const node = phrase.structure.nodes[selected];
    let shift = 0;
    for (const change of changes) {
      if (change.to <= node.from) shift += change.insert.length - (change.to - change.from);
    }
    return { changes, selection: { from: node.from + shift, to: node.baseTo + shift } };
  }
  function pixelsX(pixels: number): number { return pixels * pixelsToX; }
  function sourceX(time: number): number { return plotLeft + (plotRight - plotLeft) * time; }
  function projectionX(time: number): number {
    const span = Math.max(1, active?.structure.span ?? 1);
    return sourceX(Math.max(0, Math.min(span, time)) / span);
  }
  function timeAtX(x: number): number { return (x - plotLeft) * (active?.structure.span ?? 1) / (plotRight - plotLeft); }
  function yAt(midi: number): number { return TIME_H + (viewHigh - midi + .5) * ROW_H; }
  function midiAtY(y: number): number {
    return boundedPitch(viewHigh - Math.floor((y - TIME_H) / ROW_H), viewLow, viewHigh);
  }
  function block(start: number, end: number, y: number, className: string): SVGRectElement {
    const width = projectionX(end) - projectionX(start);
    return svgEl("rect", {
      x: String(projectionX(start) + Math.min(pixelsX(1.5), width / 4)),
      y: String(y - ROW_H / 2 + 2),
      width: String(Math.max(pixelsX(1), width - pixelsX(3))), height: String(ROW_H - 4),
      rx: String(pixelsX(2)), ry: "2", class: className,
    });
  }
  function syncDrum(next: Pattern, selected: number): void {
    if (next.kind === "drum") {
      if (drumSequencer) drumSequencer.update(next, selected);
      else drumSequencer = mountDrumSequencer(drumRoot, view, next, {
        select(index) {
          if (!active) return;
          selectedStep = index;
          selectedNode = active.steps[index]?.node ?? null;
          controls.select(index);
          render();
        },
      });
    } else if (drumSequencer) {
      drumSequencer.dispose();
      drumSequencer = null;
    }
  }
  function renderTimeLabel(): void {
    if (!active) return;
    const label = active.notationKind === "note" ? "Notes" : "Chord tones";
    eventLabel.textContent = `${label} · ${active.structure.span} local ${active.structure.span === 1 ? "cycle" : "cycles"}`;
    eventLabel.title = "Notation time, before outer speed, gate, envelope, or song placement. Four divisions are not a time-signature claim.";
  }
  function renderBands(): void {
    bands.replaceChildren();
    ruler.replaceChildren();
    const row = (y: number, name: string, sharp: boolean, pitch?: number): void => {
      bands.append(svgEl("rect", {
        x: String(plotLeft), y: String(y - ROW_H / 2), width: String(plotRight - plotLeft), height: String(ROW_H),
        class: `moving-score__lane${sharp ? " is-sharp" : ""}`,
        ...(pitch === undefined ? {} : { "data-pitch": String(pitch) }),
      }));
      bands.append(svgEl("rect", {
        x: "0", y: String(y - ROW_H / 2), width: String(plotLeft - pixelsX(4)), height: String(ROW_H),
        class: `moving-score__key${sharp ? " is-sharp" : ""}`,
      }));
      const label = svgEl("text", {
        x: String(plotLeft - pixelsX(10)), y: String(y),
        class: "moving-score__pitch-label", "dominant-baseline": "central",
      });
      label.textContent = name;
      bands.append(label);
    };
    for (let midi = viewHigh; midi >= viewLow; midi--) {
      row(yAt(midi), displayPitch(pitchName(midi)), [1, 3, 6, 8, 10].includes(midi % 12), midi);
    }
    const span = Math.max(1, active?.structure.span ?? 1);
    const divisions = rulerSelect.value === "pulse" ? span * 4 : 4;
    for (let tick = 0; tick <= divisions; tick++) {
      const time = span * tick / divisions, x = projectionX(time);
      bands.append(svgEl("path", {
        d: `M${x} ${TIME_H}V${plotHeight}`, class: `moving-score__time-line${Number.isInteger(time) ? " is-cycle" : ""}`,
      }));
      if (divisions > 8 && tick % 4 !== 0) continue;
      const label = svgEl("text", {
        x: String(x), y: "14", class: "moving-score__time-label",
        "data-time": String(time), "text-anchor": tick === 0 ? "start" : tick === divisions ? "end" : "middle",
      });
      label.textContent = rulerSelect.value === "pulse"
        ? tick === divisions ? "Next" : `${Math.floor(tick / 4) + 1}.${tick % 4 + 1}`
        : span === 1 ? ["0", "¼", "½", "¾", "1"][tick] : String(Number(time.toFixed(2)));
      ruler.append(label);
    }
  }
  function renderStructure(): void {
    structureItems.replaceChildren();
    sourceHits.replaceChildren();
    boundaries.replaceChildren();
    if (!active) return;
    const layout = layoutNodes(active.structure);
    const boundaryNodes = active.structure.nodes.flatMap((node, index) => node.kind === "atom" || node.kind === "group" ? [index] : []);
    const groupDepths = layout.flatMap(item => active!.structure.nodes[item.node].kind === "group" ? [item.depth] : []);
    const groupRows = groupDepths.length ? Math.max(...groupDepths) + 1 : 0;
    const sourceRow = groupRows;
    const rowCount = groupRows + 1;
    const structureHeight = rowCount * 32;
    const rowCssHeight = matchMedia("(pointer: coarse), (max-width: 680px)").matches ? 44 : 32;
    structureSvg.setAttribute("viewBox", `0 0 ${W} ${structureHeight}`);
    structureSvg.style.height = `${rowCount * rowCssHeight}px`;
    const hitWidth = Math.min(plotRight - plotLeft, pixelsX(44));
    const xAt = sourceX;
    structureSvg.style.setProperty("--source-text-aspect", String((rowCssHeight / 32) * pixelsX(1)));
    structureSvg.style.setProperty("--source-label-size", `${12 * 32 / rowCssHeight}px`);
    const selectedIndex = sourceNode();
    const selectedGroups = new Set<number>();
    let parent = selectedIndex === null ? null : active.structure.nodes[selectedIndex]?.parent ?? null;
    while (parent !== null) {
      if (active.structure.nodes[parent]?.kind === "group") selectedGroups.add(parent);
      parent = active.structure.nodes[parent]?.parent ?? null;
    }
    for (const item of layout) {
      const node = active.structure.nodes[item.node];
      if (node.kind === "atom") {
        const x1 = xAt(item.start), x2 = xAt(item.end), width = Math.max(1, x2 - x1);
        const index = stepFor(item.node);
        const rest = active.steps[index]?.rest ?? false;
        const selected = item.node === selectedIndex;
        const visual = svgEl("rect", {
          x: String(x1), y: String(sourceRow * 32), width: String(width), height: "32",
          class: `moving-score__source${selected ? " is-selected" : ""}`,
          "data-node": String(item.node), "data-from": String(active.steps[index].from), "data-to": String(active.steps[index].to),
        });
        structureItems.append(visual);
        const sourceLabel = rest ? "Rest" : active.steps[index].value;
        if (width / pixelsX(1) >= Math.max(36, sourceLabel.length * 7.5 * rowCssHeight / 32 + 8)) {
          const label = svgEl("text", {
            x: String((x1 + x2) / 2), y: String(sourceRow * 32 + 16),
            class: `moving-score__source-label${selected ? " is-selected" : ""}`,
            "dominant-baseline": "central", "aria-hidden": "true",
          });
          label.textContent = sourceLabel;
          structureItems.append(label);
        }
        const targetWidth = Math.max(width, hitWidth);
        const targetX = Math.max(plotLeft, Math.min(plotRight - targetWidth, (x1 + x2 - targetWidth) / 2));
        const hit = svgEl("rect", {
          x: String(targetX), y: String(sourceRow * 32), width: String(targetWidth), height: "32",
          class: `moving-score__source-hit${selected ? " is-selected" : ""}`,
          tabindex: "0", role: "button", "data-node": String(item.node),
          "data-from": String(active.steps[index].from), "data-to": String(active.steps[index].to),
          "aria-label": `Select source step ${Math.max(1, index + 1)}${rest ? ", rest" : `, ${active.steps[index]?.value ?? "note"}`}`,
        });
        sourceHits.append(hit);
      } else if (node.kind === "group") {
        const left = xAt(item.start), right = xAt(item.end);
        const y = item.depth * 32 + 5;
        const selected = item.node === selectedIndex;
        const context = selectedGroups.has(item.node);
        const targetWidth = Math.max(right - left, hitWidth);
        const targetX = Math.max(plotLeft, Math.min(plotRight - targetWidth, (left + right - targetWidth) / 2));
        const group = svgEl("g", {
          class: `moving-score__group${selected ? " is-selected" : context ? " is-context" : ""}`,
          tabindex: "0", role: "button", "data-node": String(item.node),
          "aria-label": `Select group ${node.value || "notation"}`,
        });
        group.append(svgEl("rect", {
          x: String(targetX), y: String(item.depth * 32), width: String(targetWidth), height: "32",
          class: "moving-score__group-hit",
        }));
        group.append(svgEl("path", { d: `M${left} ${y + 4}V${y}H${right}V${y + 4}`, class: "moving-score__bracket" }));
        structureItems.append(group);
      }
    }
    const layoutByNode = new Map(layout.map(item => [item.node, item]));
    for (const leftNode of boundaryNodes) {
      const info = boundaryInfo(active.structure, leftNode);
      if (!info) continue;
      const left = layoutByNode.get(leftNode), right = layoutByNode.get(info.right);
      if (!left || !right) continue;
      const boundaryX = xAt(left.end);
      const node = active.structure.nodes[leftNode];
      const ariaLabel = node.kind === "group"
        ? "Weight boundary after notation group"
        : `Weight boundary after source step ${Math.max(1, stepFor(leftNode) + 1)}`;
      const targetWidth = Math.max(44, hitWidth);
      const targetX = Math.max(plotLeft, Math.min(plotRight - targetWidth, boundaryX - targetWidth / 2));
      const handle = svgEl("g", {
        class: "moving-score__boundary", tabindex: "0", role: "slider", "aria-orientation": "horizontal",
        "data-node": String(leftNode), "data-depth": String(left.depth), "data-row": String(sourceRow), "data-ratio": String(info.ratio),
        "aria-valuemin": "0.05", "aria-valuemax": "0.95", "aria-valuenow": String(info.ratio),
        "aria-label": ariaLabel,
      });
      handle.append(svgEl("rect", {
        x: String(targetX), y: String(sourceRow * 32), width: String(targetWidth), height: "32",
        class: "moving-score__boundary-hit",
      }));
      handle.append(svgEl("path", {
        d: `M${boundaryX} ${sourceRow * 32 + 4}V${sourceRow * 32 + 28}`,
        class: "moving-score__boundary-mark",
      }));
      boundaries.append(handle);
    }
  }
  function render(): void {
    pixelsToX = W / (structureSvg.clientWidth || root.clientWidth || W);
    const pitches = active ? [
      ...active.steps.flatMap(step => {
        const midi = step.rest || active?.notationKind === "chord" ? null : noteMidi(step.value);
        return midi === null ? [] : [midi];
      }),
      ...active.structure.events.flatMap(event => event.pitch === null ? [] : [event.pitch]),
      ...(keyboardGesture?.pitches.values() ?? []),
      ...(restGesture ? [restGesture.midi] : []),
      ...(keyboardRestGesture ? [keyboardRestGesture.midi] : []),
    ] : [];
    const lowest = pitches.length ? Math.min(...pitches) : 60;
    const highest = pitches.length ? Math.max(...pitches) : 67;
    viewLow = Math.max(0, Math.min(116, lowest - 2));
    viewHigh = Math.min(127, Math.max(viewLow + 11, highest + 2));
    plotLeft = pixelsX(48);
    plotRight = W - pixelsX(8);
    const rows = viewHigh - viewLow + 1;
    plotHeight = TIME_H + rows * ROW_H;
    svg.setAttribute("viewBox", `0 ${TIME_H} ${W} ${plotHeight - TIME_H}`);
    svg.style.height = `${plotHeight - TIME_H}px`;
    svg.style.setProperty("--text-aspect", String(pixelsX(1)));
    ruler.style.setProperty("--text-aspect", String(pixelsX(1)));
    renderBands();
    const usable = !!active;
    const isDrum = pattern.kind === "drum";
    svg.toggleAttribute("hidden", !usable || isDrum);
    ruler.toggleAttribute("hidden", !usable || isDrum);
    stage.hidden = !usable || isDrum;
    drumRoot.hidden = !isDrum;
    structureSvg.toggleAttribute("hidden", !usable);
    structureLabel.hidden = !usable;
    eventLabel.hidden = !usable || isDrum;
    rulerSelect.parentElement!.hidden = !usable || isDrum;
    structureDetails.hidden = !usable;
    selectButton.hidden = !usable || pattern.notationKind !== "note";
    duplicateButton.hidden = !usable || pattern.notationKind !== "note";
    duplicateButton.disabled = selectedSources().length === 0;
    if (active && !isDrum) renderTimeLabel();
    unsupported.hidden = usable || isDrum;
    if (!usable) {
      notes.replaceChildren(); restMarks.replaceChildren(); structureItems.replaceChildren(); sourceHits.replaceChildren(); boundaries.replaceChildren();
      if (!isDrum) unsupported.textContent = `${pattern.reason || "This phrase cannot be drawn."} Edit it directly in code.`;
      return;
    }
    renderStructure();
    if (isDrum) { notes.replaceChildren(); restMarks.replaceChildren(); return; }
    const events = active!.structure.events;
    notes.replaceChildren();
    const stepByNode = new Map(active!.steps.map((step, index) => [step.node, { step, index }]));
    restMarks.replaceChildren();
    if (active!.kind === "note" && active!.notationKind === "note") {
      for (const rest of active!.structure.rests) {
        const source = stepByNode.get(rest.node);
        const start = Math.max(0, rest.start), end = Math.min(rest.end, active!.structure.span);
        if (!source?.step.rest || !(end > start)) continue;
        const x = projectionX(start);
        const hit = svgEl("g", {
          class: "moving-score__rest-hit", "data-node": String(rest.node),
          "data-start": String(rest.start), "data-end": String(rest.end),
          role: "button", tabindex: "-1",
          "aria-label": `Source rest interval, occurrence at ${rest.start}–${rest.end}; click a pitch row to enter a note`,
        });
        hit.addEventListener("touchstart", preventGestureScroll, { passive: false });
        hit.append(svgEl("rect", {
          x: String(x), y: String(TIME_H),
          width: String(Math.max(pixelsX(4), projectionX(end) - x)),
          height: String(plotHeight - TIME_H), class: "moving-score__rest-hit-area",
        }));
        restMarks.append(hit);
      }
    }
    for (const event of events) {
      const source = stepByNode.get(event.node);
      if (!source) continue;
      const { step, index } = source;
      if (step.rest) continue;
      const midi = event.pitch ?? (active!.notationKind === "chord" ? null : noteMidi(step.value));
      const x = projectionX((event.start + Math.min(event.end, active!.structure.span)) / 2);
      const group = svgEl("g", {
        class: `moving-score__note${sourceIsSelected(event.node) ? " is-selected" : ""}${moveGesture?.source === event.node ? " is-editing" : ""}`,
        "data-node": String(event.node), "data-index": String(index), "data-start": String(event.start),
        "data-from": String(step.from), "data-to": String(step.to), "data-literal-from": String(active!.contentFrom),
        "data-literal-to": String(active!.contentTo), "data-pitch": String(midi),
        tabindex: "-1", role: "button", "aria-pressed": String(sourceIsSelected(event.node)),
        "aria-label": `Select source step ${index + 1}, occurrence at ${event.start}, ${step.value}${active!.notationKind === "chord" && midi !== null ? `, ${pitchName(midi)}` : ""}`,
      });
      group.addEventListener("touchstart", preventGestureScroll, { passive: false });
      const end = Math.min(event.end, active!.structure.span);
      const width = projectionX(end) - projectionX(event.start);
      const y = yAt(midi ?? 60);
      const title = svgEl("title");
      title.textContent = `${midi === null ? step.value : pitchName(midi)} · ${event.start}–${end} cycles · source ${step.value}`;
      group.append(title);
      group.append(block(event.start, end, y, "moving-score__note-block"));
      if (width / pixelsX(1) >= 34) {
        const label = svgEl("text", {
          x: String(x), y: String(y), class: "moving-score__note-label", "dominant-baseline": "central",
        });
        label.textContent = midi === null ? step.value : displayPitch(pitchName(midi));
        group.append(label);
      }
      notes.append(group);
      const node = active!.structure.nodes[event.node];
      if (active!.kind !== "note" || active!.notationKind !== "note" || step.rest || node.kind !== "atom" ||
          node.modifiers.some(modifier => modifier.kind !== "weight") ||
          node.modifiers.filter(modifier => modifier.kind === "weight").length > 1) continue;
      let ancestor = node.parent;
      let linear = true;
      while (ancestor !== null) {
        const ancestorNode = active!.structure.nodes[ancestor];
        if (ancestorNode.kind === "parallel" ||
            (ancestorNode.kind === "group" && ancestorNode.modifiers.some(modifier => modifier.kind !== "repeat"))) linear = false;
        ancestor = ancestorNode.parent;
      }
      if (!linear) continue;
      const parent = node.parent === null ? null : active!.structure.nodes[node.parent];
      const siblings = parent?.kind === "sequence" ? parent.children : [];
      const siblingIndex = siblings.indexOf(event.node);
      for (const edge of ["left", "right"] as const) {
        const neighbor = siblings[siblingIndex + (edge === "left" ? -1 : 1)];
        const neighborNode = neighbor === undefined ? undefined : active!.structure.nodes[neighbor];
        if (!neighborNode || neighborNode.kind !== "atom" ||
            neighborNode.modifiers.some(modifier => modifier.kind !== "weight") ||
            neighborNode.modifiers.filter(modifier => modifier.kind === "weight").length > 1) continue;
        const neighborEvent = [...events, ...active!.structure.rests].find(item => item.node === neighbor &&
          Math.abs(edge === "left" ? item.end - event.start : item.start - event.end) < 1e-7);
        if (!neighborEvent) continue;
        const leftNode = edge === "left" ? neighbor : event.node;
        const rightNode = edge === "left" ? event.node : neighbor;
        const pairStart = edge === "left" ? neighborEvent.start : event.start;
        const pairEnd = edge === "left" ? event.end : neighborEvent.end;
        const centerX = projectionX(edge === "left" ? event.start : event.end);
        const target = svgEl("rect", {
          x: String(centerX - Math.min(pixelsX(4), width / 4)),
          y: String(y - ROW_H / 2 + 2),
          width: String(Math.max(1, Math.min(pixelsX(8), width / 2))),
          height: String(ROW_H - 4), class: "moving-score__note-edge",
          "data-edge": edge, "data-node": String(event.node), "data-start": String(event.start),
          "data-left-node": String(leftNode), "data-pair-start": String(pairStart),
          "data-pair-end": String(pairEnd), "aria-hidden": "true",
        });
        const leftWeight = active!.structure.nodes[leftNode].weight;
        const rightWeight = active!.structure.nodes[rightNode].weight;
        target.dataset.ratio = String(leftWeight / (leftWeight + rightWeight));
        group.append(target, svgEl("path", {
          d: `M${centerX} ${y - ROW_H / 2 + 4}V${y + ROW_H / 2 - 4}`,
          class: "moving-score__note-edge-mark", "pointer-events": "none",
        }));
      }
    }
    // Only source selection can scroll the grid, never playback highlighting.
    const selectedPitch = keyboardRestGesture?.midi ?? restGesture?.midi ??
      keyboardGesture?.pitches.get(active!.steps[keyboardGesture.to].node) ??
      events.find(event => sourceIsSelected(event.node) && event.pitch !== null)?.pitch;
    const selectionKey = `${sourceNode()}:${selectedPitch}:${viewLow}:${viewHigh}`;
    if (stage.clientHeight && selectionKey !== visibleSelection) {
      if (selectedPitch !== null && selectedPitch !== undefined) {
        const y = yAt(selectedPitch) - TIME_H;
        if (y - ROW_H < stage.scrollTop || y + ROW_H > stage.scrollTop + stage.clientHeight)
          stage.scrollTop = Math.max(0, y - stage.clientHeight / 2);
      }
      visibleSelection = selectionKey;
    }
    if (!gesture && !keyboardGesture && !restGesture && !keyboardRestGesture && !moveGesture && !edgeGesture) preview.replaceChildren();
    message.textContent = feedbackText;
  }
  function canvasPoint(event: PointerEvent): Point {
    const rect = svg.getBoundingClientRect();
    const x = Math.max(plotLeft, Math.min(plotRight, (event.clientX - rect.left) * W / Math.max(1, rect.width)));
    const y = Math.max(TIME_H, Math.min(plotHeight - 1, TIME_H + (event.clientY - rect.top) * (plotHeight - TIME_H) / Math.max(1, rect.height)));
    return { x, y };
  }
  function drawPreview(drawing: Pick<DrawGesture, "pitches">): void {
    preview.replaceChildren();
    if (!active) return;
    for (const event of active.structure.events) {
      const midi = drawing.pitches.get(event.node);
      if (midi !== undefined && !active.steps[stepFor(event.node)]?.rest) {
        preview.append(block(event.start, Math.min(event.end, active.structure.span), yAt(midi), "moving-score__preview-block"));
      }
    }
  }
  function noteMoveEdit(content: string, drawing: MoveGesture): SourceEdit {
    if (isPhraseRange(drawing.range)) {
      const parent = active!.structure.nodes[drawing.range[0]].parent;
      const siblings = parent === null ? [] : active!.structure.nodes[parent].children;
      const steps = siblings.indexOf(drawing.target) - siblings.indexOf(drawing.source);
      return moveRange(content, active!.structure, drawing.range, steps, drawing.pitch - drawing.initialPitch);
    }
    const value = drawing.pitch === drawing.initialPitch ? undefined : pitchName(drawing.pitch);
    try {
      return relocateNode(content, active!.structure, drawing.source, drawing.target, value);
    } catch (error) {
      if (drawing.target !== drawing.source) throw error;
      const node = active!.structure.nodes[drawing.source];
      if (!node || node.kind !== "atom") throw error;
      return {
        changes: value === undefined || value === node.value ? [] : [{ from: node.from, to: node.baseTo, insert: value }],
        selection: { from: node.from, to: value === undefined ? node.baseTo : node.from + value.length },
      };
    }
  }
  function previewProjection(projection: NotationProjection, selected: (node: number) => boolean): void {
    if (!active) return;
    for (const event of projection.events) {
      const midi = event.pitch ?? noteMidi(projection.nodes[event.node]?.value ?? "");
      if (midi === null) continue;
      const isSelected = selected(event.node);
      const unchanged = active.structure.events.some(old =>
        old.pitch === event.pitch && old.start === event.start && old.end === event.end);
      if (isSelected || !unchanged) preview.append(block(event.start, Math.min(event.end, projection.span), yAt(midi),
        isSelected ? "moving-score__preview-block" : "moving-score__context-preview"));
    }
  }
  function previewMove(drawing: MoveGesture): void {
    if (!active) return;
    preview.replaceChildren();
    try {
      const content = view.state.doc.sliceString(active.contentFrom, active.contentTo);
      const edit = noteMoveEdit(content, drawing);
      const projection = projectNotation("note", applyDraft(content, edit.changes));
      if (projection.error) return;
      previewProjection(projection, index => {
        const node = projection.nodes[index];
        return node.from >= edit.selection.from && node.baseTo <= edit.selection.to;
      });
    } catch {
      setMessage("This note cannot move to that source step.");
    }
  }
  function commitMove(drawing: MoveGesture): boolean {
    if (!drawing.dirty || !active) return false;
    if (view.state.doc.toString() !== drawing.startDoc) { setMessage("Score changed; note move cancelled."); return false; }
    const content = view.state.doc.sliceString(active.contentFrom, active.contentTo);
    try {
      const edit = noteMoveEdit(content, drawing);
      dispatchSourceEdit(edit);
      setMessage("");
      return true;
    } catch {
      setMessage("This note cannot move to that source step.");
      return false;
    }
  }
  function previewEdge(drawing: EdgeGesture): void {
    if (!active) return;
    preview.replaceChildren();
    try {
      const content = view.state.doc.sliceString(active.contentFrom, active.contentTo);
      const changes = moveBoundary(content, active.structure, drawing.leftNode, drawing.ratio);
      const projection = projectNotation("note", applyDraft(content, changes));
      if (projection.error) return;
      previewProjection(projection, node => node === drawing.leftNode || node === drawing.rightNode);
    } catch {
      setMessage("This note boundary has no representable adjacent weight.");
    }
  }
  function drawRestPreview(drawing: RestGesture): void {
    preview.replaceChildren();
    if (!active || !active.steps[drawing.to]?.rest) return;
    preview.append(block(drawing.occurrence.start, Math.min(drawing.occurrence.end, active.structure.span), yAt(drawing.midi), "moving-score__preview-block"));
  }
  function commitRest(drawing: RestGesture): boolean {
    const step = active?.steps[drawing.to];
    if (!active || active.notationKind !== "note" || !step || !step.rest ||
        step.node !== drawing.node || view.state.doc.toString() !== drawing.startDoc) {
      setMessage("Score changed; rest entry cancelled.");
      return false;
    }
    selectedStep = drawing.to;
    selectedNode = drawing.node;
    view.dispatch({
      changes: { from: step.from, to: step.to, insert: pitchName(drawing.midi) },
      selection: { anchor: step.from },
      annotations: isolateHistory.of("full"),
    });
    setMessage("");
    return true;
  }
  function commitDraw(drawing: Pick<DrawGesture, "startDoc" | "node" | "to" | "pitches" | "dirty">): boolean {
    if (!drawing.dirty) { setMessage(""); return false; }
    if (!active || active.notationKind !== "note" || view.state.doc.toString() !== drawing.startDoc) {
      setMessage("Score changed; drawing cancelled.");
      return false;
    }
    const changes: { from: number; to: number; insert: string }[] = [];
    for (const [node, midi] of drawing.pitches) {
      const step = active.steps.find(item => item.node === node);
      if (step && !step.rest) {
        const replacement = pitchName(midi);
        if (step.value !== replacement) changes.push({ from: step.from, to: step.to, insert: replacement });
      }
    }
    if (!changes.length) { setMessage(""); return false; }
    changes.sort((left, right) => left.from - right.from);
    const currentStep = drawing.to;
    selectedStep = currentStep;
    selectedNode = active.steps[currentStep].node;
    view.dispatch({ changes, selection: { anchor: view.state.changes(changes).mapPos(active.steps[currentStep].from) }, annotations: isolateHistory.of("full") });
    setMessage("");
    return true;
  }
  function selectSource(node: number): void {
    if (!active) return;
    const index = stepFor(node);
    focusedBoundary = null;
    if (index < 0) { selectedNode = node; controls.selectNode(node); }
    else { selectedStep = index; selectedNode = node; controls.select(index); }
    setMessage(""); render();
  }
  function nodeAtPoint(point: Point): number | null {
    if (!active) return null;
    const time = Math.min(active.structure.span - Number.EPSILON * Math.max(1, active.structure.span), timeAtX(point.x));
    const pitch = midiAtY(point.y);
    let best: number | null = null, distance = Infinity;
    for (const event of [...active.structure.events, ...active.structure.rests]) {
      if (event.start > time || time >= event.end) continue;
      const next = event.pitch === null ? 128 : Math.abs(event.pitch - pitch);
      if (next < distance) { best = event.node; distance = next; }
      else if (next === distance && best !== event.node) best = null;
    }
    return best;
  }
  function beginPointer(event: PointerEvent): void {
    if (pointerBusy || !active || gesture || moveGesture || edgeGesture || restGesture || keyboardGesture || keyboardRestGesture || boundaryGesture || event.button !== 0) return;
    const target = event.target instanceof Element ? event.target : null;
    if (selecting && target && svg.contains(target) && active.notationKind === "note") {
      if (event.clientX < svg.getBoundingClientRect().left + 48) return;
      const node = nodeAtPoint(canvasPoint(event));
      if (node === null) return;
      selectionAnchor = node;
      selectionGesture = { pointer: event.pointerId, startDoc: view.state.doc.toString(), anchor: node, focus: node, nodes: [node] };
      pointerBusy = true; render(); svg.focus({ preventScroll: true });
      svg.setPointerCapture(event.pointerId); event.preventDefault(); return;
    }
    const noteEdge = target?.closest<SVGRectElement>(".moving-score__note-edge");
    if (noteEdge && active.notationKind === "note") {
      const node = Number(noteEdge.dataset.node);
      const leftNode = Number(noteEdge.dataset.leftNode);
      const nodeIndex = stepFor(node);
      if (nodeIndex < 0 || !Number.isFinite(leftNode)) return;
      const parent = active.structure.nodes[leftNode].parent;
      const siblings = parent === null ? [] : active.structure.nodes[parent].children;
      const leftIndex = siblings.indexOf(leftNode);
      const rightNode = siblings[leftIndex + 1];
      if (rightNode === undefined) return;
      const initial = Number(noteEdge.dataset.ratio);
      edgeGesture = {
        pointer: event.pointerId, startDoc: view.state.doc.toString(), node,
        leftNode, rightNode,
        pairStart: Number(noteEdge.dataset.pairStart), pairEnd: Number(noteEdge.dataset.pairEnd),
        initial, ratio: initial,
      };
      selectSource(node); svg.focus({ preventScroll: true }); pointerBusy = true;
      svg.setPointerCapture(event.pointerId); event.preventDefault(); return;
    }
    const boundary = target?.closest<SVGGElement>(".moving-score__boundary");
    if (boundary) {
      const preferredNode = Number(boundary.dataset.node), selectedDepth = Number(boundary.dataset.depth);
      const rect = structureSvg.getBoundingClientRect();
      const pointerX = (event.clientX - rect.left) * W / Math.max(1, rect.width);
      const layout = layoutNodes(active.structure);
      let node = preferredNode, closestDistance = Infinity;
      for (const candidate of active.structure.nodes.flatMap((item, index) => item.kind === "atom" || item.kind === "group" ? [index] : [])) {
        const info = boundaryInfo(active.structure, candidate);
        const left = info && layout.find(item => item.node === candidate);
        if (!info || !left || left.depth !== selectedDepth) continue;
        const distance = Math.abs(sourceX(left.end) - pointerX);
        if (distance < closestDistance || (distance === closestDistance && candidate === preferredNode)) {
          node = candidate;
          closestDistance = distance;
        }
      }
      const info = boundaryInfo(active.structure, node);
      if (!info) return;
      const focusTarget = boundaries.querySelector<SVGGElement>(`.moving-score__boundary[data-node="${node}"]`) ?? boundary;
      focusedBoundary = node;
      focusTarget.focus({ preventScroll: true }); pointerBusy = true;
      boundaryGesture = { pointer: event.pointerId, startDoc: view.state.doc.toString(), node, initial: info.ratio, ratio: info.ratio };
      structureSvg.setPointerCapture(event.pointerId); event.preventDefault(); return;
    }
    const sourceTarget = target?.closest<SVGGElement>(".moving-score__source-hit, .moving-score__group");
    if (sourceTarget) {
      const preferredNode = Number(sourceTarget.dataset.node);
      let node = preferredNode;
      const layout = layoutNodes(active.structure);
      if (sourceTarget.classList.contains("moving-score__source-hit")) {
        const rect = structureSvg.getBoundingClientRect();
        const pointerX = (event.clientX - rect.left) * W / Math.max(1, rect.width);
        let closestDistance = Infinity;
        for (const item of layout) {
          if (active.structure.nodes[item.node].kind !== "atom") continue;
          const center = sourceX((item.start + item.end) / 2);
          const distance = Math.abs(center - pointerX);
          if (distance < closestDistance || (distance === closestDistance && item.node === preferredNode)) {
            node = item.node;
            closestDistance = distance;
          }
        }
      } else {
        const preferredLayout = layout.find(item => item.node === preferredNode);
        if (preferredLayout) {
          const rect = structureSvg.getBoundingClientRect();
          const pointerX = (event.clientX - rect.left) * W / Math.max(1, rect.width);
          let closestDistance = Infinity;
          for (const item of layout) {
            if (active.structure.nodes[item.node].kind !== "group" || item.depth !== preferredLayout.depth) continue;
            const center = sourceX((item.start + item.end) / 2);
            const distance = Math.abs(center - pointerX);
            if (distance < closestDistance || (distance === closestDistance && item.node === preferredNode)) {
              node = item.node;
              closestDistance = distance;
            }
          }
        }
      }
      if (!Number.isFinite(node)) return;
      selectSource(node);
      structureSvg.focus({ preventScroll: true });
      event.preventDefault();
      return;
    }
    if (!target || !svg.contains(target)) return;
    const bounds = svg.getBoundingClientRect();
    if (event.clientX < bounds.left + 48) return;
    const p = canvasPoint(event);
    const restTarget = target.closest<SVGGElement>(".moving-score__rest-hit");
    const time = timeAtX(p.x);
    if (restTarget && active.notationKind === "note") {
      const sourceNode = Number(restTarget.dataset.node);
      const overlapping = active.structure.rests.filter(item => item.start <= time && time < item.end);
      const sourceNodes = [...new Set(overlapping.map(item => item.node))];
      if (sourceNodes.length > 1) { setMessage("Select this rest in the source steps to add a note."); return; }
      const occurrence = overlapping.find(item => item.node === sourceNode && item.start === Number(restTarget.dataset.start))
        ?? overlapping.find(item => item.node === sourceNode);
      const index = stepFor(sourceNode);
      if (!occurrence || index < 0 || !active.steps[index].rest) return;
      selectSource(sourceNode);
      pointerOrigin.x = event.clientX; pointerOrigin.y = event.clientY;
      svg.focus({ preventScroll: true }); pointerBusy = true;
      restGesture = { pointer: event.pointerId, startDoc: view.state.doc.toString(), node: sourceNode, to: index, occurrence, midi: midiAtY(p.y) };
      svg.setPointerCapture(event.pointerId); drawRestPreview(restGesture); event.preventDefault(); return;
    }
    const note = target.closest<SVGGElement>(".moving-score__note");
    let projected: EditablePhrase["structure"]["events"][number] | undefined;
    if (note) {
      const node = Number(note.dataset.node), start = Number(note.dataset.start);
      projected = active.structure.events.find(item => item.node === node && item.start === start);
    } else {
      const phrase = active;
      const contained = phrase.structure.events.filter(item =>
        item.start <= time && time < Math.min(item.end, phrase.structure.span));
      const sourceNodes = [...new Set(contained.map(item => item.node))];
      if (sourceNodes.length !== 1) return;
      projected = contained.find(item => item.node === sourceNodes[0]);
    }
    if (!projected) return;
    const node = projected.node, index = stepFor(node);
    if (index < 0) return;
    const previousRange = selectedSources();
    const keepRange = !!note && !event.shiftKey && sourceIsSelected(node) && isPhraseRange(previousRange);
    if (!keepRange) selectSource(node);
    if (active.notationKind !== "note") { event.preventDefault(); return; }
    if (note) note.focus({ preventScroll: true });
    pointerOrigin.x = event.clientX; pointerOrigin.y = event.clientY;
    svg.focus({ preventScroll: true }); pointerBusy = true;
    if (note && !event.shiftKey) {
      const initialPitch = projected.pitch ?? noteMidi(active.steps[index].value);
      if (initialPitch === null || initialPitch === undefined) { pointerBusy = false; return; }
      moveGesture = {
        pointer: event.pointerId, startDoc: view.state.doc.toString(),
        source: keepRange ? rangeSibling(node, previousRange) ?? node : node,
        target: keepRange ? rangeSibling(node, previousRange) ?? node : node,
        pitch: initialPitch, initialPitch, start: p, dirty: false, range: keepRange ? previousRange : [node],
      };
      render();
    } else {
      gesture = { pointer: event.pointerId, startDoc: view.state.doc.toString(), node, to: index, end: p, lastTime: timeAtX(p.x), pitches: new Map([[node, midiAtY(p.y)]]), dirty: false };
    }
    svg.setPointerCapture(event.pointerId); event.preventDefault();
  }
  function movePointer(event: PointerEvent): void {
    if (selectionGesture?.pointer === event.pointerId && active) {
      if (view.state.doc.toString() !== selectionGesture.startDoc) { endSelection(event, false); return; }
      const node = nodeAtPoint(canvasPoint(event));
      if (node !== null) {
        const range = extendSourceRange(active.structure, selectionGesture.anchor, node);
        if (range.length) { selectionGesture.nodes = range; selectionGesture.focus = node; render(); }
      }
      return;
    }
    if (edgeGesture?.pointer === event.pointerId && active) {
      if (view.state.doc.toString() !== edgeGesture.startDoc) { endEdge(event, false); return; }
      const time = timeAtX(canvasPoint(event).x);
      const ratio = Math.max(.01, Math.min(.99, (time - edgeGesture.pairStart) / Math.max(1e-9, edgeGesture.pairEnd - edgeGesture.pairStart)));
      edgeGesture.ratio = ratio;
      try {
        const content = view.state.doc.sliceString(active.contentFrom, active.contentTo);
        const nextContent = applyDraft(content, moveBoundary(content, active.structure, edgeGesture.leftNode, ratio));
        if (nextContent !== edgeGesture.previewKey) {
          edgeGesture.previewKey = nextContent;
          previewEdge(edgeGesture);
        }
      } catch {
        setMessage("This note boundary has no representable adjacent weight.");
      }
      return;
    }
    if (moveGesture?.pointer === event.pointerId && active) {
      if (view.state.doc.toString() !== moveGesture.startDoc) { endMove(event, false); return; }
      if (!moveGesture.dirty && Math.hypot(event.clientX - pointerOrigin.x, event.clientY - pointerOrigin.y) < 4) return;
      const point = canvasPoint(event), time = timeAtX(point.x);
      let nextTarget = moveGesture.source, nextPitch = midiAtY(point.y);
      if (Math.abs(event.clientX - pointerOrigin.x) >= 4) {
        const targets = new Set<number>();
        for (const item of [...active.structure.events, ...active.structure.rests]) {
          if (item.start > time || time >= Math.min(item.end, active.structure.span)) continue;
          const target = isPhraseRange(moveGesture.range) ? rangeSibling(item.node, moveGesture.range)
            : item.node === moveGesture.source ? item.node : relocationTarget(active.structure, moveGesture.source, item.node);
          if (target !== null) targets.add(target);
        }
        if (targets.size === 1) {
          nextTarget = targets.values().next().value!;
          setMessage("");
        } else {
          nextPitch = moveGesture.initialPitch;
          setMessage(targets.size ? "Choose an unambiguous source step to move this note."
            : "This note can only move within its own source sequence.");
        }
      } else setMessage("");
      if (nextTarget !== moveGesture.target || nextPitch !== moveGesture.pitch) {
        moveGesture.target = nextTarget;
        moveGesture.pitch = nextPitch;
        moveGesture.dirty = nextTarget !== moveGesture.source || nextPitch !== moveGesture.initialPitch;
        if (moveGesture.dirty) previewMove(moveGesture);
        else preview.replaceChildren();
      }
      return;
    }
    if (boundaryGesture?.pointer === event.pointerId && active) {
      if (view.state.doc.toString() !== boundaryGesture.startDoc) { endBoundary(event, false); return; }
      const rect = structureSvg.getBoundingClientRect();
      const x = (event.clientX - rect.left) * W / Math.max(1, rect.width);
      const layout = layoutNodes(active.structure), left = layout.find(item => item.node === boundaryGesture!.node);
      const info = boundaryInfo(active.structure, boundaryGesture.node);
      const right = info && layout.find(item => item.node === info.right);
      if (!left || !right) return;
      const xAt = sourceX;
      const start = xAt(left.start), end = xAt(right.end);
      const ratio = Math.max(.01, Math.min(.99, (x - start) / Math.max(1, end - start)));
      boundaryGesture.ratio = ratio;
      const handle = boundaries.querySelector<SVGGElement>(`.moving-score__boundary[data-node="${boundaryGesture.node}"]`);
      if (handle) {
        handle.dataset.ratio = String(ratio);
        handle.setAttribute("aria-valuenow", String(ratio));
        const mark = handle.querySelector<SVGPathElement>(".moving-score__boundary-mark");
        const rowY = Number(handle.dataset.row) * 32;
        mark?.setAttribute("d", `M${start + (end - start) * ratio} ${rowY + 4}V${rowY + 28}`);
      }
      return;
    }
    if (restGesture?.pointer === event.pointerId && active) {
      if (view.state.doc.toString() !== restGesture.startDoc) { endRestPointer(event, false); return; }
      restGesture.midi = midiAtY(canvasPoint(event).y);
      drawRestPreview(restGesture);
      return;
    }
    if (!gesture || gesture.pointer !== event.pointerId || !active) return;
    if (!gesture.dirty && Math.hypot(event.clientX - pointerOrigin.x, event.clientY - pointerOrigin.y) < 4) return;
    if (view.state.doc.toString() !== gesture.startDoc) { endPointer(event, false); return; }
    const p = canvasPoint(event);
    const time = Math.max(0, Math.min(active.structure.span, timeAtX(p.x)));
    const nextMidi = midiAtY(p.y), delta = time - gesture.lastTime;
    const previousMidi = midiAtY(gesture.end.y);
    // Pointer coordinates may round to device pixels while SVG centers do not.
    const tolerance = active.structure.span / Math.max(1, svg.clientWidth);
    if (Math.abs(delta) < 1e-8) {
      gesture.pitches.set(active.steps[gesture.to].node, nextMidi);
    } else for (const projected of active.structure.events) {
      const center = (projected.start + Math.min(projected.end, active.structure.span)) / 2;
      if (center < Math.min(gesture.lastTime, time) - tolerance || center > Math.max(gesture.lastTime, time) + tolerance) continue;
      const fraction = Math.max(0, Math.min(1, (center - gesture.lastTime) / delta));
      gesture.pitches.set(projected.node, boundedPitch(previousMidi + (nextMidi - previousMidi) * fraction, viewLow, viewHigh));
    }
    let closestDistance = Infinity;
    for (const projected of active.structure.events) {
      const distance = Math.abs((projected.start + Math.min(projected.end, active.structure.span)) / 2 - time);
      if (distance < closestDistance) {
        const index = stepFor(projected.node);
        if (index >= 0) { gesture.to = index; closestDistance = distance; }
      }
    }
    gesture.end = p;
    gesture.lastTime = time;
    gesture.dirty = true;
    drawPreview(gesture);
  }
  function endBoundary(event: PointerEvent, commit: boolean): void {
    if (!boundaryGesture || boundaryGesture.pointer !== event.pointerId) return;
    const current = boundaryGesture; boundaryGesture = null; pointerBusy = false;
    if (structureSvg.hasPointerCapture(event.pointerId)) structureSvg.releasePointerCapture(event.pointerId);
    if (commit && view.state.doc.toString() === current.startDoc && Math.abs(current.initial - current.ratio) > .005) {
      controls.boundary(current.node, current.ratio); setMessage("");
    } else if (view.state.doc.toString() !== current.startDoc) setMessage("Score changed; boundary edit cancelled.");
    render();
    structureSvg.focus({ preventScroll: true });
  }
  function endEdge(event: PointerEvent, commit: boolean): void {
    if (!edgeGesture || edgeGesture.pointer !== event.pointerId) return;
    const current = edgeGesture;
    edgeGesture = null; pointerBusy = false;
    if (svg.hasPointerCapture(event.pointerId)) svg.releasePointerCapture(event.pointerId);
    if (commit && active && view.state.doc.toString() === current.startDoc) {
      try {
        const edit = boundaryEdit(current.leftNode, current.ratio, current.node);
        if (edit.changes.length) dispatchSourceEdit(edit);
        setMessage("");
      } catch {
        setMessage("This note boundary has no representable adjacent weight.");
      }
    } else if (view.state.doc.toString() !== current.startDoc) setMessage("Score changed; boundary edit cancelled.");
    preview.replaceChildren(); render();
  }
  function endMove(event: PointerEvent, commit: boolean): void {
    if (!moveGesture || moveGesture.pointer !== event.pointerId) return;
    const current = moveGesture; moveGesture = null; pointerBusy = false;
    if (svg.hasPointerCapture(event.pointerId)) svg.releasePointerCapture(event.pointerId);
    preview.replaceChildren();
    if (commit) commitMove(current);
    else if (active && view.state.doc.toString() !== current.startDoc) setMessage("Score changed; note move cancelled.");
    render();
  }
  function endSelection(event: PointerEvent, commit: boolean): void {
    if (!selectionGesture || selectionGesture.pointer !== event.pointerId) return;
    const current = selectionGesture; selectionGesture = null; pointerBusy = false;
    if (svg.hasPointerCapture(event.pointerId)) svg.releasePointerCapture(event.pointerId);
    if (commit && view.state.doc.toString() === current.startDoc) {
      selectionFocus = current.focus; selectRange(current.nodes);
    }
    render();
  }
  function endPointer(event: PointerEvent, commit: boolean): void {
    if (!gesture || gesture.pointer !== event.pointerId) return;
    const current = gesture; gesture = null; pointerBusy = false;
    if (svg.hasPointerCapture(event.pointerId)) svg.releasePointerCapture(event.pointerId);
    preview.replaceChildren();
    if (commit) commitDraw(current);
    render();
  }
  function endRestPointer(event: PointerEvent, commit: boolean): void {
    if (!restGesture || restGesture.pointer !== event.pointerId) return;
    const current = restGesture; restGesture = null; pointerBusy = false;
    if (svg.hasPointerCapture(event.pointerId)) svg.releasePointerCapture(event.pointerId);
    preview.replaceChildren();
    if (commit) commitRest(current);
    render();
  }
  function cancelKeyboardRest(): void {
    keyboardRestGesture = null;
    preview.replaceChildren();
    render();
  }
  function cancel(): void {
    if (selectionGesture) endSelection(new PointerEvent("pointercancel", { pointerId: selectionGesture.pointer }), false);
    if (gesture) endPointer(new PointerEvent("pointercancel", { pointerId: gesture.pointer }), false);
    if (edgeGesture) endEdge(new PointerEvent("pointercancel", { pointerId: edgeGesture.pointer }), false);
    if (moveGesture) endMove(new PointerEvent("pointercancel", { pointerId: moveGesture.pointer }), false);
    if (restGesture) endRestPointer(new PointerEvent("pointercancel", { pointerId: restGesture.pointer }), false);
    if (boundaryGesture) endBoundary(new PointerEvent("pointercancel", { pointerId: boundaryGesture.pointer }), false);
    if (keyboardGesture) { keyboardGesture = null; preview.replaceChildren(); render(); }
    if (keyboardRestGesture) cancelKeyboardRest();
    focusedBoundary = null;
    setMessage("");
  }
  function onKeyDown(event: KeyboardEvent): void {
    const target = event.target;
    const isNativeControl = target instanceof HTMLSelectElement || target instanceof HTMLInputElement;
    if (event.key === "Escape") {
      if (isNativeControl) return;
      if (gesture || moveGesture || edgeGesture || restGesture || keyboardGesture || keyboardRestGesture || boundaryGesture || selectionGesture) cancel();
      if (selecting) {
        selecting = false; selectButton.setAttribute("aria-pressed", "false");
        setMessage(""); event.preventDefault(); return;
      }
      focusedBoundary = null;
      if (active) controls.select(selectedStep);
      view.focus(); event.preventDefault(); return;
    }
    if (!isNativeControl && (event.metaKey || event.ctrlKey)) {
      if (runScopeHandlers(view, event, "pattern-control") || runScopeHandlers(view, event, "editor")) { event.preventDefault(); return; }
      if (event.key.toLowerCase() === "z") { if (event.shiftKey) redo(view); else undo(view); event.preventDefault(); return; }
    }
    if (target === svg && active && !pointerBusy && !keyboardGesture && !keyboardRestGesture) {
      const range = selectedSources();
      const horizontal = event.key === "ArrowLeft" || event.key === "ArrowRight";
      const vertical = event.key === "ArrowUp" || event.key === "ArrowDown";
      if (!range.length && (vertical || horizontal && (event.altKey || event.shiftKey) ||
          ["Enter", "Delete", "Backspace"].includes(event.key))) {
        setMessage("Select complete source steps within one sequence.");
        event.preventDefault(); return;
      }
      if (selecting && horizontal && !event.altKey) {
        const anchor = selectionAnchor ?? range[0];
        const end = selectionFocus ?? range.at(-1);
        const parent = end === undefined ? null : active.structure.nodes[end].parent;
        const siblings = parent === null ? [] : active.structure.nodes[parent].children;
        const next = end === undefined ? undefined : siblings[siblings.indexOf(end) + (event.key === "ArrowRight" ? 1 : -1)];
        if (anchor !== undefined && next !== undefined) {
          selectionAnchor = anchor; selectionFocus = next;
          selectRange(extendSourceRange(active.structure, anchor, next));
        }
        event.preventDefault(); return;
      }
      if (isPhraseRange(range) && (vertical || horizontal && event.altKey)) {
        try {
          const content = view.state.doc.sliceString(active.contentFrom, active.contentTo);
          const direction = event.key === "ArrowUp" || event.key === "ArrowRight" ? 1 : -1;
          dispatchSourceEdit(vertical ? transposeRange(content, active.structure, range, direction)
            : moveRange(content, active.structure, range, direction));
          setMessage("");
        } catch (error) { setMessage(error instanceof Error ? error.message : "This source range cannot move further."); }
        event.preventDefault(); return;
      }
      if (isPhraseRange(range) && horizontal && event.shiftKey) {
        setMessage("Resize a single note edge; moving a phrase preserves its source weights.");
        event.preventDefault(); return;
      }
    }
    if (target === svg && active?.notationKind === "note" && !pointerBusy && !keyboardGesture && !keyboardRestGesture && (event.altKey || event.shiftKey) &&
        (event.key === "ArrowLeft" || event.key === "ArrowRight")) {
      const nodeIndex = sourceNode();
      const node = nodeIndex === null ? undefined : active.structure.nodes[nodeIndex];
      const stepIndex = nodeIndex === null ? -1 : stepFor(nodeIndex);
      const step = active.steps[stepIndex];
      if (node?.kind === "atom" && step && !step.rest) {
        const direction = event.key === "ArrowRight" ? 1 : -1;
        if (event.altKey) {
          const parent = node.parent === null ? null : active.structure.nodes[node.parent];
          const siblings = parent?.kind === "sequence" ? parent.children : [];
          const position = siblings.indexOf(nodeIndex!);
          const target = siblings[position + direction];
          if (target === undefined) setMessage("No adjacent note in this source sequence.");
          else {
            try {
              const content = view.state.doc.sliceString(active.contentFrom, active.contentTo);
              dispatchSourceEdit(relocateNode(content, active.structure, nodeIndex!, target));
              setMessage("");
            } catch { setMessage("This note cannot move outside its source sequence."); }
          }
        } else {
          const info = boundaryInfo(active.structure, nodeIndex!);
          if (!info) setMessage("This note has no right boundary to resize.");
          else {
            const ratio = Math.max(.01, Math.min(.99, info.ratio + direction * .05));
            try {
              const edit = boundaryEdit(nodeIndex!, ratio, nodeIndex!);
              if (!edit.changes.length) setMessage("This note boundary cannot move further.");
              else dispatchSourceEdit(edit);
            } catch { setMessage("This note boundary has no representable adjacent weight."); }
          }
        }
        event.preventDefault(); return;
      }
    }
    if (target === svg && active && !pointerBusy && !keyboardGesture && !keyboardRestGesture && (event.key === "Delete" || event.key === "Backspace")) {
      controls.clear(); event.preventDefault(); return;
    }
    if (target instanceof Element && structureSvg.contains(target) && active) {
      const handle = target.closest<SVGGElement>(".moving-score__boundary");
      if (handle) focusedBoundary = Number(handle.dataset.node);
      const boundaryNode = handle ? Number(handle.dataset.node) : focusedBoundary;
      if (boundaryNode !== null && (target === structureSvg || handle) && (event.key === "ArrowLeft" || event.key === "ArrowRight")) {
        const info = boundaryInfo(active.structure, boundaryNode);
        if (!info) { focusedBoundary = null; return; }
        const ratio = info.ratio + (event.key === "ArrowRight" ? .05 : -.05);
        controls.boundary(boundaryNode, Math.max(.01, Math.min(.99, ratio)));
        structureSvg.focus({ preventScroll: true });
        event.preventDefault(); return;
      }
      const selected = target.closest<SVGGElement>(".moving-score__source-hit, .moving-score__group");
      if (selected && (event.key === "Enter" || event.key === " ")) {
        selectSource(Number(selected.dataset.node));
        structureSvg.focus({ preventScroll: true });
        event.preventDefault(); return;
      }
      if (event.key === "ArrowLeft" || event.key === "ArrowRight") {
        const nodes = active.structure.nodes.map((node, index) => node.kind === "group" || node.kind === "atom" ? index : -1).filter(index => index >= 0);
        const currentNode = selected?.dataset.node ? Number(selected.dataset.node) : sourceNode() ?? -1;
        const position = Math.max(0, nodes.indexOf(currentNode));
        const next = Math.max(0, Math.min(nodes.length - 1, position + (event.key === "ArrowRight" ? 1 : -1)));
        selectSource(nodes[next]); structureSvg.focus({ preventScroll: true }); event.preventDefault(); return;
      }
    }
    if (target !== svg || !active) return;
    if (keyboardRestGesture) {
      if (event.key === "Enter") {
        const current = keyboardRestGesture; keyboardRestGesture = null;
        preview.replaceChildren(); commitRest(current); render(); event.preventDefault(); return;
      }
      if (event.key === "ArrowUp" || event.key === "ArrowDown") {
        keyboardRestGesture.midi = boundedPitch(keyboardRestGesture.midi + (event.key === "ArrowUp" ? 1 : -1));
        render(); drawRestPreview(keyboardRestGesture); event.preventDefault(); return;
      }
      return;
    }
    if (event.key === "Enter" && !keyboardGesture && active.notationKind === "note" && active.steps[selectedStep]?.rest) {
      const step = active.steps[selectedStep];
      const occurrence = active.structure.rests.find(item => item.node === step.node);
      if (!occurrence) { setMessage("Select this rest in the source steps to add a note."); return; }
      let initialPitch = 60;
      for (let distance = 1; distance < active.steps.length; distance++) {
        const before = active.steps[selectedStep - distance];
        const after = active.steps[selectedStep + distance];
        const midi = before && !before.rest ? noteMidi(before.value) : after && !after.rest ? noteMidi(after.value) : null;
        if (midi !== null) { initialPitch = midi; break; }
      }
      keyboardRestGesture = { startDoc: view.state.doc.toString(), node: step.node, to: selectedStep, occurrence, midi: initialPitch };
      drawRestPreview(keyboardRestGesture); setMessage("Rest entry · Up/Down changes pitch · Enter applies · Escape cancels"); event.preventDefault(); return;
    }
    if (event.key === "Enter" && !keyboardGesture && active.notationKind === "note") {
      const step = active.steps[selectedStep]; if (!step || step.rest) return;
      const midi = noteMidi(step.value) ?? 60;
      const firstEvent = active.structure.events.find(item => item.node === step.node);
      const startTime = firstEvent?.start ?? 0;
      const start = { x: projectionX(startTime), y: yAt(midi) };
      keyboardGesture = { startDoc: view.state.doc.toString(), node: step.node, to: selectedStep, end: start, lastTime: startTime, pitches: new Map([[step.node, midi]]), dirty: false };
      drawPreview(keyboardGesture); setMessage("Drawing · Left/Right extends · Up/Down changes pitch · Enter applies · Escape cancels"); event.preventDefault(); return;
    }
    if (keyboardGesture) {
      if (event.key === "Enter") { const current = keyboardGesture; keyboardGesture = null; preview.replaceChildren(); commitDraw(current); render(); event.preventDefault(); return; }
      if (event.key === "ArrowLeft" || event.key === "ArrowRight") {
        const direction = event.key === "ArrowRight" ? 1 : -1;
        keyboardGesture.to = Math.max(0, Math.min(active.steps.length - 1, keyboardGesture.to + direction));
        const step = active.steps[keyboardGesture.to];
        const midi = keyboardGesture.pitches.get(step.node) ?? noteMidi(step.value) ?? midiAtY(keyboardGesture.end.y);
        keyboardGesture.pitches.set(step.node, midi);
        const occurrence = active.structure.events.find(item => item.node === step.node);
        keyboardGesture.end = { x: projectionX(occurrence?.start ?? 0), y: yAt(midi) };
        keyboardGesture.dirty = true;
        selectedStep = keyboardGesture.to;
        render(); drawPreview(keyboardGesture); event.preventDefault();
      } else if (event.key === "ArrowUp" || event.key === "ArrowDown") {
        const step = active.steps[keyboardGesture.to];
        const currentMidi = keyboardGesture.pitches.get(step.node) ?? noteMidi(step.value) ?? midiAtY(keyboardGesture.end.y);
        const next = boundedPitch(currentMidi + (event.key === "ArrowUp" ? 1 : -1));
        keyboardGesture.pitches.set(step.node, next);
        keyboardGesture.end = { x: keyboardGesture.end.x, y: yAt(next) };
        keyboardGesture.dirty = true;
        render(); drawPreview(keyboardGesture); event.preventDefault();
      } else {
        return;
      }
      return;
    }
    if (event.key === "ArrowRight" || event.key === "ArrowLeft") {
      selectedStep = Math.max(0, Math.min(active.steps.length - 1, selectedStep + (event.key === "ArrowRight" ? 1 : -1)));
      selectedNode = active.steps[selectedStep].node; controls.select(selectedStep); setMessage(""); render(); event.preventDefault();
    } else if ((event.key === "ArrowUp" || event.key === "ArrowDown") && active.notationKind === "note") {
      const step = active.steps[selectedStep]; if (!step || step.rest) return;
      const current = noteMidi(step.value) ?? 60, result = pitchName(boundedPitch(current + (event.key === "ArrowUp" ? 1 : -1)));
      view.dispatch({ changes: { from: step.from, to: step.to, insert: result }, annotations: isolateHistory.of("full") }); event.preventDefault();
    }
  }
  function update(next: Pattern, selected: number): void {
    if (disposed) return;
    if (next.doc !== pattern.doc && (gesture || moveGesture || edgeGesture || restGesture || keyboardGesture || keyboardRestGesture || boundaryGesture || selectionGesture)) cancel();
    if (next.doc !== pattern.doc) { focusedBoundary = null; selectionAnchor = null; selectionFocus = null; }
    pattern = next; active = validPhrase(pattern) ? pattern : null;
    selectedStep = active ? Math.max(0, Math.min(selected, active.steps.length - 1)) : 0;
    selectedNode = active?.selectedNode ?? active?.steps[selectedStep]?.node ?? null;
    if (!active && (gesture || moveGesture || edgeGesture || restGesture || keyboardGesture || keyboardRestGesture || boundaryGesture || selectionGesture)) cancel();
    syncDrum(pattern, selectedStep);
    render();
  }
  const onPointerCancel = (event: PointerEvent) => { endSelection(event, false); endPointer(event, false); endRestPointer(event, false); endBoundary(event, false); endMove(event, false); endEdge(event, false); };
  const onPointerUp = (event: PointerEvent) => { endSelection(event, true); endPointer(event, true); endRestPointer(event, true); endBoundary(event, true); endMove(event, true); endEdge(event, true); };
  const preventGestureScroll = (event: TouchEvent) => {
    // Selection redraws detach the hit group during pointerdown. Its touchstart
    // still arrives there, so listen on that group rather than the canvas.
    if (event.cancelable && (gesture || moveGesture || edgeGesture || restGesture || selectionGesture)) event.preventDefault();
  };
  svg.addEventListener("pointerdown", beginPointer);
  svg.addEventListener("pointermove", movePointer);
  svg.addEventListener("pointerup", onPointerUp);
  svg.addEventListener("pointercancel", onPointerCancel);
  structureSvg.addEventListener("pointerdown", beginPointer);
  structureSvg.addEventListener("pointermove", movePointer);
  structureSvg.addEventListener("pointerup", onPointerUp);
  structureSvg.addEventListener("pointercancel", onPointerCancel);
  root.addEventListener("keydown", onKeyDown);
  const resizeObserver = new ResizeObserver(entries => {
    const { width, height } = entries[0].contentRect;
    if (width > 0 && height > 0) {
      render();
    } else if (gesture || moveGesture || edgeGesture || restGesture || keyboardGesture || keyboardRestGesture || boundaryGesture) cancel();
    view.requestMeasure();
  });
  resizeObserver.observe(root);
  syncDrum(pattern, selectedStep);
  render();
  return {
    update,
    selectionTools,
    structureTools,
    dispose() {
      disposed = true; cancel();
      drumSequencer?.dispose(); drumSequencer = null;
      svg.removeEventListener("pointerdown", beginPointer); svg.removeEventListener("pointermove", movePointer);
      svg.removeEventListener("pointerup", onPointerUp); svg.removeEventListener("pointercancel", onPointerCancel);
      structureSvg.removeEventListener("pointerdown", beginPointer); structureSvg.removeEventListener("pointermove", movePointer);
      structureSvg.removeEventListener("pointerup", onPointerUp); structureSvg.removeEventListener("pointercancel", onPointerCancel);
      root.removeEventListener("keydown", onKeyDown); resizeObserver.disconnect(); root.replaceChildren();
      root.classList.remove("moving-score"); delete root.dataset.dense;
    },
  };
}
