///|
test "notation projection ties repeated events to exact source atoms" {
  let output = @json.parse(project_notation("note", "[60 64]*2"))
  guard output is Object(fields) &&
    fields.get("error") == Some(Json::null()) &&
    fields.get("nodes") is Some(Array(nodes)) &&
    fields.get("events") is Some(Array(events)) &&
    fields.get("rests") is Some(Array(rests)) else {
    fail("expected successful source projection")
  }
  assert_true(rests.is_empty())
  assert_eq(events.length(), 4)
  let source_node = fn(index : Int) -> Json raise {
    guard events[index] is Object(event) && event.get("node") is Some(node) else {
      fail("projected event is missing its source atom")
    }
    node
  }
  assert_true(source_node(0) == source_node(2))
  assert_true(source_node(1) == source_node(3))
  assert_true(source_node(0) != source_node(1))
  guard events[0] is Object(first) &&
    first.get("start") == Some(Json::number(0.0)) &&
    first.get("end") == Some(Json::number(0.25)) &&
    first.get("pitch") == Some(Json::number(60.0)) &&
    events[1] is Object(second) &&
    second.get("start") == Some(Json::number(0.25)) &&
    second.get("end") == Some(Json::number(0.5)) &&
    second.get("pitch") == Some(Json::number(64.0)) else {
    fail("ordinary note events should preserve their compiled timing and pitch")
  }
  assert_true(nodes.length() >= 4)
}

///|
test "invalid notation projections return errors without fabricated events" {
  let output = @json.parse(project_notation("note", "60 ! 64"))
  guard output is Object(fields) &&
    fields.get("error") is Some(String(_)) &&
    fields.get("roots") is Some(Array(roots)) &&
    fields.get("nodes") is Some(Array(nodes)) &&
    fields.get("events") is Some(Array(events)) &&
    fields.get("rests") is Some(Array(rests)) &&
    fields.get("span") is Some(Number(span, ..)) else {
    fail("expected error projection shape")
  }
  assert_eq(roots.length(), 0)
  assert_true(events.is_empty())
  assert_true(rests.is_empty())
  assert_eq(nodes.length(), 0)
  assert_true(span == 1.0)
}

///|
test "weighted and nested repeated rests retain source identity and compiled time" {
  let weighted = @json.parse(project_notation("note", "60@2 ~@2 64"))
  guard weighted is Object(fields) &&
    fields.get("events") is Some(Array(events)) &&
    fields.get("rests") is Some(Array(rests)) &&
    fields.get("nodes") is Some(Array(nodes)) else {
    fail("expected weighted rest projection")
  }
  assert_eq(events.length(), 2)
  assert_eq(rests.length(), 1)
  guard rests[0] is Object(rest) &&
    rest.get("node") is Some(Number(node_index, ..)) &&
    rest.get("start") is Some(Number(start, ..)) &&
    rest.get("end") is Some(Number(end_, ..)) &&
    rest.get("pitch") == Some(Json::null()) else {
    fail("compiled rest occurrence should map to its rest atom with null pitch")
  }
  assert_true(start > 0.399 && start < 0.401)
  assert_true(end_ > 0.799 && end_ < 0.801)
  guard nodes[node_index.to_int()] is Object(rest_node) &&
    rest_node.get("kind") == Some("atom".to_json()) &&
    rest_node.get("value") == Some("~".to_json()) else {
    fail("rest occurrence must reference the original rest source atom")
  }
  let nested = @json.parse(project_notation("note", "[~@2 60]*2"))
  guard nested is Object(nested_fields) &&
    nested_fields.get("events") is Some(Array(nested_events)) &&
    nested_fields.get("rests") is Some(Array(nested_rests)) else {
    fail("expected nested repeated rest projection")
  }
  assert_eq(nested_events.length(), 2)
  assert_eq(nested_rests.length(), 2)
  guard nested_rests[0] is Object(first) &&
    first.get("node") is Some(first_node) &&
    first.get("start") is Some(Number(first_start, ..)) &&
    first.get("end") is Some(Number(first_end, ..)) &&
    nested_rests[1] is Object(second) &&
    second.get("node") is Some(second_node) &&
    second.get("start") is Some(Number(second_start, ..)) &&
    second.get("end") is Some(Number(second_end, ..)) else {
    fail("nested repeat rest occurrence is missing its exact timing or source")
  }
  assert_true(first_node == second_node)
  assert_true(first_start == 0.0 && second_start == 0.5)
  assert_true(first_end > 0.333 && first_end < 0.334)
  assert_true(second_end > 0.833 && second_end < 0.834)
}

///|
test "all-rest phrase projects usable timed occurrences" {
  let output = @json.parse(project_notation("note", "~@2 ~"))
  guard output is Object(fields) &&
    fields.get("events") is Some(Array(events)) &&
    fields.get("rests") is Some(Array(rests)) &&
    fields.get("nodes") is Some(Array(nodes)) else {
    fail("expected all-rest projection")
  }
  assert_true(events.is_empty())
  assert_eq(rests.length(), 2)
  guard rests[0] is Object(first) &&
    first.get("node") is Some(Number(first_node, ..)) &&
    first.get("start") is Some(Number(first_start, ..)) &&
    first.get("end") is Some(Number(first_end, ..)) &&
    first.get("pitch") == Some(Json::null()) &&
    rests[1] is Object(second) &&
    second.get("node") is Some(Number(second_node, ..)) &&
    second.get("start") is Some(Number(second_start, ..)) &&
    second.get("end") is Some(Number(second_end, ..)) else {
    fail(
      "all-rest phrase should preserve each original atom and occurrence timing",
    )
  }
  assert_true(first_node != second_node)
  assert_true(
    first_start == 0.0 && second_start > 0.666 && second_start < 0.667,
  )
  assert_true(first_end > 0.666 && first_end < 0.667 && second_end == 1.0)
  guard nodes[first_node.to_int()] is Object(first_source) &&
    nodes[second_node.to_int()] is Object(second_source) &&
    first_source.get("value") == Some("~".to_json()) &&
    second_source.get("value") == Some("~".to_json()) else {
    fail("all-rest event mappings must refer to source rest atoms")
  }
}

///|
test "notation projection compiles drum and chord origins" {
  let drums = @json.parse(project_notation("drum", "bd*2 ~"))
  guard drums is Object(drum_fields) &&
    drum_fields.get("events") is Some(Array(drum_events)) &&
    drum_fields.get("rests") is Some(Array(drum_rests)) else {
    fail("expected drum projection events")
  }
  assert_true(drum_rests.is_empty())
  assert_eq(drum_events.length(), 2)
  guard drum_events[0] is Object(first_drum) &&
    first_drum.get("pitch") == Some(Json::null()) else {
    fail("drum projection should not invent MIDI pitch")
  }
  let chords = @json.parse(project_notation("chord", "C*2"))
  guard chords is Object(chord_fields) &&
    chord_fields.get("events") is Some(Array(chord_events)) &&
    chord_fields.get("rests") is Some(Array(chord_rests)) else {
    fail("expected chord projection events")
  }
  assert_true(chord_rests.is_empty())
  assert_eq(chord_events.length(), 6)
  guard chord_events[0] is Object(first_chord) &&
    first_chord.get("node") is Some(first_node) &&
    chord_events[3] is Object(repeated_chord) &&
    repeated_chord.get("node") is Some(repeated_node) else {
    fail("chord projection event is missing its source atom")
  }
  assert_true(first_node == repeated_node)
}

///|
test "explicit chord projection keeps all pitches on one complete source atom" {
  let output = @json.parse(project_notation("chord", "{60,63,68}@2*2"))
  guard output is Object(fields) &&
    fields.get("events") is Some(Array(events)) &&
    fields.get("nodes") is Some(Array(nodes)) else {
    fail("expected explicit chord projection")
  }
  assert_eq(events.length(), 6)
  guard events[0] is Object(first_event) &&
    first_event.get("node") is Some(first_node) &&
    events[3] is Object(repeated_event) &&
    repeated_event.get("node") is Some(repeated_node) &&
    first_node is Number(node_number, ..) else {
    fail("explicit chord voices must refer to a source atom")
  }
  assert_true(first_node == repeated_node)
  guard nodes[node_number.to_int()] is Object(atom) &&
    atom.get("value") == Some("{60,63,68}".to_json()) &&
    atom.get("from") == Some((0).to_json()) &&
    atom.get("baseTo") == Some((10).to_json()) &&
    atom.get("end") == Some((14).to_json()) else {
    fail("explicit chord projection must retain its full source span")
  }
}

///|
test "rest probes share the projection event and expansion bounds" {
  let boundary = @json.parse(project_notation("note", "[~ 60]*128"))
  guard boundary is Object(fields) &&
    fields.get("error") == Some(Json::null()) &&
    fields.get("events") is Some(Array(events)) &&
    fields.get("rests") is Some(Array(rests)) else {
    fail("expected a projection at the combined event limit")
  }
  assert_eq(events.length(), 128)
  assert_eq(rests.length(), 128)
  for content in ["[~ 60]*129", "[~*256 ~*256]*16"] {
    let rejected = @json.parse(project_notation("note", content))
    guard rejected is Object(fields) &&
      fields.get("error") is Some(String(_)) &&
      fields.get("events") is Some(Array([])) &&
      fields.get("rests") is Some(Array([])) else {
      fail("oversized rest projections must fail without partial geometry")
    }
  }
}

///|
test "onset lookup keeps exact references but retires edited literal geometry" {
  let draft = @mini.Draft::new("let motif = note(\"60\"); motif") catch {
    _ => fail("expected draft")
  }
  guard draft.prepare_playback() is Ok(input) else {
    fail("expected prepared exact pattern")
  }
  guard input.compile() is Ok(@mini.PreparedPlayback::Pattern(snapshot, _)) else {
    fail("expected compiled exact pattern")
  }
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let source_event = snapshot.query(arc)[0]
  let origin = source_event.origin()
  let bindings = origin.bindings()
  guard source_event.source_frame() is Some(frame) else {
    fail("expected literal frame provenance")
  }
  let row : Array[Json] = [
    Json::number(5.0),
    origin.atom().epoch().serial().to_double().to_json(),
    origin.atom().serial().to_double().to_json(),
    frame.serial().to_double().to_json(),
    source_event.source_start().to_json(),
    source_event.source_pitch().to_json(),
    bindings.length().to_json(),
  ]
  for binding in bindings {
    row.push(binding.reference().serial().to_double().to_json())
    row.push(binding.id().serial().to_double().to_json())
    row.push(binding.definition().serial().to_double().to_json())
  }
  let decoded = @json.parse(
    locate_onsets(draft, Json::array([Json::array(row)]).stringify()),
  )
  guard decoded is Array([Object(fields)]) &&
    fields.get("from") is Some(Number(from, ..)) &&
    fields.get("to") is Some(Number(to, ..)) &&
    fields.get("references") is Some(Array(references)) &&
    fields.get("notation") is Some(Object(notation)) &&
    notation.get("from") is Some(Number(notation_from, ..)) &&
    notation.get("to") is Some(Number(notation_to, ..)) &&
    notation.get("start") is Some(Number(start, ..)) &&
    notation.get("pitch") is Some(Number(pitch, ..)) else {
    fail("expected exact atom and notation location wire result")
  }
  assert_true(from == 18.0 && to == 20.0)
  guard references is [Object(reference)] else {
    fail("expected traversed motif reference")
  }
  assert_true(reference.get("from") == Some(Json::number(24.0)))
  assert_true(reference.get("to") == Some(Json::number(29.0)))
  assert_true(notation_from == 18.0 && notation_to == 20.0)
  assert_true(start == 0.0 && pitch == 60.0)
  guard @json.parse(draft_state(draft)) is Object(state) &&
    state.get("version") is Some(version) else {
    fail("expected draft version")
  }
  let edit : Json = {
    "base": version,
    "edits": Json::array([
      {
        "from": Json::number(20.0),
        "to": Json::number(20.0),
        "inserted": Json::string("*2"),
      },
    ]),
  }
  ignore(edit_draft(draft, edit.stringify()))
  let moved = @json.parse(
    locate_onsets(draft, Json::array([Json::array(row)]).stringify()),
  )
  guard moved is Array([Object(fields)]) &&
    fields.get("references") is Some(Array([Object(reference)])) else {
    fail("unchanged atom and binding must remain represented")
  }
  assert_true(fields.get("from") == Some(Json::number(18.0)))
  assert_true(fields.get("to") == Some(Json::number(20.0)))
  assert_true(reference.get("from") == Some(Json::number(26.0)))
  assert_true(reference.get("to") == Some(Json::number(31.0)))
  assert_true(fields.get("notation") == Some(Json::null()))
  draft.dispose()
}

///|
test "negative pitch is distinct from an unpitched drum onset" {
  for
    (text, pitch, from) in [
      ("note(\"-1\")", Json::number(-1.0), 6.0),
      ("s(\"hh\")", Json::null(), 3.0),
    ] {
    let draft = @mini.Draft::new(text)
    guard draft.prepare_playback() is Ok(input) &&
      input.compile() is Ok(@mini.PreparedPlayback::Pattern(snapshot, _)) else {
      fail("expected exact playback: \{draft_state(draft)}")
    }
    let event = snapshot.query(
        @pattern.TimeSpan::new(
          @pattern.Rational::from_int(0),
          @pattern.Rational::from_int(1),
        ),
      )[0]
    guard event.source_frame() is Some(frame) else {
      fail("expected source frame")
    }
    let wire_pitch = if event.source_pitch().is_nan() {
      Json::null()
    } else {
      event.source_pitch().to_json()
    }
    assert_true(wire_pitch == pitch)
    let row : Json = [
      0,
      event.origin().atom().epoch().serial().to_double().to_json(),
      event.origin().atom().serial().to_double().to_json(),
      frame.serial().to_double().to_json(),
      event.source_start().to_json(),
      wire_pitch,
      0,
    ]
    guard @json.parse(locate_onsets(draft, Json::array([row]).stringify()))
      is Array([Object(fields)]) &&
      fields.get("notation") is Some(Object(notation)) else {
      fail("expected located onset for pitched and unpitched atoms")
    }
    assert_true(notation.get("pitch") == Some(pitch))
    assert_true(fields.get("from") == Some(Json::number(from)))
    assert_true(fields.get("to") == Some(Json::number(from + 2.0)))
    draft.dispose()
  }
}
