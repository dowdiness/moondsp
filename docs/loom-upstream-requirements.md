# Loom upstream requirements from mini-CST authoring evidence

- **Status:** Requirements extracted from the `moondsp` mini-CST spike.
- **Audience:** upstream `dowdiness/loom` / `dowdiness/seam` follow-ups.
- **Scope:** authoring-only parser/projection ergonomics. This does not approve
  a production mini parser switch.

## Evidence base

The current evidence is intentionally spec-local:

- Production mini authoring still uses `mini/incr_authoring.mbt`, which keeps a
  last successful `PatternDoc`, accepts editor source-edit spans, and reuses one
  lowering cache across reparses.
- The Loom comparison lives under `specs/loom-mini-cst/` and constructs a
  parser with `@loom.new_parser(input, mini_grammar)`, shares
  `parser.runtime()` with the projection memo, and exposes the result through a
  long-lived observer.
- `specs/loom-mini-cst/src/projection.mbt::LoomMiniAtomProjection::new` now
  uses Loom's `ProjectionIdentityTracker` and `ProjectionStringIdAllocator` for
  last-good atom identity, optional editor-edit handling, failed-input edit
  composition across recovery, source-diff fallback, and fresh ID allocation.
  The spec-local `pending_source_edit` shim has been removed; the projection
  records the current edit/source-before-edit signals and delegates baseline
  selection to Loom.
- `specs/loom-mini-cst/src/projection_test.mbt` contains the provenance matrix,
  recovery matrix helper, and PR #104 control-method cache-reuse helper that
  define the current regression evidence.
- The Phase 2 Piece 2 song layer (PR #192) adds a second, structurally distinct
  grammar/projection over the same lexer: `song_grammar` / `parse_song_root`
  (`specs/loom-mini-cst/src/parser.mbt`) for `song(...)` wrapper forms, and
  `loom_mini_parse_song` (`specs/loom-mini-cst/src/projection.mbt`) projecting to
  a real `@song.Song[ControlMap]`, with a name-and-value differential harness in
  `specs/loom-mini-cst/src/song_projection_test.mbt`. Requirements 5–8 below were
  extracted from that work — they are authoring ergonomics, not parity gaps (the
  song harness is green).

These requirements are about upstreaming the reusable parts of that pattern.
They do not ask `moondsp` to add loom/seam to root `moon.mod`, route
`mini.parse` through Loom, or redo PR #104's `.cutoff(...)`, `.gain(...)`, and
`.pan(...)` projection parity.

## 1. Stable identity across edits

### Requirement

Loom should provide, or document a small companion abstraction for, stable
projection identity across editor edits. The abstraction must be stronger than
"this CST subtree was reused" or "this token has the same source span". A
semantic projection needs to map unchanged user-facing leaves to the same domain
IDs after:

- insertions among duplicate tokens;
- deletions that shift later tokens left;
- replacements inside one duplicate family;
- whitespace-only edits;
- line/layer insertions that change surrounding CST shape; and
- temporary syntax diagnostics followed by recovery.

The API should let an authoring layer supply an editor edit span when available,
fall back to source diffing when it is not, and keep enough baseline information
for recovery after a malformed intermediate document. Domain code must still be
able to choose its public ID shape; in `moondsp` that shape is
`mini:sound:<name>:<n>` and `mini:note:<value>:<n>`.

### Current workaround in `moondsp`

`LoomMiniAtomProjection` delegates prefix/suffix ID realignment, optional
editor-edit handling, failed-input edit composition, source-diff fallback, and
fresh string-ID allocation to Loom's projection identity helpers. The remaining
local logic only stores the current editor edit/source-before-edit signals and
passes them to `ProjectionIdentityTracker`; it no longer keeps a separate
pending edit shim.

### Acceptance evidence to preserve

An upstream identity helper should be able to replace the spec-local realignment
without weakening these checks:

- duplicate sound/note insertion, deletion, and replacement rows in the
  provenance matrix;
- whitespace-only edits preserving sourced event IDs;
- `$:` line insertion and layer-comma edits preserving unaffected IDs;
- parse-error recovery from `s("bd sd bd bd"` to `s("bd sd bd bd")` producing
  `mini:sound:bd:0`, `mini:sound:sd:0`, `mini:sound:bd:2`,
  `mini:sound:bd:1`; and
- lowered-event ID and lowering-cache reuse checks, including the PR #104
  unchanged control-method chain case.

## 2. Projection helper ergonomics

### Requirement

Loom/seam should make direct CST projection boring and hard to misuse. A
semantic projection needs direct-child and direct-token queries with predictable
cardinality behavior, source ranges, and ordering. It should not rely on
accidental recursive traversal when validating method arguments or nested
callback syntax.

Useful upstream surface area would include:

- a consistent projection layer around the existing direct child/token query
  primitives, including optional/required `token_of_kind`-style helpers;
- cardinality helpers that turn "expected one direct method name" or "expected
  no direct comma" into concise projection code;
- projection examples that use `@loom.new_parser`, `parser.runtime()`,
  `parser.syntax_tree()`, and `parser.diagnostics()` without constructing a raw
  imperative parser inside a derived computation; and
- guidance for the `SyntaxNode -> private IR -> domain document` pattern, so
  projection code does not encode domain semantics directly in CST traversal.

### Current workaround in `moondsp`

The mini spike uses direct seam queries where they exist, but still keeps local
traversal wrappers and many repeated cardinality checks in `projection.mbt`.
That was acceptable for a spec, but it is too much hand-rolled boilerplate for a
reusable authoring pattern.

### Acceptance evidence to preserve

A helper pass is successful only if the existing projection tests keep catching
nested-argument mistakes, invalid callback-shaped method arguments, and
mode-incompatible atoms. Ergonomic helpers must not make the projection more
permissive than the current spec-local semantics.

## 3. Diagnostics plus last-good semantic document

### Requirement

Loom should document, and ideally provide a small attachment template for, the
canonical authoring pattern:

1. parse diagnostics update immediately;
2. a malformed CST does not replace the last successful semantic document;
3. the next successful parse can reuse the last successful semantic document
   and the original edit baseline; and
4. callers can adapt the richer state back to a compatibility
   `Result[..., String]` API when a project has not chosen a public diagnostic
   type.

The important distinction is that parser diagnostics and semantic projection
state are related but not the same cell. Diagnostics should be observable for an
editor, while the semantic document used for reuse remains the last known-good
one until projection succeeds again.

### Current workaround in `moondsp`

`LoomMiniAtomProjection::new` reads parser diagnostics before projection. When
diagnostics are present, it returns `Err("loom mini syntax has diagnostics")`
without updating `previous_doc` or committing a new tracker baseline. It calls
`ProjectionIdentityTracker::record_failed_input_with_optional_edit(...)` for
syntax and semantic projection failures. After recovery,
`realign_success_with_optional_edit(...)` uses the tracker's composed failed
edit or source-diff fallback, and `commit_success(...)` updates the reusable
baseline only after a successful document is built.

### Acceptance evidence to preserve

The recovery matrix helper should remain the minimum regression gate:

- initial valid input has zero diagnostics;
- malformed input has parser diagnostics and projection returns the expected
  error;
- both Loom projection and `MiniAuthoringPipeline` reject the malformed state;
- recovered input has zero diagnostics; and
- recovered sourced event IDs match the current mini authoring pipeline.

A future upstream example should also cover semantic projection failures that
are not syntax diagnostics, such as mode-incompatible atoms, and state whether
those failures retain or replace the last-good semantic document.

## 4. Authoring-only dependency boundaries

### Requirement

Loom adoption must be easy to isolate as authoring infrastructure. A downstream
library should be able to keep runtime parsing independent from Loom while using
Loom for editor diagnostics, CST projection, and incremental authoring tests.

For `moondsp`, that means:

- no accidental loom/seam path dependencies in root `moon.mod`;
- no dependency from browser/runtime packages to the nested
  `specs/loom-mini-cst` module;
- a publishable dependency story before any production package depends on Loom;
- wasm-gc/browser build proof if Loom enters any package reachable from the
  AudioWorklet path; and
- a clear authoring facade so existing mini callers do not need to learn Loom
  APIs.

### Current workaround in `moondsp`

The spike is a nested, non-publishing module with path dependencies to editable
Loom/seam checkouts. That is useful as an upstream API canary, but it is not a
release plan for the published `dowdiness/moondsp` package.

### Acceptance evidence to preserve

An upstream or downstream promotion plan should include a manifest check proving
that Loom remains out of the runtime graph unless the same change also proves
browser target compatibility. Until then, `specs/loom-mini-cst/` remains the
right home for Loom evidence in this repository.

## 5. Lexer modes for opaque string-literal contexts

### Requirement

A grammar that has more than one kind of quoted string needs lexer context.
Loom should make mode-aware lexing the documented authoring path when a grammar
mixes a tokenized string context with an opaque (raw-until-delimiter) one, not
just an advanced corner of the lexer API.

The song grammar has exactly this shape. Inside `song(...)` the same `"..."`
delimiter wraps two different things:

- *notation* strings such as the body of `s("bd sd")`, whose interior must
  tokenize as mini-notation (idents, numbers, brackets, postfix operators); and
- *opaque literal* strings such as `section("verse", …)`, `part_id("verse:1",
  "Verse 1", …)`, and `fill("fill", …)`, whose interior is arbitrary text — it
  may contain `:` and spaces and must not be interpreted as notation.

A context-free `@core.PrefixLexer` (`@core.LanguageSpec` with `lex_step`) cannot
tell these apart, because it sees only a prefix, never the surrounding grammar
state.

### Current workaround in `moondsp`

The spike keeps a single context-free lexer (`mini_step_lexer` in
`specs/loom-mini-cst/src/lexer.mbt`) and works around the opaque-literal case
twice:

- it adds a `Colon` token (`token.mbt`, `syntax_kind.mbt`, `lexer.mbt`) purely so
  that `:` inside an occurrence id (`"verse:1"`) lexes without an `Invalid`
  diagnostic; and
- it reconstructs each literal's value from the source span *between* the two
  quote tokens (`loom_song_string_value` in `projection.mbt`), instead of reading
  a single string token, because interior whitespace and `:` arrive as separate
  notation tokens.

This works for the corpus but does not generalize: any literal character the
notation lexer rejects would need yet another token, and the value is recovered
by span arithmetic rather than by lexing.

Loom already ships `ModeLexer[T, M]`
(`canopy/loom/loom/src/core/mode_lexer.mbt`) with per-token mode tracking and an
incremental re-lex path (`ModeRelexState`), which is exactly the right tool — a
`Normal`/`InString` mode would emit one raw string-content token. The gap is
discoverability and authoring guidance: the `@loom.Grammar` factory and the
parser-authoring examples only demonstrate `PrefixLexer`, so a grammar that needs
string contexts has no signposted path to `ModeLexer`.

### Acceptance evidence to preserve

A mode-aware reworking of the song lexer must keep the song parity harness green:
occurrence ids containing `:` (`"verse:1"`, `"fill:0"`) and display names
containing spaces (`"Verse 1"`) must round-trip to the same literal the oracle's
`read_quoted_string` produces, and section bodies must still tokenize as full
mini-notation.

## 6. Separated-list parsing and delimiter-aware child grouping

### Requirement

Repeated, separator-delimited arguments are common (`stack(a, b, c)`,
`song(item, …)`, method argument lists). Loom should make it easy to both parse
and project them without re-deriving element boundaries from source offsets.
Useful surface area:

- a parse-time separated-list combinator that wraps each element in its own node
  (so the CST records argument boundaries), and/or
- a projection helper that groups a node's direct children by a separator token
  kind.

### Current workaround in `moondsp`

`parse_stack_call` emits each stack argument's base call and its trailing
`.method(...)` calls as *flat siblings* of `StackCallNode`, separated by
`CommaToken` leaves, with no per-argument wrapper node. Because
`SyntaxNode::children()` returns only nodes (commas are tokens), the projection
cannot walk children to recover argument boundaries. `loom_mini_collect_stack_expr`
(`projection.mbt`) therefore groups arguments by counting how many comma
`start()` offsets precede each child node's `start()` — correct, but fragile
offset arithmetic that every comma-delimited construct would have to repeat.

seam does expose ordered node+token traversal (`SyntaxNode::all_children() ->
Array[SyntaxElement]`, `direct_elements_iter()`), which would avoid the offset
math; but there is still no abstraction that turns "comma-separated arguments"
into per-element groups, at either parse or projection time.

### Acceptance evidence to preserve

The doc-level method-chained-stack test
(`stack(s("bd").fast(2), note("60").rev())`) and the multiline song corpus case
(method chains on stack arguments across newlines) must keep value-level event
parity with the oracle; a separated-list helper must not regroup or drop a
trailing/empty argument differently from the current grouping.

## 7. Token adjacency / no-trivia contiguity check

- **Status:** Fulfilled upstream — loom#280 shipped
  `ParserContext::at_adjacent(expected)` and `expect_adjacent(expected, kind)`
  (loom PR #284, 2026-06-10). `expect_song_keyword` now uses `at_adjacent`; the
  hand-rolled `current_token_range` offset comparison described below is gone.

### Requirement

A grammar that lexes `keyword(` as a single contiguous unit needs a way to
reject a space before the paren when the keyword is instead lexed as
`Ident` + `LParen`. Loom should provide a contiguity primitive — e.g.
`ctx.expect_adjacent(token, kind)` or a "no trivia before next token" query — so
that whitespace sensitivity does not require manual offset comparison.

### Current workaround in `moondsp`

The oracle matches `song(` / `section(` / `part(` etc. as contiguous literals
(`Parser::match_keyword`), so it rejects `song (`. The loom song grammar lexes
these keywords as `Ident` (the `['s','(']`-style rules only fire for the
production calls), and `ctx.peek()` skips trivia, so the keyword and `(` are not
naturally adjacent-checked. `expect_song_keyword` (`parser.mbt`) reproduces the
oracle by capturing `ctx.current_token_range().end` before emitting the keyword
and asserting the following `LParen`'s `current_token_range().start` equals it.
This is correct but hand-rolled, and any keyword-paren construct would repeat it.

### Acceptance evidence to preserve

The malformed song corpus rows `song (section(...),...)` and
`song(section (...),...)` must remain rejected by both the loom projection and
the oracle (`assert_song_both_reject`), and the contiguous forms must keep
parsing.

## 8. Covered-source text accessor on CST nodes

### Requirement

Projection frequently needs the source text a node spans (string literal values,
numeric literals, sub-expression slices). seam exposes `SyntaxNode::start()`,
`end()`, and `tight_span()`, plus token-level `text()`, but no node-level
accessor returning the covered source substring. A `SyntaxNode::text()` (or
`source_text()`) would let projection read spans without threading the original
source string through every helper.

### Current workaround in `moondsp`

`loom_mini_parse_song` carries the original `input : String` into every collector
and slices it with `input.view(start_offset=…, end_offset=…)` to recover literal
values (`loom_song_string_value` in `projection.mbt`), because there is no
`node.text()`. This couples projection helpers to the raw source argument purely
to do span extraction seam already has the offsets for.

### Acceptance evidence to preserve

Literal extraction must keep producing the exact oracle value (including interior
spaces and `:`), and a node-level text accessor must agree with the current
quote-span slice on every song corpus literal.

## Open upstream design questions

- Does stable projection identity live on syntax tokens, CST nodes, an edit
  lineage map, or a separate authoring projection helper?
- Should projection cardinality helpers live in `seam` because they operate on
  CST views, or in `loom` because they are part of parser-authoring guidance?
- Is the diagnostics/last-good pattern a library type, an example attachment, or
  both?
- How should whole-source `set_source` recovery differ from editor-span
  `apply_edit` recovery when no precise edit span is available?
- Should a grammar mixing tokenized and opaque string contexts always reach for
  `ModeLexer`, and what is the recommended `@loom.Grammar` wiring for it (the
  factory currently signposts only `PrefixLexer`)?
- Do separated-list grouping and the `keyword(`-adjacency check belong in `seam`
  (CST views / projection) or in `loom` (parser-authoring combinators)?
- Is a node-level covered-source accessor a `seam` `SyntaxNode` method, or should
  projection always thread the source string explicitly?
