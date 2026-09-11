///|
fn reverb_test_context() -> DspContext {
  DspContext(sample_rate=48000.0, block_size=128)
}

///|
fn render_reverb_block(
  reverb : StereoReverb,
  context : DspContext,
  left_input : AudioBuffer,
  right_input : AudioBuffer,
  left_output : AudioBuffer,
  right_output : AudioBuffer,
) -> (Double, Double) raise {
  reverb.process(context, left_input, right_input, left_output, right_output)
  let mut energy = 0.0
  let mut stereo_difference = 0.0
  for i in 0..<context.block_size() {
    let left = left_output.get(i)
    let right = right_output.get(i)
    assert_true(is_finite(left))
    assert_true(is_finite(right))
    energy += left * left + right * right
    stereo_difference += (left - right).abs()
  }
  (energy, stereo_difference)
}

///|
test "stereo reverb keeps a decorrelated tail after input stops" {
  let context = reverb_test_context()
  let reverb = StereoReverb::StereoReverb(
    48000.0,
    decay_seconds=2.4,
    damping=0.35,
  )
  let left_input = context.make_buffer()
  let right_input = context.make_buffer()
  let left_output = context.make_buffer()
  let right_output = context.make_buffer()
  left_input.set(0, 1.0)
  let mut tail_energy = 0.0
  let mut stereo_difference = 0.0
  for block in 0..<900 {
    let (energy, difference) = render_reverb_block(
      reverb, context, left_input, right_input, left_output, right_output,
    )
    if block > 20 {
      tail_energy += energy
      stereo_difference += difference
    }
    left_input.fill(0.0)
  }
  assert_true(tail_energy > 0.000001)
  assert_true(stereo_difference > 0.000001)
}

///|
test "longer reverb T60 retains more late energy" {
  let context = reverb_test_context()
  let short = StereoReverb::StereoReverb(
    48000.0,
    decay_seconds=0.4,
    damping=0.35,
  )
  let long = StereoReverb::StereoReverb(
    48000.0,
    decay_seconds=2.4,
    damping=0.35,
  )
  let short_left_input = context.make_buffer()
  let short_right_input = context.make_buffer()
  let long_left_input = context.make_buffer()
  let long_right_input = context.make_buffer()
  let short_left = context.make_buffer()
  let short_right = context.make_buffer()
  let long_left = context.make_buffer()
  let long_right = context.make_buffer()
  short_left_input.set(0, 1.0)
  long_left_input.set(0, 1.0)
  let mut short_late_energy = 0.0
  let mut long_late_energy = 0.0
  for block in 0..<900 {
    let (short_energy, _) = render_reverb_block(
      short, context, short_left_input, short_right_input, short_left, short_right,
    )
    let (long_energy, _) = render_reverb_block(
      long, context, long_left_input, long_right_input, long_left, long_right,
    )
    if block >= 600 {
      short_late_energy += short_energy
      long_late_energy += long_energy
    }
    short_left_input.fill(0.0)
    long_left_input.fill(0.0)
  }
  assert_true(long_late_energy > short_late_energy * 100.0)
}

///|
test "reverb rejects non-finite excitation and reset clears its tail" {
  let context = reverb_test_context()
  let reverb = StereoReverb::StereoReverb(48000.0)
  let left_input = context.make_buffer()
  let right_input = context.make_buffer()
  let left_output = context.make_buffer()
  let right_output = context.make_buffer()
  left_input.set(0, @double.not_a_number)
  right_input.set(0, @double.infinity)
  ignore(
    render_reverb_block(
      reverb, context, left_input, right_input, left_output, right_output,
    ),
  )
  left_input.fill(0.0)
  right_input.fill(0.0)
  left_input.set(0, 1.0)
  for _ in 0..<20 {
    ignore(
      render_reverb_block(
        reverb, context, left_input, right_input, left_output, right_output,
      ),
    )
    left_input.fill(0.0)
  }
  reverb.reset()
  let (energy, _) = render_reverb_block(
    reverb, context, left_input, right_input, left_output, right_output,
  )
  assert_true(energy == 0.0)
}
