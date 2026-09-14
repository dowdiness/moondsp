///|
fn overlay_event_signatures(
  events : Array[@pattern.Event[@pattern.ControlMap]],
) -> Array[(@pattern.TimeSpan?, @pattern.TimeSpan, Map[String, Double])] {
  events.map(event => (event.whole, event.part, event.value.entries()))
}

///|
test "plus matches explicit stack including event times and controls" {
  let plus = unwrap_ok(
    @mini.parse("s(\"bd\").gain(0.25) + s(\"sd\").pan(-0.5)"),
  )
  let explicit = unwrap_ok(
    @mini.parse("stack(s(\"bd\").gain(0.25), s(\"sd\").pan(-0.5))"),
  )
  @debug.assert_eq(
    overlay_event_signatures(query_one_cycle(plus)),
    overlay_event_signatures(query_one_cycle(explicit)),
  )
}

///|
test "method chains bind more tightly than overlay unless grouped" {
  let grouped = unwrap_ok(@mini.parse("(s(\"bd\") + s(\"sd\")).fast(2)"))
  let explicit = unwrap_ok(@mini.parse("stack(s(\"bd\"), s(\"sd\")).fast(2)"))
  @debug.assert_eq(
    overlay_event_signatures(query_one_cycle(grouped)),
    overlay_event_signatures(query_one_cycle(explicit)),
  )
  let ungrouped = unwrap_ok(@mini.parse("s(\"bd\") + s(\"sd\").fast(2)"))
  let right_only = unwrap_ok(@mini.parse("stack(s(\"bd\"), s(\"sd\").fast(2))"))
  @debug.assert_eq(
    overlay_event_signatures(query_one_cycle(ungrouped)),
    overlay_event_signatures(query_one_cycle(right_only)),
  )
}

///|
test "ordinary whitespace around plus is accepted" {
  let spaced = unwrap_ok(@mini.parse("s(\"bd\")  +\n  s(\"sd\")"))
  let explicit = unwrap_ok(@mini.parse("stack(s(\"bd\"), s(\"sd\"))"))
  @debug.assert_eq(
    overlay_event_signatures(query_one_cycle(spaced)),
    overlay_event_signatures(query_one_cycle(explicit)),
  )
}

///|
test "parentheses keep repeated reference behavior" {
  let references = unwrap_ok(
    @mini.parse("let motif = note(\"60\").gain(0.5); (motif) + motif"),
  )
  let explicit = unwrap_ok(
    @mini.parse("stack(note(\"60\").gain(0.5), note(\"60\").gain(0.5))"),
  )
  @debug.assert_eq(
    overlay_event_signatures(query_one_cycle(references)),
    overlay_event_signatures(query_one_cycle(explicit)),
  )
}

///|
test "plus works in dollar stack lines" {
  let dollar = unwrap_ok(@mini.parse("$: s(\"bd\") + s(\"sd\")"))
  let explicit = unwrap_ok(@mini.parse("stack(s(\"bd\"), s(\"sd\"))"))
  @debug.assert_eq(
    overlay_event_signatures(query_one_cycle(dollar)),
    overlay_event_signatures(query_one_cycle(explicit)),
  )
}

///|
test "plus works in song sections" {
  let song = unwrap_parsed_song(
    @mini.parse_song(
      "song(section(\"a\",1,s(\"bd\") + s(\"sd\")),part(\"a1\",\"a\"))",
    ),
  )
  let actual = song.query(song_span(0L, 1L, 1L, 1L))
  let explicit = unwrap_ok(@mini.parse("stack(s(\"bd\"), s(\"sd\"))"))
  @debug.assert_eq(
    overlay_event_signatures(actual),
    overlay_event_signatures(query_one_cycle(explicit)),
  )
}

///|
test "parentheses preserve document events and source paths" {
  let plus = unwrap_doc(
    @mini.parse_doc("s(\"bd\").gain(0.25) + (s(\"sd\").pan(-0.5))"),
  )
  let explicit = unwrap_doc(
    @mini.parse_doc("stack(s(\"bd\").gain(0.25), s(\"sd\").pan(-0.5))"),
  )
  let arc = song_span(0L, 1L, 1L, 1L)
  let actual = plus.lower()
  let expected = explicit.lower()
  @debug.assert_eq(
    overlay_event_signatures(actual.query(arc)),
    overlay_event_signatures(expected.query(arc)),
  )
  @debug.assert_eq(
    actual.query_sourced_events(arc).map(event => event.pattern_nodes()),
    expected.query_sourced_events(arc).map(event => event.pattern_nodes()),
  )
}

///|
test "overlay rejects missing operands and unmatched groups" {
  for
    source in [
      "+", "s(\"bd\") +", "s(\"bd\") ++ s(\"sd\")", "s(\"bd\") + + s(\"sd\")", "(s(\"bd\") + s(\"sd\")",
      "s(\"bd\") + 2", "s(\"bd\")\ns(\"sd\")",
    ] {
    assert_true(@mini.parse(source) is Err(_))
    assert_true(@mini.parse_doc(source) is Err(_))
  }
}

///|
test "plus inside quoted chord notation remains chord content" {
  let pat = unwrap_ok(@mini.parse("chord(\"C+7\")"))
  let events = query_one_cycle(pat)
  @debug.assert_eq(events.map(event => event.value.get("note")), [
    Some(60.0),
    Some(64.0),
    Some(68.0),
    Some(70.0),
  ])
}

///|
test "editing a binding keeps the playback identity of its use site" {
  let before = unwrap_doc(
    @mini.parse_doc("let motif = note(\"60\").slow(3); motif"),
  ).lower()
  let after = unwrap_doc(
    @mini.parse_doc("let motif = note(\"72\").slow(4); motif"),
  ).lower()
  @debug.assert_eq(before.entry_key(0), after.entry_key(0))
  @debug.assert_eq(
    after.query(song_span(0L, 1L, 1L, 1L)).map(event => event.value.get("note")),
    [Some(72.0)],
  )
}

///|
test "regrouping a shaped document preserves known material content and addresses" {
  let before = unwrap_doc(
    @mini.parse_doc(
      "(stack(note(\"60\"), note(\"72\")) + note(\"84\")).gain(0.3).slow(3).rev()",
    ),
  ).lower()
  let after = unwrap_doc(
    @mini.parse_doc(
      "(note(\"60\") + (note(\"72\") + note(\"84\"))).gain(0.3).slow(3).rev()",
    ),
  ).lower()
  assert_true(before.pat().material().same_content(after.pat().material()))
  let old_entries = before.pat().entries()
  let new_entries = after.pat().entries()
  for index in 0..<old_entries.length() {
    @debug.assert_eq(before.entry_key(index), after.entry_key(index))
    assert_true(old_entries[index].same_content(new_entries[index]))
  }
}
