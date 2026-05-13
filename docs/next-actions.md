# Next Actions

Updated: 2026-05-13

This is the active handoff list for future sessions. It should stay short and
actionable; move completed design notes or implementation plans under
`docs/superpowers/{specs,plans}/archive/` when they ship.

## Current State

- `main` is currently at
  `6d804d5 Merge pull request #34 from dowdiness/codex/phase6-lowering-cache`.
- Branch `codex/phase6-scheduler-snapshot-swap` implements the first scheduler
  snapshot-swap slice from that merged head.
- Core silent-failure hardening shipped so far:
  - `GraphControlError` result APIs for direct compiled mono/stereo graphs.
  - `HotSwapQueueError` result APIs for mono/stereo hot-swap queues.
  - `GraphTopologyQueueError` result APIs for mono/stereo topology edit queues.
  - runtime-control `GraphControlError` result APIs for mono/stereo hot-swap
    and topology wrapper controls.
  - browser graph queue/control paths expose last-error string/code helpers
    while preserving the boolean wasm ABI.
  - `BoundVoicePool` owns template validation and `ControlBindingMap` lifetime,
    so `PatternScheduler` no longer carries stale bindings.
  - remaining ambiguity-prone DSP/browser helper parameters are labelled:
    `Oscillator::process`, `DemoSource::tick_source`, browser `tick`, and
    browser `tick_source`. The generated interfaces also confirm the earlier
    `Oscillator::{process_waveform,tick,tick_waveform}`,
    `Gain::process`, `Clip::process`, `Pan::process`,
    `DspNode::stereo_gain`, and `DspNode::stereo_clip` labels.
  - topology queue diagnostics are settled on
    `InvalidEdit(index, reason)`, where `reason` is a stable
    `GraphTopologyEditError` for invalid indices, unsupported slots/templates,
    invalid delete ranges, and non-unary or non-single-consumer delete shapes.
- Song scaffold shipped so far:
  - named section layering and patchable section variations.
  - contiguous long-form layout with computed song-global occurrence spans and
    occurrence querying.
  - scheduler support for section and song structures in addition to raw
    patterns.
  - Phase 6 identity groundwork separates stable occurrence identity from
    display labels through a dependency-free identity model.
  - deferred song work remains explicit starts, gaps, overlaps, range
    addressing, boundary fills, song mini-notation, non-identity time-scope
    transforms, and efficient secondary lookup indexes.
- Pattern authoring groundwork shipped so far on `main`:
  - identity-bearing authoring documents over the existing runtime query model.
  - private node storage with stable node lookup helpers.
  - revisioned edits for root changes, node replacement, and core
    structure-building operations.
  - lowering snapshots back to the runtime query model.
- Pattern authoring explicit-node groundwork shipped so far on `main`:
  - aggregate document revisions derive from an ordered child-revision mix,
    with coverage for rebuilt sequence/stack roots, mixed-revision merged
    inputs, and shifted child-revision aliases.
  - `Revision::max` breaks equal compact-value ties deterministically by
    comparing the private fingerprint.
  - explicit authoring nodes cover the runtime operations, including filtering,
    Euclidean rhythms, degradation, periodic transforms, stereo split, and
    control-map merging.
  - deferred pattern work remains mini-notation ID reconciliation.
- Pattern lowering-cache groundwork shipped so far on `main`:
  - private per-node revision metadata inside authoring-document storage.
  - stable node identity plus revision boundaries for subtree invalidation.
  - lowering reuse keyed by stable node identity, a recursive private subtree
    token, and full revision equality.
  - coverage that editing one child invalidates that child and ancestors while
    reusing unchanged sibling lowerings.
  - regression coverage that a reused cache does not return stale audio for a
    freshly rebuilt document with the same stable ID and zero revision.
  - regression coverage that divergent replacement edits forked from the same
    base document do not alias cache entries for the edited child or ancestors.
- Scheduler snapshot-swap groundwork on active branch:
  - `PatternScheduler::queue_pattern_snapshot` stages a lowered
    `PatternSnapshot[ControlMap]` without changing playback immediately.
  - `PatternScheduler::process_snapshot_block` commits the pending snapshot at
    block start, before note expiry and event query for that block.
  - coverage proves block-boundary commit, no retroactive scheduling for past
    onsets, active-note let-ring across a silent replacement, and coalescing
    multiple pending snapshots to the latest staged snapshot.
- Latest local verification for active branch:
  - `rtk moon fmt`
  - `rtk moon info`
  - `rtk moon check`
  - `rtk moon test` (735 passed)
  - `rtk moon build --target wasm-gc`
  - `rtk git diff --check`
- Latest full local verification for PR #33 merge base `aa5f773`:
  - `rtk moon fmt`
  - `rtk moon info`
  - `rtk moon check`
  - `rtk moon test` (727 passed)
  - `rtk moon build --target wasm-gc`
  - `rtk git diff --check`

## Recommended Next Slice

1. Review, commit, and open PR for `codex/phase6-scheduler-snapshot-swap`.

2. After that branch merges, take the next Phase 6 slice from
   `docs/superpowers/specs/2026-05-12-phase6-incremental-playback-design.md`:
   mini-notation stable-ID reconciliation. Keep DSP graph identity for a later
   dedicated slice.

## Acceptance Checks For API-Hardening Slices

- Run `rtk moon info` and review `.mbti` diffs for intentional public API
  changes.
- Run `rtk moon fmt`, `rtk moon check`, and `rtk moon test`.
- If root facade or browser-relevant graph APIs changed, run
  `rtk moon build --target wasm-gc`.
- Update `docs/salat-engine-technical-reference.md` first for graph
  runtime-control behavior changes.
