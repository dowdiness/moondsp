# ADR-0013: Loom promotion criteria for mini authoring

- **Status:** Proposed
- **Date:** 2026-05-25
- **Source:** Follow-up design pass after PR #76 grammar parity, updated with
  PR #85 apply-edit parity evidence and PR #91–#112 projection, parity,
  recovery, and identity-helper work

## Context

ADR-0004 chose the hand-written mini parser because Phase 5 needed parsing
inside the AudioWorklet wasm-gc build and loom did not clear that risk gate
within the implementation budget. ADR-0011 then wrapped the hand-written
`PatternDoc` parser in `MiniAuthoringPipeline`, preserving stable subtree IDs
and lowering-cache reuse across edits. ADR-0012 scoped a loom/CST evaluation
outside the production parser path.

PR #76 expanded `specs/loom-mini-cst/` to cover the production grammar shape.
That was an important result, but it was not a production parser switch. PRs
#80, #81, #83, and #85 then added a spec-local `SyntaxNode -> PatternDoc`
projection path, chained root-method coverage, seam direct-query traversal,
and apply-edit parity against `MiniAuthoringPipeline` for replacement,
whitespace, method-name, duplicate-note, and parse-error recovery cases. PRs
#91–#104 then filled major syntax, provenance, and edge-case gaps: recursive
sub-notation/group postfix projection, production `$:` stack-line support in
the hand-written parser, Loom `$:` stack-program projection, direct callback
method projection/lowering, callback variants, callback edit/reuse parity
inside both direct expressions and `$:` stack-line programs, known edge-case
characterization, spec-local rejection of mode-incompatible atoms, the reviewed
full-grammar provenance matrix, and production control-method projection for
`.cutoff(...)`, `.gain(...)`, and `.pan(...)` with lowered-event and cache-reuse
checks. PR #107 then expanded the recovery matrix across `$:` stack lines,
direct and `$:` callbacks, control methods, and projection-only semantic
failures. PRs #109–#112 consumed upstream Loom projection helpers for stable
identity, collision-free string ID allocation, optional editor edits,
source-diff fallback, and failed-edit composition, removing the spec-local
`pending_source_edit` shim without changing production parsing.

Those PRs improve the evidence for a future loom-backed authoring path, but
they still live under the nested `specs/loom-mini-cst` module. Production mini
authoring still goes through `mini/incr_authoring.mbt`, which calls the
hand-written `parse_doc_with_token_identities` path and keeps the last
successful `PatternDoc` for reuse after parse errors.

This memo defines what would justify switching mini authoring to loom. It does
not implement the switch, add loom/seam to the root `moondsp` module, or fix
PR #76's documented follow-ups.

## Current state

The hand-written authoring path already owns these production contracts:

- `MiniAuthoringPipeline::set_input_with_source_edit(...)` accepts editor
  source spans for ambiguous identical-token edits.
- Successful parses update the reusable `PatternDoc`; failed parses return
  `Err(String)` without replacing the last successful document.
- Token-aware leaf IDs keep the public atom shape
  `mini:sound:<name>:<n>` and `mini:note:<value>:<n>` inside authoring flows.
- Lowering uses one persistent `PatternLoweringCache`, so stable IDs translate
  into lower recomputation after parsing.
- Runtime `parse(input)` remains independent of loom and continues to build in
  the browser-oriented module graph.

The loom spec path now proves these evaluation-only contracts:

- The expanded CST grammar can parse representative production mini syntax,
  including the live-demo pattern from PR #76, with zero diagnostics.
- `@loom.new_parser(...).apply_edit(...)` has nonzero reuse coverage across
  several method, postfix, sub-notation, and layer-comma edits.
- The spec-local projection can lower a private recursive notation IR to
  `PatternDoc` for atom groups, stacks, top-level `$:` stack programs,
  sub-notation/groups, `.fast`, `.slow`, `.rev`, chained root methods,
  production control methods for `.cutoff(...)`, `.gain(...)`, and
  `.pan(...)`, direct and `$:` callback methods for `.jux(...)` /
  `.every(...)`, and atom/group postfixes for `*N`, `/N`, `?`, and Euclid,
  then compare public root/leaf IDs against `@mini.parse_doc`.
- PRs #85, #96, #97, and #101 expanded apply-edit parity against
  `MiniAuthoringPipeline` for duplicate sound/note insertion and deletion,
  unaffected-token replacement, whitespace-only insertion, method-name
  replacement, duplicate-note edits, callback replacement, `$:` callback
  replacement, parse-error recovery with previous provenance, source-edit span
  rows, and lowered event ID checks across the reviewed grammar matrix.
- PRs #99 and #100 characterized the documented known edges: empty notation and
  trailing-comma layers are CST-only recovery, unterminated brackets remain a
  bounded CST recovery-quality follow-up, and digit-start/mode-incompatible
  atoms now reject at projection time rather than being silently dropped.
- PR #104 closed the named control-method projection gap by matching
  `@mini.parse_doc` for `.cutoff(...)`, `.gain(...)`, and `.pan(...)`, checking
  lowered control-map behavior, and pinning unchanged control-method chains as
  lowering-cache hits after whitespace edits.
- PR #107 expanded recovery evidence for `$:` stack-line syntax, direct and
  `$:` callback syntax, control-method syntax, and projection-only semantic
  failures, while checking recovered root IDs against `MiniAuthoringPipeline`.
- 2026-05-29/31 follow-ups adopted Loom's stable projection identity helpers in
  the spec-local projection: `ProjectionIdentityTracker` now owns the
  last-good atom baseline, optional editor-edit handling, failed-input edit
  composition across recovery, and source-diff fallback;
  `ProjectionStringIdAllocator` owns collision-free string ID allocation; and
  PR #112 removed the spec-local `pending_source_edit` shim. The production
  parser remains unchanged.
- The spec remains a nested module with path dependencies to loom, seam,
  pretty, and incr. It is intentionally not part of the published `moondsp`
  library surface.

The root release manifest is now `moon.mod`; `moon.mod.json` remains only in
the nested loom spike module. That cleanup does not by itself make loom a
publishable production dependency. Any promotion still needs an explicit
release-manifest proof that path dependencies stay out of published `moondsp`
packages or are isolated behind a deliberate authoring-only boundary.

## Non-goals

This ADR does not approve any of the following:

- Routing `mini.parse`, `parse_doc`, or `MiniAuthoringPipeline` through loom.
- Adding loom, seam, or other loom-stack packages to the root `moon.mod`.
- Pulling the nested `specs/loom-mini-cst` path dependencies into releasable
  `moondsp` code.
- Publishing, tagging, or otherwise unblocking a release.
- Treating shipped spec-local parity for atom/group postfixes, sub-notation,
  `$:` stack programs, or callback methods as approval to route production
  parsing through loom.
- Changing the public `Result[..., String]` error shape as a side effect of a
  parser implementation swap.

## Forcing functions

Switching authoring to loom is justified only if one or more of these becomes
true:

- Mini grammar changes repeatedly require touching several hand-written parser
  functions, making grammar drift more likely than a CST projection bug.
- An editor needs structured syntax, ranges, recoverable diagnostics, or
  partial-tree behavior that the current `Err(String)` parser cannot provide.
- Whole-document parsing becomes a measured authoring bottleneck after the
  existing lowering-cache reuse is accounted for.
- Runtime and authoring grammar behavior diverge often enough that a single
  grammar source becomes cheaper than keeping both parser paths aligned.
- Loom and its companion packages have a versioned dependency story that fits
  `moondsp` release and publish constraints without local path dependencies.

The following are not sufficient forcing functions by themselves:

- Grammar parity in `specs/loom-mini-cst/`.
- Nonzero CST reuse counts without full `PatternDoc` provenance parity.
- The shipped apply-edit, postfix/sub-notation, `$:`, and callback parity
  slices while they remain spec-local and syntax-limited.
- A root-manifest migration or release-prep branch that does not prove a
  publishable loom dependency graph.
- A desire to delete duplicate parser code while the current production path
  is still small, tested, and release-compatible.

## Costs

A loom authoring switch would add real ownership and release cost:

- Main-package dependency cost: `moondsp` would need published, versioned loom
  and seam dependencies or an internal package boundary that keeps path deps
  out of releasable code.
- Build-graph cost: browser and wasm-gc builds need explicit proof after the
  dependencies enter the main module, not just isolated loom-spec tests.
- Projection cost: the CST path needs a `SyntaxNode -> PatternDoc` projection
  that preserves public IDs, aggregate signatures, callback semantics, method
  lowering semantics, and parse-error behavior.
- IR-shape cost: the current spec projection now has recursive notation,
  top-level `$:` program, and callback-method structures, but they remain an
  evaluation IR rather than a stable production boundary.
- Compatibility cost: existing `MiniAuthoringPipeline` callers should not need
  to learn loom APIs. The public surface should remain text in, `PatternDoc` or
  snapshot out.
- Test cost: the existing source-edit tests in `mini/mini_test.mbt` and the
  PR #85 projection parity cases become migration gates, not examples to
  rewrite around.
- Maintenance cost: until runtime parsing also moves, production still has two
  semantic parser implementations: runtime recursive descent and authoring CST
  projection.

## Remaining promotion gates

The shipped apply-edit, postfix/sub-notation, PR #101 provenance-matrix,
PR #104 control-method, PR #107 recovery, and PR #109–#112 helper-adoption
slices close several early questions, but loom still cannot own mini authoring
until these gates have direct evidence:

- **Full PatternDoc provenance in any production-shaped prototype:** PR #101
  provides the reviewed spec-local matrix for duplicate-token insertion,
  deletion, replacement, whitespace edits, method/callback edits, `$:` edits,
  source-edit spans, recovery, and lowered event IDs. Any promotion prototype
  must keep that matrix passing through the candidate authoring boundary
  without weakening stable-ID or lowering-cache assertions.
- **Error recovery:** PR #107 provides spec-local evidence that parser
  diagnostics and projection-only semantic failures do not replace the last
  successful reusable authoring document across broader grammar contexts. This
  gate remains open until the same behavior passes through a production-shaped
  authoring boundary without weakening stable-ID assertions.
- **Semantic projection:** CST parsing alone is not enough. The projection must
  produce the same `PatternDoc` values and lowered event behavior for stack,
  method chains, callbacks, controls, Euclid, postfix, layers, and
  sub-notation. PR #104 closes the previously named spec-local control-method
  gap for `.cutoff(...)`, `.gain(...)`, and `.pan(...)`; this gate remains open
  until the full projection and provenance evidence passes through a
  production-shaped authoring boundary without weakening reuse assertions.
- **Public error shape:** callers currently receive `Result[..., String]`.
  Either loom diagnostics must be adapted to that shape or the public API
  change needs a separate decision.
- **Release manifest:** the root `moon.mod` and package contents must remain
  publishable. If loom stays authoring-only, the package boundary must make it
  impossible for nested spec path deps to leak into the published runtime graph.
- **Runtime isolation:** authoring-only adoption must not pull loom/seam into
  the AudioWorklet runtime path unless the browser build proof is part of the
  same decision.
- **Known spec follow-ups:** PR #99 records permissive empty notation,
  trailing-comma layers, unterminated-bracket recovery, and digit-start atom
  lexing as explicit promotion evidence; PR #100 hardens the digit-start /
  mode-incompatible atom projection mismatch. Unterminated-bracket recovery
  remains a CST recovery-quality follow-up, not a production parser mismatch.

## Migration criteria

The switch is acceptable when all of these are true:

- A loom-backed authoring prototype uses `@loom.new_parser` as the parser
  surface, keeps the parser engine outside downstream memo bodies, and shares
  `parser.runtime()` with attached projections.
- The prototype passes the existing `MiniAuthoringPipeline` source-edit tests
  and the PR #85 projection parity cases without weakening assertions around
  stable IDs, lowering-cache hits, parse errors, or duplicate atom/note
  provenance.
- Projection tests compare hand-written `parse_doc` output against the loom
  projection for the full PR #76 grammar surface, including the shipped
  postfix, `$:`, and callback-method structures, without relying on accidental
  traversal behavior.
- Lowering tests prove the same observable pattern events for syntax whose
  `PatternDoc` shape alone is not enough to catch semantic drift.
- A release check proves the dependency graph is acceptable for published
  `moondsp`: root `moon.mod` has no accidental loom-stack path deps, package
  contents do not include the spike module as production code, and any
  authoring-only boundary is explicit.
- Browser wasm-gc checks pass if loom enters any package reachable from the
  browser build.
- The PR plan names which behavior differences are intentional, with separate
  follow-ups for PR #76's documented edge cases instead of hiding them inside
  promotion.

## Recommended path

Do not switch production mini authoring to loom yet.

The useful next steps are to preserve the spec-local evidence as promotion
requirements, not to route production parsing through loom:

1. Keep `specs/loom-mini-cst/` as the grammar, projection, and reuse
   characterization gate.
2. Treat the known edge cases as recorded promotion evidence: empty notation
   and trailing-comma layers are CST-only recovery, unterminated-bracket input
   is bounded but noisy CST recovery, and digit-start/mode-incompatible atoms
   reject during projection instead of silently dropping tokens.
3. Treat PR #101's full-grammar provenance matrix and PR #107's expanded
   recovery matrix as regression gates for duplicate-token edits,
   method/callback edits, `$:` stack-line edits, parse diagnostics,
   projection-only semantic failures, source-edit spans, and lowered event
   behavior.
4. Treat PR #104's production control-method projection, lowered-control, and
   cache-reuse checks as regression evidence for any future authoring
   prototype.
5. Keep consuming upstream Loom helpers when they preserve the spec-local
   evidence: the mini projection now uses the stable identity tracker,
   string-ID allocator, optional-edit handling, source-diff fallback, and
   failed-edit composition. There is no remaining spec-local exact-edit shim;
   further downstream work should be a production-shaped authoring facade, not
   parser routing.
6. Use the extracted upstream Loom requirements for stable identity across
   deletion/shift edits, projection helper ergonomics, and the canonical
   "diagnostics plus last successful semantic document" authoring pattern when
   working upstream. The requirements live in
   [`../loom-upstream-requirements.md`](../loom-upstream-requirements.md).
7. Only after full grammar, provenance, lowering, release-manifest, and browser
   build gates pass, decide whether to put the projection behind
   `MiniAuthoringPipeline` as an authoring-only implementation detail.

PR #70's deletion-safe reuse contract, PR #76's grammar-parity contract, PR
#80/#81/#83's projection-IR evidence, PR #85's apply-edit parity evidence, PR
#91–#100's postfix, `$:`, callback, and known-edge evidence, PR #101's
full-grammar provenance matrix, PR #104's control-method projection parity,
PR #107's expanded recovery matrix, and PR #109–#112's identity-helper adoption
should all continue to exist. They answer
different questions: whether loom can reuse safely across edits, whether it can
express the production mini grammar shape, whether a CST can project to
`PatternDoc`, and whether projection can track authoring edit provenance across
representative syntax families. A production switch requires all of those, plus
the remaining promotion gates above.
