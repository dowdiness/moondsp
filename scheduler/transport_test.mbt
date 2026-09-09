///|
// A constant through a zero-release envelope makes scheduling audible as exact
// nonzero sample ranges, independently of oscillator phase.
fn transport_fixture(
  sample_rate? : Double = 48000.0,
) -> (
  @scheduler.PatternScheduler,
  @moondsp.BoundVoicePool,
  @moondsp.AudioBuffer,
  @moondsp.AudioBuffer,
) {
  let ctx = @moondsp.DspContext::new(sample_rate~, block_size=128)
  let template = @moondsp.CompiledTemplate::analyze([
    @moondsp.DspNode::constant(1.0),
    @moondsp.DspNode::adsr(
      attack_ms=0.0,
      decay_ms=0.0,
      sustain=1.0,
      release_ms=0.0,
    ),
    @moondsp.DspNode::envelope_gain(input=0, envelope=1, amount=1.0),
    @moondsp.DspNode::output(2),
  ])
  let pool = @moondsp.BoundVoicePool::new(
    template,
    ctx,
    @moondsp.ControlBindingBuilder::new(),
    max_voices=4,
  ).unwrap()
  (
    @scheduler.PatternScheduler::new(bpm=120.0, ctx~).unwrap(),
    pool,
    ctx.make_buffer(),
    ctx.make_buffer(),
  )
}

///|
fn single_span(
  begin : @pattern.Rational,
  end_ : @pattern.Rational,
) -> @song.Song[@pattern.ControlMap] raise {
  let duration = end_ - begin
  let section = @song.Section::Section(
    name="note",
    length_cycles=duration,
    scope=@song.TimeScope::identity(),
    body=@song.SectionBody::single(
      @pattern.Pat::pure(@pattern.ControlMap::empty()).slow(duration),
    ),
  )
  @song.Song::Song(parts=[
    @song.SongPart::at(start=begin, name="once", section~),
  ])
}

///|
test "audio starts and releases at exact samples within a block" {
  let (sched, pool, left, right) = transport_fixture()
  let pat = single_span(
    @pattern.Rational::new(17L, 24000L),
    @pattern.Rational::new(73L, 24000L),
  )
  sched.process_song_block(pat, pool, left, right)
  for i in 0..<128 {
    assert_eq(left.get(i) > 0.0, i >= 17 && i < 73)
  }
  assert_eq(sched.active_note_count(), 0)
}

///|
test "fractional onset rounded across a block survives a tempo edit exactly once" {
  let (sched, pool, left, right) = transport_fixture()
  let pat = single_span(
    @pattern.Rational::new(255L, 48000L),
    @pattern.Rational::from_int(1),
  )
  sched.process_song_block(pat, pool, left, right)
  assert_eq(sched.active_note_count(), 0)
  for i in 0..<128 {
    assert_eq(left.get(i), 0.0)
  }
  sched.set_bpm(60.0).unwrap()
  sched.process_song_block(pat, pool, left, right)
  assert_true(left.get(0) > 0.0)
  assert_eq(sched.active_note_count(), 1)
  sched.process_song_block(pat, pool, left, right)
  assert_eq(sched.active_note_count(), 1)
}

///|
test "tempo follows remaining musical duration and preserves physical deadlines" {
  // At 128 Hz a block is one second: both notes initially end at 12 seconds.
  let (sched, pool, left, right) = transport_fixture(sample_rate=128.0)
  let pat = single_span(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(24),
  )
  let physical = pool.note_on_controls({}).unwrap()
  sched.push_active_note_until(
    physical,
    @scheduler.PerformanceTime::PerformanceTime(1536L),
  )
  for _ in 0..<10 {
    sched.process_song_block(pat, pool, left, right)
  }
  let before = sched.current_block().unwrap().logical_arc.begin
  sched.set_bpm(60.0).unwrap()
  assert_true(sched.current_block().unwrap().logical_arc.begin == before)
  assert_eq(sched.sample_at(@pattern.Rational::from_int(24)).unwrap(), 1792L)
  for _ in 0..<2 {
    sched.process_song_block(pat, pool, left, right)
  }
  assert_eq(sched.active_note_count(), 1)
  sched.process_song_block(pat, pool, left, right)
  assert_eq(sched.active_note_count(), 1)
  sched.process_song_block(pat, pool, left, right)
  assert_eq(sched.active_note_count(), 0)
  // Released notes cannot be resurrected by slowing again.
  sched.set_bpm(30.0).unwrap()
  sched.process_song_block(pat, pool, left, right)
  assert_eq(sched.active_note_count(), 0)
  for i in 0..<128 {
    assert_eq(left.get(i), 0.0)
  }
}

///|
test "invalid tempo leaves the position and sounding note unchanged" {
  let (sched, pool, left, right) = transport_fixture()
  let pat = single_span(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  sched.process_song_block(pat, pool, left, right)
  let before = sched.current_block().unwrap().logical_arc
  assert_true(sched.set_bpm(0.0) is Err(_))
  assert_true(sched.current_block().unwrap().logical_arc == before)
  assert_eq(sched.active_note_count(), 1)
  assert_eq(sched.sample_at(@pattern.Rational::from_int(1)).unwrap(), 24000L)
}
