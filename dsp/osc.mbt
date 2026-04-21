///|
/// Supported oscillator waveforms for the Phase 1 source primitive.
pub(all) enum Waveform {
  Sine
  Saw
  Square
  Triangle
} derive(Eq)

///|
/// Stateful oscillator for the first reusable Phase 1 DSP primitive.
pub struct Oscillator {
  mut phase : Double
}

///|
/// Create a new oscillator at phase zero.
pub fn Oscillator::new() -> Oscillator {
  { phase: 0.0 }
}

///|
/// Reset the oscillator to the start of the waveform.
pub fn Oscillator::reset(self : Oscillator) -> Unit {
  self.phase = 0.0
}

///|
/// Expose the current phase for testing and diagnostics.
pub fn Oscillator::phase(self : Oscillator) -> Double {
  self.phase
}

///|
/// Generate one sample for the selected waveform and advance the oscillator
/// state.
pub fn Oscillator::tick_waveform(
  self : Oscillator,
  waveform : Waveform,
  freq : Double,
  sample_rate : Double,
) -> Double {
  if !is_finite(freq) || !is_finite(sample_rate) || sample_rate <= 0.0 {
    return 0.0
  }
  let out = sample_for_phase(waveform, self.phase)
  self.phase = wrap_phase(self.phase + freq / sample_rate)
  out
}

///|
/// Generate one sine sample and advance the oscillator state.
pub fn Oscillator::tick(
  self : Oscillator,
  freq : Double,
  sample_rate : Double,
) -> Double {
  self.tick_waveform(Waveform::Sine, freq, sample_rate)
}

///|
/// Fill an output buffer with samples for the selected waveform.
pub fn Oscillator::process_waveform(
  self : Oscillator,
  context : DspContext,
  output : AudioBuffer,
  waveform : Waveform,
  freq : Double,
) -> Unit {
  let sample_rate = context.sample_rate()
  let sample_count = effective_sample_count(context, output)

  if !is_finite(freq) ||
    !is_finite(sample_rate) ||
    sample_rate <= 0.0 ||
    sample_count <= 0 {
    output.fill(0.0)
    return
  }

  for index = 0; index < sample_count; index = index + 1 {
    output.set(index, self.tick_waveform(waveform, freq, sample_rate))
  }

  for index = sample_count; index < output.length(); index = index + 1 {
    output.set(index, 0.0)
  }
}

///|
/// Fill an output buffer with oscillator samples.
pub fn Oscillator::process(
  self : Oscillator,
  context : DspContext,
  output : AudioBuffer,
  freq_hz~ : Double,
) -> Unit {
  self.process_waveform(context, output, Waveform::Sine, freq_hz)
}

///|
fn sample_for_phase(waveform : Waveform, phase : Double) -> Double {
  match waveform {
    Sine => @math.sin(phase * 6.283185307179586)
    Saw => 2.0 * phase - 1.0
    Square => if phase < 0.5 { 1.0 } else { -1.0 }
    Triangle => if phase < 0.5 { 4.0 * phase - 1.0 } else { 3.0 - 4.0 * phase }
  }
}

///|
fn wrap_phase(phase : Double) -> Double {
  if phase >= 1.0 {
    phase - @math.floor(phase)
  } else if phase < 0.0 {
    phase - @math.floor(phase)
  } else {
    phase
  }
}
