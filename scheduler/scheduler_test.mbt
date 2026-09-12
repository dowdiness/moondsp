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
  let sched = @scheduler.PatternScheduler::new(bpm=120.0, ctx~).unwrap()
  @debug.assert_eq(sched.sample_counter(), 0L)
  @debug.assert_eq(sched.active_note_count(), 0)
}

///|
test "PatternScheduler::bpm round-trips construction and set_bpm" {
  let ctx = @moondsp.DspContext::new(sample_rate=48000.0, block_size=128)
  let sched = @scheduler.PatternScheduler::new(bpm=120.0, ctx~).unwrap()
  @debug.assert_eq(sched.bpm(), 120.0)
  sched.set_bpm(174.0).unwrap()
  @debug.assert_eq(sched.bpm(), 174.0)
  assert_true(sched.set_bpm(0.0) is Err(_))
  @debug.assert_eq(sched.bpm(), 174.0)
}

///|
test "current_block exposes sample range and logical arc" {
  let ctx = @moondsp.DspContext::new(sample_rate=48000.0, block_size=128)
  let sched = @scheduler.PatternScheduler::new(bpm=120.0, ctx~).unwrap()
  let frame = sched.current_block().unwrap()
  @debug.assert_eq(frame.sample_begin, 0L)
  @debug.assert_eq(frame.sample_end, 128L)
  assert_true(frame.logical_arc.begin == @pattern.Rational::from_int(0))
  assert_true(frame.logical_arc.end_ == @pattern.Rational::new(128L, 24000L))
}

///|
/// Helper: build a VoicePool with a minimal osc→adsr→envelope_gain→output
/// template. Envelope_gain wires the ADSR at index 1 into the signal path so
/// `VoicePool::new`'s orphan-ADSR gate accepts it; swapping to bare `gain(0)`
/// would orphan the ADSR and be rejected.
/// The 0.3 ms release at 48 kHz lasts about 14 samples: the first 128-sample
/// block after gate-off contains a tail, and the following block is silent.
/// Release/Kill tests deliberately use this timing to distinguish their effects.
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
    @moondsp.DspNode::envelope_gain(input=0, envelope=1, amount=1.0),
    @moondsp.DspNode::output(2),
  ]
  let ctx = @moondsp.DspContext::new(sample_rate=48000.0, block_size=128)
  let pool = @moondsp.BoundVoicePool::new(
    @moondsp.CompiledTemplate::analyze(template),
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
  let sched = @scheduler.PatternScheduler::new(bpm=120.0, ctx~).unwrap()
  let left = @moondsp.AudioBuffer::filled(128)
  let right = @moondsp.AudioBuffer::filled(128)
  (pool, sched, left, right)
}

///|
fn pid(value : String) -> @identity.PatternNodeId {
  @identity.PatternNodeId::from_string(value) catch {
    _ => abort("expected valid pattern node id")
  }
}

///|
fn note_snapshot(
  id_value : String,
  note_value : Double,
) -> @pattern.PatternSnapshot[@pattern.ControlMap] {
  let doc = @pattern.PatternDoc::from_pattern(
    id=pid(id_value),
    pat=@pattern.note(note_value),
  )
  doc.lower() catch {
    _ => abort("expected pattern snapshot")
  }
}

///|
fn silence_snapshot(
  id_value : String,
) -> @pattern.PatternSnapshot[@pattern.ControlMap] {
  let doc : @pattern.PatternDoc[@pattern.ControlMap] = @pattern.PatternDoc::silence(
    id=pid(id_value),
  )
  doc.lower() catch {
    _ => abort("expected pattern snapshot")
  }
}

///|
fn oid(value : String) -> @identity.OccurrenceId {
  @identity.OccurrenceId::from_string(value) catch {
    _ => abort("expected valid occurrence id")
  }
}

///|
fn sid(value : String) -> @identity.SectionId {
  @identity.SectionId::from_string(value) catch {
    _ => abort("expected valid section id")
  }
}

///|
fn lid(value : String) -> @identity.SectionLayerId {
  @identity.SectionLayerId::from_string(value) catch {
    _ => abort("expected valid section layer id")
  }
}

///|
fn scheduler_section_doc(
  id_value : String,
  name : String,
  midi : Double,
) -> @song.SectionDoc[@pattern.ControlMap] {
  @song.SectionDoc::single(
    id=sid(id_value),
    name~,
    length_cycles=@pattern.Rational::from_int(1),
    scope=@song.TimeScope::identity(),
    layer_id=lid("\{id_value}:main"),
    body=@pattern.note(midi),
  ) catch {
    _ => abort("expected section doc")
  }
}

///|
fn scheduler_song_doc(
  occurrences : Array[@song.SongOccurrenceDoc[@pattern.ControlMap]],
) -> @song.SongDoc[@pattern.ControlMap] {
  @song.SongDoc(parts=occurrences) catch {
    _ => abort("expected song doc")
  }
}

///|
fn song_snapshot(
  doc : @song.SongDoc[@pattern.ControlMap],
) -> @song.SongSnapshot[@pattern.ControlMap] {
  doc.lower() catch {
    _ => abort("expected song snapshot")
  }
}

///|
test "expire_notes: removes notes past their end_time" {
  let (pool, _, ctx) = make_test_pool()
  let sched = @scheduler.PatternScheduler::new(bpm=120.0, ctx~).unwrap()
  let handle = pool.note_on_controls({ "note": 440.0 })
  match handle {
    None => assert_true(false)
    Some(h) => {
      sched.push_active_note(h, @pattern.Rational::from_int(0)).unwrap()
      @debug.assert_eq(sched.active_note_count(), 1)
      let arc = @pattern.TimeSpan::new(
        @pattern.Rational::from_int(1),
        @pattern.Rational::from_int(2),
      )
      sched.expire_notes(pool, arc).unwrap()
      @debug.assert_eq(sched.active_note_count(), 0)
    }
  }
}

///|
test "expire_notes_at: expires on performance sample boundary" {
  let (pool, _, ctx) = make_test_pool()
  let sched = @scheduler.PatternScheduler::new(bpm=120.0, ctx~).unwrap()
  let handle = pool.note_on_controls({ "note": 440.0 })
  match handle {
    None => assert_true(false)
    Some(h) => {
      sched.push_active_note(h, @pattern.Rational::from_int(1)).unwrap()
      sched.expire_notes_at(pool, @scheduler.PerformanceTime(23999L))
      @debug.assert_eq(sched.active_note_count(), 1)
      sched.expire_notes_at(pool, @scheduler.PerformanceTime(24000L))
      @debug.assert_eq(sched.active_note_count(), 0)
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
  @debug.assert_eq(sched.active_note_count(), 1)
  @debug.assert_eq(pool.active_voice_count(), 1)
}

///|
test "process_events: preserves caller-owned event order" {
  let (pool, sched, _, _) = make_test_sched()
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(2),
  )
  let early = @pattern.note(60.0).query(arc)[0]
  let late = early.shift(@pattern.Rational::new(1L, 2L))
  let events = [late, early]
  sched.process_events(events, arc, pool)
  @debug.assert_eq(sched.active_note_count(), 2)
  match (events[0].whole, events[1].whole) {
    (Some(first), Some(second)) => {
      assert_true(first.begin == @pattern.Rational::new(1L, 2L))
      assert_true(second.begin == @pattern.Rational::from_int(0))
    }
    _ => assert_true(false)
  }
}

///|
test "process_block: note(60) triggers one voice" {
  let (pool, sched, left, right) = make_test_sched()
  let pat = @pattern.note(60.0)
  sched.process_block(pat, pool, left, right)
  @debug.assert_eq(pool.active_voice_count(), 1)
  @debug.assert_eq(sched.active_note_count(), 1)
  @debug.assert_eq(sched.sample_counter(), 128L)
}

///|
test "process_snapshot_block: pending snapshot commits at block boundary" {
  let (pool, sched, left, right) = make_test_sched()
  sched.queue_pattern_snapshot(note_snapshot("snapshot_note", 60.0))
  assert_true(sched.has_pending_pattern_snapshot())
  assert_true(!sched.has_active_pattern_snapshot())
  @debug.assert_eq(pool.active_voice_count(), 0)
  sched.process_snapshot_block(pool, left, right)
  assert_true(!sched.has_pending_pattern_snapshot())
  assert_true(sched.has_active_pattern_snapshot())
  @debug.assert_eq(pool.active_voice_count(), 1)
  @debug.assert_eq(sched.active_note_count(), 1)
  @debug.assert_eq(sched.sample_counter(), 128L)
}

///|
test "Release detaches the note while its tail finishes sounding" {
  let (pool, sched, left, right) = make_test_sched()
  let root = pid("release")
  sched.queue_pattern_snapshot(note_snapshot(root.value(), 60.0))
  sched.process_snapshot_block(pool, left, right)
  let outcome = sched
    .apply_pattern_voice_effect_result(
      @scheduler.PatternVoiceScope::node(root),
      @scheduler.ActiveVoiceEffect::Release,
      pool,
    )
    .unwrap()
  @debug.assert_eq(outcome.detached_note_count, 1)
  @debug.assert_eq(sched.active_note_count(), 0)
  sched.process_snapshot_block(pool, left, right)
  assert_true(buffer_abs_sum(left) > 0.0)
  sched.process_snapshot_block(pool, left, right)
  @debug.assert_eq(buffer_abs_sum(left) + buffer_abs_sum(right), 0.0)
}

///|
test "Kill detaches the note and silences it immediately" {
  let (pool, sched, left, right) = make_test_sched()
  let root = pid("kill")
  sched.queue_pattern_snapshot(note_snapshot(root.value(), 60.0))
  sched.process_snapshot_block(pool, left, right)
  let outcome = sched
    .apply_pattern_voice_effect_result(
      @scheduler.PatternVoiceScope::node(root),
      @scheduler.ActiveVoiceEffect::Kill,
      pool,
    )
    .unwrap()
  @debug.assert_eq(outcome.detached_note_count, 1)
  @debug.assert_eq(sched.active_note_count(), 0)
  sched.process_snapshot_block(pool, left, right)
  @debug.assert_eq(buffer_abs_sum(left) + buffer_abs_sum(right), 0.0)
}

///|
test "Retune changes the sounding voice without detaching its note" {
  let (pool, sched, left, right) = make_test_sched()
  let root = pid("retune")
  sched.queue_pattern_snapshot(note_snapshot(root.value(), 60.0))
  sched.process_snapshot_block(pool, left, right)
  assert_true(buffer_abs_sum(left) > 0.0)
  // Mute the envelope gain rather than asserting oscillator sample values.
  let mute = @scheduler.VoiceControlBatch(
    @moondsp.GraphControl::set_param(2, @moondsp.GraphParamSlot::Value0, 0.0),
  )
  let outcome = sched
    .apply_pattern_voice_effect_result(
      @scheduler.PatternVoiceScope::node(root),
      @scheduler.ActiveVoiceEffect::Retune(mute),
      pool,
    )
    .unwrap()
  @debug.assert_eq(outcome.retuned_voice_count, 1)
  @debug.assert_eq(outcome.detached_note_count, 0)
  @debug.assert_eq(sched.active_note_count(), 1)
  @debug.assert_eq(pool.active_voice_count(), 1)
  sched.process_snapshot_block(pool, left, right)
  @debug.assert_eq(buffer_abs_sum(left) + buffer_abs_sum(right), 0.0)
}

///|
test "Rejected retune preserves audio and the previously queued snapshot" {
  let (pool, sched, left, right) = make_test_sched()
  let (reference_pool, reference, expected_left, expected_right) = make_test_sched()
  let root = pid("rejected-retune")
  let playing = note_snapshot(root.value(), 60.0)
  sched.queue_pattern_snapshot(playing)
  reference.queue_pattern_snapshot(playing)
  sched.process_snapshot_block(pool, left, right)
  reference.process_snapshot_block(
    reference_pool, expected_left, expected_right,
  )
  let pending = silence_snapshot("already-queued")
  sched.queue_pattern_snapshot(pending)
  reference.queue_pattern_snapshot(pending)
  // A valid mutation followed by an invalid one must not partially apply.
  let invalid = @scheduler.VoiceControlBatch(
    @moondsp.GraphControl::set_param(2, @moondsp.GraphParamSlot::Value0, 0.0),
    rest=[
      @moondsp.GraphControl::set_param(
        99,
        @moondsp.GraphParamSlot::Value0,
        880.0,
      ),
    ],
  )
  assert_true(
    sched.queue_pattern_snapshot_effect_result(
      note_snapshot("rejected-replacement", 72.0),
      @scheduler.PatternVoiceScope::node(root),
      @scheduler.ActiveVoiceEffect::Retune(invalid),
      pool,
    )
    is Err(_),
  )
  assert_true(sched.has_pending_pattern_snapshot())
  sched.process_snapshot_block(pool, left, right)
  reference.process_snapshot_block(
    reference_pool, expected_left, expected_right,
  )
  for i in 0..<left.length() {
    @debug.assert_eq(left.get(i), expected_left.get(i))
    @debug.assert_eq(right.get(i), expected_right.get(i))
  }
  // Cross the next cycle onset and the old note's release tail.
  for _ in 0..<200 {
    sched.process_snapshot_block(pool, left, right)
  }
  @debug.assert_eq(sched.active_note_count(), 0)
  @debug.assert_eq(buffer_abs_sum(left) + buffer_abs_sum(right), 0.0)
}

///|
test "Pattern selection kills the selected child but leaves its sibling sounding" {
  let (pool, sched, left, right) = make_test_sched()
  let (reference_pool, reference, expected_left, expected_right) = make_test_sched()
  reference.queue_pattern_snapshot(note_snapshot("sibling", 72.0))
  reference.process_snapshot_block(
    reference_pool, expected_left, expected_right,
  )
  let doc = @pattern.PatternDoc::stack(id=pid("mix"), docs=[
    @pattern.PatternDoc::from_pattern(
      id=pid("selected"),
      pat=@pattern.note(60.0),
    ),
    @pattern.PatternDoc::from_pattern(
      id=pid("sibling"),
      pat=@pattern.note(72.0),
    ),
  ])
  sched.queue_pattern_snapshot(doc.lower())
  sched.process_snapshot_block(pool, left, right)
  let outcome = sched
    .apply_pattern_voice_effect_result(
      @scheduler.PatternVoiceScope::node(pid("selected")),
      @scheduler.ActiveVoiceEffect::Kill,
      pool,
    )
    .unwrap()
  @debug.assert_eq(outcome.detached_note_count, 1)
  @debug.assert_eq(sched.active_note_count(), 1)
  sched.process_snapshot_block(pool, left, right)
  reference.process_snapshot_block(
    reference_pool, expected_left, expected_right,
  )
  assert_true(buffer_abs_sum(expected_left) > 0.0)
  for i in 0..<left.length() {
    @debug.assert_eq(left.get(i), expected_left.get(i))
    @debug.assert_eq(right.get(i), expected_right.get(i))
  }
}

///|
test "Song layer selection does not cross section boundaries" {
  let (pool, sched, left, right) = make_test_sched()
  let (reference_pool, reference, expected_left, expected_right) = make_test_sched()
  reference.queue_pattern_snapshot(note_snapshot("unrelated", 72.0))
  reference.process_snapshot_block(
    reference_pool, expected_left, expected_right,
  )
  let layer = lid("shared-layer")
  let sections = ["selected", "unrelated"].map(name => {
    @song.SectionDoc::single(
      id=sid(name),
      name~,
      layer_id=layer,
      length_cycles=@pattern.Rational::from_int(1),
      scope=@song.TimeScope::identity(),
      body=@pattern.note(if name == "selected" { 60.0 } else { 72.0 }),
    )
  })
  let doc = scheduler_song_doc(
    sections.map(section => {
      @song.SongOccurrenceDoc::at(
        id=oid(section.name()),
        name=section.name(),
        section~,
        start=@pattern.Rational::from_int(0),
      )
    }),
  )
  sched.queue_song_snapshot(song_snapshot(doc))
  sched.process_snapshot_block(pool, left, right)
  let outcome = sched
    .apply_song_voice_effect_result(
      @scheduler.SongVoiceScope::layer(sid("selected"), layer),
      @scheduler.ActiveVoiceEffect::Kill,
      pool,
    )
    .unwrap()
  @debug.assert_eq(outcome.detached_note_count, 1)
  @debug.assert_eq(sched.active_note_count(), 1)
  sched.process_snapshot_block(pool, left, right)
  reference.process_snapshot_block(
    reference_pool, expected_left, expected_right,
  )
  assert_true(buffer_abs_sum(expected_left) > 0.0)
  for i in 0..<left.length() {
    @debug.assert_eq(left.get(i), expected_left.get(i))
    @debug.assert_eq(right.get(i), expected_right.get(i))
  }
}

///|
test "Retune preflights later voices before mutating the first voice" {
  let (pool, sched, left, right) = make_test_sched()
  let (reference_pool, reference, expected_left, expected_right) = make_test_sched()
  let root = pid("mixed-templates")
  for pair in [(pool, sched), (reference_pool, reference)] {
    let (p, s) = pair
    s.queue_pattern_snapshot(note_snapshot(root.value(), 60.0))
    s.process_snapshot_block(p, left, right)
    // Old voices keep ADSR at index 1; new voices have an oscillator there.
    p
    .set_template(
      @moondsp.CompiledTemplate::analyze([
        @moondsp.DspNode::adsr(
          attack_ms=0.01,
          decay_ms=0.1,
          sustain=0.7,
          release_ms=0.3,
        ),
        @moondsp.DspNode::oscillator(@moondsp.Waveform::Sine, 440.0),
        @moondsp.DspNode::envelope_gain(input=1, envelope=0, amount=1.0),
        @moondsp.DspNode::output(2),
      ]),
      @moondsp.ControlBindingBuilder::new().bind(
        key="note",
        node_index=1,
        slot=@moondsp.GraphParamSlot::Value0,
      ),
    )
    .unwrap()
    // A distinct entry starts while the retiring original voice is still held.
    let quick = @pattern.PatternDoc::stack(id=root, docs=[
      @pattern.PatternDoc::from_pattern(
        id=pid("mixed-templates-new"),
        pat=@pattern.note(60.0).fast(@pattern.Rational::from_int(100)),
      ),
    ])
    s.queue_pattern_snapshot(quick.lower())
    s.process_snapshot_block(p, left, right)
  }
  @debug.assert_eq(sched.active_note_count(), 2)
  let controls = @scheduler.VoiceControlBatch(
    @moondsp.GraphControl::set_param(2, @moondsp.GraphParamSlot::Value0, 0.0),
    rest=[
      @moondsp.GraphControl::set_param(1, @moondsp.GraphParamSlot::Value2, 0.0),
    ],
  )
  assert_true(
    sched.apply_pattern_voice_effect_result(
      @scheduler.PatternVoiceScope::node(root),
      @scheduler.ActiveVoiceEffect::Retune(controls),
      pool,
    )
    is Err(_),
  )
  sched.process_snapshot_block(pool, left, right)
  reference.process_snapshot_block(
    reference_pool, expected_left, expected_right,
  )
  for i in 0..<left.length() {
    @debug.assert_eq(left.get(i), expected_left.get(i))
    @debug.assert_eq(right.get(i), expected_right.get(i))
  }
}

///|
test "process_snapshot_block: queued snapshot does not backfill past onsets" {
  let (pool, sched, left, right) = make_test_sched()
  sched.process_snapshot_block(pool, left, right)
  @debug.assert_eq(sched.sample_counter(), 128L)
  sched.queue_pattern_snapshot(note_snapshot("late_snapshot_note", 60.0))
  sched.process_snapshot_block(pool, left, right)
  @debug.assert_eq(pool.active_voice_count(), 0)
  @debug.assert_eq(sched.active_note_count(), 0)
  @debug.assert_eq(sched.sample_counter(), 256L)
}

///|
test "process_snapshot_block: silent edit lets active note ring" {
  let (pool, sched, left, right) = make_test_sched()
  sched.queue_pattern_snapshot(note_snapshot("ring_note", 60.0))
  sched.process_snapshot_block(pool, left, right)
  @debug.assert_eq(pool.active_voice_count(), 1)
  @debug.assert_eq(sched.active_note_count(), 1)
  sched.queue_pattern_snapshot(silence_snapshot("ring_silence"))
  sched.process_snapshot_block(pool, left, right)
  @debug.assert_eq(pool.active_voice_count(), 1)
  @debug.assert_eq(sched.active_note_count(), 1)
}

///|
test "process_snapshot_block: multiple pending snapshots keep the latest" {
  let (pool, sched, left, right) = make_test_sched()
  sched.queue_pattern_snapshot(note_snapshot("coalesced_note", 60.0))
  sched.queue_pattern_snapshot(silence_snapshot("coalesced_silence"))
  sched.process_snapshot_block(pool, left, right)
  @debug.assert_eq(pool.active_voice_count(), 0)
  @debug.assert_eq(sched.active_note_count(), 0)
  assert_true(sched.has_active_pattern_snapshot())
  assert_true(!sched.has_pending_pattern_snapshot())
}

///|
test "process_song_snapshot_block: pending song snapshot commits at block boundary" {
  let (pool, sched, left, right) = make_test_sched()
  let main_id = oid("song-snapshot:main")
  let section = scheduler_section_doc("section:song-snapshot", "Main", 60.0)
  let doc = scheduler_song_doc([
    @song.SongOccurrenceDoc(id=main_id, name="Main", section~),
  ])
  sched.queue_song_snapshot(song_snapshot(doc))
  assert_true(sched.has_pending_song_snapshot())
  assert_true(!sched.has_active_song_snapshot())
  assert_true(sched.active_song_revision() is None)
  sched.process_song_snapshot_block(pool, left, right)
  assert_true(!sched.has_pending_song_snapshot())
  assert_true(sched.has_active_song_snapshot())
  assert_true(sched.active_song_revision() == Some(doc.revision()))
  let outcome = sched
    .apply_song_voice_effect_result(
      @scheduler.SongVoiceScope::occurrence(main_id),
      @scheduler.ActiveVoiceEffect::Release,
      pool,
    )
    .unwrap()
  @debug.assert_eq(outcome.detached_note_count, 1)
  @debug.assert_eq(sched.active_note_count(), 0)
  @debug.assert_eq(sched.sample_counter(), 128L)
}

///|
test "process_song_snapshot_block: same-layout song edit commits without layout boundary change" {
  let (pool, sched, left, right) = make_test_sched()
  let main_id = oid("song-snapshot:same-layout")
  let section_id = "section:same-layout"
  let layer_id = lid("\{section_id}:main")
  let section = scheduler_section_doc(section_id, "Main", 60.0)
  let doc = scheduler_song_doc([
    @song.SongOccurrenceDoc(id=main_id, name="Main", section~),
  ])
  sched.queue_song_snapshot(song_snapshot(doc))
  sched.process_song_snapshot_block(pool, left, right)
  let edited_section = section.replace_layer_body(
    layer_id,
    body=@pattern.note(62.0),
  )
  let edited = doc.replace_occurrence_section(main_id, section=edited_section)
  assert_true(edited.revision() != doc.revision())
  assert_true(edited.layout_revision() == doc.layout_revision())
  sched.queue_song_snapshot(song_snapshot(edited))
  sched.process_song_snapshot_block(pool, left, right)
  assert_true(sched.active_song_revision() == Some(edited.revision()))
  assert_true(
    sched.active_song_layout_revision() == Some(doc.layout_revision()),
  )
  @debug.assert_eq(sched.sample_counter(), 256L)
}

///|
test "process_song_snapshot_block: layout edit does not backfill past onsets" {
  let (pool, sched, left, right) = make_test_sched()
  let main_id = oid("song-snapshot:no-backfill")
  let section = scheduler_section_doc("section:no-backfill", "Main", 60.0)
  let doc = scheduler_song_doc([
    @song.SongOccurrenceDoc::at(
      id=main_id,
      start=@pattern.Rational::from_int(1),
      name="Main",
      section~,
    ),
  ])
  sched.queue_song_snapshot(song_snapshot(doc))
  sched.process_song_snapshot_block(pool, left, right)
  @debug.assert_eq(pool.active_voice_count(), 0)
  let edited = doc.set_occurrence_start(
    main_id,
    start=@pattern.Rational::from_int(0),
  )
  assert_true(edited.layout_revision() != doc.layout_revision())
  sched.queue_song_snapshot(song_snapshot(edited))
  sched.process_song_snapshot_block(pool, left, right)
  assert_true(
    sched.active_song_layout_revision() == Some(edited.layout_revision()),
  )
  @debug.assert_eq(pool.active_voice_count(), 0)
  @debug.assert_eq(sched.active_note_count(), 0)
  @debug.assert_eq(sched.sample_counter(), 256L)
}

///|
test "process_song_snapshot_block: layout replacement lets active note ring" {
  let (pool, sched, left, right) = make_test_sched()
  let main_id = oid("song-snapshot:ring")
  let section = scheduler_section_doc("section:ring", "Main", 60.0)
  let doc = scheduler_song_doc([
    @song.SongOccurrenceDoc(id=main_id, name="Main", section~),
  ])
  sched.queue_song_snapshot(song_snapshot(doc))
  sched.process_song_snapshot_block(pool, left, right)
  @debug.assert_eq(pool.active_voice_count(), 1)
  @debug.assert_eq(sched.active_note_count(), 1)
  let edited = doc.set_occurrence_start(
    main_id,
    start=@pattern.Rational::from_int(2),
  )
  sched.queue_song_snapshot(song_snapshot(edited))
  sched.process_song_snapshot_block(pool, left, right)
  assert_true(
    sched.active_song_layout_revision() == Some(edited.layout_revision()),
  )
  @debug.assert_eq(pool.active_voice_count(), 1)
  @debug.assert_eq(sched.active_note_count(), 1)
}

///|
test "process_song_snapshot_block: multiple pending song snapshots keep the latest" {
  let (pool, sched, left, right) = make_test_sched()
  let main_id = oid("song-snapshot:coalesced")
  let section = scheduler_section_doc("section:coalesced", "Main", 60.0)
  let first = scheduler_song_doc([
    @song.SongOccurrenceDoc(id=main_id, name="Main", section~),
  ])
  let latest = first.set_occurrence_start(
    main_id,
    start=@pattern.Rational::from_int(2),
  )
  sched.queue_song_snapshot(song_snapshot(first))
  sched.queue_song_snapshot(song_snapshot(latest))
  sched.process_song_snapshot_block(pool, left, right)
  assert_true(!sched.has_pending_song_snapshot())
  assert_true(sched.has_active_song_snapshot())
  assert_true(
    sched.active_song_layout_revision() == Some(latest.layout_revision()),
  )
  @debug.assert_eq(pool.active_voice_count(), 0)
  @debug.assert_eq(sched.active_note_count(), 0)
}

///|
test "process_playback_snapshot_block: pattern and song snapshots share one pending slot" {
  let (pool, sched, left, right) = make_test_sched()
  let pattern = note_snapshot("playback-snapshot:pattern", 60.0)
  let main_id = oid("playback-snapshot:song")
  let section = scheduler_section_doc("section:playback-snapshot", "Main", 64.0)
  let song_doc = scheduler_song_doc([
    @song.SongOccurrenceDoc::at(
      id=main_id,
      start=@pattern.Rational::from_int(2),
      name="Main",
      section~,
    ),
  ])
  sched.queue_playback_snapshot(@scheduler.PlaybackSnapshot::pattern(pattern))
  sched.queue_playback_snapshot(
    @scheduler.PlaybackSnapshot::song(song_snapshot(song_doc)),
  )
  assert_true(sched.has_pending_playback_snapshot())
  assert_true(!sched.has_pending_pattern_snapshot())
  assert_true(sched.has_pending_song_snapshot())
  sched.process_playback_snapshot_block(pool, left, right)
  assert_true(sched.has_active_playback_snapshot())
  assert_true(!sched.has_active_pattern_snapshot())
  assert_true(sched.has_active_song_snapshot())
  assert_true(sched.active_playback_revision() == Some(song_doc.revision()))
  assert_true(
    sched.active_playback_song_layout_revision() ==
    Some(song_doc.layout_revision()),
  )
  @debug.assert_eq(pool.active_voice_count(), 0)
  sched.queue_playback_snapshot(@scheduler.PlaybackSnapshot::pattern(pattern))
  sched.process_playback_snapshot_block(pool, left, right)
  assert_true(sched.has_active_pattern_snapshot())
  assert_true(!sched.has_active_song_snapshot())
  assert_true(sched.active_playback_revision() == Some(pattern.revision()))
  assert_true(sched.active_playback_song_layout_revision() is None)
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
  @debug.assert_eq(
    pattern_sched.sample_counter(),
    section_sched.sample_counter(),
  )
  @debug.assert_eq(
    pattern_sched.active_note_count(),
    section_sched.active_note_count(),
  )
  @debug.assert_eq(
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
  let song = @song.Song(parts=[@song.SongPart(name="main", section~)])
  section_sched.process_section_block(
    section, section_pool, section_left, section_right,
  )
  song_sched.process_song_block(song, song_pool, song_left, song_right)
  @debug.assert_eq(section_sched.sample_counter(), song_sched.sample_counter())
  @debug.assert_eq(
    section_sched.active_note_count(),
    song_sched.active_note_count(),
  )
  @debug.assert_eq(
    section_pool.active_voice_count(),
    song_pool.active_voice_count(),
  )
}

///|
test "process_block: empty pattern triggers no voices" {
  let (pool, sched, left, right) = make_test_sched()
  let pat : @pattern.Pat[@pattern.ControlMap] = @pattern.Pat::silence()
  sched.process_block(pat, pool, left, right)
  @debug.assert_eq(pool.active_voice_count(), 0)
  @debug.assert_eq(sched.active_note_count(), 0)
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
  @debug.assert_eq(sched.active_note_count(), 1)
  for _i = 1; _i < 190; _i = _i + 1 {
    sched.process_block(pat, pool, left, right)
  }
  // After crossing cycle boundary, old note expired, new one triggered
  @debug.assert_eq(sched.active_note_count(), 1)
}

///|
test "process_block: gate-off is sent within the block containing the endpoint" {
  let (pool, sched, left, right) = make_test_sched()
  let note_pat = @pattern.note(60.0)
  let silence_pat : @pattern.Pat[@pattern.ControlMap] = @pattern.Pat::silence()
  sched.process_block(note_pat, pool, left, right)
  for _i = 0; _i < 187; _i = _i + 1 {
    sched.process_block(silence_pat, pool, left, right)
  }
  @debug.assert_eq(sched.sample_counter(), 24064L)
  @debug.assert_eq(sched.active_note_count(), 0)
}

///|
test "process_block: pan key applies per-voice pan" {
  let (pool, sched, left, right) = make_test_sched()
  let pat = @pattern.merge_control(@pattern.note(60.0), @pattern.s_pan(-1.0))
  sched.process_block(pat, pool, left, right)
  @debug.assert_eq(pool.active_voice_count(), 1)
  @debug.assert_eq(sched.active_note_count(), 1)
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
    @moondsp.DspNode::envelope_gain(input=0, envelope=1, amount=1.0),
    @moondsp.DspNode::output(2),
  ]
  let ctx = @moondsp.DspContext::new(sample_rate=48000.0, block_size=128)
  let pool = @moondsp.BoundVoicePool::new(
    @moondsp.CompiledTemplate::analyze(template),
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
      let sched = @scheduler.PatternScheduler::new(bpm=120.0, ctx~).unwrap()
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
  let total = for i in 0..<buf.length(); sum = 0.0 {
    let v = buf.get(i)
    continue sum + (if v < 0.0 { -v } else { v })
  } nobreak {
    sum
  }
  total
}

///|
test "process_block silence produces zero output" {
  let (pool, sched, left, right) = make_test_sched()
  let pat : @pattern.Pat[@pattern.ControlMap] = @pattern.Pat::silence()
  sched.process_block(pat, pool, left, right)
  let all_zero = for i in 0..<left.length() {
    if left.get(i) != 0.0 || right.get(i) != 0.0 {
      break false
    }
  } nobreak {
    true
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
  let has_nonzero = for i in 0..<left.length() {
    if left.get(i) != 0.0 || right.get(i) != 0.0 {
      break true
    }
  } nobreak {
    false
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
  @debug.assert_eq(right_energy, 0.0)
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
  @debug.assert_eq(left_energy, 0.0)
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

///|
test "playback snapshot routes room into the shared send only" {
  let (pool, sched, left, right) = make_test_sched()
  let pat = @pattern.merge_control(
    @pattern.note(60.0),
    @pattern.control("room", 0.5),
  )
  let doc = @pattern.PatternDoc::from_pattern(
    id=pid("scheduler:room-send"),
    pat~,
  )
  sched.queue_pattern_snapshot(doc.lower())
  let send_left = @moondsp.AudioBuffer::filled(128)
  let send_right = @moondsp.AudioBuffer::filled(128)
  for _ in 0..<4 {
    sched.process_playback_snapshot_block_with_send(
      pool, left, right, send_left, send_right,
    )
  }
  let dry_energy = buffer_abs_sum(left) + buffer_abs_sum(right)
  let send_energy = buffer_abs_sum(send_left) + buffer_abs_sum(send_right)
  assert_true(dry_energy > 0.0)
  assert_true((send_energy - dry_energy * 0.5).abs() < 0.0001)
}

///|
test "deferred pattern replacement preserves selected voice provenance" {
  let (pool, sched, left, right) = make_test_sched()
  let root = pid("deferred-provenance-root")
  let selected = pid("deferred-provenance-selected")
  let sibling = pid("deferred-provenance-sibling")
  let initial = @pattern.PatternDoc::stack(id=root, docs=[
    @pattern.PatternDoc::from_pattern(id=selected, pat=@pattern.note(60.0)),
    @pattern.PatternDoc::from_pattern(id=sibling, pat=@pattern.note(72.0)),
  ])
  let replacement = @pattern.PatternDoc::stack(id=root, docs=[
    @pattern.PatternDoc::from_pattern(
      id=selected,
      pat=@pattern.note(64.0).fast(@pattern.Rational::from_int(2)),
    ),
    @pattern.PatternDoc::from_pattern(id=sibling, pat=@pattern.note(72.0)),
  ])
  sched.queue_pattern_snapshot(initial.lower())
  sched.process_snapshot_block(pool, left, right)
  @debug.assert_eq(sched.active_note_count(), 2)
  sched.queue_pattern_snapshot(replacement.lower())
  let old_outcome = sched
    .apply_pattern_voice_effect_result(
      @scheduler.PatternVoiceScope::node(selected),
      @scheduler.ActiveVoiceEffect::Kill,
      pool,
    )
    .unwrap()
  @debug.assert_eq(old_outcome.detached_note_count, 1)
  @debug.assert_eq(sched.active_note_count(), 1)
  for _ in 0..<190 {
    sched.process_snapshot_block(pool, left, right)
  }
  let new_outcome = sched
    .apply_pattern_voice_effect_result(
      @scheduler.PatternVoiceScope::node(selected),
      @scheduler.ActiveVoiceEffect::Kill,
      pool,
    )
    .unwrap()
  @debug.assert_eq(new_outcome.detached_note_count, 1)
  // The sibling remains audible after both selected generations are killed.
  @debug.assert_eq(sched.active_note_count(), 1)
}

///|
test "deferred song replacement preserves selected layer provenance" {
  let (pool, sched, left, right) = make_test_sched()
  let occurrence = oid("deferred-song-provenance-occurrence")
  let section_id = sid("deferred-song-provenance-section")
  let lead_id = lid("deferred-song-provenance-lead")
  let pad_id = lid("deferred-song-provenance-pad")
  let section = @song.SectionDoc::SectionDoc(
    id=section_id,
    name="Deferred",
    length_cycles=@pattern.Rational::from_int(4),
    scope=@song.TimeScope::identity(),
    body=@song.SectionDocBody::layers([
      @song.SectionLayerDoc(id=lead_id, name="Lead", body=@pattern.note(60.0)),
      @song.SectionLayerDoc(id=pad_id, name="Pad", body=@pattern.note(72.0)),
    ]),
  )
  let initial = scheduler_song_doc([
    @song.SongOccurrenceDoc(id=occurrence, name="Deferred", section~),
  ])
  let edited_section = section.replace_layer_body(
    lead_id,
    body=@pattern.note(64.0).fast(@pattern.Rational::from_int(2)),
  )
  let replacement = initial.replace_occurrence_section(
    occurrence,
    section=edited_section,
  )
  sched.queue_song_snapshot(song_snapshot(initial))
  sched.process_snapshot_block(pool, left, right)
  @debug.assert_eq(sched.active_note_count(), 2)
  sched.queue_song_snapshot(song_snapshot(replacement))
  let old_outcome = sched
    .apply_song_voice_effect_result(
      @scheduler.SongVoiceScope::layer(section_id, lead_id),
      @scheduler.ActiveVoiceEffect::Kill,
      pool,
    )
    .unwrap()
  @debug.assert_eq(old_outcome.detached_note_count, 1)
  @debug.assert_eq(sched.active_note_count(), 1)
  for _ in 0..<190 {
    sched.process_snapshot_block(pool, left, right)
  }
  let new_outcome = sched
    .apply_song_voice_effect_result(
      @scheduler.SongVoiceScope::layer(section_id, lead_id),
      @scheduler.ActiveVoiceEffect::Kill,
      pool,
    )
    .unwrap()
  @debug.assert_eq(new_outcome.detached_note_count, 1)
  // The unchanged pad layer remains tracked after both lead generations stop.
  @debug.assert_eq(sched.active_note_count(), 1)
}
