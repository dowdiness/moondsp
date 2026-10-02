///|
test "bench/rational/construction" (b : @bench.T) {
  let small = Array::makei(128, index => {
    match index % 4 {
      0 | 2 => 0
      1 => 1
      _ => index - 64
    }
  })
  let general = Array::makei(128, index => index * 31 - 4096)
  let denominators = Array::makei(128, index => {
    let value = Int64::from_int(index * 7 + 3)
    if index % 2 == 0 {
      value
    } else {
      -value
    }
  })
  let fractions = Array::makei(128, index => {
    (Int64::from_int(index * 13 + 5), Int64::from_int(index * 17 + 9))
  })
  b.bench(name="from_int_small", fn() {
    for value in small {
      b.keep(Rational::from_int(value))
    }
  })
  b.bench(name="from_int_general", fn() {
    for value in general {
      b.keep(Rational::from_int(value))
    }
  })
  b.bench(name="normalize_zero", fn() {
    for den in denominators {
      b.keep(Rational::new(0L, den))
    }
  })
  b.bench(name="normalize_one", fn() {
    for den in denominators {
      b.keep(Rational::new(den, den))
    }
  })
  b.bench(name="normalize_general", fn() {
    for pair in fractions {
      b.keep(Rational::new(pair.0, pair.1))
    }
  })
}

///|
test "bench/time/whole-cycles" (b : @bench.T) {
  let arcs = Array::makei(128, index => {
    let begin = Rational::new(Int64::from_int(index * 13 - 512), 12L)
    TimeSpan::new(begin, begin + Rational::new(7L, 4L))
  })
  b.bench(name="whole_cycles_varied", fn() {
    for arc in arcs {
      b.keep(arc.whole_cycles())
    }
  })
}

///|
test "bench/pattern/sequence-slots" (b : @bench.T) {
  let pat = sequence(Array::makei(16, index => Pat::pure(index)))
  let width = Rational::new(1L, 600L)
  let arcs = Array::makei(600, index => {
    let begin = Rational::new(Int64::from_int(index), 300L)
    TimeSpan::new(begin, begin + width)
  })
  b.bench(name="sequence_600_varied_arcs", fn() {
    for arc in arcs {
      b.keep(pat.query(arc))
    }
  })
}
