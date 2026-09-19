# Performance snapshot — 2026-09-19: DelayLine valid-range reset

`DelayLine::reset` no longer zero-fills its circular buffer. Reset is a
constant-time valid-range clear: unwritten samples after construction or reset
read as silence, while configured delay and feedback stay unchanged. Voice
prepared-slot steals call the same `reset()` through
`CompiledDsp::reset_runtime_state`, so long delay capacities no longer create a
capacity-proportional spike on steal. `StereoReverb` keeps physical zero-fill;
that DSP is out of scope.

## Environment and command

- CPU: AMD Ryzen 7 6800H with Radeon Graphics
- OS: Linux WSL2
- MoonBit: moon 0.1.20260904 (94521db), moonc v0.10.12+1634b282e (2026-09-07)
- Base: `c627749` on `feat/delayline-logical-reset`
- Target: wasm-gc (release)
- Command: `NEW_MOON_MOD=0 moon bench --release`
- Result: 66 benchmark groups passed, zero failures
- Focused delay command: `NEW_MOON_MOD=0 moon bench --release dsp/delay_benchmark.mbt`
- Raw output: [2026-09-19-delayline-valid-range-reset-benchmarks.txt](2026-09-19-delayline-valid-range-reset-benchmarks.txt)

## Focused results

Product columns come from the full-suite raw output above. Physical-fill baseline
columns come from the same `dsp/delay_benchmark.mbt` harness on a temporary copy
with the old `buffer.fill(0.0)` reset and no `has_wrapped` branch.

| Case | Valid-range (product) | Physical-fill baseline |
|---|---:|---:|
| `DelayLine::reset`, capacity 8 | 7.06 ns | 9.22 ns |
| `DelayLine::reset`, capacity 4,800 | 6.83 ns | 346.57 ns |
| `DelayLine::reset`, capacity 480,000 | 7.11 ns | 42.12 µs |
| reset + 16 ticks, capacity 4,800 | 105.32 ns | 461.04 ns |
| reset + 16 ticks, capacity 480,000 | 105.45 ns | 43.41 µs |
| warmed steady 16 ticks, capacity 4,800 | 119.40 ns | 130.72 ns |
| warmed steady 16 ticks, capacity 480,000 | 118.41 ns | 129.57 ns |
| prepared params4 active steal, capacity 4,800 | 1.34 µs | — |
| prepared params4 active steal, capacity 48,000 | 1.33 µs | — |
| prepared params4 active steal, capacity 480,000 | 1.33 µs | — |

Measurement notes:

- `reset + 16 ticks` resets inside each measured batch, so every iteration stays
  on the post-reset valid-range branch instead of wrapping into steady state.
- `warmed steady 16 ticks` warms past one full wrap and times ticks with no
  reset in the batch, isolating the always-on read-guard cost.
- The physical-fill baseline is comparison-only evidence, not committed product
  code.
- Steady-state tick throughput did not regress versus that physical baseline
  (≈118–119 ns vs ≈130–131 ns for 16 ticks). The valid-range branch therefore
  does not impose an unacceptable per-sample overhead on this host.

Prior physical-fill steal measurements on the same machine (experiment only)
showed prepared steal rising to ~47 µs at capacity 480,000. After this change
steal stays flat near 1.33–1.34 µs across capacities.

## Verification

- `NEW_MOON_MOD=0 moon check --deny-warn`: passed
- `NEW_MOON_MOD=0 moon test --release dsp`: 160 passed
- `NEW_MOON_MOD=0 moon test --release voice`: 73 passed
- `NEW_MOON_MOD=0 moon test --release graph`: 244 passed
- Contract tests cover post-reset silence, wrap-around stale content, feedback
  isolation, and delay-length changes after reset

## Measurement limits

These numbers are an environment-specific snapshot. They do not prove AudioWorklet
deadline success, and they do not authorize applying the same valid-range model
to reverb comb/allpass buffers.
