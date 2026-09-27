///|
test "debug: off by default" {
  let context = DspContext::new(sample_rate=48000.0, block_size=4)
  let nodes = [@graph.DspNode::constant(1.0), @graph.DspNode::output(0)]
  let compiled = @graph.Dsp::compile(
    @graph.AnalyzedGraph::analyze(nodes),
    context,
  ).unwrap()
  @debug.assert_eq(compiled.last_validation_errors().length(), 0)
}

///|
test "debug: enable and disable toggle" {
  let context = DspContext::new(sample_rate=48000.0, block_size=4)
  let nodes = [@graph.DspNode::constant(1.0), @graph.DspNode::output(0)]
  let compiled = @graph.Dsp::compile(
    @graph.AnalyzedGraph::analyze(nodes),
    context,
  ).unwrap()
  compiled.enable_debug_validation()
  let output = AudioBuffer::filled(4)
  compiled.process(context, output)
  @debug.assert_eq(compiled.last_validation_errors().length(), 0)
  compiled.disable_debug_validation()
  compiled.process(context, output)
  @debug.assert_eq(compiled.last_validation_errors().length(), 0)
}

///|
test "debug: valid graph produces no errors" {
  let context = DspContext::new(sample_rate=48000.0, block_size=4)
  let nodes = [
    @graph.DspNode::oscillator(Waveform::Sine, 440.0),
    @graph.DspNode::gain(0, 0.3),
    @graph.DspNode::output(1),
  ]
  let compiled = @graph.Dsp::compile(
    @graph.AnalyzedGraph::analyze(nodes),
    context,
  ).unwrap()
  compiled.enable_debug_validation()
  let output = AudioBuffer::filled(4)
  compiled.process(context, output)
  @debug.assert_eq(compiled.last_validation_errors().length(), 0)
  // Sample 1+ should be non-zero (sine at 440Hz, sample 0 is sin(0)=0)
  assert_true(output.get(1) != 0.0)
}

///|
test "debug: errors reset each process call" {
  let context = DspContext::new(sample_rate=48000.0, block_size=4)
  let nodes = [@graph.DspNode::constant(1.0), @graph.DspNode::output(0)]
  let compiled = @graph.Dsp::compile(
    @graph.AnalyzedGraph::analyze(nodes),
    context,
  ).unwrap()
  compiled.enable_debug_validation()
  let output = AudioBuffer::filled(4)
  compiled.process(context, output)
  @debug.assert_eq(compiled.last_validation_errors().length(), 0)
  compiled.process(context, output)
  @debug.assert_eq(compiled.last_validation_errors().length(), 0)
}

///|
test "debug stereo: valid graph produces no errors" {
  let context = DspContext::new(sample_rate=48000.0, block_size=4)
  let nodes = [
    @graph.DspNode::constant(1.0),
    @graph.DspNode::pan(0, 0.0),
    @graph.DspNode::stereo_output(1),
  ]
  let compiled = @graph.StereoDsp::compile(
    @graph.AnalyzedGraph::analyze(nodes),
    context,
  ).unwrap()
  compiled.enable_debug_validation()
  let left = AudioBuffer::filled(4)
  let right = AudioBuffer::filled(4)
  compiled.process(context, left, right)
  @debug.assert_eq(compiled.last_validation_errors().length(), 0)
}
