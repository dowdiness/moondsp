# ADR-0008: Contiguous song layout with computed occurrences

- **Status:** Accepted
- **Date:** 2026-05-11
- **Source:** Song layout implementation following PR #29

## Context

ADR-0005 introduced `Section[A]` as the first long-form structure layer above
patterns, but it did not define how sections are arranged over song time. The
next useful step is a first-class song value that can place sections and query
their events in one global logical timeline.

This should not introduce the full future addressing language yet. References
such as `verse2.last(4)`, explicit gaps, overlaps, stretch, boundary fills, and
path parsing need their own model and error semantics.

## Decision

Add a contiguous `Song[A]` layout model in `song/`.

The public authoring input is `SongPart[A]`, which gives one placement of a
reusable `Section[A]` a distinct occurrence name. The computed layout is exposed
through `SectionOccurrence[A]`, which carries the occurrence name, section, and
song-global time span.

`Song[A]` owns an ordered array of computed occurrences and a total duration.
The constructor rejects empty layouts and duplicate occurrence names. Starts and
ends are computed cumulatively from each section's validated length; users do
not provide explicit starts in this decision.

`Song::query(arc)` intersects the song-global query arc with each occurrence,
queries the section body in section-local time, then shifts returned events back
into song-global time. Event `part` remains clipped by the query/occurrence
intersection. Event `whole` is shifted without clipping so pattern duration
semantics remain intact.

This non-clipped `whole` behavior is intentional sustain semantics. A note that
begins near the end of a section may continue ringing into the next section if
its pattern duration extends past the boundary. The visible/query fragment is
still clipped through `part`, but scheduler note-off timing follows
`whole.end_`; clipping `whole` at section boundaries would create abrupt,
unnatural releases.

The scheduler gains `PatternScheduler::process_song_block(...)`, which mirrors
the existing section entry point and consumes `Song[ControlMap]` events in the
scheduler's current logical block frame.

## Consequences

**Positive**

- Long-form arrangement becomes a first-class polymorphic value without tying
  song structure to DSP controls.
- Reusing a section multiple times is explicit: one section definition can be
  placed as `verse1`, `verse2`, etc.
- The query boundary is now correct for future addressing and scheduler work:
  events are returned in song-global logical time.
- Notes can sustain naturally across section boundaries because event `whole`
  spans are shifted, not clipped.
- Keeping placement contiguous avoids committing early to gaps, overlaps, or
  stretch semantics.

**Negative**

- `Song::from_sections(...)` uses section names as occurrence names, so repeated
  section names require explicit `SongPart` construction.
- There is no efficient name index yet; occurrence lookup is linear.
- Section scopes still do not affect timing. `Song::query(...)` only translates
  logical time; groove/rubato remain deferred.

**Deferred**

- Explicit occurrence starts, gaps, overlaps, range addressing, boundary fills,
  and song mini-notation are left for follow-up decisions.
