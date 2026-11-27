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

1. **Only pattern snapshots are played.** An untracked song's sections hold
   `UntrackedPatternSnapshot`s, as Mini already lowered them, not the bare
   `Pat` it used to keep; `SongContent` is implemented for the two snapshot
   types only. Every played pattern therefore has a revision, node paths,
   and the entered-delay behavior of ADR-0025.
2. **`@pattern.PlaybackPattern[A]` is what playback plays of a snapshot.**
   `UntrackedPatternSnapshot::playback` and `TrackedPatternSnapshot::playback`
   build one. Its `query_for_entry(index, arc, at~, within?, each)` places
   each event on the playback clock itself (content time by `within`, a song
   section's placement, then by `at`) and hands it to `each` with its node
   path and, for tracked material, its event origin: the dispatch lives once,
   in `pattern`. The snapshots stay two static types (ADR-0028 Decision 1).
3. **`SongContent` gains `playback()`**, and `SongEntry` exposes `content`,
   `content_entry` and `placement`, so the scheduler builds each entry's
   view and placement once. `SongSlice`, `SongEntry::slice` and
   `SongSnapshot::slices`, which only the scheduler read, are removed.
4. **`@scheduler.PlaybackSnapshot` is an opaque value built once**: its
   revisions, its repetition period and its entry specs. It has two
   constructors, `pattern(PlaybackPattern)` and
   `song(SongSnapshot[C : SongContent], repeat?)`. `SongMaterial`, the enum
   variants, `raw`/`from_raw`, `queue_pattern_snapshot` and
   `queue_song_snapshot` are gone; callers use `queue_playback_snapshot`.
5. **`@player.Score` has two constructors**, `pattern` and `song`, for the
   same reason.

## Considered options

- **Keep the four constructors and make only the internals one struct.**
  No allocation change, but the public interface keeps naming the kinds,
  which is what #292 is about.
- **A per-event struct returned by `PlaybackPattern`.** One more
  construction per event.
- **A plain `Pat` as a playable kind.** It has no revision and no node
  paths, and entering cannot delay its one-shot signals, so playing it
  directly would differ from playing its snapshot; a snapshot already
  exists for every played pattern.
- **Mapping with a per-query lambda.** One closure per entry query (+0.61%
  for patterns): the mapper is a named function for patterns and one closure
  per song entry, and the query's placement is an argument.

## Consequences

- Adding a kind of pattern means one `PlaybackPattern` constructor; the
  scheduler, the player and the browser host do not change.
- `query_for_entry` takes the query's `Placement` and a mapper built once
  per entry, so a query constructs no closure. Patterns construct as many
  objects as before; tracked songs 1.96% fewer, since their view and
  placement are built once. Untracked songs, which no production input sends
  (#296), construct 3.20% more, the same count as tracked songs: their
  snapshot sections build events with node paths and place them twice,
  where main shifted a bare `Pat` once. PCM is identical.
