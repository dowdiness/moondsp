///|
test "debug: off by default" {
  let context = DspContext::new(sample_rate=48000.0, block_size=4)
  let nodes = [DspNode::constant(1.0), DspNode::output(0)]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  assert_eq(compiled.last_validation_errors().length(), 0)
}

///|
test "debug: enable and disable toggle" {
  let context = DspContext::new(sample_rate=48000.0, block_size=4)
  let nodes = [DspNode::constant(1.0), DspNode::output(0)]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  compiled.enable_debug_validation()
  let output = AudioBuffer::filled(4)
  compiled.process(context, output)
  assert_eq(compiled.last_validation_errors().length(), 0)
  compiled.disable_debug_validation()
  compiled.process(context, output)
  assert_eq(compiled.last_validation_errors().length(), 0)
}

///|
test "debug: valid graph produces no errors" {
  let context = DspContext::new(sample_rate=48000.0, block_size=4)
  let nodes = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::gain(0, 0.3),
    DspNode::output(1),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  compiled.enable_debug_validation()
  let output = AudioBuffer::filled(4)
  compiled.process(context, output)
  assert_eq(compiled.last_validation_errors().length(), 0)
  // Sample 1+ should be non-zero (sine at 440Hz, sample 0 is sin(0)=0)
  assert_true(output.get(1) != 0.0)
}

///|
test "debug: errors reset each process call" {
  let context = DspContext::new(sample_rate=48000.0, block_size=4)
  let nodes = [DspNode::constant(1.0), DspNode::output(0)]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  compiled.enable_debug_validation()
  let output = AudioBuffer::filled(4)
  compiled.process(context, output)
  assert_eq(compiled.last_validation_errors().length(), 0)
  compiled.process(context, output)
  assert_eq(compiled.last_validation_errors().length(), 0)
}

///|
test "debug stereo: valid graph produces no errors" {
  let context = DspContext::new(sample_rate=48000.0, block_size=4)
  let nodes = [
    DspNode::constant(1.0),
    DspNode::pan(0, 0.0),
    DspNode::stereo_output(1),
  ]
  let compiled = CompiledStereoDsp::compile(nodes, context).unwrap()
  compiled.enable_debug_validation()
  let left = AudioBuffer::filled(4)
  let right = AudioBuffer::filled(4)
  compiled.process(context, left, right)
  assert_eq(compiled.last_validation_errors().length(), 0)
}
