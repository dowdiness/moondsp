# Performance Snapshot — 2026-06-02: External authoring benchmarks

Issue #118 adds first measurements for external graph-authoring/control paths.
This is measurement-only work: no optimization is proposed here.

## Performance-investigation gate

The claim was not that one operation was already too slow; the gap was that
external-authoring costs were unmeasured. The benchmark suite therefore records
first evidence for isolated operations instead of bundling parser/lowering,
template preparation, runtime control, and audio processing into one number.

Existing mitigations checked before adding benches:

- `CompiledTemplate::analyze` is the single boundary from `Array[DspNode]` to a
  topology artifact.
- `ControlBindingBuilder::build` validates bindings once per prepared template.
- `ControlBindingMap::resolve_controls` turns string-keyed maps into prepared
  `GraphControl` batches.
- `apply_controls` applies parameter-only batches without topology edits.
- Hot-swap setup queues already compiled graphs; crossfade audio processing is
  measured separately by the existing hot-swap process benches.

## Environment

- **CPU:** AMD Ryzen 7 6800H with Radeon Graphics
- **OS:** Linux 6.6.114.1-microsoft-standard-WSL2
- **MoonBit:** moon 0.1.20260522 (4a0c52f 2026-05-22)
- **Git base:** 87142afea0050b22dbdd5eba80cab2cdf33c18ee plus working-tree
  benchmark/doc changes
- **Target:** wasm-gc release
- **Commands:**
  - External-authoring tables: `moon bench --release -p graph -f external_authoring_benchmark.mbt`
  - Full pass also completed: `moon bench --release` — 35 benchmark groups passed

## Fixtures

Generated mono graphs use:

```text
oscillator -> alternating gain / biquad / clip stages -> output
```

Each stage has a stable `GraphNodeId`, a string control key, and a `Value0`
binding. Sizes:

| Fixture | Nodes | Bound controls |
|---|---:|---:|
| `small_10_nodes` | 10 | 8 |
| `medium_34_nodes` | 34 | 32 |
| `large_130_nodes` | 130 | 128 |

## External authoring/control results (µs)

| Operation | small | medium | large |
|---|---:|---:|---:|
| `CompiledTemplate::analyze` | 0.278 | 0.882 | 3.04 |
| control binding generation from stable IDs | 0.303 | 1.37 | 5.74 |
| control binding validation (`build`) | 0.393 | 1.76 | 7.48 |
| string-key control resolution | 0.175 | 0.721 | 3.13 |
| apply param batch to compiled graph | 0.414 | 1.59 | 6.50 |
| apply param batch through topology controller | 0.589 | 2.26 | 8.75 |
| compile already analyzed template change | 4.09 | 13.62 | 55.74 |
| queue prepared hot-swap setup | 0.209 | 0.219 | 0.211 |

## Topology document roundtrips (µs)

These measure identity-bearing authoring document edits without audio
processing or recompilation.

| Roundtrip | small | medium | large |
|---|---:|---:|---:|
| replace node | 0.190 | 0.321 | 0.731 |
| add node then delete inserted node | 0.940 | 1.86 | 4.94 |
| remove node then reinsert equivalent node | 1.02 | 2.15 | 5.35 |
| reconnect edge then restore | 0.431 | 0.962 | 2.07 |

## Regression/budget notes

- The 128-sample / 48 kHz audio block budget is about **2.667 ms**. Compare
  `bench/process/*/128` and any synchronous block-boundary runtime-control
  application against that budget. In the full benchmark pass after this split,
  the slowest 128-sample process case was `stereo_chain/128` at **11.92 µs**.
- The external-authoring rows above are UI/control-thread work. Compare those
  to a frame budget such as **16.6 ms at 60 Hz**, not to the audio callback.
  The largest measured authoring-side operation here is compiling a 130-node
  already analyzed template at **55.74 µs**.
- String-key map resolution, binding generation/validation, topology document
  edits, template analysis, compile, and hot-swap setup must stay off the audio
  callback. They may allocate while preparing a candidate template or control
  batch.
- Audio processing must use prepared runtime state: precompiled graphs,
  validated bindings, and pre-resolved `GraphControl` batches published at a
  block boundary. Parser/projection/lowering/template preparation does not run
  in `process()`.

## Verdict

No bottleneck is demonstrated. The new measurements provide baselines for
future regressions and keep issue #118 scoped to measurement rather than
redesigning the external authoring contract.
