import { Annotation, EditorState, StateField, Transaction, type Extension, type Text } from "@codemirror/state";
import { Decoration, EditorView, WidgetType, keymap, runScopeHandlers, type DecorationSet } from "@codemirror/view";
import { history, historyKeymap, isolateHistory } from "@codemirror/commands";
import type { SyntaxNode, Tree } from "@lezer/common";
import { miniliveLanguage } from "./lang/minilive";

type Target = { from: number; to: number; label: string; step: number; value: string; notice: string };
const lastInlineEdit = StateField.define<boolean>({
  create: () => false,
  update: (value, transaction) => transaction.docChanged ? transaction.isUserEvent("input.type.inline") : value,
});

/** Edit complete literal arguments independently of receiver resolution or surrounding errors. */
function controlTargets(tree: Tree, source: string): Target[] {
  const targets: Target[] = [];
  const text = (node: SyntaxNode | null) => node ? source.slice(node.from, node.to) : "";
  tree.iterate({ enter(ref) {
    if (ref.name !== "Chain") return;
    const chain = ref.node;
    const members = chain.getChildren("MemberCall");
    const local: Target[] = [];
    for (const member of members) {
      const name = text(member.getChild("MethodName"));
      if (name !== "gain" && name !== "lpf") continue;
      let broken = false;
      member.toTree().iterate({ enter(node) { if (node.type.isError) broken = true; } });
      if (broken) continue;
      const args = member.getChild("Args");
      if (!args) continue;
      const children: SyntaxNode[] = [];
      for (let child = args.firstChild; child; child = child.nextSibling) {
        if (!["LineComment", "BlockComment"].includes(child.name)) children.push(child);
      }
      // Exact grammar shape excludes fractions, nested calls, missing delimiters and extra args.
      const shape = children.map(child => child.name).join(" ");
      if (shape !== "( Number )" && !(name === "lpf" && shape === "( Number , Number )")) continue;
      children.filter(child => child.name === "Number").forEach((number, index) => {
        const value = text(number);
        if (!Number.isFinite(Number(value))) return;
        const label = name === "gain" ? "Gain" : index === 0 ? "Cutoff Hz" : "Q";
        for (const earlier of local) {
          if (earlier.label === label) earlier.notice = "Overridden by a later modifier in this chain.";
        }
        local.push({ from: number.from, to: number.to, value, label,
          notice: "Source edit · browser note/chord voices only; drums are unaffected.",
          step: name === "lpf" && index === 0 ? 10 : 0.01 });
      });
    }
    targets.push(...local);
  } });
  return targets;
}

// The DOM owns only ephemeral input/gesture state. Source ranges and values are derived afresh.
const controls = new WeakMap<HTMLElement, Control>();
class Control {
  readonly dom = document.createElement("span");
  readonly input = document.createElement("input");
  readonly handle = document.createElement("button");
  private readonly hint = document.createElement("span");
  private gesture: { y: number; value: number; changed: boolean; time: number } | null = null;
  private writing = false;
  private readonly blur = () => this.finish();
  constructor(private view: EditorView, private target: Target, private doc: Text) {
    this.dom.className = "cm-inline-control";
    this.dom.contentEditable = "false";
    this.handle.type = "button";
    this.handle.className = "cm-sound-knob";
    this.handle.setAttribute("role", "slider");
    this.handle.setAttribute("aria-orientation", "vertical");
    this.handle.innerHTML = '<svg viewBox="0 0 64 64" aria-hidden="true"><circle class="knob-face" cx="32" cy="32" r="27"/><path class="knob-pointer" d="M32 10V26"/></svg>';
    this.handle.setAttribute("aria-label", `Adjust ${target.label}`);
    this.handle.setAttribute("aria-description", "Drag up or down. Shift for fine adjustment. Enter to type a number.");
    this.input.type = "text";
    this.input.inputMode = "decimal";
    this.input.setAttribute("aria-label", target.label);
    this.input.title = "Enter to apply; Escape or leaving the field to cancel";
    this.input.value = target.value;
    this.input.popover = "auto";
    this.hint.className = "cm-knob-hint";
    this.hint.setAttribute("aria-hidden", "true");
    this.dom.append(this.handle, this.input, this.hint);
    this.renderKnob();
    controls.set(this.dom, this);
    this.handle.onpointerdown = event => {
      if (event.button !== 0) return;
      event.preventDefault();
      this.handle.focus();
      this.gesture = { y: event.clientY, value: Number(this.target.value), changed: false, time: Date.now() };
      this.handle.setPointerCapture(event.pointerId);
    };
    this.handle.onpointermove = event => {
      const gesture = this.gesture;
      if (!gesture) return;
      const delta = (gesture.y - event.clientY) * this.target.step * (event.shiftKey ? 0.1 : 1);
      if (delta === 0 && !gesture.changed) return;
      const value = this.target.label === "Cutoff Hz" && gesture.value > 0
        ? Math.round(gesture.value * 2 ** (delta / 400))
        : Math.round((gesture.value + delta) * 10000) / 10000;
      this.write(String(value), gesture);
    };
    this.handle.onpointerup = () => {
      const clicked = this.gesture !== null && !this.gesture.changed;
      this.finish();
      if (clicked) this.editNumber();
    };
    this.handle.onpointercancel = this.handle.onlostpointercapture = () => this.finish();
    this.handle.onblur = () => this.finish();
    this.handle.onkeydown = event => {
      // Use CodeMirror's platform-aware history bindings, only on the knob.
      // The number input keeps its native history for uncommitted text.
      if (runScopeHandlers(this.view, event, "inline-control")) {
        event.preventDefault();
        return;
      }
      if (event.key === "Escape") { this.finish(); this.view.focus(); }
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        this.editNumber();
      }
      if (event.key !== "ArrowUp" && event.key !== "ArrowDown") return;
      event.preventDefault();
      const delta = this.target.step * (event.shiftKey ? 0.1 : 1) * (event.key === "ArrowUp" ? 1 : -1);
      this.write(String(Math.round((Number(this.target.value) + delta) * 10000) / 10000));
    };
    this.input.onkeydown = event => {
      if (event.key === "Enter") {
        event.preventDefault();
        if (this.commit()) this.view.focus();
      } else if (event.key === "Escape") {
        this.input.value = this.target.value;
        this.input.removeAttribute("aria-invalid");
        this.view.focus();
      }
    };
    this.input.onblur = () => {
      // Leaving an incomplete number cancels it; never coerce empty/invalid input to zero.
      this.input.value = this.target.value;
      this.input.removeAttribute("aria-invalid");
      this.input.hidePopover();
    };
    window.addEventListener("blur", this.blur);
  }
  private editNumber(): void {
    const rect = this.handle.getBoundingClientRect();
    this.input.style.left = `${Math.max(4, Math.min(rect.left, window.innerWidth - 130))}px`;
    this.input.style.top = `${Math.max(4, Math.min(rect.bottom + 4, window.innerHeight - 44))}px`;
    this.input.showPopover();
    this.input.focus();
    this.input.select();
  }
  private commit(): boolean {
    const value = this.input.value.trim();
    // Validation of a number, not source discovery or replacement.
    if (!/^-?(\d+(\.\d*)?|\.\d+)$/.test(value) || !Number.isFinite(Number(value))) {
      this.input.setAttribute("aria-invalid", "true");
      return false;
    }
    this.input.removeAttribute("aria-invalid");
    this.write(value);
    return true;
  }
  private write(value: string, gesture?: NonNullable<Control["gesture"]>): void {
    if (this.doc !== this.view.state.doc || !this.dom.isConnected) { this.finish(); return; }
    if (!/^-?(\d+(\.\d*)?|\.\d+)$/.test(value) || !Number.isFinite(Number(value))) return;
    if (value === this.target.value) return;
    const annotations: Annotation<unknown>[] = [Transaction.userEvent.of("input.type.inline")];
    // One gesture has one history timestamp, even when the pointer pauses.
    // Every edit still reaches the Draft listener as its own transaction.
    if (gesture) annotations.push(Transaction.time.of(gesture.time));
    if (!gesture?.changed) annotations.push(isolateHistory.of(gesture ? "before" : "full"));
    this.writing = true;
    try {
      this.view.dispatch({ changes: { from: this.target.from, to: this.target.to, insert: value }, annotations });
      if (gesture) gesture.changed = true;
    } finally { this.writing = false; }
  }
  update(target: Target, doc: Text): void {
    if (doc !== this.doc && !this.writing) {
      this.gesture = null;
      this.input.hidePopover();
    }
    this.target = target;
    this.doc = doc;
    this.input.value = target.value;
    this.input.removeAttribute("aria-invalid");
    this.renderKnob();
  }
  private renderKnob(): void {
    const value = Number(this.target.value);
    const [min, max] = this.target.label === "Gain" ? [0, 2] : this.target.label === "Q" ? [0.1, 10] : [20, 20000];
    const fraction = this.target.label === "Cutoff Hz"
      ? Math.log(Math.max(value, min) / min) / Math.log(max / min) : (value - min) / (max - min);
    const amount = Math.max(0, Math.min(1, fraction));
    this.handle.style.setProperty("--knob-angle", `${-135 + amount * 270}deg`);
    this.hint.textContent = `${this.target.label} · ${this.target.value}\nDrag ↑↓ · Shift: fine · Click: type\n${this.target.notice}`;
    this.handle.setAttribute("aria-description", `Drag up or down. Shift for fine adjustment. Enter to type a number. ${this.target.notice}`);
    this.handle.setAttribute("aria-valuemin", String(Math.min(min, value)));
    this.handle.setAttribute("aria-valuemax", String(Math.max(max, value)));
    this.handle.setAttribute("aria-valuenow", this.target.value);
    this.handle.setAttribute("aria-valuetext", `${this.target.value}${this.target.label === "Cutoff Hz" ? " Hz" : ""}`);
  }
  private finish(): void {
    const changed = this.gesture?.changed;
    this.gesture = null;
    if (changed) this.view.dispatch({ annotations: isolateHistory.of("after") });
  }
  destroy(): void {
    this.gesture = null;
    window.removeEventListener("blur", this.blur);
  }
}

class ControlWidget extends WidgetType {
  constructor(readonly target: Target, readonly doc: Text) { super(); }
  override eq(other: ControlWidget): boolean { return this.doc === other.doc && this.target.from === other.target.from; }
  toDOM(view: EditorView): HTMLElement { return new Control(view, this.target, this.doc).dom; }
  override updateDOM(dom: HTMLElement): boolean {
    const control = controls.get(dom);
    if (!control || dom.querySelector("input")?.getAttribute("aria-label") !== this.target.label) return false;
    control.update(this.target, this.doc);
    return true;
  }
  override destroy(dom: HTMLElement): void { controls.get(dom)?.destroy(); }
}

function decorations(state: EditorState): DecorationSet {
  const source = state.doc.toString();
  const targets = controlTargets(miniliveLanguage.parser.parse(source), source);
  return Decoration.set(targets.map(target => Decoration.widget({
    widget: new ControlWidget(target, state.doc), side: -1,
  }).range(target.from)), true);
}

export function inlineControls(): Extension {
  return [
    history(),
    keymap.of(historyKeymap.map(binding => ({ ...binding, scope: "inline-control" }))),
    lastInlineEdit,
    // An external source edit can interrupt a captured pointer without a blur.
    // Isolate it before history processes it, rather than dispatching inside a DOM update.
    EditorState.transactionExtender.of(transaction =>
      transaction.docChanged && transaction.startState.field(lastInlineEdit) && !transaction.isUserEvent("input.type.inline")
        ? { annotations: isolateHistory.of("before") } : null),
    StateField.define<DecorationSet>({
      create: decorations,
      update: (value, transaction) => transaction.docChanged ? decorations(transaction.state) : value,
      provide: field => EditorView.decorations.from(field),
    }),
    EditorView.baseTheme({
      ".cm-inline-control": { position: "relative", display: "inline-flex", width: "1.1em", height: "1em", margin: "0 0.18em", verticalAlign: "-0.1em", font: "inherit", color: "var(--ink)" },
      ".cm-inline-control .cm-sound-knob": { width: "1em", height: "1em", minHeight: "0", padding: "0", border: "0", borderRadius: "50%", background: "transparent", font: "inherit", lineHeight: "1", cursor: "ns-resize", touchAction: "none" },
      ".cm-sound-knob svg": { width: "100%", height: "100%", overflow: "visible" },
      ".knob-face": { fill: "var(--panel)", stroke: "var(--ink-muted)", strokeWidth: "3" },
      ".knob-pointer": { stroke: "var(--accent)", strokeWidth: "6", strokeLinecap: "round", transform: "rotate(var(--knob-angle))", transformOrigin: "32px 32px" },
      ".cm-knob-hint": { display: "none", position: "absolute", top: "calc(100% + 4px)", left: "0", zIndex: "20", pointerEvents: "none", whiteSpace: "pre", padding: "3px 7px", border: "1px solid var(--border)", borderRadius: "4px", background: "var(--panel)", color: "var(--ink-muted)", font: "12px/1.4 var(--font-body)" },
      ".cm-inline-control:hover .cm-knob-hint, .cm-inline-control:focus-within .cm-knob-hint": { display: "block" },
      ".cm-inline-control:has(input:popover-open) .cm-knob-hint": { display: "none" },
      ".cm-inline-control input": { position: "fixed", margin: "0", width: "10ch", border: "1px solid var(--accent)", borderRadius: "4px", background: "var(--panel)", color: "var(--ink)", padding: "6px", font: "16px var(--font-mono)" },
      ".cm-inline-control :focus-visible": { outline: "1px solid var(--accent)", outlineOffset: "1px" },
      '.cm-inline-control input[aria-invalid="true"]': { outline: "2px solid var(--err-fg)" },
    }),
  ];
}
