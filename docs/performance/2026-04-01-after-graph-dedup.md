# Benchmark Snapshot — 2026-04-01 (after graph dedup)

After unifying 7 pairs of duplicated mono/stereo functions. 315 net lines removed.

## Environment

- **CPU:** AMD Ryzen 7 6800H
- **OS:** Linux 6.6.87 (WSL2)
- **MoonBit:** moon 0.1.20260330
- **Target:** wasm-gc (release)
- **Command:** `moon bench --release -p lib -f graph_benchmark.mbt`

## Process Benchmarks (µs)

| Graph | Nodes | 64 | 128 | 256 |
|-------|------:|---:|----:|----:|
| passthrough | 2 | 0.10 | 0.18 | 0.36 |
| minimal_voice | 4 | 0.61 | 1.19 | 2.36 |
| fm_voice | 12 | 3.49 | 6.81 | 13.36 |
| full_voice | 12 | 1.81 | 3.40 | 6.63 |
| feedback_voice | 7 | 2.45 | 4.70 | 9.06 |
| stereo_chain | 15 | 2.98 | 5.71 | 11.64 |

## Compile Benchmarks (µs)

| Graph | Nodes | Time |
|-------|------:|-----:|
| passthrough | 2 | 0.99 |
| minimal_voice | 4 | 1.79 |
| fm_voice | 12 | 5.15 |
| full_voice | 12 | 8.75 |
| feedback_voice | 7 | 9.71 |
| stereo_chain | 15 | 15.17 |

## Hot-Swap Benchmarks (µs)

| Graph | 64 | 128 | 256 |
|-------|---:|----:|----:|
| minimal_voice | 3.79 | 7.32 | 14.40 |
| fm_voice | 5.78 | 11.28 | 22.24 |
| full_voice | 7.13 | 13.53 | 26.39 |
| stereo_chain | 6.38 | 12.12 | 23.76 |

## Topology Edit Benchmarks (µs)

| Edit type | 64 | 128 | 256 |
|-----------|---:|----:|----:|
| replace_node | 11.86 | 21.98 | 40.63 |
| insert_delete_roundtrip | 22.54 | 40.66 | 77.69 |

## Comparison vs Baseline (128 samples)

| Category | Graph | Baseline | After | Delta |
|----------|-------|----------|-------|-------|
| process | passthrough | 0.19 | 0.18 | ~same |
| process | minimal_voice | 1.20 | 1.19 | ~same |
| process | fm_voice | 6.79 | 6.81 | ~same |
| process | full_voice | 3.43 | 3.40 | ~same |
| process | feedback_voice | 4.46 | 4.70 | +5% |
| process | stereo_chain | 5.67 | 5.71 | ~same |
| compile | feedback_voice | 6.10 | 9.71 | +59% |
| compile | stereo_chain | 13.41 | 15.17 | +13% |
| hotswap | fm_voice | 11.84 | 11.28 | -5% |

## Notes

- **Process and hot-swap: no regression.** All within normal run-to-run
  variance (~5%).
- **Compile feedback_voice +59%** (6.10 → 9.71 µs with high σ ±1.50 µs):
  the unified `compile_graph_impl` uses closure callbacks which add GC
  pressure during compilation. Still microseconds — not an interactive
  bottleneck. Worth revisiting if compilation frequency increases in
  Phase 3 (voice management).
- All times remain far under the 2.67 ms real-time budget.
