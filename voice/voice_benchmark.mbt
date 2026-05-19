// Microbenchmarks for the `validate_voice_template` double-compile claim
// (project_backlog.md: "validate_voice_template double-compile").
//
// What we measure
// ---------------
// 1. `set_template`  — exercises `validate_voice_template` in isolation:
//    pool exists, slots already allocated, so the call cost is dominated
//    by `CompiledDsp::compile(...)` whose result is discarded plus a
//    template-reference swap.
// 2. `note_on`       — the per-voice compile we already pay (max_voices=1
//    keeps slot stealing stable across iterations so each call recompiles).
// 3. `voicepool_new` — full constructor (validate + max_voices=32 slot
//    allocations), the user-perceptible cost of first authoring.
//
// The decision number is the per-fixture ratio `set_template / note_on`.
// Near 1.0 = double-compile waste is real; near 0 = it is noise.
//
// Default `moon bench` runs wasm-gc (browser AudioWorklet deployment
// path). The compile path is allocation-heavy (`graph/graph_compile.mbt`
// and `dsp/delay.mbt` allocate fresh buffers per call), so a wasm-gc
// number does not automatically generalize across targets. Verified
// 2026-05-19 that `moon bench --target native` (C-native deployment
// for future CLAP plugin) reports the same ratio and 25-30% lower
// absolute cost — no RC-overhead blowup. If a JS-target deployment
// is added, re-measure there before extending any "defer" conclusion.

///|
const BENCH_SAMPLE_RATE : Double = 48000.0

///|
const BENCH_BLOCK_SIZE : Int = 128

///|
/// Minimal wired-ADSR voice (4 nodes). Exercises the orphan-ADSR guard
/// in the well-formed path; matches the smallest real voice in production.
fn bench_minimal_voice_nodes() -> Array[@graph.DspNode] {
  [
    @graph.DspNode::oscillator(@dsp.Waveform::Sine, 440.0),
    @graph.DspNode::adsr(
      attack_ms=5.0,
      decay_ms=10.0,
      sustain=0.6,
      release_ms=50.0,
    ),
    @graph.DspNode::mul(0, 1),
    @graph.DspNode::output(2),
  ]
}

///|
/// FM voice (11 nodes). Genuine FM: a modulator oscillator (whose
/// frequency is supplied by an upstream constant) is scaled by an FM
/// depth gain and mixed into the carrier's frequency input via
/// `oscillator_from`. Without `oscillator_from`, the modulator nodes
/// would be dead-code-eliminated by `analyze` and this row would only
/// measure a carrier-plus-env chain.
fn bench_fm_voice_nodes() -> Array[@graph.DspNode] {
  [
    @graph.DspNode::constant(5.0), // 0: modulator base freq (Hz)
    @graph.DspNode::oscillator_from(0, @dsp.Waveform::Sine), // 1: modulator
    @graph.DspNode::gain(1, 200.0), // 2: FM depth
    @graph.DspNode::constant(220.0), // 3: carrier base freq
    @graph.DspNode::mix(3, 2), // 4: carrier_freq + modulation
    @graph.DspNode::oscillator_from(4, @dsp.Waveform::Saw), // 5: carrier
    @graph.DspNode::adsr(
      attack_ms=5.0,
      decay_ms=10.0,
      sustain=0.6,
      release_ms=50.0,
    ), // 6: env
    @graph.DspNode::mul(5, 6), // 7: amp-modulated carrier
    @graph.DspNode::biquad(
      input=7,
      mode=@graph.BiquadMode::LowPass,
      cutoff_hz=1200.0,
      q=0.707,
    ), // 8: filter
    @graph.DspNode::gain(8, 0.7), // 9: trim
    @graph.DspNode::output(9), // 10: output
  ]
}

///|
/// Full voice (10 nodes): osc + noise → ADSR → filter → gain → delay → output.
/// Largest realistic voice topology; the longest compile is the upper bound
/// on the cost we're worried about.
fn bench_full_voice_nodes() -> Array[@graph.DspNode] {
  [
    @graph.DspNode::oscillator(@dsp.Waveform::Saw, 220.0), // 0: osc
    @graph.DspNode::noise(42U), // 1: noise
    @graph.DspNode::gain(1, 0.2), // 2: noise gain
    @graph.DspNode::mix(0, 2), // 3: mix
    @graph.DspNode::adsr(
      attack_ms=5.0,
      decay_ms=10.0,
      sustain=0.6,
      release_ms=50.0,
    ), // 4: env
    @graph.DspNode::mul(3, 4), // 5: modulated
    @graph.DspNode::biquad(
      input=5,
      mode=@graph.BiquadMode::LowPass,
      cutoff_hz=1200.0,
      q=0.707,
    ), // 6: filter
    @graph.DspNode::gain(6, 0.7), // 7: trim
    @graph.DspNode::delay(
      input=7,
      max_delay_samples=4800,
      delay_samples=2400,
      feedback=0.3,
    ), // 8: delay
    @graph.DspNode::output(8), // 9: output
  ]
}

// ---- Validation tests ----
// WHY: a failed .unwrap() inside a bench closure aborts with no diagnostic.
// These guard the fixtures so a broken topology is caught with a clear
// assertion before the benchmark runner sees it.

///|
test "bench voice: minimal_voice template compiles + pool accepts" {
  let ctx = @dsp.DspContext::new(
    sample_rate=BENCH_SAMPLE_RATE,
    block_size=BENCH_BLOCK_SIZE,
  )
  let template = @graph.CompiledTemplate::analyze(bench_minimal_voice_nodes())
  assert_true(@graph.CompiledDsp::compile(template, ctx) is Some(_))
  assert_true(VoicePool::new(template, ctx) is Ok(_))
}

///|
test "bench voice: fm_voice template compiles + pool accepts" {
  let ctx = @dsp.DspContext::new(
    sample_rate=BENCH_SAMPLE_RATE,
    block_size=BENCH_BLOCK_SIZE,
  )
  let template = @graph.CompiledTemplate::analyze(bench_fm_voice_nodes())
  assert_true(@graph.CompiledDsp::compile(template, ctx) is Some(_))
  assert_true(VoicePool::new(template, ctx) is Ok(_))
}

///|
test "bench voice: full_voice template compiles + pool accepts" {
  let ctx = @dsp.DspContext::new(
    sample_rate=BENCH_SAMPLE_RATE,
    block_size=BENCH_BLOCK_SIZE,
  )
  let template = @graph.CompiledTemplate::analyze(bench_full_voice_nodes())
  assert_true(@graph.CompiledDsp::compile(template, ctx) is Some(_))
  assert_true(VoicePool::new(template, ctx) is Ok(_))
}

// ---- set_template (isolates the discarded compile) ----
// WHY this isolates the validator: at iteration time the pool already
// exists, slots are allocated, so the only work is validate_voice_template
// (which IS CompiledDsp::compile in the well-formed case) plus one
// template-pointer assignment and an adsr_authoring_indices() snapshot.
// That snapshot is O(node count); a single 4-10-node array scan is far
// below the compile cost we are measuring.

///|
test "bench/voice/set_template" (b : @bench.T) {
  let ctx = @dsp.DspContext::new(
    sample_rate=BENCH_SAMPLE_RATE,
    block_size=BENCH_BLOCK_SIZE,
  )
  let minimal = @graph.CompiledTemplate::analyze(bench_minimal_voice_nodes())
  let fm = @graph.CompiledTemplate::analyze(bench_fm_voice_nodes())
  let full = @graph.CompiledTemplate::analyze(bench_full_voice_nodes())
  let pool_min = VoicePool::new(minimal, ctx).unwrap()
  let pool_fm = VoicePool::new(fm, ctx).unwrap()
  let pool_full = VoicePool::new(full, ctx).unwrap()
  b.bench(name="minimal_voice", fn() {
    let r = pool_min.set_template(minimal)
    b.keep(r)
  })
  b.bench(name="fm_voice", fn() {
    let r = pool_fm.set_template(fm)
    b.keep(r)
  })
  b.bench(name="full_voice", fn() {
    let r = pool_full.set_template(full)
    b.keep(r)
  })
}

// ---- note_on (the productive per-voice compile) ----
// WHY max_voices=1: every iter steals slot 0 and recompiles. This keeps
// `find_slot` cost constant and bounded, isolating compile cost as the
// dominant per-call work. The slot's pre-existing CompiledDsp from the
// previous iter is replaced; no leak.
// WHY params=[]: skips the apply_controls branch so we measure pure compile
// overhead, not control validation.

///|
test "bench/voice/note_on" (b : @bench.T) {
  let ctx = @dsp.DspContext::new(
    sample_rate=BENCH_SAMPLE_RATE,
    block_size=BENCH_BLOCK_SIZE,
  )
  let minimal = @graph.CompiledTemplate::analyze(bench_minimal_voice_nodes())
  let fm = @graph.CompiledTemplate::analyze(bench_fm_voice_nodes())
  let full = @graph.CompiledTemplate::analyze(bench_full_voice_nodes())
  let pool_min = VoicePool::new(minimal, ctx, max_voices=1).unwrap()
  let pool_fm = VoicePool::new(fm, ctx, max_voices=1).unwrap()
  let pool_full = VoicePool::new(full, ctx, max_voices=1).unwrap()
  let empty : Array[@graph.GraphControl] = []
  b.bench(name="minimal_voice", fn() {
    let h = pool_min.note_on(empty)
    b.keep(h)
  })
  b.bench(name="fm_voice", fn() {
    let h = pool_fm.note_on(empty)
    b.keep(h)
  })
  b.bench(name="full_voice", fn() {
    let h = pool_full.note_on(empty)
    b.keep(h)
  })
}

// ---- voicepool_new (constructor cost, post-analyze) ----
// WHY: measures validate + 32 × VoiceSlot::new (each allocates a
// mono_buffer of block_size doubles). `CompiledTemplate::analyze` is
// hoisted OUT of the bench closure because real authoring re-uses one
// analyzed template across many pool constructions; the bench therefore
// reports the steady-state per-call cost, not first-edit cost from raw
// authoring nodes. If `set_template` and `voicepool_new` differ by
// roughly the slot-allocation constant across all fixtures, that confirms
// the compile is what dominates `set_template`.

///|
test "bench/voice/voicepool_new" (b : @bench.T) {
  let ctx = @dsp.DspContext::new(
    sample_rate=BENCH_SAMPLE_RATE,
    block_size=BENCH_BLOCK_SIZE,
  )
  let minimal = @graph.CompiledTemplate::analyze(bench_minimal_voice_nodes())
  let fm = @graph.CompiledTemplate::analyze(bench_fm_voice_nodes())
  let full = @graph.CompiledTemplate::analyze(bench_full_voice_nodes())
  b.bench(name="minimal_voice", fn() {
    let pool = VoicePool::new(minimal, ctx)
    b.keep(pool)
  })
  b.bench(name="fm_voice", fn() {
    let pool = VoicePool::new(fm, ctx)
    b.keep(pool)
  })
  b.bench(name="full_voice", fn() {
    let pool = VoicePool::new(full, ctx)
    b.keep(pool)
  })
}
