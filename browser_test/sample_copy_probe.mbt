///|
/// Measurement prototype for ADR-0026: how long JS takes to copy a decoded
/// waveform into a wasm-gc buffer one sample per call. JS cannot write a
/// wasm-gc array directly, so every sample crosses as one export call. This is
/// not the sample store; it only owns one 32-bit float waveform.
let sample_copy_buffer : @ref.Ref[FixedArray[Float]] = Ref(
  FixedArray::make(0, 0.0),
)

///|
/// Allocate a zeroed waveform of `length` samples, replacing the previous one.
/// Returns the length, or -1 when `length` is negative.
pub fn sample_copy_reserve(length : Int32) -> Int32 {
  guard length >= 0 else { return -1 }
  sample_copy_buffer.val = FixedArray::make(length, 0.0)
  length
}

///|
/// Write one sample. An index outside the waveform writes nothing.
pub fn sample_copy_write(index : Int32, value : Float) -> Unit {
  let data = sample_copy_buffer.val
  if index >= 0 && index < data.length() {
    data[index] = value
  }
}

///|
/// The sample at `index`, or 0 outside the waveform.
pub fn sample_copy_sample(index : Int32) -> Double {
  let data = sample_copy_buffer.val
  if index >= 0 && index < data.length() {
    data[index].to_double()
  } else {
    0.0
  }
}

///|
/// The sum of every sample, so a caller can check the whole copy landed.
pub fn sample_copy_checksum() -> Double {
  let mut sum = 0.0
  for value in sample_copy_buffer.val {
    sum = sum + value.to_double()
  }
  sum
}
