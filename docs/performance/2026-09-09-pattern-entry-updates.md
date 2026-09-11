# Pattern entry updates — validation, 2026-09-09

Implementation base: `896ec77` (anchored transport).
The [scheduler guide](../../scheduler/README.mbt.md#pattern-edits) defines the
replacement rules, source identity limits, and receipt semantics.

## Correctness

The deterministic playback tests cover independent 3- and 4-cycle materials,
replacement without postponement, exact-boundary acceptance, period changes,
named reordering, deletion, cancellation by reverting, additions, variation
phase, and finite occurrences with no later entry. Compiler tests check names,
content signatures, silent material periods, and combined transformations.
Custom composite sources without signatures are conservatively replaced.
Both additions and content edits preserve the variation phase of the source grid.

The scheduler audio test places an entry at sample 128.5. An edit received at
sample 128 stays silent for that sample and becomes audible at sample 129,
inside the same block. Browser-host tests verify that invalid input preserves a
valid pending edit and that a tempo edit changes the physical time of a
reservation without choosing another musical entry.

Full MoonBit suites pass on JS, wasm-gc, and native: 1,105 tests per target.
The release WASM and TypeScript/Vite builds pass. The browser/controller/audio
comparison suite passes all 26 tests, and the Live UI suite passes all 35 tests,
with one worker per suite and no retries. Targeted controller (3 tests) and
Live update (9 tests) reruns also pass. The five
public, architecture, incremental-import, graph-facade, and browser ABI checks
pass. The demo and Live distribution WASM assets have matching SHA-256 hashes.

## Performance

[Raw measurements](2026-09-09-pattern-entry-updates-benchmarks.txt) contain the
full existing release benchmark suite (59 groups) and a focused scheduler run
(4 groups, including one new group with two measurements). Commands:

```sh
NEW_MOON_MOD=0 moon bench --release
NEW_MOON_MOD=0 moon bench scheduler/jux_benchmark.mbt --release
```

Temporary target directories isolated the builds. Some measurements overlapped
other validation work. These are local snapshots, not a controlled A/B study.

| Prepared playback, 48 kHz / 128 samples | Mean |
| --- | ---: |
| Two materials, render | 114.04 µs |
| Same score acceptance plus render | 126.76 µs |

The latter measures reconciliation of unchanged authored content, not parsing
or compilation and not every possible edit. Both run the production snapshot
render path with two stereo phrases. The existing direct jux render measured
51.72 µs in the full run, compared with 49.48 µs in the earlier transport
snapshot. Separate runs and background load prevent attributing that difference
to this change alone.

## Limits

This validates entry semantics and integration; it does not establish a
worst-case AudioWorklet deadline or an allocation-free callback. Parsing,
metadata construction, reconciliation, and event queries allocate. Large scores
and edit bursts need separate workload measurements. The scheduler still checks
future material placements during block queries.

The numeric model remains bounded by Int64; arbitrary nested rates are not an
arbitrary-precision guarantee. Named siblings are stable within a stack;
anonymous members and repeated uses of the same name depend on position.

This implementation adds entry-based replacement to the existing language.
Explicit physical-time syntax, independent clocks, transport-position UI,
and new effects remain separate work. It does not
claim listening approval for a complete composition or CLAP host readiness.
