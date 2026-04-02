# NaN Firewall Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add output sanitization at the graph rendering boundary — replace non-finite samples with 0.0 and report the count.

**Architecture:** `sanitize_buffer` helper in `lib/util.mbt`. Called at the end of `CompiledDsp::process`, `CompiledStereoDsp::process`, and `VoicePool::process`. Count stored in a mutable `last_sanitized_count` field on `CompiledGraph` and `VoicePool`, accessible via method. Process functions keep returning `Unit` to avoid breaking ~100 existing call sites.

**Tech Stack:** MoonBit, moon check/test/fmt/info

**Spec:** `docs/superpowers/specs/2026-04-02-nan-firewall-design.md`

**Note on signature:** The spec originally proposed `process() -> Int`. During planning, we discovered MoonBit requires non-Unit returns to be explicitly consumed (compile error on unused return). Changing ~100 call sites to `ignore(compiled.process(...))` is high churn. Instead, process() stays `-> Unit` and the sanitized count is stored as state with an accessor. The safety guarantee is identical — sanitization always runs.

---

### Task 1: Implement sanitize_buffer helper

**Files:**
- Modify: `lib/util.mbt` (append function)
- Create: `lib/util_test.mbt` (sanitize_buffer tests — currently no test file for util)

- [ ] **Step 1: Write failing tests**

Create `lib/util_test.mbt`:

```moonbit
///|
test "sanitize_buffer: clean buffer returns 0" {
  let buf = AudioBuffer::filled(4)
  buf.set(0, 0.5)
  buf.set(1, -0.3)
  buf.set(2, 1.0)
  buf.set(3, 0.0)
  let count = sanitize_buffer(buf, 4)
  assert_eq(count, 0)
  assert_eq(buf.get(0), 0.5)
  assert_eq(buf.get(3), 0.0)
}

///|
test "sanitize_buffer: NaN replaced with 0.0" {
  let buf = AudioBuffer::filled(4)
  buf.set(0, 0.5)
  buf.set(1, Double::nan())
  buf.set(2, Double::nan())
  buf.set(3, 0.5)
  let count = sanitize_buffer(buf, 4)
  assert_eq(count, 2)
  assert_eq(buf.get(0), 0.5)
  assert_eq(buf.get(1), 0.0)
  assert_eq(buf.get(2), 0.0)
  assert_eq(buf.get(3), 0.5)
}

///|
test "sanitize_buffer: +Inf and -Inf replaced" {
  let buf = AudioBuffer::filled(4)
  buf.set(0, Double::inf(1))
  buf.set(1, Double::inf(-1))
  buf.set(2, 0.5)
  buf.set(3, Double::nan())
  let count = sanitize_buffer(buf, 4)
  assert_eq(count, 3)
  assert_eq(buf.get(0), 0.0)
  assert_eq(buf.get(1), 0.0)
  assert_eq(buf.get(2), 0.5)
  assert_eq(buf.get(3), 0.0)
}

///|
test "sanitize_buffer: sample_count clamped to buffer length" {
  let buf = AudioBuffer::filled(2)
  buf.set(0, Double::nan())
  buf.set(1, 0.5)
  let count = sanitize_buffer(buf, 100)
  assert_eq(count, 1)
  assert_eq(buf.get(0), 0.0)
  assert_eq(buf.get(1), 0.5)
}

///|
test "sanitize_buffer: zero sample_count returns 0" {
  let buf = AudioBuffer::filled(4)
  buf.set(0, Double::nan())
  let count = sanitize_buffer(buf, 0)
  assert_eq(count, 0)
  // NaN should still be there — not touched
  assert_true(buf.get(0).is_nan())
}

///|
test "sanitize_buffer: idempotent — sanitized buffer returns 0" {
  let buf = AudioBuffer::filled(4)
  buf.set(0, Double::nan())
  buf.set(1, Double::inf(1))
  let first = sanitize_buffer(buf, 4)
  assert_eq(first, 2)
  let second = sanitize_buffer(buf, 4)
  assert_eq(second, 0)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon check 2>&1`
Expected: FAIL — `sanitize_buffer` not defined

- [ ] **Step 3: Implement sanitize_buffer**

Append to `lib/util.mbt`:

```moonbit
///|
/// Replace non-finite samples (NaN, Inf) with 0.0 in-place.
/// Returns the number of samples replaced. This is the output firewall —
/// the last line of defense before samples leave the DSP engine.
pub fn sanitize_buffer(buffer : AudioBuffer, sample_count : Int) -> Int {
  let count = if sample_count > buffer.length() {
    buffer.length()
  } else if sample_count < 0 {
    0
  } else {
    sample_count
  }
  let mut sanitized = 0
  for i = 0; i < count; i = i + 1 {
    if !is_finite(buffer.get(i)) {
      buffer.set(i, 0.0)
      sanitized = sanitized + 1
    }
  }
  sanitized
}
```

- [ ] **Step 4: Run moon check**

Run: `moon check 2>&1`
Expected: 0 errors

- [ ] **Step 5: Run tests**

Run: `moon test -f util_test.mbt 2>&1 | tail -5`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add lib/util.mbt lib/util_test.mbt
git commit -m "feat: add sanitize_buffer output firewall helper"
```

---

### Task 2: Add last_sanitized_count field to CompiledGraph

**Files:**
- Modify: `lib/graph.mbt` (add field to CompiledGraph struct, initialize in compile_graph_impl, add accessor)

- [ ] **Step 1: Add mutable field to CompiledGraph**

In `lib/graph.mbt`, find the `CompiledGraph` struct definition (search for `struct CompiledGraph`). Add a mutable field:

```moonbit
  mut last_sanitized_count : Int
```

- [ ] **Step 2: Initialize the field in compile_graph_impl**

In `compile_graph_impl` (search for `Some({` around line 767), add `last_sanitized_count: 0` to the struct literal.

- [ ] **Step 3: Add public accessor**

Add after the CompiledGraph struct:

```moonbit
///|
/// Number of non-finite samples replaced with 0.0 during the most recent
/// process() call. Returns 0 if output was clean. Useful for telemetry
/// and debugging — a nonzero value means the graph produced corruption.
pub fn CompiledDsp::last_sanitized_count(self : CompiledDsp) -> Int {
  self.0.last_sanitized_count
}

///|
pub fn CompiledStereoDsp::last_sanitized_count(
  self : CompiledStereoDsp,
) -> Int {
  self.0.last_sanitized_count
}
```

- [ ] **Step 4: Run moon check**

Run: `moon check 2>&1`
Expected: 0 errors

- [ ] **Step 5: Commit**

```bash
git add lib/graph.mbt
git commit -m "feat: add last_sanitized_count field to CompiledGraph"
```

---

### Task 3: Wire sanitize_buffer into CompiledDsp::process

**Files:**
- Modify: `lib/graph.mbt` (CompiledDsp::process and process_feedback_graph)
- Modify: `lib/graph_test.mbt` (append tests)

- [ ] **Step 1: Write failing tests**

Append to `lib/graph_test.mbt`:

```moonbit
///|
test "process: clean graph has zero sanitized count" {
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
  let nodes = [
    DspNode::oscillator(Waveform::Sine, OSCILLATOR_FREQ),
    DspNode::output(0),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  compiled.process(context, output)
  assert_eq(compiled.last_sanitized_count(), 0)
}

///|
test "process: NaN constant is sanitized in output" {
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
  let nodes = [
    DspNode::constant(Double::nan()),
    DspNode::output(0),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  compiled.process(context, output)
  assert_true(compiled.last_sanitized_count() > 0)
  // All output samples should be 0.0 (sanitized)
  for i = 0; i < SMALL_BLOCK_SIZE; i = i + 1 {
    assert_eq(output.get(i), 0.0)
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test -f graph_test.mbt 2>&1 | tail -5`
Expected: FAIL — `last_sanitized_count` returns 0 even for NaN (sanitization not wired yet)

- [ ] **Step 3: Wire sanitize_buffer into CompiledDsp::process**

In `CompiledDsp::process` (line ~824), change the ending. Before the function's closing `}`, after the `copy_buffer` call at line ~995, add:

```moonbit
  self.0.last_sanitized_count = sanitize_buffer(output, sample_count)
```

Also in the early-return paths (lines ~836-837, ~843-844) where output is filled with 0.0, set:

```moonbit
  self.0.last_sanitized_count = 0
```

For the feedback path (line ~847), the `process_feedback_graph` function writes to output. After that call returns, add sanitization. Change:

```moonbit
  if self.0.feedback_edges.length() > 0 {
    self.process_feedback_graph(context, output, sample_count)
    return
  }
```

To:

```moonbit
  if self.0.feedback_edges.length() > 0 {
    self.process_feedback_graph(context, output, sample_count)
    self.0.last_sanitized_count = sanitize_buffer(output, sample_count)
    return
  }
```

- [ ] **Step 4: Run moon check**

Run: `moon check 2>&1`
Expected: 0 errors

- [ ] **Step 5: Run tests**

Run: `moon test -f graph_test.mbt 2>&1 | tail -5`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add lib/graph.mbt lib/graph_test.mbt
git commit -m "feat: wire sanitize_buffer into CompiledDsp::process"
```

---

### Task 4: Wire sanitize_buffer into CompiledStereoDsp::process

**Files:**
- Modify: `lib/graph.mbt` (CompiledStereoDsp::process and process_feedback_graph)
- Modify: `lib/graph_test.mbt` (append test)

- [ ] **Step 1: Write failing test**

Append to `lib/graph_test.mbt`:

```moonbit
///|
test "stereo process: both channels sanitized" {
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
  let nodes = [
    DspNode::constant(Double::nan()),
    DspNode::pan(0, 0.0),
    DspNode::stereo_output(1),
  ]
  let compiled = CompiledStereoDsp::compile(nodes, context).unwrap()
  let left = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  let right = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  compiled.process(context, left, right)
  assert_true(compiled.last_sanitized_count() > 0)
  for i = 0; i < SMALL_BLOCK_SIZE; i = i + 1 {
    assert_eq(left.get(i), 0.0)
    assert_eq(right.get(i), 0.0)
  }
}
```

- [ ] **Step 2: Wire sanitize_buffer into CompiledStereoDsp::process**

Same pattern as Task 3 but for stereo. In `CompiledStereoDsp::process` (line ~1399):

After the final `copy_stereo_buffers` at line ~1584-1590, add:

```moonbit
  self.0.last_sanitized_count = sanitize_buffer(left_output, sample_count) +
    sanitize_buffer(right_output, sample_count)
```

In early-return paths (lines ~1414-1416, ~1422-1423):

```moonbit
  self.0.last_sanitized_count = 0
```

For feedback path (line ~1426-1430):

```moonbit
  if self.0.feedback_edges.length() > 0 {
    self.process_feedback_graph(
      context, left_output, right_output, sample_count,
    )
    self.0.last_sanitized_count = sanitize_buffer(left_output, sample_count) +
      sanitize_buffer(right_output, sample_count)
    return
  }
```

- [ ] **Step 3: Run moon check && moon test**

Run: `moon check 2>&1 && moon test -f graph_test.mbt 2>&1 | tail -5`
Expected: All pass

- [ ] **Step 4: Commit**

```bash
git add lib/graph.mbt lib/graph_test.mbt
git commit -m "feat: wire sanitize_buffer into CompiledStereoDsp::process"
```

---

### Task 5: Wire sanitize_buffer into VoicePool::process

**Files:**
- Modify: `lib/voice.mbt` (add field, wire sanitize, add accessor)
- Modify: `lib/voice_test.mbt` (append test)

- [ ] **Step 1: Write failing test**

Append to `lib/voice_test.mbt`:

```moonbit
///|
test "VoicePool process sanitizes final mixdown output" {
  let ctx = DspContext::new(48000.0, 4)
  let nodes = [
    DspNode::constant(Double::nan()),
    DspNode::output(0),
  ]
  let pool = VoicePool::new(nodes, ctx, max_voices=2).unwrap()
  ignore(pool.note_on([]))
  let left = AudioBuffer::filled(4)
  let right = AudioBuffer::filled(4)
  pool.process(ctx, left, right)
  assert_true(pool.last_sanitized_count() > 0)
  for i = 0; i < 4; i = i + 1 {
    assert_eq(left.get(i), 0.0)
    assert_eq(right.get(i), 0.0)
  }
}
```

- [ ] **Step 2: Add field and accessor to VoicePool**

In `lib/voice.mbt`, add a mutable field to VoicePool struct:

```moonbit
  mut last_sanitized_count : Int
```

Initialize to 0 in the constructor. Add accessor:

```moonbit
///|
pub fn VoicePool::last_sanitized_count(self : VoicePool) -> Int {
  self.last_sanitized_count
}
```

- [ ] **Step 3: Wire sanitize at end of VoicePool::process**

At the end of `VoicePool::process` (after the voice loop at line ~381), add:

```moonbit
  let sample_count = if context.block_size() < left_output.length() {
    context.block_size()
  } else {
    left_output.length()
  }
  self.last_sanitized_count = sanitize_buffer(left_output, sample_count) +
    sanitize_buffer(right_output, sample_count)
```

- [ ] **Step 4: Run moon check && moon test**

Run: `moon check 2>&1 && moon test 2>&1 | tail -5`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/voice.mbt lib/voice_test.mbt
git commit -m "feat: wire sanitize_buffer into VoicePool::process"
```

---

### Task 6: Final verification and cleanup

- [ ] **Step 1: Run full test suite**

Run: `moon test 2>&1 | tail -5`
Expected: All tests pass

- [ ] **Step 2: Update interfaces and format**

Run: `moon info && moon fmt`

- [ ] **Step 3: Check API surface**

Run: `git diff lib/pkg.generated.mbti`
Expected: New symbols: `sanitize_buffer`, `CompiledDsp::last_sanitized_count`, `CompiledStereoDsp::last_sanitized_count`, `VoicePool::last_sanitized_count`

- [ ] **Step 4: Commit**

```bash
git add lib/pkg.generated.mbti
git commit -m "chore: update .mbti for NaN firewall public API"
```
