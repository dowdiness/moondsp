// Context-aware completion for moondsp mini-notation.
//
// `miniliveCompletion` works before the score tools load. Four contexts, in
// priority order:
//   1. Inside a `String` → nothing; `scoreCompletion` names sounds there.
//   2. After `.<word>` → method names (`fast`, `slow`, `rev`, …).
//   2a. After `.` on a chain that starts with a signal → `range`, `fast`, `slow`.
//   3. Inside `Args` of a `MemberCall` whose method is `jux` (any
//      position) or `every` (past the first comma) → callback names
//      (`fast`, `slow`, `rev`); of a control method → signal names.
//   4. Top-level prefix → `$:`, `s`, `note`, `chord`, `stack`.

import type { CompletionContext, CompletionResult, Completion } from "@codemirror/autocomplete";
import { snippetCompletion } from "@codemirror/autocomplete";
import { syntaxTree } from "@codemirror/language";
import type { SyntaxNode } from "@lezer/common";
import type { EditorState } from "@codemirror/state";
import type { SoundEntry, SoundVocabulary } from "../authoring";

const TOP_LEVEL: Completion[] = [
  snippetCompletion('let ${name} = ${pattern};', { label: "let", type: "keyword", detail: "define a reusable pattern" }),
  snippetCompletion('$: ${}', { label: "$:", type: "keyword", detail: "stack line" }),
  snippetCompletion('bpm(${120});', { label: "bpm", type: "function", detail: "beats per minute, 4 beats per cycle; default 120" }),
  snippetCompletion("silence()", { label: "silence", type: "function", detail: "silent pattern" }),
  snippetCompletion('song(section("${name}", ${4}, ${pattern}), part("${occurrence}", "${name}"))', { label: "song", type: "function", detail: "finite arrangement" }),
  snippetCompletion('s("${}")', { label: "s", type: "function", detail: "drum sounds" }),
  snippetCompletion('note("${}")', { label: "note", type: "function", detail: "MIDI numbers or note names" }),
  snippetCompletion('chord("${}")', { label: "chord", type: "function", detail: "chord names" }),
  snippetCompletion("stack(${})", { label: "stack", type: "function", detail: "combine layers" }),
];

const METHODS: Completion[] = [
  snippetCompletion("repeat()", { label: "repeat", type: "method", detail: "repeat an arranged song" }),
  snippetCompletion("attack(${seconds})", { label: "attack", type: "method", detail: "note fade-in, seconds" }),
  snippetCompletion("hold(${seconds})", { label: "hold", type: "method", detail: "hold after attack, seconds" }),
  snippetCompletion("release(${seconds})", { label: "release", type: "method", detail: "note fade-out, seconds" }),
  snippetCompletion("gate(${fraction})", { label: "gate", type: "method", detail: "audible fraction of each step (0–1)" }),
  snippetCompletion("gain(${amount})", { label: "gain", type: "method", detail: "voice level" }),
  snippetCompletion("lpf(${hz}, ${resonance})", { label: "lpf", type: "method", detail: "low-pass cutoff and optional resonance (Q)" }),
  snippetCompletion("hpf(${hz}, ${resonance})", { label: "hpf", type: "method", detail: "high-pass cutoff and optional resonance (Q)" }),
  snippetCompletion("room(${send})", { label: "room", type: "method", detail: "send to shared room (0–1)" }),
  snippetCompletion("fast(${n})", { label: "fast", type: "method", detail: "n× faster" }),
  snippetCompletion("slow(${n})", { label: "slow", type: "method", detail: "n× slower" }),
  snippetCompletion("rev()", { label: "rev", type: "method", detail: "reverse" }),
  snippetCompletion("degradeBy(${p})", { label: "degradeBy", type: "method", detail: "drop with prob p (0–1)" }),
  snippetCompletion("every(${n}, ${rev})", { label: "every", type: "method", detail: "apply f every nth cycle" }),
  snippetCompletion("jux(${rev})", { label: "jux", type: "method", detail: "split stereo, apply f to right" }),
];

const CALLBACKS: Completion[] = [
  snippetCompletion("fast(${k})", { label: "fast", type: "function" }),
  snippetCompletion("slow(${k})", { label: "slow", type: "function" }),
  { label: "rev", type: "constant" },
];

// Methods whose arguments take a number, a quoted pattern, or a signal.
const CONTROL_METHODS = new Set(["gain", "pan", "room", "lpf", "hpf", "attack", "hold", "release"]);

const SIGNALS: Completion[] = [
  { label: "sine", type: "constant", detail: "0–1 sine, one period per cycle" },
  { label: "cosine", type: "constant", detail: "sine starting at 1" },
  { label: "saw", type: "constant", detail: "rise 0→1 each cycle" },
  { label: "isaw", type: "constant", detail: "fall 1→0 each cycle" },
  { label: "tri", type: "constant", detail: "0→1→0 each cycle" },
  { label: "square", type: "constant", detail: "0, then 1 for the second half" },
];

const SIGNAL_METHODS: Completion[] = [
  snippetCompletion("range(${low}, ${high})", { label: "range", type: "method", detail: "map 0–1 onto low–high" }),
  snippetCompletion("slow(${n})", { label: "slow", type: "method", detail: "n× slower" }),
  snippetCompletion("fast(${n})", { label: "fast", type: "method", detail: "n× faster" }),
];

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

function pastFirstComma(args: SyntaxNode, pos: number, doc: { sliceString(from: number, to: number): string }): boolean {
  // Only commas at the OUTER Args nesting level separate arguments.
  // A raw includes(",") would falsely fire for `every(stack(a,b)|` —
  // cursor is still in slot 1 of `every`, but the nested `stack(a,b)`
  // contains a comma. Walk between the opening `(` and the cursor,
  // tracking paren/bracket nesting and string literals.
  const text = doc.sliceString(args.from + 1, pos);
  let depth = 0;
  let inString = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (inString) {
      if (ch === "\\") {
        i++; // skip escaped char
        continue;
      }
      if (ch === '"') inString = false;
      continue;
    }
    if (ch === '"') inString = true;
    else if (ch === "(" || ch === "[") depth++;
    else if (ch === ")" || ch === "]") {
      // Clamp at zero — a stray unmatched close from a typo would
      // otherwise drive depth negative and prevent any later top-level
      // comma from being recognized.
      if (depth > 0) depth--;
    }
    else if (ch === "," && depth === 0) return true;
  }
  return false;
}

export function miniliveCompletion(context: CompletionContext): CompletionResult | null {
  const { state, pos } = context;
  const tree = syntaxTree(state);
  const node = tree.resolveInner(pos, -1);

  // ── 1. Inside a String? ───────────────────────────────────
  if (ancestorOfType(node, "String")) return null;

  // ── 2. After `.` → method completion ───────────────────────
  const dot = context.matchBefore(/\.[A-Za-z_]*$/);
  if (dot) {
    const chain = ancestorOfType(tree.resolveInner(dot.from, -1), "Chain");
    const head = chain?.firstChild?.name === "Call" ? chain.firstChild.getChild("CallName") : null;
    const headText = head ? state.doc.sliceString(head.from, head.to) : "";
    return {
      from: dot.from + 1,
      options: SIGNALS.some(signal => signal.label === headText) ? SIGNAL_METHODS : METHODS,
      validFor: /^[A-Za-z_0-9]*$/,
    };
  }

  // ── 3. Inside Args of `jux(…)` or `every(_, …)` → callbacks ─
  const argsNode = ancestorOfType(node, "Args");
  if (argsNode) {
    const owner = argsNode.parent;
    if (owner && owner.name === "MemberCall") {
      const mname = owner.getChild("MethodName");
      const mtext = mname ? state.doc.sliceString(mname.from, mname.to) : "";
      const isCallbackSlot =
        mtext === "jux" || (mtext === "every" && pastFirstComma(argsNode, pos, state.doc));
      if (isCallbackSlot || CONTROL_METHODS.has(mtext)) {
        const word = context.matchBefore(/[A-Za-z_]+$/);
        if (!word && !context.explicit) return null;
        return {
          from: word ? word.from : pos,
          options: isCallbackSlot ? CALLBACKS : SIGNALS,
          validFor: /^[A-Za-z_0-9]*$/,
        };
      }
    }
  }

  // ── 4. Top-level prefix ────────────────────────────────────
  const bindings: Completion[] = [];
  const seen = new Set<string>();
  tree.iterate({ enter(node) {
    if (node.name !== "Binding" || node.to >= pos) return;
    const name = node.node.getChild("BindingName");
    if (!name) return;
    const label = state.doc.sliceString(name.from, name.to);
    if (!seen.has(label)) {
      seen.add(label);
      bindings.push({ label, type: "variable", detail: "named pattern" });
    }
  } });
  const dollarLine = context.matchBefore(/\$?$/);
  if (dollarLine && (dollarLine.from < dollarLine.to || context.explicit)) {
    return {
      from: dollarLine.from,
      options: [...bindings, ...TOP_LEVEL],
      validFor: /^\$?$/,
    };
  }
  const ident = context.matchBefore(/[A-Za-z_][A-Za-z_0-9]*$|$/);
  if (ident && (ident.from < ident.to || context.explicit)) {
    return {
      from: ident.from,
      options: [...bindings, ...TOP_LEVEL],
      validFor: /^[A-Za-z_0-9]*$/,
    };
  }

  return null;
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

/** What the score language tells completion; it loads with the score tools. */
export type ScoreLanguage = Readonly<{
  sounds: SoundVocabulary;
  takesInstruments(receiver: string): boolean;
}>;

const CHOOSE_INSTRUMENT = snippetCompletion('s("${name}")', { label: "s", type: "method", detail: "play notes on an instrument" });

// Sound names inside `s("…")` and `.s("…")`, and `.s` after a receiver the
// score language accepts it on.
export function scoreCompletion(language: ScoreLanguage) {
  const option = (detail: (sound: SoundEntry) => string) => (sound: SoundEntry): Completion =>
    ({ label: sound.name, type: "constant", detail: detail(sound) });
  const drums = language.sounds.drums.map(option(sound => sound.description));
  const { default: preferred, others } = language.sounds.instruments;
  const instruments = [
    option(sound => `${sound.description} (default)`)(preferred),
    ...others.map(option(sound => sound.description)),
  ];
  return (context: CompletionContext): CompletionResult | null => {
    const { state, pos } = context;
    const string = notationAt(state, pos);
    if (string) {
      const owner = string.parent?.name === "Args" ? string.parent.parent : null;
      const name = owner?.name === "Call" ? owner.getChild("CallName")
        : owner?.name === "MemberCall" ? owner.getChild("MethodName")
        : null;
      if (!name || state.doc.sliceString(name.from, name.to) !== "s") return null;
      const word = context.matchBefore(/[a-z]+$/);
      if (!word && !context.explicit) return null;
      return { from: word ? word.from : pos, options: owner?.name === "Call" ? drums : instruments, validFor: /^[a-z]*$/ };
    }
    const dot = context.matchBefore(/\.[A-Za-z_]*$/);
    if (!dot) return null;
    const chain = ancestorOfType(syntaxTree(state).resolveInner(dot.from, -1), "Chain");
    if (!chain) return null;
    // The receiver before the `.`, after the `let` bindings before it.
    const bindings = syntaxTree(state).topNode.getChildren("Binding").filter(binding => binding.to <= chain.from);
    const receiver = [...bindings.map(binding => state.doc.sliceString(binding.from, binding.to)), state.doc.sliceString(chain.from, dot.from)].join("\n");
    if (!language.takesInstruments(receiver)) return null;
    return { from: dot.from + 1, options: [CHOOSE_INSTRUMENT], validFor: /^[A-Za-z_0-9]*$/ };
  };
}
