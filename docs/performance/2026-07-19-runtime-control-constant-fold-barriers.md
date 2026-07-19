# Performance Snapshot — 2026-07-19: Runtime-control constant-fold barriers

This change preserves authoring control nodes during constant folding so
runtime controls and bindings keep targeting the authored parameter kind.
Pure arithmetic dependencies still fold beneath those nodes.

## Structural cost

The optimizer now retains one additional runtime node in each affected
constant-fed chain:

| Authoring shape | Optimized shape |
|---|---|
| constant source → scaling control → output | unchanged (3 nodes) |
| constant source → limiting control → output | unchanged (3 nodes) |
| constant sources → pure arithmetic → scaling control → output | folded constant → scaling control → output (3 nodes) |

Before this correction, the first two shapes collapsed to a constant source
and output. The third shape still folds its pure arithmetic region, but the
retained control adds one node relative to folding the complete scalar chain.
Each affected render therefore keeps the control node's dispatch and buffer
pass. This bounded cost is the intentional tradeoff for preserving
runtime-control identity; recomputing folded dependency graphs when controls
change remains out of scope.

## Environment

- **CPU:** AMD Ryzen 7 6800H with Radeon Graphics
- **OS:** Linux 6.6.114.1-microsoft-standard-WSL2
- **MoonBit:** moon 0.1.20260713 (75c7e1f 2026-07-13)
- **Git base:** fcc167f4666da5a82379c616f75c3890551cc8c6 plus this working tree
- **Command:** `NEW_MOON_MOD=0 moon bench`
- **Result:** 59 benchmark groups passed

## Selected graph results

| Area | Case | Mean |
|---|---|---:|
| process | minimal_voice/128 | 2.59 µs |
| process | full_voice/128 | 6.55 µs |
| process | stereo_chain/128 | 11.62 µs |
| compile | minimal_voice | 2.06 µs |
| compile | full_voice | 9.32 µs |
| compile | stereo_chain | 14.71 µs |
| template analyze | small_10_nodes | 0.436 µs |
| template analyze | medium_34_nodes | 1.39 µs |
| template analyze | large_130_nodes | 5.12 µs |
| realistic template analyze | branch_fanout_11_nodes | 0.523 µs |
| realistic template analyze | mix_bus_17_nodes | 0.848 µs |
| realistic template analyze | terminal_stereo_15_nodes | 0.655 µs |
| realistic template analyze | feedback_loop_6_nodes | 0.210 µs |

## Isolated runtime A/B

The graph benchmark now carries a repeatable comparison at the production
128-sample block size. All three cases produce the same constant output, are
compiled before timing begins, and benchmark only `CompiledDsp::process`:

| Shape | Mean | Added time | Relative change | 2.67 ms block budget |
|---|---:|---:|---:|---:|
| Pre-fix folded equivalent: `Constant(5) -> Output` | 0.856 µs | — | — | 0.032% |
| Retained `Constant(10) -> Gain(0.5) -> Output` | 1.28 µs | 0.424 µs | +49.6% | 0.048% |
| Retained `Constant(10) -> Clip(5) -> Output` | 1.27 µs | 0.414 µs | +48.4% | 0.048% |

The percentage increase is large because the folded baseline is only the
runtime's two-node floor. In absolute terms, preserving a runtime control adds
about 0.41–0.42 µs per affected 128-sample render, or about 0.016% of
the AudioWorklet block budget. The benchmark lives in
`graph/graph_benchmark.mbt` as
`bench/process/runtime_control_fold_barrier_ab`.

## Verdict

The standard benchmark suite passes with the corrected optimizer. The isolated
A/B quantifies the runtime cost of the exact structural difference introduced
by retaining `Gain` or `Clip`; it does not attribute unrelated whole-engine
benchmark drift to this change. The cost is bounded to constant-fed
runtime-control barriers, and unaffected arithmetic subgraphs retain their
prior folding behavior.

A possible future design that preserves authoring control identity while
partially evaluating the execution plan is recorded in
[`../control-aware-partial-evaluation.md`](../control-aware-partial-evaluation.md).
It remains exploratory and is gated on representative scaling evidence.
