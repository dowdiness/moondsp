///|
fn wire_test_input(text : String) -> @mini.PlaybackInput raise {
  let draft = @mini.Draft::new(text)
  match draft.prepare_playback() {
    Ok(input) => input
    Err(error) => fail(error.message())
  }
}

///|
fn wire_test_snapshot(
  input : @mini.PlaybackInput,
) -> @pattern.PatternSnapshotWithOrigins[@pattern.ControlMap] raise {
  match input.compile() {
    Ok(@mini.PreparedPlayback::Pattern(snapshot, _)) => snapshot
    _ => fail("expected exact pattern")
  }
}

///|
test "wire roundtrip preserves named routes and frozen source identity" {
  let draft = @mini.Draft::new("let tone = note(\"60\"); stack(tone, tone)")
  guard draft.prepare_playback() is Ok(input) else { fail("expected input") }
  let encoded = input.encode_wire()
  let before = wire_test_snapshot(input)
  guard draft.edit(
      @mini.EditTransaction::EditTransaction(base=draft.state().version(), edits=[
        @mini.TextEdit::TextEdit(from=0, to=0, inserted=" "),
      ]),
    )
    is Ok(_) else {
    fail("expected edit")
  }
  guard @mini.PlaybackInput::decode_wire(encoded) is Ok(decoded) else {
    fail("decode failed")
  }
  assert_eq(decoded.version(), input.version())
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let expected = before.query(arc)
  let actual = wire_test_snapshot(decoded).query(arc)
  guard actual is [left, right] && expected is [expected_left, expected_right] else {
    fail("expected two notes")
  }
  assert_eq(left.origin(), expected_left.origin())
  assert_eq(right.origin(), expected_right.origin())
  assert_true(
    left.origin().bindings()[0].reference() !=
    right.origin().bindings()[0].reference(),
  )
  assert_true(draft.locate_origin(left.origin()) is Located(_, _))
  assert_eq(left.event().value.get("note"), Some(60.0))
}

///|
test "wire rejects forged or missing facts including unused definitions" {
  let input = wire_test_input(
    "let unused = note(\"62\"); let tone = note(\"60\"); tone",
  )
  for corruption in 0..<5 {
    let json = @json.parse(input.encode_wire())
    guard json is Object(fields) &&
      fields.get("sourceMap") is Some(Object(sources)) &&
      sources.get("atoms") is Some(Array(atoms)) &&
      sources.get("references") is Some(Array(references)) &&
      atoms[0] is Array(first_atom) &&
      atoms[1] is Array(second_atom) &&
      references[0] is Array(reference) else {
      fail("missing witness rows")
    }
    match corruption {
      0 => atoms.remove(0) |> ignore
      1 => first_atom[2] = 0
      2 => second_atom[0] = first_atom[0]
      3 => reference[5] = first_atom[0]
      _ => reference[4] = 1.5
    }
    assert_true(@mini.PlaybackInput::decode_wire(json.stringify()) is Err(_))
  }
}

///|
test "wire capabilities cannot downgrade exact failure or forge song mode" {
  let input = wire_test_input("note(\"60\")")
  let json = @json.parse(input.encode_wire())
  guard json is Object(fields) else { fail("expected object") }
  fields["kind"] = "text"
  assert_true(@mini.PlaybackInput::decode_wire(json.stringify()) is Err(_))
  fields["kind"] = "song"
  ignore(fields.remove("sourceMap"))
  guard @mini.PlaybackInput::decode_wire(json.stringify()) is Ok(song) else {
    fail("expected envelope decode")
  }
  assert_true(song.compile() is Err(_))
  let text = @mini.PlaybackInput::text("note(\"60\")")
  guard @mini.PlaybackInput::decode_wire(text.encode_wire()) is Ok(runtime) else {
    fail("expected text decode")
  }
  assert_true(runtime.version() is None)
  assert_true(runtime.compile() is Ok(@mini.PreparedPlayback::Runtime(_)))
}

///|
test "wire validates safe integers versions and input bounds" {
  let input = wire_test_input("s(\"bd\")")
  for invalid in [0.0, -1.0, 1.5, 9007199254740992.0] {
    let json = @json.parse(input.encode_wire())
    guard json is Object(fields) &&
      fields.get("version") is Some(version) &&
      fields.get("sourceMap") is Some(Object(sources)) else {
      fail("expected tracked input")
    }
    fields["version"] = [invalid.to_json(), 0]
    assert_true(@mini.PlaybackInput::decode_wire(json.stringify()) is Err(_))
    fields["version"] = version
    sources["epoch"] = invalid.to_json()
    assert_true(@mini.PlaybackInput::decode_wire(json.stringify()) is Err(_))
  }
  assert_true(
    @mini.PlaybackInput::decode_wire(
      @mini.PlaybackInput::text(" ".repeat(8193)).encode_wire(),
    )
    is Err(_),
  )
  assert_true(@mini.PlaybackInput::decode_wire("[".repeat(1025)) is Err(_))
}

///|
test "wire preserves rotated source epochs independently of document versions" {
  let text = "let tone = note(\"60\"); tone"
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  for
    interruption in [
      "song(section(\"a\",1,note(\"60\")),part(\"p\",\"a\"))",
      " ".repeat(8193),
    ] {
    let draft = @mini.Draft::new(text)
    guard draft.prepare_playback() is Ok(initial) else {
      fail("expected input")
    }
    let old_origin = wire_test_snapshot(initial).query(arc)[0].origin()
    for replacement in [interruption, text] {
      let state = draft.state()
      guard draft.edit(
          @mini.EditTransaction::EditTransaction(base=state.version(), edits=[
            @mini.TextEdit::TextEdit(
              from=0,
              to=state.text().length(),
              inserted=replacement,
            ),
          ]),
        )
        is Ok(_) else {
        fail("expected edit")
      }
    }
    guard draft.prepare_playback() is Ok(input) else {
      fail("expected restored input")
    }
    let expected = wire_test_snapshot(input).query(arc)[0].origin()
    guard @mini.PlaybackInput::decode_wire(input.encode_wire()) is Ok(decoded) else {
      fail("expected transported input")
    }
    let actual = wire_test_snapshot(decoded).query(arc)[0].origin()
    assert_eq(decoded.version(), input.version())
    assert_eq(actual, expected)
    assert_true(actual.atom().epoch() != old_origin.atom().epoch())
    assert_true(draft.locate_origin(actual) is Located(_, _))
    assert_true(draft.locate_origin(old_origin) is Unavailable(SourceReset))
  }
}
