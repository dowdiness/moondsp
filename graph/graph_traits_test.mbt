///|
test "NodeFoldable: Constant is foldable" {
  let node = @graph.DspNode::constant(42.0)
  assert_true(node.is_foldable())
}

///|
test "NodeFoldable: Oscillator is not foldable" {
  let node = @graph.DspNode::oscillator(Waveform::Sine, 440.0)
  assert_false(node.is_foldable())
}

///|
test "NodeStateful: Biquad is stateful" {
  let node = @graph.DspNode::biquad(
    input=0,
    mode=BiquadMode::LowPass,
    cutoff_hz=1000.0,
    q=0.707,
  )
  assert_true(node.is_stateful())
}

///|
test "NodeStateful: Gain is not stateful" {
  let node = @graph.DspNode::gain(0, 0.5)
  assert_false(node.is_stateful())
}

///|
test "NodeFoldable: fold Mul evaluates 3.0 * 4.0 = 12.0" {
  let node = @graph.DspNode::mul(0, 1)
  @debug.assert_eq(node.fold_value(3.0, 4.0), 12.0)
}

///|
test "NodeFoldable: fold Clip clamps 5.0 at threshold 3.0 = 3.0" {
  let node = @graph.DspNode::clip(0, 3.0)
  @debug.assert_eq(node.fold_value(5.0, 0.0), 3.0)
}

///|
test "NodeSpanning: Gain has mono shape (0)" {
  let node = @graph.DspNode::gain(0, 0.5)
  @debug.assert_eq(node.signal_shape(), 0)
}

///|
test "NodeSpanning: Pan has stereo shape (1)" {
  let node = @graph.DspNode::pan(0, 0.0)
  @debug.assert_eq(node.signal_shape(), 1)
}

///|
test "NodeEditable: Output cannot insert after" {
  let node = @graph.DspNode::output(0)
  assert_false(node.can_insert_after())
}

///|
test "NodeEditable: Gain can be deleted (unary)" {
  let node = @graph.DspNode::gain(0, 0.5)
  assert_true(node.can_delete())
}

///|
test "NodeEditable: Mul cannot be deleted (binary)" {
  let node = @graph.DspNode::mul(0, 1)
  assert_false(node.can_delete())
}
