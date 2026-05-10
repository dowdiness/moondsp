///|
/// Shared execution context for block-based DSP processing.
pub struct DspContext {
  priv sample_rate : Double
  priv block_size : Int
}

///|
/// Create a DSP context with normalized runtime parameters.
pub fn DspContext::new(sample_rate~ : Double, block_size~ : Int) -> DspContext {
  {
    sample_rate: normalize_sample_rate(sample_rate),
    block_size: normalize_block_size(block_size),
  }
}

///|
/// Return the configured sample rate for this processing context.
pub fn DspContext::sample_rate(self : DspContext) -> Double {
  self.sample_rate
}

///|
/// Return the configured block size for this processing context.
pub fn DspContext::block_size(self : DspContext) -> Int {
  self.block_size
}

///|
/// Create an owned audio buffer sized to this context's block size.
pub fn DspContext::make_buffer(
  self : DspContext,
  init? : Double = 0.0,
) -> AudioBuffer {
  AudioBuffer::filled(self.block_size, init~)
}

///|
fn normalize_sample_rate(sample_rate : Double) -> Double {
  if sample_rate > 0.0 {
    sample_rate
  } else {
    0.0
  }
}

///|
fn normalize_block_size(block_size : Int) -> Int {
  if block_size > 0 {
    block_size
  } else {
    0
  }
}
