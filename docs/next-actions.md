# Next Actions

Updated: 2026-05-26

Forward-looking handoff for the next session. Keep this short and actionable;
per-PR verification logs and merged-PR lists live in `git log` and
`CHANGELOG.md`, not here.

## Current State

- `main` is aligned with `origin/main` after PR #92.
- Latest release: **v0.5.1** (tagged and published 2026-05-20).
- The next release should be **v0.6.0** if it includes the current
  `Unreleased` entries, because public API has been added since v0.5.1.
- Open GitHub issues: none.
- Open PRs: PR #86 (`release/v0.6.0`) is release prep and intentionally
  remains open until an explicit release pass. Do not tag or publish v0.6.0 as
  part of loom-authoring work.
- ADR-0013 defines loom mini promotion criteria using the shipped apply-edit
  and projection parity evidence, but it does not approve a production parser
  switch.
- `moon.mod` is now the root manifest. `moon.mod.json` remains only in the
  nested `specs/loom-mini-cst` spike module.
- Production mini parsing still uses the hand-written parser and
  `mini/incr_authoring.mbt::MiniAuthoringPipeline`; loom remains an
  authoring-only evaluation path under `specs/loom-mini-cst`.

For the broader backlog, read
`~/.claude/projects/-home-antisatori-ghq-github-com-dowdiness-moondsp/memory/project_backlog.md`.

## Recommended Next Slice

**Add loom CST parity for top-level `$:` stack programs.** Keep the work under
`specs/loom-mini-cst`; do not add loom/seam to root `moon.mod` and do not route
`mini.parse`, `parse_doc`, or `MiniAuthoringPipeline` through loom. The
production parser now supports `$:` lines, so the loom spike should learn that
program shape next and compare against `@mini.parse_doc`.

## Alternative Slices

- **v0.6.0 release prep** — bump `moon.mod` to `0.6.0`, move `CHANGELOG.md`
  `Unreleased` entries under a dated `0.6.0` section, validate package
  contents, and publish only after review. Do not republish `0.5.1`.

- **Loom callback-method parity** — after `$:` program parity, extend the spike
  projection to cover `.jux(...)` and `.every(...)` callback methods. Keep this
  in `specs/loom-mini-cst`; do not add loom/seam to root `moon.mod`.

- **Voice API result hardening follow-up** — decide whether to deprecate/remove
  Bool wrappers, rename voice `*_result` methods to graph-style unsuffixed
  `Result` methods, or first migrate `CompiledDsp::compile` away from `Self?`.

- **CompiledTemplate / DspNode Eq with NaN policy** — still deferred until an
  incr/Salsa-style early-cutoff use case needs it. Decide the NaN equality
  policy before adding structural Eq.

## Closed Since Previous Update

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

- Normal code/docs slices: `rtk moon check --deny-warn` and
  `rtk moon test --release`.
- `specs/loom-mini-cst` slices: also run
  `rtk moon -C specs/loom-mini-cst check --deny-warn` and
  `rtk moon -C specs/loom-mini-cst test`.
- Release prep: also run `rtk moon fmt`, `rtk moon info`, and
  `rtk moon package --list`, then inspect the generated zip contents.
- Graph runtime-control behavior changes: update
  `docs/salat-engine-technical-reference.md` first.
