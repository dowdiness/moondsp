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

## 2026-11-01: merged controls come from buses at the snapshot root

ADR-0019 lowering stopped querying each `merge_control` provider; a snapshot
now writes bound keys from their buses at its root. Measured with a temporary
`moon bench --release` (native, Moon 0.1.20261023 `3778465`, Linux x64 orb)
that queried `query_sourced_events` and `pat().query` for 750 blocks of 128
samples at 48 kHz, against the previous commit in a separate worktree, run
sequentially once each:

| Mini source | Before (mean ± σ) | After (mean ± σ) |
|---|---:|---:|
| `note("C4 E4 G4 B4").gain(0.5).lpf(1200).pan(-0.3).room(0.2)` | 37.96 ± 5.50 ms | 18.87 ± 3.34 ms |
| `chord("Dm9 Bbmaj7").slow(2).lpf(saw.range(200, 4000).slow(4)).gain("1 0.6").pan(sine)` | 78.93 ± 7.28 ms | 64.01 ± 8.30 ms |
| `s("hh*16").gain("1 0.4 0.7 0.4")` | 14.38 ± 0.33 ms | 7.54 ± 0.66 ms |

Browser host output was bit-identical over 400 blocks for seven scores,
four with time-varying controls; only `note("C3").gain(saw).gain("1 ~")`
changed, because its rest now falls back to the inner `saw`. This was a
shared orb with one run per side: it supports that removing the provider
queries outweighs the root fill, not a stable speedup figure. Allocation
counts and the Worklet path were not measured.

## 2026-11-19: typed control keys (ADR-0020 step 2)

`ControlMap` and the bus bindings moved from `String` keys to the closed
`Control` enum. Measured with the 2026-11-01 method: a temporary
`moon bench --release` (native, Moon 0.1.20261117 `eb64713`, MoonBit
0.10.21, Linux x64 orb) querying `query_sourced_events` and `pat().query`
over 750 blocks of 128 samples at 48 kHz. The baseline was `03e1a05` plus
the uncommitted work up to ADR-0020 step 1, in a separate worktree; the two
sides alternated for three rounds.

The first comparison was 2–6% slower in 8 of 9 pairs. An isolated map
benchmark (2,000 rounds of five inserts, a copy, and five lookups) traced it
to the derived `Hash`, which runs the full `Hasher`: `Map[Control, Double]`
took 2.29 ms against 1.68 ms for `Map[String, Double]`. Hashing the variant's
position directly brought it to 1.40 ms. With that hash, the means of the
three rounds were:

| Mini source | Before | After |
|---|---:|---:|
| `note("C4 E4 G4 B4").gain(0.5).lpf(1200).pan(-0.3).room(0.2)` | 11.25 ms | 10.54 ms |
| `chord("Dm9 Bbmaj7").slow(2).lpf(saw.range(200, 4000).slow(4)).gain("1 0.6").pan(sine)` | 41.31 ms | 39.21 ms |
| `s("hh*16").gain("1 0.4 0.7 0.4")` | 5.53 ms | 5.47 ms |

Browser host output over 400 blocks (both channels hashed per sample) was
identical to the baseline for ten scores: the seven 2026-11-01 scores,
`note("C3").gain(saw).gain("1 ~")`, `note("C3").gain(0.5).gain(0.25)`, and
`note("C3 E3").hold(0.2).release(0.1)`, whose output differs from the same
score without `hold`, so the renamed `Decay`/`Sustain` envelope bindings were
exercised. Against `03e1a05` only the two nested-`gain` scores differ, as the
gain multiplication intends; `03e1a05`'s hash for the first matches the
2026-11-01 "after" value. This is one shared orb: it supports "no
regression", not a speedup figure. Allocation counts and the Worklet path
were not measured.

## 2026-11-19: own values and buses kept apart (ADR-0020 step 3)

Lowering stopped writing bus values into payloads; controls are projected
only where they leave lowering, with every bound key written by one `apply`.
Same method and orb as the step 2 entry, against `20016ea` in a separate
worktree, three alternating rounds. The first version projected each key
with its own `ControlMap::single` and merge and was about 4% slower on the
first score; writing all keys at once gave:

| Mini source | Before | After |
|---|---:|---:|
| `note("C4 E4 G4 B4").gain(0.5).lpf(1200).pan(-0.3).room(0.2)` | 10.84 ms | 9.00 ms |
| `chord("Dm9 Bbmaj7").slow(2).lpf(saw.range(200, 4000).slow(4)).gain("1 0.6").pan(sine)` | 39.86 ms | 33.90 ms |
| `s("hh*16").gain("1 0.4 0.7 0.4")` | 5.65 ms | 5.24 ms |

Browser host output hashes over 400 blocks were identical to the step 2
entry's for all ten scores. One shared orb; allocation counts and the
Worklet path were not measured.

## 2026-11-19: voices read an event's controls (ADR-0020 step 4)

The scheduler hands each note-on `@pattern.Controls` instead of copying its
controls into a `Map` and collecting a follow list. An isolated benchmark
starts and kills one voice for each of the 72 onsets that
`chord("Dm9 Bbmaj7").lpf(saw.range(200, 4000).slow(4)).gain("1 0.6").pan(sine).room(0.2)`
plays over 8 cycles, through `note_gate` and note-on, on a pool binding
`note`, `lpf`, `gain`, and `pan`. Against `37b034b`, in a separate worktree
with the old call sequence, three alternating rounds (wasm-gc, release):

| Round | Before | After |
|---|---:|---:|
| 1 | 275.63 µs | 260.94 µs |
| 2 | 265.43 µs | 262.07 µs |
| 3 | 293.73 µs | 272.62 µs |

Voice start dominates the cost, so this supports "no regression", not a
speedup. The three pattern query scores above stayed within noise of
`37b034b` (8.8–9.5 ms, 33–36 ms, 4.8–5.4 ms). Browser host output hashes
over 400 blocks were identical to the step 3 entry's for all ten scores. The
CLAP allocation audit stayed at zero, with followers now returning
`ControlValue`. One shared orb; allocation counts on the browser note-on path
were not measured.

## 2026-11-24: one TimeMap for queries and bus signals (ADR-0024)

`fast`, `slow`, `rev`, sequences, weighted sequences, Euclid, and placement
now share one piecewise affine `TimeMap` for event queries and bus reads.
Baseline `690d93c` (after the `rev` fix, before `TimeMap`) in a separate
worktree against `fd7109e`; three alternating rounds, wasm-gc release,
moon 0.1.20261117, one shared orb. The middle column is the refactor before
the three query fixes below, an intermediate state later folded into
`3536579`. Medians:

| Benchmark | `690d93c` | Refactor before the fixes | `fd7109e` |
|---|---:|---:|---:|
| `note("C4 E4 G4 B4").gain(0.5).lpf(1200).pan(-0.3).room(0.2)`, 750 block queries | 1.21 ms | 1.19 ms | 1.07 ms |
| `chord("Dm9 Bbmaj7").slow(2).lpf(saw.range(200, 4000).slow(4)).gain("1 0.6").pan(sine)` | 3.56 ms | 4.06 ms | 3.76 ms |
| `s("hh*16").gain("1 0.4 0.7 0.4")` | 552 µs | 640 µs | 565 µs |
| `s("bd(3,8) [hh hh]*2 [sd cp]/2").rev().fast(1.5)` | 2.91 ms | 2.70 ms | 2.34 ms |
| `jux_benchmark` `rev_4step` | 4.22 µs | 5.28 µs | 4.44 µs |
| `jux_benchmark` `fast_4step` | 7.04 µs | 7.42 µs | 7.23 µs |
| `control_bus_benchmark` block query with bus bindings | 2.08 ms | 2.20 ms | 2.23 ms |
| `control_bus_benchmark` one compiled bus signal per block | 21.6 µs | 20.7 µs | 20.0 µs |

The refactor alone cost up to 22% on queries. Three changes recovered it:
a reduced `a/b` inverts to `b/a` and a mirror to itself, without division;
slots start at the arc's first slot (`slot_at`) instead of building every
slot's arc; and a bus read reduces by a gcd only when its denominator grew.
Two candidates did not help and were not kept: a `−1` fast path in the
span map alone, and a closed-form `slot_at` for equal slots.

Noise on this orb is large: `path_allocation_benchmark` `depth_12`, which
does not touch `TimeMap`, moved 17% between rounds, and the baseline's first
score ranged 1.21–1.63 ms. Read differences under about 10% as no change;
the first and fourth scores are consistently faster.

Allocation: `BusSignal::eval` and every function it calls (`TimeMap`
`cycle_at`, `slot_at`, `scale_*`, `offset_*`, `time_floor`, `gcd`) contain
no `struct.new`/`array.new` in release wasm-gc WAT and construct no object
(`new`) in release JS, inspected statically, not counted at run time. On JS
`Int64` is a `BigInt`, so its arithmetic may still allocate on the heap; the
code before the refactor had the same property. The CLAP audit
(`scripts/audit-clap-audio-allocations.sh --expect-zero`) stayed at zero.

Output: FNV-1a hashes of 400 rendered browser-host blocks (exact editor
input) for nine scores were identical at `690d93c` and the refactor before
the fixes, and the fixes changed none of them. Of these nine scores, step 6
(`fd7109e`, sequence slots keep the cycle) changed only the two with a
slowed step in a sequence, `note("60 [64 67]/2").fast(4)` and
`s("bd [sd cp]/2").fast(4)`. Scores outside this set can change too: `?`
inside a sequence now rolls per cycle (see the CHANGELOG).

## Provenance and reproduction limits

Optimization toolchain: Moon 0.1.20260920 (`914d7da`), Node 24.14.1, Python 3.14.2, Binaryen 125, WSL2 x64. Direct Moon commands used `NEW_MOON_MOD=0`.

This summary replaces nine report/result/archive families. The two tracked optimization families remain recoverable from the [pre-consolidation Git snapshot](https://github.com/dowdiness/moondsp/tree/5a8e495e5ba3524ebe856643fd0526eff3440430/docs/performance). The seven onset families were local untracked evidence, not published artifacts. Their standalone raw profiles and replay bundles were intentionally removed from this working tree; this summary is not a substitute for those reproduction inputs. No backup or external artifact migration was created by the consolidation.
