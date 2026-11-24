# ADR-0025: One-shot signals start where their material enters

- **Status:** Accepted 2026-11-24
- **Date:** 2026-11-24
- **Source:** [Amp thread T-01a20b2e](https://ampcode.com/threads/T-01a20b2e-880d-7665-89be-6641f7c6a852)
- **Refines:** [ADR-0024](0024-time-maps-defined-once.md) Decision 3 (live
  edits switch at a material's entry period) and
  [ADR-0019](0019-automatic-control-buses.md) (buses are compiled once per
  snapshot).
- **Related:** [mini notation](../mini-notation.md), `CONTEXT.md`
  (playback origin)

## Context

`ramp`, `.fadeIn(n)`, and `.fadeOut(n)` run once and then keep their end
value. They read the material's local time, which starts at the material's
origin: the start of playback, or of a song section.

A live edit keeps the origin when the replacement has the same start and
period (`replacement_origin`), so that the cycle count goes on: `every`,
alternation, and slowed sequence steps continue where they were
(`entries_wbtest.mbt`, "content edits preserve the cycle count used by
variation"). So adding `.fadeOut(4)` after eight cycles read the ramp at
local time 8 or later: the pattern went silent at once, and `.fadeIn(8)`
did nothing. A fade written live has to start where the edit enters.

## Decision

### 1. One-shot signals are their own signal kind

`BusSignal::Once(f, delay)` reads `f(t − delay)`; `Continuous(f)` reads
`f(t)`. `PatternDoc::once` builds one, and mini notation lowers `ramp`, and
so `fadeIn` and `fadeOut`, to it. Periodic signals stay `Continuous`.

### 2. Entering delays only the one-shot signals

When unbounded material enters at a boundary `due` (a live edit's
replacement, or a layer added while playing), playback keeps the origin and
calls `EntrySpec::entered(due − origin)`. That compiles a snapshot whose
buses have each `Once` delayed by the entry (`BusSignal::delayed`), and
re-projects the onset values from them (`PatternSnapshot::entered`). The
rhythm, the cycle count, and the periodic signals are unchanged.

The delay is a whole number of the material's periods, because `due` is an
entry boundary. A time map passes it to its children: `Affine` scales it,
and a cycle map (`rev`, slots) keeps it. Periods make that exact: a cycle
map repeats after whole cycles (ADR-0024 Decision 3), so shifting its input
by a multiple of its period shifts its output the same.

Resubmitting unchanged material keeps its running delay. The comparison
(`same_content`) needs content signatures, so `PatternDoc::continuous` and
`PatternDoc::once` require a `signature`, which mini notation fills from the
signal's shape, range, and rate. Before, a signal had no content signature,
so a material with a signal never counted as unchanged and was replaced at
its next boundary, which would now restart its fade.

### 3. Songs keep section-local time

A song occurrence starts its one-shot signals at the section's start, as
before: a section is the authored unit of a fade. `entered` leaves song
entries unchanged.

## Alternatives considered

1. **Restart the origin at the edit's boundary.** Simplest, and the
   replacement's own rhythm would keep its phase, but the cycle count restarts:
   `every`, alternation, and slowed steps would jump to their cycle-zero
   variation at every edit.
2. **A second offset on `Placement`, for one-shot signals only.** No
   recompilation per edit, but every event and every bus read would carry a
   value that only fades use, and the offset would need to survive each
   `then` composition with a different rule from the origin.
3. **`once` as a pattern transform** (an earlier proposal). Rejected by the
   user in favor of signals.

## Consequences

- A fade added or changed by a live edit starts where the edit enters. A
  material whose text did not change keeps its fade where it is.
- Accepting an edit recompiles the buses and onset projection of each
  delayed material once. In the browser this runs in the AudioWorklet, in
  the same update command that already parses and lowers the edit and so
  already allocates there (`player_update_input`, `accept_playback`). A
  snapshot queued through `queue_playback_snapshot` is reconciled, and so
  recompiled, at the next `render_block`, where reconciliation already
  allocated. Settling entries at later blocks does not call it, and reading
  a bus stays allocation-free: `Once` evaluates like `Continuous`.
- A ramp under `every(n, …)` with a delay that is not a multiple of `n`
  selects branches by the unchanged cycle count, as the events do.
