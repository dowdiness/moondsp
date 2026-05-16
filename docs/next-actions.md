# Next Actions

Updated: 2026-05-16

Forward-looking handoff for the next session. Keep short and actionable;
per-PR verification logs and merged-PR lists live in `git log` and
`CHANGELOG.md`, not here.

## Current State

- `main` HEAD: `a92a3a3 docs(changelog): amend v0.3.0 entry per Codex review`.
- Latest release: **v0.3.0** (2026-05-16) — hide graph-internal `NodeXxx`
  traits, lock down `PatternScheduler` fields, require labelled args on
  `DspNode::{delay, stereo_delay, envelope_gain}`.
- No active feature branch; no open PRs.
- Known outstanding warnings: 8 `[0020]` Show-vs-Debug deprecations in
  `pattern/property_test.mbt` + `pattern/pattern_doc_test.mbt`, originating
  in `@qc.quick_check_fn`'s trait bound. Pinned on `moonbitlang/quickcheck`
  publishing ≥0.14.0 (verified: 0.13.0 still has the old bound). No action
  on our side until mooncakes ships 0.14.0.

For shipped-work history, read `CHANGELOG.md`. For the broader backlog
(quick wins, pre-1.0 API hygiene, Phase 6+ roadmap), read
`memory/project_backlog.md`.

## Recommended Next Slice

**Narrow `GraphBuilder::nodes()`.** Only abstraction leak still tracked
under Action (2) of the pre-1.0 API review (per
`memory/project_backlog.md`). Currently exposes `Array[DspNode]` (mutable,
accumulated). Options: leave as-is, narrow to `ArrayView[DspNode]`, or
replace with a snapshot accessor. Decide before v1.0; brainstorm before
plan.

## Alternative Slices

- **Issue #22 follow-up cleanup** if anything remains after the
  `sched_routes` consolidation closed the issue on 2026-05-16.

- **Open another Phase 6+ slice** (per `memory/project_backlog.md`):
  incremental reparsing with loom, canopy structural editor, or per-sound
  parameter control. Each is multi-session scope; brainstorm before
  planning.

## Acceptance Checks For API-Hardening Slices

- Run `rtk moon info` and review `.mbti` diffs for intentional public API
  changes.
- Run `rtk moon fmt`, `rtk moon check`, and `rtk moon test`.
- If root facade or browser-relevant graph APIs changed, run
  `rtk moon build --target wasm-gc`.
- Update `docs/salat-engine-technical-reference.md` first for graph
  runtime-control behavior changes.
