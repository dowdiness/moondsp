# Browser Slot Refactor — Design Spec

**Date:** 2026-04-17
**Status:** Draft — awaiting user review
**Audit reference:** `docs/audit-2026-04-02.md` §S2 ("Browser package is monolithic")

## Goal

Eliminate the copy-pasted lifecycle scaffolding across seven browser graph variants so that future variants, bug fixes, and phase-6 additions change one place instead of five or seven.

## Motivation

The `browser/` package exposes seven near-identical graph variants to JavaScript as wasm exports. Each variant file (`browser_compiled.mbt`, `browser_hot_swap.mbt`, `browser_topology_edit.mbt`, `browser_stereo.mbt`, `browser_stereo_hot_swap.mbt`, `browser_stereo_topology_edit.mbt`, `browser_exit_deliverable.mbt`) repeats the same skeleton:

- Five `@ref.Ref` globals: graph, context, output buffer(s), sample_rate, block_size
- An `ensure_*` function with identical rate/block caching logic
- A `reset_*` function that nulls all five refs
- An `init_*_graph` public wrapper over `ensure_*`
- A `process_*_block` public wrapper that calls `ensure_*` then drives the graph
- A `*_output_sample` (mono) or `*_left_sample` + `*_right_sample` (stereo) accessor

The 2026-04-02 audit flagged this (S2) with the prediction: *"the next bug will come from a change applied to 5 of 6 variants."* Phase 6 work will add more variants, which compounds the risk.

## Non-goals

- **`browser_scheduler.mbt` is out of scope.** It holds four `SoundPool` globals with a pattern and control binding, not a single graph — structurally different from the seven target variants. Refactoring it needs a different abstraction; defer to a separate effort.
- **`browser.mbt` header, `main`, `reset_phase`, and demo tick passthroughs stay as-is.** They are not the problem.
- **No changes to the JavaScript-facing wasm ABI.** Every exported function keeps its exact name and signature. Existing Playwright tests are the behavioral check.
- **No changes to `lib/`, `graph/`, `dsp/`, `voice/`, `pattern/`, or `scheduler/`.** The refactor is confined to the `browser/` package.

## Design

### Shared machinery: `browser/slot.mbt` (new file)

Three private types plus one capability trait, following MoonBit's Pattern 3 (Capability Traits) from `moonbit-traits`: keep the trait small (two methods) and leave structurally-different methods on concrete types.

```moonbit
///|
/// Capability trait — uniform-signature lifecycle methods the generic slot
/// needs from the output buffers. Structurally-different sample accessors
/// live on concrete types, not the trait.
priv trait Output {
  reset(Self) -> Unit
  allocate(Self, block_size : Int) -> Unit
}

///|
priv struct MonoOut {
  buffer : @ref.Ref[@lib.AudioBuffer?]

  fn new() -> MonoOut
}

fn MonoOut::new() -> MonoOut { { buffer: @ref.new(None) } }
impl Output for MonoOut with reset(self) { self.buffer.val = None }
impl Output for MonoOut with allocate(self, n) {
  self.buffer.val = Some(@lib.AudioBuffer::filled(n))
}

// Concrete type-specific API — NOT on the trait.
fn MonoOut::get(self) -> @lib.AudioBuffer { self.buffer.val.unwrap() }
fn MonoOut::sample(self, i : Int) -> Double { checked_sample(i, self.buffer.val) }

///|
priv struct StereoOut {
  left  : @ref.Ref[@lib.AudioBuffer?]
  right : @ref.Ref[@lib.AudioBuffer?]

  fn new() -> StereoOut
}

fn StereoOut::new() -> StereoOut {
  { left: @ref.new(None), right: @ref.new(None) }
}
impl Output for StereoOut with reset(self) {
  self.left.val = None; self.right.val = None
}
impl Output for StereoOut with allocate(self, n) {
  self.left.val  = Some(@lib.AudioBuffer::filled(n))
  self.right.val = Some(@lib.AudioBuffer::filled(n))
}

fn StereoOut::left_buf(self)  -> @lib.AudioBuffer { self.left.val.unwrap() }
fn StereoOut::right_buf(self) -> @lib.AudioBuffer { self.right.val.unwrap() }
fn StereoOut::left_sample(self, i : Int)  -> Double { checked_sample(i, self.left.val) }
fn StereoOut::right_sample(self, i : Int) -> Double { checked_sample(i, self.right.val) }

///|
/// Generic slot parameterised by graph type `T` and output shape `O`.
/// Holds the uniform 5-Ref scaffolding and drives rate/block caching.
priv struct GraphSlot[T, O] {
  graph       : @ref.Ref[T?]
  context     : @ref.Ref[@lib.DspContext?]
  output      : O
  sample_rate : @ref.Ref[Double]
  block_size  : @ref.Ref[Int]
  compile     : (@lib.DspContext) -> T?

  fn[T, O] new(output~ : O, compile~ : (@lib.DspContext) -> T?) -> GraphSlot[T, O]
}

fn[T, O] GraphSlot::new(
  output~ : O,
  compile~ : (@lib.DspContext) -> T?,
) -> GraphSlot[T, O] {
  {
    graph: @ref.new(None),
    context: @ref.new(None),
    output,
    sample_rate: @ref.new(0.0),
    block_size: @ref.new(0),
    compile,
  }
}

// Trait-bounded scaffolding — written once:
fn[T, O : Output] GraphSlot::ensure(
  self : GraphSlot[T, O],
  rate : Double,
  block : Int,
) -> Bool {
  if rate <= 0.0 || block <= 0 {
    self.reset()
    return false
  }
  if self.graph.val is Some(_)
      && self.sample_rate.val == rate
      && self.block_size.val == block {
    return true
  }
  let ctx = @lib.DspContext::new(rate, block)
  match (self.compile)(ctx) {
    Some(g) => {
      // Allocate output buffers FIRST so that if allocation aborts,
      // no slot refs are published — preserving the all-or-nothing init
      // invariant the current per-variant code enforces with locals.
      self.output.allocate(block)
      self.graph.val = Some(g)
      self.context.val = Some(ctx)
      self.sample_rate.val = rate
      self.block_size.val = block
      true
    }
    None => { self.reset(); false }
  }
}

fn[T, O : Output] GraphSlot::reset(self : GraphSlot[T, O]) -> Unit {
  self.graph.val = None
  self.context.val = None
  self.output.reset()
  self.sample_rate.val = 0.0
  self.block_size.val = 0
}

fn[T, O] GraphSlot::graph_val(self : GraphSlot[T, O]) -> T { self.graph.val.unwrap() }
fn[T, O] GraphSlot::ctx_val(self : GraphSlot[T, O]) -> @lib.DspContext { self.context.val.unwrap() }

// Moved from browser.mbt to co-locate with MonoOut.sample / StereoOut.*_sample:
fn checked_sample(index : Int, output : @lib.AudioBuffer?) -> Double {
  match output {
    Some(buffer) if index >= 0 && index < buffer.length() => buffer.get(index)
    _ => 0.0
  }
}
```

### Rationale

- **Capability trait, not monolithic.** `Output` contains only the two methods whose signatures are identical across mono and stereo. The MoonBit Feasibility Check rule rules out unifying `process` (mono takes one buffer, stereo takes two) or the sample accessors (different method names) — those stay on concrete types.
- **Trait bounds on methods, not the struct.** MoonBit syntax: `struct GraphSlot[T, O] { ... }` declares no bounds; `fn[T, O : Output] GraphSlot::ensure(...)` adds the bound only where needed. This matches MoonBit idiom — e.g., `fn[T : FilterSym] exit_deliverable()` in `README.mbt.md`.
- **Concrete output type preserved at call sites.** Because `O` is a type parameter (not a trait object), `compiled.output` is statically typed as `MonoOut`; calling `compiled.output.left_sample(i)` is a compile error, not a runtime zero. No runtime dispatch.
- **`fn new` inside struct body for all structs.** Per the corrected MoonBit base convention: applies regardless of visibility. Enables `GraphSlot(output=..., compile=...)` call syntax with labelled args. Generic form uses `fn[T, O] new(...)` — `@ref.Ref[T]` in core is precedent.
- **Variant-specific extras (gain, inserted flag) stay as plain module-level `@ref.Ref`s** alongside the slot in their variant file. Adding a third type parameter `E` for extras would over-engineer for the one or two variants that have them.

### Variant file shape — worked examples

**Mono, with controls** (`browser_compiled.mbt`):

```moonbit
let compiled : GraphSlot[@lib.CompiledDsp, MonoOut] = GraphSlot(
  output = MonoOut(),
  compile = fn(ctx) { @lib.CompiledDsp::compile([
    @lib.DspNode::oscillator(@lib.Waveform::Triangle, BROWSER_COMPILED_DEFAULT_FREQ),
    @lib.DspNode::gain(0, BROWSER_COMPILED_DEFAULT_GAIN),
    @lib.DspNode::clip(1, BROWSER_COMPILED_CLIP_THRESHOLD),
    @lib.DspNode::output(2),
  ], ctx) },
)

pub fn init_compiled_graph(sample_rate : Double, block_size : Int) -> Bool {
  compiled.ensure(sample_rate, block_size)
}

pub fn process_compiled_block(
  freq : Double, gain : Double, sample_rate : Double, block_size : Int,
) -> Bool {
  if !compiled.ensure(sample_rate, block_size) { return false }
  let g = compiled.graph_val()
  if !g.apply_controls([
    @lib.GraphControl::set_param(0, @lib.GraphParamSlot::Value0, freq),
    @lib.GraphControl::set_param(1, @lib.GraphParamSlot::Value0, gain),
  ]) { return false }
  g.process(compiled.ctx_val(), compiled.output.get())
  true
}

pub fn compiled_output_sample(index : Int) -> Double { compiled.output.sample(index) }

fn reset_compiled_graph() -> Unit { compiled.reset() }
```

**Stereo, no extras** (`browser_stereo.mbt`):

```moonbit
let stereo : GraphSlot[@lib.CompiledStereoDsp, StereoOut] = GraphSlot(
  output = StereoOut(),
  compile = fn(ctx) { @lib.CompiledStereoDsp::compile(/* graph nodes */, ctx) },
)

pub fn init_compiled_stereo_graph(r : Double, b : Int) -> Bool { stereo.ensure(r, b) }

pub fn process_compiled_stereo_block(...) -> Bool {
  if !stereo.ensure(r, b) { return false }
  let g = stereo.graph_val()
  g.process(stereo.ctx_val(), stereo.output.left_buf(), stereo.output.right_buf())
  true
}

pub fn compiled_stereo_left_sample(i : Int)  -> Double { stereo.output.left_sample(i) }
pub fn compiled_stereo_right_sample(i : Int) -> Double { stereo.output.right_sample(i) }

fn reset_compiled_stereo_graph() -> Unit { stereo.reset() }
```

**Mono, with extras** (`browser_topology_edit.mbt`):

```moonbit
let topo_edit_gain : @ref.Ref[Double] = @ref.new(BROWSER_COMPILED_DEFAULT_GAIN)
let topo_edit_inserted : @ref.Ref[Bool] = @ref.new(false)

let topo_edit : GraphSlot[@lib.CompiledDspTopologyController, MonoOut] = GraphSlot(
  output = MonoOut(),
  compile = fn(ctx) { @lib.CompiledDspTopologyController::from_nodes(
    [@lib.DspNode::constant(BROWSER_COMPILED_DEFAULT_GAIN), @lib.DspNode::output(0)],
    ctx,
    crossfade_samples = BROWSER_TOPOLOGY_EDIT_CROSSFADE_SAMPLES,
  ) },
)

// queue_*, set_*, process_* use topo_edit_gain + topo_edit_inserted alongside the slot.

fn reset_compiled_topology_edit_graph() -> Unit {
  topo_edit.reset()
  topo_edit_gain.val = BROWSER_COMPILED_DEFAULT_GAIN
  topo_edit_inserted.val = false
}
```

The `reset_phase()` function in `browser.mbt` continues to call each `reset_<variant>()` explicitly — explicit is clearer than iterating a registry for seven known variants.

## Invariants

The refactor must preserve these contracts:

- **All-or-nothing init.** After `ensure` returns `true`, the slot's `graph`, `context`, output buffer(s), `sample_rate`, and `block_size` are all consistent with the requested rate/block. After `ensure` returns `false`, the slot matches the post-`reset` state (all refs cleared). There is no intermediate state observable to callers. This is why `ensure` allocates output *before* publishing graph/context.
- **Compile closures are side-effect free.** The `compile : (DspContext) -> T?` closure must only construct the graph; it must not mutate external state, log, or depend on anything other than its argument. Re-running on rate/block change must be idempotent.
- **Single-threaded access per variant.** Unchanged from today — documented in `browser/browser.mbt:1`. Any overlap between `init`/`reset`/`queue`/`set` and `process` on the same slot remains undefined behavior; this refactor neither improves nor regresses that contract.
- **Wasm ABI stable.** Every `pub fn` currently exported to JavaScript keeps its name and signature.

## Verification

- **Type check:** `moon check && moon test` passes across all packages.
- **WASM export gate:** `browser/moon.pkg` lists every symbol exposed to JavaScript. Diff before and after the refactor — it MUST show zero changes to exported names. This is a stricter check than "does it compile" and catches accidental rename/removal of a public wrapper.
- **Playwright suite:** the existing browser integration tests exercise every wasm export and must continue to pass without modification. They are the primary behavioral check.
- **WASM build:** `moon build --target wasm-gc` produces a working bundle that loads in the browser demo.
- **Manual browser smoke test:** open `web/index.html` after deploying, confirm the existing demo behaviors (mono oscillator, hot-swap crossfade, topology edit, stereo pan, scheduler drums) still work.
- **LOC and file counts:** measure `browser/` before and after. Expected outcome: roughly 30–40% reduction in `browser/` LOC, one new file (`slot.mbt`), seven variant files stay but shrink substantially.

## Rollout approach

Single bundled PR. The refactor is mechanical once `slot.mbt` exists; splitting it into per-variant PRs would create churn without reducing risk (the Playwright suite is the safety net, not incremental review).

Suggested implementation order inside the PR:

1. Add `browser/slot.mbt` with the three types and the trait. Move `checked_sample` from `browser.mbt`. Confirm `moon check` passes.
2. Convert `browser_compiled.mbt` end-to-end — validates the `MonoOut` + simple-controls shape. Run Playwright tests.
3. Convert `browser_stereo.mbt` end-to-end — validates the `StereoOut` shape. Run Playwright tests. Together steps 2–3 catch any `MonoOut`/`StereoOut` mistakes before bulk conversion.
4. Convert the remaining five variants in sequence, running `moon check` after each file per the Incremental Edit Rule.
5. Diff `browser/moon.pkg` against the pre-refactor baseline — confirm zero changes to exported symbols.
6. Run `moon info && moon fmt && moon test`.
7. Playwright sweep + manual browser smoke test.

Note: `bounded_feedback_gain` in `browser.mbt:165` stays — it is still called by `browser_stereo.mbt:48`, not duplicated scaffolding. No deletion step for it.

## Risks

- **Closure capture in `compile : (@lib.DspContext) -> T?`.** The closure object allocates once when the top-level slot is constructed, not on every `ensure` call. Allocations inside the closure body happen only on rebuild, matching today's behavior. wasm-gc tolerates function fields. Keep captures small — the DSP constants referenced inside are module-level `const`s, not heap values.
- **The `graph_val()` / `ctx_val()` helpers unwrap without checking.** This preserves the current contract: callers always call `ensure` first. A mis-ordered call still panics, same as today. No regression.
- **Scheduler variant diverges further.** After this refactor, `browser_scheduler.mbt` is the lone copy-paste holdout. That is a known tradeoff — documented as out of scope.
- **Alternative considered and rejected: swap `@ref.Ref`s for `mut` struct fields.** Would simplify the slot further but is a larger semantic shift than "dedupe existing scaffolding." Keeping refs preserves the current mutation pattern for an easier review.

## Success criteria

- All existing `moon test` and Playwright tests pass unchanged.
- `browser/` shrinks by roughly 30–40%.
- Every uniform-signature lifecycle method (`ensure`, `reset`, `allocate`) exists in exactly one place.
- Type-safe sample accessors: `stereo.output.sample(i)` would fail to compile; the current copy-paste bug class is eliminated.
