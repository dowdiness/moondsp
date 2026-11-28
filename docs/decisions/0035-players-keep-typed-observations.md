# ADR-0035: The scheduler reports observations, the player keeps them typed, the browser encodes them

- **Status:** Accepted
- **Date:** 2026-11-28
- **Resolves:** the last open item of [ADR-0030](0030-players-accept-scores.md)
  ("`onsets()` and `signals()` still return the scheduler's ring types")
- **Related:** issue #295, [ADR-0029](0029-platform-free-player.md),
  [ADR-0018](0018-playback-visualization-origin-truth.md)

## Context

`Player::onsets()` and `signals()` returned the scheduler's `OnsetBuffer` and
`SignalBuffer`. Both were rings of flat `Double` rows shaped for the
AudioWorklet's JavaScript reader: a missing frame was serial 0 with start -1,
a drum hit's pitch was NaN, binding paths were written as serial triples up to
32 links, and ids a JavaScript number cannot hold exactly were dropped while
recording. The ring capacity, 256, was the browser's shared ring capacity.
These were the only reason the player's interface imported the scheduler,
and an offline renderer reading what played got the browser's wire format.

## Decision

1. **The scheduler reports what happens.** It defines the open trait
   `PlaybackObserver`: `onset(sample, EventWithOrigin)` for a tracked event it
   dispatches, `signal(sample, SourceAtomId, material, value)` for what voices
   following an authored signal read at a block start (once per signal and
   material time), and `signal_lost()` when it cannot observe a followed
   signal (it follows at most 64 at once). A host attaches one observer with
   `attach_observer`, which preallocates the follower storage, and turns each
   kind on with `observe_onsets` / `observe_signals`. The scheduler keeps no
   observation storage or wire rule.
2. **The player keeps typed observations.** `Player::onsets()` returns
   `Onsets` (`count`, `sample(i)`, `source(i)`, `dropped`, `clear`) and
   `Player::signals()` returns `SignalValues` (`count`, `sample`, `signal`,
   `material`, `value`, `dropped`, `clear`), each keeping the newest 256 in
   storage allocated with the player. `Player::observe_onsets` /
   `observe_signals` turn recording on. The player's interface no longer
   mentions the scheduler.
3. **The browser host encodes.** `player_onset_count` / `player_signal_count`
   encode the recorded observations into preallocated rows, leaving out those
   the wire cannot carry and counting them in `player_*_dropped`. The browser
   ABI, the row layout and the JavaScript readers are unchanged. Encoding
   reads the event origin's atom, frame, start, binding path and sound, so the
   host imports `pattern`; the boundary rule for `playback_host` allows it.

## Consequences

- Everything a renderer observes is a typed value: the dispatched event with
  its origin, frame, start and sound, and the signal's source atom.
- Recording allocates nothing: rings and follower storage are preallocated,
  and a ring slot holds a reference to the event the scheduler already has.
  The render-path allocation audit is unchanged.
- A followed signal whose id is not wire-safe is now reported and left out at
  encoding, once per block, where it used to be dropped once when the voice
  started following it. Such ids exceed 2^53 and do not occur in practice.

## Rejected alternatives

- **Typed rings in the scheduler, wrapped by the player.** Keeps the ring
  policy (capacity, overwrite) in the scheduler and adds a forwarding layer.
- **Encode per field read, statelessly.** Rows the wire cannot carry would
  vanish from the drop count, and binding fields would walk the path per read.
