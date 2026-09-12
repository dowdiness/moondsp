# ADR-0011: Incr-backed mini authoring pipeline

- **Status:** Accepted
- **Date:** 2026-05-20
- **Source:** Phase 6+ incremental reparsing design slice

## Context

`mini/` now has two parser surfaces:

- `parse(input) -> Result[Pat[ControlMap], String]`, the runtime parser entry
  point used by playback-oriented callers.
- `parse_doc(input)` and `parse_doc_reusing(input, previous)`, the
  identity-bearing `PatternDoc` parser entry points used by authoring flows.

`parse_doc_reusing` already gives deterministic stable IDs and can preserve
unchanged subtrees when an edited string still produces the same
`PatternNodeId`s. `PatternLoweringCache` can then reuse lowered pattern
subtrees by stable identity and the complete dependency identity, including
referenced definitions. Playback and provenance share one compiled result;
editing revisions remain separate from cache identity.

Phase 6+ needs an incremental authoring pipeline, but replacing the
hand-written parser or introducing loom too early would mix two separate
questions: whether the authoring cache contract is right, and whether a
token/CST parser should own future edit spans.

## Decision

Add `MiniAuthoringPipeline` as a small `dowdiness/incr` wrapper around the
existing `PatternDoc` parser before replacing any parser code.

The pipeline contract is:

- The source text is the only mutable input signal.
- Parsing is a derived incr memo that calls `parse_doc` for the first parse and
  `parse_doc_reusing` after the first successful `PatternDoc`.
- Parser-local previous-document state is updated only after successful parses
  and exists solely to preserve stable identity on later valid edits.
- An accepted derived tracks the parsed candidate and retains the latest
  successful document. It has no value before the first successful parse.
- Parse errors remain visible on the current channel and update neither the
  parser reuse baseline nor the accepted channel.
- Construction primes the initial candidate before the eager accepted fold so
  parser-local mutation does not occur inside a reactive compute context.
- Lowering is a second derived memo over the parsed document and uses one
  persistent `PatternLoweringCache`.
- A `Scope` owns the long-lived incr cells, and persistent `Observer` handles
  anchor the parsed and lowered reads for the pipeline lifetime.

This is incremental recomputation around whole-document parsing. It is not yet
token-level incremental parsing: every text edit still reparses the whole mini
source string. The first reuse benefit is stable-subtree identity plus
lowering-cache reuse after parsing.

## Boundary note

`mini/moon.pkg` is the intentional production package that imports the full
`dowdiness/incr` facade: `MiniAuthoringPipeline` owns `Scope`, `Signal`, `Memo`,
and persistent `Observer` cells. Packages that only need `BackdateEq`,
`HasChangedAt`, or `Revision` vocabulary should import `dowdiness/incr/types`
instead. `scripts/check-incr-import-boundaries.sh` keeps the full-facade
carve-out list explicit and ADR-referenced.

## Consequences

**Positive**

- The stable-ID/cache-reuse contract is tested without changing the parser.
- Runtime parser behavior remains separate from the authoring `PatternDoc`
  parser behavior.
- Parse-error recovery is explicit: a bad edit reports an error on the current
  channel, the accepted channel retains the last valid document, and the next
  valid edit can still reuse its identity baseline.
- The pipeline uses incr's lifecycle model directly (`Scope` plus persistent
  `Observer` anchors), so later authoring UI code has a concrete ownership
  pattern to follow.
- The mini token layer now has an internal contiguous token edit-span helper.
  It preserves unchanged prefix/suffix token identity and allocates fresh keys
  inside the changed window, including duplicate-token insertion/deletion
  cases.
- `MiniAuthoringPipeline::set_input_with_source_edit(...)` gives editor
  integrations a concrete way to provide cursor-owned source edit spans without
  exposing the token-span representation.
- The pipeline feeds aligned token identities into `PatternDoc` atom IDs for
  sound/note leaves. Aggregate nodes remain structural, and public atom IDs keep
  the existing `mini:sound:bd:N` / `mini:note:60:N` shape.

**Negative**

- The pipeline does not reduce parse cost yet; it only reduces downstream
  lowering work when stable IDs survive an edit.
- The parsed memo closes over mutable previous-document state for identity
  reuse. That state must not be updated on parse errors and must not become a
  second consumer-facing acceptance policy.
- Token-aware atom IDs are currently attached inside `MiniAuthoringPipeline`;
  direct `parse_doc` / `parse_doc_reusing` calls keep deterministic structural
  occurrence IDs unless they are routed through a token-aware internal path.
  This keeps the public one-shot parser API stable and avoids accepting partial
  editor state without a clear owner for source edit spans.
- Public API surface grows with an experimental authoring type before there is
  a full editor integration.
- Old/new token sequences alone cannot represent cursor intent for ambiguous
  identical-token edits. Editor-provided source spans cover this for the
  current token layer; loom/CST ownership may still be preferable if future
  incremental parsing needs the CST to own token identity directly.

## Revisit when

Before deciding whether loom enters the design, compare the editor-provided
source-span path against loom/CST-owned token identity. The current path is
enough to preserve leaf identity and provenance for ambiguous identical-token
edits, but it still keeps parsing whole-document and leaves CST ownership
unresolved. ADR-0012 scopes that comparison as an authoring-only loom/CST
evaluation before any runtime parser migration.
