# ADR-0020: Controls are typed signals with one representation

- **Status:** Accepted 2026-11-19. Migration steps 1–4 are implemented; step 5 (browser ABI nesting rules) remains.
- **Date:** 2026-11-19
- **Supersedes:** in [ADR-0019](0019-automatic-control-buses.md), the event
  binding mechanism of Decision 2 and the rejected alternative "a new signal
  value type in `ControlMap`"; in [ADR-0007](0007-control-map-accessor-surface.md),
  string control keys. ADR-0019's Consequences already name a typed key enum
  as "a separate decision"; this is that decision.
- **Related:** [ADR-0019 automatic control buses](0019-automatic-control-buses.md),
  [ADR-0007 ControlMap accessor surface](0007-control-map-accessor-surface.md),
  [pattern algebra](../pattern-algebra.md)

## Context

ADR-0019 made sounding voices follow controls through buses: a control is a
signal over root time, and nested occurrences of a key combine by one rule
per key (Decision 8). That model is right. Its implementation keeps every
control in two places at once:

1. **The payload.** Each event carries a `ControlMap` (`Map[String, Double]`)
   with the value at its onset.
2. **The bindings.** Each event also carries `(key, bus)` bindings into a bus
   table, through the private `ScopedValue.bindings`.

Everything below exists only to keep those two in step:

- `fill_bound_controls` writes each bus's value back into the payload at
  `part.begin` (`Pat::fill_bound_controls`, `CompiledPattern::at_root`).
- `FilterMap` drops all bindings when its function changes the payload, and
  `jux` calls `unbind_keys` for the pan it fixes.
- Nesting a `Multiply` key over a payload value that no inner bus provides
  needs `BusBinding.inner`, and the lowering caches bindings per atom only
  while that recorded payload value is unchanged (`last_payload`).
- The scheduler passes both forms to the voice:
  `BoundVoicePool::note_on_controls(controls : Map[String, Double], follow~)`.

Three more properties of the current model are accidental:

- **Keys are strings.** The nesting rule is a string comparison
  (`Nesting::of`), the voice and scheduler name keys as literals, a
  misspelled key fails silently (ADR-0007, Consequences), and the live editor
  duplicates the `gain` rule in TypeScript (`web/live/src/inline-controls.ts`).
- **Absence is `NaN`.** `BusSignal::eval` returns `NaN` for "no value here",
  `EventBuses::reader` passes it across the public boundary, and
  `BoundVoicePool::update_follows` filters it with `is_nan`. A continuous
  function that computes `NaN` is indistinguishable from a rest.
  `Double?` is not an option on the render path: a probe built with MoonBit
  0.10.21 allocates one `Some` per evaluation on wasm-gc (`struct.new`),
  JS (`new …Some`), and native (`moonbit_malloc`). A single-field newtype
  over `Double` does not allocate on any of them (same probe; the evaluator
  returns `f64`, a JS number, and `double`).
- **Constant controls are a special case.** A constant bus "needs no
  follower" (`EventBuses::each_reader` skips `is_constant`), so a constant is
  both a payload value and, sometimes, a bus.

The essential complexity is smaller: a control is a function of time with
gaps; nesting composes two such functions by the key's rule; a voice reads
the function at note-on and, if it varies, once per block; a key belongs to
a closed set the engine knows how to apply.

## Decision

### 1. A closed, typed control key

`Control` is an enum of the controls the engine applies. Text names a
control only where it enters, in Mini's method names; everything past the
parser, including `PatternDoc` control atoms and host bindings, takes
`Control`. There is no string-to-`Control` parser beside Mini's:

```text
Note | Sound | Gain | Pan | Room | Lpf | LpfResonance | Hpf | HpfResonance
| Attack | Decay | Sustain | Hold | Release
```

This is the set Mini emits (`mini/expression_syntax.mbt`) plus `Decay` and
`Sustain`, which the voice writes itself to turn the envelope into a hold
envelope for `hold` (`BoundVoicePool::note_on`). `Control` lives in
its own leaf package, `control`, so `pattern` and `voice` share it without
depending on each other. `Nesting::of(Control)` states each variant's
nesting rule (`Gain` multiplies, the rest override) by an exhaustive match.
Pool bindings target a `Control`, not a string. There is no open
`Named(String)` case: adding a control means adding a variant, which a new
control needs anyway for its nesting rule.

The graph binding types stay below this vocabulary: `ControlBindingBuilder[K]`
and `ControlBindingMap[K]` are generic over their key. A voice pool binds
`Control`; external graph authoring (ADR-0010) binds as many parameters as
its graph has, named by `String`, which a closed set cannot name. A
binding's unit stays on the binding, not on the variant, because it belongs
to the target: the browser synth converts `Note` with `MidiToHz`, the CLAP
synth binds it linearly.

### 2. An event's own values and its buses are disjoint

*Amended 2026-11-19, when step 3 was implemented.* The first version of this
decision gave each event its signals directly and removed the bus table. That
conflicts with ADR-0019 Decision 2: a compiled subtree keeps its buses in its
own time and every enclosing node wraps the whole table once at compile time,
which is what lets `CompiledCache` share the subtree wherever it is reused.
Signals held by events would have to be rewrapped per event at every time
transform on every query, or compiled top-down, which breaks that sharing.

So the table stays, and the duplication is removed instead:

- An event's payload holds only its **own** values, the ones its leaf
  (`Pure`, `Atom`) or a `FilterMap`/`jux` result set. Lowering never writes a
  bus value into it.
- An event's bindings map a key to a bus and nothing else (`BusBinding` is
  `(key, bus)`). They depend neither on time nor on the payload, so events of
  one atom share them by identity.
- A bound key's signal is `Nesting::of(key).signal(own, bus)`: the event's own
  value is the innermost occurrence of the key, for every key. Where the
  outer bus rests, the own value applies, for `Override` keys as for `gain`.
- Bus values enter a payload only where controls leave lowering
  (`project_controls`): the public `pat()`, each snapshot event, and the view
  a `FilterMap` function receives. A reader composes the same signal from the
  event's own values (`EventBuses.own`).
- `FilterMap` sees the projection at the event's onset, on the child's clock.
  Returning it unchanged keeps the own values and buses; any other result
  becomes the event's own values and follows no bus, since a bus would undo
  the mapping. `jux` sets its pan as an own value and unbinds the pan bus.

This removes `BusBinding.inner`, the payload-keyed binding cache
(`last_payload`), the payload argument of `bind_buses`, and the write-back
into the payload at the snapshot root (`at_root`). Projection is computed
without building signals (`Nesting::combine`) and writes all bound keys with
one `apply`.

### 3. Absence is a value type, not a sentinel

`ControlValue` (in `control`) is a single-field newtype over `Double`. Its
methods own the only absence rules: `times` (for `Multiply`), `or_else` (for
`Override` and `Merge` presence), `is_absent`, `get`, and `unwrap_or`, the
non-allocating read the audio thread uses. `BusSignal` gains an `Absent`
variant, so `Const` always holds a value; the `Fast` silence case and Euclid
gaps return `Absent`. A continuous function's result is checked once where it
becomes a `ControlValue`. Bus readers and voice followers return
`ControlValue`, so no public API passes `NaN` for absence.

### 4. One read path at note-on and while sounding

A voice reads a note's controls through one source, the
`@control.ControlSource` trait: `value(key)` is the key's value at the onset,
and `each_varying` visits each key whose value changes while the note sounds,
with its reader. `BoundVoicePool::note_on(controls)` and `note_gate(controls)`
take any source; `note_on` resolves graph and voice-frame bindings from the
onset values, and the varying keys become the voice's followers. The `hold`
envelope substitutes `Decay` and `Sustain` in its lookup instead of copying
the controls.

`@pattern.Controls` is the source for a pattern event: its payload as it
leaves lowering, and its `EventBuses`. The payload is projected at the onset
(`part.begin`), so a bound key's onset value is already there and the bus is
evaluated only for keys whose signal varies. `EventBuses` stays as what an
event carries through song and playback placement. A `Map[Control, Double]`
is a source of fixed controls, for hosts and tests. The trait lives in
`control` because `voice` must not depend on `pattern`; the scheduler, which
sees both, joins them.

### 5. The engine is the only source of nesting rules

The browser ABI exposes each control's nesting rule, and the live editor
reads it instead of hard-coding `gain`.

## Evidence required before acceptance

- The allocation audit (`scripts/audit-clap-audio-allocations.sh
  --expect-zero`) stays at zero, and a probe of the final `ControlValue`
  evaluator shows no allocation on wasm-gc, JS, and native.
- Block-query benchmarks for the three Mini scores in
  [the pattern performance summary](../performance/2026-10-02-pattern-allocation-summary.md)
  do not regress, recorded under `docs/performance/`.
- Browser output for the seven ADR-0019 comparison scores is bit-identical,
  and the existing control-bus tests pass unchanged in meaning.

## Alternatives considered

| Alternative | Why not chosen |
| --- | --- |
| Keep payload plus bindings (status quo) | Every rule above exists only to synchronize them |
| Signals in a `Map[String, BusSignal]` | Removes the duplication but keeps stringly keys and the duplicated nesting rule |
| `Double?` for absence | Allocates per evaluation on all three backends (measured) |
| One typed record with a field per control | Every event pays for every control; sparse keys are the common case |
| Events hold their signals directly; no bus table (this decision's first version) | Rewraps signals per event at every time transform on every query, or compiles top-down and loses `CompiledCache` sharing (ADR-0019 Decision 2) |
| Leaf values as `Const` buses in the table | Every child of a sequence would own buses, so renumbering runs per event for each one, and slot wrapping grows quadratically with sequence length |
| Record each key's own value on its binding (generalized `inner`) | Keeps the binding dependent on the payload and the payload-keyed cache |

## Consequences

- Breaking for `@pattern`, `@voice`, `@graph`, and `@scheduler` public
  APIs: string-keyed bindings, `NaN`-valued readers, and
  `note_on_controls` are replaced. No compatibility layer, as in ADR-0019.
- ADR-0007's accessor surface becomes `ControlMap` accessors by `Control`.
- A voice host that is not a pattern, such as the CLAP engine, attaches
  followers whose readers return `ControlValue`; a host with fixed controls
  passes a `Map[Control, Double]`.
- Mini's grammar and the browser score format do not change; their parsers
  produce `Control` values.
- The bus table and its renumbering (`shift_bus_bindings`,
  `concat_child_buses` offsets) stay: they are what lets a compiled subtree
  be shared (Decision 2).
- A projection from signals to values stays for as long as a function sees
  values: `FilterMap`, and `Pat[ControlMap]` queries through `pat()`.

## Migration order

1. `BusValue` and `BusSignal::Absent`, internal to `pattern` (no API change).
   Done: `BusSignal::eval` returns `BusValue`, which the release builds
   compile to `f64` (wasm-gc), a number (JS), and `double` (native), with no
   allocation in its body; `NaN` remains only inside `BusValue` and at
   `EventBuses::reader`.
2. `Control` enum and typed pool bindings. Done: `ControlMap` and every
   pattern, Mini, scheduler, and voice API that named a key take `Control`;
   graph bindings are generic over their key. Measured against step 1:
   no query-benchmark regression once `Control` hashes its variant's
   position (the derived hash was slower than `String`'s), and
   identical browser output hashes for ten scores
   ([record](../performance/2026-10-02-pattern-allocation-summary.md)).
3. Own values and buses are disjoint in lowering (Decision 2, as amended).
   Done: `BusBinding.inner`, `last_payload`, and `at_root` are gone, and an
   outer `Override` bus that rests falls back to the event's own value.
   Against step 2, the pattern query benchmarks ran 7–17% faster and browser
   output hashes for ten scores were identical
   ([record](../performance/2026-10-02-pattern-allocation-summary.md)).
4. Voice and scheduler read an event's controls instead of a copied `Map`
   plus a `follow` list. Done: `note_on(controls : ControlSource)` replaces
   `note_on_controls`, `ControlValue` moved to `control` and replaces `NaN`
   in bus readers and followers, and graph binding resolution takes a lookup
   instead of a `Map`. Against step 3, an isolated note-on benchmark and the
   query benchmarks did not regress, browser output hashes for ten scores
   were identical, and the CLAP allocation audit stayed at zero
   ([record](../performance/2026-10-02-pattern-allocation-summary.md)).
5. Browser ABI exports nesting rules; the editor drops its `gain` check.

Each step lands with the full test suite and the allocation audit green.

## Revisit when

- A host needs user-defined graph parameters that the closed `Control` set
  cannot name.
- Per-event binding sharing does not hold for some combinator and query
  allocation grows measurably.
