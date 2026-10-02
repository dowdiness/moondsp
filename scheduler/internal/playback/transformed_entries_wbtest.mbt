///|
test "public transformations of identified material reach playback" {
  let source = @pattern.sequence([@pattern.note(60.0), @pattern.note(72.0)]).material()
  let cases = [
    (source.filter_map(_ => None), []),
    (@pattern.merge_control(source, @pattern.note(80.0)), [80, 80]),
    (
      @pattern.merge_control(
        source,
        @pattern.Pat::from_query(@pattern.note(80.0).query),
      ),
      [80, 80],
    ),
    (source.rev(), [72, 60]),
    (source.degrade_by(1.0), []),
    (@pattern.every(1, p => p.rev(), source), [72, 60]),
    (source.jux(p => p.rev()), [60, 72, 72, 60]),
  ]
  for case in cases {
    let (changed, expected) = case
    let state = PlaybackState()
    accept(state, [source], 0)
    accept(state, [changed], 1)
    assert_eq(notes(state, 1, 2), expected)
  }
}

///|
test "authored Euclid preserves stacked notes timing and child provenance" {
  let left = @identity.PatternNodeId::from_string("left")
  let right = @identity.PatternNodeId::from_string("right")
  let pair = @identity.PatternNodeId::from_string("pair")
  let euclid = @identity.PatternNodeId::from_string("euclid")
  let snapshot = @pattern.PatternDoc::stack(id=pair, docs=[
      @pattern.PatternDoc::from_pattern(id=left, pat=@pattern.note(60.0)),
      @pattern.PatternDoc::from_pattern(id=right, pat=@pattern.note(67.0)),
    ])
    .euclid(id=euclid, k=1, n=2)
    .lower()
  let state = PlaybackState()
  state.queue(PlaybackSnapshot::pattern(snapshot))
  state.commit_pending(@pattern.Rational::from_int(0))
  let whole = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::new(1L, 2L),
  )
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let events = state.query_active_sourced_events(arc)
  assert_eq(
    events.map(event => event.event().value.get("note").unwrap().to_int()),
    [60, 67],
  )
  let children = [left, right]
  for i, sourced in events {
    let event = sourced.event()
    assert_true(event.whole == Some(whole))
    assert_true(event.part == whole)
    guard sourced.origin() is @model.VoiceOrigin::Pattern(path) else {
      fail("authored Euclid event lost its pattern origin")
    }
    assert_true(path.nodes() == [euclid, pair, children[i]])
  }
  let clipped = state.query_active_sourced_events(
    @pattern.TimeSpan::new(
      @pattern.Rational::new(1L, 4L),
      @pattern.Rational::new(3L, 4L),
    ),
  )
  assert_eq(
    clipped.map(event => event.event().value.get("note").unwrap().to_int()),
    [60, 67],
  )
  for sourced in clipped {
    assert_true(sourced.event().whole == Some(whole))
    assert_true(
      sourced.event().part ==
      @pattern.TimeSpan::new(
        @pattern.Rational::new(1L, 4L),
        @pattern.Rational::new(1L, 2L),
      ),
    )
  }
}

///|
test "direct pitch edits wait for the next material entry" {
  let phrase = @pattern.sequence([@pattern.note(60.0), @pattern.note(60.0)])
    .slow(@pattern.Rational::from_int(4))
    .material()
    .named_entry("phrase")
  let scale = [0, 2, 4, 5, 7, 9, 11]
  let edits = [
    (phrase.transpose(2), phrase.transpose(4), 62, 64),
    (phrase.steps(scale, 1), phrase.steps(scale, 2), 62, 64),
    (phrase.steps(scale, 1), phrase.steps([0, 3, 5, 7, 10], 1), 62, 63),
  ]
  for (before, after, old_note, new_note) in edits {
    let state = PlaybackState()
    accept(state, [before], 0)
    accept(state, [after], 1)
    assert_true(state.has_pending())
    assert_eq(notes(state, 2, 3), [old_note])
    state.commit_pending(@pattern.Rational::from_int(4))
    assert_eq(notes(state, 4, 5), [new_note])
  }
}

///|
test "authored pitch edits wait for the next material entry" {
  let phrase = @pattern.PatternDoc::from_pattern(
    id=@identity.PatternNodeId::from_string("phrase"),
    pat=@pattern.sequence([@pattern.note(60.0), @pattern.note(60.0)]).slow(
      @pattern.Rational::from_int(4),
    ),
  )
  let id = @identity.PatternNodeId::from_string("pitch")
  let operations = [
    (
      @pattern.CompositionOp::Transpose(2),
      @pattern.CompositionOp::Transpose(4),
      62,
      64,
    ),
    (
      @pattern.CompositionOp::Steps([0, 2, 4, 5, 7, 9, 11], 1),
      @pattern.CompositionOp::Steps([0, 2, 4, 5, 7, 9, 11], 2),
      62,
      64,
    ),
  ]
  for (old_op, new_op, old_note, new_note) in operations {
    let state = PlaybackState()
    state.queue(
      PlaybackSnapshot::pattern(phrase.compose(id~, operation=old_op).lower()),
    )
    state.commit_pending(@pattern.Rational::from_int(0))
    state.queue(
      PlaybackSnapshot::pattern(phrase.compose(id~, operation=new_op).lower()),
    )
    state.commit_pending(@pattern.Rational::from_int(1))
    assert_true(state.has_pending())
    assert_eq(notes(state, 2, 3), [old_note])
    state.commit_pending(@pattern.Rational::from_int(4))
    assert_eq(notes(state, 4, 5), [new_note])
  }
}
