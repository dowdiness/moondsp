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
- Full-suite command:
  `NEW_MOON_MOD=0 moon bench --release --target wasm-gc`
- Focused comparison command:
  `OUTPUT=/tmp/result.txt scripts/bench-delayline-reset-ab.sh`
- Result: 66 benchmark groups passed, zero failures
- Dry-run confirmation: builds under `_build/wasm-gc/release/bench/`
- Full-suite raw output: [2026-09-19-delayline-valid-range-reset-benchmarks.txt](2026-09-19-delayline-valid-range-reset-benchmarks.txt)
- Candidate/baseline raw output: [2026-09-19-delayline-valid-range-reset-ab.txt](2026-09-19-delayline-valid-range-reset-ab.txt)
- Reproducible runner: [`scripts/bench-delayline-reset-ab.sh`](../../scripts/bench-delayline-reset-ab.sh)

## Focused results (wasm-gc)

Product columns come from the refreshed full-suite raw output above
(`--target wasm-gc`). Physical-fill baseline columns come from the pinned
comparison runner. Before running, the runner rejects uncommitted changes in
the relevant manifests and DSP sources. It archives `HEAD` once, extracts that
same archive for both sides, and replaces only `dsp/delay.mbt` in the baseline
copy with the exact source from commit
`c62774961895f2b2fd7b96adf448672df93527ad`. Both sides therefore use the same
benchmark harness and surrounding integration code.

| Case | Valid-range (product) | Physical-fill baseline |
|---|---:|---:|
| `DelayLine::reset`, capacity 8 | 1.12 ns | 3.94 ns |
| `DelayLine::reset`, capacity 4,800 | 4.79 ns | 319.66 ns |
| `DelayLine::reset`, capacity 480,000 | 4.70 ns | 43.64 µs |
| reset + 16 ticks, capacity 4,800 | 47.88 ns | 388.14 ns |
| reset + 16 ticks, capacity 480,000 | 55.28 ns | 45.19 µs |
| warmed steady 16 ticks, capacity 4,800 | 50.10 ns | 52.50 ns |
| warmed steady 16 ticks, capacity 480,000 | 50.82 ns | 65.12 ns |
| prepared params4 active steal, capacity 4,800 | 761.96 ns | — |
| prepared params4 active steal, capacity 48,000 | 759.25 ns | — |
| prepared params4 active steal, capacity 480,000 | 744.79 ns | — |

Measurement notes:

- The reset-only fixture primes the line once. Repeated reset-only batches are
  useful for checking capacity scaling, but `reset + 16 ticks` and prepared
  stealing are the primary active-use measurements.
- `reset + 16 ticks` resets inside each measured batch, so every iteration stays
  on the post-reset valid-range branch instead of wrapping into steady state.
- The steady-state fixture warms each line for `max_delay_samples() * 2` ticks
  before timing, so both capacities have completed at least one full ring wrap.
  The timed batch contains no reset and isolates the always-on `has_wrapped`
  read overhead.
- On wasm-gc, steady-state tick throughput did not show a capacity-dependent
  regression versus the matched physical baseline (≈50 ns vs ≈46 ns at
  capacity 4,800; ≈51 ns vs ≈67 ns at capacity 480,000). These are local
  microbenchmark results, not an AudioWorklet deadline guarantee.
- An earlier default-target suite (no `--target`, resolving to **wasm**/WASI)
  is not used for the browser tick-overhead claim.

## Verification

- `NEW_MOON_MOD=0 moon update`: passed
- `NEW_MOON_MOD=0 moon check --deny-warn`: passed
- `NEW_MOON_MOD=0 moon test --release --target wasm-gc dsp`: 161 passed
- The transition contract compares the valid-range implementation with a
  physical-clear reference across ticks, reset, wrap, delay-length changes,
  zero-delay passthrough, feedback, and negative input.

## Measurement limits

These numbers are an environment-specific snapshot. They do not prove AudioWorklet
deadline success, and they do not authorize applying the same valid-range model
to reverb comb/allpass buffers.
