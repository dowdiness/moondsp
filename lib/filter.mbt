///|
/// Supported biquad response shapes for the Phase 1 filter primitive.
pub(all) enum BiquadMode {
  LowPass
  HighPass
  BandPass
} derive(Eq)

///|
/// Stateful biquad filter using Direct Form II Transposed processing.
pub struct Biquad {
  priv mut b0 : Double
  priv mut b1 : Double
  priv mut b2 : Double
  priv mut a1 : Double
  priv mut a2 : Double
  priv mut z1 : Double
  priv mut z2 : Double
  priv mut configured : Bool

  fn new() -> Biquad
}

///|
/// Create a new biquad filter with zeroed state and no active coefficients.
pub fn Biquad::new() -> Biquad {
  {
    b0: 0.0,
    b1: 0.0,
    b2: 0.0,
    a1: 0.0,
    a2: 0.0,
    z1: 0.0,
    z2: 0.0,
    configured: false,
  }
}

///|
/// Clear the filter delay state without changing the current coefficients.
pub fn Biquad::reset(self : Biquad) -> Unit {
  self.z1 = 0.0
  self.z2 = 0.0
}

///|
/// Recalculate filter coefficients for the given mode, cutoff, and resonance.
///
/// Returns `false` and disables processing when the parameters are invalid.
pub fn Biquad::update(
  self : Biquad,
  context : DspContext,
  mode : BiquadMode,
  cutoff : Double,
  q : Double,
) -> Bool {
  let sample_rate = context.sample_rate()
  if !valid_biquad_params(sample_rate, cutoff, q) {
    self.invalidate()
    return false
  }

  let w0 = 2.0 * @math.PI * cutoff / sample_rate
  let cos_w0 = @math.cos(w0)
  let alpha = @math.sin(w0) / (2.0 * q)
  let a0 = 1.0 + alpha
  if !is_finite(a0) || a0 <= 0.0 {
    self.invalidate()
    return false
  }

  let b0 = match mode {
    LowPass => (1.0 - cos_w0) * 0.5
    HighPass => (1.0 + cos_w0) * 0.5
    BandPass => alpha
  }
  let b1 = match mode {
    LowPass => 1.0 - cos_w0
    HighPass => -(1.0 + cos_w0)
    BandPass => 0.0
  }
  let b2 = match mode {
    LowPass => (1.0 - cos_w0) * 0.5
    HighPass => (1.0 + cos_w0) * 0.5
    BandPass => -alpha
  }
  let a1 = -2.0 * cos_w0
  let a2 = 1.0 - alpha
  let inv_a0 = 1.0 / a0

  self.b0 = b0 * inv_a0
  self.b1 = b1 * inv_a0
  self.b2 = b2 * inv_a0
  self.a1 = a1 * inv_a0
  self.a2 = a2 * inv_a0
  self.configured = self.finite_coefficients()
  if !self.configured {
    self.invalidate()
  }
  self.configured
}

///|
/// Filter one input sample and advance the internal delay state.
pub fn Biquad::tick(self : Biquad, input : Double) -> Double {
  if !self.configured {
    return 0.0
  }

  let output = self.b0 * input + self.z1
  let next_z1 = self.b1 * input - self.a1 * output + self.z2
  let next_z2 = self.b2 * input - self.a2 * output
  if !is_finite(output) || !is_finite(next_z1) || !is_finite(next_z2) {
    self.invalidate()
    return 0.0
  }

  self.z1 = next_z1
  self.z2 = next_z2
  output
}

///|
/// Filter one block of samples in place.
pub fn Biquad::process(
  self : Biquad,
  context : DspContext,
  buffer : AudioBuffer,
) -> Unit {
  let sample_rate = context.sample_rate()
  let sample_count = effective_sample_count(context, buffer)
  if sample_rate <= 0.0 || sample_count <= 0 || !self.configured {
    buffer.fill(0.0)
    return
  }

  for index = 0; index < sample_count; index = index + 1 {
    buffer.set(index, self.tick(buffer.get(index)))
  }

  for index = sample_count; index < buffer.length(); index = index + 1 {
    buffer.set(index, 0.0)
  }
}

///|
fn valid_biquad_params(
  sample_rate : Double,
  cutoff : Double,
  q : Double,
) -> Bool {
  let nyquist = sample_rate * 0.5
  sample_rate > 0.0 &&
  is_finite(sample_rate) &&
  cutoff > 0.0 &&
  cutoff < nyquist &&
  is_finite(cutoff) &&
  q > 0.0 &&
  is_finite(q)
}

///|
fn Biquad::invalidate(self : Biquad) -> Unit {
  self.b0 = 0.0
  self.b1 = 0.0
  self.b2 = 0.0
  self.a1 = 0.0
  self.a2 = 0.0
  self.z1 = 0.0
  self.z2 = 0.0
  self.configured = false
}

///|
fn Biquad::finite_coefficients(self : Biquad) -> Bool {
  is_finite(self.b0) &&
  is_finite(self.b1) &&
  is_finite(self.b2) &&
  is_finite(self.a1) &&
  is_finite(self.a2)
}
