///|
test "node_accepts_slot: Constant accepts Value0" {
  let node = @graph.DspNode::constant(1.0)
  assert_true(@graph.node_accepts_slot(node, @graph.GraphParamSlot::Value0))
}

///|
test "node_accepts_slot: Constant rejects Value1" {
  let node = @graph.DspNode::constant(1.0)
  assert_false(@graph.node_accepts_slot(node, @graph.GraphParamSlot::Value1))
}

///|
test "node_accepts_slot: Biquad accepts Value0 and Value1" {
  let node = @graph.DspNode::biquad(
    input=0,
    mode=BiquadMode::LowPass,
    cutoff_hz=1000.0,
    q=0.707,
  )
  assert_true(@graph.node_accepts_slot(node, @graph.GraphParamSlot::Value0))
  assert_true(@graph.node_accepts_slot(node, @graph.GraphParamSlot::Value1))
}

///|
test "node_accepts_slot: Delay accepts Value0 and DelaySamples" {
  let node = @graph.DspNode::delay(
    input=0,
    max_delay_samples=128,
    delay_samples=0,
  )
  assert_true(@graph.node_accepts_slot(node, @graph.GraphParamSlot::Value0))
  assert_true(
    @graph.node_accepts_slot(node, @graph.GraphParamSlot::DelaySamples),
  )
  assert_false(@graph.node_accepts_slot(node, @graph.GraphParamSlot::Value1))
}

///|
test "node_accepts_slot: Output rejects all slots" {
  let node = @graph.DspNode::output(0)
  assert_false(@graph.node_accepts_slot(node, @graph.GraphParamSlot::Value0))
  assert_false(
    @graph.node_accepts_slot(node, @graph.GraphParamSlot::DelaySamples),
  )
}

///|
test "node_accepts_slot: FM oscillator rejects Value0" {
  let node = @graph.DspNode::oscillator_from(0, Waveform::Sine)
  assert_false(@graph.node_accepts_slot(node, @graph.GraphParamSlot::Value0))
}

///|
test "node_accepts_slot: non-FM oscillator accepts Value0" {
  let node = @graph.DspNode::oscillator(Waveform::Sine, 440.0)
  assert_true(@graph.node_accepts_slot(node, @graph.GraphParamSlot::Value0))
}

///|
test "DspNode equality treats NaN as a stable authoring sentinel" {
  let left = @graph.DspNode::constant(0.0 / 0.0)
  let right = @graph.DspNode::constant(0.0 / 0.0)
  assert_true(left == right)
}

///|
test "DspNode equality normalizes signed zero" {
  let left = @graph.DspNode::gain(0, -0.0)
  let right = @graph.DspNode::gain(0, 0.0)
  assert_true(left == right)
}

///|
test "DspNode equality still distinguishes finite authoring values" {
  let left = @graph.DspNode::gain(0, 0.5)
  let right = @graph.DspNode::gain(0, 0.75)
  assert_false(left == right)
}
