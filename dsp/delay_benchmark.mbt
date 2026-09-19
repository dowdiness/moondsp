///|
/// Measure DelayLine::reset across capacities.
///
/// The interesting claim is that reset cost stays constant while capacity
/// grows. Fill one sample before each measured reset so the call is not
/// measuring a brand-new empty line.
fn delay_reset_fixture(capacity : Int) -> DelayLine {
  let delay = DelayLine::new(capacity, delay_samples=1, feedback=0.3)
  ignore(delay.tick(1.0))
  delay
}

///|
test "bench/dsp/delay_reset" (b : @bench.T) {
  let tiny = delay_reset_fixture(8)
  let medium = delay_reset_fixture(4800)
  let large = delay_reset_fixture(480000)
  b.bench(name="reset_cap_8", fn() { tiny.reset() })
  b.bench(name="reset_cap_4800", fn() { medium.reset() })
  b.bench(name="reset_cap_480000", fn() { large.reset() })
}

///|
/// Measure a short post-reset tick train so the valid-range read branch stays
/// in the suite. Capacity differences should not dominate this path.
test "bench/dsp/delay_tick_after_reset" (b : @bench.T) {
  let medium = DelayLine::new(4800, delay_samples=2400, feedback=0.3)
  let large = DelayLine::new(480000, delay_samples=2400, feedback=0.3)
  for _ in 0..<4800 {
    ignore(medium.tick(1.0))
  }
  for _ in 0..<4800 {
    ignore(large.tick(1.0))
  }
  medium.reset()
  large.reset()
  b.bench(name="tick16_cap_4800", fn() {
    for _ in 0..<16 {
      ignore(medium.tick(0.0))
    }
  })
  b.bench(name="tick16_cap_480000", fn() {
    for _ in 0..<16 {
      ignore(large.tick(0.0))
    }
  })
}
