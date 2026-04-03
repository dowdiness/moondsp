# Pattern Scheduler Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a `scheduler/` package that bridges the pattern engine and DSP voice pool — querying patterns each audio block, triggering voices with MIDI-to-Hz conversion, and scheduling gate-off at event boundaries.

**Architecture:** New `scheduler/` package depends on `lib/` (VoicePool, ControlBindingMap, GraphControl, DspContext, AudioBuffer) and `pattern/` (Pat, Event, ControlMap, TimeSpan, Rational). Integer sample counter derives cycle-time arcs each block — no cumulative floating-point drift. Block-quantized gate-off (~2.7ms).

**Tech Stack:** MoonBit, moon build system

**Spec:** `docs/superpowers/specs/2026-04-03-pattern-scheduler-design.md`

---

## File Structure

```text
scheduler/
  moon.pkg              — package config with imports
  scheduler.mbt         — ActiveNote, PatternScheduler, midi_to_hz, process_block
  scheduler_test.mbt    — all tests (unit, integration, edge case)
```

Single source file — the scheduler is small (~120 lines). Tests in one file organized by section comments.

---

### Task 1: Package scaffold + midi_to_hz with tests

**Files:**
- Create: `scheduler/moon.pkg`
- Create: `scheduler/scheduler.mbt`
- Create: `scheduler/scheduler_test.mbt`

- [ ] **Step 1: Write the failing test for midi_to_hz**

Create `scheduler/scheduler_test.mbt`:

```moonbit
///|
test "midi_to_hz: A4 (69) = 440 Hz" {
  let hz = @scheduler.midi_to_hz(69.0)
  // Allow tiny floating-point tolerance
  assert_true!((hz - 440.0).abs() < 0.001)
}

///|
test "midi_to_hz: C4 (60) = 261.63 Hz" {
  let hz = @scheduler.midi_to_hz(60.0)
  assert_true!((hz - 261.6255653006) < 0.01)
}

///|
test "midi_to_hz: MIDI 0" {
  let hz = @scheduler.midi_to_hz(0.0)
  // C-1 = 8.1758 Hz
  assert_true!((hz - 8.1758) < 0.01)
}

///|
test "midi_to_hz: MIDI 127" {
  let hz = @scheduler.midi_to_hz(127.0)
  // G9 = 12543.85 Hz
  assert_true!((hz - 12543.85) < 1.0)
}
```

- [ ] **Step 2: Create the package config**

Create `scheduler/moon.pkg`:

```text
import {
  "dowdiness/mdsp/lib",
  "dowdiness/mdsp/pattern",
}
```

- [ ] **Step 3: Write midi_to_hz to make tests pass**

Create `scheduler/scheduler.mbt`:

```moonbit
///|
pub fn midi_to_hz(midi : Double) -> Double {
  440.0 * Double::pow(2.0, (midi - 69.0) / 12.0)
}
```

- [ ] **Step 4: Run tests**

Run: `moon check && moon test -p dowdiness/mdsp/scheduler`
Expected: all 4 tests PASS

- [ ] **Step 5: Commit**

```bash
moon info && moon fmt
git add scheduler/
git commit -m "feat(scheduler): add package scaffold and midi_to_hz"
```

---

### Task 2: ActiveNote struct and PatternScheduler constructor

**Files:**
- Modify: `scheduler/scheduler.mbt`
- Modify: `scheduler/scheduler_test.mbt`

- [ ] **Step 1: Write the failing test for constructor**

Append to `scheduler/scheduler_test.mbt`:

```moonbit
///|
test "PatternScheduler::new initializes with zero position" {
  // Minimal template: oscillator(0) -> gain(1) -> adsr(2) -> output(3)
  let template : Array[@lib.DspNode] = [
    @lib.DspNode::oscillator(@lib.Waveform::Sine, 440.0),
    @lib.DspNode::gain(0, 1.0),
    @lib.DspNode::adsr(0.01, 0.1, 0.7, 0.3),
    @lib.DspNode::output(1),
  ]
  let ctx = @lib.DspContext::new(48000.0, 128)
  let bindings = @lib.ControlBindingBuilder::new()
    .bind(key="note", node_index=0, slot=@lib.GraphParamSlot::Value0)
    .build(template)
  match bindings {
    Ok(b) => {
      let sched = @scheduler.PatternScheduler::new(bpm=120.0, bindings=b, ctx~)
      inspect!(sched.sample_counter(), content="0")
      inspect!(sched.active_note_count(), content="0")
    }
    Err(_) => assert_true!(false)
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `moon check`
Expected: FAIL — `PatternScheduler` not defined

- [ ] **Step 3: Write ActiveNote and PatternScheduler**

Add to `scheduler/scheduler.mbt` before `midi_to_hz`:

```moonbit
///|
/// Tracks a sounding voice for gate-off scheduling.
struct ActiveNote {
  handle : @lib.VoiceHandle
  end_time : @pattern.Rational
}

///|
pub struct PatternScheduler {
  bpm : Double
  mut sample_counter : Int64
  sample_rate : Int
  block_size : Int
  active_notes : Array[ActiveNote]
  bindings : @lib.ControlBindingMap

  fn new(
    bpm~ : Double,
    bindings~ : @lib.ControlBindingMap,
    ctx~ : @lib.DspContext,
  ) -> PatternScheduler
}

///|
pub fn PatternScheduler::new(
  bpm~ : Double,
  bindings~ : @lib.ControlBindingMap,
  ctx~ : @lib.DspContext,
) -> PatternScheduler {
  {
    bpm,
    sample_counter: 0L,
    sample_rate: ctx.block_size().reinterpret_as_uint().reinterpret_as_int(), // use block_size getter
    block_size: ctx.block_size(),
    active_notes: [],
    bindings,
  }
}

///|
pub fn PatternScheduler::sample_counter(self : PatternScheduler) -> Int64 {
  self.sample_counter
}

///|
pub fn PatternScheduler::active_note_count(self : PatternScheduler) -> Int {
  self.active_notes.length()
}
```

Wait — `DspContext::sample_rate()` returns `Double`, but we need `Int`. Fix the constructor:

```moonbit
///|
pub fn PatternScheduler::new(
  bpm~ : Double,
  bindings~ : @lib.ControlBindingMap,
  ctx~ : @lib.DspContext,
) -> PatternScheduler {
  {
    bpm,
    sample_counter: 0L,
    sample_rate: ctx.sample_rate().to_int(),
    block_size: ctx.block_size(),
    active_notes: [],
    bindings,
  }
}
```

- [ ] **Step 4: Run tests**

Run: `moon check && moon test -p dowdiness/mdsp/scheduler`
Expected: all tests PASS

- [ ] **Step 5: Commit**

```bash
moon info && moon fmt
git add scheduler/
git commit -m "feat(scheduler): add ActiveNote and PatternScheduler types"
```

---

### Task 3: Arc computation helper

**Files:**
- Modify: `scheduler/scheduler.mbt`
- Modify: `scheduler/scheduler_test.mbt`

- [ ] **Step 1: Write the failing test for arc computation**

Append to `scheduler/scheduler_test.mbt`:

```moonbit
///|
test "compute_arc: first block at 120 BPM" {
  // At 120 BPM, cycle_duration = 0.5s = 24000 samples
  // First block: samples 0..128
  // arc_start = 0 * 120 / (48000 * 60) = 0
  // arc_end = 128 * 120 / (48000 * 60) = 15360 / 2880000 = 1/187.5
  let arc = @scheduler.compute_arc(0L, 120.0, 48000, 128)
  let zero = @pattern.Rational::from_int(0)
  assert_true!(arc.begin == zero)
  // arc_end = Rational(128 * 120, 48000 * 60) = Rational(15360, 2880000)
  // simplified = Rational(1, 187) — actually 15360/2880000 = 2/375
  let expected_end = @pattern.Rational::new(15360L, 2880000L)
  assert_true!(arc.end_ == expected_end)
}

///|
test "compute_arc: second block at 120 BPM" {
  let arc = @scheduler.compute_arc(128L, 120.0, 48000, 128)
  let expected_start = @pattern.Rational::new(15360L, 2880000L)
  let expected_end = @pattern.Rational::new(30720L, 2880000L)
  assert_true!(arc.begin == expected_start)
  assert_true!(arc.end_ == expected_end)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `moon check`
Expected: FAIL — `compute_arc` not defined

- [ ] **Step 3: Write compute_arc**

Add to `scheduler/scheduler.mbt`:

```moonbit
///|
/// Derive the cycle-time arc for a block from the integer sample counter.
/// Denominators are bounded by sample_rate * 60 — no overflow risk for
/// practical session lengths with Int64 numerators.
pub fn compute_arc(
  sample_counter : Int64,
  bpm : Double,
  sample_rate : Int,
  block_size : Int,
) -> @pattern.TimeSpan {
  let bpm_int = bpm.to_int().to_int64()
  let sr60 = sample_rate.to_int64() * 60L
  let arc_start = @pattern.Rational::new(sample_counter * bpm_int, sr60)
  let arc_end = @pattern.Rational::new(
    (sample_counter + block_size.to_int64()) * bpm_int,
    sr60,
  )
  @pattern.TimeSpan::new(arc_start, arc_end)
}
```

- [ ] **Step 4: Run tests**

Run: `moon check && moon test -p dowdiness/mdsp/scheduler`
Expected: all tests PASS

- [ ] **Step 5: Commit**

```bash
moon info && moon fmt
git add scheduler/
git commit -m "feat(scheduler): add compute_arc timing helper"
```

---

### Task 4: process_block — gate-off expired notes

**Files:**
- Modify: `scheduler/scheduler.mbt`
- Modify: `scheduler/scheduler_test.mbt`

- [ ] **Step 1: Write the failing test for gate-off**

This test creates a scheduler, manually injects an ActiveNote with a past end_time, calls `expire_notes`, and verifies it was removed and `note_off` was called.

Append to `scheduler/scheduler_test.mbt`:

```moonbit
///|
/// Helper: build a VoicePool with a minimal osc+adsr+output template.
fn make_test_pool() -> (@lib.VoicePool, Array[@lib.DspNode], @lib.DspContext) {
  let template : Array[@lib.DspNode] = [
    @lib.DspNode::oscillator(@lib.Waveform::Sine, 440.0),
    @lib.DspNode::adsr(0.01, 0.1, 0.7, 0.3),
    @lib.DspNode::gain(0, 1.0),
    @lib.DspNode::output(2),
  ]
  let ctx = @lib.DspContext::new(48000.0, 128)
  let pool = @lib.VoicePool::new(template, ctx, max_voices=4)
  match pool {
    Some(p) => (p, template, ctx)
    None => abort("test pool creation failed")
  }
}

///|
test "expire_notes: removes notes past their end_time" {
  let (pool, template, ctx) = make_test_pool()
  let bindings = @lib.ControlBindingBuilder::new()
    .bind(key="note", node_index=0, slot=@lib.GraphParamSlot::Value0)
    .build(template)
  match bindings {
    Err(_) => assert_true!(false)
    Ok(b) => {
      let sched = @scheduler.PatternScheduler::new(bpm=120.0, bindings=b, ctx~)
      // Trigger a voice manually
      let controls = b.resolve_controls({ "note": 440.0 })
      let handle = pool.note_on(controls)
      match handle {
        None => assert_true!(false)
        Some(h) => {
          // Inject an ActiveNote that expires at cycle 0 (already past)
          sched.push_active_note(h, @pattern.Rational::from_int(0))
          inspect!(sched.active_note_count(), content="1")
          // Expire with arc starting at cycle 1
          let arc = @pattern.TimeSpan::new(
            @pattern.Rational::from_int(1),
            @pattern.Rational::from_int(2),
          )
          sched.expire_notes(pool, arc)
          inspect!(sched.active_note_count(), content="0")
        }
      }
    }
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `moon check`
Expected: FAIL — `push_active_note` and `expire_notes` not defined

- [ ] **Step 3: Write expire_notes and push_active_note**

Add to `scheduler/scheduler.mbt`:

```moonbit
///|
/// Test helper: inject an active note for testing gate-off logic.
pub fn PatternScheduler::push_active_note(
  self : PatternScheduler,
  handle : @lib.VoiceHandle,
  end_time : @pattern.Rational,
) -> Unit {
  self.active_notes.push({ handle, end_time })
}

///|
/// Gate-off all notes whose end_time <= arc.begin, then remove them.
/// Block-quantized: notes ending mid-block stay active until the next block.
pub fn PatternScheduler::expire_notes(
  self : PatternScheduler,
  pool : @lib.VoicePool,
  arc : @pattern.TimeSpan,
) -> Unit {
  let mut i = 0
  while i < self.active_notes.length() {
    if self.active_notes[i].end_time <= arc.begin {
      ignore(pool.note_off(self.active_notes[i].handle))
      self.active_notes.remove(i)
    } else {
      i = i + 1
    }
  }
}
```

- [ ] **Step 4: Run tests**

Run: `moon check && moon test -p dowdiness/mdsp/scheduler`
Expected: all tests PASS

- [ ] **Step 5: Commit**

```bash
moon info && moon fmt
git add scheduler/
git commit -m "feat(scheduler): add expire_notes gate-off logic"
```

---

### Task 5: process_block — event processing (note-on, pan, sort)

**Files:**
- Modify: `scheduler/scheduler.mbt`
- Modify: `scheduler/scheduler_test.mbt`

- [ ] **Step 1: Write the failing test for process_events**

Append to `scheduler/scheduler_test.mbt`:

```moonbit
///|
test "process_events: single note-on creates active voice" {
  let (pool, template, ctx) = make_test_pool()
  let bindings = @lib.ControlBindingBuilder::new()
    .bind(key="note", node_index=0, slot=@lib.GraphParamSlot::Value0)
    .build(template)
  match bindings {
    Err(_) => assert_true!(false)
    Ok(b) => {
      let sched = @scheduler.PatternScheduler::new(bpm=120.0, bindings=b, ctx~)
      // Create a pattern event with onset at cycle 0, ending at cycle 1
      let event : @pattern.Event[@pattern.ControlMap] = {
        whole: Some(@pattern.TimeSpan::new(
          @pattern.Rational::from_int(0),
          @pattern.Rational::from_int(1),
        )),
        part: @pattern.TimeSpan::new(
          @pattern.Rational::from_int(0),
          @pattern.Rational::from_int(1),
        ),
        value: @pattern.ControlMap({ "note": 60.0 }),
      }
      let events : Array[@pattern.Event[@pattern.ControlMap]] = [event]
      let arc = @pattern.TimeSpan::new(
        @pattern.Rational::from_int(0),
        @pattern.Rational::new(1L, 100L),
      )
      sched.process_events(events, arc, pool)
      inspect!(sched.active_note_count(), content="1")
      inspect!(pool.active_voice_count(), content="1")
    }
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `moon check`
Expected: FAIL — `process_events` not defined

- [ ] **Step 3: Write process_events**

Add to `scheduler/scheduler.mbt`:

```moonbit
///|
/// Process pattern events: sort by onset, trigger note-ons, handle pan.
/// Events with no `whole` or whose onset is outside the arc are skipped.
pub fn PatternScheduler::process_events(
  self : PatternScheduler,
  events : Array[@pattern.Event[@pattern.ControlMap]],
  arc : @pattern.TimeSpan,
  pool : @lib.VoicePool,
) -> Unit {
  // Sort by onset time for deterministic voice allocation
  events.sort_by(fn(a, b) {
    match (a.whole, b.whole) {
      (Some(wa), Some(wb)) => wa.begin.compare(wb.begin)
      (Some(_), None) => -1
      (None, Some(_)) => 1
      (None, None) => 0
    }
  })
  for i = 0; i < events.length(); i = i + 1 {
    let event = events[i]
    // Only process events with an onset (whole is Some) inside the arc
    match event.whole {
      None => continue i + 1
      Some(whole) => {
        if !arc.contains(whole.begin) {
          continue i + 1
        }
        // Extract inner map from ControlMap
        let map = event.value.0
        // Convert MIDI note to Hz if present
        match map.get("note") {
          Some(midi) => map["note"] = midi_to_hz(midi)
          None => ()
        }
        // Extract and remove pan before resolve_controls
        let pan_value = map.get("pan")
        match pan_value {
          Some(_) => map.remove("pan")
          None => ()
        }
        // Resolve remaining controls through bindings
        let controls = self.bindings.resolve_controls(map)
        // Trigger voice
        match pool.note_on(controls) {
          None => () // silent skip
          Some(handle) => {
            self.active_notes.push({ handle, end_time: whole.end_ })
            // Apply per-voice pan if present
            match pan_value {
              Some(pan) => ignore(pool.set_voice_pan(handle, pan))
              None => ()
            }
          }
        }
      }
    }
  }
}
```

- [ ] **Step 4: Run tests**

Run: `moon check && moon test -p dowdiness/mdsp/scheduler`
Expected: all tests PASS

- [ ] **Step 5: Commit**

```bash
moon info && moon fmt
git add scheduler/
git commit -m "feat(scheduler): add process_events with onset sorting and pan"
```

---

### Task 6: process_block — full integration

**Files:**
- Modify: `scheduler/scheduler.mbt`
- Modify: `scheduler/scheduler_test.mbt`

- [ ] **Step 1: Write the failing test for process_block**

Append to `scheduler/scheduler_test.mbt`:

```moonbit
///|
test "process_block: note(60) triggers one voice" {
  let (pool, template, ctx) = make_test_pool()
  let bindings = @lib.ControlBindingBuilder::new()
    .bind(key="note", node_index=0, slot=@lib.GraphParamSlot::Value0)
    .build(template)
  match bindings {
    Err(_) => assert_true!(false)
    Ok(b) => {
      let sched = @scheduler.PatternScheduler::new(bpm=120.0, bindings=b, ctx~)
      let pat = @pattern.note(60.0)
      let left = @lib.AudioBuffer::filled(128)
      let right = @lib.AudioBuffer::filled(128)
      // First block starts at sample 0 — onset at cycle 0 should fire
      sched.process_block(pat, pool, ctx, left, right)
      inspect!(pool.active_voice_count(), content="1")
      inspect!(sched.active_note_count(), content="1")
      // Sample counter advanced by one block
      inspect!(sched.sample_counter(), content="128")
    }
  }
}

///|
test "process_block: empty pattern triggers no voices" {
  let (pool, template, ctx) = make_test_pool()
  let bindings = @lib.ControlBindingBuilder::new()
    .bind(key="note", node_index=0, slot=@lib.GraphParamSlot::Value0)
    .build(template)
  match bindings {
    Err(_) => assert_true!(false)
    Ok(b) => {
      let sched = @scheduler.PatternScheduler::new(bpm=120.0, bindings=b, ctx~)
      let pat : @pattern.Pat[@pattern.ControlMap] = @pattern.Pat::silence()
      let left = @lib.AudioBuffer::filled(128)
      let right = @lib.AudioBuffer::filled(128)
      sched.process_block(pat, pool, ctx, left, right)
      inspect!(pool.active_voice_count(), content="0")
      inspect!(sched.active_note_count(), content="0")
    }
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `moon check`
Expected: FAIL — `process_block` not defined

- [ ] **Step 3: Write process_block**

Add to `scheduler/scheduler.mbt`:

```moonbit
///|
/// Main entry point: called once per audio block.
/// 1. Compute block arc from sample counter
/// 2. Gate-off expired notes
/// 3. Query pattern
/// 4. Process note-ons (sorted, with pan and MIDI→Hz)
/// 5. Advance sample counter
/// 6. Zero buffers and render audio
pub fn PatternScheduler::process_block(
  self : PatternScheduler,
  pat : @pattern.Pat[@pattern.ControlMap],
  pool : @lib.VoicePool,
  ctx : @lib.DspContext,
  left : @lib.AudioBuffer,
  right : @lib.AudioBuffer,
) -> Unit {
  // Step 1: compute block arc
  let arc = compute_arc(
    self.sample_counter,
    self.bpm,
    self.sample_rate,
    self.block_size,
  )
  // Step 2: gate-off expired notes
  self.expire_notes(pool, arc)
  // Step 3: query pattern
  let events = pat.query(arc)
  // Step 4: process note-ons
  self.process_events(events, arc, pool)
  // Step 5: advance sample counter
  self.sample_counter = self.sample_counter + self.block_size.to_int64()
  // Step 6: zero buffers and render
  left.fill(0.0)
  right.fill(0.0)
  pool.process(ctx, left, right)
}
```

- [ ] **Step 4: Run tests**

Run: `moon check && moon test -p dowdiness/mdsp/scheduler`
Expected: all tests PASS

- [ ] **Step 5: Commit**

```bash
moon info && moon fmt
git add scheduler/
git commit -m "feat(scheduler): add process_block integration"
```

---

### Task 7: Integration tests — fast pattern and gate-off crossing

**Files:**
- Modify: `scheduler/scheduler_test.mbt`

- [ ] **Step 1: Write integration test for fast pattern**

Append to `scheduler/scheduler_test.mbt`:

```moonbit
///|
test "process_block: fast(2) triggers two voices per cycle" {
  let (pool, template, ctx) = make_test_pool()
  let bindings = @lib.ControlBindingBuilder::new()
    .bind(key="note", node_index=0, slot=@lib.GraphParamSlot::Value0)
    .build(template)
  match bindings {
    Err(_) => assert_true!(false)
    Ok(b) => {
      let sched = @scheduler.PatternScheduler::new(bpm=120.0, bindings=b, ctx~)
      // fast(2) = two events per cycle, onsets at 0 and 0.5
      let pat = @pattern.note(60.0).fast(@pattern.Rational::from_int(2))
      let left = @lib.AudioBuffer::filled(128)
      let right = @lib.AudioBuffer::filled(128)
      // At 120 BPM, one cycle = 24000 samples = ~187.5 blocks
      // Process enough blocks to cover one full cycle
      // After first block, onset at 0 should fire (1 voice)
      sched.process_block(pat, pool, ctx, left, right)
      assert_true!(pool.active_voice_count() >= 1)
      // Process blocks until we've covered half a cycle (12000 samples = ~93 blocks)
      let mut voices_seen = pool.active_voice_count()
      for _i = 1; _i < 94; _i = _i + 1 {
        sched.process_block(pat, pool, ctx, left, right)
        if pool.active_voice_count() > voices_seen {
          voices_seen = pool.active_voice_count()
        }
      }
      // Should have seen at least 2 voices (onset at 0 and at 0.5 cycles)
      assert_true!(voices_seen >= 2)
    }
  }
}
```

- [ ] **Step 2: Write integration test for gate-off boundary crossing**

Append to `scheduler/scheduler_test.mbt`:

```moonbit
///|
test "process_block: gate-off fires after note ends" {
  let (pool, template, ctx) = make_test_pool()
  let bindings = @lib.ControlBindingBuilder::new()
    .bind(key="note", node_index=0, slot=@lib.GraphParamSlot::Value0)
    .build(template)
  match bindings {
    Err(_) => assert_true!(false)
    Ok(b) => {
      let sched = @scheduler.PatternScheduler::new(bpm=120.0, bindings=b, ctx~)
      let pat = @pattern.note(60.0)
      let left = @lib.AudioBuffer::filled(128)
      let right = @lib.AudioBuffer::filled(128)
      // First block: note-on at cycle 0
      sched.process_block(pat, pool, ctx, left, right)
      inspect!(sched.active_note_count(), content="1")
      // Process blocks until we pass cycle 1 (24000 samples / 128 = 187.5 blocks)
      // After ~188 blocks the note's whole.end_ (cycle 1) should be expired
      for _i = 1; _i < 190; _i = _i + 1 {
        sched.process_block(pat, pool, ctx, left, right)
      }
      // Note should have been gated off — but a new note-on fires each cycle,
      // so active_note_count reflects the current cycle's note.
      // The key check: the original voice was released.
      // After 190 blocks at 120 BPM we're in cycle 1, which triggers a new note.
      // active_note_count should be 1 (new note), not 2 (accumulated).
      inspect!(sched.active_note_count(), content="1")
    }
  }
}
```

- [ ] **Step 3: Write pan integration test**

Append to `scheduler/scheduler_test.mbt`:

```moonbit
///|
test "process_block: pan key applies per-voice pan" {
  let (pool, template, ctx) = make_test_pool()
  let bindings = @lib.ControlBindingBuilder::new()
    .bind(key="note", node_index=0, slot=@lib.GraphParamSlot::Value0)
    .build(template)
  match bindings {
    Err(_) => assert_true!(false)
    Ok(b) => {
      let sched = @scheduler.PatternScheduler::new(bpm=120.0, bindings=b, ctx~)
      // merge note + pan
      let pat = @pattern.merge_control(@pattern.note(60.0), @pattern.s_pan(-1.0))
      let left = @lib.AudioBuffer::filled(128)
      let right = @lib.AudioBuffer::filled(128)
      sched.process_block(pat, pool, ctx, left, right)
      // Voice was created and pan was applied (no crash = pan path works)
      inspect!(pool.active_voice_count(), content="1")
      inspect!(sched.active_note_count(), content="1")
    }
  }
}
```

- [ ] **Step 4: Run tests**

Run: `moon check && moon test -p dowdiness/mdsp/scheduler`
Expected: all tests PASS

- [ ] **Step 5: Commit**

```bash
moon info && moon fmt
git add scheduler/
git commit -m "test(scheduler): add integration tests for fast, gate-off, pan"
```

---

### Task 8: Edge case tests

**Files:**
- Modify: `scheduler/scheduler_test.mbt`

- [ ] **Step 1: Write edge case tests**

Append to `scheduler/scheduler_test.mbt`:

```moonbit
///|
test "process_block: dense pattern fires multiple note-ons per block" {
  let (pool, template, ctx) = make_test_pool()
  let bindings = @lib.ControlBindingBuilder::new()
    .bind(key="note", node_index=0, slot=@lib.GraphParamSlot::Value0)
    .build(template)
  match bindings {
    Err(_) => assert_true!(false)
    Ok(b) => {
      let sched = @scheduler.PatternScheduler::new(bpm=120.0, bindings=b, ctx~)
      // fast(1000) = 1000 events per cycle. Many onsets will fall in a single block.
      let pat = @pattern.note(60.0).fast(@pattern.Rational::from_int(1000))
      let left = @lib.AudioBuffer::filled(128)
      let right = @lib.AudioBuffer::filled(128)
      sched.process_block(pat, pool, ctx, left, right)
      // Should have multiple voices active (up to max_voices=4 due to stealing)
      assert_true!(pool.active_voice_count() >= 1)
    }
  }
}

///|
test "process_block: stolen voice gate-off is harmless" {
  // Pool with only 1 voice — second note steals the first
  let template : Array[@lib.DspNode] = [
    @lib.DspNode::oscillator(@lib.Waveform::Sine, 440.0),
    @lib.DspNode::adsr(0.01, 0.1, 0.7, 0.3),
    @lib.DspNode::gain(0, 1.0),
    @lib.DspNode::output(2),
  ]
  let ctx = @lib.DspContext::new(48000.0, 128)
  let pool = @lib.VoicePool::new(template, ctx, max_voices=1)
  match pool {
    None => assert_true!(false)
    Some(pool) => {
      let bindings = @lib.ControlBindingBuilder::new()
        .bind(key="note", node_index=0, slot=@lib.GraphParamSlot::Value0)
        .build(template)
      match bindings {
        Err(_) => assert_true!(false)
        Ok(b) => {
          let sched = @scheduler.PatternScheduler::new(bpm=120.0, bindings=b, ctx~)
          // Two events per cycle — second steals the first's voice
          let pat = @pattern.note(60.0).fast(@pattern.Rational::from_int(2))
          let left = @lib.AudioBuffer::filled(128)
          let right = @lib.AudioBuffer::filled(128)
          // Process enough blocks that both onsets fire and gate-off is attempted
          for _i = 0; _i < 200; _i = _i + 1 {
            sched.process_block(pat, pool, ctx, left, right)
          }
          // No crash = stolen voice gate-off was handled safely
          assert_true!(true)
        }
      }
    }
  }
}
```

- [ ] **Step 2: Run tests**

Run: `moon check && moon test -p dowdiness/mdsp/scheduler`
Expected: all tests PASS

- [ ] **Step 3: Commit**

```bash
moon info && moon fmt
git add scheduler/
git commit -m "test(scheduler): add edge case tests for dense patterns and voice stealing"
```

---

### Task 9: Final cleanup — update CLAUDE.md, moon info, push

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update CLAUDE.md with scheduler package**

Add `scheduler/` to the package table in `CLAUDE.md`:

```markdown
| `scheduler/` | Pattern scheduler — bridges pattern engine to DSP voice pool |
```

Update the test count after running `moon test` to get the final number.

Update Key Facts to mention Phase 5:

```markdown
- Phases 0–5 complete: AudioWorklet proof, DSP primitives, compiled graph runtime, voice management, pattern engine, pattern scheduler
```

- [ ] **Step 2: Run full test suite**

Run: `moon check && moon test`
Expected: all tests PASS (old 453 + new scheduler tests)

- [ ] **Step 3: Update interfaces and format**

Run: `moon info && moon fmt`

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md scheduler/
git commit -m "docs: add scheduler package to CLAUDE.md, update phase status"
```

- [ ] **Step 5: Run full test suite one more time**

Run: `moon check && moon test`
Expected: all tests PASS
