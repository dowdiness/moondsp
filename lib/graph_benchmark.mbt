///|
const BENCH_SAMPLE_RATE : Double = 48000.0

///|
/// WHY three sizes: 64 stresses per-block overhead, 128 is the production
/// AudioWorklet quantum, 256 is common for higher-latency backends.
let bench_block_sizes : FixedArray[Int] = [64, 128, 256]

///|
/// Passthrough: constant → output (2 nodes).
/// WHY: establishes the absolute floor for process() overhead — any time above
/// this is attributable to actual DSP math, not graph traversal bookkeeping.
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
/// FM voice: LFO → range → carrier → LPF → gain → output (12 nodes).
/// WHY exit_deliverable(): reuses the Phase 2 exit deliverable directly so
/// benchmark results stay comparable to the canonical "does it sound right?" graph.
fn build_bench_fm_voice() -> GraphBuilder {
  exit_deliverable()
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
/// Feedback voice (7 nodes): osc → filter → mix(filter, gain) → delay → gain → output.
/// WHY raw DspNode array: GraphBuilder cannot express feedback cycles. The mix
/// node at index 3 references the gain node at index 5 (which is downstream),
/// creating a z^-1 back-edge that the compiler detects and routes through the
/// per-sample feedback path (process_feedback_graph) instead of the per-buffer path.
/// WHY feedback=0.0 on delay: the recirculating feedback comes from the
/// explicit back-edge in mix(2,5), not from the delay's internal feedback tap.
fn build_bench_feedback_voice_nodes() -> Array[DspNode] {
  [
    DspNode::constant(440.0), // 0: freq
    DspNode::oscillator(Waveform::Saw, 440.0), // 1: osc (fixed freq)
    DspNode::biquad(1, BiquadMode::LowPass, 1000.0, 0.707), // 2: filter
    DspNode::mix(2, 5), // 3: mix (filter + feedback from gain) — back-edge
    DspNode::delay(3, 4800, delay_samples=2400, feedback=0.0), // 4: delay
    DspNode::gain(4, 0.5), // 5: gain (feedback source)
    DspNode::output(5), // 6: output
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

// ---- Validation tests ----
// WHY: a failed .unwrap() inside a benchmark closure gives no diagnostic.
// These guard-rail tests catch broken graph builders before the benchmark
// runner sees them, producing clear assertion failures instead of silent aborts.

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
    build_bench_stereo_chain().nodes(),
    ctx,
  )
  assert_true(compiled is Some(_))
}

///|
test "bench graph: stereo chain hotswap compiles" {
  let ctx = DspContext::new(BENCH_SAMPLE_RATE, 128)
  let compiled = CompiledStereoDsp::compile(
    build_bench_stereo_chain().nodes(),
    ctx,
  )
  assert_true(compiled is Some(_))
  let hs = CompiledStereoDspHotSwap::from_graph(
    compiled.unwrap(),
    crossfade_samples=128,
  )
  let left = AudioBuffer::filled(128)
  let right = AudioBuffer::filled(128)
  hs.process(ctx, left, right)
}

// ---- Process benchmarks ----
// WHY separate compile per block_size: the compiled graph's internal buffer
// capacity is tied to the context's block_size (see compiled_block_size in
// graph.mbt). Reusing a graph compiled at 128 with a 64-sample context would
// hit the capacity check and zero the output.

///|
test "bench/process/passthrough" (b : @bench.T) {
  let nodes = build_bench_passthrough().nodes()
  for block_size in bench_block_sizes {
    let ctx = DspContext::new(BENCH_SAMPLE_RATE, block_size)
    let compiled = CompiledDsp::compile(nodes, ctx).unwrap()
    let output = AudioBuffer::filled(block_size)
    b.bench(name="passthrough/\{block_size}", fn() {
      compiled.process(ctx, output)
      b.keep(output)
    })
  }
}

///|
test "bench/process/minimal_voice" (b : @bench.T) {
  let nodes = build_bench_minimal_voice().nodes()
  for block_size in bench_block_sizes {
    let ctx = DspContext::new(BENCH_SAMPLE_RATE, block_size)
    let compiled = CompiledDsp::compile(nodes, ctx).unwrap()
    let output = AudioBuffer::filled(block_size)
    b.bench(name="minimal_voice/\{block_size}", fn() {
      compiled.process(ctx, output)
      b.keep(output)
    })
  }
}

///|
test "bench/process/fm_voice" (b : @bench.T) {
  let nodes = build_bench_fm_voice().nodes()
  for block_size in bench_block_sizes {
    let ctx = DspContext::new(BENCH_SAMPLE_RATE, block_size)
    let compiled = CompiledDsp::compile(nodes, ctx).unwrap()
    let output = AudioBuffer::filled(block_size)
    b.bench(name="fm_voice/\{block_size}", fn() {
      compiled.process(ctx, output)
      b.keep(output)
    })
  }
}

///|
test "bench/process/full_voice" (b : @bench.T) {
  let nodes = build_bench_full_voice().nodes()
  for block_size in bench_block_sizes {
    let ctx = DspContext::new(BENCH_SAMPLE_RATE, block_size)
    let compiled = CompiledDsp::compile(nodes, ctx).unwrap()
    let output = AudioBuffer::filled(block_size)
    b.bench(name="full_voice/\{block_size}", fn() {
      compiled.process(ctx, output)
      b.keep(output)
    })
  }
}

///|
test "bench/process/feedback_voice" (b : @bench.T) {
  let nodes = build_bench_feedback_voice_nodes()
  for block_size in bench_block_sizes {
    let ctx = DspContext::new(BENCH_SAMPLE_RATE, block_size)
    let compiled = CompiledDsp::compile(nodes, ctx).unwrap()
    let output = AudioBuffer::filled(block_size)
    b.bench(name="feedback_voice/\{block_size}", fn() {
      compiled.process(ctx, output)
      b.keep(output)
    })
  }
}

///|
test "bench/process/stereo_chain" (b : @bench.T) {
  let nodes = build_bench_stereo_chain().nodes()
  for block_size in bench_block_sizes {
    let ctx = DspContext::new(BENCH_SAMPLE_RATE, block_size)
    let compiled = CompiledStereoDsp::compile(nodes, ctx).unwrap()
    let left = AudioBuffer::filled(block_size)
    let right = AudioBuffer::filled(block_size)
    b.bench(name="stereo_chain/\{block_size}", fn() {
      compiled.process(ctx, left, right)
      b.keep(left)
      b.keep(right)
    })
  }
}

///|
test "bench/compile/passthrough" (b : @bench.T) {
  let nodes = build_bench_passthrough().nodes()
  let ctx = DspContext::new(BENCH_SAMPLE_RATE, 128)
  b.bench(name="passthrough", fn() {
    let compiled = CompiledDsp::compile(nodes, ctx)
    b.keep(compiled)
  })
}

///|
test "bench/compile/minimal_voice" (b : @bench.T) {
  let nodes = build_bench_minimal_voice().nodes()
  let ctx = DspContext::new(BENCH_SAMPLE_RATE, 128)
  b.bench(name="minimal_voice", fn() {
    let compiled = CompiledDsp::compile(nodes, ctx)
    b.keep(compiled)
  })
}

///|
test "bench/compile/fm_voice" (b : @bench.T) {
  let nodes = build_bench_fm_voice().nodes()
  let ctx = DspContext::new(BENCH_SAMPLE_RATE, 128)
  b.bench(name="fm_voice", fn() {
    let compiled = CompiledDsp::compile(nodes, ctx)
    b.keep(compiled)
  })
}

///|
test "bench/compile/full_voice" (b : @bench.T) {
  let nodes = build_bench_full_voice().nodes()
  let ctx = DspContext::new(BENCH_SAMPLE_RATE, 128)
  b.bench(name="full_voice", fn() {
    let compiled = CompiledDsp::compile(nodes, ctx)
    b.keep(compiled)
  })
}

///|
test "bench/compile/feedback_voice" (b : @bench.T) {
  let nodes = build_bench_feedback_voice_nodes()
  let ctx = DspContext::new(BENCH_SAMPLE_RATE, 128)
  b.bench(name="feedback_voice", fn() {
    let compiled = CompiledDsp::compile(nodes, ctx)
    b.keep(compiled)
  })
}

///|
test "bench/compile/stereo_chain" (b : @bench.T) {
  let nodes = build_bench_stereo_chain().nodes()
  let ctx = DspContext::new(BENCH_SAMPLE_RATE, 128)
  b.bench(name="stereo_chain", fn() {
    let compiled = CompiledStereoDsp::compile(nodes, ctx)
    b.keep(compiled)
  })
}

///|
/// WHY a distinct graph: hot-swap crossfade blends old and new graphs sample
/// by sample. Using a structurally different topology (Sine vs Saw, different
/// freq/gain) ensures the crossfade codepath is exercised with genuinely
/// different sample values rather than blending a graph with itself.
fn build_bench_minimal_voice_alt() -> GraphBuilder {
  let freq : GraphBuilder = GraphBuilder::constant(880.0)
  let osc = freq.oscillator(Waveform::Sine)
  let gained = osc.gain(0.3)
  GraphBuilder::output(gained)
}

///|
/// WHY simpler than the main stereo chain: intentionally fewer nodes so the
/// hot-swap crossfade blends graphs of different sizes, which is the common
/// real-world case (user edits simplify or expand the graph).
fn build_bench_stereo_chain_alt() -> GraphBuilder {
  let freq : GraphBuilder = GraphBuilder::constant(330.0)
  let osc = freq.oscillator(Waveform::Sine)
  let gained = osc.gain(0.5)
  let panned = gained.pan(0.3)
  let stereo_gained = panned.stereo_gain(0.7)
  GraphBuilder::stereo_output(stereo_gained)
}

// ---- Hot-swap benchmarks ----
// WHY alternating: after process() completes a crossfade, the pending graph
// becomes active. Without alternation, every iteration after the first would
// queue_swap the same graph that is already active — crossfading a graph with
// itself. Alternating ensures each iteration swaps between genuinely different
// compiled graphs, exercising the real crossfade codepath.

///|
test "bench/hotswap/minimal_voice" (b : @bench.T) {
  let nodes_a = build_bench_minimal_voice().nodes()
  let nodes_b = build_bench_minimal_voice_alt().nodes()
  for block_size in bench_block_sizes {
    let ctx = DspContext::new(BENCH_SAMPLE_RATE, block_size)
    let compiled_a = CompiledDsp::compile(nodes_a, ctx).unwrap()
    let compiled_b = CompiledDsp::compile(nodes_b, ctx).unwrap()
    let hs = CompiledDspHotSwap::from_graph(
      compiled_a,
      crossfade_samples=block_size,
    )
    let output = AudioBuffer::filled(block_size)
    let use_b = @ref.new(true)
    b.bench(name="minimal_voice/\{block_size}", fn() {
      let next = if use_b.val { compiled_b } else { compiled_a }
      use_b.val = !use_b.val
      ignore(hs.queue_swap(next))
      hs.process(ctx, output)
      b.keep(output)
    })
  }
}

///|
test "bench/hotswap/fm_voice" (b : @bench.T) {
  let nodes_a = build_bench_fm_voice().nodes()
  let nodes_b = build_bench_minimal_voice().nodes()
  for block_size in bench_block_sizes {
    let ctx = DspContext::new(BENCH_SAMPLE_RATE, block_size)
    let compiled_a = CompiledDsp::compile(nodes_a, ctx).unwrap()
    let compiled_b = CompiledDsp::compile(nodes_b, ctx).unwrap()
    let hs = CompiledDspHotSwap::from_graph(
      compiled_a,
      crossfade_samples=block_size,
    )
    let output = AudioBuffer::filled(block_size)
    let use_b = @ref.new(true)
    b.bench(name="fm_voice/\{block_size}", fn() {
      let next = if use_b.val { compiled_b } else { compiled_a }
      use_b.val = !use_b.val
      ignore(hs.queue_swap(next))
      hs.process(ctx, output)
      b.keep(output)
    })
  }
}

///|
test "bench/hotswap/full_voice" (b : @bench.T) {
  let nodes_a = build_bench_full_voice().nodes()
  let nodes_b = build_bench_fm_voice().nodes()
  for block_size in bench_block_sizes {
    let ctx = DspContext::new(BENCH_SAMPLE_RATE, block_size)
    let compiled_a = CompiledDsp::compile(nodes_a, ctx).unwrap()
    let compiled_b = CompiledDsp::compile(nodes_b, ctx).unwrap()
    let hs = CompiledDspHotSwap::from_graph(
      compiled_a,
      crossfade_samples=block_size,
    )
    let output = AudioBuffer::filled(block_size)
    let use_b = @ref.new(true)
    b.bench(name="full_voice/\{block_size}", fn() {
      let next = if use_b.val { compiled_b } else { compiled_a }
      use_b.val = !use_b.val
      ignore(hs.queue_swap(next))
      hs.process(ctx, output)
      b.keep(output)
    })
  }
}

///|
test "bench/hotswap/stereo_chain" (b : @bench.T) {
  let nodes_a = build_bench_stereo_chain().nodes()
  let nodes_b = build_bench_stereo_chain_alt().nodes()
  for block_size in bench_block_sizes {
    let ctx = DspContext::new(BENCH_SAMPLE_RATE, block_size)
    let compiled_a = CompiledStereoDsp::compile(nodes_a, ctx).unwrap()
    let compiled_b = CompiledStereoDsp::compile(nodes_b, ctx).unwrap()
    let hs = CompiledStereoDspHotSwap::from_graph(
      compiled_a,
      crossfade_samples=block_size,
    )
    let left = AudioBuffer::filled(block_size)
    let right = AudioBuffer::filled(block_size)
    let use_b = @ref.new(true)
    b.bench(name="stereo_chain/\{block_size}", fn() {
      let next = if use_b.val { compiled_b } else { compiled_a }
      use_b.val = !use_b.val
      ignore(hs.queue_swap(next))
      hs.process(ctx, left, right)
      b.keep(left)
      b.keep(right)
    })
  }
}

// ---- Topology edit benchmarks ----
// WHY topology edits trigger full recompilation internally: the topology
// controller maintains authoring_nodes (the user's view) and a compiled graph.
// Each edit mutates authoring_nodes, recompiles, and crossfades to the new graph.
// This makes topology edits much more expensive than hot-swap (which only
// swaps pre-compiled graphs) or replace_node (which substitutes in-place).

///|
/// WHY replace_node is stable across iterations: replace mutates the node
/// in-place without changing the graph's node count or topology, so the
/// authoring array stays the same size every iteration.
test "bench/topology/replace_node" (b : @bench.T) {
  let nodes = build_bench_fm_voice().nodes()
  for block_size in bench_block_sizes {
    let ctx = DspContext::new(BENCH_SAMPLE_RATE, block_size)
    let tc = CompiledDspTopologyController::from_nodes(
      nodes,
      ctx,
      crossfade_samples=block_size,
    ).unwrap()
    let output = AudioBuffer::filled(block_size)
    let edit = GraphTopologyEdit::replace_node(0, DspNode::constant(3.0))
    b.bench(name="replace_node/\{block_size}", fn() {
      ignore(tc.queue_topology_edit(edit))
      tc.process(ctx, output)
      b.keep(output)
    })
  }
}

///|
/// WHY insert+delete roundtrip: a bare insert_node benchmark would grow the
/// authoring_nodes array by one node per iteration, causing unbounded O(N)
/// growth and making later iterations measure a larger graph than earlier ones.
/// By following each insert with a delete (and vice versa), the graph returns
/// to its original size every two process() calls, keeping measurements stable.
/// The cost measured is one insert recompile + one delete recompile per iteration.
test "bench/topology/insert_delete_roundtrip" (b : @bench.T) {
  let nodes = build_bench_fm_voice().nodes()
  for block_size in bench_block_sizes {
    let ctx = DspContext::new(BENCH_SAMPLE_RATE, block_size)
    let tc = CompiledDspTopologyController::from_nodes(
      nodes,
      ctx,
      crossfade_samples=block_size,
    ).unwrap()
    let output = AudioBuffer::filled(block_size)
    let last_index = nodes.length() - 1
    let insert_edit = GraphTopologyEdit::insert_node(
      last_index,
      GraphTopologyInputSlot::Input0,
      DspNode::gain(-1, 0.9),
    )
    // WHY delete targets last_index + 1: after insert, the new gain node is
    // appended at index last_index + 1. The output node (at last_index) was
    // rewired to read from the new gain. Deleting the gain (last_index + 1)
    // and retargeting output (last_index) back to its original source restores
    // the graph to its pre-insert state.
    let delete_edit = GraphTopologyEdit::delete_node(
      last_index + 1,
      last_index,
      GraphTopologyInputSlot::Input0,
      last_index + 1,
    )
    b.bench(name="insert_delete_roundtrip/\{block_size}", fn() {
      ignore(tc.queue_topology_edit(insert_edit))
      tc.process(ctx, output)
      ignore(tc.queue_topology_edit(delete_edit))
      tc.process(ctx, output)
      b.keep(output)
    })
  }
}
