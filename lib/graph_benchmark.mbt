///|
const BENCH_SAMPLE_RATE : Double = 48000.0

///|
let bench_block_sizes : FixedArray[Int] = [64, 128, 256]

///|
/// Passthrough: constant → output (2 nodes). Baseline for graph traversal overhead.
fn build_bench_passthrough() -> GraphBuilder {
  let signal : GraphBuilder = GraphBuilder::constant(0.5)
  GraphBuilder::output(signal)
}

///|
/// Minimal voice: osc → gain → output (~4 nodes).
fn build_bench_minimal_voice() -> GraphBuilder {
  let freq : GraphBuilder = GraphBuilder::constant(440.0)
  let osc = freq.oscillator(Waveform::Saw)
  let gained = osc.gain(0.5)
  GraphBuilder::output(gained)
}

///|
/// FM voice: LFO → range → carrier → LPF → gain → output (~12 nodes).
/// Same topology as exit_deliverable().
fn build_bench_fm_voice() -> GraphBuilder {
  let lfo : GraphBuilder = GraphBuilder::constant(2.0).oscillator(Waveform::Sine)
  let freq = range(lfo, 200.0, 400.0)
  let carrier = freq.oscillator(Waveform::Sine)
  let filtered = carrier.biquad(BiquadMode::LowPass, 800.0, 1.0)
  let gained = filtered.gain(0.3)
  GraphBuilder::output(gained)
}

///|
/// Full voice: osc + noise → ADSR → filter → gain → delay → clip → output.
fn build_bench_full_voice() -> GraphBuilder {
  let freq : GraphBuilder = GraphBuilder::constant(220.0)
  let osc = freq.oscillator(Waveform::Saw)
  let noise : GraphBuilder = GraphBuilder::noise(42U)
  let noise_gained = noise.gain(0.2)
  let mixed = osc.mix(noise_gained)
  let env : GraphBuilder = GraphBuilder::adsr(5.0, 10.0, 0.6, 50.0)
  let modulated = mixed.mul(env)
  let filtered = modulated.biquad(BiquadMode::LowPass, 1200.0, 0.707)
  let gained = filtered.gain(0.7)
  let delayed = gained.delay(4800, 2400, 0.3)
  let clipped = delayed.clip(0.9)
  GraphBuilder::output(clipped)
}

///|
/// Feedback voice: constant → mix(osc, feedback) → gain → output.
/// The mix node references the downstream gain node, creating a z^-1 back-edge.
/// Uses raw DspNode array because GraphBuilder cannot express feedback cycles.
fn build_bench_feedback_voice_nodes() -> Array[DspNode] {
  [
    DspNode::constant(440.0),          // 0: freq
    DspNode::oscillator(Waveform::Saw, 440.0), // 1: osc (fixed freq)
    DspNode::biquad(1, BiquadMode::LowPass, 1000.0, 0.707), // 2: filter
    DspNode::mix(2, 5),                // 3: mix (filter + feedback from gain) — back-edge
    DspNode::delay(3, 4800, delay_samples=2400, feedback=0.0), // 4: delay
    DspNode::gain(4, 0.5),            // 5: gain (feedback source)
    DspNode::output(5),               // 6: output
  ]
}

///|
/// Stereo chain: full voice → pan → stereo filter → stereo delay →
/// stereo gain → stereo clip → stereo output.
fn build_bench_stereo_chain() -> GraphBuilder {
  let freq : GraphBuilder = GraphBuilder::constant(220.0)
  let osc = freq.oscillator(Waveform::Saw)
  let noise : GraphBuilder = GraphBuilder::noise(42U)
  let noise_gained = noise.gain(0.2)
  let mixed = osc.mix(noise_gained)
  let env : GraphBuilder = GraphBuilder::adsr(5.0, 10.0, 0.6, 50.0)
  let modulated = mixed.mul(env)
  let filtered = modulated.biquad(BiquadMode::LowPass, 1200.0, 0.707)
  let gained = filtered.gain(0.7)
  let panned = gained.pan(0.0)
  let stereo_filtered = panned.stereo_biquad(BiquadMode::LowPass, 2000.0, 0.707)
  let stereo_delayed = stereo_filtered.stereo_delay(4800, 2400, 0.3)
  let stereo_gained = stereo_delayed.stereo_gain(0.8)
  let stereo_clipped = stereo_gained.stereo_clip(0.9)
  GraphBuilder::stereo_output(stereo_clipped)
}

///|
test "bench graph: passthrough compiles" {
  let ctx = DspContext::new(BENCH_SAMPLE_RATE, 128)
  let compiled = CompiledDsp::compile(build_bench_passthrough().nodes(), ctx)
  assert_true(compiled is Some(_))
}

///|
test "bench graph: minimal voice compiles" {
  let ctx = DspContext::new(BENCH_SAMPLE_RATE, 128)
  let compiled = CompiledDsp::compile(build_bench_minimal_voice().nodes(), ctx)
  assert_true(compiled is Some(_))
}

///|
test "bench graph: fm voice compiles" {
  let ctx = DspContext::new(BENCH_SAMPLE_RATE, 128)
  let compiled = CompiledDsp::compile(build_bench_fm_voice().nodes(), ctx)
  assert_true(compiled is Some(_))
}

///|
test "bench graph: full voice compiles" {
  let ctx = DspContext::new(BENCH_SAMPLE_RATE, 128)
  let compiled = CompiledDsp::compile(build_bench_full_voice().nodes(), ctx)
  assert_true(compiled is Some(_))
}

///|
test "bench graph: feedback voice compiles" {
  let ctx = DspContext::new(BENCH_SAMPLE_RATE, 128)
  let compiled = CompiledDsp::compile(build_bench_feedback_voice_nodes(), ctx)
  assert_true(compiled is Some(_))
}

///|
test "bench graph: stereo chain compiles" {
  let ctx = DspContext::new(BENCH_SAMPLE_RATE, 128)
  let compiled = CompiledStereoDsp::compile(
    build_bench_stereo_chain().nodes(), ctx,
  )
  assert_true(compiled is Some(_))
}

///|
test "bench graph: stereo chain hotswap compiles" {
  let ctx = DspContext::new(BENCH_SAMPLE_RATE, 128)
  let compiled = CompiledStereoDsp::compile(
    build_bench_stereo_chain().nodes(), ctx,
  )
  assert_true(compiled is Some(_))
  let hs = CompiledStereoDspHotSwap::from_graph(
    compiled.unwrap(), crossfade_samples=128,
  )
  let left = AudioBuffer::filled(128)
  let right = AudioBuffer::filled(128)
  hs.process(ctx, left, right)
  assert_true(true)
}
