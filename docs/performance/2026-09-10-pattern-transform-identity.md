# Pattern transform identity — validation, 2026-09-10

Base: `0dadc68`. Toolchain: moon 0.1.20260814 (a2de5b2).

Public transformations previously retained a source's content identity after
changing its events. Playback could therefore skip a valid update. A parsed
note filtered to silence continued playing; a merged pitch control also left
the old pitch playing. The reproduction failed before the fix.

Known transformations now update content identity themselves. Unidentified
callbacks invalidate it, so they cannot hide an edit. The compiler and fixed
routing adapters identify their known callbacks explicitly. The compiler no
longer repairs arbitrary transformations through a separate post-processing API.
See the [scheduler guide](../../scheduler/README.mbt.md#pattern-edits).

## Evidence

| Check | Result |
| --- | --- |
| Full MoonBit suites: JS, wasm-gc, native | 1,108 passed per target |
| Browser/controller/audio comparison | 26 passed, no retries |
| Live UI | 35 passed, no retries |
| Public/architecture/import/parity/browser ABI checks | Passed |
| Release WASM and TypeScript/Vite builds | Passed |
| Full benchmark suite | 60 groups passed |
| Focused scheduler benchmarks | 4 groups passed |

The permanent playback regression tests filtering, known and unknown control
inputs, reverse, degradation, every, and jux against their resulting notes.
It uses an identified source directly so the scheduler tests do not depend on
the text parser. Compiler tests independently verify stable identities and
changed parameters. The browser-host test verifies that reverting a routed edit
cancels its pending replacement.

## Measurements and limits

[Raw results](2026-09-10-pattern-transform-identity-benchmarks.txt) include both
runs. The full run overlapped compilation and browser validation and had large
variance. A focused run after that work finished measured:

| Scheduler operation | Mean |
| --- | ---: |
| Direct jux render | 43.11 µs |
| Two prepared materials, render | 86.03 µs |
| Same score acceptance plus render | 89.92 µs |

Commands were `NEW_MOON_MOD=0 moon bench --release` and
`NEW_MOON_MOD=0 moon bench scheduler/jux_benchmark.mbt --release`, with a
temporary target directory. The installed toolchain differs from the earlier
entry-update measurement, so these numbers are not a controlled speed comparison.
They do not establish worst-case AudioWorklet latency or allocation freedom.
Parsing, reconciliation, and pattern queries still allocate.
