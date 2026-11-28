///|
// A constant through a zero-release envelope makes scheduling audible as exact
// nonzero sample ranges, independently of oscillator phase.
fn transport_fixture(
  sample_rate~ : Double = 48000.0,
) -> (
  @scheduler.PatternScheduler,
  @moondsp.BoundVoicePool,
  @moondsp.AudioBuffer,
  @moondsp.AudioBuffer,
) raise {
  let ctx = @moondsp.DspContext(sample_rate~, block_size=128)
  let template = @moondsp.AnalyzedGraph::analyze([
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
  let pool = @moondsp.BoundVoicePool(
    template,
    ctx,
    @moondsp.ControlBindingBuilder()
    .bind_voice(key=@moondsp.Control::Pan, param=Pan)
    .bind(
      key=Attack,
      node_index=1,
      slot=@moondsp.GraphParamSlot::Value0,
      unit=SecondsToMs,
    )
    .bind(key=Decay, node_index=1, slot=@moondsp.GraphParamSlot::Value1)
    .bind(key=Sustain, node_index=1, slot=@moondsp.GraphParamSlot::Value2)
    .bind(
      key=Release,
      node_index=1,
      slot=@moondsp.GraphParamSlot::Value3,
      unit=SecondsToMs,
    ),
    max_voices=4,
  )
  (
    @scheduler.PatternScheduler(bpm=120.0, ctx~, pools=[pool], route=_ => 0),
    pool,
    ctx.make_buffer(),
    ctx.make_buffer(),
  )
}

///|
fn transport_content(
  name : String,
  control : @pattern.ControlMap,
  duration : @pattern.Rational,
) -> @song.SectionLayerDoc[@pattern.UntrackedPatternSnapshot[@score.ScoreEvent]] raise {
  @song.SectionLayerDoc(
    id=@identity.SectionLayerId::from_string("transport:\{name}"),
    name~,
    body=@pattern.PatternDoc::from_pattern(
      id=@identity.PatternNodeId::from_string("transport:\{name}"),
      pat=@pattern.Pat::pure(played(control)).slow(duration),
    ).lower(),
  )
}

///|
/// One note from `begin` to `end_` that plays once; `physical` adds a second
/// note over the same span whose controls give it a physical gate.
fn single_span(
  begin : @pattern.Rational,
  end_ : @pattern.Rational,
  control~ : @pattern.ControlMap = @pattern.ControlMap::empty(),
  physical? : @pattern.ControlMap,
) -> @scheduler.PlaybackSnapshot raise {
  let duration = end_ - begin
  let layers = [transport_content("note", control, duration)]
  if physical is Some(physical) {
    layers.push(transport_content("physical", physical, duration))
  }
  let section = @song.SectionDoc(
    id=@identity.SectionId::from_string("transport:section"),
    name="note",
    length_cycles=duration,
    scope=@song.TimeScope::identity(),
    body=@song.SectionDocBody::layers(layers),
  )
  let song = @song.SongDoc(parts=[
    @song.SongOccurrenceDoc::at(
      id=@identity.OccurrenceId::from_string("transport:once"),
      start=begin,
      name="once",
      section~,
    ),
  ]).lower()
  @scheduler.PlaybackSnapshot::song(song)
}

///|
test "audio starts and releases at exact samples within a block" {
  let (sched, _, left, right) = transport_fixture()
  let pat = single_span(
    @pattern.Rational(17L, 96000L),
    @pattern.Rational(73L, 96000L),
  )
  sched.accept_playback_snapshot(pat)
  sched.render_block(left, right)
  for i in 0..<128 {
    assert_eq(left.get(i) > 0.0, i >= 17 && i < 73)
  }
  assert_eq(sched.active_note_count(), 0)
}

///|
test "fractional onset rounded across a block survives a tempo edit exactly once" {
  let (sched, _, left, right) = transport_fixture()
  let pat = single_span(
    @pattern.Rational(255L, 192000L),
    @pattern.Rational::from_int(1),
  )
  sched.accept_playback_snapshot(pat)
  sched.render_block(left, right)
  assert_eq(sched.active_note_count(), 0)
  for i in 0..<128 {
    assert_eq(left.get(i), 0.0)
  }
  sched.set_bpm(60.0).unwrap()
  sched.render_block(left, right)
  assert_true(left.get(0) > 0.0)
  assert_eq(sched.active_note_count(), 1)
  sched.render_block(left, right)
  assert_eq(sched.active_note_count(), 1)
}

///|
test "tempo follows remaining musical duration and preserves physical deadlines" {
  // At 128 Hz a block is one second: both notes initially end at 12 seconds.
  let (sched, _, left, right) = transport_fixture(sample_rate=128.0)
  // The second note's hold gives it a physical gate of twelve seconds.
  let pat = single_span(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(6),
    physical=@pattern.ControlMap::empty().set(Hold, 12.0),
  )
  sched.accept_playback_snapshot(pat)
  for _ in 0..<10 {
    sched.render_block(left, right)
  }
  let before = sched.current_block().unwrap().logical_arc.begin
  sched.set_bpm(60.0).unwrap()
  assert_true(sched.current_block().unwrap().logical_arc.begin == before)
  assert_eq(sched.sample_at(@pattern.Rational::from_int(6)).unwrap(), 1792L)
  for _ in 0..<2 {
    sched.render_block(left, right)
  }
  assert_eq(sched.active_note_count(), 1)
  sched.render_block(left, right)
  assert_eq(sched.active_note_count(), 1)
  sched.render_block(left, right)
  assert_eq(sched.active_note_count(), 0)
  // Released notes cannot be resurrected by slowing again.
  sched.set_bpm(30.0).unwrap()
  sched.render_block(left, right)
  assert_eq(sched.active_note_count(), 0)
  for i in 0..<128 {
    assert_eq(left.get(i), 0.0)
  }
}

///|
test "invalid tempo leaves the position and sounding note unchanged" {
  let (sched, _, left, right) = transport_fixture()
  let pat = single_span(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  sched.accept_playback_snapshot(pat)
  sched.render_block(left, right)
  let before = sched.current_block().unwrap().logical_arc
  assert_true(sched.set_bpm(0.0) is Err(_))
  assert_true(sched.current_block().unwrap().logical_arc == before)
  assert_eq(sched.active_note_count(), 1)
  assert_eq(sched.sample_at(@pattern.Rational::from_int(1)).unwrap(), 96000L)
}

///|
test "set_tempo rejects atomically when an endpoint is unrepresentable" {
  let (sched, _, left, right) = transport_fixture()
  sched.set_bpm(0.001).unwrap()
  let endpoint = @pattern.Rational(100000000L, 10000019L * 100000003L)
  sched.accept_playback_snapshot(
    single_span(@pattern.Rational::from_int(0), endpoint),
  )
  sched.render_block(left, right)
  assert_eq(sched.active_note_count(), 1)
  let before = sched.current_block().unwrap().logical_arc
  let tempo = @scheduler.Tempo::from_bpm(1000.0).unwrap()
  assert_true(sched.set_tempo(tempo) is Err(_))
  @debug.assert_eq(sched.bpm(), 0.001)
  assert_true(sched.current_block().unwrap().logical_arc == before)
}

///|
test "physical envelope lasts thirteen seconds across a tempo change" {
  let (sched, _, left, right) = transport_fixture(sample_rate=128.0)
  let control = @pattern.ControlMap::empty()
    .set(Attack, 2.0)
    .set(Hold, 3.0)
    .set(Release, 8.0)
  // Half a cycle at 120 BPM lasts one second.
  let song = single_span(
    @pattern.Rational::from_int(0),
    @pattern.Rational(1L, 2L),
    control=control.set(Pan, -1.0),
  )
  // Levels at each second: attack reaches its peak at 2s, hold ends at 5s,
  // and release reaches silence at 13s. The section itself ends at 1s.
  let levels = [
    0.5, 1.0, 1.0, 1.0, 1.0, 0.875, 0.75, 0.625, 0.5, 0.375, 0.25, 0.125, 0.0, 0.0,
  ]
  sched.accept_playback_snapshot(song)
  for second in 0..<14 {
    if second == 3 {
      sched.set_bpm(240.0).unwrap()
    }
    sched.render_block(left, right)
    assert_eq(sched.active_note_count(), if second < 4 { 1 } else { 0 })
    assert_true((left.get(127) - levels[second]).abs() < 0.000001)
  }
}

///|
test "zero hold finishes immediately and invalid hold does not start a voice" {
  let (sched, _, left, right) = transport_fixture(sample_rate=128.0)
  sched.accept_playback_snapshot(
    single_span(
      @pattern.Rational::from_int(0),
      @pattern.Rational::from_int(1),
      control=@pattern.ControlMap::empty().set(Hold, 0.0),
    ),
  )
  sched.render_block(left, right)
  assert_eq(left.get(0), 0.0)
  assert_eq(sched.active_note_count(), 0)
  let (sched, _, left, right) = transport_fixture(sample_rate=128.0)
  sched.accept_playback_snapshot(
    single_span(
      @pattern.Rational::from_int(0),
      @pattern.Rational::from_int(1),
      control=@pattern.ControlMap::empty().set(Attack, 2.0).set(Hold, -1.0),
    ),
  )
  sched.render_block(left, right)
  assert_eq(sched.active_note_count(), 0)
  assert_eq(left.get(0), 0.0)
}

///|
test "without hold the event end releases an unfinished attack" {
  let (sched, _, left, right) = transport_fixture(sample_rate=128.0)
  let song = single_span(
    @pattern.Rational::from_int(0),
    @pattern.Rational(1L, 4L),
    control=@pattern.ControlMap::empty().set(Attack, 2.0).set(Release, 1.0),
  )
  // A quarter cycle at 120 BPM: the gate closes after half a second, during
  // the attack.
  sched.accept_playback_snapshot(song)
  sched.render_block(left, right)
  assert_true(left.get(63) > 0.0)
  assert_true(left.get(127) < left.get(63))
}

///|
test "tempo sample spans preserve exact millibpm arithmetic" {
  let tempo = @scheduler.Tempo::from_bpm(120.1234).unwrap()
  let span = tempo.span_for_samples(128, sample_rate=48000.0).unwrap()
  assert_true(span == @pattern.Rational(128L * 120123L, 11520000000L))
  // The exact block boundary maps back to its final sample without drift.
  assert_eq(tempo.sample_at_start(span, sample_rate=48000.0).unwrap(), 128L)
  assert_true(
    tempo.span_for_samples(128, sample_rate=128.0).unwrap() ==
    @pattern.Rational(128L * 120123L, 128L * 240000L),
  )
  assert_true(
    tempo.span_for_samples(0, sample_rate=48000.0).unwrap() ==
    @pattern.Rational::from_int(0),
  )
}

///|
test "a block's query window is its span at the fastest tempo" {
  // 128 frames / 48000 Hz * 1000 beats/min / 60 / 4 beats per cycle = 1/90 cycle.
  let window = @scheduler.max_query_window_for(
    sample_rate=48000.0,
    block_size=128,
  ).unwrap()
  assert_true(window.span() == @pattern.Rational(1L, 90L))
  for block_size in [0, -1, 65537] {
    assert_true(
      @scheduler.max_query_window_for(sample_rate=48000.0, block_size~)
      is Err(InvalidBlockSize),
    )
  }
  assert_true(
    @scheduler.max_query_window_for(sample_rate=44100.5, block_size=128)
    is Err(InvalidSampleRate),
  )
}

///|
test "tempo sample spans reject invalid sample counts and rates" {
  let tempo = @scheduler.Tempo::from_bpm(120.0).unwrap()
  assert_true(tempo.span_for_samples(-1, sample_rate=48000.0) is Err(_))
  for sample_rate in [0.0, 48000.5, 384001.0, 0.0 / 0.0, 1.0 / 0.0] {
    assert_true(tempo.span_for_samples(128, sample_rate~) is Err(_))
  }
}

///|
test "material admission rejects before retiming and restart recovers capacity" {
  // Tracked material records each onset's pitch, so the test can tell which
  // material plays. Each plays one onset per cycle.
  fn snapshot(
    name : String,
    note : Double,
  ) -> @scheduler.PlaybackSnapshot raise {
    let epoch = @identity.SourceEpoch::SourceEpoch(1L)
    @scheduler.PlaybackSnapshot::pattern(
      @pattern.PatternDoc::atom(
        id=@identity.PatternNodeId::from_string(name),
        source_atom=@identity.SourceAtomId::SourceAtomId(epoch, note.to_int64()),
        value=@score.note(note).query(
            @pattern.TimeSpan(
              @pattern.Rational::from_int(0),
              @pattern.Rational::from_int(1),
            ),
          )[0].value,
      )
      .lower_tracked()
      .playback(),
    )
  }
  let (second, _, left, right) = transport_fixture(sample_rate=128.0)
  let onsets = @scheduler.OnsetBuffer()
  onsets.enable(true)
  second.attach_onset_buffer(onsets)
  second.accept_playback_snapshot(snapshot("old", 60.0))
  second.render_block(left, right)
  assert_eq(onsets.count(), 1)
  assert_eq(onsets.field(0, 5), 60.0)
  let before = second.current_block().unwrap().logical_arc
  let next = snapshot("new", 80.0)
  let tempo = @scheduler.Tempo::from_bpm(60.0).unwrap()
  assert_true(
    second.accept_playback(next, tempo, material_limit=1) is Err(MaterialLimit),
  )
  assert_eq(second.bpm(), 120.0)
  assert_true(second.current_block().unwrap().logical_arc == before)
  assert_eq(second.active_note_count(), 1)
  // The refused material is not staged: nothing waits for a boundary, and
  // the old material keeps playing with no new onset.
  assert_eq(second.pending_material_change_count(), 0)
  second.render_block(left, right)
  assert_true(left.get(0) > 0.0)
  assert_eq(onsets.count(), 1)
  second.accept_playback(next, tempo, material_limit=1, restart=true).unwrap()
  assert_eq(second.bpm(), 60.0)
  assert_eq(second.sample_counter(), 0L)
  assert_eq(second.pending_material_change_count(), 0)
  second.render_block(left, right)
  assert_eq(onsets.count(), 2)
  assert_eq(onsets.field(1, 5), 80.0)
}

///|
/// One occurrence `id`, at 0, of a section played at `rate`, `length`
/// cycles long.
fn rated_song(
  id : String,
  rate : Int64,
  length~ : Int64 = 4L,
) -> @scheduler.PlaybackSnapshot raise {
  let section = @song.SectionDoc::single(
    id=@identity.SectionId::from_string("rated"),
    name="rated",
    length_cycles=@pattern.Rational(length, 1L),
    scope=@song.TimeScope::at_rate(rate=@pattern.Rational(rate, 1L)),
    layer_id=@identity.SectionLayerId::from_string("main"),
    body=@pattern.PatternDoc::from_pattern(
      id=@identity.PatternNodeId::from_string("rated"),
      pat=@pattern.Pat::pure(played(@pattern.ControlMap::empty())),
    ).lower(),
  )
  @scheduler.PlaybackSnapshot::song(
    @song.SongDoc(parts=[
      @song.SongOccurrenceDoc::at(
        id=@identity.OccurrenceId::from_string(id),
        start=@pattern.Rational::from_int(0),
        name=id,
        section~,
      ),
    ]).lower(),
  )
}

///|
test "a section's rate is content, its occurrences are arrangement" {
  let (sched, _, left, right) = transport_fixture()
  let tempo = @scheduler.Tempo::from_bpm(120.0).unwrap()
  sched.accept_playback(rated_song("a", 1L), tempo, material_limit=8).unwrap()
  sched.render_block(left, right)
  // Playing the section twice as fast continues.
  assert_true(
    sched.accept_playback(rated_song("a", 2L), tempo, material_limit=8) is Ok(_),
  )
  // Another length, or another occurrence, is another arrangement.
  assert_true(
    sched.accept_playback(
      rated_song("a", 2L, length=5L),
      tempo,
      material_limit=8,
    )
    is Err(ArrangementChanged),
  )
  assert_true(
    sched.accept_playback(rated_song("b", 2L), tempo, material_limit=8)
    is Err(ArrangementChanged),
  )
  assert_true(
    sched.accept_playback(
      rated_song("b", 2L),
      tempo,
      material_limit=8,
      restart=true,
    )
    is Ok(_),
  )
}

///|
test "the scheduler reports reaching the accepted song's finite end" {
  let (sched, _, left, right) = transport_fixture(sample_rate=128.0)
  // Half a cycle at 120 BPM is one second, one block at 128 Hz.
  let song = single_span(
    @pattern.Rational::from_int(0),
    @pattern.Rational(1L, 2L),
  )
  sched.accept_playback_snapshot(song)
  assert_true(sched.song_end() is Ahead)
  sched.render_block(left, right)
  guard sched.song_end() is Reached(sample, position) else {
    fail("expected the end to be reached")
  }
  assert_eq(sample, 128L)
  assert_eq(position, @pattern.Rational(1L, 2L))
  // A pattern has no finite end.
  sched.accept_playback_snapshot(
    @scheduler.PlaybackSnapshot::pattern(
      @pattern.PatternDoc::from_pattern(
        id=@identity.PatternNodeId::from_string("end:pattern"),
        pat=@pattern.Pat::pure(played(@pattern.ControlMap::empty())),
      )
      .lower()
      .playback(),
    ),
  )
  assert_true(sched.song_end() is Ahead)
}

///|
test "fit is checked from the snapshot: repetition and finite end" {
  let (sched, _, _, _) = transport_fixture()
  let tempo = @scheduler.Tempo::from_bpm(120.0).unwrap()
  let fast = @scheduler.Tempo::from_bpm(1000.0).unwrap()
  // A 1/750-cycle repetition is one block at 120 BPM and less at 1000.
  let section = @song.SectionDoc::single(
    id=@identity.SectionId::from_string("fit"),
    name="fit",
    length_cycles=@pattern.Rational(1L, 750L),
    scope=@song.TimeScope::identity(),
    layer_id=@identity.SectionLayerId::from_string("main"),
    body=@pattern.PatternDoc::from_pattern(
      id=@identity.PatternNodeId::from_string("fit"),
      pat=@pattern.Pat::pure(played(@pattern.ControlMap::empty())),
    ).lower(),
  )
  let repeating = @scheduler.PlaybackSnapshot::song(
    @song.SongDoc(parts=[
      @song.SongOccurrenceDoc(
        id=@identity.OccurrenceId::from_string("fit"),
        name="fit",
        section~,
      ),
    ]).lower(),
    repeat=true,
  )
  assert_true(sched.check_fits(repeating, tempo) is Ok(_))
  assert_true(
    sched.check_fits(repeating, fast) is Err(RepetitionShorterThanBlock),
  )
  sched.accept_playback_snapshot(repeating)
  assert_true(sched.set_tempo(fast) is Err(RepetitionShorterThanBlock))
  assert_eq(sched.bpm(), 120.0)
}
