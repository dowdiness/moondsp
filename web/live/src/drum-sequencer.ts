import type { EditorView } from "@codemirror/view";
import type { Pattern } from "./pattern-controls";
import { dispatchPatternEdit } from "./pattern-edit";
import { columnFor, rowFor } from "./roving-focus";
import type { SourceElement, SourceElements } from "./source-elements";
import "./drum-sequencer.css";

const SOUNDS = [
  { name: "bd", label: "Kick" },
  { name: "sd", label: "Snare" },
  { name: "hh", label: "Hi-hat" },
  { name: "oh", label: "Open hat" },
  { name: "cp", label: "Clap" },
] as const;
type Sound = (typeof SOUNDS)[number]["name"];
type Controls = {
  select(index: number): void;
  /** Where the occupied cells are shown as they are drawn. */
  sources: SourceElements;
};

/** The step of the pattern's selected source, or the first step when a group is selected. */
function selectedIndex(pattern: Pattern): number {
  return Math.max(0, pattern.steps?.findIndex(step => step.node === pattern.selectedNode) ?? 0);
}

/** Mount a source-step percussion matrix. Its only musical state is the editor's text. */
export function mountDrumSequencer(
  root: HTMLElement,
  view: EditorView,
  pattern: Pattern,
  controls: Controls,
): { update(pattern: Pattern): void; dispose(): void } {
  const abort = new AbortController();
  const dom = document.createElement("section");
  const shownCells = controls.sources.slot();
  dom.className = "drum-sequencer";
  dom.setAttribute("aria-label", "Percussion source steps");
  const viewport = document.createElement("div");
  viewport.className = "drum-sequencer__viewport";
  viewport.setAttribute("role", "group");
  viewport.setAttribute("aria-label", "Percussion source-step matrix. Arrow keys move between sounds and steps.");
  const matrix = document.createElement("div");
  matrix.className = "drum-sequencer__matrix";
  viewport.append(matrix);
  dom.append(viewport);
  root.append(dom);

  let current = pattern;
  let selected = selectedIndex(pattern);
  let disposed = false;
  let headers: HTMLButtonElement[] = [];
  let headerRow: HTMLDivElement | null = null;
  let empty: HTMLElement | null = null;
  const rows = new Map<Sound, { row: HTMLDivElement; label: HTMLDivElement; cells: HTMLButtonElement[] }>();

  function callSelect(index: number): void {
    if (!current.steps?.length) return;
    const next = Math.max(0, Math.min(current.steps.length - 1, index));
    selected = next;
    controls.select(next);
    renderState();
  }
  function renderState(): void {
    const steps = current.steps;
    const active = dom.ownerDocument.activeElement;
    const focused = active instanceof HTMLButtonElement && dom.contains(active) ? active : null;
    const focusStep = focused && steps?.length ? Math.max(0, Math.min(steps.length - 1, Number(focused.dataset.step))) : selected;
    const focusSound = focused?.dataset.sound as Sound | undefined;
    const focusHeader = focused?.classList.contains("drum-sequencer__step") ?? true;
    const scrollLeft = viewport.scrollLeft;
    if (!steps?.length) {
      matrix.replaceChildren();
      headers = [];
      headerRow = null;
      rows.clear();
      empty = document.createElement("p");
      empty.className = "drum-sequencer__empty";
      empty.textContent = current.reason || "No percussion source steps are available.";
      matrix.append(empty);
      viewport.scrollLeft = scrollLeft;
      shownCells.show([]);
      return;
    }
    if (empty) {
      matrix.replaceChildren();
      empty = null;
    }

    matrix.style.setProperty("--step-count", String(steps.length));
    const stepRow = ensureRow("step", "Source step");
    while (headers.length > steps.length) headers.pop()!.remove();
    for (let index = 0; index < steps.length; index++) {
      let button = headers[index];
      if (!button) {
        button = document.createElement("button");
        button.type = "button";
        button.className = "drum-sequencer__step";
        button.dataset.step = String(index);
        button.addEventListener("click", () => callSelect(index), { signal: abort.signal });
        button.addEventListener("keydown", onHeaderKeyDown, { signal: abort.signal });
        button.addEventListener("focus", () => callSelect(index), { signal: abort.signal });
        stepRow.row.append(button);
        headers.push(button);
      }
      const step = steps[index];
      const occurrences = current.structure?.events.filter(event => event.node === step.node).length ?? 0;
      const weight = Number.isFinite(step.weight) ? step.weight : 1;
      const details = [`weight ${weight}`, ...(occurrences > 1 ? [`repeats ${occurrences} times`] : [])].join(" · ");
      button.textContent = String(index + 1);
      button.title = `Source step ${index + 1} · ${details}`;
      button.setAttribute("aria-label", `Select source step ${index + 1}, ${details}`);
      button.setAttribute("aria-pressed", String(index === selected));
      button.tabIndex = index === selected && focusHeader ? 0 : -1;
      button.classList.toggle("is-selected", index === selected);
    }

    for (const sound of SOUNDS) {
      const row = ensureRow(sound.name, sound.label);
      while (row.cells.length > steps.length) row.cells.pop()!.remove();
      for (let index = 0; index < steps.length; index++) {
        let button = row.cells[index];
        if (!button) {
          button = document.createElement("button");
          button.type = "button";
          button.className = "drum-sequencer__cell";
          button.dataset.sound = sound.name;
          button.dataset.step = String(index);
          button.addEventListener("click", () => edit(index, sound.name), { signal: abort.signal });
          button.addEventListener("focus", () => callSelect(index), { signal: abort.signal });
          button.addEventListener("keydown", onKeyDown, { signal: abort.signal });
          row.row.append(button);
          row.cells.push(button);
        }
        const step = steps[index];
        const occupied = step.value === sound.name;
        button.textContent = "";
        button.setAttribute("aria-label", `${occupied ? `Clear ${sound.label}` : `Set ${sound.label}`} at source step ${index + 1}`);
        button.setAttribute("aria-pressed", String(occupied));
        button.title = `${occupied ? `Clear ${sound.label}` : `Set ${sound.label}`} · source step ${index + 1}`;
        button.classList.toggle("moving-score__source", occupied);
        if (!occupied) button.classList.remove("is-playing");
        button.tabIndex = index === selected && !focusHeader && sound.name === (focusSound ?? currentSoundAt(selected)) ? 0 : -1;
        button.classList.toggle("is-selected-column", index === selected);
      }
    }
    viewport.scrollLeft = scrollLeft;
    shownCells.show(SOUNDS.flatMap(sound => steps.flatMap((step, index): SourceElement[] => step.value === sound.name
      ? [{ element: rows.get(sound.name)!.cells[index], from: step.from, to: step.to, note: null, hint: true }] : [])));
    if (focused) {
      const target = focusHeader ? headers[focusStep] : rows.get(focusSound ?? currentSoundAt(focusStep))?.cells[focusStep];
      if (target && target !== focused) target.focus({ preventScroll: true });
    }
  }
  function ensureRow(key: string, label: string): { row: HTMLDivElement; label: HTMLDivElement; cells: HTMLButtonElement[] } {
    let result = rows.get(key as Sound);
    if (key === "step") {
      if (!headerRow) {
        headerRow = document.createElement("div");
        headerRow.className = "drum-sequencer__row drum-sequencer__header";
        const labelCell = document.createElement("div");
        labelCell.className = "drum-sequencer__sound-label";
        labelCell.textContent = label;
        headerRow.append(labelCell);
        matrix.append(headerRow);
      }
      return { row: headerRow, label: headerRow.firstElementChild as HTMLDivElement, cells: headers };
    }
    if (result) return result;
    const row = document.createElement("div");
    row.className = "drum-sequencer__row";
    row.dataset.sound = key;
    const rowLabel = document.createElement("div");
    rowLabel.className = "drum-sequencer__sound-label";
    rowLabel.textContent = label;
    row.append(rowLabel);
    matrix.append(row);
    result = { row, label: rowLabel, cells: [] };
    rows.set(key as Sound, result);
    return result;
  }
  function currentSoundAt(index: number): Sound {
    const value = current.steps?.[index]?.value;
    return SOUNDS.find(sound => sound.name === value)?.name ?? SOUNDS[0].name;
  }
  function onKeyDown(event: KeyboardEvent): void {
    const target = event.currentTarget;
    if (!(target instanceof HTMLButtonElement)) return;
    if (event.key === "Escape") {
      event.preventDefault();
      view.focus();
      return;
    }
    const rowIndex = SOUNDS.findIndex(sound => sound.name === target.dataset.sound);
    if (rowIndex < 0 || !current.steps?.length) return;
    const column = Number(target.dataset.step);
    const movedColumn = columnFor(event.key, column, current.steps.length);
    const movedRow = rowFor(event.key, rowIndex, SOUNDS.length);
    if (movedColumn === null && movedRow === null) return;
    const nextColumn = movedColumn ?? column, nextRow = movedRow ?? rowIndex;
    event.preventDefault();
    callSelect(nextColumn);
    rows.get(SOUNDS[nextRow].name)?.cells[nextColumn]?.focus();
  }
  function onHeaderKeyDown(event: KeyboardEvent): void {
    const target = event.currentTarget;
    if (!(target instanceof HTMLButtonElement) || !current.steps?.length) return;
    if (event.key === "Escape") {
      event.preventDefault();
      view.focus();
      return;
    }
    const column = Number(target.dataset.step);
    if (event.key === "ArrowDown") {
      event.preventDefault();
      rows.get(SOUNDS[0].name)?.cells[column]?.focus();
      return;
    }
    const nextColumn = columnFor(event.key, column, current.steps.length);
    if (nextColumn === null) return;
    event.preventDefault();
    callSelect(nextColumn);
    headers[nextColumn]?.focus();
  }
  function edit(index: number, sound: Sound): void {
    const step = current.steps?.[index];
    if (!step || current.doc !== view.state.doc) return;
    const next = step.value === sound ? "~" : sound;
    const anchor = dom.ownerDocument.activeElement instanceof HTMLButtonElement ? dom.ownerDocument.activeElement : null;
    dispatchPatternEdit(view, { changes: [{ from: step.from, to: step.to, insert: next }], selection: { from: step.from, to: step.from + next.length } });
    callSelect(index);
    const cell = rows.get(sound)?.cells[index];
    if (anchor && cell && !cell.matches(":focus")) cell.focus({ preventScroll: true });
  }

  // All matrix cells share this key handler; headers remain select-only controls.
  renderState();
  return {
    update(nextPattern) {
      if (disposed) return;
      current = nextPattern;
      selected = selectedIndex(current);
      renderState();
    },
    dispose() {
      if (disposed) return;
      disposed = true;
      abort.abort();
      shownCells.dispose();
      dom.remove();
      headers = [];
      rows.clear();
    },
  };
}
