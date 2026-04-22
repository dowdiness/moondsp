# Browser Slot Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace seven copy-pasted `browser/` graph-variant files with a shared `GraphSlot[T, O]` + `Output` capability trait, preserving every wasm export byte-for-byte.

**Architecture:** Introduce `browser/slot.mbt` holding a generic slot struct that encapsulates the five-Ref lifecycle scaffolding (graph, context, output, sample_rate, block_size). Mono and stereo output shapes are two concrete structs implementing a two-method capability trait (`reset`, `allocate`). Each variant file shrinks to a single `GraphSlot` global plus thin public wasm-export wrappers. Variant-specific extras (gain, inserted flag, etc.) stay as module-level `@ref.Ref`s next to their use sites. `browser_scheduler.mbt` is out of scope.

**Tech Stack:** MoonBit (wasm-gc target), Playwright (browser integration tests), `moon` CLI (check/test/build/info/fmt).

**Design spec:** `docs/superpowers/specs/2026-04-17-browser-slot-refactor-design.md`

**Pre-flight:** Ensure working tree is clean and you're on a dedicated branch.

```bash
git status        # expect clean
git checkout -b refactor/browser-slot
```

---

## Task 1: Create `browser/slot.mbt` scaffolding

**Files:**
- Create: `browser/slot.mbt`

**Safety net:** Playwright tests remain the behavioral check. This task adds code but doesn't yet change any variant, so type-check is the gate.

- [ ] **Step 1: Write `browser/slot.mbt`**

```moonbit
///|
/// Shared lifecycle scaffolding for browser graph variants.
///
/// `Output` is a two-method capability trait — the only methods whose
/// signatures are uniform across mono and stereo. Structurally-different
/// sample accessors and buffer getters live on concrete `MonoOut` /
/// `StereoOut` types, preserving compile-time shape safety.

///|
priv trait Output {
  reset(Self) -> Unit
  allocate(Self, block_size : Int) -> Unit
}

///|
/// Single-buffer output used by mono graph variants.
priv struct MonoOut {
  buffer : @ref.Ref[@lib.AudioBuffer?]

  fn new() -> MonoOut
}

///|
fn MonoOut::new() -> MonoOut {
  { buffer: @ref.new(None) }
}

///|
impl Output for MonoOut with reset(self) {
  self.buffer.val = None
}

///|
impl Output for MonoOut with allocate(self, n) {
  self.buffer.val = Some(@lib.AudioBuffer::filled(n))
}

///|
/// Concrete mono API — NOT on the trait.
fn MonoOut::get(self : MonoOut) -> @lib.AudioBuffer {
  self.buffer.val.unwrap()
}

///|
fn MonoOut::sample(self : MonoOut, index : Int) -> Double {
  checked_sample(index, self.buffer.val)
}

///|
/// Paired-buffer output used by stereo graph variants.
priv struct StereoOut {
  left : @ref.Ref[@lib.AudioBuffer?]
  right : @ref.Ref[@lib.AudioBuffer?]

  fn new() -> StereoOut
}

///|
fn StereoOut::new() -> StereoOut {
  { left: @ref.new(None), right: @ref.new(None) }
}

///|
impl Output for StereoOut with reset(self) {
  self.left.val = None
  self.right.val = None
}

///|
impl Output for StereoOut with allocate(self, n) {
  self.left.val = Some(@lib.AudioBuffer::filled(n))
  self.right.val = Some(@lib.AudioBuffer::filled(n))
}

///|
/// Concrete stereo API — NOT on the trait. Type-safe: calling
/// `mono.left_sample(i)` would fail to compile.
fn StereoOut::left_buf(self : StereoOut) -> @lib.AudioBuffer {
  self.left.val.unwrap()
}

///|
fn StereoOut::right_buf(self : StereoOut) -> @lib.AudioBuffer {
  self.right.val.unwrap()
}

///|
fn StereoOut::left_sample(self : StereoOut, index : Int) -> Double {
  checked_sample(index, self.left.val)
}

///|
fn StereoOut::right_sample(self : StereoOut, index : Int) -> Double {
  checked_sample(index, self.right.val)
}

///|
/// Generic slot parameterised by graph type `T` and output shape `O`.
/// Holds the uniform 5-Ref scaffolding and drives rate/block caching.
priv struct GraphSlot[T, O] {
  graph : @ref.Ref[T?]
  context : @ref.Ref[@lib.DspContext?]
  output : O
  sample_rate : @ref.Ref[Double]
  block_size : @ref.Ref[Int]
  compile : (@lib.DspContext) -> T?

  fn[T, O] new(output~ : O, compile~ : (@lib.DspContext) -> T?) -> GraphSlot[T, O]
}

///|
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

///|
/// Ensure the slot is initialized for the given rate/block.
/// Returns true iff the slot is now ready to `process`.
///
/// Invariant: after `ensure` returns true, graph/context/output/rate/block
/// are all consistent. After it returns false, the slot is reset.
/// Allocation happens BEFORE publishing graph/context so that a failing
/// allocator leaves the slot cleared rather than half-initialized.
fn[T, O : Output] GraphSlot::ensure(
  self : GraphSlot[T, O],
  rate : Double,
  block : Int,
) -> Bool {
  if rate <= 0.0 || block <= 0 {
    self.reset()
    return false
  }
  if self.graph.val is Some(_) &&
    self.sample_rate.val == rate &&
    self.block_size.val == block {
    return true
  }
  let ctx = @lib.DspContext::new(rate, block)
  match (self.compile)(ctx) {
    Some(g) => {
      self.output.allocate(block)
      self.graph.val = Some(g)
      self.context.val = Some(ctx)
      self.sample_rate.val = rate
      self.block_size.val = block
      true
    }
    None => {
      self.reset()
      false
    }
  }
}

///|
fn[T, O : Output] GraphSlot::reset(self : GraphSlot[T, O]) -> Unit {
  self.graph.val = None
  self.context.val = None
  self.output.reset()
  self.sample_rate.val = 0.0
  self.block_size.val = 0
}

///|
fn[T, O] GraphSlot::graph_val(self : GraphSlot[T, O]) -> T {
  self.graph.val.unwrap()
}

///|
fn[T, O] GraphSlot::ctx_val(self : GraphSlot[T, O]) -> @lib.DspContext {
  self.context.val.unwrap()
}

///|
/// Bounds-checked sample read from an optional buffer. Returns 0.0
/// for out-of-bounds indices or uninitialized buffers. Shared by
/// `MonoOut::sample` / `StereoOut::*_sample` and the scheduler file.
fn checked_sample(index : Int, output : @lib.AudioBuffer?) -> Double {
  match output {
    Some(buffer) =>
      if index >= 0 && index < buffer.length() {
        buffer.get(index)
      } else {
        0.0
      }
    None => 0.0
  }
}
```

- [ ] **Step 2: Delete the duplicate `checked_sample` from `browser/browser.mbt`**

`slot.mbt` now defines `checked_sample`; leaving the copy in `browser.mbt` would produce a duplicate-definition error at compile time. Delete the old one before type-checking.

First, reread `browser/browser.mbt:143-175` to locate the exact block. The `// Shared helpers` section header and `bounded_feedback_gain` must stay — only the `checked_sample` block and its `///|` separator are removed.

Use `Edit` to replace this block:

```moonbit
///|
/// Bounds-checked sample read from an optional buffer.
/// Shared by all mono and stereo output_sample functions.
/// Returns 0.0 for out-of-bounds indices or uninitialized buffers.
fn checked_sample(index : Int, output : @lib.AudioBuffer?) -> Double {
  match output {
    Some(buffer) =>
      if index >= 0 && index < buffer.length() {
        buffer.get(index)
      } else {
        0.0
      }
    None => 0.0
  }
}

///|
/// Clamp gain to safe feedback range, replacing NaN/Inf with default.
fn bounded_feedback_gain(gain : Double) -> Double {
```

with:

```moonbit
///|
/// Clamp gain to safe feedback range, replacing NaN/Inf with default.
fn bounded_feedback_gain(gain : Double) -> Double {
```

- [ ] **Step 3: Type-check**

```bash
moon check 2>&1 | tail -20
```

Expected: no errors. `MonoOut::get`, `StereoOut::left_buf`, `GraphSlot::graph_val`, etc. will show as unused warnings — that's expected (no variant file calls them yet). Proceed.

- [ ] **Step 4: Run tests**

```bash
moon test 2>&1 | tail -10
```

Expected: all 470 tests pass. This is a sanity check that we haven't broken `lib/`, `graph/`, or any other downstream package.

- [ ] **Step 5: Commit**

```bash
git add browser/slot.mbt browser/browser.mbt
git commit -m "$(cat <<'EOF'
refactor(browser): add GraphSlot scaffolding and move checked_sample

Creates browser/slot.mbt with the Output capability trait, MonoOut,
StereoOut, and the generic GraphSlot[T, O] — shared lifecycle for the
seven browser graph variants.

No variant files converted yet; follow-up commits convert them one at
a time. Moves checked_sample from browser.mbt into slot.mbt since the
sample accessors that will call it now live on MonoOut / StereoOut.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Convert `browser_compiled.mbt` (simplest mono variant)

**Files:**
- Modify: `browser/browser_compiled.mbt` (full rewrite)

**Why this first:** smallest mono variant, proves `MonoOut` plumbing and `apply_controls` batch pattern end-to-end.

- [ ] **Step 1: Replace the entire contents of `browser/browser_compiled.mbt`**

```moonbit
///|
let compiled : GraphSlot[@lib.CompiledDsp, MonoOut] = GraphSlot::new(
  output=MonoOut::new(),
  compile=fn(ctx) {
    @lib.CompiledDsp::compile(
      [
        @lib.DspNode::oscillator(
          @lib.Waveform::Triangle,
          BROWSER_COMPILED_DEFAULT_FREQ,
        ),
        @lib.DspNode::gain(0, BROWSER_COMPILED_DEFAULT_GAIN),
        @lib.DspNode::clip(1, BROWSER_COMPILED_CLIP_THRESHOLD),
        @lib.DspNode::output(2),
      ],
      ctx,
    )
  },
)

///|
/// Initialize the browser proof graph that runs through `CompiledDsp`.
pub fn init_compiled_graph(sample_rate : Double, block_size : Int) -> Bool {
  compiled.ensure(sample_rate, block_size)
}

///|
/// Run one render quantum through the browser proof `CompiledDsp` graph.
pub fn process_compiled_block(
  freq : Double,
  gain : Double,
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  if !compiled.ensure(sample_rate, block_size) {
    return false
  }
  let graph = compiled.graph_val()
  if !graph.apply_controls([
      @lib.GraphControl::set_param(0, @lib.GraphParamSlot::Value0, freq),
      @lib.GraphControl::set_param(1, @lib.GraphParamSlot::Value0, gain),
    ]) {
    return false
  }
  graph.process(compiled.ctx_val(), compiled.output.get())
  true
}

///|
/// Read one sample from the most recent compiled browser output block.
pub fn compiled_output_sample(index : Int) -> Double {
  compiled.output.sample(index)
}

///|
fn reset_compiled_graph() -> Unit {
  compiled.reset()
}
```

- [ ] **Step 2: Type-check**

```bash
moon check 2>&1 | tail -10
```

Expected: no errors. The call to `reset_compiled_graph()` from `browser/browser.mbt:117` continues to resolve.

- [ ] **Step 3: Run MoonBit test suite**

```bash
moon test 2>&1 | tail -5
```

Expected: 470 tests pass.

- [ ] **Step 4: Run Playwright tests (safety net — full run)**

```bash
npm run test:browser 2>&1 | tail -30
```

Expected: every Playwright test passes. If anything fails here, STOP and diagnose — the refactor must preserve behavior byte-for-byte on the JS side.

- [ ] **Step 5: Commit**

```bash
git add browser/browser_compiled.mbt
git commit -m "$(cat <<'EOF'
refactor(browser): convert browser_compiled.mbt to GraphSlot

First variant converted. Validates MonoOut + GraphSlot plumbing on the
simplest mono shape. Playwright suite passes; no JS-visible change.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Convert `browser_stereo.mbt` (simplest stereo variant)

**Files:**
- Modify: `browser/browser_stereo.mbt` (full rewrite)

**Why this second:** validates `StereoOut` plumbing and the stereo `process(ctx, left, right)` call shape. Between Tasks 2 and 3 we've now exercised both output shapes; remaining tasks are routine.

- [ ] **Step 1: Replace the entire contents of `browser/browser_stereo.mbt`**

```moonbit
///|
let compiled_stereo : GraphSlot[@lib.CompiledStereoDsp, StereoOut] = GraphSlot::new(
  output=StereoOut::new(),
  compile=fn(ctx) {
    @lib.CompiledStereoDsp::compile(
      [
        @lib.DspNode::constant(1.0),
        @lib.DspNode::oscillator(
          @lib.Waveform::Sine,
          BROWSER_COMPILED_DEFAULT_FREQ,
        ),
        @lib.DspNode::gain(1, BROWSER_COMPILED_OSC_GAIN),
        @lib.DspNode::mix(0, 2),
        @lib.DspNode::mix(3, 5),
        @lib.DspNode::gain(4, BROWSER_COMPILED_DEFAULT_GAIN),
        @lib.DspNode::pan(5, BROWSER_COMPILED_DEFAULT_PAN),
        @lib.DspNode::stereo_delay(
          6,
          BROWSER_COMPILED_DELAY_CAPACITY,
          delay_samples=BROWSER_COMPILED_DELAY_SAMPLES,
        ),
        @lib.DspNode::stereo_biquad(
          7,
          @lib.BiquadMode::LowPass,
          BROWSER_COMPILED_DEFAULT_CUTOFF,
          BROWSER_COMPILED_FILTER_Q,
        ),
        @lib.DspNode::stereo_clip(8, BROWSER_COMPILED_CLIP_THRESHOLD),
        @lib.DspNode::stereo_output(9),
      ],
      ctx,
    )
  },
)

///|
/// Initialize the browser proof graph that runs through `CompiledStereoDsp`.
pub fn init_compiled_stereo_graph(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  compiled_stereo.ensure(sample_rate, block_size)
}

///|
/// Run one render quantum through the browser proof `CompiledStereoDsp` graph.
pub fn process_compiled_stereo_block(
  freq : Double,
  gain : Double,
  pan : Double,
  delay_samples : Double,
  cutoff : Double,
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  if !compiled_stereo.ensure(sample_rate, block_size) {
    return false
  }
  let graph = compiled_stereo.graph_val()
  if !graph.apply_controls([
      @lib.GraphControl::set_param(1, @lib.GraphParamSlot::Value0, freq),
      @lib.GraphControl::set_param(
        5,
        @lib.GraphParamSlot::Value0,
        bounded_feedback_gain(gain),
      ),
      @lib.GraphControl::set_param(6, @lib.GraphParamSlot::Value0, pan),
      @lib.GraphControl::set_param(
        7,
        @lib.GraphParamSlot::DelaySamples,
        delay_samples,
      ),
      @lib.GraphControl::set_param(8, @lib.GraphParamSlot::Value0, cutoff),
    ]) {
    return false
  }
  graph.process(
    compiled_stereo.ctx_val(),
    compiled_stereo.output.left_buf(),
    compiled_stereo.output.right_buf(),
  )
  true
}

///|
/// Read one sample from the most recent compiled stereo left block.
pub fn compiled_stereo_left_sample(index : Int) -> Double {
  compiled_stereo.output.left_sample(index)
}

///|
/// Read one sample from the most recent compiled stereo right block.
pub fn compiled_stereo_right_sample(index : Int) -> Double {
  compiled_stereo.output.right_sample(index)
}

///|
fn reset_compiled_stereo_graph() -> Unit {
  compiled_stereo.reset()
}
```

- [ ] **Step 2: Type-check**

```bash
moon check 2>&1 | tail -10
```

Expected: no errors.

- [ ] **Step 3: Run MoonBit tests**

```bash
moon test 2>&1 | tail -5
```

Expected: 470 tests pass.

- [ ] **Step 4: Run Playwright tests**

```bash
npm run test:browser 2>&1 | tail -30
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add browser/browser_stereo.mbt
git commit -m "$(cat <<'EOF'
refactor(browser): convert browser_stereo.mbt to GraphSlot

Validates StereoOut + stereo process(ctx, left, right) shape.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Convert `browser_hot_swap.mbt` (mono + queue pattern)

**Files:**
- Modify: `browser/browser_hot_swap.mbt` (full rewrite)

**Note:** the `queue_*` function reaches into the slot's `graph.val` to call `hot_swap.queue_swap(replacement)`. It returns `false` if the slot hasn't been initialized.

- [ ] **Step 1: Replace the entire contents of `browser/browser_hot_swap.mbt`**

```moonbit
///|
let compiled_hot_swap : GraphSlot[@lib.CompiledDspHotSwap, MonoOut] = GraphSlot::new(
  output=MonoOut::new(),
  compile=fn(ctx) {
    match
      @lib.CompiledDsp::compile(
        [
          @lib.DspNode::constant(BROWSER_HOT_SWAP_OLD_CONSTANT),
          @lib.DspNode::output(0),
        ],
        ctx,
      ) {
      Some(active) =>
        Some(
          @lib.CompiledDspHotSwap::from_graph(
            active,
            crossfade_samples=BROWSER_HOT_SWAP_CROSSFADE_SAMPLES,
          ),
        )
      None => None
    }
  },
)

///|
/// Initialize the browser proof graph that runs through `CompiledDspHotSwap`.
pub fn init_compiled_hot_swap_graph(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  compiled_hot_swap.ensure(sample_rate, block_size)
}

///|
/// Queue the fixed browser hot-swap replacement graph.
pub fn queue_compiled_hot_swap() -> Bool {
  let ctx = match compiled_hot_swap.context.val {
    Some(c) => c
    None => return false
  }
  let hot_swap = match compiled_hot_swap.graph.val {
    Some(h) => h
    None => return false
  }
  let replacement = match
    @lib.CompiledDsp::compile(
      [
        @lib.DspNode::constant(BROWSER_HOT_SWAP_NEW_CONSTANT),
        @lib.DspNode::output(0),
      ],
      ctx,
    ) {
    Some(r) => r
    None => return false
  }
  hot_swap.queue_swap(replacement)
}

///|
/// Run one render quantum through the browser proof `CompiledDspHotSwap` graph.
pub fn process_compiled_hot_swap_block(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  if !compiled_hot_swap.ensure(sample_rate, block_size) {
    return false
  }
  let hot_swap = compiled_hot_swap.graph_val()
  hot_swap.process(compiled_hot_swap.ctx_val(), compiled_hot_swap.output.get())
  true
}

///|
/// Read one sample from the most recent hot-swap browser output block.
pub fn compiled_hot_swap_output_sample(index : Int) -> Double {
  compiled_hot_swap.output.sample(index)
}

///|
fn reset_compiled_hot_swap_graph() -> Unit {
  compiled_hot_swap.reset()
}
```

- [ ] **Step 2: Type-check**

```bash
moon check 2>&1 | tail -10
```

Expected: no errors.

- [ ] **Step 3: Run MoonBit tests**

```bash
moon test 2>&1 | tail -5
```

Expected: 470 tests pass.

- [ ] **Step 4: Commit**

```bash
git add browser/browser_hot_swap.mbt
git commit -m "refactor(browser): convert browser_hot_swap.mbt to GraphSlot

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Convert `browser_stereo_hot_swap.mbt`

**Files:**
- Modify: `browser/browser_stereo_hot_swap.mbt` (full rewrite)

- [ ] **Step 1: Replace the entire contents of `browser/browser_stereo_hot_swap.mbt`**

```moonbit
///|
let compiled_stereo_hot_swap : GraphSlot[@lib.CompiledStereoDspHotSwap, StereoOut] = GraphSlot::new(
  output=StereoOut::new(),
  compile=fn(ctx) {
    match
      @lib.CompiledStereoDsp::compile(
        [
          @lib.DspNode::constant(BROWSER_STEREO_HOT_SWAP_OLD_CONSTANT),
          @lib.DspNode::pan(0, 0.0),
          @lib.DspNode::stereo_output(1),
        ],
        ctx,
      ) {
      Some(active) =>
        Some(
          @lib.CompiledStereoDspHotSwap::from_graph(
            active,
            crossfade_samples=BROWSER_STEREO_HOT_SWAP_CROSSFADE_SAMPLES,
          ),
        )
      None => None
    }
  },
)

///|
/// Initialize the browser proof graph that runs through `CompiledStereoDspHotSwap`.
pub fn init_compiled_stereo_hot_swap_graph(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  compiled_stereo_hot_swap.ensure(sample_rate, block_size)
}

///|
/// Queue the fixed browser stereo hot-swap replacement graph.
pub fn queue_compiled_stereo_hot_swap() -> Bool {
  let ctx = match compiled_stereo_hot_swap.context.val {
    Some(c) => c
    None => return false
  }
  let hot_swap = match compiled_stereo_hot_swap.graph.val {
    Some(h) => h
    None => return false
  }
  let replacement = match
    @lib.CompiledStereoDsp::compile(
      [
        @lib.DspNode::constant(BROWSER_STEREO_HOT_SWAP_NEW_CONSTANT),
        @lib.DspNode::pan(0, 0.0),
        @lib.DspNode::stereo_output(1),
      ],
      ctx,
    ) {
    Some(r) => r
    None => return false
  }
  hot_swap.queue_swap(replacement)
}

///|
/// Run one render quantum through the browser proof `CompiledStereoDspHotSwap` graph.
pub fn process_compiled_stereo_hot_swap_block(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  if !compiled_stereo_hot_swap.ensure(sample_rate, block_size) {
    return false
  }
  let hot_swap = compiled_stereo_hot_swap.graph_val()
  hot_swap.process(
    compiled_stereo_hot_swap.ctx_val(),
    compiled_stereo_hot_swap.output.left_buf(),
    compiled_stereo_hot_swap.output.right_buf(),
  )
  true
}

///|
/// Read one sample from the most recent stereo hot-swap browser left block.
pub fn compiled_stereo_hot_swap_left_sample(index : Int) -> Double {
  compiled_stereo_hot_swap.output.left_sample(index)
}

///|
/// Read one sample from the most recent stereo hot-swap browser right block.
pub fn compiled_stereo_hot_swap_right_sample(index : Int) -> Double {
  compiled_stereo_hot_swap.output.right_sample(index)
}

///|
fn reset_compiled_stereo_hot_swap_graph() -> Unit {
  compiled_stereo_hot_swap.reset()
}
```

- [ ] **Step 2: Type-check + tests**

```bash
moon check 2>&1 | tail -5
moon test 2>&1 | tail -5
```

Expected: no errors, 470 tests pass.

- [ ] **Step 3: Commit**

```bash
git add browser/browser_stereo_hot_swap.mbt
git commit -m "refactor(browser): convert browser_stereo_hot_swap.mbt to GraphSlot

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Convert `browser_topology_edit.mbt` (mono + extras)

**Files:**
- Modify: `browser/browser_topology_edit.mbt` (full rewrite)

**Extras:** `topo_edit_gain : Ref[Double]`, `topo_edit_inserted : Ref[Bool]` — stay as module-level globals alongside the slot. `reset_compiled_topology_edit_graph` resets both.

- [ ] **Step 1: Replace the entire contents of `browser/browser_topology_edit.mbt`**

```moonbit
///|
let topo_edit_gain : @ref.Ref[Double] = @ref.new(BROWSER_COMPILED_DEFAULT_GAIN)

///|
let topo_edit_inserted : @ref.Ref[Bool] = @ref.new(false)

///|
let compiled_topology_edit : GraphSlot[
  @lib.CompiledDspTopologyController,
  MonoOut,
] = GraphSlot::new(
  output=MonoOut::new(),
  compile=fn(ctx) {
    @lib.CompiledDspTopologyController::from_nodes(
      [
        @lib.DspNode::constant(BROWSER_COMPILED_DEFAULT_GAIN),
        @lib.DspNode::output(0),
      ],
      ctx,
      crossfade_samples=BROWSER_TOPOLOGY_EDIT_CROSSFADE_SAMPLES,
    )
  },
)

///|
/// Initialize the browser proof graph that runs through
/// `CompiledDspTopologyController`.
pub fn init_compiled_topology_edit_graph(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  compiled_topology_edit.ensure(sample_rate, block_size)
}

///|
/// Queue the fixed browser topology edit insertion that appends one gain node
/// before the output.
pub fn queue_compiled_topology_edit() -> Bool {
  let topology = match compiled_topology_edit.graph.val {
    Some(t) => t
    None => return false
  }
  if topo_edit_inserted.val {
    return false
  }
  let queued = topology.queue_topology_edit(
    @lib.GraphTopologyEdit::insert_node(
      1,
      @lib.GraphTopologyInputSlot::Input0,
      @lib.DspNode::gain(0, BROWSER_TOPOLOGY_EDIT_INSERTED_GAIN),
    ),
  )
  if queued {
    topo_edit_inserted.val = true
  }
  queued
}

///|
/// Queue the fixed browser topology edit deletion that removes the inserted
/// gain node and returns to the baseline graph.
pub fn queue_compiled_topology_delete_edit() -> Bool {
  let topology = match compiled_topology_edit.graph.val {
    Some(t) => t
    None => return false
  }
  if !topo_edit_inserted.val {
    return false
  }
  let queued = topology.queue_topology_edit(
    @lib.GraphTopologyEdit::delete_node(2, 1, @lib.GraphTopologyInputSlot::Input0, 2),
  )
  if queued {
    topo_edit_inserted.val = false
  }
  queued
}

///|
/// Update the fixed browser topology-edit gain control.
pub fn set_compiled_topology_edit_gain(gain : Double) -> Bool {
  if compiled_topology_edit.graph.val is None {
    return false
  }
  topo_edit_gain.val = gain
  true
}

///|
/// Run one render quantum through the browser proof
/// `CompiledDspTopologyController` graph.
pub fn process_compiled_topology_edit_block(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  if !compiled_topology_edit.ensure(sample_rate, block_size) {
    return false
  }
  let topology = compiled_topology_edit.graph_val()
  if !topology.apply_control(
      @lib.GraphControl::set_param(
        0,
        @lib.GraphParamSlot::Value0,
        topo_edit_gain.val,
      ),
    ) {
    return false
  }
  topology.process(
    compiled_topology_edit.ctx_val(),
    compiled_topology_edit.output.get(),
  )
  true
}

///|
/// Read one sample from the most recent topology-edit browser output block.
pub fn compiled_topology_edit_output_sample(index : Int) -> Double {
  compiled_topology_edit.output.sample(index)
}

///|
fn reset_compiled_topology_edit_graph() -> Unit {
  compiled_topology_edit.reset()
  topo_edit_gain.val = BROWSER_COMPILED_DEFAULT_GAIN
  topo_edit_inserted.val = false
}
```

- [ ] **Step 2: Type-check + tests**

```bash
moon check 2>&1 | tail -5
moon test 2>&1 | tail -5
```

Expected: no errors, 470 tests pass.

- [ ] **Step 3: Commit**

```bash
git add browser/browser_topology_edit.mbt
git commit -m "refactor(browser): convert browser_topology_edit.mbt to GraphSlot

Extras (gain, inserted flag) stay as module-level refs alongside the
slot. reset_compiled_topology_edit_graph handles both.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Convert `browser_stereo_topology_edit.mbt` (stereo + level extra)

**Files:**
- Modify: `browser/browser_stereo_topology_edit.mbt` (full rewrite)

**Extras:** `stereo_topo_edit_level : Ref[Double]`.

- [ ] **Step 1: Replace the entire contents of `browser/browser_stereo_topology_edit.mbt`**

```moonbit
///|
let stereo_topo_edit_level : @ref.Ref[Double] = @ref.new(1.0)

///|
let compiled_stereo_topology_edit : GraphSlot[
  @lib.CompiledStereoDspTopologyController,
  StereoOut,
] = GraphSlot::new(
  output=StereoOut::new(),
  compile=fn(ctx) {
    @lib.CompiledStereoDspTopologyController::from_nodes(
      [
        @lib.DspNode::constant(1.0),
        @lib.DspNode::pan(0, BROWSER_STEREO_TOPOLOGY_EDIT_OLD_PAN),
        @lib.DspNode::stereo_output(1),
      ],
      ctx,
      crossfade_samples=BROWSER_STEREO_TOPOLOGY_EDIT_CROSSFADE_SAMPLES,
    )
  },
)

///|
/// Initialize the browser proof graph that runs through
/// `CompiledStereoDspTopologyController`.
pub fn init_compiled_stereo_topology_edit_graph(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  compiled_stereo_topology_edit.ensure(sample_rate, block_size)
}

///|
/// Queue the fixed browser stereo topology edit that replaces the pan node.
/// WHY no idempotency guard (unlike mono topology_edit's `inserted` bool):
/// replace_node is inherently idempotent — replacing with the same node is a no-op.
pub fn queue_compiled_stereo_topology_edit() -> Bool {
  let topology = match compiled_stereo_topology_edit.graph.val {
    Some(t) => t
    None => return false
  }
  topology.queue_topology_edit(
    @lib.GraphTopologyEdit::replace_node(
      1,
      @lib.DspNode::pan(0, BROWSER_STEREO_TOPOLOGY_EDIT_NEW_PAN),
    ),
  )
}

///|
/// Update the fixed browser stereo topology-edit level control.
pub fn set_compiled_stereo_topology_edit_level(level : Double) -> Bool {
  if compiled_stereo_topology_edit.graph.val is None {
    return false
  }
  stereo_topo_edit_level.val = level
  true
}

///|
/// Run one render quantum through the browser proof
/// `CompiledStereoDspTopologyController` graph.
pub fn process_compiled_stereo_topology_edit_block(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  if !compiled_stereo_topology_edit.ensure(sample_rate, block_size) {
    return false
  }
  let topology = compiled_stereo_topology_edit.graph_val()
  if !topology.apply_control(
      @lib.GraphControl::set_param(
        0,
        @lib.GraphParamSlot::Value0,
        stereo_topo_edit_level.val,
      ),
    ) {
    return false
  }
  topology.process(
    compiled_stereo_topology_edit.ctx_val(),
    compiled_stereo_topology_edit.output.left_buf(),
    compiled_stereo_topology_edit.output.right_buf(),
  )
  true
}

///|
/// Read one sample from the most recent stereo topology-edit browser left block.
pub fn compiled_stereo_topology_edit_left_sample(index : Int) -> Double {
  compiled_stereo_topology_edit.output.left_sample(index)
}

///|
/// Read one sample from the most recent stereo topology-edit browser right block.
pub fn compiled_stereo_topology_edit_right_sample(index : Int) -> Double {
  compiled_stereo_topology_edit.output.right_sample(index)
}

///|
fn reset_compiled_stereo_topology_edit_graph() -> Unit {
  compiled_stereo_topology_edit.reset()
  stereo_topo_edit_level.val = 1.0
}
```

- [ ] **Step 2: Type-check + tests**

```bash
moon check 2>&1 | tail -5
moon test 2>&1 | tail -5
```

Expected: no errors, 470 tests pass.

- [ ] **Step 3: Commit**

```bash
git add browser/browser_stereo_topology_edit.mbt
git commit -m "refactor(browser): convert browser_stereo_topology_edit.mbt to GraphSlot

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Convert `browser_exit_deliverable.mbt` (mono + three setters)

**Files:**
- Modify: `browser/browser_exit_deliverable.mbt` (full rewrite)

**Extras:** `exit_lfo_rate`, `exit_cutoff`, `exit_gain` — all `Ref[Double]`. The graph is built from `@lib.exit_deliverable()` (a tagless builder), not a hand-authored node list.

- [ ] **Step 1: Replace the entire contents of `browser/browser_exit_deliverable.mbt`**

```moonbit
///|
// WHY this map: node indices are positional after GraphBuilder flattening.
// apply_control targets nodes by index, so this map is needed to aim correctly.
// [0] Constant(2.0)       — LFO rate
// [1] Oscillator(Sine)    — LFO
// [2] Constant(1.0)       — range offset
// [3] Mix(1,2)            — lfo + 1
// [4] Constant(100.0)     — range scale = 0.5*(hi-lo)
// [5] Mul(3,4)            — (lfo+1)*scale
// [6] Constant(200.0)     — range lo
// [7] Mix(5,6)            — modulated freq
// [8] Oscillator(Sine)    — carrier
// [9] Biquad(LowPass)     — filter
// [10] Gain(0.3)          — master gain
// [11] Output
const EXIT_LFO_RATE_NODE : Int = 0

///|
const EXIT_BIQUAD_NODE : Int = 9

///|
const EXIT_GAIN_NODE : Int = 10

///|
let exit_lfo_rate : @ref.Ref[Double] = @ref.new(2.0)

///|
let exit_cutoff : @ref.Ref[Double] = @ref.new(800.0)

///|
let exit_gain : @ref.Ref[Double] = @ref.new(0.3)

///|
let exit_deliverable : GraphSlot[@lib.CompiledDsp, MonoOut] = GraphSlot::new(
  output=MonoOut::new(),
  compile=fn(ctx) {
    let builder : @lib.GraphBuilder = @lib.exit_deliverable()
    @lib.CompiledDsp::compile(builder.nodes(), ctx)
  },
)

///|
/// Initialize the exit deliverable graph: FM synthesis via tagless composition.
pub fn init_exit_deliverable_graph(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  exit_deliverable.ensure(sample_rate, block_size)
}

///|
/// Set the LFO rate (Hz) for the exit deliverable.
pub fn set_exit_deliverable_lfo_rate(rate : Double) -> Bool {
  if rate.is_nan() || rate.is_inf() {
    return false
  }
  exit_lfo_rate.val = rate
  true
}

///|
/// Set the filter cutoff (Hz) for the exit deliverable.
pub fn set_exit_deliverable_cutoff(cutoff : Double) -> Bool {
  if cutoff.is_nan() || cutoff.is_inf() || cutoff < 0.0 {
    return false
  }
  exit_cutoff.val = cutoff
  true
}

///|
/// Set the master gain for the exit deliverable.
pub fn set_exit_deliverable_gain(gain : Double) -> Bool {
  if gain.is_nan() || gain.is_inf() || gain < 0.0 {
    return false
  }
  exit_gain.val = gain
  true
}

///|
/// Run one render quantum through the exit deliverable graph.
pub fn process_exit_deliverable_block(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  if !exit_deliverable.ensure(sample_rate, block_size) {
    return false
  }
  let graph = exit_deliverable.graph_val()
  // Apply controls individually — batch is transactional and one failure
  // rejects all. Individual controls are independent.
  ignore(
    graph.apply_control(
      @lib.GraphControl::set_param(
        EXIT_LFO_RATE_NODE,
        @lib.GraphParamSlot::Value0,
        exit_lfo_rate.val,
      ),
    ),
  )
  ignore(
    graph.apply_control(
      @lib.GraphControl::set_param(
        EXIT_BIQUAD_NODE,
        @lib.GraphParamSlot::Value0,
        exit_cutoff.val,
      ),
    ),
  )
  ignore(
    graph.apply_control(
      @lib.GraphControl::set_param(
        EXIT_GAIN_NODE,
        @lib.GraphParamSlot::Value0,
        exit_gain.val,
      ),
    ),
  )
  graph.process(exit_deliverable.ctx_val(), exit_deliverable.output.get())
  true
}

///|
/// Read one sample from the most recent exit deliverable output block.
pub fn exit_deliverable_output_sample(index : Int) -> Double {
  exit_deliverable.output.sample(index)
}

///|
fn reset_exit_deliverable_graph() -> Unit {
  exit_deliverable.reset()
  exit_lfo_rate.val = 2.0
  exit_cutoff.val = 800.0
  exit_gain.val = 0.3
}
```

- [ ] **Step 2: Type-check + tests**

```bash
moon check 2>&1 | tail -5
moon test 2>&1 | tail -5
```

Expected: no errors, 470 tests pass.

- [ ] **Step 3: Commit**

```bash
git add browser/browser_exit_deliverable.mbt
git commit -m "refactor(browser): convert browser_exit_deliverable.mbt to GraphSlot

Last of seven target variants. browser_scheduler.mbt remains unchanged
(out of scope per spec).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Final verification

**Files:**
- Check (no modifications expected): `browser/moon.pkg`, `browser/pkg.generated.mbti`

- [ ] **Step 1: Confirm `browser/moon.pkg` export list is unchanged**

```bash
git diff main -- browser/moon.pkg 2>&1 | head -30
```

Expected: empty output. Every symbol in the `exports` list must be identical to what was there before the refactor.

- [ ] **Step 2: Regenerate `.mbti` interface and inspect the diff**

```bash
moon info 2>&1 | tail -5
git diff browser/pkg.generated.mbti 2>&1 | head -60
```

Expected: diff may show the new private `Output` trait and `GraphSlot` / `MonoOut` / `StereoOut` types (or nothing if they're fully private). Critically: **no changes to any `pub fn`** — that's the ABI gate. Review the diff line by line.

If any `pub fn` has changed signature, STOP and fix before proceeding.

- [ ] **Step 3: Format and re-check**

```bash
moon fmt 2>&1 | tail -5
moon check 2>&1 | tail -5
moon test 2>&1 | tail -5
```

Expected: `moon fmt` may reorganize whitespace; `moon check` and `moon test` both pass.

- [ ] **Step 4: Full Playwright sweep**

```bash
npm run test:browser 2>&1 | tail -30
```

Expected: every Playwright test passes. This is the authoritative behavioral verification.

- [ ] **Step 5: Manual browser smoke test**

```bash
./playwright-serve.sh &
SERVE_PID=$!
```

Open `http://localhost:8000/web/index.html` (or whatever the serve script advertises) in a browser. Confirm:

- The mono oscillator (`init_compiled_graph` → `process_compiled_block`) produces audio.
- Hot-swap crossfade works (queue button triggers crossfade).
- Topology edit insert/delete works.
- Stereo pan is audibly distinct left vs right.
- The scheduler drums still play (verifies we didn't break browser_scheduler.mbt by moving checked_sample).

Then stop the server:

```bash
kill $SERVE_PID 2>/dev/null || true
```

- [ ] **Step 6: Measure LOC change**

```bash
git diff --stat main -- browser/ 2>&1 | tail -15
```

Expected: `browser/` net LOC reduced by roughly 30–40% (spec target). If the reduction is dramatically less or more, investigate — it may indicate missed opportunities or accidental changes.

- [ ] **Step 7: Commit any formatting-only changes and regenerated `.mbti`**

```bash
git add browser/pkg.generated.mbti browser/
git status         # confirm only expected files staged
git commit -m "$(cat <<'EOF'
refactor(browser): regenerate .mbti and apply formatter

Final cleanup after variant conversions. No semantic changes.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

If `git status` shows nothing staged after `moon fmt`, skip the commit.

- [ ] **Step 8: Push and open PR**

```bash
git push -u origin refactor/browser-slot
gh pr create --title "refactor(browser): deduplicate graph-variant scaffolding via GraphSlot" --body "$(cat <<'EOF'
## Summary
- Introduce `browser/slot.mbt` with generic `GraphSlot[T, O]` + `Output` capability trait.
- Convert the seven simple browser graph variants to use it.
- Every wasm export name and signature is unchanged; `browser_scheduler.mbt` is out of scope.

Addresses audit §S2. Full design: `docs/superpowers/specs/2026-04-17-browser-slot-refactor-design.md`.

## Test plan
- [x] `moon check && moon test` — 470 tests pass
- [x] `npm run test:browser` — Playwright suite passes
- [x] `git diff main -- browser/moon.pkg` — zero changes to exports
- [x] Manual browser smoke test — all demo behaviors still work
- [x] `browser/` LOC reduced by ~30–40%

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-review checklist (for the plan author)

- Spec coverage: every section of `2026-04-17-browser-slot-refactor-design.md` maps to a task. `slot.mbt` creation (§Shared machinery) → Task 1. Each of the seven converted variants (§Variant file shape) → Tasks 2–8. Verification gates (§Verification) → Task 9. Invariants (all-or-nothing init, closures side-effect-free, ABI unchanged) are encoded in `slot.mbt` (Task 1) and checked by the moon.pkg diff (Task 9).
- Placeholder scan: no TBDs, no "TODO", no "similar to Task N" references — every file's full new contents are inline.
- Type consistency: method names used across tasks — `compiled.ensure`, `compiled.graph_val()`, `compiled.ctx_val()`, `compiled.output.get()`, `compiled.output.sample()`, `stereo.output.left_buf()`, `stereo.output.right_buf()`, `stereo.output.left_sample()`, `stereo.output.right_sample()` — all defined in Task 1 and used consistently in Tasks 2–8.
- Order of conversions: Task 2 (simplest mono) and Task 3 (simplest stereo) validate both `MonoOut` and `StereoOut` shapes before bulk conversion of Tasks 4–8, matching the spec's rollout note.
