///|
test "replay: Constant+Mul through Eval" {
  let nodes : Array[DspNode] = [
    DspNode::constant(3.0),
    DspNode::constant(4.0),
    DspNode::mul(0, 1),
  ]
  let result : Eval = replay(nodes).unwrap()
  assert_eq(result.value, 12.0)
}

///|
test "replay: Gain+Clip+Output through Eval" {
  let nodes : Array[DspNode] = [
    DspNode::constant(5.0),
    DspNode::gain(0, 0.5),
    DspNode::clip(1, 2.0),
    DspNode::output(2),
  ]
  let result : Eval = replay(nodes).unwrap()
  // 5.0 * 0.5 = 2.5, clipped to 2.0
  assert_eq(result.value, 2.0)
}

///|
test "replay: tagless -> GraphBuilder -> replay roundtrip" {
  let a : GraphBuilder = ArithSym::constant(3.0)
  let b : GraphBuilder = ArithSym::constant(4.0)
  let product : GraphBuilder = ArithSym::mul(a, b)
  let result : Eval = replay(product.nodes()).unwrap()
  assert_eq(result.value, 12.0)
}
