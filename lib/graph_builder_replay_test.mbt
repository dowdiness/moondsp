///|
test "replay: Constant+Mul through Eval" {
  let nodes : Array[@lib.DspNode] = [
    @lib.DspNode::constant(3.0),
    @lib.DspNode::constant(4.0),
    @lib.DspNode::mul(0, 1),
  ]
  let result : Eval = @lib.replay(nodes).unwrap()
  assert_eq(result.value, 12.0)
}

///|
test "replay: Gain+Clip+Output through Eval" {
  let nodes : Array[@lib.DspNode] = [
    @lib.DspNode::constant(5.0),
    @lib.DspNode::gain(0, 0.5),
    @lib.DspNode::clip(1, 2.0),
    @lib.DspNode::output(2),
  ]
  let result : Eval = @lib.replay(nodes).unwrap()
  // 5.0 * 0.5 = 2.5, clipped to 2.0
  assert_eq(result.value, 2.0)
}

///|
test "replay: tagless -> GraphBuilder -> replay roundtrip" {
  let a : @lib.GraphBuilder = @lib.ArithSym::constant(3.0)
  let b : @lib.GraphBuilder = @lib.ArithSym::constant(4.0)
  let product : @lib.GraphBuilder = @lib.ArithSym::mul(a, b)
  let result : Eval = @lib.replay(product.nodes()).unwrap()
  assert_eq(result.value, 12.0)
}
