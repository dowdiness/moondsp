///|
/// Thin wrapper around `FixedArray[Double]` for DSP block processing.
pub struct AudioBuffer {
  data : FixedArray[Double]

  fn new(data : FixedArray[Double]) -> AudioBuffer
}

///|
/// Wrap an existing `FixedArray[Double]` without copying.
pub fn AudioBuffer::new(data : FixedArray[Double]) -> AudioBuffer {
  { data, }
}

///|
/// Create a new owned audio buffer with all samples initialized to the same value.
pub fn AudioBuffer::filled(size : Int, init? : Double = 0.0) -> AudioBuffer {
  AudioBuffer(FixedArray::make(size, init))
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
/// Expose the underlying fixed array for low-level integration points.
pub fn AudioBuffer::as_fixed_array(self : AudioBuffer) -> FixedArray[Double] {
  self.data
}
