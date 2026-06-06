///|
fn assert_facade_node_matches_model(
  label : String,
  node : DspNode,
  raw : @model.DspNode,
) -> Unit raise {
  guard node.raw() == raw else {
    fail("facade node constructor drift: \{label}")
  }
  guard node.kind() == dsp_node_kind_from_model(raw.kind()) else {
    fail("facade node kind drift: \{label}")
  }
  @debug.assert_eq(node.input0(), raw.input0())
  @debug.assert_eq(node.input1(), raw.input1())
  @debug.assert_eq(node.value0(), raw.value0())
  @debug.assert_eq(node.value1(), raw.value1())
  @debug.assert_eq(node.value2(), raw.value2())
  @debug.assert_eq(node.value3(), raw.value3())
  guard node.waveform() == raw.waveform() else {
    fail("facade node waveform drift: \{label}")
  }
  guard node.filter_mode() == raw.filter_mode() else {
    fail("facade node filter mode drift: \{label}")
  }
  @debug.assert_eq(node.delay_max_samples(), raw.delay_max_samples())
  @debug.assert_eq(node.delay_samples(), raw.delay_samples())
  @debug.assert_eq(node.seed(), raw.seed())
}

///|
fn assert_slot_mapping(
  label : String,
  slot : GraphParamSlot,
  raw : @model.GraphParamSlot,
) -> Unit raise {
  guard slot.to_model() == raw else {
    fail("facade slot to_model drift: \{label}")
  }
  guard graph_param_slot_from_model(raw) == slot else {
    fail("facade slot from_model drift: \{label}")
  }
}

///|
fn assert_facade_control_matches_model(
  label : String,
  control : GraphControl,
  raw : @model.GraphControl,
) -> Unit raise {
  guard control.raw().kind() == raw.kind() else {
    fail("facade control raw kind drift: \{label}")
  }
  guard control.kind() == graph_control_kind_from_model(raw.kind()) else {
    fail("facade control kind drift: \{label}")
  }
  @debug.assert_eq(control.raw().node_index(), raw.node_index())
  @debug.assert_eq(control.node_index(), raw.node_index())
  guard control.raw().slot() == raw.slot() else {
    fail("facade control raw slot drift: \{label}")
  }
  guard control.slot().to_model() == raw.slot() else {
    fail("facade control slot drift: \{label}")
  }
  @debug.assert_eq(control.raw().value(), raw.value())
  @debug.assert_eq(control.value(), raw.value())
}

///|
fn parity_node_cases() -> Array[(String, DspNode, @model.DspNode)] {
  [
    ("constant", DspNode::constant(1.25), @model.DspNode::constant(1.25)),
    (
      "oscillator",
      DspNode::oscillator(Waveform::Saw, 440.0),
      @model.DspNode::oscillator(Waveform::Saw, 440.0),
    ),
    (
      "oscillator_from",
      DspNode::oscillator_from(0, Waveform::Square),
      @model.DspNode::oscillator_from(0, Waveform::Square),
    ),
    ("noise", DspNode::noise(99U), @model.DspNode::noise(99U)),
    (
      "adsr",
      DspNode::adsr(attack_ms=1.0, decay_ms=2.0, sustain=0.5, release_ms=3.0),
      @model.DspNode::adsr(
        attack_ms=1.0,
        decay_ms=2.0,
        sustain=0.5,
        release_ms=3.0,
      ),
    ),
    (
      "biquad",
      DspNode::biquad(
        input=0,
        mode=BiquadMode::HighPass,
        cutoff_hz=1200.0,
        q=0.75,
      ),
      @model.DspNode::biquad(
        input=0,
        mode=BiquadMode::HighPass,
        cutoff_hz=1200.0,
        q=0.75,
      ),
    ),
    (
      "delay explicit",
      DspNode::delay(
        input=0,
        max_delay_samples=64,
        delay_samples=12,
        feedback=0.25,
      ),
      @model.DspNode::delay(
        input=0,
        max_delay_samples=64,
        delay_samples=12,
        feedback=0.25,
      ),
    ),
    (
      "delay default",
      DspNode::delay(input=0, max_delay_samples=64),
      @model.DspNode::delay(input=0, max_delay_samples=64),
    ),
    ("gain", DspNode::gain(0, 0.5), @model.DspNode::gain(0, 0.5)),
    (
      "envelope_gain",
      DspNode::envelope_gain(input=0, envelope=1, amount=0.8),
      @model.DspNode::envelope_gain(input=0, envelope=1, amount=0.8),
    ),
    ("mul", DspNode::mul(0, 1), @model.DspNode::mul(0, 1)),
    ("mix", DspNode::mix(0, 1), @model.DspNode::mix(0, 1)),
    ("clip", DspNode::clip(0, 0.9), @model.DspNode::clip(0, 0.9)),
    ("output", DspNode::output(0), @model.DspNode::output(0)),
    ("pan", DspNode::pan(0, -0.25), @model.DspNode::pan(0, -0.25)),
    (
      "stereo_gain",
      DspNode::stereo_gain(input=0, amount=0.5),
      @model.DspNode::stereo_gain(input=0, amount=0.5),
    ),
    (
      "stereo_clip",
      DspNode::stereo_clip(input=0, threshold=0.9),
      @model.DspNode::stereo_clip(input=0, threshold=0.9),
    ),
    (
      "stereo_biquad",
      DspNode::stereo_biquad(
        input=0,
        mode=BiquadMode::BandPass,
        cutoff_hz=800.0,
        q=0.6,
      ),
      @model.DspNode::stereo_biquad(
        input=0,
        mode=BiquadMode::BandPass,
        cutoff_hz=800.0,
        q=0.6,
      ),
    ),
    (
      "stereo_delay explicit",
      DspNode::stereo_delay(
        input=0,
        max_delay_samples=128,
        delay_samples=24,
        feedback=0.2,
      ),
      @model.DspNode::stereo_delay(
        input=0,
        max_delay_samples=128,
        delay_samples=24,
        feedback=0.2,
      ),
    ),
    (
      "stereo_delay default",
      DspNode::stereo_delay(input=0, max_delay_samples=128),
      @model.DspNode::stereo_delay(input=0, max_delay_samples=128),
    ),
    (
      "stereo_mixdown",
      DspNode::stereo_mixdown(0),
      @model.DspNode::stereo_mixdown(0),
    ),
    (
      "stereo_output",
      DspNode::stereo_output(0),
      @model.DspNode::stereo_output(0),
    ),
  ]
}

///|
fn parity_node_kind_cases() -> Array[(@model.DspNodeKind, DspNodeKind)] {
  [
    (@model.DspNodeKind::Constant, DspNodeKind::Constant),
    (@model.DspNodeKind::Oscillator, DspNodeKind::Oscillator),
    (@model.DspNodeKind::Noise, DspNodeKind::Noise),
    (@model.DspNodeKind::Adsr, DspNodeKind::Adsr),
    (@model.DspNodeKind::Biquad, DspNodeKind::Biquad),
    (@model.DspNodeKind::Delay, DspNodeKind::Delay),
    (@model.DspNodeKind::Gain, DspNodeKind::Gain),
    (@model.DspNodeKind::Mul, DspNodeKind::Mul),
    (@model.DspNodeKind::Mix, DspNodeKind::Mix),
    (@model.DspNodeKind::Clip, DspNodeKind::Clip),
    (@model.DspNodeKind::Output, DspNodeKind::Output),
    (@model.DspNodeKind::Pan, DspNodeKind::Pan),
    (@model.DspNodeKind::StereoGain, DspNodeKind::StereoGain),
    (@model.DspNodeKind::StereoClip, DspNodeKind::StereoClip),
    (@model.DspNodeKind::StereoBiquad, DspNodeKind::StereoBiquad),
    (@model.DspNodeKind::StereoDelay, DspNodeKind::StereoDelay),
    (@model.DspNodeKind::StereoMixDown, DspNodeKind::StereoMixDown),
    (@model.DspNodeKind::StereoOutput, DspNodeKind::StereoOutput),
  ]
}

///|
fn parity_slot_cases() -> Array[(String, GraphParamSlot, @model.GraphParamSlot)] {
  [
    ("Value0", GraphParamSlot::Value0, @model.GraphParamSlot::Value0),
    ("Value1", GraphParamSlot::Value1, @model.GraphParamSlot::Value1),
    ("Value2", GraphParamSlot::Value2, @model.GraphParamSlot::Value2),
    ("Value3", GraphParamSlot::Value3, @model.GraphParamSlot::Value3),
    (
      "DelaySamples",
      GraphParamSlot::DelaySamples,
      @model.GraphParamSlot::DelaySamples,
    ),
  ]
}

///|
fn parity_control_cases() -> Array[(String, GraphControl, @model.GraphControl)] {
  [
    ("gate_on", GraphControl::gate_on(2), @model.GraphControl::gate_on(2)),
    ("gate_off", GraphControl::gate_off(3), @model.GraphControl::gate_off(3)),
    (
      "set_param",
      GraphControl::set_param(4, GraphParamSlot::Value1, 0.25),
      @model.GraphControl::set_param(4, @model.GraphParamSlot::Value1, 0.25),
    ),
  ]
}

///|
test "graph facade constructors mirror internal model constructors" {
  for item in parity_node_cases() {
    let (label, node, raw) = item
    assert_facade_node_matches_model(label, node, raw)
  }
}

///|
test "graph facade enum conversions mirror internal model variants" {
  for item in parity_node_kind_cases() {
    let (raw, expected) = item
    assert_true(dsp_node_kind_from_model(raw) == expected)
  }
  for item in parity_slot_cases() {
    let (label, slot, raw) = item
    assert_slot_mapping(label, slot, raw)
  }
}

///|
test "graph facade controls mirror internal model controls" {
  for item in parity_control_cases() {
    let (label, control, raw) = item
    assert_facade_control_matches_model(label, control, raw)
  }
}

///|
test "graph facade node slot and trait behavior delegates to internal model" {
  for item in parity_node_cases() {
    let (_, node, _) = item
    for slot_item in parity_slot_cases() {
      let (_, slot, raw_slot) = slot_item
      @debug.assert_eq(
        node_accepts_slot(node, slot),
        @model.node_accepts_slot(node.raw(), raw_slot),
      )
    }
    @debug.assert_eq(node.signal_shape(), @model.node_signal_shape(node.raw()))
    @debug.assert_eq(node.is_foldable(), @model.node_is_foldable(node.raw()))
    @debug.assert_eq(
      node.fold_value(2.0, 3.0),
      @model.node_fold_value(node.raw(), 2.0, 3.0),
    )
    @debug.assert_eq(node.is_stateful(), @model.node_is_stateful(node.raw()))
    @debug.assert_eq(
      node.can_insert_after(),
      @model.node_can_insert_after(node.raw()),
    )
    @debug.assert_eq(node.can_delete(), @model.node_can_delete(node.raw()))
  }
}
