///|
test "replay: Constant+Mul through Eval" {
  let nodes : Array[@moondsp.DspNode] = [
    @moondsp.DspNode::constant(3.0),
    @moondsp.DspNode::constant(4.0),
    @moondsp.DspNode::mul(0, 1),
  ]
  let result : Eval = @moondsp.replay(nodes).unwrap()
  @debug.assert_eq(result.value, 12.0)
}

///|
test "replay: Gain+Clip+Output through Eval" {
  let nodes : Array[@moondsp.DspNode] = [
    @moondsp.DspNode::constant(5.0),
    @moondsp.DspNode::gain(0, 0.5),
    @moondsp.DspNode::clip(1, 2.0),
    @moondsp.DspNode::output(2),
  ]
  let result : Eval = @moondsp.replay(nodes).unwrap()
  // 5.0 * 0.5 = 2.5, clipped to 2.0
  @debug.assert_eq(result.value, 2.0)
}

///|
test "replay: tagless -> GraphBuilder -> replay roundtrip" {
  let a : @moondsp.GraphBuilder = @moondsp.ArithSym::constant(3.0)
  let b : @moondsp.GraphBuilder = @moondsp.ArithSym::constant(4.0)
  let product : @moondsp.GraphBuilder = @moondsp.ArithSym::mul(a, b)
  let result : Eval = @moondsp.replay(product.nodes()).unwrap()
  @debug.assert_eq(result.value, 12.0)
}
