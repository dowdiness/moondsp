///|
/// Stateless equal-power pan processor for mono-to-stereo routing.
pub struct Pan {}

///|
/// Create a pan processor.
#alias(new)
pub fn Pan::Pan() -> Pan {
  Pan::{  }
}

///|
/// Pan a mono input buffer into explicit left and right output buffers.
///
/// Finite positions are clamped to `[-1.0, 1.0]`, where `-1.0` is hard left,
/// `0.0` is center, and `1.0` is hard right. Invalid positions or contexts
/// write silence to both outputs.
pub fn Pan::process(
  self : Pan,
  context~ : DspContext,
  input~ : AudioBuffer,
  left_output~ : AudioBuffer,
  right_output~ : AudioBuffer,
  position~ : Double,
) -> Unit {
  ignore(self)
  let sample_rate = context.sample_rate()
  let sample_count = pan_sample_count(context, input, left_output, right_output)
  if !is_finite_positive(sample_rate) ||
    !is_finite(position) ||
    sample_count <= 0 {
    left_output.fill(0.0)
    right_output.fill(0.0)
    return
  }

  let left_gain = pan_left_gain(position)
  let right_gain = pan_right_gain(position)

  for index = 0; index < sample_count; index = index + 1 {
    let sample = input.get(index)
    left_output.set(index, sample * left_gain)
    right_output.set(index, sample * right_gain)
  }

  for index = sample_count; index < left_output.length(); index = index + 1 {
    left_output.set(index, 0.0)
  }

  for index = sample_count; index < right_output.length(); index = index + 1 {
    right_output.set(index, 0.0)
  }
}

///|
/// Equal-power left-channel gain for a pan position in [-1.0, 1.0].
/// -1.0 = hard left (gain 1.0), 0.0 = center (~0.707), 1.0 = hard right (gain 0.0).
/// Non-finite positions return 0.0.
pub fn pan_left_gain(position : Double) -> Double {
  if !is_finite(position) {
    0.0
  } else {
    let clamped = position.clamp(min=-1.0, max=1.0)
    if clamped <= -1.0 {
      1.0
    } else if clamped >= 1.0 {
      0.0
    } else {
      let angle = (clamped + 1.0) * @math.PI * 0.25
      @math.cos(angle)
    }
  }
}

///|
/// Equal-power right-channel gain for a pan position in [-1.0, 1.0].
/// -1.0 = hard left (gain 0.0), 0.0 = center (~0.707), 1.0 = hard right (gain 1.0).
/// Non-finite positions return 0.0.
pub fn pan_right_gain(position : Double) -> Double {
  if !is_finite(position) {
    0.0
  } else {
    let clamped = position.clamp(min=-1.0, max=1.0)
    if clamped <= -1.0 {
      0.0
    } else if clamped >= 1.0 {
      1.0
    } else {
      let angle = (clamped + 1.0) * @math.PI * 0.25
      @math.sin(angle)
    }
  }
}

///|
fn pan_sample_count(
  context : DspContext,
  input : AudioBuffer,
  left_output : AudioBuffer,
  right_output : AudioBuffer,
) -> Int {
  let block_size = context.block_size()
  let input_len = input.length()
  let left_len = left_output.length()
  let right_len = right_output.length()
  let bounded = if input_len < left_len {
    if input_len < right_len {
      input_len
    } else {
      right_len
    }
  } else if left_len < right_len {
    left_len
  } else {
    right_len
  }
  if bounded < block_size {
    bounded
  } else {
    block_size
  }
}
