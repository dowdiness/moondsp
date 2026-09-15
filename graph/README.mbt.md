# Compiled DSP graphs

`graph` turns an authoring-order `Array[DspNode]` into a reusable DSP runtime.
It validates topology, optimizes the graph once, compiles preallocated runtime
state, applies live controls, and supports block-boundary replacement.

## Architecture context

In moondsp's layered design, `graph` sits between authoring/voice orchestration
and low-level sample processing:

```text
[ mini ] (text notation)
   ↓
[ pattern / song ] (musical time & event streams)
   ↓
[ scheduler ] (event-to-voice scheduling)
   ↓
[ voice ] / [ engine ] (voice allocation & mixing)
   ↓
[ graph ] ← (topology validation, optimization, compilation, hot-swap)
   ↓
[ dsp ] (primitive state & buffer processing)
```

- **Upstream consumers**: [`voice/`](../voice/) compiles templates into voice
  slots and applies pitch/gate controls; [`engine/`](../engine/) mounts and
  mixes independent graphs; live editors use `GraphTemplateDoc` and hot-swap.
- **Downstream dependencies**: [`dsp/`](../dsp/) executes individual sample
  operations; [`identity/`](../identity/) provides stable node IDs and
  revisions across edits.

## API quick reference

| Category | Types | Key operations |
|---|---|---|
| **Authoring** | `DspNode`, `DspNodeKind`, `GraphBuilder` | `DspNode::constant`, `DspNode::oscillator`, `DspNode::gain`, `DspNode::biquad`, `DspNode::adsr`, `DspNode::delay`, `DspNode::pan`, `DspNode::output`, `DspNode::stereo_output`, `GraphBuilder::analyze` |
| **Compilation** | `CompiledTemplate`, `CompiledDsp`, `CompiledStereoDsp` | `CompiledTemplate::analyze`, `CompiledDsp::compile_result`, `CompiledDsp::compile`, `CompiledDsp::process`, `CompiledStereoDsp::compile_result`, `CompiledStereoDsp::process` |
| **Runtime Control** | `GraphControl`, `GraphParamSlot`, `ControlBindingMap` | `GraphControl::set_param`, `GraphControl::gate_on`, `GraphControl::gate_off`, `CompiledDsp::apply_control`, `CompiledDsp::apply_controls`, `ControlBindingMap::resolve_controls` |
| **Hot-Swap & Topology** | `CompiledDspHotSwap`, `CompiledDspTopologyController`, `GraphTemplateDoc`, `GraphIndexMap` | `CompiledDspHotSwap::queue_swap`, `CompiledDspTopologyController::queue_topology_edit`, `CompiledDspTopologyController::queue_topology_edits`, `GraphTemplateDoc::from_nodes`, `GraphTemplateDoc::index_map`, `GraphTemplateDoc::replace_node` |
| **Diagnostics & Errors** | `GraphCompileError`, `GraphControlError`, `GraphTopologyQueueError`, `GraphTopologyEditError` | Structured rejection reporting for cycles, invalid slots, input mismatches, or hot-swap capacity differences |

## Analyze, compile, process

The canonical boundary is:

```text
Array[DspNode]
  -> CompiledTemplate::analyze
  -> CompiledTemplate
  -> CompiledDsp::compile_result
  -> CompiledDsp
```

`CompiledTemplate` is the only exchange type between graph authoring and runtime
compilation. Analyze once and reuse the template when creating multiple runtime
instances, such as the slots in a voice pool.

```mbt check
///|
test "compile and process a mono graph" {
  let context = @dsp.DspContext::new(sample_rate=48000.0, block_size=8)
  let nodes = [
    @graph.DspNode::constant(0.5),
    @graph.DspNode::gain(0, 0.4),
    @graph.DspNode::output(1),
  ]
  let template = @graph.CompiledTemplate::analyze(nodes)
  let compiled = @graph.CompiledDsp::compile_result(template, context).unwrap()
  let output = context.make_buffer()

  compiled.process(context, output)

  assert_true(output.all(sample => (sample - 0.2).abs() < 0.000001))
}
```

Inputs are authoring indices. In the example, node `1` reads node `0`, and the
terminal output reads node `1`. Nodes may appear out of dependency order; the
compiler topologically sorts reachable nodes.

## Compilation failures

Prefer `compile_result` when the caller needs a rejection reason. Compilation
rejects missing or multiple outputs, invalid references and parameters,
unreachable nodes, and unsupported feedback cycles.

```mbt check
///|
test "compile_result reports an invalid input" {
  let context = @dsp.DspContext::new(sample_rate=48000.0, block_size=8)
  let template = @graph.CompiledTemplate::analyze([
    @graph.DspNode::gain(9, 0.5),
    @graph.DspNode::output(0),
  ])

  match @graph.CompiledDsp::compile_result(template, context) {
    Err(@graph.GraphCompileError::InvalidInput(index, _, _, source)) => {
      assert_eq(index, 0)
      assert_eq(source, 9)
    }
    _ => assert_true(false)
  }
}
```

`CompiledDsp::compile` and `CompiledStereoDsp::compile` return `None` for the
same failures when the reason is not needed.

## Runtime controls

`GraphControl` targets authoring indices, even after optimization and
reordering. `apply_controls` validates a whole batch before mutation, then
applies it in order. An invalid control rejects the complete batch.

```mbt check
///|
test "retune a compiled graph" {
  let context = @dsp.DspContext::new(sample_rate=48000.0, block_size=4)
  let template = @graph.CompiledTemplate::analyze([
    @graph.DspNode::constant(1.0),
    @graph.DspNode::gain(0, 0.25),
    @graph.DspNode::output(1),
  ])
  let compiled = @graph.CompiledDsp::compile_result(template, context).unwrap()
  let output = context.make_buffer()

  compiled.process(context, output)
  assert_true(output.all(sample => sample == 0.25))

  assert_true(
    compiled.apply_control(
      @graph.GraphControl::set_param(1, @graph.GraphParamSlot::Value0, 0.75),
    )
    is Ok(_),
  )
  compiled.process(context, output)
  assert_true(output.all(sample => sample == 0.75))
}
```

The supported parameter slot depends on the node kind. Gate controls apply only
to `Adsr` nodes. See the technical reference for the current slot matrix and
validation rules.

## Mono and stereo runtimes

`CompiledDsp` renders one output buffer. `CompiledStereoDsp` renders separate
left and right buffers from a terminal `StereoOutput` graph.

```mbt check
///|
test "compile a terminal stereo graph" {
  let context = @dsp.DspContext::new(sample_rate=48000.0, block_size=4)
  let template = @graph.CompiledTemplate::analyze([
    @graph.DspNode::constant(1.0),
    @graph.DspNode::pan(0, -1.0),
    @graph.DspNode::stereo_output(1),
  ])
  let compiled = @graph.CompiledStereoDsp::compile_result(template, context).unwrap()
  let left = context.make_buffer()
  let right = context.make_buffer()

  compiled.process(context, left, right)

  assert_true(left.all(sample => sample > 0.99))
  assert_true(right.all(sample => sample.abs() < 0.000001))
}
```

The stereo surface is intentionally narrower than the mono surface. It supports
`Pan`, stereo gain, clip, biquad, delay, and `StereoOutput`; mono graphs may fold
a stereo path down through `StereoMixDown`.

## Hot-swap

`CompiledDspHotSwap` and `CompiledStereoDspHotSwap` stage one compatible
replacement for the next `process` call. A positive `crossfade_samples` value
uses an equal-power transition; the default replaces the graph immediately.

```mbt check
///|
test "replace a graph at a block boundary" {
  let context = @dsp.DspContext::new(sample_rate=48000.0, block_size=4)
  let old_graph = @graph.CompiledDsp::compile_result(
    @graph.CompiledTemplate::analyze([
      @graph.DspNode::constant(0.25),
      @graph.DspNode::output(0),
    ]),
    context,
  ).unwrap()
  let replacement = @graph.CompiledDsp::compile_result(
    @graph.CompiledTemplate::analyze([
      @graph.DspNode::constant(0.75),
      @graph.DspNode::output(0),
    ]),
    context,
  ).unwrap()
  let hot_swap = @graph.CompiledDspHotSwap::from_graph(old_graph)
  let output = context.make_buffer()

  assert_true(hot_swap.queue_swap(replacement) is Ok(_))
  hot_swap.process(context, output)

  assert_true(output.all(sample => sample == 0.75))
}
```

Replacement graphs must match the active graph's sample rate and block
capacity. Compile and queue replacements on the control side, not in the audio
callback.

## Topology editing and stable identity

`CompiledDspTopologyController` applies transactional `GraphTopologyEdit`
batches, recompiles a replacement, and stages it through an internal hot-swap.
`GraphTemplateDoc` adds stable `GraphNodeId` values and revisions for editors.
Its `GraphIndexMap` translates stable identities into authoring indices for
controls, bindings, and topology edits.

Use these layers for structural live editing:

1. edit a `GraphTemplateDoc` on the control side;
2. derive controls or topology edits through its index map;
3. queue the validated replacement;
4. let the next process block adopt it.

## Real-time boundary

Compilation, analysis, topology editing, and graph replacement may allocate.
`CompiledDsp::process` and `CompiledStereoDsp::process` operate on preallocated
runtime state. If a requested block is larger than the compiled capacity,
processing fails closed to silence.

The graph package owns topology and runtime control. DSP algorithms remain in
[`dsp/`](../dsp/); polyphonic allocation and mixing remain in
[`voice/`](../voice/).

- [Technical reference](../docs/technical-reference.md#351-compiled-graph--runtime-control-surface)
- [Graph boundary ADR](../docs/decisions/0010-compiled-template-runtime-boundary.md)
- [External DSL lowering](../docs/external-dsl-lowering.md)
