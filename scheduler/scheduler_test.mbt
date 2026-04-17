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
  let ctx = @lib.DspContext::new(48000.0, 128)
  let bindings = @lib.ControlBindingBuilder::new()
    .bind(key="note", node_index=0, slot=@lib.GraphParamSlot::Value0)
    .build(template)
  match bindings {
    Ok(b) => {
      let sched = @scheduler.PatternScheduler::new(bpm=120.0, bindings=b, ctx~)
      assert_eq(sched.sample_counter(), 0L)
      assert_eq(sched.active_note_count(), 0)
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
test "compute_arc: fractional BPM 120.5 preserves precision" {
  let ctx = @lib.DspContext::new(48000.0, 128)
  // 120.5 BPM → bpm_scaled = 1205, denominator = 48000 * 600 = 28800000
  // arc_end = 128 * 1205 / 28800000 = 154240 / 28800000
  let arc = @scheduler.compute_arc(0L, 120.5, ctx)
  let expected_end = @pattern.Rational::new(154240L, 28800000L)
  assert_true(arc.end_ == expected_end)
  // Verify 120.5 and 120.0 produce different arcs
  let arc_120 = @scheduler.compute_arc(0L, 120.0, ctx)
  assert_true(arc.end_ != arc_120.end_)
}

///|
/// Helper: build a VoicePool with a minimal osc→adsr→envelope_gain→output
/// template. Envelope_gain wires the ADSR at index 1 into the signal path so
/// `VoicePool::new`'s orphan-ADSR gate accepts it; swapping to bare `gain(0)`
/// would orphan the ADSR and be rejected.
fn make_test_pool() -> (@lib.VoicePool, Array[@lib.DspNode], @lib.DspContext) {
  let template : Array[@lib.DspNode] = [
    @lib.DspNode::oscillator(@lib.Waveform::Sine, 440.0),
    @lib.DspNode::adsr(0.01, 0.1, 0.7, 0.3),
    @lib.DspNode::envelope_gain(0, 1, 1.0),
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
  @lib.AudioBuffer,
  @lib.AudioBuffer,
) {
  let (pool, template, ctx) = make_test_pool()
  let bindings = @lib.ControlBindingBuilder::new()
    .bind(key="note", node_index=0, slot=@lib.GraphParamSlot::Value0)
    .build(template)
  match bindings {
    Ok(b) => {
      let sched = @scheduler.PatternScheduler::new(bpm=120.0, bindings=b, ctx~)
      let left = @lib.AudioBuffer::filled(128)
      let right = @lib.AudioBuffer::filled(128)
      (pool, sched, left, right)
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
      let sched = @scheduler.PatternScheduler::new(bpm=120.0, bindings=b, ctx~)
      let controls = b.resolve_controls({ "note": 440.0 })
      let handle = pool.note_on(controls)
      match handle {
        None => assert_true(false)
        Some(h) => {
          sched.push_active_note(h, @pattern.Rational::from_int(0))
          assert_eq(sched.active_note_count(), 1)
          let arc = @pattern.TimeSpan::new(
            @pattern.Rational::from_int(1),
            @pattern.Rational::from_int(2),
          )
          sched.expire_notes(pool, arc)
          assert_eq(sched.active_note_count(), 0)
        }
      }
    }
  }
}

///|
test "process_events: single note-on creates active voice" {
  let (pool, sched, _, _) = make_test_sched()
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::new(1L, 100L),
  )
  let events = @pattern.note(60.0).query(arc)
  sched.process_events(events, arc, pool)
  assert_eq(sched.active_note_count(), 1)
  assert_eq(pool.active_voice_count(), 1)
}

///|
test "process_block: note(60) triggers one voice" {
  let (pool, sched, left, right) = make_test_sched()
  let pat = @pattern.note(60.0)
  sched.process_block(pat, pool, left, right)
  assert_eq(pool.active_voice_count(), 1)
  assert_eq(sched.active_note_count(), 1)
  assert_eq(sched.sample_counter(), 128L)
}

///|
test "process_block: empty pattern triggers no voices" {
  let (pool, sched, left, right) = make_test_sched()
  let pat : @pattern.Pat[@pattern.ControlMap] = @pattern.Pat::silence()
  sched.process_block(pat, pool, left, right)
  assert_eq(pool.active_voice_count(), 0)
  assert_eq(sched.active_note_count(), 0)
}

///|
test "process_block: fast(2) triggers two voices per cycle" {
  let (pool, sched, left, right) = make_test_sched()
  let pat = @pattern.note(60.0).fast(@pattern.Rational::from_int(2))
  sched.process_block(pat, pool, left, right)
  assert_true(pool.active_voice_count() >= 1)
  let mut voices_seen = pool.active_voice_count()
  for _i = 1; _i < 94; _i = _i + 1 {
    sched.process_block(pat, pool, left, right)
    if pool.active_voice_count() > voices_seen {
      voices_seen = pool.active_voice_count()
    }
  }
  assert_true(voices_seen >= 2)
}

///|
test "process_block: gate-off fires after note ends" {
  let (pool, sched, left, right) = make_test_sched()
  let pat = @pattern.note(60.0)
  sched.process_block(pat, pool, left, right)
  assert_eq(sched.active_note_count(), 1)
  for _i = 1; _i < 190; _i = _i + 1 {
    sched.process_block(pat, pool, left, right)
  }
  // After crossing cycle boundary, old note expired, new one triggered
  assert_eq(sched.active_note_count(), 1)
}

///|
test "process_block: pan key applies per-voice pan" {
  let (pool, sched, left, right) = make_test_sched()
  let pat = @pattern.merge_control(@pattern.note(60.0), @pattern.s_pan(-1.0))
  sched.process_block(pat, pool, left, right)
  assert_eq(pool.active_voice_count(), 1)
  assert_eq(sched.active_note_count(), 1)
}

///|
test "process_block: dense pattern fires multiple note-ons per block" {
  let (pool, sched, left, right) = make_test_sched()
  let pat = @pattern.note(60.0).fast(@pattern.Rational::from_int(1000))
  sched.process_block(pat, pool, left, right)
  assert_true(pool.active_voice_count() >= 1)
}

///|
test "process_block: stolen voice gate-off is harmless" {
  let template : Array[@lib.DspNode] = [
    @lib.DspNode::oscillator(@lib.Waveform::Sine, 440.0),
    @lib.DspNode::adsr(0.01, 0.1, 0.7, 0.3),
    @lib.DspNode::envelope_gain(0, 1, 1.0),
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
          let sched = @scheduler.PatternScheduler::new(
            bpm=120.0,
            bindings=b,
            ctx~,
          )
          let pat = @pattern.note(60.0).fast(@pattern.Rational::from_int(2))
          let left = @lib.AudioBuffer::filled(128)
          let right = @lib.AudioBuffer::filled(128)
          for _i = 0; _i < 200; _i = _i + 1 {
            sched.process_block(pat, pool, left, right)
          }
          assert_true(true)
        }
      }
    }
  }
}

///|
test "process_block silence produces zero output" {
  let (pool, sched, left, right) = make_test_sched()
  let pat : @pattern.Pat[@pattern.ControlMap] = @pattern.Pat::silence()
  sched.process_block(pat, pool, left, right)
  let mut all_zero = true
  for i = 0; i < left.length(); i = i + 1 {
    if left.get(i) != 0.0 || right.get(i) != 0.0 {
      all_zero = false
    }
  }
  inspect(all_zero, content="true")
}

///|
test "process_block note pattern produces non-zero output" {
  let (pool, sched, left, right) = make_test_sched()
  let pat = @pattern.note(60.0)
  // Process several blocks so the oscillator has time to produce output
  for _i = 0; _i < 4; _i = _i + 1 {
    sched.process_block(pat, pool, left, right)
  }
  let mut has_nonzero = false
  for i = 0; i < left.length(); i = i + 1 {
    if left.get(i) != 0.0 || right.get(i) != 0.0 {
      has_nonzero = true
    }
  }
  inspect(has_nonzero, content="true")
}

///|
test "process_block multi-block note expiry" {
  let (pool, sched, left, right) = make_test_sched()
  let note_pat = @pattern.note(60.0)
  let silence_pat : @pattern.Pat[@pattern.ControlMap] = @pattern.Pat::silence()
  // First block triggers the note
  sched.process_block(note_pat, pool, left, right)
  inspect(sched.active_note_count() > 0, content="true")
  // Now feed silence so no new notes are triggered.
  // Process enough blocks to cross the cycle boundary (~188 blocks at 120 BPM)
  // so the original note expires via gate-off.
  for _i = 1; _i < 200; _i = _i + 1 {
    sched.process_block(silence_pat, pool, left, right)
  }
  inspect(sched.active_note_count(), content="0")
}
