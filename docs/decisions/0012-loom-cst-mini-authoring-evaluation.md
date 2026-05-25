# ADR-0012: Loom/CST evaluation for mini authoring

- **Status:** Proposed
- **Date:** 2026-05-21
- **Source:** Phase 6+ mini notation editing reliability spike

## Context

ADR-0004 chose the hand-written mini parser because Phase 5 needed runtime
parsing inside the AudioWorklet wasm-gc build, and loom did not clear that
risk gate within the implementation budget. ADR-0011 then added an
`incr`-backed authoring pipeline around the existing `PatternDoc` parser,
including source-edit-aware token identity realignment for ambiguous
duplicate-token edits.

That leaves a narrow ownership question before introducing loom for
incremental parsing:

- Should editor-provided source edit spans stay owned by the mini token layer?
- Or should a loom/seam CST own token identity and edit damage once mini has a
  CST?

This ADR starts a small evaluation only. It does not replace the runtime
parser and does not add a loom/seam dependency to `moondsp`. Because the same
team owns loom and incr, the evaluation may change those libraries directly if
their current APIs force awkward ownership boundaries for mini authoring.

## Findings

loom/seam has the shape needed for an authoring parser:

- `@loom.new_parser(source, grammar)` returns a reactive parser with
  edit-driven `apply_edit(edit, new_source)` and whole-source `set_source`.
- `@loom.Grammar::new(...)` packages lexing, CST parsing, AST folding,
  optional incremental relex, and block reparse policy.
- `seam` separates immutable, position-independent `CstNode`s from ephemeral
  positioned `SyntaxNode` views, which fits stable subtree reuse better than
  source-offset-only parser state.
- The JSON example in canopy demonstrates the expected grammar shape,
  diagnostic recovery, CST parsing, and reuse cursor setup.

The runtime risk from ADR-0004 is narrower than it was, but not resolved for
`moondsp`. On 2026-05-21, targeted wasm-gc tests passed for loom itself
(`rtk moon test --target wasm-gc` from canopy's `loom/loom` module: 253
tests) and for the JSON grammar example (`rtk moon test --target wasm-gc`
from canopy's `loom/examples/json` module: 92 tests). A workspace-level
`rtk moon build --target wasm-gc` from canopy's `loom/` checkout still fails
in sibling packages that use JavaScript/C FFI, matching canopy's documented
"WebAssembly is not a supported build target" warning.

That means loom core looks viable for an isolated wasm-gc proof, but runtime
adoption still needs a `moondsp` build-graph proof before loom can replace the
AudioWorklet parser.

## Ownership Options

**Option A: mini token layer owns edit identity**

Keep `MiniAuthoringPipeline::set_input_with_source_edit(...)` as the source of
truth for source edit spans. The token realignment layer preserves prefix and
suffix identity, allocates fresh keys inside the changed window, and feeds
token-backed leaf IDs into `PatternDoc`.

This is the lowest-risk production path. It keeps the one-shot runtime parser
and authoring parser behavior aligned, but it still reparses the whole mini
source and cannot reuse CST subtrees.

**Option B: loom/seam CST owns edit identity**

Move edit damage, token identity, diagnostics, and `PatternDoc` projection
behind a loom grammar. `PatternDoc` leaf IDs would derive from CST token
identity instead of the current mini token realignment helper.

This gives one parser-level owner for incremental reparse, but it requires a
mini grammar port, dependency work, duplicate-token identity proof, and a clear
answer for runtime wasm-gc support before it can replace the current parser.
Library API changes are in scope if they make the ownership model clearer than
adapting mini to an ill-fitting interface.

**Option C: authoring-only hybrid spike**

Build a small loom grammar/projection spike outside the runtime parser path.
Use it only to compare CST-owned identity against the current token-owned path
for the Phase 6+ edit cases.

This evaluates the CST ownership model without changing shipped runtime
behavior. The cost is temporary duplication while the spike exists.

## Proposal

Use Option C as the next loom/CST step, and keep Option A as the production
owner until the spike proves a stronger contract.

The first spike lives under `specs/loom-mini-cst/` as a nested MoonBit module
with local path dependencies to the editable canopy loom/seam/incr checkouts.
It starts with only `s("bd sd bd")`-style notation, because duplicate atom
spans are the immediate identity question. Its initial checks pass on
2026-05-21: `rtk moon test --target wasm-gc` reports 5 tests passed, and
`rtk moon check --target wasm-gc` reports no work/errors.

The first `apply_edit` characterization is mixed:

- Inserting ` cp` into `s("bd sd bd")` updates the CST projection to
  `bd@[3,5)`, `sd@[6,8)`, `cp@[9,11)`, `bd@[12,14)` and reports nonzero
  `reuse_count`.
- Deleting ` sd` updates the CST projection to `bd@[3,5)`, `bd@[6,8)`, but
  currently reports `reuse_count == 0`.

So CST spans are enough to distinguish duplicate atoms in one recovered tree,
and `apply_edit` can drive the authoring parser shape, but span-derived IDs
alone are not yet a replacement for the current mini source-edit identity
realignment. Either loom needs a stronger reusable token/subtree identity
projection for deletion/shift cases, or the authoring layer still needs to own
identity realignment above the CST. The corresponding upstream loom follow-up
is tracked in canopy loom's `ROADMAP.md` as "Authoring identity after
deletion/shift edits."

A 2026-05-25 follow-up expanded the authoring-only projection comparison:
replacement edits, whitespace-only insertions, method-name replacement, duplicate
note edits, and parse-error recovery now compare the loom projection against
`MiniAuthoringPipeline`. The projection keeps the caller's successful-source
edit span pending across syntax errors so recovery preserves the same duplicate
atom provenance as the current mini token layer. This strengthens Option C but
still does not move loom into production parsing.

The spike should pass these gates before loom owns mini edit identity:

- Duplicate-token insertion, deletion, and replacement preserve the same leaf
  provenance that the current source-span token tests cover.
- Parse errors publish diagnostics without replacing the last successful
  authoring document.
- `PatternDoc` leaf IDs can keep the existing public shape
  (`mini:sound:bd:N`, `mini:note:60:N`) or provide a documented migration path.
- Runtime parsing remains independent of loom unless `moondsp` has a verified
  loom/seam wasm-gc dependency proof and browser build proof.
- The integration boundary is authoring-only and does not add loom/seam to the
  browser runtime build graph during evaluation.

## Consequences

- The team can discuss token/CST ownership against a concrete evaluation plan
  instead of a parser migration.
- The current Phase 6+ reliability work remains useful even if loom is adopted
  later, because its regression tests define the identity contract a CST path
  must preserve.
- Loom is no longer blocked by isolated loom-package wasm-gc tests, but it
  remains blocked for runtime use until the `moondsp` dependency graph and
  browser target are proven.

## Revisit when

Revisit this ADR after an authoring-only loom mini grammar spike compares CST
identity against the current `MiniAuthoringPipeline` source-edit tests. Accept
loom ownership only if it matches or improves the duplicate-token and
parse-error recovery behavior without pulling loom into the runtime
AudioWorklet path.
