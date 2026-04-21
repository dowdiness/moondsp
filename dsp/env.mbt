///|
/// Public ADSR stage names for diagnostics and tests.
pub(all) enum EnvStage {
  Idle
  Attack
  Decay
  Sustain
  Release
} derive(Eq)

///|
/// Stateful ADSR envelope generator.
pub struct Adsr {
  attack_ms : Double
  decay_ms : Double
  sustain : Double
  release_ms : Double
  mut stage : EnvStage
  mut level : Double
  mut level_at_release : Double

  fn new(
    attack_ms~ : Double,
    decay_ms~ : Double,
    sustain~ : Double,
    release_ms~ : Double,
  ) -> Adsr
}

///|
/// Create a new ADSR envelope with normalized parameters.
pub fn Adsr::new(
  attack_ms~ : Double,
  decay_ms~ : Double,
  sustain~ : Double,
  release_ms~ : Double,
) -> Adsr {
  {
    attack_ms: normalize_time_ms(attack_ms),
    decay_ms: normalize_time_ms(decay_ms),
    sustain: normalize_sustain(sustain),
    release_ms: normalize_time_ms(release_ms),
    stage: EnvStage::Idle,
    level: 0.0,
    level_at_release: 0.0,
  }
}

///|
/// Return the current envelope stage.
pub fn Adsr::stage(self : Adsr) -> EnvStage {
  self.stage
}

///|
/// Return the current envelope level.
pub fn Adsr::level(self : Adsr) -> Double {
  self.level
}

///|
/// Start a new note and enter the attack stage from silence.
pub fn Adsr::gate_on(self : Adsr) -> Unit {
  self.level = 0.0
  self.level_at_release = 0.0
  self.stage = EnvStage::Attack
}

///|
/// Release the current note from the envelope's present level.
pub fn Adsr::gate_off(self : Adsr) -> Unit {
  if self.stage is EnvStage::Idle {
    return
  }
  self.level_at_release = self.level
  self.stage = EnvStage::Release
}

///|
/// Reset the envelope to idle silence.
pub fn Adsr::reset(self : Adsr) -> Unit {
  self.stage = EnvStage::Idle
  self.level = 0.0
  self.level_at_release = 0.0
}

///|
/// Advance the envelope by one sample using the given DSP context.
pub fn Adsr::tick(self : Adsr, context : DspContext) -> Double {
  let sample_rate = context.sample_rate()
  self.tick_with_sample_rate(sample_rate)
}

///|
fn Adsr::tick_with_sample_rate(self : Adsr, sample_rate : Double) -> Double {
  if !is_finite_positive(sample_rate) {
    self.reset()
    return 0.0
  }

  // WHY bounded loop: zero-time stages (e.g. attack_ms=0) advance to the next
  // stage without producing a sample. The loop re-evaluates until a non-zero
  // stage is reached. Bound of 4 = number of ADSR stages, guaranteeing termination.
  for transitions = 0; transitions < 4; transitions = transitions + 1 {
    match self.stage {
      Idle => {
        self.level = 0.0
        break
      }
      Attack =>
        if self.attack_ms <= 0.0 {
          self.level = 1.0
          self.stage = EnvStage::Decay
          continue
        } else {
          self.level += 1000.0 / (self.attack_ms * sample_rate)
          if self.level >= 1.0 {
            self.level = 1.0
            self.stage = EnvStage::Decay
          }
          break
        }
      Decay =>
        if self.decay_ms <= 0.0 {
          self.level = self.sustain
          self.stage = EnvStage::Sustain
          continue
        } else {
          self.level -= (1.0 - self.sustain) *
            1000.0 /
            (self.decay_ms * sample_rate)
          if self.level <= self.sustain {
            self.level = self.sustain
            self.stage = EnvStage::Sustain
          }
          break
        }
      Sustain => {
        self.level = self.sustain
        break
      }
      Release => {
        if self.release_ms <= 0.0 || self.level_at_release <= 0.0 {
          self.level = 0.0
          self.stage = EnvStage::Idle
        } else {
          self.level -= self.level_at_release *
            1000.0 /
            (self.release_ms * sample_rate)
          if self.level <= 0.0 {
            self.level = 0.0
            self.stage = EnvStage::Idle
          }
        }
        break
      }
    }
  }
  self.level
}

///|
/// Fill a buffer with successive envelope values.
pub fn Adsr::process(
  self : Adsr,
  context : DspContext,
  output : AudioBuffer,
) -> Unit {
  let sample_rate = context.sample_rate()
  let sample_count = effective_sample_count(context, output)
  if !is_finite_positive(sample_rate) {
    output.fill(0.0)
    self.reset()
    return
  }
  if sample_count <= 0 {
    return
  }

  for index = 0; index < sample_count; index = index + 1 {
    output.set(index, self.tick(context))
  }

  for index = sample_count; index < output.length(); index = index + 1 {
    output.set(index, 0.0)
  }
}

///|
fn normalize_time_ms(value : Double) -> Double {
  if value.is_nan() || value.is_inf() || value < 0.0 {
    0.0
  } else {
    value
  }
}

///|
fn normalize_sustain(value : Double) -> Double {
  if !is_finite(value) {
    0.0
  } else {
    value.clamp(min=0.0, max=1.0)
  }
}
