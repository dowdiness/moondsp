# Next Actions

Updated: 2026-05-12

This is the active handoff list for future sessions. It should stay short and
actionable; move completed design notes or implementation plans under
`docs/superpowers/{specs,plans}/archive/` when they ship.

## Current State

- `main` is currently at
  `44ccb09 Merge pull request #30 from dowdiness/codex-song-layout-model`
  (`558f644 feat(song): add contiguous song layout`).
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
  - named section layers and section patch APIs.
  - contiguous `SongPart` layout with named `SectionOccurrence`s,
    song-global spans, occurrence lookup, and `Song::query`.
  - scheduler entrypoints for sections and songs, including
    `PatternScheduler::process_song_block`.
  - Phase 6 identity groundwork: dependency-free `identity/` package,
    `Revision`, typed stable ID wrappers, explicit occurrence IDs on
    `SongPart`, stable IDs on `SectionOccurrence`, and
    `Song::get_occurrence_by_id`.
  - deferred song work remains explicit starts, gaps, overlaps, range
    addressing, boundary fills, song mini-notation, effective `TimeScope`
    transforms, and efficient name/range indexes beyond stable-ID lookup.
- Latest full verification for current `main` plus local Phase 6 identity
  groundwork:
  - `rtk moon fmt`
  - `rtk moon info`
  - `rtk moon check`
  - `rtk moon test`
  - `rtk moon build --target wasm-gc`
  - `rtk git diff --check`

## Recommended Next Slice

1. Implement the Phase 6 pattern authoring layer from
   `docs/superpowers/specs/2026-05-12-phase6-incremental-playback-design.md`.

   Start with `PatternDoc[A]` over the existing `Pat[A]` runtime query model:
   stable `PatternNodeId`s, private node storage, revisions, and a lowering
   path that can later be cached by `(PatternNodeId, Revision)`. Do not change
   mini-notation or scheduler snapshot swapping in the first pattern slice.

## Acceptance Checks For API-Hardening Slices

- Run `rtk moon info` and review `.mbti` diffs for intentional public API
  changes.
- Run `rtk moon fmt`, `rtk moon check`, and `rtk moon test`.
- If root facade or browser-relevant graph APIs changed, run
  `rtk moon build --target wasm-gc`.
- Update `docs/salat-engine-technical-reference.md` first for graph
  runtime-control behavior changes.
