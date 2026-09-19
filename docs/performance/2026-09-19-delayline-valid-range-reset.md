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
- Result: 65 benchmark groups passed, zero failures
- Raw output: [2026-09-19-delayline-valid-range-reset-benchmarks.txt](2026-09-19-delayline-valid-range-reset-benchmarks.txt)

## Focused results

| Case | Mean |
|---|---:|
| `DelayLine::reset`, capacity 8 | 7.43 ns |
| `DelayLine::reset`, capacity 4,800 | 7.27 ns |
| `DelayLine::reset`, capacity 480,000 | 7.10 ns |
| 16 ticks after reset, capacity 4,800 | 120.25 ns |
| 16 ticks after reset, capacity 480,000 | 118.41 ns |
| prepared params4 active steal, capacity 4,800 | 1.49 µs |
| prepared params4 active steal, capacity 48,000 | 1.45 µs |
| prepared params4 active steal, capacity 480,000 | 1.44 µs |

Prior physical-fill measurements on the same machine (experiment only, not
committed product code) showed `reset` at ~393 ns / ~47 µs for capacities
4,800 / 480,000, and prepared steal rising to ~47 µs at capacity 480,000.
After this change both families stay flat across capacity.

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
