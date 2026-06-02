///|
fn editor_preview_gid(value : String) -> GraphNodeId {
  let result = try? GraphNodeId::from_string(value)
  match result {
    Ok(id) => id
    Err(_) => abort("expected valid graph node id")
  }
}

///|
fn editor_preview_unwrap_doc(
  result : Result[GraphTemplateDoc, GraphTemplateDocError],
) -> GraphTemplateDoc {
  match result {
    Ok(doc) => doc
    Err(error) => abort("expected graph template doc, got \{error}")
  }
}

///|
fn editor_preview_base_doc() -> GraphTemplateDoc {
  editor_preview_unwrap_doc(
    try? GraphTemplateDoc::from_nodes(
      ids=[
        editor_preview_gid("osc"),
        editor_preview_gid("gain"),
        editor_preview_gid("out"),
      ],
      nodes=[
        DspNode::oscillator(Waveform::Sine, 440.0),
        DspNode::gain(0, 0.3),
        DspNode::output(1),
      ],
    ),
  )
}

///|
test "editor preview handoff: stages topology replacement and parameter update" {
  let ctx = DspContext::new(sample_rate=48000.0, block_size=16)
  let active_doc = editor_preview_base_doc()
  let active_runtime = CompiledDsp::compile_result(active_doc.analyze(), ctx).unwrap()
  let preview = CompiledDspHotSwap::from_graph(
    active_runtime,
    crossfade_samples=16,
  )

  let replacement_doc = editor_preview_unwrap_doc(
    try? active_doc.insert_node(
      editor_preview_gid("clip"),
      editor_preview_gid("out"),
      GraphTopologyInputSlot::Input0,
      DspNode::clip(1, 0.75),
    ),
  )
  let replacement_template = replacement_doc.analyze()
  let replacement_index = replacement_doc.index_map()
  let replacement_bindings = match
    replacement_index.bind_control(
      ControlBindingBuilder::new(),
      "gain",
      editor_preview_gid("gain"),
      GraphParamSlot::Value0,
    ) {
    Some(builder) => builder.build(replacement_template).unwrap()
    None => fail("expected stable gain id to bind")
  }
  @debug.assert_eq(replacement_bindings.length(), 1)

  let replacement_runtime = CompiledDsp::compile_result(
    replacement_template, ctx,
  ).unwrap()
  preview.queue_swap(replacement_runtime).unwrap()

  // Parameter-only UI edits target the current authoring index for the stable
  // node ID and are applied as controls, not as graph recompiles. Because a
  // hot-swap is pending, the runtime validates and applies this batch to both
  // the active and pending graphs transactionally.
  let gain_control = match
    replacement_index.set_param(
      editor_preview_gid("gain"),
      GraphParamSlot::Value0,
      0.2,
    ) {
    Some(control) => control
    None => fail("expected stable gain id to resolve to a control")
  }
  preview.apply_control(gain_control).unwrap()

  let output = AudioBuffer::filled(16)
  preview.process(ctx, output)
  assert_true(output.all(fn(sample) { is_finite(sample) }))
}

///|
test "editor preview handoff: failed candidate maps diagnostics to stable ids" {
  let ctx = DspContext::new(sample_rate=48000.0, block_size=16)
  let last_good = CompiledDsp::compile_result(
    CompiledTemplate::analyze([DspNode::constant(0.25), DspNode::output(0)]),
    ctx,
  ).unwrap()
  let candidate = editor_preview_unwrap_doc(
    try? GraphTemplateDoc::from_nodes(
      ids=[editor_preview_gid("gain"), editor_preview_gid("out")],
      nodes=[DspNode::gain(99, 0.5), DspNode::output(0)],
    ),
  )

  match CompiledDsp::compile_result(candidate.analyze(), ctx) {
    Err(GraphCompileError::InvalidInput(index, kind, slot, input)) => {
      @debug.assert_eq(index, 0)
      @debug.assert_eq(kind, DspNodeKind::Gain)
      @debug.assert_eq(slot, GraphTopologyInputSlot::Input0)
      @debug.assert_eq(input, 99)
      match candidate.index_map().node_id_at(index) {
        Some(id) => @debug.assert_eq(id.value(), "gain")
        None => fail("expected compile diagnostic to map to a stable node id")
      }
    }
    _ => fail("expected invalid preview candidate to report InvalidInput")
  }

  // The failed candidate must not replace the previous preview runtime.
  let output = AudioBuffer::filled(16)
  last_good.process(ctx, output)
  @debug.assert_eq(output.get(0), 0.25)
}
