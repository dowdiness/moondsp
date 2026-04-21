///|
/// 4-node template where index 1 (the second Oscillator) has no downstream
/// consumer and is eliminated by optimize_graph. Used by orphan-binding tests.
fn orphan_template() -> Array[DspNode] {
  [
    DspNode::oscillator(Waveform::Sine, 440.0), // index 0 — live (feeds Output via gain)
    DspNode::oscillator(Waveform::Sine, 880.0), // index 1 — orphan
    DspNode::gain(0, 0.3),
    DspNode::output(2),
  ]
}

///|
test "build: valid bindings produce Ok" {
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::gain(0, 0.3),
    DspNode::output(1),
  ]
  let result = ControlBindingBuilder::new()
    .bind(key="note", node_index=0, slot=GraphParamSlot::Value0)
    .bind(key="gain", node_index=1, slot=GraphParamSlot::Value0)
    .build(CompiledTemplate::analyze(template))
  assert_true(result is Ok(_))
}

///|
test "build: invalid node index returns InvalidNodeIndex" {
  let template = [DspNode::constant(1.0), DspNode::output(0)]
  let result = ControlBindingBuilder::new()
    .bind(key="note", node_index=5, slot=GraphParamSlot::Value0)
    .build(CompiledTemplate::analyze(template))
  assert_eq(result, Err(ControlBindingError::InvalidNodeIndex(5)))
}

///|
test "build: negative node index returns InvalidNodeIndex" {
  let template = [DspNode::constant(1.0), DspNode::output(0)]
  let result = ControlBindingBuilder::new()
    .bind(key="note", node_index=-1, slot=GraphParamSlot::Value0)
    .build(CompiledTemplate::analyze(template))
  assert_eq(result, Err(ControlBindingError::InvalidNodeIndex(-1)))
}

///|
test "build: invalid slot for node returns InvalidSlotForNode" {
  let template = [DspNode::constant(1.0), DspNode::output(0)]
  let result = ControlBindingBuilder::new()
    .bind(key="x", node_index=1, slot=GraphParamSlot::Value0)
    .build(CompiledTemplate::analyze(template))
  assert_eq(
    result,
    Err(ControlBindingError::InvalidSlotForNode(1, GraphParamSlot::Value0)),
  )
}

///|
test "build: duplicate keys returns DuplicateKey" {
  // Oscillator feeds gain feeds output — all nodes are live (osc is not
  // foldable, so constant-folding cannot eliminate it).
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::gain(0, 0.3),
    DspNode::output(1),
  ]
  let result = ControlBindingBuilder::new()
    .bind(key="freq", node_index=0, slot=GraphParamSlot::Value0)
    .bind(key="freq", node_index=1, slot=GraphParamSlot::Value0)
    .build(CompiledTemplate::analyze(template))
  assert_eq(result, Err(ControlBindingError::DuplicateKey("freq")))
}

///|
test "build: multiple keys mapping to same node and slot are allowed" {
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::output(0),
  ]
  let result = ControlBindingBuilder::new()
    .bind(key="freq", node_index=0, slot=GraphParamSlot::Value0)
    .bind(key="note", node_index=0, slot=GraphParamSlot::Value0)
    .build(CompiledTemplate::analyze(template))
  assert_true(result is Ok(_))
}

///|
test "build: empty builder produces Ok with empty map" {
  let template = [DspNode::constant(1.0), DspNode::output(0)]
  let result = ControlBindingBuilder::new().build(
    CompiledTemplate::analyze(template),
  )
  assert_true(result is Ok(_))
}

///|
test "resolve: all present keys converted in binding insertion order" {
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::gain(0, 0.3),
    DspNode::output(1),
  ]
  let map = ControlBindingBuilder::new()
    .bind(key="note", node_index=0, slot=GraphParamSlot::Value0)
    .bind(key="gain", node_index=1, slot=GraphParamSlot::Value0)
    .build(CompiledTemplate::analyze(template))
    .unwrap()
  let controls : Map[String, Double] = { "note": 60.0, "gain": 0.5 }
  let result = map.resolve_controls(controls)
  assert_eq(result.length(), 2)
  assert_eq(result[0].node_index, 0)
  assert_eq(result[0].slot, GraphParamSlot::Value0)
  assert_eq(result[0].value, 60.0)
  assert_eq(result[1].node_index, 1)
  assert_eq(result[1].slot, GraphParamSlot::Value0)
  assert_eq(result[1].value, 0.5)
}

///|
test "resolve: partial map skips missing keys" {
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::gain(0, 0.3),
    DspNode::output(1),
  ]
  let map = ControlBindingBuilder::new()
    .bind(key="note", node_index=0, slot=GraphParamSlot::Value0)
    .bind(key="gain", node_index=1, slot=GraphParamSlot::Value0)
    .build(CompiledTemplate::analyze(template))
    .unwrap()
  let controls : Map[String, Double] = { "gain": 0.8 }
  let result = map.resolve_controls(controls)
  assert_eq(result.length(), 1)
  assert_eq(result[0].node_index, 1)
  assert_eq(result[0].value, 0.8)
}

///|
test "resolve: extra keys in map are ignored" {
  let template = [DspNode::constant(1.0), DspNode::output(0)]
  let map = ControlBindingBuilder::new()
    .bind(key="freq", node_index=0, slot=GraphParamSlot::Value0)
    .build(CompiledTemplate::analyze(template))
    .unwrap()
  let controls : Map[String, Double] = { "freq": 220.0, "unknown": 99.0 }
  let result = map.resolve_controls(controls)
  assert_eq(result.length(), 1)
  assert_eq(result[0].value, 220.0)
}

///|
test "resolve: empty map produces empty controls" {
  let template = [DspNode::constant(1.0), DspNode::output(0)]
  let map = ControlBindingBuilder::new()
    .bind(key="freq", node_index=0, slot=GraphParamSlot::Value0)
    .build(CompiledTemplate::analyze(template))
    .unwrap()
  let controls : Map[String, Double] = {}
  let result = map.resolve_controls(controls)
  assert_eq(result.length(), 0)
}

///|
test "resolve: empty binding map produces empty controls" {
  let template = [DspNode::constant(1.0), DspNode::output(0)]
  let map = ControlBindingBuilder::new()
    .build(CompiledTemplate::analyze(template))
    .unwrap()
  let controls : Map[String, Double] = { "freq": 440.0 }
  let result = map.resolve_controls(controls)
  assert_eq(result.length(), 0)
}

///|
test "integration: resolved controls accepted by VoicePool::note_on" {
  let ctx = DspContext::new(48000.0, 16)
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::gain(0, 0.3),
    DspNode::output(1),
  ]
  let pool = VoicePool::new(template, ctx, max_voices=4).unwrap()
  let bindings = ControlBindingBuilder::new()
    .bind(key="note", node_index=0, slot=GraphParamSlot::Value0)
    .bind(key="gain", node_index=1, slot=GraphParamSlot::Value0)
    .build(CompiledTemplate::analyze(template))
    .unwrap()
  let controls : Map[String, Double] = { "note": 880.0, "gain": 0.5 }
  let resolved = bindings.resolve_controls(controls)
  let handle = pool.note_on(resolved)
  assert_true(handle is Some(_))
  assert_true(pool.voice_state(handle.unwrap()) is VoiceState::Active)
}

///|
test "build: post-build bind does not mutate validated map" {
  let template = [DspNode::constant(1.0), DspNode::output(0)]
  let builder = ControlBindingBuilder::new().bind(
    key="freq",
    node_index=0,
    slot=GraphParamSlot::Value0,
  )
  let map = builder.build(CompiledTemplate::analyze(template)).unwrap()
  // Mutate the builder after build — must not affect the validated map
  ignore(builder.bind(key="extra", node_index=0, slot=GraphParamSlot::Value0))
  assert_eq(map.length(), 1)
}

///|
test "build: live binding on surviving node produces Ok" {
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::gain(0, 0.3),
    DspNode::output(1),
  ]
  let result = ControlBindingBuilder::new()
    .bind(key="freq", node_index=0, slot=GraphParamSlot::Value0)
    .build(CompiledTemplate::analyze(template))
  assert_true(result is Ok(_))
}

///|
test "build: orphan binding returns OrphanBinding with key and index" {
  let result = ControlBindingBuilder::new()
    .bind(key="orphan_freq", node_index=1, slot=GraphParamSlot::Value0)
    .build(CompiledTemplate::analyze(orphan_template()))
  assert_eq(result, Err(ControlBindingError::OrphanBinding("orphan_freq", 1)))
}

///|
test "build: orphan error carries the specific binding's key" {
  // Two bindings on the same orphan node with different keys — build reports
  // the FIRST encountered (insertion order).
  let result = ControlBindingBuilder::new()
    .bind(key="orphan_a", node_index=1, slot=GraphParamSlot::Value0)
    .bind(key="orphan_b", node_index=1, slot=GraphParamSlot::Value0)
    .build(CompiledTemplate::analyze(orphan_template()))
  assert_eq(result, Err(ControlBindingError::OrphanBinding("orphan_a", 1)))
}

///|
test "build: slot error preempts orphan check" {
  // Node 1 is Output — has no Value0 slot. Slot check runs before orphan
  // check per the per-binding validation ordering.
  let template = [DspNode::constant(1.0), DspNode::output(0)]
  let result = ControlBindingBuilder::new()
    .bind(key="x", node_index=1, slot=GraphParamSlot::Value0)
    .build(CompiledTemplate::analyze(template))
  assert_eq(
    result,
    Err(ControlBindingError::InvalidSlotForNode(1, GraphParamSlot::Value0)),
  )
}

///|
test "build: bounds error preempts orphan check" {
  // Out-of-range node_index reports InvalidNodeIndex regardless of
  // optimization state.
  let result = ControlBindingBuilder::new()
    .bind(key="x", node_index=99, slot=GraphParamSlot::Value0)
    .build(CompiledTemplate::analyze(orphan_template()))
  assert_eq(result, Err(ControlBindingError::InvalidNodeIndex(99)))
}

///|
test "build: orphan preempts duplicate key" {
  // First binding is orphan; duplicate appears later. Orphan reported first.
  let result = ControlBindingBuilder::new()
    .bind(key="dup", node_index=1, slot=GraphParamSlot::Value0)
    .bind(key="dup", node_index=0, slot=GraphParamSlot::Value0)
    .build(CompiledTemplate::analyze(orphan_template()))
  assert_eq(result, Err(ControlBindingError::OrphanBinding("dup", 1)))
}

///|
test "build: duplicate key still reported for live-node bindings" {
  // Regression: no orphans present, duplicate check still fires.
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::gain(0, 0.3),
    DspNode::output(1),
  ]
  let result = ControlBindingBuilder::new()
    .bind(key="g", node_index=0, slot=GraphParamSlot::Value0)
    .bind(key="g", node_index=1, slot=GraphParamSlot::Value0)
    .build(CompiledTemplate::analyze(template))
  assert_eq(result, Err(ControlBindingError::DuplicateKey("g")))
}

///|
test "build: empty builder still succeeds on any template" {
  let result = ControlBindingBuilder::new().build(
    CompiledTemplate::analyze(orphan_template()),
  )
  assert_true(result is Ok(_))
}

///|
test "build: orphan via constant-folding rejected" {
  // Coverage for the optimizer path that eliminates nodes via fold_constants
  // rather than dead-branch elimination. Gain is foldable; when its inputs
  // are constants, optimize_graph replaces the Gain with a Constant and the
  // upstream Constant becomes unreachable. A binding at the upstream
  // Constant's authoring index must be rejected as OrphanBinding.
  let template = [
    DspNode::constant(1.0), // index 0 — eliminated by fold_constants
    DspNode::gain(0, 0.3), // index 1 — foldable; folds to a new Constant
    DspNode::output(1), // index 2 — wires to the folded node
  ]
  let result = ControlBindingBuilder::new()
    .bind(key="base", node_index=0, slot=GraphParamSlot::Value0)
    .build(CompiledTemplate::analyze(template))
  assert_eq(result, Err(ControlBindingError::OrphanBinding("base", 0)))
}
