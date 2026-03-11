///|
test "compiled dsp renders a constant graph" {
  let context = DspContext::new(48000.0, 4)
  let nodes = [DspNode::constant(0.25), DspNode::output(0)]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(4)

  compiled.process(context, output)

  assert_eq(output.get(0), 0.25)
  assert_eq(output.get(1), 0.25)
  assert_eq(output.get(2), 0.25)
  assert_eq(output.get(3), 0.25)
}

///|
test "compiled dsp renders an oscillator gain clip chain" {
  let context = DspContext::new(48000.0, 8)
  let nodes = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::gain(0, 0.5),
    DspNode::clip(1, 0.2),
    DspNode::output(2),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(8)

  compiled.process(context, output)

  assert_eq(output.get(0), 0.0)
  assert_true(output.as_fixed_array().any(sample => sample != 0.0))
  assert_true(
    output.as_fixed_array().every(sample => sample >= -0.2 && sample <= 0.2),
  )
}

///|
test "compiled dsp mixes two constants" {
  let context = DspContext::new(48000.0, 4)
  let nodes = [
    DspNode::constant(0.25),
    DspNode::constant(-0.1),
    DspNode::mix(0, 1),
    DspNode::output(2),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(4)

  compiled.process(context, output)

  assert_eq(output.get(0), 0.15)
  assert_eq(output.get(1), 0.15)
  assert_eq(output.get(2), 0.15)
  assert_eq(output.get(3), 0.15)
}

///|
test "compiled dsp noise graph stays bounded and non-zero" {
  let context = DspContext::new(48000.0, 8)
  let nodes = [DspNode::noise(123U), DspNode::output(0)]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(8)

  compiled.process(context, output)

  assert_true(output.as_fixed_array().any(sample => sample != 0.0))
  assert_true(
    output.as_fixed_array().every(sample => sample >= -1.0 && sample <= 1.0),
  )
}

///|
test "compiled dsp rejects non-finite constants" {
  let context = DspContext::new(48000.0, 4)
  let nan_nodes = [DspNode::constant(0.0 / 0.0), DspNode::output(0)]
  let inf_nodes = [DspNode::constant(1.0 / 0.0), DspNode::output(0)]

  assert_true(CompiledDsp::compile(nan_nodes, context) is None)
  assert_true(CompiledDsp::compile(inf_nodes, context) is None)
}

///|
test "compiled dsp silences when runtime block exceeds compiled capacity" {
  let compile_context = DspContext::new(48000.0, 4)
  let runtime_context = DspContext::new(48000.0, 8)
  let nodes = [DspNode::constant(0.25), DspNode::output(0)]
  let compiled = CompiledDsp::compile(nodes, compile_context).unwrap()
  let output = AudioBuffer::filled(8, init=1.0)

  compiled.process(runtime_context, output)

  assert_true(output.as_fixed_array().every(sample => sample == 0.0))
}

///|
test "compiled dsp rejects forward references" {
  let context = DspContext::new(48000.0, 4)
  let nodes = [DspNode::gain(1, 0.5), DspNode::output(0)]

  assert_true(CompiledDsp::compile(nodes, context) is None)
}

///|
test "compiled dsp rejects graphs without a final output node" {
  let context = DspContext::new(48000.0, 4)
  let nodes = [DspNode::constant(0.25)]

  assert_true(CompiledDsp::compile(nodes, context) is None)
}
