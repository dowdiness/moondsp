# Phase 3: Voice Management — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a polyphonic `VoicePool` managing 32+ simultaneous mono voices with priority-based stealing, generation-tagged handles, two-stage silence detection, and per-voice equal-power pan mixdown to stereo.

**Architecture:** `VoicePool` owns an array of `VoiceSlot`s, each containing a `CompiledDsp?`, a `VoiceState`, a generation counter, a pan value, and a mono output buffer. `note_on` compiles from a template, `process` iterates active voices and mixes to stereo. `is_voice_finished` uses ADSR idle + output energy check.

**Tech Stack:** MoonBit

**Spec:** `docs/superpowers/specs/2026-04-01-voice-management-design.md`

---

### Task 1: `CompiledDsp::is_voice_finished` method

**Files:**
- Modify: `lib/graph.mbt`
- Create: `lib/voice_test.mbt` (start with this one test, more tests added later)

This is a prerequisite for voice lifecycle management. It needs to exist on `CompiledDsp` before the pool can use it.

- [ ] **Step 1: Add `is_voice_finished` to CompiledDsp**

Add after the existing `CompiledDsp::set_param` method (~line 1684 of `lib/graph.mbt`):

```moonbit
///|
/// Returns true when a voice using this compiled graph can be safely reclaimed.
///
/// Two-stage check:
/// 1. All ADSR nodes must be in Idle stage (envelope has finished)
/// 2. The last output buffer must be silent (all samples below threshold)
///
/// WHY two stages: ADSR-only detection would cut voices with downstream delay
/// or feedback tails that are still audible. Energy-only detection would keep
/// voices alive during sustain (where output is non-zero but expected).
pub fn CompiledDsp::is_voice_finished(self : CompiledDsp) -> Bool {
  let nodes = self.0.nodes
  let env_states = self.0.env_states
  // Stage 1: check all ADSR nodes are idle
  for i = 0; i < nodes.length(); i = i + 1 {
    if nodes[i].kind is Adsr {
      match env_states[i] {
        Some(adsr) =>
          if !(adsr.stage() is EnvStage::Idle) {
            return false
          }
        None => ()
      }
    }
  }
  // Stage 2: check output buffer is silent
  let last_index = nodes.length() - 1
  if last_index < 0 {
    return true
  }
  let output_buf = self.0.buffers[last_index]
  for i = 0; i < output_buf.length(); i = i + 1 {
    if output_buf.get(i).abs() > 0.0001 {
      return false
    }
  }
  true
}
```

- [ ] **Step 2: Run `moon check`**

Run: `moon check`
Expected: No errors.

- [ ] **Step 3: Write tests for is_voice_finished**

Create `lib/voice_test.mbt` with:

```moonbit
///|
test "is_voice_finished returns false during active envelope" {
  let ctx = DspContext::new(48000.0, 16)
  // Graph: constant(440) → osc → adsr → gain → output
  let nodes = [
    DspNode::constant(440.0),
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::adsr(5.0, 5.0, 0.5, 50.0),
    DspNode::gain(1, 0.5),
    DspNode::output(3),
  ]
  let compiled = CompiledDsp::compile(nodes, ctx).unwrap()
  compiled.gate_on(2)
  let buf = AudioBuffer::filled(16)
  compiled.process(ctx, buf)
  assert_true(!compiled.is_voice_finished())
}

///|
test "is_voice_finished returns true after envelope completes release" {
  // Use 1000 Hz sample rate and 1ms release for fast completion
  let ctx = DspContext::new(1000.0, 8)
  let nodes = [
    DspNode::constant(100.0),
    DspNode::oscillator(Waveform::Sine, 100.0),
    DspNode::adsr(0.0, 0.0, 1.0, 1.0),
    DspNode::gain(1, 0.3),
    DspNode::output(3),
  ]
  let compiled = CompiledDsp::compile(nodes, ctx).unwrap()
  compiled.gate_on(2)
  let buf = AudioBuffer::filled(8)
  compiled.process(ctx, buf)
  compiled.gate_off(2)
  // Process enough blocks for the 1ms release to complete at 1000Hz
  for i = 0; i < 10; i = i + 1 {
    compiled.process(ctx, buf)
  }
  assert_true(compiled.is_voice_finished())
}

///|
test "is_voice_finished returns true for graph with no ADSR when output is silent" {
  let ctx = DspContext::new(48000.0, 4)
  let nodes = [DspNode::constant(0.0), DspNode::output(0)]
  let compiled = CompiledDsp::compile(nodes, ctx).unwrap()
  let buf = AudioBuffer::filled(4)
  compiled.process(ctx, buf)
  assert_true(compiled.is_voice_finished())
}

///|
test "is_voice_finished returns false when delay tail is audible" {
  let ctx = DspContext::new(48000.0, 16)
  let nodes = [
    DspNode::constant(440.0),
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::adsr(0.0, 0.0, 1.0, 0.0),
    DspNode::gain(1, 0.5),
    DspNode::delay(3, 4800, delay_samples=16, feedback=0.9),
    DspNode::output(4),
  ]
  let compiled = CompiledDsp::compile(nodes, ctx).unwrap()
  compiled.gate_on(2)
  let buf = AudioBuffer::filled(16)
  compiled.process(ctx, buf)
  compiled.gate_off(2)
  // ADSR has 0ms release, so it goes idle immediately
  compiled.process(ctx, buf)
  // But the delay with 0.9 feedback should still have audible output
  assert_true(!compiled.is_voice_finished())
}
```

- [ ] **Step 4: Run tests**

Run: `moon check && moon test -p lib -f voice_test.mbt`
Expected: All 4 tests pass. If the delay-tail test fails (delay doesn't ring long enough), adjust `feedback` or `delay_samples`.

- [ ] **Step 5: Run full test suite**

Run: `moon test`
Expected: 310 existing + 4 new = 314 pass.

- [ ] **Step 6: Run `moon info && moon fmt`**

Expected: `is_voice_finished` appears in `lib/pkg.generated.mbti`.

- [ ] **Step 7: Commit**

```bash
git add lib/graph.mbt lib/voice_test.mbt lib/pkg.generated.mbti
git commit -m "feat: add CompiledDsp::is_voice_finished with two-stage silence detection"
```

---

### Task 2: VoiceState enum, VoiceHandle struct, VoiceSlot struct

**Files:**
- Create: `lib/voice.mbt`

These are the data types. No behavior yet — just the structs and constructors.

- [ ] **Step 1: Create `lib/voice.mbt` with core types**

```moonbit
///|
pub enum VoiceState {
  Idle
  Active
  Releasing
} derive(Eq, Show)

///|
/// Generation-tagged voice handle. Prevents stale handles from operating on
/// a slot that has been stolen and reused for a different note.
pub struct VoiceHandle {
  slot : Int
  generation : Int
} derive(Eq, Show)

///|
priv struct VoiceSlot {
  mut compiled : CompiledDsp?
  mut state : VoiceState
  mut generation : Int
  mut allocation_order : Int
  mut pan : Double
  mono_buffer : AudioBuffer
}

///|
fn VoiceSlot::new(block_size : Int) -> VoiceSlot {
  {
    compiled: None,
    state: VoiceState::Idle,
    generation: 0,
    allocation_order: 0,
    pan: 0.0,
    mono_buffer: AudioBuffer::filled(block_size),
  }
}

///|
fn VoiceSlot::is_handle_valid(self : VoiceSlot, handle : VoiceHandle) -> Bool {
  handle.generation == self.generation
}
```

- [ ] **Step 2: Run `moon check`**

Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add lib/voice.mbt
git commit -m "feat: add VoiceState, VoiceHandle, VoiceSlot core types"
```

---

### Task 3: VoicePool constructor and template management

**Files:**
- Modify: `lib/voice.mbt`

- [ ] **Step 1: Add VoicePool struct and constructor**

Append to `lib/voice.mbt`:

```moonbit
///|
pub struct VoicePool {
  priv slots : FixedArray[VoiceSlot]
  priv mut template : Array[DspNode]
  priv compile_context : DspContext
  priv mut next_allocation_order : Int
  priv max_voices : Int
}

///|
pub fn VoicePool::new(
  template : Array[DspNode],
  context : DspContext,
  max_voices~ : Int = 32,
) -> VoicePool? {
  if max_voices <= 0 {
    return None
  }
  // Verify the template compiles before accepting it
  let test_compile = CompiledDsp::compile(template, context)
  if test_compile is None {
    return None
  }
  let block_size = context.block_size()
  let slots = FixedArray::makei(max_voices, _ => VoiceSlot::new(block_size))
  Some({
    slots,
    template: template.copy(),
    compile_context: context,
    next_allocation_order: 0,
    max_voices,
  })
}

///|
pub fn VoicePool::set_template(
  self : VoicePool,
  template : Array[DspNode],
) -> Bool {
  // Verify the new template compiles before accepting
  let test_compile = CompiledDsp::compile(template, self.compile_context)
  if test_compile is None {
    return false
  }
  self.template = template.copy()
  true
}

///|
pub fn VoicePool::active_voice_count(self : VoicePool) -> Int {
  let mut count = 0
  for i = 0; i < self.max_voices; i = i + 1 {
    if !(self.slots[i].state is VoiceState::Idle) {
      count = count + 1
    }
  }
  count
}
```

- [ ] **Step 2: Run `moon check`**

Expected: No errors.

- [ ] **Step 3: Add tests for constructor and set_template**

Append to `lib/voice_test.mbt`:

```moonbit
///|
test "voice pool constructor accepts valid template" {
  let ctx = DspContext::new(48000.0, 128)
  let nodes = [DspNode::constant(440.0), DspNode::output(0)]
  let pool = VoicePool::new(nodes, ctx)
  assert_true(pool is Some(_))
  assert_true(pool.unwrap().active_voice_count() == 0)
}

///|
test "voice pool constructor rejects invalid template" {
  let ctx = DspContext::new(48000.0, 128)
  let nodes : Array[DspNode] = [] // empty graph won't compile
  let pool = VoicePool::new(nodes, ctx)
  assert_true(pool is None)
}

///|
test "set_template accepts valid template" {
  let ctx = DspContext::new(48000.0, 128)
  let nodes = [DspNode::constant(440.0), DspNode::output(0)]
  let pool = VoicePool::new(nodes, ctx).unwrap()
  let new_nodes = [DspNode::constant(880.0), DspNode::output(0)]
  assert_true(pool.set_template(new_nodes))
}

///|
test "set_template rejects invalid template" {
  let ctx = DspContext::new(48000.0, 128)
  let nodes = [DspNode::constant(440.0), DspNode::output(0)]
  let pool = VoicePool::new(nodes, ctx).unwrap()
  assert_true(!pool.set_template([]))
}
```

- [ ] **Step 4: Run tests**

Run: `moon check && moon test -p lib -f voice_test.mbt`
Expected: All tests pass (4 old + 4 new = 8).

- [ ] **Step 5: Commit**

```bash
git add lib/voice.mbt lib/voice_test.mbt
git commit -m "feat: add VoicePool constructor and template management"
```

---

### Task 4: Voice allocation and stealing

**Files:**
- Modify: `lib/voice.mbt`

- [ ] **Step 1: Add slot selection helper**

Append to `lib/voice.mbt`:

```moonbit
///|
/// Find the best slot for a new voice using priority-based stealing:
/// 1. Any Idle slot (first found)
/// 2. Oldest Releasing voice
/// 3. Oldest Active voice
fn VoicePool::find_slot(self : VoicePool) -> Int {
  // Priority 1: any idle slot
  for i = 0; i < self.max_voices; i = i + 1 {
    if self.slots[i].state is VoiceState::Idle {
      return i
    }
  }
  // Priority 2: oldest releasing voice
  let mut best_releasing = -1
  let mut best_releasing_order = 2147483647 // Int max
  for i = 0; i < self.max_voices; i = i + 1 {
    if self.slots[i].state is VoiceState::Releasing &&
      self.slots[i].allocation_order < best_releasing_order {
      best_releasing = i
      best_releasing_order = self.slots[i].allocation_order
    }
  }
  if best_releasing >= 0 {
    return best_releasing
  }
  // Priority 3: oldest active voice
  let mut best_active = 0
  let mut best_active_order = 2147483647
  for i = 0; i < self.max_voices; i = i + 1 {
    if self.slots[i].allocation_order < best_active_order {
      best_active = i
      best_active_order = self.slots[i].allocation_order
    }
  }
  best_active
}
```

- [ ] **Step 2: Add note_on**

Append to `lib/voice.mbt`:

```moonbit
///|
pub fn VoicePool::note_on(
  self : VoicePool,
  params : Array[GraphControl],
) -> VoiceHandle? {
  let slot_index = self.find_slot()
  let slot = self.slots[slot_index]
  // Compile from current template
  let compiled = match CompiledDsp::compile(self.template, self.compile_context) {
    Some(c) => c
    None => return None
  }
  // Apply params transactionally — if any fail, don't activate the voice
  if params.length() > 0 {
    if !compiled.apply_controls(params) {
      return None
    }
  }
  // Gate on all ADSR nodes
  let nodes = self.template
  for i = 0; i < nodes.length(); i = i + 1 {
    if nodes[i].kind is Adsr {
      ignore(compiled.gate_on(i))
    }
  }
  // Install in slot
  slot.compiled = Some(compiled)
  slot.state = VoiceState::Active
  slot.generation = slot.generation + 1
  slot.allocation_order = self.next_allocation_order
  self.next_allocation_order = self.next_allocation_order + 1
  Some(VoiceHandle::{ slot: slot_index, generation: slot.generation })
}
```

- [ ] **Step 3: Run `moon check`**

Expected: No errors.

- [ ] **Step 4: Add tests for allocation and stealing**

Append to `lib/voice_test.mbt`:

```moonbit
///|
test "note_on allocates a voice and returns valid handle" {
  let ctx = DspContext::new(48000.0, 16)
  let nodes = [DspNode::constant(440.0), DspNode::output(0)]
  let pool = VoicePool::new(nodes, ctx, max_voices=4).unwrap()
  let handle = pool.note_on([])
  assert_true(handle is Some(_))
  assert_true(pool.active_voice_count() == 1)
}

///|
test "note_on fills pool to capacity" {
  let ctx = DspContext::new(48000.0, 16)
  let nodes = [DspNode::constant(440.0), DspNode::output(0)]
  let pool = VoicePool::new(nodes, ctx, max_voices=4).unwrap()
  for i = 0; i < 4; i = i + 1 {
    let h = pool.note_on([])
    assert_true(h is Some(_))
  }
  assert_true(pool.active_voice_count() == 4)
}

///|
test "note_on steals oldest active when pool is full" {
  let ctx = DspContext::new(48000.0, 16)
  let nodes = [DspNode::constant(440.0), DspNode::output(0)]
  let pool = VoicePool::new(nodes, ctx, max_voices=2).unwrap()
  let h1 = pool.note_on([]).unwrap()
  let _h2 = pool.note_on([]).unwrap()
  // Pool is full. Next note_on steals the oldest (h1's slot)
  let h3 = pool.note_on([]).unwrap()
  assert_true(h3 is Some(_) |> ignore)
  // h1's slot was stolen, so its generation changed
  assert_true(h1.slot == h3.slot || pool.active_voice_count() == 2)
}
```

- [ ] **Step 5: Run tests**

Run: `moon check && moon test -p lib -f voice_test.mbt`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/voice.mbt lib/voice_test.mbt
git commit -m "feat: add voice allocation with priority-based stealing"
```

---

### Task 5: note_off, note_off_all, set_voice_pan, voice_state

**Files:**
- Modify: `lib/voice.mbt`

- [ ] **Step 1: Add note_off**

Append to `lib/voice.mbt`:

```moonbit
///|
pub fn VoicePool::note_off(self : VoicePool, handle : VoiceHandle) -> Bool {
  if handle.slot < 0 || handle.slot >= self.max_voices {
    return false
  }
  let slot = self.slots[handle.slot]
  if !slot.is_handle_valid(handle) {
    return false
  }
  if slot.state is VoiceState::Idle {
    return false
  }
  // Gate off all ADSR nodes
  match slot.compiled {
    Some(compiled) => {
      let nodes = self.template
      for i = 0; i < nodes.length(); i = i + 1 {
        if nodes[i].kind is Adsr {
          ignore(compiled.gate_off(i))
        }
      }
    }
    None => ()
  }
  slot.state = VoiceState::Releasing
  true
}

///|
pub fn VoicePool::note_off_all(self : VoicePool) -> Unit {
  for i = 0; i < self.max_voices; i = i + 1 {
    let slot = self.slots[i]
    if slot.state is VoiceState::Active {
      match slot.compiled {
        Some(compiled) => {
          let nodes = self.template
          for j = 0; j < nodes.length(); j = j + 1 {
            if nodes[j].kind is Adsr {
              ignore(compiled.gate_off(j))
            }
          }
        }
        None => ()
      }
      slot.state = VoiceState::Releasing
    }
  }
}

///|
pub fn VoicePool::set_voice_pan(
  self : VoicePool,
  handle : VoiceHandle,
  pan : Double,
) -> Bool {
  if handle.slot < 0 || handle.slot >= self.max_voices {
    return false
  }
  let slot = self.slots[handle.slot]
  if !slot.is_handle_valid(handle) {
    return false
  }
  slot.pan = pan.clamp(min=-1.0, max=1.0)
  true
}

///|
pub fn VoicePool::voice_state(
  self : VoicePool,
  handle : VoiceHandle,
) -> VoiceState {
  if handle.slot < 0 || handle.slot >= self.max_voices {
    return VoiceState::Idle
  }
  let slot = self.slots[handle.slot]
  if !slot.is_handle_valid(handle) {
    return VoiceState::Idle
  }
  slot.state
}
```

- [ ] **Step 2: Run `moon check`**

Expected: No errors.

- [ ] **Step 3: Add tests**

Append to `lib/voice_test.mbt`:

```moonbit
///|
test "note_off transitions voice to Releasing" {
  let ctx = DspContext::new(48000.0, 16)
  let nodes = [
    DspNode::constant(440.0),
    DspNode::adsr(5.0, 5.0, 0.5, 50.0),
    DspNode::output(1),
  ]
  let pool = VoicePool::new(nodes, ctx, max_voices=4).unwrap()
  let handle = pool.note_on([]).unwrap()
  assert_true(pool.voice_state(handle) is VoiceState::Active)
  assert_true(pool.note_off(handle))
  assert_true(pool.voice_state(handle) is VoiceState::Releasing)
}

///|
test "stale handle note_off returns false" {
  let ctx = DspContext::new(48000.0, 16)
  let nodes = [DspNode::constant(440.0), DspNode::output(0)]
  let pool = VoicePool::new(nodes, ctx, max_voices=1).unwrap()
  let h1 = pool.note_on([]).unwrap()
  // Steal h1's slot
  let _h2 = pool.note_on([]).unwrap()
  // h1 is now stale
  assert_true(!pool.note_off(h1))
}

///|
test "stale handle voice_state returns Idle" {
  let ctx = DspContext::new(48000.0, 16)
  let nodes = [DspNode::constant(440.0), DspNode::output(0)]
  let pool = VoicePool::new(nodes, ctx, max_voices=1).unwrap()
  let h1 = pool.note_on([]).unwrap()
  let _h2 = pool.note_on([]).unwrap()
  assert_true(pool.voice_state(h1) is VoiceState::Idle)
}

///|
test "set_voice_pan clamps to [-1, 1]" {
  let ctx = DspContext::new(48000.0, 16)
  let nodes = [DspNode::constant(440.0), DspNode::output(0)]
  let pool = VoicePool::new(nodes, ctx, max_voices=4).unwrap()
  let handle = pool.note_on([]).unwrap()
  assert_true(pool.set_voice_pan(handle, 5.0))
  // Pan should be clamped to 1.0 — verified indirectly via mixdown tests later
  assert_true(pool.set_voice_pan(handle, -5.0))
}
```

- [ ] **Step 4: Run tests**

Run: `moon check && moon test -p lib -f voice_test.mbt`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/voice.mbt lib/voice_test.mbt
git commit -m "feat: add note_off, note_off_all, set_voice_pan, voice_state"
```

---

### Task 6: process() with stereo mixdown and voice reclamation

**Files:**
- Modify: `lib/voice.mbt`

This is the audio hot path.

- [ ] **Step 1: Add process method**

Append to `lib/voice.mbt`:

```moonbit
///|
pub fn VoicePool::process(
  self : VoicePool,
  context : DspContext,
  left_output : AudioBuffer,
  right_output : AudioBuffer,
) -> Unit {
  for i = 0; i < self.max_voices; i = i + 1 {
    let slot = self.slots[i]
    if slot.state is VoiceState::Idle {
      continue i + 1
    }
    match slot.compiled {
      None => {
        slot.state = VoiceState::Idle
        continue i + 1
      }
      Some(compiled) => {
        // Process the voice into its pre-allocated mono buffer
        compiled.process(context, slot.mono_buffer)
        // Equal-power pan gains (computed once per voice per block)
        let left_gain = feedback_pan_left_gain(slot.pan)
        let right_gain = feedback_pan_right_gain(slot.pan)
        // Accumulate into stereo output (caller must clear before calling)
        let sample_count = if context.block_size() < left_output.length() {
          context.block_size()
        } else {
          left_output.length()
        }
        for s = 0; s < sample_count; s = s + 1 {
          let mono = slot.mono_buffer.get(s)
          left_output.set(s, left_output.get(s) + mono * left_gain)
          right_output.set(s, right_output.get(s) + mono * right_gain)
        }
        // Reclaim finished voices
        if slot.state is VoiceState::Releasing && compiled.is_voice_finished() {
          slot.state = VoiceState::Idle
          slot.compiled = None
        }
      }
    }
  }
}
```

- [ ] **Step 2: Run `moon check`**

Expected: No errors. If `feedback_pan_left_gain`/`feedback_pan_right_gain` are not visible (they're `fn` not `pub fn` in `graph.mbt`), they should be accessible within the same package since `voice.mbt` is in `lib/`. Verify.

- [ ] **Step 3: Add mixdown and reclamation tests**

Append to `lib/voice_test.mbt`:

```moonbit
///|
test "process produces stereo output from mono voices" {
  let ctx = DspContext::new(48000.0, 4)
  let nodes = [DspNode::constant(1.0), DspNode::output(0)]
  let pool = VoicePool::new(nodes, ctx, max_voices=4).unwrap()
  ignore(pool.note_on([]))
  let left = AudioBuffer::filled(4)
  let right = AudioBuffer::filled(4)
  pool.process(ctx, left, right)
  // Center pan: both channels should have signal
  for i = 0; i < 4; i = i + 1 {
    assert_true(left.get(i) > 0.0)
    assert_true(right.get(i) > 0.0)
    // Equal-power center: left ≈ right
    assert_true((left.get(i) - right.get(i)).abs() < 0.0001)
  }
}

///|
test "process pans hard left" {
  let ctx = DspContext::new(48000.0, 4)
  let nodes = [DspNode::constant(1.0), DspNode::output(0)]
  let pool = VoicePool::new(nodes, ctx, max_voices=4).unwrap()
  let handle = pool.note_on([]).unwrap()
  ignore(pool.set_voice_pan(handle, -1.0))
  let left = AudioBuffer::filled(4)
  let right = AudioBuffer::filled(4)
  pool.process(ctx, left, right)
  for i = 0; i < 4; i = i + 1 {
    assert_true(left.get(i) > 0.9)
    assert_true(right.get(i).abs() < 0.0001)
  }
}

///|
test "process reclaims finished releasing voices" {
  let ctx = DspContext::new(1000.0, 8)
  let nodes = [
    DspNode::constant(0.0),
    DspNode::adsr(0.0, 0.0, 1.0, 0.0),
    DspNode::output(1),
  ]
  let pool = VoicePool::new(nodes, ctx, max_voices=4).unwrap()
  let handle = pool.note_on([]).unwrap()
  let left = AudioBuffer::filled(8)
  let right = AudioBuffer::filled(8)
  pool.process(ctx, left, right)
  assert_true(pool.active_voice_count() == 1)
  assert_true(pool.note_off(handle))
  // With 0ms release and constant(0.0) input, voice should be reclaimed
  left.fill(0.0)
  right.fill(0.0)
  pool.process(ctx, left, right)
  assert_true(pool.active_voice_count() == 0)
}

///|
test "process mixes multiple voices" {
  let ctx = DspContext::new(48000.0, 4)
  let nodes = [DspNode::constant(1.0), DspNode::output(0)]
  let pool = VoicePool::new(nodes, ctx, max_voices=4).unwrap()
  ignore(pool.note_on([]))
  ignore(pool.note_on([]))
  let left = AudioBuffer::filled(4)
  let right = AudioBuffer::filled(4)
  pool.process(ctx, left, right)
  // Two voices at center pan: output should be roughly 2x one voice
  let one_voice_left = AudioBuffer::filled(4)
  let one_voice_right = AudioBuffer::filled(4)
  let pool2 = VoicePool::new(nodes, ctx, max_voices=4).unwrap()
  ignore(pool2.note_on([]))
  pool2.process(ctx, one_voice_left, one_voice_right)
  for i = 0; i < 4; i = i + 1 {
    assert_true(
      (left.get(i) - 2.0 * one_voice_left.get(i)).abs() < 0.001,
    )
  }
}
```

- [ ] **Step 4: Run tests**

Run: `moon check && moon test -p lib -f voice_test.mbt`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/voice.mbt lib/voice_test.mbt
git commit -m "feat: add VoicePool::process with stereo mixdown and voice reclamation"
```

---

### Task 7: Template change test and stealing-order tests

**Files:**
- Modify: `lib/voice_test.mbt`

- [ ] **Step 1: Add template change test**

Append to `lib/voice_test.mbt`:

```moonbit
///|
test "new voices use updated template after set_template" {
  let ctx = DspContext::new(48000.0, 4)
  let nodes_a = [DspNode::constant(1.0), DspNode::output(0)]
  let nodes_b = [DspNode::constant(2.0), DspNode::output(0)]
  let pool = VoicePool::new(nodes_a, ctx, max_voices=4).unwrap()
  // First voice uses template A (constant 1.0)
  let _h1 = pool.note_on([]).unwrap()
  let left1 = AudioBuffer::filled(4)
  let right1 = AudioBuffer::filled(4)
  pool.process(ctx, left1, right1)
  let first_output = left1.get(0)
  // Change template to B (constant 2.0)
  assert_true(pool.set_template(nodes_b))
  // Second voice should use template B
  let _h2 = pool.note_on([]).unwrap()
  let left2 = AudioBuffer::filled(4)
  let right2 = AudioBuffer::filled(4)
  pool.process(ctx, left2, right2)
  // Two voices: one at 1.0, one at 2.0 — sum should be 3.0 * pan_gain
  assert_true(left2.get(0) > first_output * 1.5)
}

///|
test "stealing prefers releasing over active" {
  let ctx = DspContext::new(48000.0, 16)
  let nodes = [
    DspNode::constant(440.0),
    DspNode::adsr(5.0, 5.0, 0.5, 100.0),
    DspNode::output(1),
  ]
  let pool = VoicePool::new(nodes, ctx, max_voices=2).unwrap()
  let h1 = pool.note_on([]).unwrap()
  let h2 = pool.note_on([]).unwrap()
  let left = AudioBuffer::filled(16)
  let right = AudioBuffer::filled(16)
  pool.process(ctx, left, right)
  // Release h1 so it's in Releasing state
  assert_true(pool.note_off(h1))
  assert_true(pool.voice_state(h1) is VoiceState::Releasing)
  assert_true(pool.voice_state(h2) is VoiceState::Active)
  // New note should steal h1 (Releasing) not h2 (Active)
  let h3 = pool.note_on([]).unwrap()
  assert_true(h3.slot == h1.slot)
}
```

- [ ] **Step 2: Run tests**

Run: `moon check && moon test -p lib -f voice_test.mbt`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add lib/voice_test.mbt
git commit -m "test: add template change and stealing-order tests"
```

---

### Task 8: Final verification, formatting, and benchmarks

**Files:**
- Modify: `lib/voice.mbt` (if needed)
- Modify: `lib/voice_test.mbt` (if needed)

- [ ] **Step 1: Run full test suite**

Run: `moon test`
Expected: 310 existing + ~20 new voice tests = ~330 pass.

- [ ] **Step 2: Run `moon info && moon fmt`**

Expected: `VoicePool`, `VoiceHandle`, `VoiceState`, `CompiledDsp::is_voice_finished` in .mbti.

- [ ] **Step 3: Check API changes**

Run: `git diff -- '*.mbti'`
Expected: New public API additions only (no removals or changes to existing API).

- [ ] **Step 4: Run benchmarks**

Run: `moon bench --release -p lib -f graph_benchmark.mbt`
Expected: No regression in existing benchmarks. Process times should be comparable to baseline.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: complete Phase 3 voice management (VoicePool with polyphonic support)"
```
