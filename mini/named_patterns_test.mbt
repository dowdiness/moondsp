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
    @debug.assert_eq(old_events[i].value.get("note"), Some(60.0))
    @debug.assert_eq(events[i].value.get("note"), Some(72.0))
  }
}

///|
fn assert_named_events(
  actual : Array[@pattern.Event[@pattern.ControlMap]],
  expected : Array[@pattern.Event[@pattern.ControlMap]],
) -> Unit raise {
  // Compare the complete audible event, without depending on source identities.
  @debug.assert_eq(
    actual.map(event => (event.whole, event.part, event.value.entries())),
    expected.map(event => (event.whole, event.part, event.value.entries())),
  )
}

///|
fn assert_named_compiles_like(
  source : String,
  inline : String,
  span : @pattern.TimeSpan,
) -> Unit raise {
  let expected = unwrap_ok(@mini.parse(inline)).query(span)
  assert_named_events(unwrap_ok(@mini.parse(source)).query(span), expected)
  assert_named_events(
    unwrap_mini_snapshot(@mini.parse_snapshot(source)).query(span),
    expected,
  )
}

///|
test "Draft definition edits update nested named groups without stale playback" {
  let tail = "let group = stack(tone,tone.gain(0.2)); group.slow(3)"
  let prefix = "let tone = note(\""
  let draft = @mini.Draft::new(prefix + "60\"); " + tail)
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
  draft.dispose()
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
  position : Int,
) -> Unit raise {
  guard result is Err(error) else { fail("expected an undefined pattern") }
  assert_true(error.contains("undefined pattern '\{name}'"))
  assert_true(error.has_prefix("position \{position}:"))
}

///|
test "undefined names are reported before invalid notes" {
  let prefix = "stack(note(\"NotANote\"), "
  let source = prefix + "missing)"
  assert_undefined_pattern_at(@mini.parse(source), "missing", prefix.length())
  assert_undefined_pattern_at(
    @mini.parse_doc(source),
    "missing",
    prefix.length(),
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
test "unused definitions are validated by both compilation paths" {
  let source = "let unused = note(\"NotANote\"); note(\"60\")"
  assert_true(@mini.parse(source) is Err(_))
  assert_true(@mini.parse_doc(source) is Err(_))
}
