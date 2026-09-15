# Pattern engine

`pattern` describes what happens in musical time. It has no dependency on DSP
graphs, voices, schedulers, or browser APIs.

## Architecture context

In moondsp's layered design, `pattern` represents pure musical time and event
streams, situated between text notation and audio-rate scheduling:

```text
[ mini ] (text notation & document parsing)
   ↓
[ pattern ] ← (exact rational time, event queries, combinators, docs)
   ↓
[ song ] (structural section layout & arrangement)
   ↓
[ scheduler ] (event-to-voice scheduling & block quantization)
   ↓
[ voice ] / [ engine ] (voice allocation & mixing)
   ↓
[ graph ] (topology validation & compilation)
   ↓
[ dsp ] (primitives: buffers, oscillators, filters, envelopes)
```

- **Upstream consumers**: [`mini/`](../mini/) parses mini notation strings
  into `Pat[ControlMap]` or `PatternDoc[ControlMap]`.
- **Downstream dependencies**: [`identity/`](../identity/) provides stable node
  identifiers and revisions for `PatternDoc`. [`song/`](../song/) and
  [`scheduler/`](../scheduler/) consume patterns over time spans. `pattern` has
  zero dependencies on DSP, audio buffers, voices, or host runtimes.

## API quick reference

| Category | Types | Key operations |
|---|---|---|
| **Musical Time** | `Rational`, `TimeSpan`, `TimeTransform` | `Rational::from_int`, `Rational::to_double`, `TimeSpan::duration`, `TimeSpan::contains`, `TimeSpan::intersect`, `TimeSpan::shift`, `TimeTransform::apply` |
| **Core Query & Events** | `Pat[A]`, `Event[A]` | `Pat::pure`, `Pat::silence`, `Pat::from_query`, `Pat::query`, `Pat::same_content`, `Event::shift` |
| **Combinators** | `sequence`, `stack`, `merge_control`, `+` | `sequence`, `stack`, `merge_control`, `Pat::entries`, `Pat::named_entry`, `Pat::select_control` |
| **Time Transforms** | `Pat[A]` methods | `Pat::fast`, `Pat::slow`, `Pat::rev`, `Pat::euclid`, `Pat::degrade_by`, `every`, `Pat::gate`, `Pat::jux`, `Pat::filter_map` |
| **Control Helpers** | `ControlMap`, helper functions | `note`, `note_name`, `chord`, `sound`, `control`, `s_gain`, `s_cutoff`, `s_pan`, `ControlMap::get`, `ControlMap::set`, `ControlMap::merge` |
| **Document & Identity** | `PatternDoc[A]`, `PatternSnapshot[A]`, `PatternLoweringCache[A]` | `PatternDoc::from_pattern`, `PatternDoc::pure`, `PatternDoc::sequence`, `PatternDoc::stack`, `PatternDoc::lower`, `PatternDoc::lower_with_cache`, `PatternSnapshot::query` |

A pattern is a query:

```text
Pat[A] + TimeSpan -> Array[Event[A]]
```

The caller asks for a half-open time span such as `[0, 1)`. The pattern returns
all events that overlap that span.

## Exact musical time

`Rational` stores musical positions as reduced `Int64` fractions. This avoids
floating-point drift when patterns are stretched, repeated, and queried over
many cycles.

`TimeSpan` is a half-open interval. Adjacent spans `[0, 1)` and `[1, 2)` do not
overlap, so an event at cycle 1 is returned only by the second query.

```mbt check
///|
test "rational time stays exact" {
  let third = @pattern.Rational::new(1L, 3L)
  assert_true(third + third + third == @pattern.Rational::from_int(1))

  let first_cycle = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  assert_true(first_cycle.duration() == @pattern.Rational::from_int(1))
  assert_true(first_cycle.contains(third))
  assert_false(first_cycle.contains(@pattern.Rational::from_int(1)))
}
```

## Patterns and events

`Pat[A]` can hold any event value type. `Pat::pure(value)` produces one event
per cycle. `sequence` divides a cycle between patterns:

```mbt check
///|
test "sequence divides one cycle" {
  let pat = @pattern.sequence([
    @pattern.Pat::pure("a"),
    @pattern.Pat::pure("b"),
    @pattern.Pat::pure("c"),
  ])
  let cycle = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let events = pat.query(cycle)

  assert_eq(events.length(), 3)
  assert_eq(events.map(event => event.value), ["a", "b", "c"])
  assert_true(events[0].part.duration() == @pattern.Rational::new(1L, 3L))
}
```

Each `Event` has:

- `whole`: the event's ideal span before the query clips it;
- `part`: the part that overlaps the requested span;
- `value`: the event payload.

This distinction lets the scheduler keep the original note lifetime when a
query starts or ends inside an event.

## Combine patterns

Use `+` to play patterns together:

```mbt check
///|
test "overlay keeps separate events" {
  let notes = @pattern.note(60.0)
  let drums = @pattern.sound(36.0)
  let cycle = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let events = (notes + drums).query(cycle)

  assert_eq(events.length(), 2)
  assert_true(events[0].value.get("note") == Some(60.0))
  assert_true(events[1].value.get("sound") == Some(36.0))
}
```

`p + q` is the concise form of `stack([p, q])`. Overlay preserves both events;
it does not merge their values.

Use `merge_control` when one `Pat[ControlMap]` should add controls to another:

```mbt check
///|
test "merge control shapes one event" {
  let note = @pattern.note(60.0)
  let pan = @pattern.s_pan(-0.5)
  let cycle = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let events = @pattern.merge_control(note, pan).query(cycle)

  assert_eq(events.length(), 1)
  assert_true(events[0].value.get("note") == Some(60.0))
  assert_true(events[0].value.get("pan") == Some(-0.5))
}
```

Right-hand controls replace matching keys. `ControlMap::set` and
`ControlMap::merge` return new values, and `entries()` returns an owned copy.

## Transform time

The main time operations are:

| Operation | Effect |
|---|---|
| `fast(factor)` | Fit more events into the same span |
| `slow(factor)` | Stretch events across a longer span |
| `rev()` | Reverse events inside each cycle |
| `euclid(k, n)` | Spread `k` events over `n` steps |
| `degrade_by(p)` | Drop events with probability `p` |
| `every(n, f)` | Apply a transform every nth cycle |

Factors use `Rational`:

```mbt nocheck
///|
let twice = pat.fast(@pattern.Rational::from_int(2))

///|
let half_speed = pat.slow(@pattern.Rational::from_int(2))
```

`filter_map` changes or removes event values without defining new timing.
`Pat::silence()` returns no events.

## Control patterns

Audio-facing helpers produce `Pat[ControlMap]` values:

- `note` and `note_name` set `note`;
- `chord` overlays several note events;
- `sound` sets `sound`;
- `control` creates any scalar control;
- `s_gain`, `s_cutoff`, and `s_pan` create common control patterns.

The pattern package only carries these values. A scheduler or host decides how
a control maps to an instrument or DSP parameter.

## Live-editing identity

`PatternDoc[A]` adds stable `PatternNodeId` values and revisions to an authored
pattern tree. Lowering produces a `PatternSnapshot[A]`, which keeps source paths
for events while exposing the same runtime query model.

Use `PatternLoweringCache` when repeatedly lowering edited documents. Unchanged
subtrees can reuse their previous lowered patterns. Identity, content equality,
and playback entry addresses are separate concepts; changing one does not imply
that the others changed.

Mini notation builds this layer through `mini.parse_doc` and
`MiniAuthoringPipeline`. Direct `Pat` users do not need `PatternDoc`.

## Package boundary

`pattern` depends on `identity` and incremental value traits, but remains
independent of the DSP layers. It can be used as a standalone timing and event
library.

- [Live-coding cookbook](../docs/guides/live-coding-cookbook.md) — use patterns
  in the browser editor.
- [Mini notation reference](../docs/mini-notation.md) — text syntax that lowers
  into this package.
- [Pattern algebra design note](../docs/pattern-algebra.md) — overlay, value
  mapping, and future algebra choices.
