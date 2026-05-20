# Next Actions

Updated: 2026-05-20

Forward-looking handoff for the next session. Keep short and actionable;
per-PR verification logs and merged-PR lists live in `git log` and
`CHANGELOG.md`, not here.

## Current State

- `main` HEAD: `bf02217 [codex] Normalize scheduler test loops (#64)`.
- Latest release: **v0.4.0** (tagged 2026-05-18; GitHub release pinned;
  `mooncakes` `dowdiness/moondsp@0.4.0` published 2026-05-19). The v0.4.0
  branch of pre-1.0 API hygiene is closed; remaining slices are
  free-choice.
- No open PRs.
- `## [Unreleased]` in `CHANGELOG.md` now carries the AudioBuffer::new
  defensive-copy breaking change + AudioBuffer::adopt addition, plus the
  AudioBuffer write-time non-finite normalization from PR #63. Rolls into
  the next release tag.
- Known outstanding warnings: 8 `[0020]` Show-vs-Debug deprecations from
  `@qc.quick_check_fn` in DSP and pattern property tests. Treat as
  dependency-bound unless `moonbitlang/quickcheck` has changed its trait
  bound; verify the current mooncakes state before planning local edits.

For shipped-work history, read `CHANGELOG.md`. For the broader backlog
(quick wins, pre-1.0 API hygiene, Phase 6+ roadmap), read
`memory/project_backlog.md`.

## Recommended Next Slice

Free choice — pick from "Alternative Slices" below or from
`memory/project_backlog.md`. Nothing is release-gated. The most concrete
small follow-up is the quickcheck warning sweep, but only after verifying
whether a dependency update removes the deprecated `Show` bound.

## Alternative Slices

- **Quickcheck warning sweep** — `rtk moon check` still reports 8
  dependency-bound `[0020]` Show-vs-Debug warnings from
  `@qc.quick_check_fn` in property tests. First verify whether a
  `moonbitlang/quickcheck` update removes the old bound; only plan local
  suppressions or test rewrites if the dependency remains blocked.

- **Open another Phase 6+ slice** (per `memory/project_backlog.md`):
  incremental reparsing with loom, canopy structural editor, or
  per-sound parameter control. Each is multi-session scope; brainstorm
  before planning.

### Closed since the last update

- ~~**C-style loops in `scheduler/scheduler_test.mbt:2255/2272`**~~ —
  SHIPPED 2026-05-20 in PR #64 (squash commit `bf02217`). The two
  sample-scan helper loops now use `for i in 0..<left.length()`; no
  scheduler behavior changed.

- ~~**AudioBuffer write-time validation**~~ — SHIPPED 2026-05-20 in PR
  #63 (squash commit `f431b13`). MoonBit-owned writes through `new`,
  `filled`, `fill`, and `set` normalize non-finite samples to `0.0`;
  finite samples pass through unchanged. `adopt` remains the explicit
  retained-handle bypass, with normalized writes through buffer methods.

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
