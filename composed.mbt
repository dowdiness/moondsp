///|
/// Maps [-1, 1] -> [lo, hi]. Only requires ArithSym.
pub fn[T : ArithSym] range(input : T, lo : Double, hi : Double) -> T {
  T::mix(
    T::mul(T::mix(input, T::constant(1.0)), T::constant(0.5 * (hi - lo))),
    T::constant(lo),
  )
}

///|
/// The Phase 2 exit deliverable: sine(2).range(200,400).sine().lpf(800,1).out()
/// An LFO at 2 Hz modulates the frequency of a carrier oscillator between
/// 200-400 Hz, then filtered through a low-pass biquad at 800 Hz.
pub fn[T : FilterSym] exit_deliverable() -> T {
  let lfo = T::oscillator(T::constant(2.0), Waveform::Sine)
  let freq = range(lfo, 200.0, 400.0)
  let carrier = T::oscillator(freq, Waveform::Sine)
  let filtered = T::biquad(carrier, BiquadMode::LowPass, 800.0, 1.0)
  let gained = T::gain(filtered, 0.3)
  T::output(gained)
}

///|
/// Maps [in_lo, in_hi] -> [out_lo, out_hi]. Only requires ArithSym.
/// Precondition: in_lo != in_hi (division by zero otherwise).
pub fn[T : ArithSym] lin_map(
  input : T,
  in_lo : Double,
  in_hi : Double,
  out_lo : Double,
  out_hi : Double,
) -> T {
  if in_hi == in_lo {
    return T::constant(out_lo)
  }
  let scale = (out_hi - out_lo) / (in_hi - in_lo)
  T::mix(
    T::mul(T::mix(input, T::constant(-in_lo)), T::constant(scale)),
    T::constant(out_lo),
  )
}
