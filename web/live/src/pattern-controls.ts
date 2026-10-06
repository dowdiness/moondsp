import { EditorState, Facet, MapMode, StateField, Transaction, type ChangeDesc, type Extension, type Text } from "@codemirror/state";
import { isolateHistory, historyKeymap } from "@codemirror/commands";
import { Decoration, EditorView, WidgetType, keymap, runScopeHandlers, type DecorationSet } from "@codemirror/view";
import type { SyntaxNode } from "@lezer/common";
import { miniliveLanguage } from "./lang/minilive";
import { midiValue, transposePitch } from "./pitch";
import { mountMovingScore } from "./moving-score";
import { mountChordControls } from "./chord-controls";
import {
  projectNotation, leafNodes, splitNode, repeatNode, weightNode, moveBoundary, boundaryInfo, sourceRangeNodes,
  type NotationProjection, type SourceChange,
} from "./notation-structure";

type PatternMemory = { pitchOpen?: boolean; timingOpen?: boolean; structureOpen?: boolean; tonesOpen?: boolean };

export const patternControlsVisible = Facet.define<boolean, boolean>({
  combine: values => values[0] ?? true,
});

type Kind = "drum" | "note";
type Step = { from: number; to: number; end: number; value: string; rest: boolean; weight: number; node: number };
type TimingValue = { from: number; to: number; value: number };
type PhraseTiming = { slow: TimingValue | null; gate: TimingValue | null; ambiguous: Set<string> };
export type Pattern = {
  from: number; to: number; kind: Kind; notationKind: "note" | "drum" | "chord"; name: string;
  steps: Step[] | null; reason: string; doc: Text; cursor: number;
  selectionFrom: number; selectionTo: number;
  contentFrom: number; contentTo: number; structure: NotationProjection | null; selectedNode: number | null;
  timing: PhraseTiming;
};

function parentNamed(node: SyntaxNode, name: string): SyntaxNode | null {
  for (let parent = node.parent; parent; parent = parent.parent) if (parent.name === name) return parent;
  return null;
}

export function sourcePatterns(state: EditorState): Pattern[] {
  const source = state.doc.toString();
  const tree = miniliveLanguage.parser.parse(source);
  const patterns: Pattern[] = [];
  tree.iterate({ enter(ref) {
    if (ref.name !== "Chain") return;
    const call = ref.node.getChild("Call");
    if (!call) return;
    const nameNode = call.getChild("CallName");
    const callName = nameNode ? source.slice(nameNode.from, nameNode.to) : "";
    if (!["s", "note", "chord"].includes(callName)) return;
    let broken = false;
    call.toTree().iterate({ enter(node) { if (node.type.isError) broken = true; } });
    if (broken) return;
    const args = call.getChild("Args");
    if (!args) return;
    const values: SyntaxNode[] = [];
    for (let child = args.firstChild; child; child = child.nextSibling) {
      if (child.name !== "LineComment" && child.name !== "BlockComment") values.push(child);
    }
    if (values.length !== 3 || values[0].name !== "(" || values[1].name !== "String" || values[2].name !== ")") return;
    const string = values[1];
    const literal = source.slice(string.from, string.to);
    if (literal.length < 2 || literal[0] !== '"' || literal.at(-1) !== '"') return;
    const content = literal.slice(1, -1);
    const notationKind = callName === "s" ? "drum" : callName as "note" | "chord";
    const kind: Kind = notationKind === "drum" ? "drum" : "note";
    const structure = projectNotation(notationKind, content);
    const contentFrom = string.from + 1, contentTo = string.to - 1;
    const reason = structure.error ?? "";
    const steps: Step[] | null = structure.error ? null : leafNodes(structure).map(node => {
      const item = structure.nodes[node];
      return { from: contentFrom + item.from, to: contentFrom + item.baseTo, end: contentFrom + item.end,
        value: item.value, rest: item.value === "~", weight: item.weight, node };
    });
    const selection = state.selection.main;
    const selectedNode = structure.nodes.map((node, index) => ({ node, index }))
      .filter(({ node }) => (node.kind === "atom" || node.kind === "group") &&
        selection.from >= contentFrom + node.from && selection.to <= contentFrom + node.end)
      .sort((a, b) => (a.node.end - a.node.from) - (b.node.end - b.node.from))[0]?.index
      ?? steps?.[0]?.node ?? null;
    const timing: PhraseTiming = { slow: null, gate: null, ambiguous: new Set() };
    for (const member of ref.node.getChildren("MemberCall")) {
      const method = member.getChild("MethodName");
      const name = method && source.slice(method.from, method.to);
      if (name !== "slow" && name !== "gate") continue;
      const args = member.getChild("Args"), number = args?.getChild("Number");
      if (!number || timing[name]) { timing.ambiguous.add(name); continue; }
      const value = Number(source.slice(number.from, number.to));
      if (!Number.isFinite(value)) { timing.ambiguous.add(name); continue; }
      timing[name] = { from: number.from, to: number.to, value };
    }
    let binding = "";
    const bindingNode = parentNamed(ref.node, "Binding");
    const bindingName = bindingNode?.getChild("BindingName");
    if (bindingName) binding = source.slice(bindingName.from, bindingName.to);
    const end = ref.node.to;
    patterns.push({ from: ref.node.from, to: end, kind, notationKind, name: binding, steps, reason,
      doc: state.doc, cursor: state.selection.main.head, selectionFrom: selection.from, selectionTo: selection.to,
      contentFrom, contentTo, structure, selectedNode, timing });
  } });
  const totals = new Map<Kind, number>();
  for (const pattern of patterns) totals.set(pattern.kind, (totals.get(pattern.kind) ?? 0) + 1);
  const seen = new Map<Kind, number>();
  for (const pattern of patterns) {
    const index = (seen.get(pattern.kind) ?? 0) + 1;
    seen.set(pattern.kind, index);
    if ((totals.get(pattern.kind) ?? 0) > 1) pattern.name = pattern.name ? `${pattern.name} · ${index}` : String(index);
  }
  return patterns;
}

export function canAppendMelody(state: EditorState): boolean {
  const source = state.doc.toString();
  return source.trim().length === 0 || miniliveLanguage.parser.parse(source).topNode.getChild("DollarStack") !== null;
}

export function appendMelody(view: EditorView): void {
  if (!canAppendMelody(view.state)) return;
  const doc = view.state.doc;
  const separator = doc.length === 0 || doc.sliceString(doc.length - 1) === "\n" ? "" : "\n";
  const notes = "C4 Eb4 F4 G4 Bb4 G4 F4 Eb4";
  const source = `${separator}$: note("${notes}").slow(6).gain(0.12).lpf(1600).pan(0.35)`;
  view.dispatch({
    changes: { from: doc.length, insert: source },
    selection: { anchor: doc.length + separator.length + 9 },
    annotations: isolateHistory.of("full"),
    scrollIntoView: true,
  });
  view.focus();
}

const liveWidgets = new WeakMap<HTMLElement, PatternWidgetDOM>();
class PatternWidgetDOM {
  readonly dom = document.createElement("section");
  private label = "";
  private unavailable = document.createElement("span");
  private grid = document.createElement("div");
  private cells: HTMLElement[] = [];
  private selected = 0;
  private choices: HTMLButtonElement[] = [];
  private keyboard = document.createElement("div");
  private keys: HTMLButtonElement[] = [];
  private octave = 4;
  private octaveControls = document.createElement("div");
  private octaveLabel = document.createElement("span");
  private octaveDown = this.button("−", "octave-down", () => this.showOctave(-1));
  private octaveUp = this.button("+", "octave-up", () => this.showOctave(1));
  private rest = this.button("Rest", "step-rest", () => this.toggleRest());
  private feedback = document.createElement("span");
  private properties = document.createElement("div");
  private selectionLabel = document.createElement("span");
  private length = document.createElement("input");
  private repeat = document.createElement("input");
  private share = document.createElement("input");
  private shareLabel = document.createElement("label");
  private split = this.button("Split", "structure-split", () => this.editStructure("split"));
  private scope = document.createElement("span");
  private stretch = document.createElement("input");
  private gate = document.createElement("input");
  private timingDetails = document.createElement("details");
  private melody?: ReturnType<typeof mountMovingScore>;
  private pitchDetails?: HTMLDetailsElement;
  private phraseUpdate = document.createElement("p");
  private chordControls?: ReturnType<typeof mountChordControls>;

  private button(label: string, className: string, action: (event: MouseEvent) => void): HTMLButtonElement {
    const button = document.createElement("button");
    button.type = "button";
    button.className = className;
    button.textContent = label;
    button.addEventListener("click", action);
    return button;
  }

  constructor(private view: EditorView, private pattern: Pattern, readonly memory: PatternMemory) {
    this.dom.className = "score-pattern cm-score-pattern";
    this.dom.dataset.kind = pattern.kind;
    this.dom.dataset.patternStart = String(pattern.from);
    this.dom.contentEditable = "false";
    this.dom.setAttribute("aria-description", "Select a note or group. Structural edits change its source, including every linked repetition.");
    this.unavailable.className = "pattern-unavailable";
    this.unavailable.textContent = "Edit in code";
    this.grid.className = "step-grid";
    this.keyboard.className = "pitch-keyboard";
    this.keyboard.setAttribute("role", "group");
    this.octaveControls.className = "octave-controls";
    this.octaveDown.setAttribute("aria-label", "Show lower octave");
    this.octaveUp.setAttribute("aria-label", "Show higher octave");
    this.octaveControls.append(this.octaveDown, this.octaveLabel, this.octaveUp);
    // DOM order follows pitch, while grid placement retains the familiar key layout.
    const columns = [1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13];
    for (let pitch = 0; pitch < 12; pitch++) {
      const key = this.button("", "pitch-key", () => this.choosePitch(pitch));
      key.dataset.pitch = String(pitch);
      key.dataset.accidental = String([1, 3, 6, 8, 10].includes(pitch));
      key.style.gridColumn = `${columns[pitch]} / span 2`;
      this.keys.push(key);
      this.keyboard.append(key);
    }
    this.feedback.className = "step-feedback";
    this.feedback.setAttribute("role", "status");
    this.properties.className = "note-properties";
    this.properties.setAttribute("role", "group");
    this.properties.setAttribute("aria-label", "Selected step");
    this.selectionLabel.className = "note-selection";
    this.scope.className = "structure-scope";
    const lengthLabel = this.numberControl(this.length, "Weight", "Relative weight", 1, 16, 1,
      () => this.editStructure("weight", this.length.valueAsNumber));
    const repeatLabel = this.numberControl(this.repeat, "Repeat", "Repeat selected source", 1, 16, 1,
      () => this.editStructure("repeat", this.repeat.valueAsNumber));
    this.share.type = "range";
    this.share.min = "0.05"; this.share.max = "0.95"; this.share.step = "0.05";
    this.share.setAttribute("aria-label", "Share with next step");
    this.share.addEventListener("change", () => this.changeBoundary(this.pattern.selectedNode, this.share.valueAsNumber));
    this.shareLabel.className = "structure-share";
    this.shareLabel.append("Share ", this.share);
    this.properties.append(this.selectionLabel, this.scope, this.rest, this.feedback);
    this.timingDetails.className = "structure-timing";
    this.timingDetails.open = memory.timingOpen ?? false;
    const timingSummary = document.createElement("summary");
    timingSummary.textContent = "Timing";
    const timingFields = document.createElement("div");
    timingFields.className = "note-properties";
    timingFields.append(lengthLabel,
      this.numberControl(this.stretch, "Phrase stretch", "Phrase stretch factor", 0.001, 16, 0.25,
        () => this.changeTiming("slow", this.stretch.valueAsNumber)),
      this.numberControl(this.gate, "Phrase gate", "Phrase gate fraction", 0, 1, 0.05,
        () => this.changeTiming("gate", this.gate.valueAsNumber)));
    this.timingDetails.append(timingSummary, timingFields);
    this.timingDetails.addEventListener("toggle", () => {
      memory.timingOpen = this.timingDetails.open; this.view.requestMeasure();
    });
    this.dom.append(this.grid, this.octaveControls, this.keyboard, this.properties, this.timingDetails, this.unavailable);
    this.phraseUpdate.className = "phrase-update";
    this.phraseUpdate.setAttribute("role", "status");
    this.phraseUpdate.hidden = true;
    this.dom.prepend(this.phraseUpdate);
    const drawing = document.createElement("div");
    this.dom.prepend(drawing);
    this.melody = mountMovingScore(drawing, view, pattern, {
      select: index => this.selectStep(index, true),
      selectNode: node => this.selectNode(node),
      boundary: (node, ratio) => this.changeBoundary(node, ratio),
      clear: () => this.toggleRest(),
      structureOpen: memory.structureOpen ?? false,
      structureChanged: open => { memory.structureOpen = open; this.view.requestMeasure(); },
      tonesOpen: memory.tonesOpen ?? false,
      tonesChanged: open => { memory.tonesOpen = open; this.view.requestMeasure(); },
    });
    this.melody.selectionTools.append(this.properties);
    this.melody.structureTools.append(this.split, repeatLabel, this.shareLabel);
    if (pattern.notationKind === "note") {
      const details = document.createElement("details");
      details.className = "pattern-pitch-editor";
      details.open = memory.pitchOpen ?? false;
      const summary = document.createElement("summary");
      summary.textContent = "Pitch controls";
      details.append(summary, this.grid, this.octaveControls, this.keyboard);
      details.addEventListener("toggle", () => {
        if (!details.isConnected) return;
        memory.pitchOpen = details.open;
        this.view.requestMeasure();
      });
      this.pitchDetails = details;
      this.dom.append(details);
      this.choices = this.keys;
    } else if (pattern.notationKind === "chord") {
      const controls = document.createElement("div");
      this.chordControls = mountChordControls(controls, value => {
        const step = this.pattern.steps?.[this.selected];
        if (!step || this.view.state.doc !== this.pattern.doc) return false;
        const { doc, contentFrom, contentTo } = this.pattern;
        const candidate = doc.sliceString(contentFrom, step.from) + value + doc.sliceString(step.to, contentTo);
        const projection = projectNotation("chord", candidate);
        if (projection.error) {
          this.feedback.textContent = projection.error;
          this.view.requestMeasure();
          return false;
        }
        this.apply(step, value);
        return true;
      }, () => this.view.requestMeasure());
      const editor = document.createElement("div");
      editor.className = "chord-editor";
      editor.append(this.grid, controls, this.properties);
      this.dom.insertBefore(editor, drawing);
    }
    this.dom.addEventListener("focusin", event => {
      const target = event.target;
      const cell = target instanceof HTMLElement ? target.closest<HTMLElement>(".step-cell") : null;
      if (cell) {
        const next = this.cells.indexOf(cell);
        if (next !== this.selected) this.feedback.textContent = "";
        this.selectStep(next, this.pattern.notationKind === "chord");
      } else if (target instanceof HTMLButtonElement) {
        const buttons = this.choices.includes(target) ? this.choices : [];
        buttons.forEach(button => { button.tabIndex = button === target ? 0 : -1; });
      }
    });
    // Share explicit commands and focus return here; leave native control keys
    // outside the editor keymap, as with the inline knobs.
    this.dom.addEventListener("keydown", event => {
      if (event.defaultPrevented) return;
      if (event.target instanceof HTMLInputElement) {
        if (event.key === "Enter" && !event.ctrlKey && !event.metaKey) {
          event.preventDefault();
          event.target.dispatchEvent(new Event("change"));
          return;
        }
        if (event.key === "Escape") this.renderTools();
        else if (!(event.key === "Enter" && (event.ctrlKey || event.metaKey))) return;
      }
      if (runScopeHandlers(this.view, event, "pattern-control")) {
        event.preventDefault();
      } else if (event.key === "Escape") {
        event.preventDefault();
        this.view.focus();
      } else if (event.target instanceof HTMLElement && event.target.classList.contains("step-pad") &&
          (event.key === "ArrowUp" || event.key === "ArrowDown")) {
        event.preventDefault();
        this.transpose((event.key === "ArrowUp" ? 1 : -1) * (event.shiftKey ? 12 : 1));
      } else if (event.target instanceof HTMLButtonElement &&
          ["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) {
        const target = event.target;
        const buttons = this.choices.includes(target) ? this.choices.filter(button => !button.disabled)
          : target.classList.contains("step-pad") ? this.cells.map(cell => cell.querySelector<HTMLButtonElement>(".step-pad")!)
          : [];
        if (buttons.length) {
          event.preventDefault();
          const current = buttons.indexOf(target);
          const next = event.key === "Home" ? 0 : event.key === "End" ? buttons.length - 1
            : Math.max(0, Math.min(buttons.length - 1, current + (event.key === "ArrowRight" ? 1 : -1)));
          buttons.forEach((button, index) => { button.tabIndex = index === next ? 0 : -1; });
          buttons[next].focus();
        }
      }
    });
    liveWidgets.set(this.dom, this);
    this.update(pattern);
  }

  update(pattern: Pattern): void {
    if (pattern.doc !== this.pattern.doc || pattern.from !== this.pattern.from ||
        (pattern.cursor !== this.pattern.cursor && !this.dom.contains(document.activeElement))) {
      this.feedback.textContent = "";
    }
    if (pattern.cursor !== this.pattern.cursor || !this.dom.contains(document.activeElement)) {
      this.selected = pattern.steps?.findIndex(step => step.node === pattern.selectedNode) ?? -1;
    } else {
      const old = this.pattern.structure?.nodes[this.pattern.selectedNode ?? -1];
      const retained = old && pattern.structure?.nodes.findIndex(node => node.from === old.from && node.kind === old.kind);
      if (retained !== undefined && retained >= 0) pattern = { ...pattern, selectedNode: retained };
      this.selected = pattern.steps?.findIndex(step => step.node === pattern.selectedNode) ?? -1;
    }
    this.pattern = pattern;
    this.dom.dataset.kind = pattern.kind;
    this.dom.dataset.notationKind = pattern.notationKind;
    this.dom.dataset.patternStart = String(pattern.from);
    this.dom.dataset.patternEnd = String(pattern.to);
    this.dom.dataset.contentFrom = String(pattern.contentFrom);
    this.dom.dataset.contentTo = String(pattern.contentTo);
    this.render();
  }

  private render(): void {
    const { kind, name, steps } = this.pattern;
    this.label = `${kind === "drum" ? "Drums" : this.pattern.notationKind === "chord" ? "Chords" : "Melody"}${name ? ` · ${name}` : ""}`;
    this.unavailable.hidden = !!steps;
    this.properties.hidden = !steps;
    this.timingDetails.hidden = !steps;
    if (this.pitchDetails) this.pitchDetails.hidden = !steps || this.selected < 0;
    this.melody?.update(this.pattern, this.selected);
    this.grid.hidden = !steps || kind === "drum";
    this.keyboard.hidden = !steps || this.pattern.notationKind !== "note" || this.selected < 0;
    this.octaveControls.hidden = !steps || this.pattern.notationKind !== "note" || this.selected < 0;
    if (!steps) {
      this.chordControls?.update(null, "", this.pattern.doc, -1);
      this.unavailable.textContent = this.pattern.reason || "Edit in code";
      this.grid.replaceChildren();
      this.cells = [];
      this.dom.setAttribute("aria-label", this.pattern.reason);
      this.dom.title = this.pattern.reason;
      return;
    }
    this.dom.removeAttribute("aria-label");
    this.dom.title = "";
    const cellSteps = kind === "drum" ? [] : steps;
    while (this.cells.length > cellSteps.length) this.cells.pop()!.remove();
    for (let index = 0; index < cellSteps.length; index++) {
      const step = cellSteps[index];
      let cell = this.cells[index];
      if (!cell) {
        cell = this.makeCell(index);
        this.cells.push(cell);
        this.grid.append(cell);
      }
      this.updateCell(cell, step, index);
    }
    this.selected = Math.min(this.selected, steps.length - 1);
    this.renderTools();
  }

  private makeCell(index: number): HTMLElement {
    const cell = document.createElement("div");
    cell.className = "step-cell";
    const pad = document.createElement("button");
    pad.type = "button";
    pad.className = "step-pad";
    const number = document.createElement("span");
    number.className = "step-index";
    number.textContent = String(index + 1);
    const value = document.createElement("span");
    value.className = "step-note";
    pad.append(number, value);
    cell.append(pad);
    pad.addEventListener("click", () => this.selectStep(index, this.pattern.notationKind === "chord"));
    return cell;
  }

  private updateCell(cell: HTMLElement, step: Step, index: number): void {
    const pad = cell.querySelector<HTMLButtonElement>(".step-pad")!;
    const voice = step.rest ? "Rest" : step.value;
    pad.setAttribute("aria-label", `Select ${voice}, ${this.label}, step ${index + 1}`);
    pad.title = `${voice}, step ${index + 1}`;
    pad.querySelector<HTMLElement>(".step-note")!.textContent = voice;
    if (this.pattern.notationKind === "chord") {
      pad.dataset.from = String(step.from);
      pad.dataset.to = String(step.to);
    }
  }

  private apply(step: Step, value: string): void {
    if (value === step.value || !this.dom.isConnected || this.view.state.doc !== this.pattern.doc ||
      step.from < 0 || step.to > this.view.state.doc.length ||
      this.view.state.doc.sliceString(step.from, step.to) !== step.value) return;
    const active = document.activeElement;
    const root = active instanceof HTMLElement ? active.closest<HTMLElement>(".cm-score-pattern") : null;
    const focusedClass = root === this.dom && active instanceof HTMLElement && active.classList.contains("step-pad")
      ? "step-pad" : "";
    const index = this.pattern.steps?.indexOf(step) ?? -1;
    this.view.dispatch({
      changes: { from: step.from, to: step.to, insert: value },
      annotations: [Transaction.userEvent.of("input.type.pattern"), isolateHistory.of("full")],
    });
    if (focusedClass && document.activeElement !== active) {
      const selector = `.cm-score-pattern[data-pattern-start="${this.pattern.from}"][data-kind="${this.pattern.kind}"] .step-cell:nth-child(${index + 1}) .${focusedClass}`;
      this.view.dom.querySelector<HTMLElement>(selector)?.focus({ preventScroll: true });
    }
  }

  private selectStep(index: number, moveCursor = false): void {
    const step = this.pattern.steps?.[index];
    if (!step) return;
    this.selected = index;
    this.pattern = { ...this.pattern, selectedNode: step.node };
    // Chord pads and drawing target source atoms; note pads retain text ranges.
    if (moveCursor) this.view.dispatch({ selection: { anchor: step.from } });
    this.renderTools();
    this.melody?.update(this.pattern, index);
  }
  private renderTools(): void {
    const step = this.pattern.steps?.[this.selected];
    const node = this.pattern.structure?.nodes[this.pattern.selectedNode ?? -1];
    const parent = node?.parent === null ? null : this.pattern.structure?.nodes[node?.parent ?? -1];
    const siblings = parent?.kind === "sequence" ? parent.children : [];
    const total = siblings.reduce((sum, index) => sum + (this.pattern.structure?.nodes[index].weight ?? 1), 0);
    this.selectionLabel.textContent = node?.kind === "group" ? "Group" : step?.rest ? "Rest" : step?.value ?? "";
    const selectedRange = this.pattern.structure ? sourceRangeNodes(this.pattern.structure,
      this.pattern.selectionFrom - this.pattern.contentFrom, this.pattern.selectionTo - this.pattern.contentFrom) : [];
    const multiple = selectedRange.length > 1;
    const unsupportedSelection = this.pattern.selectionTo > this.pattern.selectionFrom && !selectedRange.length;
    this.selectionLabel.hidden = this.pattern.notationKind === "chord" && !!step && !multiple && !unsupportedSelection;
    if (multiple) this.selectionLabel.textContent = `${selectedRange.length} source steps`;
    this.length.value = String(node?.weight ?? 1);
    this.length.max = String(Math.min(16, 256 - total + (node?.weight ?? 1)));
    this.length.disabled = unsupportedSelection || multiple || !node || node.modifiers.filter(m => m.kind === "weight").length > 1;
    this.length.title = "Relative share within the parent group; changes the other shares too";
    const repeats = node?.modifiers.filter(m => m.kind === "repeat") ?? [];
    this.repeat.value = String(repeats.at(-1)?.value ?? 1);
    this.repeat.disabled = unsupportedSelection || multiple || !node || repeats.length > 1 || !!node.modifiers.some(m => ["slow", "euclid", "degrade"].includes(m.kind));
    this.repeat.title = this.repeat.disabled ? "Edit this combination of transforms in code" : "Repeat the selected source, not a single performed occurrence";
    this.split.disabled = unsupportedSelection || multiple || node?.kind !== "atom";
    const boundary = this.pattern.structure && this.pattern.selectedNode !== null
      ? boundaryInfo(this.pattern.structure, this.pattern.selectedNode) : null;
    this.shareLabel.hidden = unsupportedSelection || multiple || !boundary;
    this.share.value = String(boundary?.ratio ?? 0.5);
    this.share.setAttribute("aria-valuetext", `${Math.round((boundary?.ratio ?? 0.5) * 100)}% of the pair`);
    this.share.title = "Move the boundary with the next sibling; keep all other boundaries fixed";
    const projection = this.pattern.structure;
    const events = projection?.events.filter(event => event.node === this.pattern.selectedNode) ?? [];
    const occurrences = (this.pattern.notationKind === "chord" ? new Set(events.map(event => event.start)).size : events.length) +
      (projection?.rests.filter(event => event.node === this.pattern.selectedNode).length ?? 0);
    const linkedKind = step?.rest ? "rests" : this.pattern.kind === "drum" ? "hits" : this.pattern.notationKind === "chord" ? "chords" : "notes";
    this.scope.textContent = occurrences > 1 ? `${occurrences} linked ${linkedKind}` : node?.kind === "group" ? "Edits apply to this group" : "";
    if (multiple) this.scope.textContent = "";
    if (unsupportedSelection) {
      this.selectionLabel.textContent = "Source selection";
      this.scope.textContent = "Select complete steps within one sequence";
    }
    this.stretch.value = String(this.pattern.timing.slow?.value ?? 1);
    this.gate.value = String(this.pattern.timing.gate?.value ?? 1);
    this.stretch.disabled = this.pattern.timing.ambiguous.has("slow");
    this.gate.disabled = this.pattern.timing.ambiguous.has("gate");
    this.stretch.title = this.stretch.disabled ? "Multiple slow transforms: edit in code" : "Time scale of this source phrase; explicit envelope seconds are unchanged";
    this.gate.title = this.gate.disabled ? "Multiple gate transforms: edit in code" : "All events in this phrase; an explicit hold uses seconds instead";
    this.cells.forEach((cell, index) => {
      cell.classList.toggle("is-selected", index === this.selected);
      const pad = cell.querySelector<HTMLButtonElement>(".step-pad")!;
      pad.setAttribute("aria-pressed", String(index === this.selected));
      pad.tabIndex = index === this.selected ? 0 : -1;
    });
    if (this.pitchDetails) this.pitchDetails.hidden = unsupportedSelection || multiple || this.selected < 0;
    this.octaveControls.hidden = this.pattern.notationKind !== "note" || this.selected < 0;
    this.keyboard.hidden = this.pattern.notationKind !== "note" || this.selected < 0;
    const canAdd = !multiple && !!step?.rest && this.pattern.kind === "note";
    const rangeFrom = selectedRange.length ? this.pattern.structure!.nodes[selectedRange[0]].from + this.pattern.contentFrom : 0;
    const rangeTo = selectedRange.length ? this.pattern.structure!.nodes[selectedRange.at(-1)!].end + this.pattern.contentFrom : 0;
    this.rest.disabled = multiple || node?.kind === "group"
      ? !this.pattern.steps?.some(item => !item.rest && item.from >= rangeFrom && item.to <= rangeTo)
      : !step || (step.rest && !canAdd);
    if (unsupportedSelection) this.rest.disabled = true;
    this.rest.textContent = canAdd ? this.pattern.notationKind === "chord" ? "Add chord" : "Add note" : "Rest";
    this.rest.title = canAdd ? `Place ${this.restValue()} here, keeping its timing` : "Replace selected sounds with rests, preserving their timing";
    const parsed = step && midiValue(step.value);
    if (parsed) this.octave = Math.floor(parsed.midi / 12) - 1;
    this.renderKeyboard();
    this.chordControls?.update(!unsupportedSelection && !multiple && step ? step.value : null, this.restValue(), this.pattern.doc, step?.from ?? -1);
  }

  private showOctave(delta: number): void {
    this.octave = Math.max(-1, Math.min(9, this.octave + delta));
    this.renderKeyboard();
  }

  private renderKeyboard(): void {
    if (this.pattern.notationKind !== "note") return;
    const step = this.pattern.steps?.[this.selected];
    const parsed = step && midiValue(step.value);
    const base = (this.octave + 1) * 12;
    this.octaveLabel.textContent = `Octave ${this.octave}`;
    this.octaveDown.disabled = this.octave === -1;
    this.octaveUp.disabled = this.octave === 9;
    this.keyboard.setAttribute("aria-label", `Change pitch for ${this.label}, step ${this.selected + 1}`);
    const selectedPitch = parsed && Math.floor(parsed.midi / 12) - 1 === this.octave ? parsed.midi % 12 : 0;
    this.keys.forEach((key, pitch) => {
      const midi = base + pitch;
      const name = transposePitch(parsed?.flat ? "Db4" : "C4", pitch - (parsed?.flat ? 1 : 0))!
        .replace(/\d+$/, String(this.octave));
      key.disabled = midi > 127;
      key.textContent = name.replace(/-?\d+$/, "");
      key.setAttribute("aria-label", `Set ${name}`);
      key.setAttribute("aria-pressed", String(parsed?.midi === midi));
      key.tabIndex = pitch === selectedPitch ? 0 : -1;
    });
  }

  private choosePitch(pitch: number): void {
    const step = this.pattern.steps?.[this.selected];
    if (!step) return;
    const target = (this.octave + 1) * 12 + pitch;
    const parsed = midiValue(step.value);
    // Keep numeric/flat spelling; pressing the current key must not rewrite the atom.
    const value = parsed ? (parsed.midi === target ? step.value : transposePitch(step.value, target - parsed.midi))
      : transposePitch("C-1", target);
    if (value !== null) this.choose(value);
  }

  private transpose(semitones: number): void {
    const step = this.pattern.steps?.[this.selected];
    if (!step || this.pattern.notationKind !== "note") return;
    const value = transposePitch(step.value, semitones);
    if (value === null) return;
    this.apply(step, value);
  }

  private numberControl(input: HTMLInputElement, text: string, name: string,
    min: number, max: number, step: number, commit: () => void): HTMLLabelElement {
    const label = document.createElement("label");
    input.type = "number";
    input.min = String(min); input.max = String(max); input.step = String(step);
    input.setAttribute("aria-label", name);
    input.addEventListener("change", commit);
    label.append(`${text} `, input);
    return label;
  }

  private selectNode(index: number): void {
    const node = this.pattern.structure?.nodes[index];
    if (!node) return;
    this.pattern = { ...this.pattern, selectedNode: index };
    this.selected = this.pattern.steps?.findIndex(step => step.node === index) ?? -1;
    this.view.dispatch({ selection: {
      anchor: this.pattern.contentFrom + node.from, head: this.pattern.contentFrom + node.baseTo,
    } });
    this.renderTools();
    this.melody?.update(this.pattern, this.selected);
  }

  private commitStructure(changes: SourceChange[], nodeIndex: number): void {
    if (!changes.length || this.view.state.doc !== this.pattern.doc || !this.dom.isConnected) return;
    const node = this.pattern.structure?.nodes[nodeIndex];
    if (!node) return;
    const offset = this.pattern.contentFrom;
    const absolute = changes
      .filter(change => this.pattern.doc.sliceString(change.from + offset, change.to + offset) !== change.insert)
      .map(change => ({ ...change, from: change.from + offset, to: change.to + offset }));
    if (!absolute.length) return;
    const changeSet = this.view.state.changes(absolute);
    this.feedback.textContent = "";
    this.view.dispatch({
      changes: changeSet,
      selection: { anchor: changeSet.mapPos(offset + node.from, -1), head: changeSet.mapPos(offset + node.baseTo, 1) },
      annotations: [Transaction.userEvent.of("input.type.pattern"), isolateHistory.of("full")],
    });
  }

  private editStructure(operation: "split" | "repeat" | "weight", value = 0): void {
    const { structure, selectedNode, contentFrom, contentTo, doc } = this.pattern;
    if (!structure || selectedNode === null || this.view.state.doc !== doc) return;
    try {
      const content = doc.sliceString(contentFrom, contentTo);
      const changes = operation === "split" ? splitNode(content, structure, selectedNode)
        : operation === "repeat" ? repeatNode(content, structure, selectedNode, value)
        : weightNode(content, structure, selectedNode, value);
      this.commitStructure(changes, selectedNode);
    } catch (error) {
      this.renderTools();
      this.feedback.textContent = error instanceof Error ? error.message : "Cannot edit this structure.";
      this.view.requestMeasure();
    }
  }

  private changeBoundary(node: number | null, ratio: number): void {
    const { structure, doc, contentFrom, contentTo } = this.pattern;
    if (!structure || node === null || this.view.state.doc !== doc) return;
    try {
      this.commitStructure(moveBoundary(doc.sliceString(contentFrom, contentTo), structure, node, ratio), node);
    } catch (error) {
      this.renderTools();
      this.feedback.textContent = error instanceof Error ? error.message : "Cannot move this boundary.";
      this.view.requestMeasure();
    }
  }

  private changeTiming(kind: "slow" | "gate", value: number): void {
    const { timing, doc, to } = this.pattern;
    if (this.view.state.doc !== doc || timing.ambiguous.has(kind)) return;
    if (!Number.isFinite(value) || (kind === "slow" ? value < 0.001 || value > 16 : value < 0 || value > 1)) {
      this.renderTools();
      this.feedback.textContent = kind === "slow" ? "Stretch must be between 0.001 and 16." : "Gate must be between 0 and 1.";
      return;
    }
    const current = timing[kind];
    if (value === (current?.value ?? 1)) return;
    this.view.dispatch({
      changes: current ? { from: current.from, to: current.to, insert: String(value) }
        : { from: to, insert: `.${kind}(${value})` },
      annotations: [Transaction.userEvent.of("input.type.pattern"), isolateHistory.of("full")],
    });
  }

  destroy(): void {
    this.melody?.dispose();
    this.chordControls?.dispose();
  }

  private restValue(): string {
    const steps = this.pattern.steps ?? [];
    for (let index = this.selected - 1; index >= 0; index--)
      if (!steps[index].rest) return steps[index].value;
    for (let index = this.selected + 1; index < steps.length; index++)
      if (!steps[index].rest) return steps[index].value;
    return this.pattern.notationKind === "chord" ? "C" : "C4";
  }

  private toggleRest(): void {
    const { structure, contentFrom, selectionFrom, selectionTo } = this.pattern;
    const range = structure ? sourceRangeNodes(structure, selectionFrom - contentFrom, selectionTo - contentFrom) : [];
    if (structure && (range.length > 1 || structure.nodes[range[0]]?.kind === "group")) {
      const from = structure.nodes[range[0]].from + contentFrom;
      const to = structure.nodes[range.at(-1)!].end + contentFrom;
      const changes = this.pattern.steps?.filter(step => !step.rest && step.from >= from && step.to <= to)
        .map(step => ({ from: step.from, to: step.to, insert: "~" })) ?? [];
      if (!changes.length) return;
      const changeSet = this.view.state.changes(changes);
      this.view.dispatch({ changes: changeSet, selection: { anchor: from, head: changeSet.mapPos(to, 1) },
        annotations: isolateHistory.of("full") });
      this.view.dispatch({ selection: this.view.state.selection });
      return;
    }
    const step = this.pattern.steps?.[this.selected];
    if (!step) return;
    if (!step.rest) this.apply(step, "~");
    else if (this.pattern.kind === "note") this.apply(step, this.restValue());
  }

  private choose(value: string): void {
    const step = this.pattern.steps?.[this.selected];
    if (step && (value === "~" || (this.pattern.notationKind === "note" && midiValue(value) !== null))) {
      this.apply(step, value);
    }
  }
}

class PatternWidget extends WidgetType {
  constructor(readonly pattern: Pattern, readonly memory: PatternMemory) { super(); }
  override eq(other: PatternWidget): boolean {
    return this.pattern.doc === other.pattern.doc && this.pattern.from === other.pattern.from &&
      this.pattern.notationKind === other.pattern.notationKind && this.pattern.cursor === other.pattern.cursor &&
      this.pattern.selectionFrom === other.pattern.selectionFrom && this.pattern.selectionTo === other.pattern.selectionTo &&
      this.pattern.selectedNode === other.pattern.selectedNode && this.memory === other.memory;
  }
  toDOM(view: EditorView): HTMLElement { return new PatternWidgetDOM(view, this.pattern, this.memory).dom; }
  override updateDOM(dom: HTMLElement): boolean {
    const widget = liveWidgets.get(dom);
    if (!widget || widget.memory !== this.memory || dom.dataset.notationKind !== this.pattern.notationKind) return false;
    widget.update(this.pattern);
    return true;
  }
  override destroy(dom: HTMLElement): void { liveWidgets.get(dom)?.destroy(); }
}

type PatternState = { memories: Map<number, PatternMemory>; decorations: DecorationSet };

function patternState(state: EditorState, previous?: PatternState, changes?: ChangeDesc): PatternState {
  const all = sourcePatterns(state);
  const memories = new Map<number, PatternMemory>();
  const current = new Set(all.map(pattern => pattern.from));
  previous?.memories.forEach((memory, from) => {
    const mapped = changes ? changes.mapPos(from, 1, MapMode.TrackDel) : from;
    if (mapped !== null && current.has(mapped)) memories.set(mapped, memory);
  });
  for (const pattern of all) if (!memories.has(pattern.from)) memories.set(pattern.from, {});
  if (!state.facet(patternControlsVisible)) return { memories, decorations: Decoration.none };
  const head = state.selection.main.head;
  let selected = all.filter(pattern => head >= pattern.from && head <= pattern.to);
  if (selected.length === 0) {
    const line = state.doc.lineAt(head);
    selected = all.filter(pattern => state.doc.lineAt(pattern.from).from === line.from);
    selected.sort((a, b) => Math.abs(a.from - head) - Math.abs(b.from - head));
    selected = selected.slice(0, 1);
  }
  if (selected.length > 1) selected = selected.sort((a, b) => (a.to - a.from) - (b.to - b.from)).slice(0, 1);
  return { memories, decorations: Decoration.set(selected.map(pattern => Decoration.widget({
    widget: new PatternWidget(pattern, memories.get(pattern.from)!), side: 1, block: true,
  }).range(state.doc.lineAt(pattern.to).to)), true) };
}

export function patternControls(): Extension {
  return [
    keymap.of(historyKeymap.map(binding => ({ ...binding, scope: "pattern-control" }))),
    StateField.define<PatternState>({
      create: state => patternState(state),
      update: (value, transaction) => transaction.docChanged || transaction.selection ||
        transaction.startState.facet(patternControlsVisible) !== transaction.state.facet(patternControlsVisible)
        ? patternState(transaction.state, value, transaction.changes) : value,
      provide: field => EditorView.decorations.from(field, value => value.decorations),
    }),
  ];
}
