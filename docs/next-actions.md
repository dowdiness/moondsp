# Next Actions

Updated: 2026-05-19

Forward-looking handoff for the next session. Keep short and actionable;
per-PR verification logs and merged-PR lists live in `git log` and
`CHANGELOG.md`, not here.

## Current State

- `main` HEAD: `8de2106 refactor(dsp): tighten AudioBuffer encapsulation (#60)`.
- Latest release: **v0.4.0** (tagged 2026-05-18; GitHub release pinned;
  `mooncakes` `dowdiness/moondsp@0.4.0` published 2026-05-19).
- Open PR: **#61 `bench(voice): microbenchmark validate_voice_template
  double-compile`** — CI green, awaiting merge. Adds
  `voice/voice_benchmark.mbt` + `docs/performance/2026-05-19-...md`. No
  behavior change. The microbench measured a 0.89×–1.06× waste-to-
  productive compile ratio across wasm-gc and native, but only 1.6–7 µs
  of control-thread cost per call — well below user-perceptible
  authoring thresholds. **Verdict: defer the `is_compilable_in`
  optimization indefinitely** (see snapshot for details).
- Known outstanding warnings: 8 `[0020]` Show-vs-Debug deprecations in
  `pattern/property_test.mbt` + `pattern/pattern_doc_test.mbt`, originating
  in `@qc.quick_check_fn`'s trait bound. Pinned on `moonbitlang/quickcheck`
  publishing ≥0.14.0 (verified: 0.13.0 still has the old bound). No action
  on our side until mooncakes ships 0.14.0.

For shipped-work history, read `CHANGELOG.md`. For the broader backlog
(quick wins, pre-1.0 API hygiene, Phase 6+ roadmap), read
`memory/project_backlog.md`.

## Recommended Next Slice

**Merge PR #61**, then pick the next slice from "Alternative Slices"
below or from `memory/project_backlog.md`. The post-v0.4.0 work is no
longer release-gated, so the next slice is free choice.

## Alternative Slices

- **`AudioBuffer::new(FixedArray)` constructor leak** — recorded in
  `memory/project_backlog.md`. The zero-copy constructor accepts external
  storage by reference; callers can retain the original `FixedArray` and
  mutate it after construction, bypassing future write-time validation.
  Pre-1.0 API hygiene; brainstorm whether to (a) split into
  `AudioBuffer::from_copy` (defensive) + a package-private zero-copy
  variant, (b) document a borrow-style contract, or (c) leave as-is.
  Surfaced by Codex during PR #60 design review (2026-05-19).

- **C-style loops in `scheduler/scheduler_test.mbt:2255/2272`** — two
  helpers use `for i = 0; i < left.length(); i = i + 1 { ... }`,
  re-evaluating `length()` per iteration. Pre-existing, test-helper-only,
  no runtime impact. Single-line mechanical rewrite to
  `for i in 0..<left.length()`; bundle with the next scheduler-test touch.

- **Open another Phase 6+ slice** (per `memory/project_backlog.md`):
  incremental reparsing with loom, canopy structural editor, or
  per-sound parameter control. Each is multi-session scope; brainstorm
  before planning.

### Closed since the last update

- ~~**`AudioBuffer::as_fixed_array` encapsulation cleanup**~~ — SHIPPED
  2026-05-19 in PR #60. `every`/`any` added with `raise?` parity,
  `as_fixed_array` deleted, ~145 call sites migrated, zero codegen
  overhead verified at the WAT level.
## Acceptance Checks For API-Hardening Slices

- Run `rtk moon info` and review `.mbti` diffs for intentional public API
  changes.
- Run `rtk moon fmt`, `rtk moon check`, and `rtk moon test`.
- If root facade or browser-relevant graph APIs changed, run
  `rtk moon build --target wasm-gc`.
- Update `docs/salat-engine-technical-reference.md` first for graph
  runtime-control behavior changes.
