// CodeMirror language support for the moondsp live REPL surface
// (Strudel-style `$:` lines, `+` overlays, groups, and method chains).
// Wraps the Lezer parser with style tags for highlighting
// and registers the autocomplete source via languageData.

import { LRLanguage, LanguageSupport, syntaxHighlighting, defaultHighlightStyle } from "@codemirror/language";
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
    commentTokens: {},
    closeBrackets: { brackets: ["(", "[", '"'] },
    autocomplete: miniliveCompletion,
  },
});

export function minilive(): LanguageSupport {
  return new LanguageSupport(miniliveLanguage, [
    autocompletion(),
    syntaxHighlighting(defaultHighlightStyle, { fallback: true }),
  ]);
}
