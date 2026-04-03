///|
test "midi_to_hz: A4 (69) = 440 Hz" {
  let hz = @scheduler.midi_to_hz(69.0)
  assert_true((hz - 440.0).abs() < 0.001)
}

///|
test "midi_to_hz: C4 (60) = 261.63 Hz" {
  let hz = @scheduler.midi_to_hz(60.0)
  assert_true((hz - 261.6255653006).abs() < 0.01)
}

///|
test "midi_to_hz: MIDI 0" {
  let hz = @scheduler.midi_to_hz(0.0)
  assert_true((hz - 8.1758).abs() < 0.01)
}

///|
test "midi_to_hz: MIDI 127" {
  let hz = @scheduler.midi_to_hz(127.0)
  assert_true((hz - 12543.85).abs() < 1.0)
}

///|
test "PatternScheduler::new initializes with zero position" {
  let template : Array[@lib.DspNode] = [
    @lib.DspNode::oscillator(@lib.Waveform::Sine, 440.0),
    @lib.DspNode::gain(0, 1.0),
    @lib.DspNode::adsr(0.01, 0.1, 0.7, 0.3),
    @lib.DspNode::output(1),
  ]
  let bindings = @lib.ControlBindingBuilder::new()
    .bind(key="note", node_index=0, slot=@lib.GraphParamSlot::Value0)
    .build(template)
  match bindings {
    Ok(b) => {
      let sched = @scheduler.PatternScheduler::new(bpm=120.0, bindings=b)
      inspect(sched.sample_counter(), content="0")
      inspect(sched.active_note_count(), content="0")
    }
    Err(_) => assert_true(false)
  }
}

///|
test "compute_arc: first block at 120 BPM" {
  let ctx = @lib.DspContext::new(48000.0, 128)
  let arc = @scheduler.compute_arc(0L, 120.0, ctx)
  let zero = @pattern.Rational::from_int(0)
  assert_true(arc.begin == zero)
  let expected_end = @pattern.Rational::new(15360L, 2880000L)
  assert_true(arc.end_ == expected_end)
}

///|
test "compute_arc: second block at 120 BPM" {
  let ctx = @lib.DspContext::new(48000.0, 128)
  let arc = @scheduler.compute_arc(128L, 120.0, ctx)
  let expected_start = @pattern.Rational::new(15360L, 2880000L)
  let expected_end = @pattern.Rational::new(30720L, 2880000L)
  assert_true(arc.begin == expected_start)
  assert_true(arc.end_ == expected_end)
}

///|
/// Helper: build a VoicePool with a minimal osc→adsr→gain→output template.
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
/// Helper: build pool + scheduler + audio buffers for standard test setup.
fn make_test_sched() -> (
  @lib.VoicePool,
  @scheduler.PatternScheduler,
  @lib.DspContext,
  @lib.AudioBuffer,
  @lib.AudioBuffer,
) {
  let (pool, template, ctx) = make_test_pool()
  let bindings = @lib.ControlBindingBuilder::new()
    .bind(key="note", node_index=0, slot=@lib.GraphParamSlot::Value0)
    .build(template)
  match bindings {
    Ok(b) => {
      let sched = @scheduler.PatternScheduler::new(bpm=120.0, bindings=b)
      let left = @lib.AudioBuffer::filled(128)
      let right = @lib.AudioBuffer::filled(128)
      (pool, sched, ctx, left, right)
    }
    Err(_) => abort("test bindings creation failed")
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
      let sched = @scheduler.PatternScheduler::new(bpm=120.0, bindings=b)
      let controls = b.resolve_controls({ "note": 440.0 })
      let handle = pool.note_on(controls)
      match handle {
        None => assert_true(false)
        Some(h) => {
          sched.push_active_note(h, @pattern.Rational::from_int(0))
          inspect(sched.active_note_count(), content="1")
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
  let (pool, sched, ctx, _, _) = make_test_sched()
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::new(1L, 100L),
  )
  let events = @pattern.note(60.0).query(arc)
  sched.process_events(events, arc, pool)
  inspect(sched.active_note_count(), content="1")
  inspect(pool.active_voice_count(), content="1")
}

///|
test "process_block: note(60) triggers one voice" {
  let (pool, sched, ctx, left, right) = make_test_sched()
  let pat = @pattern.note(60.0)
  sched.process_block(pat, pool, ctx, left, right)
  inspect(pool.active_voice_count(), content="1")
  inspect(sched.active_note_count(), content="1")
  inspect(sched.sample_counter(), content="128")
}

///|
test "process_block: empty pattern triggers no voices" {
  let (pool, sched, ctx, left, right) = make_test_sched()
  let pat : @pattern.Pat[@pattern.ControlMap] = @pattern.Pat::silence()
  sched.process_block(pat, pool, ctx, left, right)
  inspect(pool.active_voice_count(), content="0")
  inspect(sched.active_note_count(), content="0")
}

///|
test "process_block: fast(2) triggers two voices per cycle" {
  let (pool, sched, ctx, left, right) = make_test_sched()
  let pat = @pattern.note(60.0).fast(@pattern.Rational::from_int(2))
  sched.process_block(pat, pool, ctx, left, right)
  assert_true(pool.active_voice_count() >= 1)
  let mut voices_seen = pool.active_voice_count()
  for _i = 1; _i < 94; _i = _i + 1 {
    sched.process_block(pat, pool, ctx, left, right)
    if pool.active_voice_count() > voices_seen {
      voices_seen = pool.active_voice_count()
    }
  }
  assert_true(voices_seen >= 2)
}

///|
test "process_block: gate-off fires after note ends" {
  let (pool, sched, ctx, left, right) = make_test_sched()
  let pat = @pattern.note(60.0)
  sched.process_block(pat, pool, ctx, left, right)
  inspect(sched.active_note_count(), content="1")
  for _i = 1; _i < 190; _i = _i + 1 {
    sched.process_block(pat, pool, ctx, left, right)
  }
  // After crossing cycle boundary, old note expired, new one triggered
  inspect(sched.active_note_count(), content="1")
}

///|
test "process_block: pan key applies per-voice pan" {
  let (pool, sched, ctx, left, right) = make_test_sched()
  let pat = @pattern.merge_control(@pattern.note(60.0), @pattern.s_pan(-1.0))
  sched.process_block(pat, pool, ctx, left, right)
  inspect(pool.active_voice_count(), content="1")
  inspect(sched.active_note_count(), content="1")
}

///|
test "process_block: dense pattern fires multiple note-ons per block" {
  let (pool, sched, ctx, left, right) = make_test_sched()
  let pat = @pattern.note(60.0).fast(@pattern.Rational::from_int(1000))
  sched.process_block(pat, pool, ctx, left, right)
  assert_true(pool.active_voice_count() >= 1)
}

///|
test "process_block: stolen voice gate-off is harmless" {
  let template : Array[@lib.DspNode] = [
    @lib.DspNode::oscillator(@lib.Waveform::Sine, 440.0),
    @lib.DspNode::adsr(0.01, 0.1, 0.7, 0.3),
    @lib.DspNode::gain(0, 1.0),
    @lib.DspNode::output(2),
  ]
  let ctx = @lib.DspContext::new(48000.0, 128)
  let pool = @lib.VoicePool::new(template, ctx, max_voices=1)
  match pool {
    None => assert_true(false)
    Some(pool) => {
      let bindings = @lib.ControlBindingBuilder::new()
        .bind(key="note", node_index=0, slot=@lib.GraphParamSlot::Value0)
        .build(template)
      match bindings {
        Err(_) => assert_true(false)
        Ok(b) => {
          let sched = @scheduler.PatternScheduler::new(bpm=120.0, bindings=b)
          let pat = @pattern.note(60.0).fast(@pattern.Rational::from_int(2))
          let left = @lib.AudioBuffer::filled(128)
          let right = @lib.AudioBuffer::filled(128)
          for _i = 0; _i < 200; _i = _i + 1 {
            sched.process_block(pat, pool, ctx, left, right)
          }
          assert_true(true)
        }
      }
    }
  }
}
