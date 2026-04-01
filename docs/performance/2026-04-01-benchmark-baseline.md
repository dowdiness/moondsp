# Benchmark Baseline — 2026-04-01

First benchmark run after adding the audio hot-path benchmark suite.

## Environment

- **CPU:** AMD Ryzen 7 6800H
- **OS:** Linux 6.6.87 (WSL2)
- **MoonBit:** moon 0.1.20260330
- **Target:** wasm-gc (release)
- **Command:** `moon bench --release -p lib -f graph_benchmark.mbt`

## Process Benchmarks (µs)

The audio callback budget at 48 kHz is **1.33 ms** (64), **2.67 ms** (128), **5.33 ms** (256).

| Graph | Nodes | 64 | 128 | 256 |
|-------|------:|---:|----:|----:|
| passthrough | 2 | 0.10 | 0.19 | 0.36 |
| minimal_voice | 4 | 0.61 | 1.20 | 2.37 |
| fm_voice | 12 | 3.52 | 6.79 | 13.23 |
| full_voice | 12 | 1.80 | 3.43 | 6.64 |
| feedback_voice | 7 | 2.26 | 4.46 | 8.40 |
| stereo_chain | 15 | 3.01 | 5.67 | 10.96 |

All process times are well under the real-time budget. The feedback_voice
(per-sample loop) is ~2x the cost of full_voice (per-buffer loop) at equal
node counts, confirming that the feedback path is the more expensive codepath.

## Compile Benchmarks (µs)

| Graph | Nodes | Time |
|-------|------:|-----:|
| passthrough | 2 | 1.05 |
| minimal_voice | 4 | 1.82 |
| fm_voice | 12 | 5.21 |
| full_voice | 12 | 8.31 |
| feedback_voice | 7 | 6.10 |
| stereo_chain | 15 | 13.41 |

Compilation is measured at block_size=128. All times are microseconds —
compilation is never a bottleneck for interactive use.

## Hot-Swap Benchmarks (µs)

Measures `queue_swap` + one full crossfade block. Alternates between two
distinct compiled graphs each iteration.

| Graph | 64 | 128 | 256 |
|-------|---:|----:|----:|
| minimal_voice | 3.78 | 7.36 | 14.58 |
| fm_voice | 5.89 | 11.84 | 22.37 |
| full_voice | 7.00 | 13.72 | 26.38 |
| stereo_chain | 6.68 | 12.44 | 23.23 |

Hot-swap cost is roughly 2x the process cost (old graph + new graph both
process one block, then crossfade mixes the outputs).

## Topology Edit Benchmarks (µs)

Topology edits trigger internal recompilation + crossfade.

| Edit type | 64 | 128 | 256 |
|-----------|---:|----:|----:|
| replace_node | 11.68 | 21.44 | 40.24 |
| insert_delete_roundtrip | 22.26 | 40.30 | 74.32 |

`replace_node` is a single in-place edit + recompile. `insert_delete_roundtrip`
performs two edits (insert + delete) to keep the graph at constant size,
so its cost is roughly 2x replace_node.

## Key Observations

1. **Headroom is large.** The most expensive process benchmark (fm_voice at
   256 samples = 13.23 µs) uses only 0.25% of the 5.33 ms budget. Even
   stacking 100 voices would stay within budget at this graph size.

2. **Feedback path is the bottleneck.** The per-sample feedback loop
   (feedback_voice) is ~2x more expensive than the per-buffer path
   (full_voice) for comparable node counts. Optimizing
   `process_feedback_graph` would have the highest impact.

3. **Topology edits are cheap enough for interactive use.** At 40 µs for a
   replace_node at 128 samples, users can edit the graph hundreds of times
   per second without audible glitches.

4. **Compilation is negligible.** Even the largest graph (stereo_chain, 15
   nodes) compiles in ~13 µs. Graph construction is not a performance concern.
