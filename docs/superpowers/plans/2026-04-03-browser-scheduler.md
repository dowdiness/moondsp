# Browser Scheduler Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the pattern scheduler and voice pool into the browser AudioWorklet as a new graph variant with 4 built-in demo patterns, selectable from JS.

**Architecture:** New `browser/browser_scheduler.mbt` exports 7 WASM functions following the existing `@ref.Ref` global state pattern. `web/processor.js` gets a `useScheduler` mode. `web/index.html` gets a "Scheduler" button with pattern/BPM/gain controls.

**Tech Stack:** MoonBit (WASM-GC), JavaScript (AudioWorklet), Playwright (smoke tests)

**Spec:** `docs/superpowers/specs/2026-04-03-browser-scheduler-design.md`

---

## File Structure

```text
browser/
  browser_scheduler.mbt  — NEW: scheduler variant WASM glue (~100 lines)
  moon.pkg               — MODIFY: add scheduler/pattern imports + 7 new exports
web/
  processor.js           — MODIFY: add useScheduler branch
  index.html             — MODIFY: add scheduler UI controls
```

---

### Task 1: browser_scheduler.mbt — global state + init + sample readers

**Files:**
- Create: `browser/browser_scheduler.mbt`
- Modify: `browser/moon.pkg`

- [ ] **Step 1: Add imports to browser/moon.pkg**

Add `"dowdiness/mdsp/scheduler"` and `"dowdiness/mdsp/pattern"` to the import block in `browser/moon.pkg`:

```text
import {
  "dowdiness/mdsp/lib" @lib,
  "dowdiness/mdsp/scheduler" @scheduler,
  "dowdiness/mdsp/pattern" @pattern,
  "moonbitlang/core/ref" @ref,
}
```

Add 7 new exports to BOTH the `"js"` and `"wasm-gc"` export lists in `browser/moon.pkg`:

```text
"init_scheduler_graph",
"process_scheduler_block",
"scheduler_left_sample",
"scheduler_right_sample",
"set_scheduler_pattern",
"set_scheduler_bpm",
"set_scheduler_gain",
```

- [ ] **Step 2: Create browser_scheduler.mbt with global state and init**

Create `browser/browser_scheduler.mbt`:

```moonbit
///|
let sched_pool : @ref.Ref[@lib.VoicePool?] = @ref.new(None)

///|
let sched_scheduler : @ref.Ref[@scheduler.PatternScheduler?] = @ref.new(None)

///|
let sched_left : @ref.Ref[@lib.AudioBuffer?] = @ref.new(None)

///|
let sched_right : @ref.Ref[@lib.AudioBuffer?] = @ref.new(None)

///|
let sched_pattern_index : @ref.Ref[Int] = @ref.new(0)

///|
let sched_gain : @ref.Ref[Double] = @ref.new(0.3)

///|
/// Voice template: oscillator → ADSR → gain → output.
/// Node 0 (oscillator) Value0 slot = frequency, set via "note" binding.
fn sched_template() -> Array[@lib.DspNode] {
  [
    @lib.DspNode::oscillator(@lib.Waveform::Sine, 440.0),
    @lib.DspNode::adsr(0.01, 0.1, 0.7, 0.3),
    @lib.DspNode::gain(0, 1.0),
    @lib.DspNode::output(2),
  ]
}

///|
pub fn init_scheduler_graph(sample_rate : Double, block_size : Int) -> Bool {
  if sample_rate <= 0.0 || block_size <= 0 {
    reset_scheduler_graph()
    return false
  }
  let ctx = @lib.DspContext::new(sample_rate, block_size)
  let template = sched_template()
  let pool = @lib.VoicePool::new(template, ctx, max_voices=8)
  match pool {
    None => {
      reset_scheduler_graph()
      false
    }
    Some(p) => {
      let bindings_result = @lib.ControlBindingBuilder::new()
        .bind(key="note", node_index=0, slot=@lib.GraphParamSlot::Value0)
        .build(template)
      match bindings_result {
        Err(_) => {
          reset_scheduler_graph()
          false
        }
        Ok(bindings) => {
          let scheduler = @scheduler.PatternScheduler::new(
            bpm=120.0,
            bindings~,
            ctx~,
          )
          sched_pool.val = Some(p)
          sched_scheduler.val = Some(scheduler)
          sched_left.val = Some(@lib.AudioBuffer::filled(block_size))
          sched_right.val = Some(@lib.AudioBuffer::filled(block_size))
          sched_pattern_index.val = 0
          sched_gain.val = 0.3
          true
        }
      }
    }
  }
}

///|
fn reset_scheduler_graph() -> Unit {
  sched_pool.val = None
  sched_scheduler.val = None
  sched_left.val = None
  sched_right.val = None
}

///|
pub fn scheduler_left_sample(index : Int) -> Double {
  checked_sample(index, sched_left.val)
}

///|
pub fn scheduler_right_sample(index : Int) -> Double {
  checked_sample(index, sched_right.val)
}
```

- [ ] **Step 3: Run moon check**

Run: `moon check`
Expected: 0 errors (warnings OK)

- [ ] **Step 4: Commit**

```bash
moon info && moon fmt
git add browser/browser_scheduler.mbt browser/moon.pkg
git commit -m "feat(browser): add scheduler variant — init, state, sample readers"
```

---

### Task 2: Built-in patterns + set_scheduler_pattern

**Files:**
- Modify: `browser/browser_scheduler.mbt`

- [ ] **Step 1: Add built-in pattern function and set_scheduler_pattern**

Append to `browser/browser_scheduler.mbt`:

```moonbit
///|
/// Return one of 4 built-in demo patterns by index.
/// 0 = single note, 1 = arpeggio, 2 = chord, 3 = fast repeated note.
fn sched_get_pattern(index : Int) -> @pattern.Pat[@pattern.ControlMap] {
  match index {
    1 =>
      @pattern.sequence(
        [
          @pattern.note(60.0),
          @pattern.note(64.0),
          @pattern.note(67.0),
          @pattern.note(72.0),
        ],
      )
    2 =>
      @pattern.stack(
        [
          @pattern.note(60.0),
          @pattern.note(64.0),
          @pattern.note(67.0),
        ],
      )
    3 => @pattern.note(60.0).fast(@pattern.Rational::from_int(4))
    _ => @pattern.note(60.0)
  }
}

///|
/// Switch the active pattern. Index is clamped to 0–3.
pub fn set_scheduler_pattern(index : Int) -> Unit {
  let clamped = if index < 0 {
    0
  } else if index > 3 {
    3
  } else {
    index
  }
  sched_pattern_index.val = clamped
}
```

- [ ] **Step 2: Run moon check**

Run: `moon check`
Expected: 0 errors

- [ ] **Step 3: Commit**

```bash
moon info && moon fmt
git add browser/browser_scheduler.mbt
git commit -m "feat(browser): add built-in patterns and set_scheduler_pattern"
```

---

### Task 3: process_scheduler_block + set_scheduler_bpm + set_scheduler_gain

**Files:**
- Modify: `browser/browser_scheduler.mbt`
- Modify: `browser/browser.mbt` (add reset_scheduler_graph to reset_phase)

- [ ] **Step 1: Add process_scheduler_block, set_scheduler_bpm, set_scheduler_gain**

Append to `browser/browser_scheduler.mbt`:

```moonbit
///|
/// Run one audio block through the scheduler + voice pool.
/// Returns false if not initialized.
pub fn process_scheduler_block() -> Bool {
  let pool = match sched_pool.val {
    Some(p) => p
    None => return false
  }
  let scheduler = match sched_scheduler.val {
    Some(s) => s
    None => return false
  }
  let left = match sched_left.val {
    Some(b) => b
    None => return false
  }
  let right = match sched_right.val {
    Some(b) => b
    None => return false
  }
  let pat = sched_get_pattern(sched_pattern_index.val)
  scheduler.process_block(pat, pool, left, right)
  // Apply master gain post-mixdown
  let gain = sched_gain.val
  let len = left.length()
  for i = 0; i < len; i = i + 1 {
    left.set(i, left.get(i) * gain)
    right.set(i, right.get(i) * gain)
  }
  true
}

///|
/// Update tempo. Recreates the scheduler with new BPM (sample counter resets).
/// Active voices in the pool continue sounding.
pub fn set_scheduler_bpm(bpm : Double) -> Unit {
  match sched_scheduler.val {
    None => ()
    Some(old) => {
      let new_sched = @scheduler.PatternScheduler::new(
        bpm~,
        bindings=old.bindings,
        ctx=old.ctx,
      )
      sched_scheduler.val = Some(new_sched)
    }
  }
}

///|
/// Set master gain (0.0–1.0). Applied post-mixdown each block.
pub fn set_scheduler_gain(gain : Double) -> Unit {
  sched_gain.val = if gain < 0.0 {
    0.0
  } else if gain > 1.0 {
    1.0
  } else {
    gain
  }
}
```

- [ ] **Step 2: Add reset_scheduler_graph to reset_phase in browser.mbt**

In `browser/browser.mbt`, add `reset_scheduler_graph()` to the `reset_phase` function body, after the existing reset calls:

```moonbit
pub fn reset_phase() -> Unit {
  @lib.reset_phase()
  reset_compiled_graph()
  reset_compiled_hot_swap_graph()
  reset_compiled_topology_edit_graph()
  reset_compiled_stereo_graph()
  reset_compiled_stereo_hot_swap_graph()
  reset_compiled_stereo_topology_edit_graph()
  reset_exit_deliverable_graph()
  reset_scheduler_graph()  // ADD THIS LINE
}
```

- [ ] **Step 3: Run moon check and verify build**

Run: `moon check && moon build --target wasm-gc`
Expected: 0 errors, WASM build succeeds

- [ ] **Step 4: Commit**

```bash
moon info && moon fmt
git add browser/browser_scheduler.mbt browser/browser.mbt
git commit -m "feat(browser): add process_scheduler_block, BPM, and gain controls"
```

---

### Task 4: processor.js — add useScheduler mode

**Files:**
- Modify: `web/processor.js`

- [ ] **Step 1: Add useScheduler to constructor**

In the constructor, after `this.prefersExitDeliverable = ...` (line 16), add:

```javascript
this.prefersScheduler = Boolean(options?.processorOptions?.useScheduler);
```

After `this.usesCompiledGraph = false;` (line 23), add:

```javascript
this.usesScheduler = false;
```

- [ ] **Step 2: Add scheduler message handlers**

In `port.onmessage`, after the existing `else if` chain for `"set-cutoff"` (around line 46), add:

```javascript
      } else if (data.type === "set-scheduler-pattern") {
        if (this.usesScheduler && this.wasm && typeof this.wasm.set_scheduler_pattern === "function") {
          this.wasm.set_scheduler_pattern(Number(data.index));
        }
      } else if (data.type === "set-scheduler-bpm") {
        if (this.usesScheduler && this.wasm && typeof this.wasm.set_scheduler_bpm === "function") {
          this.wasm.set_scheduler_bpm(Number(data.bpm));
        }
      } else if (data.type === "set-scheduler-gain") {
        if (this.usesScheduler && this.wasm && typeof this.wasm.set_scheduler_gain === "function") {
          this.wasm.set_scheduler_gain(Number(data.gain));
        }
```

- [ ] **Step 3: Add scheduler feature detection and initialization**

After the `supportsExitDeliverable` detection block (around line 236), add:

```javascript
      const supportsScheduler =
        typeof this.wasm.init_scheduler_graph === "function" &&
        typeof this.wasm.process_scheduler_block === "function" &&
        typeof this.wasm.scheduler_left_sample === "function" &&
        typeof this.wasm.scheduler_right_sample === "function";
```

After the exit deliverable initialization block (around line 250), before the stereo graph fallback, add:

```javascript
      if (
        !this.usesCompiledHotSwap &&
        !this.usesCompiledTopologyEdit &&
        !this.usesCompiledStereoTopologyEdit &&
        !this.usesCompiledStereoHotSwap &&
        !this.usesExitDeliverable &&
        this.prefersScheduler &&
        supportsScheduler
      ) {
        const initialized = this.wasm.init_scheduler_graph(sampleRate, 128);
        if (initialized) {
          this.usesScheduler = true;
        }
      }
```

Add `!this.usesScheduler` to the fallback guard conditions (the stereo graph fallback at line 252 and the compiled graph fallback at line 259, and the error checks).

- [ ] **Step 4: Add scheduler process branch**

In the `process()` method, before the `usesCompiledStereoGraph` branch (around line 535), add:

```javascript
    if (this.usesScheduler) {
      const processed = this.wasm.process_scheduler_block();
      if (!processed) {
        this.fillSilence(left, right);
        if (!this.reportedRuntimeError) {
          this.reportedRuntimeError = true;
          this.port.postMessage({
            type: "error",
            message: "Scheduler block processing failed",
          });
        }
        return true;
      }

      for (let index = 0; index < left.length; index += 1) {
        left[index] = this.wasm.scheduler_left_sample(index);
        if (right) {
          right[index] = this.wasm.scheduler_right_sample(index);
        }
      }

      this.reportBlockTelemetry(left, right);
      return true;
    }
```

- [ ] **Step 5: Verify WASM build + manual test**

Run: `moon build --target wasm-gc --release && ./playwright-sync-wasm.sh`
Expected: builds and copies without error

- [ ] **Step 6: Commit**

```bash
git add web/processor.js
git commit -m "feat(browser): add useScheduler mode to AudioWorklet processor"
```

---

### Task 5: index.html — scheduler UI controls

**Files:**
- Modify: `web/index.html`

- [ ] **Step 1: Add scheduler button to graph variant selector**

Find the graph variant button group in `index.html`. Add a "Scheduler" button that creates the AudioWorklet with `useScheduler: true`:

```html
<button id="btnScheduler" onclick="startScheduler()">Scheduler</button>
```

- [ ] **Step 2: Add scheduler controls section**

Add a scheduler controls section (hidden by default, shown when scheduler variant is active):

```html
<div id="schedulerControls" style="display: none;">
  <div>
    <label>Pattern:</label>
    <button onclick="setSchedulerPattern(0)">Single Note</button>
    <button onclick="setSchedulerPattern(1)">Arpeggio</button>
    <button onclick="setSchedulerPattern(2)">Chord</button>
    <button onclick="setSchedulerPattern(3)">Fast</button>
  </div>
  <div>
    <label>BPM: <span id="bpmValue">120</span></label>
    <input type="range" id="bpmSlider" min="60" max="240" value="120"
           oninput="setSchedulerBpm(this.value)">
  </div>
  <div>
    <label>Gain: <span id="schedulerGainValue">0.3</span></label>
    <input type="range" id="schedulerGainSlider" min="0" max="100" value="30"
           oninput="setSchedulerGain(this.value / 100)">
  </div>
</div>
```

- [ ] **Step 3: Add JavaScript functions for scheduler controls**

Add in the `<script>` section:

```javascript
function startScheduler() {
  startAudioWith({ useScheduler: true });
  document.getElementById('schedulerControls').style.display = 'block';
}

function setSchedulerPattern(index) {
  if (workletNode) {
    workletNode.port.postMessage({ type: 'set-scheduler-pattern', index: index });
  }
}

function setSchedulerBpm(bpm) {
  document.getElementById('bpmValue').textContent = bpm;
  if (workletNode) {
    workletNode.port.postMessage({ type: 'set-scheduler-bpm', bpm: Number(bpm) });
  }
}

function setSchedulerGain(gain) {
  document.getElementById('schedulerGainValue').textContent = gain.toFixed(2);
  if (workletNode) {
    workletNode.port.postMessage({ type: 'set-scheduler-gain', gain: gain });
  }
}
```

Note: `startAudioWith` is the existing function that creates the AudioWorkletNode with processor options. Follow the existing pattern in index.html for how other variant buttons call it.

- [ ] **Step 4: Build and test manually**

Run: `moon build --target wasm-gc --release && ./playwright-sync-wasm.sh`
Open `http://localhost:8090` and click "Scheduler". Verify:
- Audio plays (single note at 120 BPM)
- Pattern buttons switch patterns
- BPM slider changes tempo
- Gain slider changes volume

- [ ] **Step 5: Commit**

```bash
git add web/index.html
git commit -m "feat(browser): add scheduler UI controls to index.html"
```

---

### Task 6: Final cleanup — build, test, CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Run full WASM build**

Run: `moon build --target wasm-gc --release`
Expected: builds without error

- [ ] **Step 2: Run full MoonBit test suite**

Run: `moon check && moon test`
Expected: 470 tests pass, 0 errors

- [ ] **Step 3: Run browser smoke test**

Run: `npm run test:browser`
Expected: existing Playwright tests still pass

- [ ] **Step 4: Update CLAUDE.md**

No CLAUDE.md changes needed — the browser package already exists in the table. The test count hasn't changed (no new MoonBit tests). Phase count already says "0–5".

- [ ] **Step 5: Final commit**

```bash
moon info && moon fmt
git add -A
git commit -m "chore: final cleanup for browser scheduler integration"
```
