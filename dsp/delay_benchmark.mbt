///|
/// Measure DelayLine::reset across capacities.
///
/// Prime once before timing. Repeated reset-only batches mostly measure an
/// already-reset line; use reset-plus-ticks and prepared stealing as the
/// primary evidence for active-use cost.
fn delay_reset_fixture(capacity : Int) -> DelayLine {
  let delay = DelayLine::new(capacity, delay_samples=1, feedback=0.3)
  ignore(delay.tick(1.0))
  delay
}

///|
fn delay_tick_fixture(capacity : Int) -> DelayLine {
  DelayLine::new(capacity, delay_samples=2400, feedback=0.3)
}

///|
fn warm_delay_ticks(delay : DelayLine, ticks : Int) -> Unit {
  for _ in 0..<ticks {
    ignore(delay.tick(1.0))
  }
}

///|
fn tick16(delay : DelayLine) -> Unit {
  for _ in 0..<16 {
    ignore(delay.tick(0.0))
  }
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
/// Measure reset plus a short post-reset tick train.
///
/// Reset must happen inside each measured batch. Otherwise repeated batches
/// wrap the ring and leave the valid-range branch, so the suite would time
/// steady-state ticks instead of the advertised post-reset path.
test "bench/dsp/delay_reset_plus_tick16" (b : @bench.T) {
  let medium = delay_tick_fixture(4800)
  let large = delay_tick_fixture(480000)
  warm_delay_ticks(medium, 4800)
  warm_delay_ticks(large, 4800)
  b.bench(name="reset_plus_tick16_cap_4800", fn() {
    medium.reset()
    tick16(medium)
  })
  b.bench(name="reset_plus_tick16_cap_480000", fn() {
    large.reset()
    tick16(large)
  })
}

///|
/// Measure warmed steady-state ticks with no reset in the timed batch.
///
/// This isolates the always-on `has_wrapped` / valid-range read overhead after
/// the ring has wrapped, separate from the post-reset branch.
test "bench/dsp/delay_tick16_steady" (b : @bench.T) {
  let medium = delay_tick_fixture(4800)
  let large = delay_tick_fixture(480000)
  warm_delay_ticks(medium, medium.max_delay_samples() * 2)
  warm_delay_ticks(large, large.max_delay_samples() * 2)
  b.bench(name="tick16_steady_cap_4800", fn() { tick16(medium) })
  b.bench(name="tick16_steady_cap_480000", fn() { tick16(large) })
}
