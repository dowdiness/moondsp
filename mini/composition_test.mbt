///|
fn composition_test_events(
  source : String,
  end_cycles? : Int = 4,
) -> Array[@pattern.Event[@pattern.ControlMap]] raise {
  let pat = match @mini.parse(source) {
    Ok(value) => value
    Err(message) => fail(message)
  }
  pat.query(
    @pattern.TimeSpan::new(
      @pattern.Rational::from_int(0),
      @pattern.Rational::from_int(end_cycles),
    ),
  )
}

///|
fn composition_test_notes(
  events : Array[@pattern.Event[@pattern.ControlMap]],
) -> Array[Double] {
  events.filter_map(event => event.value.get("note"))
}

///|
fn composition_test_signatures(
  events : Array[@pattern.Event[@pattern.ControlMap]],
) -> Array[(@pattern.TimeSpan?, @pattern.TimeSpan, Map[String, Double])] {
  events.map(event => (event.whole, event.part, event.value.entries()))
}

///|
test "shared chord progression supports lowest tones voicings and onset masks" {
  let source = "let changes = chord(\"C G Am F\").slow(4); " +
    "stack(changes.lowest(), changes.voicing(48, 79).mask(\"x ~ x x\"))"
  let events = composition_test_events(source)
  let notes = composition_test_notes(events)
  assert_true(notes.contains(60.0))
  assert_true(notes.contains(67.0))
  assert_true(notes.contains(69.0))
  assert_true(notes.contains(65.0))
  assert_false(notes.contains(71.0))
}

///|
test "Mini voicing omission retains four chord tones" {
  assert_eq(
    composition_test_notes(
      composition_test_events("chord(\"G7\").voicing(48, 79)", end_cycles=1),
    ),
    [67.0, 71.0, 74.0, 77.0],
  )
  assert_eq(
    composition_test_notes(
      composition_test_events("chord(\"G7\").voicing(48, 79, 3)", end_cycles=1),
    ),
    [67.0, 71.0, 74.0],
  )
}

///|
test "Mini motif transpose and explicit scale-step transpose" {
  let semitones = composition_test_notes(
    composition_test_events("note(\"C4 E4 G4\").transpose(2)", end_cycles=1),
  )
  assert_eq(semitones, [62.0, 66.0, 69.0])
  let scale_steps = composition_test_notes(
    composition_test_events(
      "note(\"C4 E4 G4\").steps(\"C D E F G A B\", 1)",
      end_cycles=1,
    ),
  )
  assert_eq(scale_steps, [62.0, 65.0, 69.0])
}

///|
test "seeded Mini dropout is stable for repeated and split queries" {
  let pat = match @mini.parse("s(\"bd sd hh cp\").degradeBy(0.5, 119)") {
    Ok(value) => value
    Err(message) => fail(message)
  }
  let zero = @pattern.Rational::from_int(0)
  let half = @pattern.Rational::new(1L, 2L)
  let one = @pattern.Rational::from_int(1)
  let full = pat.query(@pattern.TimeSpan::new(zero, one))
  let split = []
  for event in pat.query(@pattern.TimeSpan::new(zero, half)) {
    split.push(event)
  }
  for event in pat.query(@pattern.TimeSpan::new(half, one)) {
    split.push(event)
  }
  assert_eq(
    composition_test_signatures(full),
    composition_test_signatures(pat.query(@pattern.TimeSpan::new(zero, one))),
  )
  assert_eq(
    composition_test_signatures(full),
    composition_test_signatures(split),
  )
}

///|
test "composition transforms are accepted by document parsing" {
  assert_true(
    @mini.parse_doc(
      "let changes = chord(\"C G\").slow(2); " +
      "stack(changes.lowest(), changes.voicing(48, 79, 3).mask(\"x ~\"))",
    )
    is Ok(_),
  )
}

///|
test "tail replaces only the chosen suffix and preserves the cycle span" {
  let pat = match @mini.parse("note(\"C4\").slow(4).tail(note(\"E4\"))") {
    Ok(value) => value
    Err(message) => fail(message)
  }
  let events = pat.query(
    @pattern.TimeSpan::new(
      @pattern.Rational::from_int(0),
      @pattern.Rational::from_int(4),
    ),
  )
  assert_eq(composition_test_notes(events), [60.0, 64.0])
  assert_eq(pat.entry_period(), @pattern.Rational::from_int(4))
  assert_true(@mini.parse_doc("silence().slow(4).tail(note(\"E4\"))") is Ok(_))
}

///|
test "phase transforms only its normalized progression interval" {
  let notes = composition_test_notes(
    composition_test_events(
      "chord(\"C G Am F\").slow(4).phase(transpose(2), 0.25, 0.75)",
    ),
  )
  assert_eq(notes, [
    60.0, 64.0, 67.0, 69.0, 73.0, 76.0, 71.0, 74.0, 78.0, 65.0, 69.0, 72.0,
  ])
  assert_true(
    @mini.parse_doc(
      "chord(\"C G Am F\").slow(4).phase(transpose(2), 0.25, 0.75)",
    )
    is Ok(_),
  )
}

///|
test "phase defaults to period end and tail rejects short default" {
  let notes = composition_test_notes(
    composition_test_events(
      "note(\"C4 E4 G4 A4\").phase(transpose(2), 0.5)",
      end_cycles=1,
    ),
  )
  assert_eq(notes, [60.0, 64.0, 69.0, 71.0])
  match @mini.parse("note(\"C4\").fast(2).tail(note(\"E4\"))") {
    Err(message) => assert_true(message.contains("specify a shorter duration"))
    Ok(_) => fail("tail should reject the one-cycle default")
  }
  match @mini.parse_doc("note(\"C4\").fast(2).tail(note(\"E4\"))") {
    Err(message) => assert_true(message.contains("specify a shorter duration"))
    Ok(_) => fail("document tail should reject the one-cycle default")
  }
  assert_eq(
    composition_test_notes(
      composition_test_events(
        "note(\"C4\").fast(2).tail(note(\"E4\"), 0.5)",
        end_cycles=1,
      ),
    ),
    [64.0, 64.0],
  )
}

///|
test "composition keeps authored origins for retained and replacement notes" {
  let draft = @mini.Draft::new(
    "let phrase = note(\"C4 E4 G4 A4\"); " +
    "phrase.steps(\"C D E F G A B\", 1).phase(transpose(2), 0.5).tail(note(\"C5\"), 0.25)",
  )
  let input = match draft.prepare_playback() {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  guard input.compile() is Ok(@mini.PreparedPlayback::Pattern(snapshot, _)) else {
    fail("expected exact authored composition")
  }
  let events = snapshot.query(
    @pattern.TimeSpan::new(
      @pattern.Rational::from_int(0),
      @pattern.Rational::from_int(1),
    ),
  )
  assert_eq(composition_test_notes(events.map(event => event.event())), [
    62.0, 65.0, 71.0, 72.0,
  ])
  assert_true(events[0].origin().atom() != events[1].origin().atom())
  assert_true(events[2].origin().atom() != events[3].origin().atom())
  assert_eq(events[0].origin().bindings().length(), 1)
  assert_true(draft.locate_origin(events[0].origin()) is Located(_, _))
  assert_true(draft.locate_origin(events[3].origin()) is Located(_, _))
  let edit = @mini.EditTransaction::EditTransaction(
    base=draft.state().version(),
    edits=[@mini.TextEdit::TextEdit(from=0, to=0, inserted="// offset\n")],
  )
  assert_true(draft.edit(edit) is Ok(_))
  guard draft.prepare_playback() is Ok(edited) else {
    fail("expected accepted offset edit")
  }
  guard edited.compile() is Ok(@mini.PreparedPlayback::Pattern(updated, _)) else {
    fail("expected exact offset edit")
  }
  let shifted = updated.query(
    @pattern.TimeSpan::new(
      @pattern.Rational::from_int(0),
      @pattern.Rational::from_int(1),
    ),
  )
  assert_eq(shifted[0].origin(), events[0].origin())
  assert_eq(shifted[3].origin(), events[3].origin())
}

///|
test "chord projections and masks keep the original chord atom" {
  let draft = @mini.Draft::new(
    "let changes = chord(\"C Am\"); " +
    "stack(changes.lowest().mask(\"x ~\"), changes.voicing(48, 79, 2))",
  )
  let input = match draft.prepare_playback() {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  guard input.compile() is Ok(@mini.PreparedPlayback::Pattern(snapshot, _)) else {
    fail("expected exact chord projection")
  }
  let events = snapshot.query(
    @pattern.TimeSpan::new(
      @pattern.Rational::from_int(0),
      @pattern.Rational::from_int(1),
    ),
  )
  assert_eq(composition_test_notes(events.map(event => event.event())), [
    60.0, 60.0, 64.0, 69.0, 72.0,
  ])
  assert_eq(events[0].origin().atom(), events[1].origin().atom())
  assert_true(events[0].origin().atom() != events[3].origin().atom())
  assert_true(
    events.all(event => draft.locate_origin(event.origin()) is Located(_, _)),
  )
}

///|
test "cross-layer pitch projections retain exactly the playback entries heard" {
  for
    source in [
      "stack(note(\"C4\"), note(\"E4\")).lowest()", "stack(note(\"C4\"), note(\"E4\")).voicing(48, 79, 1)",
    ] {
    let draft = @mini.Draft::new(source)
    let input = match draft.prepare_playback() {
      Ok(value) => value
      Err(error) => fail(error.message())
    }
    guard input.compile() is Ok(@mini.PreparedPlayback::Pattern(snapshot, _)) else {
      fail("expected a compiled stacked projection")
    }
    let arc = @pattern.TimeSpan::new(
      @pattern.Rational::from_int(0),
      @pattern.Rational::from_int(1),
    )
    let whole = snapshot.query(arc)
    assert_eq(composition_test_notes(whole.map(event => event.event())), [60.0])
    let playback = []
    for index = 0; snapshot.entry_key(index) is Some(_); index = index + 1 {
      playback.append(snapshot.query_for_entry(index, arc))
    }
    assert_eq(composition_test_notes(playback.map(event => event.event())), [
      60.0,
    ])
    assert_eq(playback[0].origin(), whole[0].origin())
  }
}
