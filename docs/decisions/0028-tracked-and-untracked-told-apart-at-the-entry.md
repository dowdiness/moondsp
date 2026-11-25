# ADR-0028: Tracked and untracked material are told apart where an entry is built

- **Status:** Accepted
- **Date:** 2026-11-25
- **Refines:** [ADR-0021](0021-song-structure-generic-over-content.md) §6
  (the scheduler names the two playable kinds)
- **Related:** [ADR-0018](0018-playback-visualization-origin-truth.md),
  [tracked and untracked entry allocation audit](../performance/2026-11-25-tracked-untracked-entry-allocations.md)

## Context

`CONTEXT.md` calls material whose events carry event origins *tracked* and
material without them *untracked*. ADR-0021 made tracked content a type
(`TrackedPatternSnapshot`, `Song[TrackedPatternSnapshot]`) and said the two kinds
are told apart "at the scheduler". In practice the scheduler spelled the
difference in three places: the facade's `PlaybackSnapshot`, the internal
`PlaybackSnapshot`, and `EntrySource`, with `EntrySpec::entered`,
`PlaybackSnapshot::entries` and `EntrySpec::query_sourced` each repeating one
arm per kind. Sourced events also carried four source fields with placeholders:
`-1.0` for the facts untracked events lack, and NaN for the pitch of a tracked
drum hit.

## Decision

1. Tracked and untracked stay two static types in `pattern` and `song`.
   Authoring, `control_traces` and `Song[TrackedPatternSnapshot]` need tracked
   statically, and a single material type would bring back ADR-0021's context #3
   (one type holding two capabilities, told apart at run time).
2. The difference is erased once per entry, where the scheduler builds the
   entry (`PlaybackSnapshot::entries`). An `EntryContent` holds closures built
   there for the entry's own operations (`entered`, `query_sourced`), so those
   operations have no per-kind branches. Adding a kind means adding one
   constructor.
3. A `PlaybackSourcedEvent` holds the lowered `EventWithOrigin` for tracked
   material and `None` for untracked. It replaces four fields and their
   placeholders. `OnsetBuffer::record` reads origin, frame, start and pitch from
   it, and the flat Double row it writes for the browser is unchanged, so the
   `-1.0` and NaN encodings live only there.
4. The facade's public `PlaybackSnapshot` and `SongMaterial` keep their tracked
   and untracked variants: callers choose the kind with a type.

## Considered options

- **One material type in `pattern`.** Rejected for the reason in decision 1.
- **A source-info enum on the event** (`Untracked | Tracked(origin) |
  TrackedInFrame(origin, frame, start)`). Typed, but each tracked event
  constructs one more object than today (`Option` of a reference is a nullable
  pointer, an enum payload is a struct): +6,152 executed constructions over
  3,000 blocks (+0.63%) for a tracked pattern, +1,922 (+0.52%) for a tracked
  song. Holding the existing `EventWithOrigin` costs nothing.
- **A struct holding `Option` fields for frame, start and pitch.** +1.25% for a
  tracked pattern, for the same reason.

## Consequences

- Executed `struct.new*`/`array.new*` counts, onset rows and rendered PCM are
  identical before and after for tracked and untracked patterns. Songs
  construct about 1% fewer objects (373k to 369k tracked, 354k to 350k
  untracked over 3,000 blocks); the cause was not investigated. Rendered PCM,
  onset rows and onset fields are identical for songs too. Method:
  `scripts/instrument-wasm-allocations.py` on the release browser build, a
  Player rendering at 48 kHz with 128-frame blocks, onsets off and on.
- The frame-and-start pair is guaranteed by `EventWithOrigin`, not by a type
  in the scheduler.
- `PlaybackSnapshot`'s own accessors (`revision`, `material_count`,
  `song_layout_revision`, `query_events`) still match per kind; they are small
  and belong to the public enum.
