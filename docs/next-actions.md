# Next Actions

Updated: 2026-05-21

Forward-looking handoff for the next session. Keep short and actionable;
per-PR verification logs and merged-PR lists live in `git log` and
`CHANGELOG.md`, not here.

## Current State

- `origin/main` is current after PR #70 (`test(loom-mini-cst): pin
  deletion-safe reuse contract`, squash commit `bafaa30`). The root checkout
  may be detached at `origin/main` because `main` is checked out in the
  mini-incr loom evaluation worktree.
- Latest release: **v0.5.1** (tagged 2026-05-20; GitHub release pinned;
  `mooncakes` `dowdiness/moondsp@0.5.1` published 2026-05-20).
- No open PRs as of 2026-05-21.
- `CHANGELOG.md` has non-empty `## [Unreleased]` entries from PR #68
  (mini incr authoring / loom-CST evaluation) and PR #69 (typed voice
  mutation APIs).
- Next release target: **v0.6.0** if releasing current `Unreleased`, because
  PR #69 added public API. Use a patch release only after carving out or
  intentionally reclassifying public additive 0.x API changes.
- Known outstanding warnings: 8 `[0020]` Show-vs-Debug deprecations from
  `@qc.quick_check_fn` in DSP and pattern property tests. Treat as
  dependency-bound unless `moonbitlang/quickcheck` has changed its trait
  bound; verify the current mooncakes state before planning local edits.

For shipped-work history, read `CHANGELOG.md`. For the broader backlog
(quick wins, pre-1.0 API hygiene, Phase 6+ roadmap), read
`memory/project_backlog.md`.

## Recommended Next Slice

Free choice — pick from "Alternative Slices" below or from
`memory/project_backlog.md`. Nothing is release-gated. The most concrete loom
follow-up is dependency hardening: after Loom PR #135 lands, publish or pin Loom
and companion modules so `specs/loom-mini-cst` can stop relying on sibling
local path dependencies.

## Alternative Slices

- **Quickcheck warning sweep** — `rtk moon check` still reports 8
  dependency-bound `[0020]` Show-vs-Debug warnings from
  `@qc.quick_check_fn` in property tests. First verify whether a
  `moonbitlang/quickcheck` update removes the old bound; only plan local
  suppressions or test rewrites if the dependency remains blocked.

- **Loom dependency publish/pin follow-up** — PR #70 intentionally validates
  against the sibling Loom checkout containing PR #135 behavior. Once Loom
  PR #135 lands, publish or otherwise pin `dowdiness/loom` plus companion
  modules (`seam`, `pretty`, `text_change`, and likely `moji`) and replace
  `specs/loom-mini-cst` local path deps with versioned deps.

- **Voice API result hardening follow-up** — PR #69 added typed result peers
  for handle mutators while keeping Bool wrappers. The next design question is
  whether to deprecate/remove those wrappers, rename voice `*_result` methods
  to graph-style unsuffixed `Result` methods, or first migrate
  `CompiledDsp::compile` away from `Self?`.

- **v0.6.0 release prep** — `Unreleased` now contains public API additions and
  authoring-pipeline work. If cutting a release, run normal release prep and
  treat the target as `v0.6.0` unless deliberately carving scope down.

- **Open another Phase 6+ slice** (per `memory/project_backlog.md`):
  incremental reparsing with loom, canopy structural editor, or another
  targeted mini authoring improvement. Each is multi-session scope;
  brainstorm before planning.

### Closed since the last update

- ~~**Loom mini-CST deletion-safe reuse spec**~~ — SHIPPED 2026-05-21 in
  PR #70 (squash commit `bafaa30`). The nested `specs/loom-mini-cst/` spike now
  pins Loom PR #135 semantics as deletion-safe left-adjacent CST reuse, not
  parser-owned token/subtree identity projection. Remaining follow-up:
  publish or pin Loom dependencies instead of relying on sibling local paths.

- ~~**Voice result mutator APIs**~~ — SHIPPED 2026-05-21 in PR #69
  (squash commit `cfa7af9`). Added typed result-returning peers for
  `VoicePool::note_off`, `VoicePool::set_voice_pan`,
  `BoundVoicePool::note_off`, `BoundVoicePool::kill`, and
  `BoundVoicePool::set_voice_pan`; existing Bool wrappers remain and delegate
  to the result path. Validation: CI green, `rtk moon test` 891/891 before
  merge.

- ~~**Mini incr authoring / loom-CST evaluation**~~ — SHIPPED 2026-05-21
  in PR #68 (tip commit `bd423f4`). Added `MiniAuthoringPipeline`,
  source-edit-aware token identity realignment, ADR-0011/0012 updates, and a
  nested `specs/loom-mini-cst/` spike for duplicate atom span evaluation.
  Loom production migration remains separate and active in its own worktree.

- ~~**v0.5.1 mini scalar-control release**~~ — SHIPPED 2026-05-20 as tag
  `v0.5.1`, GitHub release, and mooncakes `dowdiness/moondsp@0.5.1`.
  Bundles PR #66 and #67 plus documentation updates for `.cutoff(f)`,
  `.gain(g)`, and `.pan(p)`.

- ~~**Mini per-sound parameter control**~~ — SHIPPED 2026-05-20 in PR
  #66 and #67 (squash commits `b187efe` and `8432075`). Mini notation now
  supports `.cutoff(f)`, `.gain(g)`, and `.pan(p)` method chains in both the
  runtime parser and PatternDoc parser, lowering through existing
  `ControlMap` / `merge_control` behavior. Regression coverage includes
  repeated scalar-control values and `.pan(...).jux(...)` override behavior.

- ~~**v0.5.0 AudioBuffer API-hardening release**~~ — SHIPPED 2026-05-20
  as tag `v0.5.0`, GitHub release, and mooncakes
  `dowdiness/moondsp@0.5.0`. Bundles PR #60, #62, and #63: removes
  `AudioBuffer::as_fixed_array`, adds `AudioBuffer::all` / `any` and
  `AudioBuffer::adopt`, switches `AudioBuffer::new` to defensive copy,
  and normalizes non-finite samples on MoonBit-owned writes.

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
