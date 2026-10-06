# Pattern-query allocation and onset investigations

Measurements: 2026-09-25–2026-10-02. The retained pattern optimizations shipped in `5a8e495e5ba3524ebe856643fd0526eff3440430`. The onset-observation integration remained an isolated experiment, not a shipped API.

## Initial batch

Baseline: `e07ad86ff99c0d6e315e330c7129e4203ca4211a`. Retained changes:

- Share immutable `PatternNodePath` tails and prepare invariant leaf paths during lowering. `nodes()` still returns an independently mutable array; ordered paths and duplicates remain exact.
- Reuse immutable operands for rational add/subtract-zero and multiply/divide-by-positive-one, preserving the divide-by-zero guard and general exact arithmetic.
- Reuse zero-offset event/span shifts and nonempty contained intersections. Empty/touching spans still do not intersect.

The dense workload executed 32.97% fewer Wasm GC construction instructions. A separate 600-arc release query benchmark improved from 41.30 to 24.88 ms dense and 3.96 to 2.85 ms sparse; these are query-batch timings, not callback durations.

## Follow-up loop

Baseline: the completed initial batch, not the original `e07ad86` implementation. Retained changes:

- Precompute sequence indices and exact rational slot bounds at construction.
- Reuse the invariant complete-slot `[0,1)` child-query span while independently clipping requested event parts.
- Advance `whole_cycles` to its already computed cycle end.

Generic rational-constructor zero/one sharing was rejected. It lowered constructor counts but slowed general-fraction controls: 9.49→12.68 µs in the initial comparison and 11.29→13.05 µs in a later pair. The generic constructor changes were removed; the narrower arithmetic identity reuse above remains.

### Render comparison

48 kHz, 128 frames/block, 600 blocks per scenario; counters instrument optimized release Wasm GC construction instructions. Initialization/admission is excluded except scheduled live control actions in the control scenarios. Diagnostic state getters execute only in the uncounted pass.

| Scenario | Original baseline | Initial batch | Final |
|---|---:|---:|---:|
| Dense tracked | 5,399,504 | 3,619,295 | 3,252,467 |
| Sparse tracked | 575,885 | 432,431 | 367,331 |
| Dense text, no source map | 5,399,504 | 3,619,295 | 3,252,467 |
| Fractional timing + update/control | 755,131 | 570,911 | 508,297 |
| Rest/degrade/zero gain | 1,644,011 | 1,169,329 | 965,415 |

The final dense count is 10.14% lower than the initial batch. Two reversed-order actual AudioWorklet comparisons, using uninstrumented binaries in Chrome 148.0.7778.215, confirmed another 10.20% reduction in V8 Wasm-stack trace records (3,597,332→3,230,504) and 11.68% in trace-accounted sizes (74,079,952→65,430,304 bytes).

The follow-up's separate 600-arc query comparisons were dense 21.88→19.25 ms forward and 21.15→18.85 ms reverse; sparse 2.51→1.79 ms and 2.43→1.79 ms. Do not chain these timings with the initial batch's differently timed benchmark runs. Sequence construction now retains O(n) immutable slot data; admission and retained-memory costs are outside these hot-query timings.

### Semantic checks and limits

- All five scenarios preserved every compared Float32 PCM sample and 600-block transport/pending/skipped/tempo/sample/cycle state stream. Counted and uninstrumented binaries agreed.
- Three tracked MiniDraft sources queried over 1,800 arcs preserved serialized whole/part spans, note/gain, source atoms, reference bindings and node paths byte-for-byte.
- Final historical checks: release suite 1,273/1,273; pattern JS and native 249/249 each; 35 generated interfaces unchanged. These are recorded past results, not a new test run during documentation consolidation.
- Dense PCM SHA256: `28d2d746be53de50b4c696a3bb6fd41792d6832ebb903a69c581af14a458810a`.
- Final production Wasm SHA256: `95cd20797736cf035c36b091e818cd5b4ef7d459f2d1d0429300c8e31d782759`.

Executed GC instructions, V8 trace records and physical heap allocations are different quantities. Trace sizes are not retained/peak heap. Profile windows and contiguous 128-frame steps do not establish callback deadlines, GC-pause bounds or underrun safety. Queries still allocate substantially; this is not allocation-free audio. No CLAP/native bridge, graph, browser ABI or source-map policy change was made.

## Onset investigation findings

These isolated experiments pin `0e3549d3aafd026d353976205ef3e6c48b9700e3`, plus a scratch integration patch. Their workload/binary boundaries differ from the optimization baseline above; older totals must not be substituted for the remeasured `e07ad86` baseline.

### Semantics worth preserving

The prototype observed actual successful scheduler dispatch, including previous-block carry, with run/sample/source atom and ordered reference bindings. Chord notes shared their authored atom; nested reference paths remained distinct. Rest/full degradation emitted no dispatch; zero gain could dispatch while producing silent PCM. Untracked text did not fabricate source records. Edits retained old authored events until replacement boundaries; restart changed the run identifier.

The original experimental material-ID field added 6,644 logical scalar payload bytes across 1,661 dense event records even with observation OFF. Removing it eliminated that measured payload delta while preserving the exercised PCM/onset behavior. This deliberately did not provide stable material-instance identity, multi-player ownership or a production contract. Preallocated scratch/SAB transport dropped whole records/batches under overflow or stalled UI rather than blocking audio.

High source identities above 2^32 survived actual scheduler/getter/SAB transport. A separate high-sample fixture exercised signed low limbs; the real scheduler was not run past 2^32 samples. That bridge check is not long-session clock validation.

### Measurement corrections and source attribution

1. The initial heap-sampling driver used invalid `includeObjectsCollected`. The corrected experiment enabled `includeObjectsCollectedByMajorGC` and `includeObjectsCollectedByMinorGC`, used equal 600-block windows and reversed-order controls. Earlier positive ON sampled-byte differences were not reproducibly attributable to sink/getters/SAB.
2. V8 allocation tracking detected a small short-lived JS positive control. A small apparent SAB-copy delta disappeared with diagnostic code-shape changes; it was not a proven source-level allocation. Page-target native sampling failed its Worklet positive control, so zero native samples were not evidence of zero allocation.
3. Silence/DSP/getter/aggregation controls located the bulk trace records on the scheduler/DSP Wasm-call path, not sample retrieval or checksum aggregation.
4. Named-Wasm dynamic instrumentation attributed 5,170,623 of 5,399,504 dense executed GC construction instructions (95.761%) to the sourced-pattern query subtree. Rational/time values, scoped values, event arrays and path traversal dominated. Function-ordinal mapping was rejected when rebuilt binaries differed; the named rebuild was independently instrumented. These rankings motivated the remeasured pattern optimization, not speculative getter/SAB changes.

No complete Worklet-thread JS + Wasm-GC + native allocation census or unconditional allocation-neutral onset transport was established. Timing checks in one Chromium environment do not establish worst-case latency or physical glitch-free output.

## Provenance and reproduction limits

Optimization toolchain: Moon 0.1.20260920 (`914d7da`), Node 24.14.1, Python 3.14.2, Binaryen 125, WSL2 x64. Direct Moon commands used `NEW_MOON_MOD=0`.

This summary replaces nine report/result/archive families. The two tracked optimization families remain recoverable from the [pre-consolidation Git snapshot](https://github.com/dowdiness/moondsp/tree/5a8e495e5ba3524ebe856643fd0526eff3440430/docs/performance). The seven onset families were local untracked evidence, not published artifacts. Their standalone raw profiles and replay bundles were intentionally removed from this working tree; this summary is not a substitute for those reproduction inputs. No backup or external artifact migration was created by the consolidation.
