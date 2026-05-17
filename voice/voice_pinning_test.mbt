///|
/// PR-2 local enum used by A2/A3 closure-parameterized tests.
/// Mirrors the future VoicePoolError but lives in the test file because
/// VoicePoolError doesn't exist yet (added in PR 3). The pre-classifier
/// inside the test closure populates these variants by checking
/// max_voices and orphan_adsr_count before invoking the current
/// Option/Bool-returning API.
enum A2Reason {
  InvalidMaxVoices
  OrphanAdsr
  CompileRejected
} derive(Eq, @debug.Debug)

///|
/// PR-2 local enum mirroring the subset of VoicePoolError that the
/// VoicePool::set_template path can produce (no max_voices check there).
/// Deleted in PR 3 when the real VoicePoolError is available.
enum A3Reason {
  OrphanAdsr
  CompileRejected
} derive(Eq, @debug.Debug)

///|
/// Closure type for A2. PR 3 swaps the body to call the new
/// VoicePool::new(CompiledTemplate, ctx, max_voices?) -> Result[Self, VoicePoolError]
/// and maps VoicePoolError variants to A2Reason via an inline match.
type A2Closure = (Array[DspNode], DspContext, Int) -> Result[
  VoicePool,
  A2Reason,
]

///|
type A3Closure = (VoicePool, Array[DspNode]) -> Result[Unit, A3Reason]

///|
/// PR-2 A2 closure: pre-classify failure reasons before calling the
/// current Option-returning VoicePool::new. PR 3 replaces this body
/// with a direct call to VoicePool::new(CompiledTemplate::analyze(nodes), ctx,
/// max_voices?) and an inline match mapping VoicePoolError variants to A2Reason.
fn pr2_a2_closure(
  nodes : Array[DspNode],
  ctx : DspContext,
  max_voices : Int,
) -> Result[VoicePool, A2Reason] {
  guard max_voices > 0 else { return Err(A2Reason::InvalidMaxVoices) }
  guard @graph.CompiledTemplate::analyze(nodes).orphan_adsr_count() == 0 else {
    return Err(A2Reason::OrphanAdsr)
  }
  match VoicePool::new(nodes, ctx, max_voices~) {
    Some(pool) => Ok(pool)
    None => Err(A2Reason::CompileRejected)
  }
}

///|
/// PR-2 A3 closure: pre-classify orphan_adsr before calling the
/// current Bool-returning VoicePool::set_template.
fn pr2_a3_closure(
  pool : VoicePool,
  nodes : Array[DspNode],
) -> Result[Unit, A3Reason] {
  guard @graph.CompiledTemplate::analyze(nodes).orphan_adsr_count() == 0 else {
    return Err(A3Reason::OrphanAdsr)
  }
  if VoicePool::set_template(pool, nodes) {
    Ok(())
  } else {
    Err(A3Reason::CompileRejected)
  }
}

///|
/// A2 well-formed: a minimal valid template (Oscillator → Output)
/// produces a VoicePool successfully.
test "A2: well-formed template constructs VoicePool successfully" {
  let nodes : Array[DspNode] = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::output(0),
  ]
  let ctx = DspContext::new(sample_rate=48000.0, block_size=128)
  let result = pr2_a2_closure(nodes, ctx, 4)
  assert_true(result is Ok(_))
}

///|
/// A2 InvalidMaxVoices: max_voices=0 fails with the specific reason.
test "A2: max_voices=0 fails with InvalidMaxVoices" {
  let nodes : Array[DspNode] = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::output(0),
  ]
  let ctx = DspContext::new(sample_rate=48000.0, block_size=128)
  let result = pr2_a2_closure(nodes, ctx, 0)
  match result {
    Err(reason) => @debug.assert_eq(reason, A2Reason::InvalidMaxVoices)
    Ok(_) => fail("expected Err(InvalidMaxVoices), got Ok")
  }
}

///|
/// A2 OrphanAdsr: a dead-code ADSR node (no consumer) fails with the
/// specific reason. Note: ADSR must be in the template but unreferenced
/// by Output, so optimize_graph eliminates it.
test "A2: orphan ADSR fails with OrphanAdsr" {
  let nodes : Array[DspNode] = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::adsr(attack_ms=10.0, decay_ms=50.0, sustain=0.5, release_ms=100.0), // orphan — not referenced by Output
    DspNode::output(0),
  ]
  let ctx = DspContext::new(sample_rate=48000.0, block_size=128)
  let result = pr2_a2_closure(nodes, ctx, 4)
  match result {
    Err(reason) => @debug.assert_eq(reason, A2Reason::OrphanAdsr)
    Ok(_) => fail("expected Err(OrphanAdsr), got Ok")
  }
}

///|
/// A2 CompileRejected: a template with no Output node fails with
/// CompileRejected.
test "A2: missing Output fails with CompileRejected" {
  let nodes : Array[DspNode] = [DspNode::oscillator(Waveform::Sine, 440.0)]
  let ctx = DspContext::new(sample_rate=48000.0, block_size=128)
  let result = pr2_a2_closure(nodes, ctx, 4)
  match result {
    Err(reason) => @debug.assert_eq(reason, A2Reason::CompileRejected)
    Ok(_) => fail("expected Err(CompileRejected), got Ok")
  }
}

///|
/// A3: replacing with a well-formed template succeeds.
test "A3: well-formed replacement succeeds" {
  let nodes : Array[DspNode] = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::output(0),
  ]
  let ctx = DspContext::new(sample_rate=48000.0, block_size=128)
  let pool = VoicePool::new(nodes, ctx, max_voices=4).unwrap()
  let new_nodes : Array[DspNode] = [
    DspNode::oscillator(Waveform::Square, 880.0),
    DspNode::output(0),
  ]
  @debug.assert_eq(pr2_a3_closure(pool, new_nodes), Ok(()))
}

///|
/// A3: replacing with an orphan-ADSR template fails with OrphanAdsr.
test "A3: orphan ADSR replacement fails with OrphanAdsr" {
  let nodes : Array[DspNode] = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::output(0),
  ]
  let ctx = DspContext::new(sample_rate=48000.0, block_size=128)
  let pool = VoicePool::new(nodes, ctx, max_voices=4).unwrap()
  let new_nodes : Array[DspNode] = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::adsr(attack_ms=10.0, decay_ms=50.0, sustain=0.5, release_ms=100.0),
    DspNode::output(0),
  ]
  @debug.assert_eq(pr2_a3_closure(pool, new_nodes), Err(A3Reason::OrphanAdsr))
}

///|
/// A3: replacing with a no-Output template fails with CompileRejected.
test "A3: missing Output replacement fails with CompileRejected" {
  let nodes : Array[DspNode] = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::output(0),
  ]
  let ctx = DspContext::new(sample_rate=48000.0, block_size=128)
  let pool = VoicePool::new(nodes, ctx, max_voices=4).unwrap()
  let new_nodes : Array[DspNode] = [DspNode::oscillator(Waveform::Sine, 440.0)]
  @debug.assert_eq(
    pr2_a3_closure(pool, new_nodes),
    Err(A3Reason::CompileRejected),
  )
}

///|
/// PR-2 A4 closure: passes through unchanged. BoundVoicePool already
/// returns Result[..., BoundVoicePoolError]. PR 3 changes only the
/// input type (Array → CompiledTemplate).
fn pr2_a4_closure(
  nodes : Array[DspNode],
  ctx : DspContext,
  builder : ControlBindingBuilder,
  max_voices : Int,
) -> Result[BoundVoicePool, BoundVoicePoolError] {
  BoundVoicePool::new(nodes, ctx, builder, max_voices~)
}

///|
/// A4: well-formed template + valid bindings constructs BoundVoicePool.
test "A4: well-formed template constructs BoundVoicePool successfully" {
  let nodes : Array[DspNode] = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::output(0),
  ]
  let ctx = DspContext::new(sample_rate=48000.0, block_size=128)
  let builder = ControlBindingBuilder::new()
  let result = pr2_a4_closure(nodes, ctx, builder, 4)
  assert_true(result is Ok(_))
}

///|
/// A4 InvalidMaxVoices: max_voices=0 fails with the specific variant.
test "A4: max_voices=0 fails with InvalidMaxVoices" {
  let nodes : Array[DspNode] = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::output(0),
  ]
  let ctx = DspContext::new(sample_rate=48000.0, block_size=128)
  let builder = ControlBindingBuilder::new()
  let result = pr2_a4_closure(nodes, ctx, builder, 0)
  match result {
    Err(reason) =>
      @debug.assert_eq(reason, BoundVoicePoolError::InvalidMaxVoices)
    Ok(_) => fail("expected Err(InvalidMaxVoices), got Ok")
  }
}

///|
/// A4 OrphanAdsr: dead-code ADSR fails with the specific variant.
test "A4: orphan ADSR fails with OrphanAdsr" {
  let nodes : Array[DspNode] = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::adsr(attack_ms=10.0, decay_ms=50.0, sustain=0.5, release_ms=100.0),
    DspNode::output(0),
  ]
  let ctx = DspContext::new(sample_rate=48000.0, block_size=128)
  let builder = ControlBindingBuilder::new()
  let result = pr2_a4_closure(nodes, ctx, builder, 4)
  match result {
    Err(reason) => @debug.assert_eq(reason, BoundVoicePoolError::OrphanAdsr)
    Ok(_) => fail("expected Err(OrphanAdsr), got Ok")
  }
}

///|
/// A4 CompileRejected: missing Output fails with the specific variant.
test "A4: missing Output fails with CompileRejected" {
  let nodes : Array[DspNode] = [DspNode::oscillator(Waveform::Sine, 440.0)]
  let ctx = DspContext::new(sample_rate=48000.0, block_size=128)
  let builder = ControlBindingBuilder::new()
  let result = pr2_a4_closure(nodes, ctx, builder, 4)
  match result {
    Err(reason) =>
      @debug.assert_eq(reason, BoundVoicePoolError::CompileRejected)
    Ok(_) => fail("expected Err(CompileRejected), got Ok")
  }
}
