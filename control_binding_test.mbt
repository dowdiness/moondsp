///|
/// 4-node template where index 1 (the second Oscillator) has no downstream
/// consumer and is eliminated by optimize_graph. Used by orphan-binding tests.
fn orphan_template() -> Array[@moondsp.DspNode] {
  [
    @moondsp.DspNode::oscillator(@moondsp.Waveform::Sine, 440.0), // index 0 — live (feeds Output via gain)
    @moondsp.DspNode::oscillator(@moondsp.Waveform::Sine, 880.0), // index 1 — orphan
    @moondsp.DspNode::gain(0, 0.3),
    @moondsp.DspNode::output(2),
  ]
}

///|
test "build: valid bindings produce Ok" {
  let template = [
    @moondsp.DspNode::oscillator(@moondsp.Waveform::Sine, 440.0),
    @moondsp.DspNode::gain(0, 0.3),
    @moondsp.DspNode::output(1),
  ]
  let result = @moondsp.ControlBindingBuilder::new()
    .bind(key="note", node_index=0, slot=@moondsp.GraphParamSlot::Value0)
    .bind(key="gain", node_index=1, slot=@moondsp.GraphParamSlot::Value0)
    .build(@moondsp.AnalyzedGraph::analyze(template))
  assert_true(result is Ok(_))
}

///|
test "build: invalid node index returns InvalidNodeIndex" {
  let template = [@moondsp.DspNode::constant(1.0), @moondsp.DspNode::output(0)]
  let result = @moondsp.ControlBindingBuilder::new()
    .bind(key="note", node_index=5, slot=@moondsp.GraphParamSlot::Value0)
    .build(@moondsp.AnalyzedGraph::analyze(template))
  @debug.assert_eq(
    result,
    Err(@moondsp.ControlBindingError::InvalidNodeIndex(5)),
  )
}

///|
test "build: negative node index returns InvalidNodeIndex" {
  let template = [@moondsp.DspNode::constant(1.0), @moondsp.DspNode::output(0)]
  let result = @moondsp.ControlBindingBuilder::new()
    .bind(key="note", node_index=-1, slot=@moondsp.GraphParamSlot::Value0)
    .build(@moondsp.AnalyzedGraph::analyze(template))
  @debug.assert_eq(
    result,
    Err(@moondsp.ControlBindingError::InvalidNodeIndex(-1)),
  )
}

///|
test "build: invalid slot for node returns InvalidSlotForNode" {
  let template = [@moondsp.DspNode::constant(1.0), @moondsp.DspNode::output(0)]
  let result = @moondsp.ControlBindingBuilder::new()
    .bind(key="x", node_index=1, slot=@moondsp.GraphParamSlot::Value0)
    .build(@moondsp.AnalyzedGraph::analyze(template))
  @debug.assert_eq(
    result,
    Err(
      @moondsp.ControlBindingError::InvalidSlotForNode(
        1,
        @moondsp.GraphParamSlot::Value0,
      ),
    ),
  )
}

///|
test "build: duplicate keys returns DuplicateKey" {
  // Oscillator feeds gain feeds output — all nodes are live (osc is not
  // foldable, so constant-folding cannot eliminate it).
  let template = [
    @moondsp.DspNode::oscillator(@moondsp.Waveform::Sine, 440.0),
    @moondsp.DspNode::gain(0, 0.3),
    @moondsp.DspNode::output(1),
  ]
  let result = @moondsp.ControlBindingBuilder::new()
    .bind(key="freq", node_index=0, slot=@moondsp.GraphParamSlot::Value0)
    .bind(key="freq", node_index=1, slot=@moondsp.GraphParamSlot::Value0)
    .build(@moondsp.AnalyzedGraph::analyze(template))
  @debug.assert_eq(
    result,
    Err(@moondsp.ControlBindingError::DuplicateKey("freq")),
  )
}

///|
test "build: multiple keys mapping to same node and slot are allowed" {
  let template = [
    @moondsp.DspNode::oscillator(@moondsp.Waveform::Sine, 440.0),
    @moondsp.DspNode::output(0),
  ]
  let result = @moondsp.ControlBindingBuilder::new()
    .bind(key="freq", node_index=0, slot=@moondsp.GraphParamSlot::Value0)
    .bind(key="note", node_index=0, slot=@moondsp.GraphParamSlot::Value0)
    .build(@moondsp.AnalyzedGraph::analyze(template))
  assert_true(result is Ok(_))
}

///|
test "build: empty builder produces Ok with empty map" {
  let template = [@moondsp.DspNode::constant(1.0), @moondsp.DspNode::output(0)]
  let result = @moondsp.ControlBindingBuilder::new().build(
    @moondsp.AnalyzedGraph::analyze(template),
  )
  assert_true(result is Ok(_))
}

///|
test "resolve: all present keys converted in binding insertion order" {
  let template = [
    @moondsp.DspNode::oscillator(@moondsp.Waveform::Sine, 440.0),
    @moondsp.DspNode::gain(0, 0.3),
    @moondsp.DspNode::output(1),
  ]
  let map = @moondsp.ControlBindingBuilder::new()
    .bind(key="note", node_index=0, slot=@moondsp.GraphParamSlot::Value0)
    .bind(key="gain", node_index=1, slot=@moondsp.GraphParamSlot::Value0)
    .build(@moondsp.AnalyzedGraph::analyze(template))
    .unwrap()
  let controls : Map[String, Double] = { "note": 60.0, "gain": 0.5 }
  let result = map.resolve_controls(controls)
  @debug.assert_eq(result.length(), 2)
  @debug.assert_eq(result[0].node_index(), 0)
  @debug.assert_eq(result[0].slot(), @moondsp.GraphParamSlot::Value0)
  @debug.assert_eq(result[0].value(), 60.0)
  @debug.assert_eq(result[1].node_index(), 1)
  @debug.assert_eq(result[1].slot(), @moondsp.GraphParamSlot::Value0)
  @debug.assert_eq(result[1].value(), 0.5)
}

///|
test "resolve: partial map skips missing keys" {
  let template = [
    @moondsp.DspNode::oscillator(@moondsp.Waveform::Sine, 440.0),
    @moondsp.DspNode::gain(0, 0.3),
    @moondsp.DspNode::output(1),
  ]
  let map = @moondsp.ControlBindingBuilder::new()
    .bind(key="note", node_index=0, slot=@moondsp.GraphParamSlot::Value0)
    .bind(key="gain", node_index=1, slot=@moondsp.GraphParamSlot::Value0)
    .build(@moondsp.AnalyzedGraph::analyze(template))
    .unwrap()
  let controls : Map[String, Double] = { "gain": 0.8 }
  let result = map.resolve_controls(controls)
  @debug.assert_eq(result.length(), 1)
  @debug.assert_eq(result[0].node_index(), 1)
  @debug.assert_eq(result[0].value(), 0.8)
}

///|
test "resolve: extra keys in map are ignored" {
  let template = [@moondsp.DspNode::constant(1.0), @moondsp.DspNode::output(0)]
  let map = @moondsp.ControlBindingBuilder::new()
    .bind(key="freq", node_index=0, slot=@moondsp.GraphParamSlot::Value0)
    .build(@moondsp.AnalyzedGraph::analyze(template))
    .unwrap()
  let controls : Map[String, Double] = { "freq": 220.0, "unknown": 99.0 }
  let result = map.resolve_controls(controls)
  @debug.assert_eq(result.length(), 1)
  @debug.assert_eq(result[0].value(), 220.0)
}

///|
test "resolve: empty map produces empty controls" {
  let template = [@moondsp.DspNode::constant(1.0), @moondsp.DspNode::output(0)]
  let map = @moondsp.ControlBindingBuilder::new()
    .bind(key="freq", node_index=0, slot=@moondsp.GraphParamSlot::Value0)
    .build(@moondsp.AnalyzedGraph::analyze(template))
    .unwrap()
  let controls : Map[String, Double] = Map([])
  let result = map.resolve_controls(controls)
  @debug.assert_eq(result.length(), 0)
}

///|
test "resolve: empty binding map produces empty controls" {
  let template = [@moondsp.DspNode::constant(1.0), @moondsp.DspNode::output(0)]
  let map = @moondsp.ControlBindingBuilder::new()
    .build(@moondsp.AnalyzedGraph::analyze(template))
    .unwrap()
  let controls : Map[String, Double] = { "freq": 440.0 }
  let result = map.resolve_controls(controls)
  @debug.assert_eq(result.length(), 0)
}

///|
test "integration: resolved controls accepted by VoicePool::note_on" {
  let ctx = @moondsp.DspContext::new(sample_rate=48000.0, block_size=16)
  let template = [
    @moondsp.DspNode::oscillator(@moondsp.Waveform::Sine, 440.0),
    @moondsp.DspNode::gain(0, 0.3),
    @moondsp.DspNode::output(1),
  ]
  let pool = @moondsp.VoicePool::new(
    @moondsp.AnalyzedGraph::analyze(template),
    ctx,
    max_voices=4,
  ).unwrap()
  let bindings = @moondsp.ControlBindingBuilder::new()
    .bind(key="note", node_index=0, slot=@moondsp.GraphParamSlot::Value0)
    .bind(key="gain", node_index=1, slot=@moondsp.GraphParamSlot::Value0)
    .build(@moondsp.AnalyzedGraph::analyze(template))
    .unwrap()
  let controls : Map[String, Double] = { "note": 880.0, "gain": 0.5 }
  let resolved = bindings.resolve_controls(controls)
  let handle = pool.note_on(resolved)
  assert_true(handle is Some(_))
  assert_true(pool.voice_state(handle.unwrap()) is @moondsp.VoiceState::Active)
}

///|
test "build: post-build bind does not mutate validated map" {
  let template = [@moondsp.DspNode::constant(1.0), @moondsp.DspNode::output(0)]
  let builder = @moondsp.ControlBindingBuilder::new().bind(
    key="freq",
    node_index=0,
    slot=@moondsp.GraphParamSlot::Value0,
  )
  let map = builder.build(@moondsp.AnalyzedGraph::analyze(template)).unwrap()
  // Mutate the builder after build — must not affect the validated map
  ignore(
    builder.bind(
      key="extra",
      node_index=0,
      slot=@moondsp.GraphParamSlot::Value0,
    ),
  )
  @debug.assert_eq(map.length(), 1)
}

///|
test "build: live binding on surviving node produces Ok" {
  let template = [
    @moondsp.DspNode::oscillator(@moondsp.Waveform::Sine, 440.0),
    @moondsp.DspNode::gain(0, 0.3),
    @moondsp.DspNode::output(1),
  ]
  let result = @moondsp.ControlBindingBuilder::new()
    .bind(key="freq", node_index=0, slot=@moondsp.GraphParamSlot::Value0)
    .build(@moondsp.AnalyzedGraph::analyze(template))
  assert_true(result is Ok(_))
}

///|
test "build: orphan binding returns OrphanBinding with key and index" {
  let result = @moondsp.ControlBindingBuilder::new()
    .bind(key="orphan_freq", node_index=1, slot=@moondsp.GraphParamSlot::Value0)
    .build(@moondsp.AnalyzedGraph::analyze(orphan_template()))
  @debug.assert_eq(
    result,
    Err(@moondsp.ControlBindingError::OrphanBinding("orphan_freq", 1)),
  )
}

///|
test "build: orphan error carries the specific binding's key" {
  // Two bindings on the same orphan node with different keys — build reports
  // the FIRST encountered (insertion order).
  let result = @moondsp.ControlBindingBuilder::new()
    .bind(key="orphan_a", node_index=1, slot=@moondsp.GraphParamSlot::Value0)
    .bind(key="orphan_b", node_index=1, slot=@moondsp.GraphParamSlot::Value0)
    .build(@moondsp.AnalyzedGraph::analyze(orphan_template()))
  @debug.assert_eq(
    result,
    Err(@moondsp.ControlBindingError::OrphanBinding("orphan_a", 1)),
  )
}

///|
test "build: slot error preempts orphan check" {
  // Node 1 is Output — has no Value0 slot. Slot check runs before orphan
  // check per the per-binding validation ordering.
  let template = [@moondsp.DspNode::constant(1.0), @moondsp.DspNode::output(0)]
  let result = @moondsp.ControlBindingBuilder::new()
    .bind(key="x", node_index=1, slot=@moondsp.GraphParamSlot::Value0)
    .build(@moondsp.AnalyzedGraph::analyze(template))
  @debug.assert_eq(
    result,
    Err(
      @moondsp.ControlBindingError::InvalidSlotForNode(
        1,
        @moondsp.GraphParamSlot::Value0,
      ),
    ),
  )
}

///|
test "build: bounds error preempts orphan check" {
  // Out-of-range node_index reports InvalidNodeIndex regardless of
  // optimization state.
  let result = @moondsp.ControlBindingBuilder::new()
    .bind(key="x", node_index=99, slot=@moondsp.GraphParamSlot::Value0)
    .build(@moondsp.AnalyzedGraph::analyze(orphan_template()))
  @debug.assert_eq(
    result,
    Err(@moondsp.ControlBindingError::InvalidNodeIndex(99)),
  )
}

///|
test "build: orphan preempts duplicate key" {
  // First binding is orphan; duplicate appears later. Orphan reported first.
  let result = @moondsp.ControlBindingBuilder::new()
    .bind(key="dup", node_index=1, slot=@moondsp.GraphParamSlot::Value0)
    .bind(key="dup", node_index=0, slot=@moondsp.GraphParamSlot::Value0)
    .build(@moondsp.AnalyzedGraph::analyze(orphan_template()))
  @debug.assert_eq(
    result,
    Err(@moondsp.ControlBindingError::OrphanBinding("dup", 1)),
  )
}

///|
test "build: duplicate key still reported for live-node bindings" {
  // Regression: no orphans present, duplicate check still fires.
  let template = [
    @moondsp.DspNode::oscillator(@moondsp.Waveform::Sine, 440.0),
    @moondsp.DspNode::gain(0, 0.3),
    @moondsp.DspNode::output(1),
  ]
  let result = @moondsp.ControlBindingBuilder::new()
    .bind(key="g", node_index=0, slot=@moondsp.GraphParamSlot::Value0)
    .bind(key="g", node_index=1, slot=@moondsp.GraphParamSlot::Value0)
    .build(@moondsp.AnalyzedGraph::analyze(template))
  @debug.assert_eq(result, Err(@moondsp.ControlBindingError::DuplicateKey("g")))
}

///|
test "build: empty builder still succeeds on any template" {
  let result = @moondsp.ControlBindingBuilder::new().build(
    @moondsp.AnalyzedGraph::analyze(orphan_template()),
  )
  assert_true(result is Ok(_))
}

///|
test "build: constant-fed source and Gain bindings remain valid" {
  let template = [
    @moondsp.DspNode::constant(1.0),
    @moondsp.DspNode::gain(0, 0.3),
    @moondsp.DspNode::output(1),
  ]
  let bindings = @moondsp.ControlBindingBuilder::new()
    .bind(key="base", node_index=0, slot=@moondsp.GraphParamSlot::Value0)
    .bind(key="gain", node_index=1, slot=@moondsp.GraphParamSlot::Value0)
    .build(@moondsp.AnalyzedGraph::analyze(template))
    .unwrap()
  @debug.assert_eq(bindings.length(), 2)
}

///|
test "binding defaults belong to each validated template" {
  let builder = @moondsp.ControlBindingBuilder::new().bind(
    key="note",
    node_index=0,
    slot=@moondsp.GraphParamSlot::Value0,
  )
  let original = builder
    .build(
      @moondsp.AnalyzedGraph::analyze([
        @moondsp.DspNode::oscillator(@moondsp.Waveform::Sine, 440.0),
        @moondsp.DspNode::output(0),
      ]),
    )
    .unwrap()
  let changed = builder
    .build(
      @moondsp.AnalyzedGraph::analyze([
        @moondsp.DspNode::oscillator(@moondsp.Waveform::Sine, 880.0),
        @moondsp.DspNode::output(0),
      ]),
    )
    .unwrap()
  assert_eq(original.default_value("note"), Some(440.0))
  assert_eq(changed.default_value("note"), Some(880.0))
  assert_eq(original.default_value("missing"), None)
}
