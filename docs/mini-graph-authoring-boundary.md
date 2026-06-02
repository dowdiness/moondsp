# Mini pattern ↔ graph authoring boundary

This contract defines how MoonDsp's Mini pattern/control DSL composes with a
separate graph/topology DSL. It complements the external DSL lowering contract:
external graph authoring still lowers validated topology to `Array[DspNode]`,
crosses into MoonDsp through `CompiledTemplate::analyze`, and builds validated
control bindings on the control side.

## Intended flow

```text
Mini PatternDoc / PatternSnapshot
  -> scheduler events + ControlMap
  -> template registry + ControlMapper
  -> ControlBindingMap for the selected CompiledTemplate
  -> GraphControl batch / BoundVoicePool note-on at block boundary

Graph DSL document
  -> normalized topology + declared named controls
  -> Array[DspNode]
  -> CompiledTemplate::analyze
  -> ControlBindingBuilder::build + compile/hotswap on the control side
```

Mini is the pattern/control layer. A graph DSL is the topology/template layer.
The bridge is metadata owned by the editor, host, or live-coding environment: it
selects a prepared template for a Mini event, transforms Mini control keys into
graph-facing keys, and resolves those keys through bindings proven against the
selected template.

## Responsibility split

| Layer | Owns | Must not own |
| --- | --- | --- |
| Mini DSL | Text pattern syntax, rhythmic structure, event timing, `ControlMap`, pattern snapshots, and block-boundary scheduler delivery. | DSP topology, graph node identity, graph source diagnostics, or graph recompilation policy. |
| Graph DSL authoring | Template names, topology, stable graph node IDs, declared controls, defaults/requiredness, source diagnostics, and lowering to `Array[DspNode]` plus binding declarations. | Pattern syntax, event-time scheduling, Mini drum/note semantics, or sample-accurate automation. |
| MoonDsp graph runtime | `DspNode`, `CompiledTemplate`, compile diagnostics, validated `ControlBindingMap`, runtime `GraphControl` validation, hotswap, and audio-safe processing. | Source parsing/projection, external name resolution, or deciding which template a Mini event meant. |

## Canonical control bridge

Mini events carry numeric `ControlMap` entries. The integration bridge applies
these rules before calling `ControlBindingMap::resolve_controls`:

| Mini key | Mini meaning | Bridge behavior | Graph-control result |
| --- | --- | --- | --- |
| `sound` | Drum/sound selector from `s("...")`; current Mini atoms use GM MIDI drum numbers such as `bd = 36`. | Consumed as a template/route selector. A registry may expose graph templates by name (`bd`) while normalizing to the same sound code. | No `GraphControl` by default. Missing selected template is a control-side diagnostic; do not parse/lower/compile on the audio callback. |
| `note` | MIDI note number from `note("...")`. | Convert to Hz when using the default scheduler semantics, then bind to the selected template's pitch/frequency control. The canonical graph-facing key is `note`; a host may explicitly alias it to another declared key such as `freq`. | `GraphControl::set_param` for the bound oscillator/frequency slot. |
| `cutoff` | Filter cutoff in Hz from `.cutoff(f)`. | Pass through only if the selected graph template declares/binds it. | Usually `GraphParamSlot::Value0` on `Biquad` / `StereoBiquad`; runtime validation still checks sample-rate-dependent domains. |
| `gain` | Linear gain from `.gain(g)`. | Pass through only if declared/bound. | Usually `GraphParamSlot::Value0` on `Gain` / `StereoGain`. |
| `pan` | Voice pan from `.pan(p)` or `.jux(...)`. | Default scheduler behavior consumes it as a per-voice pan side effect and drops it before binding. If a graph template wants an internal `Pan` control, use a custom mapper/alias and do not also apply the voice-pan side effect. | None by default; opt-in mapping may bind to `GraphParamSlot::Value0` on `Pan`. |
| Future keys | Opaque numeric controls added by Mini or host code. | The graph document's declared-control schema decides whether the key is accepted, optional, required, defaulted, or reported as unknown. | `GraphControl::set_param` only after validated binding compatibility. |

`ControlBindingMap::resolve_controls` deliberately ignores unbound keys so low
level callers can compose generic pattern maps. Editor-facing bridges that have
a graph DSL control schema should validate unknown graph-facing keys before
resolution and surface those diagnostics in the authoring UI.

## Template selection

A bridge maintains a prepared registry entry per playable graph template:

- template name or route key used by the editor;
- optional Mini `sound` code or track/default selector;
- analyzed `CompiledTemplate`;
- `ControlBindingMap` built against that exact template;
- compiled runtime, hot-swap target, or `BoundVoicePool` prepared from the same
  template and bindings.

For `s("bd")`, Mini emits `sound = 36`. The bridge maps that code to the
registry entry for the `bd` graph template. For note-only patterns, a host may
use the currently selected track/template as the selector. If selection fails,
report a missing-template diagnostic and skip the event or keep the last-good
runtime alive; do not fall back to graph recompilation inside the scheduler or
audio callback.

## Required, optional, and defaulted controls

Graph DSL documents may declare controls as required or optional and may attach
defaults, but that metadata lives in the graph-authoring bridge, not in Mini and
not in `ControlBindingMap`.

- A missing required event control with no default is an authoring/control-side
  diagnostic for that selected template.
- A missing optional control emits no `GraphControl`; the compiled template's
  current/default parameter remains in effect.
- A bridge-level default may be materialized as a control value during event
  resolution. A default baked into the `DspNode` array is part of the graph
  template and changes through the template-analysis/compile path.
- Retargeting a declared control to a different node/slot requires rebuilding
  the `ControlBindingMap` against the selected `CompiledTemplate`.

## Recompile vs runtime control

Do not recompile graph templates for Mini-only changes. Use pattern snapshot
updates for timing changes and runtime controls for parameter values:

- Mini pattern edits that change timing, density, or event ordering;
- `ControlMap` value changes for note, cutoff, gain, pan, and future numeric
  automation;
- bridge-level defaults that are applied as event controls.

Use graph analysis/compile/hotswap or voice-pool replacement on the control side
for topology/template changes:

- adding, removing, or rewiring DSP nodes;
- changing node kinds or terminal output shape;
- changing graph-authored static defaults encoded in `DspNode` values;
- adding/removing declared controls or changing their target node/slot;
- rebuilding a template registry entry after graph DSL lowering changes.

`GraphControl` values are still validated by the graph runtime. Invalid runtime
values reject the control batch transactionally and should not trigger a graph
recompile attempt.

## Block-boundary staging

Pattern snapshot updates and graph template updates share the same timing rule:
prepare everything on the control side, then publish at a block boundary.

- Mini parsing, Mini lowering, graph DSL parsing/projection/lowering,
  `CompiledTemplate::analyze`, binding validation, compile, and hotswap setup
  are control-thread/editor work.
- The scheduler commits queued pattern/song snapshots at block start before
  querying events.
- Hot-swap wrappers and `BoundVoicePool::set_template` install already prepared
  templates/bindings transactionally.
- If a UI changes both pattern and graph template selection, stage the selected
  template, its bindings, and the replacement pattern snapshot together so the
  next block observes a coherent pair.

## Benchmark guidance

Do not treat all authoring work as one benchmark. Measure these paths
separately, as issue #118 tracks:

1. Mini parse/lower and pattern snapshot update cost;
2. per-event bridge control resolution and binding lookup;
3. graph DSL lowering, `CompiledTemplate::analyze`, binding build, and compile;
4. audio block processing with already compiled runtimes and block-boundary
   controls.

Only the fourth category is audio-hot-path work. Performance-motivated changes
to the other categories should be backed by isolated measurements.

## Non-goals

- Replacing production Mini parsing with Loom.
- Embedding Mini pattern syntax inside the graph DSL.
- Letting graph recompilation stand in for Mini parameter automation.
- Adding sample-accurate automation; current control semantics are
  block-boundary.
