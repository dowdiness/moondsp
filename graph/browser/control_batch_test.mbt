///|
// Exercise the adapter's internal bound runtime and the shared lifecycle.
fn mount(
  engine : @lifecycle.Engine[@runtime.BoundDsp],
  context : @dsp.DspContext,
  nodes : Array[@model.DspNode],
  targets : Array[@runtime.GraphControlTarget],
) -> @lifecycle.Mount[@runtime.BoundDsp] raise {
  engine.check_mount()
  engine.register(
    @runtime.BoundDsp::BoundDsp(
      @template.AnalyzedGraph::analyze(nodes),
      context,
      targets,
    ),
  )
}

///|
test "numeric batches are bounded atomic and mount-local" {
  let ctx = @dsp.DspContext::DspContext(sample_rate=48000.0, block_size=16)
  let engine = @lifecycle.Engine::Engine(
    ctx,
    @runtime.BoundDsp::process,
    capacity=1,
  )
  let nodes = [@model.DspNode::constant(0.25), @model.DspNode::output(0)]
  let targets = [
    @runtime.GraphControlTarget::Param(0, @model.GraphParamSlot::Value0),
  ]
  let sound = mount(engine, ctx, nodes, targets)
  assert_true(sound.live_graph() is Some(_))
  let batch = @runtime.GraphControlBatch::GraphControlBatch(2)
  assert_true(batch.push(0, 0.5))
  assert_true(batch.push(1, 0.75))
  assert_false(batch.push(0, 1.0))
  assert_eq(batch.length(), 2)
  for _ in 0..<2 {
    guard sound.graph().update(batch)
      is Some(@runtime.GraphControlBatchError::BatchCapacityExceeded) else {
      fail("overflow must poison batch until clear")
    }
  }
  batch.clear()
  assert_true(batch.push(0, 0.5))
  assert_true(batch.push(1, 0.75))
  guard sound.graph().update(batch)
    is Some(@runtime.GraphControlBatchError::InvalidBindingIndex(1)) else {
    fail("invalid binding")
  }
  sound.unmount()
  assert_true(sound.live_graph() is None)
  let replacement = mount(engine, ctx, nodes, targets)
  batch.clear()
  assert_true(batch.push(0, 0.5))
  let stale = try {
    let _ = sound.graph().update(batch)
    None
  } catch {
    e => Some(e)
  }
  guard stale is Some(@lifecycle.LifecycleError::InvalidHandle) else {
    fail("stale update")
  }
  replacement.play()
  let out = ctx.make_buffer()
  assert_true(engine.process(out) is None)
  assert_true(out.all(x => x == 0.25))
  assert_true(replacement.graph().update(batch) is None)
  assert_true(engine.process(out) is None)
  assert_true(out.all(x => x == 0.5))
  batch.clear()
  assert_true(batch.push(0, 0.75))
  assert_true(batch.push(1, 1.0))
  guard replacement.graph().update(batch)
    is Some(@runtime.GraphControlBatchError::InvalidBindingIndex(1)) else {
    fail("invalid binding must reject the valid prefix")
  }
  assert_true(engine.process(out) is None)
  assert_true(out.all(x => x == 0.5))
  assert_false(batch.push(0, 1.0))
  guard replacement.graph().update(batch)
    is Some(@runtime.GraphControlBatchError::BatchCapacityExceeded) else {
    fail("overflow must reject the valid prefix")
  }
  assert_true(engine.process(out) is None)
  assert_true(out.all(x => x == 0.5))
  batch.clear()
  assert_true(batch.push(0, 0.75))
  assert_true(batch.push(0, 0.0 / 0.0))
  guard replacement.graph().update(batch)
    is Some(@runtime.GraphControlBatchError::InvalidParamValue(0, _, _, _)) else {
    fail("invalid value")
  }
  assert_true(engine.process(out) is None)
  assert_true(out.all(x => x == 0.5))
  let zero = @runtime.GraphControlBatch::GraphControlBatch(0)
  assert_true(replacement.graph().update(zero) is None)
  assert_false(zero.push(0, 1.0))
  guard replacement.graph().update(zero)
    is Some(@runtime.GraphControlBatchError::BatchCapacityExceeded) else {
    fail("zero capacity overflow")
  }
  zero.clear()
  assert_true(replacement.graph().update(zero) is None)
  engine.close()
  let closed = try {
    let _ = replacement.graph().update(batch)
    None
  } catch {
    e => Some(e)
  }
  guard closed is Some(@lifecycle.LifecycleError::EngineClosed) else {
    fail("closed update")
  }
  assert_true(replacement.live_graph() is None)
}

///|
test "numeric gates retain supplied order and reject atomically" {
  let ctx = @dsp.DspContext::DspContext(sample_rate=48000.0, block_size=16)
  let engine = @lifecycle.Engine::Engine(ctx, @runtime.BoundDsp::process)
  let nodes = [
    @model.DspNode::constant(99.0),
    @model.DspNode::adsr(
      attack_ms=0.0,
      decay_ms=0.0,
      sustain=0.25,
      release_ms=0.0,
    ),
    @model.DspNode::output(1),
  ]
  let sound = mount(engine, ctx, nodes, [
    @runtime.GraphControlTarget::Gate(1),
    @runtime.GraphControlTarget::Param(1, @model.GraphParamSlot::Value2),
  ])
  let batch = @runtime.GraphControlBatch::GraphControlBatch(3)
  assert_true(batch.push(0, 1.0))
  assert_true(batch.push(1, 0.75))
  assert_true(batch.push(0, 2.0))
  guard sound.graph().update(batch)
    is Some(@runtime.GraphControlBatchError::InvalidGateValue(1, 2.0)) else {
    fail("gate diagnostic authoring index")
  }
  sound.play()
  let out = ctx.make_buffer()
  assert_true(engine.process(out) is None)
  assert_true(out.all(x => x == 0.0))
  batch.clear()
  assert_true(batch.push(0, 0.0))
  assert_true(batch.push(0, 1.0))
  assert_true(sound.graph().update(batch) is None)
  assert_true(engine.process(out) is None)
  assert_true(out.all(x => x == 0.25))
  batch.clear()
  assert_true(batch.push(0, 1.0))
  assert_true(batch.push(0, 0.0))
  assert_true(sound.graph().update(batch) is None)
  assert_true(engine.process(out) is None)
  assert_true(out.all(x => x == 0.0))
  batch.clear()
  assert_true(batch.push(0, 1.0))
  assert_true(batch.push(1, 0.75))
  assert_true(sound.graph().update(batch) is None)
  assert_true(engine.process(out) is None)
  assert_true(out.all(x => x == 0.75))
  engine.close()
}

///|
test "targets resolve before registration and are independent of authoring arrays" {
  let ctx = @dsp.DspContext::DspContext(sample_rate=48000.0, block_size=16)
  let engine = @lifecycle.Engine::Engine(
    ctx,
    @runtime.BoundDsp::process,
    capacity=1,
  )
  let nodes = [
    @model.DspNode::constant(99.0),
    @model.DspNode::constant(0.25),
    @model.DspNode::output(1),
  ]
  let error = try {
    let _ = mount(engine, ctx, nodes, [
      @runtime.GraphControlTarget::Param(0, @model.GraphParamSlot::Value0),
    ])
    None
  } catch {
    e => Some(e)
  }
  guard error
    is Some(
      @runtime.BoundGraphError::ControlRejected(
        @runtime.GraphControlError::OrphanNode(0)
      )
    ) else {
    fail("orphan target rejected")
  }
  let targets = [
    @runtime.GraphControlTarget::Param(1, @model.GraphParamSlot::Value0),
  ]
  let sound = mount(engine, ctx, nodes, targets)
  targets[0] = @runtime.GraphControlTarget::Gate(0)
  sound.play()
  let out = ctx.make_buffer()
  assert_true(engine.process(out) is None)
  assert_true(out.all(x => x == 0.25))
  let batch = @runtime.GraphControlBatch::GraphControlBatch(1)
  assert_true(batch.push(0, 0.75))
  assert_true(sound.graph().update(batch) is None)
  assert_true(engine.process(out) is None)
  assert_true(out.all(x => x == 0.75))
}

///|
test "panic negative numeric batch capacity is rejected" {
  let _ = @runtime.GraphControlBatch::GraphControlBatch(-1)
}
