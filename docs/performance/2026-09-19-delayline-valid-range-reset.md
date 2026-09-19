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
- Target: **wasm-gc** (release). The module declares no preferred target;
  bare `moon bench --release` defaults to **wasm** (WASI). Browser/AudioWorklet
  claims below use an explicit `--target wasm-gc`.
- Commands:
  - `NEW_MOON_MOD=0 moon bench --release --target wasm-gc`
  - `NEW_MOON_MOD=0 moon bench --release --target wasm-gc dsp/delay_benchmark.mbt`
  - `NEW_MOON_MOD=0 moon bench --release --target wasm-gc voice/delay_reset_benchmark.mbt`
- Result: 66 benchmark groups passed, zero failures
- Dry-run confirmation: builds under `_build/wasm-gc/release/bench/`
- Raw output: [2026-09-19-delayline-valid-range-reset-benchmarks.txt](2026-09-19-delayline-valid-range-reset-benchmarks.txt)

## Focused results (wasm-gc)

Product columns come from the full-suite raw output above
(`--target wasm-gc`). Physical-fill baseline columns use the same
`dsp/delay_benchmark.mbt` harness on a temporary copy with the old
`buffer.fill(0.0)` reset and no `has_wrapped` branch, also run with
`--target wasm-gc`.

| Case | Valid-range (product) | Physical-fill baseline |
|---|---:|---:|
| `DelayLine::reset`, capacity 8 | 1.26 ns | 3.65 ns |
| `DelayLine::reset`, capacity 4,800 | 4.60 ns | 326.40 ns |
| `DelayLine::reset`, capacity 480,000 | 5.00 ns | 42.82 µs |
| reset + 16 ticks, capacity 4,800 | 48.77 ns | 390.67 ns |
| reset + 16 ticks, capacity 480,000 | 56.99 ns | 42.84 µs |
| warmed steady 16 ticks, capacity 4,800 | 48.45 ns | 45.85 ns |
| warmed steady 16 ticks, capacity 480,000 | 50.39 ns | 72.80 ns |
| prepared params4 active steal, capacity 4,800 | 800.93 ns | — |
| prepared params4 active steal, capacity 48,000 | 775.94 ns | — |
| prepared params4 active steal, capacity 480,000 | 781.72 ns | — |

Measurement notes:

- `reset + 16 ticks` resets inside each measured batch, so every iteration stays
  on the post-reset valid-range branch instead of wrapping into steady state.
- `warmed steady 16 ticks` warms past one full wrap and times ticks with no
  reset in the batch, isolating the always-on read-guard cost.
- The physical-fill baseline is comparison-only evidence, not committed product
  code. Candidate and baseline for the delay tick rows were both measured with
  `--target wasm-gc`.
- On wasm-gc, steady-state tick throughput did not show an unacceptable
  per-sample overhead versus the matched physical baseline (≈48 ns vs ≈46 ns
  at capacity 4,800; ≈50 ns vs ≈73 ns at capacity 480,000).
- An earlier default-target suite (no `--target`, resolving to **wasm**/WASI)
  is not used for the browser tick-overhead claim.

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
