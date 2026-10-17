import { redo, undo } from "@codemirror/commands";
import { runScopeHandlers, type EditorView } from "@codemirror/view";
import type { Pattern } from "./pattern-controls";
import { mountDrumSequencer } from "./drum-sequencer";
import { mountNoteGrid, type EditablePhrase } from "./note-grid";
import { noteMidi } from "./note-grid-layout";
import { needsResizeRender, type GridSize } from "./score-geometry";
import { mountStructureStrip } from "./structure-strip";
import "./moving-score.css";

/** The score's one running interaction, on the note grid or the structure strip. */
export type InteractionLock = { holder: "grid" | "strip" | null };

function drawable(pattern: Pattern): EditablePhrase | null {
  if (!pattern.steps?.length || !pattern.structure) return null;
  if (pattern.notationKind === "note" && !pattern.steps.every(step => step.rest || noteMidi(step.value) !== null)) return null;
  return pattern as EditablePhrase;
}

/**
 * Mount a phrase's drawing: the note grid (chord tones for chords, the
 * percussion matrix for drums) above its structure strip. The widget is
 * rebuilt when a phrase's notation kind changes, so the kind is fixed here.
 */
export function mountMovingScore(
  root: HTMLElement,
  view: EditorView,
  pattern: Pattern,
  controls: { select(index: number): void; selectNode(node: number): void; boundary(node: number, ratio: number): void;
    clear(): void; structureOpen: boolean; structureChanged(open: boolean): void;
    tonesOpen: boolean; tonesChanged(open: boolean): void },
): { update(pattern: Pattern): void; dispose(): void; selectionTools: HTMLElement; structureTools: HTMLElement } {
  root.classList.add("moving-score");
  root.innerHTML = `
    <div class="moving-score__selection-tools"></div>
    <details class="moving-score__structure-details">
      <summary>Structure</summary>
      <div class="moving-score__structure-label">Source steps · linked repetitions</div>
      <svg class="moving-score__structure" preserveAspectRatio="none" role="group" aria-label="Selectable source structure and adjacent weight boundaries" tabindex="0"></svg>
      <div class="moving-score__structure-tools note-properties"></div>
    </details>
    <div class="moving-score__foot"><span class="moving-score__message" role="status" aria-live="polite"></span></div>
    <p class="moving-score__unsupported" hidden></p>`;
  const selectionTools = root.querySelector<HTMLElement>(".moving-score__selection-tools")!;
  const structureDetails = root.querySelector<HTMLDetailsElement>(".moving-score__structure-details")!;
  const structureSvg = root.querySelector<SVGSVGElement>(".moving-score__structure")!;
  const structureTools = root.querySelector<HTMLElement>(".moving-score__structure-tools")!;
  const message = root.querySelector<HTMLElement>(".moving-score__message")!;
  const unsupported = root.querySelector<HTMLElement>(".moving-score__unsupported")!;
  structureDetails.open = controls.structureOpen;
  structureDetails.addEventListener("toggle", () => controls.structureChanged(structureDetails.open));

  const kind = pattern.notationKind;
  const lock: InteractionLock = { holder: null };
  let current = pattern;
  let active = drawable(pattern);
  // The size the last render measured; height changes caused by our own content need no re-render.
  let rendered: GridSize = { width: 0, stageHeight: 0 };
  let disposed = false;
  const setMessage = (text: string): void => { message.textContent = text; };
  function stepFor(node: number | null): number { return active?.steps.findIndex(step => step.node === node) ?? -1; }
  function selectSource(node: number): void {
    if (!active) return;
    strip.forgetBoundary();
    setMessage("");
    // Either control re-renders this drawing with the new selection.
    const index = stepFor(node);
    if (index < 0) controls.selectNode(node);
    else controls.select(index);
  }
  const strip = mountStructureStrip(structureSvg, { select: selectSource, boundary: controls.boundary, setMessage, lock });
  let drum: ReturnType<typeof mountDrumSequencer> | null = null;
  if (kind === "drum") {
    const drumRoot = document.createElement("div");
    drumRoot.className = "moving-score__drums";
    root.prepend(drumRoot);
    drum = mountDrumSequencer(drumRoot, view, pattern, { select: index => controls.select(index) });
  }
  const grid = kind === "drum" ? null : mountNoteGrid(selectionTools, view, kind, selectionTools, {
    select: index => controls.select(index),
    selectNode: node => controls.selectNode(node),
    selectSource,
    clear: () => controls.clear(),
    setMessage,
    shown: node => strip.render(rendered.width, node),
    lock,
    tonesOpen: controls.tonesOpen,
    tonesChanged: open => controls.tonesChanged(open),
  });

  function measure(): GridSize {
    return { width: structureSvg.clientWidth || root.clientWidth, stageHeight: grid?.stageHeight() ?? 0 };
  }
  function render(): void {
    rendered = measure();
    structureDetails.hidden = !active;
    unsupported.hidden = !!active || kind === "drum";
    if (!unsupported.hidden) unsupported.textContent = `${current.reason || "This phrase cannot be drawn."} Edit it directly in code.`;
    // The grid shows the strip the source it draws as selected.
    if (grid) grid.render(rendered.width);
    else strip.render(rendered.width, active?.selectedNode ?? null);
  }
  function cancel(): void {
    grid?.cancel();
    strip.cancel();
    setMessage("");
  }
  function onKeyDown(event: KeyboardEvent): void {
    const target = event.target;
    const nativeControl = target instanceof HTMLSelectElement || target instanceof HTMLInputElement;
    if (event.key === "Escape") {
      if (nativeControl) return;
      if (lock.holder) cancel();
      if (grid?.stopSelecting()) { setMessage(""); event.preventDefault(); return; }
      strip.forgetBoundary();
      if (active) controls.select(grid ? grid.selectedStep() : stepFor(active.selectedNode));
      view.focus(); event.preventDefault(); return;
    }
    if (!nativeControl && (event.metaKey || event.ctrlKey)) {
      if (runScopeHandlers(view, event, "pattern-control") || runScopeHandlers(view, event, "editor")) { event.preventDefault(); return; }
      if (event.key.toLowerCase() === "z") { if (event.shiftKey) redo(view); else undo(view); event.preventDefault(); return; }
    }
    if (target instanceof Element && structureSvg.contains(target)) strip.keydown(event);
    else grid?.keydown(event);
  }
  function update(next: Pattern): void {
    if (disposed) return;
    const docChanged = next.doc !== current.doc;
    current = next;
    active = drawable(next);
    if ((docChanged || !active) && lock.holder) cancel();
    grid?.update(active, docChanged);
    strip.update(active, docChanged);
    drum?.update(next);
    render();
  }

  root.addEventListener("keydown", onKeyDown);
  const resizeObserver = new ResizeObserver(entries => {
    const { width, height } = entries[0].contentRect;
    if (width > 0 && height > 0) {
      if (needsResizeRender(measure(), rendered)) render();
    } else if (lock.holder && grid?.interaction() !== "selection") cancel();
    view.requestMeasure();
  });
  resizeObserver.observe(root);
  grid?.update(active, false);
  strip.update(active, false);
  render();
  return {
    update,
    selectionTools,
    structureTools,
    dispose() {
      disposed = true;
      cancel();
      drum?.dispose();
      grid?.dispose();
      strip.dispose();
      root.removeEventListener("keydown", onKeyDown);
      resizeObserver.disconnect();
      root.replaceChildren();
      root.classList.remove("moving-score");
    },
  };
}
