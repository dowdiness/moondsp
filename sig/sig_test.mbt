///|
test "number literals need no wrapper, including q" {
  let nodes = @sig.nodes(g => g.saw(220).lpf(1200.0, q=0.9).gain(0.2))
  let kinds = nodes.map(n => n.kind())
  assert_true(kinds is [Oscillator, Biquad, Gain, Output])
  assert_true(nodes[0].value0() == 220.0)
  assert_true(nodes[1].value1() == 0.9)
}

///|
test "reproduces the hand-indexed CLAP template with Control keys" {
  let template = @sig.Synth::build(g => {
    let osc = g.saw(g.param(@moondsp.Control::Note, default=440.0))
    let amp = g.adsr(
      attack_ms=2.0,
      decay_ms=80.0,
      sustain=0.7,
      release_ms=120.0,
    )
    osc
    .lpf(g.param(Lpf, default=1600.0), q=g.param(LpfResonance, default=0.707))
    .envelope(amp)
  })
  assert_true(template.nodes == @clap_engine.default_synth_template())
  let graph = @moondsp.AnalyzedGraph::analyze(template.nodes)
  assert_true(template.bindings.build(graph) is Ok(_))
}

///|
test "the host may use its own key type" {
  let template = @sig.Synth::build(g => {
    g
    .saw(g.param("frequency", default=220.0))
    .gain(g.param("volume", default=0.2))
  })
  let graph = @moondsp.AnalyzedGraph::analyze(template.nodes)
  assert_true(template.bindings.build(graph) is Ok(_))
  println("string keys: \{template.bindings}")
}

///|
test "statement order may change; bindings and gates follow" {
  let template = @sig.Synth::build(g => {
    // ADSR written first, so every index differs from the CLAP template.
    let amp = g.gate(
      "amp",
      g.adsr(attack_ms=2.0, decay_ms=80.0, sustain=0.7, release_ms=120.0),
    )
    g
    .saw(g.param(@moondsp.Control::Note, default=440.0))
    .lpf(g.param(Lpf, default=1600.0), q=g.param(LpfResonance, default=0.707))
    .envelope(amp)
  })
  assert_true(template.nodes != @clap_engine.default_synth_template())
  let graph = @moondsp.AnalyzedGraph::analyze(template.nodes)
  assert_true(template.bindings.build(graph) is Ok(_))
  let amp = template.gate("amp").unwrap()
  assert_true(template.nodes[amp].kind() is @moondsp.DspNodeKind::Adsr)
}

///|
test "a let-bound signal used twice stays one node" {
  let nodes = @sig.nodes(g => {
    let lfo = g.sine(2)
    let x = g.constant(1.0)
    x * lfo + lfo
  })
  assert_true(nodes.length() == 5)
}

///|
test "a signal kept after build cannot change the result" {
  let mut stray : @sig.Sig[Unit]? = None
  let nodes = @sig.nodes(g => {
    let s = g.sine(1.0)
    stray = Some(s)
    s
  })
  let _ = stray.unwrap().gain(0.5)
  assert_true(nodes.length() == 2)
}

///|
test "a signal from another builder is rejected" {
  let mut stray : @sig.Sig[Unit]? = None
  let _ = @sig.nodes(g => {
    let s = g.sine(1.0)
    stray = Some(s)
    s
  })
  let rejected = try {
    let _ = @sig.nodes(g => g.sine(2.0) + stray.unwrap())
    None
  } catch {
    error => Some(error)
  }
  assert_true(rejected is Some(@sig.SigError::ForeignSignal(1)))
}

///|
test "a param from another builder is rejected" {
  let mut stray : @sig.Param? = None
  let _ = @sig.Synth::build(g => {
    let p = g.param("a", default=1.0)
    stray = Some(p)
    g.sine(p)
  })
  let rejected = try {
    let _ = @sig.Synth::build(g => {
      ignore(g.param("b", default=2.0))
      g.sine(2.0).gain(stray.unwrap())
    })
    None
  } catch {
    error => Some(error)
  }
  assert_true(rejected is Some(@sig.SigError::ForeignSignal(1)))
}

///|
test "a built graph mounts and renders audio" {
  let nodes = @sig.nodes(g => g.saw(220).lpf(1200).gain(0.2))
  let context = @moondsp.DspContext::DspContext(
    sample_rate=48000.0,
    block_size=128,
  )
  let engine = @moondsp.GraphEngine::GraphEngine(context)
  let sound = engine.mount(nodes)
  let output = context.make_buffer()
  sound.play()
  engine.process(output)
  assert_true(output.any(sample => sample != 0.0))
  sound.unmount()
  engine.close()
}
