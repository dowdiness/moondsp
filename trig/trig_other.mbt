///|
/// `sin(2π · turns)` for `turns` in `[0, 1]`, as the sine oscillator computes
/// it.
pub fn sine_of_turns(turns : Double) -> Double {
  @math.sin(turns * 2.0 * @math.PI)
}

///|
/// `sin(x)` for nonnegative angles up to one turn.
pub fn sin(x : Double) -> Double {
  @math.sin(x)
}

///|
/// `cos(x)` for nonnegative angles up to one turn.
pub fn cos(x : Double) -> Double {
  @math.cos(x)
}
