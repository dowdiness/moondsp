///|
test "edit correspondence follows sequential compaction and insertion" {
  let nodes = [
    DspNode::constant(1.0),
    DspNode::gain(0, 0.5),
    DspNode::gain(1, 0.25),
    DspNode::output(2),
  ]
  let result = apply_topology_edits(nodes, [
    GraphTopologyEdit::delete_node(1, 2, GraphTopologyInputSlot::Input0, 0),
    GraphTopologyEdit::insert_node(
      2,
      GraphTopologyInputSlot::Input0,
      DspNode::gain(-1, 0.75),
    ),
    GraphTopologyEdit::delete_node(1, 3, GraphTopologyInputSlot::Input0, 0),
  ]).unwrap()
  assert_eq(result.old_to_new(), FixedArray::from_array([0, -1, -1, 1]))
  let final_nodes = result.nodes()
  assert_eq(final_nodes.length(), 3)
  assert_eq(final_nodes[1].input0(), 2)
  assert_eq(final_nodes[2].input0(), 0)
  assert_eq(nodes[3].input0(), 2)
  assert_eq(nodes[2].input0(), 1)
}

///|
test "rewiring signal input preserves envelope gain modulation" {
  let nodes = [
    DspNode::constant(1.0),
    DspNode::adsr(attack_ms=1.0, decay_ms=2.0, sustain=0.5, release_ms=3.0),
    DspNode::envelope_gain(input=0, envelope=1, amount=0.75),
    DspNode::constant(2.0),
    DspNode::output(2),
  ]
  let result = apply_topology_edit_result(
    nodes,
    GraphTopologyEdit::rewire_input(2, GraphTopologyInputSlot::Input0, 3),
  ).unwrap()
  let edited = result.nodes()
  assert_eq(edited[2].input0(), 3)
  assert_eq(edited[2].input1(), 1)
  assert_eq(edited[2].value0(), 0.75)
  assert_eq(nodes[2].input0(), 0)
}
