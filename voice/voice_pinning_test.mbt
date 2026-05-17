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
