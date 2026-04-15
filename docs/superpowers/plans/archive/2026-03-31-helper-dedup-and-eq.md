# Helper Dedup, Derive Eq, and DspNode Documentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate duplicated validation and sample-count helpers across DSP primitives, derive `Eq` for all simple enums to remove manual matching, and document the `DspNode` flat-struct design decision.

**Architecture:** Create `lib/util.mbt` with shared `is_finite`, `is_finite_positive`, and `effective_sample_count` functions. Replace per-file duplicates. Add `derive(Eq)` to all payload-less enums and delete `node_kind_matches`. Add a doc comment to the `DspNode` struct explaining why it uses a flat layout.

**Tech Stack:** MoonBit

---

### Task 1: Create shared validation helpers

**Files:**
- Create: `lib/util.mbt`

- [ ] **Step 1: Create `lib/util.mbt` with shared helpers**

```moonbit
///|
/// Check whether a floating-point value is finite (not NaN, not Inf).
pub fn is_finite(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
/// Check whether a floating-point value is finite and strictly positive.
pub fn is_finite_positive(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf() && value > 0.0
}

///|
/// Compute the effective number of samples to process, bounded by both
/// the context block size and the buffer length.
pub fn effective_sample_count(
  context : DspContext,
  buffer : AudioBuffer,
) -> Int {
  if buffer.length() < context.block_size() {
    buffer.length()
  } else {
    context.block_size()
  }
}
```

- [ ] **Step 2: Run `moon check`**

Run: `moon check 2>&1`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/util.mbt
git commit -m "feat: add shared is_finite, is_finite_positive, effective_sample_count helpers"
```

---

### Task 2: Replace duplicated is_finite validators

**Files:**
- Modify: `lib/filter.mbt` (delete `is_finite` at line 193, replace usages)
- Modify: `lib/osc.mbt` (delete `is_valid_osc_param` at line 129, replace usages)
- Modify: `lib/smooth.mbt` (delete `is_valid_param_value` at line 117, replace usages)
- Modify: `lib/pan.mbt` (delete `is_valid_pan_position` at line 79, replace usages)
- Modify: `lib/graph.mbt` (delete `valid_finite_value` at line 2484, replace usages)

These 5 functions all check `!value.is_nan() && !value.is_inf()` — identical to `is_finite`.

- [ ] **Step 1: In `lib/filter.mbt`, delete the local `is_finite` function (lines 193-195) and verify all call sites already use the name `is_finite`**

The local function is named `is_finite` which matches the shared helper exactly. Since both are in the same package `lib/`, the shared `is_finite` from `util.mbt` will be found. Delete lines 192-195:

```
///|
fn is_finite(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}
```

- [ ] **Step 2: Run `moon check`**

Run: `moon check 2>&1`
Expected: no errors.

- [ ] **Step 3: In `lib/osc.mbt`, delete `is_valid_osc_param` (lines 128-131) and replace all usages with `is_finite`**

Delete lines 128-131:
```
///|
fn is_valid_osc_param(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}
```

Replace at lines 43-44:
```
  if !is_valid_osc_param(freq) ||
    !is_valid_osc_param(sample_rate) ||
```
with:
```
  if !is_finite(freq) ||
    !is_finite(sample_rate) ||
```

Replace at lines 79-80 (same pattern):
```
  if !is_valid_osc_param(freq) ||
    !is_valid_osc_param(sample_rate) ||
```
with:
```
  if !is_finite(freq) ||
    !is_finite(sample_rate) ||
```

- [ ] **Step 4: Run `moon check`**

Run: `moon check 2>&1`
Expected: no errors.

- [ ] **Step 5: In `lib/smooth.mbt`, delete `is_valid_param_value` (lines 117-119) and replace usages with `is_finite`**

Delete lines 116-119:
```
///|
fn is_valid_param_value(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}
```

Replace all `is_valid_param_value(` with `is_finite(` in the file.

- [ ] **Step 6: In `lib/pan.mbt`, delete `is_valid_pan_position` (lines 79-81) and replace usages with `is_finite`**

Delete lines 78-81:
```
///|
fn is_valid_pan_position(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}
```

Replace all `is_valid_pan_position(` with `is_finite(` in the file.

- [ ] **Step 7: In `lib/graph.mbt`, delete `valid_finite_value` (lines 2483-2486) and replace usages with `is_finite`**

Delete lines 2483-2486:
```
///|
fn valid_finite_value(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}
```

Replace all `valid_finite_value(` with `is_finite(` in the file.

- [ ] **Step 8: Run `moon check` and `moon test`**

Run: `moon check 2>&1 && moon test 2>&1 | tail -1`
Expected: no errors, 264 tests pass.

- [ ] **Step 9: Commit**

```bash
git add lib/filter.mbt lib/osc.mbt lib/smooth.mbt lib/pan.mbt lib/graph.mbt
git commit -m "refactor: replace per-file is_finite validators with shared helper"
```

---

### Task 3: Replace duplicated is_finite_positive validators

**Files:**
- Modify: `lib/delay.mbt` (delete `is_valid_delay_sample_rate` at line 193)
- Modify: `lib/noise.mbt` (delete `is_valid_noise_sample_rate` at line 76)
- Modify: `lib/pan.mbt` (delete `is_valid_pan_sample_rate` at line 74)
- Modify: `lib/env.mbt` (delete `is_valid_sample_rate` at line 193)
- Modify: `lib/graph.mbt` (delete `valid_compiled_context` at line 3179)

These 5 functions all check `!is_nan() && !is_inf() && > 0.0` — identical to `is_finite_positive`.

- [ ] **Step 1: In `lib/delay.mbt`, delete `is_valid_delay_sample_rate` (lines 192-195) and replace usages with `is_finite_positive`**

Delete lines 192-195:
```
///|
fn is_valid_delay_sample_rate(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf() && value > 0.0
}
```

Replace all `is_valid_delay_sample_rate(` with `is_finite_positive(` in the file.

- [ ] **Step 2: Run `moon check`**

- [ ] **Step 3: In `lib/noise.mbt`, delete `is_valid_noise_sample_rate` (lines 75-78) and replace usages with `is_finite_positive`**

Delete lines 75-78:
```
///|
fn is_valid_noise_sample_rate(sample_rate : Double) -> Bool {
  sample_rate > 0.0 && !sample_rate.is_nan() && !sample_rate.is_inf()
}
```

Replace all `is_valid_noise_sample_rate(` with `is_finite_positive(` in the file.

- [ ] **Step 4: In `lib/pan.mbt`, delete `is_valid_pan_sample_rate` (lines 73-76) and replace usages with `is_finite_positive`**

Delete lines 73-76:
```
///|
fn is_valid_pan_sample_rate(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf() && value > 0.0
}
```

Replace all `is_valid_pan_sample_rate(` with `is_finite_positive(` in the file.

- [ ] **Step 5: In `lib/env.mbt`, delete `is_valid_sample_rate` (lines 192-195) and replace usages with `is_finite_positive`**

Delete lines 192-195:
```
///|
fn is_valid_sample_rate(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf() && value > 0.0
}
```

Replace all `is_valid_sample_rate(` with `is_finite_positive(` in the file.

- [ ] **Step 6: In `lib/graph.mbt`, delete `valid_compiled_context` (lines 3178-3181) and replace usages with `is_finite_positive`**

Delete lines 3178-3181:
```
///|
fn valid_compiled_context(sample_rate : Double) -> Bool {
  !sample_rate.is_nan() && !sample_rate.is_inf() && sample_rate > 0.0
}
```

Replace all `valid_compiled_context(` with `is_finite_positive(` in the file.

- [ ] **Step 7: Run `moon check` and `moon test`**

Run: `moon check 2>&1 && moon test 2>&1 | tail -1`
Expected: no errors, 264 tests pass.

- [ ] **Step 8: Commit**

```bash
git add lib/delay.mbt lib/noise.mbt lib/pan.mbt lib/env.mbt lib/graph.mbt
git commit -m "refactor: replace per-file is_finite_positive validators with shared helper"
```

---

### Task 4: Replace duplicated sample_count helpers

**Files:**
- Modify: `lib/gain.mbt` (delete `sample_count` at line 44)
- Modify: `lib/filter.mbt` (delete `biquad_sample_count` at line 163)
- Modify: `lib/delay.mbt` (delete `delay_sample_count` at line 198)
- Modify: `lib/clip.mbt` (delete `clip_sample_count` at line 57)
- Modify: `lib/env.mbt` (delete `adsr_sample_count` at line 198)
- Modify: `lib/noise.mbt` (delete `noise_sample_count` at line 81)
- Modify: `lib/graph.mbt` (delete `compiled_sample_count` at line 3152)
- Modify: `lib/osc.mbt` (replace inline ternary at lines 73-77)

Note: `pan_sample_count` (pan.mbt), `mix_sample_count` (mix.mbt), and `compiled_stereo_sample_count` (graph.mbt) take multiple buffers — leave those as-is.

- [ ] **Step 1: In `lib/gain.mbt`, delete `sample_count` (lines 43-50) and replace usages with `effective_sample_count`**

Delete lines 43-50:
```
///|
fn sample_count(context : DspContext, buffer : AudioBuffer) -> Int {
  if buffer.length() < context.block_size() {
    buffer.length()
  } else {
    context.block_size()
  }
}
```

Replace all `sample_count(context, buffer)` with `effective_sample_count(context, buffer)` in the file. Note: the name change from `sample_count` to `effective_sample_count` avoids shadowing.

- [ ] **Step 2: Run `moon check`**

- [ ] **Step 3: In `lib/filter.mbt`, delete `biquad_sample_count` (lines 162-169) and replace usages with `effective_sample_count`**

Delete lines 162-169:
```
///|
fn biquad_sample_count(context : DspContext, buffer : AudioBuffer) -> Int {
  if buffer.length() < context.block_size() {
    buffer.length()
  } else {
    context.block_size()
  }
}
```

Replace all `biquad_sample_count(` with `effective_sample_count(` in the file.

- [ ] **Step 4: In `lib/delay.mbt`, delete `delay_sample_count` and replace usages with `effective_sample_count`**

Delete the function and replace all `delay_sample_count(` with `effective_sample_count(`.

- [ ] **Step 5: In `lib/clip.mbt`, delete `clip_sample_count` and replace usages with `effective_sample_count`**

Delete the function and replace all `clip_sample_count(` with `effective_sample_count(`.

- [ ] **Step 6: In `lib/env.mbt`, delete `adsr_sample_count` and replace usages with `effective_sample_count`**

Delete the function and replace all `adsr_sample_count(` with `effective_sample_count(`.

- [ ] **Step 7: In `lib/noise.mbt`, delete `noise_sample_count` and replace usages with `effective_sample_count`**

Delete the function and replace all `noise_sample_count(` with `effective_sample_count(`.

- [ ] **Step 8: In `lib/graph.mbt`, delete `compiled_sample_count` and replace usages with `effective_sample_count`**

Delete the function and replace all `compiled_sample_count(` with `effective_sample_count(`.

- [ ] **Step 9: In `lib/osc.mbt`, replace inline sample count computation with `effective_sample_count`**

In `process` method (around lines 73-77), replace:
```moonbit
  let sample_count = if output.length() < context.block_size() {
    output.length()
  } else {
    context.block_size()
  }
```
with:
```moonbit
  let sample_count = effective_sample_count(context, output)
```

In `process_waveform` method, apply the same replacement.

- [ ] **Step 10: Run `moon check` and `moon test`**

Run: `moon check 2>&1 && moon test 2>&1 | tail -1`
Expected: no errors, 264 tests pass.

- [ ] **Step 11: Commit**

```bash
git add lib/gain.mbt lib/filter.mbt lib/delay.mbt lib/clip.mbt lib/env.mbt lib/noise.mbt lib/graph.mbt lib/osc.mbt
git commit -m "refactor: replace per-file sample_count helpers with shared effective_sample_count"
```

---

### Task 5: Derive Eq for payload-less enums and delete node_kind_matches

**Files:**
- Modify: `lib/graph.mbt` (DspNodeKind, GraphControlKind, GraphParamSlot — add derive(Eq))
- Modify: `lib/graph.mbt` (delete `node_kind_matches` at line 3644, replace usages with `==`)
- Modify: `lib/osc.mbt` (Waveform — add derive(Eq))
- Modify: `lib/filter.mbt` (BiquadMode — add derive(Eq))
- Modify: `lib/env.mbt` (EnvStage — add derive(Eq))
- Modify: `lib/graph_topology_edit.mbt` (GraphTopologyEditKind, GraphTopologyInputSlot — add derive(Eq))

- [ ] **Step 1: Add `derive(Eq)` to `DspNodeKind` in `lib/graph.mbt` (lines 3-22)**

Change:
```moonbit
pub(all) enum DspNodeKind {
  Constant
  ...
  StereoOutput
}
```
to:
```moonbit
pub(all) enum DspNodeKind {
  Constant
  ...
  StereoOutput
} derive(Eq)
```

- [ ] **Step 2: Delete `node_kind_matches` in `lib/graph.mbt` (lines 3643-3665) and replace usages with `==`**

Delete the entire function (lines 3643-3665):
```
///|
fn node_kind_matches(left : DspNodeKind, right : DspNodeKind) -> Bool {
  match left {
    Constant => right is Constant
    ...
  }
}
```

Replace all `node_kind_matches(a, b)` with `a == b` in the file.

- [ ] **Step 3: Run `moon check`**

- [ ] **Step 4: Add `derive(Eq)` to remaining enums**

In `lib/graph.mbt`:
- `GraphParamSlot` (line 26): add `} derive(Eq)` after the closing brace
- `GraphControlKind` (line 36): add `} derive(Eq)` after the closing brace

In `lib/osc.mbt`:
- `Waveform` (line 3): add `} derive(Eq)` after the closing brace

In `lib/filter.mbt`:
- `BiquadMode` (line 3): add `} derive(Eq)` after the closing brace

In `lib/env.mbt`:
- `EnvStage` (line 3): add `} derive(Eq)` after the closing brace

In `lib/graph_topology_edit.mbt`:
- `GraphTopologyEditKind` (line 3): add `} derive(Eq)` after the closing brace
- `GraphTopologyInputSlot` (line 14): add `} derive(Eq)` after the closing brace

- [ ] **Step 5: Run `moon check` and `moon test`**

Run: `moon check 2>&1 && moon test 2>&1 | tail -1`
Expected: no errors, 264 tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/graph.mbt lib/osc.mbt lib/filter.mbt lib/env.mbt lib/graph_topology_edit.mbt
git commit -m "refactor: derive Eq for all payload-less enums, delete node_kind_matches"
```

---

### Task 6: Document DspNode flat-struct design decision

**Files:**
- Modify: `lib/graph.mbt` (DspNode struct, line 79)

- [ ] **Step 1: Add documentation comment to DspNode struct**

Above the struct definition at line 79, add:

```moonbit
///|
/// Flat graph node representation for compiled DSP graphs.
///
/// Design decision: DspNode uses a flat struct with generic fields (value0-value3)
/// rather than per-kind structs or a tagged union with payloads. This is deliberate:
///
/// 1. **Flat memory layout** — all nodes are the same size, enabling fixed-array
///    storage without boxing. Critical for zero-allocation audio processing.
/// 2. **Copy-on-update** — node_with_value0/value1/delay_samples create updated
///    copies without knowing the node kind, supporting runtime parameter changes.
/// 3. **Serialization** — uniform layout simplifies graph serialization for
///    hot-swap and topology editing.
///
/// The cost is that field semantics depend on `kind` — see each constructor
/// (e.g. `DspNode::oscillator`, `DspNode::biquad`) for the field mapping.
```

- [ ] **Step 2: Run `moon check`**

Run: `moon check 2>&1`
Expected: no errors.

- [ ] **Step 3: Run `moon info && moon fmt`**

Run: `moon info && moon fmt`

- [ ] **Step 4: Commit**

```bash
git add lib/graph.mbt
git commit -m "docs: document DspNode flat-struct design decision"
```

---

### Task 7: Final verification

- [ ] **Step 1: Run full test suite**

Run: `moon test 2>&1`
Expected: 264 tests pass, zero warnings.

- [ ] **Step 2: Run JS build**

Run: `moon build --target js 2>&1`
Expected: build succeeds.

- [ ] **Step 3: Regenerate interfaces**

Run: `moon info && moon fmt`

- [ ] **Step 4: Review .mbti changes**

Run: `git diff -- '*.mbti'`
Expected: `derive(Eq)` may add `Eq` impl lines to the .mbti. `is_finite`, `is_finite_positive`, and `effective_sample_count` appear as new public functions. Verify no unintended API removals.

- [ ] **Step 5: Commit interface changes if any**

```bash
git add -u
git commit -m "chore: regenerate .mbti interfaces after helper dedup"
```
