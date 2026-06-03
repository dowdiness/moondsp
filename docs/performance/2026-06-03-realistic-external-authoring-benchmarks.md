# Performance Snapshot — 2026-06-03: Realistic external-authoring graph shapes

Issue #127 extends the external-authoring benchmark suite from synthetic linear
mono chains to realistic authoring graph shapes. This is measurement-only work:
no optimization is proposed here.

## Performance-investigation gate

The claim was not that a specific operation was too slow; the gap was that
realistic external-authoring graph shapes were unmeasured. The benchmarks keep
PR #126's decomposition and isolate the same boundaries instead of bundling
parser/lowering, template preparation, runtime control, and audio processing
into one number.

Existing mitigations checked before adding benches:

- `CompiledTemplate::analyze` remains the single `Array[DspNode]` -> topology
  artifact boundary.
- `ControlBindingBuilder::build` validates stable-ID bindings once per prepared
  template.
- `ControlBindingMap::resolve_controls` prepares index-based `GraphControl`
  batches before runtime application.
- Parameter batches apply without topology recompilation.
- Hot-swap setup queues already compiled graphs; audio crossfade processing is
  measured by the existing process/hot-swap benchmarks, not here.

## Environment

- **CPU:** AMD Ryzen 7 6800H with Radeon Graphics
- **OS:** Linux 6.6.114.1-microsoft-standard-WSL2
- **MoonBit:** moon 0.1.20260522 (4a0c52f 2026-05-22)
- **Git base:** 37e6558873b745f80f5bec1ad40fe540feca9a1f plus working-tree
  benchmark/doc changes
- **Target:** wasm-gc release
- **Command:** `moon bench --release -p graph -f external_authoring_benchmark.mbt`
  — 32 benchmark groups passed. This file also contains the previously merged
  valid-path and diagnostic groups; the table below records only the realistic
  shape rows.

## Fixtures

| Fixture | Shape | Nodes | Bound controls |
|---|---|---:|---:|
| `branch_fanout_11_nodes` | mono fan-out branch bus | 11 | 6 |
| `mix_bus_17_nodes` | mono mix-heavy fan-in bus | 17 | 8 |
| `terminal_stereo_15_nodes` | terminal-stereo preview chain | 15 | 9 |
| `feedback_loop_6_nodes` | mono feedback-capable loop | 6 | 3 |

Prepared shape-change benchmarks use stable-ID rewires that keep existing IDs
and terminal output shape stable.

## Realistic external authoring/control results (µs)

| Operation | branch | mix bus | stereo | feedback |
|---|---:|---:|---:|---:|
| `CompiledTemplate::analyze` | 0.351 | 0.549 | 0.440 | 0.113 |
| control binding generation from stable IDs | 0.252 | 0.343 | 0.417 | 0.139 |
| control binding validation (`build`) | 0.639 | 0.767 | 0.995 | 0.385 |
| string-key control resolution | 0.425 | 0.553 | 0.588 | 0.254 |
| apply param batch to compiled graph | 0.471 | 0.849 | 0.927 | 0.364 |
| apply param batch through topology controller | 0.689 | 0.911 | 0.974 | 0.305 |
| shape rewire doc roundtrip | 0.349 | 0.531 | 0.474 | 0.379 |
| compile already analyzed shape change | 8.39 | 12.76 | 21.98 | 6.16 |
| queue prepared hot-swap setup | 0.221 | 0.230 | 0.388 | 0.220 |

## Budget notes

- These rows are authoring/control-side measurements, not audio sample
  processing. Compare most of them to a UI/control-thread frame budget such as
  **16.6 ms at 60 Hz**.
- The `apply param batch*` rows are pre-resolved block-boundary runtime-control
  costs. If applied synchronously on the audio side, compare them to the
  128-sample / 48 kHz block budget of about **2.667 ms**. They still do not run
  parser/projection/lowering/template analysis/compile or sample processing.
- No audio block process numbers are added in this snapshot. Existing
  `bench/process/*` snapshots remain the source for audio processing budgets.
- Parser/projection/lowering/template preparation remains off the audio
  callback. The realistic fixtures are direct graph snapshots with stable IDs,
  not production Mini parsing through Loom.

## Verdict

No bottleneck is demonstrated. The largest measured realistic authoring-side
operation is compiling an already analyzed terminal-stereo shape change at
**21.98 µs**, far below a 60 Hz UI frame budget. The block-boundary parameter
application rows remain below **1 µs** for these fixtures.
