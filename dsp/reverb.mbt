///|
const REVERB_REFERENCE_SAMPLE_RATE : Double = 44100.0

///|
const REVERB_INPUT_GAIN : Double = 0.015

///|
const REVERB_OUTPUT_GAIN : Double = 0.12

///|
const REVERB_DEFAULT_SAMPLE_RATE : Double = 48000.0

///|
const REVERB_DEFAULT_DECAY_SECONDS : Double = 2.4

///|
const REVERB_DEFAULT_DAMPING : Double = 0.35

///|
priv struct ReverbComb {
  buffer : FixedArray[Double]
  mut position : Int
  feedback : Double
  damping : Double
  mut filter_state : Double
}

///|
fn ReverbComb::ReverbComb(
  size : Int,
  sample_rate : Double,
  decay_seconds : Double,
  damping : Double,
) -> ReverbComb {
  let delay_seconds = size.to_double() / sample_rate
  let feedback = @math.pow(0.001, delay_seconds / decay_seconds).clamp(
    min=0.0,
    max=0.999,
  )
  {
    buffer: FixedArray::make(size, 0.0),
    position: 0,
    feedback,
    damping,
    filter_state: 0.0,
  }
}

///|
fn reverb_finite_state(value : Double) -> Double {
  if !is_finite(value) || value.abs() < 1.0e-30 {
    0.0
  } else {
    value
  }
}

///|
fn ReverbComb::reset(self : ReverbComb) -> Unit {
  self.buffer.fill(0.0)
  self.position = 0
  self.filter_state = 0.0
}

///|
fn ReverbComb::tick(self : ReverbComb, input : Double) -> Double {
  let delayed = reverb_finite_state(self.buffer[self.position])
  let filtered = reverb_finite_state(
    delayed * (1.0 - self.damping) + self.filter_state * self.damping,
  )
  self.filter_state = filtered
  self.buffer[self.position] = reverb_finite_state(
    input + filtered * self.feedback,
  )
  self.position += 1
  if self.position == self.buffer.length() {
    self.position = 0
  }
  delayed
}

///|
priv struct ReverbAllpass {
  buffer : FixedArray[Double]
  mut position : Int
}

///|
fn ReverbAllpass::ReverbAllpass(size : Int) -> ReverbAllpass {
  { buffer: FixedArray::make(size, 0.0), position: 0, }
}

///|
fn ReverbAllpass::reset(self : ReverbAllpass) -> Unit {
  self.buffer.fill(0.0)
  self.position = 0
}

///|
fn ReverbAllpass::tick(self : ReverbAllpass, input : Double) -> Double {
  let delayed = reverb_finite_state(self.buffer[self.position])
  let output = reverb_finite_state(delayed - input)
  self.buffer[self.position] = reverb_finite_state(input + delayed * 0.5)
  self.position += 1
  if self.position == self.buffer.length() {
    self.position = 0
  }
  output
}

///|
/// Wet-only stereo room reverb with fixed delay lengths and preallocated state.
///
/// The network is eight parallel damped feedback combs followed by four serial
/// allpasses per channel. Delay lengths use the published Freeverb tunings,
/// scaled once for the requested sample rate. `decay_seconds` is the low-
/// frequency T60; `damping` is a normalized high-frequency loss coefficient.
pub struct StereoReverb {
  priv left_combs : Array[ReverbComb]
  priv right_combs : Array[ReverbComb]
  priv left_allpasses : Array[ReverbAllpass]
  priv right_allpasses : Array[ReverbAllpass]
}

///|
fn reverb_scaled_delay(base : Int, sample_rate : Double) -> Int {
  let scaled = (base.to_double() * sample_rate / REVERB_REFERENCE_SAMPLE_RATE)
    .round()
    .to_int()
  if scaled > 0 {
    scaled
  } else {
    1
  }
}

///|
pub fn StereoReverb::StereoReverb(
  sample_rate : Double,
  decay_seconds? : Double = REVERB_DEFAULT_DECAY_SECONDS,
  damping? : Double = REVERB_DEFAULT_DAMPING,
) -> StereoReverb {
  let safe_rate = if is_finite_positive(sample_rate) {
    sample_rate
  } else {
    REVERB_DEFAULT_SAMPLE_RATE
  }
  let safe_decay = if !is_finite(decay_seconds) {
    REVERB_DEFAULT_DECAY_SECONDS
  } else {
    decay_seconds.clamp(min=0.2, max=20.0)
  }
  let safe_damping = if !is_finite(damping) {
    REVERB_DEFAULT_DAMPING
  } else {
    damping.clamp(min=0.0, max=0.95)
  }
  let comb_tunings = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
  let allpass_tunings = [556, 441, 341, 225]
  let stereo_spread = reverb_scaled_delay(23, safe_rate)
  {
    left_combs: comb_tunings.map(n => {
      ReverbComb(
        reverb_scaled_delay(n, safe_rate),
        safe_rate,
        safe_decay,
        safe_damping,
      )
    }),
    right_combs: comb_tunings.map(n => {
      ReverbComb(
        reverb_scaled_delay(n, safe_rate) + stereo_spread,
        safe_rate,
        safe_decay,
        safe_damping,
      )
    }),
    left_allpasses: allpass_tunings.map(n => {
      ReverbAllpass(reverb_scaled_delay(n, safe_rate))
    }),
    right_allpasses: allpass_tunings.map(n => {
      ReverbAllpass(reverb_scaled_delay(n, safe_rate) + stereo_spread)
    }),
  }
}

///|
/// Clear the complete late-field state. Ordinary zero-input processing should
/// be used to preserve and drain a tail; reset is for an explicit hard stop.
pub fn StereoReverb::reset(self : StereoReverb) -> Unit {
  for comb in self.left_combs {
    comb.reset()
  }
  for comb in self.right_combs {
    comb.reset()
  }
  for allpass in self.left_allpasses {
    allpass.reset()
  }
  for allpass in self.right_allpasses {
    allpass.reset()
  }
}

///|
fn reverb_channel_tick(
  combs : Array[ReverbComb],
  allpasses : Array[ReverbAllpass],
  input : Double,
) -> Double {
  let mut output = 0.0
  for comb in combs {
    output += comb.tick(input)
  }
  for allpass in allpasses {
    output = allpass.tick(output)
  }
  reverb_finite_state(output * REVERB_OUTPUT_GAIN)
}

///|
/// Render wet stereo only. Inputs and outputs may be reused across calls; no
/// allocation occurs in this audio-rate path.
pub fn StereoReverb::process(
  self : StereoReverb,
  context : DspContext,
  left_input : AudioBuffer,
  right_input : AudioBuffer,
  left_output : AudioBuffer,
  right_output : AudioBuffer,
) -> Unit {
  let mut count = effective_sample_count(context, left_input)
  if right_input.length() < count {
    count = right_input.length()
  }
  if left_output.length() < count {
    count = left_output.length()
  }
  if right_output.length() < count {
    count = right_output.length()
  }
  for i in 0..<count {
    let input = reverb_finite_state(
      (left_input.get(i) + right_input.get(i)) * REVERB_INPUT_GAIN,
    )
    left_output.set(
      i,
      reverb_channel_tick(self.left_combs, self.left_allpasses, input),
    )
    right_output.set(
      i,
      reverb_channel_tick(self.right_combs, self.right_allpasses, input),
    )
  }
  for i in count..<left_output.length() {
    left_output.set(i, 0.0)
  }
  for i in count..<right_output.length() {
    right_output.set(i, 0.0)
  }
}
