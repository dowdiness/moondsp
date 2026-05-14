# Phase 6: Incremental Playback Edit Model - Design Spec

**Date:** 2026-05-12
**Status:** Draft; first identity/song slice implemented 2026-05-12; first
pattern authoring slice implemented 2026-05-12
**Related:**
`docs/next-actions.md`,
`docs/salat-engine-blueprint.md`,
`docs/decisions/0003-compiled-template-topology-artifact.md`,
`docs/decisions/0005-song-section-layer.md`,
`docs/decisions/0006-scheduler-performance-time-expiry.md`,
`docs/decisions/0008-contiguous-song-layout.md`

## Goal

Define the edit model needed for Phase 6 live playback:

- stable IDs for pattern, song, and DSP graph authoring objects
- incremental invalidation boundaries for edits
- scheduler behavior when edits arrive while audio is playing

The practical Phase 6 deliverable remains: editing a pattern while audio plays
should avoid rebuilding or retriggering unrelated material. Changed future
events should be heard; already-sounding voices should continue predictably.

## Current Baseline

The runtime has several useful pieces already:

- `Pat[A]` is a query closure over `TimeSpan`, with no stable authoring tree.
- `Song[A]` provides contiguous `SongPart` layout, named
  `SectionOccurrence`s, song-global spans, and `Song::query`.
- `PatternScheduler` derives `BlockFrame`s from a monotonic sample counter and
  tracks active note expiry in absolute sample time.
- `BoundVoicePool` owns the pair of voice template and
  `ControlBindingMap`, and swaps them transactionally.
- Graph topology and runtime-control APIs are result typed, but topology edits
  and controls still target authoring node indices.

This is enough to stage Phase 6 without changing the audio hot path first: add
identity-bearing authoring snapshots above the existing runtime APIs, then lower
those snapshots to `Pat`, `Song`, `BoundVoicePool`, `GraphControl`, and
`GraphTopologyEdit` values at block boundaries.

## Non-goals

- Do not replace `Pat[A]` as the runtime query representation in the first
  slice. Add an identity-bearing authoring layer that lowers to `Pat[A]`.
- Do not introduce sample-accurate note starts. Block-quantized scheduling
  remains the scheduler contract.
- Do not force active voices to restart after a pattern or song edit.
- Do not use content hashes as stable IDs. Content changes during edits; IDs
  must survive content changes.
- Do not expose a concrete incremental engine in public APIs. An `incr`
  dependency can back the implementation later, but public boundaries should be
  snapshots, revisions, IDs, and edit results.
- Do not change graph runtime-control behavior without first updating
  `docs/salat-engine-technical-reference.md`.

## Design Principles

1. IDs identify authoring intent, not array position.
2. Revisions identify content versions, not object identity.
3. Edits commit at audio block boundaries.
4. Failed edits leave the current playback snapshot untouched.
5. The scheduler never backfills missed note-ons after a late edit.
6. Active notes keep their already-computed gate-off sample unless an explicit
   future kill/replace policy says otherwise.

## Stable ID Model

Add typed ID wrappers for authoring objects that need to survive reordering,
layout compaction, parsing, and incremental rebuilds.

Place shared ID wrappers and `Revision` in a new dependency-free `identity/`
package. Current package imports make this the least coupled option:
`pattern/`, `graph/`, `song/`, and future orchestration code can all depend on
`identity/` without creating a cycle. Keeping the wrappers inside `song/` would
make `pattern/` and `graph/` either duplicate the revision/ID conventions or
depend on a higher-level package.

The wrapper API should follow the local tuple-wrapper style: public docs and
callers use named constructors/accessors; implementation code may use the tuple
constructor internally.

Proposed shared shape:

```moonbit
pub(all) suberror StableIdError {
  EmptyId
  InvalidId(String)
}

pub struct Revision(Int64)
pub fn Revision::zero() -> Revision
pub fn Revision::next(self : Revision) -> Revision

pub struct PatternNodeId(String)
pub fn PatternNodeId::from_string(value : String) -> PatternNodeId raise StableIdError

pub struct SectionId(String)
pub fn SectionId::from_string(value : String) -> SectionId raise StableIdError

pub struct SectionLayerId(String)
pub fn SectionLayerId::from_string(value : String) -> SectionLayerId raise StableIdError

pub struct OccurrenceId(String)
pub fn OccurrenceId::from_string(value : String) -> OccurrenceId raise StableIdError

pub struct GraphNodeId(String)
pub fn GraphNodeId::from_string(value : String) -> GraphNodeId raise StableIdError
```

ID strings should be non-empty and limited to a portable authoring subset:
ASCII letters, digits, `_`, `-`, `.`, and `:`. The exact validation helper can
be package-private. The public rule matters more than the storage type.

### Song IDs

The current `SongPart` occurrence name can seed `OccurrenceId` for the first
implementation slice, but it should not remain the only identity field.

Future repeated or renamed sections need:

- `SectionId` for the reusable section definition
- `SectionLayerId` for named layers inside a section
- `OccurrenceId` for one placement of a section in a song
- display names that can change without changing the ID

Current contiguous layout means occurrence spans are derived from ordered parts.
When a section length changes, downstream spans shift, but downstream occurrence
IDs do not change.

### Pattern IDs

`Pat[A]` is currently only a query closure, so it cannot support incremental
subtree invalidation by itself. Phase 6 should add an authoring pattern layer
that carries `PatternNodeId`s and lowers to `Pat[A]`.

Sketch:

```moonbit
pub struct PatternDoc[A] {
  root : PatternNodeId
  revision : Revision
}

pub struct PatternSnapshot[A] {
  root : PatternNodeId
  revision : Revision
  pat : Pat[A]
}
```

The exact internal node enum can be private. It should cover the existing
constructors and combinators first: silence, pure/control, fast, slow, rev,
sequence, stack, filter_map, euclid, degrade_by, every, jux, and merge_control.

Mini-notation parsing should eventually produce `PatternDoc[ControlMap]`. When
text changes, a reconciliation pass should preserve IDs for syntactically
unchanged subexpressions and allocate new IDs only for new subexpressions.

### Graph IDs

Graph runtime APIs currently target authoring indices. Phase 6 should add an
identity mapping layer rather than changing the compiled graph immediately.

Sketch:

```moonbit
pub struct GraphTemplateDoc {
  revision : Revision
}

pub struct GraphIndexMap {
  revision : Revision
}

pub fn GraphIndexMap::node_index(
  self : GraphIndexMap,
  id : GraphNodeId,
) -> Int?
```

`GraphNodeId` maps to authoring-order indices at the edge where the system
builds `GraphControl`, `ControlBindingBuilder`, or `GraphTopologyEdit`. This
keeps existing graph validation and result-typed errors useful while avoiding
index-based authoring commands.

Graph topology edits that insert/delete compacted arrays must preserve IDs for
surviving nodes and allocate IDs for new nodes. Deleted IDs must not be reused
within the same authoring document.

## Incremental Invalidation Boundaries

Every authoring snapshot should carry a `Revision`. Revisions are cheap
monotonic tokens used to invalidate caches. Stable IDs say "same authoring
object"; revisions say "same or different content".

### Pattern Edit

Invalidates:

- edited pattern node
- ancestor pattern nodes up to the pattern root
- any lowered `Pat[A]` snapshots for those nodes

Does not invalidate:

- sibling subtrees with unchanged IDs and revisions
- containing section layout if the section length does not change
- song layout if section length and occurrence placement do not change
- DSP template/bindings unless the edit changes control keys that require a
  different binding model

The minimum cache is a lowering cache keyed by `(PatternNodeId, Revision)` that
returns a lowered `Pat[A]`. Query-result caching by block arc can be added
later, but it is not required for the first Phase 6 slice.

### Section Layer Edit

Invalidates:

- the changed `SectionLayerId`
- the section body lowering
- any section snapshot that includes that layer

Does not invalidate:

- other layers in the same section
- song occurrence order or spans if section length is unchanged
- active notes that were already scheduled

### Section Length Or TimeScope Edit

Invalidates:

- the edited section snapshot
- all contiguous song occurrence spans at and after each occurrence of that
  section
- scheduler queries from the next committed block onward

Does not invalidate:

- the stable `OccurrenceId`s of shifted occurrences
- active note gate-off samples that were already computed before the edit

`TimeScope` is identity-only today. When non-identity scopes are introduced,
scope edits must invalidate the section-to-performance-time mapping, not just
pattern lowering.

### Song Layout Edit

Invalidates:

- the song layout index
- occurrence spans from the first changed placement onward in the contiguous
  model
- range-address lookup caches

Does not invalidate:

- section definitions whose IDs and revisions are unchanged
- pattern lowerings inside unchanged sections
- active notes that were already scheduled from the old layout

Insert/delete/reorder operations must keep `OccurrenceId`s for surviving
placements. A rename changes display text only; it must not force a new
occurrence ID.

### DSP Parameter Edit

There are two distinct cases:

1. **Template default edit:** updates the voice template used for future
   `note_on`s. Active voices keep their already-compiled graph.
2. **Live active-voice edit:** applies `GraphControl`s to currently active
   compiled voices. This needs an explicit `BoundVoicePool` API in a later
   implementation slice; it should resolve `GraphNodeId` through the current
   `GraphIndexMap` and return result-typed failures.

The first Phase 6 implementation can support template-default edits only. A
later slice can add active-voice controls when the desired musical semantics
are clear.

### DSP Topology Edit

Invalidates:

- `GraphIndexMap`
- `CompiledTemplate`
- `ControlBindingMap`
- voice template snapshot used for future `note_on`s

Must be transactional through `BoundVoicePool::set_template(template, bindings)`.
If template validation, compilation, or binding validation fails, playback keeps
the previous template and binding map.

Active voices keep their compiled graph and their `VoiceSlot.template_snapshot`
for note-off. New voices use the new template after the edit commits.

## Playback Snapshot

Introduce a single immutable playback snapshot for scheduler consumption.

Sketch:

```moonbit
pub struct PlaybackSnapshot {
  revision : Revision
}

pub(all) enum PlaybackEditError {
  InvalidPattern(StableIdError)
  InvalidSong(SongBuildError)
  InvalidVoicePool(BoundVoicePoolError)
  InvalidGraphControl(GraphControlError)
  InvalidTopology(GraphTopologyQueueError)
}
```

The exact package boundary can be chosen during implementation. The important
boundary is semantic:

- authoring/editor code mutates documents and builds the next snapshot
- scheduler/audio code reads only the current snapshot
- snapshot swap is atomic at block boundary

For the current package graph, a small `live/` package may be justified later:
it would depend on `pattern/`, `song/`, `scheduler/`, and the root `@moondsp`
facade. Do not add it until two packages need to share this orchestration.

## Scheduler Commit Semantics

The scheduler should treat edits as pending commits that become visible only at
the beginning of a block.

Block order:

1. compute `BlockFrame` from the current sample counter
2. commit at most one prepared playback snapshot for `frame.sample_begin`
3. expire active notes at `PerformanceTime(frame.sample_begin)`
4. query the committed snapshot for `frame.logical_arc`
5. process events whose `whole.begin` is inside the block arc
6. advance the sample counter
7. render the voice pool

If multiple edits arrive between blocks, the implementation may coalesce them
and commit only the latest successfully prepared snapshot. Rejected edits do
not affect the current snapshot.

### No Retroactive Scheduling

When a new pattern or song snapshot is committed, the scheduler does not scan
backward for note-ons that would have occurred before the current block. It
only triggers events whose `whole.begin` is contained in the current block arc.

Consequences:

- adding a note whose onset is already in the past does not trigger it late
- moving a future note earlier can make it silent if the new onset is before
  the commit block
- moving a note later works normally if the new onset is still in the future

This rule keeps edit behavior deterministic and avoids bursts of backfilled
voices after large song edits.

### Active Note Policy

Default policy: let active notes ring to their stored `end_sample`.

Pattern/song edits do not call `note_off` for existing voices, even if the new
snapshot removes the event that created the voice. This matches the current
sample-time expiry model and avoids abrupt releases at edit boundaries.

Future policies can be explicit:

- `LetRing` - current default
- `GateOffAffected` - gate off voices linked to changed IDs
- `KillAffected` - immediate stop for destructive edits

Do not add those policies until active notes carry enough provenance to decide
which voice came from which pattern node, section, and occurrence.

### Event Provenance

To support future affected-voice policies and better debugging, scheduler
events should eventually carry optional provenance:

```moonbit
pub struct EventSource {
  pattern_node : PatternNodeId?
  section : SectionId?
  layer : SectionLayerId?
  occurrence : OccurrenceId?
}
```

This should not be added to `Event[A]` in the first slice. A wrapper around
queried events is enough for scheduler/live orchestration. Keep `pattern/`
standalone and payload-polymorphic.

Implementation direction as of the affected-voice policy slice: explicit
playback-event query helpers attach provenance where the committed snapshot has
it, while default audio-block processing continues through raw event queries and
empty sources. This keeps compatibility and avoids reintroducing wrapper
allocation into the default block-processing path. Pattern snapshots currently
provide authored pattern-node path provenance through
`PatternSnapshot::query_sourced_events`; structural nodes preserve ancestor and
leaf IDs, while callback nodes (`every`, `jux`, `merge_control`)
conservatively tag their wrapper ID plus all reachable child subtree node IDs.
Song snapshots provide occurrence and section/layer provenance from the
authoring document through
`SongSnapshot::query_sourced_events`.

## Edit Behavior Matrix

| Edit while playing | Commit result | Active voices | Future note-ons |
| --- | --- | --- | --- |
| Change pattern value | New pattern revision | Let ring | Use new value from next block |
| Change pattern structure | Rebuilt ancestors only | Let ring | Changed subtree affects future events |
| Change section layer | New section revision | Let ring | Occurrences of that section use new layer |
| Change section length | New song layout revision | Let ring with old end samples | Downstream occurrence spans shift |
| Insert song occurrence | New song layout revision | Let ring | New occurrence schedules future onsets only |
| Delete song occurrence | New song layout revision | Let ring | Removed occurrence stops scheduling future onsets |
| Rename occurrence | Display-only revision | Let ring | No timing change |
| Change DSP template default | Transactional pool swap | Existing voices keep old compiled graph | New voices use new template |
| Change DSP topology | Transactional pool swap | Existing voices keep old compiled graph | New voices use new topology |
| Invalid DSP topology/binding | Reject edit | Unchanged | Unchanged |

## Interaction With Existing Result-Typed APIs

Phase 6 should preserve the hardening already shipped:

- graph controls still return `GraphControlError`
- hot-swap queues still return `HotSwapQueueError`
- topology queues still return `GraphTopologyQueueError`
- bound voice template/binding swaps still return `BoundVoicePoolError`

Stable IDs should lower to existing index-based APIs only after validation.
For example, a graph parameter edit by `GraphNodeId` should fail before
constructing `GraphControl` if the ID is absent from the current `GraphIndexMap`.

## First Implementation Slice

1. Add a dependency-free `identity/` package with typed stable ID wrappers and
   `Revision`.
2. Extend `song/` with identity-bearing section/layer/occurrence variants or
   adapters that preserve the existing constructors.
3. Add an occurrence index keyed by `OccurrenceId` while keeping current
   name-based lookup for compatibility.
4. Add tests proving that reordering or length changes preserve surviving
   occurrence IDs.
5. Keep the current `PatternScheduler::process_song_block(song, ...)`
   entry point unchanged.

This slice gives the song scaffold stable identity and creates the pressure
test for pattern and graph IDs without changing mini-notation or browser UI.

## Later Implementation Slices

### Pattern Authoring Layer

- First slice shipped an authoring document with private node storage, stable
  node IDs, revisioned edits, and lowering snapshots back to the existing
  runtime query model.
- The explicit-node slice covers the runtime pattern operations, including
  filtering, Euclidean rhythms, degradation, periodic transforms, stereo split,
  and control-map merging.
- Add a lowering cache keyed by node ID and revision.
- Update mini-notation parsing to preserve IDs across text edits where a small
  reconciliation pass can prove syntactic continuity.

### Graph Identity Layer

- Add `GraphNodeId` to the authoring graph layer.
- Build `GraphIndexMap` at compile/template-analysis time.
- Add ID-based helper APIs that lower to `GraphControl`,
  `ControlBindingBuilder`, and `GraphTopologyEdit`.
- Keep raw index-based graph APIs as low-level escape hatches.

### Scheduler Snapshot Swap

- Add a pending snapshot queue or slot.
- Commit prepared snapshots at block boundaries.
- Add tests for no retroactive scheduling, failed-edit rollback, and active
  note let-ring behavior.

### Active Voice Live Controls

- Add provenance to scheduled voices.
- Add a `BoundVoicePool` result API for applying validated controls to active
  voices when a live control edit should affect already-sounding notes.
- Decide whether smoothed parameter changes are graph-level controls,
  `ControlMap` events, or a separate automation lane.

## Acceptance Checks

For design-only changes:

- `rtk git diff --check`

For implementation slices:

- `rtk moon fmt`
- `rtk moon info`
- `rtk moon check`
- `rtk moon test`
- `rtk moon build --target wasm-gc` when facade, graph, voice, scheduler, or
  browser-relevant APIs change
- `rtk npm run test:browser` when browser behavior changes

## Open Questions

- Should the first pattern authoring layer cover all existing combinators or
  only the subset emitted by mini-notation?
- Should section length edits immediately affect the current cycle after the
  commit block, or only future cycle boundaries?
- Should callback-heavy pattern APIs later grow a typed sourced-query contract
  for exact leaf attribution, or is conservative subtree coverage sufficient
  for edit policies?
- Should live active-voice controls beyond explicit affected-voice policies
  target every active voice, selected provenance, or only future voices by
  default?
