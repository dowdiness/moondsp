# ADR-0031: Playback takes one view of a pattern, whatever tracks it

- **Status:** Accepted
- **Date:** 2026-11-27
- **Supersedes:** [ADR-0028](0028-tracked-and-untracked-told-apart-at-the-entry.md)
  Decision 4, [ADR-0021](0021-song-structure-generic-over-content.md) §6
- **Related:** issue #292,
  [entry allocation audit](../performance/2026-11-25-tracked-untracked-entry-allocations.md#playback-view-adr-0031)

## Context

ADR-0028 erased the tracked/untracked difference inside the scheduler, once
per entry, but left it in the public interface: `PlaybackSnapshot` had the
variants `UntrackedPattern`, `TrackedPattern`, `Song(SongMaterial)` and
`RepeatSong(SongMaterial)`, and `SongMaterial` had `Untracked` and `Tracked`.
The facade mirrored the internal enum with `raw`/`from_raw`, each kind had its
own `EntryContent` builder, every caller and `@player.Score` had one
constructor per kind, and a repeating song rebuilt its entry specs at every
repetition. The difference that matters to playback is per event — does this
event carry an origin — not per kind of material.

A trait cannot unify the kinds at the scheduler: it would return per-event
types the scheduler keeps internal (ADR-0015), and a trait in `pattern`
cannot name `ScoreEvent`.

## Decision

1. **`@pattern.PlaybackPattern[A]` is what playback plays of a pattern.**
   `UntrackedPatternSnapshot::playback`, `TrackedPatternSnapshot::playback`
   and `Pat::playback` build one. Its `query_for_entry` hands each event over
   with its node path and event origin as `Option`s: the three-way dispatch
   lives once, in `pattern`. The snapshots stay two static types (ADR-0028
   Decision 1); the view is not a material type and has no authoring use.
2. **`SongContent` gains `playback()`**, and `SongEntry` exposes `content`,
   `content_entry` and `placement`, so the scheduler builds each entry's
   view and placement once instead of slicing per query.
3. **`@scheduler.PlaybackSnapshot` is an opaque value built once**: its
   revisions, its repetition period and its entry specs. It has two
   constructors, `pattern(PlaybackPattern)` and
   `song(SongSnapshot[C : SongContent], repeat?)`. `SongMaterial`, the enum
   variants, `raw`/`from_raw`, `queue_pattern_snapshot` and
   `queue_song_snapshot` are gone; callers use `queue_playback_snapshot`. A
   plain pattern has revision zero and its voices are `Anonymous`.
4. **`@player.Score` has two constructors**, `pattern` and `song`, for the
   same reason.

## Considered options

- **Keep the four constructors and make only the internals one struct.**
  No allocation change, but the public interface keeps naming the kinds,
  which is what #292 is about.
- **A per-event struct returned by `PlaybackPattern`.** One more
  construction per event.
- **A lambda per query.** One closure per entry query (+0.61% for patterns).

## Consequences

- Adding a kind of pattern means one `PlaybackPattern` constructor; the
  scheduler, the player and the browser host do not change.
- `query_for_entry` takes the query's `Placement` and a mapper built once
  per entry, so a query constructs no closure. Patterns construct as many
  objects as before; tracked songs 1.96% fewer, since their view and
  placement are built once. Untracked songs, which no production input sends
  (#296), construct 2.65% more: each event is placed twice instead of
  shifted once. PCM is identical.
