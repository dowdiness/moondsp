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
  .material("\{note}")
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
fn notes(state : PlaybackState, begin : Int, end_ : Int) -> Array[Int] {
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(begin),
    @pattern.Rational::from_int(end_),
  )
  let events = state
    .query_active_events(arc)
    .filter(e => e.whole is Some(w) && arc.contains(w.begin))
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
  assert_eq(state.entries.length(), 1)
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
test "reverting cancels a reservation while a new material waits for its entry" {
  let state = PlaybackState()
  accept(state, [material("a", 60, 3)], 0)
  accept(state, [material("a", 70, 3)], 1)
  accept(state, [material("a", 60, 3), material("b", 80, 4)], 2)
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
