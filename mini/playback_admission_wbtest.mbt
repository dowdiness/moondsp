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
