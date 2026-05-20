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
subtrees by stable ID, subtree token, and revision.

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
- Successful parses update the last reusable `PatternDoc`.
- Parse errors are returned as `Err(String)` and do not replace the last
  successful reusable document.
- Lowering is a second derived memo over the parsed document and uses one
  persistent `PatternLoweringCache`.
- A `Scope` owns the long-lived incr cells, and persistent `Observer` handles
  anchor the parsed and lowered reads for the pipeline lifetime.

This is incremental recomputation around whole-document parsing. It is not yet
token-level incremental parsing: every text edit still reparses the whole mini
source string. The first reuse benefit is stable-subtree identity plus
lowering-cache reuse after parsing.

## Consequences

**Positive**

- The stable-ID/cache-reuse contract is tested without changing the parser.
- Runtime parser behavior remains separate from the authoring `PatternDoc`
  parser behavior.
- Parse-error recovery is explicit: a bad edit reports an error, while the next
  valid edit can still reuse the previous successful document.
- The pipeline uses incr's lifecycle model directly (`Scope` plus persistent
  `Observer` anchors), so later authoring UI code has a concrete ownership
  pattern to follow.

**Negative**

- The pipeline does not reduce parse cost yet; it only reduces downstream
  lowering work when stable IDs survive an edit.
- The parsed memo closes over mutable `previous` state. That state is part of
  the contract and must not be updated on parse errors.
- Public API surface grows with an experimental authoring type before there is
  a full editor integration.

## Revisit when

Add edit-span and token-identity tests before deciding whether loom enters the
design. The next design question is whether loom owns token/CST identity before
`parse_doc_reusing`, or whether the current parser first gains a narrower
tokenization layer that feeds the existing `PatternDoc` builder.
