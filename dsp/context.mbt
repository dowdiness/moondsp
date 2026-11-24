///|
/// Shared execution context for block-based DSP processing.
pub struct DspContext {
  priv sample_rate : Double
  priv block_size : Int32
  priv samples : SampleStore
}

///|
/// Create a DSP context with normalized runtime parameters. Graphs compiled
/// with it read recorded waveforms from `samples`, which defaults to a store
/// with no entries (ADR-0026 Decision 2).
pub fn DspContext::DspContext(
  sample_rate~ : Double,
  block_size~ : Int32,
  samples~ : SampleStore = empty_sample_store,
) -> DspContext {
  {
    sample_rate: normalize_sample_rate(sample_rate),
    block_size: normalize_block_size(block_size),
    samples,
  }
}

///|
/// This context with another block size and the same sample rate and store.
/// Derive contexts with this instead of constructing one, so the store stays.
pub fn DspContext::with_block_size(
  self : DspContext,
  block_size : Int32,
) -> DspContext {
  { ..self, block_size: normalize_block_size(block_size), }
}

///|
/// The store graphs compiled with this context read waveforms from.
pub fn DspContext::samples(self : DspContext) -> SampleStore {
  self.samples
}

///|
/// Return the configured sample rate for this processing context.
pub fn DspContext::sample_rate(self : DspContext) -> Double {
  self.sample_rate
}

///|
/// Return the configured block size for this processing context.
pub fn DspContext::block_size(self : DspContext) -> Int32 {
  self.block_size
}

///|
/// Create an owned audio buffer sized to this context's block size.
pub fn DspContext::make_buffer(
  self : DspContext,
  init~ : Double = 0.0,
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
fn normalize_block_size(block_size : Int32) -> Int32 {
  if block_size > 0 {
    block_size
  } else {
    0
  }
}
