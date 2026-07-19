///|
fn analyzed_optimized_graph(
  nodes : Array[@model.DspNode],
) -> (Array[@model.DspNode], FixedArray[Int]) {
  let analyzed = CompiledTemplate::analyze(nodes)
  (analyzed.optimized_nodes(), analyzed.index_map())
}

///|
test "fold constants: Mul(Constant, Constant) -> Constant" {
  let nodes : Array[@model.DspNode] = [
    @model.DspNode::constant(3.0),
    @model.DspNode::constant(4.0),
    @model.DspNode::mul(0, 1),
    @model.DspNode::output(2),
  ]
  let (optimized, _) = analyzed_optimized_graph(nodes)
  @debug.assert_eq(optimized.length(), 2) // Constant(12) + Output
  assert_true(optimized[0].kind() is @model.DspNodeKind::Constant)
  @debug.assert_eq(optimized[0].value0(), 12.0)
}

///|
test "fold constants: Gain preserves runtime-control identity" {
  let nodes : Array[@model.DspNode] = [
    @model.DspNode::constant(10.0),
    @model.DspNode::gain(0, 0.5),
    @model.DspNode::output(1),
  ]
  let (optimized, index_map) = analyzed_optimized_graph(nodes)
  @debug.assert_eq(optimized.length(), 3)
  assert_true(optimized[0].kind() is @model.DspNodeKind::Constant)
  assert_true(optimized[1].kind() is @model.DspNodeKind::Gain)
  assert_true(optimized[2].kind() is @model.DspNodeKind::Output)
  @debug.assert_eq(index_map[0], 0)
  @debug.assert_eq(index_map[1], 1)
  @debug.assert_eq(index_map[2], 2)
}

///|
test "fold constants: Clip preserves runtime-control identity" {
  let nodes : Array[@model.DspNode] = [
    @model.DspNode::constant(10.0),
    @model.DspNode::clip(0, 3.0),
    @model.DspNode::output(1),
  ]
  let (optimized, index_map) = analyzed_optimized_graph(nodes)
  @debug.assert_eq(optimized.length(), 3)
  assert_true(optimized[0].kind() is @model.DspNodeKind::Constant)
  assert_true(optimized[1].kind() is @model.DspNodeKind::Clip)
  assert_true(optimized[2].kind() is @model.DspNodeKind::Output)
  @debug.assert_eq(index_map[0], 0)
  @debug.assert_eq(index_map[1], 1)
  @debug.assert_eq(index_map[2], 2)
}

///|
test "fold constants: pure arithmetic folds beneath retained Gain" {
  let nodes : Array[@model.DspNode] = [
    @model.DspNode::constant(3.0),
    @model.DspNode::constant(4.0),
    @model.DspNode::mul(0, 1),
    @model.DspNode::gain(2, 0.5),
    @model.DspNode::output(3),
  ]
  let (optimized, index_map) = analyzed_optimized_graph(nodes)
  @debug.assert_eq(optimized.length(), 3)
  assert_true(optimized[0].kind() is @model.DspNodeKind::Constant)
  @debug.assert_eq(optimized[0].value0(), 12.0)
  assert_true(optimized[1].kind() is @model.DspNodeKind::Gain)
  assert_true(optimized[2].kind() is @model.DspNodeKind::Output)
  @debug.assert_eq(index_map[0], -1)
  @debug.assert_eq(index_map[1], -1)
  @debug.assert_eq(index_map[2], 0)
  @debug.assert_eq(index_map[3], 1)
  @debug.assert_eq(index_map[4], 2)
}

///|
test "fold constants: stateful nodes not folded" {
  let nodes : Array[@model.DspNode] = [
    @model.DspNode::oscillator(@dsp.Waveform::Sine, 440.0),
    @model.DspNode::output(0),
  ]
  let (optimized, _) = analyzed_optimized_graph(nodes)
  @debug.assert_eq(optimized.length(), 2) // unchanged
}

///|
test "dead-node elimination: removes unreachable nodes" {
  let nodes : Array[@model.DspNode] = [
    @model.DspNode::constant(1.0), // 0: reachable
    @model.DspNode::constant(999.0), // 1: dead (not referenced)
    @model.DspNode::output(0), // 2: reachable
  ]
  let (optimized, _) = analyzed_optimized_graph(nodes)
  @debug.assert_eq(optimized.length(), 2) // Constant(1) + Output
}

///|
test "optimize: multi-node constant subgraph collapses" {
  let nodes : Array[@model.DspNode] = [
    @model.DspNode::constant(-1.0),
    @model.DspNode::constant(200.0),
    @model.DspNode::constant(300.0),
    @model.DspNode::mul(0, 2),
    @model.DspNode::mix(1, 3),
    @model.DspNode::output(4),
  ]
  let (optimized, _) = analyzed_optimized_graph(nodes)
  assert_true(optimized.length() < nodes.length())
}

///|
test "optimize: index_map tracks original to optimized indices" {
  let nodes : Array[@model.DspNode] = [
    @model.DspNode::constant(3.0), // 0 -> folds away
    @model.DspNode::constant(4.0), // 1 -> folds away
    @model.DspNode::mul(0, 1), // 2 -> becomes Constant(12.0) at index 0
    @model.DspNode::output(2), // 3 -> Output at index 1
  ]
  let (_, index_map) = analyzed_optimized_graph(nodes)
  // Original indices 0, 1 should map to -1 (eliminated)
  // Original index 2 should map to 0 (the folded Constant)
  // Original index 3 should map to 1 (the Output)
  @debug.assert_eq(index_map[0], -1)
  @debug.assert_eq(index_map[1], -1)
  @debug.assert_eq(index_map[2], 0)
  @debug.assert_eq(index_map[3], 1)
}
