///|
fn new_test_engine() -> @clap_engine.ClapSynthEngine {
  match
    @clap_engine.ClapSynthEngine::new(
      sample_rate=48000.0,
      max_block_size=128,
      max_voices=8,
    ) {
    Ok(engine) => engine
    Err(error) => abort("expected CLAP synth engine to initialize: \{error}")
  }
}

///|
fn abs_double(value : Double) -> Double {
  if value < 0.0 {
    -value
  } else {
    value
  }
}

///|
fn rendered_peak(engine : @clap_engine.ClapSynthEngine, frames : Int) -> Double {
  let processed = engine.process(frames)
  for i in 0..<processed; peak = 0.0 {
    let l = abs_double(engine.left_sample(i))
    let r = abs_double(engine.right_sample(i))
    let next_l = if l > peak { l } else { peak }
    let next_peak = if r > next_l { r } else { next_l }
    continue next_peak
  } nobreak {
    peak
  }
}

///|
test "default synth template has the expected CLAP binding shape" {
  let template = @clap_engine.default_synth_template()
  @debug.assert_eq(template.length(), 6)
  assert_true(
    @moondsp.node_accepts_slot(template[0], @moondsp.GraphParamSlot::Value0),
  )
  assert_true(
    @moondsp.node_accepts_slot(template[3], @moondsp.GraphParamSlot::Value0),
  )
  assert_true(
    @moondsp.node_accepts_slot(template[3], @moondsp.GraphParamSlot::Value1),
  )
  assert_true(
    @moondsp.node_accepts_slot(template[4], @moondsp.GraphParamSlot::Value0),
  )
}

///|
test "engine initializes and renders silence before notes" {
  let engine = new_test_engine()
  @debug.assert_eq(engine.process(128), 128)
  @debug.assert_eq(engine.left_sample(0), 0.0)
  @debug.assert_eq(engine.right_sample(0), 0.0)
}

///|
test "note on renders non-zero stereo samples and note off removes handle" {
  let engine = new_test_engine()
  assert_true(engine.note_on(note_id=7, key=69, velocity=1.0))
  let peak = rendered_peak(engine, 128)
  assert_true(peak > 0.000001)
  assert_true(engine.note_off(note_id=7, key=69))
  assert_true(!engine.note_off(note_id=7, key=69))
}

///|
test "process clamps CLAP frame count to the preallocated block" {
  let engine = new_test_engine()
  @debug.assert_eq(engine.process(1024), 128)
  @debug.assert_eq(engine.left_sample(128), 0.0)
  @debug.assert_eq(engine.right_sample(-1), 0.0)
}

///|
test "flat parameter dispatcher sanitizes host values" {
  let engine = new_test_engine()
  assert_true(engine.set_param(@clap_engine.CLAP_PARAM_MASTER_GAIN, 100.0))
  @debug.assert_eq(engine.master_gain(), 4.0)
  assert_true(engine.set_param(@clap_engine.CLAP_PARAM_PAN, -5.0))
  @debug.assert_eq(engine.pan(), -1.0)
  assert_true(engine.set_param(@clap_engine.CLAP_PARAM_CUTOFF_HZ, 1000000.0))
  assert_true(engine.cutoff_hz() < 24000.0)
  assert_true(!engine.set_param(999, 0.0))
}

///|
test "voice gain automation preserves held-note velocity" {
  let quiet = new_test_engine()
  assert_true(quiet.note_on(note_id=1, key=69, velocity=0.25))
  ignore(quiet.set_voice_gain(1.0))
  let quiet_peak = rendered_peak(quiet, 128)
  let full = new_test_engine()
  assert_true(full.note_on(note_id=1, key=69, velocity=1.0))
  ignore(full.set_voice_gain(1.0))
  let full_peak = rendered_peak(full, 128)
  assert_true(quiet_peak > 0.000001)
  assert_true(full_peak > 0.000001)
  assert_true(quiet_peak < full_peak * 0.5)
}
