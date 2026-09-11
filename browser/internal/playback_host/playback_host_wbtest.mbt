///|
fn test_drum_template(freq : Double) -> Array[@moondsp.DspNode] {
  [
    @moondsp.DspNode::oscillator(@moondsp.Waveform::Sine, freq),
    @moondsp.DspNode::adsr(
      attack_ms=0.5,
      decay_ms=60.0,
      sustain=0.0,
      release_ms=40.0,
    ),
    @moondsp.DspNode::envelope_gain(input=0, envelope=1, amount=1.0),
    @moondsp.DspNode::output(2),
  ]
}

///|
fn test_synth_template() -> Array[@moondsp.DspNode] {
  [
    @moondsp.DspNode::oscillator(@moondsp.Waveform::Sine, 440.0),
    @moondsp.DspNode::adsr(
      attack_ms=10.0,
      decay_ms=100.0,
      sustain=0.7,
      release_ms=300.0,
    ),
    @moondsp.DspNode::envelope_gain(input=0, envelope=1, amount=1.0),
    @moondsp.DspNode::output(2),
  ]
}

///|
fn init_scheduler_graph_for_test() -> Bool {
  init_scheduler_graph_with_templates(
    48000.0,
    128,
    test_drum_template(60.0),
    test_drum_template(180.0),
    test_drum_template(8000.0),
    test_drum_template(1200.0),
    test_drum_template(6000.0),
    test_synth_template(),
  )
}

///|
fn prepare_for_test(text : String, song? : Bool = false) -> Int {
  clear_playback_input()
  for i in 0..<text.length() {
    push_playback_char(text[i].to_int())
  }
  if song {
    prepare_song_input()
  } else {
    prepare_pattern_input()
  }
}

///|
fn submit_for_test(
  text : String,
  song? : Bool = false,
  restart? : Bool = true,
) -> Int {
  let token = prepare_for_test(text, song~)
  if token == 0 {
    1
  } else {
    apply_prepared_playback(token, restart)
  }
}

///|
fn render_for_test(count : Int) -> Unit raise {
  for _ in 0..<count {
    assert_true(process_scheduler_block())
  }
}

///|
fn output_energy() -> Double {
  let mut energy = 0.0
  for i in 0..<128 {
    energy = energy + scheduler_left_sample(i).abs()
  }
  energy
}

///|
fn assert_position(position : Int) -> Unit raise {
  for route in sched_routes.val {
    assert_eq(route.pool.scheduler.sample_counter(), position.to_int64())
  }
}

///|
fn test_song(length~ : Int, bpm~ : Int) -> String {
  "song(bpm(\{bpm}),section(\"a\",\{length},note(\"60\")),part(\"a1\",\"a\"))"
}

///|
// All routes must observe the same tempo at the commit boundary.
fn assert_tempo(bpm : Double) -> Unit raise {
  for route in sched_routes.val {
    assert_eq(route.pool.scheduler.bpm(), bpm)
  }
}

///|
test "live edits preserve the sounding envelope" {
  fn render(edit : Bool) -> Array[Double] raise {
    assert_true(init_scheduler_graph_for_test())
    assert_eq(
      submit_for_test("note(\"60\").slow(40).hold(0.1).release(0.2)"),
      0,
    )
    let samples : Array[Double] = []
    for block in 0..<120 {
      // Edit just before the original note enters its release.
      if edit && block == 41 {
        assert_eq(
          submit_for_test(
            "note(\"60\").slow(40).hold(0).release(0)",
            restart=false,
          ),
          0,
        )
      }
      render_for_test(1)
      for i in 0..<128 {
        samples.push(scheduler_left_sample(i))
      }
    }
    samples
  }
  let uninterrupted = render(false)
  assert_eq(render(true), uninterrupted)
  // The release is audible at 0.2s and has finished by the end of the render.
  assert_true(
    uninterrupted[9600:9728]
    .to_array()
    .any(fn(sample) { sample.abs() > 0.0001 }),
  )
  assert_false(
    uninterrupted[uninterrupted.length() - 128:]
    .to_array()
    .any(fn(sample) { sample != 0.0 }),
  )
}

///|
test "envelope controls on a mixed stack leave drum voices unchanged" {
  fn render(text : String) -> Array[Double] raise {
    assert_true(init_scheduler_graph_for_test())
    assert_eq(submit_for_test(text), 0)
    let samples : Array[Double] = []
    for _ in 0..<80 {
      render_for_test(1)
      for i in 0..<128 {
        samples.push(scheduler_left_sample(i))
        samples.push(scheduler_right_sample(i))
      }
    }
    samples
  }

  let drums = render("s(\"bd\").slow(8)")
  assert_true(drums.any(fn(sample) { sample.abs() > 0.01 }))
  assert_eq(render("s(\"bd\").slow(8).hold(0)"), drums)
  assert_eq(render("s(\"bd\").slow(8).hold(3)"), drums)
  assert_eq(
    render(
      "stack(note(\"60\"), s(\"bd\")).attack(0.01).hold(0.02).release(0.03)",
    ),
    render(
      "stack(note(\"60\").attack(0.01).hold(0.02).release(0.03), s(\"bd\"))",
    ),
  )
}
