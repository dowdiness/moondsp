///|
test "s_lpf and s_hpf carry cutoff and resonance on one event" {
  let lpf = @pattern.s_lpf(800.0, resonance=2.0).query(span(0, 1, 1, 1))
  let hpf = @pattern.s_hpf(120.0).query(span(0, 1, 1, 1))
  @debug.assert_eq(lpf.length(), 1)
  @debug.assert_eq(lpf[0].value.get(LpfResonance), Some(2.0))
  @debug.assert_eq(hpf[0].value.get(HpfResonance), None)
  let merged = @pattern.controls(
    @pattern.ControlMap::single(Note, 60.0)
    .merge(lpf[0].value)
    .set(Hpf, 120.0)
    .set(HpfResonance, 0.5),
  )
  let events = merged.query(span(0, 1, 1, 1))
  @debug.assert_eq(events.length(), 1)
  @debug.assert_eq(events[0].value.get(Note), Some(60.0))
  @debug.assert_eq(events[0].value.get(Lpf), Some(800.0))
  @debug.assert_eq(events[0].value.get(LpfResonance), Some(2.0))
  @debug.assert_eq(events[0].value.get(Hpf), Some(120.0))
  @debug.assert_eq(events[0].value.get(HpfResonance), Some(0.5))
}

///|
test "jux(rev): event count and pan keys" {
  let pat = @pattern.sequence([
    @pattern.control(Note, 36.0),
    @pattern.control(Note, 38.0),
  ])
  let result = pat.jux(fn(p) { p.rev() })
  let events = result.query(span(0, 1, 1, 1))
  @debug.assert_eq(events.length(), 4)
  let (pan_neg1, pan_pos1) = for ev in events; neg = 0, pos = 0 {
    match ev.value.get(Pan) {
      Some(-1.0) => continue neg + 1, pos
      Some(1.0) => continue neg, pos + 1
      _ => continue neg, pos
    }
  } nobreak {
    (neg, pos)
  }
  @debug.assert_eq(pan_neg1, 2)
  @debug.assert_eq(pan_pos1, 2)
}

///|
test "jux(rev): channel identity (pan=-1 matches self, pan=+1 matches f(self))" {
  // Use a multi-key pattern so the comparison loop catches any bug that
  // drops a control key while routing through merge_control. Without
  // a non-pan secondary key, the test only proves part+sound parity.
  let pat = @pattern.sequence([
    @pattern.controls(@pattern.ControlMap::single(Note, 36.0).set(Lpf, 800.0)),
    @pattern.controls(@pattern.ControlMap::single(Note, 38.0).set(Lpf, 800.0)),
  ])
  let result = pat.jux(fn(p) { p.rev() })
  let arc = span(0, 1, 1, 1)
  let combined = result.query(arc)
  let self_events = pat.query(arc)
  let f_events = pat.rev().query(arc)
  // Filter combined by pan key
  let left : Array[@pattern.Event[@pattern.ControlMap]] = []
  let right : Array[@pattern.Event[@pattern.ControlMap]] = []
  for ev in combined {
    match ev.value.get(Pan) {
      Some(-1.0) => left.push(ev)
      Some(1.0) => right.push(ev)
      _ => ()
    }
  }
  // Compare key-by-key for sound and lpf (every non-pan key from
  // the input). If jux drops or mangles either one, this fails.
  @debug.assert_eq(left.length(), self_events.length())
  for i in 0..<left.length() {
    @debug.assert_eq(left[i].part, self_events[i].part)
    @debug.assert_eq(left[i].value.get(Note), self_events[i].value.get(Note))
    @debug.assert_eq(left[i].value.get(Lpf), self_events[i].value.get(Lpf))
  }
  @debug.assert_eq(right.length(), f_events.length())
  for i in 0..<right.length() {
    @debug.assert_eq(right[i].part, f_events[i].part)
    @debug.assert_eq(right[i].value.get(Note), f_events[i].value.get(Note))
    @debug.assert_eq(right[i].value.get(Lpf), f_events[i].value.get(Lpf))
  }
}

///|
test "jux: overrides pre-existing pan" {
  // Pre-pan to 0.5, then jux — result should have only ±1 pan values.
  let pat = @pattern.controls(
    @pattern.ControlMap::single(Note, 36.0).set(Pan, 0.5),
  )
  let result = pat.jux(fn(p) { p.rev() })
  let events = result.query(span(0, 1, 1, 1))
  // Guard against a vacuously-passing empty result.
  @debug.assert_eq(events.length(), 2)
  for ev in events {
    let p = ev.value.get(Pan)
    let is_pm1 = p == Some(-1.0) || p == Some(1.0)
    assert_true(is_pm1)
  }
}

///|
test "jux(fast(2)): right channel doubles event count" {
  let pat = @pattern.sequence([
    @pattern.control(Note, 36.0),
    @pattern.control(Note, 38.0),
  ])
  let result = pat.jux(fn(p) { p.fast(@pattern.Rational::from_int(2)) })
  let events = result.query(span(0, 1, 1, 1))
  // Left: 2 events. Right: fast(2) of 2-event = 4 events. Total 6.
  @debug.assert_eq(events.length(), 6)
}

///|
test "deliverable: sequence c3 e3 g3 fast 2 produces 6 events" {
  let pat = @pattern.sequence([
    @pattern.control(Note, 48.0),
    @pattern.control(Note, 52.0),
    @pattern.control(Note, 55.0),
  ]).fast(@pattern.Rational::from_int(2))
  let events = pat.query(span(0, 1, 1, 1))
  @debug.assert_eq(events.length(), 6)
  // First half: c3 e3 g3 in [0, 1/2)
  @debug.assert_eq(events[0].value.get(Note), Some(48.0))
  @debug.assert_eq(events[1].value.get(Note), Some(52.0))
  @debug.assert_eq(events[2].value.get(Note), Some(55.0))
  // Second half: c3 e3 g3 in [1/2, 1)
  @debug.assert_eq(events[3].value.get(Note), Some(48.0))
  @debug.assert_eq(events[4].value.get(Note), Some(52.0))
  @debug.assert_eq(events[5].value.get(Note), Some(55.0))
  // Verify rational time boundaries
  @debug.assert_eq(events[0].part.begin, @pattern.Rational(0L, 1L))
  @debug.assert_eq(events[0].part.end_, @pattern.Rational(1L, 6L))
  @debug.assert_eq(events[5].part.begin, @pattern.Rational(5L, 6L))
  @debug.assert_eq(events[5].part.end_, @pattern.Rational(1L, 1L))
}
