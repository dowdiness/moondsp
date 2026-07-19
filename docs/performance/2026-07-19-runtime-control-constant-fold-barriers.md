# Performance Snapshot — 2026-07-19: Runtime-control constant-fold barriers

This change preserves authoring `Gain` and `Clip` nodes during constant folding
so runtime controls and bindings keep targeting the authored parameter kind.
Pure arithmetic dependencies still fold beneath those nodes.

## Structural cost

The optimizer now retains one additional runtime node in each affected
constant-fed chain:

| Authoring graph | Optimized graph |
|---|---|
| `Constant -> Gain -> Output` | `Constant -> Gain -> Output` (3 nodes) |
| `Constant -> Clip -> Output` | `Constant -> Clip -> Output` (3 nodes) |
| `Constant, Constant -> Mul -> Gain -> Output` | `Constant(12) -> Gain -> Output` (3 nodes) |

Before this correction, the first two shapes collapsed to `Constant -> Output`.
The third shape still folds `Mul`, but the retained `Gain` adds one node
relative to folding the whole scalar chain. Each affected render therefore
keeps the control node's dispatch and buffer pass. This bounded cost is the
intentional tradeoff for preserving runtime-control identity; recomputing
folded dependency graphs when controls change remains out of scope.

## Environment

- **CPU:** AMD Ryzen 7 6800H with Radeon Graphics
- **OS:** Linux 6.6.114.1-microsoft-standard-WSL2
- **MoonBit:** moon 0.1.20260713 (75c7e1f 2026-07-13)
- **Git base:** fcc167f4666da5a82379c616f75c3890551cc8c6 plus this working tree
- **Command:** `NEW_MOON_MOD=0 moon bench`
- **Result:** 58 benchmark groups passed

## Selected graph results

| Area | Case | Mean |
|---|---|---:|
| process | minimal_voice/128 | 2.57 µs |
| process | full_voice/128 | 6.22 µs |
| process | stereo_chain/128 | 11.59 µs |
| compile | minimal_voice | 2.20 µs |
| compile | full_voice | 8.54 µs |
| compile | stereo_chain | 13.58 µs |
| template analyze | small_10_nodes | 0.448 µs |
| template analyze | medium_34_nodes | 1.43 µs |
| template analyze | large_130_nodes | 5.29 µs |
| realistic template analyze | branch_fanout_11_nodes | 0.546 µs |
| realistic template analyze | mix_bus_17_nodes | 0.846 µs |
| realistic template analyze | terminal_stereo_15_nodes | 0.867 µs |
| realistic template analyze | feedback_loop_6_nodes | 0.275 µs |

## Verdict

The standard benchmark suite passes with the corrected optimizer. These
measurements are a post-change snapshot, not an isolated before/after
microbenchmark, so they do not support a causal regression percentage. The
known cost is structural and limited to constant-fed runtime-control barriers;
unaffected arithmetic subgraphs retain their prior folding behavior.
