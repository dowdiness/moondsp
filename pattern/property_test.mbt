///|
fn r_prop(num : Int, den : Int) -> Rational {
  Rational::new(Int64::from_int(num), Int64::from_int(den))
}

///|
fn span_prop(b_num : Int, b_den : Int, e_num : Int, e_den : Int) -> TimeSpan {
  TimeSpan::new(r_prop(b_num, b_den), r_prop(e_num, e_den))
}

///|
fn events_equal(a : Array[Event[Int]], b : Array[Event[Int]]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i = 0; i < a.length(); i = i + 1 {
    if a[i].part.begin != b[i].part.begin {
      return false
    }
    if a[i].part.end_ != b[i].part.end_ {
      return false
    }
    if a[i].value != b[i].value {
      return false
    }
    match (a[i].whole, b[i].whole) {
      (Some(wa), Some(wb)) =>
        if wa.begin != wb.begin || wa.end_ != wb.end_ {
          return false
        }
      (None, None) => ()
      _ => return false
    }
  }
  true
}

///|
// Law 1: fast(a, fast(b, pat)) == fast(a*b, pat)
// Associativity of time scaling.
test "prop: fast(a, fast(b, pat)) == fast(a*b, pat)" {
  @qc.quick_check_fn(
    fn(pair : (Int, Int)) {
      let a_raw = pair.0.abs() % 7 + 1
      let b_raw = pair.1.abs() % 7 + 1
      let a = Rational::from_int(a_raw)
      let b = Rational::from_int(b_raw)
      let pat = Pat::pure(42)
      let lhs = pat.fast(a).fast(b)
      let rhs = pat.fast(a * b)
      let arc = span_prop(0, 1, 1, 1)
      let lhs_events = lhs.query(arc)
      let rhs_events = rhs.query(arc)
      events_equal(lhs_events, rhs_events)
    },
    max_success=100,
  )
}

///|
// Law 2: slow(n, pat) == fast(1/n, pat)
// Slow is the inverse of fast.
test "prop: slow(n, pat) == fast(1/n, pat)" {
  @qc.quick_check_fn(
    fn(n_raw : Int) {
      let n_val = n_raw.abs() % 7 + 1
      let n = Rational::from_int(n_val)
      let inv_n = Rational::new(1L, Int64::from_int(n_val))
      let pat = Pat::pure(42)
      let lhs = pat.slow(n)
      let rhs = pat.fast(inv_n)
      let arc = span_prop(0, 1, 1, 1)
      events_equal(lhs.query(arc), rhs.query(arc))
    },
    max_success=100,
  )
}

///|
// Law 3: fast(1, pat) == pat
// Identity: speed factor 1 changes nothing.
test "prop: fast(1, pat) == pat" {
  @qc.quick_check_fn(
    fn(value : Int) {
      let v = value.abs() % 1000
      let pat = Pat::pure(v)
      let lhs = pat.fast(Rational::from_int(1))
      let arc = span_prop(0, 1, 1, 1)
      events_equal(lhs.query(arc), pat.query(arc))
    },
    max_success=100,
  )
}

///|
// Law 4: rev(rev(pat)) == pat
// Double reversal is identity.
test "prop: rev(rev(pat)) == pat" {
  @qc.quick_check_fn(
    fn(value : Int) {
      let v = value.abs() % 1000
      let pat = Pat::pure(v)
      let double_rev = pat.rev().rev()
      let arc = span_prop(0, 1, 1, 1)
      events_equal(double_rev.query(arc), pat.query(arc))
    },
    max_success=100,
  )
}

///|
// Law 5: sequence of one element == fast(1, pat)
// A single-element sequence should be equivalent to the original pattern.
test "prop: sequence([pat]) == fast(1, pat)" {
  @qc.quick_check_fn(
    fn(value : Int) {
      let v = value.abs() % 1000
      let pat = Pat::pure(v)
      let seq1 = sequence([pat])
      let fast1 = pat.fast(Rational::from_int(1))
      let arc = span_prop(0, 1, 1, 1)
      events_equal(seq1.query(arc), fast1.query(arc))
    },
    max_success=100,
  )
}

///|
// Law 6: stack([pat]) == pat
// Stacking one pattern returns the same events.
test "prop: stack([pat]) == pat" {
  @qc.quick_check_fn(
    fn(value : Int) {
      let v = value.abs() % 1000
      let pat = Pat::pure(v)
      let stacked = stack([pat])
      let arc = span_prop(0, 1, 1, 1)
      events_equal(stacked.query(arc), pat.query(arc))
    },
    max_success=100,
  )
}

///|
// Law 7: silence produces no events for any arc
// For any begin < end, silence returns empty.
test "prop: silence produces no events for any arc" {
  @qc.quick_check_fn(
    fn(pair : (Int, Int)) {
      let b = pair.0.abs() % 10
      let len = pair.1.abs() % 5 + 1
      let e = b + len
      let arc = span_prop(b, 1, e, 1)
      let s : Pat[Int] = Pat::silence()
      s.query(arc).length() == 0
    },
    max_success=100,
  )
}

///|
// Law 8: pure value count matches cycle count
// For a query spanning N cycles, pure produces exactly N events.
test "prop: pure produces exactly N events for N-cycle query" {
  @qc.quick_check_fn(
    fn(n_raw : Int) {
      let n = n_raw.abs() % 8 + 1
      let pat = Pat::pure(42)
      let arc = span_prop(0, 1, n, 1)
      pat.query(arc).length() == n
    },
    max_success=100,
  )
}

// ---- Stronger tests using non-pure patterns and non-integer factors ----

///|
// Law 9: fast(a, fast(b, sequence)) == fast(a*b, sequence) over multi-cycle
// Tests fast associativity with a real sequence, not just pure, over 2 cycles.
test "prop: fast associativity with sequence over multi-cycle" {
  @qc.quick_check_fn(
    fn(pair : (Int, Int)) {
      let a_raw = pair.0.abs() % 4 + 1
      let b_raw = pair.1.abs() % 4 + 1
      let a = Rational::from_int(a_raw)
      let b = Rational::from_int(b_raw)
      let pat = sequence([Pat::pure(1), Pat::pure(2), Pat::pure(3)])
      let lhs = pat.fast(a).fast(b)
      let rhs = pat.fast(a * b)
      let arc = span_prop(0, 1, 2, 1) // 2 cycles
      events_equal(lhs.query(arc), rhs.query(arc))
    },
    max_success=50,
  )
}

///|
// Law 10: rev(rev(sequence)) == sequence over multi-cycle
// Double reversal of a sequence preserves event order across cycles.
test "prop: rev(rev(sequence)) is identity over multi-cycle" {
  @qc.quick_check_fn(
    fn(n_raw : Int) {
      let n = n_raw.abs() % 5 + 2 // 2..6 elements
      let pats : Array[Pat[Int]] = []
      for i = 0; i < n; i = i + 1 {
        pats.push(Pat::pure(i))
      }
      let pat = sequence(pats)
      let double_rev = pat.rev().rev()
      let arc = span_prop(0, 1, 2, 1) // 2 cycles
      events_equal(double_rev.query(arc), pat.query(arc))
    },
    max_success=50,
  )
}

///|
// Law 11: fast with non-integer factor preserves event count correctly
// fast(3/2, pure) over [0, 1) should produce 2 events (ceil(3/2) = 2 cycles in inner time)
test "fast with non-integer factor 3/2" {
  let pat = Pat::pure(42)
  let fast_pat = pat.fast(r_prop(3, 2))
  let events = fast_pat.query(span_prop(0, 1, 1, 1))
  // Inner query is [0, 3/2) which spans 2 cycles → 2 events
  @debug.assert_eq(events.length(), 2)
  // First event: whole [0, 2/3), part [0, 2/3)
  @debug.assert_eq(events[0].part.begin, r_prop(0, 1))
  @debug.assert_eq(events[0].part.end_, r_prop(2, 3))
  // Second event: whole [2/3, 4/3) but part clipped to [2/3, 1)
  @debug.assert_eq(events[1].part.begin, r_prop(2, 3))
  @debug.assert_eq(events[1].part.end_, r_prop(1, 1))
}

///|
// Law 12: sequence queried over partial multi-cycle arc [1/2, 3/2)
test "sequence over partial multi-cycle arc" {
  let pat = sequence([Pat::pure(1), Pat::pure(2)])
  let events = pat.query(span_prop(1, 2, 3, 2))
  // Cycle 0 portion [1/2, 1): slot 1 (value 2) occupies [1/2, 1)
  // Cycle 1 portion [1, 3/2): slot 0 (value 1) occupies [1, 3/2)
  @debug.assert_eq(events.length(), 2)
  @debug.assert_eq(events[0].value, 2)
  @debug.assert_eq(events[1].value, 1)
}

///|
// Law 13: rev(sequence([a, b, c])) reverses time positions within each cycle
// WHY array order differs from time order: rev mirrors event positions but
// the array preserves the inner query's enumeration order. We check that
// the value at the LATEST time position is what was originally FIRST.
test "rev of sequence reverses correctly" {
  let pat = sequence([Pat::pure(1), Pat::pure(2), Pat::pure(3)]).rev()
  let events = pat.query(span_prop(0, 1, 1, 1))
  @debug.assert_eq(events.length(), 3)
  // Events are in inner-query order (1, 2, 3) but their time positions
  // are mirrored: value 1 is now at [2/3, 1), value 3 is at [0, 1/3)
  // Find the event at position [0, 1/3) — it should have value 3
  let mut first_pos_value = 0
  for ev in events {
    if ev.part.begin == r_prop(0, 1) {
      first_pos_value = ev.value
    }
  }
  @debug.assert_eq(first_pos_value, 3)
  // Find the event at position [2/3, 1) — it should have value 1
  let mut last_pos_value = 0
  for ev in events {
    if ev.part.begin == r_prop(2, 3) {
      last_pos_value = ev.value
    }
  }
  @debug.assert_eq(last_pos_value, 1)
}
