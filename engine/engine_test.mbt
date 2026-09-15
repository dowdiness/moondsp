///|
fn patch(frequency : Double) -> Array[@graph.DspNode] {
  [
    @graph.DspNode::oscillator(@dsp.Waveform::Sine, frequency),
    @graph.DspNode::gain(0, 0.1),
    @graph.DspNode::output(1),
  ]
}

///|
test "independent MoonBit engines and graph handles preserve paused phase" {
  let ctx = @dsp.DspContext::DspContext(sample_rate=48000.0, block_size=128)
  let engine = @engine.GraphEngine::GraphEngine(ctx)
  let other_engine = @engine.GraphEngine::GraphEngine(ctx)
  let sound = engine.mount(patch(437.0))
  let other = engine.mount(patch(613.0))
  let independent = other_engine.mount(patch(437.0))
  let out = ctx.make_buffer()
  let reference = ctx.make_buffer()
  engine.process(out)
  assert_true(out.all(x => x == 0.0))
  sound.play()
  other.play()
  independent.play()
  for block in 0..<4 {
    if block == 1 {
      sound.pause()
    }
    if block == 2 {
      sound.play()
    }
    if block == 3 {
      other.unmount()
    }
    engine.process(out)
    other_engine.process(reference)
    for i in 0..<128 {
      let frame = block * 128 + i
      let sound_frame = if block < 2 { frame } else { frame - 128 }
      let expected = (if block == 1 {
          0.0
        } else {
          0.1 *
          @math.sin(2.0 * @math.PI * 437.0 * sound_frame.to_double() / 48000.0)
        }) +
        (if block == 3 {
          0.0
        } else {
          0.1 * @math.sin(2.0 * @math.PI * 613.0 * frame.to_double() / 48000.0)
        })
      assert_true((out.get(i) - expected).abs() < 0.000001)
      assert_true(
        (reference.get(i) -
        0.1 * @math.sin(2.0 * @math.PI * 437.0 * frame.to_double() / 48000.0)).abs() <
        0.000001,
      )
    }
  }
  engine.close()
  other_engine.process(reference)
  assert_true(reference.any(x => x != 0.0))
  other_engine.close()
}

///|
test "retired handles cannot affect a reused slot or seal mount admission" {
  let ctx = @dsp.DspContext::DspContext(sample_rate=48000.0, block_size=128)
  let engine = @engine.GraphEngine::GraphEngine(ctx, capacity=1)
  let retired = engine.mount(patch(440.0))
  retired.unmount()
  let replacement = engine.mount(patch(375.0))
  retired.unmount()
  let stale = try {
    retired.play()
    None
  } catch {
    error => Some(error)
  }
  guard stale is Some(@engine.GraphEngineError::InvalidHandle) else {
    fail("expected invalid handle")
  }
  replacement.play()
  let out = ctx.make_buffer()
  engine.process(out)
  assert_true((out.get(32) - 0.1).abs() < 0.000001)
  replacement.pause()
  replacement.unmount()
  let admission = try {
    let _ = engine.mount(patch(440.0))
    None
  } catch {
    error => Some(error)
  }
  guard admission is Some(@engine.GraphEngineError::MountClosed) else {
    fail("expected sealed admission")
  }
  engine.close()
}

///|
test "invalid compilation and capacity rejection leave the engine usable" {
  let ctx = @dsp.DspContext::DspContext(sample_rate=48000.0, block_size=128)
  let engine = @engine.GraphEngine::GraphEngine(ctx, capacity=1)
  let invalid = try {
    let _ = engine.mount([])
    None
  } catch {
    error => Some(error)
  }
  guard invalid is Some(@engine.GraphEngineError::InvalidGraph(_)) else {
    fail("expected compile failure")
  }
  let sound = engine.mount(patch(375.0))
  let full = try {
    let _ = engine.mount(patch(440.0))
    None
  } catch {
    error => Some(error)
  }
  guard full is Some(@engine.GraphEngineError::CapacityExceeded) else {
    fail("expected capacity rejection")
  }
  sound.play()
  let wrong = @dsp.AudioBuffer::filled(127, init=0.25)
  let rejected = try {
    engine.process(wrong)
    None
  } catch {
    error => Some(error)
  }
  guard rejected
    is Some(
      @engine.GraphEngineError::BufferSizeMismatch(expected=128, actual=127)
    ) else {
    fail("expected buffer mismatch")
  }
  assert_true(wrong.all(x => x == 0.25))
  let out = ctx.make_buffer()
  engine.process(out)
  // Rejected rendering did not advance oscillator phase.
  @debug.assert_eq(out.get(0), 0.0)
  assert_true((out.get(32) - 0.1).abs() < 0.000001)
  engine.close()
}

///|
test "mounted control batches are atomic and lifecycle-aware" {
  let ctx = @dsp.DspContext::DspContext(sample_rate=48000.0, block_size=128)
  let engine = @engine.GraphEngine::GraphEngine(ctx)
  let sound = engine.mount(patch(440.0))
  let rejected = try {
    sound.apply_controls([
      @graph.GraphControl::set_param(1, @graph.GraphParamSlot::Value0, 0.2),
      @graph.GraphControl::set_param(
        1,
        @graph.GraphParamSlot::DelaySamples,
        1.0,
      ),
    ])
    None
  } catch {
    error => Some(error)
  }
  guard rejected
    is Some(
      @engine.GraphEngineError::ControlRejected(
        @graph.GraphControlError::InvalidSlotForNode(
          1,
          @graph.DspNodeKind::Gain,
          @graph.GraphParamSlot::DelaySamples
        )
      )
    ) else {
    fail("expected atomic control rejection")
  }
  let other = engine.mount(patch(220.0))
  sound.play()
  let out = ctx.make_buffer()
  engine.process(out)
  assert_true(
    (out.get(32) - 0.1 * @math.sin(2.0 * @math.PI * 440.0 * 32.0 / 48000.0)).abs() <
    0.000001,
  )
  sound.unmount()
  let after_unmount = try {
    sound.apply_controls([@graph.GraphControl::gate_on(0)])
    None
  } catch {
    error => Some(error)
  }
  guard after_unmount is Some(@engine.GraphEngineError::InvalidHandle) else {
    fail("expected unmounted handle rejection")
  }
  engine.close()
  let after_close = try {
    other.apply_controls([
      @graph.GraphControl::set_param(0, @graph.GraphParamSlot::Value0, 440.0),
    ])
    None
  } catch {
    error => Some(error)
  }
  guard after_close is Some(@engine.GraphEngineError::EngineClosed) else {
    fail("expected closed engine rejection")
  }
}

///|
test "close is idempotent and invalidates remaining handles with typed errors" {
  let ctx = @dsp.DspContext::DspContext(sample_rate=48000.0, block_size=128)
  let engine = @engine.GraphEngine::GraphEngine(ctx)
  let sound = engine.mount(patch(440.0))
  let retired = engine.mount(patch(220.0))
  retired.unmount()
  sound.play()
  engine.close()
  engine.close()
  retired.unmount()
  let errors = [
    try {
      sound.play()
      None
    } catch {
      error => Some(error)
    },
    try {
      sound.pause()
      None
    } catch {
      error => Some(error)
    },
    try {
      sound.unmount()
      None
    } catch {
      error => Some(error)
    },
    try {
      let _ = engine.mount(patch(440.0))
      None
    } catch {
      error => Some(error)
    },
    try {
      engine.process(ctx.make_buffer())
      None
    } catch {
      error => Some(error)
    },
  ]
  for error in errors {
    guard error is Some(@engine.GraphEngineError::EngineClosed) else {
      fail("expected closed engine")
    }
  }
}

///|
test "invalid engine configuration is rejected before allocation" {
  let ctx = @dsp.DspContext::DspContext(sample_rate=48000.0, block_size=128)
  let invalid = try {
    let _ = @engine.GraphEngine::GraphEngine(ctx, capacity=0)
    None
  } catch {
    error => Some(error)
  }
  guard invalid is Some(@engine.GraphEngineError::InvalidConfiguration) else {
    fail("expected invalid capacity")
  }
  @debug.assert_eq(ctx.block_size(), 128)
}
