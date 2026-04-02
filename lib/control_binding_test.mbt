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
    .build(template)
  assert_true(result is Ok(_))
}

///|
test "build: invalid node index returns InvalidNodeIndex" {
  let template = [DspNode::constant(1.0), DspNode::output(0)]
  let result = ControlBindingBuilder::new()
    .bind(key="note", node_index=5, slot=GraphParamSlot::Value0)
    .build(template)
  assert_eq(result, Err(ControlBindingError::InvalidNodeIndex(5)))
}

///|
test "build: negative node index returns InvalidNodeIndex" {
  let template = [DspNode::constant(1.0), DspNode::output(0)]
  let result = ControlBindingBuilder::new()
    .bind(key="note", node_index=-1, slot=GraphParamSlot::Value0)
    .build(template)
  assert_eq(result, Err(ControlBindingError::InvalidNodeIndex(-1)))
}

///|
test "build: invalid slot for node returns InvalidSlotForNode" {
  let template = [DspNode::constant(1.0), DspNode::output(0)]
  let result = ControlBindingBuilder::new()
    .bind(key="x", node_index=1, slot=GraphParamSlot::Value0)
    .build(template)
  assert_eq(
    result,
    Err(ControlBindingError::InvalidSlotForNode(1, GraphParamSlot::Value0)),
  )
}

///|
test "build: duplicate keys returns DuplicateKey" {
  let template = [
    DspNode::constant(1.0),
    DspNode::gain(0, 0.3),
    DspNode::output(1),
  ]
  let result = ControlBindingBuilder::new()
    .bind(key="gain", node_index=0, slot=GraphParamSlot::Value0)
    .bind(key="gain", node_index=1, slot=GraphParamSlot::Value0)
    .build(template)
  assert_eq(result, Err(ControlBindingError::DuplicateKey("gain")))
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
    .build(template)
  assert_true(result is Ok(_))
}

///|
test "build: empty builder produces Ok with empty map" {
  let template = [DspNode::constant(1.0), DspNode::output(0)]
  let result = ControlBindingBuilder::new().build(template)
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
    .build(template)
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
    .build(template)
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
    .build(template)
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
    .build(template)
    .unwrap()
  let controls : Map[String, Double] = {}
  let result = map.resolve_controls(controls)
  assert_eq(result.length(), 0)
}

///|
test "resolve: empty binding map produces empty controls" {
  let template = [DspNode::constant(1.0), DspNode::output(0)]
  let map = ControlBindingBuilder::new().build(template).unwrap()
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
    .build(template)
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
  let map = builder.build(template).unwrap()
  // Mutate the builder after build — must not affect the validated map
  ignore(builder.bind(key="extra", node_index=0, slot=GraphParamSlot::Value0))
  assert_eq(map.length(), 1)
}
