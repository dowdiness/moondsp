///|
/// Reject NaN/Inf and clamp to minimum 1.0 BPM.
pub fn sanitize_bpm(bpm : Double) -> Double {
  if bpm.is_nan() || bpm.is_inf() || bpm < 1.0 {
    1.0
  } else {
    bpm
  }
}

///|
/// Derive the cycle-time arc for a block from the integer sample counter.
pub fn compute_arc(
  sample_counter : Int64,
  bpm : Double,
  ctx : @dsp.DspContext,
) -> @pattern.TimeSpan {
  // WHY scale by 10: BPM is a Double but Rational needs Int64. Multiplying
  // by 10 preserves one decimal place (120.5 → 1205) which covers all
  // standard tempos. The denominator becomes sample_rate * 600 instead of
  // sample_rate * 60 — still well within Int64 range.
  let bpm_scaled = (bpm * 10.0).to_int64()
  let sr600 = ctx.sample_rate().to_int().to_int64() * 600L
  let block_size = ctx.block_size().to_int64()
  let arc_start = @pattern.Rational::new(sample_counter * bpm_scaled, sr600)
  let arc_end = @pattern.Rational::new(
    (sample_counter + block_size) * bpm_scaled,
    sr600,
  )
  @pattern.TimeSpan::new(arc_start, arc_end)
}

///|
pub fn block_sample_end(sample_begin : Int64, ctx : @dsp.DspContext) -> Int64 {
  sample_begin + ctx.block_size().to_int64()
}

///|
pub fn advance_block_sample(
  sample_counter : Int64,
  ctx : @dsp.DspContext,
) -> Int64 {
  block_sample_end(sample_counter, ctx)
}

///|
fn ceil_div_i64(num : Int64, den : Int64) -> Int64 {
  if den <= 0L {
    abort("ceil_div_i64: denominator must be positive")
  }
  let q = num / den
  let r = num % den
  if r == 0L || num < 0L {
    q
  } else {
    q + 1L
  }
}

///|
/// Convert an absolute logical cycle position into the first sample at or after
/// that cycle position for the scheduler's BPM scaling convention.
pub fn cycle_to_sample(
  cycle : @pattern.Rational,
  bpm : Double,
  ctx : @dsp.DspContext,
) -> Int64 {
  let bpm_scaled = (sanitize_bpm(bpm) * 10.0).to_int64()
  let sr600 = ctx.sample_rate().to_int().to_int64() * 600L
  ceil_div_i64(cycle.num * sr600, cycle.den * bpm_scaled)
}
