///|
/// Prepared-slot steal cost across Delay capacities.
///
/// `note_on_prevalidated_params4_id` reuses the compiled voice and calls
/// `reset_runtime_state`, which resets every DelayLine. These rows exist to
/// show that active-slot steal no longer scales with delay capacity.
fn delay_reset_voice_nodes(capacity : Int) -> Array[@graph.DspNode] {
  let delay_samples = if capacity < 2400 { capacity } else { 2400 }
  [
    @graph.DspNode::oscillator(@dsp.Waveform::Saw, 220.0),
    @graph.DspNode::noise(42U),
    @graph.DspNode::gain(1, 0.2),
    @graph.DspNode::mix(0, 2),
    @graph.DspNode::adsr(
      attack_ms=5.0,
      decay_ms=10.0,
      sustain=0.6,
      release_ms=50.0,
    ),
    @graph.DspNode::mul(3, 4),
    @graph.DspNode::biquad(
      input=5,
      mode=@dsp.BiquadMode::LowPass,
      cutoff_hz=1200.0,
      q=0.707,
    ),
    @graph.DspNode::gain(6, 0.7),
    @graph.DspNode::delay(
      input=7,
      max_delay_samples=capacity,
      delay_samples~,
      feedback=0.3,
    ),
    @graph.DspNode::output(8),
  ]
}

///|
test "bench/voice/prepared_steal_delay_reset" (b : @bench.T) {
  let ctx = @dsp.DspContext::new(sample_rate=48000.0, block_size=128)
  for capacity in [4800, 48000, 480000] {
    let template = @graph.CompiledTemplate::analyze(
      delay_reset_voice_nodes(capacity),
    )
    let pool = BoundVoicePool::new(
      template,
      ctx,
      @graph.ControlBindingBuilder::new(),
      max_voices=1,
    ).unwrap()
    let values = Array::makei(64, i => {
      (
        220.0 + i.to_double(),
        0.1 + i.to_double() / 1000.0,
        900.0 + i.to_double() * 10.0,
        0.3 + i.to_double() / 1000.0,
      )
    })
    let first = values[0]
    ignore(
      pool.note_on_prevalidated_params4_id(
        0,
        @graph.GraphParamSlot::Value0,
        first.0,
        2,
        @graph.GraphParamSlot::Value0,
        first.1,
        6,
        @graph.GraphParamSlot::Value0,
        first.2,
        7,
        @graph.GraphParamSlot::Value0,
        first.3,
        0.0,
      ),
    )
    let mut fi = 0
    b.bench(name="params4_active_steal_cap_\{capacity}", fn() {
      let value = values[fi]
      ignore(
        pool.note_on_prevalidated_params4_id(
          0,
          @graph.GraphParamSlot::Value0,
          value.0,
          2,
          @graph.GraphParamSlot::Value0,
          value.1,
          6,
          @graph.GraphParamSlot::Value0,
          value.2,
          7,
          @graph.GraphParamSlot::Value0,
          value.3,
          0.0,
        ),
      )
      fi = (fi + 1) % 64
    })
  }
}
