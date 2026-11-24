///|
/// `cos(2π · turns)` for `turns` in `[0, 1]`. Allocates nothing on every target.
pub fn cosine_of_turns(turns : Double) -> Double {
  cos(turns * 2.0 * @math.PI)
}
