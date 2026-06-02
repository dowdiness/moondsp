///|
test "node_accepts_slot: Constant accepts Value0" {
  let node = DspNode::constant(1.0)
  assert_true(node_accepts_slot(node, GraphParamSlot::Value0))
}

///|
test "node_accepts_slot: Constant rejects Value1" {
  let node = DspNode::constant(1.0)
  assert_false(node_accepts_slot(node, GraphParamSlot::Value1))
}

///|
test "node_accepts_slot: Biquad accepts Value0 and Value1" {
  let node = DspNode::biquad(
    input=0,
    mode=BiquadMode::LowPass,
    cutoff_hz=1000.0,
    q=0.707,
  )
  assert_true(node_accepts_slot(node, GraphParamSlot::Value0))
  assert_true(node_accepts_slot(node, GraphParamSlot::Value1))
}

///|
test "node_accepts_slot: Delay accepts Value0 and DelaySamples" {
  let node = DspNode::delay(input=0, max_delay_samples=128, delay_samples=0)
  assert_true(node_accepts_slot(node, GraphParamSlot::Value0))
  assert_true(node_accepts_slot(node, GraphParamSlot::DelaySamples))
  assert_false(node_accepts_slot(node, GraphParamSlot::Value1))
}

///|
test "node_accepts_slot: Output rejects all slots" {
  let node = DspNode::output(0)
  assert_false(node_accepts_slot(node, GraphParamSlot::Value0))
  assert_false(node_accepts_slot(node, GraphParamSlot::DelaySamples))
}

///|
test "node_accepts_slot: FM oscillator rejects Value0" {
  let node = DspNode::oscillator_from(0, Waveform::Sine)
  assert_false(node_accepts_slot(node, GraphParamSlot::Value0))
}

///|
test "node_accepts_slot: non-FM oscillator accepts Value0" {
  let node = DspNode::oscillator(Waveform::Sine, 440.0)
  assert_true(node_accepts_slot(node, GraphParamSlot::Value0))
}

///|
test "DspNode equality treats NaN as a stable authoring sentinel" {
  let left = DspNode::constant(0.0 / 0.0)
  let right = DspNode::constant(0.0 / 0.0)
  assert_true(left == right)
}

///|
test "DspNode equality normalizes signed zero" {
  let left = DspNode::gain(0, -0.0)
  let right = DspNode::gain(0, 0.0)
  assert_true(left == right)
}

///|
test "DspNode equality still distinguishes finite authoring values" {
  let left = DspNode::gain(0, 0.5)
  let right = DspNode::gain(0, 0.75)
  assert_false(left == right)
}
