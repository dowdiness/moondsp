///|
/// Run the compiled graph for one buffer and write the final output into
/// `output`.
pub fn Dsp::process(
  self : Dsp,
  context : DspContext,
  output : AudioBuffer,
) -> Unit {
  self.raw().process(context, output)
}

///|
/// Run the compiled stereo graph for one buffer and write the final output into
/// explicit left and right buffers.
pub fn StereoDsp::process(
  self : StereoDsp,
  context : DspContext,
  left_output : AudioBuffer,
  right_output : AudioBuffer,
) -> Unit {
  self.raw().process(context, left_output, right_output)
}
