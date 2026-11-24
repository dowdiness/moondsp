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

## Stage 3: making the store, and rendering without allocation

Measured 2026-11-24 with the stage 3 store and `SamplePlayer` (ADR-0026 Order
of work, step 3). Same orb, Moon and Chromium as above; release wasm-gc
artifact SHA-256
`7218174bb03affb5f27bbbd477bfe8707a2529903eb03a44f7b1c1e0cbc1a482`.

### Making the browser default store

`sample_store_create(64, 1440000, 8388608)` in
[`browser_test/sample_copy_probe.mbt`](../../browser_test/sample_copy_probe.mbt)
makes the Decision 6 browser default: 64 entries, 1,440,000 samples per
waveform and 8,388,608 samples (32 MiB of `Float`). The same AudioWorklet
harness times it, before the copy measurements:

1. One cold make, the first thing the module does after instantiation.
2. Nine warm makes. Each one first replaces the store with an empty one, so the
   32 MiB it replaces becomes garbage.

Five realtime runs, `Date.now()` (1 ms):

| Make | Result |
|---|---:|
| Cold, first make | 15–20 ms (20, 20, 15, 20, 18) |
| Warm, median of nine per run | 12–14 ms |
| Warm, range over all 45 | 10–21 ms |

The ADR's estimate of 9–13 ms was extrapolated from the 480,000-float figure.
The measurement is higher: 15–20 ms for the make that a host actually does, once,
at start-up. That is 6–8 render quanta of 2.67 ms. A store made while an
`AudioContext` is running would make those blocks late. Stage 4 must make it
before the first `process()` call, for example in the processor's
constructor before the node is connected, or while the context is suspended.

```sh
NEW_MOON_MOD=0 moon build browser_test --target wasm-gc --release
node scripts/bench-sample-copy/run.cjs _build/wasm-gc/release/build/browser_test/browser_test.wasm 16384 rt
```

The copy figures in the same five runs matched the earlier ones: 2.65–3.0 ms
warm median for 480,000 samples, and 5–6 ms for the cold copy.

### No construction while a sample player renders

[`scripts/bench-sample-copy/audit-player.cjs`](../../scripts/bench-sample-copy/audit-player.cjs)
uses the instrumenter from the
[browser update audit](2026-10-23-browser-updates.md). Each `struct.new*` and
`array.new*` site gets a counter. The audit builds a one-second 440 Hz sine
store and a `sample_player → output` graph, then zeroes the counters. It then
renders 1,000 blocks of 128 frames in four cases:

- root pitch at speed 1, which reaches the end of the waveform after 375 blocks;
- pitch 62 at speed 1.5, which interpolates;
- speed −1;
- a `reset_runtime_state` every 50 blocks, which binds the waveform again;
- stage 5: a `begin`/`end` slice, forwards and backwards, with the same
  resets, so each bind computes the slice. Rerun after stage 5 added
  `begin` and `end`.

| Case | Constructions while rendering | Energy, counted = reference |
|---|---:|---:|
| Root pitch, speed 1 | 0 | 24,000.0 |
| Pitch 62, speed 1.5 | 0 | 23,959.7 |
| Speed −1 | 0 | 24,000.0 |
| Reset every 50 blocks | 0 | 63,917.4 |
| Slice 0.25–0.75, reset every 50 blocks (stage 5) | 0 | 63,917.4 |
| Slice 0.25–0.75 backwards, reset every 50 blocks (stage 5) | 0 | 63,932.4 |

Building the store and graph is the positive control: its counters are
nonzero. The instrumented output matched the uninstrumented build exactly.

```sh
W=_build/wasm-gc/release/build/browser_test/browser_test.wasm
moon-wasm-opt $W --all-features -S -o /tmp/folded.wat
python3 scripts/instrument-wasm-allocations.py /tmp/folded.wat /tmp/counted.wat
moon-wasm-opt /tmp/counted.wat --all-features -o /tmp/counted.wasm
node --experimental-wasm-custom-descriptors scripts/bench-sample-copy/audit-player.cjs /tmp/counted.wasm $W
```

This counts constructions in the compiled graph's render path only. It does
not cover the voice pool, the scheduler or MessagePort traffic, which
stage 4 routes samples through, and it does not measure GC pauses.

## Stage 4: loading while a realtime context plays

Measured 2026-11-24 with the stage 4 loader (ADR-0026 Order of work, step 4,
the parts that do not depend on the vocabulary). Same orb and toolchain.

[`scripts/bench-sample-copy/loading-check.cjs`](../../scripts/bench-sample-copy/loading-check.cjs)
runs the production `scheduler-processor.js` and `sample-loader.js` from
`web/live/public` in a realtime `AudioContext` at 48 kHz. A subclass records
every rendered block by engine sample position. The score is
`stack(note("60 64 67 71 72 71 67 64"), s("bd sd hh sd"), s("hh*8"))`, and each
run renders 3,000 blocks (8 s).

- **Control run:** no sample loads.
- **Loading run:** two seconds in, a 480,000-sample (10 s) waveform is posted
  for `ping`. One second later, a 1,440,001-sample waveform, one sample over
  the length limit, is posted for `burst`.

The scheduler is deterministic, so a load that disturbed rendering would show
as a difference from the control.

| Browser | Blocks compared / differing | Blocks that copied | Longest `process()` while copying (1 ms clock) |
|---|---:|---:|---:|
| Chromium 159 (headless shell), 4 runs | 3,000 / 0 | 30 (31 with the over-limit run) | 1 ms |
| Firefox 159 (Playwright), 3 runs | 3,000 / 0 | 30 | 1–2 ms |
| Playwright WebKit 27.2 (Linux, not Safari), 2 runs | 3,000 / 0 | 30 | 3 ms |

- **Output:** every block of every loading run matched the control exactly
  (largest difference 0). The crackle-probe metrics over the copying blocks
  (largest step 0.0035, largest boundary step 0.0031 in Chromium) equal the
  control's over the same blocks.
- **Status channel:** it reported `loading: ["ping"]` when the load arrived and
  `loading: []` 77–80 ms later. The oversized `burst` reported
  `overLimit: [{ name: "burst", limit: "length" }]` in the same block.
- **Chromium trace:** in the loading run, `AudioWorkletProcessor::Process`
  callbacks had p50 0.073 ms and p99 0.20 ms. Only two callbacks exceeded the
  2.67 ms quantum, and neither is the load:
  - the first render, which builds the voice pools (7.5–8.3 ms);
  - the harness's own final report, which posts the recorded output (2.7–3.7 ms).

  No callback over the quantum fell in the loading window.

```sh
npm --prefix web/live run sync:assets
NODE_PATH=web/live/node_modules node scripts/bench-sample-copy/loading-check.cjs chromium 8
```

Limits:

- **Underruns:** none of the three browsers exposes an underrun or glitch
  count here. `AudioContext.playoutStats` is absent in Chromium 158 and 159,
  even with `--enable-blink-features=AudioContextPlayoutStats`. Late
  callbacks come from the Chromium trace only.
- **Firefox:** the 1 ms clock cannot show a callback just over 2.67 ms.
- **WebKit:** this is Linux WebKit, not Safari on macOS. Its 3 ms reading may
  be one late block or clock granularity. Safari still needs its own check
  on a Mac before the browser path is called done.
- **Device:** the runs used a headless device in a shared orb.

## Stage 4: scores play bank samples

Measured 2026-11-24 after `Sound::Play` and routing landed. Same orb and
toolchain.

[`scripts/bench-sample-copy/play-check.cjs`](../../scripts/bench-sample-copy/play-check.cjs)
runs the production `scheduler-processor.js` in a realtime `AudioContext` at
48 kHz. It sends the bank as the editor does (`web/sample-bank.js`) and waits
until the status channel reports nothing loading. Then it plays each score and
sums the squared output of the left channel over 1.5 s (562 blocks). Each
score is slowed by 4 so one onset falls in the window.

| Score | Energy | Ratio to `s("ping")` |
|---|---:|---:|
| `silence()` | 0 | 0 |
| `s("ping")` | 32.84 | 1 |
| `note("69").s("ping")` (root pitch) | 32.84 | 1.000 |
| `note("57").s("ping")` (an octave down) | 65.67 | 2.000 |
| `s("ping").gain(0.25)` | 2.052 | 0.0625 |
| `s("ping").lpf(200)` | 1.294 | 0.039 |
| `note("69").s("ping").lpf(200)` | 1.294 | 0.039 |
| `s("burst")` | 2.964 | — |
| `s("bd")` | 43.51 | — |

- `s("ping")` and `.s("ping")` at the root pitch produce the same output.
- An octave down plays the waveform at half speed, so it lasts twice as long
  and carries twice the energy.
- `.gain(0.25)` scales energy by 0.25² = 0.0625, as amplitude gain should.
- `.lpf(200)` removes most of the 440 Hz ping through both `s` and `.s`.
- The status channel reported `loading: ["ping"]`, then `["ping", "burst"]`,
  then `["burst"]`, then `[]`.

```sh
npm --prefix web/live run sync:assets
NODE_PATH=web/live/node_modules node scripts/bench-sample-copy/play-check.cjs chromium
```

Chromium only. Firefox and Safari remain required before the browser path is
called done.

## Stage 5: begin, end and speed in a realtime context

Measured 2026-11-24 after `begin`, `end` and `speed` landed, with the same
[`play-check.cjs`](../../scripts/bench-sample-copy/play-check.cjs) run in
Chromium 159. Energies over 1.5 s; `s("ping")` alone is 32.84.

| Score | Energy | Ratio |
|---|---:|---:|
| `s("ping").end(0.25)` | 31.19 | 0.950 |
| `s("ping").begin(0.5)` | 0.081 | 0.002 |
| `s("ping").speed(-1)` | 32.96 | 1.004 |
| `s("ping").speed(2)` | 16.37 | 0.498 |
| `s("ping").begin(0.5).end(0.25)` | 0 | 0 |

`ping` decays, so its first quarter holds 95% of its energy and its second
half 0.2%. Backwards it holds the same total energy, so the harness also sums
the first 0.1 s (37 blocks): backwards that is 0.00001× of forwards (17.85),
because the reversed ping starts from its decayed tail. Twice as fast, the
whole decay plays in half the time. A slice whose `begin` is not before its
`end` is silent.

Total energy alone could not tell whether `speed` reached the sampler voice.
With the `Speed` binding removed from the browser pool, the backwards and
double-speed checks now fail, and they pass with it.

The render-path allocation audit was rerun with two slice cases; see
[No construction while a sample player renders](#no-construction-while-a-sample-player-renders).

### Firefox, and a harness correction

`play-check.cjs` was then run in Firefox 159 (Playwright). Every score, in
stages 4 and 5, gave the same energy as in Chromium to the last digit.

Two harness races turned up first, and both are fixed:

- **Measuring window.** A `player-restart` starts playing at cycle 0 in the
  block that handles it. The harness opened its measuring window only after
  the restart's receipt came back. In Chromium the receipt returned within
  the same block, so the earlier figures stand. In Firefox it took about 7
  blocks (cycle 0.0093 at Play), so the start of each note fell before the
  window and `s("ping")` read 24–28 instead of 32.84. The window now opens
  before the restart, in message order on the audio thread. The one figure
  this changed is `begin(0.5)`, from 0.075 to 0.081.
- **`ready` before `resume()`.** The harness registered its wait for
  `ready` after `await ctx.resume()`. In Firefox the worklet sometimes sent
  `ready` first, and the run timed out (2 of 7 runs). It now waits before
  resuming. The editor already does this (`waitForReady` in
  `web/live/src/audio.ts`), and so does `loading-check.cjs`.

Safari still needs its own run on a Mac.
