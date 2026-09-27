///|
struct Eval {
  value : Double
} derive(Eq)

///|
pub impl ArithSym for Eval with fn constant(v) -> Eval {
  { value: v, }
}

///|
pub impl ArithSym for Eval with fn mul(a, b) -> Eval {
  { value: a.value * b.value, }
}

///|
pub impl ArithSym for Eval with fn mix(a, b) -> Eval {
  { value: a.value + b.value, }
}

///|
pub impl ArithSym for Eval with fn clip(a, t) -> Eval {
  let v = a.value
  let clamped = if v > t { t } else if v < -t { -t } else { v }
  { value: clamped, }
}

///|
test "ArithSym Eval: constant" {
  let result : Eval = @moondsp.ArithSym::constant(42.0)
  @debug.assert_eq(result.value, 42.0)
}

///|
test "ArithSym Eval: mul" {
  let a : Eval = @moondsp.ArithSym::constant(3.0)
  let b : Eval = @moondsp.ArithSym::constant(4.0)
  let result = @moondsp.ArithSym::mul(a, b)
  @debug.assert_eq(result.value, 12.0)
}

///|
test "ArithSym Eval: mix" {
  let a : Eval = @moondsp.ArithSym::constant(3.0)
  let b : Eval = @moondsp.ArithSym::constant(4.0)
  let result = @moondsp.ArithSym::mix(a, b)
  @debug.assert_eq(result.value, 7.0)
}

///|
test "ArithSym Eval: clip" {
  let a : Eval = @moondsp.ArithSym::constant(5.0)
  let result = @moondsp.ArithSym::clip(a, 3.0)
  @debug.assert_eq(result.value, 3.0)
}

///|
test "ArithSym Eval: clip negative" {
  let a : Eval = @moondsp.ArithSym::constant(-5.0)
  let result = @moondsp.ArithSym::clip(a, 3.0)
  @debug.assert_eq(result.value, -3.0)
}

///|
impl DspSym for Eval with fn oscillator(self, _waveform) {
  { value: self.value, }
}

///|
impl DspSym for Eval with fn noise(_seed) {
  { value: 0.0, }
}

///|
impl DspSym for Eval with fn adsr(_a, _d, _s, _r) {
  { value: 0.0, }
}

///|
impl DspSym for Eval with fn gain(self, amount) {
  { value: self.value * amount, }
}

///|
impl DspSym for Eval with fn output(self) {
  self
}

///|
impl FilterSym for Eval with fn biquad(self, _mode, _cutoff, _q) {
  self
}

///|
impl DelaySym for Eval with fn delay(self, _max, _samples, _feedback) {
  self
}

///|
impl StereoSym for Eval with fn pan(self, _pos) {
  self
}

///|
impl StereoSym for Eval with fn stereo_gain(self, _amount) {
  self
}

///|
impl StereoSym for Eval with fn stereo_clip(self, _threshold) {
  self
}

///|
impl StereoSym for Eval with fn stereo_mixdown(a) {
  a
}

///|
impl StereoSym for Eval with fn stereo_output(a) {
  a
}

///|
impl StereoFilterSym for Eval with fn stereo_biquad(self, _mode, _cutoff, _q) {
  self
}

///|
impl StereoDelaySym for Eval with fn stereo_delay(
  self,
  _max,
  _samples,
  _feedback,
) {
  self
}

///|
fn[T : FilterSym] exercise_filter() -> T {
  @dsp.ArithSym::constant(1.0)
}

///|
test "FilterSym bound implies ArithSym" {
  let result : Eval = exercise_filter()
  @debug.assert_eq(result.value, 1.0)
}

///|
test "DspSym gain" {
  let input : Eval = @moondsp.ArithSym::constant(10.0)
  let result = @moondsp.DspSym::gain(input, 0.5)
  @debug.assert_eq(result.value, 5.0)
}

///|
test "range maps -1 to lo" {
  let input : Eval = @moondsp.ArithSym::constant(-1.0)
  let result = @moondsp.range(input, 200.0, 400.0)
  @debug.assert_eq(result.value, 200.0)
}

///|
test "range maps 1 to hi" {
  let input : Eval = @moondsp.ArithSym::constant(1.0)
  let result = @moondsp.range(input, 200.0, 400.0)
  @debug.assert_eq(result.value, 400.0)
}

///|
test "range maps 0 to midpoint" {
  let input : Eval = @moondsp.ArithSym::constant(0.0)
  let result = @moondsp.range(input, 200.0, 400.0)
  @debug.assert_eq(result.value, 300.0)
}

///|
test "lin_map maps in_lo to out_lo" {
  let input : Eval = @moondsp.ArithSym::constant(0.0)
  let result = @moondsp.lin_map(input, 0.0, 10.0, 100.0, 200.0)
  @debug.assert_eq(result.value, 100.0)
}

///|
test "lin_map maps in_hi to out_hi" {
  let input : Eval = @moondsp.ArithSym::constant(10.0)
  let result = @moondsp.lin_map(input, 0.0, 10.0, 100.0, 200.0)
  @debug.assert_eq(result.value, 200.0)
}

///|
test "lin_map with in_lo == in_hi returns out_lo fallback" {
  let input : Eval = @moondsp.ArithSym::constant(5.0)
  let result = @moondsp.lin_map(input, 3.0, 3.0, 0.0, 100.0)
  @debug.assert_eq(result.value, 0.0) // out_lo = 0.0
}
