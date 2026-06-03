///|
/// Generated mono fixture for external-authoring benchmarks.
///
/// Fields keep the graph snapshot, stable IDs, and declared control keys
/// together so each benchmark isolates one boundary step without rebuilding
/// unrelated authoring metadata in the timed closure.
priv struct BenchExternalAuthoringFixture {
  name : String
  nodes : Array[DspNode]
  ids : Array[@identity.GraphNodeId]
  control_keys : Array[String]
  control_ids : Array[@identity.GraphNodeId]
}

///|
fn bench_external_graph_id(index : Int) -> @identity.GraphNodeId {
  try @identity.GraphNodeId::from_string("bench:node:\{index}") catch {
    _ => abort("expected valid generated graph id")
  } noraise {
    id => id
  }
}

///|
fn bench_external_inserted_id(suffix : String) -> @identity.GraphNodeId {
  try @identity.GraphNodeId::from_string("bench:inserted:\{suffix}") catch {
    _ => abort("expected valid inserted graph id")
  } noraise {
    id => id
  }
}

///|
fn build_bench_external_authoring_fixture(
  name : String,
  stage_count : Int,
) -> BenchExternalAuthoringFixture {
  let nodes : Array[DspNode] = Array::new(capacity=stage_count + 2)
  let ids : Array[@identity.GraphNodeId] = Array::new(capacity=stage_count + 2)
  let control_keys : Array[String] = Array::new(capacity=stage_count)
  let control_ids : Array[@identity.GraphNodeId] = Array::new(
    capacity=stage_count,
  )
  nodes.push(DspNode::oscillator(Waveform::Saw, 220.0))
  ids.push(bench_external_graph_id(0))
  let mut previous = 0
  for stage in 0..<stage_count {
    let node_index = nodes.length()
    let node = match stage % 3 {
      0 => DspNode::gain(previous, 0.7)
      1 =>
        DspNode::biquad(
          input=previous,
          mode=BiquadMode::LowPass,
          cutoff_hz=900.0 + Double::from_int(stage),
          q=0.707,
        )
      _ => DspNode::clip(previous, 0.9)
    }
    nodes.push(node)
    ids.push(bench_external_graph_id(node_index))
    control_keys.push("p:\{stage}")
    control_ids.push(ids[node_index])
    previous = node_index
  }
  let output_index = nodes.length()
  nodes.push(DspNode::output(previous))
  ids.push(bench_external_graph_id(output_index))
  { name, nodes, ids, control_keys, control_ids }
}

///|
fn bench_external_authoring_fixtures() -> Array[BenchExternalAuthoringFixture] {
  [
    build_bench_external_authoring_fixture("small_10_nodes", 8),
    build_bench_external_authoring_fixture("medium_34_nodes", 32),
    build_bench_external_authoring_fixture("large_130_nodes", 128),
  ]
}

///|
fn bench_external_doc(
  fixture : BenchExternalAuthoringFixture,
) -> GraphTemplateDoc {
  try GraphTemplateDoc::from_nodes(ids=fixture.ids, nodes=fixture.nodes) catch {
    error => abort("expected generated graph doc, got \{error}")
  } noraise {
    doc => doc
  }
}

///|
fn build_bench_external_binding_builder(
  index_map : GraphIndexMap,
  fixture : BenchExternalAuthoringFixture,
) -> ControlBindingBuilder {
  let mut builder = ControlBindingBuilder::new()
  for i in 0..<fixture.control_ids.length() {
    match
      index_map.bind_control(
        builder,
        fixture.control_keys[i],
        fixture.control_ids[i],
        GraphParamSlot::Value0,
      ) {
      Some(next) => builder = next
      None => abort("expected generated control id to resolve")
    }
  }
  builder
}

///|
fn bench_external_binding_map(
  fixture : BenchExternalAuthoringFixture,
) -> ControlBindingMap {
  let doc = bench_external_doc(fixture)
  let template = doc.analyze()
  build_bench_external_binding_builder(doc.index_map(), fixture)
  .build(template)
  .unwrap()
}

///|
fn bench_external_control_values(
  fixture : BenchExternalAuthoringFixture,
  offset : Double,
) -> Map[String, Double] {
  let controls : Map[String, Double] = {}
  for i in 0..<fixture.control_keys.length() {
    controls[fixture.control_keys[i]] = 0.5 +
      offset +
      Double::from_int(i % 5) * 0.01
  }
  controls
}

///|
fn bench_external_control_batch(
  fixture : BenchExternalAuthoringFixture,
  offset : Double,
) -> Array[GraphControl] {
  let controls : Array[GraphControl] = Array::new(
    capacity=fixture.control_ids.length(),
  )
  for i in 0..<fixture.control_ids.length() {
    controls.push(
      GraphControl::set_param(i + 1, GraphParamSlot::Value0, 0.5 + offset),
    )
  }
  controls
}

///|
fn bench_external_replace_roundtrip(
  doc : GraphTemplateDoc,
  fixture : BenchExternalAuthoringFixture,
) -> GraphTemplateDoc {
  let target_id = fixture.ids[1]
  let replaced = try doc.replace_node(target_id, DspNode::gain(0, 0.55)) catch {
    error => abort("expected replace edit to apply, got \{error}")
  } noraise {
    next => next
  }
  try replaced.replace_node(target_id, fixture.nodes[1]) catch {
    error => abort("expected replace roundtrip to apply, got \{error}")
  } noraise {
    next => next
  }
}

///|
fn bench_external_add_roundtrip(
  doc : GraphTemplateDoc,
  fixture : BenchExternalAuthoringFixture,
) -> GraphTemplateDoc {
  let output_id = fixture.ids[fixture.nodes.length() - 1]
  let inserted_id = bench_external_inserted_id("add")
  let inserted = try
    doc.insert_node(
      inserted_id,
      output_id,
      GraphTopologyInputSlot::Input0,
      DspNode::gain(-1, 0.8),
    )
  catch {
    error => abort("expected insert edit to apply, got \{error}")
  } noraise {
    next => next
  }
  try
    inserted.delete_node(
      inserted_id,
      output_id,
      GraphTopologyInputSlot::Input0,
      inserted_id,
    )
  catch {
    error => abort("expected add roundtrip to apply, got \{error}")
  } noraise {
    next => next
  }
}

///|
fn bench_external_remove_roundtrip(
  doc : GraphTemplateDoc,
  fixture : BenchExternalAuthoringFixture,
) -> GraphTemplateDoc {
  let output_id = fixture.ids[fixture.nodes.length() - 1]
  let delete_index = fixture.nodes.length() - 2
  let delete_id = fixture.ids[delete_index]
  let removed = try
    doc.delete_node(
      delete_id,
      output_id,
      GraphTopologyInputSlot::Input0,
      delete_id,
    )
  catch {
    error => abort("expected delete edit to apply, got \{error}")
  } noraise {
    next => next
  }
  try
    removed.insert_node(
      bench_external_inserted_id("restore"),
      output_id,
      GraphTopologyInputSlot::Input0,
      fixture.nodes[delete_index],
    )
  catch {
    error => abort("expected remove roundtrip to apply, got \{error}")
  } noraise {
    next => next
  }
}

///|
fn bench_external_rewire_roundtrip(
  doc : GraphTemplateDoc,
  fixture : BenchExternalAuthoringFixture,
) -> GraphTemplateDoc {
  let target_index = fixture.nodes.length() - 2
  let target_id = fixture.ids[target_index]
  let replacement_source_id = fixture.ids[0]
  let original_source_id = fixture.ids[target_index - 1]
  let rewired = try
    doc.rewire_input(
      target_id,
      GraphTopologyInputSlot::Input0,
      replacement_source_id,
    )
  catch {
    error => abort("expected rewire edit to apply, got \{error}")
  } noraise {
    next => next
  }
  try
    rewired.rewire_input(
      target_id,
      GraphTopologyInputSlot::Input0,
      original_source_id,
    )
  catch {
    error => abort("expected rewire roundtrip to apply, got \{error}")
  } noraise {
    next => next
  }
}

///|
test "bench graph: external authoring fixtures compile, bind, and edit" {
  let ctx = DspContext::new(sample_rate=BENCH_SAMPLE_RATE, block_size=128)
  for fixture in bench_external_authoring_fixtures() {
    let doc = bench_external_doc(fixture)
    assert_true(doc.length() == fixture.nodes.length())
    let template = doc.analyze()
    let bindings = build_bench_external_binding_builder(
        doc.index_map(),
        fixture,
      )
      .build(template)
      .unwrap()
    assert_true(bindings.length() == fixture.control_keys.length())
    let compiled = CompiledDsp::compile(doc.analyze(), ctx).unwrap()
    compiled
    .apply_controls(bench_external_control_batch(fixture, 0.01))
    .unwrap()
    assert_true(
      bench_external_replace_roundtrip(doc, fixture).length() ==
      fixture.nodes.length(),
    )
    assert_true(
      bench_external_add_roundtrip(doc, fixture).length() ==
      fixture.nodes.length(),
    )
    assert_true(
      bench_external_remove_roundtrip(doc, fixture).length() ==
      fixture.nodes.length(),
    )
    assert_true(
      bench_external_rewire_roundtrip(doc, fixture).length() ==
      fixture.nodes.length(),
    )
  }
}

// ---- External authoring/control benchmarks ----
// WHY separate from process(): these measure editor/control-thread work from
// the Mini/graph authoring boundary, not audio block processing. Parser,
// lowering, template analysis, binding validation, compile, and hot-swap setup
// may allocate; only precompiled process/apply at block boundaries belongs on
// the audio callback.

///|
test "bench/external_authoring/template_analyze" (b : @bench.T) {
  for fixture in bench_external_authoring_fixtures() {
    let nodes = fixture.nodes
    b.bench(name=fixture.name, fn() {
      let template = CompiledTemplate::analyze(nodes)
      b.keep(template)
    })
  }
}

///|
test "bench/external_authoring/control_binding_generation" (b : @bench.T) {
  for fixture in bench_external_authoring_fixtures() {
    let doc = bench_external_doc(fixture)
    let index_map = doc.index_map()
    b.bench(name=fixture.name, fn() {
      let builder = build_bench_external_binding_builder(index_map, fixture)
      b.keep(builder)
    })
  }
}

///|
test "bench/external_authoring/control_binding_validation" (b : @bench.T) {
  for fixture in bench_external_authoring_fixtures() {
    let doc = bench_external_doc(fixture)
    let template = doc.analyze()
    let builder = build_bench_external_binding_builder(doc.index_map(), fixture)
    b.bench(name=fixture.name, fn() {
      let bindings = builder.build(template)
      b.keep(bindings)
    })
  }
}

///|
test "bench/external_authoring/string_control_resolution" (b : @bench.T) {
  for fixture in bench_external_authoring_fixtures() {
    let bindings = bench_external_binding_map(fixture)
    let controls_a = bench_external_control_values(fixture, 0.01)
    let controls_b = bench_external_control_values(fixture, 0.02)
    let use_b = @ref.new(false)
    b.bench(name=fixture.name, fn() {
      let controls = if use_b.val { controls_b } else { controls_a }
      use_b.val = !use_b.val
      let batch = bindings.resolve_controls(controls)
      b.keep(batch)
    })
  }
}

///|
test "bench/external_control/apply_param_batch_compiled" (b : @bench.T) {
  let ctx = DspContext::new(sample_rate=BENCH_SAMPLE_RATE, block_size=128)
  for fixture in bench_external_authoring_fixtures() {
    let compiled = CompiledDsp::compile(
      CompiledTemplate::analyze(fixture.nodes),
      ctx,
    ).unwrap()
    let controls_a = bench_external_control_batch(fixture, 0.01)
    let controls_b = bench_external_control_batch(fixture, 0.02)
    let use_b = @ref.new(false)
    b.bench(name=fixture.name, fn() {
      let controls = if use_b.val { controls_b } else { controls_a }
      use_b.val = !use_b.val
      compiled.apply_controls(controls).unwrap()
      b.keep(compiled)
    })
  }
}

///|
test "bench/external_control/apply_param_batch_topology_controller" (
  b : @bench.T,
) {
  let ctx = DspContext::new(sample_rate=BENCH_SAMPLE_RATE, block_size=128)
  for fixture in bench_external_authoring_fixtures() {
    let controller = CompiledDspTopologyController::from_nodes(
      fixture.nodes,
      ctx,
      crossfade_samples=128,
    ).unwrap()
    let controls_a = bench_external_control_batch(fixture, 0.01)
    let controls_b = bench_external_control_batch(fixture, 0.02)
    let use_b = @ref.new(false)
    b.bench(name=fixture.name, fn() {
      let controls = if use_b.val { controls_b } else { controls_a }
      use_b.val = !use_b.val
      controller.apply_controls(controls).unwrap()
      b.keep(controller)
    })
  }
}

///|
test "bench/external_authoring/topology_doc_roundtrips" (b : @bench.T) {
  for fixture in bench_external_authoring_fixtures() {
    let doc = bench_external_doc(fixture)
    let fixture_name = fixture.name
    b.bench(name="replace_node/\{fixture_name}", fn() {
      let edited = bench_external_replace_roundtrip(doc, fixture)
      b.keep(edited)
    })
    b.bench(name="add_node/\{fixture_name}", fn() {
      let edited = bench_external_add_roundtrip(doc, fixture)
      b.keep(edited)
    })
    b.bench(name="remove_node/\{fixture_name}", fn() {
      let edited = bench_external_remove_roundtrip(doc, fixture)
      b.keep(edited)
    })
    b.bench(name="reconnect_edge/\{fixture_name}", fn() {
      let edited = bench_external_rewire_roundtrip(doc, fixture)
      b.keep(edited)
    })
  }
}

///|
test "bench/external_authoring/compile_prepared_template_change" (b : @bench.T) {
  let ctx = DspContext::new(sample_rate=BENCH_SAMPLE_RATE, block_size=128)
  for fixture in bench_external_authoring_fixtures() {
    let doc = bench_external_doc(fixture)
    let edited_doc = try
      doc.replace_node(fixture.ids[1], DspNode::gain(0, 0.55))
    catch {
      error => abort("expected prepared template edit, got \{error}")
    } noraise {
      next => next
    }
    let template_a = doc.analyze()
    let template_b = edited_doc.analyze()
    let use_b = @ref.new(false)
    b.bench(name=fixture.name, fn() {
      let template = if use_b.val { template_b } else { template_a }
      use_b.val = !use_b.val
      let compiled = CompiledDsp::compile_result(template, ctx)
      b.keep(compiled)
    })
  }
}

///|
test "bench/external_authoring/queue_prepared_hotswap_setup" (b : @bench.T) {
  let ctx = DspContext::new(sample_rate=BENCH_SAMPLE_RATE, block_size=128)
  for fixture in bench_external_authoring_fixtures() {
    let doc = bench_external_doc(fixture)
    let edited_doc = try
      doc.replace_node(fixture.ids[1], DspNode::gain(0, 0.55))
    catch {
      error => abort("expected prepared hotswap edit, got \{error}")
    } noraise {
      next => next
    }
    let compiled_a = CompiledDsp::compile(doc.analyze(), ctx).unwrap()
    let compiled_b = CompiledDsp::compile(edited_doc.analyze(), ctx).unwrap()
    let use_b = @ref.new(false)
    b.bench(name=fixture.name, fn() {
      let active = if use_b.val { compiled_b } else { compiled_a }
      let next = if use_b.val { compiled_a } else { compiled_b }
      use_b.val = !use_b.val
      let hs = CompiledDspHotSwap::from_graph(active, crossfade_samples=128)
      hs.queue_swap(next).unwrap()
      b.keep(hs)
    })
  }
}
