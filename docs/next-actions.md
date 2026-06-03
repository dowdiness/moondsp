# Next Actions

Updated: 2026-06-03

Forward-looking handoff for the next session. Keep this short and actionable;
per-PR verification logs and merged-PR lists live in `git log` and
`CHANGELOG.md`, not here.

## Current State

- `main` is aligned with `origin/main` after PR #132 (`44a1335`), which
  closed issue #129 by adding cross-target external-authoring benchmark
  snapshots. The external-authoring boundary and benchmark follow-ups are now
  shipped through issues #117–#121 and #118/#127/#128/#129.
- Latest release: **v0.5.1** (tagged and published 2026-05-20).
- The next release should be **v0.6.0** if it includes the current
  `Unreleased` entries, because public API has been added since v0.5.1.
- Open moondsp GitHub issues: #133–#140 track the architecture-boundary
  roadmap from ADR-0015 (validation wiring, graph facade/internal extraction,
  scheduler split, and browser ABI/demo-host split).
- Open PRs: PR #86 (`release/v0.6.0`) is release prep and intentionally
  remains open until an explicit release pass. Do not tag or publish v0.6.0 as
  part of unrelated docs, benchmark, or loom-authoring work.
- ADR-0013 defines loom mini promotion criteria using the shipped apply-edit,
  projection parity, PR #101 provenance-matrix evidence, PR #104
  control-method projection parity, PR #107 recovery evidence, and PR #109–#112
  identity-helper adoption, but it does not approve a production parser
  switch.
- `moon.mod` is now the root manifest. `moon.mod.json` remains only in the
  nested `specs/loom-mini-cst` spike module.
- Production mini parsing still uses the hand-written parser and
  `mini/incr_authoring.mbt::MiniAuthoringPipeline`; loom remains an
  authoring-only evaluation path under `specs/loom-mini-cst`.

For the broader backlog, read
`~/.claude/projects/-home-antisatori-ghq-github-com-dowdiness-moondsp/memory/project_backlog.md`.

## Recommended Next Slice

**v0.6.0 release prep.** Review the existing PR #86 release branch, then bump
`moon.mod` to `0.6.0`, move `CHANGELOG.md` `Unreleased` entries under a dated
`0.6.0` section, validate package contents, and publish only after review. Do
not republish `0.5.1` and do not tag/publish v0.6.0 as part of unrelated
loom-authoring work.

## Alternative Slices

- **Loom upstream attachment / production-shaped boundary** — PRs #109–#112
  moved spec-local identity realignment, optional-edit handling, source-diff
  fallback, and failed-edit composition onto Loom helpers while preserving the
  recovery evidence. Further Loom work should either happen upstream
  (`dowdiness/loom#162`, `dowdiness/loom#163`, `dowdiness/loom#164`,
  `dowdiness/seam#2`) or become a production-shaped authoring-boundary
  prototype. Keep any moondsp work under `specs/loom-mini-cst`; do not add
  loom/seam to root `moon.mod` and do not route production parsing through
  loom.

- **Voice API result hardening follow-up** — decide whether to deprecate/remove
  Bool wrappers, rename voice `*_result` methods to graph-style unsuffixed
  `Result` methods, or first migrate `CompiledDsp::compile` away from `Self?`.

- **Incr early-cutoff use of DspNode/CompiledTemplate Eq** — structural Eq and
  typed compile diagnostics shipped in PR #122. Do not wire Eq into an
  incr/Salsa-style early-cutoff path until a benchmark reproduces meaningful
  authoring-side cost.

## Closed Since Previous Update

- ~~**Issue #129 / PR #132 — cross-target external-authoring snapshots**~~ —
  SHIPPED 2026-06-03 (`44a1335`). Added a dated performance snapshot comparing
  wasm-gc, native, and JS target runs for valid paths, diagnostic/failure paths,
  and realistic graph shapes. Verdict: no bottleneck demonstrated; keep results
  target-qualified and preserve the audio block-boundary vs UI/control-thread
  budget split.

- ~~**External-authoring boundary and benchmark sequence**~~ — SHIPPED
  2026-06-02/03 (`89da733`, `c067cf5`, `87142af`, `f361bc3`, `37e6558`,
  `bc55c43`). Added the external DSL lowering contract, Mini pattern DSL ↔
  graph DSL boundary, editor audio-preview handoff, valid-path benchmarks,
  diagnostic/failure-path benchmarks, and realistic graph-shape benchmarks.
  Parser/projection/lowering/template preparation remains off the audio
  callback.

- ~~**Issue #119 / PR #122 — authoring Eq and compile diagnostics**~~ — SHIPPED
  2026-06-02 (`1fb2615`). Added ADR-0014, structural authoring equality for
  `DspNode`/`CompiledTemplate`, and additive typed `compile_result` diagnostics
  while preserving the compatibility `compile(...) -> Self?` APIs.

- ~~**Issue #114 / PRs #115–#116 — browser song playback and UI docs**~~ —
  SHIPPED 2026-05-31 (`47b163c`, `3a64b1d`). Added browser/live song playback,
  Pattern/Song mode UI, global BPM behavior, and multiline song-syntax help.
  Production parsing remains hand-written.

- ~~**PR #113 — loom promotion notes refresh**~~ — SHIPPED 2026-05-31
  (`24e150d`). Aligned ADR-0013, Loom upstream requirements, and this handoff
  with the PR #112 tracker cleanup. Production parsing remains hand-written.

- ~~**PR #112 — loom tracker failed-edit composition cleanup**~~ — SHIPPED
  2026-05-31 (`1f54c54`). Removed the spec-local `pending_source_edit` shim;
  the spec projection now delegates optional-edit and failed-recovery
  composition to Loom's `ProjectionIdentityTracker`. Production parsing remains
  hand-written.

- ~~**PRs #109–#111 — loom projection helper adoption**~~ — SHIPPED
  2026-05-29/31 (`dbfd781`, `98df144`, `32601d7`). Adopted Loom identity,
  string-ID, optional-edit, and source-diff fallback helpers in the nested
  mini-CST spike. Production parsing remains hand-written.

- ~~**PR #107 — loom recovery evidence expansion**~~ — SHIPPED 2026-05-28
  (`07a4451`). Expanded the spec-local recovery matrix for `$:` stack-line
  syntax, direct and `$:` callback syntax, control-method syntax, and
  projection-only semantic failures; recovered states now compare Loom and
  `MiniAuthoringPipeline` root IDs as well as lowered event IDs. Production
  parsing remains hand-written.

- ~~**PR #106 — loom upstream requirements extraction**~~ — SHIPPED
  2026-05-28 (`49d1fe5`). Added `docs/loom-upstream-requirements.md`, linked
  it from ADR-0013, and opened upstream follow-up issues in Loom/seam for
  stable identity, projection ergonomics, diagnostics plus last-good semantic
  documents, and authoring-only dependency boundaries.

- ~~**PR #104 — loom control-method projection parity**~~ — SHIPPED
  2026-05-28 (`f1759c6`). Added spec-local projection/lowering support for
  `.cutoff(...)`, `.gain(...)`, and `.pan(...)`, with parity against
  `@mini.parse_doc`, lowered control-map checks, and a lowering-cache reuse
  regression. Production parsing remains hand-written.

- ~~**PR #101 — loom full-grammar provenance matrix**~~ — SHIPPED
  2026-05-27 (`787e23a`). Added the matrix helper and representative rows under
  `specs/loom-mini-cst/src/projection_test.mbt` for duplicate-token edits,
  `$:` lines, layers, postfixes, callback/root method edits, recovery,
  source-edit spans, and lowered event IDs. Production parsing remains
  hand-written.

- ~~**PR #100 — loom mode-incompatible atom rejection**~~ — SHIPPED
  2026-05-27 (`cc268e4`). Hardened the spec-local Loom projection so numeric
  atoms in `s(...)` and identifier atoms in `note(...)` reject instead of being
  silently dropped; production parsing remains hand-written.

- ~~**PR #99 — loom known edge-case characterization**~~ — SHIPPED
  2026-05-27 (`0c7f5fb`). Characterized permissive empty notation,
  trailing-comma layers, unterminated-bracket recovery, and digit-start atom
  lexing under `specs/loom-mini-cst`; no production parser routing changed.

- ~~**PR #97 — loom `$:` callback parity**~~ — SHIPPED 2026-05-27
  (`fceb86b`). Added Loom mini-CST projection parity for callback methods inside
  `$:` stack-line programs, callback variants, and callback edit/reuse parity
  against `MiniAuthoringPipeline`; production parsing remains hand-written.

- ~~**PR #96 — loom callback variant and edit parity**~~ — SHIPPED
  2026-05-27 (`57ff069`). Added direct `.jux(...)` / `.every(...)` callback
  variants and direct callback edit/reuse parity; no `$:` stack-line coverage.

- ~~**PR #95 — loom callback-method projection parity**~~ — SHIPPED
  2026-05-26 (`6d3d439`). Added callback-method projection/lowering for
  `.jux(...)` and `.every(...)`, with initial `rev` parity tests against
  `@mini.parse_doc`; production parsing remains hand-written.

- ~~**PR #94 — `$:` docs refresh**~~ — SHIPPED 2026-05-26 (`cc95e75`).
  Refreshed mini-notation docs, ADR/backlog pointers, and `$:` syntax summary;
  no production parser switch.

- ~~**PR #93 — loom `$:` stack-program parity**~~ — SHIPPED 2026-05-26
  (`3b566d6`). Added loom mini-CST projection parity for top-level `$:` stack
  programs against `@mini.parse_doc`; no callback-method projection yet.

- ~~**PR #92 — Strudel-style `$:` stack lines**~~ — SHIPPED 2026-05-26
  (`2ce2930`). Added top-level `$:` stack syntax to the production mini parser,
  PatternDoc parser, browser live examples, CodeMirror grammar/completion, and
  smoke tests. Existing `stack(...)` remains supported.

- ~~**PR #91 — loom mini-CST sub-notation/group postfix parity**~~ — SHIPPED
  2026-05-26 (`0d14e5a`). Added recursive notation projection for atom/group
  elements and group postfix parity for `*`, `?`, and Euclid; no production
  parser routing changed.

- ~~**PR #85 — loom mini-CST apply-edit authoring parity**~~ — SHIPPED
  2026-05-25 (`cddb6e9`). Added replacement, whitespace, method-replacement,
  duplicate-note, and parse-error recovery parity against
  `MiniAuthoringPipeline`; no production parser routing changed.

- ~~**PR #77 — root manifest migration**~~ — SHIPPED 2026-05-25 (`6229659`).
  Migrated root `moon.mod.json` to `moon.mod`, preserving release metadata,
  dependencies, and publish excludes.

- ~~**Issue #82 / PR #84 — loop-expression refactor**~~ — SHIPPED 2026-05-24
  (`17c59ad`) with style guidance in `9e72655`. Stop broad loop-expression
  sweeps; only convert loops when a targeted change already has local context
  and the loop naturally computes a value.

- ~~**Quickcheck warning sweep**~~ — SHIPPED 2026-05-24 in PR #75 (`c5db26c`).
  `moonbitlang/quickcheck` is now `0.14.0`; the previous dependency-bound
  Show-vs-Debug warnings are gone under `rtk moon check --deny-warn`.

## Acceptance Checks

- Normal code/docs slices: `NEW_MOON_MOD=0 moon check --deny-warn` and
  `NEW_MOON_MOD=0 moon test --release`.
- `specs/loom-mini-cst` slices: also run
  `NEW_MOON_MOD=0 moon -C specs/loom-mini-cst check --deny-warn` and
  `NEW_MOON_MOD=0 moon -C specs/loom-mini-cst test`.
- Release prep: also run `NEW_MOON_MOD=0 moon fmt`,
  `NEW_MOON_MOD=0 moon info`, and `NEW_MOON_MOD=0 moon package --list`, then
  inspect the generated zip contents.
- Graph runtime-control behavior changes: update
  `docs/salat-engine-technical-reference.md` first.
