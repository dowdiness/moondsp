///|
/// Stateless in-place mixer for combining audio buffers.
pub struct Mix {
  unit : Unit

  fn new() -> Mix
}

///|
/// Create a mix processor.
pub fn Mix::new() -> Mix {
  Mix::{ unit: () }
}

///|
/// Add one input buffer into the output buffer without implicit clipping.
pub fn Mix::process(
  self : Mix,
  context : DspContext,
  output : AudioBuffer,
  input : AudioBuffer,
) -> Unit {
  ignore(self)
  let sample_rate = context.sample_rate()
  let sample_count = mix_sample_count(context, output, input)
  if sample_rate <= 0.0 || sample_count <= 0 {
    output.fill(0.0)
    return
  }

  for index = 0; index < sample_count; index = index + 1 {
    output.set(index, output.get(index) + input.get(index))
  }

  for index = sample_count; index < output.length(); index = index + 1 {
    output.set(index, 0.0)
  }
}

///|
fn mix_sample_count(
  context : DspContext,
  output : AudioBuffer,
  input : AudioBuffer,
) -> Int {
  let block_size = context.block_size()
  let output_len = output.length()
  let input_len = input.length()
  let bounded_len = if output_len < input_len { output_len } else { input_len }
  if bounded_len < block_size {
    bounded_len
  } else {
    block_size
  }
}
