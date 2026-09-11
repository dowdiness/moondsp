# Anchored transport — validation, 2026-09-09

Implementation base: `bc1d682`. Toolchain: moon 0.1.20260907 (7aabba5).
The behavior and API limits are documented in the
[scheduler guide](../../scheduler/README.mbt.md#transport) and
[ADR-0006](../decisions/0006-scheduler-performance-time-expiry.md).

## Evidence

| Check | Result |
| --- | --- |
| MoonBit full suites: JS, wasm-gc, native | 1,093 passed per target |
| Live UI and AudioWorklet | 35 passed, no retries or skips |
| Browser, controller, audio comparison | 26 passed, no retries |
| Existing benchmark suite | 59 groups passed |
| Release WASM and TypeScript/Vite builds | Passed |
| Public, architecture, incremental-import, graph-facade and browser ABI checks | Passed |

The transport tests verify exact position after repeated tempo edits, an
8-hour fractional-tempo query, conversion rejection, and note ownership across
a tempo change. A constant signal through an envelope checks the exact audible
sample range, including starts and releases within a block. Another case checks
an onset rounded across a block boundary with a tempo edit at that boundary.
The browser test edits a playing song's tempo without requiring Stop.

Two new rational-arithmetic tests failed against the original implementation.
They pass with factor cancellation and comparison without cross-products.

The first Live UI run served HTML instead of WASM because the validation setup
had omitted asset synchronization. After synchronization, the built WASM and
the file in the Live UI distribution had identical SHA-256 hashes. All 35 tests
then passed. The first browser run timed out waiting five seconds for
`#patternStatus` to show `Pattern updated`; the full rerun with one worker
passed all 26 tests. That timeout's cause is not established.

## Measurement limits

[Raw benchmark results](2026-09-09-anchored-transport-benchmarks.txt) were
captured with `NEW_MOON_MOD=0 moon bench --release`, using a temporary build
directory. Part of the run overlapped browser validation. These are a local
snapshot, not a controlled speed comparison or a real-time deadline guarantee.

This is a local correctness and integration result. It does not prove a
worst-case AudioWorklet deadline, an allocation-free callback, a complete
long-duration listening result, or CLAP host readiness. Pattern queries and
voice dispatch still allocate. The 8-hour test advances the clock directly;
it does not render eight hours of audio.

Rational arithmetic remains bounded by Int64. Cancellation avoids unnecessary
intermediate overflow; it does not validate every possible nested pattern
transformation or provide arbitrary-precision arithmetic.

Per-pattern entry edits, group defaults, seconds in the authoring language,
and independent clocks are separate stages. This change supplies their
position-continuous, sample-accurate transport foundation.
