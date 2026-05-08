///|
test "note_name c3 = 48" {
  let pat = note_name("c3")
  let events = pat.query(span(0, 1, 1, 1))
  assert_eq(events[0].value.0.get("note"), Some(48.0))
}

///|
test "note_name e3 = 52" {
  let pat = note_name("e3")
  let events = pat.query(span(0, 1, 1, 1))
  assert_eq(events[0].value.0.get("note"), Some(52.0))
}

///|
test "note_name g3 = 55" {
  let pat = note_name("g3")
  let events = pat.query(span(0, 1, 1, 1))
  assert_eq(events[0].value.0.get("note"), Some(55.0))
}

///|
test "note_name fs4 = 66" {
  let pat = note_name("fs4")
  let events = pat.query(span(0, 1, 1, 1))
  assert_eq(events[0].value.0.get("note"), Some(66.0))
}

///|
test "note_name a4 = 69" {
  let pat = note_name("a4")
  let events = pat.query(span(0, 1, 1, 1))
  assert_eq(events[0].value.0.get("note"), Some(69.0))
}

///|
test "merge_control combines note and cutoff" {
  let merged = merge_control(note(60.0), s_cutoff(800.0))
  let events = merged.query(span(0, 1, 1, 1))
  assert_eq(events.length(), 1)
  assert_eq(events[0].value.0.get("note"), Some(60.0))
  assert_eq(events[0].value.0.get("cutoff"), Some(800.0))
}

///|
test "merge_control right-biased on conflict" {
  let a = note(60.0)
  let b = note(72.0)
  let merged = merge_control(a, b)
  let events = merged.query(span(0, 1, 1, 1))
  assert_eq(events[0].value.0.get("note"), Some(72.0))
}

///|
test "jux(rev): event count and pan keys" {
  let pat = sequence([sound(36.0), sound(38.0)])
  let result = pat.jux(fn(p) { p.rev() })
  let events = result.query(span(0, 1, 1, 1))
  assert_eq(events.length(), 4)
  let mut pan_neg1 = 0
  let mut pan_pos1 = 0
  for ev in events {
    match ev.value.0.get("pan") {
      Some(-1.0) => pan_neg1 += 1
      Some(1.0) => pan_pos1 += 1
      _ => ()
    }
  }
  assert_eq(pan_neg1, 2)
  assert_eq(pan_pos1, 2)
}

///|
test "jux(rev): channel identity (pan=-1 matches self, pan=+1 matches f(self))" {
  // Use a multi-key pattern so the comparison loop catches any bug that
  // drops a control key while routing through merge_control. Without
  // a non-pan secondary key, the test only proves part+sound parity.
  let pat = merge_control(sequence([sound(36.0), sound(38.0)]), s_cutoff(800.0))
  let result = pat.jux(fn(p) { p.rev() })
  let arc = span(0, 1, 1, 1)
  let combined = result.query(arc)
  let self_events = pat.query(arc)
  let f_events = pat.rev().query(arc)
  // Filter combined by pan key
  let left : Array[Event[ControlMap]] = []
  let right : Array[Event[ControlMap]] = []
  for ev in combined {
    match ev.value.0.get("pan") {
      Some(-1.0) => left.push(ev)
      Some(1.0) => right.push(ev)
      _ => ()
    }
  }
  // Compare key-by-key for sound and cutoff (every non-pan key from
  // the input). If jux drops or mangles any of them, this fails.
  assert_eq(left.length(), self_events.length())
  for i in 0..<left.length() {
    assert_eq(left[i].part, self_events[i].part)
    assert_eq(left[i].value.0.get("sound"), self_events[i].value.0.get("sound"))
    assert_eq(
      left[i].value.0.get("cutoff"),
      self_events[i].value.0.get("cutoff"),
    )
  }
  assert_eq(right.length(), f_events.length())
  for i in 0..<right.length() {
    assert_eq(right[i].part, f_events[i].part)
    assert_eq(right[i].value.0.get("sound"), f_events[i].value.0.get("sound"))
    assert_eq(right[i].value.0.get("cutoff"), f_events[i].value.0.get("cutoff"))
  }
}

///|
test "jux: overrides pre-existing pan" {
  // Pre-pan to 0.5, then jux — result should have only ±1 pan values.
  let pat = merge_control(sound(36.0), s_pan(0.5))
  let result = pat.jux(fn(p) { p.rev() })
  let events = result.query(span(0, 1, 1, 1))
  // Guard against a vacuously-passing empty result.
  assert_eq(events.length(), 2)
  for ev in events {
    let p = ev.value.0.get("pan")
    let is_pm1 = p == Some(-1.0) || p == Some(1.0)
    assert_true(is_pm1)
  }
}

///|
test "jux(fast(2)): right channel doubles event count" {
  let pat = sequence([sound(36.0), sound(38.0)])
  let result = pat.jux(fn(p) { p.fast(Rational::from_int(2)) })
  let events = result.query(span(0, 1, 1, 1))
  // Left: 2 events. Right: fast(2) of 2-event = 4 events. Total 6.
  assert_eq(events.length(), 6)
}

///|
test "note_name bf4 = 70 (B-flat)" {
  let pat = note_name("bf4")
  let events = pat.query(span(0, 1, 1, 1))
  assert_eq(events[0].value.0.get("note"), Some(70.0))
}

///|
test "note_name ef3 = 51 (E-flat)" {
  let pat = note_name("ef3")
  let events = pat.query(span(0, 1, 1, 1))
  assert_eq(events[0].value.0.get("note"), Some(51.0))
}

///|
test "note_name f4 = 65 (F natural, not flat)" {
  let pat = note_name("f4")
  let events = pat.query(span(0, 1, 1, 1))
  assert_eq(events[0].value.0.get("note"), Some(65.0))
}

///|
test "note_name cs3 = 49 (C-sharp)" {
  let pat = note_name("cs3")
  let events = pat.query(span(0, 1, 1, 1))
  assert_eq(events[0].value.0.get("note"), Some(49.0))
}

///|
test "deliverable: sequence c3 e3 g3 fast 2 produces 6 events" {
  let pat = sequence([note_name("c3"), note_name("e3"), note_name("g3")]).fast(
    Rational::from_int(2),
  )
  let events = pat.query(span(0, 1, 1, 1))
  assert_eq(events.length(), 6)
  // First half: c3 e3 g3 in [0, 1/2)
  assert_eq(events[0].value.0.get("note"), Some(48.0))
  assert_eq(events[1].value.0.get("note"), Some(52.0))
  assert_eq(events[2].value.0.get("note"), Some(55.0))
  // Second half: c3 e3 g3 in [1/2, 1)
  assert_eq(events[3].value.0.get("note"), Some(48.0))
  assert_eq(events[4].value.0.get("note"), Some(52.0))
  assert_eq(events[5].value.0.get("note"), Some(55.0))
  // Verify rational time boundaries
  assert_eq(events[0].part.begin, Rational::new(0L, 1L))
  assert_eq(events[0].part.end_, Rational::new(1L, 6L))
  assert_eq(events[5].part.begin, Rational::new(5L, 6L))
  assert_eq(events[5].part.end_, Rational::new(1L, 1L))
}
