# Wasm-GC allocations: pan trigonometry and Biquad::update (issue #254)

Date: 2026-11-07
Source commit: `f7701dc642659bdbb070c36b3430d2cbc4e895eb` (2026-11-05)
Toolchain: moon `0.1.20260920` / moonc `v0.10.14+7d59c7ec9` (same pin as CI)
Core under analysis: `moonbitlang/core` `math/trig_double_sincos_non_native_or_js.mbt` as shipped with moonc v0.10.14 (installed 2026-11-06)
Method: source inspection + call-path frequency analysis, cross-checked against the sine evidence chain already established in issue #254 (same core file, same allocation pattern). WAT-level verification was not repeated for this record; issue #254 already verified with emitted WAT that the identical `let y = [0.0, 0.0]` pattern in core's `sin` allocates a temporary two-element array per call.

## Summary

| Target | Call site | Implementation reached on wasm-gc | Per-call allocation? |
| --- | --- | --- | --- |
| `dsp/filter.mbt:77-78` (`Biquad::update` → bare `cos(w0)`/`sin(w0)`) | control path, not per-sample | package-local scalar kernel `dsp/osc_sine_wasm_gc.mbt` (`trig_kernel`, header says "shared by oscillators and biquads") | **No** — scalars only |
| `dsp/pan.mbt:69` (`pan_left_gain` → `@math.cos`) | per block, 1× per Pan node | core `cos` (pure-MoonBit wasm-gc path) | **Yes** — `let y = [0.0, 0.0]` allocates unconditionally, even on the `≤ PI/4` fast path that never reads `y` |
| `dsp/pan.mbt:89` (`pan_right_gain` → `@math.sin`) | per block, 1× per Pan node | core `sin` (pure-MoonBit wasm-gc path) | **Yes** — same pattern |

JS and native backends are unaffected: `math/trig_double_js.mbt` binds `Math.cos`/`Math.sin` natively and native uses the C `sincos` path.

## Call frequency (Pan)

`Pan::process` computes both gains once per block, outside the sample loop
(`dsp/pan.mbt:36-37`). At 48 kHz / block 128 that is 375 blocks/s × 2 calls =
~750 trig calls/s per Pan node. Each call allocates a two-element array plus
its wrapper on wasm-gc, i.e. a continuous small-allocation stream on the order
of tens of KB/s per node — 128× smaller than the per-sample sine case measured
in issue #254, but of the same provenance and avoidable.

## Why Biquad::update is clean

`Biquad::update` (`dsp/filter.mbt:58-114`) writes only `mut` scalar fields of
`Biquad`. Its `cos`/`sin` calls are unqualified names resolved inside the `dsp`
package: on wasm-gc they bind to the package-local scalar kernels in
`dsp/osc_sine_wasm_gc.mbt` (adapted from core, scratch array replaced by
scalars, explicitly documented as shared by oscillators and biquads). On other
targets they bind to `dsp/osc_sine_other.mbt`, which forwards to `@math`; that
is fine for js (native binding) and native (C `sincos`), and `update` runs on
the control path rather than per sample.

## Pan discrepancy

`pan_left_gain`/`pan_right_gain` call `@math.cos`/`@math.sin` **with the
package prefix**, so on wasm-gc they reach the allocating core implementation
even though a local scalar kernel with an exactly matching input domain
("nonnegative angles up to one turn"; pan angle ∈ [0, π/2]) already exists in
the same package.

## Suggested fix (not implemented here, per issue scope)

Either:

- change `dsp/pan.mbt:69/89` from `@math.cos(angle)`/`@math.sin(angle)` to the
  package-local `cos(angle)`/`sin(angle)` (two-line change, same treatment
  `Biquad::update` already received), with a numeric-regression check that
  equal-power gains match core's results within 1 ULP for the pan angle range;
  or
- upstream a scalar (non-allocating) trig variant to `moonbitlang/core` so all
  callers benefit.

Both options eliminate the recurring per-block allocation stream on the
wasm-gc audio path without touching the sample loop.
