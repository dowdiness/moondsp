# Signal observation: render-path allocation audit

Measured 2026-11-24 in the Linux x64 orb with Node v26.13.1 and Moon
0.1.20261117 (eb64713), release wasm-gc browser build (`99c46a7e…` SHA-256
prefix), this branch rebased onto `origin/main` 6851a04.

## Method

[`scripts/audit-player-signal-allocations.mjs`](../../scripts/audit-player-signal-allocations.mjs)
prepares Draft playback input with the JS authoring build, plays it through the
browser Player exports at 48 kHz / 128 frames, and drains the signal rows each
block as the Worklet ring does. Setup, the update, and 375 warm-up blocks are
excluded; 3,000 blocks are counted with signal observation off and on. Each
case also runs uninstrumented: every sample matched, and observation on and off
rendered identical PCM. Counts are executed `struct.new*` / `array.new*`
instructions, the method of the
[2026-10-25 audit](2026-10-23-browser-updates.md#2026-10-25-transitive-allocation-audit).

```sh
NEW_MOON_MOD=0 moon build browser --target wasm-gc --release
moon-wasm-opt _build/wasm-gc/release/build/browser/browser.wasm --all-features -S -o /tmp/folded.wat
python3 scripts/instrument-wasm-allocations.py /tmp/folded.wat /tmp/counted.wat
moon-wasm-opt /tmp/counted.wat --all-features -o /tmp/counted.wasm
node --experimental-wasm-custom-descriptors scripts/audit-player-signal-allocations.mjs \
  /tmp/counted.wasm _build/wasm-gc/release/build/browser/browser.wasm web/live/src/generated/authoring.js
```

## Results

| Draft | Rows | Constructions, off | Constructions, on | Added |
|---|---:|---:|---:|---:|
| Pattern: `saw` filter, `isaw` gain, `tri` pan | 9,000 | 774,702 | 774,702 | 0 |
| Song: `saw.range(4000, 200)` in the second section | 1,508 | 338,768 | 338,768 | 0 |
| Pattern: `pan(sine)` | 3,000 | 397,479 | 397,479 | 0 |
| Pattern: `pan(cosine)` | 3,000 | 397,415 | 397,415 | 0 |

The first run found observation-specific constructions, now removed: a closure
from `Option::bind` in the bus's `signal_source` per followed bus, and two
`Rational::from_int` values per followed note. Following a note reads the
readers its voice already holds (`BoundVoicePool::followed`) instead of
building them again, and asks the pool each block whether the voice still
follows them, so observation keeps no copy of voice lifetime. Mini's `sine` and `cosine` called core `@math.sin`/`cos`, which construct on
wasm-gc each call, so observation added 5,984 constructions for `pan(sine)`
(385,991 off, 391,975 on), and each voice's bus follow paid the same. They now
use `@trig.sine_of_turns`/`cosine_of_turns`, the oscillator's scalar kernel,
which matches core bit for bit over one turn: the `pan(sine)` PCM hash is
unchanged, and its baseline fell by 12,576.

The baseline itself is not allocation-free: the scheduler's event dispatch and
pattern queries construct about 100 to 260 objects per block in these drafts,
so the complete render path is not certified allocation-free.
