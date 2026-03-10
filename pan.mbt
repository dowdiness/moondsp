///|
/// Stateless equal-power pan processor for mono-to-stereo routing.
pub struct Pan {
  unit : Unit

  fn new() -> Pan
}

///|
/// Create a pan processor.
pub fn Pan::new() -> Pan {
  Pan::{ unit: () }
}

///|
/// Pan a mono input buffer into explicit left and right output buffers.
///
/// Finite positions are clamped to `[-1.0, 1.0]`, where `-1.0` is hard left,
/// `0.0` is center, and `1.0` is hard right. Invalid positions or contexts
/// write silence to both outputs.
pub fn Pan::process(
  self : Pan,
  context : DspContext,
  input : AudioBuffer,
  left_output : AudioBuffer,
  right_output : AudioBuffer,
  position : Double,
) -> Unit {
  ignore(self)
  let sample_rate = context.sample_rate()
  let sample_count = pan_sample_count(context, input, left_output, right_output)
  if !is_valid_pan_sample_rate(sample_rate) ||
    !is_valid_pan_position(position) ||
    sample_count <= 0 {
    left_output.fill(0.0)
    right_output.fill(0.0)
    return
  }

  let clamped = position.clamp(min=-1.0, max=1.0)
  let left_gain = if clamped <= -1.0 {
    1.0
  } else if clamped >= 1.0 {
    0.0
  } else {
    let angle = (clamped + 1.0) * @math.PI * 0.25
    @math.cos(angle)
  }
  let right_gain = if clamped <= -1.0 {
    0.0
  } else if clamped >= 1.0 {
    1.0
  } else {
    let angle = (clamped + 1.0) * @math.PI * 0.25
    @math.sin(angle)
  }

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
fn is_valid_pan_sample_rate(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf() && value > 0.0
}

///|
fn is_valid_pan_position(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
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
