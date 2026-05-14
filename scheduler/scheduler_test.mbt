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
fn pid(value : String) -> @identity.PatternNodeId {
  let result = try? @identity.PatternNodeId::from_string(value)
  match result {
    Ok(id) => id
    Err(_) => abort("expected valid pattern node id")
  }
}

///|
fn unwrap_control_snapshot(
  result : Result[
    @pattern.PatternSnapshot[@pattern.ControlMap],
    @pattern.PatternDocError,
  ],
) -> @pattern.PatternSnapshot[@pattern.ControlMap] {
  match result {
    Ok(snapshot) => snapshot
    Err(_) => abort("expected pattern snapshot")
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
  unwrap_control_snapshot(try? doc.lower())
}

///|
fn silence_snapshot(
  id_value : String,
) -> @pattern.PatternSnapshot[@pattern.ControlMap] {
  let doc : @pattern.PatternDoc[@pattern.ControlMap] = @pattern.PatternDoc::silence(
    id=pid(id_value),
  )
  unwrap_control_snapshot(try? doc.lower())
}

///|
fn oid(value : String) -> @identity.OccurrenceId {
  let result = try? @identity.OccurrenceId::from_string(value)
  match result {
    Ok(id) => id
    Err(_) => abort("expected valid occurrence id")
  }
}

///|
fn sid(value : String) -> @identity.SectionId {
  let result = try? @identity.SectionId::from_string(value)
  match result {
    Ok(id) => id
    Err(_) => abort("expected valid section id")
  }
}

///|
fn lid(value : String) -> @identity.SectionLayerId {
  let result = try? @identity.SectionLayerId::from_string(value)
  match result {
    Ok(id) => id
    Err(_) => abort("expected valid section layer id")
  }
}

///|
fn scheduler_section_doc(
  id_value : String,
  name : String,
  midi : Double,
) -> @song.SectionDoc[@pattern.ControlMap] {
  let result = try? @song.SectionDoc::single(
    id=sid(id_value),
    name~,
    length_cycles=@pattern.Rational::from_int(1),
    scope=@song.TimeScope::identity(),
    layer_id=lid("\{id_value}:main"),
    body=@pattern.note(midi),
  )
  match result {
    Ok(section) => section
    Err(_) => abort("expected section doc")
  }
}

///|
fn scheduler_song_doc(
  occurrences : Array[@song.SongOccurrenceDoc[@pattern.ControlMap]],
) -> @song.SongDoc[@pattern.ControlMap] {
  let result = try? @song.SongDoc(parts=occurrences)
  match result {
    Ok(doc) => doc
    Err(_) => abort("expected song doc")
  }
}

///|
fn unwrap_song_snapshot(
  result : Result[@song.SongSnapshot[@pattern.ControlMap], @song.SongBuildError],
) -> @song.SongSnapshot[@pattern.ControlMap] {
  match result {
    Ok(snapshot) => snapshot
    Err(_) => abort("expected song snapshot")
  }
}

///|
fn song_snapshot(
  doc : @song.SongDoc[@pattern.ControlMap],
) -> @song.SongSnapshot[@pattern.ControlMap] {
  unwrap_song_snapshot(try? doc.lower())
}

///|
fn note_event(
  note_value : Double,
  arc : @pattern.TimeSpan,
) -> @pattern.Event[@pattern.ControlMap] {
  match @pattern.note(note_value).query(arc).get(0) {
    Some(event) => event
    None => abort("expected note event")
  }
}

///|
fn playback_note_event(
  note_value : Double,
  source : @scheduler.EventSource,
  arc : @pattern.TimeSpan,
) -> @scheduler.PlaybackEvent {
  @scheduler.PlaybackEvent(event=note_event(note_value, arc), source~)
}

///|
test "EventSource records optional authoring IDs" {
  let pattern_id = pid("source:pattern")
  let section_id = sid("source:section")
  let layer_id = lid("source:layer")
  let occurrence_id = oid("source:occurrence")
  let empty = @scheduler.EventSource::none()
  assert_true(empty.is_empty())
  assert_true(empty.pattern_node() is None)
  assert_eq(empty.pattern_nodes().length(), 0)
  assert_true(empty.section() is None)
  assert_true(empty.layer() is None)
  assert_true(empty.occurrence() is None)
  let source = @scheduler.EventSource(
    pattern_node=Some(pattern_id),
    section=Some(section_id),
    layer=Some(layer_id),
    occurrence=Some(occurrence_id),
  )
  assert_true(!source.is_empty())
  assert_true(source.pattern_node() == Some(pattern_id))
  let pattern_nodes = source.pattern_nodes()
  assert_eq(pattern_nodes.length(), 1)
  assert_true(pattern_nodes[0] == pattern_id)
  assert_true(source.section() == Some(section_id))
  assert_true(source.layer() == Some(layer_id))
  assert_true(source.occurrence() == Some(occurrence_id))
}

///|
test "EventSource pattern-node path matches ancestors and primary leaf" {
  let root_id = pid("source:root")
  let leaf_id = pid("source:leaf")
  let source = @scheduler.EventSource::from_pattern_nodes(
    pattern_nodes=[root_id, leaf_id],
    section=None,
    layer=None,
    occurrence=None,
  )
  assert_true(source.pattern_node() == Some(leaf_id))
  assert_true(
    source.matches(@scheduler.AffectedVoiceTarget::from_pattern_node(root_id)),
  )
  assert_true(
    source.matches(@scheduler.AffectedVoiceTarget::from_pattern_node(leaf_id)),
  )
}

///|
test "AffectedVoiceTarget matches explicit provenance and ignores empty targets" {
  let pattern_id = pid("target:pattern")
  let section_id = sid("target:section")
  let layer_id = lid("target:layer")
  let occurrence_id = oid("target:occurrence")
  let source = @scheduler.EventSource(
    pattern_node=Some(pattern_id),
    section=Some(section_id),
    layer=Some(layer_id),
    occurrence=Some(occurrence_id),
  )
  let empty_target = @scheduler.AffectedVoiceTarget(
    pattern_node=None,
    section=None,
    layer=None,
    occurrence=None,
  )
  assert_true(empty_target.is_empty())
  assert_true(!source.matches(empty_target))
  assert_true(
    source.matches(
      @scheduler.AffectedVoiceTarget::from_pattern_node(pattern_id),
    ),
  )
  assert_true(
    source.matches(@scheduler.AffectedVoiceTarget::from_section(section_id)),
  )
  assert_true(
    source.matches(@scheduler.AffectedVoiceTarget::from_layer(layer_id)),
  )
  assert_true(
    source.matches(
      @scheduler.AffectedVoiceTarget::from_occurrence(occurrence_id),
    ),
  )
  let combined = @scheduler.AffectedVoiceTarget(
    pattern_node=Some(pattern_id),
    section=Some(section_id),
    layer=None,
    occurrence=Some(occurrence_id),
  )
  assert_true(source.matches(combined))
  let wrong_occurrence = @scheduler.AffectedVoiceTarget(
    pattern_node=Some(pattern_id),
    section=Some(section_id),
    layer=None,
    occurrence=Some(oid("target:other-occurrence")),
  )
  assert_true(!source.matches(wrong_occurrence))
  assert_true(
    !@scheduler.EventSource::none().matches(
      @scheduler.AffectedVoiceTarget::from_pattern_node(pattern_id),
    ),
  )
}

///|
test "PlaybackSnapshot::query_playback_events tags pattern root provenance" {
  let root_id = "playback-events:pattern"
  let snapshot = @scheduler.PlaybackSnapshot::pattern(
    note_snapshot(root_id, 60.0),
  )
  let events = snapshot.query_playback_events(
    @pattern.TimeSpan::new(
      @pattern.Rational::from_int(0),
      @pattern.Rational::new(1L, 100L),
    ),
  )
  assert_eq(events.length(), 1)
  assert_true(events[0].source().pattern_node() == Some(pid(root_id)))
  let pattern_nodes = events[0].source().pattern_nodes()
  assert_eq(pattern_nodes.length(), 1)
  assert_true(pattern_nodes[0] == pid(root_id))
  assert_true(events[0].source().section() is None)
  assert_true(events[0].source().occurrence() is None)
  assert_true(events[0].event().value.get("note") == Some(60.0))
}

///|
test "PlaybackSnapshot::query_playback_events tags pattern sub-node path" {
  let (pool, sched, _, _) = make_test_sched()
  let doc_result = try? @pattern.PatternDoc::from_pattern(
    id=pid("playback-events:leaf"),
    pat=@pattern.note(60.0),
  ).fast(id=pid("playback-events:fast"), factor=@pattern.Rational::from_int(2))
  let doc = match doc_result {
    Ok(doc) => doc
    Err(_) => abort("expected pattern doc")
  }
  let snapshot = @scheduler.PlaybackSnapshot::pattern(
    unwrap_control_snapshot(try? doc.lower()),
  )
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::new(1L, 100L),
  )
  let events = snapshot.query_playback_events(arc)
  assert_eq(events.length(), 1)
  let pattern_nodes = events[0].source().pattern_nodes()
  assert_eq(pattern_nodes.length(), 2)
  assert_true(pattern_nodes[0] == pid("playback-events:fast"))
  assert_true(pattern_nodes[1] == pid("playback-events:leaf"))
  assert_true(
    events[0].source().pattern_node() == Some(pid("playback-events:leaf")),
  )
  sched.process_playback_events(events, arc, pool)
  assert_eq(
    sched.affected_active_note_count(
      @scheduler.AffectedVoiceTarget::from_pattern_node(
        pid("playback-events:fast"),
      ),
    ),
    1,
  )
  assert_eq(
    sched.affected_active_note_count(
      @scheduler.AffectedVoiceTarget::from_pattern_node(
        pid("playback-events:leaf"),
      ),
    ),
    1,
  )
}

///|
test "PlaybackSnapshot::query_playback_events tags song occurrence provenance" {
  let (pool, sched, _, _) = make_test_sched()
  let occurrence_id = oid("playback-events:song-occurrence")
  let section_id_value = "section:playback-events-song"
  let section = scheduler_section_doc(section_id_value, "Main", 60.0)
  let doc = scheduler_song_doc([
    @song.SongOccurrenceDoc(id=occurrence_id, name="Main", section~),
  ])
  let snapshot = @scheduler.PlaybackSnapshot::song(song_snapshot(doc))
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::new(1L, 100L),
  )
  let events = snapshot.query_playback_events(arc)
  assert_eq(events.length(), 1)
  assert_true(events[0].source().pattern_node() is None)
  assert_true(events[0].source().section() == Some(sid(section_id_value)))
  assert_true(
    events[0].source().layer() == Some(lid("\{section_id_value}:main")),
  )
  assert_true(events[0].source().occurrence() == Some(occurrence_id))
  assert_true(events[0].event().value.get("note") == Some(60.0))
  sched.process_playback_events(events, arc, pool)
  let target = @scheduler.AffectedVoiceTarget::from_section(
    sid(section_id_value),
  )
  assert_eq(sched.affected_active_note_count(target), 1)
  assert_eq(
    sched.apply_affected_voice_policy(
      @scheduler.AffectedVoicePolicy::GateOffAffected,
      target,
      pool,
    ),
    1,
  )
  assert_eq(sched.active_note_count(), 0)
}

///|
test "PlaybackSnapshot::query_playback_events tags song layer provenance" {
  let (pool, sched, _, _) = make_test_sched()
  let occurrence_id = oid("playback-events:layered-occurrence")
  let section_id = sid("section:playback-events-layered")
  let lead_id = lid("layer:playback-events-lead")
  let pad_id = lid("layer:playback-events-pad")
  let section_result = try? @song.SectionDoc::SectionDoc(
    id=section_id,
    name="Layered",
    length_cycles=@pattern.Rational::from_int(1),
    scope=@song.TimeScope::identity(),
    body=@song.SectionDocBody::layers([
      @song.SectionLayerDoc(id=lead_id, name="Lead", body=@pattern.note(60.0)),
      @song.SectionLayerDoc(id=pad_id, name="Pad", body=@pattern.note(67.0)),
    ]),
  )
  let section = match section_result {
    Ok(section) => section
    Err(_) => abort("expected layered section doc")
  }
  let doc = scheduler_song_doc([
    @song.SongOccurrenceDoc(id=occurrence_id, name="Layered", section~),
  ])
  let snapshot = @scheduler.PlaybackSnapshot::song(song_snapshot(doc))
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::new(1L, 100L),
  )
  let events = snapshot.query_playback_events(arc)
  assert_eq(events.length(), 2)
  assert_true(events[0].source().section() == Some(section_id))
  assert_true(events[0].source().layer() == Some(lead_id))
  assert_true(events[0].source().occurrence() == Some(occurrence_id))
  assert_true(events[0].event().value.get("note") == Some(60.0))
  assert_true(events[1].source().section() == Some(section_id))
  assert_true(events[1].source().layer() == Some(pad_id))
  assert_true(events[1].source().occurrence() == Some(occurrence_id))
  assert_true(events[1].event().value.get("note") == Some(67.0))
  sched.process_playback_events(events, arc, pool)
  assert_eq(
    sched.affected_active_note_count(
      @scheduler.AffectedVoiceTarget::from_layer(lead_id),
    ),
    1,
  )
  assert_eq(
    sched.affected_active_note_count(
      @scheduler.AffectedVoiceTarget::from_layer(pad_id),
    ),
    1,
  )
  assert_eq(
    sched.apply_affected_voice_policy(
      @scheduler.AffectedVoicePolicy::GateOffAffected,
      @scheduler.AffectedVoiceTarget::from_layer(lead_id),
      pool,
    ),
    1,
  )
  assert_eq(sched.active_note_count(), 1)
  assert_eq(
    sched.affected_active_note_count(
      @scheduler.AffectedVoiceTarget::from_layer(pad_id),
    ),
    1,
  )
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
  match sched.active_note_source(0) {
    Some(source) => assert_true(source.is_empty())
    None => assert_true(false)
  }
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
  assert_eq(sched.active_note_count(), 2)
  match (events[0].whole, events[1].whole) {
    (Some(first), Some(second)) => {
      assert_true(first.begin == @pattern.Rational::new(1L, 2L))
      assert_true(second.begin == @pattern.Rational::from_int(0))
    }
    _ => assert_true(false)
  }
}

///|
test "process_playback_events: active note keeps explicit event source" {
  let (pool, sched, _, _) = make_test_sched()
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::new(1L, 100L),
  )
  let events = @pattern.note(60.0).query(arc)
  let event = match events.get(0) {
    Some(event) => event
    None => abort("expected note event")
  }
  let source = @scheduler.EventSource(
    pattern_node=Some(pid("source:active-pattern")),
    section=Some(sid("source:active-section")),
    layer=Some(lid("source:active-layer")),
    occurrence=Some(oid("source:active-occurrence")),
  )
  sched.process_playback_events(
    [@scheduler.PlaybackEvent(event~, source~)],
    arc,
    pool,
  )
  assert_eq(sched.active_note_count(), 1)
  match sched.active_note_source(0) {
    Some(active_source) => assert_true(active_source == source)
    None => assert_true(false)
  }
}

///|
test "affected voice policy preserves empty-source voices and let-ring policy" {
  let (pool, sched, _, _) = make_test_sched()
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::new(1L, 100L),
  )
  let pattern_id = pid("affected:ring-pattern")
  let target = @scheduler.AffectedVoiceTarget::from_pattern_node(pattern_id)
  let source = @scheduler.EventSource(
    pattern_node=Some(pattern_id),
    section=None,
    layer=None,
    occurrence=None,
  )
  sched.process_playback_events(
    [playback_note_event(60.0, source, arc)],
    arc,
    pool,
  )
  sched.process_events(@pattern.note(62.0).query(arc), arc, pool)
  assert_eq(sched.active_note_count(), 2)
  assert_eq(sched.affected_active_note_count(target), 1)
  assert_eq(
    sched.apply_affected_voice_policy(
      @scheduler.AffectedVoicePolicy::LetRing,
      target,
      pool,
    ),
    0,
  )
  assert_eq(sched.active_note_count(), 2)
  assert_true(sched.active_note_matches(0, target) == Some(true))
  assert_true(sched.active_note_matches(99, target) is None)
  assert_eq(
    sched.apply_affected_voice_policy(
      @scheduler.AffectedVoicePolicy::GateOffAffected,
      @scheduler.AffectedVoiceTarget(
        pattern_node=None,
        section=None,
        layer=None,
        occurrence=None,
      ),
      pool,
    ),
    0,
  )
  assert_eq(sched.active_note_count(), 2)
  assert_eq(
    sched.apply_affected_voice_policy(
      @scheduler.AffectedVoicePolicy::GateOffAffected,
      target,
      pool,
    ),
    1,
  )
  assert_eq(sched.active_note_count(), 1)
  match sched.active_note_source(0) {
    Some(active_source) => assert_true(active_source.is_empty())
    None => assert_true(false)
  }
}

///|
test "affected voice policy gates only matching pattern-node active notes" {
  let (pool, sched, _, _) = make_test_sched()
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::new(1L, 100L),
  )
  let first_id = pid("affected:first-pattern")
  let second_id = pid("affected:second-pattern")
  let first_source = @scheduler.EventSource(
    pattern_node=Some(first_id),
    section=None,
    layer=None,
    occurrence=None,
  )
  let second_source = @scheduler.EventSource(
    pattern_node=Some(second_id),
    section=None,
    layer=None,
    occurrence=None,
  )
  sched.process_playback_events(
    [
      playback_note_event(60.0, first_source, arc),
      playback_note_event(62.0, second_source, arc),
    ],
    arc,
    pool,
  )
  let first_target = @scheduler.AffectedVoiceTarget::from_pattern_node(first_id)
  let second_target = @scheduler.AffectedVoiceTarget::from_pattern_node(
    second_id,
  )
  assert_eq(sched.active_note_count(), 2)
  assert_eq(sched.affected_active_note_count(first_target), 1)
  assert_eq(sched.affected_active_note_count(second_target), 1)
  assert_eq(
    sched.apply_affected_voice_policy(
      @scheduler.AffectedVoicePolicy::GateOffAffected,
      first_target,
      pool,
    ),
    1,
  )
  assert_eq(sched.active_note_count(), 1)
  assert_eq(sched.affected_active_note_count(first_target), 0)
  assert_eq(sched.affected_active_note_count(second_target), 1)
}

///|
test "affected voice policy can target section and occurrence boundaries" {
  let (pool, sched, _, _) = make_test_sched()
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::new(1L, 100L),
  )
  let main_section = sid("affected:main-section")
  let other_section = sid("affected:other-section")
  let layer = lid("affected:main-layer")
  let first_occurrence = oid("affected:first-occurrence")
  let second_occurrence = oid("affected:second-occurrence")
  let other_occurrence = oid("affected:other-occurrence")
  let first_source = @scheduler.EventSource(
    pattern_node=None,
    section=Some(main_section),
    layer=Some(layer),
    occurrence=Some(first_occurrence),
  )
  let second_source = @scheduler.EventSource(
    pattern_node=None,
    section=Some(main_section),
    layer=Some(layer),
    occurrence=Some(second_occurrence),
  )
  let other_source = @scheduler.EventSource(
    pattern_node=None,
    section=Some(other_section),
    layer=None,
    occurrence=Some(other_occurrence),
  )
  sched.process_playback_events(
    [
      playback_note_event(60.0, first_source, arc),
      playback_note_event(62.0, second_source, arc),
      playback_note_event(64.0, other_source, arc),
    ],
    arc,
    pool,
  )
  let section_target = @scheduler.AffectedVoiceTarget::from_section(
    main_section,
  )
  let first_occurrence_target = @scheduler.AffectedVoiceTarget::from_occurrence(
    first_occurrence,
  )
  let combined_target = @scheduler.AffectedVoiceTarget(
    pattern_node=None,
    section=Some(main_section),
    layer=None,
    occurrence=Some(first_occurrence),
  )
  assert_eq(sched.active_note_count(), 3)
  assert_eq(sched.affected_active_note_count(section_target), 2)
  assert_eq(sched.affected_active_note_count(first_occurrence_target), 1)
  assert_eq(sched.affected_active_note_count(combined_target), 1)
  assert_eq(
    sched.apply_affected_voice_policy(
      @scheduler.AffectedVoicePolicy::GateOffAffected,
      first_occurrence_target,
      pool,
    ),
    1,
  )
  assert_eq(sched.active_note_count(), 2)
  assert_eq(sched.affected_active_note_count(section_target), 1)
  assert_eq(
    sched.apply_affected_voice_policy(
      @scheduler.AffectedVoicePolicy::GateOffAffected,
      section_target,
      pool,
    ),
    1,
  )
  assert_eq(sched.active_note_count(), 1)
  assert_eq(
    sched.affected_active_note_count(
      @scheduler.AffectedVoiceTarget::from_section(other_section),
    ),
    1,
  )
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
test "process_snapshot_block: pending snapshot commits at block boundary" {
  let (pool, sched, left, right) = make_test_sched()
  sched.queue_pattern_snapshot(note_snapshot("snapshot_note", 60.0))
  assert_true(sched.has_pending_pattern_snapshot())
  assert_true(!sched.has_active_pattern_snapshot())
  assert_eq(pool.active_voice_count(), 0)
  sched.process_snapshot_block(pool, left, right)
  assert_true(!sched.has_pending_pattern_snapshot())
  assert_true(sched.has_active_pattern_snapshot())
  assert_eq(pool.active_voice_count(), 1)
  assert_eq(sched.active_note_count(), 1)
  assert_eq(sched.sample_counter(), 128L)
}

///|
test "process_snapshot_block: queued snapshot does not backfill past onsets" {
  let (pool, sched, left, right) = make_test_sched()
  sched.process_snapshot_block(pool, left, right)
  assert_eq(sched.sample_counter(), 128L)
  sched.queue_pattern_snapshot(note_snapshot("late_snapshot_note", 60.0))
  sched.process_snapshot_block(pool, left, right)
  assert_eq(pool.active_voice_count(), 0)
  assert_eq(sched.active_note_count(), 0)
  assert_eq(sched.sample_counter(), 256L)
}

///|
test "process_snapshot_block: silent edit lets active note ring" {
  let (pool, sched, left, right) = make_test_sched()
  sched.queue_pattern_snapshot(note_snapshot("ring_note", 60.0))
  sched.process_snapshot_block(pool, left, right)
  assert_eq(pool.active_voice_count(), 1)
  assert_eq(sched.active_note_count(), 1)
  sched.queue_pattern_snapshot(silence_snapshot("ring_silence"))
  sched.process_snapshot_block(pool, left, right)
  assert_eq(pool.active_voice_count(), 1)
  assert_eq(sched.active_note_count(), 1)
}

///|
test "process_snapshot_block: multiple pending snapshots keep the latest" {
  let (pool, sched, left, right) = make_test_sched()
  sched.queue_pattern_snapshot(note_snapshot("coalesced_note", 60.0))
  sched.queue_pattern_snapshot(silence_snapshot("coalesced_silence"))
  sched.process_snapshot_block(pool, left, right)
  assert_eq(pool.active_voice_count(), 0)
  assert_eq(sched.active_note_count(), 0)
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
  assert_true(
    sched.active_song_layout_revision() == Some(doc.layout_revision()),
  )
  assert_eq(pool.active_voice_count(), 1)
  assert_eq(sched.active_note_count(), 1)
  match sched.active_note_source(0) {
    Some(source) => assert_true(source.is_empty())
    None => assert_true(false)
  }
  assert_eq(sched.sample_counter(), 128L)
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
  let edited_section_result = try? section.replace_layer_body(
    layer_id,
    body=@pattern.note(62.0),
  )
  let edited_section = match edited_section_result {
    Ok(section) => section
    Err(_) => abort("expected section body edit")
  }
  let edited_result = try? doc.replace_occurrence_section(
    main_id,
    section=edited_section,
  )
  let edited = match edited_result {
    Ok(doc) => doc
    Err(_) => abort("expected song body edit")
  }
  assert_true(edited.revision() != doc.revision())
  assert_true(edited.layout_revision() == doc.layout_revision())
  sched.queue_song_snapshot(song_snapshot(edited))
  sched.process_song_snapshot_block(pool, left, right)
  assert_true(sched.active_song_revision() == Some(edited.revision()))
  assert_true(
    sched.active_song_layout_revision() == Some(doc.layout_revision()),
  )
  assert_eq(sched.sample_counter(), 256L)
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
  assert_eq(pool.active_voice_count(), 0)
  let edited_result = try? doc.set_occurrence_start(
    main_id,
    start=@pattern.Rational::from_int(0),
  )
  let edited = match edited_result {
    Ok(doc) => doc
    Err(_) => abort("expected layout edit")
  }
  assert_true(edited.layout_revision() != doc.layout_revision())
  sched.queue_song_snapshot(song_snapshot(edited))
  sched.process_song_snapshot_block(pool, left, right)
  assert_true(
    sched.active_song_layout_revision() == Some(edited.layout_revision()),
  )
  assert_eq(pool.active_voice_count(), 0)
  assert_eq(sched.active_note_count(), 0)
  assert_eq(sched.sample_counter(), 256L)
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
  assert_eq(pool.active_voice_count(), 1)
  assert_eq(sched.active_note_count(), 1)
  let edited_result = try? doc.set_occurrence_start(
    main_id,
    start=@pattern.Rational::from_int(2),
  )
  let edited = match edited_result {
    Ok(doc) => doc
    Err(_) => abort("expected layout edit")
  }
  sched.queue_song_snapshot(song_snapshot(edited))
  sched.process_song_snapshot_block(pool, left, right)
  assert_true(
    sched.active_song_layout_revision() == Some(edited.layout_revision()),
  )
  assert_eq(pool.active_voice_count(), 1)
  assert_eq(sched.active_note_count(), 1)
}

///|
test "process_song_snapshot_block: multiple pending song snapshots keep the latest" {
  let (pool, sched, left, right) = make_test_sched()
  let main_id = oid("song-snapshot:coalesced")
  let section = scheduler_section_doc("section:coalesced", "Main", 60.0)
  let first = scheduler_song_doc([
    @song.SongOccurrenceDoc(id=main_id, name="Main", section~),
  ])
  let latest_result = try? first.set_occurrence_start(
    main_id,
    start=@pattern.Rational::from_int(2),
  )
  let latest = match latest_result {
    Ok(doc) => doc
    Err(_) => abort("expected layout edit")
  }
  sched.queue_song_snapshot(song_snapshot(first))
  sched.queue_song_snapshot(song_snapshot(latest))
  sched.process_song_snapshot_block(pool, left, right)
  assert_true(!sched.has_pending_song_snapshot())
  assert_true(sched.has_active_song_snapshot())
  assert_true(
    sched.active_song_layout_revision() == Some(latest.layout_revision()),
  )
  assert_eq(pool.active_voice_count(), 0)
  assert_eq(sched.active_note_count(), 0)
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
  assert_eq(pool.active_voice_count(), 0)
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
