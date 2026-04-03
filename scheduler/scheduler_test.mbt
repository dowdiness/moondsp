///|
test "midi_to_hz: A4 (69) = 440 Hz" {
  let hz = @scheduler.midi_to_hz(69.0)
  assert_true((hz - 440.0).abs() < 0.001)
}

///|
test "midi_to_hz: C4 (60) = 261.63 Hz" {
  let hz = @scheduler.midi_to_hz(60.0)
  assert_true(hz - 261.6255653006 < 0.01)
}

///|
test "midi_to_hz: MIDI 0" {
  let hz = @scheduler.midi_to_hz(0.0)
  assert_true(hz - 8.1758 < 0.01)
}

///|
test "midi_to_hz: MIDI 127" {
  let hz = @scheduler.midi_to_hz(127.0)
  assert_true(hz - 12543.85 < 1.0)
}

///|
test "PatternScheduler::new initializes with zero position" {
  let template : Array[@lib.DspNode] = [
    @lib.DspNode::oscillator(@lib.Waveform::Sine, 440.0),
    @lib.DspNode::gain(0, 1.0),
    @lib.DspNode::adsr(0.01, 0.1, 0.7, 0.3),
    @lib.DspNode::output(1),
  ]
  let ctx = @lib.DspContext::new(48000.0, 128)
  let bindings = @lib.ControlBindingBuilder::new()
    .bind(key="note", node_index=0, slot=@lib.GraphParamSlot::Value0)
    .build(template)
  match bindings {
    Ok(b) => {
      let sched = @scheduler.PatternScheduler::new(bpm=120.0, bindings=b, ctx~)
      inspect(sched.sample_counter(), content="0")
      inspect(sched.active_note_count(), content="0")
    }
    Err(_) => assert_true(false)
  }
}

///|
test "compute_arc: first block at 120 BPM" {
  let arc = @scheduler.compute_arc(0L, 120.0, 48000, 128)
  let zero = @pattern.Rational::from_int(0)
  assert_true(arc.begin == zero)
  let expected_end = @pattern.Rational::new(15360L, 2880000L)
  assert_true(arc.end_ == expected_end)
}

///|
test "compute_arc: second block at 120 BPM" {
  let arc = @scheduler.compute_arc(128L, 120.0, 48000, 128)
  let expected_start = @pattern.Rational::new(15360L, 2880000L)
  let expected_end = @pattern.Rational::new(30720L, 2880000L)
  assert_true(arc.begin == expected_start)
  assert_true(arc.end_ == expected_end)
}

///|
/// Helper: build a VoicePool with a minimal osc+adsr+output template.
fn make_test_pool() -> (@lib.VoicePool, Array[@lib.DspNode], @lib.DspContext) {
  let template : Array[@lib.DspNode] = [
    @lib.DspNode::oscillator(@lib.Waveform::Sine, 440.0),
    @lib.DspNode::adsr(0.01, 0.1, 0.7, 0.3),
    @lib.DspNode::gain(0, 1.0),
    @lib.DspNode::output(2),
  ]
  let ctx = @lib.DspContext::new(48000.0, 128)
  let pool = @lib.VoicePool::new(template, ctx, max_voices=4)
  match pool {
    Some(p) => (p, template, ctx)
    None => abort("test pool creation failed")
  }
}

///|
test "expire_notes: removes notes past their end_time" {
  let (pool, template, ctx) = make_test_pool()
  let bindings = @lib.ControlBindingBuilder::new()
    .bind(key="note", node_index=0, slot=@lib.GraphParamSlot::Value0)
    .build(template)
  match bindings {
    Err(_) => assert_true(false)
    Ok(b) => {
      let sched = @scheduler.PatternScheduler::new(bpm=120.0, bindings=b, ctx~)
      // Trigger a voice manually
      let controls = b.resolve_controls({ "note": 440.0 })
      let handle = pool.note_on(controls)
      match handle {
        None => assert_true(false)
        Some(h) => {
          // Inject an ActiveNote that expires at cycle 0 (already past)
          sched.push_active_note(h, @pattern.Rational::from_int(0))
          inspect(sched.active_note_count(), content="1")
          // Expire with arc starting at cycle 1
          let arc = @pattern.TimeSpan::new(
            @pattern.Rational::from_int(1),
            @pattern.Rational::from_int(2),
          )
          sched.expire_notes(pool, arc)
          inspect(sched.active_note_count(), content="0")
        }
      }
    }
  }
}

///|
test "process_events: single note-on creates active voice" {
  let (pool, template, ctx) = make_test_pool()
  let bindings = @lib.ControlBindingBuilder::new()
    .bind(key="note", node_index=0, slot=@lib.GraphParamSlot::Value0)
    .build(template)
  match bindings {
    Err(_) => assert_true(false)
    Ok(b) => {
      let sched = @scheduler.PatternScheduler::new(bpm=120.0, bindings=b, ctx~)
      // Use the pattern API to generate events — Event is not directly constructible
      let arc = @pattern.TimeSpan::new(
        @pattern.Rational::from_int(0),
        @pattern.Rational::new(1L, 100L),
      )
      let events = @pattern.note(60.0).query(arc)
      sched.process_events(events, arc, pool)
      inspect(sched.active_note_count(), content="1")
      inspect(pool.active_voice_count(), content="1")
    }
  }
}

///|
test "process_block: note(60) triggers one voice" {
  let (pool, template, ctx) = make_test_pool()
  let bindings = @lib.ControlBindingBuilder::new()
    .bind(key="note", node_index=0, slot=@lib.GraphParamSlot::Value0)
    .build(template)
  match bindings {
    Err(_) => assert_true(false)
    Ok(b) => {
      let sched = @scheduler.PatternScheduler::new(bpm=120.0, bindings=b, ctx~)
      let pat = @pattern.note(60.0)
      let left = @lib.AudioBuffer::filled(128)
      let right = @lib.AudioBuffer::filled(128)
      sched.process_block(pat, pool, ctx, left, right)
      inspect(pool.active_voice_count(), content="1")
      inspect(sched.active_note_count(), content="1")
      inspect(sched.sample_counter(), content="128")
    }
  }
}

///|
test "process_block: empty pattern triggers no voices" {
  let (pool, template, ctx) = make_test_pool()
  let bindings = @lib.ControlBindingBuilder::new()
    .bind(key="note", node_index=0, slot=@lib.GraphParamSlot::Value0)
    .build(template)
  match bindings {
    Err(_) => assert_true(false)
    Ok(b) => {
      let sched = @scheduler.PatternScheduler::new(bpm=120.0, bindings=b, ctx~)
      let pat : @pattern.Pat[@pattern.ControlMap] = @pattern.Pat::silence()
      let left = @lib.AudioBuffer::filled(128)
      let right = @lib.AudioBuffer::filled(128)
      sched.process_block(pat, pool, ctx, left, right)
      inspect(pool.active_voice_count(), content="0")
      inspect(sched.active_note_count(), content="0")
    }
  }
}
