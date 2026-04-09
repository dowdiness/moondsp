///|
/// Check whether a floating-point value is finite (not NaN, not Inf).
pub fn is_finite(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
/// Check whether a floating-point value is finite and strictly positive.
pub fn is_finite_positive(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf() && value > 0.0
}

///|
/// Compute the effective number of samples to process, bounded by both
/// the context block size and the buffer length.
pub fn effective_sample_count(
  context : DspContext,
  buffer : AudioBuffer,
) -> Int {
  if buffer.length() < context.block_size() {
    buffer.length()
  } else {
    context.block_size()
  }
}

///|
/// Replace non-finite samples (NaN, Inf) with 0.0 in-place.
/// Returns the number of samples replaced. This is the output firewall —
/// the last line of defense before samples leave the DSP engine.
pub fn sanitize_buffer(buffer : AudioBuffer, sample_count : Int) -> Int {
  let count = if sample_count > buffer.length() {
    buffer.length()
  } else if sample_count < 0 {
    0
  } else {
    sample_count
  }
  let mut sanitized = 0
  for i = 0; i < count; i = i + 1 {
    if !is_finite(buffer.get(i)) {
      buffer.set(i, 0.0)
      sanitized = sanitized + 1
    }
  }
  sanitized
}
