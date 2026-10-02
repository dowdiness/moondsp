///|
fn time_bench_rationals() -> Array[Rational] {
  [
    for i in 0..<128 => {
      Rational::new(
        Int64::from_int(i * 7919 % 100003 - 50001),
        Int64::from_int(i * 3571 % 997 + 1),
      )
    }
  ]
}

///|
test "bench/pattern-time/rational-identities" (b : @bench.T) {
  let values = time_bench_rationals()
  let other_values = [
    for i in 0..<values.length() => {
      Rational::new(
        Int64::from_int(i * 4567 % 997 + 1),
        Int64::from_int(i * 1237 % 991 + 1),
      )
    }
  ]
  let zeros = [ for _ in 0..<values.length() => Rational::from_int(0) ]
  let ones = [ for _ in 0..<values.length() => Rational::from_int(1) ]

  b.bench(name="add_zero", fn() {
    let mut checksum = 0L
    for i in 0..<values.length() {
      let value = values[i] + zeros[i]
      checksum += value.num + value.den
    }
    b.keep(checksum)
  })
  b.bench(name="sub_zero", fn() {
    let mut checksum = 0L
    for i in 0..<values.length() {
      let value = values[i] - zeros[i]
      checksum += value.num + value.den
    }
    b.keep(checksum)
  })
  b.bench(name="mul_positive_one", fn() {
    let mut checksum = 0L
    for i in 0..<values.length() {
      let value = values[i] * ones[i]
      checksum += value.num + value.den
    }
    b.keep(checksum)
  })
  b.bench(name="div_positive_one", fn() {
    let mut checksum = 0L
    for i in 0..<values.length() {
      let value = values[i] / ones[i]
      checksum += value.num + value.den
    }
    b.keep(checksum)
  })
  b.bench(name="add_non_identity", fn() {
    let mut checksum = 0L
    for i in 0..<values.length() {
      let value = values[i] + other_values[i]
      checksum += value.num + value.den
    }
    b.keep(checksum)
  })
  b.bench(name="mul_non_identity", fn() {
    let mut checksum = 0L
    for i in 0..<values.length() {
      let value = values[i] * other_values[i]
      checksum += value.num + value.den
    }
    b.keep(checksum)
  })
}

///|
test "bench/pattern-time/shift-intersection-identities" (b : @bench.T) {
  let spans = [
    for i in 0..<128 => {
      TimeSpan::new(
        Rational::new(Int64::from_int(i * 17), 23L),
        Rational::new(Int64::from_int(i * 17 + 11), 23L),
      )
    }
  ]
  let zero = Rational::from_int(0)
  let offset = Rational::new(7L, 13L)
  let events = [
    for i in 0..<spans.length() => {
      {
        whole: if i % 2 == 0 {
          Some(spans[i])
        } else {
          None
        },
        part: spans[i],
        value: i,
      }
    }
  ]
  let containers = [
    for i in 0..<spans.length() => {
      TimeSpan::new(
        Rational::new(Int64::from_int(i * 17 - 1), 23L),
        Rational::new(Int64::from_int(i * 17 + 12), 23L),
      )
    }
  ]
  let overlaps = [
    for i in 0..<spans.length() => {
      TimeSpan::new(
        Rational::new(Int64::from_int(i * 17 + 5), 23L),
        Rational::new(Int64::from_int(i * 17 + 15), 23L),
      )
    }
  ]

  b.bench(name="timespan_shift_zero", fn() {
    let mut checksum = 0L
    for span in spans {
      let shifted = span.shift(zero)
      checksum += shifted.begin.num + shifted.end_.num
    }
    b.keep(checksum)
  })
  b.bench(name="timespan_shift_nonzero", fn() {
    let mut checksum = 0L
    for span in spans {
      let shifted = span.shift(offset)
      checksum += shifted.begin.num + shifted.end_.num
    }
    b.keep(checksum)
  })
  b.bench(name="event_shift_zero", fn() {
    let mut checksum = 0L
    for event in events {
      let shifted = event.shift(zero)
      checksum += shifted.part.begin.num
      match shifted.whole {
        Some(whole) => checksum += whole.end_.num
        None => ()
      }
    }
    b.keep(checksum)
  })
  b.bench(name="event_shift_nonzero", fn() {
    let mut checksum = 0L
    for event in events {
      let shifted = event.shift(offset)
      checksum += shifted.part.begin.num
      match shifted.whole {
        Some(whole) => checksum += whole.end_.num
        None => ()
      }
    }
    b.keep(checksum)
  })
  b.bench(name="intersect_contained", fn() {
    let mut checksum = 0L
    for i in 0..<spans.length() {
      match spans[i].intersect(containers[i]) {
        Some(span) => checksum += span.begin.num + span.end_.num
        None => ()
      }
    }
    b.keep(checksum)
  })
  b.bench(name="intersect_partial_overlap", fn() {
    let mut checksum = 0L
    for i in 0..<spans.length() {
      match spans[i].intersect(overlaps[i]) {
        Some(span) => checksum += span.begin.num + span.end_.num
        None => ()
      }
    }
    b.keep(checksum)
  })
}
