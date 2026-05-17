///|
/// PR-2 equivalence pin: CompiledDsp::compile(Array, ctx) must
/// produce block-equivalent output to
/// CompiledDsp::compile_template(CompiledTemplate::analyze(nodes), ctx).
/// This file is DELETED in PR 3 because compile(Array) ceases to
/// exist (it collapses into compile(CompiledTemplate)).
test "A1: compile(Array) and compile_template(analyze) produce identical first block" {
  let nodes : Array[DspNode] = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::output(0),
  ]
  let ctx = DspContext::new(sample_rate=48000.0, block_size=128)
  let compiled_a = CompiledDsp::compile(nodes, ctx).unwrap()
  let compiled_b = CompiledDsp::compile_template(
    CompiledTemplate::analyze(nodes),
    ctx,
  ).unwrap()
  let buf_a = AudioBuffer::filled(128)
  let buf_b = AudioBuffer::filled(128)
  compiled_a.process(ctx, buf_a)
  compiled_b.process(ctx, buf_b)
  for i in 0..<128 {
    @debug.assert_eq(buf_a.get(i), buf_b.get(i))
  }
}

///|
/// A1 adversarial: both paths agree on "missing Output" rejection.
test "A1: compile(Array) and compile_template both reject missing Output with None" {
  let nodes : Array[DspNode] = [DspNode::oscillator(Waveform::Sine, 440.0)]
  let ctx = DspContext::new(sample_rate=48000.0, block_size=128)
  assert_true(CompiledDsp::compile(nodes, ctx) is None)
  assert_true(
    CompiledDsp::compile_template(CompiledTemplate::analyze(nodes), ctx) is None,
  )
}

///|
/// A1 stereo: same equivalence for CompiledStereoDsp.
test "A1: stereo compile(Array) and compile_template(analyze) produce identical first block" {
  let nodes : Array[DspNode] = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::pan(0, 0.0),
    DspNode::stereo_output(1),
  ]
  let ctx = DspContext::new(sample_rate=48000.0, block_size=128)
  let compiled_a = CompiledStereoDsp::compile(nodes, ctx).unwrap()
  let compiled_b = CompiledStereoDsp::compile_template(
    CompiledTemplate::analyze(nodes),
    ctx,
  ).unwrap()
  let left_a = AudioBuffer::filled(128)
  let right_a = AudioBuffer::filled(128)
  let left_b = AudioBuffer::filled(128)
  let right_b = AudioBuffer::filled(128)
  compiled_a.process(ctx, left_a, right_a)
  compiled_b.process(ctx, left_b, right_b)
  for i in 0..<128 {
    @debug.assert_eq(left_a.get(i), left_b.get(i))
    @debug.assert_eq(right_a.get(i), right_b.get(i))
  }
}
