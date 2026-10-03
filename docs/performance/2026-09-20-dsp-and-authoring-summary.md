# DSP and Authoring — Consolidated Findings

DSP and external-authoring performance work, 2026-04 through 2026-09.
Original sources at
[`docs/performance/` at commit 5a8e495](https://github.com/dowdiness/moondsp/tree/5a8e495e5ba3524ebe856643fd0526eff3440430/docs/performance).
Targets and toolchains differ by experiment; the comparisons below retain
their recorded scope. Repetitive per-build suite tables are omitted;
in-tree benchmarks serve regression detection.

## sine-allocation

*Source: 2026-09-14 Wasm-GC sine allocation fix. Base: `0979c8e`.*

Wasm-GC oscillator's private sine kernel replaced its two-element scratch
`Array` with scalar locals. Core coefficients, reduction cutoffs,
cancellation corrections, evaluation order retained. Other targets use
`core.math.sin`; public `.mbti` unchanged.

**Regression tests:** 65 537 phases, exact `Double` bit patterns vs
`core.math.sin` (signed zero, subnormals, quadrant boundaries, cancellation,
wrap-to-one, overflow). **Browser PCM:** Original vs fixed WASM rendered
4,718,592 samples across nine graphs, zero mismatches (`Object.is` including
signed zero). **Allocation:** WAT shows no heap/reference ops in sine call
graph. Sampling harness: ~92 MB → ~0.23 MB (1 graph), ~1470 MB → ~0.39 MB
(16 graphs). Residual includes harness; not zero-allocation claim.
**AudioWorklet:** Paired browser traces (~15 s/variant). Original: 430 minor
GC events. Fixed: 0. One fixed window recorded one underrun (11.625 ms) with
zero GC; original recorded none. **Does not establish glitch-free audio.**

## graph-control

*Source: 2026-09-20 graph single-control allocation probe. Base: `e2c3fd7`.*

`Dsp::apply_control` / `StereoDsp::apply_control` constructed one-element
batches via `apply_controls_impl`. Fix routes directly to
`CompiledGraph::apply_control_impl`. Validation/transactional semantics
unchanged. **Method:** Native release, GNU linker wrappers counting
`malloc`/`calloc`/`realloc`/`mi_malloc` during measured loops. 3-node mono
and 4-node stereo, same prebuilt gain control × 1 000. **Result (allocations
per 1 000 calls):** mono `apply_control` 7 000 → 4 000, stereo `apply_control`
7 000 → 4 000, retained-batch `apply_controls` 7 000 → 7 000. PCM matched at
index 32. **Limits:** Counts allocation *calls*, not bytes/time/GC/glitches.
`Result`-returning API still allocates (4 calls/update). **Not an
allocation-free control API claim.**

## constant-fold-barriers

*Source: 2026-07-19 runtime-control constant-fold barriers. Base: `fcc167f` plus the working-tree correction; Moon 0.1.20260713.*

Optimizer retains runtime control nodes (`Gain`, `Clip`) during constant
folding so controls/bindings keep targeting the authored parameter kind.
Pure arithmetic still folds beneath those nodes. **Isolated A/B (128
samples):** Folded `Constant(5) → Output` 0.856 µs; retained
`→ Gain(0.5) → Output` 1.28 µs (+0.424 µs); retained `→ Clip(5) → Output`
1.27 µs (+0.414 µs). Absolute cost ~0.41–0.42 µs per affected render
(~0.016 % of 2.667 ms block budget). Large relative % because folded
baseline is the two-node floor. Quantifies exact structural difference;
does not attribute whole-engine drift. Exploratory follow-up in
[`control-aware-partial-evaluation.md`](../control-aware-partial-evaluation.md).
The original records `moon bench` without an explicit target. These local
benchmark numbers are not verified AudioWorklet callback timings.

## delayline-reset

*Source: 2026-09-19 DelayLine valid-range reset. Physical-fill baseline: `c627749`.*

`DelayLine::reset` no longer zero-fills its circular buffer — constant-time
valid-range clear. Unwritten samples read as silence; delay/feedback
unchanged. Voice prepared-slot steals use the same `reset()` via
`CompiledDsp::reset_runtime_state`. `StereoReverb` keeps physical zero-fill.
**Focused A/B (wasm-gc, same archive, only `dsp/delay.mbt` differs):**
Reset-only at capacity 480 000: 5.28 ns (valid-range) vs 46.03 µs (physical
fill). At capacity 4 800: 5.23 ns vs 350.83 ns. Reset + 16 ticks at 480 000:
63.80 ns vs 46.29 µs. Warmed steady-state 16 ticks differed by about 15 ns
between variants (58–67 ns vs 52–71 ns), within run-to-run noise.

## shared-reverb

*Source: 2026-09-11 shared stereo room reverb benchmarks.*

Room processed once per playback block, independent of voice count. 128
frames at 48 kHz: wasm-gc 26.05 µs (0.98 % of 2.667 ms quantum), js 23.71 µs
(0.89 %), native 19.58 µs (0.73 %). Local focused snapshot, not a worst-case
AudioWorklet guarantee.

## external-authoring

*Sources: 2026-06-02 external authoring, 2026-06-03 cross-target / diagnostic
/ realistic snapshots.*

External graph-authoring/control measured in isolation across wasm-gc,
native, and JS. Fixtures: synthetic mono chains (10/34/130 nodes), realistic
shapes (branch fan-out, mix bus, terminal stereo, feedback loop), and
diagnostic/rejection paths. **Measured peaks:** Largest authoring operation
in these snapshots: 130-node template compile — wasm-gc 55.74–63.35 µs, native
~48 µs, JS ~130 µs. All below 60 Hz UI frame (16.6 ms) in these fixtures.
Block-boundary control application peaked at ~17.56 µs (native, synthetic
large topology-controller path) — below 2.667 ms audio budget in this
fixture. **Separation enforced:** template analysis, binding generation,
string-key resolution, topology edits, compile, and hot-swap setup stay off
the audio callback. Audio consumes only prepared state: precompiled graphs,
validated bindings, pre-resolved `GraphControl`. **Cross-target:** wasm-gc
is the AudioWorklet baseline; native for future plugin experiments; JS
practical with Node-specific caveats.

## Historical baselines

*Sources: 2026-04-01 baseline + after-dedup, 2026-04-09 pre-redesign,
2026-05-10 post-redesign, 2026-06-10 core-method adoption, 2026-06-10
declarative loop sweep.*

Older architecture/style-refactor tables are omitted: cross-run suite
numbers are not a controlled comparison against the current engine.
The 2026-05-19 voice-template investigation found `validate_voice_template`
compiled and discarded a graph (waste-to-productive ratio 0.89×–1.06× on
wasm-gc/native), costing 1.6–7 µs of control-thread work per call. It deferred
the change until an authoring-latency complaint, sustained rates above
1 kHz, or JS-target evidence justified it. This is a historical tradeoff,
not a prohibition on future optimization.
