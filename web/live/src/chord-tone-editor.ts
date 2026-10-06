import { transposePitch } from "./pitch";
import "./chord-tone-editor.css";

const NS = "http://www.w3.org/2000/svg";
const ROW = 24;
const WIDTH = 320;
function svg<K extends keyof SVGElementTagNameMap>(tag: K, attrs: Record<string, string | number>) {
  const element = document.createElementNS(NS, tag);
  for (const [key, value] of Object.entries(attrs)) element.setAttribute(key, String(value));
  return element;
}

/** The gesture is a preview only; release writes one source edit. */
export function mountChordToneEditor(root: HTMLElement, change: (pitches: readonly number[]) => boolean) {
  root.className = "chord-tones";
  const tools = document.createElement("div");
  tools.className = "chord-tones__tools";
  const button = (label: string, action: () => void) => {
    const result = document.createElement("button");
    result.type = "button";
    result.textContent = label;
    result.addEventListener("click", action);
    tools.append(result);
    return result;
  };
  const whole = button("Move chord", () => { selected = null; render(); });
  whole.className = "chord-tones__whole";
  whole.title = "Drag up or down to move all tones; arrow keys also work";
  const lower = button("Lower", () => move(-1));
  const raise = button("Raise", () => move(1));
  button("Add tone", () => {
    const anchor = selected === null ? pitches.at(-1) ?? 59 : pitches[selected];
    for (let distance = 1; distance <= 128; distance++) {
      for (const pitch of [anchor + distance, anchor - distance]) {
        if (pitch >= 0 && pitch <= 127 && !pitches.includes(pitch)) {
          commit([...pitches, pitch], pitch);
          canvas.focus({ preventScroll: true });
          return;
        }
      }
    }
    message.textContent = "Every MIDI pitch already has a tone.";
  });
  const remove = button("Remove tone", () => removeTone());
  const selection = document.createElement("span");
  selection.className = "chord-tones__selection";
  selection.setAttribute("role", "status");
  const viewport = document.createElement("div");
  viewport.className = "chord-tones__viewport";
  const canvas = svg("svg", { class: "chord-tones__canvas", tabindex: 0, role: "application", "aria-label": "Chord tones. Left and Right select a tone; Up and Down change pitch; Delete removes it. Tap an empty row to add a tone." });
  const lanes = svg("g", { class: "chord-tones__lanes" });
  const marks = svg("g", { class: "chord-tones__marks" });
  canvas.append(lanes, marks);
  viewport.append(canvas);
  const scrollGutter = document.createElement("div");
  scrollGutter.className = "chord-tones__scroll-gutter";
  scrollGutter.setAttribute("aria-hidden", "true");
  viewport.append(scrollGutter);
  const hint = document.createElement("p");
  hint.className = "chord-tones__hint";
  hint.textContent = "Drag a tone · tap an empty row to add";
  const message = document.createElement("span");
  message.className = "chord-tones__message";
  message.setAttribute("role", "status");
  root.append(tools, selection, viewport, hint, message);

  let pitches: readonly number[] = [];
  let spelling = "C4";
  let selected: number | null = null;
  let low = 58, high = 69;
  let doc: unknown;
  let from = -1;
  let disposed = false;
  let gesture: { id: number; y: number; x: number; index: number | null; base: readonly number[]; preview: number[]; add: number | null; moved: boolean } | null = null;
  const name = (pitch: number) => transposePitch(spelling, pitch - (spelling === "Db4" ? 61 : 60)) ?? String(pitch);
  const y = (pitch: number) => (high - pitch) * ROW;

  function render() {
    const values = gesture?.preview ?? pitches;
    marks.replaceChildren();
    for (let index = 0; index < values.length; index++) {
      const pitch = values[index];
      const note = svg("g", { class: `chord-tones__tone${selected === null || selected === index ? " is-selected" : ""}${gesture ? " is-preview" : ""}`, "data-index": index, "data-pitch": pitch, role: "button", "aria-label": name(pitch) });
      note.append(svg("rect", { x: 44, y: y(pitch) + 1, width: WIDTH - 50, height: ROW - 2, rx: 3 }));
      const label = svg("text", { x: 54, y: y(pitch) + 16 });
      label.textContent = name(pitch);
      note.append(label);
      marks.append(note);
    }
    whole.setAttribute("aria-pressed", String(selected === null));
    const target = selected === null ? "whole chord" : name(values[selected] ?? pitches[selected]);
    selection.textContent = values.length ? `Editing ${target}` : "Rest — add a tone below";
    lower.setAttribute("aria-label", `Lower ${target}`);
    raise.setAttribute("aria-label", `Raise ${target}`);
    const movable = selected === null ? values : values.slice(selected, selected + 1);
    lower.disabled = !movable.length || movable.some(pitch => pitch <= 0);
    raise.disabled = !movable.length || movable.some(pitch => pitch >= 127);
    whole.disabled = !values.length;
    remove.disabled = selected === null || !values.length;
  }
  function layout(reference: readonly number[]) {
    low = Math.max(0, Math.min(...(reference.length ? reference : [60])) - 2);
    high = Math.min(127, Math.max(...(reference.length ? reference : [67])) + 2);
    if (high - low < 11) { high = Math.min(127, low + 11); low = Math.max(0, high - 11); }
    const height = (high - low + 1) * ROW;
    canvas.setAttribute("viewBox", `0 0 ${WIDTH} ${height}`);
    canvas.setAttribute("preserveAspectRatio", "none");
    canvas.style.height = `${height}px`;
    scrollGutter.style.height = `${height}px`;
    lanes.replaceChildren();
    for (let pitch = high; pitch >= low; pitch--) {
      const row = svg("rect", { x: 0, y: y(pitch), width: WIDTH, height: ROW, class: `chord-tones__lane${[1, 3, 6, 8, 10].includes(pitch % 12) ? " is-sharp" : ""}`, "data-pitch": pitch });
      const label = svg("text", { x: 5, y: y(pitch) + 16, "aria-hidden": "true" });
      label.textContent = name(pitch);
      lanes.append(row, label);
    }
    render();
  }
  function commit(next: readonly number[], chosen: number | null) {
    if (next.some(pitch => !Number.isInteger(pitch) || pitch < 0 || pitch > 127)) {
      message.textContent = "Keep tones within MIDI 0–127."; render(); return;
    }
    if (new Set(next).size !== next.length) {
      message.textContent = "That pitch already has a tone. Move to an empty row."; render(); return;
    }
    if (next.length === pitches.length && next.every((pitch, index) => pitch === pitches[index])) { render(); return; }
    message.textContent = "";
    const previous = selected;
    const ordered = [...next].sort((a, b) => a - b);
    selected = chosen === null ? null : ordered.indexOf(chosen);
    if (!change(ordered)) selected = previous;
    render();
  }
  function move(delta: number) {
    const next = pitches.map((pitch, index) => selected === null || index === selected ? pitch + delta : pitch);
    commit(next, selected === null ? null : next[selected]);
  }
  function removeTone() {
    if (selected === null) return;
    const next = pitches.filter((_, index) => index !== selected);
    commit(next, next.length ? next[Math.min(selected, next.length - 1)] : null);
  }
  function cancel() {
    if (!gesture) return;
    const id = gesture.id;
    gesture = null;
    if (root.hasPointerCapture(id)) root.releasePointerCapture(id);
    render();
  }
  function onDown(event: PointerEvent) {
    if (disposed || !event.isPrimary || event.button !== 0 || gesture) return;
    const target = event.target instanceof Element ? event.target : null;
    const tone = target?.closest<SVGGElement>(".chord-tones__tone");
    const all = target === whole;
    if (!all && !canvas.contains(target)) return;
    if (all && !pitches.length) return;
    const rect = canvas.getBoundingClientRect();
    const localX = (event.clientX - rect.left) * WIDTH / rect.width;
    if (!all && localX < 44) return; // Gutter remains available for touch scrolling.
    const pitch = Math.max(low, Math.min(high, high - Math.floor((event.clientY - rect.top) / ROW)));
    const index = tone ? Number(tone.dataset.index) : null;
    if (tone || all) selected = index;
    const add = tone || all ? null : pitch;
    gesture = { id: event.pointerId, y: event.clientY, x: event.clientX, index, base: pitches, preview: [...pitches], add, moved: false };
    root.setPointerCapture(event.pointerId);
    if (add === null) {
      event.preventDefault();
      (all ? whole : canvas).focus({ preventScroll: true });
    }
    render();
  }
  function onMove(event: PointerEvent) {
    const active = gesture;
    if (!active || active.id !== event.pointerId) return;
    active.moved ||= Math.hypot(event.clientX - active.x, event.clientY - active.y) > 6;
    if (active.add !== null) return;
    const delta = Math.round((active.y - event.clientY) / ROW);
    active.preview = active.base.map((pitch, index) => active.index === null || active.index === index ? pitch + delta : pitch);
    render();
  }
  function onUp(event: PointerEvent) {
    const active = gesture;
    if (!active || active.id !== event.pointerId) return;
    gesture = null;
    if (root.hasPointerCapture(event.pointerId)) root.releasePointerCapture(event.pointerId);
    if (active.add !== null) {
      if (!active.moved) commit([...pitches, active.add], active.add);
    } else commit(active.preview, active.index === null ? null : active.preview[active.index]);
    render();
  }
  root.addEventListener("pointerdown", onDown);
  root.addEventListener("pointermove", onMove);
  root.addEventListener("pointerup", onUp);
  root.addEventListener("pointercancel", cancel);
  root.addEventListener("lostpointercapture", cancel);
  root.addEventListener("keydown", event => {
    if (event.key === "Escape" && gesture) { cancel(); event.preventDefault(); return; }
    if (event.ctrlKey || event.metaKey || event.altKey || ![canvas, whole].includes(event.target as typeof canvas)) return;
    if (event.key === "ArrowUp" || event.key === "ArrowDown") {
      cancel(); move((event.key === "ArrowUp" ? 1 : -1) * (event.shiftKey ? 12 : 1));
    } else if (event.target === canvas && (event.key === "ArrowLeft" || event.key === "ArrowRight")) {
      if (pitches.length) selected = selected === null ? 0 : Math.max(0, Math.min(pitches.length - 1, selected + (event.key === "ArrowRight" ? 1 : -1)));
      render();
    } else if (event.target === canvas && (event.key === "Delete" || event.key === "Backspace")) removeTone();
    else return;
    event.preventDefault();
  });
  return {
    update(next: readonly number[], seed: readonly number[], nextSpelling: string, nextDoc: unknown, nextFrom: number) {
      const changed = doc !== nextDoc || from !== nextFrom;
      if (changed) cancel();
      if (from !== nextFrom) selected = null;
      doc = nextDoc; from = nextFrom; pitches = next; spelling = nextSpelling;
      if (selected !== null && selected >= pitches.length) selected = pitches.length ? pitches.length - 1 : null;
      message.textContent = "";
      layout(next.length ? next : seed);
    },
    dispose() { disposed = true; cancel(); },
  };
}
