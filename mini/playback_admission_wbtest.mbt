///|
test "query bounds cover phase edges full-cycle slots and future callbacks" {
  let sources = [
    "note(\"60*16 ~ 64(3,8)\").slow(2)", "note(\"60 64\").every(1000000,fast(16))",
    "chord(\"C G7\").jux(rev).gain(0.5)", "stack(note(\"60 64\").fast(3),note(\"67\").slow(2)).rev()",
  ]
  let starts = [
    @pattern.Rational::from_int(0),
    @pattern.Rational::new(999L, 1000L),
    @pattern.Rational::from_int(999999),
    @pattern.Rational::from_int(1000000),
  ]
  let widths = [
    @pattern.Rational::new(1L, 1000L),
    @pattern.Rational::new(1L, 8L),
  ]
  for source in sources {
    let parser = Parser(source)
    let syntax = parser.parse_syntax_expr()
    let admission = PlaybackAdmission(0.125)
    let work = admission.expression(syntax)
    let pat = compile_mini_pattern(resolve_mini_expr(syntax, parser.bindings))
    for start in starts {
      for width in widths {
        let events = pat.query(@pattern.TimeSpan::new(start, start + width))
        assert_true(
          events.length().to_double() <= work.estimate(width.to_double()).events,
        )
      }
    }
  }
}

///|
test "notation modifier chains and exact time factor growth reject before lowering" {
  let span = Some(@pattern.Rational::new(2L, 45L))
  let source = "note(\"60" + Array::make(1000, "*1").join("") + "\")"
  assert_true(parse_play_source(source, max_query_span=span) is Err(_))
  assert_true(
    parse_play_source("note(\"60/1000000000/1000000000\")", max_query_span=span)
    is Err(_),
  )
  let masked = "note(\"60" + Array::make(8, "*1000000000").join("") + "(0,1)\")"
  assert_true(parse_play_source(masked, max_query_span=span) is Err(_))
}

///|
test "replacement tail contributes its own query work at playback admission" {
  let span = Some(@pattern.Rational::new(1L, 8L))
  match
    parse_play_source(
      "note(\"C4\").slow(4).tail(note(\"E4*4\"))",
      max_query_span=span,
    ) {
    Ok(_) => ()
    Err(message) => fail(message)
  }
  assert_true(
    parse_play_source(
      "note(\"C4\").slow(4).tail(note(\"E4*4096\"))",
      max_query_span=span,
    )
    is Err(_),
  )
}

///|
test "block comments cannot hide recursive syntax from playback admission" {
  let span = Some(@pattern.Rational::new(2L, 45L))
  for depth in [40, 2000] {
    let source = "/* // */ " +
      Array::make(depth, "(").join("") +
      "note(\"60\")" +
      Array::make(depth, ")").join("")
    assert_true(parse_play_source(source, max_query_span=span) is Err(_))
  }
  let harmless = "/* " + Array::make(40, "(\"//").join("") + " */ note(\"60\")"
  assert_true(parse_play_source(harmless, max_query_span=span) is Ok(_))
}

///|
test "unterminated comments never publish a valid source prefix" {
  for suffix in ["/*", "/* ", "/* x"] {
    let source = "bpm(120); note(\"64\") " + suffix
    assert_true(parse_play_source(source) is Err(_))
    assert_true(
      parse_play_source(
        source,
        max_query_span=Some(@pattern.Rational::new(2L, 45L)),
      )
      is Err(_),
    )
    assert_true(parse("note(\"64\") " + suffix) is Err(_))
    assert_true(parse_doc("note(\"64\") " + suffix) is Err(_))
  }
}

///|
test "bounded recursive descent rejects depth without relying on the pre-scan" {
  let source = Array::make(2000, "(").join("") +
    "note(\"60\")" +
    Array::make(2000, ")").join("")
  let parser = Parser(source, admission=Some(PlaybackAdmission(0.125)))
  let rejected = try parser.parse_syntax_expr() catch {
    ParseError(_) => true
  } noraise {
    _ => false
  }
  assert_true(rejected)
}

///|
test "generated transform compositions respect estimated events and preserve output" {
  let atoms = [
    "note(\"60 64\")", "note(\"60*2 ~\")", "chord(\"C G7\").slow(2)", "stack(note(\"60\"),note(\"67\"))",
  ]
  let transforms = [
    ".fast(2)", ".slow(2)", ".rev()", ".every(3,fast(2))", ".jux(rev)", ".gain(0.5)",
    ".gate(0.5)", ".lpf(1200,0.7)",
  ]
  let starts = [
    @pattern.Rational::new(-1L, 16L),
    @pattern.Rational::new(999L, 1000L),
    @pattern.Rational::from_int(3),
    @pattern.Rational::from_int(1000000),
  ]
  let widths = [
    @pattern.Rational::new(1L, 1000L),
    @pattern.Rational::new(1L, 8L),
  ]
  for atom in atoms {
    for first in transforms {
      for second in transforms {
        let source = atom + first + second
        let parser = Parser(source)
        let syntax = parser.parse_syntax_expr()
        let admission = PlaybackAdmission(0.125)
        let work = admission.expression(syntax)
        let ordinary = parse(source).unwrap()
        let bounded = parse_play_source(
          source,
          max_query_span=Some(@pattern.Rational::new(1L, 8L)),
        ).unwrap()
        guard bounded.body() is Pattern(doc) else { fail("expected pattern") }
        let snapshot = doc.lower()
        for start in starts {
          for width in widths {
            let arc = @pattern.TimeSpan::new(start, start + width)
            let events = ordinary.query(arc)
            assert_true(
              events.length().to_double() <=
              work.estimate(width.to_double()).events,
            )
            assert_eq(
              snapshot.pat().query(arc).map(event => event.to_string()),
              events.map(event => event.to_string()),
            )
          }
        }
      }
    }
  }
}
