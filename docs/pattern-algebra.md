# Pattern algebra design note

This note records the intended algebra for `Pat[A]` before adding more
pattern-combinator APIs or mini-notation sugar. It is a design contract for
future work, not a claim that every candidate operation already exists.

## Current model

`Pat[A]` is a query function from a `TimeSpan` to an array of `Event[A]`.
Combinators transform either:

- **time** — `fast`, `slow`, `rev`, `sequence`, Euclidean distribution, and
  degradation change where events appear;
- **values** — `filter_map` changes or drops event payloads while preserving
  event timing; or
- **layers** — `stack` overlays independent patterns without merging payloads.

Keeping these axes separate matters. Overlaying two patterns is not the same
operation as combining two simultaneous event values.

## Overlay / stack

`stack(Array[Pat[A]]) -> Pat[A]` is the core overlay operation for patterns of
the same payload type.

Semantics:

- querying `stack([p, q])` queries both `p` and `q` over the same arc and
  concatenates their events;
- event `whole`, `part`, and `value` are preserved exactly from each child;
- `stack([])` is `Pat::silence()`;
- `stack([p])` should behave like `p`;
- nested stacks are expected to be semantically associative modulo event array
  ordering.

Therefore `Pat::silence()` is the identity for overlay, and `stack([...])` is
the array form of a Monoid-like `overlay` over `Pat[A]`:

```text
overlay(p, q) = stack([p, q])
stack([p0, p1, ...]) = fold(overlay, Pat::silence(), ...)
```

Do not overload overlay to merge payloads. For `Pat[ControlMap]`, overlay means
multiple events may occur at the same time; it does not mean their control maps
are combined into one event.

### Mini-notation consequences

Future mini sugar such as `p + q` or implicit top-level newline overlay should
lower to the same overlay algebra as `stack(p, q)` and `$:` lines. The operator
should not be numeric addition, and it should not perform `ControlMap` merging.

`$:` should remain the explicit top-level stack-line syntax even if other sugar
is added.

## Value mapping

A Functor-like mapping operation is the safest next API family because it does
not invent new time semantics.

Candidate public shape:

```moonbit nocheck
pub fn[A, B] Pat::map(self : Pat[A], f : (A) -> B) -> Pat[B]
```

Semantics:

- query the input pattern over the same arc;
- preserve each event's `whole` and `part` spans;
- replace only `value` with `f(value)`;
- do not drop events.

`filter_map` already implements the value-transform-plus-drop variant. If
`map` is added, `filter_map` should remain the explicit operation for changing
event cardinality.

Prefer method form first (`pat.map(f)`) because existing `Pat` transformations
are method-heavy. A free function can be added later only if it improves
composition with external DSLs.

## Applicative-like candidates

`Pat::pure(value)` exists, but that alone does not define an Applicative API.
Operations such as `zip_with`, `lift2`, or `ap` combine events from two
patterns, and that requires a precise time rule.

Candidate names should stay reserved until their semantics are proven:

```moonbit nocheck
pub fn[A, B, C] zip_with(Pat[A], Pat[B], (A, B) -> C) -> Pat[C]
pub fn[A, B] ap(Pat[(A) -> B], Pat[A]) -> Pat[B]
pub fn[A, B, C] lift2((A, B) -> C, Pat[A], Pat[B]) -> Pat[C]
```

Open semantic choices:

1. **same onset** — combine only events whose `part.begin` is equal;
2. **arc intersection** — combine events whose `part` spans overlap, with the
   output event span equal to the intersection;
3. **left-shaped overlap** — keep the left event's span and fold all overlapping
   right values into it;
4. **cartesian within query arc** — combine every pair returned by the query,
   regardless of overlap.

These choices are not interchangeable. They produce different event counts,
different spans, and different scheduler behavior. Until a use case selects one
rule, do not expose a generic Applicative-like API.

## `ControlMap` merging is a special operation

`merge_control(a, b)` is specific to `Pat[ControlMap]`. It keeps events from
`a`, finds overlapping events from `b`, and merges right-hand controls into the
left event's `ControlMap`.

That is intentionally not generic overlay:

- `stack([a, b])` preserves both events as separate layers;
- `merge_control(a, b)` shapes `a` with overlapping controls from `b`;
- key conflicts use `ControlMap::merge`, so right-hand controls override
  matching keys.

This operation is useful for controls such as `.gain`, `.cutoff`, `.pan`, and
`.jux`, but it should not be treated as the default Applicative semantics for
all `Pat[A]`.

## Placement rules

- `pattern/` owns algebraic operations over `Pat[A]`, `Pat[ControlMap]`, and
  `ControlMap`.
- `mini/` owns syntax sugar that lowers into existing `pattern/` operations.
- New mini syntax must not introduce semantics that cannot be named and tested
  in `pattern/`.

## Recommended follow-ups

1. Add `Pat::map` as the first value-only mapping API, with tests that event
   timing is preserved.
2. Add mini `+` overlay sugar by lowering to `stack`, not to numeric addition
   or `merge_control` (tracked by #217).
3. Add implicit top-level newline overlay only after it is specified as the
   same overlay operation as `stack` and `$:` lines (tracked by #219).
4. Defer `zip_with`, `lift2`, and `ap` until one time-combination rule is chosen
   and documented with examples.
