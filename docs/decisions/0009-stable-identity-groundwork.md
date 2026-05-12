# ADR-0009: Stable identity groundwork for Phase 6

- **Status:** Accepted
- **Date:** 2026-05-12
- **Source:** [`docs/superpowers/specs/2026-05-12-phase6-incremental-playback-design.md`](../superpowers/specs/2026-05-12-phase6-incremental-playback-design.md)

## Context

Phase 6 needs incremental playback edits. Pattern, song, and graph authoring
objects must survive reordering, layout shifts, parsing, and topology
compaction without relying on array positions or mutable display names.

The current song scaffold already has occurrence names and contiguous computed
spans, but names serve two roles at once: user-facing labels and implicit
identity. That is enough for static layout, but it is too fragile for future
range addressing, rename operations, and incremental invalidation.

The identity model also needs to serve future pattern and graph work. Putting
shared ID types inside `song/` would force lower-level packages such as
`pattern/` or `graph/` to depend on a higher-level song package, or to
duplicate ID and revision conventions.

## Decision

Add a dependency-free `identity/` package containing:

- `Revision`
- `PatternNodeId`
- `SectionId`
- `SectionLayerId`
- `OccurrenceId`
- `GraphNodeId`
- `StableIdError`

Stable IDs are string wrappers with named constructors and `value()` accessors.
They reject empty strings and characters outside a portable authoring subset:
ASCII letters, digits, `_`, `-`, `.`, and `:`.

Use this package in `song/` for the first Phase 6 implementation slice:

- `SongPart[A]` keeps the existing `SongPart(name~, section~)` constructor,
  deriving `OccurrenceId` from the name for compatibility.
- `SongPart::with_id(id~, name~, section~)` lets callers separate stable
  identity from display names.
- `SectionOccurrence[A]` exposes `id()`.
- `Song[A]` keeps name lookup and adds `get_occurrence_by_id(...)`.
- duplicate names still raise `DuplicateOccurrence`; duplicate explicit or
  derived IDs raise `DuplicateOccurrenceId`.

## Consequences

**Positive**

- Phase 6 now has a shared identity vocabulary without introducing package
  cycles.
- Existing song callers continue using `SongPart(name~, section~)`.
- Display names can contain spaces or other non-ID characters when callers use
  explicit IDs.
- Occurrence lookup by stable ID survives reordering and section length
  changes.

**Negative**

- The compatibility constructor now requires occurrence names to be valid ID
  strings because the name is used to seed the ID.
- Public APIs now expose `identity/` types from `song/`, so downstream users
  who adopt explicit IDs import one more package.
- Name lookup remains linear; only stable-ID lookup has an index in this slice.

**Deferred**

- Pattern authoring documents with stable `PatternNodeId`s.
- Graph authoring/index maps with stable `GraphNodeId`s.
- Scheduler snapshot swapping and no-retroactive edit commit behavior.
- Efficient name/range indexes, explicit occurrence starts, gaps, overlaps,
  range addressing, boundary fills, song mini-notation, and non-identity
  `TimeScope` behavior.
