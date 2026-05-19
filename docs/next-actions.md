# Next Actions

Updated: 2026-05-19

Forward-looking handoff for the next session. Keep short and actionable;
per-PR verification logs and merged-PR lists live in `git log` and
`CHANGELOG.md`, not here.

## Current State

- `main` HEAD: `79c5ab9 refactor(dsp)!: AudioBuffer::new defensive copy + AudioBuffer::adopt (#62)`.
- Latest release: **v0.4.0** (tagged 2026-05-18; GitHub release pinned;
  `mooncakes` `dowdiness/moondsp@0.4.0` published 2026-05-19). The v0.4.0
  branch of pre-1.0 API hygiene is closed; remaining slices are
  free-choice.
- No open PRs.
- `## [Unreleased]` in `CHANGELOG.md` now carries the AudioBuffer::new
  defensive-copy breaking change + AudioBuffer::adopt addition. Rolls
  into the next release tag.
- Known outstanding warnings: 8 `[0020]` Show-vs-Debug deprecations in
  `pattern/property_test.mbt` + `pattern/pattern_doc_test.mbt`, originating
  in `@qc.quick_check_fn`'s trait bound. Pinned on `moonbitlang/quickcheck`
  publishing ≥0.14.0 (verified: 0.13.0 still has the old bound). No action
  on our side until mooncakes ships 0.14.0.

For shipped-work history, read `CHANGELOG.md`. For the broader backlog
(quick wins, pre-1.0 API hygiene, Phase 6+ roadmap), read
`memory/project_backlog.md`.

## Recommended Next Slice

Free choice — pick from "Alternative Slices" below or from
`memory/project_backlog.md`. Nothing is release-gated.

## Alternative Slices

- **C-style loops in `scheduler/scheduler_test.mbt:2255/2272`** — two
  helpers use `for i = 0; i < left.length(); i = i + 1 { ... }`,
  re-evaluating `length()` per iteration. Pre-existing, test-helper-only,
  no runtime impact. Single-line mechanical rewrite to
  `for i in 0..<left.length()`; bundle with the next scheduler-test touch.

- **AudioBuffer write-time validation** — surfaced by the constructor
  refactor (PR #62, spec
  `docs/superpowers/specs/2026-05-19-audiobuffer-constructor-design.md`,
  "What this design does NOT promise" section). `new`'s ingest,
  `filled`'s ingest, `fill`, and `adopt` all bypass `set`, so any future
  write-time validation (NaN screening, clipping, normalization) must
  factor into a shared internal path covering all four entrypoints —
  not just `set`. Brainstorm the validation contract before planning;
  the decision shapes both the public surface and the FFI / SAB story
  on `adopt`.

- **Open another Phase 6+ slice** (per `memory/project_backlog.md`):
  incremental reparsing with loom, canopy structural editor, or
  per-sound parameter control. Each is multi-session scope; brainstorm
  before planning.

### Closed since the last update

- ~~**`AudioBuffer::new` constructor encapsulation leak**~~ — SHIPPED
  2026-05-19 in PR #62 (`refactor/audiobuffer-constructor`, squash
  commit `79c5ab9`). `new` now defensively copies; `adopt` carries the
  explicit zero-copy contract; `filled` re-routes through `adopt` to
  preserve the single-allocation production hot path. Codex PR review:
  one Low docstring-tense finding, fixed.

- ~~**`validate_voice_template` double-compile microbenchmark**~~ —
  SHIPPED 2026-05-19 in PR #61 (squash commit `20bae6b`). Measured a
  0.89×–1.06× waste-to-productive compile ratio across wasm-gc and
  native, but only 1.6–7 µs of control-thread cost per call — well
  below user-perceptible authoring thresholds. **Verdict: defer the
  `is_compilable_in` optimization indefinitely** (see
  `docs/performance/2026-05-19-validate-voice-template-double-compile.md`).

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
