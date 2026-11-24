///|
test "query bounds cover phase edges full-cycle slots and future callbacks" {
  let sources = [
    "note(\"60*16 ~ 64(3,8)\").slow(2)", "note(\"60 64\").every(1000000,fast(16))",
    "chord(\"C G7\").jux(rev).gain(0.5)", "stack(note(\"60 64\").fast(3),note(\"67\").slow(2)).rev()",
  ]
  let starts = [
    @pattern.Rational::from_int(0),
    @pattern.Rational(999L, 1000L),
    @pattern.Rational::from_int(999999),
    @pattern.Rational::from_int(1000000),
  ]
  let widths = [@pattern.Rational(1L, 1000L), @pattern.Rational(1L, 8L)]
  for source in sources {
    let parser = Parser(source)
    let syntax = resolve_mini_expr(parser.parse_syntax_expr(), parser.bindings)
    let admission = PlaybackAdmission(0.125)
    let work = admission.expression(syntax)
    let pat = compile_mini_doc(syntax, MiniDocBuilder()).lower().pat()
    for start in starts {
      for width in widths {
        let events = pat.query(@pattern.TimeSpan(start, start + width))
        assert_true(
          events.length().to_double() <= work.estimate(width.to_double()).events,
        )
      }
    }
  }
}

///|
test "notation modifier chains and exact time factor growth reject before lowering" {
  let window = calibrated_window()
  let source = "note(\"60" + Array::make(1000, "*1").join("") + "\")"
  assert_true(parse_play_source(source, query_window=window) is Err(_))
  assert_true(
    parse_play_source("note(\"60/1000000000/1000000000\")", query_window=window)
    is Err(_),
  )
  let masked = "note(\"60" + Array::make(8, "*1000000000").join("") + "(0,1)\")"
  assert_true(parse_play_source(masked, query_window=window) is Err(_))
}

///|
test "block comments cannot hide recursive syntax from playback admission" {
  let window = calibrated_window()
  for depth in [40, 2000] {
    let source = "/* // */ " +
      Array::make(depth, "(").join("") +
      "note(\"60\")" +
      Array::make(depth, ")").join("")
    assert_true(parse_play_source(source, query_window=window) is Err(_))
  }
  let harmless = "/* " + Array::make(40, "(\"//").join("") + " */ note(\"60\")"
  assert_true(parse_play_source(harmless, query_window=window) is Ok(_))
}

///|
test "unterminated comments never publish a valid source prefix" {
  for suffix in ["/*", "/* ", "/* x"] {
    let source = "bpm(120); note(\"64\") " + suffix
    assert_true(parse_play_source(source) is Err(_))
    assert_true(
      parse_play_source(source, query_window=calibrated_window()) is Err(_),
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
    problem => problem == OverLimit(Nesting(32))
  } noraise {
    _ => false
  }
  assert_true(rejected)
}

///|
/// An event with its controls in key order: which merge set a key first
/// does not change the event.
fn admission_event_text(event : @pattern.Event[@score.ScoreEvent]) -> String {
  let controls = [
    match event.value.sound {
      Hit(drum) => "hit=\{drum.name()}"
      Note(instrument, pitch~) => "\{instrument.name()}=\{pitch}"
    },
  ]
  event.value.controls.each((key, value) => controls.push("\{key}=\{value}"))
  controls.sort()
  let whole = match event.whole {
    Some(span) => span.to_string()
    None => "-"
  }
  "\{whole} \{event.part} \{controls.join(",")}"
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
    @pattern.Rational(-1L, 16L),
    @pattern.Rational(999L, 1000L),
    @pattern.Rational::from_int(3),
    @pattern.Rational::from_int(1000000),
  ]
  let widths = [@pattern.Rational(1L, 1000L), @pattern.Rational(1L, 8L)]
  for atom in atoms {
    for first in transforms {
      for second in transforms {
        let source = atom + first + second
        let parser = Parser(source)
        let syntax = resolve_mini_expr(
          parser.parse_syntax_expr(),
          parser.bindings,
        )
        let admission = PlaybackAdmission(0.125)
        let work = admission.expression(syntax)
        let ordinary = parse(source).unwrap()
        let bounded = parse_play_source(
          source,
          query_window=@pattern.QueryWindow::from_span(
            @pattern.Rational(1L, 8L),
          ).unwrap(),
        ).unwrap()
        guard bounded.body() is Pattern(doc) else { fail("expected pattern") }
        let snapshot = doc.lower()
        for start in starts {
          for width in widths {
            let arc = @pattern.TimeSpan(start, start + width)
            let events = ordinary.query(arc)
            assert_true(
              events.length().to_double() <=
              work.estimate(width.to_double()).events,
            )
            assert_eq(
              snapshot.pat().query(arc).map(admission_event_text),
              events.map(admission_event_text),
            )
          }
        }
      }
    }
  }
}

///|
test "sequential song sections are admitted one occurrence at a time" {
  let window = @pattern.QueryWindow::from_span(@pattern.Rational::from_int(1)).unwrap()
  let sections = [
    for name in ["bd", "sd", "hh", "cp", "oh"] => {
      "section(\"\{name}\",4,s(\"\{name}*64\"))"
    }
  ]
  let parts = [
    for name in ["bd", "sd", "hh", "cp", "oh"] => {
      "part(\"p\{name}\",\"\{name}\")"
    }
  ]
  let song = "song(" + sections.join(",") + "," + parts.join(",") + ")"
  assert_true(parse_play_source(song, query_window=window) is Ok(_))
  let draft = Draft(song)
  assert_true(draft.check_playback_within(window).diagnostic() is None)
  guard draft.prepare_playback() is Ok(input) else { fail("prepare") }
  assert_true(input.compile(query_window=window) is Ok(_))
  // Occurrences that sound together are still bounded together.
  let layered = "song(" +
    sections.join(",") +
    "," +
    parts.map(part => part.replace(old=")", new=",0)")).join(",") +
    ")"
  assert_true(
    parse_play_source(layered, query_window=window)
    is Err(OverLimit(ArrangementExpansion)),
  )
  // The editor reports the player's rejection before Play is pressed.
  guard draft.edit(
      EditTransaction(base=draft.state().version(), edits=[
        TextEdit(from=0, to=song.length(), inserted=layered),
      ]),
    )
    is Ok(state) else {
    fail("edit")
  }
  guard state.diagnostic() is Some(diagnostic) else {
    fail("expected admission diagnostic")
  }
  assert_eq(diagnostic.problem(), OverLimit(ArrangementExpansion))
  assert_true(draft.prepare_playback() is Err(_))
  // A Draft that learns its player later reports the same, at the same version.
  let late = Draft(layered)
  let unchecked = late.state()
  assert_true(unchecked.diagnostic() is None)
  let checked = late.check_playback_within(window)
  assert_eq(checked.version(), unchecked.version())
  assert_true(checked.diagnostic() is Some(_))
  assert_true(late.prepare_playback() is Err(_))
}

///|
/// The 2/45-cycle window these admission bounds are calibrated against.
fn calibrated_window() -> @pattern.QueryWindow {
  @pattern.QueryWindow::from_span(@pattern.Rational(2L, 45L)).unwrap()
}
