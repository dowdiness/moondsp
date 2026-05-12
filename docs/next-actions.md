# Next Actions

Updated: 2026-05-12

This is the active handoff list for future sessions. It should stay short and
actionable; move completed design notes or implementation plans under
`docs/superpowers/{specs,plans}/archive/` when they ship.

## Current State

- `main` is currently at
  `fdfa12b Merge pull request #31 from dowdiness/codex/phase6-stable-identity`.
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
- Pattern authoring groundwork shipped so far:
  - identity-bearing authoring documents over the existing runtime query model.
  - private node storage with stable node lookup helpers.
  - revisioned edits for root changes, node replacement, and core
    structure-building operations.
  - aggregate document revisions derive from an ordered child-revision mix,
    with coverage for rebuilt sequence/stack roots, mixed-revision merged
    inputs, and shifted child-revision aliases.
  - explicit authoring nodes cover the runtime operations, including filtering,
    Euclidean rhythms, degradation, periodic transforms, stereo split, and
    control-map merging.
  - lowering snapshots back to the runtime query model.
  - deferred pattern work remains lowering caches, mini-notation ID
    reconciliation, and scheduler snapshot swapping.
- Latest full verification for current head plus local Phase 6 pattern
  authoring groundwork:
  - `rtk moon fmt`
  - `rtk moon info`
  - `rtk moon check`
  - `rtk moon test` (726 passed)
  - `rtk moon build --target wasm-gc`
  - `rtk git diff --check`

## Recommended Next Slice

1. Implement the Phase 6 pattern authoring layer from
   `docs/superpowers/specs/2026-05-12-phase6-incremental-playback-design.md`.

   Continue from the explicit-node slice by adding the first lowering cache
   boundary. Keep mini-notation reconciliation and scheduler snapshot swapping
   out of the next slice unless the cache boundary requires a small integration
   test.

## Acceptance Checks For API-Hardening Slices

- Run `rtk moon info` and review `.mbti` diffs for intentional public API
  changes.
- Run `rtk moon fmt`, `rtk moon check`, and `rtk moon test`.
- If root facade or browser-relevant graph APIs changed, run
  `rtk moon build --target wasm-gc`.
- Update `docs/salat-engine-technical-reference.md` first for graph
  runtime-control behavior changes.
