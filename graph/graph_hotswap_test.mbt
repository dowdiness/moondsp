///|
const HOT_SWAP_SAMPLE_RATE : Double = 48000.0

///|
const HOT_SWAP_BLOCK_SIZE : Int = 4

///|
const HOT_SWAP_EPSILON : Double = 0.000000001

///|
const HOT_SWAP_CROSSFADE_SAMPLES : Int = 8

///|
const HOT_SWAP_CENTER_GAIN : Double = 0.7071067811865476

///|
test "compiled dsp hot swap crossfades equal-power between graphs" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let old_graph = CompiledDsp::compile(
    [DspNode::constant(0.0), DspNode::output(0)],
    context,
  ).unwrap()
  let new_graph = CompiledDsp::compile(
    [DspNode::constant(1.0), DspNode::output(0)],
    context,
  ).unwrap()
  let hot_swap = CompiledDspHotSwap::from_graph(
    old_graph,
    crossfade_samples=HOT_SWAP_CROSSFADE_SAMPLES,
  )
  let first_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let second_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let settled_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  assert_true(hot_swap.queue_swap(new_graph))
  hot_swap.process(context, first_block)
  hot_swap.process(context, second_block)
  hot_swap.process(context, settled_block)

  assert_true((first_block.get(0) - 0.0).abs() < HOT_SWAP_EPSILON)
  assert_true(
    (first_block.get(1) - 0.19509032201612825).abs() < HOT_SWAP_EPSILON,
  )
  assert_true(
    (first_block.get(2) - 0.3826834323650898).abs() < HOT_SWAP_EPSILON,
  )
  assert_true(
    (first_block.get(3) - 0.5555702330196022).abs() < HOT_SWAP_EPSILON,
  )
  assert_true(
    (second_block.get(0) - 0.7071067811865475).abs() < HOT_SWAP_EPSILON,
  )
  assert_true(
    (second_block.get(1) - 0.8314696123025452).abs() < HOT_SWAP_EPSILON,
  )
  assert_true(
    (second_block.get(2) - 0.9238795325112867).abs() < HOT_SWAP_EPSILON,
  )
  assert_true(
    (second_block.get(3) - 0.9807852804032304).abs() < HOT_SWAP_EPSILON,
  )
  assert_true(settled_block.as_fixed_array().every(sample => sample == 1.0))
}

///|
test "compiled dsp hot swap can replace instantly" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let old_graph = CompiledDsp::compile(
    [DspNode::constant(0.25), DspNode::output(0)],
    context,
  ).unwrap()
  let new_graph = CompiledDsp::compile(
    [DspNode::constant(0.75), DspNode::output(0)],
    context,
  ).unwrap()
  let hot_swap = CompiledDspHotSwap::from_graph(old_graph)
  let output = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  assert_true(hot_swap.queue_swap(new_graph))
  hot_swap.process(context, output)

  assert_true(output.as_fixed_array().every(sample => sample == 0.75))
}

///|
test "compiled dsp hot swap rejects incompatible replacement graph" {
  let active_context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let incompatible_context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=8,
  )
  let active = CompiledDsp::compile(
    [DspNode::constant(0.0), DspNode::output(0)],
    active_context,
  ).unwrap()
  let incompatible = CompiledDsp::compile(
    [DspNode::constant(1.0), DspNode::output(0)],
    incompatible_context,
  ).unwrap()
  let hot_swap = CompiledDspHotSwap::from_graph(active)
  let output = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  assert_false(hot_swap.queue_swap(incompatible))
  hot_swap.process(active_context, output)

  assert_true(output.as_fixed_array().every(sample => sample == 0.0))
}

///|
test "compiled dsp hot swap mirrors runtime param changes into pending graph" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let active = CompiledDsp::compile(
    [DspNode::constant(1.0), DspNode::gain(0, 0.25), DspNode::output(1)],
    context,
  ).unwrap()
  let replacement = CompiledDsp::compile(
    [DspNode::constant(1.0), DspNode::gain(0, 0.75), DspNode::output(1)],
    context,
  ).unwrap()
  let hot_swap = CompiledDspHotSwap::from_graph(
    active,
    crossfade_samples=HOT_SWAP_CROSSFADE_SAMPLES,
  )
  let first_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let second_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let settled_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  assert_true(hot_swap.queue_swap(replacement))
  assert_true(
    hot_swap.apply_control(
      GraphControl::set_param(1, GraphParamSlot::Value0, 0.5),
    ),
  )
  hot_swap.process(context, first_block)
  hot_swap.process(context, second_block)
  hot_swap.process(context, settled_block)

  assert_true(
    first_block
    .as_fixed_array()
    .every(sample => !sample.is_nan() && !sample.is_inf() && sample >= 0.5),
  )
  assert_true(
    second_block
    .as_fixed_array()
    .every(sample => !sample.is_nan() && !sample.is_inf() && sample >= 0.5),
  )
  assert_true(settled_block.as_fixed_array().every(sample => sample == 0.5))
}

///|
test "compiled stereo dsp hot swap crossfades equal-power between graphs" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let old_graph = CompiledStereoDsp::compile(
    [DspNode::constant(0.0), DspNode::pan(0, 0.0), DspNode::stereo_output(1)],
    context,
  ).unwrap()
  let new_graph = CompiledStereoDsp::compile(
    [DspNode::constant(1.0), DspNode::pan(0, 0.0), DspNode::stereo_output(1)],
    context,
  ).unwrap()
  let hot_swap = CompiledStereoDspHotSwap::from_graph(
    old_graph,
    crossfade_samples=HOT_SWAP_CROSSFADE_SAMPLES,
  )
  let first_left = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let first_right = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let second_left = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let second_right = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let settled_left = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let settled_right = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  assert_true(hot_swap.queue_swap(new_graph))
  hot_swap.process(context, first_left, first_right)
  hot_swap.process(context, second_left, second_right)
  hot_swap.process(context, settled_left, settled_right)

  assert_true((first_left.get(0) - 0.0).abs() < HOT_SWAP_EPSILON)
  assert_true(
    (first_left.get(1) - 0.19509032201612825 * HOT_SWAP_CENTER_GAIN).abs() <
    HOT_SWAP_EPSILON,
  )
  assert_true(
    (first_left.get(2) - 0.3826834323650898 * HOT_SWAP_CENTER_GAIN).abs() <
    HOT_SWAP_EPSILON,
  )
  assert_true(
    (first_left.get(3) - 0.5555702330196022 * HOT_SWAP_CENTER_GAIN).abs() <
    HOT_SWAP_EPSILON,
  )
  assert_true(
    (second_left.get(0) - 0.7071067811865475 * HOT_SWAP_CENTER_GAIN).abs() <
    HOT_SWAP_EPSILON,
  )
  assert_true(
    (second_left.get(1) - 0.8314696123025452 * HOT_SWAP_CENTER_GAIN).abs() <
    HOT_SWAP_EPSILON,
  )
  assert_true(
    (second_left.get(2) - 0.9238795325112867 * HOT_SWAP_CENTER_GAIN).abs() <
    HOT_SWAP_EPSILON,
  )
  assert_true(
    (second_left.get(3) - 0.9807852804032304 * HOT_SWAP_CENTER_GAIN).abs() <
    HOT_SWAP_EPSILON,
  )
  assert_true(
    first_left
    .as_fixed_array()
    .all(sample => sample >= 0.0 && sample <= HOT_SWAP_CENTER_GAIN),
  )
  assert_true(
    second_left
    .as_fixed_array()
    .all(sample => sample >= 0.0 && sample <= HOT_SWAP_CENTER_GAIN),
  )
  assert_true(
    settled_left
    .as_fixed_array()
    .every(sample => (sample - HOT_SWAP_CENTER_GAIN).abs() < HOT_SWAP_EPSILON),
  )
  assert_true(
    settled_right
    .as_fixed_array()
    .every(sample => (sample - HOT_SWAP_CENTER_GAIN).abs() < HOT_SWAP_EPSILON),
  )
  assert_true(hot_swap_buffers_equal(first_left, first_right, HOT_SWAP_EPSILON))
  assert_true(
    hot_swap_buffers_equal(second_left, second_right, HOT_SWAP_EPSILON),
  )
}

///|
test "compiled stereo dsp hot swap mirrors pan changes into pending graph" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let active = CompiledStereoDsp::compile(
    [DspNode::constant(0.5), DspNode::pan(0, 0.0), DspNode::stereo_output(1)],
    context,
  ).unwrap()
  let replacement = CompiledStereoDsp::compile(
    [DspNode::constant(1.0), DspNode::pan(0, 0.0), DspNode::stereo_output(1)],
    context,
  ).unwrap()
  let hot_swap = CompiledStereoDspHotSwap::from_graph(
    active,
    crossfade_samples=HOT_SWAP_CROSSFADE_SAMPLES,
  )
  let first_left = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let first_right = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let second_left = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let second_right = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let settled_left = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let settled_right = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  assert_true(hot_swap.queue_swap(replacement))
  assert_true(
    hot_swap.apply_control(
      GraphControl::set_param(1, GraphParamSlot::Value0, 1.0),
    ),
  )
  hot_swap.process(context, first_left, first_right)
  hot_swap.process(context, second_left, second_right)
  hot_swap.process(context, settled_left, settled_right)

  assert_true(
    first_left.as_fixed_array().every(sample => sample.abs() < HOT_SWAP_EPSILON),
  )
  assert_true(
    second_left
    .as_fixed_array()
    .every(sample => sample.abs() < HOT_SWAP_EPSILON),
  )
  assert_true(
    settled_left
    .as_fixed_array()
    .every(sample => sample.abs() < HOT_SWAP_EPSILON),
  )
  assert_true(
    first_right
    .as_fixed_array()
    .every(sample => !sample.is_nan() && !sample.is_inf() && sample >= 0.5),
  )
  assert_true(
    second_right
    .as_fixed_array()
    .every(sample => !sample.is_nan() && !sample.is_inf() && sample >= 1.0),
  )
  assert_true(settled_right.as_fixed_array().every(sample => sample == 1.0))
}

///|
fn hot_swap_buffers_equal(
  left : AudioBuffer,
  right : AudioBuffer,
  epsilon : Double,
) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for index = 0; index < left.length(); index = index + 1 {
    if (left.get(index) - right.get(index)).abs() > epsilon {
      return false
    }
  }
  true
}
