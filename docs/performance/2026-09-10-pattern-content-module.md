# Pattern content comparison — validation, 2026-09-10

Base: `95218f8`. Toolchain: moon 0.1.20260814 (a2de5b2).

Playback needs to distinguish a changed material from an unchanged one while
preserving its entry address and timing. The pattern module owns this comparison.
Callers supply musical operations, not strings that claim to identify their
implementation.

The current interface and ownership contract are documented in the
[scheduler guide](../../scheduler/README.mbt.md#content-comparison).
This record describes validation at the base revision above.

## Verification

Public-interface tests cover source values, grouped names, selections, known
operations, and opaque callbacks. A sequence copies its input array so later
caller mutation cannot invalidate its advertised content. Playback tests retain
the existing behavioral checks for changed notes, pending edits, and reverts.

The full JS, wasm-gc, and native suites each passed 1,110 tests. Release WASM and
TypeScript/Vite builds passed. Public, architecture, import, facade-parity, and
browser-ABI checks passed. Deleting unused compiler callback factories afterward
was checked separately with `moon check` and 151 passing mini tests; it does not
change reachable behavior. Browser integration passed 26 tests and Live UI passed
35 tests, both with one worker and no retries. The release WASM, browser asset,
and built Live asset had matching SHA-256 hashes.

## Measurements and limits

The [raw benchmark results](2026-09-10-pattern-content-module-benchmarks.txt)
contain 60 passing groups from `NEW_MOON_MOD=0 moon bench --release`, using a
temporary target directory. The full run overlapped compilation and had variable
results. It is a diagnostic snapshot, not evidence of a speed improvement.

A focused scheduler run passed four groups, overlapping the final Live tests.
It measured 51.56 µs for direct jux rendering, 102.23 µs for two prepared
materials, and 105.66 µs for acceptance plus rendering. The command was
`NEW_MOON_MOD=0 moon bench scheduler/jux_benchmark.mbt --release`, with the
same temporary target directory. Both runs are included in the raw results.

The scheduler benchmark uses an arbitrary `jux` callback. Grouping no longer
allows that callback to assert a known identity, so repeated acceptance exercises
conservative replacement. Its acceptance measurement is not directly comparable
to earlier runs that supplied explicit identities.

These checks do not establish worst-case AudioWorklet latency or allocation
freedom. Parsing, reconciliation, and pattern queries still allocate. Content
comparison is conservative structural comparison, not proof that two arbitrary
programs generate the same music.
