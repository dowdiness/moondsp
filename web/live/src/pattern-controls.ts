import { EditorState, Facet, StateField, Transaction, type Extension, type Text } from "@codemirror/state";
import { isolateHistory, historyKeymap } from "@codemirror/commands";
import { Decoration, EditorView, WidgetType, keymap, runScopeHandlers, type DecorationSet } from "@codemirror/view";
import type { SyntaxNode, Tree } from "@lezer/common";
import { miniliveLanguage } from "./lang/minilive";
import type { Audition } from "./audition";
import { auditionSource, midiValue, transposePitch } from "./pattern-audition";

const listening = Facet.define<{ audition: Audition; autoListen: () => boolean }, { audition: Audition; autoListen: () => boolean }>({
  combine: values => values[0],
});

type Kind = "drum" | "note";
type Step = { from: number; to: number; value: string; rest: boolean };
type Pattern = { from: number; to: number; kind: Kind; name: string; steps: Step[] | null; reason: string; doc: Text; cursor: number; tree: Tree };
const DRUMS = ["bd", "sd", "hh", "oh", "cp"] as const;
const PITCH = /^[A-G](?:#|b)?(?:-?[0-9])?$/;
const DRUM_LABEL: Record<(typeof DRUMS)[number], string> = { bd: "Kick", sd: "Snare", hh: "Hi-hat", oh: "Open hat", cp: "Clap" };

function parentNamed(node: SyntaxNode, name: string): SyntaxNode | null {
  for (let parent = node.parent; parent; parent = parent.parent) if (parent.name === name) return parent;
  return null;
}

function targets(state: EditorState): Pattern[] {
  const source = state.doc.toString();
  const tree = miniliveLanguage.parser.parse(source);
  const patterns: Pattern[] = [];
  tree.iterate({ enter(ref) {
    if (ref.name !== "Chain") return;
    const call = ref.node.getChild("Call");
    if (!call) return;
    const nameNode = call.getChild("CallName");
    const callName = nameNode ? source.slice(nameNode.from, nameNode.to) : "";
    if (callName !== "s" && callName !== "note") return;
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
    const kind: Kind = callName === "s" ? "drum" : "note";
    const matches = [...content.matchAll(/[^\s]+/g)];
    if (matches.length === 0) return;
    let reason = "";
    let steps: Step[] | null = [];
    if (matches.length > 32) {
      reason = "Pattern editing supports up to 32 steps.";
      steps = null;
    } else {
      for (const match of matches) {
        const token = match[0];
        const valid = token === "~" || (kind === "drum"
          ? (DRUMS as readonly string[]).includes(token)
          : (/^\d+$/.test(token) && Number(token) <= 127) || PITCH.test(token));
        if (!valid) {
          reason = "Mini-notation, chords, and grouped or repeated steps stay editable in source.";
          steps = null;
          break;
        }
        const start = string.from + 1 + match.index!;
        steps.push({ from: start, to: start + token.length, value: token, rest: token === "~" });
      }
    }
    let binding = "";
    const bindingNode = parentNamed(ref.node, "Binding");
    const bindingName = bindingNode?.getChild("BindingName");
    if (bindingName) binding = source.slice(bindingName.from, bindingName.to);
    const end = ref.node.to;
    patterns.push({ from: ref.node.from, to: end, kind, name: binding, steps, reason, doc: state.doc, cursor: state.selection.main.head, tree });
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
  private drums = document.createElement("div");
  private drumButtons: HTMLButtonElement[] = [];
  private octave = 4;
  private octaveControls = document.createElement("div");
  private octaveLabel = document.createElement("span");
  private octaveDown = this.button("−", "octave-down", () => this.showOctave(-1));
  private octaveUp = this.button("+", "octave-up", () => this.showOctave(1));
  private rest = this.button("Rest", "step-rest", () => this.choose("~"));
  private feedback = document.createElement("span");
  private readonly listening: { audition: Audition; autoListen: () => boolean };

  private button(label: string, className: string, action: (event: MouseEvent) => void): HTMLButtonElement {
    const button = document.createElement("button");
    button.type = "button";
    button.className = className;
    button.textContent = label;
    button.addEventListener("click", action);
    return button;
  }

  private get audition(): Audition { return this.listening.audition; }

  constructor(private view: EditorView, private pattern: Pattern) {
    this.listening = view.state.facet(listening);
    this.dom.className = "score-pattern cm-score-pattern";
    this.dom.dataset.kind = pattern.kind;
    this.dom.dataset.patternStart = String(pattern.from);
    this.dom.contentEditable = "false";
    this.dom.setAttribute("aria-description", "Choose a sound or rest. Press a numbered step to preview. All edits change the code.");
    this.unavailable.className = "pattern-unavailable";
    this.unavailable.textContent = "Edit in code";
    this.grid.className = "step-grid";
    this.keyboard.className = "pitch-keyboard";
    this.keyboard.setAttribute("role", "group");
    this.drums.className = "drum-choices";
    this.drums.setAttribute("role", "group");
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
    for (const drum of DRUMS) {
      const button = this.button(DRUM_LABEL[drum], "drum-choice", () => this.choose(drum));
      button.dataset.sound = drum;
      this.drumButtons.push(button);
      this.drums.append(button);
    }
    this.feedback.className = "step-feedback";
    this.feedback.setAttribute("role", "status");
    this.dom.append(this.grid, this.octaveControls, this.keyboard, this.drums, this.feedback, this.unavailable);
    this.dom.addEventListener("focusin", event => {
      const target = event.target;
      const cell = target instanceof HTMLElement ? target.closest<HTMLElement>(".step-cell") : null;
      if (cell) {
        const next = this.cells.indexOf(cell);
        if (next !== this.selected) {
          this.audition.stop();
          this.feedback.textContent = "";
        }
        this.selected = next;
        this.renderTools();
      } else if (target instanceof HTMLButtonElement) {
        const buttons = this.choices.includes(target) ? this.choices : [];
        buttons.forEach(button => { button.tabIndex = button === target ? 0 : -1; });
      }
    });
    // Share explicit commands and focus return here; leave native control keys
    // outside the editor keymap, as with the inline knobs.
    this.dom.addEventListener("keydown", event => {
      const before = this.view.state.doc;
      if (runScopeHandlers(this.view, event, "pattern-control")) {
        event.preventDefault();
        if (this.view.state.doc !== before) this.hearEdit();
      } else if (event.key === "Escape") {
        event.preventDefault();
        this.audition.stop();
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
      this.audition.stop();
      this.feedback.textContent = "";
    }
    if (!this.dom.contains(document.activeElement)) {
      const head = this.view.state.selection.main.head;
      this.selected = Math.max(0, pattern.steps?.findIndex(step => head >= step.from && head <= step.to) ?? 0);
    }
    this.pattern = pattern;
    this.dom.dataset.kind = pattern.kind;
    this.dom.dataset.patternStart = String(pattern.from);
    this.render();
  }

  private render(): void {
    const { kind, name, steps } = this.pattern;
    this.label = `${kind === "drum" ? "Drums" : "Melody"}${name ? ` · ${name}` : ""}`;
    this.unavailable.hidden = !!steps;
    this.grid.hidden = !steps;
    this.keyboard.hidden = !steps || kind !== "note";
    this.drums.hidden = !steps || kind !== "drum";
    this.octaveControls.hidden = !steps || kind !== "note";
    const restContainer = kind === "note" ? this.octaveControls : this.drums;
    if (this.rest.parentElement !== restContainer) {
      restContainer.append(this.rest);
      this.choices = kind === "note" ? this.keys : [...this.drumButtons, this.rest];
    }
    if (!steps) {
      this.grid.replaceChildren();
      this.cells = [];
      this.dom.setAttribute("aria-label", this.pattern.reason);
      this.dom.title = this.pattern.reason;
      return;
    }
    this.dom.removeAttribute("aria-label");
    this.dom.title = "";
    while (this.cells.length > steps.length) this.cells.pop()!.remove();
    for (let index = 0; index < steps.length; index++) {
      const step = steps[index];
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
    const play = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    play.setAttribute("viewBox", "0 0 12 12");
    play.setAttribute("aria-hidden", "true");
    play.innerHTML = '<path d="M3 2 10 6 3 10Z" fill="currentColor"/>';
    const value = document.createElement("span");
    value.className = "step-note";
    pad.append(number, value, play);
    cell.append(pad);
    pad.addEventListener("click", () => { this.selected = index; this.renderTools(); this.hear(); });
    return cell;
  }

  private updateCell(cell: HTMLElement, step: Step, index: number): void {
    const pad = cell.querySelector<HTMLButtonElement>(".step-pad")!;
    const voice = this.pattern.kind === "drum" ? (step.rest ? "Rest" : DRUM_LABEL[step.value as keyof typeof DRUM_LABEL] ?? step.value) : (step.rest ? "Rest" : step.value);
    pad.setAttribute("aria-label", `${step.rest ? "Select rest" : `Listen to ${voice}`}, ${this.label}, step ${index + 1}`);
    pad.title = step.rest ? `Rest, step ${index + 1}` : `Listen to ${voice}, step ${index + 1}`;
    pad.querySelector<HTMLElement>(".step-note")!.textContent = voice;
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
  private renderTools(): void {
    const step = this.pattern.steps?.[this.selected];
    this.cells.forEach((cell, index) => {
      cell.classList.toggle("is-selected", index === this.selected);
      const pad = cell.querySelector<HTMLButtonElement>(".step-pad")!;
      pad.setAttribute("aria-pressed", String(index === this.selected));
      pad.tabIndex = index === this.selected ? 0 : -1;
    });
    this.octaveControls.hidden = this.pattern.kind !== "note";
    this.rest.disabled = !step;
    this.rest.setAttribute("aria-pressed", String(!!step?.rest));
    this.rest.title = "Choose a rest";
    this.rest.tabIndex = this.pattern.kind === "note" || step?.rest ? 0 : -1;
    const parsed = step && midiValue(step.value);
    if (parsed) this.octave = Math.floor(parsed.midi / 12) - 1;
    this.renderKeyboard();
    this.drums.setAttribute("aria-label", `Change drum for ${this.label}, step ${this.selected + 1}`);
    this.drumButtons.forEach((button, index) => {
      button.setAttribute("aria-pressed", String(step?.value === DRUMS[index]));
      button.tabIndex = step?.value === DRUMS[index] ? 0 : -1;
    });
  }

  private showOctave(delta: number): void {
    this.octave = Math.max(-1, Math.min(9, this.octave + delta));
    this.renderKeyboard();
  }

  private renderKeyboard(): void {
    if (this.pattern.kind !== "note") return;
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
    if (!step || this.pattern.kind !== "note") return;
    const value = transposePitch(step.value, semitones);
    if (value === null) return;
    this.apply(step, value);
    this.hearEdit();
  }

  private hearEdit(): void {
    if (this.listening.autoListen()) this.hear();
    else this.audition.stop();
  }

  private hear(): void {
    const step = this.pattern.steps?.[this.selected];
    if (!step || step.rest) {
      this.audition.stop();
      this.feedback.textContent = "Rest";
      return;
    }
    const source = auditionSource(this.view.state.doc.toString(), this.pattern.from, step.from, this.pattern.tree);
    if (source === null) {
      this.audition.stop();
      this.feedback.textContent = "Cannot preview this step. Use Play to hear the score.";
      return;
    }
    const value = step.value;
    this.audition.play(source, state => {
      this.dom.dataset.preview = state.kind;
      this.feedback.textContent = state.kind === "loading" ? `Loading ${value}…`
        : state.kind === "playing" ? `Previewing ${value}`
        : state.kind === "error" ? `Preview failed: ${state.message}. Use Play to hear the score.` : "";
    });
  }

  destroy(): void { this.audition.stop(); }

  private choose(value: string): void {
    const step = this.pattern.steps?.[this.selected];
    if (step && (value === "~" || (this.pattern.kind === "drum"
      ? (DRUMS as readonly string[]).includes(value)
      : midiValue(value) !== null))) {
      this.apply(step, value);
      this.hearEdit();
    }
  }
}

class PatternWidget extends WidgetType {
  constructor(readonly pattern: Pattern) { super(); }
  override eq(other: PatternWidget): boolean {
    return this.pattern.doc === other.pattern.doc && this.pattern.from === other.pattern.from &&
      this.pattern.kind === other.pattern.kind && this.pattern.cursor === other.pattern.cursor;
  }
  toDOM(view: EditorView): HTMLElement { return new PatternWidgetDOM(view, this.pattern).dom; }
  override updateDOM(dom: HTMLElement): boolean {
    const widget = liveWidgets.get(dom);
    if (!widget) return false;
    widget.update(this.pattern);
    return true;
  }
  override destroy(dom: HTMLElement): void { liveWidgets.get(dom)?.destroy(); }
}

function decorations(state: EditorState): DecorationSet {
  const all = targets(state);
  const head = state.selection.main.head;
  let selected = all.filter(pattern => head >= pattern.from && head <= pattern.to);
  if (selected.length === 0) {
    const line = state.doc.lineAt(head);
    selected = all.filter(pattern => state.doc.lineAt(pattern.from).from === line.from);
    selected.sort((a, b) => Math.abs(a.from - head) - Math.abs(b.from - head));
    selected = selected.slice(0, 1);
  }
  if (selected.length > 1) selected = selected.sort((a, b) => (a.to - a.from) - (b.to - b.from)).slice(0, 1);
  return Decoration.set(selected.map(pattern => Decoration.widget({
    widget: new PatternWidget(pattern), side: 1, block: true,
  }).range(state.doc.lineAt(pattern.to).to)), true);
}

export function patternControls(audition: Audition, autoListen: () => boolean): Extension {
  return [
    listening.of({ audition, autoListen }),
    keymap.of(historyKeymap.map(binding => ({ ...binding, scope: "pattern-control" }))),
    StateField.define<DecorationSet>({
      create: decorations,
      update: (value, transaction) => transaction.docChanged || transaction.selection ? decorations(transaction.state) : value,
      provide: field => EditorView.decorations.from(field),
    }),
  ];
}
