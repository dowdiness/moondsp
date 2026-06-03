///|
priv enum BenchExternalGraphKind {
  MonoExternalGraph
  StereoExternalGraph
}

///|
/// Generated fixture for external-authoring benchmarks.
///
/// Fields keep the graph snapshot, stable IDs, and declared control keys
/// together so each benchmark isolates one boundary step without rebuilding
/// unrelated authoring metadata in the timed closure.
priv struct BenchExternalAuthoringFixture {
  name : String
  graph_kind : BenchExternalGraphKind
  nodes : Array[DspNode]
  ids : Array[@identity.GraphNodeId]
  control_keys : Array[String]
  control_ids : Array[@identity.GraphNodeId]
  control_indices : Array[Int]
  control_slots : Array[GraphParamSlot]
  shape_rewire_target_id : @identity.GraphNodeId
  shape_rewire_slot : GraphTopologyInputSlot
  shape_rewire_source_id : @identity.GraphNodeId
  shape_rewire_restore_id : @identity.GraphNodeId
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
priv struct BenchExternalFixtureBuilder {
  nodes : Array[DspNode]
  ids : Array[@identity.GraphNodeId]
  control_keys : Array[String]
  control_ids : Array[@identity.GraphNodeId]
  control_indices : Array[Int]
  control_slots : Array[GraphParamSlot]
}

///|
fn BenchExternalFixtureBuilder::BenchExternalFixtureBuilder(
  node_capacity~ : Int,
  control_capacity~ : Int,
) -> BenchExternalFixtureBuilder {
  {
    nodes: Array::new(capacity=node_capacity),
    ids: Array::new(capacity=node_capacity),
    control_keys: Array::new(capacity=control_capacity),
    control_ids: Array::new(capacity=control_capacity),
    control_indices: Array::new(capacity=control_capacity),
    control_slots: Array::new(capacity=control_capacity),
  }
}

///|
fn BenchExternalFixtureBuilder::push_node(
  self : BenchExternalFixtureBuilder,
  node : DspNode,
) -> Int {
  let index = self.nodes.length()
  self.nodes.push(node)
  self.ids.push(bench_external_graph_id(index))
  index
}

///|
fn BenchExternalFixtureBuilder::push_value0_control(
  self : BenchExternalFixtureBuilder,
  key : String,
  index : Int,
) -> Unit {
  if index < 0 || index >= self.ids.length() {
    abort("expected generated control index to resolve")
  }
  self.control_keys.push(key)
  self.control_ids.push(self.ids[index])
  self.control_indices.push(index)
  self.control_slots.push(GraphParamSlot::Value0)
}

///|
fn BenchExternalFixtureBuilder::finish(
  self : BenchExternalFixtureBuilder,
  name : String,
  graph_kind : BenchExternalGraphKind,
  shape_rewire_target_index : Int,
  shape_rewire_slot : GraphTopologyInputSlot,
  shape_rewire_source_index : Int,
  shape_rewire_restore_index : Int,
) -> BenchExternalAuthoringFixture {
  if shape_rewire_target_index < 0 ||
    shape_rewire_target_index >= self.ids.length() ||
    shape_rewire_source_index < 0 ||
    shape_rewire_source_index >= self.ids.length() ||
    shape_rewire_restore_index < 0 ||
    shape_rewire_restore_index >= self.ids.length() {
    abort("expected valid shape-edit rewire indices")
  }
  {
    name,
    graph_kind,
    nodes: self.nodes,
    ids: self.ids,
    control_keys: self.control_keys,
    control_ids: self.control_ids,
    control_indices: self.control_indices,
    control_slots: self.control_slots,
    shape_rewire_target_id: self.ids[shape_rewire_target_index],
    shape_rewire_slot,
    shape_rewire_source_id: self.ids[shape_rewire_source_index],
    shape_rewire_restore_id: self.ids[shape_rewire_restore_index],
  }
}

///|
fn build_bench_external_authoring_fixture(
  name : String,
  stage_count : Int,
) -> BenchExternalAuthoringFixture {
  let builder = BenchExternalFixtureBuilder(
    node_capacity=stage_count + 2,
    control_capacity=stage_count,
  )
  let mut previous = builder.push_node(
    DspNode::oscillator(Waveform::Saw, 220.0),
  )
  for stage in 0..<stage_count {
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
    let node_index = builder.push_node(node)
    builder.push_value0_control("p:\{stage}", node_index)
    previous = node_index
  }
  let output_index = builder.push_node(DspNode::output(previous))
  builder.finish(
    name,
    BenchExternalGraphKind::MonoExternalGraph,
    output_index,
    GraphTopologyInputSlot::Input0,
    0,
    previous,
  )
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
fn build_bench_external_branch_fanout_fixture() -> BenchExternalAuthoringFixture {
  let builder = BenchExternalFixtureBuilder(
    node_capacity=11,
    control_capacity=6,
  )
  let osc = builder.push_node(DspNode::oscillator(Waveform::Saw, 220.0))
  let pre_gain = builder.push_node(DspNode::gain(osc, 0.72))
  builder.push_value0_control("branch:pre_gain", pre_gain)
  let branch_filter = builder.push_node(
    DspNode::biquad(
      input=pre_gain,
      mode=BiquadMode::LowPass,
      cutoff_hz=1400.0,
      q=0.707,
    ),
  )
  builder.push_value0_control("branch:filter_cutoff", branch_filter)
  let filter_gain = builder.push_node(DspNode::gain(branch_filter, 0.55))
  builder.push_value0_control("branch:filter_gain", filter_gain)
  let branch_delay = builder.push_node(
    DspNode::delay(
      input=pre_gain,
      max_delay_samples=4800,
      delay_samples=900,
      feedback=0.22,
    ),
  )
  builder.push_value0_control("branch:delay_feedback", branch_delay)
  let delayed_clip = builder.push_node(DspNode::clip(branch_delay, 0.85))
  builder.push_value0_control("branch:delay_clip", delayed_clip)
  let noise = builder.push_node(DspNode::noise(91U))
  let noise_gain = builder.push_node(DspNode::gain(noise, 0.16))
  builder.push_value0_control("branch:noise_gain", noise_gain)
  let wet_mix = builder.push_node(DspNode::mix(filter_gain, delayed_clip))
  let final_mix = builder.push_node(DspNode::mix(wet_mix, noise_gain))
  ignore(builder.push_node(DspNode::output(final_mix)))
  builder.finish(
    "branch_fanout_11_nodes",
    BenchExternalGraphKind::MonoExternalGraph,
    branch_filter,
    GraphTopologyInputSlot::Input0,
    osc,
    pre_gain,
  )
}

///|
fn build_bench_external_mix_bus_fixture() -> BenchExternalAuthoringFixture {
  let builder = BenchExternalFixtureBuilder(
    node_capacity=17,
    control_capacity=8,
  )
  let osc_a = builder.push_node(DspNode::oscillator(Waveform::Saw, 110.0))
  let gain_a = builder.push_node(DspNode::gain(osc_a, 0.45))
  builder.push_value0_control("mix:a_gain", gain_a)
  let osc_b = builder.push_node(DspNode::oscillator(Waveform::Square, 220.0))
  let gain_b = builder.push_node(DspNode::gain(osc_b, 0.32))
  builder.push_value0_control("mix:b_gain", gain_b)
  let noise = builder.push_node(DspNode::noise(123U))
  let noise_filter = builder.push_node(
    DspNode::biquad(
      input=noise,
      mode=BiquadMode::HighPass,
      cutoff_hz=1800.0,
      q=0.8,
    ),
  )
  builder.push_value0_control("mix:noise_filter", noise_filter)
  let noise_gain = builder.push_node(DspNode::gain(noise_filter, 0.18))
  builder.push_value0_control("mix:noise_gain", noise_gain)
  let osc_c = builder.push_node(DspNode::oscillator(Waveform::Triangle, 330.0))
  let clipped_c = builder.push_node(DspNode::clip(osc_c, 0.7))
  builder.push_value0_control("mix:c_clip", clipped_c)
  let mix_ab = builder.push_node(DspNode::mix(gain_a, gain_b))
  let mix_noise_c = builder.push_node(DspNode::mix(noise_gain, clipped_c))
  let bus_mix = builder.push_node(DspNode::mix(mix_ab, mix_noise_c))
  let bus_filter = builder.push_node(
    DspNode::biquad(
      input=bus_mix,
      mode=BiquadMode::LowPass,
      cutoff_hz=2400.0,
      q=0.707,
    ),
  )
  builder.push_value0_control("mix:bus_filter", bus_filter)
  let bus_delay = builder.push_node(
    DspNode::delay(
      input=bus_filter,
      max_delay_samples=7200,
      delay_samples=1800,
      feedback=0.18,
    ),
  )
  builder.push_value0_control("mix:bus_delay", bus_delay)
  let wet_bus = builder.push_node(DspNode::mix(bus_mix, bus_delay))
  let limited = builder.push_node(DspNode::clip(wet_bus, 0.92))
  builder.push_value0_control("mix:limiter", limited)
  ignore(builder.push_node(DspNode::output(limited)))
  builder.finish(
    "mix_bus_17_nodes",
    BenchExternalGraphKind::MonoExternalGraph,
    bus_filter,
    GraphTopologyInputSlot::Input0,
    mix_ab,
    bus_mix,
  )
}

///|
fn build_bench_external_terminal_stereo_fixture() -> BenchExternalAuthoringFixture {
  let builder = BenchExternalFixtureBuilder(
    node_capacity=15,
    control_capacity=9,
  )
  let osc = builder.push_node(DspNode::oscillator(Waveform::Saw, 196.0))
  let filter = builder.push_node(
    DspNode::biquad(
      input=osc,
      mode=BiquadMode::LowPass,
      cutoff_hz=1600.0,
      q=0.707,
    ),
  )
  builder.push_value0_control("stereo:filter", filter)
  let voice_gain = builder.push_node(DspNode::gain(filter, 0.6))
  builder.push_value0_control("stereo:voice_gain", voice_gain)
  let noise = builder.push_node(DspNode::noise(321U))
  let noise_gain = builder.push_node(DspNode::gain(noise, 0.08))
  builder.push_value0_control("stereo:noise_gain", noise_gain)
  let dry_mix = builder.push_node(DspNode::mix(voice_gain, noise_gain))
  let mono_delay = builder.push_node(
    DspNode::delay(
      input=dry_mix,
      max_delay_samples=4800,
      delay_samples=1200,
      feedback=0.15,
    ),
  )
  builder.push_value0_control("stereo:mono_delay", mono_delay)
  let wet_mix = builder.push_node(DspNode::mix(dry_mix, mono_delay))
  let clipped = builder.push_node(DspNode::clip(wet_mix, 0.88))
  builder.push_value0_control("stereo:mono_clip", clipped)
  let pan = builder.push_node(DspNode::pan(clipped, -0.2))
  builder.push_value0_control("stereo:pan", pan)
  let stereo_filter = builder.push_node(
    DspNode::stereo_biquad(
      input=pan,
      mode=BiquadMode::LowPass,
      cutoff_hz=2600.0,
      q=0.707,
    ),
  )
  builder.push_value0_control("stereo:stereo_filter", stereo_filter)
  let stereo_delay = builder.push_node(
    DspNode::stereo_delay(
      input=stereo_filter,
      max_delay_samples=9600,
      delay_samples=2400,
      feedback=0.2,
    ),
  )
  builder.push_value0_control("stereo:stereo_delay", stereo_delay)
  let stereo_gain = builder.push_node(
    DspNode::stereo_gain(input=stereo_delay, amount=0.8),
  )
  builder.push_value0_control("stereo:stereo_gain", stereo_gain)
  let stereo_clip = builder.push_node(
    DspNode::stereo_clip(input=stereo_gain, threshold=0.92),
  )
  let stereo_output = builder.push_node(DspNode::stereo_output(stereo_clip))
  builder.finish(
    "terminal_stereo_15_nodes",
    BenchExternalGraphKind::StereoExternalGraph,
    stereo_output,
    GraphTopologyInputSlot::Input0,
    stereo_gain,
    stereo_clip,
  )
}

///|
/// Feedback fixture with no dead authoring nodes.
///
/// WHY no unused frequency constant: topology-controller benchmarks compile raw
/// authoring arrays to preserve control indices, so dead nodes would be rejected
/// instead of optimized away. The forward `mix(filter, gain)` input still gives
/// the compiler a safe feedback edge to route.
fn build_bench_external_feedback_loop_fixture() -> BenchExternalAuthoringFixture {
  let builder = BenchExternalFixtureBuilder(node_capacity=6, control_capacity=3)
  let osc = builder.push_node(DspNode::oscillator(Waveform::Saw, 440.0))
  let filter = builder.push_node(
    DspNode::biquad(
      input=osc,
      mode=BiquadMode::LowPass,
      cutoff_hz=1000.0,
      q=0.707,
    ),
  )
  builder.push_value0_control("feedback:filter", filter)
  let loop_mix = builder.push_node(DspNode::mix(filter, 4))
  let delay = builder.push_node(
    DspNode::delay(
      input=loop_mix,
      max_delay_samples=4800,
      delay_samples=2400,
      feedback=0.0,
    ),
  )
  builder.push_value0_control("feedback:delay_feedback", delay)
  let gain = builder.push_node(DspNode::gain(delay, 0.5))
  builder.push_value0_control("feedback:return_gain", gain)
  let output = builder.push_node(DspNode::output(gain))
  builder.finish(
    "feedback_loop_6_nodes",
    BenchExternalGraphKind::MonoExternalGraph,
    output,
    GraphTopologyInputSlot::Input0,
    delay,
    gain,
  )
}

///|
fn bench_external_realistic_authoring_fixtures() -> Array[
  BenchExternalAuthoringFixture,
] {
  [
    build_bench_external_branch_fanout_fixture(),
    build_bench_external_mix_bus_fixture(),
    build_bench_external_terminal_stereo_fixture(),
    build_bench_external_feedback_loop_fixture(),
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
        fixture.control_slots[i],
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
      GraphControl::set_param(
        fixture.control_indices[i],
        fixture.control_slots[i],
        0.5 + offset,
      ),
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
fn bench_external_shape_rewire_doc(
  doc : GraphTemplateDoc,
  fixture : BenchExternalAuthoringFixture,
) -> GraphTemplateDoc {
  try
    doc.rewire_input(
      fixture.shape_rewire_target_id,
      fixture.shape_rewire_slot,
      fixture.shape_rewire_source_id,
    )
  catch {
    error => abort("expected realistic shape rewire, got \{error}")
  } noraise {
    next => next
  }
}

///|
fn bench_external_shape_rewire_roundtrip(
  doc : GraphTemplateDoc,
  fixture : BenchExternalAuthoringFixture,
) -> GraphTemplateDoc {
  let rewired = bench_external_shape_rewire_doc(doc, fixture)
  try
    rewired.rewire_input(
      fixture.shape_rewire_target_id,
      fixture.shape_rewire_slot,
      fixture.shape_rewire_restore_id,
    )
  catch {
    error => abort("expected realistic shape rewire roundtrip, got \{error}")
  } noraise {
    next => next
  }
}

///|
fn bench_external_template_analyze_group(
  b : @bench.T,
  fixtures : Array[BenchExternalAuthoringFixture],
) -> Unit {
  for fixture in fixtures {
    let nodes = fixture.nodes
    b.bench(name=fixture.name, fn() {
      let template = CompiledTemplate::analyze(nodes)
      b.keep(template)
    })
  }
}

///|
fn bench_external_control_binding_generation_group(
  b : @bench.T,
  fixtures : Array[BenchExternalAuthoringFixture],
) -> Unit {
  for fixture in fixtures {
    let doc = bench_external_doc(fixture)
    let index_map = doc.index_map()
    b.bench(name=fixture.name, fn() {
      let builder = build_bench_external_binding_builder(index_map, fixture)
      b.keep(builder)
    })
  }
}

///|
fn bench_external_control_binding_validation_group(
  b : @bench.T,
  fixtures : Array[BenchExternalAuthoringFixture],
) -> Unit {
  for fixture in fixtures {
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
fn bench_external_string_control_resolution_group(
  b : @bench.T,
  fixtures : Array[BenchExternalAuthoringFixture],
) -> Unit {
  for fixture in fixtures {
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
fn[T, E] bench_expect_err(result : Result[T, E], label : String) -> E {
  match result {
    Err(error) => error
    Ok(_) => abort("expected \{label} to reject")
  }
}

///|
fn bench_external_control_binding_rejection(
  b : @bench.T,
  make_builder : (GraphIndexMap, BenchExternalAuthoringFixture) -> ControlBindingBuilder,
  label : String,
) -> Unit {
  for fixture in bench_external_authoring_fixtures() {
    let doc = bench_external_doc(fixture)
    let template = doc.analyze()
    let builder = make_builder(doc.index_map(), fixture)
    b.bench(name=fixture.name, fn() {
      let error = bench_expect_err(builder.build(template), label)
      b.keep(error)
    })
  }
}

///|
fn bench_external_compile_result_rejection(
  b : @bench.T,
  make_template : (BenchExternalAuthoringFixture) -> CompiledTemplate,
  label : String,
) -> Unit {
  let ctx = DspContext::new(sample_rate=BENCH_SAMPLE_RATE, block_size=128)
  for fixture in bench_external_authoring_fixtures() {
    let template = make_template(fixture)
    b.bench(name=fixture.name, fn() {
      let error = bench_expect_err(
        CompiledDsp::compile_result(template, ctx),
        label,
      )
      b.keep(error)
    })
  }
}

///|
fn bench_external_invalid_index_binding_builder(
  index_map : GraphIndexMap,
  fixture : BenchExternalAuthoringFixture,
) -> ControlBindingBuilder {
  let builder = build_bench_external_binding_builder(index_map, fixture)
  builder.bind(
    key="diagnostic:invalid-index",
    node_index=fixture.nodes.length() + 7,
    slot=GraphParamSlot::Value0,
  )
}

///|
fn bench_external_invalid_slot_binding_builder(
  index_map : GraphIndexMap,
  fixture : BenchExternalAuthoringFixture,
) -> ControlBindingBuilder {
  let builder = build_bench_external_binding_builder(index_map, fixture)
  builder.bind(
    key="diagnostic:invalid-slot",
    node_index=1,
    slot=GraphParamSlot::Value1,
  )
}

///|
fn bench_external_duplicate_key_binding_builder(
  index_map : GraphIndexMap,
  fixture : BenchExternalAuthoringFixture,
) -> ControlBindingBuilder {
  let builder = build_bench_external_binding_builder(index_map, fixture)
  builder.bind(
    key=fixture.control_keys[0],
    node_index=1,
    slot=GraphParamSlot::Value0,
  )
}

///|
fn bench_external_invalid_param_batch(
  fixture : BenchExternalAuthoringFixture,
  offset : Double,
) -> Array[GraphControl] {
  let controls = bench_external_control_batch(fixture, offset)
  // Node 3 is the first generated Clip stage in all benchmark fixtures.
  controls.push(GraphControl::set_param(3, GraphParamSlot::Value0, -1.0))
  controls
}

///|
fn bench_external_invalid_topology_edit() -> GraphTopologyEdit {
  GraphTopologyEdit::rewire_input(0, GraphTopologyInputSlot::Input0, 1)
}

///|
fn bench_external_valid_replace_edit(amount : Double) -> GraphTopologyEdit {
  GraphTopologyEdit::replace_node(1, DspNode::gain(0, amount))
}

///|
fn bench_external_invalid_topology_edit_batch() -> Array[GraphTopologyEdit] {
  [
    bench_external_valid_replace_edit(0.55),
    bench_external_invalid_topology_edit(),
  ]
}

///|
fn bench_external_recompile_rejected_topology_edit(
  fixture : BenchExternalAuthoringFixture,
) -> GraphTopologyEdit {
  let output_index = fixture.nodes.length() - 1
  GraphTopologyEdit::replace_node(
    output_index,
    DspNode::gain(output_index - 1, 0.5),
  )
}

///|
fn bench_external_invalid_doc_rewire(
  doc : GraphTemplateDoc,
  fixture : BenchExternalAuthoringFixture,
) -> GraphTemplateDocError {
  try
    doc.rewire_input(
      fixture.ids[0],
      GraphTopologyInputSlot::Input0,
      fixture.ids[1],
    )
  catch {
    error => error
  } noraise {
    _ => abort("expected invalid topology document rewire")
  }
}

///|
fn bench_external_missing_output_template(
  fixture : BenchExternalAuthoringFixture,
) -> CompiledTemplate {
  let nodes = fixture.nodes.copy()
  ignore(nodes.pop())
  CompiledTemplate::analyze(nodes)
}

///|
fn bench_external_multiple_outputs_template(
  fixture : BenchExternalAuthoringFixture,
) -> CompiledTemplate {
  let nodes = fixture.nodes.copy()
  nodes.push(DspNode::output(fixture.nodes.length() - 2))
  CompiledTemplate::analyze(nodes)
}

///|
fn bench_external_invalid_input_template(
  fixture : BenchExternalAuthoringFixture,
) -> CompiledTemplate {
  let nodes = fixture.nodes.copy()
  let output_index = nodes.length() - 1
  nodes[output_index] = DspNode::output(nodes.length() + 17)
  CompiledTemplate::analyze(nodes)
}

///|
fn bench_external_invalid_param_template(
  fixture : BenchExternalAuthoringFixture,
) -> CompiledTemplate {
  let nodes = fixture.nodes.copy()
  nodes[1] = DspNode::gain(0, 0.0 / 0.0)
  CompiledTemplate::analyze(nodes)
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

///|
test "bench graph: external authoring diagnostic fixtures reject safely" {
  let ctx = DspContext::new(sample_rate=BENCH_SAMPLE_RATE, block_size=128)
  for fixture in bench_external_authoring_fixtures() {
    let doc = bench_external_doc(fixture)
    let index_map = doc.index_map()
    let template = doc.analyze()
    assert_true(
      bench_external_invalid_index_binding_builder(index_map, fixture).build(
        template,
      )
      is Err(_),
    )
    assert_true(
      bench_external_invalid_slot_binding_builder(index_map, fixture).build(
        template,
      )
      is Err(_),
    )
    assert_true(
      bench_external_duplicate_key_binding_builder(index_map, fixture).build(
        template,
      )
      is Err(_),
    )
    ignore(bench_external_invalid_doc_rewire(doc, fixture))
    assert_true(doc.length() == fixture.nodes.length())
    assert_true(
      CompiledDsp::compile_result(
        bench_external_missing_output_template(fixture),
        ctx,
      )
      is Err(_),
    )
    assert_true(
      CompiledDsp::compile_result(
        bench_external_multiple_outputs_template(fixture),
        ctx,
      )
      is Err(_),
    )
    assert_true(
      CompiledDsp::compile_result(
        bench_external_invalid_input_template(fixture),
        ctx,
      )
      is Err(_),
    )
    assert_true(
      CompiledDsp::compile_result(
        bench_external_invalid_param_template(fixture),
        ctx,
      )
      is Err(_),
    )
    let compiled = CompiledDsp::compile(template, ctx).unwrap()
    assert_true(
      compiled.apply_controls(bench_external_invalid_param_batch(fixture, 0.01))
      is Err(_),
    )
    assert_true(
      compiled.apply_controls(bench_external_control_batch(fixture, 0.02))
      is Ok(_),
    )
    let controller = CompiledDspTopologyController::from_nodes(
      fixture.nodes,
      ctx,
      crossfade_samples=128,
    ).unwrap()
    assert_true(
      controller.apply_controls(
        bench_external_invalid_param_batch(fixture, 0.03),
      )
      is Err(_),
    )
    assert_true(
      controller.apply_controls(bench_external_control_batch(fixture, 0.04))
      is Ok(_),
    )
    assert_true(
      controller.queue_topology_edit(bench_external_invalid_topology_edit())
      is Err(_),
    )
    assert_true(
      controller.queue_topology_edit(bench_external_valid_replace_edit(0.55))
      is Ok(_),
    )
    let recompile_controller = CompiledDspTopologyController::from_nodes(
      fixture.nodes,
      ctx,
      crossfade_samples=128,
    ).unwrap()
    assert_true(
      recompile_controller.queue_topology_edit(
        bench_external_recompile_rejected_topology_edit(fixture),
      )
      is Err(_),
    )
    assert_true(
      recompile_controller.queue_topology_edit(
        bench_external_valid_replace_edit(0.56),
      )
      is Ok(_),
    )
  }
}

///|
test "bench graph: realistic external authoring fixtures compile, bind, and edit" {
  let ctx = DspContext::new(sample_rate=BENCH_SAMPLE_RATE, block_size=128)
  for fixture in bench_external_realistic_authoring_fixtures() {
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
    let controls = bench_external_control_batch(fixture, 0.01)
    let edited_doc = bench_external_shape_rewire_doc(doc, fixture)
    let edited_template = edited_doc.analyze()
    let edited_bindings = build_bench_external_binding_builder(
        edited_doc.index_map(),
        fixture,
      )
      .build(edited_template)
      .unwrap()
    assert_true(edited_bindings.length() == fixture.control_keys.length())
    match fixture.graph_kind {
      MonoExternalGraph => {
        let compiled = CompiledDsp::compile(doc.analyze(), ctx).unwrap()
        compiled.apply_controls(controls).unwrap()
        let edited_compiled = CompiledDsp::compile(edited_doc.analyze(), ctx).unwrap()
        edited_compiled.apply_controls(controls).unwrap()
      }
      StereoExternalGraph => {
        let compiled = CompiledStereoDsp::compile(doc.analyze(), ctx).unwrap()
        compiled.apply_controls(controls).unwrap()
        let edited_compiled = CompiledStereoDsp::compile(
          edited_doc.analyze(),
          ctx,
        ).unwrap()
        edited_compiled.apply_controls(controls).unwrap()
      }
    }
    assert_true(
      bench_external_shape_rewire_roundtrip(doc, fixture).length() ==
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
  bench_external_template_analyze_group(b, bench_external_authoring_fixtures())
}

///|
test "bench/external_authoring/control_binding_generation" (b : @bench.T) {
  bench_external_control_binding_generation_group(
    b,
    bench_external_authoring_fixtures(),
  )
}

///|
test "bench/external_authoring/control_binding_validation" (b : @bench.T) {
  bench_external_control_binding_validation_group(
    b,
    bench_external_authoring_fixtures(),
  )
}

///|
test "bench/external_authoring/string_control_resolution" (b : @bench.T) {
  bench_external_string_control_resolution_group(
    b,
    bench_external_authoring_fixtures(),
  )
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

// ---- External diagnostic/failure benchmarks ----
// These isolate editor/control-thread rejection paths. Invalid candidates are
// prepared outside audio processing; rejected work must leave the current
// compiled/template state usable.

///|
test "bench/external_authoring_diagnostics/control_binding_invalid_index" (
  b : @bench.T,
) {
  bench_external_control_binding_rejection(
    b, bench_external_invalid_index_binding_builder, "invalid-index control binding",
  )
}

///|
test "bench/external_authoring_diagnostics/control_binding_invalid_slot" (
  b : @bench.T,
) {
  bench_external_control_binding_rejection(
    b, bench_external_invalid_slot_binding_builder, "invalid-slot control binding",
  )
}

///|
test "bench/external_authoring_diagnostics/control_binding_duplicate_key" (
  b : @bench.T,
) {
  bench_external_control_binding_rejection(
    b, bench_external_duplicate_key_binding_builder, "duplicate-key control binding",
  )
}

///|
test "bench/external_control_diagnostics/apply_invalid_param_batch_compiled" (
  b : @bench.T,
) {
  let ctx = DspContext::new(sample_rate=BENCH_SAMPLE_RATE, block_size=128)
  for fixture in bench_external_authoring_fixtures() {
    let compiled = CompiledDsp::compile(
      CompiledTemplate::analyze(fixture.nodes),
      ctx,
    ).unwrap()
    let controls_a = bench_external_invalid_param_batch(fixture, 0.01)
    let controls_b = bench_external_invalid_param_batch(fixture, 0.02)
    let use_b = @ref.new(false)
    b.bench(name=fixture.name, fn() {
      let controls = if use_b.val { controls_b } else { controls_a }
      use_b.val = !use_b.val
      let error = bench_expect_err(
        compiled.apply_controls(controls),
        "compiled invalid param batch",
      )
      b.keep(error)
    })
  }
}

///|
test "bench/external_control_diagnostics/apply_invalid_param_batch_topology_controller" (
  b : @bench.T,
) {
  let ctx = DspContext::new(sample_rate=BENCH_SAMPLE_RATE, block_size=128)
  for fixture in bench_external_authoring_fixtures() {
    let controller = CompiledDspTopologyController::from_nodes(
      fixture.nodes,
      ctx,
      crossfade_samples=128,
    ).unwrap()
    let controls_a = bench_external_invalid_param_batch(fixture, 0.01)
    let controls_b = bench_external_invalid_param_batch(fixture, 0.02)
    let use_b = @ref.new(false)
    b.bench(name=fixture.name, fn() {
      let controls = if use_b.val { controls_b } else { controls_a }
      use_b.val = !use_b.val
      let error = bench_expect_err(
        controller.apply_controls(controls),
        "topology-controller invalid param batch",
      )
      b.keep(error)
    })
  }
}

///|
test "bench/external_authoring_diagnostics/topology_doc_invalid_rewire" (
  b : @bench.T,
) {
  for fixture in bench_external_authoring_fixtures() {
    let doc = bench_external_doc(fixture)
    b.bench(name=fixture.name, fn() {
      let error = bench_external_invalid_doc_rewire(doc, fixture)
      b.keep(error)
    })
  }
}

///|
test "bench/external_authoring_diagnostics/queue_invalid_topology_edit" (
  b : @bench.T,
) {
  let ctx = DspContext::new(sample_rate=BENCH_SAMPLE_RATE, block_size=128)
  for fixture in bench_external_authoring_fixtures() {
    let controller = CompiledDspTopologyController::from_nodes(
      fixture.nodes,
      ctx,
      crossfade_samples=128,
    ).unwrap()
    let edit = bench_external_invalid_topology_edit()
    b.bench(name=fixture.name, fn() {
      let error = bench_expect_err(
        controller.queue_topology_edit(edit),
        "invalid topology edit",
      )
      b.keep(error)
    })
  }
}

///|
test "bench/external_authoring_diagnostics/queue_invalid_topology_edit_batch" (
  b : @bench.T,
) {
  let ctx = DspContext::new(sample_rate=BENCH_SAMPLE_RATE, block_size=128)
  for fixture in bench_external_authoring_fixtures() {
    let controller = CompiledDspTopologyController::from_nodes(
      fixture.nodes,
      ctx,
      crossfade_samples=128,
    ).unwrap()
    let edits = bench_external_invalid_topology_edit_batch()
    b.bench(name=fixture.name, fn() {
      let error = bench_expect_err(
        controller.queue_topology_edits(edits),
        "invalid topology edit batch",
      )
      b.keep(error)
    })
  }
}

///|
test "bench/external_authoring_diagnostics/queue_topology_recompile_rejected" (
  b : @bench.T,
) {
  let ctx = DspContext::new(sample_rate=BENCH_SAMPLE_RATE, block_size=128)
  for fixture in bench_external_authoring_fixtures() {
    let controller = CompiledDspTopologyController::from_nodes(
      fixture.nodes,
      ctx,
      crossfade_samples=128,
    ).unwrap()
    let edit = bench_external_recompile_rejected_topology_edit(fixture)
    b.bench(name=fixture.name, fn() {
      let error = bench_expect_err(
        controller.queue_topology_edit(edit),
        "topology recompile rejection",
      )
      b.keep(error)
    })
  }
}

///|
test "bench/external_authoring_diagnostics/queue_topology_pending_rejection" (
  b : @bench.T,
) {
  let ctx = DspContext::new(sample_rate=BENCH_SAMPLE_RATE, block_size=128)
  for fixture in bench_external_authoring_fixtures() {
    let controller = CompiledDspTopologyController::from_nodes(
      fixture.nodes,
      ctx,
      crossfade_samples=128,
    ).unwrap()
    controller
    .queue_topology_edit(bench_external_valid_replace_edit(0.55))
    .unwrap()
    b.bench(name=fixture.name, fn() {
      let error = bench_expect_err(
        controller.queue_topology_edit(bench_external_valid_replace_edit(0.56)),
        "pending topology queue",
      )
      b.keep(error)
    })
  }
}

///|
test "bench/external_authoring_diagnostics/compile_result_missing_output" (
  b : @bench.T,
) {
  bench_external_compile_result_rejection(
    b, bench_external_missing_output_template, "compile missing output",
  )
}

///|
test "bench/external_authoring_diagnostics/compile_result_multiple_outputs" (
  b : @bench.T,
) {
  bench_external_compile_result_rejection(
    b, bench_external_multiple_outputs_template, "compile multiple outputs",
  )
}

///|
test "bench/external_authoring_diagnostics/compile_result_invalid_input" (
  b : @bench.T,
) {
  bench_external_compile_result_rejection(
    b, bench_external_invalid_input_template, "compile invalid input",
  )
}

///|
test "bench/external_authoring_diagnostics/compile_result_invalid_param" (
  b : @bench.T,
) {
  bench_external_compile_result_rejection(
    b, bench_external_invalid_param_template, "compile invalid param",
  )
}

// ---- Realistic external authoring/control shape benchmarks ----
// WHY separate from the linear fixtures: these keep the same boundary
// decomposition while exercising fan-out, mix-heavy fan-in, terminal stereo,
// and feedback-capable authoring snapshots.

///|
test "bench/external_authoring/realistic_template_analyze" (b : @bench.T) {
  bench_external_template_analyze_group(
    b,
    bench_external_realistic_authoring_fixtures(),
  )
}

///|
test "bench/external_authoring/realistic_control_binding_generation" (
  b : @bench.T,
) {
  bench_external_control_binding_generation_group(
    b,
    bench_external_realistic_authoring_fixtures(),
  )
}

///|
test "bench/external_authoring/realistic_control_binding_validation" (
  b : @bench.T,
) {
  bench_external_control_binding_validation_group(
    b,
    bench_external_realistic_authoring_fixtures(),
  )
}

///|
test "bench/external_authoring/realistic_string_control_resolution" (
  b : @bench.T,
) {
  bench_external_string_control_resolution_group(
    b,
    bench_external_realistic_authoring_fixtures(),
  )
}

///|
test "bench/external_control/realistic_apply_param_batch_compiled" (
  b : @bench.T,
) {
  let ctx = DspContext::new(sample_rate=BENCH_SAMPLE_RATE, block_size=128)
  for fixture in bench_external_realistic_authoring_fixtures() {
    let controls_a = bench_external_control_batch(fixture, 0.01)
    let controls_b = bench_external_control_batch(fixture, 0.02)
    let use_b = @ref.new(false)
    match fixture.graph_kind {
      MonoExternalGraph => {
        let compiled = CompiledDsp::compile(
          CompiledTemplate::analyze(fixture.nodes),
          ctx,
        ).unwrap()
        b.bench(name=fixture.name, fn() {
          let controls = if use_b.val { controls_b } else { controls_a }
          use_b.val = !use_b.val
          compiled.apply_controls(controls).unwrap()
          b.keep(compiled)
        })
      }
      StereoExternalGraph => {
        let compiled = CompiledStereoDsp::compile(
          CompiledTemplate::analyze(fixture.nodes),
          ctx,
        ).unwrap()
        b.bench(name=fixture.name, fn() {
          let controls = if use_b.val { controls_b } else { controls_a }
          use_b.val = !use_b.val
          compiled.apply_controls(controls).unwrap()
          b.keep(compiled)
        })
      }
    }
  }
}

///|
test "bench/external_control/realistic_apply_param_batch_topology_controller" (
  b : @bench.T,
) {
  let ctx = DspContext::new(sample_rate=BENCH_SAMPLE_RATE, block_size=128)
  for fixture in bench_external_realistic_authoring_fixtures() {
    let controls_a = bench_external_control_batch(fixture, 0.01)
    let controls_b = bench_external_control_batch(fixture, 0.02)
    let use_b = @ref.new(false)
    match fixture.graph_kind {
      MonoExternalGraph => {
        let controller = match
          CompiledDspTopologyController::from_nodes(
            fixture.nodes,
            ctx,
            crossfade_samples=128,
          ) {
          Some(controller) => controller
          None => abort("expected mono topology controller for \{fixture.name}")
        }
        b.bench(name=fixture.name, fn() {
          let controls = if use_b.val { controls_b } else { controls_a }
          use_b.val = !use_b.val
          match controller.apply_controls(controls) {
            Ok(_) => ()
            Err(error) =>
              abort(
                "expected mono topology controls for \{fixture.name}, got \{error}",
              )
          }
          b.keep(controller)
        })
      }
      StereoExternalGraph => {
        let controller = match
          CompiledStereoDspTopologyController::from_nodes(
            fixture.nodes,
            ctx,
            crossfade_samples=128,
          ) {
          Some(controller) => controller
          None =>
            abort("expected stereo topology controller for \{fixture.name}")
        }
        b.bench(name=fixture.name, fn() {
          let controls = if use_b.val { controls_b } else { controls_a }
          use_b.val = !use_b.val
          match controller.apply_controls(controls) {
            Ok(_) => ()
            Err(error) =>
              abort(
                "expected stereo topology controls for \{fixture.name}, got \{error}",
              )
          }
          b.keep(controller)
        })
      }
    }
  }
}

///|
test "bench/external_authoring/realistic_shape_rewire_roundtrip" (b : @bench.T) {
  for fixture in bench_external_realistic_authoring_fixtures() {
    let doc = bench_external_doc(fixture)
    b.bench(name=fixture.name, fn() {
      let edited = bench_external_shape_rewire_roundtrip(doc, fixture)
      b.keep(edited)
    })
  }
}

///|
test "bench/external_authoring/realistic_compile_prepared_shape_change" (
  b : @bench.T,
) {
  let ctx = DspContext::new(sample_rate=BENCH_SAMPLE_RATE, block_size=128)
  for fixture in bench_external_realistic_authoring_fixtures() {
    let doc = bench_external_doc(fixture)
    let edited_doc = bench_external_shape_rewire_doc(doc, fixture)
    let template_a = doc.analyze()
    let template_b = edited_doc.analyze()
    let use_b = @ref.new(false)
    match fixture.graph_kind {
      MonoExternalGraph =>
        b.bench(name=fixture.name, fn() {
          let template = if use_b.val { template_b } else { template_a }
          use_b.val = !use_b.val
          let compiled = CompiledDsp::compile_result(template, ctx)
          b.keep(compiled)
        })
      StereoExternalGraph =>
        b.bench(name=fixture.name, fn() {
          let template = if use_b.val { template_b } else { template_a }
          use_b.val = !use_b.val
          let compiled = CompiledStereoDsp::compile_result(template, ctx)
          b.keep(compiled)
        })
    }
  }
}

///|
test "bench/external_authoring/realistic_queue_prepared_hotswap_setup" (
  b : @bench.T,
) {
  let ctx = DspContext::new(sample_rate=BENCH_SAMPLE_RATE, block_size=128)
  for fixture in bench_external_realistic_authoring_fixtures() {
    let doc = bench_external_doc(fixture)
    let edited_doc = bench_external_shape_rewire_doc(doc, fixture)
    let use_b = @ref.new(false)
    match fixture.graph_kind {
      MonoExternalGraph => {
        let compiled_a = CompiledDsp::compile(doc.analyze(), ctx).unwrap()
        let compiled_b = CompiledDsp::compile(edited_doc.analyze(), ctx).unwrap()
        b.bench(name=fixture.name, fn() {
          let active = if use_b.val { compiled_b } else { compiled_a }
          let next = if use_b.val { compiled_a } else { compiled_b }
          use_b.val = !use_b.val
          let hs = CompiledDspHotSwap::from_graph(active, crossfade_samples=128)
          hs.queue_swap(next).unwrap()
          b.keep(hs)
        })
      }
      StereoExternalGraph => {
        let compiled_a = CompiledStereoDsp::compile(doc.analyze(), ctx).unwrap()
        let compiled_b = CompiledStereoDsp::compile(edited_doc.analyze(), ctx).unwrap()
        b.bench(name=fixture.name, fn() {
          let active = if use_b.val { compiled_b } else { compiled_a }
          let next = if use_b.val { compiled_a } else { compiled_b }
          use_b.val = !use_b.val
          let hs = CompiledStereoDspHotSwap::from_graph(
            active,
            crossfade_samples=128,
          )
          hs.queue_swap(next).unwrap()
          b.keep(hs)
        })
      }
    }
  }
}
