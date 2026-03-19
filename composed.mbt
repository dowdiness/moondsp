///|
/// Maps [-1, 1] -> [lo, hi]. Only requires ArithSym.
pub fn[T : ArithSym] range(input : T, lo : Double, hi : Double) -> T {
  T::mix(
    T::mul(T::mix(input, T::constant(1.0)), T::constant(0.5 * (hi - lo))),
    T::constant(lo),
  )
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
  let scale = (out_hi - out_lo) / (in_hi - in_lo)
  T::mix(
    T::mul(T::mix(input, T::constant(-in_lo)), T::constant(scale)),
    T::constant(out_lo),
  )
}
