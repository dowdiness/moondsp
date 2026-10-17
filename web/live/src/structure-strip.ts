import { BOUNDARY_STEP, boundaryInfo, clampBoundary } from "./notation-structure";
import { W, plotScale, scoreGeometry } from "./score-geometry";
import { STRIP_ROW, hitStrip, stripLayout, stripNodes, type StripLayout, type StripPhrase } from "./structure-layout";
import { patchSvg } from "./svg-patch";
import type { InteractionLock } from "./moving-score";

type Drag = { pointer: number; node: number; initial: number; ratio: number };

/**
 * Mount the structure strip: select source steps and groups, and drag or nudge
 * the weight boundaries between neighbours.
 */
export function mountStructureStrip(
  svg: SVGSVGElement,
  controls: Readonly<{
    select(node: number): void;
    boundary(node: number, ratio: number): void;
    setMessage(text: string): void;
    lock: InteractionLock;
  }>,
): {
  update(phrase: StripPhrase | null, docChanged: boolean): void;
  render(width: number, selected: number | null): void;
  cancel(): void;
  /** Forget the boundary the keyboard last adjusted, after something else is selected. */
  forgetBoundary(): void;
  dragging(): boolean;
  keydown(event: KeyboardEvent): void;
  dispose(): void;
} {
  const ns = "http://www.w3.org/2000/svg";
  const items = document.createElementNS(ns, "g");
  items.setAttribute("class", "moving-score__structure-items");
  const hits = document.createElementNS(ns, "g");
  hits.setAttribute("class", "moving-score__source-hits");
  const marks = document.createElementNS(ns, "g");
  marks.setAttribute("class", "moving-score__boundaries");
  svg.append(items, hits, marks);

  let phrase: StripPhrase | null = null;
  let layout: StripLayout | null = null;
  let width = 0;
  let selected: number | null = null;
  let drag: Drag | null = null;
  let focusedBoundary: number | null = null;

  function render(): void {
    if (!phrase) {
      layout = null;
      patchSvg(items, []); patchSvg(hits, []); patchSvg(marks, []);
      return;
    }
    const rowPixels = matchMedia("(pointer: coarse), (max-width: 680px)").matches ? 44 : 32;
    const scale = plotScale(scoreGeometry(width, []), phrase.structure.span);
    layout = stripLayout(phrase, scale, rowPixels);
    svg.setAttribute("viewBox", `0 0 ${W} ${layout.rows * STRIP_ROW}`);
    svg.style.height = `${layout.rows * rowPixels}px`;
    svg.style.setProperty("--source-text-aspect", String((rowPixels / STRIP_ROW) * scale.px(1)));
    svg.style.setProperty("--source-label-size", `${12 * STRIP_ROW / rowPixels}px`);
    const nodes = stripNodes(layout, phrase.structure, { selected, dragging: drag });
    patchSvg(items, nodes.items); patchSvg(hits, nodes.hits); patchSvg(marks, nodes.boundaries);
  }
  function point(event: PointerEvent): { x: number; y: number } {
    const rect = svg.getBoundingClientRect();
    return {
      x: (event.clientX - rect.left) * W / Math.max(1, rect.width),
      y: (event.clientY - rect.top) * (layout?.rows ?? 1) * STRIP_ROW / Math.max(1, rect.height),
    };
  }
  function boundaryElement(node: number): SVGGElement | null {
    return marks.querySelector<SVGGElement>(`.moving-score__boundary[data-node="${node}"]`);
  }
  function finish(commit: boolean): void {
    const current = drag;
    if (!current) return;
    drag = null;
    controls.lock.holder = null;
    if (svg.hasPointerCapture(current.pointer)) svg.releasePointerCapture(current.pointer);
    if (commit && Math.abs(current.initial - current.ratio) > .005) {
      controls.boundary(current.node, current.ratio);
      controls.setMessage("");
    }
    render();
    svg.focus({ preventScroll: true });
  }
  function pointerdown(event: PointerEvent): void {
    if (controls.lock.holder || !layout || event.button !== 0) return;
    const { x, y } = point(event);
    const hit = hitStrip(layout, x, y);
    if (!hit) return;
    event.preventDefault();
    if (hit.kind === "select") {
      controls.select(hit.node);
      svg.focus({ preventScroll: true });
      return;
    }
    const { node, ratio } = hit.boundary;
    focusedBoundary = node;
    boundaryElement(node)?.focus({ preventScroll: true });
    drag = { pointer: event.pointerId, node, initial: ratio, ratio };
    controls.lock.holder = "strip";
    svg.setPointerCapture(event.pointerId);
  }
  function pointermove(event: PointerEvent): void {
    const boundary = drag && layout?.boundaries.find(item => item.node === drag!.node);
    if (!drag || drag.pointer !== event.pointerId || !boundary) return;
    drag.ratio = clampBoundary((point(event).x - boundary.start) / Math.max(1, boundary.end - boundary.start));
    render();
  }
  function pointerend(event: PointerEvent): void {
    if (drag?.pointer === event.pointerId) finish(event.type === "pointerup");
  }
  function keydown(event: KeyboardEvent): void {
    if (!phrase || !(event.target instanceof Element)) return;
    const target = event.target;
    const handle = target.closest<SVGGElement>(".moving-score__boundary");
    if (handle) focusedBoundary = Number(handle.dataset.node);
    const horizontal = event.key === "ArrowLeft" || event.key === "ArrowRight";
    if (focusedBoundary !== null && (target === svg || handle) && horizontal) {
      const info = boundaryInfo(phrase.structure, focusedBoundary);
      if (!info) { focusedBoundary = null; return; }
      controls.boundary(focusedBoundary, clampBoundary(info.ratio + (event.key === "ArrowRight" ? BOUNDARY_STEP : -BOUNDARY_STEP)));
      svg.focus({ preventScroll: true });
      event.preventDefault();
      return;
    }
    const chosen = target.closest<SVGElement>(".moving-score__source-hit, .moving-score__group");
    if (chosen && (event.key === "Enter" || event.key === " ")) {
      controls.select(Number(chosen.dataset.node));
      svg.focus({ preventScroll: true });
      event.preventDefault();
      return;
    }
    if (horizontal) {
      const nodes = phrase.structure.nodes.flatMap((node, index) => node.kind === "group" || node.kind === "atom" ? [index] : []);
      const current = chosen ? Number(chosen.dataset.node) : selected ?? -1;
      const position = Math.max(0, nodes.indexOf(current));
      controls.select(nodes[Math.max(0, Math.min(nodes.length - 1, position + (event.key === "ArrowRight" ? 1 : -1)))]);
      svg.focus({ preventScroll: true });
      event.preventDefault();
    }
  }
  svg.addEventListener("pointerdown", pointerdown);
  svg.addEventListener("pointermove", pointermove);
  svg.addEventListener("pointerup", pointerend);
  svg.addEventListener("pointercancel", pointerend);
  return {
    update(next, docChanged) {
      if (docChanged) focusedBoundary = null;
      phrase = next;
    },
    render(nextWidth, nextSelected) {
      width = nextWidth;
      selected = nextSelected;
      render();
    },
    cancel() { finish(false); focusedBoundary = null; },
    forgetBoundary() { focusedBoundary = null; },
    dragging: () => drag !== null,
    keydown,
    dispose() {
      finish(false);
      svg.removeEventListener("pointerdown", pointerdown);
      svg.removeEventListener("pointermove", pointermove);
      svg.removeEventListener("pointerup", pointerend);
      svg.removeEventListener("pointercancel", pointerend);
    },
  };
}
