// Completion for moondsp mini-notation (ADR-0023). The editor decides where
// the cursor is from the Lezer tree; every name it offers comes from the
// score language's vocabulary, and the methods after a pattern from
// `methodsAfter`. Before the score tools load, it offers only the earlier
// bindings, `let`, and `$:`.

import type { CompletionContext, CompletionResult, Completion } from "@codemirror/autocomplete";
import { snippetCompletion } from "@codemirror/autocomplete";
import { syntaxTree } from "@codemirror/language";
import type { SyntaxNode } from "@lezer/common";
import type { EditorState } from "@codemirror/state";
import type { Argument, ArgumentKind, Call, Position, Term, Vocabulary } from "../authoring";

/** What the score language tells completion; it loads with the score tools. */
export type ScoreLanguage = Readonly<{
  vocabulary: Vocabulary;
  methodsAfter(receiver: string): readonly Call[];
}>;

/** What completion knows of the language: the score language once it loads, before that no names. */
type Names = Readonly<{
  calls: readonly Call[];
  signals: readonly Term[];
  drums: readonly Term[];
  instruments: readonly Completion[];
  samples: readonly Term[];
  methodsAfter(receiver: string): readonly Call[];
}>;

const NO_NAMES: Names = { calls: [], signals: [], drums: [], instruments: [], samples: [], methodsAfter: () => [] };

function namesOf({ vocabulary, methodsAfter }: ScoreLanguage): Names {
  const { default: preferred, others } = vocabulary.instruments;
  return {
    calls: vocabulary.calls,
    signals: vocabulary.signals,
    drums: vocabulary.drums,
    instruments: [termCompletion(preferred, `${preferred.description} (default)`), ...others.map(term => termCompletion(term))],
    samples: vocabulary.samples,
    methodsAfter,
  };
}

// The syntax that is not a name, which the grammar owns.
const KEYWORDS: readonly Completion[] = [
  snippetCompletion("let ${name} = ${pattern};", { label: "let", type: "keyword", detail: "define a reusable pattern" }),
  snippetCompletion("$: ${}", { label: "$:", type: "keyword", detail: "stack line" }),
];

const WORD = /^[A-Za-z_0-9]*$/;

/** What stands at a place: an argument's kind, or the top of the score. */
type Place = ArgumentKind | "top";

function ancestorOfType(node: SyntaxNode | null, name: string): SyntaxNode | null {
  for (let n: SyntaxNode | null = node; n; n = n.parent) {
    if (n.name === name) return n;
  }
  return null;
}

function isClosedString(text: string): boolean {
  // The grammar's String token regex `'"' (![\\\n"] | "\\" _)* '"'?`
  // allows an optional closing quote. A trailing `"` is the close ONLY
  // when an even number of backslashes precede it — odd parity means
  // the final `"` was consumed as the second half of an `\"` escape and
  // the token is actually unterminated. Without this, a string like
  // `"foo\"` (length 6, endsWith `"`) would be misclassified as closed
  // and reject completion at the end-of-string position.
  if (text.length < 2 || !text.endsWith('"')) return false;
  let backslashes = 0;
  for (let i = text.length - 2; i >= 1 && text[i] === "\\"; i--) backslashes++;
  return backslashes % 2 === 0;
}

// The String around `pos` when `pos` is inside its notation. The grammar
// accepts unterminated strings (`'"' (...)* '"'?`): while the user is typing
// one, `pos === string.to` is inside it; once the closing quote exists, the
// same position is past it.
function notationAt(state: EditorState, pos: number): SyntaxNode | null {
  const string = ancestorOfType(syntaxTree(state).resolveInner(pos, -1), "String");
  if (!string) return null;
  const inside = isClosedString(state.doc.sliceString(string.from, string.to))
    ? pos > string.from && pos < string.to
    : pos > string.from && pos <= string.to;
  return inside ? string : null;
}

const QUOTED: ReadonlySet<ArgumentKind> = new Set(["drums", "instruments", "text"]);
const METHOD_POSITIONS: ReadonlySet<Position> = new Set(["after-song", "after-pattern", "after-signal"]);

// A call as a snippet that fills in its required arguments, quoting those
// written as strings. A declaration ends with `;`, as the grammar writes it.
function callCompletion(call: Call): Completion {
  const slot = (argument: Argument) => QUOTED.has(argument.kind) ? `"\${${argument.name}}"` : `\${${argument.name}}`;
  const end = call.position === "declaration" ? ";" : "";
  const type = METHOD_POSITIONS.has(call.position) ? "method" : "function";
  return snippetCompletion(`${call.name}(${call.required.map(slot).join(", ")})${end}`, { label: call.name, type, detail: call.description });
}

function termCompletion(term: Term, detail = term.description): Completion {
  return { label: term.name, type: "constant", detail };
}

export function scoreCompletion(language: ScoreLanguage | null) {
  const { calls, methodsAfter, ...names } = language ? namesOf(language) : NO_NAMES;
  const callsAt = (...positions: Position[]) => calls.filter(call => positions.includes(call.position)).map(callCompletion);
  const options = {
    top: callsAt("declaration", "arrangement", "pattern"),
    pattern: callsAt("pattern"),
    songItem: callsAt("song-item"),
    callback: callsAt("callback"),
    signalMethods: callsAt("after-signal"),
    signals: names.signals.map(term => termCompletion(term)),
    // `s("…")` takes drums and samples, `.s("…")` instruments and samples (ADR-0026).
    drums: [...names.drums, ...names.samples].map(term => termCompletion(term)),
    instruments: [...names.instruments, ...names.samples.map(term => termCompletion(term))],
  };
  const signals = new Set(names.signals.map(term => term.name));

  return (context: CompletionContext): CompletionResult | null => {
    const { state, pos } = context;
    const tree = syntaxTree(state);
    const text = (node: SyntaxNode) => state.doc.sliceString(node.from, node.to);

    // The calls a `Call` node can be, by where it stands.
    const callPositions = (call: SyntaxNode): readonly Position[] => {
      if (call.parent?.name === "Declaration") return ["declaration"];
      const place = call.parent?.name === "Chain" && call.parent.parent ? placeOf(call.parent.parent) : null;
      switch (place) {
        case "top": return ["declaration", "arrangement", "pattern"];
        case "pattern": return ["pattern"];
        case "song-item": return ["song-item"];
        case "callback": return ["callback"];
        default: return [];
      }
    };
    // The argument at `pos` in `args`, by the call that owns it and the
    // commas before `pos`.
    const argumentAt = (args: SyntaxNode, at: number): Argument | null => {
      const owner = args.parent;
      const name = owner?.getChild(owner.name === "MemberCall" ? "MethodName" : "CallName");
      if (!owner || !name) return null;
      const positions: readonly Position[] = owner.name === "MemberCall"
        ? [owner.parent?.parent && placeOf(owner.parent.parent) === "control" ? "after-signal" : "after-pattern"]
        : callPositions(owner);
      const call = calls.find(candidate => positions.includes(candidate.position) && candidate.name === text(name));
      if (!call) return null;
      let index = 0;
      for (let child = args.firstChild; child && child.to <= at; child = child.nextSibling) if (child.name === ",") index++;
      return [...call.required, ...call.optional][index] ?? call.repeated;
    };
    // What stands at `at`, inside `node`.
    const placeOf = (node: SyntaxNode, at = node.from): Place | null => {
      for (let n: SyntaxNode | null = node; n; n = n.parent) {
        switch (n.name) {
          case "Args": return argumentAt(n, at)?.kind ?? null;
          case "Group": case "DollarLine": return "pattern";
          case "Binding": {
            const equals = n.getChild("=");
            return equals && at >= equals.to ? "pattern" : null;
          }
          case "Program": case "Declaration": return "top";
        }
      }
      return null;
    };
    const result = (from: number, offered: readonly Completion[], validFor = WORD): CompletionResult | null =>
      offered.length === 0 ? null : { from, options: [...offered], validFor };

    // Inside a string: sound names, when the argument takes them.
    const string = notationAt(state, pos);
    if (string) {
      const kind = string.parent?.name === "Args" ? argumentAt(string.parent, string.from)?.kind : null;
      if (kind !== "drums" && kind !== "instruments") return null;
      const word = context.matchBefore(/[a-z]+$/);
      if (!word && !context.explicit) return null;
      return result(word ? word.from : pos, kind === "drums" ? options.drums : options.instruments, /^[a-z]*$/);
    }
    if (ancestorOfType(tree.resolveInner(pos, -1), "String")) return null;

    // After `.`: a signal's methods in a control argument; otherwise the
    // methods the score language accepts after the receiver.
    const dot = context.matchBefore(/\.[A-Za-z_]*$/);
    if (dot) {
      const chain = ancestorOfType(tree.resolveInner(dot.from, -1), "Chain");
      if (!chain) return null;
      if (chain.parent && placeOf(chain.parent) === "control") {
        const head = chain.firstChild?.name === "Call" ? chain.firstChild.getChild("CallName") : null;
        return head && signals.has(text(head)) ? result(dot.from + 1, options.signalMethods) : null;
      }
      // The receiver before the `.`, after the `let` bindings before it.
      const bindings = tree.topNode.getChildren("Binding").filter(binding => binding.to <= chain.from);
      const receiver = [...bindings.map(text), state.doc.sliceString(chain.from, dot.from)].join("\n");
      return result(dot.from + 1, methodsAfter(receiver).map(callCompletion));
    }

    // A name being written: what its place takes.
    const word = context.matchBefore(/(?:\$:?|[A-Za-z_][A-Za-z_0-9]*)$/);
    if (!word && !context.explicit) return null;
    const from = word ? word.from : pos;
    const bindings: Completion[] = [];
    for (const binding of tree.topNode.getChildren("Binding")) {
      const name = binding.getChild("BindingName");
      if (binding.to < pos && name && !bindings.some(earlier => earlier.label === text(name))) {
        bindings.push({ label: text(name), type: "variable", detail: "named pattern" });
      }
    }
    switch (placeOf(tree.resolveInner(pos, -1), from)) {
      case "top": return result(from, [...bindings, ...KEYWORDS, ...options.top], /^(?:\$:?|[A-Za-z_0-9]*)$/);
      case "pattern": return result(from, [...bindings, ...options.pattern]);
      case "song-item": return result(from, options.songItem);
      case "callback": return result(from, options.callback);
      case "control": return result(from, options.signals);
      default: return null;
    }
  };
}
