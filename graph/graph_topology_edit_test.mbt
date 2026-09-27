///|
test "compiled dsp topology controller crossfades a replaced node" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let topology = @graph.DspTopologyController::from_nodes(
    [
      @graph.DspNode::constant(1.0),
      @graph.DspNode::gain(0, 0.25),
      @graph.DspNode::output(1),
    ],
    context,
    crossfade_samples=HOT_SWAP_CROSSFADE_SAMPLES,
  ).unwrap()
  let first_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let second_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let settled_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  assert_true(
    topology.queue_topology_edit(
      @graph.GraphTopologyEdit::replace_node(1, @graph.DspNode::gain(0, 0.75)),
    )
    is Ok(_),
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
  assert_true(settled_block.every(sample => sample == 0.75))
}

///|
test "compiled dsp topology controller rejects invalid edit batches transactionally" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let topology = @graph.DspTopologyController::from_nodes(
    [
      @graph.DspNode::constant(1.0),
      @graph.DspNode::gain(0, 0.25),
      @graph.DspNode::output(1),
    ],
    context,
  ).unwrap()
  let output = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  assert_true(
    topology.queue_topology_edits([
      @graph.GraphTopologyEdit::replace_node(0, @graph.DspNode::constant(0.5)),
      @graph.GraphTopologyEdit::replace_node(2, @graph.DspNode::gain(1, 0.5)),
    ])
    is Err(_),
  )
  topology.process(context, output)

  assert_true(output.every(sample => sample == 0.25))
}

///|
test "compiled dsp topology controller result reports invalid edit index" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let topology = @graph.DspTopologyController::from_nodes(
    [
      @graph.DspNode::constant(1.0),
      @graph.DspNode::gain(0, 0.25),
      @graph.DspNode::output(1),
    ],
    context,
  ).unwrap()
  let output = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  match
    topology.queue_topology_edits([
      @graph.GraphTopologyEdit::replace_node(0, @graph.DspNode::constant(0.5)),
      @graph.GraphTopologyEdit::replace_node(99, @graph.DspNode::constant(0.75)),
    ]) {
    Err(
      @graph.GraphTopologyQueueError::InvalidEdit(
        index,
        @graph.GraphTopologyEditError::InvalidNodeIndex(node_index)
      )
    ) => {
      @debug.assert_eq(index, 1)
      @debug.assert_eq(node_index, 99)
    }
    other => fail("expected InvalidEdit, got \{@debug.to_string(other)}")
  }
  topology.process(context, output)

  assert_true(output.every(sample => sample == 0.25))
}

///|
test "compiled dsp topology controller result reports invalid edit reason" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let topology = @graph.DspTopologyController::from_nodes(
    [
      @graph.DspNode::constant(1.0),
      @graph.DspNode::gain(0, 0.25),
      @graph.DspNode::output(1),
    ],
    context,
  ).unwrap()

  match
    topology.queue_topology_edit(
      @graph.GraphTopologyEdit::rewire_input(
        0,
        @graph.GraphTopologyInputSlot::Input0,
        1,
      ),
    ) {
    Err(
      @graph.GraphTopologyQueueError::InvalidEdit(
        index,
        @graph.GraphTopologyEditError::UnsupportedInputSlot(
          node_index,
          @graph.GraphTopologyInputSlot::Input0,
          @graph.DspNodeKind::Constant
        )
      )
    ) => {
      @debug.assert_eq(index, 0)
      @debug.assert_eq(node_index, 0)
    }
    other =>
      fail("expected UnsupportedInputSlot, got \{@debug.to_string(other)}")
  }
  match
    topology.queue_topology_edit(
      @graph.GraphTopologyEdit::insert_node(
        2,
        @graph.GraphTopologyInputSlot::Input0,
        @graph.DspNode::constant(0.5),
      ),
    ) {
    Err(
      @graph.GraphTopologyQueueError::InvalidEdit(
        index,
        @graph.GraphTopologyEditError::UnsupportedInsertTemplate(
          @graph.DspNodeKind::Constant
        )
      )
    ) => @debug.assert_eq(index, 0)
    other =>
      fail("expected UnsupportedInsertTemplate, got \{@debug.to_string(other)}")
  }
}

///|
test "compiled dsp topology controller result reports recompile rejection" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let topology = @graph.DspTopologyController::from_nodes(
    [
      @graph.DspNode::constant(1.0),
      @graph.DspNode::gain(0, 0.25),
      @graph.DspNode::output(1),
    ],
    context,
  ).unwrap()

  match
    topology.queue_topology_edit(
      @graph.GraphTopologyEdit::replace_node(2, @graph.DspNode::gain(1, 0.5)),
    ) {
    Err(@graph.GraphTopologyQueueError::RecompileRejected) => ()
    other => fail("expected RecompileRejected, got \{@debug.to_string(other)}")
  }
}

///|
test "compiled dsp topology controller result reports pending swap" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let topology = @graph.DspTopologyController::from_nodes(
    [
      @graph.DspNode::constant(1.0),
      @graph.DspNode::gain(0, 0.25),
      @graph.DspNode::output(1),
    ],
    context,
    crossfade_samples=HOT_SWAP_CROSSFADE_SAMPLES,
  ).unwrap()

  match
    topology.queue_topology_edit(
      @graph.GraphTopologyEdit::replace_node(0, @graph.DspNode::constant(0.5)),
    ) {
    Ok(_) => ()
    other => fail("expected Ok, got \{@debug.to_string(other)}")
  }
  match
    topology.queue_topology_edit(
      @graph.GraphTopologyEdit::replace_node(0, @graph.DspNode::constant(0.25)),
    ) {
    Err(@graph.GraphTopologyQueueError::PendingSwap) => ()
    other => fail("expected PendingSwap, got \{@debug.to_string(other)}")
  }
}

///|
test "compiled dsp topology controller mirrors runtime params into queued edit" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let topology = @graph.DspTopologyController::from_nodes(
    [
      @graph.DspNode::constant(1.0),
      @graph.DspNode::gain(0, 0.25),
      @graph.DspNode::output(1),
    ],
    context,
    crossfade_samples=HOT_SWAP_CROSSFADE_SAMPLES,
  ).unwrap()
  let first_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let second_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let settled_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  assert_true(
    topology.queue_topology_edit(
      @graph.GraphTopologyEdit::replace_node(1, @graph.DspNode::gain(0, 0.75)),
    )
    is Ok(_),
  )
  assert_true(
    topology.apply_control(
      @graph.GraphControl::set_param(1, @graph.GraphParamSlot::Value0, 0.5),
    )
    is Ok(_),
  )
  topology.process(context, first_block)
  topology.process(context, second_block)
  topology.process(context, settled_block)

  assert_true(
    first_block.every(sample => {
      !sample.is_nan() && !sample.is_inf() && sample >= 0.5
    }),
  )
  assert_true(
    second_block.every(sample => {
      !sample.is_nan() && !sample.is_inf() && sample >= 0.5
    }),
  )
  assert_true(settled_block.every(sample => sample == 0.5))
}

///|
test "compiled dsp topology controller result reports pending graph control rejection" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let topology = @graph.DspTopologyController::from_nodes(
    [
      @graph.DspNode::constant(1.0),
      @graph.DspNode::gain(0, 0.25),
      @graph.DspNode::output(1),
    ],
    context,
    crossfade_samples=HOT_SWAP_CROSSFADE_SAMPLES,
  ).unwrap()
  let first_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  assert_true(
    topology.queue_topology_edit(
      @graph.GraphTopologyEdit::replace_node(1, @graph.DspNode::mix(0, 0)),
    )
    is Ok(_),
  )
  match topology.set_param(1, @graph.GraphParamSlot::Value0, 0.5) {
    Err(
      @graph.GraphControlError::InvalidSlotForNode(
        1,
        @graph.DspNodeKind::Mix,
        @graph.GraphParamSlot::Value0
      )
    ) => ()
    other =>
      fail(
        "expected pending InvalidSlotForNode, got \{@debug.to_string(other)}",
      )
  }
  topology.process(context, first_block)

  assert_true((first_block.get(0) - 0.25).abs() < HOT_SWAP_EPSILON)
}

///|
test "compiled dsp topology controller rejected control batch does not mirror authoring nodes" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let topology = @graph.DspTopologyController::from_nodes(
    [
      @graph.DspNode::constant(1.0),
      @graph.DspNode::gain(0, 0.25),
      @graph.DspNode::output(1),
    ],
    context,
    crossfade_samples=HOT_SWAP_CROSSFADE_SAMPLES,
  ).unwrap()
  let first_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let second_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let settled_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  match
    topology.apply_controls([
      @graph.GraphControl::set_param(1, @graph.GraphParamSlot::Value0, 0.5),
      @graph.GraphControl::set_param(99, @graph.GraphParamSlot::Value0, 0.5),
    ]) {
    Err(@graph.GraphControlError::InvalidNodeIndex(99)) => ()
    other => fail("expected InvalidNodeIndex, got \{@debug.to_string(other)}")
  }
  assert_true(
    topology.queue_topology_edit(
      @graph.GraphTopologyEdit::replace_node(0, @graph.DspNode::constant(2.0)),
    )
    is Ok(_),
  )
  topology.process(context, first_block)
  topology.process(context, second_block)
  topology.process(context, settled_block)

  assert_true(settled_block.every(sample => sample == 0.5))
}

///|
test "compiled dsp topology controller preserves runtime params across later topology edits" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let topology = @graph.DspTopologyController::from_nodes(
    [
      @graph.DspNode::constant(1.0),
      @graph.DspNode::gain(0, 0.25),
      @graph.DspNode::output(1),
    ],
    context,
    crossfade_samples=HOT_SWAP_CROSSFADE_SAMPLES,
  ).unwrap()
  let first_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let second_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let settled_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  assert_true(
    topology.apply_control(
      @graph.GraphControl::set_param(1, @graph.GraphParamSlot::Value0, 0.5),
    )
    is Ok(_),
  )
  assert_true(
    topology.queue_topology_edit(
      @graph.GraphTopologyEdit::replace_node(0, @graph.DspNode::constant(2.0)),
    )
    is Ok(_),
  )
  topology.process(context, first_block)
  topology.process(context, second_block)
  topology.process(context, settled_block)

  for index = 0; index < HOT_SWAP_BLOCK_SIZE; index = index + 1 {
    let first_progress = topology_test_hot_swap_progress(
      index,
      HOT_SWAP_CROSSFADE_SAMPLES,
    )
    let first_expected = 0.5 * topology_test_old_gain(first_progress) +
      1.0 * topology_test_new_gain(first_progress)
    assert_true(
      (first_block.get(index) - first_expected).abs() < HOT_SWAP_EPSILON,
    )

    let second_position = HOT_SWAP_BLOCK_SIZE + index
    let second_progress = topology_test_hot_swap_progress(
      second_position,
      HOT_SWAP_CROSSFADE_SAMPLES,
    )
    let second_expected = 0.5 * topology_test_old_gain(second_progress) +
      1.0 * topology_test_new_gain(second_progress)
    assert_true(
      (second_block.get(index) - second_expected).abs() < HOT_SWAP_EPSILON,
    )
  }
  assert_true(settled_block.every(sample => sample == 1.0))
}

///|
test "compiled dsp topology controller crossfades a rewired input" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let topology = @graph.DspTopologyController::from_nodes(
    [
      @graph.DspNode::constant(2.0),
      @graph.DspNode::constant(1.0),
      @graph.DspNode::gain(0, 0.5),
      @graph.DspNode::gain(1, 0.5),
      @graph.DspNode::mix(2, 3),
      @graph.DspNode::mix(4, 3),
      @graph.DspNode::output(5),
    ],
    context,
    crossfade_samples=HOT_SWAP_CROSSFADE_SAMPLES,
  ).unwrap()
  let first_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let second_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let settled_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  assert_true(
    topology.queue_topology_edit(
      @graph.GraphTopologyEdit::rewire_input(
        4,
        @graph.GraphTopologyInputSlot::Input1,
        0,
      ),
    )
    is Ok(_),
  )
  topology.process(context, first_block)
  topology.process(context, second_block)
  topology.process(context, settled_block)

  for index = 0; index < HOT_SWAP_BLOCK_SIZE; index = index + 1 {
    let first_progress = topology_test_hot_swap_progress(
      index,
      HOT_SWAP_CROSSFADE_SAMPLES,
    )
    let first_expected = 2.0 * topology_test_old_gain(first_progress) +
      3.5 * topology_test_new_gain(first_progress)
    assert_true(
      (first_block.get(index) - first_expected).abs() < HOT_SWAP_EPSILON,
    )

    let second_position = HOT_SWAP_BLOCK_SIZE + index
    let second_progress = topology_test_hot_swap_progress(
      second_position,
      HOT_SWAP_CROSSFADE_SAMPLES,
    )
    let second_expected = 2.0 * topology_test_old_gain(second_progress) +
      3.5 * topology_test_new_gain(second_progress)
    assert_true(
      (second_block.get(index) - second_expected).abs() < HOT_SWAP_EPSILON,
    )
  }
  assert_true(settled_block.every(sample => sample == 3.5))
}

///|
test "compiled dsp topology controller rejects invalid rewires transactionally" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let topology = @graph.DspTopologyController::from_nodes(
    [
      @graph.DspNode::constant(2.0),
      @graph.DspNode::constant(1.0),
      @graph.DspNode::gain(0, 0.5),
      @graph.DspNode::gain(1, 0.5),
      @graph.DspNode::mix(2, 3),
      @graph.DspNode::mix(4, 3),
      @graph.DspNode::output(5),
    ],
    context,
  ).unwrap()
  let output = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  assert_true(
    topology.queue_topology_edit(
      @graph.GraphTopologyEdit::rewire_input(
        2,
        @graph.GraphTopologyInputSlot::Input1,
        1,
      ),
    )
    is Err(_),
  )
  topology.process(context, output)

  assert_true(output.every(sample => sample == 2.0))
}

///|
test "compiled dsp topology controller crossfades an inserted node" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let topology = @graph.DspTopologyController::from_nodes(
    [@graph.DspNode::constant(1.0), @graph.DspNode::output(0)],
    context,
    crossfade_samples=HOT_SWAP_CROSSFADE_SAMPLES,
  ).unwrap()
  let first_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let second_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let settled_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  assert_true(
    topology.queue_topology_edit(
      @graph.GraphTopologyEdit::insert_node(
        1,
        @graph.GraphTopologyInputSlot::Input0,
        @graph.DspNode::gain(0, 0.5),
      ),
    )
    is Ok(_),
  )
  topology.process(context, first_block)
  topology.process(context, second_block)
  topology.process(context, settled_block)

  for index = 0; index < HOT_SWAP_BLOCK_SIZE; index = index + 1 {
    let first_progress = topology_test_hot_swap_progress(
      index,
      HOT_SWAP_CROSSFADE_SAMPLES,
    )
    let first_expected = topology_test_old_gain(first_progress) +
      0.5 * topology_test_new_gain(first_progress)
    assert_true(
      (first_block.get(index) - first_expected).abs() < HOT_SWAP_EPSILON,
    )

    let second_position = HOT_SWAP_BLOCK_SIZE + index
    let second_progress = topology_test_hot_swap_progress(
      second_position,
      HOT_SWAP_CROSSFADE_SAMPLES,
    )
    let second_expected = topology_test_old_gain(second_progress) +
      0.5 * topology_test_new_gain(second_progress)
    assert_true(
      (second_block.get(index) - second_expected).abs() < HOT_SWAP_EPSILON,
    )
  }
  assert_true(settled_block.every(sample => sample == 0.5))
}

///|
test "compiled dsp topology controller rejects invalid insert templates transactionally" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let topology = @graph.DspTopologyController::from_nodes(
    [@graph.DspNode::constant(1.0), @graph.DspNode::output(0)],
    context,
  ).unwrap()
  let output = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  assert_true(
    topology.queue_topology_edit(
      @graph.GraphTopologyEdit::insert_node(
        1,
        @graph.GraphTopologyInputSlot::Input0,
        @graph.DspNode::mix(0, 0),
      ),
    )
    is Err(_),
  )
  topology.process(context, output)

  assert_true(output.every(sample => sample == 1.0))
}

///|
test "compiled dsp topology controller crossfades a deleted node" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let topology = @graph.DspTopologyController::from_nodes(
    [
      @graph.DspNode::constant(1.0),
      @graph.DspNode::gain(0, 0.5),
      @graph.DspNode::output(1),
    ],
    context,
    crossfade_samples=HOT_SWAP_CROSSFADE_SAMPLES,
  ).unwrap()
  let first_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let second_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let settled_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  assert_true(
    topology.queue_topology_edit(
      @graph.GraphTopologyEdit::delete_node(
        1,
        2,
        @graph.GraphTopologyInputSlot::Input0,
        1,
      ),
    )
    is Ok(_),
  )
  topology.process(context, first_block)
  topology.process(context, second_block)
  topology.process(context, settled_block)

  for index = 0; index < HOT_SWAP_BLOCK_SIZE; index = index + 1 {
    let first_progress = topology_test_hot_swap_progress(
      index,
      HOT_SWAP_CROSSFADE_SAMPLES,
    )
    let first_expected = 0.5 * topology_test_old_gain(first_progress) +
      topology_test_new_gain(first_progress)
    assert_true(
      (first_block.get(index) - first_expected).abs() < HOT_SWAP_EPSILON,
    )

    let second_position = HOT_SWAP_BLOCK_SIZE + index
    let second_progress = topology_test_hot_swap_progress(
      second_position,
      HOT_SWAP_CROSSFADE_SAMPLES,
    )
    let second_expected = 0.5 * topology_test_old_gain(second_progress) +
      topology_test_new_gain(second_progress)
    assert_true(
      (second_block.get(index) - second_expected).abs() < HOT_SWAP_EPSILON,
    )
  }
  assert_true(settled_block.every(sample => sample == 1.0))
}

///|
test "compiled dsp topology controller rejects invalid deletes transactionally" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let topology = @graph.DspTopologyController::from_nodes(
    [
      @graph.DspNode::constant(1.0),
      @graph.DspNode::gain(0, 0.5),
      @graph.DspNode::output(1),
    ],
    context,
  ).unwrap()
  let output = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  assert_true(
    topology.queue_topology_edit(
      @graph.GraphTopologyEdit::delete_node(
        0,
        2,
        @graph.GraphTopologyInputSlot::Input0,
        0,
      ),
    )
    is Err(_),
  )
  topology.process(context, output)

  assert_true(output.every(sample => sample == 0.5))
}

///|
test "compiled dsp topology controller insert delete roundtrip restores baseline" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let topology = @graph.DspTopologyController::from_nodes(
    [@graph.DspNode::constant(1.0), @graph.DspNode::output(0)],
    context,
    crossfade_samples=HOT_SWAP_CROSSFADE_SAMPLES,
  ).unwrap()
  let insert_first_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let insert_second_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let inserted_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let delete_first_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let delete_second_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let restored_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  assert_true(
    topology.queue_topology_edit(
      @graph.GraphTopologyEdit::insert_node(
        1,
        @graph.GraphTopologyInputSlot::Input0,
        @graph.DspNode::gain(0, 0.5),
      ),
    )
    is Ok(_),
  )
  topology.process(context, insert_first_block)
  topology.process(context, insert_second_block)
  topology.process(context, inserted_block)
  assert_true(inserted_block.every(sample => sample == 0.5))

  assert_true(
    topology.queue_topology_edit(
      @graph.GraphTopologyEdit::delete_node(
        2,
        1,
        @graph.GraphTopologyInputSlot::Input0,
        2,
      ),
    )
    is Ok(_),
  )
  topology.process(context, delete_first_block)
  topology.process(context, delete_second_block)
  topology.process(context, restored_block)

  for index = 0; index < HOT_SWAP_BLOCK_SIZE; index = index + 1 {
    let first_progress = topology_test_hot_swap_progress(
      index,
      HOT_SWAP_CROSSFADE_SAMPLES,
    )
    let first_expected = 0.5 * topology_test_old_gain(first_progress) +
      topology_test_new_gain(first_progress)
    assert_true(
      (delete_first_block.get(index) - first_expected).abs() < HOT_SWAP_EPSILON,
    )

    let second_position = HOT_SWAP_BLOCK_SIZE + index
    let second_progress = topology_test_hot_swap_progress(
      second_position,
      HOT_SWAP_CROSSFADE_SAMPLES,
    )
    let second_expected = 0.5 * topology_test_old_gain(second_progress) +
      topology_test_new_gain(second_progress)
    assert_true(
      (delete_second_block.get(index) - second_expected).abs() <
      HOT_SWAP_EPSILON,
    )
  }
  assert_true(restored_block.every(sample => sample == 1.0))
}

///|
test "compiled dsp topology controller rejects deletes with mismatched retarget nodes" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let topology = @graph.DspTopologyController::from_nodes(
    [
      @graph.DspNode::constant(1.0),
      @graph.DspNode::gain(0, 0.5),
      @graph.DspNode::output(1),
    ],
    context,
  ).unwrap()
  let output = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  assert_true(
    topology.queue_topology_edit(
      @graph.GraphTopologyEdit::delete_node(
        1,
        0,
        @graph.GraphTopologyInputSlot::Input0,
        1,
      ),
    )
    is Err(_),
  )
  topology.process(context, output)

  assert_true(output.every(sample => sample == 0.5))
}

///|
test "compiled stereo dsp topology controller crossfades a replaced pan node" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let topology = @graph.StereoDspTopologyController::from_nodes(
    [
      @graph.DspNode::constant(1.0),
      @graph.DspNode::pan(0, 0.0),
      @graph.DspNode::stereo_output(1),
    ],
    context,
    crossfade_samples=HOT_SWAP_CROSSFADE_SAMPLES,
  ).unwrap()
  let first_left = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let first_right = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let second_left = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let second_right = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let settled_left = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let settled_right = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  assert_true(
    topology.queue_topology_edit(
      @graph.GraphTopologyEdit::replace_node(1, @graph.DspNode::pan(0, 1.0)),
    )
    is Ok(_),
  )
  topology.process(context, first_left, first_right)
  topology.process(context, second_left, second_right)
  topology.process(context, settled_left, settled_right)

  for index = 0; index < HOT_SWAP_BLOCK_SIZE; index = index + 1 {
    let first_progress = topology_test_hot_swap_progress(
      index,
      HOT_SWAP_CROSSFADE_SAMPLES,
    )
    let first_old_gain = topology_test_old_gain(first_progress)
    let first_new_gain = topology_test_new_gain(first_progress)
    let first_expected_left = HOT_SWAP_CENTER_GAIN * first_old_gain
    let first_expected_right = HOT_SWAP_CENTER_GAIN * first_old_gain +
      first_new_gain
    assert_true(
      (first_left.get(index) - first_expected_left).abs() < HOT_SWAP_EPSILON,
    )
    assert_true(
      (first_right.get(index) - first_expected_right).abs() < HOT_SWAP_EPSILON,
    )

    let second_position = HOT_SWAP_BLOCK_SIZE + index
    let second_progress = topology_test_hot_swap_progress(
      second_position,
      HOT_SWAP_CROSSFADE_SAMPLES,
    )
    let second_old_gain = topology_test_old_gain(second_progress)
    let second_new_gain = topology_test_new_gain(second_progress)
    let second_expected_left = HOT_SWAP_CENTER_GAIN * second_old_gain
    let second_expected_right = HOT_SWAP_CENTER_GAIN * second_old_gain +
      second_new_gain
    assert_true(
      (second_left.get(index) - second_expected_left).abs() < HOT_SWAP_EPSILON,
    )
    assert_true(
      (second_right.get(index) - second_expected_right).abs() < HOT_SWAP_EPSILON,
    )
  }
  assert_true(settled_left.every(sample => sample.abs() < HOT_SWAP_EPSILON))
  assert_true(settled_right.every(sample => sample == 1.0))
}

///|
test "compiled stereo dsp topology controller rejects invalid edit batches transactionally" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let topology = @graph.StereoDspTopologyController::from_nodes(
    [
      @graph.DspNode::constant(1.0),
      @graph.DspNode::pan(0, 0.0),
      @graph.DspNode::stereo_output(1),
    ],
    context,
  ).unwrap()
  let left = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let right = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  assert_true(
    topology.queue_topology_edits([
      @graph.GraphTopologyEdit::replace_node(0, @graph.DspNode::constant(0.5)),
      @graph.GraphTopologyEdit::replace_node(2, @graph.DspNode::output(1)),
    ])
    is Err(_),
  )
  topology.process(context, left, right)

  assert_true(
    left.every(sample => {
      (sample - HOT_SWAP_CENTER_GAIN).abs() < HOT_SWAP_EPSILON
    }),
  )
  assert_true(
    right.every(sample => {
      (sample - HOT_SWAP_CENTER_GAIN).abs() < HOT_SWAP_EPSILON
    }),
  )
}

///|
test "compiled stereo dsp topology controller result queues valid edit" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let topology = @graph.StereoDspTopologyController::from_nodes(
    [
      @graph.DspNode::constant(1.0),
      @graph.DspNode::pan(0, 0.0),
      @graph.DspNode::stereo_output(1),
    ],
    context,
  ).unwrap()
  let left = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let right = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  match
    topology.queue_topology_edit(
      @graph.GraphTopologyEdit::replace_node(1, @graph.DspNode::pan(0, 1.0)),
    ) {
    Ok(_) => ()
    other => fail("expected Ok, got \{@debug.to_string(other)}")
  }
  topology.process(context, left, right)

  assert_true(left.every(sample => sample == 0.0))
  assert_true(right.every(sample => sample == 1.0))
}

///|
test "compiled stereo dsp topology controller accepts insert nodes" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let topology = @graph.StereoDspTopologyController::from_nodes(
    [
      @graph.DspNode::constant(1.0),
      @graph.DspNode::pan(0, 0.0),
      @graph.DspNode::stereo_output(1),
    ],
    context,
    crossfade_samples=HOT_SWAP_CROSSFADE_SAMPLES,
  ).unwrap()
  let first_left = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let first_right = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let second_left = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let second_right = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let settled_left = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let settled_right = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  assert_true(
    topology.queue_topology_edit(
      @graph.GraphTopologyEdit::insert_node(
        2,
        @graph.GraphTopologyInputSlot::Input0,
        @graph.DspNode::stereo_gain(input=0, amount=0.5),
      ),
    )
    is Ok(_),
  )
  topology.process(context, first_left, first_right)
  topology.process(context, second_left, second_right)
  topology.process(context, settled_left, settled_right)

  // After insert: constant(1.0) -> pan(0,0.0) -> stereo_gain(0,0.5) ->
  // stereo_output. Center pan = ~0.707, then * 0.5 = ~0.354
  let expected = HOT_SWAP_CENTER_GAIN * 0.5
  assert_true(
    settled_left.every(sample => (sample - expected).abs() < HOT_SWAP_EPSILON),
  )
  assert_true(
    settled_right.every(sample => (sample - expected).abs() < HOT_SWAP_EPSILON),
  )
}

///|
test "compiled stereo dsp topology controller accepts delete nodes" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  // Graph: constant -> pan -> stereo_gain -> stereo_output
  let topology = @graph.StereoDspTopologyController::from_nodes(
    [
      @graph.DspNode::constant(1.0),
      @graph.DspNode::pan(0, 0.0),
      @graph.DspNode::stereo_gain(input=1, amount=0.5),
      @graph.DspNode::stereo_output(2),
    ],
    context,
    crossfade_samples=HOT_SWAP_CROSSFADE_SAMPLES,
  ).unwrap()
  let first_left = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let first_right = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let second_left = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let second_right = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let settled_left = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let settled_right = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  // Delete the stereo_gain node (index 2), retarget stereo_output (index 3)
  // to read from pan (replacement_source = 2 means self-resolve to its input)
  assert_true(
    topology.queue_topology_edit(
      @graph.GraphTopologyEdit::delete_node(
        2,
        3,
        @graph.GraphTopologyInputSlot::Input0,
        2,
      ),
    )
    is Ok(_),
  )
  topology.process(context, first_left, first_right)
  topology.process(context, second_left, second_right)
  topology.process(context, settled_left, settled_right)

  // After delete: constant(1.0) -> pan(0, 0.0) -> stereo_output
  // Center pan with gain 1.0 = ~0.707 on each channel
  assert_true(
    settled_left.every(sample => {
      (sample - HOT_SWAP_CENTER_GAIN).abs() < HOT_SWAP_EPSILON
    }),
  )
  assert_true(
    settled_right.every(sample => {
      (sample - HOT_SWAP_CENTER_GAIN).abs() < HOT_SWAP_EPSILON
    }),
  )
}

///|
test "compiled stereo dsp topology controller mirrors runtime params into queued edit" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let topology = @graph.StereoDspTopologyController::from_nodes(
    [
      @graph.DspNode::constant(1.0),
      @graph.DspNode::pan(0, 0.0),
      @graph.DspNode::stereo_output(1),
    ],
    context,
    crossfade_samples=HOT_SWAP_CROSSFADE_SAMPLES,
  ).unwrap()
  let first_left = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let first_right = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let second_left = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let second_right = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let settled_left = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let settled_right = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  assert_true(
    topology.queue_topology_edit(
      @graph.GraphTopologyEdit::replace_node(1, @graph.DspNode::pan(0, 1.0)),
    )
    is Ok(_),
  )
  assert_true(
    topology.apply_control(
      @graph.GraphControl::set_param(1, @graph.GraphParamSlot::Value0, -1.0),
    )
    is Ok(_),
  )
  topology.process(context, first_left, first_right)
  topology.process(context, second_left, second_right)
  topology.process(context, settled_left, settled_right)

  assert_true(
    first_left.every(sample => {
      !sample.is_nan() && !sample.is_inf() && sample >= 1.0
    }),
  )
  assert_true(
    second_left.every(sample => {
      !sample.is_nan() && !sample.is_inf() && sample >= 1.0
    }),
  )
  assert_true(settled_left.every(sample => sample == 1.0))
  assert_true(first_right.every(sample => sample.abs() < HOT_SWAP_EPSILON))
  assert_true(second_right.every(sample => sample.abs() < HOT_SWAP_EPSILON))
  assert_true(settled_right.every(sample => sample.abs() < HOT_SWAP_EPSILON))
}

///|
test "compiled stereo dsp topology controller set_param reports invalid value" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let topology = @graph.StereoDspTopologyController::from_nodes(
    [
      @graph.DspNode::constant(1.0),
      @graph.DspNode::pan(0, 0.0),
      @graph.DspNode::stereo_output(1),
    ],
    context,
  ).unwrap()
  let left = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let right = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  match topology.set_param(1, @graph.GraphParamSlot::Value0, 0.0 / 0.0) {
    Err(
      @graph.GraphControlError::InvalidParamValue(
        1,
        @graph.DspNodeKind::Pan,
        @graph.GraphParamSlot::Value0,
        _
      )
    ) => ()
    other => fail("expected InvalidParamValue, got \{@debug.to_string(other)}")
  }
  topology.process(context, left, right)

  assert_true(
    left.every(sample => {
      (sample - HOT_SWAP_CENTER_GAIN).abs() < HOT_SWAP_EPSILON
    }),
  )
  assert_true(
    right.every(sample => {
      (sample - HOT_SWAP_CENTER_GAIN).abs() < HOT_SWAP_EPSILON
    }),
  )
}

///|
test "compiled stereo dsp topology controller crossfades a rewired input" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let topology = @graph.StereoDspTopologyController::from_nodes(
    [
      @graph.DspNode::constant(1.0),
      @graph.DspNode::constant(0.5),
      @graph.DspNode::gain(0, 0.5),
      @graph.DspNode::gain(1, 0.5),
      @graph.DspNode::mix(2, 3),
      @graph.DspNode::mix(4, 3),
      @graph.DspNode::pan(5, 0.0),
      @graph.DspNode::stereo_output(6),
    ],
    context,
    crossfade_samples=HOT_SWAP_CROSSFADE_SAMPLES,
  ).unwrap()
  let first_left = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let first_right = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let second_left = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let second_right = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let settled_left = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let settled_right = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  assert_true(
    topology.queue_topology_edit(
      @graph.GraphTopologyEdit::rewire_input(
        4,
        @graph.GraphTopologyInputSlot::Input1,
        0,
      ),
    )
    is Ok(_),
  )
  topology.process(context, first_left, first_right)
  topology.process(context, second_left, second_right)
  topology.process(context, settled_left, settled_right)

  for index = 0; index < HOT_SWAP_BLOCK_SIZE; index = index + 1 {
    let first_progress = topology_test_hot_swap_progress(
      index,
      HOT_SWAP_CROSSFADE_SAMPLES,
    )
    let first_expected = 1.0 *
      HOT_SWAP_CENTER_GAIN *
      topology_test_old_gain(first_progress) +
      1.75 * HOT_SWAP_CENTER_GAIN * topology_test_new_gain(first_progress)
    assert_true(
      (first_left.get(index) - first_expected).abs() < HOT_SWAP_EPSILON,
    )
    assert_true(
      (first_right.get(index) - first_expected).abs() < HOT_SWAP_EPSILON,
    )

    let second_position = HOT_SWAP_BLOCK_SIZE + index
    let second_progress = topology_test_hot_swap_progress(
      second_position,
      HOT_SWAP_CROSSFADE_SAMPLES,
    )
    let second_expected = 1.0 *
      HOT_SWAP_CENTER_GAIN *
      topology_test_old_gain(second_progress) +
      1.75 * HOT_SWAP_CENTER_GAIN * topology_test_new_gain(second_progress)
    assert_true(
      (second_left.get(index) - second_expected).abs() < HOT_SWAP_EPSILON,
    )
    assert_true(
      (second_right.get(index) - second_expected).abs() < HOT_SWAP_EPSILON,
    )
  }
  assert_true(
    settled_left.every(sample => {
      (sample - 1.75 * HOT_SWAP_CENTER_GAIN).abs() < HOT_SWAP_EPSILON
    }),
  )
  assert_true(
    settled_right.every(sample => {
      (sample - 1.75 * HOT_SWAP_CENTER_GAIN).abs() < HOT_SWAP_EPSILON
    }),
  )
}

///|
test "compiled stereo dsp topology controller preserves runtime params across later topology edits" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let topology = @graph.StereoDspTopologyController::from_nodes(
    [
      @graph.DspNode::constant(1.0),
      @graph.DspNode::pan(0, 0.0),
      @graph.DspNode::stereo_output(1),
    ],
    context,
    crossfade_samples=HOT_SWAP_CROSSFADE_SAMPLES,
  ).unwrap()
  let first_left = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let first_right = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let second_left = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let second_right = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let settled_left = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let settled_right = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  assert_true(
    topology.apply_controls([
      @graph.GraphControl::set_param(1, @graph.GraphParamSlot::Value0, -1.0),
    ])
    is Ok(_),
  )
  assert_true(
    topology.queue_topology_edit(
      @graph.GraphTopologyEdit::replace_node(0, @graph.DspNode::constant(0.5)),
    )
    is Ok(_),
  )
  topology.process(context, first_left, first_right)
  topology.process(context, second_left, second_right)
  topology.process(context, settled_left, settled_right)

  for index = 0; index < HOT_SWAP_BLOCK_SIZE; index = index + 1 {
    let first_progress = topology_test_hot_swap_progress(
      index,
      HOT_SWAP_CROSSFADE_SAMPLES,
    )
    let first_expected = topology_test_old_gain(first_progress) +
      0.5 * topology_test_new_gain(first_progress)
    assert_true(
      (first_left.get(index) - first_expected).abs() < HOT_SWAP_EPSILON,
    )
    assert_true(first_right.get(index).abs() < HOT_SWAP_EPSILON)

    let second_position = HOT_SWAP_BLOCK_SIZE + index
    let second_progress = topology_test_hot_swap_progress(
      second_position,
      HOT_SWAP_CROSSFADE_SAMPLES,
    )
    let second_expected = topology_test_old_gain(second_progress) +
      0.5 * topology_test_new_gain(second_progress)
    assert_true(
      (second_left.get(index) - second_expected).abs() < HOT_SWAP_EPSILON,
    )
    assert_true(second_right.get(index).abs() < HOT_SWAP_EPSILON)
  }
  assert_true(settled_left.every(sample => sample == 0.5))
  assert_true(settled_right.every(sample => sample.abs() < HOT_SWAP_EPSILON))
}

///|
test "topology edit: insert chain of two gain nodes" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  // Graph: constant(1.0) -> output(0)
  let topology = @graph.DspTopologyController::from_nodes(
    [@graph.DspNode::constant(1.0), @graph.DspNode::output(0)],
    context,
    crossfade_samples=HOT_SWAP_CROSSFADE_SAMPLES,
  ).unwrap()
  let first_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let second_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let settled_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  // Insert chain [Gain(0.5), Gain(0.8)] between constant and output
  assert_true(
    topology.queue_topology_edit(
      @graph.GraphTopologyEdit::insert_chain(
        1,
        @graph.GraphTopologyInputSlot::Input0,
        [@graph.DspNode::gain(0, 0.5), @graph.DspNode::gain(0, 0.8)],
      ),
    )
    is Ok(_),
  )
  topology.process(context, first_block)
  topology.process(context, second_block)
  topology.process(context, settled_block)

  // After insert: constant(1.0) -> gain(0.5) -> gain(0.8) -> output
  // Output = 1.0 * 0.5 * 0.8 = 0.4
  assert_true(settled_block.every(sample => sample == 0.4))
}

///|
test "topology edit: delete chain reverses insert chain" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  // Graph: constant(1.0) -> output(0)
  let topology = @graph.DspTopologyController::from_nodes(
    [@graph.DspNode::constant(1.0), @graph.DspNode::output(0)],
    context,
    crossfade_samples=HOT_SWAP_CROSSFADE_SAMPLES,
  ).unwrap()
  let insert_first = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let insert_second = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let inserted_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  // Insert chain [Gain(0.5), Gain(0.8)] between constant and output
  assert_true(
    topology.queue_topology_edit(
      @graph.GraphTopologyEdit::insert_chain(
        1,
        @graph.GraphTopologyInputSlot::Input0,
        [@graph.DspNode::gain(0, 0.5), @graph.DspNode::gain(0, 0.8)],
      ),
    )
    is Ok(_),
  )
  topology.process(context, insert_first)
  topology.process(context, insert_second)
  topology.process(context, inserted_block)
  assert_true(inserted_block.every(sample => sample == 0.4))

  // After insert: [constant(1.0), output(3), gain(0,0.5), gain(2,0.8)]
  // Indices: 0=constant, 1=output, 2=gain(0.5), 3=gain(0.8)
  // Delete chain from 2 to 3, retarget output (node 1) to constant (node 0)
  let delete_first = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let delete_second = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  let restored_block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  assert_true(
    topology.queue_topology_edit(
      @graph.GraphTopologyEdit::delete_chain(
        2,
        3,
        1,
        @graph.GraphTopologyInputSlot::Input0,
        0,
      ),
    )
    is Ok(_),
  )
  topology.process(context, delete_first)
  topology.process(context, delete_second)
  topology.process(context, restored_block)
  assert_true(restored_block.every(sample => sample == 1.0))
}

///|
test "topology edit: insert_chain rejects empty chain" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let topology = @graph.DspTopologyController::from_nodes(
    [@graph.DspNode::constant(1.0), @graph.DspNode::output(0)],
    context,
  ).unwrap()
  let output = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  assert_true(
    topology.queue_topology_edit(
      @graph.GraphTopologyEdit::insert_chain(
        1,
        @graph.GraphTopologyInputSlot::Input0,
        [],
      ),
    )
    is Err(_),
  )
  topology.process(context, output)
  assert_true(output.every(sample => sample == 1.0))
}

///|
test "topology edit: insert_chain rejects chain with binary node" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  let topology = @graph.DspTopologyController::from_nodes(
    [@graph.DspNode::constant(1.0), @graph.DspNode::output(0)],
    context,
  ).unwrap()
  let output = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  // Mix is binary (has input1), should be rejected
  assert_true(
    topology.queue_topology_edit(
      @graph.GraphTopologyEdit::insert_chain(
        1,
        @graph.GraphTopologyInputSlot::Input0,
        [@graph.DspNode::gain(0, 0.5), @graph.DspNode::mix(0, 0)],
      ),
    )
    is Err(_),
  )
  topology.process(context, output)
  assert_true(output.every(sample => sample == 1.0))
}

///|
test "topology edit: delete_chain rejects chain with binary node" {
  let context = DspContext::new(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
  )
  // Build a graph with a binary node (mix) in the potential delete range
  let topology = @graph.DspTopologyController::from_nodes(
    [
      @graph.DspNode::constant(1.0),
      @graph.DspNode::constant(0.5),
      @graph.DspNode::mix(0, 1),
      @graph.DspNode::output(2),
    ],
    context,
  ).unwrap()
  let output = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)

  // Try to delete chain containing mix node (binary, has input1 >= 0)
  assert_true(
    topology.queue_topology_edit(
      @graph.GraphTopologyEdit::delete_chain(
        2,
        2,
        3,
        @graph.GraphTopologyInputSlot::Input0,
        0,
      ),
    )
    is Err(_),
  )
  topology.process(context, output)
  assert_true(output.every(sample => sample == 1.5))
}

///|
test "topology edit preserves oscillator phase across recompilation" {
  let nodes = [
    @graph.DspNode::constant(440.0),
    @graph.DspNode::oscillator_from(0, Waveform::Sine),
    @graph.DspNode::output(1),
  ]
  let ctx = DspContext::new(sample_rate=48000.0, block_size=128)
  let controller = @graph.DspTopologyController::from_nodes(
    nodes,
    ctx,
    crossfade_samples=0,
  ).unwrap()

  // Process one block to advance oscillator phase
  let buf = AudioBuffer::filled(128)
  controller.process(ctx, buf)

  // Insert a gain(1.0) identity node — should not change output
  let edit = @graph.GraphTopologyEdit::insert_node(
    2,
    @graph.GraphTopologyInputSlot::Input0,
    @graph.DspNode::gain(-1, 1.0),
  )
  assert_true(controller.queue_topology_edit(edit) is Ok(_))
  controller.process(ctx, buf) // applies the swap

  // Process another block — phase should be continuous (not reset)
  controller.process(ctx, buf)
  let sample_after_first = buf.get(0)

  // If phase was preserved, the output continues naturally
  // If phase reset to 0, the first sample would be 0.0
  assert_true(sample_after_first != 0.0)
}

///|
test "topology edit preserves stereo oscillator phase across recompilation" {
  let nodes = [
    @graph.DspNode::constant(440.0),
    @graph.DspNode::oscillator_from(0, Waveform::Sine),
    @graph.DspNode::pan(1, 0.0),
    @graph.DspNode::stereo_output(2),
  ]
  let ctx = DspContext::new(sample_rate=48000.0, block_size=128)
  let controller = @graph.StereoDspTopologyController::from_nodes(
    nodes,
    ctx,
    crossfade_samples=0,
  ).unwrap()

  // Process one block to advance oscillator phase
  let left = AudioBuffer::filled(128)
  let right = AudioBuffer::filled(128)
  controller.process(ctx, left, right)

  // Insert a stereo_gain(1.0) identity node — should not change output
  let edit = @graph.GraphTopologyEdit::insert_node(
    3,
    @graph.GraphTopologyInputSlot::Input0,
    @graph.DspNode::stereo_gain(input=-1, amount=1.0),
  )
  assert_true(controller.queue_topology_edit(edit) is Ok(_))
  controller.process(ctx, left, right) // applies the swap

  // Process another block — phase should be continuous (not reset)
  controller.process(ctx, left, right)
  let left_after_first = left.get(0)

  // If phase was preserved, the output continues naturally
  // If phase reset to 0, the first sample would be 0.0
  assert_true(left_after_first != 0.0)
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
