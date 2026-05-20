///|
/// Thin wrapper around `FixedArray[Double]` for DSP block processing.
pub struct AudioBuffer {
  priv data : FixedArray[Double]
}

///|
fn normalize_audio_sample(value : Double) -> Double {
  if is_finite(value) {
    value
  } else {
    0.0
  }
}

///|
fn normalize_audio_samples(data : FixedArray[Double]) -> Unit {
  for index in 0..<data.length() {
    data[index] = normalize_audio_sample(data[index])
  }
}

///|
/// Wrap a `FixedArray[Double]` by copying its contents.
///
/// The buffer's underlying storage is distinct from the source array;
/// neither side observes mutations made through the other. Mutating
/// the source has no effect on the buffer, and writes through the
/// buffer (via `set` / `fill`) do not propagate back to the source.
/// Non-finite source samples (`NaN`, `+Inf`, `-Inf`) are normalized to
/// `0.0` in the copied storage; finite samples pass through unchanged.
/// Use this when ingesting external data of unclear lifetime. For
/// explicit zero-copy adoption, see `AudioBuffer::adopt`.
#alias(new)
pub fn AudioBuffer::AudioBuffer(data : FixedArray[Double]) -> AudioBuffer {
  let copy = data.copy()
  normalize_audio_samples(copy)
  AudioBuffer::adopt(copy)
}

///|
/// Wrap a `FixedArray[Double]` without copying.
///
/// The buffer and the source array share storage in both directions:
/// writes through the buffer (`set` / `fill`) mutate the source, and
/// mutations through the source handle appear through the buffer.
/// Two specific bypasses follow from this: (a) the buffer's initial
/// contents are whatever the source array holds at adoption time, not
/// run through the normal non-finite-to-0.0 normalization path; and
/// (b) any later mutation through the retained source handle skips
/// AudioBuffer validation entirely. Writes through `buf.set(...)` or
/// `buf.fill(...)` on an adopted buffer still go through those methods
/// and normalize non-finite values to `0.0`. Use this only for
/// FFI-bridged buffers (e.g., `TypedArray` or `SharedArrayBuffer`
/// wrappers) where the copy cost is genuinely prohibitive and the
/// caller can reason about the source lifetime. Otherwise use
/// `AudioBuffer::new`.
pub fn AudioBuffer::adopt(data : FixedArray[Double]) -> AudioBuffer {
  { data, }
}

///|
/// Construct an audio buffer pre-filled with `init` (default 0.0).
///
/// The buffer's storage is freshly allocated and not shared with any
/// caller-visible array. Routed through `adopt` to avoid the
/// unnecessary copy `AudioBuffer::new` would now perform on the
/// freshly-allocated `FixedArray`.
/// The initializer is normalized once before allocation: non-finite
/// values become `0.0`, while finite values pass through unchanged.
pub fn AudioBuffer::filled(size : Int, init? : Double = 0.0) -> AudioBuffer {
  AudioBuffer::adopt(FixedArray::make(size, normalize_audio_sample(init)))
}

///|
/// Get the number of samples stored in the buffer.
pub fn AudioBuffer::length(self : AudioBuffer) -> Int {
  self.data.length()
}

///|
/// Fill the buffer with a single sample value.
///
/// Non-finite values (`NaN`, `+Inf`, `-Inf`) are normalized to `0.0`.
pub fn AudioBuffer::fill(self : AudioBuffer, value : Double) -> Unit {
  self.data.fill(normalize_audio_sample(value))
}

///|
/// Read one sample from the buffer.
pub fn AudioBuffer::get(self : AudioBuffer, index : Int) -> Double {
  self.data[index]
}

///|
/// Write one sample into the buffer.
///
/// Non-finite values (`NaN`, `+Inf`, `-Inf`) are normalized to `0.0`.
pub fn AudioBuffer::set(
  self : AudioBuffer,
  index : Int,
  value : Double,
) -> Unit {
  self.data[index] = normalize_audio_sample(value)
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
