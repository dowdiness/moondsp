# Audio Hot-Path Benchmarks — Design Spec

> **Date:** 2026-04-01
> **Scope:** Benchmarks for the compiled graph process loop, graph compilation, hot-swap crossfade, and topology editing.

---

## Goal

Establish performance baselines for the four most latency-sensitive operations in the DSP engine:

1. **Process** — the per-buffer audio callback (`CompiledDsp::process`, `CompiledStereoDsp::process`)
2. **Compile** — graph construction from `Array[DspNode]` → compiled form
3. **Hot-swap** — live graph replacement with crossfade (mono and stereo)
4. **Topology edit** — live node insertion/replacement/deletion via `CompiledDspTopologyController`

These benchmarks enable regression detection and informed optimization decisions.

---

## Benchmark Graphs

Five realistic graph configurations built via the public tagless `GraphBuilder` API, plus one minimal baseline (6 total).

| Name | Nodes | Description | Feedback? | Stereo? |
|------|-------|-------------|-----------|---------|
| **Passthrough** | 2 | constant → output (baseline for graph traversal overhead) | No | No |
| **Minimal voice** | 4 | osc → gain → output | No | No |
| **FM voice** | 12 | LFO → range → carrier → LPF → gain → output (`exit_deliverable`) | No | No |
| **Full voice** | 12 | osc → ADSR → filter → gain → delay → clip → output, noise bus mixed in | No | No |
| **Feedback voice** | 7 | osc → filter → delay(feedback) → gain → output, with `z^-1` back-edge | Yes | No |
| **Stereo chain** | 15 | Full voice → pan → stereo filter → stereo delay → stereo gain → stereo clip → stereo output | No | Yes |

Node counts measured from implemented graph builders.

Each graph is constructed by a `fn build_bench_*() -> GraphBuilder` function using the same tagless API that real users would use. Graph parameters (frequencies, cutoffs, gains) use production-realistic values.

Each graph builder function must have a companion unit test confirming successful compilation before being used in benchmarks (a failed `.unwrap()` in a benchmark gives no diagnostic).

---

## Dimensions

### Block sizes

Each process and hot-swap benchmark runs across three block sizes at 48 kHz:

| Block size | Real-time budget |
|------------|------------------|
| 64 samples | ~1.33 ms |
| 128 samples | ~2.67 ms (production target) |
| 256 samples | ~5.33 ms |

Compile benchmarks have no block-size dimension — compilation cost is independent of buffer size.

**Important:** Each block-size variant requires its own `DspContext` and its own `compile()` call. The compiled graph's internal buffer capacity is tied to the context's block size (`compiled_block_size` in `graph.mbt`). Do not reuse a graph compiled at block_size=128 with a block_size=64 context.

### Naming convention

```
process/<graph_name>/<block_size>
compile/<graph_name>
hotswap/<graph_name>/<block_size>
topology/<edit_type>/<block_size>
```

Examples: `process/fm_voice/128`, `compile/stereo_chain`, `hotswap/full_voice/128`, `topology/replace_node/128`.

---

## Benchmark Categories

### 1. Process (per-buffer hot path)

**Count:** 6 graphs x 3 block sizes = 18 benchmarks

- Graph is compiled once before the benchmark loop (one compile per block size)
- Each iteration calls `process()` on the pre-compiled graph
- Output buffer is passed to `b.keep()` to prevent dead-code elimination
- For stereo graphs, both left and right output buffers are kept
- The passthrough graph (2 nodes) establishes the floor for graph traversal overhead

At 48 kHz / 128 samples, the audio callback fires 375x/sec — this is the most critical path.

### 2. Compile (graph construction)

**Count:** 6 graphs = 6 benchmarks

- Each iteration calls `CompiledDsp::compile()` or `CompiledStereoDsp::compile()`
- Includes the optimization pass (constant folding, dead-node elimination)
- The compiled result is kept to prevent elimination
- Measures latency users experience when building or rebuilding a graph

### 3. Hot-swap (live graph replacement)

**Count:** 4 graphs x 3 block sizes = 12 benchmarks

- `crossfade_samples` is set equal to the block size for each benchmark, so every iteration measures a complete crossfade
- Each iteration queues a swap then processes one buffer (the full crossfade)
- Mono graphs (minimal, FM, full voice) use `CompiledDspHotSwap`
- Stereo chain uses `CompiledStereoDspHotSwap`
- Two distinct pre-compiled graphs (A and B) are created; each iteration queues B into the hot-swap wrapper and processes the crossfade buffer

Hot-swap latency matters during live performance when the user edits the graph.

### 4. Topology edit (live node manipulation)

**Count:** 2 edit types x 3 block sizes = 6 benchmarks

- Uses `CompiledDspTopologyController` on the FM voice graph
- Two edit types benchmarked:
  - `replace_node` — replace a node in-place (stable graph size across iterations)
  - `insert_delete_roundtrip` — insert a node then delete it, keeping the graph at constant size (a bare insert would grow the authoring_nodes array unboundedly, and a bare delete would be a no-op after the first iteration)
- Each iteration calls `queue_topology_edit()` then `process()` (which triggers internal recompilation + crossfade)
- `crossfade_samples` is set equal to the block size

Topology edits trigger internal recompilation, making them more expensive than hot-swap. This category isolates that cost.

### Total: 42 benchmarks

---

## File Structure

Single file: `lib/graph_benchmark.mbt`

```
1. Constants — sample rate (48000.0), block sizes (64, 128, 256), graph parameters
2. Graph builders — 6 `fn build_bench_*() -> GraphBuilder` functions (+ 2 alternate graphs for hot-swap)
3. Graph builder validation tests — 7 unit tests confirming successful compilation
4. Process benchmarks — 18 benchmark functions using @bench.T
5. Compile benchmarks — 6 benchmark functions
6. Hot-swap benchmarks — 12 benchmark functions
7. Topology edit benchmarks — 6 benchmark functions
```

Note: `moon bench` discovers benchmark tests in `*_benchmark.mbt` files (verified via smoke test). The `@bench` package must be imported in `lib/moon.pkg`.

### Implementation patterns

Process — note separate compile per block size:

```moonbit
test "bench/process/fm_voice" (b : @bench.T) {
  let graph : GraphBuilder = build_bench_fm_voice()
  for block_size in [64, 128, 256] {
    let ctx = DspContext::new(48000.0, block_size)
    let compiled = CompiledDsp::compile(graph.nodes(), ctx).unwrap()
    let output = AudioBuffer::filled(block_size)
    b.bench(name="fm_voice/\{block_size}", fn() {
      compiled.process(ctx, output)
      b.keep(output)
    })
  }
}
```

Hot-swap — `crossfade_samples` matches block size for complete crossfade per iteration:

```moonbit
test "bench/hotswap/fm_voice" (b : @bench.T) {
  let graph_a : GraphBuilder = build_bench_fm_voice()
  let graph_b : GraphBuilder = build_bench_full_voice()
  for block_size in [64, 128, 256] {
    let ctx = DspContext::new(48000.0, block_size)
    let compiled_a = CompiledDsp::compile(graph_a.nodes(), ctx).unwrap()
    let compiled_b = CompiledDsp::compile(graph_b.nodes(), ctx).unwrap()
    let hs = CompiledDspHotSwap::from_graph(compiled_a, crossfade_samples=block_size)
    let output = AudioBuffer::filled(block_size)
    b.bench(name="fm_to_full/\{block_size}", fn() {
      ignore(hs.queue_swap(compiled_b))
      hs.process(ctx, output)
      b.keep(output)
    })
  }
}
```

Topology edit — measures recompilation + crossfade triggered by a single edit:

```moonbit
test "bench/topology/replace_node" (b : @bench.T) {
  let graph : GraphBuilder = build_bench_fm_voice()
  for block_size in [64, 128, 256] {
    let ctx = DspContext::new(48000.0, block_size)
    let tc = CompiledDspTopologyController::from_nodes(
      graph.nodes(), ctx, crossfade_samples=block_size,
    ).unwrap()
    let output = AudioBuffer::filled(block_size)
    let edit = GraphTopologyEdit::replace_node(
      1, DspNode::constant(3.0),
    )
    b.bench(name="replace_node/\{block_size}", fn() {
      ignore(tc.queue_topology_edit(edit))
      tc.process(ctx, output)
      b.keep(output)
    })
  }
}
```

### Running

```bash
moon bench --release -p lib
```

---

## What These Benchmarks Do NOT Cover

- Individual DSP primitive throughput (osc, filter, delay in isolation) — future work
- Standalone `optimize_graph` cost — currently folded into compile benchmarks; can be split out if optimization becomes a bottleneck
- Memory allocation tracking — MoonBit does not expose GC metrics to user code
- Multi-voice polyphony — Phase 3 scope
- Browser/AudioWorklet overhead — platform-layer concern, not measurable in `moon bench`

---

## Success Criteria

1. All 42 benchmarks compile and run under `moon bench --release -p lib`
2. All 7 graph builder validation tests pass under `moon test -p lib`
3. Process benchmarks for 128-sample blocks complete well under the 2.67 ms real-time budget
4. Results are reproducible across runs (low variance)
5. No heap allocation in the process benchmark loop (verified by code inspection, not runtime measurement)
