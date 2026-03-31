///|
/// Stateless in-place gain processor for Phase 1 block processing.
pub struct Gain {
  unit : Unit

  fn new() -> Gain
}

///|
/// Create a gain processor.
pub fn Gain::new() -> Gain {
  Gain::{ unit: () }
}

///|
/// Apply a scalar gain to a block of audio samples in place.
pub fn Gain::process(
  self : Gain,
  context : DspContext,
  buffer : AudioBuffer,
  amount : Double,
) -> Unit {
  ignore(self)
  let sample_rate = context.sample_rate()
  let sample_count = effective_sample_count(context, buffer)
  if sample_rate <= 0.0 ||
    sample_count <= 0 ||
    amount.is_nan() ||
    amount.is_inf() {
    buffer.fill(0.0)
    return
  }

  for index = 0; index < sample_count; index = index + 1 {
    buffer.set(index, buffer.get(index) * amount)
  }

  for index = sample_count; index < buffer.length(); index = index + 1 {
    buffer.set(index, 0.0)
  }
}
