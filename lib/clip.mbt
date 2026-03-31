///|
/// Stateless hard-clipping processor for explicit range limiting.
pub struct Clip {
  unit : Unit

  fn new() -> Clip
}

///|
/// Create a clip processor.
pub fn Clip::new() -> Clip {
  Clip::{ unit: () }
}

///|
/// Apply hard clipping in place using a symmetric threshold.
pub fn Clip::process(
  self : Clip,
  context : DspContext,
  buffer : AudioBuffer,
  threshold : Double,
) -> Unit {
  ignore(self)
  let sample_rate = context.sample_rate()
  let sample_count = effective_sample_count(context, buffer)
  if sample_rate <= 0.0 ||
    sample_count <= 0 ||
    threshold <= 0.0 ||
    threshold.is_nan() ||
    threshold.is_inf() {
    buffer.fill(0.0)
    return
  }

  for index = 0; index < sample_count; index = index + 1 {
    let sample = buffer.get(index)
    buffer.set(index, clip_sample(sample, threshold))
  }

  for index = sample_count; index < buffer.length(); index = index + 1 {
    buffer.set(index, 0.0)
  }
}

///|
fn clip_sample(sample : Double, threshold : Double) -> Double {
  if sample > threshold {
    threshold
  } else if sample < -threshold {
    -threshold
  } else {
    sample
  }
}
