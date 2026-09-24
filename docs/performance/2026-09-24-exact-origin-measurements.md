# Exact-origin measurements — 2026-09-24

## Current result

The local compiler fix moves `EventOrigin` and `OriginBindings.Link`
construction out of query callbacks. Release browser WAT now contains these
allocations only in cold compilation helpers. Public interfaces and scheduler
ownership are unchanged; a prerequisite architecture PR was not needed.

This trades additional cold compilation and cached variants for reuse of
immutable origins during querying. See [local fix verification](#local-fix-verification)
and the [post-fix raw data](2026-09-24-exact-origin-prebinding.json).
This is **not** a claim that the complete query/render path is allocation-free.

A subsequent [cache prototype comparison](#cache-prototype-comparison) selected
a first-entry fast path with a secondary context-hash index. This improves
preparation for large reference sets, with a measured small-workload tradeoff;
it does not change query-time origin handling.

## Baseline decision

The two small query cases did not show a large added CPU cost. Nested-reference
query means increased by 0.29–0.58 µs (1.3–2.7%) across two repetitions; the
individual benchmark ranges overlap. These observations do not establish a
statistically significant regression or an upper bound for larger inputs.

**At baseline, the allocation-free gate was not passed.** Release wasm-gc output
retained query-time `OriginBindings.Link` and `EventOrigin` heap construction.
This was stronger evidence than the previous unmeasured allocation concern,
but not a measurement of allocated bytes or GC pauses. The baseline measurements
below preceded the production fix.

## Baseline scope and environment

- Production source: `0ca1f514822213cab90e4f16faa5c040778a7b20` (PR #280).
- Comparison is within that revision, with measurement-only additions. It is
  **not** a historical base-versus-PR benchmark.
- Linux/WSL2 x64, AMD Ryzen 7 6800H; Node 24.14.1.
- Moon 0.1.20260904 (`94521db`), moonc v0.10.12+1634b282e, release wasm-gc.
- Worklet: bundled headless Chromium 145.0.7632.6, 48 kHz, 128-frame blocks,
  muted output, no cross-origin isolation. The nominal quantum is 2.667 ms.
- Full environment, artifact/probe SHA256 hashes, unabridged benchmark output,
  Worklet summaries, and generated-WAT excerpts are in the
  [measurement data](2026-09-24-exact-origin-measurements.json).

## Matched query benchmark

[The benchmark](../../mini/exact_origin_benchmark.mbt) obtains one origin-bearing
`PatternDoc` from a real `Draft`, then lowers that same document separately with
`lower()` and `lower_with_origins()`. The ordinary control is not
`exact.as_snapshot()`, which would retain origin computation internally.

Before timing, it checks equality of musical event times, values, order, and
pattern-node paths across all query arcs. The nested case also requires
nonempty reference bindings on every returned event. Parsing, lowering,
assertions, origin-path inspection, and arc construction are outside timing.
The timed operations are `query_sourced_events()` versus `query()`, with no
extra erase/map operation in either timed arm; both retain results with
`bench.keep`.

Two workloads:

```text
note("60 62 64 67")

let motif = note("60 62 64 67"); let phrase = stack(motif, motif.slow(2)); stack(phrase, phrase.slow(3))
```

Prebuilt arcs rotate through starts 0, 1, 2, and 3, each spanning 1.5 cycles.
These are event-query timings, **not 128-frame DSP block timings**. Both
snapshots are reused; this does not measure cold compilation or cache misses.
The Moon benchmark runner calibrates each group independently; its raw sample
counts and ranges are retained in the JSON. Groups run serially in fixed
ordinary-then-exact order; two independent invocations were recorded after a
successful smoke invocation.

| Workload | Ordinary run 1 | Exact run 1 | Ordinary run 2 | Exact run 2 |
|---|---:|---:|---:|---:|
| Direct atoms | 5.90 µs | 5.84 µs | 6.06 µs | 5.95 µs |
| Nested reused references | 21.67 µs | 22.25 µs | 21.86 µs | 22.15 µs |

Values are benchmark means, not per-call tail latencies. The small negative
variation in the direct case is not evidence of an exact-origin speedup.

## Actual AudioWorklet updates

[The existing probe](../../scripts/measure-playback-api.cjs) now accepts
`--exact-origin --order=AB|BA`. A is explicit text input; B is tracked input.
Both receive the nested workload above and the same 40 first-note edits,
alternating 60/61. Tracked wires are produced by the real generated authoring
module using `Draft.edit` and `prepare_playback`, not fabricated source maps.
All 41 immutable inputs are prepared before either audio measurement window.

Each arm has a fresh AudioContext/Worklet, 10 warmup updates, a one-second
no-edit baseline, then 40 updates with a 20 ms pause after each receipt.
After the final update, both arms continue for **at least six further musical
cycles** and until observed pending material count is zero. This keeps the
observation horizon comparable even when one arm adopts changes sooner.
A 30-second wait bound and the existing instrumentation overflow checks fail
incomplete observations rather than silently treating them as success.

Pending/cycle observations use existing receipts and status messages on the
page side. No extra per-quantum getters, object snapshots, logging, or messages
were added to the Worklet instrumentation. Its preallocated timing storage is
unchanged. Existing production status reporting remains enabled in both arms.

| Order / arm | Edited render callbacks | Owner update mean | Owner update p95 / max | Render p95 / max | Receipt p95 |
|---|---:|---:|---:|---:|---:|
| AB / text | 2572 | 0.675 ms | 1 / 1 ms | 1 / 2 ms | 1.10 ms |
| AB / tracked | 2581 | 0.575 ms | 1 / 1 ms | 1 / 1 ms | 1.20 ms |
| BA / tracked | 2576 | 0.750 ms | 1 / 1 ms | 1 / 2 ms | 1.20 ms |
| BA / text | 2572 | 0.550 ms | 1 / 1 ms | 1 / 1 ms | 1.00 ms |

All four arms accepted 40 measured updates, observed a pending peak of four
materials, drained to zero pending, and remained Playing. The final observed
cycle was 8.184, more than six cycles after each final update. Text wire size
was 142 UTF-16 code units; tracked wire sizes were 430–432 code units.

Interpretation limits:

- Worklet timing uses `Date.now()`: integer milliseconds. Over 80% of edited
  render samples recorded zero; this means unresolved sub-millisecond timing,
  **not zero work**. Means are averages of quantized durations.
- The order reversal changes which owner-update mean is higher. These data do
  not resolve a consistent owner-update penalty at this scale.
- Owner timing includes validation, copying into WASM, decode, compile,
  admission, receipt construction, and posting. It does not isolate decode
  from compile or measure main-thread Draft/edit/encode cost.
- Text versus tracked also changes identity continuity and compilation reuse;
  it is a production-path comparison, not an origin-only causal ablation or
  a claim that edited audio should be identical between the arms.
- Callback interarrival p95 values are much larger than one quantum even in
  the no-edit baselines. This headless environment processes buffered bursts;
  gaps are not counted as audible dropouts or deadline misses.
- No audio recording, dynamic allocation counter, GC trace, near-limit source,
  high-density pattern, or large/deep reference workload was measured. This
  is neither a worst-case capacity result nor a glitch-free guarantee.

## Allocation evidence

The release browser WAT contains:

1. The closure from `DocumentOrigin for EventOrigin::bind_origin`
   ([source](../../pattern/pattern_doc.mbt), lines 543–545) constructs
   `OriginBindings.Link` with `struct.new` and calls the `EventOrigin` constructor.
2. That constructor also contains `struct.new`.
3. The ordinary `Unit` binding closure simply returns its scalar argument.

This is a query-time distinction, not merely setup allocation: reference
annotation calls the binding closure from `map_payload`, whose query callback
maps returned events ([source](../../pattern/pattern.mbt), lines 65–85;
`pattern_doc.mbt`, lines 815–818). The scheduler queries these origin-bearing
snapshots on the render path.

The JSON includes the complete generated bodies of the two binding closures
and the exact constructor. Ordinary querying also allocates arrays/events;
those preexisting allocations must not be attributed wholesale to this PR.
Conversely, small timing differences do not remove the new heap-construction
path or certify it as allocation-free. Physical allocation counts, bytes,
possible browser-engine elimination, and GC behavior remain unmeasured.

## Reproduction

From the repository root, with existing dependencies installed:

```sh
NEW_MOON_MOD=0 moon build browser --target wasm-gc --release
NEW_MOON_MOD=0 moon build browser_authoring --target js --release
./playwright-sync-wasm.sh
NEW_MOON_MOD=0 moon bench mini/exact_origin_benchmark.mbt --target wasm-gc --release --no-parallelize
```

Repeat the benchmark command twice without concurrent builds or other probes.
In a separate terminal, serve the matching browser assets:

```sh
python3 -m http.server 5189 --bind 127.0.0.1 --directory web
```

Run the two orders serially:

```sh
node scripts/measure-playback-api.cjs http://127.0.0.1:5189 --exact-origin --order=AB
node scripts/measure-playback-api.cjs http://127.0.0.1:5189 --exact-origin --order=BA
```

Generate allocation-inspection output separately, outside timing runs:

```sh
NEW_MOON_MOD=0 moon build browser --target wasm-gc --release --output-wat --target-dir /tmp/moondsp-origin-wat
```

For the baseline revision, inspect
`/tmp/moondsp-origin-wat/wasm-gc/release/build/browser/browser.wat` for
`DocumentOrigin12bind__origin` and `EventOrigin19EventOrigin_2einner`.
The fixed revision replaces the former with cold `bind__context` and
`make__origin` helpers. Generated suffixes/line numbers can vary.

Baseline validation completed: `moon check --target all --deny-warn` with
`NEW_MOON_MOD=0`, release builds, benchmark parity checks and four groups,
both exact-origin Worklet orders, JavaScript syntax checking, and both
preexisting probe modes (60 page-local iterations; 40 Song Worklet updates).
No full test suite was rerun for these measurement-only additions.

## Local fix verification

### Implementation and lifetime

The shared compiler passes an immutable reference context down to atom
compilation. Each atom captures its completed `EventOrigin`; reference query
callbacks prepend the existing voice-scope path and forward that origin
unchanged. The private cache matches both dependency tokens and reference
contexts, so reusing a definition at two call sites cannot mix their binding
paths. Ordinary lowering and control-provider lowering use the empty context.

No first-query warmup, query-time interning, global origin table, public API
change, or scheduler ownership change was introduced. Contexts and origins
are prepared from the document, independently of future query arcs/counts.
The existing version-retaining cache now also retains context-specific
compilations until cleared; snapshots remain valid after clearing it.

This is not a new hard compilation budget. Reference-context specialization
reduces sharing and increases preparation time and retained compiler state.
Path-rich documents need more preparation; the measurements below are not an
upper bound for arbitrary documents. A regression exercises a shared nested
definition first lowered standalone, then at two reference sites, then
rebound after cache clearing—all before querying the retained snapshots.

### Generated allocation evidence

The post-fix release browser WAT contains exactly three functions with
`struct.new` for `OriginBindings.Link` or `EventOrigin`:

- `DocumentOrigin::bind_context`: builds the reversed compilation context.
- `DocumentOrigin::make_origin`: builds the final outer-to-inner binding path.
- `EventOrigin`'s inner constructor: called only by `make_origin`.

The first two are called only by the exact specialization of
`compile_pattern_node`; none of the three is referenced through `ref.func`.
The former query-time `bind_origin` callback is absent. The generated
`ScopedValue::prepend` reads and forwards its existing origin field.
Full allocator/forwarding functions, caller sites, and source/artifact hashes
are saved in the post-fix JSON.

`ScopedValue`, voice-scope paths, events, and query arrays still allocate.
No allocated-byte, GC-pause, native-target, or whole-render allocation claim
is made.

### Query and preparation costs

One additional pre-fix invocation and two post-fix invocations used the same
release wasm-gc benchmark. Preparation groups parse the document outside
timing, then lower it with a fresh cache on every timed invocation.
The added shared case has five levels of doubled references and 32 paths.

| Measurement | Before fix | After run 1 | After run 2 |
|---|---:|---:|---:|
| Nested ordinary sourced query | 23.05 µs | 23.40 µs | 23.64 µs |
| Nested exact-origin query | 23.37 µs | 23.42 µs | 23.05 µs |
| Direct cold exact compilation | 3.76 µs | 4.11 µs | 4.01 µs |
| Nested reused cold exact compilation | 26.90 µs | 45.40 µs | 44.40 µs |
| 32-path cold exact compilation | 96.77 µs | 262.85 µs | 256.43 µs |

Query timings do not establish a speedup. Cold preparation rose about
1.7× for the nested workload and 2.7× for the 32-path case. Removing the
identified query-time origin construction, not claiming lower elapsed time,
is the reason for the change.

### Actual Worklet and validation

The fixed runtime repeated both AB and BA orders using the same probe and
40 edits per arm. All four arms finished `Playing`, with observed pending
peak 4 and final pending 0 after at least six post-update cycles.
Owner-update means were 0.550/0.525 ms (AB: text/tracked) and
0.575/0.525 ms (BA: tracked/text); p95 and max were 1 ms in every arm.
Edited render p95 was 1 ms, max 1–2 ms. The integer-millisecond clock,
headless callback bursts, muted output, and other baseline limitations apply.
These observations are not a deadline or audible-dropout guarantee.

Validation after the compiler change: 239 pattern tests; all 1,263 project
tests; strict all-target check; `moon info` and `moon fmt`; release browser
and authoring builds; two benchmark repetitions; and both Worklet orders.
Generated interfaces for pattern, mini, and scheduler remained byte-identical.

## Cache prototype comparison

The baseline in this section is the **cold-origin implementation above**, not
the original query-time origin implementation. The
[experiment archive](2026-09-24-origin-cache-prototypes.json) contains the
baseline compiler source, five candidate patches, benchmark sources,
unabridged measurements, integrated artifact hashes, and a replay program.

### Compared candidates

| Candidate | Change | Decision |
|---|---|---|
| Forward binding paths | Append during descent; atoms share the finished path | Reject: small atom-heavy improvement, worse large branching cases |
| Compile-only binding memo | Reverse once per context on first cold use | Reject: improvement too small/inconsistent for the extra state |
| Composite hash index | Index every lookup by node ID and context fingerprint | Reject: improves large cases, adds overhead to small cases |
| Cached fingerprint | Compute the composite-index fingerprint once per reference context | Reject: did not remove the small-case cost |
| Sparse secondary index | Direct first entry; allocate/index additional variants only | **Adopt**, accepting the tradeoffs below |

Screening rotated four pre-parsed documents per scenario and created a fresh
lowering cache per timed call. Dimensions were 32/128/512 branching paths,
a depth-16 single path, 8/64 atoms at depth 8, and 32 paths with 16 atoms.
Parsing, event-value/time/order parity, scope-path parity, and binding-depth
checks were outside timing. Stress fixtures are compiler workloads, not a
claim that the browser admits every fixture for playback.

Separate-invocation screening was repeated in reverse order. The selected
candidate was then compared with baseline **within the same compiled Wasm
module/process**, in per-scenario AB and BA order:

| Cold preparation | AB baseline | AB sparse | BA baseline | BA sparse |
|---|---:|---:|---:|---:|
| 32 paths | 268.05 µs | 289.18 µs | 270.48 µs | 274.69 µs |
| 128 paths | 1.93 ms | 1.80 ms | 1.85 ms | 1.66 ms |
| 512 paths | 17.02 ms | 14.47 ms | 17.04 ms | 14.24 ms |
| Depth 16 | 32.46 µs | 33.07 µs | 32.22 µs | 32.26 µs |
| 8 atoms, depth 8 | 32.55 µs | 33.09 µs | 33.88 µs | 34.40 µs |
| 64 atoms, depth 8 | 195.42 µs | 194.66 µs | 202.82 µs | 199.48 µs |
| 32 paths, 16 atoms | 1.83 ms | 1.81 ms | 1.94 ms | 1.85 ms |

The 512-path case improves 15.0–16.4%; the 128-path case improves 6.7–10.3%.
The 32-path case regresses 1.6–7.9%. This is a scalability tradeoff, not a
universal speedup. For the original nested musical workload, paired cold
means were 40.60→41.23 µs (AB) and 40.57→40.87 µs (BA): about 0.3–0.6 µs
additional cost. A separate replay smoke confirmed the direction.
No outliers were removed; noisy screening and direct-case samples remain
in the archive. These few repetitions are not statistical confidence bounds.

### Integrated change and remaining costs

The first cached variant stays directly accessible without hashing its
context or allocating a secondary table. Additional variants are grouped
by a binding-serial fingerprint. Fingerprints are **not identities**:
full binding witnesses, epochs, and dependency tokens are still checked.
A regression with coincident binding serials exercises distinct reference
witnesses in the same bucket. Existing cache statistics, revision isolation,
and retained-snapshot behavior remain intact.

Hash collisions still require a bucket scan. Whole-pattern specialization,
dependency-token construction/copies, and per-atom binding reversal remain.
Retained heap size, allocated bytes, GC pauses, and retained-cache update
latency were not measured. This experiment does not establish a hard
preparation bound or native-target performance.

Integrated verification: strict all-target check; all **1,264 tests**;
`moon info`/`moon fmt`; unchanged pattern public interface; release browser
and authoring builds; the existing query/preparation benchmark; and actual
Worklet AB/BA runs. Every arm accepted 40 measured updates, finished `Playing`,
and drained pending updates to zero.

Worklet owner-update p95/max were 1 ms. Render p95 was 1 ms, with reported
maxima of 1–3 ms. The 3 ms reading exceeds the nominal 2.667 ms quantum,
but the integer-millisecond clock cannot establish an exact deadline miss
or deadline compliance. Muted headless playback is not audible-dropout proof.
Release WAT still places all `EventOrigin`/`OriginBindings.Link` constructors
in the three cold functions documented above, with no allocator `ref.func`
references or restored `bind_origin` callback.

### Replay

From the repository root, with existing Moon dependencies and `patch` installed:

```sh
python3 -c 'import json; exec(json.load(open("docs/performance/2026-09-24-origin-cache-prototypes.json"))["reproducer"])'
```

This creates a temporary module, reconstructs baseline and candidate
packages, runs the paired benchmarks serially, and removes the module.
Add `--smoke` to run only the representative direct/nested comparison.
The smoke command was executed successfully. It does not edit production
sources. No prototype packages or benchmark-only public APIs were retained.
