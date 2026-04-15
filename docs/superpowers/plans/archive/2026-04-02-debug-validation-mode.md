# Debug Validation Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add runtime bounds checking for graph buffer indexing, gated by a `debug_validate` flag on CompiledGraph. Reports `GraphValidationError` with node index, invalid input, and state kind. Zero overhead when disabled.

**Architecture:** Two-path design in `process()` — fast path (existing loop unchanged) and debug path (separate `process_debug` function with per-node validation). Flag, error type, and validation helpers in a new `lib/graph_debug.mbt` file to keep graph.mbt focused. Error cap at 32 per block.

**Tech Stack:** MoonBit, moon check/test/fmt/info

**Spec:** `docs/superpowers/specs/2026-04-02-debug-validation-mode-design.md`

---

### Task 1: Add GraphValidationError type and debug fields to CompiledGraph

**Files:**
- Create: `lib/graph_debug.mbt`
- Modify: `lib/graph.mbt` (add fields to CompiledGraph struct and compile_graph_impl)

- [ ] **Step 1: Create graph_debug.mbt with error type and constants**

Create `lib/graph_debug.mbt`:

```moonbit
///|
const MAX_DEBUG_ERRORS : Int = 32

///|
pub(all) enum GraphValidationError {
  InvalidInput0(Int, Int, Int)
  InvalidInput1(Int, Int, Int)
  InvalidStateIndex(Int, String)
} derive(Show, Eq)
```

- [ ] **Step 2: Add debug fields to CompiledGraph struct**

In `lib/graph.mbt`, find the `CompiledGraph` struct (search for `mut last_sanitized_count : Int`). After that line, add:

```moonbit
  mut debug_validate : Bool
  mut last_validation_errors : Array[GraphValidationError]
```

- [ ] **Step 3: Initialize fields in compile_graph_impl**

In `compile_graph_impl`, find `last_sanitized_count: 0,` and add after it:

```moonbit
    debug_validate: false,
    last_validation_errors: [],
```

- [ ] **Step 4: Run moon check**

Run: `moon check 2>&1`
Expected: 0 errors

- [ ] **Step 5: Commit**

```bash
git add lib/graph_debug.mbt lib/graph.mbt
git commit -m "feat: add GraphValidationError type and debug fields to CompiledGraph"
```

---

### Task 2: Add enable/disable/errors public API

**Files:**
- Modify: `lib/graph_debug.mbt` (append accessors)
- Test: `lib/graph_debug_test.mbt` (create)

- [ ] **Step 1: Write failing tests**

Create `lib/graph_debug_test.mbt`:

```moonbit
///|
test "debug: off by default" {
  let context = DspContext::new(48000.0, 4)
  let nodes = [DspNode::constant(1.0), DspNode::output(0)]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  assert_eq(compiled.last_validation_errors().length(), 0)
}

///|
test "debug: enable and disable toggle" {
  let context = DspContext::new(48000.0, 4)
  let nodes = [DspNode::constant(1.0), DspNode::output(0)]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  compiled.enable_debug_validation()
  let output = AudioBuffer::filled(4)
  compiled.process(context, output)
  assert_eq(compiled.last_validation_errors().length(), 0)
  compiled.disable_debug_validation()
  compiled.process(context, output)
  assert_eq(compiled.last_validation_errors().length(), 0)
}
```

- [ ] **Step 2: Implement accessors**

Append to `lib/graph_debug.mbt`:

```moonbit
///|
pub fn CompiledDsp::enable_debug_validation(self : CompiledDsp) -> Unit {
  self.0.debug_validate = true
}

///|
pub fn CompiledDsp::disable_debug_validation(self : CompiledDsp) -> Unit {
  self.0.debug_validate = false
  self.0.last_validation_errors = []
}

///|
pub fn CompiledDsp::last_validation_errors(
  self : CompiledDsp,
) -> Array[GraphValidationError] {
  self.0.last_validation_errors
}

///|
pub fn CompiledStereoDsp::enable_debug_validation(
  self : CompiledStereoDsp,
) -> Unit {
  self.0.debug_validate = true
}

///|
pub fn CompiledStereoDsp::disable_debug_validation(
  self : CompiledStereoDsp,
) -> Unit {
  self.0.debug_validate = false
  self.0.last_validation_errors = []
}

///|
pub fn CompiledStereoDsp::last_validation_errors(
  self : CompiledStereoDsp,
) -> Array[GraphValidationError] {
  self.0.last_validation_errors
}
```

- [ ] **Step 3: Run moon check && moon test**

Run: `moon check 2>&1 && moon test -f graph_debug_test.mbt 2>&1 | tail -5`
Expected: All pass

- [ ] **Step 4: Commit**

```bash
git add lib/graph_debug.mbt lib/graph_debug_test.mbt
git commit -m "feat: add debug validation enable/disable/errors API"
```

---

### Task 3: Implement validation helpers

**Files:**
- Modify: `lib/graph_debug.mbt` (append validation functions)

- [ ] **Step 1: Implement validate_node_inputs**

Append to `lib/graph_debug.mbt`:

```moonbit
///|
/// Check that node's input0 and input1 are within buffer bounds.
/// Called per node in debug mode only. Returns true if valid.
fn validate_node_inputs(
  node : DspNode,
  node_index : Int,
  buffer_count : Int,
  errors : Array[GraphValidationError],
) -> Bool {
  let max_valid = buffer_count - 1
  let mut valid = true
  if node.input0 >= 0 && node.input0 >= buffer_count {
    if errors.length() < MAX_DEBUG_ERRORS {
      errors.push(GraphValidationError::InvalidInput0(
        node_index,
        node.input0,
        max_valid,
      ))
    }
    valid = false
  }
  if node.input1 >= 0 && node.input1 >= buffer_count {
    if errors.length() < MAX_DEBUG_ERRORS {
      errors.push(GraphValidationError::InvalidInput1(
        node_index,
        node.input1,
        max_valid,
      ))
    }
    valid = false
  }
  valid
}

///|
/// Check that stateful node has its required state present.
/// Called per node in debug mode only. Returns true if valid.
fn validate_node_state(
  graph : CompiledGraph,
  node : DspNode,
  node_index : Int,
  errors : Array[GraphValidationError],
) -> Bool {
  let missing = match node.kind {
    Oscillator =>
      if graph.osc_states[node_index] is None { Some("osc") } else { None }
    Noise =>
      if graph.noise_states[node_index] is None { Some("noise") } else { None }
    Adsr =>
      if graph.env_states[node_index] is None { Some("env") } else { None }
    Biquad =>
      if graph.biquad_states[node_index] is None {
        Some("biquad")
      } else {
        None
      }
    Delay =>
      if graph.delay_states[node_index] is None { Some("delay") } else { None }
    StereoBiquad =>
      if graph.stereo_biquad_left_states[node_index] is None ||
        graph.stereo_biquad_right_states[node_index] is None {
        Some("stereo_biquad")
      } else {
        None
      }
    StereoDelay =>
      if graph.stereo_delay_left_states[node_index] is None ||
        graph.stereo_delay_right_states[node_index] is None {
        Some("stereo_delay")
      } else {
        None
      }
    _ => None
  }
  match missing {
    Some(kind) => {
      if errors.length() < MAX_DEBUG_ERRORS {
        errors.push(GraphValidationError::InvalidStateIndex(node_index, kind))
      }
      false
    }
    None => true
  }
}
```

- [ ] **Step 2: Run moon check**

Run: `moon check 2>&1`
Expected: 0 errors

- [ ] **Step 3: Commit**

```bash
git add lib/graph_debug.mbt
git commit -m "feat: add validate_node_inputs and validate_node_state helpers"
```

---

### Task 4: Wire debug path into CompiledDsp::process

**Files:**
- Modify: `lib/graph_debug.mbt` (add process_mono_debug)
- Modify: `lib/graph.mbt` (add debug branch at top of CompiledDsp::process)
- Test: `lib/graph_debug_test.mbt` (append tests)

- [ ] **Step 1: Write failing tests**

Append to `lib/graph_debug_test.mbt`:

```moonbit
///|
test "debug: valid graph produces no errors" {
  let context = DspContext::new(48000.0, 4)
  let nodes = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::gain(0, 0.3),
    DspNode::output(1),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  compiled.enable_debug_validation()
  let output = AudioBuffer::filled(4)
  compiled.process(context, output)
  assert_eq(compiled.last_validation_errors().length(), 0)
  assert_true(output.get(0) != 0.0)
}

///|
test "debug: errors reset each process call" {
  let context = DspContext::new(48000.0, 4)
  let nodes = [DspNode::constant(1.0), DspNode::output(0)]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  compiled.enable_debug_validation()
  let output = AudioBuffer::filled(4)
  // First call — clean
  compiled.process(context, output)
  assert_eq(compiled.last_validation_errors().length(), 0)
  // Second call — still clean, errors didn't accumulate
  compiled.process(context, output)
  assert_eq(compiled.last_validation_errors().length(), 0)
}
```

- [ ] **Step 2: Implement process_mono_debug**

Append to `lib/graph_debug.mbt`:

```moonbit
///|
/// Debug variant of the mono process loop. Validates each node's inputs
/// and state before processing. On violation, fills the node's output
/// buffer with silence and skips to the next node.
fn CompiledDsp::process_mono_debug(
  self : CompiledDsp,
  context : DspContext,
  output : AudioBuffer,
  sample_count : Int,
) -> Unit {
  self.0.last_validation_errors = []
  let buffer_count = self.0.buffers.length()
  let pan = Pan::new()
  for index = 0; index < self.0.nodes.length(); index = index + 1 {
    let node = self.0.nodes[index]
    let buffer = self.0.buffers[index]
    if !validate_node_inputs(node, index, buffer_count, self.0.last_validation_errors) ||
      !validate_node_state(self.0, node, index, self.0.last_validation_errors) {
      buffer.fill(0.0)
      continue index + 1
    }
    match node.kind {
      Constant => fill_constant_buffer(buffer, sample_count, node.value0)
      Oscillator =>
        if node.input0 >= 0 {
          let osc = self.0.osc_states[index].unwrap()
          let freq_buf = self.0.buffers[node.input0]
          let sr = context.sample_rate()
          for i = 0; i < sample_count; i = i + 1 {
            buffer.set(i, osc.tick_waveform(node.waveform, freq_buf.get(i), sr))
          }
        } else {
          self.0.osc_states[index]
          .unwrap()
          .process_waveform(context, buffer, node.waveform, node.value0)
        }
      Noise => self.0.noise_states[index].unwrap().process(context, buffer)
      Adsr => self.0.env_states[index].unwrap().process(context, buffer)
      Biquad => {
        copy_buffer(self.0.buffers[node.input0], buffer, sample_count)
        process_graph_biquad(
          self.0.biquad_states[index].unwrap(),
          context,
          buffer,
          node.filter_mode,
          node.value0,
          node.value1,
        )
      }
      Delay => {
        copy_buffer(self.0.buffers[node.input0], buffer, sample_count)
        self.0.delay_states[index].unwrap().process(context, buffer)
      }
      Gain => {
        copy_buffer(self.0.buffers[node.input0], buffer, sample_count)
        apply_gain_buffer(buffer, sample_count, node.value0)
      }
      Mul =>
        multiply_buffers(
          self.0.buffers[node.input0],
          self.0.buffers[node.input1],
          buffer,
          sample_count,
        )
      Mix =>
        mix_buffers(
          self.0.buffers[node.input0],
          self.0.buffers[node.input1],
          buffer,
          sample_count,
        )
      Clip => {
        copy_buffer(self.0.buffers[node.input0], buffer, sample_count)
        clip_buffer(buffer, sample_count, node.value0)
      }
      Output => copy_buffer(self.0.buffers[node.input0], buffer, sample_count)
      Pan =>
        pan.process(
          context,
          self.0.buffers[node.input0],
          self.0.left_buffers[index],
          self.0.right_buffers[index],
          node.value0,
        )
      StereoGain => {
        copy_stereo_buffers(
          self.0.left_buffers[node.input0],
          self.0.right_buffers[node.input0],
          self.0.left_buffers[index],
          self.0.right_buffers[index],
          sample_count,
        )
        apply_gain_buffer(self.0.left_buffers[index], sample_count, node.value0)
        apply_gain_buffer(
          self.0.right_buffers[index],
          sample_count,
          node.value0,
        )
      }
      StereoClip => {
        copy_stereo_buffers(
          self.0.left_buffers[node.input0],
          self.0.right_buffers[node.input0],
          self.0.left_buffers[index],
          self.0.right_buffers[index],
          sample_count,
        )
        clip_buffer(self.0.left_buffers[index], sample_count, node.value0)
        clip_buffer(self.0.right_buffers[index], sample_count, node.value0)
      }
      StereoBiquad => {
        copy_stereo_buffers(
          self.0.left_buffers[node.input0],
          self.0.right_buffers[node.input0],
          self.0.left_buffers[index],
          self.0.right_buffers[index],
          sample_count,
        )
        process_graph_biquad(
          self.0.stereo_biquad_left_states[index].unwrap(),
          context,
          self.0.left_buffers[index],
          node.filter_mode,
          node.value0,
          node.value1,
        )
        process_graph_biquad(
          self.0.stereo_biquad_right_states[index].unwrap(),
          context,
          self.0.right_buffers[index],
          node.filter_mode,
          node.value0,
          node.value1,
        )
      }
      StereoDelay => {
        copy_stereo_buffers(
          self.0.left_buffers[node.input0],
          self.0.right_buffers[node.input0],
          self.0.left_buffers[index],
          self.0.right_buffers[index],
          sample_count,
        )
        self.0.stereo_delay_left_states[index]
        .unwrap()
        .process(context, self.0.left_buffers[index])
        self.0.stereo_delay_right_states[index]
        .unwrap()
        .process(context, self.0.right_buffers[index])
      }
      StereoMixDown =>
        mixdown_stereo_buffers(
          self.0.left_buffers[node.input0],
          self.0.right_buffers[node.input0],
          buffer,
          sample_count,
        )
      StereoOutput => buffer.fill(0.0)
    }
  }
  copy_buffer(self.0.buffers[self.0.buffers.length() - 1], output, sample_count)
  self.0.last_sanitized_count = sanitize_buffer(output, sample_count)
}
```

- [ ] **Step 3: Wire debug branch into CompiledDsp::process**

In `lib/graph.mbt`, find the line in `CompiledDsp::process` just before the feedback check (`if self.0.feedback_edges.length() > 0`). Add before it:

```moonbit
  if self.0.debug_validate {
    self.process_mono_debug(context, output, sample_count)
    return
  }
```

- [ ] **Step 4: Run moon check && moon test**

Run: `moon check 2>&1 && moon test 2>&1 | tail -5`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/graph_debug.mbt lib/graph_debug_test.mbt lib/graph.mbt
git commit -m "feat: wire debug validation into CompiledDsp::process"
```

---

### Task 5: Wire debug path into CompiledStereoDsp::process

**Files:**
- Modify: `lib/graph_debug.mbt` (add process_stereo_debug — same pattern as mono but with left/right buffers)
- Modify: `lib/graph.mbt` (add debug branch in CompiledStereoDsp::process)
- Test: `lib/graph_debug_test.mbt` (append stereo test)

- [ ] **Step 1: Write stereo test**

Append to `lib/graph_debug_test.mbt`:

```moonbit
///|
test "debug stereo: valid graph produces no errors" {
  let context = DspContext::new(48000.0, 4)
  let nodes = [
    DspNode::constant(1.0),
    DspNode::pan(0, 0.0),
    DspNode::stereo_output(1),
  ]
  let compiled = CompiledStereoDsp::compile(nodes, context).unwrap()
  compiled.enable_debug_validation()
  let left = AudioBuffer::filled(4)
  let right = AudioBuffer::filled(4)
  compiled.process(context, left, right)
  assert_eq(compiled.last_validation_errors().length(), 0)
}
```

- [ ] **Step 2: Implement process_stereo_debug**

Append to `lib/graph_debug.mbt`. This mirrors the stereo process loop from `CompiledStereoDsp::process` in graph.mbt but adds validation before each node. Read the stereo process loop in graph.mbt (~line 1449-1610) and replicate it with the validation gate at the top of each iteration — same pattern as `process_mono_debug` but using left/right buffers.

The function signature:

```moonbit
fn CompiledStereoDsp::process_stereo_debug(
  self : CompiledStereoDsp,
  context : DspContext,
  left_output : AudioBuffer,
  right_output : AudioBuffer,
  sample_count : Int,
) -> Unit
```

Follow the exact same pattern: clear errors, validate each node, fill silence on failure, process normally on success, copy and sanitize at end.

- [ ] **Step 3: Wire debug branch into CompiledStereoDsp::process**

In `lib/graph.mbt`, in `CompiledStereoDsp::process`, add before the feedback check:

```moonbit
  if self.0.debug_validate {
    self.process_stereo_debug(context, left_output, right_output, sample_count)
    return
  }
```

- [ ] **Step 4: Run moon check && moon test**

Run: `moon check 2>&1 && moon test 2>&1 | tail -5`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/graph_debug.mbt lib/graph_debug_test.mbt lib/graph.mbt
git commit -m "feat: wire debug validation into CompiledStereoDsp::process"
```

---

### Task 6: Final verification and cleanup

- [ ] **Step 1: Run full test suite**

Run: `moon test 2>&1 | tail -5`
Expected: All tests pass (444 existing + ~4 new debug tests)

- [ ] **Step 2: Update interfaces and format**

Run: `moon info && moon fmt`

- [ ] **Step 3: Check API surface**

Run: `git diff lib/pkg.generated.mbti`
Expected: New symbols: `GraphValidationError`, `CompiledDsp::enable_debug_validation`, `CompiledDsp::disable_debug_validation`, `CompiledDsp::last_validation_errors`, same three for `CompiledStereoDsp`.

- [ ] **Step 4: Commit**

```bash
git add lib/pkg.generated.mbti
git commit -m "chore: update .mbti for debug validation mode public API"
```
