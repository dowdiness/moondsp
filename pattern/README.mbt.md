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
  into `Pat[ScoreEvent]` or `PatternDoc[ScoreEvent]`.
- **Downstream dependencies**: [`identity/`](../identity/) provides stable node
  identifiers and revisions for `PatternDoc`. [`song/`](../song/) and
  [`scheduler/`](../scheduler/) consume patterns over time spans. `pattern` has
  zero dependencies on DSP, audio buffers, voices, or host runtimes.

## API quick reference

| Category | Types | Key operations |
|---|---|---|
| **Musical Time** | `Rational`, `TimeSpan`, `TimeTransform` | `Rational::from_int`, `Rational::to_double`, `TimeSpan::duration`, `TimeSpan::contains`, `TimeSpan::intersect`, `TimeSpan::shift`, `TimeTransform::apply` |
| **Core Query & Events** | `Pat[A]`, `Event[A]` | `Pat::pure`, `Pat::silence`, `Pat::from_query`, `Pat::query`, `Pat::same_content`, `Event::shift` |
| **Combinators** | `sequence`, `stack`, `controls`, `+` | `sequence`, `stack`, `controls`, `Pat::entries`, `Pat::material`, `Pat::select_control` |
| **Time Transforms** | `Pat[A]` methods | `Pat::fast`, `Pat::slow`, `Pat::rev`, `Pat::euclid`, `Pat::degrade_by`, `every`, `Pat::gate`, `Pat::jux`, `Pat::filter_map` |
| **Control Helpers** | `ControlMap`, helper functions | `control`, `s_gain`, `s_cutoff`, `s_pan`, `ControlMap::get`, `ControlMap::set`, `ControlMap::merge` |
| **Document & Identity** | `PatternDoc`, `UntrackedPatternSnapshot`, `PatternLoweringCache` | `PatternDoc::from_pattern`, `PatternDoc::pure`, `PatternDoc::sequence`, `PatternDoc::stack`, `PatternDoc::lower_untracked`, `PatternDoc::lower_untracked_with_cache`, `UntrackedPatternSnapshot::query` |
| **Tracked material** | `TrackedPatternSnapshot`, `EventWithOrigin`, `EventOrigin`, `ResolvedReference` | `PatternDoc::atom`, `PatternDoc::control_atom`, `PatternDoc::reference_with_binding`, `PatternDoc::lower_tracked` |

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
  let third = @pattern.Rational(1L, 3L)
  assert_true(third + third + third == @pattern.Rational::from_int(1))

  let first_cycle = @pattern.TimeSpan(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  assert_true(first_cycle.duration() == @pattern.Rational::from_int(1))
  assert_true(first_cycle.contains(third))
  assert_false(first_cycle.contains(@pattern.Rational::from_int(1)))
}
```

### Allocation behavior

Pattern-node paths share immutable tails internally. `PatternNodePath::nodes`
still returns an independently mutable array; modifying it cannot change the
stored path or another event's provenance. Lowering prepares invariant leaf
paths before querying.

Rational identity operations and zero-offset span/event shifts can reuse their
immutable inputs. A nonempty intersection can reuse an already contained span.
These optimizations preserve exact values and half-open boundary semantics.
Pattern queries still allocate event and time temporaries; they do not provide
an allocation-free audio-thread contract. See the
[allocation measurements](../docs/performance/2026-10-02-pattern-allocation-summary.md#initial-batch).

`sequence` prepares immutable slot indices and rational bounds when constructed.
Queries translate those bounds into the current cycle and reuse the complete
slot's `[0,1)` child-query span; event-part clipping still uses the requested
query span. `whole_cycles` advances to the cycle end it already computed.
The [follow-up findings](../docs/performance/2026-10-02-pattern-allocation-summary.md#follow-up-loop)
compare these changes with the previous optimized baseline, including actual
Worklet allocation profiles and exact-origin preservation.

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
  let cycle = @pattern.TimeSpan(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let events = pat.query(cycle)

  assert_eq(events.length(), 3)
  assert_eq(events.map(event => event.value), ["a", "b", "c"])
  assert_true(events[0].part.duration() == @pattern.Rational(1L, 3L))
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
  let notes = @pattern.control(Note, 60.0)
  let drums = @pattern.control(Note, 36.0)
  let cycle = @pattern.TimeSpan(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let events = (notes + drums).query(cycle)

  assert_eq(events.length(), 2)
  assert_true(events[0].value.get(Note) == Some(60.0))
  assert_true(events[1].value.get(Note) == Some(36.0))
}
```

`p + q` is the concise form of `stack([p, q])`. Overlay preserves both events;
it does not merge their values.

Use `controls` to put several controls on one event. Controls that follow
their own timing over another pattern, such as `.gain("0.3 0.6")`, belong to
`PatternDoc::merge_control`, which lowers them to control buses (ADR-0019).

```mbt check
///|
test "controls shapes one event" {
  let cycle = @pattern.TimeSpan(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let events = @pattern.controls(
    @pattern.ControlMap::single(Note, 60.0).set(Pan, -0.5),
  ).query(cycle)

  assert_eq(events.length(), 1)
  assert_true(events[0].value.get(Note) == Some(60.0))
  assert_true(events[0].value.get(Pan) == Some(-0.5))
}
```

`ControlMap::set` and
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

- `control` creates any scalar control;
- `continuous` creates a control whose value is a function of exact time;
- `s_gain`, `s_lpf`, `s_hpf`, and `s_pan` create common control patterns.

The pattern package only carries these values. Which sound an event plays is
not a control: score events (`@score.ScoreEvent`) carry it beside their
controls. Operations that touch controls work on any payload that implements
`WithControls`. A scheduler or host decides how a control maps to a DSP
parameter.

## Live-editing identity

`PatternDoc[A]` adds stable `PatternNodeId` values and revisions to an
authored pattern tree. Untracked lowering produces an `UntrackedPatternSnapshot` with voice-scope
paths. A scope may contain several leaves; its last node is not an exact source
atom. Use `pattern_node_path()` for scope operations, not source highlighting.

Use `PatternLoweringCache` when repeatedly lowering edited documents. Unchanged
subtrees can reuse their previous lowered patterns. Identity, content equality,
and playback entry addresses are separate concepts; changing one does not imply
that the others changed.

Mini notation builds general documents through `mini.parse_doc`; `mini.Draft`
adds causal source witnesses. Direct `Pat` users do not need `PatternDoc`.

### Origin-preserving snapshots

`PatternDoc::atom(id~, source_atom~, value~)` associates a value with an explicit
`identity.SourceAtomId`. `control_atom(id~, source_atom~, key~, value~)` additionally
retains the canonical `control` content signature. A generic atom's musical
content remains unknown.

For named uses, construct `ResolvedReference::ResolvedReference` with
`definition~`, `definition_id~`, `reference~`, and `binding~`, then pass it to
`PatternDoc::reference_with_binding(id~, resolved_reference~)`. Reference,
definition, and binding IDs must share a source epoch. Identity constructors
check positive JavaScript-safe `Int64` components; `mini.Draft`, not this compiler,
allocates non-reused epochs and serials for edited text.

`doc.lower_tracked(cache?)` returns `TrackedPatternSnapshot` or raises
`PatternDocError`. It rejects unattributed primary leaves with `MissingAtomOrigin`
and ordinary references with `MissingReferenceBinding` during lowering. A merge's
right-hand control provider needs no primary origin. `pure`, `from_pattern`,
ordinary `reference`, and `lower_untracked` remain valid general APIs.

The tracked snapshot's `query(arc)` and `query_for_entry(index, arc)` return
`EventWithOrigin`: `event()` carries the musical event, `origin()` carries its
atom and outer-to-inner bindings, and `pattern_node_path()` carries the separate
voice scope. Returned binding arrays are defensive copies. `pat()` and
`as_snapshot()` erase origin capability without recompilation. Entry keys,
periods, musical signatures, and degradation seeds never include source IDs.

Lowering also derives automatic control buses ([ADR-0019](../docs/decisions/0019-automatic-control-buses.md)):
one per `PatternDoc::merge_control` and control key. An event's `buses()` carries the
buses its keys follow, placed on the clock the event is on; `reader(key)`
returns an allocation-free reader of exact time that yields a
`@control.ControlValue`. `Controls(event.value, buses~)` is what a voice reads
(`@control.ControlSource`): onset values from the payload, and through
`each_varying` the keys whose bus changes over time. A
provider must be built from atoms, `pure`, `continuous`, and time or
structure nodes; an opaque `from_pattern` provider raises
`UnsupportedControl`.

`doc.with_source_frame(frame~)` captures literal-local onset coordinates before
enclosing transforms. It annotates the root without adding a musical graph node
or changing node paths. Exact events expose `source_frame()` and `source_start()`;
the pitch belongs to the event payload. Local time wraps over the notation's whole-cycle repeat span.
`EventOrigin::write_binding_serials(storage, offset, limit)` writes complete
reference/binding/definition triples into caller-owned storage. It returns the
binding count, or `-1` without writing if capacity, epoch, or scalar bounds fail.

Document `every(id~, n~, transform~)` and `jux(id~, transform~)` accept
`TimeTransform::Fast`, `Slow`, or `Reverse`, not pattern callbacks. Arbitrary
callbacks remain available on raw `Pat`. Document every/jux keep their previous
unknown-content policy and broad branch scopes.

`mini.Draft::prepare_playback` captures these witnesses in immutable input.
Tracked Pattern input and tracked Song sections preserve them through scheduler
dispatch. The browser maps observations back through the current Draft; this
package owns neither DOM highlighting nor a browser clock.

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
