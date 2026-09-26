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
    @moondsp.DspNode::biquad(
      input=0,
      mode=@moondsp.BiquadMode::LowPass,
      cutoff_hz=8000.0,
      q=0.707,
    ),
    @moondsp.DspNode::biquad(
      input=2,
      mode=@moondsp.BiquadMode::HighPass,
      cutoff_hz=20.0,
      q=0.707,
    ),
    @moondsp.DspNode::envelope_gain(input=3, envelope=1, amount=1.0),
    @moondsp.DspNode::gain(4, 1.0),
    @moondsp.DspNode::output(5),
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
fn submit_for_test(text : String, restart? : Bool = true) -> Int {
  clear_playback_input()
  let fields : Map[String, Json] = {
    "schema": Json::number(1.0),
    "kind": Json::string("text"),
    "text": Json::string(text),
  }
  let wire = Json::object(fields).stringify()
  for i in 0..<wire.length() {
    push_playback_char(wire[i].to_int())
  }
  if restart {
    player_restart_input()
  } else {
    player_update_input()
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
fn rendered_synth_energy(text : String) -> Double raise {
  assert_true(init_scheduler_graph_for_test())
  assert_eq(submit_for_test(text), 0)
  let mut energy = 0.0
  for _ in 0..<48 {
    render_for_test(1)
    energy = energy + output_energy()
  }
  energy
}

///|
test "live synth applies gain, cutoff, and independent filter resonance" {
  let baseline = rendered_synth_energy("note(\"69\").slow(40)")
  let quieter = rendered_synth_energy("note(\"69\").slow(40).gain(0.25)")
  let low_passed = rendered_synth_energy("note(\"69\").slow(40).lpf(100)")
  let high_passed = rendered_synth_energy("note(\"69\").slow(40).hpf(4000)")
  let low_q_lpf = rendered_synth_energy("note(\"69\").slow(40).lpf(440, 0.5)")
  let resonant_lpf = rendered_synth_energy("note(\"69\").slow(40).lpf(440, 4)")
  let low_q_hpf = rendered_synth_energy("note(\"69\").slow(40).hpf(440, 0.5)")
  let resonant_hpf = rendered_synth_energy("note(\"69\").slow(40).hpf(440, 4)")
  assert_true(baseline > 0.0)
  assert_true(quieter > 0.0 && quieter < baseline * 0.35)
  assert_true(low_passed > 0.0 && low_passed < baseline * 0.35)
  assert_true(high_passed > 0.0 && high_passed < baseline * 0.35)
  assert_true(resonant_lpf > low_q_lpf * 2.0)
  assert_true(resonant_hpf > low_q_hpf * 2.0)
}

///|
fn wet_energy() -> Double {
  let owner = player.val.unwrap()
  let mut energy = 0.0
  for i in 0..<128 {
    energy += owner.wet_left.get(i).abs() + owner.wet_right.get(i).abs()
  }
  energy
}

///|
fn sound_route_active_notes(sound : Double) -> Int {
  for route in player.val.unwrap().routes {
    if route.selector is RouteSound(code) && code == sound {
      return route.pool.scheduler.active_note_count()
    }
  }
  0
}

///|
fn assert_position(position : Int) -> Unit raise {
  for route in player.val.unwrap().routes {
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
  for route in player.val.unwrap().routes {
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
    .to_owned()
    .any(fn(sample) { sample.abs() > 0.0001 }),
  )
  assert_false(
    uninterrupted[uninterrupted.length() - 128:]
    .to_owned()
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

///|
test "shared room tail survives a two-part continue edit and restart clears it" {
  let before = "song(section(\"a\",4,s(\"bd\").slow(8).room(1)),section(\"b\",4,s(\"sd\").slow(8)),part(\"a1\",\"a\",0),part(\"b1\",\"b\",0))"
  let after = "song(section(\"a\",4,s(\"bd\").slow(8).gain(0)),section(\"b\",4,s(\"sd\").slow(8)),part(\"a1\",\"a\",0),part(\"b1\",\"b\",0))"
  assert_true(init_scheduler_graph_for_test())
  assert_eq(submit_for_test(before), 0)
  render_for_test(30)
  assert_true(wet_energy() > 0.0)
  assert_eq(submit_for_test(after, restart=false), 0)
  render_for_test(1)
  assert_true(wet_energy() > 0.0)
  assert_true(sound_route_active_notes(38.0) > 0)
  assert_true(output_energy() > 0.0)
  assert_eq(submit_for_test(after), 0)
  render_for_test(1)
  assert_eq(wet_energy(), 0.0)
  assert_true(sound_route_active_notes(38.0) > 0)
}

///|
test "room send leaves dry playback dry and adds one wet return" {
  assert_true(init_scheduler_graph_for_test())
  assert_eq(submit_for_test("s(\"bd\").slow(8)"), 0)
  render_for_test(30)
  let dry_output = output_energy()
  assert_eq(wet_energy(), 0.0)
  assert_true(init_scheduler_graph_for_test())
  assert_eq(submit_for_test("s(\"bd\").slow(8).room(1)"), 0)
  render_for_test(30)
  let reverberant_output = output_energy()
  assert_true(wet_energy() > 0.0)
  assert_true((reverberant_output - dry_output).abs() > 0.000001)
}

///|
test "seeking an ended song starts its accepted section again" {
  assert_true(init_scheduler_graph_for_test())
  assert_eq(submit_for_test(test_song(length=1, bpm=120)), 0)
  render_for_test(205)
  assert_true(player.val.unwrap().session is Ended(_, _, _))
  assert_eq(player_seek_section(0), 0)
  let mut energy = 0.0
  for _ in 0..<24 {
    render_for_test(1)
    energy += output_energy()
  }
  assert_true(energy > 0.0)
}

///|
fn preview_song_samples(
  accepted_after_end : Bool,
  position_milli : Int,
  loop_preview : Bool,
  old_source? : Bool = false,
) -> Array[Double] raise {
  let old = "song(bpm(120),section(\"a\",1,note(\"60\")),part(\"a1\",\"a\"))"
  let latest = "song(bpm(120),section(\"a\",2,note(\"72 74\")),part(\"a1\",\"a\"))"
  assert_true(init_scheduler_graph_for_test())
  if accepted_after_end {
    assert_eq(submit_for_test(old), 0)
    render_for_test(752)
    assert_eq(player_state(), 4)
    let ended_position = scheduler_sample_position()
    assert_eq(submit_for_test(latest, restart=false), 0)
    assert_eq(player_state(), 4)
    assert_eq(scheduler_sample_position(), ended_position)
  } else {
    assert_eq(submit_for_test(if old_source { old } else { latest }), 0)
  }
  if loop_preview {
    assert_eq(player_loop_cycles(position_milli, 2000), 0)
    assert_eq(player_loop_begin(), position_milli.to_double() / 1000.0)
    assert_eq(player_loop_end(), 2.0)
  } else {
    assert_eq(player_seek_cycle(position_milli), 0)
  }
  let samples : Array[Double] = []
  for _ in 0..<3 {
    render_for_test(1)
    for i in 0..<128 {
      samples.push(scheduler_left_sample(i))
    }
  }
  assert_true(samples.any(sample => sample.abs() > 0.0001))
  samples
}

///|
test "Ended update previews latest notes at zero and beyond old duration" {
  let zero = preview_song_samples(true, 0, false)
  assert_eq(zero, preview_song_samples(false, 0, false))
  assert_true(zero != preview_song_samples(false, 0, false, old_source=true))
  let later = preview_song_samples(true, 1500, false)
  assert_eq(later, preview_song_samples(false, 1500, false))
  assert_true(zero != later)
  let looped = preview_song_samples(true, 1500, true)
  assert_eq(looped, preview_song_samples(false, 1500, true))
}

///|
test "Ended accepts a longer song without sounding its future notes" {
  let old = "song(bpm(120),section(\"a\",1,silence()),part(\"a1\",\"a\"))"
  let latest = "song(bpm(120),section(\"a\",2,note(\"~ 74\")),part(\"a1\",\"a\"))"
  assert_true(init_scheduler_graph_for_test())
  assert_eq(submit_for_test(old), 0)
  render_for_test(752)
  assert_eq(player_state(), 4)
  assert_eq(submit_for_test(latest, restart=false), 0)
  let ended_position = scheduler_sample_position()
  for _ in 0..<400 {
    render_for_test(1)
    assert_eq(output_energy(), 0.0)
  }
  assert_eq(player_state(), 4)
  assert_eq(scheduler_sample_position(), ended_position)
  assert_eq(player_seek_cycle(1500), 0)
  render_for_test(3)
  assert_true(output_energy() > 0.01)
}

///|
test "source tempo update cannot shorten an installed loop below one block" {
  fn run(rejected : Bool) -> Array[Double] raise {
    let original = "song(bpm(1),section(\"a\",2,note(\"60\")),part(\"a1\",\"a\"))"
    let faster = "song(bpm(1000),section(\"a\",2,note(\"72\")),part(\"a1\",\"a\"))"
    assert_true(init_scheduler_graph_for_test())
    assert_eq(submit_for_test(original), 0)
    assert_eq(player_loop_cycles(0, 1), 0)
    render_for_test(2)
    let position = scheduler_sample_position()
    if rejected {
      assert_eq(submit_for_test(faster, restart=false), 1)
    }
    assert_eq(player_state(), 2)
    assert_eq(player.val.unwrap().view().source, Some(original))
    assert_eq(scheduler_bpm(), 1.0)
    assert_tempo(1.0)
    assert_eq(scheduler_sample_position(), position)
    assert_eq(player_loop_begin(), 0.0)
    assert_eq(player_loop_end(), 0.001)
    let samples : Array[Double] = []
    for _ in 0..<8 {
      render_for_test(1)
      for i in 0..<128 {
        samples.push(scheduler_left_sample(i))
      }
    }
    samples
  }
  let uninterrupted = run(false)
  assert_true(uninterrupted.any(sample => sample.abs() > 0.0001))
  assert_eq(run(true), uninterrupted)
}

///|
test "accepted song loop sounds again after the first section wraps" {
  assert_true(init_scheduler_graph_for_test())
  let source = "song(bpm(120),section(\"a\",1,note(\"60\")),section(\"b\",1,note(\"67\")),part(\"a\",\"a\"),part(\"b\",\"b\"))"
  assert_eq(submit_for_test(source), 0)
  assert_eq(player_loop_cycles(0, 2000), 0)
  render_for_test(750)
  let mut energy = 0.0
  for _ in 0..<24 {
    render_for_test(1)
    energy += output_energy()
  }
  assert_true(energy > 0.0)
}
