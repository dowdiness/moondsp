# ADR-0029: The player is platform-free, below the browser host

- **Status:** Accepted. Its `Player` interface is refined by
  [ADR-0030](0030-players-accept-scores.md).
- **Date:** 2026-11-25
- **Refines:** [ADR-0015](0015-graph-internal-boundaries-and-maintainability.md)
  (browser shape: `browser/internal/playback_host`)

## Context

Offline rendering and WAV export are planned. Everything that performs a score
lived in `browser/internal/playback_host`: preparing a `@mini.PlaybackInput`,
accepting it, the Empty/Ready/Playing/Paused/Ended/Fault session, finite-song
endings, tempo and gain changes, the shared reverb, and the voice pools of every
drum, instrument and sample. The same package held the browser's globals,
UTF-16 wire buffer, diagnostic strings and sample loading. An offline renderer
could not use any of it: other packages may not import `browser/internal/*`, and
the session logic was written against those globals.

## Decision

1. A top-level package `player` holds the performance of one score. `Player`
   prepares and accepts input, owns the session, renders blocks into its
   `left()` and `right()` buffers, and changes tempo and gain. Its sound set
   (`NoteVoice`, `SamplerVoice`, a drum `AnalyzedGraph` per drum) is passed in,
   so every adapter can make the same sound.
2. `player` knows no platform. It may import the root facade, `identity`,
   `mini`, `pattern`, `scheduler`, `score` and `song`
   (`scripts/check-architecture-boundaries.sh`).
3. `browser/internal/playback_host` is the browser's adapter: the global
   player, the exported functions, wire decoding, diagnostic strings, and
   sample loading into the store it gives the player's `DspContext`.
4. Two adapters make this a real seam: the AudioWorklet host, and offline
   rendering, which drives `process()` until the song is Ended. A test in
   `player` renders a finite song that way.

## Consequences

- Behaviour and the browser ABI are unchanged. The session tests (Play,
  Pause, Ended, updates, tempo, admission) moved to `player`, where they read
  the scheduler's own clock and tempo and submit untracked text as the host's
  wire does; so did the tests of reverb returns, active notes, song snapshot
  preparation, and the sampler pool's bindings and shaping. The host keeps
  tests of its exports: owner reset, UTF-16 diagnostics, wire witnesses, and
  that a score is silent until its sample's load commits.
- The render path is unchanged: `scripts/audit-player-source-allocations.mjs`
  counts the same executed constructions, onset rows and fields, and PCM as
  before for tracked and untracked patterns and songs. `process()` returns a
  `Bool` and `fault()` gives the reason, because a `Result` cost one
  construction per block.
- The drum sound crosses as an `AnalyzedGraph`, the runtime exchange type of
  ADR-0010, not as an `Array[DspNode]`.
- `Player` still accepts only a Mini `PlaybackInput`. Playing content with no
  source text, also a requirement, arrives with the scheduler's playback
  snapshot redesign.
- The browser's built-in sounds stay in `browser/internal/demo_templates`; an
  offline renderer that must sound the same needs them below the browser too.
