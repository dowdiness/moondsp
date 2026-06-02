///|
struct ExternalLoweredGraphFixture {
  nodes : Array[DspNode]
  bindings : ControlBindingBuilder
}

///|
enum ExternalLoweringError {
  UnresolvedReference(String)
} derive(Debug, Eq)

///|
fn valid_external_lowering_fixture() -> ExternalLoweredGraphFixture {
  {
    // Generated from stable external IDs:
    // "osc" -> authoring index 0, "amp" -> 1, "out" -> 2.
    nodes: [
      DspNode::oscillator(Waveform::Sine, 440.0),
      DspNode::gain(0, 0.3),
      DspNode::output(1),
    ],
    bindings: ControlBindingBuilder::new()
    .bind(key="freq", node_index=0, slot=GraphParamSlot::Value0)
    .bind(key="gain", node_index=1, slot=GraphParamSlot::Value0),
  }
}

///|
fn unresolved_external_reference_fixture() -> Result[
  ExternalLoweredGraphFixture,
  ExternalLoweringError,
] {
  // An external DSL should reject unresolved stable IDs before it creates an
  // Array[DspNode]; MoonDsp cannot recover source spans or name-resolution
  // context from a sentinel node.
  Err(ExternalLoweringError::UnresolvedReference("filter:missing"))
}

///|
test "external DSL lowering contract: generated graph compiles with bindings" {
  let context = DspContext::new(sample_rate=48000.0, block_size=16)
  let fixture = valid_external_lowering_fixture()
  let template = CompiledTemplate::analyze(fixture.nodes)
  let bindings = fixture.bindings.build(template).unwrap()
  let compiled = CompiledDsp::compile_result(template, context).unwrap()
  let controls : Map[String, Double] = { "freq": 660.0, "gain": 0.25 }
  let resolved = bindings.resolve_controls(controls)
  @debug.assert_eq(resolved.length(), 2)
  compiled.apply_controls(resolved).unwrap()
  let output = AudioBuffer::filled(16)
  compiled.process(context, output)
  assert_true(output.all(fn(sample) { is_finite(sample) }))
}

///|
test "external DSL lowering contract: unresolved references reject before analyze" {
  match unresolved_external_reference_fixture() {
    Err(ExternalLoweringError::UnresolvedReference(id)) =>
      @debug.assert_eq(id, "filter:missing")
    Ok(_) => fail("expected external lowering to reject unresolved reference")
  }
}

///|
test "external DSL lowering contract: compile errors preserve last good runtime" {
  let context = DspContext::new(sample_rate=48000.0, block_size=16)
  let last_good = CompiledDsp::compile_result(
    CompiledTemplate::analyze([DspNode::constant(0.25), DspNode::output(0)]),
    context,
  ).unwrap()
  let current_template = CompiledTemplate::analyze([
    DspNode::gain(99, 0.5),
    DspNode::output(0),
  ])
  match CompiledDsp::compile_result(current_template, context) {
    Err(GraphCompileError::InvalidInput(index, kind, slot, input)) => {
      @debug.assert_eq(index, 0)
      @debug.assert_eq(kind, DspNodeKind::Gain)
      @debug.assert_eq(slot, GraphTopologyInputSlot::Input0)
      @debug.assert_eq(input, 99)
    }
    _ => fail("expected invalid generated graph to report InvalidInput")
  }
  let output = AudioBuffer::filled(16)
  last_good.process(context, output)
  @debug.assert_eq(output.get(0), 0.25)
}
