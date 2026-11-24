# Copying sample data into the wasm-gc engine

Measured 2026-11-24 for [ADR-0026](../decisions/0026-sample-playback.md), at
commit 3405321 plus the prototype export below. Linux x64 orb (2 vCPU Intel
Xeon @ 2.60 GHz, shared), Moon 0.1.20261117 (eb64713), release wasm-gc,
HeadlessChrome 159.0.8154.6 (Playwright `chromium_headless_shell-1255`). The
artifact SHA-256 was
`bae4b036dc524ed14a89df4eabb843a918d3932f22dbde3d7a46625a3e70d0ed`.

## What was measured

JS cannot write into a wasm-gc array, so a decoded waveform has to cross one
sample per export call. The prototype
[`browser_test/sample_copy_probe.mbt`](../../browser_test/sample_copy_probe.mbt)
owns one `FixedArray[Float]`, which is a wasm `array` of `f32` (checked in the
release WAT). `sample_copy_write(index, value)` is a bounds check and an
`array.set`. It does not allocate and does not normalize. It is not the
sample store.

[`scripts/bench-sample-copy/`](../../scripts/bench-sample-copy/) instantiates
the module inside an `AudioWorkletProcessor` (realtime `AudioContext`,
48 kHz) and copies a 480,000-sample `Float32Array`, which is 10 s of mono audio. Steps:

1. One cold pass straight after instantiation.
2. Three warm-up passes.
3. Nine rounds of 20 passes each.
4. The same copy in chunks, one chunk per `process()` call, followed by a checksum.

`AudioWorkletGlobalScope` has no `performance.now` in Chromium, so the harness
uses `Date.now()` (1 ms) and divides each round by its 20 passes. A spot
sample and the checksum matched the source every time.

```sh
NEW_MOON_MOD=0 moon build browser_test --target wasm-gc --release
node scripts/bench-sample-copy/run.cjs _build/wasm-gc/release/build/browser_test/browser_test.wasm 16384 rt
```

## Results

Nine full runs: six realtime and three offline, at chunk 4,096 or 16,384.

| Quantity | Result |
|---|---:|
| 480,000 samples, warm, median of the nine rounds per run | 2.6–3.3 ms |
| Per call, warm median | 5.4–6.9 ns (about 6 ns) |
| 480,000 samples, slowest warm round seen | 5.15 ms (10.7 ns/call) |
| 480,000 samples, cold first pass | 4–8 ms (8–17 ns/call) |
| 480,000 calls that write nothing (index −1) | 2.2–2.5 ms |
| JS loop over the same `Float32Array`, no call | 0.45–0.55 ms |
| Allocating a zeroed 480,000-sample `FixedArray[Float]` | 0.5–0.75 ms |

Nearly all of the cost is the JS→wasm call itself. The empty call costs about
85% as much as the write. This is about 4× cheaper than the earlier Node proxy
(about 25 ns per `push_playback_char`, which also grows an `Array`).

## Chunk size

One 128-frame block at 48 kHz is 2.67 ms. At the warm median rate that would
fit about 440,000 samples. At the cold rate it would fit about 160,000.
Rendering needs most of the block, so the copy should take only a small part of it.

**Chosen chunk: 16,384 samples per block.**

- At the warm median rate it takes 0.10 ms (4% of the block).
- At the slowest warm rate it takes 0.18 ms (7%).
- At the cold rate it takes 0.27 ms (10%).
- That leaves room for a device about 2.5× slower before the copy reaches 25% of a block.
- 480,000 samples load in 30 blocks, which is 80 ms of audio time.

The per-`process()` timings (1 ms clock) never read more than 1 ms at 4,096
or 8,192 samples. At 16,384 one realtime run read 2 ms once and seven runs
read at most 1 ms. That clock cannot resolve 0.1 ms, so it bounds the outliers
and does not confirm the per-chunk figures. The figures above are derived
from the per-call rate.

## Limits and consequences

- Only one desktop-class CPU in a shared orb was measured, with headless Chromium only:
  no Firefox, no Safari, no mobile device. The 2.5× margin is a guess about
  slower devices, not a measurement of them.
- The 1 ms clock in the worklet cannot show GC pauses or late blocks. This
  measures copy cost, not glitch-free loading.
- Allocating the waveform costs about as much as a quarter of the copy, and it
  allocates on the audio thread. The store should allocate its capacity
  once at start-up, so that registering a sample only copies into it (ADR-0026
  Decision 6).
- The prototype stores 32-bit floats. 480,000 samples take 1.92 MB, against
  3.84 MB for `Double`.
