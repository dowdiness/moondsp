///|
test "public graph facade smoke test covers source-facing graph API" {
  let nodes : Array[@graph.DspNode] = [
    @graph.DspNode::constant(1.0),
    @graph.DspNode::gain(0, 0.25),
    @graph.DspNode::output(1),
  ]
  let template = @graph.AnalyzedGraph::analyze(nodes)
  @debug.assert_eq(template.orphan_adsr_count(), 0)

  let control = @graph.GraphControl::set_param(
    1,
    @graph.GraphParamSlot::Value0,
    0.5,
  )
  assert_true(control.kind() is @graph.GraphControlKind::SetParam)
  @debug.assert_eq(control.node_index(), 1)
  assert_true(control.slot() is @graph.GraphParamSlot::Value0)
  @debug.assert_eq(control.value(), 0.5)

  assert_true(nodes[1].kind() is @graph.DspNodeKind::Gain)
  assert_true(@graph.node_accepts_slot(nodes[1], @graph.GraphParamSlot::Value0))
  assert_true(nodes[1].can_delete())
}
