# Audio Hot-Path Benchmarks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 45 benchmarks covering the compiled graph process loop, compilation, hot-swap, and topology editing at three block sizes.

**Architecture:** Single benchmark file `lib/graph_benchmark.mbt` using MoonBit's `@bench.T` API. Six graph configurations (passthrough baseline through stereo chain) built via the public tagless `GraphBuilder` API, each with a companion validation test.

**Tech Stack:** MoonBit, `@bench` (moonbitlang/core/bench)

**Spec:** `docs/superpowers/specs/2026-04-01-audio-hotpath-benchmarks-design.md`

---

### Task 1: Add `@bench` import to lib/moon.pkg

**Files:**
- Modify: `lib/moon.pkg`

- [ ] **Step 1: Add the bench import**

Add the `@bench` import to `lib/moon.pkg`:

```
import {
  "moonbitlang/core/bench" @bench,
  "moonbitlang/core/math" @math,
  "moonbitlang/core/ref" @ref,
}
```

- [ ] **Step 2: Verify the project still compiles**

Run: `moon check`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add lib/moon.pkg
git commit -m "chore: add @bench import to lib package"
```

---

### Task 2: Graph builder functions and validation tests

**Files:**
- Create: `lib/graph_benchmark.mbt`

- [ ] **Step 1: Create the benchmark file with constants and all 7 graph builders**

Create `lib/graph_benchmark.mbt` with:

```moonbit
///|
const BENCH_SAMPLE_RATE : Double = 48000.0

///|
const BENCH_BLOCK_SIZES : FixedArray[Int] = [64, 128, 256]

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
```

- [ ] **Step 2: Run moon check**

Run: `moon check`
Expected: No errors.

- [ ] **Step 3: Add 7 validation tests confirming each graph compiles**

Append to `lib/graph_benchmark.mbt`:

```moonbit
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
```

- [ ] **Step 4: Run tests to verify all 7 validation tests pass**

Run: `moon test -p lib -f graph_benchmark.mbt`
Expected: 7 tests passed.

- [ ] **Step 5: Commit**

```bash
git add lib/graph_benchmark.mbt
git commit -m "feat: add benchmark graph builders with validation tests"
```

---

### Task 3: Process benchmarks (18 benchmarks)

**Files:**
- Modify: `lib/graph_benchmark.mbt`

- [ ] **Step 1: Add process benchmarks for all 7 graphs**

Append to `lib/graph_benchmark.mbt`:

```moonbit
///|
test "bench/process/passthrough" (b : @bench.T) {
  let nodes = build_bench_passthrough().nodes()
  for block_size in BENCH_BLOCK_SIZES {
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
  for block_size in BENCH_BLOCK_SIZES {
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
  for block_size in BENCH_BLOCK_SIZES {
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
  for block_size in BENCH_BLOCK_SIZES {
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
  for block_size in BENCH_BLOCK_SIZES {
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
  for block_size in BENCH_BLOCK_SIZES {
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
```

Note: 5 mono graphs × 3 block sizes = 15 + 1 stereo graph × 3 = 3, totaling 18 process benchmarks.

- [ ] **Step 2: Run moon check**

Run: `moon check`
Expected: No errors.

- [ ] **Step 3: Run benchmarks to verify they execute**

Run: `moon bench --release -p lib -f graph_benchmark.mbt`
Expected: All process benchmarks run and print timing results. No crashes.

- [ ] **Step 4: Commit**

```bash
git add lib/graph_benchmark.mbt
git commit -m "feat: add 18 process benchmarks for compiled graph hot path"
```

---

### Task 4: Compile benchmarks (6 benchmarks)

**Files:**
- Modify: `lib/graph_benchmark.mbt`

- [ ] **Step 1: Add compile benchmarks for all 7 graphs**

Append to `lib/graph_benchmark.mbt`:

```moonbit
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
```

Note: 5 mono + 1 stereo = 6 compile benchmarks. No block-size dimension.

- [ ] **Step 2: Run moon check**

Run: `moon check`
Expected: No errors.

- [ ] **Step 3: Run benchmarks to verify**

Run: `moon bench --release -p lib -f graph_benchmark.mbt`
Expected: All compile benchmarks run. Compile times should be measurably larger than process times.

- [ ] **Step 4: Commit**

```bash
git add lib/graph_benchmark.mbt
git commit -m "feat: add 6 compile benchmarks for graph construction"
```

---

### Task 5: Hot-swap benchmarks (12 benchmarks)

**Files:**
- Modify: `lib/graph_benchmark.mbt`

- [ ] **Step 1: Add a helper to build an alternate mono graph for swapping**

Append to `lib/graph_benchmark.mbt`:

```moonbit
///|
/// Alternate minimal voice for hot-swap benchmarks (different freq/gain).
fn build_bench_minimal_voice_alt() -> GraphBuilder {
  let freq : GraphBuilder = GraphBuilder::constant(880.0)
  let osc = freq.oscillator(Waveform::Sine)
  let gained = osc.gain(0.3)
  GraphBuilder::output(gained)
}

///|
/// Alternate stereo chain for hot-swap benchmarks (different freq).
fn build_bench_stereo_chain_alt() -> GraphBuilder {
  let freq : GraphBuilder = GraphBuilder::constant(330.0)
  let osc = freq.oscillator(Waveform::Sine)
  let gained = osc.gain(0.5)
  let panned = gained.pan(0.3)
  let stereo_gained = panned.stereo_gain(0.7)
  GraphBuilder::stereo_output(stereo_gained)
}
```

- [ ] **Step 2: Add mono hot-swap benchmarks (minimal, FM, full voice)**

Append to `lib/graph_benchmark.mbt`:

```moonbit
///|
test "bench/hotswap/minimal_voice" (b : @bench.T) {
  let nodes_a = build_bench_minimal_voice().nodes()
  let nodes_b = build_bench_minimal_voice_alt().nodes()
  for block_size in BENCH_BLOCK_SIZES {
    let ctx = DspContext::new(BENCH_SAMPLE_RATE, block_size)
    let compiled_a = CompiledDsp::compile(nodes_a, ctx).unwrap()
    let compiled_b = CompiledDsp::compile(nodes_b, ctx).unwrap()
    let hs = CompiledDspHotSwap::from_graph(
      compiled_a, crossfade_samples=block_size,
    )
    let output = AudioBuffer::filled(block_size)
    b.bench(name="minimal_voice/\{block_size}", fn() {
      ignore(hs.queue_swap(compiled_b))
      hs.process(ctx, output)
      b.keep(output)
    })
  }
}

///|
test "bench/hotswap/fm_voice" (b : @bench.T) {
  let nodes_a = build_bench_fm_voice().nodes()
  let nodes_b = build_bench_minimal_voice().nodes()
  for block_size in BENCH_BLOCK_SIZES {
    let ctx = DspContext::new(BENCH_SAMPLE_RATE, block_size)
    let compiled_a = CompiledDsp::compile(nodes_a, ctx).unwrap()
    let compiled_b = CompiledDsp::compile(nodes_b, ctx).unwrap()
    let hs = CompiledDspHotSwap::from_graph(
      compiled_a, crossfade_samples=block_size,
    )
    let output = AudioBuffer::filled(block_size)
    b.bench(name="fm_voice/\{block_size}", fn() {
      ignore(hs.queue_swap(compiled_b))
      hs.process(ctx, output)
      b.keep(output)
    })
  }
}

///|
test "bench/hotswap/full_voice" (b : @bench.T) {
  let nodes_a = build_bench_full_voice().nodes()
  let nodes_b = build_bench_fm_voice().nodes()
  for block_size in BENCH_BLOCK_SIZES {
    let ctx = DspContext::new(BENCH_SAMPLE_RATE, block_size)
    let compiled_a = CompiledDsp::compile(nodes_a, ctx).unwrap()
    let compiled_b = CompiledDsp::compile(nodes_b, ctx).unwrap()
    let hs = CompiledDspHotSwap::from_graph(
      compiled_a, crossfade_samples=block_size,
    )
    let output = AudioBuffer::filled(block_size)
    b.bench(name="full_voice/\{block_size}", fn() {
      ignore(hs.queue_swap(compiled_b))
      hs.process(ctx, output)
      b.keep(output)
    })
  }
}
```

- [ ] **Step 3: Add stereo hot-swap benchmark**

Append to `lib/graph_benchmark.mbt`:

```moonbit
///|
test "bench/hotswap/stereo_chain" (b : @bench.T) {
  let nodes_a = build_bench_stereo_chain().nodes()
  let nodes_b = build_bench_stereo_chain_alt().nodes()
  for block_size in BENCH_BLOCK_SIZES {
    let ctx = DspContext::new(BENCH_SAMPLE_RATE, block_size)
    let compiled_a = CompiledStereoDsp::compile(nodes_a, ctx).unwrap()
    let compiled_b = CompiledStereoDsp::compile(nodes_b, ctx).unwrap()
    let hs = CompiledStereoDspHotSwap::from_graph(
      compiled_a, crossfade_samples=block_size,
    )
    let left = AudioBuffer::filled(block_size)
    let right = AudioBuffer::filled(block_size)
    b.bench(name="stereo_chain/\{block_size}", fn() {
      ignore(hs.queue_swap(compiled_b))
      hs.process(ctx, left, right)
      b.keep(left)
      b.keep(right)
    })
  }
}
```

- [ ] **Step 4: Run moon check**

Run: `moon check`
Expected: No errors.

- [ ] **Step 5: Run benchmarks to verify**

Run: `moon bench --release -p lib -f graph_benchmark.mbt`
Expected: All hot-swap benchmarks run. Each shows crossfade timing.

- [ ] **Step 6: Commit**

```bash
git add lib/graph_benchmark.mbt
git commit -m "feat: add 12 hot-swap benchmarks for mono and stereo graphs"
```

---

### Task 6: Topology edit benchmarks (9 benchmarks)

**Files:**
- Modify: `lib/graph_benchmark.mbt`

- [ ] **Step 1: Add replace_node topology benchmark**

Append to `lib/graph_benchmark.mbt`:

```moonbit
///|
test "bench/topology/replace_node" (b : @bench.T) {
  let nodes = build_bench_fm_voice().nodes()
  for block_size in BENCH_BLOCK_SIZES {
    let ctx = DspContext::new(BENCH_SAMPLE_RATE, block_size)
    let tc = CompiledDspTopologyController::from_nodes(
      nodes, ctx, crossfade_samples=block_size,
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
```

- [ ] **Step 2: Add insert_node topology benchmark**

Append to `lib/graph_benchmark.mbt`:

```moonbit
///|
test "bench/topology/insert_node" (b : @bench.T) {
  let nodes = build_bench_fm_voice().nodes()
  for block_size in BENCH_BLOCK_SIZES {
    let ctx = DspContext::new(BENCH_SAMPLE_RATE, block_size)
    let tc = CompiledDspTopologyController::from_nodes(
      nodes, ctx, crossfade_samples=block_size,
    ).unwrap()
    let output = AudioBuffer::filled(block_size)
    // Insert a gain node before the output node (last node in the FM voice)
    let last_index = nodes.length() - 1
    let insert_edit = GraphTopologyEdit::insert_node(
      last_index,
      GraphTopologyInputSlot::Input0,
      DspNode::gain(-1, 0.9),
    )
    b.bench(name="insert_node/\{block_size}", fn() {
      ignore(tc.queue_topology_edit(insert_edit))
      tc.process(ctx, output)
      b.keep(output)
    })
  }
}
```

- [ ] **Step 3: Add delete_node topology benchmark**

Append to `lib/graph_benchmark.mbt`:

```moonbit
///|
test "bench/topology/delete_node" (b : @bench.T) {
  // Build a graph with an extra gain node that can be deleted each iteration.
  // FM voice with an extra gain appended before output.
  let fm : GraphBuilder = build_bench_fm_voice()
  let nodes = fm.nodes()
  for block_size in BENCH_BLOCK_SIZES {
    let ctx = DspContext::new(BENCH_SAMPLE_RATE, block_size)
    let tc = CompiledDspTopologyController::from_nodes(
      nodes, ctx, crossfade_samples=block_size,
    ).unwrap()
    let output = AudioBuffer::filled(block_size)
    // First insert a node so we have something to delete
    let last_index = nodes.length() - 1
    let insert_edit = GraphTopologyEdit::insert_node(
      last_index,
      GraphTopologyInputSlot::Input0,
      DspNode::gain(-1, 0.9),
    )
    ignore(tc.queue_topology_edit(insert_edit))
    tc.process(ctx, output)
    // Now benchmark deleting it — the topology controller tracks the inserted node
    let delete_edit = GraphTopologyEdit::delete_node(
      last_index,
      last_index + 1,
      GraphTopologyInputSlot::Input0,
      last_index,
    )
    b.bench(name="delete_node/\{block_size}", fn() {
      ignore(tc.queue_topology_edit(delete_edit))
      tc.process(ctx, output)
      b.keep(output)
    })
  }
}
```

- [ ] **Step 4: Run moon check**

Run: `moon check`
Expected: No errors.

- [ ] **Step 5: Run benchmarks to verify topology edits execute**

Run: `moon bench --release -p lib -f graph_benchmark.mbt`
Expected: All 9 topology benchmarks run. Topology edits should be measurably slower than process-only benchmarks due to internal recompilation.

- [ ] **Step 6: Commit**

```bash
git add lib/graph_benchmark.mbt
git commit -m "feat: add 9 topology edit benchmarks for replace/insert/delete"
```

---

### Task 7: Final verification and cleanup

**Files:**
- Modify: `lib/graph_benchmark.mbt` (if needed)
- Modify: `lib/moon.pkg` (if needed)

- [ ] **Step 1: Run all existing tests to verify nothing broke**

Run: `moon test -p lib`
Expected: All existing tests pass plus 7 new validation tests.

- [ ] **Step 2: Run the full benchmark suite**

Run: `moon bench --release -p lib -f graph_benchmark.mbt`
Expected: All 49 benchmarks run and print timing results. Verify:
- Process benchmarks for 128-sample blocks are well under 2.67 ms
- Compile benchmarks complete without timeout
- Hot-swap benchmarks show crossfade timing
- Topology benchmarks show recompilation overhead

- [ ] **Step 3: Regenerate interfaces and format**

Run: `moon info && moon fmt`
Expected: No errors.

- [ ] **Step 4: Check for API changes**

Run: `git diff -- '*.mbti'`
Expected: No changes to .mbti files (benchmarks are private functions, not public API).

- [ ] **Step 5: Update the spec with actual node counts**

Print node counts for each graph builder and update the TBD entries in `docs/superpowers/specs/2026-04-01-audio-hotpath-benchmarks-design.md`.

- [ ] **Step 6: Commit**

```bash
git add lib/graph_benchmark.mbt docs/superpowers/specs/2026-04-01-audio-hotpath-benchmarks-design.md
git commit -m "feat: complete audio hot-path benchmark suite (45 benchmarks)"
```
