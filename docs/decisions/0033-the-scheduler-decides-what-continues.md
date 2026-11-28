# ADR-0033: The scheduler decides whether a song can replace the playing one

- **Status:** Accepted
- **Date:** 2026-11-28
- **Refines:** [ADR-0030](0030-players-accept-scores.md) (what `update` refuses)
- **Related:** issue #294, [ADR-0032](0032-mini-song-identities-are-their-names.md)

## Context

`Player::update` refused a Playing or Paused update whose *layout* differed,
with `RestartRequired`. It decided this by copying each occurrence's id,
name, section name, start, length and rate into a `PlaybackLayout` and
comparing two of them. The rule came from #237, whose scope note says song
layout changes "still require Stop then Play".

The scheduler has since defined how every material edit plays (pending
entries, moved occurrences, skipped occurrences), so the rule needed a
reason, not a history. A probe of `PlaybackState` (2026-11-28) played each
kind of edit mid-performance against the same edit after a restart:

| Edit while playing | Plays |
|---|---|
| repetition length 4 → 3 or 4 → 6 | the new song, aligned to the new repetition grid |
| repeat off → on, during the first pass | the first pass, then repetitions |
| repeat on → off, during a later repetition | silence |
| a finite song's end 8 → 12 | the old content to its old end |
| pattern → song | silence |
| song → pattern | both, until the song's occurrence ends |

The silences come from one documented rule: a finite occurrence never joins
midway (technical reference, playback reconciliation). Accepting an edit that
replaces started occurrences leaves them silent for the rest of the Play.

Song layout revisions cannot stand for "same layout": Mini lowers a fresh
`SongDoc` for every compile (ADR-0032), so its revisions start alike.

## Decision

1. **Refusing an update is the scheduler's call, made in `accept_playback`.**
   When `restart` is false and the snapshot is arranged differently from the
   latest accepted one, `accept_playback` returns `ArrangementChanged` before
   it retimes anything; the player maps it to `RestartRequired`.
2. **An arrangement is where occurrences play**: a song's occurrence ids with
   their start and end, and its repetition length (none when it does not
   repeat). Two patterns always continue; a pattern and a song never do.
   The scheduler records the arrangement once, when it builds the snapshot.
3. **Names, rates and content are not arrangement.** Renaming a section, or
   the display name of a part with a `part_id`, continues. A content edit of
   a started occurrence continues and waits for the next Play, counted as
   skipped, as before. A part without `part_id` is identified by its name, so
   renaming it places another occurrence.

## Considered options

- **Let a started occurrence join at its next entry**, which would remove
  `RestartRequired`. It contradicts the reconciliation rule and is a musical
  decision, not a refactor.
- **Restart automatically** on an arrangement change: it rewinds the
  transport without being asked.
- **Accept and report skipped materials**: the probe shows silence, which a
  count does not explain.
- **Refuse only when the repetition offset changes**: the probe shows no
  misalignment in those cases, and silence in cases this would accept.

## Consequences

- `PlaybackLayout`, `PlaybackLayoutRow` and `Score`'s layout are deleted;
  `Player::mode` reads the score's span.
- `PlaybackSnapshot::revision` and `song_layout_revision`, and
  `PlaybackPattern::revision`, which only tests read, are deleted.
- Status code `2` keeps its meaning, for fewer edits.
- [Issue #306] The scheduler also owns how long the accepted song plays:
  `check_fits` (a repetition lasts a block, a finite end is representable),
  `accept_playback` and `set_tempo` check the snapshot's own finite end, and
  `song_end` reports reaching it. The player's `Score.span` and the `end_?`
  arguments are gone.
