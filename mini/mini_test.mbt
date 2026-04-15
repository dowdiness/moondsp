///|
test "drum_midi returns correct GM numbers" {
  inspect(@mini.drum_midi("bd"), content="Some(36)")
  inspect(@mini.drum_midi("sd"), content="Some(38)")
  inspect(@mini.drum_midi("hh"), content="Some(42)")
}

///|
test "drum_midi returns None for unknown names" {
  inspect(@mini.drum_midi("snare"), content="None")
  inspect(@mini.drum_midi(""), content="None")
  inspect(@mini.drum_midi("123"), content="None")
}

///|
/// Query a pattern over one cycle [0, 1) and return events.
fn query_one_cycle(
  pat : @pattern.Pat[@pattern.ControlMap],
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  pat.query(arc)
}

///|
/// Unwrap an Ok result or fail the test.
fn unwrap_ok(
  result : Result[@pattern.Pat[@pattern.ControlMap], String],
) -> @pattern.Pat[@pattern.ControlMap] {
  match result {
    Ok(pat) => pat
    Err(msg) => abort("expected Ok, got Err(\{msg})")
  }
}

///|
test "parse single drum sound" {
  let pat = unwrap_ok(@mini.parse("s(\"bd\")"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="1")
  inspect(
    events[0].value,
    content=(
      #|ControlMap({"sound": 36})
    ),
  )
}

///|
test "parse drum sequence" {
  let pat = unwrap_ok(@mini.parse("s(\"bd sd hh sd\")"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="4")
}

///|
test "parse note sequence" {
  let pat = unwrap_ok(@mini.parse("note(\"60 64 67\")"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="3")
  inspect(
    events[0].value,
    content=(
      #|ControlMap({"note": 60})
    ),
  )
  inspect(
    events[1].value,
    content=(
      #|ControlMap({"note": 64})
    ),
  )
  inspect(
    events[2].value,
    content=(
      #|ControlMap({"note": 67})
    ),
  )
}

///|
test "parse with fast method" {
  let pat = unwrap_ok(@mini.parse("s(\"bd sd\").fast(2)"))
  let events = query_one_cycle(pat)
  // fast(2) doubles the pattern, so 2 elements * 2 = 4 events
  inspect(events.length(), content="4")
}

///|
test "parse with sub-group brackets" {
  let pat = unwrap_ok(@mini.parse("s(\"bd [sd hh]\")"))
  let events = query_one_cycle(pat)
  // bd takes first half, [sd hh] takes second half (2 events in sub-group)
  inspect(events.length(), content="3")
}

///|
test "parse with stack (comma)" {
  let pat = unwrap_ok(@mini.parse("s(\"bd sd, hh hh hh\")"))
  let events = query_one_cycle(pat)
  // stack of [bd sd] (2 events) and [hh hh hh] (3 events) = 5 events
  inspect(events.length(), content="5")
}

///|
test "parse empty input returns error" {
  match @mini.parse("") {
    Err(msg) => inspect(msg, content="empty input")
    Ok(_) => fail("expected Err, got Ok")
  }
}

///|
test "parse unknown primary returns error" {
  match @mini.parse("foo(\"bar\")") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err, got Ok")
  }
}

///|
test "parse fast(0) returns error" {
  match @mini.parse("s(\"bd\").fast(0)") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err, got Ok")
  }
}

///|
test "parse fast(-1) returns error" {
  match @mini.parse("s(\"bd\").fast(-1)") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err, got Ok")
  }
}

///|
test "parse unknown drum name returns error" {
  match @mini.parse("s(\"snare\")") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err, got Ok")
  }
}

///|
test "parse with slow method" {
  let pat = unwrap_ok(@mini.parse("s(\"bd sd\").slow(2)"))
  // slow(2) halves the speed, querying [0,1) sees only 1 event (first half of pattern)
  let events = query_one_cycle(pat)
  inspect(events.length(), content="1")
}

///|
test "parse with rev method" {
  let pat = unwrap_ok(@mini.parse("s(\"bd sd hh\").rev()"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="3")
  // Reversed: hh, sd, bd
  inspect(
    events[0].value,
    content=(
      #|ControlMap({"sound": 36})
    ),
  )
  inspect(
    events[1].value,
    content=(
      #|ControlMap({"sound": 38})
    ),
  )
  inspect(
    events[2].value,
    content=(
      #|ControlMap({"sound": 42})
    ),
  )
}
