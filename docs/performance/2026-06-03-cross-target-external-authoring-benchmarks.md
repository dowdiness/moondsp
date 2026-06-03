# Performance Snapshot — 2026-06-03: Cross-target external-authoring benchmarks

Issue #129 compares the external-authoring benchmark suite across supported
MoonBit targets. This is measurement-only work: no optimization is proposed
from target-to-target differences alone.

## Performance-investigation gate

There was no claim that a specific operation was too slow. The gap was that
existing external-authoring snapshots were wasm-gc-only:

- valid paths: `docs/performance/2026-06-02-external-authoring-benchmarks.md`;
- diagnostic/failure paths:
  `docs/performance/2026-06-03-external-authoring-diagnostic-benchmarks.md`;
- realistic graph shapes:
  `docs/performance/2026-06-03-realistic-external-authoring-benchmarks.md`.

The cross-target run therefore reuses the existing isolated benchmark groups
and records first target-qualified evidence. It does not redesign fixtures,
merge parser/projection/lowering into these numbers, or infer codegen/runtime
bugs from backend differences.

## Environment

- **CPU:** AMD Ryzen 7 6800H with Radeon Graphics
- **OS:** Linux 6.6.114.1-microsoft-standard-WSL2
- **MoonBit:** moon 0.1.20260522 (4a0c52f 2026-05-22)
- **Node.js for JS target:** v24.14.1
- **Git base:** bc55c435731f23f9249647e0dda4aee95eadecab
- **Commands:**
  - wasm-gc: `moon bench --release -p graph -f external_authoring_benchmark.mbt`
  - native: `moon bench --release --target native -p graph -f external_authoring_benchmark.mbt`
  - JS: `moon bench --release --target js -p graph -f external_authoring_benchmark.mbt`

All three target runs completed the same **32** benchmark groups with **0**
failures. Times below are mean microseconds from one completed target run.

## Target support and caveats

| Target | Status | Deployment relevance | Caveat |
|---|---|---|---|
| wasm-gc | supported | Current browser AudioWorklet-relevant baseline | Default `moon bench --release` target. |
| native | supported | Future native/plugin experiments such as CLAP | Native backend costs may include reference-counting/runtime effects that do not apply to wasm-gc. |
| JS | supported | Possible browser UI/control-thread deployment | Measured by MoonBit's JS benchmark runner on Node.js, not inside a browser UI thread. |

## Synthetic valid paths — large fixture (µs)

The table compares the largest generated mono-chain fixture
(`large_130_nodes`, 128 bound controls). Smaller fixtures remain documented in
the wasm-gc baseline snapshot.

| Operation | wasm-gc | native | JS |
|---|---:|---:|---:|
| `CompiledTemplate::analyze` | 3.750 | 4.090 | 8.630 |
| control binding generation from stable IDs | 6.600 | 8.780 | 7.570 |
| control binding validation (`build`) | 8.560 | 14.10 | 19.43 |
| string-key control resolution | 3.410 | 5.750 | 5.210 |
| apply param batch to compiled graph | 7.150 | 13.18 | 11.40 |
| apply param batch through topology controller | 9.950 | 17.56 | 14.27 |
| topology doc replace node | 0.793 | 1.780 | 0.639 |
| topology doc add node then delete | 5.470 | 7.540 | 8.540 |
| topology doc remove node then reinsert | 5.880 | 8.040 | 8.450 |
| topology doc reconnect edge | 2.250 | 2.890 | 1.420 |
| compile already analyzed template change | 63.35 | 48.82 | 129.57 |
| queue prepared hot-swap setup | 0.239 | 0.165 | 0.480 |

## Diagnostic/failure paths — large fixture (µs)

The table compares rejection/diagnostic work on the same `large_130_nodes`
fixture. These are prepared editor/control-thread rejection paths, not parser
or lowering diagnostics.

| Operation | wasm-gc | native | JS |
|---|---:|---:|---:|
| invalid binding node index | 9.610 | 13.68 | 19.05 |
| invalid slot for node | 9.420 | 13.64 | 18.96 |
| duplicate binding key | 8.600 | 13.88 | 19.43 |
| invalid param batch on compiled graph | 3.590 | 5.850 | 6.250 |
| invalid param batch through topology controller | 3.040 | 4.300 | 4.180 |
| topology document invalid rewire | 0.233 | 0.459 | 0.148 |
| queue invalid topology edit | 0.210 | 0.467 | 0.134 |
| queue invalid topology edit batch | 0.217 | 0.452 | 0.138 |
| queue topology edit rejected by recompile | 0.790 | 1.590 | 1.040 |
| queue topology edit while pending | 0.035 | 0.055 | 0.036 |
| `compile_result` missing output | 0.575 | 0.826 | 0.712 |
| `compile_result` multiple outputs | 1.120 | 1.760 | 2.490 |
| `compile_result` invalid input | 1.100 | 1.910 | 2.330 |
| `compile_result` invalid parameter value | 1.520 | 2.360 | 4.070 |

## Realistic graph shapes — per-target maxima (µs)

Each cell is the maximum row for that target across the four realistic fixtures:
branch fan-out, mix bus, terminal stereo, and feedback loop.

| Operation | wasm-gc max | native max | JS max |
|---|---:|---:|---:|
| `CompiledTemplate::analyze` | 0.601 (mix bus) | 0.703 (mix bus) | 1.370 (mix bus) |
| control binding generation from stable IDs | 0.431 (stereo) | 0.605 (stereo) | 0.483 (stereo) |
| control binding validation (`build`) | 1.210 (stereo) | 1.080 (stereo) | 1.220 (stereo) |
| string-key control resolution | 0.626 (stereo) | 0.543 (stereo) | 0.429 (stereo) |
| apply param batch to compiled graph | 0.628 (stereo) | 1.020 (stereo) | 1.140 (stereo) |
| apply param batch through topology controller | 0.848 (stereo) | 1.420 (stereo) | 1.720 (stereo) |
| shape rewire doc roundtrip | 0.527 (mix bus) | 0.636 (mix bus) | 0.410 (mix bus) |
| compile already analyzed shape change | 25.13 (stereo) | 12.26 (stereo) | 61.44 (stereo) |
| queue prepared hot-swap setup | 0.446 (stereo) | 0.236 (stereo) | 0.892 (stereo) |

## Budget notes

- The 128-sample / 48 kHz audio block budget is about **2.667 ms**. Only
  pre-resolved runtime-control application rows are plausible block-boundary
  work: `apply param batch to compiled graph`, `apply param batch through
  topology controller`, and their invalid prepared-batch counterparts. The
  largest cross-target value in those rows is **17.56 µs** on native for the
  synthetic large topology-controller path.
- Authoring/control-thread work should be compared to UI budgets such as
  **16.6 ms at 60 Hz**. The largest measured authoring-side operation here is
  JS `compile already analyzed template change` on the 130-node synthetic
  fixture at **129.57 µs**.
- Template analysis, binding generation/validation, string-key resolution,
  topology document edits, compile/diagnostic template work, and hot-swap setup
  must stay off the audio callback. They may allocate while preparing candidate
  templates or control batches.
- This snapshot adds no sample-processing benchmark rows. Existing
  `bench/process/*` snapshots remain the source for audio processing budgets,
  and hot-swap crossfade processing is separate from the queue/setup rows here.
- Audio processing still consumes prepared runtime state: precompiled graphs,
  validated bindings, and pre-resolved `GraphControl` batches published at a
  block boundary. Parser/projection/lowering/template preparation does not run
  in `process()`.

## Verdict

No bottleneck is demonstrated. wasm-gc remains the browser AudioWorklet-relevant
baseline, native is supported for future native/plugin investigation, and JS is
practical through MoonBit's benchmark target with Node-specific caveats. All
measured block-boundary runtime-control rows remain far below the 2.667 ms audio
block budget, and all authoring/control-thread rows remain far below a 60 Hz UI
frame budget.
