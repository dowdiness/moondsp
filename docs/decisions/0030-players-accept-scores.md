# ADR-0030: Players accept scores, from text or from content

- **Status:** Accepted
- **Date:** 2026-11-27
- **Refines:** [ADR-0029](0029-platform-free-player.md) Decision 1 (the
  `Player` interface)

## Context

ADR-0029 moved the player below the browser host with the interface the host
had: `update` and `restart` took a `@mini.PlaybackInput`, so preparing a score
and accepting it were one step, and only Mini text could be played. Playing
content with no source text is a requirement. `process()` rendered into the
player's own buffers, which `left()` and `right()` exposed for writing, and a
failure was told three ways: a `Bool`, `fault()`, and the raised
`PlayerError`. `view()` built a `PlayerView` on every status read, and
`Failed` meant both "the player is in Fault" and "the song's end is out of
range".

## Decision

1. **A `Score` is the value a player accepts.** It holds the lowered
   material, its tempo, its layout and how long it plays. `Score::pattern` and
   `song` build one from content with no player (ADR-0031); `Player::compile` builds one from Mini input, because the work
   Mini admits depends on the player's query window, and records that
   window in the score. A player in Fault compiles nothing.
2. **The player checks its own limits when it accepts.** `update` and
   `restart` check that a repeated song spans a block, the material budget,
   and a finite end the transport can reach, as before. They also refuse a
   compiled score whose admitted window is shorter than this player's, so a
   score compiled for shorter blocks cannot overrun a player with longer
   ones.
3. **Content scores carry no workload bound.** Mini's admission is a static
   check of source text; arbitrary `Pat` content has none to check. The
   caller answers for its work, as it already does when it hands the
   scheduler a snapshot.
4. **`process(left, right)` renders into the caller's buffers** and returns
   `PlayerError?`, as `engine/lifecycle`'s `Engine::process` does: `None`
   constructs nothing, so the audio thread allocates no more than before.
   Buffers that do not hold one block are refused.
5. **Status is read through accessors** (`state`, `mode`, `bpm`,
   `cycle_position`, `sample_position`, `pending_materials`,
   `skipped_materials`), not a constructed view. `mode` is a `ScoreKind?`;
   the browser maps it to its constant-enum ABI. The player keeps no source
   text: the editor owns the accepted source.
6. **`Sounds` is one value** for the drum graphs, instrument voices and
   sampler a player uses, so two adapters can share it.
7. **Error types follow the call that catches them.** Each names one cause
   per variant, and `message()` on each is the one place that turns it into
   the text the browser shows.
   - `ScoreError`, from `compile` and the song constructors: Mini's refusal,
     pattern or song lowering, an empty song, and the score's tempo.
   - `TempoOutOfRange`, from `Tempo(bpm)`, the player's own tempo type,
     which every constructor and `set_tempo` take; `ScoreError::Tempo` wraps it for a
     source's tempo, a genuine subset. Pattern constructors cannot fail.
   - `UnsupportedFormat`, from `Player(ctx, sounds)` only.
   - `PlayerError`, from accepting, Play, Pause, tempo changes and
     rendering: the player's limits, layout, state, and buffers. Fault
     carries a `FaultReason`, a plain enum: it is the state's data, and no
     call fails with it alone.
   Only Mini's refusal and a song's lowering failure, whose errors are of
   several types, are strings.
8. **Whether a score fits a tempo is one check**, used when a score is
   accepted and when the tempo changes. Songs enter as lowered
   `SongSnapshot`s, like patterns.

## Considered options

- **`prepare`, `admit` or `load` for `Player::compile`.** `compile` names what
  it does to the input, and matches `@mini.PlaybackInput::compile`, which it
  calls. `admit` names only the work check, and `load` suggests acceptance.
- **A `Score` built only by the player.** It would keep text-less content
  behind the player and its limits; content needs no player to exist.

## Consequences

- The browser ABI is unchanged. The host owns the output buffers it reads
  samples from. Its commands compile, then accept, with the same codes and,
  with two exceptions below, the same diagnostics.
- Updating to a finite song whose end the transport cannot reach now reports
  "song end exceeds transport range"; it used to say "tempo change exceeds
  transport range".
- `compile` no longer looks at the player's state. A player in Fault given
  invalid input reports the input's problem, not the Fault; accepting still
  raises `Faulted`.
- `scripts/audit-player-source-allocations.mjs` counts the same executed
  constructions, onset rows and fields, and PCM as before for tracked and
  untracked patterns and songs.
- When a score fails both the repeat-span check and song lowering, lowering's
  error is now the one reported, because the span check moved to acceptance.
- The session tests call `Player` directly and assert the states and errors
  it raises.
- `onsets()` and `signals()` still return the scheduler's ring types.
