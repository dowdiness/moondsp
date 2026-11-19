# ADR-0020: Controls are typed signals with one representation

- **Status:** Accepted 2026-11-19. Migration steps 1 (`BusValue`, `BusSignal::Absent`) and 2 (`Control`, typed pool bindings) are implemented; steps 3–5 remain.
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
envelope for `hold` (`BoundVoicePool::note_on_controls`). `Control` lives in
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

### 2. An event's controls are signals, and only signals

An event carries `Controls`: for each `Control` it sets, one signal over its
own clock. A fixed value is `Const(v)`. There is no `ControlMap` payload
beside it and no binding table into a separate bus array; the signal *is*
the control.

Consequences inside lowering:

- A leaf's values (`Pure`, `Atom`) become `Const` signals.
- `MergeControl` composes each key as `nesting(key).signal(inner, outer)`.
  A payload value is just another inner signal, so `BusBinding.inner`, the
  payload cache, and `fill_bound_controls` disappear.
- `jux` sets `Pan` to `Const(±1)`; no unbinding.
- `FilterMap` receives the controls read at the event's onset and returns a
  replacement. Keys it returns unchanged keep their signals; keys it changes
  become `Const`. This is the one place a function sees values instead of
  signals, and the rule is stated, not reconstructed from physical equality.
- Placement and time transforms wrap signals exactly as ADR-0019 Decision 2
  defines.

Sharing stays structural: events of one atom share one `Controls` value, as
they share bindings today, so query allocation per event does not grow.

### 3. Absence is a value type, not a sentinel

`BusValue` is a single-field newtype over `Double`. Its methods own the only
absence rules: `times` (for `Multiply`), `or_else` (for `Override` and
`Merge` presence), and `is_absent`. `BusSignal` gains an `Absent` variant,
so `Const` always holds a value; the `Fast` silence case and Euclid gaps
return `Absent`. A continuous function's result is checked once where it
becomes a `BusValue`.

### 4. One read path at note-on and while sounding

The voice receives `Controls` and reads every key at the onset for its
note-on value. A key whose signal varies is also followed per block. The
scheduler no longer builds a `Map[String, Double]` plus a `follow` list;
`note_on_controls(controls, follow~)` becomes `note_on(controls)`.
`EventBuses` is replaced by `Controls`; its reader returns `BusValue`.

### 5. The engine is the only source of nesting rules

The browser ABI exposes each control's nesting rule, and the live editor
reads it instead of hard-coding `gain`.

## Evidence required before acceptance

- The allocation audit (`scripts/audit-clap-audio-allocations.sh
  --expect-zero`) stays at zero, and a probe of the final `BusValue`
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

## Consequences

- Breaking for `@pattern`, `@voice`, and `@scheduler` public APIs:
  `ControlMap`, `EventBuses`, and string-keyed bindings are replaced. No
  compatibility layer, as in ADR-0019.
- ADR-0007's accessor surface becomes `Controls` accessors by `Control`.
- Mini's grammar and the browser score format do not change; their parsers
  produce `Control` values.
- The bus table and its renumbering (`shift_bus_bindings`,
  `concat_child_buses` offsets) disappear, because an event refers to its
  signals directly.

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
3. `Controls` replaces payload plus bindings in lowering; delete
   `fill_bound_controls`, `unbind_keys`, `BusBinding`.
4. Voice and scheduler read `Controls`; delete `note_on_controls` and
   `EventBuses`.
5. Browser ABI exports nesting rules; the editor drops its `gain` check.

Each step lands with the full test suite and the allocation audit green.

## Revisit when

- A host needs user-defined graph parameters that the closed `Control` set
  cannot name.
- Per-event `Controls` sharing does not hold for some combinator and query
  allocation grows measurably.
