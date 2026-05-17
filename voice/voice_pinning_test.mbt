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
/// and maps VoicePoolError variants to A2Reason via a helper added in PR 3.
type A2Closure = (Array[DspNode], DspContext, Int) -> Result[
  VoicePool,
  A2Reason,
]

///|
type A3Closure = (VoicePool, Array[DspNode]) -> Result[Unit, A3Reason]

///|
/// PR-2 A2 closure: pre-classify failure reasons before calling the
/// current Option-returning VoicePool::new. PR 3 replaces this body
/// with `VoicePool::new(CompiledTemplate::analyze(nodes), ctx, max_voices?)
/// .map_err(A2Reason::from_voice_pool)`.
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
