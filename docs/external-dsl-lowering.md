# External DSL lowering contract

This guide defines the public boundary for editors, text DSLs, or graph DSLs
that generate MoonDsp graphs. It complements ADR-0010 (the
`CompiledTemplate` runtime boundary) and ADR-0014 (authoring equality and typed
compile diagnostics).

## Intended flow

```text
validated authoring graph
  -> Array[DspNode]
  -> CompiledTemplate::analyze
  -> CompiledDsp::compile_result / CompiledStereoDsp::compile_result
  -> compile, hot-swap, or voice-pool replacement on the control side
```

Parser, projection, semantic lowering, `CompiledTemplate::analyze`, binding
validation, and compile are editor/control-thread work. They are not audio-hot
path work. The audio thread should only process already compiled graphs and
apply block-boundary controls or swaps.

## What the external DSL owns

An external DSL owns source-level facts that MoonDsp cannot reconstruct from a
flat graph:

- source ranges and diagnostics for parser/projection errors;
- stable authoring node IDs;
- the current mapping from stable IDs to authoring array indices;
- control keys and their target stable IDs plus `GraphParamSlot`s;
- last-good source/lowering state if the current edit is invalid.

Reject syntax errors, unresolved IDs, type errors, ambiguous names, and other
source-language failures before constructing `Array[DspNode]`. Do not encode
those failures as sentinel graph nodes just to hand them to MoonDsp.

## Required `DspNode` array contract

The array passed to `CompiledTemplate::analyze` is an authoring graph snapshot.
It should satisfy these invariants:

- Build nodes through the public `DspNode` constructors.
- `input0` and `input1` values are authoring indices into the same array for
  slots that the node kind uses. The array does not have to be topologically
  sorted; MoonDsp sorts the reachable graph during compile.
- Choose one terminal shape for the compile path: one `Output` for mono
  `CompiledDsp`, or one `StereoOutput` for terminal-stereo
  `CompiledStereoDsp`.
- Numeric parameters should satisfy the domains in
  `docs/salat-engine-technical-reference.md` (finite frequencies/gains, valid
  filter cutoffs, valid delay lengths and feedback, positive clip thresholds,
  and so on). If they do not, `compile_result` returns a typed
  `GraphCompileError`.
- Dead authoring nodes may exist in the snapshot. They remain visible to
  `CompiledTemplate` equality, but optimization can eliminate them. Do not bind
  controls or voice gates to nodes that the analyzed template eliminates.
- Runtime controls target original authoring indices, not optimized runtime
  indices.

## What `CompiledTemplate::analyze` does

`CompiledTemplate::analyze(Array[DspNode])` is the single canonical crossing
from authoring data to the runtime template artifact. It snapshots the input
array, runs graph optimization/liveness analysis once, and retains the mapping
from authoring indices to optimized nodes.

`analyze` is deliberately infallible and does not take a `DspContext`. It is
not a source validator and not a numeric-domain validator. Use
`compile_result` for MoonDsp graph rejection after analysis.

## Compile and last-good behavior

Use `CompiledDsp::compile_result(template, context)` or
`CompiledStereoDsp::compile_result(template, context)` when an editor or DSL
needs diagnostics. The older `compile(...) -> Self?` APIs remain compatibility
entry points, but they intentionally do not explain rejections.

On `Err(GraphCompileError)`, keep the last-good runtime graph/template alive,
show the diagnostic through the external DSL's source mapping, and do not queue
a hot-swap or replace a voice-pool template. Node-indexed compile diagnostics
are reported as authoring indices when MoonDsp can map them back.

## Control bindings

A lowering layer should retain enough data to rebuild bindings for every valid
snapshot:

1. stable external control key;
2. stable target node ID;
3. current authoring index for that node ID;
4. target `GraphParamSlot`.

After `CompiledTemplate::analyze`, call `ControlBindingBuilder::build` with the
same analyzed template. The builder checks authoring-index bounds, slot
compatibility, post-optimization liveness, and duplicate keys. Rebuild the
`ControlBindingMap` whenever the template changes; a map is proven only against
the template it was built with.

## Public example

```moonbit
let context = DspContext::new(sample_rate=48000.0, block_size=128)

// Produced by a validated external DSL. Comments show stable external IDs.
let nodes = [
  DspNode::oscillator(Waveform::Sine, 440.0), // id: "osc"
  DspNode::gain(0, 0.25), // id: "amp"
  DspNode::output(1), // id: "out"
]

let template = CompiledTemplate::analyze(nodes)
let bindings = ControlBindingBuilder::new()
  .bind(key="freq", node_index=0, slot=GraphParamSlot::Value0)
  .bind(key="gain", node_index=1, slot=GraphParamSlot::Value0)
  .build(template)

match CompiledDsp::compile_result(template, context) {
  Ok(next_runtime) => {
    // Control side: install `next_runtime` directly, queue it into a hot-swap,
    // or pass the template/runtime pair into a voice-pool replacement flow.
    ignore(next_runtime)
  }
  Err(error) => {
    // Editor side: keep the previous runtime alive and map `error` through
    // the external DSL's authoring-index -> source-range table.
    ignore(error)
  }
}
```

For an external semantic failure, stop earlier:

```text
source edit -> parse/project/lower -> Err(unresolved stable node id)
```

No `Array[DspNode]` is produced in that case, so the current runtime template is
left untouched.
