///|
// Test-local bridge fixture for the Mini/graph authoring contract. It avoids
// adding production routing behavior while pinning the expected boundary shape.
struct MiniGraphPreparedTemplate {
  name : String
  bindings : @moondsp.ControlBindingMap[@moondsp.Control]
  runtime : @moondsp.Dsp
}

///|
#derive(Debug, Eq)
enum MiniGraphBridgeError {
  MissingTemplate(String)
}

///|
fn prepared_bd_graph_template(
  ctx : @moondsp.DspContext,
) -> MiniGraphPreparedTemplate {
  let nodes = [
    @moondsp.DspNode::oscillator(@moondsp.Waveform::Sine, 110.0),
    @moondsp.DspNode::biquad(
      input=0,
      mode=@moondsp.BiquadMode::LowPass,
      cutoff_hz=800.0,
      q=0.707,
    ),
    @moondsp.DspNode::biquad(
      input=1,
      mode=@moondsp.BiquadMode::HighPass,
      cutoff_hz=20.0,
      q=0.707,
    ),
    @moondsp.DspNode::gain(2, 0.2),
    @moondsp.DspNode::output(3),
  ]
  let template = @moondsp.AnalyzedGraph::analyze(nodes)
  let bindings = @moondsp.ControlBindingBuilder()
    .bind(
      key=@moondsp.Control::Lpf,
      node_index=1,
      slot=@moondsp.GraphParamSlot::Value0,
    )
    .bind(key=Hpf, node_index=2, slot=@moondsp.GraphParamSlot::Value0)
    .bind(key=Gain, node_index=3, slot=@moondsp.GraphParamSlot::Value0)
    .build(template)
    .unwrap()
  let runtime = @moondsp.Dsp::compile_result(template, ctx).unwrap()
  { name: "bd", bindings, runtime, }
}

///|
fn find_prepared_template(
  registry : Array[MiniGraphPreparedTemplate],
  name : String,
) -> MiniGraphPreparedTemplate? {
  for entry in registry {
    if entry.name == name {
      break Some(entry)
    }
  } nobreak {
    None
  }
}

///|
fn first_mini_event(input : String) -> @score.ScoreEvent {
  let pat = @mini.parse(input).unwrap()
  let arc = @pattern.TimeSpan(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let events = pat.query(arc)
  events[0].value
}

///|
fn resolve_mini_graph_controls(
  event : @score.ScoreEvent,
  registry : Array[MiniGraphPreparedTemplate],
) -> Result[Array[@moondsp.GraphControl], MiniGraphBridgeError] {
  let template_name = match event.sound {
    Hit(drum) => drum.name()
    Note(instrument, ..) => instrument.name()
  }
  let prepared = match find_prepared_template(registry, template_name) {
    Some(entry) => entry
    None => return Err(MiniGraphBridgeError::MissingTemplate(template_name))
  }
  let graph_controls : Map[@moondsp.Control, Double] = Map([])
  event.controls.each(fn(key, value) {
    match key {
      Pan => () // default scheduler side-effect, not a graph parameter
      _ => graph_controls[key] = value
    }
  })
  Ok(prepared.bindings.resolve_controls(key => graph_controls.get(key)))
}

///|
test "Mini graph boundary: sound selects template and controls resolve" {
  let ctx = @moondsp.DspContext(sample_rate=48000.0, block_size=16)
  let bd = prepared_bd_graph_template(ctx)
  let event = first_mini_event(
    "s(\"bd\").lpf(1200).hpf(80).gain(0.5).pan(-0.25)",
  )
  let resolved = resolve_mini_graph_controls(event, [bd]).unwrap()

  @debug.assert_eq(resolved.length(), 3)
  @debug.assert_eq(resolved[0].node_index(), 1)
  @debug.assert_eq(resolved[0].slot(), @moondsp.GraphParamSlot::Value0)
  @debug.assert_eq(resolved[0].value(), 1200.0)
  @debug.assert_eq(resolved[1].node_index(), 2)
  @debug.assert_eq(resolved[1].slot(), @moondsp.GraphParamSlot::Value0)
  @debug.assert_eq(resolved[1].value(), 80.0)
  @debug.assert_eq(resolved[2].node_index(), 3)
  @debug.assert_eq(resolved[2].slot(), @moondsp.GraphParamSlot::Value0)
  @debug.assert_eq(resolved[2].value(), 0.5)

  bd.runtime.apply_controls(resolved).unwrap()
  let output = @moondsp.AudioBuffer::filled(16)
  bd.runtime.process(ctx, output)
  assert_true(output.all(fn(sample) { @moondsp.is_finite(sample) }))
}

///|
test "Mini graph boundary: missing selected template is diagnostic" {
  let ctx = @moondsp.DspContext(sample_rate=48000.0, block_size=16)
  let bd = prepared_bd_graph_template(ctx)
  let event = first_mini_event("s(\"sd\").gain(0.5)")
  match resolve_mini_graph_controls(event, [bd]) {
    Err(MiniGraphBridgeError::MissingTemplate(name)) =>
      @debug.assert_eq(name, "sd")
    _ => fail("expected Mini sound selector to report missing graph template")
  }
}
