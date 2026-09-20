///|
fn play_source_song() -> String {
  "song(section(\"a\",1,s(\"bd\")),part(\"a1\",\"a\"))"
}

///|
test "play source parses pattern and preserves previous document" {
  let first = @mini.parse_play_source("s(\"bd\")").unwrap()
  let first_doc = match first.body() {
    Pattern(doc) => doc
    Arrangement(_, _) => fail("expected pattern")
  }
  let edited = @mini.parse_play_source(
    "// header\ns(\"sd\") // tail",
    previous=Some(first_doc),
  ).unwrap()
  assert_eq(edited.bpm(), 60.0)
  match edited.body() {
    Pattern(_) => ()
    Arrangement(_, _) => fail("expected pattern")
  }
}

///|
test "play source parses bindings and default bpm" {
  let pattern = @mini.parse_play_source("let beat = s(\"bd\"); beat").unwrap()
  assert_eq(pattern.bpm(), 60.0)
  match pattern.body() {
    Pattern(_) => ()
    Arrangement(_, _) => fail("expected pattern")
  }
}

///|
test "play source accepts silence pattern" {
  let parsed = @mini.parse_play_source("silence()").unwrap()
  match parsed.body() {
    Pattern(_) => ()
    Arrangement(_, _) => fail("expected pattern")
  }
}

///|
test "play source parses arrangement declaration and repeat marker" {
  let source = "bpm(96); // authored tempo\n" + play_source_song() + ".repeat()"
  let parsed = @mini.parse_play_source(source).unwrap()
  assert_eq(parsed.bpm(), 96.0)
  match parsed.body() {
    Arrangement(_, repeats) => assert_true(repeats)
    Pattern(_) => fail("expected arrangement")
  }
  let finite = @mini.parse_play_source(play_source_song()).unwrap()
  match finite.body() {
    Arrangement(_, repeats) => assert_false(repeats)
    Pattern(_) => fail("expected arrangement")
  }
}

///|
test "play source rejects empty and duplicate tempo declarations" {
  assert_true(@mini.parse_play_source("") is Err(_))
  assert_true(
    @mini.parse_play_source(
      "bpm(90); song(bpm(120),section(\"a\",1,s(\"bd\")),part(\"a1\",\"a\"))",
    )
    is Err(_),
  )
  assert_true(
    @mini.parse_play_source(
      "song(bpm(90),bpm(120),section(\"a\",1,s(\"bd\")),part(\"a1\",\"a\"))",
    )
    is Err(_),
  )
}

///|
test "bounded play source preserves ordinary musical output" {
  let source = "let beat = note(\"60 64\"); beat.fast(2)"
  let bounded = @mini.parse_play_source(
    source,
    max_query_span=Some(@pattern.Rational::new(2L, 45L)),
  ).unwrap()
  guard bounded.body() is Pattern(doc) else { fail("expected pattern") }
  let snapshot = doc.lower()
  let events = snapshot
    .pat()
    .query(
      @pattern.TimeSpan::new(
        @pattern.Rational::from_int(0),
        @pattern.Rational::from_int(1),
      ),
    )
  assert_eq(events.length(), 4)
  assert_eq(events[0].value.get("note"), Some(60.0))
  assert_eq(events[1].value.get("note"), Some(64.0))
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
      @mini.parse_play_source(
        source,
        max_query_span=Some(@pattern.Rational::new(2L, 45L)),
      )
      is Err(_),
    )
  }
}

///|
test "bounded play source prevents eager Euclidean allocation" {
  assert_true(
    @mini.parse_play_source(
      "s(\"bd(1,128)\")",
      max_query_span=Some(@pattern.Rational::new(2L, 45L)),
    )
    is Ok(_),
  )
  assert_true(
    @mini.parse_play_source(
      "s(\"bd(1,129)\")",
      max_query_span=Some(@pattern.Rational::new(2L, 45L)),
    )
    is Err(_),
  )
  assert_true(
    @mini.parse_play_source(
      "song(section(\"a\",1,s(\"bd(1,100000)\")),part(\"a1\",\"a\"))",
      max_query_span=Some(@pattern.Rational::new(2L, 45L)),
    )
    is Err(_),
  )
}

///|
test "bounded play source accounts for cumulative layers and repeated occurrences" {
  let layer = "note(\"60\").fast(1000)"
  assert_true(
    @mini.parse_play_source(
      layer,
      max_query_span=Some(@pattern.Rational::new(2L, 45L)),
    )
    is Ok(_),
  )
  let layers = Array::make(6, layer).join(" + ")
  assert_true(
    @mini.parse_play_source(
      layers,
      max_query_span=Some(@pattern.Rational::new(2L, 45L)),
    )
    is Err(_),
  )
  let song = "song(section(\"a\",1," +
    layer +
    "),part(\"a1\",\"a\"),part(\"a2\",\"a\"),part(\"a3\",\"a\"))"
  assert_true(
    @mini.parse_play_source(
      song,
      max_query_span=Some(@pattern.Rational::new(2L, 45L)),
    )
    is Ok(_),
  )
  assert_true(
    @mini.parse_play_source(
      song + ".repeat()",
      max_query_span=Some(@pattern.Rational::new(2L, 45L)),
    )
    is Err(_),
  )
}

///|
test "bounded play source rejects source size and recursive depth before parsing" {
  let span = Some(@pattern.Rational::new(2L, 45L))
  let oversized = "note(\"60\")" + Array::make(8192, " ").join("")
  assert_true(@mini.parse_play_source(oversized, max_query_span=span) is Err(_))
  let nested = Array::make(40, "(").join("") +
    "note(\"60\")" +
    Array::make(40, ")").join("")
  assert_true(@mini.parse_play_source(nested, max_query_span=span) is Err(_))
  let misleading_comment = "// " + Array::make(40, ")").join("") + "\n"
  assert_true(
    @mini.parse_play_source(misleading_comment + nested, max_query_span=span)
    is Err(_),
  )
  assert_true(
    @mini.parse_play_source("// ((( ignored\nnote(\"60\")", max_query_span=span)
    is Ok(_),
  )
}
