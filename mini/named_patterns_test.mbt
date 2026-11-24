///|
test "named groups preserve cycles and transformations without mutating definitions" {
  let source =
    #|let motif = note("E4 G4 A4").slow(3);
    #|let beat = s("bd");
    #|let groove = stack(motif, beat);
    #|stack(groove.gain(0.2), motif)
  let inline = "stack(stack(note(\"E4 G4 A4\").slow(3),s(\"bd\")).gain(0.2),note(\"E4 G4 A4\").slow(3))"
  assert_named_compiles_like(source, inline, song_span(0L, 1L, 12L, 1L))
}

///|
test "definitions work with dollar stack lines" {
  let source = "let tone = note(\"60\");\n$: tone\n$: tone.gain(0.2)"
  let inline = "stack(note(\"60\"),note(\"60\").gain(0.2))"
  assert_named_compiles_like(source, inline, song_span(0L, 1L, 1L, 1L))
}

///|
test "definitions are scoped to one input" {
  let source = "let tone = note(\"60\"); tone"
  for
    parse in [
      fn(input) { @mini.parse(input).map(_ => ()) },
      fn(input) { @mini.parse_doc(input).map(_ => ()) },
    ] {
    assert_true(parse(source) is Ok(_))
    assert_true(parse("tone") is Err(_))
  }
}

///|
test "binding diagnostics reject duplicates unresolved names and recursive definitions" {
  let cases = [
    ("let a = note(\"60\"); let a = note(\"62\"); a", "duplicate pattern 'a'"),
    ("let a = missing; a", "undefined pattern 'missing'"),
    ("let a = a; a", "undefined pattern 'a'"),
    ("let a = b; let b = a; a", "undefined pattern 'b'"),
    ("let s = note(\"60\"); s", "reserved pattern name 's'"),
    ("let a = note(\"60\") a", "expected ';'"),
  ]
  for item in cases {
    let (source, message) = item
    for
      result in [
        @mini.parse(source).map(_ => ()),
        @mini.parse_song(source).map(_ => ()),
        @mini.parse_doc(source).map(_ => ()),
      ] {
      match result {
        Err(error) => assert_true(error.contains(message))
        Ok(_) => fail("expected binding error: \{source}")
      }
    }
  }
}

///|
test "one definition edit changes every section while preserving song layout" {
  let suffix = "song(section(\"a\",3,theme),section(\"b\",4,theme),part(\"a1\",\"a\"),part(\"b1\",\"b\"))"
  let before = unwrap_parsed_song(
    @mini.parse_song("let theme = note(\"60\").slow(3); " + suffix),
  )
  let after = unwrap_parsed_song(
    @mini.parse_song("let theme = note(\"72\").slow(3); " + suffix),
  )
  @debug.assert_eq(before.duration(), after.duration())
  let span = song_span(0L, 1L, 7L, 1L)
  let old_events = before.query(span)
  let events = after.query(span)
  @debug.assert_eq(events.length(), old_events.length())
  for i in 0..<events.length() {
    @debug.assert_eq(events[i].whole, old_events[i].whole)
    @debug.assert_eq(events[i].part, old_events[i].part)
    @debug.assert_eq(pitch_of(old_events[i].value), Some(60.0))
    @debug.assert_eq(pitch_of(events[i].value), Some(72.0))
  }
}

///|
fn assert_named_events(
  actual : Array[@pattern.Event[@score.ScoreEvent]],
  expected : Array[@pattern.Event[@score.ScoreEvent]],
) -> Unit raise {
  // Compare the complete audible event, without depending on source identities.
  @debug.assert_eq(
    actual.map(event => {
      (event.whole, event.part, event.value.controls.entries())
    }),
    expected.map(event => {
      (event.whole, event.part, event.value.controls.entries())
    }),
  )
}

///|
fn assert_named_compiles_like(
  source : String,
  inline : String,
  span : @pattern.TimeSpan,
) -> Unit raise {
  assert_named_events(
    unwrap_ok(@mini.parse(source)).query(span),
    unwrap_ok(@mini.parse(inline)).query(span),
  )
}

///|
test "Draft definition edits update nested named groups without stale playback" {
  let tail = "let group = stack(tone,tone.gain(0.2)); group.slow(3)"
  let prefix = "let tone = note(\""
  let draft = @mini.Draft(prefix + "60\"); " + tail)
  let span = song_span(0L, 1L, 3L, 1L)
  for note in [60, 72, 67] {
    edit_draft(draft, prefix.length(), prefix.length() + 2, note.to_string())
    let snapshot = draft_snapshot(draft)
    let inline = "stack(note(\"\{note}\"),note(\"\{note}\").gain(0.2)).slow(3)"
    assert_named_events(
      snapshot.query(span).map(event => event.event()),
      unwrap_ok(@mini.parse(inline)).query(span),
    )
  }
}

///|
test "named document events retain distinct references and their shared definition source" {
  let doc = unwrap_doc(
    @mini.parse_doc("let phrase = note(\"60\").slow(3); stack(phrase,phrase)"),
  )
  let snapshot = doc.lower()
  let events = snapshot.query_sourced_events(song_span(0L, 1L, 3L, 1L))
  @debug.assert_eq(events.length(), 2)
  let first = events[0].pattern_nodes()
  let second = events[1].pattern_nodes()
  assert_true(first[1] != second[1])
  @debug.assert_eq(first[first.length() - 1], second[second.length() - 1])
  guard doc.referenced_definition(first[1]) is Some(definition) else {
    fail("reference became opaque")
  }
  assert_true(definition.contains_node(first[first.length() - 1]))
}

///|
fn[T] assert_undefined_pattern_at(
  result : Result[T, String],
  name : String,
  position : Int32,
) -> Unit raise {
  guard result is Err(error) else { fail("expected an undefined pattern") }
  assert_true(error.contains("undefined pattern '\{name}'"))
  assert_true(error.has_prefix("position \{position}:"))
}

///|
test "notation mistakes and undefined names are reported in source order" {
  let invalid_note_first = "stack(note(\"NotANote\"), missing)"
  let undefined_name_first = "stack(missing, note(\"NotANote\"))"
  for
    parsed in [
      @mini.parse(invalid_note_first).map(_ => ()),
      @mini.parse_doc(invalid_note_first).map(_ => ()),
    ] {
    assert_eq(parsed, Err("position 12: expected note name or number"))
  }
  // Control values are read in the same pass as the notation before them.
  let control_after_note = "note(\"c4 x\").gain(\"0.5 y\")"
  assert_eq(
    @mini.parse(control_after_note).map(_ => ()),
    Err("position 9: expected note name or number"),
  )
  assert_undefined_pattern_at(@mini.parse(undefined_name_first), "missing", 6)
  assert_undefined_pattern_at(
    @mini.parse_doc(undefined_name_first),
    "missing",
    6,
  )
}

///|
test "undefined names are reported before missing declaration terminators" {
  let prefix = "let a = "
  let source = prefix + "missing note(\"60\")"
  assert_undefined_pattern_at(@mini.parse(source), "missing", prefix.length())
  assert_undefined_pattern_at(
    @mini.parse_doc(source),
    "missing",
    prefix.length(),
  )
  assert_undefined_pattern_at(
    @mini.parse_song(source),
    "missing",
    prefix.length(),
  )
}

///|
test "unused definitions are validated" {
  let source = "let unused = note(\"NotANote\"); note(\"60\")"
  assert_true(@mini.parse(source) is Err(_))
}
