///|
/// Deterministic white-noise source with explicit RNG state.
pub struct Noise {
  mut state : UInt
}

///|
/// Create a new white-noise generator from an explicit seed.
pub fn Noise::new(seed : UInt) -> Noise {
  { state: normalize_seed(seed) }
}

///|
/// Expose the current RNG state for testing and diagnostics.
pub fn Noise::seed(self : Noise) -> UInt {
  self.state
}

///|
/// Reset the generator to a new explicit seed.
pub fn Noise::reset(self : Noise, seed : UInt) -> Unit {
  self.state = normalize_seed(seed)
}

///|
/// Generate one white-noise sample in the range `[-1.0, 1.0]`.
pub fn Noise::tick(self : Noise) -> Double {
  self.state = next_state(self.state)
  sample_from_state(self.state)
}

///|
/// Fill an output buffer with white-noise samples.
pub fn Noise::process(
  self : Noise,
  context : DspContext,
  output : AudioBuffer,
) -> Unit {
  let sample_rate = context.sample_rate()
  let sample_count = noise_sample_count(context, output)

  if !is_valid_noise_sample_rate(sample_rate) || sample_count <= 0 {
    output.fill(0.0)
    return
  }

  for index = 0; index < sample_count; index = index + 1 {
    output.set(index, self.tick())
  }

  for index = sample_count; index < output.length(); index = index + 1 {
    output.set(index, 0.0)
  }
}

///|
fn normalize_seed(seed : UInt) -> UInt {
  if seed == 0U {
    0x6D2B79F5U
  } else {
    seed
  }
}

///|
fn next_state(state : UInt) -> UInt {
  normalize_seed(state * 1664525U + 1013904223U)
}

///|
fn sample_from_state(state : UInt) -> Double {
  state.to_double() / 2147483648.0 - 1.0
}

///|
fn is_valid_noise_sample_rate(sample_rate : Double) -> Bool {
  sample_rate > 0.0 && !sample_rate.is_nan() && !sample_rate.is_inf()
}

///|
fn noise_sample_count(context : DspContext, output : AudioBuffer) -> Int {
  if output.length() < context.block_size() {
    output.length()
  } else {
    context.block_size()
  }
}
