///|
/// Thin wrapper around `FixedArray[Double]` for DSP block processing.
pub struct AudioBuffer {
  priv data : FixedArray[Double]
}

///|
/// Wrap an existing `FixedArray[Double]` without copying.
#alias(new)
pub fn AudioBuffer::AudioBuffer(data : FixedArray[Double]) -> AudioBuffer {
  { data, }
}

///|
/// Wrap a `FixedArray[Double]` without copying.
///
/// The buffer and the source array share storage in both directions:
/// writes through the buffer (`set` / `fill`) mutate the source, and
/// mutations through the source handle appear through the buffer.
/// Two specific bypasses follow from this: (a) the buffer's initial
/// contents are whatever the source array holds at adoption time, not
/// run through any normalization that future `set`/`fill` may apply;
/// and (b) any later mutation through the retained source handle
/// skips `AudioBuffer::set` entirely. (Writes through `buf.set(...)`
/// or `buf.fill(...)` on an adopted buffer still go through those
/// methods and pick up whatever validation they perform.) Use this
/// only for FFI-bridged buffers (e.g., `TypedArray` or
/// `SharedArrayBuffer` wrappers) where the copy cost is genuinely
/// prohibitive and the caller can reason about the source lifetime.
/// Otherwise use `AudioBuffer::new`.
pub fn AudioBuffer::adopt(data : FixedArray[Double]) -> AudioBuffer {
  { data, }
}

///|
/// Create a new owned audio buffer with all samples initialized to the same value.
pub fn AudioBuffer::filled(size : Int, init? : Double = 0.0) -> AudioBuffer {
  AudioBuffer::new(FixedArray::make(size, init))
}

///|
/// Get the number of samples stored in the buffer.
pub fn AudioBuffer::length(self : AudioBuffer) -> Int {
  self.data.length()
}

///|
/// Fill the buffer with a single sample value.
pub fn AudioBuffer::fill(self : AudioBuffer, value : Double) -> Unit {
  self.data.fill(value)
}

///|
/// Read one sample from the buffer.
pub fn AudioBuffer::get(self : AudioBuffer, index : Int) -> Double {
  self.data[index]
}

///|
/// Write one sample into the buffer.
pub fn AudioBuffer::set(
  self : AudioBuffer,
  index : Int,
  value : Double,
) -> Unit {
  self.data[index] = value
}

///|
/// Test whether `predicate` holds for every sample in the buffer.
#alias(every)
pub fn AudioBuffer::all(
  self : AudioBuffer,
  predicate : (Double) -> Bool raise?,
) -> Bool raise? {
  self.data.all(predicate)
}

///|
/// Test whether `predicate` holds for at least one sample in the buffer.
#alias(exists)
pub fn AudioBuffer::any(
  self : AudioBuffer,
  predicate : (Double) -> Bool raise?,
) -> Bool raise? {
  self.data.any(predicate)
}
