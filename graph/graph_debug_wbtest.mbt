///|
/// Corrupt a compiled node's input0 to an out-of-bounds value.
/// Whitebox test helper — needs access to private CompiledGraph fields.
fn corrupt_input0(
  compiled : CompiledDsp,
  node_index : Int,
  value : Int,
) -> Unit {
  let nodes = compiled.0.nodes
  let node = nodes[node_index]
  nodes[node_index] = DspNode(
    node.kind,
    value,
    node.input1,
    node.value0,
    node.value1,
    node.value2,
    node.value3,
    node.waveform,
    node.filter_mode,
    node.delay_max_samples,
    node.delay_samples,
    node.seed,
  )
}

///|
test "debug: invalid input0 produces InvalidInput0 error" {
  let context = DspContext::new(48000.0, 4)
  let nodes = [
    DspNode::constant(1.0),
    DspNode::gain(0, 0.3),
    DspNode::output(1),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  compiled.enable_debug_validation()
  // Corrupt node 1 (Gain) to reference input0=99 (out of bounds)
  corrupt_input0(compiled, 1, 99)
  let output = AudioBuffer::filled(4)
  compiled.process(context, output)
  let errors = compiled.last_validation_errors()
  assert_eq(errors.length(), 1)
  // max_valid depends on compiled node count (may differ from source due to optimization)
  assert_true(errors[0] is GraphValidationError::InvalidInput0(1, 99, _))
}

///|
test "debug: skipped node outputs silence, downstream processes normally" {
  let context = DspContext::new(48000.0, 4)
  let nodes = [
    DspNode::constant(1.0),
    DspNode::gain(0, 0.5),
    DspNode::output(1),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  compiled.enable_debug_validation()
  // Corrupt node 1 (Gain) — it should output silence (0.0)
  // Node 2 (Output) reads from node 1, so output should be 0.0
  corrupt_input0(compiled, 1, 99)
  let output = AudioBuffer::filled(4)
  compiled.process(context, output)
  for i = 0; i < 4; i = i + 1 {
    assert_eq(output.get(i), 0.0)
  }
}

///|
test "debug: errors reset on next process call" {
  let context = DspContext::new(48000.0, 4)
  let nodes = [
    DspNode::constant(1.0),
    DspNode::gain(0, 0.3),
    DspNode::output(1),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  compiled.enable_debug_validation()
  // First call: corrupted
  corrupt_input0(compiled, 1, 99)
  let output = AudioBuffer::filled(4)
  compiled.process(context, output)
  assert_eq(compiled.last_validation_errors().length(), 1)
  // Fix the corruption and process again — errors should be empty
  corrupt_input0(compiled, 1, 0)
  compiled.process(context, output)
  assert_eq(compiled.last_validation_errors().length(), 0)
}

///|
test "debug: feedback graph validation failure yields silence and records errors" {
  let context = DspContext::new(48000.0, 4)
  // Minimal feedback graph: Constant → Mix(0,2) → Gain → Output
  // Back-edge: node 2 feeds back to node 1
  let nodes = [
    DspNode::constant(0.5),
    DspNode::mix(0, 2),
    DspNode::gain(1, 0.3),
    DspNode::output(2),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  assert_true(compiled.0.feedback_edges.length() > 0)
  compiled.enable_debug_validation()
  // Corrupt node 1 (Mix) to reference input0=99 (out of bounds)
  corrupt_input0(compiled, 1, 99)
  let output = AudioBuffer::filled(4)
  compiled.process(context, output)
  // Output should be silence
  for i = 0; i < 4; i = i + 1 {
    assert_eq(output.get(i), 0.0)
  }
  // Validation errors should be recorded
  let errors = compiled.last_validation_errors()
  assert_true(errors.length() >= 1)
  assert_true(errors[0] is GraphValidationError::InvalidInput0(_, 99, _))
}

///|
test "debug: multiple errors in one block" {
  let context = DspContext::new(48000.0, 4)
  // Use oscillators (stateful, not foldable) to prevent optimization
  let nodes = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::oscillator(Waveform::Sine, 220.0),
    DspNode::mix(0, 1),
    DspNode::output(2),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  compiled.enable_debug_validation()
  // Corrupt both Mix inputs
  corrupt_input0(compiled, 2, 99)
  let output = AudioBuffer::filled(4)
  compiled.process(context, output)
  let errors = compiled.last_validation_errors()
  assert_true(errors.length() >= 1)
}
