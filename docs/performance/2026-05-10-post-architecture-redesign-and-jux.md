# Performance Snapshot - 2026-05-10 (Post-Architecture Redesign; .jux Shipped)

Snapshot after the graph package split, API-stabilization pass, pattern
scheduler, mini-notation pipeline, and `.jux` stereo split support. The graph
hot-path benchmarks remain comparable to prior snapshots; dedicated `.jux`
benchmarks cover pattern query, mini parse, scheduler dispatch, and stereo
routing.

This snapshot keeps the existing graph hot-path benchmark suite unchanged so
the process/compile/hot-swap/topology numbers remain comparable to the
2026-04-09 pre-architecture-redesign baseline.

## Environment

- **CPU:** AMD Ryzen 7 6800H with Radeon Graphics
- **OS:** Linux 6.6.87.2-microsoft-standard-WSL2
- **MoonBit:** moon 0.1.20260427 (48d7def 2026-04-27)
- **Git commit:** 07c8210912e5c51e7e82dea8a116ffca8efe79ee
- **Target:** wasm-gc (release)
- **Graph command:** `moon bench --release -p graph -f graph_benchmark.mbt`
- **Graph result:** 18 benchmark test groups passed, covering 45 measured
  cases across process, compile, hot-swap, and topology benchmarks.
- **.jux commands:**
  - `moon bench --release -p pattern -f jux_benchmark.mbt`
  - `moon bench --release -p mini -f jux_benchmark.mbt`
  - `moon bench --release -p scheduler -f jux_benchmark.mbt`
- **.jux result:** 5 benchmark test groups passed, covering 8 measured cases.
- **Regression suite:** `moon test` - 632 passed, 0 failed

## Process Benchmarks (us)

| Graph | Nodes | 64 | 128 | 256 |
|-------|------:|---:|----:|----:|
| passthrough | 2 | 0.19 | 0.35 | 0.70 |
| minimal_voice | 4 | 0.71 | 1.35 | 2.71 |
| fm_voice | 12 | 3.71 | 7.20 | 13.92 |
| full_voice | 12 | 1.95 | 3.71 | 7.09 |
| feedback_voice | 7 | 2.60 | 4.90 | 9.74 |
| stereo_chain | 15 | 3.42 | 6.47 | 12.08 |

## Compile Benchmarks (us)

| Graph | Nodes | Time |
|-------|------:|-----:|
| passthrough | 2 | 0.90 |
| minimal_voice | 4 | 1.66 |
| fm_voice | 12 | 4.41 |
| full_voice | 12 | 7.45 |
| feedback_voice | 7 | 5.71 |
| stereo_chain | 15 | 13.23 |

## Hot-Swap Benchmarks (us)

| Graph | 64 | 128 | 256 |
|-------|---:|----:|----:|
| minimal_voice | 3.76 | 7.45 | 15.20 |
| fm_voice | 6.05 | 11.43 | 22.76 |
| full_voice | 7.15 | 13.95 | 28.06 |
| stereo_chain | 7.34 | 13.84 | 26.92 |

## Topology Edit Benchmarks (us)

| Edit type | 64 | 128 | 256 |
|-----------|---:|----:|----:|
| replace_node | 12.66 | 22.46 | 44.17 |
| insert_delete_roundtrip | 23.91 | 42.20 | 78.94 |

## Dedicated .jux Benchmarks (us)

| Area | Case | Time |
|------|------|-----:|
| pattern query | rev_4step | 3.86 |
| pattern query | fast_4step | 5.72 |
| mini parse | s_rev | 0.68 |
| mini parse | s_fast | 0.78 |
| mini parse | stack_rev | 0.86 |
| scheduler dispatch | process_events_8_jux_events | 17.93 |
| stereo routing | voicepool_process_8_panned_jux_voices | 28.54 |
| scheduler block | process_block_jux_rev | 10.25 |

## Comparison vs 2026-04-09 (128 samples)

| Category | Graph / edit | 2026-04-09 | 2026-05-10 | Delta |
|----------|--------------|-----------:|-----------:|------:|
| process | passthrough | 0.78 | 0.35 | -55% |
| process | minimal_voice | 2.85 | 1.35 | -53% |
| process | fm_voice | 16.86 | 7.20 | -57% |
| process | full_voice | 6.62 | 3.71 | -44% |
| process | feedback_voice | 9.26 | 4.90 | -47% |
| process | stereo_chain | 8.97 | 6.47 | -28% |
| compile | passthrough | 1.90 | 0.90 | -53% |
| compile | minimal_voice | 3.01 | 1.66 | -45% |
| compile | fm_voice | 9.27 | 4.41 | -52% |
| compile | full_voice | 13.17 | 7.45 | -43% |
| compile | feedback_voice | 13.12 | 5.71 | -56% |
| compile | stereo_chain | 24.17 | 13.23 | -45% |
| hot-swap | minimal_voice | 24.81 | 7.45 | -70% |
| hot-swap | fm_voice | 22.11 | 11.43 | -48% |
| hot-swap | full_voice | 27.50 | 13.95 | -49% |
| hot-swap | stereo_chain | 23.12 | 13.84 | -40% |
| topology | replace_node | 35.20 | 22.46 | -36% |
| topology | insert_delete_roundtrip | 79.72 | 42.20 | -47% |

## Notes

- All graph hot-path process timings remain far below the 128-sample
  real-time audio budget at 48 kHz: 2.67 ms per block. The slowest measured
  128-sample process benchmark is `fm_voice` at 7.20 us.
- The package split changed the benchmark command from the historical
  `-p lib` path to `-p graph`.
- `.jux` is now measured at four layers: pure pattern query, mini parser,
  scheduler event dispatch, and voice-pool stereo routing. `process_block` is
  included as a realistic timeline benchmark, but dispatch is measured
  separately because most audio blocks do not contain note onsets.
- Current numbers are faster than the 2026-04-09 snapshot across every
  comparable 128-sample graph benchmark. Treat exact deltas as point-in-time
  measurements; the useful signal is that there is no regression in the
  existing graph hot-path benchmark suite on the current post-architecture /
  `.jux` codebase.
