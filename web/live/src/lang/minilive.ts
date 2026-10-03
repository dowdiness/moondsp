// CodeMirror language support for the moondsp live REPL surface
// (Strudel-style `$:` lines, `+` overlays, groups, and method chains).
// Wraps the Lezer parser with style tags for highlighting
// and registers the autocomplete source via languageData.

import { LRLanguage, LanguageSupport, syntaxHighlighting, HighlightStyle, defaultHighlightStyle } from "@codemirror/language";
import { autocompletion } from "@codemirror/autocomplete";
import { styleTags, tags as t } from "@lezer/highlight";

import { parser } from "./minilive.grammar";
import { miniliveCompletion } from "./minilive-completion";

const parserWithMetadata = parser.configure({
  props: [
    styleTags({
      BindingName: t.definition(t.variableName),
      let: t.definitionKeyword,
      "=": t.definitionOperator,
      ";": t.separator,
      CallName: t.function(t.variableName),
      MethodName: t.propertyName,
      String: t.string,
      Number: t.number,
      LineComment: t.lineComment,
      BlockComment: t.blockComment,
      "( )": t.paren,
      ".": t.derefOperator,
      ",": t.separator,
      "$: +": t.operator,
    }),
  ],
});

export const miniliveLanguage = LRLanguage.define({
  parser: parserWithMetadata,
  languageData: {
    commentTokens: { line: "//", block: { open: "/*", close: "*/" } },
    closeBrackets: { brackets: ["(", "[", '"'] },
    autocomplete: miniliveCompletion,
  },
});

// Keep the established token coverage; adapt its palette to the workspace theme.
const scoreHighlightStyle = HighlightStyle.define([
  ...defaultHighlightStyle.specs,
  { tag: t.string, color: "var(--syntax-string, #97424d)" },
  { tag: t.number, color: "var(--syntax-number, #286653)" },
  { tag: [t.keyword, t.definition(t.variableName)], color: "var(--accent, #3e50a8)" },
  { tag: t.comment, color: "var(--ink-muted, #616a7a)", fontStyle: "italic" },
]);

export function minilive(): LanguageSupport {
  return new LanguageSupport(miniliveLanguage, [
    autocompletion(),
    syntaxHighlighting(scoreHighlightStyle, { fallback: true }),
  ]);
}
