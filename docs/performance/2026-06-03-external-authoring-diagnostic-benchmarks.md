# Performance Snapshot — 2026-06-03: External authoring diagnostic benchmarks

Issue #128 adds first measurements for external-authoring failure and
diagnostic paths. This is measurement-only work: no diagnostic contracts were
changed and no optimization is proposed here.

## Performance-investigation gate

There was no claim that a specific failure path was too slow. The gap was that
editor/control-thread rejection costs were unmeasured after the valid-path
external-authoring baseline in
`docs/performance/2026-06-02-external-authoring-benchmarks.md`.

The benchmark fixtures therefore isolate diagnostic categories rather than
profiling a parser/projection/lowering pipeline:

- invalid control-binding validation: bad node index, bad slot for node, and
  duplicate key;
- runtime control batches that reject an invalid parameter value;
- identity/topology edit rejections and topology-controller queue rejections;
- `compile_result` diagnostics for missing output, multiple outputs, invalid
  input, and invalid parameter value.

Prepared templates, invalid edit values, and invalid control batches are built
outside the timed closures. The measured operations are the rejection paths
that an editor/control thread would run against already prepared graph state.

## Environment

- **CPU:** AMD Ryzen 7 6800H with Radeon Graphics
- **OS:** Linux 6.6.114.1-microsoft-standard-WSL2
- **MoonBit:** moon 0.1.20260522 (4a0c52f 2026-05-22)
- **Git base:** f361bc39a9225aa2b5be01508806ed59ae00ccca plus working-tree
  benchmark/doc changes
- **Target:** wasm-gc release
- **Commands:**
  - Diagnostic tables: `moon bench --release -p graph -f external_authoring_benchmark.mbt`
    — 23 benchmark groups passed
  - Full benchmark pass: `moon bench --release` — 49 benchmark groups passed

## Fixtures

Generated mono graphs match the valid-path baseline:

```text
oscillator -> alternating gain / biquad / clip stages -> output
```

| Fixture | Nodes | Bound controls |
|---|---:|---:|
| `small_10_nodes` | 10 | 8 |
| `medium_34_nodes` | 34 | 32 |
| `large_130_nodes` | 130 | 128 |

## Valid-path baseline separation

The valid-path baseline remains the 2026-06-02 snapshot. This document records
only failure/diagnostic costs. Do not compare these rows to parser/lowering or
template-preparation failures, and do not treat them as audio-callback work
unless the candidate has already been reduced to a block-boundary runtime
control application.

## Control binding diagnostics (µs)

Each invalid binding is appended after all valid bindings so the benchmark
measures the full validation scan before rejection.

| Diagnostic | small | medium | large |
|---|---:|---:|---:|
| invalid binding node index | 0.389 | 1.80 | 7.66 |
| invalid slot for node | 0.378 | 1.73 | 7.57 |
| duplicate binding key | 0.420 | 1.83 | 8.08 |

## Runtime-control diagnostics (µs)

Each batch contains the fixture's valid parameter controls plus one invalid
Clip threshold at the end. Rejection is transactional; the existing compiled or
controller state remains usable after the failed batch.

| Diagnostic | small | medium | large |
|---|---:|---:|---:|
| invalid param batch on compiled graph | 0.265 | 0.956 | 3.21 |
| invalid param batch through topology controller | 0.233 | 0.752 | 2.83 |

## Topology/document/controller diagnostics (µs)

These are identity/topology authoring costs, not audio processing. The raw
`CompiledDspHotSwap` queue path on this base does not reject an already pending
swap; the topology controller does reject queued topology work while its
underlying hot-swap has a pending replacement, so that controller path is
measured here.

| Diagnostic | small | medium | large |
|---|---:|---:|---:|
| topology document invalid rewire | 0.085 | 0.127 | 0.228 |
| queue invalid topology edit | 0.067 | 0.105 | 0.210 |
| queue invalid topology edit batch | 0.065 | 0.123 | 0.219 |
| queue topology edit rejected by recompile | 0.131 | 0.266 | 0.781 |
| queue topology edit while pending | 0.036 | 0.036 | 0.037 |

## `compile_result` diagnostics on prepared templates (µs)

Invalid templates are analyzed before timing; the closure measures only
`CompiledDsp::compile_result` producing the typed diagnostic.

| Diagnostic | small | medium | large |
|---|---:|---:|---:|
| missing output | 0.071 | 0.167 | 0.591 |
| multiple outputs | 0.119 | 0.314 | 1.06 |
| invalid input | 0.121 | 0.290 | 0.974 |
| invalid parameter value | 0.174 | 0.444 | 1.40 |

## Safety and budget notes

- These failure paths are UI/control-thread work. They should be compared to an
  editor frame budget such as **16.6 ms at 60 Hz**, not to the 128-sample audio
  callback budget.
- Rejected authoring/control work must stay off the audio callback and existing
  prepared runtime state must remain usable.
- Parser, projection, lowering, string-to-template preparation, and diagnostic
  template construction do not run in `process()`.
- Audio processing should only consume prepared runtime state: precompiled
  graphs, validated bindings, and pre-resolved `GraphControl` batches published
  at a block boundary.

## Verdict

No bottleneck is demonstrated. The largest measured diagnostic path in this
snapshot is duplicate-key control-binding validation on the 130-node fixture at
about **8.08 µs**, still far below a 60 Hz editor-frame budget. The results
provide a baseline for future regressions without changing external-authoring
contracts.
