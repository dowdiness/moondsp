// CodeMirror language support for the moondsp live REPL surface
// (mini-notation embedded in identifier-headed calls and method
// chains). Wraps the Lezer parser with style tags for highlighting
// and registers the autocomplete source via languageData.

import { LRLanguage, LanguageSupport, syntaxHighlighting, defaultHighlightStyle } from "@codemirror/language";
import { autocompletion } from "@codemirror/autocomplete";
import { styleTags, tags as t } from "@lezer/highlight";

import { parser } from "./minilive.grammar";
import { miniliveCompletion } from "./minilive-completion";

const parserWithMetadata = parser.configure({
  props: [
    styleTags({
      CallName: t.function(t.variableName),
      MethodName: t.propertyName,
      String: t.string,
      Number: t.number,
      "( )": t.paren,
      ".": t.derefOperator,
      ",": t.separator,
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
