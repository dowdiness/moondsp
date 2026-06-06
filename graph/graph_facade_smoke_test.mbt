///|
test "public graph facade smoke test covers source-facing graph API" {
  let nodes : Array[DspNode] = [
    DspNode::constant(1.0),
    DspNode::gain(0, 0.25),
    DspNode::output(1),
  ]
  let template = CompiledTemplate::analyze(nodes)
  @debug.assert_eq(template.orphan_adsr_count(), 0)

  let control = GraphControl::set_param(1, GraphParamSlot::Value0, 0.5)
  assert_true(control.kind() is GraphControlKind::SetParam)
  @debug.assert_eq(control.node_index(), 1)
  assert_true(control.slot() is GraphParamSlot::Value0)
  @debug.assert_eq(control.value(), 0.5)

  assert_true(nodes[1].kind() is DspNodeKind::Gain)
  assert_true(node_accepts_slot(nodes[1], GraphParamSlot::Value0))
  assert_true(nodes[1].can_delete())
}
