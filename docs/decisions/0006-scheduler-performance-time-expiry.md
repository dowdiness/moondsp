# ADR-0006: Scheduler note expiry uses performance time

- **Status:** Accepted
- **Date:** 2026-05-11
- **Source:** [PR #29](https://github.com/dowdiness/moondsp/pull/29) design discussion and implementation

## Context

Before this decision, `PatternScheduler` tracked active note expiry as a
logical `Rational` cycle position. That matched the pattern engine's query
model, but it mixed two responsibilities:

- logical time: the compositional time seen by pattern combinators
- performance/audio time: the block/sample timeline used by the voice pool

Future groove, nudge, and rubato semantics all need note lifetimes to be
resolved against performance time. If active notes continue to expire in
logical time, a note whose start or end is shifted by a section time scope would
be difficult to reason about and could release at the wrong audio block.

## Decision

Track active-note expiry internally as absolute sample time.

The scheduler now exposes:

- `BlockFrame` with `sample_begin`, `sample_end`, and `logical_arc`
- `PerformanceTime(sample)`
- `cycle_to_sample(cycle, bpm, ctx)`
- `PatternScheduler::expire_notes_at(pool, PerformanceTime)`

`PatternScheduler::expire_notes(pool, arc)` remains as a compatibility wrapper
for callers and tests that still speak logical arcs. `process_block(...)` and
`process_section_block(...)` expire notes against `frame.sample_begin`.

Pattern combinators still operate only on logical time. This decision changes
only the scheduler's active-note bookkeeping and boundary conversion.

## Consequences

**Positive**

- The scheduler boundary now has an explicit performance-time representation
  before groove/rubato are introduced.
- Existing pattern playback remains block-quantized and keeps the same public
  `process_block(pat, ...)` entry point.
- `cycle_to_sample(...)` centralizes the inverse of the existing BPM scaling
  convention used by `compute_arc(...)`.

**Negative**

- Active notes keep their computed end sample when `set_bpm(...)` is called.
  This is a behavior clarification: newly scheduled notes use the new tempo,
  but already-active note releases do not move with later tempo changes.
- Sample conversion currently uses the scheduler's existing one-decimal BPM
  scaling convention. If tempo precision changes, `compute_arc(...)` and
  `cycle_to_sample(...)` must change together.

**Deferred**

- Sub-block note starts are not implemented here. Events whose onset falls
  inside a block still trigger at the start of that block. A future
  sample-accurate scheduler would need delayed note-on or sub-block voice
  rendering support.
