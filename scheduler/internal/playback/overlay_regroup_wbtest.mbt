///|
test "regrouping overlay keeps material clocks and publishes current provenance" {
  fn leaf(
    name : String,
    note : Int,
    period : Int,
  ) -> @pattern.PatternDoc[@pattern.ControlMap] raise {
    @pattern.PatternDoc::from_pattern(
      id=@identity.PatternNodeId::from_string(name),
      pat=material(name, note, period),
    )
  }
  let a = leaf("a", 60, 3)
  let b = leaf("b", 80, 4)
  let c = leaf("c", 100, 5)
  let old_root = @identity.PatternNodeId::from_string("old-layout")
  let new_root = @identity.PatternNodeId::from_string("new-layout")
  let before = @pattern.PatternDoc::stack(id=old_root, docs=[
    @pattern.PatternDoc::stack(
      id=@identity.PatternNodeId::from_string("old-group"),
      docs=[a, b],
    ),
    c,
  ]).lower()
  let after = @pattern.PatternDoc::stack(id=new_root, docs=[a, b, c]).lower()
  let control = PlaybackState()
  let edited = PlaybackState()
  for state in [control, edited] {
    state.queue(PlaybackSnapshot::pattern(before))
    state.commit_pending(@pattern.Rational::from_int(0))
  }
  edited.queue(PlaybackSnapshot::pattern(after))
  edited.commit_pending(@pattern.Rational::from_int(1))
  assert_false(edited.has_pending())
  assert_eq(notes(edited, 1, 8), notes(control, 1, 8))
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(1),
    @pattern.Rational::from_int(2),
  )
  let events = edited.query_active_sourced_events(arc)
  for event in events {
    assert_true(
      event
      .origin()
      .matches_pattern_scope(
        @model.PatternVoiceScope::PatternVoiceScope(new_root),
      ),
    )
    assert_false(
      event
      .origin()
      .matches_pattern_scope(
        @model.PatternVoiceScope::PatternVoiceScope(old_root),
      ),
    )
  }
}

///|
test "internal metadata changes do not reserve a material replacement" {
  let a = @pattern.note(60.0)
  let b = @pattern.note(64.0)
  let c = @pattern.note(67.0)
  let period = @pattern.Rational::from_int(3)
  let before = (a + b + c).material().slow(period).named_entry("track")
  let after = ((a + b).named_entry("phrase") +
    c +
    @pattern.Pat::silence().named_entry("rest"))
    .material()
    .slow(period)
    .named_entry("track")
  let control = PlaybackState()
  let edited = PlaybackState()
  for state in [control, edited] {
    accept(state, [before], 0)
  }
  accept(edited, [after], 1)
  assert_false(edited.has_pending())
  assert_eq(notes(edited, 1, 8), notes(control, 1, 8))
}
