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
  let ctx = @moondsp.DspContext::new(sample_rate=48000.0, block_size=128)
  let sched = @scheduler.PatternScheduler::new(bpm=120.0, ctx~)
  assert_eq(sched.sample_counter(), 0L)
  assert_eq(sched.active_note_count(), 0)
}

///|
test "compute_arc: first block at 120 BPM" {
  let ctx = @moondsp.DspContext::new(sample_rate=48000.0, block_size=128)
  let arc = @scheduler.compute_arc(0L, 120.0, ctx)
  let zero = @pattern.Rational::from_int(0)
  assert_true(arc.begin == zero)
  let expected_end = @pattern.Rational::new(15360L, 2880000L)
  assert_true(arc.end_ == expected_end)
}

///|
test "compute_arc: second block at 120 BPM" {
  let ctx = @moondsp.DspContext::new(sample_rate=48000.0, block_size=128)
  let arc = @scheduler.compute_arc(128L, 120.0, ctx)
  let expected_start = @pattern.Rational::new(15360L, 2880000L)
  let expected_end = @pattern.Rational::new(30720L, 2880000L)
  assert_true(arc.begin == expected_start)
  assert_true(arc.end_ == expected_end)
}

///|
test "compute_arc: fractional BPM 120.5 preserves precision" {
  let ctx = @moondsp.DspContext::new(sample_rate=48000.0, block_size=128)
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
test "cycle_to_sample: one cycle at 120 BPM is 24000 samples" {
  let ctx = @moondsp.DspContext::new(sample_rate=48000.0, block_size=128)
  let sample = @scheduler.cycle_to_sample(
    @pattern.Rational::from_int(1),
    120.0,
    ctx,
  )
  assert_eq(sample, 24000L)
}

///|
test "cycle_to_sample: rounds up to the first sample at or after cycle" {
  let ctx = @moondsp.DspContext::new(sample_rate=48000.0, block_size=128)
  let sample = @scheduler.cycle_to_sample(
    @pattern.Rational::new(1L, 3L),
    120.0,
    ctx,
  )
  assert_eq(sample, 8000L)
  let rounded = @scheduler.cycle_to_sample(
    @pattern.Rational::new(1L, 7L),
    120.0,
    ctx,
  )
  assert_eq(rounded, 3429L)
}

///|
test "current_block exposes sample range and logical arc" {
  let ctx = @moondsp.DspContext::new(sample_rate=48000.0, block_size=128)
  let sched = @scheduler.PatternScheduler::new(bpm=120.0, ctx~)
  let frame = sched.current_block()
  assert_eq(frame.sample_begin, 0L)
  assert_eq(frame.sample_end, 128L)
  assert_true(frame.logical_arc == @scheduler.compute_arc(0L, 120.0, ctx))
}

///|
/// Helper: build a VoicePool with a minimal osc→adsr→envelope_gain→output
/// template. Envelope_gain wires the ADSR at index 1 into the signal path so
/// `VoicePool::new`'s orphan-ADSR gate accepts it; swapping to bare `gain(0)`
/// would orphan the ADSR and be rejected.
fn make_test_pool() -> (
  @moondsp.BoundVoicePool,
  Array[@moondsp.DspNode],
  @moondsp.DspContext,
) {
  let template : Array[@moondsp.DspNode] = [
    @moondsp.DspNode::oscillator(@moondsp.Waveform::Sine, 440.0),
    @moondsp.DspNode::adsr(
      attack_ms=0.01,
      decay_ms=0.1,
      sustain=0.7,
      release_ms=0.3,
    ),
    @moondsp.DspNode::envelope_gain(0, 1, 1.0),
    @moondsp.DspNode::output(2),
  ]
  let ctx = @moondsp.DspContext::new(sample_rate=48000.0, block_size=128)
  let pool = @moondsp.BoundVoicePool::new(
    template,
    ctx,
    @moondsp.ControlBindingBuilder::new().bind(
      key="note",
      node_index=0,
      slot=@moondsp.GraphParamSlot::Value0,
    ),
    max_voices=4,
  )
  match pool {
    Ok(p) => (p, template, ctx)
    Err(_) => abort("test pool creation failed")
  }
}

///|
/// Helper: build pool + scheduler + audio buffers for standard test setup.
fn make_test_sched() -> (
  @moondsp.BoundVoicePool,
  @scheduler.PatternScheduler,
  @moondsp.AudioBuffer,
  @moondsp.AudioBuffer,
) {
  let (pool, _, ctx) = make_test_pool()
  let sched = @scheduler.PatternScheduler::new(bpm=120.0, ctx~)
  let left = @moondsp.AudioBuffer::filled(128)
  let right = @moondsp.AudioBuffer::filled(128)
  (pool, sched, left, right)
}

///|
test "expire_notes: removes notes past their end_time" {
  let (pool, _, ctx) = make_test_pool()
  let sched = @scheduler.PatternScheduler::new(bpm=120.0, ctx~)
  let handle = pool.note_on_controls({ "note": 440.0 })
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

///|
test "expire_notes_at: expires on performance sample boundary" {
  let (pool, _, ctx) = make_test_pool()
  let sched = @scheduler.PatternScheduler::new(bpm=120.0, ctx~)
  let handle = pool.note_on_controls({ "note": 440.0 })
  match handle {
    None => assert_true(false)
    Some(h) => {
      sched.push_active_note(h, @pattern.Rational::from_int(1))
      sched.expire_notes_at(pool, @scheduler.PerformanceTime(23999L))
      assert_eq(sched.active_note_count(), 1)
      sched.expire_notes_at(pool, @scheduler.PerformanceTime(24000L))
      assert_eq(sched.active_note_count(), 0)
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
test "process_section_block: identity section matches pattern scheduling" {
  let (pattern_pool, pattern_sched, pattern_left, pattern_right) = make_test_sched()
  let (section_pool, section_sched, section_left, section_right) = make_test_sched()
  let pat = @pattern.note(60.0)
  let section = @song.Section::from_pattern(name="main", body=pat)
  pattern_sched.process_block(pat, pattern_pool, pattern_left, pattern_right)
  section_sched.process_section_block(
    section, section_pool, section_left, section_right,
  )
  assert_eq(pattern_sched.sample_counter(), section_sched.sample_counter())
  assert_eq(
    pattern_sched.active_note_count(),
    section_sched.active_note_count(),
  )
  assert_eq(
    pattern_pool.active_voice_count(),
    section_pool.active_voice_count(),
  )
}

///|
test "process_song_block: one-section song matches section scheduling" {
  let (section_pool, section_sched, section_left, section_right) = make_test_sched()
  let (song_pool, song_sched, song_left, song_right) = make_test_sched()
  let pat = @pattern.note(60.0)
  let section = @song.Section::from_pattern(name="main", body=pat)
  let result = try? @song.Song(parts=[@song.SongPart(name="main", section~)])
  let song = match result {
    Ok(song) => song
    Err(_) => abort("song creation failed")
  }
  section_sched.process_section_block(
    section, section_pool, section_left, section_right,
  )
  song_sched.process_song_block(song, song_pool, song_left, song_right)
  assert_eq(section_sched.sample_counter(), song_sched.sample_counter())
  assert_eq(section_sched.active_note_count(), song_sched.active_note_count())
  assert_eq(section_pool.active_voice_count(), song_pool.active_voice_count())
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
test "process_block: sample-time expiry stays block-quantized" {
  let (pool, sched, left, right) = make_test_sched()
  let note_pat = @pattern.note(60.0)
  let silence_pat : @pattern.Pat[@pattern.ControlMap] = @pattern.Pat::silence()
  sched.process_block(note_pat, pool, left, right)
  for _i = 0; _i < 187; _i = _i + 1 {
    sched.process_block(silence_pat, pool, left, right)
  }
  assert_eq(sched.sample_counter(), 24064L)
  assert_eq(sched.active_note_count(), 1)
  sched.process_block(silence_pat, pool, left, right)
  assert_eq(sched.active_note_count(), 0)
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
  let template : Array[@moondsp.DspNode] = [
    @moondsp.DspNode::oscillator(@moondsp.Waveform::Sine, 440.0),
    @moondsp.DspNode::adsr(
      attack_ms=0.01,
      decay_ms=0.1,
      sustain=0.7,
      release_ms=0.3,
    ),
    @moondsp.DspNode::envelope_gain(0, 1, 1.0),
    @moondsp.DspNode::output(2),
  ]
  let ctx = @moondsp.DspContext::new(sample_rate=48000.0, block_size=128)
  let pool = @moondsp.BoundVoicePool::new(
    template,
    ctx,
    @moondsp.ControlBindingBuilder::new().bind(
      key="note",
      node_index=0,
      slot=@moondsp.GraphParamSlot::Value0,
    ),
    max_voices=1,
  )
  match pool {
    Err(_) => assert_true(false)
    Ok(pool) => {
      let sched = @scheduler.PatternScheduler::new(bpm=120.0, ctx~)
      let pat = @pattern.note(60.0).fast(@pattern.Rational::from_int(2))
      let left = @moondsp.AudioBuffer::filled(128)
      let right = @moondsp.AudioBuffer::filled(128)
      for _i = 0; _i < 200; _i = _i + 1 {
        sched.process_block(pat, pool, left, right)
      }
      assert_true(true)
    }
  }
}

///|
/// Sum of absolute sample values across an `AudioBuffer`. Used to
/// detect whether a buffer carries any signal vs is silent.
fn buffer_abs_sum(buf : @moondsp.AudioBuffer) -> Double {
  let arr = buf.as_fixed_array()
  let mut total = 0.0
  for i in 0..<arr.length() {
    let v = arr[i]
    total = total + (if v < 0.0 { -v } else { v })
  }
  total
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
test "process_block: pan=-1 routes signal to left buffer only" {
  let (pool, sched, left, right) = make_test_sched()
  let pat = @pattern.merge_control(@pattern.note(60.0), @pattern.s_pan(-1.0))
  // Run 4 blocks so the ADSR attack accumulates audible energy; matches
  // the existing `process_block: produces non-zero output` test shape.
  for _i = 0; _i < 4; _i = _i + 1 {
    sched.process_block(pat, pool, left, right)
  }
  let left_energy = buffer_abs_sum(left)
  let right_energy = buffer_abs_sum(right)
  // Strict assertion is on the silent side: pan_right_gain is exactly 0
  // for pan=-1, so right_energy is exactly 0 regardless of envelope phase.
  assert_eq(right_energy, 0.0)
  // Loose assertion on the active side: any non-zero proves routing fired.
  assert_true(left_energy > 0.0)
}

///|
test "process_block: pan=+1 routes signal to right buffer only" {
  let (pool, sched, left, right) = make_test_sched()
  let pat = @pattern.merge_control(@pattern.note(60.0), @pattern.s_pan(1.0))
  for _i = 0; _i < 4; _i = _i + 1 {
    sched.process_block(pat, pool, left, right)
  }
  let left_energy = buffer_abs_sum(left)
  let right_energy = buffer_abs_sum(right)
  assert_eq(left_energy, 0.0)
  assert_true(right_energy > 0.0)
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
