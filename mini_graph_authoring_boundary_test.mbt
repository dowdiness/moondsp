///|
// Test-local bridge fixture for the Mini/graph authoring contract. It avoids
// adding production routing behavior while pinning the expected boundary shape.
struct MiniGraphPreparedTemplate {
  name : String
  bindings : ControlBindingMap
  runtime : CompiledDsp
}

///|
enum MiniGraphBridgeError {
  MissingSoundKey
  MissingTemplate(String)
} derive(Debug, Eq)

///|
fn prepared_bd_graph_template(ctx : DspContext) -> MiniGraphPreparedTemplate {
  let nodes = [
    DspNode::oscillator(Waveform::Sine, 110.0),
    DspNode::biquad(input=0, mode=BiquadMode::LowPass, cutoff_hz=800.0, q=0.707),
    DspNode::gain(1, 0.2),
    DspNode::output(2),
  ]
  let template = CompiledTemplate::analyze(nodes)
  let bindings = ControlBindingBuilder::new()
    .bind(key="cutoff", node_index=1, slot=GraphParamSlot::Value0)
    .bind(key="gain", node_index=2, slot=GraphParamSlot::Value0)
    .build(template)
    .unwrap()
  let runtime = CompiledDsp::compile_result(template, ctx).unwrap()
  { name: "bd", bindings, runtime }
}

///|
fn mini_template_name_for_sound(sound : Double) -> String? {
  let code = sound.to_int()
  guard sound == code.to_double() else { return None }
  match code {
    36 => Some("bd")
    38 => Some("sd")
    39 => Some("cp")
    42 => Some("hh")
    46 => Some("oh")
    _ => None
  }
}

///|
fn find_prepared_template(
  registry : Array[MiniGraphPreparedTemplate],
  name : String,
) -> MiniGraphPreparedTemplate? {
  for entry in registry {
    if entry.name == name {
      return Some(entry)
    }
  }
  None
}

///|
fn first_mini_control_map(input : String) -> @pattern.ControlMap {
  let pat = @mini.parse(input).unwrap()
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let events = pat.query(arc)
  events[0].value
}

///|
fn resolve_mini_graph_controls(
  controls : @pattern.ControlMap,
  registry : Array[MiniGraphPreparedTemplate],
) -> Result[Array[GraphControl], MiniGraphBridgeError] {
  let sound = match controls.get("sound") {
    Some(value) => value
    None => return Err(MiniGraphBridgeError::MissingSoundKey)
  }
  let template_name = match mini_template_name_for_sound(sound) {
    Some(name) => name
    None => return Err(MiniGraphBridgeError::MissingTemplate("sound"))
  }
  let prepared = match find_prepared_template(registry, template_name) {
    Some(entry) => entry
    None => return Err(MiniGraphBridgeError::MissingTemplate(template_name))
  }
  let graph_controls : Map[String, Double] = {}
  controls.each(fn(key, value) {
    match key {
      "sound" => () // selector, not a graph parameter
      "pan" => () // default scheduler side-effect, not a graph parameter
      _ => graph_controls[key] = value
    }
  })
  Ok(prepared.bindings.resolve_controls(graph_controls))
}

///|
test "Mini graph boundary: sound selects template and controls resolve" {
  let ctx = DspContext::new(sample_rate=48000.0, block_size=16)
  let bd = prepared_bd_graph_template(ctx)
  let controls = first_mini_control_map(
    "s(\"bd\").cutoff(1200).gain(0.5).pan(-0.25)",
  )
  let resolved = resolve_mini_graph_controls(controls, [bd]).unwrap()

  @debug.assert_eq(resolved.length(), 2)
  @debug.assert_eq(resolved[0].node_index(), 1)
  @debug.assert_eq(resolved[0].slot(), GraphParamSlot::Value0)
  @debug.assert_eq(resolved[0].value(), 1200.0)
  @debug.assert_eq(resolved[1].node_index(), 2)
  @debug.assert_eq(resolved[1].slot(), GraphParamSlot::Value0)
  @debug.assert_eq(resolved[1].value(), 0.5)

  bd.runtime.apply_controls(resolved).unwrap()
  let output = AudioBuffer::filled(16)
  bd.runtime.process(ctx, output)
  assert_true(output.all(fn(sample) { is_finite(sample) }))
}

///|
test "Mini graph boundary: missing selected template is diagnostic" {
  let ctx = DspContext::new(sample_rate=48000.0, block_size=16)
  let bd = prepared_bd_graph_template(ctx)
  let controls = first_mini_control_map("s(\"sd\").gain(0.5)")
  match resolve_mini_graph_controls(controls, [bd]) {
    Err(MiniGraphBridgeError::MissingTemplate(name)) =>
      @debug.assert_eq(name, "sd")
    _ => fail("expected Mini sound selector to report missing graph template")
  }
}
