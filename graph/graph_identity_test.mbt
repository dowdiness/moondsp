///|
fn gid(value : String) -> @identity.GraphNodeId {
  let result = try? @identity.GraphNodeId::from_string(value)
  match result {
    Ok(id) => id
    Err(_) => abort("expected valid graph node id")
  }
}

///|
fn unwrap_graph_doc(
  result : Result[GraphTemplateDoc, GraphTemplateDocError],
) -> GraphTemplateDoc {
  match result {
    Ok(doc) => doc
    Err(error) => abort("expected graph template doc, got \{error}")
  }
}

///|
fn unwrap_graph_control(control : GraphControl?) -> GraphControl {
  match control {
    Some(control) => control
    None => abort("expected graph control")
  }
}

///|
fn unwrap_binding_builder(
  builder : ControlBindingBuilder?,
) -> ControlBindingBuilder {
  match builder {
    Some(builder) => builder
    None => abort("expected control binding builder")
  }
}

///|
fn unwrap_graph_node(node : DspNode?) -> DspNode {
  match node {
    Some(node) => node
    None => abort("expected graph node")
  }
}

///|
fn identity_graph_nodes() -> Array[DspNode] {
  [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::gain(0, 0.5),
    DspNode::output(1),
  ]
}

///|
fn identity_graph_ids() -> Array[@identity.GraphNodeId] {
  [gid("osc"), gid("gain"), gid("out")]
}

///|
fn identity_graph_doc() -> GraphTemplateDoc {
  unwrap_graph_doc(
    try? GraphTemplateDoc::from_nodes(
      ids=identity_graph_ids(),
      nodes=identity_graph_nodes(),
    ),
  )
}

///|
test "GraphTemplateDoc maps stable ids to controls, bindings, and compile" {
  let doc = identity_graph_doc()
  let index_map = doc.index_map()
  inspect(doc.revision().value(), content="0")
  inspect(index_map.revision().value(), content="0")
  match index_map.node_index(gid("gain")) {
    Some(index) => inspect(index, content="1")
    None => fail("expected gain index")
  }
  let control = unwrap_graph_control(
    index_map.set_param(gid("gain"), GraphParamSlot::Value0, 0.25),
  )
  inspect(control.node_index(), content="1")
  inspect(control.value(), content="0.25")
  let builder = unwrap_binding_builder(
    index_map.bind_control(
      ControlBindingBuilder::new(),
      "freq",
      gid("osc"),
      GraphParamSlot::Value0,
    ),
  )
  match builder.build(doc.analyze()) {
    Ok(bindings) => inspect(bindings.length(), content="1")
    Err(error) => abort("expected valid control binding map, got \{error}")
  }
  let context = DspContext::new(sample_rate=48000.0, block_size=128)
  assert_true(doc.compile(context) is Some(_))
}

///|
test "GraphTemplateDoc rejects duplicate ids" {
  let result = try? GraphTemplateDoc::from_nodes(ids=[gid("dup"), gid("dup")], nodes=[
    DspNode::constant(1.0),
    DspNode::output(0),
  ])
  match result {
    Err(DuplicateNodeId(value)) => inspect(value, content="dup")
    _ => fail("expected duplicate id error")
  }
}

///|
test "GraphTemplateDoc replace and rewire preserve stable ids" {
  let doc = identity_graph_doc()
  let replaced = unwrap_graph_doc(
    try? doc.replace_node(gid("gain"), DspNode::gain(0, 0.25)),
  )
  inspect(replaced.revision().value(), content="1")
  match replaced.node_index(gid("gain")) {
    Some(index) => inspect(index, content="1")
    None => fail("expected gain id to survive replacement")
  }
  let gain = unwrap_graph_node(replaced.node_at(gid("gain")))
  inspect(gain.value0(), content="0.25")
  let rewired = unwrap_graph_doc(
    try? replaced.rewire_input(
      gid("out"),
      GraphTopologyInputSlot::Input0,
      gid("osc"),
    ),
  )
  let output = unwrap_graph_node(rewired.node_at(gid("out")))
  inspect(output.input0(), content="0")
  match rewired.node_index(gid("gain")) {
    Some(index) => inspect(index, content="1")
    None => fail("expected gain id to survive rewire")
  }
}

///|
test "GraphTemplateDoc insert and delete compact ids without reuse" {
  let base = unwrap_graph_doc(
    try? GraphTemplateDoc::from_nodes(ids=[gid("osc"), gid("out")], nodes=[
      DspNode::oscillator(Waveform::Sine, 440.0),
      DspNode::output(0),
    ]),
  )
  let inserted = unwrap_graph_doc(
    try? base.insert_node(
      gid("gain"),
      gid("out"),
      GraphTopologyInputSlot::Input0,
      DspNode::gain(0, 0.5),
    ),
  )
  inspect(inserted.length(), content="3")
  match inserted.node_index(gid("out")) {
    Some(index) => inspect(index, content="1")
    None => fail("expected output id")
  }
  match inserted.node_index(gid("gain")) {
    Some(index) => inspect(index, content="2")
    None => fail("expected inserted gain id")
  }
  let inserted_output = unwrap_graph_node(inserted.node_at(gid("out")))
  inspect(inserted_output.input0(), content="2")
  let deleted = unwrap_graph_doc(
    try? inserted.delete_node(
      gid("gain"),
      gid("out"),
      GraphTopologyInputSlot::Input0,
      gid("gain"),
    ),
  )
  inspect(deleted.length(), content="2")
  assert_true(deleted.node_index(gid("gain")) is None)
  assert_true(deleted.contains_retired_node(gid("gain")))
  let deleted_output = unwrap_graph_node(deleted.node_at(gid("out")))
  inspect(deleted_output.input0(), content="0")
  let reuse_result = try? deleted.insert_node(
    gid("gain"),
    gid("out"),
    GraphTopologyInputSlot::Input0,
    DspNode::gain(0, 0.75),
  )
  match reuse_result {
    Err(RetiredNodeId(value)) => inspect(value, content="gain")
    _ => fail("expected retired id rejection")
  }
}
