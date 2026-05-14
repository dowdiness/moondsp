# Next Actions

Updated: 2026-05-14

This is the active handoff list for future sessions. It should stay short and
actionable; move completed design notes or implementation plans under
`docs/superpowers/{specs,plans}/archive/` when they ship.

## Current State

- `main` is currently at
  `81b1b19 [codex] Add scheduler song snapshots and playback provenance (#45)`.
- PR #37 is merged:
  https://github.com/dowdiness/moondsp/pull/37
- PR #38 is merged:
  https://github.com/dowdiness/moondsp/pull/38
- PR #39 is merged:
  https://github.com/dowdiness/moondsp/pull/39
- PR #40 is merged:
  https://github.com/dowdiness/moondsp/pull/40
- PR #41 is merged:
  https://github.com/dowdiness/moondsp/pull/41
- PR #42 is merged:
  https://github.com/dowdiness/moondsp/pull/42
- PR #43 is merged:
  https://github.com/dowdiness/moondsp/pull/43
- PR #44 is merged:
  https://github.com/dowdiness/moondsp/pull/44
- PR #45 is merged:
  https://github.com/dowdiness/moondsp/pull/45
- Active branch: `codex/phase6-affected-voice-policy`, based on
  `81b1b19 [codex] Add scheduler song snapshots and playback provenance (#45)`.
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
  - boundary fills now derive generated fill occurrences from uncovered song
    spans while preserving existing occurrence identity and authoring order.
  - song mini-notation parses sections, parts, explicit starts, explicit
    occurrence IDs, gaps, overlaps, and fills.
  - non-identity `TimeScope` transforms apply section-local rate changes
    through song and direct section playback.
  - efficient secondary lookup indexes now cover occurrence name, stable ID,
    start time, and end time while preserving authoring-order overlap results.
  - section/layer authoring identity and revision boundaries now cover reusable
    section definitions and layered section bodies.
  - deferred song work is now an identity-bearing song layout authoring model
    for occurrence edits and layout revision boundaries.
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
- Song mini-notation shipped so far on `main`:
  - `parse_song` parses `song(...)` text into `Song[ControlMap]`.
  - `section("name", length, pattern_expr)` reuses the existing pattern mini
    expression surface, including `s(...)`, `note(...)`, `stack(...)`, and
    method chains.
  - `part(...)` supports implicit-contiguous and explicit rational starts;
    `part_id(...)` supports stable occurrence IDs separate from display names.
  - `fill("prefix", "section")` applies the boundary-fill surface over parsed
    gaps after the base song layout is built.
  - coverage proves implicit sections/parts, exact rational starts and gaps,
    explicit overlaps with authoring order, boundary fills, explicit occurrence
    IDs, and unknown-section errors.
- TimeScope transforms shipped so far on `main`:
  - `TimeScope` now carries an exact body-cycles-per-section-cycle rate and
    exposes identity, `at_rate`, `fast`, `slow`, and non-positive validation.
  - `Section::query` applies the section scope while `Section::body` continues
    to expose the raw unscoped pattern for structural callers.
  - `Song::query` and `PatternScheduler::process_section_block` now route
    through `Section::query`, so song and direct section playback observe the
    same scope mapping.
  - coverage proves fast/slow scope construction, invalid rate rejection,
    scoped section query output, and song occurrence spans staying unchanged
    while scoped events move inside those spans.
- Latest local verification for PR #41 before merge:
  - `rtk moon fmt`
  - `rtk moon info`
  - `rtk moon check`
  - `rtk moon test song` (37 passed)
  - `rtk moon test scheduler` (33 passed)
  - `rtk moon check --target all`
  - `rtk moon test` (763 passed)
  - `rtk moon build --target wasm-gc`
  - `rtk git diff --check`
- Song lookup indexes shipped so far on `main`:
  - `Song` now keeps private secondary indexes for occurrence name, stable ID,
    start time, and end time.
  - point and range occurrence lookups bound candidate scans with the start/end
    indexes, then return hits in authoring order to preserve overlap semantics.
  - `Song::query`, `Song::gap_spans`, `Song::get_occurrence`, and
    `Song::get_occurrence_by_id` now use the indexed paths without changing
    the public song API surface.
  - coverage proves timeline-sorted overlapping occurrences still return in
    authoring order for `occurrence_at`, `occurrences_at`, and
    `occurrences_intersecting`.
- Latest local verification for PR #42 before merge:
  - `rtk moon fmt`
  - `rtk moon info`
  - `rtk moon check`
  - `rtk moon test song` (38 passed)
  - `rtk moon check --target all`
  - `rtk moon test` (764 passed)
  - `rtk moon build --target wasm-gc`
  - `rtk git diff --check`
- Song section/layer identity shipped so far on `main`:
  - identity-preserving section and layer authoring adapters now cover reusable
    section definitions and layered section bodies.
  - section and layer display renames preserve stable identities and revisions;
    layer body edits advance the affected layer revision and the containing
    section revision.
  - section length and scope edits advance the section revision; length edits
    may still shift downstream song layout while preserving occurrence IDs.
  - the authoring model lowers back to the existing playback/query surface
    without changing current song/scheduler query semantics.
  - coverage proves section/layer display rename stability, duplicate layer
    display-name rejection, body revision boundaries without layout changes,
    and length-driven layout shifts with stable occurrence IDs.
- Latest local verification for PR #43 before merge:
  - `rtk moon fmt`
  - `rtk moon info`
  - `rtk moon check`
  - `rtk moon test song` (43 passed)
  - `rtk moon check --target all`
  - `rtk moon test` (769 passed)
  - `rtk moon build --target wasm-gc`
  - `rtk git diff --check`
- Song layout authoring shipped so far on `main`:
  - identity-preserving song layout authoring now covers section placements and
    lowers back to the existing playback/query surface.
  - occurrence display renames advance the authoring revision while preserving
    the layout revision, stable occurrence identity, and computed spans.
  - occurrence insertion, removal, reordering, and explicit-start edits advance
    the layout revision and preserve surviving occurrence identities.
  - same-length section edits reuse the existing layout boundary, while section
    length edits advance the layout revision and shift downstream spans.
  - coverage proves rename stability, insertion/removal, reorder, downstream
    span shifts, unchanged section reuse, and missing-ID edit errors.
- Latest local verification for PR #44 before merge:
  - `rtk moon fmt`
  - `rtk moon info`
  - `rtk moon check`
  - `rtk moon test song` (49 passed)
  - `rtk moon check --target all`
  - `rtk moon test` (775 passed)
  - `rtk moon build --target wasm-gc`
  - `rtk git diff --check`
- Song layout scheduler snapshot/provenance shipped so far on `main`:
  - song authoring lowers to runtime snapshots that carry both whole-document
    and layout-scoped revision tokens, so playback can distinguish content-only
    edits from timeline-boundary edits.
  - staged playback changes commit only at audio block boundaries, and multiple
    staged changes coalesce so the latest pending state wins before the next
    block starts.
  - pattern and song playback share one staging boundary while existing pattern,
    section, song, snapshot, and raw-event processing entry points remain
    compatible.
  - authored playback can propagate source provenance into active notes, while
    legacy raw-event paths continue to use an explicit empty source until richer
    authoring context is available.
  - raw-event processing preserves caller-owned event array ordering and never
    sorts or mutates those arrays in place.
  - audio-block paths avoid per-event wrapper allocation on empty-source
    compatibility paths.
  - runtime revision tokens remain available to orchestration layers for
    snapshot-swap decisions without changing existing raw song-processing
    behavior.
  - coverage proves block-boundary commit timing, same-layout body edits
    committing without layout-boundary churn, no retroactive note-on backfill,
    active-note let-ring across layout replacement, latest-staged-state
    coalescing, empty default source behavior, explicit source retention for
    authored playback, public event-query compatibility, and caller-owned
    event-order preservation.
- Latest local verification on `codex/phase6-song-layout-scheduler`:
  - `rtk moon fmt`
  - `rtk moon info`
  - `rtk moon check`
  - `rtk moon test song` (49 passed)
  - `rtk moon test scheduler` (43 passed)
  - `rtk moon check --target all`
  - `rtk moon test` (785 passed)
  - `rtk moon build --target wasm-gc`
  - `rtk git diff --check`
  - final PR #45 CI passed before merge; merged at `81b1b19`.
- Active affected-voice policy branch:
  - provenance selectors can target active voices by pattern node, section,
    layer, occurrence, or a combined subset of those IDs.
  - empty selectors intentionally match nothing, and empty-source compatibility
    voices are not affected by provenance-targeted edits.
  - the first policy surface keeps the default let-ring behavior explicit and
    adds an explicit gate-off path for matched active voices without adding
    allocation to the audio-block query path.
  - explicit sourced snapshot queries now attach root pattern provenance for
    pattern snapshots and occurrence/section provenance for song snapshots,
    while block-processing compatibility paths continue to use raw events and
    empty sources.
  - coverage proves selector matching, empty-source safety, let-ring no-op,
    pattern-node targeting, section targeting, occurrence/layout targeting,
    sourced pattern/song snapshot queries, and empty-source block processing.
- Latest local verification on `codex/phase6-affected-voice-policy`:
  - `rtk moon update`
  - `rtk moon fmt`
  - `rtk moon info`
  - `rtk moon check --deny-warn`
  - `rtk moon test scheduler` (48 passed)
  - `rtk moon test song` (49 passed)
  - `rtk moon check --target all`
  - `rtk moon test` (790 passed)
  - `rtk moon test --release` (790 passed)
  - `rtk moon build --target wasm-gc`
  - `rtk git diff --check`
- Latest local verification for PR #40 before merge:
  - `moon fmt`
  - `moon info`
  - `moon check`
  - `moon test mini` (64 passed)
  - `moon check --target all`
  - `moon test` (759 passed)
  - `moon build --target wasm-gc`
  - `git diff --check`
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
- Song boundary fills shipped so far on `main`:
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
- Latest local verification for PR #39 before merge:
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

1. Continue the stacked Phase 6 branch without opening a PR yet.

2. Next implementation choice: add layer-level song provenance or pattern
   sub-node provenance. The current sourced wrapper query surface is intentionally
   coarse for pattern snapshots and does not yet identify section layers.

## Acceptance Checks For API-Hardening Slices

- Run `rtk moon info` and review `.mbti` diffs for intentional public API
  changes.
- Run `rtk moon fmt`, `rtk moon check`, and `rtk moon test`.
- If root facade or browser-relevant graph APIs changed, run
  `rtk moon build --target wasm-gc`.
- Update `docs/salat-engine-technical-reference.md` first for graph
  runtime-control behavior changes.
