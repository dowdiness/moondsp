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
shared identity conventions inside one higher-level authoring area would either
force the lower-level layers to depend upward or encourage each layer to invent
incompatible identity and revision rules.

## Decision

Introduce a small, dependency-free identity layer that all authoring packages
can share without creating package cycles. It provides validated stable
identities for authoring objects and revision tokens for future incremental
invalidation.

Stable identities use a portable text representation. They reject empty values
and characters outside the agreed authoring subset so serialized references,
generated names, and user-authored references can share the same rules.

Apply the first implementation slice to song occurrences. Occurrence identity
is now separate from display labels, while compatibility paths continue to
derive identity from simple labels where possible. Song construction validates
identity uniqueness up front, so later lookup and invalidation logic can assume
that occurrence identity is unambiguous.

Detailed public API names and generated interface changes live in the Phase 6
design spec, changelog, and generated package interfaces rather than this
decision record.

## Consequences

**Positive**

- Phase 6 now has a shared identity vocabulary without introducing package
  cycles.
- Existing song callers can keep using the simple construction path when labels
  are valid stable identities.
- Display names can contain spaces or other non-ID characters when callers use
  explicit IDs.
- Occurrence lookup by stable ID survives reordering and section length
  changes.

**Negative**

- The compatibility constructor now requires occurrence names to be valid ID
  strings because the name is used to seed the ID.
- Downstream users who adopt explicit identities now work with the shared
  identity layer directly.
- Name lookup remains linear; only stable-ID lookup has an index in this slice.

**Deferred**

- Pattern authoring documents with stable node identities.
- Graph authoring and index maps with stable graph identities.
- Scheduler snapshot swapping and no-retroactive edit commit behavior.
- Efficient name/range indexes, explicit occurrence starts, gaps, overlaps,
  range addressing, boundary fills, song mini-notation, and non-identity
  time-scope behavior.
