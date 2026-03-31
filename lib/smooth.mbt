///|
/// Stateful one-pole smoother for click-free control changes.
pub struct ParamSmoother {
  mut current : Double
  mut target : Double
  mut coeff : Double
}

///|
/// Create a parameter smoother from an initial value, smoothing time, and
/// explicit sample rate.
pub fn ParamSmoother::new(
  initial : Double,
  smoothing_ms : Double,
  sample_rate : Double,
) -> ParamSmoother {
  let normalized = normalize_param_value(initial)
  {
    current: normalized,
    target: normalized,
    coeff: smoothing_coeff(smoothing_ms, sample_rate),
  }
}

///|
/// Create a parameter smoother using the sample rate stored in a DSP context.
pub fn ParamSmoother::from_context(
  initial : Double,
  smoothing_ms : Double,
  context : DspContext,
) -> ParamSmoother {
  ParamSmoother::new(initial, smoothing_ms, context.sample_rate())
}

///|
/// Return the current smoothed value.
pub fn ParamSmoother::current(self : ParamSmoother) -> Double {
  self.current
}

///|
/// Return the current target value.
pub fn ParamSmoother::target(self : ParamSmoother) -> Double {
  self.target
}

///|
/// Immediately snap both the current and target value to a new point.
pub fn ParamSmoother::reset(self : ParamSmoother, value : Double) -> Unit {
  let normalized = normalize_param_value(value)
  self.current = normalized
  self.target = normalized
}

///|
/// Update the smoothing time using an explicit sample rate.
pub fn ParamSmoother::set_smoothing_time(
  self : ParamSmoother,
  smoothing_ms : Double,
  sample_rate : Double,
) -> Unit {
  self.coeff = smoothing_coeff(smoothing_ms, sample_rate)
}

///|
/// Update the smoothing time using the sample rate stored in a DSP context.
pub fn ParamSmoother::set_smoothing_time_from_context(
  self : ParamSmoother,
  smoothing_ms : Double,
  context : DspContext,
) -> Unit {
  self.set_smoothing_time(smoothing_ms, context.sample_rate())
}

///|
/// Set a new target value. Invalid inputs are ignored to keep the state
/// deterministic inside the audio path.
pub fn ParamSmoother::set_target(self : ParamSmoother, value : Double) -> Unit {
  if is_finite(value) {
    self.target = value
  }
}

///|
/// Advance the smoother by one sample.
pub fn ParamSmoother::tick(self : ParamSmoother) -> Double {
  if self.current == self.target {
    return self.current
  }

  self.current = self.target + self.coeff * (self.current - self.target)
  self.current
}

///|
fn smoothing_coeff(smoothing_ms : Double, sample_rate : Double) -> Double {
  if !is_finite(smoothing_ms) ||
    !is_finite(sample_rate) ||
    smoothing_ms <= 0.0 ||
    sample_rate <= 0.0 {
    0.0
  } else {
    @math.exp(-1000.0 / (smoothing_ms * sample_rate))
  }
}

///|
fn normalize_param_value(value : Double) -> Double {
  if is_finite(value) {
    value
  } else {
    0.0
  }
}
