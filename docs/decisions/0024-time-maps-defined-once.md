# ADR-0024: Each time transform is defined once, for events and signals

- **Status:** Proposed 2026-11-24.
- **Date:** 2026-11-24
- **Source:** [Amp thread T-01a20b2e](https://ampcode.com/threads/T-01a20b2e-880d-7665-89be-6641f7c6a852)
  and its plan "計画：時間変換を1か所で定義する".
- **Refines:** [ADR-0019](0019-automatic-control-buses.md) Decision 3 (buses
  wrap every enclosing time transform) and
  [ADR-0020](0020-controls-as-signals.md) Decision 2 (the bus table stays
  beside the pattern).
- **Related:** [pattern algebra](../pattern-algebra.md),
  [mini notation](../mini-notation.md)

## Context

A pattern answers two questions about time. A query asks which events fall in
an arc (`Pat::query`, rational spans). A bus asks a control's value at one
instant while a voice sounds (`BusSignal::eval`, an exact `num / den`, with no
allocation on the audio thread). Both must agree: a voice reads at its onset
the same value the event carries.

Every time transform is written once for each question, and placement is
written a third time:

| Transform | Events | Signals | Placement |
|---|---|---|---|
| fast / slow | `Pat::fast`, `Pat::slow` | `Fast` | `Placement.rate` |
| shift | `Event::shift` | `Shift` | `Placement.origin` |
| rev | `Pat::rev` | `Rev` | — |
| sequence | `sequence` | `Sequence` | — |
| weighted sequence | `sequence_weighted` | `Weighted` | — |
| Euclid | `Pat::euclid` (via `sequence`) | `euclid_slots` (via `Sequence`) | — |

Document lowering then pairs them by hand at each node
(`.transform(pat => …)` beside `.map_buses(signal => …)`), and `every`/`jux`
callbacks pair `TimeTransform::apply` with `BusSignal::transformed`.

Two copies drift, and here both copies drifted the same way:

- `rev` mapped time `t` in cycle `c` to `c + 1 − t` in both copies, so every
  cycle read the child's cycle 0. A pattern longer than one cycle replayed
  its first cycle, and `fadeOut(4).rev()` stopped moving. Fixed in
  `34256c6` by editing both copies.
- `sequence` and `sequence_weighted` show each slot's child only its cycle 0,
  in both copies. `note("60 [64 67]/2")` plays 60 64 in every cycle and never
  67, although `/2` is documented as "stretch 2× slower".

Tests checked only one-cycle patterns and period-one signals. The property
test `rev().rev() == id` holds with either bug.

## Decision

### 1. A time transform is a piecewise affine map

Each transform listed above divides outer time into pieces and, on each
piece, maps outer time `t` to child time `a·t + b` with `a ≠ 0`:

| Transform | Pieces | a | b (cycle c, slot i) |
|---|---|---|---|
| fast(k) / slow(k) | one | k / 1/k | 0 |
| shift(o) | one | 1 | −o |
| placement(origin, rate) | one | rate | −origin·rate |
| rev | each cycle | −1 | 2c + 1 |
| sequence(n) | each slot of each cycle | n | c − n·c − i |
| weighted (bounds) | each weighted slot | total / weight | same rule |
| Euclid(k, n, r) | sequence(n); rest slots have no child | n | as sequence |

`pattern/time_map.mbt` holds these coefficients in one private type,
`TimeMap` (`Affine`, `MirrorCycles`, `Slots`). It is the only place the
formulas are written. It answers both questions from them:

- `pieces(arc)` splits a query arc into pieces with their child index, `a`,
  `b`, and outer span. `Pat::mapped(map, children)` queries each child over
  its mapped span and maps events back, swapping span ends when `a < 0`.
- `slot_at(num, den, left)`, `scale(slot)`, and `offset(cycle, slot)` locate
  one instant. `BusSignal::Mapped(map, children)` evaluates the child at the
  mapped instant, flipping `left` when `a < 0` (the half-open boundary rule
  that `Rev` uses today).

They return scalars, not a pair or a struct. A probe with moon
0.1.20261117 found that a `#valtype` two-field struct returns by value on
native but allocates on wasm-gc (`struct.new`) and JS (`new`), like a plain
struct; ADR-0020 found the same for `Option`.

`Pat::fast`, `slow`, `rev`, `sequence`, `sequence_weighted`, `euclid`,
`Event::placed`, and `Controls::place` construct a `TimeMap` and delegate.
Document lowering builds one `TimeMap` per node and gives the same value to
the pattern and to its buses. `TimeTransform` names a map;
`TimeTransform::apply` and `BusSignal::transformed` both use it. The public
signatures of these functions do not change.

### 2. A sequence slot keeps the cycle number

A slot in cycle `c` shows its child the child's cycle `c` (b = c − n·c − i).
`note("60 [64 67]/2")` plays 60 64 in even cycles and 60 67 in odd ones,
which is what `/2` documents. This is the meaning of Tidal's and Strudel's
`fastcat`/`timecat`: Strudel's `slowcat` shifts each child so that "cycles
from constituent patterns aren't skipped", and `fastcat` is `slowcat`
sped up. The comment in `sequence` that every slot maps to `[0, 1)`
"independent of its index and cycle" is replaced.

Euclid keeps its documented meaning: each hit plays the child compressed
into the hit's step. With this decision a hit in cycle `c` plays the child's
cycle `c`.

### 3. A pattern's entry period follows its map

Live edits switch at a material's entry period (`next_unbounded_entry`,
`replacement_origin`), so the period must be a length after which the
material repeats. `TimeMap::period(child_periods)` states it once:

- `Affine`: `p / a`, the existing rule for fast and slow.
- `MirrorCycles`: `lcm(p, 1)`.
- `Slots`: `lcm(1, p₀, p₁, …)`, now that slots keep their child's cycle.

`stack` uses the same `lcm` of its members instead of its fixed 1, which
matters where a stack sits inside a material (`.material()`, or under a
transform). Raw top-level stacks still split into one entry per member.
`lcm` of reduced rationals is `lcm(numerators) / gcd(denominators)`. `every`
keeps its child's period; its own period is a separate question.

### 4. Not time maps

These change which events exist or which subtree answers, not how time maps,
and keep their own code: `gate` (shortens events), `degradeBy` (drops them),
`every` (selects a subtree by cycle number, already in absolute cycles),
`stack`, control merging, and `filter_map`/`jux` payload changes.
`PatternDoc` node kinds do not change.

## Alternatives considered

1. **Read controls by a zero-width pattern query** (Tidal, Strudel). Removes
   `BusSignal` and leaves one implementation. Rejected: a query allocates
   arrays and closures, and a sounding voice reads its controls on the audio
   thread.
2. **A small set of primitives that everything composes from** (Strudel:
   `sequence = slowcat + fast`, `timecat` = a stack of `compress`). Fewer
   primitives, but each is still written once for events and once for
   signals. Its `slowcat` offset is adopted as the meaning of Decision 2.
3. **`BusSignal` as the only definition, with queries derived from it.** A
   signal maps one instant; a query also needs to split an arc and map events
   back, which a point map does not provide.
4. **One lowered time tree interpreted by both queries and signals.** One
   definition, but it replaces event queries wholesale, which is larger than
   the problem. Sharing one `TimeMap` value at lowering gives the same
   guarantee.
5. **Return a `#valtype` struct from the instant lookup.** Allocates on
   wasm-gc and JS (Decision 1).

## Consequences

- A transform's formula exists once. A wrong coefficient is wrong for events
  and signals alike, so the onset agreement between them holds by
  construction, and one property test covers both.
- Behavior changes: sequences, weighted sequences, and Euclid hits keep the
  cycle number (Decision 2); periods of sequences and stacks become `lcm`s
  (Decision 3). One-cycle patterns sound the same.
- `BusSignal` loses `Fast`, `Shift`, `Rev`, `Sequence`, and `Weighted`, and
  lowering loses its paired `.transform`/`.map_buses` code.
- `rev`'s `b = 2c + 1` and a slot's `b = c − n·c − i` grow with the cycle
  number; long sessions must stay within `Int64` like other exact times.

## Migration order

Each step lands on its own and keeps the tests green, except where noted.

1. This ADR.
2. Property tests against an independently written reference map for each
   transform and random trees of them, at cycles 0, ≥ 1, negative times, and
   exact piece boundaries: a leaf event's value is its local onset; a leaf
   signal is `f(t) = t`; each event's onset value equals the signal there.
   Sequence cases fail until step 6 and are marked as such.
3. `TimeMap` reproducing current behavior (sequence slots still at cycle 0).
4. Events through `Pat::mapped`. Refactor only; existing tests unchanged.
5. Signals through `BusSignal::Mapped`, placement through `TimeMap::Affine`,
   lowering through one map per node. Refactor only.
6. Decisions 2 and 3: change the slot offset and the period rule; update
   docs, CHANGELOG, and expectations. The sequence property cases pass.
7. Benchmarks (`time_benchmark`, `path_allocation_benchmark`,
   `jux_benchmark`) before and after, and the browser allocation audit, with
   a dated record under `docs/performance/`.

## Revisit when

- A new time transform is not piecewise affine (for example a nonlinear
  warp such as swing by a curve).
- Bus evaluation through `Mapped` measures slower than the specialized
  variants on a real host.
