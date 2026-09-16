///|
fn material(
  name : String,
  note : Int,
  period : Int,
) -> @pattern.Pat[@pattern.ControlMap] {
  @pattern.sequence([
    @pattern.note(note.to_double()),
    @pattern.note((note + 1).to_double()),
  ])
  .slow(@pattern.Rational::from_int(period))
  .material()
  .named_entry(name)
}

///|
fn score(
  parts : Array[@pattern.Pat[@pattern.ControlMap]],
) -> PlaybackSnapshot raise {
  PlaybackSnapshot::pattern(
    @pattern.PatternDoc::from_pattern(
      id=@identity.PatternNodeId::from_string("test"),
      pat=@pattern.stack(parts),
    ).lower(),
  )
}

///|
fn accept(
  state : PlaybackState,
  parts : Array[@pattern.Pat[@pattern.ControlMap]],
  at : Int,
) -> Unit raise {
  state.queue(score(parts))
  state.commit_pending(@pattern.Rational::from_int(at))
}

///|
fn notes(state : PlaybackState, begin : Int, end_ : Int) -> Array[Int] raise {
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(begin),
    @pattern.Rational::from_int(end_),
  )
  let raw = state.query_active_events(arc)
  let sourced = state.query_active_sourced_events(arc)
  assert_eq(raw.length(), sourced.length())
  for i, event in raw {
    let actual = sourced[i].event()
    assert_true(event.whole == actual.whole)
    assert_true(event.part == actual.part)
    assert_true(event.value.entries() == actual.value.entries())
  }
  let events = raw.filter(e => e.whole is Some(w) && arc.contains(w.begin))
  events.sort_by((a, b) => {
    a.whole.unwrap().begin.compare(b.whole.unwrap().begin)
  })
  events.map(e => e.value.get("note").unwrap().to_int())
}

///|
test "independent entries preserve the rest of each playing phrase" {
  let state = PlaybackState()
  accept(state, [material("three", 60, 3), material("four", 80, 4)], 0)
  accept(state, [material("three", 70, 3), material("four", 90, 4)], 1)
  assert_eq(notes(state, 1, 5), [61, 81, 70, 90, 71])
  assert_true(state.has_pending())
  state.commit_pending(@pattern.Rational::from_int(5))
  assert_false(state.has_pending())
}

///|
test "new content replaces a reservation without postponing its boundary" {
  let state = PlaybackState()
  accept(state, [material("a", 60, 3)], 0)
  accept(state, [material("a", 70, 3)], 1)
  accept(state, [material("a", 80, 3)], 2)
  assert_eq(notes(state, 2, 4), [80])
  // An available boundary exactly at admission is eligible.
  accept(state, [material("a", 90, 3)], 3)
  assert_eq(notes(state, 3, 4), [90])
}

///|
test "period edits start the new cycle at the reserved old entry" {
  let state = PlaybackState()
  accept(state, [material("a", 60, 3)], 0)
  accept(state, [material("a", 70, 4)], 1)
  assert_eq(notes(state, 1, 8), [61, 70, 71, 70])
  state.commit_pending(@pattern.Rational::from_int(4))
  assert_eq(notes(state, 4, 8), [71, 70])
}

///|
test "reordering named entries preserves pending targets and deletion finishes the interval" {
  let state = PlaybackState()
  accept(state, [material("a", 60, 3), material("b", 80, 4)], 0)
  accept(state, [material("b", 80, 4), material("a", 70, 3)], 1)
  accept(state, [material("b", 80, 4)], 2)
  assert_eq(notes(state, 2, 5), [81, 80])
  state.commit_pending(@pattern.Rational::from_int(4))
  assert_eq(notes(state, 4, 5), [80])
  assert_false(state.has_pending())
}

///|
test "finite phrase keeps its current content until a new playback" {
  fn finite(note : Int) -> PlaybackSnapshot raise {
    let section = @song.SectionDoc::single(
      id=@identity.SectionId::from_string("section"),
      name="once",
      length_cycles=@pattern.Rational::from_int(2),
      scope=@song.TimeScope::identity(),
      layer_id=@identity.SectionLayerId::from_string("body"),
      body=material("a", note, 3),
    )
    PlaybackSnapshot::song(
      @song.SongDoc(parts=[
        @song.SongOccurrenceDoc::at(
          id=@identity.OccurrenceId::from_string("once"),
          start=@pattern.Rational::from_int(0),
          name="once",
          section~,
        ),
      ]).lower(),
    )
  }
  let state = PlaybackState()
  state.queue(finite(60))
  state.commit_pending(@pattern.Rational::from_int(0))
  state.queue(finite(70))
  state.commit_pending(@pattern.Rational::from_int(1))
  assert_eq(notes(state, 1, 3), [61])
  state.reset()
  state.queue(finite(70))
  state.commit_pending(@pattern.Rational::from_int(0))
  assert_eq(notes(state, 0, 2), [70, 71])
}

///|
test "settling after an old finite end retains its already entered replacement" {
  fn finite(note : Int, length : Int) -> PlaybackSnapshot raise {
    let section = @song.SectionDoc::single(
      id=@identity.SectionId::from_string("section"),
      name="phrase",
      length_cycles=@pattern.Rational::from_int(length),
      scope=@song.TimeScope::identity(),
      layer_id=@identity.SectionLayerId::from_string("body"),
      body=material("a", note, 3),
    )
    PlaybackSnapshot::song(
      @song.SongDoc(parts=[
        @song.SongOccurrenceDoc::at(
          id=@identity.OccurrenceId::from_string("once"),
          start=@pattern.Rational::from_int(0),
          name="phrase",
          section~,
        ),
      ]).lower(),
    )
  }
  let state = PlaybackState()
  state.queue(finite(60, 5))
  state.commit_pending(@pattern.Rational::from_int(0))
  state.queue(finite(70, 10))
  state.commit_pending(@pattern.Rational::from_int(1))
  assert_eq(notes(state, 1, 6), [61, 70, 71])
  state.commit_pending(@pattern.Rational::from_int(6))
  assert_eq(notes(state, 6, 8), [70, 71])
}

///|
test "reverting cancels a reservation while a new material waits for its entry" {
  let state = PlaybackState()
  accept(state, [material("a", 60, 3)], 0)
  accept(state, [material("a", 70, 3)], 1)
  accept(state, [material("a", 60, 3), material("b", 80, 4)], 2)
  assert_eq(state.skipped_entry_count(), 0)
  assert_true(state.has_pending())
  assert_eq(notes(state, 2, 5), [60, 80, 61])
  state.commit_pending(@pattern.Rational::from_int(5))
  assert_false(state.has_pending())
}

///|
test "content edits preserve the cycle count used by variation" {
  fn varying(note : Int) -> @pattern.Pat[@pattern.ControlMap] {
    @pattern.every(2, p => p.rev(), material("a", note, 3))
  }
  let state = PlaybackState()
  accept(state, [varying(60)], 0)
  accept(state, [varying(70)], 1)
  // Cycle 3 is odd. Restarting the source clock here would incorrectly select
  // the reversed cycle-zero variation, starting with note 71.
  assert_eq(notes(state, 3, 4), [70])
  let added = PlaybackState()
  accept(added, [], 0)
  accept(added, [varying(70)], 1)
  assert_eq(notes(added, 3, 4), [70])
}

///|
test "combined custom content without signatures is conservatively replaced" {
  fn combined(note : Int) -> @pattern.Pat[@pattern.ControlMap] {
    @pattern.stack([
      @pattern.note(note.to_double()),
      @pattern.note((note + 1).to_double()),
    ])
    .jux(p => p.rev())
    .named_entry("a")
  }
  let state = PlaybackState()
  accept(state, [combined(60)], 0)
  accept(state, [combined(70)], 1)
  assert_eq(notes(state, 1, 2), [70, 71, 70, 71])
}

///|
test "pending additions retain valid boundaries and cancel immediately" {
  let replaced = PlaybackState()
  accept(replaced, [], 0)
  accept(replaced, [material("a", 60, 3)], 1)
  accept(replaced, [material("a", 70, 4)], 2)
  assert_eq(notes(replaced, 2, 8), [70, 71, 70])
  replaced.commit_pending(@pattern.Rational::from_int(3))
  assert_eq(notes(replaced, 3, 8), [70, 71, 70])
  assert_false(replaced.has_pending())
  let cancelled = PlaybackState()
  accept(cancelled, [], 0)
  accept(cancelled, [material("a", 60, 3)], 1)
  accept(cancelled, [], 2)
  assert_eq(notes(cancelled, 2, 5), [])
  assert_false(cancelled.has_pending())
  cancelled.commit_pending(@pattern.Rational::from_int(3))
  assert_eq(notes(cancelled, 3, 5), [])
  assert_false(cancelled.has_pending())
}

///|
test "silence cancels a waiting addition without starting its old material" {
  let state = PlaybackState()
  accept(state, [], 0)
  accept(state, [material("a", 60, 3)], 1)
  let silence : @pattern.Pat[@pattern.ControlMap] = @pattern.Pat::silence()
    .slow(@pattern.Rational::from_int(3))
    .named_entry("a")
  accept(state, [silence], 2)
  assert_false(state.has_pending())
  assert_eq(notes(state, 2, 5), [])
  accept(state, [material("a", 70, 3)], 2)
  assert_eq(notes(state, 2, 5), [70, 71])
}

///|
fn finite_occurrence_score(lead_start : Int?) -> PlaybackSnapshot raise {
  let base = @song.SectionDoc::single(
    id=@identity.SectionId::from_string("base-section"),
    name="base",
    length_cycles=@pattern.Rational::from_int(8),
    scope=@song.TimeScope::identity(),
    layer_id=@identity.SectionLayerId::from_string("base-layer"),
    body=material("base", 40, 1),
  )
  let parts = [
    @song.SongOccurrenceDoc::at(
      id=@identity.OccurrenceId::from_string("base-occurrence"),
      start=@pattern.Rational::from_int(0),
      name="base",
      section=base,
    ),
  ]
  if lead_start is Some(start) {
    let lead = @song.SectionDoc::single(
      id=@identity.SectionId::from_string("lead-section"),
      name="lead",
      length_cycles=@pattern.Rational::from_int(8 - start),
      scope=@song.TimeScope::identity(),
      layer_id=@identity.SectionLayerId::from_string("lead-layer"),
      body=material("lead", 80, 1),
    )
    parts.push(
      @song.SongOccurrenceDoc::at(
        id=@identity.OccurrenceId::from_string("lead-occurrence"),
        start=@pattern.Rational::from_int(start),
        name="lead",
        section=lead,
      ),
    )
  }
  PlaybackSnapshot::song(@song.SongDoc(parts~).lower())
}

///|
test "finite occurrence added midway is skipped until a new Play" {
  let state = PlaybackState()
  state.queue(finite_occurrence_score(None))
  state.commit_pending(@pattern.Rational::from_int(0))
  state.queue(finite_occurrence_score(Some(2)))
  state.commit_pending(@pattern.Rational::from_int(3))

  assert_eq(state.skipped_entry_count(), 1)
  assert_false(state.has_pending())
  assert_false(notes(state, 3, 6).any(note => note == 80 || note == 81))
  state.commit_pending(@pattern.Rational::from_int(5))
  assert_eq(state.skipped_entry_count(), 1)
  assert_false(notes(state, 5, 6).any(note => note == 80 || note == 81))

  state.reset()
  state.queue(finite_occurrence_score(Some(2)))
  state.commit_pending(@pattern.Rational::from_int(0))
  assert_eq(state.skipped_entry_count(), 0)
  assert_true(notes(state, 2, 3).any(note => note == 80 || note == 81))
}

///|
test "moving a waiting finite occurrence invalidates its reserved entry" {
  let state = PlaybackState()
  state.queue(finite_occurrence_score(None))
  state.commit_pending(@pattern.Rational::from_int(0))
  state.queue(finite_occurrence_score(Some(6)))
  state.commit_pending(@pattern.Rational::from_int(3))
  assert_true(state.has_pending())

  state.queue(finite_occurrence_score(Some(2)))
  state.commit_pending(@pattern.Rational::from_int(4))
  assert_false(state.has_pending())
  assert_eq(state.skipped_entry_count(), 1)
  assert_false(notes(state, 6, 8).any(note => note == 80 || note == 81))
}

///|
fn finite_single_score(start : Int, note : Int) -> PlaybackSnapshot raise {
  let section = @song.SectionDoc::single(
    id=@identity.SectionId::from_string("moving-section"),
    name="moving",
    length_cycles=@pattern.Rational::from_int(8 - start),
    scope=@song.TimeScope::identity(),
    layer_id=@identity.SectionLayerId::from_string("moving-layer"),
    body=material("moving", note, 3),
  )
  PlaybackSnapshot::song(
    @song.SongDoc(parts=[
      @song.SongOccurrenceDoc::at(
        id=@identity.OccurrenceId::from_string("moving-occurrence"),
        start=@pattern.Rational::from_int(start),
        name="moving",
        section~,
      ),
    ]).lower(),
  )
}

///|
test "moving current material finishes old content and skips incoming occurrence" {
  let state = PlaybackState()
  state.queue(finite_single_score(0, 60))
  state.commit_pending(@pattern.Rational::from_int(0))
  state.queue(finite_single_score(2, 80))
  state.commit_pending(@pattern.Rational::from_int(4))

  assert_true(state.has_pending())
  assert_eq(state.skipped_entry_count(), 1)
  assert_false(notes(state, 4, 6).any(note => note == 80 || note == 81))

  state.commit_pending(@pattern.Rational::from_int(6))
  assert_false(state.has_pending())
  assert_eq(state.skipped_entry_count(), 1)
  assert_false(notes(state, 6, 8).any(note => note == 80 || note == 81))
}

///|
fn repeated(snapshot : PlaybackSnapshot) -> PlaybackSnapshot {
  match snapshot {
    Song(song) => PlaybackSnapshot::repeat_song(song)
    other => other
  }
}

///|
test "repeating updates preserve old phrase and rebuild within a queried block" {
  let state = PlaybackState()
  state.queue(repeated(finite_single_score(0, 60)))
  state.commit_pending(@pattern.Rational::from_int(0))
  state.queue(repeated(finite_single_score(0, 70)))
  state.commit_pending(@pattern.Rational::from_int(1))
  assert_eq(notes(state, 1, 10), [61, 70, 71, 70, 71, 70, 71])
  state.commit_pending(@pattern.Rational::from_int(9))
  assert_eq(notes(state, 9, 12), [71, 70])
  assert_false(state.has_pending())
}

///|
test "skipped occurrence enters next repetition including a boundary-crossing query" {
  let state = PlaybackState()
  state.queue(repeated(finite_occurrence_score(None)))
  state.commit_pending(@pattern.Rational::from_int(0))
  state.queue(repeated(finite_occurrence_score(Some(2))))
  state.commit_pending(@pattern.Rational::from_int(3))
  assert_eq(state.skipped_entry_count(), 1)
  assert_false(notes(state, 3, 8).any(note => note == 80 || note == 81))
  assert_true(notes(state, 7, 11).any(note => note == 80))
  state.commit_pending(@pattern.Rational::from_int(9))
  assert_eq(state.skipped_entry_count(), 0)
  assert_true(notes(state, 10, 11).any(note => note == 80))
}

///|
test "another update cannot drop material awaiting removal" {
  let state = PlaybackState()
  accept(state, [material("a", 60, 4)], 0)
  accept(state, [], 1)
  accept(state, [], 2)
  assert_eq(notes(state, 2, 5), [61])
  accept(state, [material("a", 60, 4)], 3)
  assert_false(state.has_pending())
  assert_eq(notes(state, 4, 5), [60])
}

///|
test "retained entry budget preserves music and recovers at removal boundaries" {
  let state = PlaybackState()
  accept(state, [material("a", 60, 1000), material("b", 80, 1000)], 0)
  let next = score([material("c", 90, 1000)])
  assert_true(
    state.prepare_acceptance(
      next,
      @pattern.Rational::from_int(1),
      material_limit=2,
      restart=false,
    )
    is None,
  )
  assert_eq(notes(state, 0, 1000), [60, 80, 61, 81])
  assert_false(state.has_pending())
  let removing = state
    .prepare_acceptance(
      score([]),
      @pattern.Rational::from_int(1),
      material_limit=2,
      restart=false,
    )
    .unwrap()
  state.install_acceptance(removing)
  assert_true(state.has_pending())
  assert_eq(notes(state, 1, 1000), [61, 81])
  let recovered = state
    .prepare_acceptance(
      next,
      @pattern.Rational::from_int(1000),
      material_limit=2,
      restart=false,
    )
    .unwrap()
  state.install_acceptance(recovered)
  assert_eq(notes(state, 1000, 1001), [90])
  assert_false(state.has_pending())
}
