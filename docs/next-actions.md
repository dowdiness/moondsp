# Next Actions

Updated: 2026-05-13

This is the active handoff list for future sessions. It should stay short and
actionable; move completed design notes or implementation plans under
`docs/superpowers/{specs,plans}/archive/` when they ship.

## Current State

- `main` is currently at
  `06a2787 feat(song): add explicit layout ranges (#38)`.
- Branch `codex/phase6-song-boundary-fills` starts the next deferred
  song-layout boundary slice from that merged head. It currently includes
  `8f9adc7 docs: mark song layout ranges merged`.
- PR #37 is merged:
  https://github.com/dowdiness/moondsp/pull/37
- PR #38 is merged:
  https://github.com/dowdiness/moondsp/pull/38
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
  - explicit occurrence starts can now create gaps and overlaps, with point and
    range occurrence lookup over overlapping layouts.
  - boundary fills are implemented on the current branch via uncovered-span
    detection and generated fill occurrences.
  - deferred song work remains song mini-notation, non-identity time-scope
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
- Scheduler snapshot-swap groundwork shipped so far on `main`:
  - `PatternScheduler::queue_pattern_snapshot` stages a lowered
    `PatternSnapshot[ControlMap]` without changing playback immediately.
  - `PatternScheduler::process_snapshot_block` commits the pending snapshot at
    block start, before note expiry and event query for that block.
  - coverage proves block-boundary commit, no retroactive scheduling for past
    onsets, active-note let-ring across a silent replacement, and coalescing
    multiple pending snapshots to the latest staged snapshot.
- Mini-notation stable-ID reconciliation shipped so far on `main`:
  - deterministic `PatternNodeId` assignment for parsed mini atoms,
    combinators, sequences, stacks, and method chains.
  - `parse_doc`, `parse_doc_reusing`, `parse_snapshot`, and
    `parse_snapshot_reusing` expose mini output through `PatternDoc` and
    `PatternSnapshot` without breaking the existing `parse` API.
  - `PatternDoc::subdoc` lets reconciliation reuse unchanged parsed subtrees
    with their existing generation/revision metadata.
  - coverage proves whitespace-only reparses preserve IDs and hit the lowering
    cache, token replacement preserves unaffected token IDs, insertion/removal
    keeps surviving token IDs, and changed tokens miss the cache while
    unchanged nodes hit.
- DSP graph identity mapping shipped so far on `main`:
  - `GraphTemplateDoc` owns stable `GraphNodeId` authoring IDs, graph nodes,
    revision state, and a retired-ID set.
  - `GraphIndexMap` maps stable IDs to existing graph indices and builds
    existing `GraphControl`, `ControlBindingBuilder`, and `GraphTopologyEdit`
    values at API boundaries.
  - the root `@moondsp` facade re-exports the graph identity API plus
    `GraphNodeId`, `Revision`, and `StableIdError` for documented facade
    consumers.
  - graph document edits preserve IDs for replacements and rewires, append IDs
    for inserted nodes/chains, compact IDs for deletions, and reject reuse of
    deleted IDs inside the same document.
  - coverage proves control, binding, and compile mapping; duplicate ID
    rejection; replace/rewire ID preservation; single-node and chain
    insert/delete compaction; and retired-ID rejection.
- Song layout ranges shipped so far on `main`:
  - `SongPart` can carry an optional explicit start via `SongPart::at` and
    `SongPart::with_id_at`; existing constructors remain implicit-contiguous.
  - implicit parts continue from the latest occurrence end, so explicit starts
    can create gaps or overlaps without pulling later implicit parts backward.
  - `Song::occurrences_at` and `Song::occurrences_intersecting` expose point
    and range lookup across overlapping layouts.
  - coverage proves gaps, overlap queries, range-address half-open boundaries,
    and implicit continuation after explicit overlaps.
- Song boundary fills implemented so far on `codex/phase6-song-boundary-fills`:
  - `Song::gap_spans` reports uncovered ranges in song-time order, treating
    overlaps as covered time rather than as new gaps.
  - `Song::fill_gaps(prefix~, section~)` returns a derived song with generated
    `prefix:index` occurrences for uncovered spans.
  - generated fill occurrences reuse the supplied section body/scope, resize
    section length to the uncovered span, and preserve all existing occurrence
    IDs and authoring order.
  - coverage proves multi-gap detection, fill sizing and query output, overlap
    coverage, existing-ID/order preservation, and generated-name collision
    errors.
- Latest local verification for the boundary-fill branch:
  - `moon fmt`
  - `moon info`
  - `moon check`
  - `moon test song` (33 passed)
  - `moon check --target all`
  - `moon test` (753 passed)
  - `moon build --target wasm-gc`
  - `git diff --check`
- Latest local verification for PR #38 before merge:
  - `rtk moon fmt`
  - `rtk moon info`
  - `rtk moon check`
  - `rtk moon test song` (28 passed)
  - `rtk moon test` (748 passed)
  - `rtk moon build --target wasm-gc`
  - `rtk moon check --target all`
  - `rtk git diff --check`
- Latest local verification for PR #37 before merge:
  - `rtk moon fmt`
  - `rtk moon info`
  - `rtk moon check`
  - `rtk moon test graph` (241 passed)
  - `rtk moon test` (744 passed)
  - `rtk moon build --target wasm-gc`
  - `rtk moon check --target all`
  - `rtk git diff --check`
- Latest full local verification for PR #33 merge base `aa5f773`:
  - `rtk moon fmt`
  - `rtk moon info`
  - `rtk moon check`
  - `rtk moon test` (727 passed)
  - `rtk moon build --target wasm-gc`
  - `rtk git diff --check`

## Recommended Next Slice

1. Review, commit, push, and open the PR for the boundary fills slice on
   `codex/phase6-song-boundary-fills`.

2. After that branch merges, continue with song mini-notation, non-identity
   time-scope transforms, or efficient secondary lookup indexes.

## Acceptance Checks For API-Hardening Slices

- Run `rtk moon info` and review `.mbti` diffs for intentional public API
  changes.
- Run `rtk moon fmt`, `rtk moon check`, and `rtk moon test`.
- If root facade or browser-relevant graph APIs changed, run
  `rtk moon build --target wasm-gc`.
- Update `docs/salat-engine-technical-reference.md` first for graph
  runtime-control behavior changes.
