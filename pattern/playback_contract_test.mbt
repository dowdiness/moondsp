///|
test "document control merge preserves material clocks and broad voice scopes" {
  let bass = note(60.0)
    .slow(Rational::from_int(2))
    .material()
    .named_entry("bass")
  let lead = note(64.0)
    .fast(Rational::from_int(2))
    .material()
    .named_entry("lead")
  let source = PatternDoc::stack(id=pid("parts"), docs=[
    PatternDoc::from_pattern(id=pid("bass"), pat=bass),
    PatternDoc::from_pattern(id=pid("lead"), pat=lead),
  ])
  let controls = PatternDoc::from_pattern(id=pid("gain"), pat=s_gain(0.0))
  let snapshot = PatternDoc::merge_control(
    id=pid("merge"),
    left=source,
    right=controls,
  ).lower()
  let arc = doc_span(1, 4, 3, 4)
  let expected = [
    (Some(doc_span(0, 1, 2, 1)), doc_span(1, 4, 3, 4), Some(60.0), Some(0.0)),
    (Some(doc_span(0, 1, 1, 2)), doc_span(1, 4, 1, 2), Some(64.0), Some(0.0)),
    (Some(doc_span(1, 2, 1, 1)), doc_span(1, 2, 3, 4), Some(64.0), Some(0.0)),
  ]
  @debug.assert_eq(
    snapshot
    .query(arc)
    .map(e => (e.whole, e.part, e.value.get("note"), e.value.get("gain"))),
    expected,
  )
  let scoped = snapshot.query_sourced_events(arc)
  @debug.assert_eq(
    scoped.map(e => {
      let event = e.event()
      (
        event.whole,
        event.part,
        event.value.get("note"),
        event.value.get("gain"),
      )
    }),
    expected,
  )
  for event in scoped {
    assert_pattern_event_path(event, ["merge", "parts", "bass", "lead", "gain"])
  }
  let entries = snapshot.pat().entries()
  @debug.assert_eq(entries.map(p => p.entry_period()), [
    Rational::from_int(2),
    Rational::new(1L, 2L),
  ])
  let before = source.lower()
  @debug.assert_eq(snapshot.entry_key(0), before.entry_key(0))
  @debug.assert_eq(snapshot.entry_key(1), before.entry_key(1))
  assert_true(snapshot.entry_key(0) != snapshot.entry_key(1))
  let raw = merge_control(stack([bass, lead]), s_gain(0.0)).entries()
  for i in 0..<entries.length() {
    assert_true(entries[i].same_content(raw[i]))
    @debug.assert_eq(
      snapshot
      .query_sourced_events_for_entry(i, arc)
      .map(e => e.event().value.get("note")),
      raw[i].query(arc).map(e => e.value.get("note")),
    )
  }
}

///|
test "document every preserves negative cycle selection and branch voice scopes" {
  let source = PatternDoc::stack(id=pid("parts"), docs=[
    PatternDoc::pure(id=pid("left"), value=1),
    PatternDoc::pure(id=pid("right"), value=2),
  ])
  let snapshot = source
    .every(
      id=pid("every"),
      n=2,
      transform=TimeTransform::Fast(Rational::from_int(2)),
    )
    .lower()
  let events = snapshot.query_sourced_events(doc_span(-1, 1, 1, 1))
  @debug.assert_eq(events.map(e => e.event().value), [1, 2, 1, 1, 2, 2])
  assert_pattern_event_path(events[0], ["every", "parts", "left"])
  assert_pattern_event_path(events[1], ["every", "parts", "right"])
  for i in 2..<events.length() {
    assert_pattern_event_path(events[i], ["every", "parts", "left", "right"])
  }
  @debug.assert_eq(snapshot.pat().entries().length(), 1)
  assert_false(snapshot.pat().same_content(snapshot.pat()))
}

///|
test "document jux preserves atomic material pan precedence and unknown content" {
  let source = PatternDoc::stack(id=pid("parts"), docs=[
    PatternDoc::from_pattern(
      id=pid("left"),
      pat=merge_control(note(60.0), s_pan(0.25)),
    ),
    PatternDoc::from_pattern(id=pid("right"), pat=note(64.0)),
  ])
  let snapshot = source
    .jux(id=pid("jux"), transform=TimeTransform::Reverse)
    .lower()
  let events = snapshot.query_sourced_events(doc_span(0, 1, 1, 1))
  @debug.assert_eq(
    events.map(e => (e.event().value.get("note"), e.event().value.get("pan"))),
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
  @debug.assert_eq(snapshot.pat().entry_period(), Rational::from_int(1))
  assert_false(snapshot.pat().same_content(snapshot.pat()))
}
