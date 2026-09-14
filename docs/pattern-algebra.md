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
- `stack([p])` returns `p`;
- raw anonymous nested stacks normalize to one ordered overlay;
- regrouping preserves event array order and duplicates, not just event sets.

Therefore `Pat::silence()` is the identity for ordered overlay. Native MoonBit
`p + q` uses `Add for Pat[A]` and delegates to the same constructor:

```text
overlay(p, q) = stack([p, q])
stack([p0, p1, ...]) = fold(overlay, Pat::silence(), ...)
```

Do not overload overlay to merge payloads. For `Pat[ControlMap]`, overlay means
multiple events may occur at the same time; it does not mean their control maps
are combined into one event.

Normalization only traverses raw overlays. A transformed query is not rebuilt
from its playback entries: for example, reversing an overlay can produce a
different cross-cycle event order from overlaying individually reversed entries.
Named scopes retain their address boundary; `.material()` explicitly groups
an expression into one playback material. Naming alone does not group clocks.

### Content, playback identity, and source ancestry

These are separate contracts:

- Known content compares equally after raw overlay regrouping, including after
  `.material()` and known transforms. Content normalization traverses raw overlays
  independently of named/material boundaries, removes silence, and reduces a
  single remaining operand to its own content identity. Playback boundaries and
  silent placeholders remain intact. Opaque queries stay atomic; arbitrary
  queries and callbacks remain unknown and cannot suppress a live replacement.
- Playback occurrence keys exclude raw overlay ancestry. Document references
  own their member slots independently of their definition's content IDs.
  Anonymous silence has no playback entry; explicitly named/material silence
  retains a placeholder for playback transitions.
- `PatternDoc` retains the authored source tree. `PatternSnapshot::entry_key`
  identifies the playback occurrence; sourced queries still report its source
  ancestry. Regrouping unchanged known content preserves the material clock
  while publishing the latest source view.

### Mini-notation consequences

Mini `p + q`, `stack(p, q)`, and `$:` lines lower to the same ordered overlay.
The operator is neither numeric addition nor `ControlMap` merging. Method
chains bind more tightly than `+`; `(p + q).rev()` transforms the whole group.
Parentheses do not add a source node.

`$:` remains the explicit top-level stack-line syntax. Ordinary newlines are
whitespace, not an implicit overlay.

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
2. Add implicit top-level newline overlay only after it is specified as the
   same overlay operation as `stack` and `$:` lines (tracked by #219).
3. Defer `zip_with`, `lift2`, and `ap` until one time-combination rule is chosen
   and documented with examples.
