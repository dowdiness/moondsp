///|
/// Seam contract for the one canonical authoring->runtime crossing, ADR-0010.
///
/// `CompiledTemplate::analyze(Array[DspNode]) -> CompiledTemplate` is the single
/// boundary between the authoring model and the runtime. ADR-0010's stated
/// guarantee is that the analyzed template is a *reusable, immutable* runtime
/// exchange artifact: `optimize_graph` runs exactly once per template, and the
/// same `CompiledTemplate` value can be compiled repeatedly. VoicePool and
/// BoundVoicePool depend on this — they analyze once and compile one graph per
/// voice from that single template.
///
/// WHY this is not covered by the determinism property test: that test calls
/// `CompiledTemplate::analyze` once *per compile* (a fresh analyze each time), so
/// it pins "same topology, re-analyzed -> identical output". It would not catch
/// `compile` consuming or mutating a *shared* template — the exact failure mode
/// that would corrupt every voice after the first. This test analyzes once and
/// compiles the same value twice to pin that reuse invariant directly.
test "seam contract: one analyzed CompiledTemplate compiles into independent deterministic graphs" {
  let context = DspContext::new(sample_rate=STANDARD_SAMPLE_RATE, block_size=64)
  // Stateful topology (oscillator -> biquad -> output) so per-sample identity
  // across the block is a real signal: divergent internal state would show up.
  let nodes = [
    DspNode::oscillator(Waveform::Saw, 220.0),
    DspNode::biquad(
      input=0,
      mode=BiquadMode::LowPass,
      cutoff_hz=1000.0,
      q=0.707,
    ),
    DspNode::output(1),
  ]

  // Cross the boundary exactly once.
  let template = CompiledTemplate::analyze(nodes)
  let orphan_before = template.orphan_adsr_count()

  // Compile the *same* template value twice. If `compile` consumed or mutated
  // `template`, the second graph would be built from a disturbed artifact.
  let compiled_a = CompiledDsp::compile(template, context).unwrap()
  let compiled_b = CompiledDsp::compile(template, context).unwrap()

  let out_a = AudioBuffer::filled(64)
  let out_b = AudioBuffer::filled(64)
  compiled_a.process(context, out_a)
  compiled_b.process(context, out_b)

  // Reuse-determinism: two compiles of one analyzed template are identical.
  assert_true(buffers_identical(out_a, out_b, 64))

  // NaN firewall: the seam never lets non-finite samples through.
  let all_finite = for s in 0..<64 {
    if !is_finite(out_a.get(s)) {
      break false
    }
  } nobreak {
    true
  }
  assert_true(all_finite)

  // Immutability observed on the public template surface: analyzing once and
  // compiling twice leaves the template's reported structure unchanged.
  @debug.assert_eq(template.orphan_adsr_count(), orphan_before)
}

///|
/// Same reuse invariant for the parallel stereo crossing. `CompiledStereoDsp::compile`
/// is a *distinct* compile_internal (different compile plan, different terminal-shape
/// validator) that also accepts the shared `CompiledTemplate` per ADR-0010. A bug that
/// consumed or mutated the template on the stereo path would corrupt every stereo voice
/// after the first and would not be caught by the mono case above, so the contract is
/// pinned independently here.
test "seam contract: one analyzed CompiledTemplate compiles into independent deterministic stereo graphs" {
  let context = DspContext::new(sample_rate=STANDARD_SAMPLE_RATE, block_size=64)
  // Stateful mono chain (oscillator -> biquad) into a stereo terminal, so per-sample
  // identity across L and R is a real signal of undisturbed internal state.
  let nodes = [
    DspNode::oscillator(Waveform::Saw, 220.0),
    DspNode::biquad(
      input=0,
      mode=BiquadMode::LowPass,
      cutoff_hz=1000.0,
      q=0.707,
    ),
    DspNode::pan(1, PAN_CENTER),
    DspNode::stereo_output(2),
  ]

  // Cross the boundary exactly once.
  let template = CompiledTemplate::analyze(nodes)
  let orphan_before = template.orphan_adsr_count()

  // Compile the *same* template value twice.
  let compiled_a = CompiledStereoDsp::compile(template, context).unwrap()
  let compiled_b = CompiledStereoDsp::compile(template, context).unwrap()

  let left_a = AudioBuffer::filled(64)
  let right_a = AudioBuffer::filled(64)
  let left_b = AudioBuffer::filled(64)
  let right_b = AudioBuffer::filled(64)
  compiled_a.process(context, left_a, right_a)
  compiled_b.process(context, left_b, right_b)

  // Reuse-determinism: two compiles of one analyzed template are identical on
  // both channels.
  assert_true(buffers_identical(left_a, left_b, 64))
  assert_true(buffers_identical(right_a, right_b, 64))

  // NaN firewall on both channels: the seam never lets non-finite samples through.
  let all_finite = for s in 0..<64 {
    if !is_finite(left_a.get(s)) || !is_finite(right_a.get(s)) {
      break false
    }
  } nobreak {
    true
  }
  assert_true(all_finite)

  // Immutability observed on the public template surface.
  @debug.assert_eq(template.orphan_adsr_count(), orphan_before)
}
