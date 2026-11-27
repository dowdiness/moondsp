///|
fn play_source_song() -> String {
  "song(section(\"a\",1,s(\"bd\")),part(\"a1\",\"a\"))"
}

///|
test "play source parses a pattern with comments" {
  let edited = parse_play_source("// header\ns(\"sd\") // tail").unwrap()
  assert_eq(edited.bpm(), 120.0)
  match edited.body() {
    Pattern(_) => ()
    _ => fail("expected pattern")
  }
}

///|
test "play source parses bindings and default bpm" {
  let pattern = parse_play_source("let beat = s(\"bd\"); beat").unwrap()
  assert_eq(pattern.bpm(), 120.0)
  match pattern.body() {
    Pattern(_) => ()
    _ => fail("expected pattern")
  }
}

///|
test "play source accepts silence pattern" {
  let parsed = parse_play_source("silence()").unwrap()
  match parsed.body() {
    Pattern(_) => ()
    _ => fail("expected pattern")
  }
}

///|
test "play source parses arrangement declaration and repeat marker" {
  let source = "bpm(96); // authored tempo\n" + play_source_song() + ".repeat()"
  let parsed = parse_play_source(source).unwrap()
  assert_eq(parsed.bpm(), 96.0)
  match parsed.body() {
    UntrackedArrangement(_, repeats) => assert_true(repeats)
    _ => fail("expected arrangement")
  }
  let finite = parse_play_source(play_source_song()).unwrap()
  match finite.body() {
    UntrackedArrangement(_, repeats) => assert_false(repeats)
    _ => fail("expected arrangement")
  }
}

///|
test "play source rejects empty and duplicate tempo declarations" {
  assert_true(parse_play_source("") is Err(_))
  assert_true(
    parse_play_source(
      "bpm(90); song(bpm(120),section(\"a\",1,s(\"bd\")),part(\"a1\",\"a\"))",
    )
    is Err(_),
  )
  assert_true(
    parse_play_source(
      "song(bpm(90),bpm(120),section(\"a\",1,s(\"bd\")),part(\"a1\",\"a\"))",
    )
    is Err(_),
  )
}

///|
test "play source problems say whether the author made a mistake or exceeded a limit" {
  let problem = (source : String) => {
    match parse_play_source(source) {
      Ok(_) => None
      Err(problem) => Some(problem)
    }
  }
  // Inside quoted notation, a mistake is still located in the whole source.
  guard problem("note(\"c4 ?? e4\")") is Some(Mistake(9, _)) else {
    fail("expected a mistake at the unknown note")
  }
  let song = "song(section(\"a\",4,s(\"bd\")),part(\"p\",\"b\",0))"
  guard problem(song) is Some(Mistake(at, _)) else {
    fail("expected a mistake at the unknown section")
  }
  assert_eq(song[at:at + 3].to_owned(), "\"b\"")
  // A repeated part is reported where it first repeats, not where the song
  // begins.
  let repeated = "song(section(\"a\",4,s(\"bd\")),part(\"p\",\"a\",0),part(\"p\",\"a\",4),part(\"p\",\"a\",8))"
  guard problem(repeated) is Some(Mistake(at, "duplicate song part 'p'")) else {
    fail("expected a mistake at the repeated part")
  }
  assert_true(repeated[at:].to_owned().has_prefix("part(\"p\",\"a\",4)"))
  // Valid but too deep for playback: a limit, with no position to blame.
  let nested = "note(\"" + "[".repeat(40) + "60" + "]".repeat(40) + "\")"
  assert_true(
    parse_play_source(nested, query_window=calibrated_window())
    is Err(OverLimit(Nesting(32))),
  )
}

///|
test "bounded play source preserves ordinary musical output" {
  let source = "let beat = note(\"60 64\"); beat.fast(2)"
  let bounded = parse_play_source(source, query_window=calibrated_window()).unwrap()
  guard bounded.body() is Pattern(doc) else { fail("expected pattern") }
  let snapshot = doc.lower()
  let events = snapshot
    .pat()
    .query(
      @pattern.TimeSpan(
        @pattern.Rational::from_int(0),
        @pattern.Rational::from_int(1),
      ),
    )
  assert_eq(events.length(), 4)
  assert_eq(pitch_of(events[0].value), Some(60.0))
  assert_eq(pitch_of(events[1].value), Some(64.0))
}

///|
test "bounded play source rejects amplification before querying future branches" {
  let sources = [
    "note(\"60\").fast(100000)", "note(\"60*100000\")", "note(\"60*1000 ~\")", "let dense = note(\"60\").fast(1000); dense.fast(1000)",
    "note(\"60\").every(1000000,fast(100000))", "note(\"60\").jux(fast(100000))",
    "song(section(\"a\",1,note(\"60\").fast(100000)),part(\"a1\",\"a\"))",
  ]
  for source in sources {
    assert_true(
      parse_play_source(source, query_window=calibrated_window()) is Err(_),
    )
  }
}

///|
test "bounded play source prevents eager Euclidean allocation" {
  assert_true(
    parse_play_source("s(\"bd(1,128)\")", query_window=calibrated_window())
    is Ok(_),
  )
  assert_true(
    parse_play_source("s(\"bd(1,129)\")", query_window=calibrated_window())
    is Err(_),
  )
  assert_true(
    parse_play_source(
      "song(section(\"a\",1,s(\"bd(1,100000)\")),part(\"a1\",\"a\"))",
      query_window=calibrated_window(),
    )
    is Err(_),
  )
}

///|
test "bounded play source accounts for cumulative layers and repeated occurrences" {
  let layer = "note(\"60\").fast(1000)"
  assert_true(
    parse_play_source(layer, query_window=calibrated_window()) is Ok(_),
  )
  let layers = Array::make(6, layer).join(" + ")
  assert_true(
    parse_play_source(layers, query_window=calibrated_window()) is Err(_),
  )
  let song = "song(section(\"a\",1," +
    layer +
    "),part(\"a1\",\"a\"),part(\"a2\",\"a\"),part(\"a3\",\"a\"))"
  assert_true(
    parse_play_source(song, query_window=calibrated_window()) is Ok(_),
  )
  assert_true(
    parse_play_source(song + ".repeat()", query_window=calibrated_window())
    is Err(_),
  )
}

///|
test "bounded play source rejects source size and recursive depth before parsing" {
  let window = calibrated_window()
  let oversized = "note(\"60\")" + Array::make(8192, " ").join("")
  assert_true(parse_play_source(oversized, query_window=window) is Err(_))
  let nested = Array::make(40, "(").join("") +
    "note(\"60\")" +
    Array::make(40, ")").join("")
  assert_true(parse_play_source(nested, query_window=window) is Err(_))
  let misleading_comment = "// " + Array::make(40, ")").join("") + "\n"
  assert_true(
    parse_play_source(misleading_comment + nested, query_window=window)
    is Err(_),
  )
  assert_true(
    parse_play_source("// ((( ignored\nnote(\"60\")", query_window=window)
    is Ok(_),
  )
}

///|
/// The pitch `event` plays, if it is a note.
fn pitch_of(event : @score.ScoreEvent) -> Double? {
  match event.sound {
    Note(_, pitch~) | Play(_, pitch~) => Some(pitch)
    Hit(_) => None
  }
}
