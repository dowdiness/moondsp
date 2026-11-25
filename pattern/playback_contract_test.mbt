///|
test "document control merge preserves material clocks and broad voice scopes" {
  let bass = @pattern.control(Note, 60.0)
    .slow(@pattern.Rational::from_int(2))
    .material()
  let lead = @pattern.control(Note, 64.0)
    .fast(@pattern.Rational::from_int(2))
    .material()
  let source = @pattern.PatternDoc::stack(id=pid("parts"), docs=[
    @pattern.PatternDoc::from_pattern(id=pid("bass"), pat=bass),
    @pattern.PatternDoc::from_pattern(id=pid("lead"), pat=lead),
  ])
  let controls = @pattern.PatternDoc::control_atom(
    id=pid("gain"),
    key=Gain,
    value=0.0,
  )
  let snapshot = @pattern.PatternDoc::merge_control(
    id=pid("merge"),
    left=source,
    right=controls,
  ).lower_untracked()
  let arc = doc_span(1, 4, 3, 4)
  let expected = [
    (Some(doc_span(0, 1, 2, 1)), doc_span(1, 4, 3, 4), Some(60.0), Some(0.0)),
    (Some(doc_span(0, 1, 1, 2)), doc_span(1, 4, 1, 2), Some(64.0), Some(0.0)),
    (Some(doc_span(1, 2, 1, 1)), doc_span(1, 2, 3, 4), Some(64.0), Some(0.0)),
  ]
  @debug.assert_eq(
    snapshot
    .query(arc)
    .map(e => (e.whole, e.part, e.value.get(Note), e.value.get(Gain))),
    expected,
  )
  let scoped = snapshot.query_sourced_events(arc)
  @debug.assert_eq(
    scoped.map(e => {
      let event = e.event()
      (event.whole, event.part, event.value.get(Note), event.value.get(Gain))
    }),
    expected,
  )
  for event in scoped {
    assert_pattern_event_path(event, ["merge", "parts", "bass", "lead", "gain"])
  }
  let entries = snapshot.pat().entries()
  @debug.assert_eq(entries.map(p => p.entry_period()), [
    @pattern.Rational::from_int(2),
    @pattern.Rational(1L, 2L),
  ])
  let before = source.lower_untracked()
  @debug.assert_eq(
    snapshot.pat().entries()[0].entry_key(),
    before.pat().entries()[0].entry_key(),
  )
  @debug.assert_eq(
    snapshot.pat().entries()[1].entry_key(),
    before.pat().entries()[1].entry_key(),
  )
  assert_true(
    snapshot.pat().entries()[0].entry_key() !=
    snapshot.pat().entries()[1].entry_key(),
  )
  let raw = @pattern.stack([bass, lead]).entries()
  for i in 0..<entries.length() {
    @debug.assert_eq(
      snapshot
      .query_sourced_events_for_entry(i, arc)
      .map(e => e.event().value.get(Note)),
      raw[i].query(arc).map(e => e.value.get(Note)),
    )
  }
}

///|
test "document every preserves negative cycle selection and branch voice scopes" {
  let source = @pattern.PatternDoc::stack(id=pid("parts"), docs=[
    @pattern.PatternDoc::pure(id=pid("left"), value=n(1)),
    @pattern.PatternDoc::pure(id=pid("right"), value=n(2)),
  ])
  let snapshot = source
    .every(
      id=pid("every"),
      n=2,
      transform=@pattern.TimeTransform::Fast(@pattern.Rational::from_int(2)),
    )
    .lower_untracked()
  let events = snapshot.query_sourced_events(doc_span(-1, 1, 1, 1))
  @debug.assert_eq(events.map(e => e.event().value), [
    n(1),
    n(2),
    n(1),
    n(1),
    n(2),
    n(2),
  ])
  assert_pattern_event_path(events[0], ["every", "parts", "left"])
  assert_pattern_event_path(events[1], ["every", "parts", "right"])
  for i in 2..<events.length() {
    assert_pattern_event_path(events[i], ["every", "parts", "left", "right"])
  }
  @debug.assert_eq(snapshot.pat().entries().length(), 1)
  assert_false(snapshot.pat().same_content(snapshot.pat()))
}

///|
test "document jux preserves atomic material pan precedence and its content" {
  let source = @pattern.PatternDoc::stack(id=pid("parts"), docs=[
    @pattern.PatternDoc::from_pattern(
      id=pid("left"),
      pat=@pattern.controls(
        @pattern.ControlMap::single(Note, 60.0).set(Pan, 0.25),
      ),
    ),
    @pattern.PatternDoc::from_pattern(
      id=pid("right"),
      pat=@pattern.control(Note, 64.0),
    ),
  ])
  let snapshot = source
    .jux(id=pid("jux"), transform=@pattern.TimeTransform::Reverse)
    .lower_untracked()
  let events = snapshot.query_sourced_events(doc_span(0, 1, 1, 1))
  @debug.assert_eq(
    events.map(e => (e.event().value.get(Note), e.event().value.get(Pan))),
    [
      (Some(60.0), Some(-1.0)),
      (Some(64.0), Some(-1.0)),
      (Some(60.0), Some(1.0)),
      (Some(64.0), Some(1.0)),
    ],
  )
  for event in events {
    assert_pattern_event_path(event, ["jux", "parts", "left", "right"])
  }
  @debug.assert_eq(snapshot.pat().entries().length(), 1)
  @debug.assert_eq(
    snapshot.pat().entry_period(),
    @pattern.Rational::from_int(1),
  )
  // The typed transform is part of the content, so a different one differs.
  fn jux_with(transform) raise {
    source.jux(id=pid("jux"), transform~).lower_untracked().pat()
  }

  assert_true(snapshot.pat().same_content(jux_with(Reverse)))
  assert_false(
    snapshot.pat().same_content(jux_with(Fast(@pattern.Rational::from_int(2)))),
  )
}
