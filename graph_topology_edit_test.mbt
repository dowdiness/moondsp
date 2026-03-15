///|
test "compiled dsp topology controller crossfades a replaced node" {
  let context = DspContext::new(HOT_SWAP_SAMPLE_RATE, HOT_SWAP_BLOCK_SIZE)
  let topology = CompiledDspTopologyController::from_nodes(
    [DspNode::constant(1.0), DspNode::gain(0, 0.25), DspNode::output(1)],
    context,
    crossfade_samples=HOT_SWAP_CROSSFADE_SAMPLES,
  ).unwrap()
  let first_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let second_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let settled_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  assert_true(
    topology.queue_topology_edit(
      GraphTopologyEdit::replace_node(1, DspNode::gain(0, 0.75)),
    ),
  )
  topology.process(context, first_block)
  topology.process(context, second_block)
  topology.process(context, settled_block)

  for index = 0; index < HOT_SWAP_BLOCK_SIZE; index = index + 1 {
    let first_progress = topology_test_hot_swap_progress(
      index,
      HOT_SWAP_CROSSFADE_SAMPLES,
    )
    let first_expected = 0.25 * topology_test_old_gain(first_progress) +
      0.75 * topology_test_new_gain(first_progress)
    assert_true(
      (first_block.get(index) - first_expected).abs() < HOT_SWAP_EPSILON,
    )

    let second_position = HOT_SWAP_BLOCK_SIZE + index
    let second_progress = topology_test_hot_swap_progress(
      second_position,
      HOT_SWAP_CROSSFADE_SAMPLES,
    )
    let second_expected = 0.25 * topology_test_old_gain(second_progress) +
      0.75 * topology_test_new_gain(second_progress)
    assert_true(
      (second_block.get(index) - second_expected).abs() < HOT_SWAP_EPSILON,
    )
  }
  assert_true(settled_block.as_fixed_array().every(sample => sample == 0.75))
}

///|
test "compiled dsp topology controller rejects invalid edit batches transactionally" {
  let context = DspContext::new(HOT_SWAP_SAMPLE_RATE, HOT_SWAP_BLOCK_SIZE)
  let topology = CompiledDspTopologyController::from_nodes(
    [DspNode::constant(1.0), DspNode::gain(0, 0.25), DspNode::output(1)],
    context,
  ).unwrap()
  let output = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  assert_false(
    topology.queue_topology_edits([
      GraphTopologyEdit::replace_node(0, DspNode::constant(0.5)),
      GraphTopologyEdit::replace_node(2, DspNode::gain(1, 0.5)),
    ]),
  )
  topology.process(context, output)

  assert_true(output.as_fixed_array().every(sample => sample == 0.25))
}

///|
test "compiled dsp topology controller mirrors runtime params into queued edit" {
  let context = DspContext::new(HOT_SWAP_SAMPLE_RATE, HOT_SWAP_BLOCK_SIZE)
  let topology = CompiledDspTopologyController::from_nodes(
    [DspNode::constant(1.0), DspNode::gain(0, 0.25), DspNode::output(1)],
    context,
    crossfade_samples=HOT_SWAP_CROSSFADE_SAMPLES,
  ).unwrap()
  let first_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let second_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let settled_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  assert_true(
    topology.queue_topology_edit(
      GraphTopologyEdit::replace_node(1, DspNode::gain(0, 0.75)),
    ),
  )
  assert_true(
    topology.apply_control(
      GraphControl::set_param(1, GraphParamSlot::Value0, 0.5),
    ),
  )
  topology.process(context, first_block)
  topology.process(context, second_block)
  topology.process(context, settled_block)

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
fn topology_test_hot_swap_progress(
  position : Int,
  crossfade_samples : Int,
) -> Double {
  if crossfade_samples <= 0 {
    1.0
  } else if position <= 0 {
    0.0
  } else if position >= crossfade_samples {
    1.0
  } else {
    position.to_double() / crossfade_samples.to_double()
  }
}

///|
fn topology_test_old_gain(progress : Double) -> Double {
  @math.cos(progress * 0.5 * @math.PI)
}

///|
fn topology_test_new_gain(progress : Double) -> Double {
  @math.sin(progress * 0.5 * @math.PI)
}
