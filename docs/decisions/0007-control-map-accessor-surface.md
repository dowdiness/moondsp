# ADR-0007: ControlMap keeps a map-backed accessor surface

- **Status:** Accepted
- **Date:** 2026-05-11
- **Source:** [PR #29](https://github.com/dowdiness/moondsp/pull/29) design discussion and implementation

## Context

`ControlMap` is the bridge value between the pattern layer and the scheduler.
It currently represents numeric controls as a `Map[String, Double]`, which
matches the mini-notation parser and graph control binding model.

The long-form song work raised the question of whether to turn `ControlMap`
into a typed record with timing and expression fields immediately. Doing that
in the same change as the section scaffold would couple two decisions:

- adding a structural song layer
- changing the payload contract used by existing patterns, the scheduler, and
  browser drum routing

Existing code also reached through the tuple field directly (`map.0`), making
future representation changes harder.

## Decision

Keep `ControlMap` map-backed for this PR and add a small public accessor API:

- `ControlMap::empty()`
- `ControlMap::single(key, value)`
- `ControlMap::get(key)`
- `ControlMap::each(f)`
- `ControlMap::entries()`
- `ControlMap::set(key, value)`
- `ControlMap::merge(other)`

Schedulers and pattern helpers should use these methods instead of reaching
through the tuple field. Timing and expression controls are not added as typed
fields in this decision; they remain deferred until the scheduler has concrete
groove/rubato semantics to preserve.

## Consequences

**Positive**

- Existing `Pat[ControlMap]` code keeps its observable behavior.
- The map representation remains compatible with mini-notation, control
  binding, and the browser routing path.
- A public accessor surface gives future refactors a stable migration point if
  `ControlMap` later becomes a record, tagged map, or richer payload type.
- Immutable-style `set` and `merge` helpers make pattern composition avoid
  mutating event values that callers may reuse.

**Negative**

- `ControlMap` remains stringly typed; misspelled control names still cannot be
  caught by the compiler.
- `set`, `merge`, and `entries` copy maps. That is acceptable for authoring and
  pattern-event payloads now, but audio-thread code must continue to lower
  events into preallocated scheduler/voice structures.
- The tuple constructor remains visible through the public type, so the
  accessor discipline is conventional rather than fully enforced.

**Deferred**

- Typed timing and expression fields such as velocity, articulation, groove
  role, or nudge are intentionally left for a later PR that implements the
  corresponding scheduler behavior.
