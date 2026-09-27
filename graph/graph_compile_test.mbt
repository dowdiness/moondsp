///|
test "compiled dsp rejects implicit stereo to mono output" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    @graph.DspNode::constant(UNIT_SAMPLE),
    @graph.DspNode::pan(0, PAN_CENTER),
    @graph.DspNode::output(1),
  ]

  assert_true(
    @graph.Dsp::compile(@graph.AnalyzedGraph::analyze(nodes), context) is None,
  )
}

///|
test "compiled dsp rejects stereo-only nodes" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let stereo_gain_nodes = [
    @graph.DspNode::constant(UNIT_SAMPLE),
    @graph.DspNode::stereo_gain(input=0, amount=HALF_GAIN),
    @graph.DspNode::output(1),
  ]
  let stereo_clip_nodes = [
    @graph.DspNode::constant(UNIT_SAMPLE),
    @graph.DspNode::stereo_clip(input=0, threshold=STEREO_CLIP_THRESHOLD),
    @graph.DspNode::output(1),
  ]
  let stereo_biquad_nodes = [
    @graph.DspNode::constant(UNIT_SAMPLE),
    @graph.DspNode::stereo_biquad(
      input=0,
      mode=BiquadMode::LowPass,
      cutoff_hz=LOWPASS_CUTOFF,
      q=LOWPASS_Q,
    ),
    @graph.DspNode::output(1),
  ]
  let stereo_delay_nodes = [
    @graph.DspNode::constant(UNIT_SAMPLE),
    @graph.DspNode::stereo_delay(
      input=0,
      max_delay_samples=DELAY_CAPACITY,
      delay_samples=DELAY_SAMPLES,
    ),
    @graph.DspNode::output(1),
  ]

  assert_true(
    @graph.Dsp::compile(
      @graph.AnalyzedGraph::analyze(stereo_gain_nodes),
      context,
    )
    is None,
  )
  assert_true(
    @graph.Dsp::compile(
      @graph.AnalyzedGraph::analyze(stereo_clip_nodes),
      context,
    )
    is None,
  )
  assert_true(
    @graph.Dsp::compile(
      @graph.AnalyzedGraph::analyze(stereo_biquad_nodes),
      context,
    )
    is None,
  )
  assert_true(
    @graph.Dsp::compile(
      @graph.AnalyzedGraph::analyze(stereo_delay_nodes),
      context,
    )
    is None,
  )
}

///|
test "compiled dsp rejects non-finite adsr parameters" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    @graph.DspNode::adsr(
      attack_ms=0.0 / 0.0,
      decay_ms=ADSR_DECAY_MS,
      sustain=HALF_GAIN,
      release_ms=10.0,
    ),
    @graph.DspNode::output(0),
  ]

  assert_true(
    @graph.Dsp::compile(@graph.AnalyzedGraph::analyze(nodes), context) is None,
  )
}

///|
test "compiled dsp rejects non-finite constants" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nan_nodes = [
    @graph.DspNode::constant(0.0 / 0.0),
    @graph.DspNode::output(0),
  ]
  let inf_nodes = [
    @graph.DspNode::constant(1.0 / 0.0),
    @graph.DspNode::output(0),
  ]

  assert_true(
    @graph.Dsp::compile(@graph.AnalyzedGraph::analyze(nan_nodes), context)
    is None,
  )
  assert_true(
    @graph.Dsp::compile(@graph.AnalyzedGraph::analyze(inf_nodes), context)
    is None,
  )
}

///|
test "compile_result reports non-finite constant parameter" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [@graph.DspNode::constant(0.0 / 0.0), @graph.DspNode::output(0)]

  match
    @graph.Dsp::compile_result(@graph.AnalyzedGraph::analyze(nodes), context) {
    Err(@graph.GraphCompileError::InvalidParamValue(index, kind, slot, value)) => {
      @debug.assert_eq(index, 0)
      @debug.assert_eq(kind, @graph.DspNodeKind::Constant)
      @debug.assert_eq(slot, @graph.GraphParamSlot::Value0)
      assert_true(value.is_nan())
    }
    _ => fail("expected InvalidParamValue for NaN constant")
  }
}

///|
test "compile_result maps optimized errors back to authoring indices" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    @graph.DspNode::constant(QUARTER_SAMPLE), // eliminated before compile
    @graph.DspNode::constant(0.0 / 0.0),
    @graph.DspNode::output(1),
  ]

  match
    @graph.Dsp::compile_result(@graph.AnalyzedGraph::analyze(nodes), context) {
    Err(@graph.GraphCompileError::InvalidParamValue(index, kind, slot, value)) => {
      @debug.assert_eq(index, 1)
      @debug.assert_eq(kind, @graph.DspNodeKind::Constant)
      @debug.assert_eq(slot, @graph.GraphParamSlot::Value0)
      assert_true(value.is_nan())
    }
    _ => fail("expected authoring-indexed InvalidParamValue")
  }
}

///|
test "compile_result preserves invalid authoring input before optimization" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    @graph.DspNode::constant(QUARTER_SAMPLE), // eliminated before compile
    @graph.DspNode::gain(99, HALF_GAIN),
    @graph.DspNode::output(1),
  ]

  match
    @graph.Dsp::compile_result(@graph.AnalyzedGraph::analyze(nodes), context) {
    Err(@graph.GraphCompileError::InvalidInput(index, kind, slot, input)) => {
      @debug.assert_eq(index, 1)
      @debug.assert_eq(kind, @graph.DspNodeKind::Gain)
      @debug.assert_eq(slot, @graph.GraphTopologyInputSlot::Input0)
      @debug.assert_eq(input, 99)
    }
    _ => fail("expected authoring-indexed InvalidInput")
  }
}

///|
test "compile_result reports missing output" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [@graph.DspNode::constant(QUARTER_SAMPLE)]

  match
    @graph.Dsp::compile_result(@graph.AnalyzedGraph::analyze(nodes), context) {
    Err(@graph.GraphCompileError::MissingOutput(kind)) =>
      @debug.assert_eq(kind, @graph.DspNodeKind::Output)
    _ => fail("expected MissingOutput")
  }
}

///|
test "compiled dsp rejects graphs without a final output node" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [@graph.DspNode::constant(QUARTER_SAMPLE)]

  assert_true(
    @graph.Dsp::compile(@graph.AnalyzedGraph::analyze(nodes), context) is None,
  )
}

///|
test "compiled dsp rejects multiple output nodes" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    @graph.DspNode::constant(QUARTER_SAMPLE),
    @graph.DspNode::output(0),
    @graph.DspNode::output(0),
  ]

  assert_true(
    @graph.Dsp::compile(@graph.AnalyzedGraph::analyze(nodes), context) is None,
  )
}

///|
test "compiled dsp rejects invalid biquad parameters" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    @graph.DspNode::constant(UNIT_SAMPLE),
    @graph.DspNode::biquad(
      input=0,
      mode=BiquadMode::LowPass,
      cutoff_hz=INVALID_NYQUIST_CUTOFF,
      q=LOWPASS_Q,
    ),
    @graph.DspNode::output(1),
  ]

  assert_true(
    @graph.Dsp::compile(@graph.AnalyzedGraph::analyze(nodes), context) is None,
  )
}

///|
test "compiled dsp topologically sorts declarative filter graph" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=LARGE_BLOCK_SIZE,
  )
  let nodes = [
    @graph.DspNode::output(1),
    @graph.DspNode::biquad(
      input=2,
      mode=BiquadMode::LowPass,
      cutoff_hz=LOWPASS_CUTOFF,
      q=LOWPASS_Q,
    ),
    @graph.DspNode::constant(UNIT_SAMPLE),
  ]
  let compiled = @graph.Dsp::compile(
    @graph.AnalyzedGraph::analyze(nodes),
    context,
  ).unwrap()
  let output = AudioBuffer::filled(LARGE_BLOCK_SIZE)

  compiled.process(context, output)

  assert_true(output.get(0) > ZERO_SAMPLE)
  assert_true(output.get(0) < UNIT_SAMPLE)
  assert_true(output.get(7) < UNIT_SAMPLE)
}

///|
test "compiled dsp topologically sorts declarative node order" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    @graph.DspNode::output(1),
    @graph.DspNode::gain(2, HALF_GAIN),
    @graph.DspNode::oscillator(Waveform::Sine, OSCILLATOR_FREQ),
  ]
  let compiled = @graph.Dsp::compile(
    @graph.AnalyzedGraph::analyze(nodes),
    context,
  ).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  compiled.process(context, output)

  @debug.assert_eq(output.get(0), ZERO_SAMPLE)
  assert_true(output.any(sample => sample != ZERO_SAMPLE))
  assert_true(
    output.every(sample => sample >= -HALF_GAIN && sample <= HALF_GAIN),
  )
}

///|
test "compiled dsp optimizes constant subgraph during compilation" {
  // Build: Constant(3) * Constant(4) -> Output
  // After optimization: Constant(12) -> Output (only 2 nodes to compile)
  let nodes : Array[@graph.DspNode] = [
    @graph.DspNode::constant(3.0),
    @graph.DspNode::constant(4.0),
    @graph.DspNode::mul(0, 1),
    @graph.DspNode::output(2),
  ]
  let ctx = DspContext::new(sample_rate=48000.0, block_size=128)
  let compiled = @graph.Dsp::compile(@graph.AnalyzedGraph::analyze(nodes), ctx)
  assert_true(compiled is Some(_))
  // Process and verify output = 12.0 (constant)
  let compiled = compiled.unwrap()
  let buf = AudioBuffer::filled(128)
  compiled.process(ctx, buf)
  @debug.assert_eq(buf.get(0), 12.0)
}

///|
test "compiled dsp compile preserves authoring control indices" {
  let nodes = [
    @graph.DspNode::output(1),
    @graph.DspNode::oscillator(Waveform::Sine, OSCILLATOR_FREQ),
  ]
  let ctx = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let compiled = @graph.Dsp::compile(@graph.AnalyzedGraph::analyze(nodes), ctx).unwrap()

  assert_true(
    compiled.set_param(1, @graph.GraphParamSlot::Value0, 880.0) is Ok(_),
  )
}

///|
test "compiled dsp delay node keeps zero-capacity default as passthrough" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    @graph.DspNode::constant(QUARTER_SAMPLE),
    @graph.DspNode::delay(input=0, max_delay_samples=0),
    @graph.DspNode::output(1),
  ]
  let compiled = @graph.Dsp::compile(
    @graph.AnalyzedGraph::analyze(nodes),
    context,
  ).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  compiled.process(context, output)

  @debug.assert_eq(output.get(0), QUARTER_SAMPLE)
  @debug.assert_eq(output.get(1), QUARTER_SAMPLE)
  @debug.assert_eq(output.get(2), QUARTER_SAMPLE)
  @debug.assert_eq(output.get(3), QUARTER_SAMPLE)
}

///|
test "compiled graphs reject delay feedback outside live supported range" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let mono_nodes = [
    @graph.DspNode::constant(UNIT_SAMPLE),
    @graph.DspNode::delay(
      input=0,
      max_delay_samples=DELAY_CAPACITY,
      delay_samples=DELAY_SAMPLES,
      feedback=CLAMPED_HIGH_DELAY_FEEDBACK,
    ),
    @graph.DspNode::output(1),
  ]
  let stereo_nodes = [
    @graph.DspNode::constant(UNIT_SAMPLE),
    @graph.DspNode::pan(0, PAN_CENTER),
    @graph.DspNode::stereo_delay(
      input=1,
      max_delay_samples=DELAY_CAPACITY,
      delay_samples=DELAY_SAMPLES,
      feedback=CLAMPED_LOW_DELAY_FEEDBACK,
    ),
    @graph.DspNode::stereo_output(2),
  ]

  assert_true(
    @graph.Dsp::compile(@graph.AnalyzedGraph::analyze(mono_nodes), context)
    is None,
  )
  assert_true(
    @graph.StereoDsp::compile(
      @graph.AnalyzedGraph::analyze(stereo_nodes),
      context,
    )
    is None,
  )
}

///|
test "compiled stereo dsp rejects mono direct to stereo output" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    @graph.DspNode::constant(UNIT_SAMPLE),
    @graph.DspNode::stereo_output(0),
  ]

  assert_true(
    @graph.StereoDsp::compile(@graph.AnalyzedGraph::analyze(nodes), context)
    is None,
  )
}

///|
test "compiled stereo dsp rejects stereo post processing after pan" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    @graph.DspNode::constant(UNIT_SAMPLE),
    @graph.DspNode::pan(0, PAN_HARD_LEFT),
    @graph.DspNode::gain(1, HALF_GAIN),
    @graph.DspNode::stereo_output(2),
  ]

  assert_true(
    @graph.StereoDsp::compile(@graph.AnalyzedGraph::analyze(nodes), context)
    is None,
  )
}

///|
test "compiled stereo dsp rejects stereo mixdown before stereo output" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    @graph.DspNode::constant(UNIT_SAMPLE),
    @graph.DspNode::pan(0, PAN_CENTER),
    @graph.DspNode::stereo_mixdown(1),
    @graph.DspNode::stereo_output(2),
  ]

  assert_true(
    @graph.StereoDsp::compile(@graph.AnalyzedGraph::analyze(nodes), context)
    is None,
  )
}

///|
test "compiled stereo dsp rejects internal stereo mixdown roundtrip" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    @graph.DspNode::constant(UNIT_SAMPLE),
    @graph.DspNode::pan(0, PAN_CENTER),
    @graph.DspNode::stereo_mixdown(1),
    @graph.DspNode::gain(2, HALF_GAIN),
    @graph.DspNode::pan(3, PAN_CENTER),
    @graph.DspNode::stereo_output(4),
  ]

  assert_true(
    @graph.StereoDsp::compile(@graph.AnalyzedGraph::analyze(nodes), context)
    is None,
  )
}
