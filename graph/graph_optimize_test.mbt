///|
test "fold constants: Mul(Constant, Constant) -> Constant" {
  let nodes : Array[DspNode] = [
    DspNode::constant(3.0),
    DspNode::constant(4.0),
    DspNode::mul(0, 1),
    DspNode::output(2),
  ]
  let (optimized, _) = optimize_graph(nodes)
  assert_eq(optimized.length(), 2) // Constant(12) + Output
  assert_true(optimized[0].kind is DspNodeKind::Constant)
  assert_eq(optimized[0].value0, 12.0)
}

///|
test "fold constants: Gain(Constant, amount) -> Constant" {
  let nodes : Array[DspNode] = [
    DspNode::constant(10.0),
    DspNode::gain(0, 0.5),
    DspNode::output(1),
  ]
  let (optimized, _) = optimize_graph(nodes)
  assert_eq(optimized.length(), 2) // Constant(5) + Output
  assert_true(optimized[0].kind is DspNodeKind::Constant)
  assert_eq(optimized[0].value0, 5.0)
}

///|
test "fold constants: stateful nodes not folded" {
  let nodes : Array[DspNode] = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::output(0),
  ]
  let (optimized, _) = optimize_graph(nodes)
  assert_eq(optimized.length(), 2) // unchanged
}

///|
test "dead-node elimination: removes unreachable nodes" {
  let nodes : Array[DspNode] = [
    DspNode::constant(1.0), // 0: reachable
    DspNode::constant(999.0), // 1: dead (not referenced)
    DspNode::output(0), // 2: reachable
  ]
  let (optimized, _) = optimize_graph(nodes)
  assert_eq(optimized.length(), 2) // Constant(1) + Output
}

///|
test "optimize: range subgraph with constant input collapses" {
  // range(constant(-1.0), 200, 400) should fold to ~Constant(200.0)
  let input : GraphBuilder = ArithSym::constant(-1.0)
  let mapped = range(input, 200.0, 400.0)
  let output : GraphBuilder = DspSym::output(mapped)
  let (optimized, _) = optimize_graph(output.nodes())
  assert_true(optimized.length() < output.nodes().length())
}

///|
test "optimize: index_map tracks original to optimized indices" {
  let nodes : Array[DspNode] = [
    DspNode::constant(3.0), // 0 -> folds away
    DspNode::constant(4.0), // 1 -> folds away
    DspNode::mul(0, 1), // 2 -> becomes Constant(12.0) at index 0
    DspNode::output(2), // 3 -> Output at index 1
  ]
  let (_, index_map) = optimize_graph(nodes)
  // Original indices 0, 1 should map to -1 (eliminated)
  // Original index 2 should map to 0 (the folded Constant)
  // Original index 3 should map to 1 (the Output)
  assert_eq(index_map[0], -1)
  assert_eq(index_map[1], -1)
  assert_eq(index_map[2], 0)
  assert_eq(index_map[3], 1)
}
