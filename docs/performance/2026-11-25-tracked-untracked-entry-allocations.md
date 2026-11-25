# Tracked and untracked entries: render-path allocation audit

Measured 2026-11-25 in the Linux x64 orb with Node v24.14.1 and Moon
0.1.20261117 (eb64713, moonc 0.10.21), release wasm-gc browser build.
Baseline `0cc23b4`; stage 1 `f2508ce`; stage 2 `d55e1e8` (ADR-0028).

## Method

[`scripts/audit-player-source-allocations.mjs`](../../scripts/audit-player-source-allocations.mjs)
prepares four inputs, plays each through the browser Player exports at 48 kHz /
128 frames, and drains the onset rows each block as the Worklet ring does.
Setup, the update, and 375 warm-up blocks are excluded; 3,000 blocks are counted
with onset observation off and on. Each case also runs uninstrumented: every
sample matched. Counts are executed `struct.new*` / `array.new*` instructions,
the method of the
[2026-11-24 audit](2026-11-19-signal-observation-allocations.md#method).

| Case | Input |
|---|---|
| tracked pattern | Draft preparation of `bpm(240); $: note("C2*8 E2 G2*3").s("bass")` and `$: s("bd*4 sd hh*8")` |
| tracked song | Draft preparation of a two-section `song(...)` of `note` and `s` parts |
| untracked pattern, song | the same two sources as `{ schema: 1, kind: "text", text }` |

```sh
NEW_MOON_MOD=0 moon build browser --target wasm-gc --release
NEW_MOON_MOD=0 moon build browser_authoring --target js --release
moon-wasm-opt _build/wasm-gc/release/build/browser/browser.wasm --all-features -S -o /tmp/folded.wat
python3 scripts/instrument-wasm-allocations.py /tmp/folded.wat /tmp/counted.wat
moon-wasm-opt /tmp/counted.wat --all-features -o /tmp/counted.wasm
node --experimental-wasm-custom-descriptors scripts/audit-player-source-allocations.mjs \
  /tmp/counted.wasm _build/wasm-gc/release/build/browser/browser.wasm \
  _build/js/release/build/browser_authoring/browser_authoring.js
```

`web/live/src/generated/authoring.js` was stale on this checkout (it did not know
`.s`), so the authoring build above stands in for it.

## Results

Constructions over 3,000 blocks; onset observation on and off gave the same
count in every case. Rows, onset fields and the PCM hash were identical across
all three builds for all eight runs.

| Case | Baseline | Stage 1 | Stage 2 |
|---|---:|---:|---:|
| tracked pattern | 984,152 | 984,152 | 984,152 |
| tracked song | 372,674 | 372,674 | 368,924 |
| untracked pattern | 984,152 | 984,152 | 984,152 |
| untracked song | 354,235 | 354,235 | 350,485 |

Stage 1 first measured two typed variants of the source facts before it settled
on holding the existing `EventWithOrigin`:

| Variant | Tracked pattern | Tracked song |
|---|---:|---:|
| `Option` fields in a `TrackedSource` struct | +12,304 (+1.25%) | +3,844 (+1.03%) |
| source-info enum with one variant per shape | +6,152 (+0.63%) | +1,922 (+0.52%) |

A reference-typed `Option` is a nullable pointer and costs nothing; an enum
payload or a struct is one construction per tracked event.

The song drop in stage 2 is unexplained. `alloc:$N` site numbers are function
indices that shift between builds, so per-site counts cannot be compared across
builds to name it.

Tracked and untracked patterns construct the same number of objects at the
baseline.

## Limits

Constructions only, not bytes. One run per build; the counts are deterministic.
The baseline render path is not allocation-free (pattern queries and event
dispatch construct objects every block), so this audit shows no growth, not
none.
