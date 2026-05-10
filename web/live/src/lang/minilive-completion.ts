// Context-aware completion for moondsp mini-notation.
//
// Four contexts, in priority order:
//   1. Inside a `String` whose enclosing call is `s(...)` → drum names.
//   2. After `.<word>` → method names (`fast`, `slow`, `rev`, …).
//   3. Inside `Args` of a `MemberCall` whose method is `jux` (any
//      position) or `every` (past the first comma) → callback names
//      (`fast`, `slow`, `rev`).
//   4. Top-level identifier prefix → `s`, `note`, `stack`.

import type { CompletionContext, CompletionResult, Completion } from "@codemirror/autocomplete";
import { snippetCompletion } from "@codemirror/autocomplete";
import { syntaxTree } from "@codemirror/language";
import type { SyntaxNode } from "@lezer/common";

const TOP_LEVEL: Completion[] = [
  snippetCompletion('s("${}")', { label: "s", type: "function", detail: "drum sounds" }),
  snippetCompletion('note("${}")', { label: "note", type: "function", detail: "MIDI numbers" }),
  snippetCompletion("stack(${})", { label: "stack", type: "function", detail: "combine layers" }),
];

const METHODS: Completion[] = [
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

const DRUMS: Completion[] = [
  { label: "bd", type: "constant", detail: "kick (36)" },
  { label: "sd", type: "constant", detail: "snare (38)" },
  { label: "cp", type: "constant", detail: "clap (39)" },
  { label: "hh", type: "constant", detail: "closed hat (42)" },
  { label: "oh", type: "constant", detail: "open hat (46)" },
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
  const stringNode = ancestorOfType(node, "String");
  if (stringNode) {
    // The grammar accepts unterminated strings (`'"' (...)* '"'?`), so
    // the bounds check has to differ between closed and unclosed forms.
    // While the user is typing the string, `pos === stringNode.to` IS
    // inside the contents; once the closing quote exists, the same
    // position sits AFTER the close and must be rejected.
    const text = state.doc.sliceString(stringNode.from, stringNode.to);
    const inside = isClosedString(text)
      ? pos > stringNode.from && pos < stringNode.to
      : pos > stringNode.from && pos <= stringNode.to;
    if (!inside) return null;

    const args = stringNode.parent;
    if (args && args.name === "Args") {
      const owner = args.parent;
      const nameNode = owner?.getChild("CallName");
      const callText =
        owner?.name === "Call" && nameNode
          ? state.doc.sliceString(nameNode.from, nameNode.to)
          : "";
      if (callText === "s") {
        const word = context.matchBefore(/[a-z]+$/);
        if (!word && !context.explicit) return null;
        return {
          from: word ? word.from : pos,
          options: DRUMS,
          validFor: /^[a-z]*$/,
        };
      }
    }
    return null;
  }

  // ── 2. After `.` → method completion ───────────────────────
  const dot = context.matchBefore(/\.[A-Za-z_]*$/);
  if (dot) {
    return {
      from: dot.from + 1,
      options: METHODS,
      validFor: /^[A-Za-z_]*$/,
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
      if (isCallbackSlot) {
        const word = context.matchBefore(/[A-Za-z_]+$/);
        if (!word && !context.explicit) return null;
        return {
          from: word ? word.from : pos,
          options: CALLBACKS,
          validFor: /^[A-Za-z_]*$/,
        };
      }
    }
  }

  // ── 4. Top-level identifier prefix ─────────────────────────
  const ident = context.matchBefore(/[A-Za-z_]*$/);
  if (ident && (ident.from < ident.to || context.explicit)) {
    return {
      from: ident.from,
      options: TOP_LEVEL,
      validFor: /^[A-Za-z_]*$/,
    };
  }

  return null;
}
