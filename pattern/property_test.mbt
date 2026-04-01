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
