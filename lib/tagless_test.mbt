///|
struct Eval {
  value : Double
} derive(Eq)

///|
pub impl @lib.ArithSym for Eval with constant(v) -> Eval {
  { value: v }
}

///|
pub impl @lib.ArithSym for Eval with mul(a, b) -> Eval {
  { value: a.value * b.value }
}

///|
pub impl @lib.ArithSym for Eval with mix(a, b) -> Eval {
  { value: a.value + b.value }
}

///|
pub impl @lib.ArithSym for Eval with clip(a, t) -> Eval {
  let v = a.value
  let clamped = if v > t { t } else if v < -t { -t } else { v }
  { value: clamped }
}

///|
test "ArithSym Eval: constant" {
  let result : Eval = @lib.ArithSym::constant(42.0)
  assert_eq(result.value, 42.0)
}

///|
test "ArithSym Eval: mul" {
  let a : Eval = @lib.ArithSym::constant(3.0)
  let b : Eval = @lib.ArithSym::constant(4.0)
  let result = @lib.ArithSym::mul(a, b)
  assert_eq(result.value, 12.0)
}

///|
test "ArithSym Eval: mix" {
  let a : Eval = @lib.ArithSym::constant(3.0)
  let b : Eval = @lib.ArithSym::constant(4.0)
  let result = @lib.ArithSym::mix(a, b)
  assert_eq(result.value, 7.0)
}

///|
test "ArithSym Eval: clip" {
  let a : Eval = @lib.ArithSym::constant(5.0)
  let result = @lib.ArithSym::clip(a, 3.0)
  assert_eq(result.value, 3.0)
}

///|
test "ArithSym Eval: clip negative" {
  let a : Eval = @lib.ArithSym::constant(-5.0)
  let result = @lib.ArithSym::clip(a, 3.0)
  assert_eq(result.value, -3.0)
}

///|
impl @lib.DspSym for Eval with oscillator(self, _waveform) {
  { value: self.value }
}

///|
impl @lib.DspSym for Eval with noise(_seed) {
  { value: 0.0 }
}

///|
impl @lib.DspSym for Eval with adsr(_a, _d, _s, _r) {
  { value: 0.0 }
}

///|
impl @lib.DspSym for Eval with gain(self, amount) {
  { value: self.value * amount }
}

///|
impl @lib.DspSym for Eval with output(self) {
  self
}

///|
impl @lib.FilterSym for Eval with biquad(self, _mode, _cutoff, _q) {
  self
}

///|
impl @lib.DelaySym for Eval with delay(self, _max, _samples, _feedback) {
  self
}

///|
impl @lib.StereoSym for Eval with pan(self, _pos) {
  self
}

///|
impl @lib.StereoSym for Eval with stereo_gain(self, _amount) {
  self
}

///|
impl @lib.StereoSym for Eval with stereo_clip(self, _threshold) {
  self
}

///|
impl @lib.StereoSym for Eval with stereo_mixdown(a) {
  a
}

///|
impl @lib.StereoSym for Eval with stereo_output(a) {
  a
}

///|
impl @lib.StereoFilterSym for Eval with stereo_biquad(self, _mode, _cutoff, _q) {
  self
}

///|
impl @lib.StereoDelaySym for Eval with stereo_delay(
  self,
  _max,
  _samples,
  _feedback,
) {
  self
}

///|
fn[T : @lib.FilterSym] exercise_filter() -> T {
  T::constant(1.0)
}

///|
test "FilterSym bound implies ArithSym" {
  let result : Eval = exercise_filter()
  assert_eq(result.value, 1.0)
}

///|
test "DspSym gain" {
  let input : Eval = @lib.ArithSym::constant(10.0)
  let result = @lib.DspSym::gain(input, 0.5)
  assert_eq(result.value, 5.0)
}

///|
test "range maps -1 to lo" {
  let input : Eval = @lib.ArithSym::constant(-1.0)
  let result = @lib.range(input, 200.0, 400.0)
  assert_eq(result.value, 200.0)
}

///|
test "range maps 1 to hi" {
  let input : Eval = @lib.ArithSym::constant(1.0)
  let result = @lib.range(input, 200.0, 400.0)
  assert_eq(result.value, 400.0)
}

///|
test "range maps 0 to midpoint" {
  let input : Eval = @lib.ArithSym::constant(0.0)
  let result = @lib.range(input, 200.0, 400.0)
  assert_eq(result.value, 300.0)
}

///|
test "lin_map maps in_lo to out_lo" {
  let input : Eval = @lib.ArithSym::constant(0.0)
  let result = @lib.lin_map(input, 0.0, 10.0, 100.0, 200.0)
  assert_eq(result.value, 100.0)
}

///|
test "lin_map maps in_hi to out_hi" {
  let input : Eval = @lib.ArithSym::constant(10.0)
  let result = @lib.lin_map(input, 0.0, 10.0, 100.0, 200.0)
  assert_eq(result.value, 200.0)
}

///|
test "lin_map with in_lo == in_hi returns out_lo fallback" {
  let input : Eval = @lib.ArithSym::constant(5.0)
  let result = @lib.lin_map(input, 3.0, 3.0, 0.0, 100.0)
  assert_eq(result.value, 0.0) // out_lo = 0.0
}
