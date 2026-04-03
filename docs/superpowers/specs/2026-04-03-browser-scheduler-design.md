# Browser Scheduler Integration — Design Spec

> **Scope:** Wire the pattern scheduler and voice pool into the browser AudioWorklet as a new graph variant. Built-in demo patterns, no pattern serialization. Coexists with existing graph variants.

## Motivation

The scheduler (`scheduler/`) and voice pool (`lib/`) are complete and tested but not accessible from the browser. This connects the full audio path: pattern → scheduler → voice pool → stereo output → speakers.

## Architecture

New file `browser/browser_scheduler.mbt` adds a scheduler variant following the same `@ref.Ref` global state pattern as all existing browser variants. The browser package gains a dependency on `scheduler/` and `pattern/`.

### WASM-Exported Functions

| Function | Purpose |
|----------|---------|
| `init_scheduler_graph(sample_rate, block_size) -> Bool` | Create VoicePool, PatternScheduler, output buffers |
| `process_scheduler_block()` | Run one block: scheduler.process_block + gain |
| `scheduler_left_sample(index) -> Double` | Read left output sample |
| `scheduler_right_sample(index) -> Double` | Read right output sample |
| `set_scheduler_pattern(index)` | Switch built-in pattern (0–3) |
| `set_scheduler_bpm(bpm)` | Update tempo |
| `set_scheduler_gain(gain)` | Master volume (post-mixdown multiply) |

### Global State (`@ref.Ref`)

```moonbit
let scheduler_pool : Ref[VoicePool?] = @ref.new(None)
let scheduler : Ref[PatternScheduler?] = @ref.new(None)
let scheduler_left : Ref[AudioBuffer?] = @ref.new(None)
let scheduler_right : Ref[AudioBuffer?] = @ref.new(None)
let scheduler_pattern_index : Ref[Int] = @ref.new(0)
let scheduler_gain : Ref[Double] = @ref.new(0.3)
```

### Voice Template

Simple 4-node graph: oscillator → ADSR → gain → output.

```moonbit
let template = [
  DspNode::oscillator(Waveform::Sine, 440.0),  // node 0: freq via Value0
  DspNode::adsr(0.01, 0.1, 0.7, 0.3),          // node 1: envelope
  DspNode::gain(0, 1.0),                         // node 2: voice gain
  DspNode::output(2),                             // node 3: output
]
```

Control binding: `"note"` → node 0, `GraphParamSlot::Value0` (oscillator frequency).

### Built-in Patterns

Selected by index 0–3 via `set_scheduler_pattern(index)`:

| Index | Pattern | Description |
|-------|---------|-------------|
| 0 | `note(60.0)` | Single Middle C |
| 1 | `sequence([note(60), note(64), note(67), note(72)])` | C major arpeggio |
| 2 | `stack([note(60), note(64), note(67)])` | C major chord (polyphony) |
| 3 | `note(60.0).fast(Rational::from_int(4))` | Rapid repeated C |

Default BPM: 120.0. Default pattern index: 0.

## Data Flow

```
Main thread (JS)                    AudioWorklet (WASM)
─────────────────                   ───────────────────
set_scheduler_pattern(2) ──msg──→   pattern_index = 2
set_scheduler_bpm(140)   ──msg──→   scheduler.set_bpm(140) in-place
set_scheduler_gain(0.5)  ──msg──→   gain = 0.5

                                    process_scheduler_block():
                                      pat = built_in_patterns[pattern_index]
                                      scheduler.process_block(pat, pool, left, right)
                                      apply gain to left/right buffers

scheduler_left_sample(i)  ←──────   left[i]
scheduler_right_sample(i) ←──────   right[i]
```

Pattern objects live entirely in WASM. JS sends only an integer index. The scheduler owns timing (sample counter, BPM), the voice pool owns polyphony, output buffers are read sample-by-sample by the worklet's `process()` callback.

### BPM Changes

`set_scheduler_bpm(bpm)` calls `PatternScheduler::set_bpm(bpm)` to update the tempo in-place. The sample counter is preserved — no timeline reset, no voice interruption. Active notes continue with their existing gate-off cycle positions, which simply arrive faster or slower with the new BPM. This produces seamless, click-free tempo transitions.

### Gain

Applied after `pool.process()` as a simple multiply over both output buffers. Keeps the voice pool and scheduler clean.

## JS Changes (processor.js)

Add `useScheduler` constructor option alongside existing flags. In the `process()` callback, add a branch for the scheduler variant:

```javascript
if (this.useScheduler && this.supportsSchedulerGraph) {
  this.instance.exports.process_scheduler_block();
  for (let i = 0; i < 128; i++) {
    outputL[i] = this.instance.exports.scheduler_left_sample(i);
    outputR[i] = this.instance.exports.scheduler_right_sample(i);
  }
}
```

Message handlers:
- `"set-scheduler-pattern"` → calls `set_scheduler_pattern(data.index)`
- `"set-scheduler-bpm"` → calls `set_scheduler_bpm(data.bpm)`
- `"set-scheduler-gain"` → calls `set_scheduler_gain(data.gain)`

Feature detection: check if `init_scheduler_graph` exists on the WASM exports.

## HTML Changes (index.html)

Add a "Scheduler" button to the graph variant selector. When selected:
- Show pattern selector (4 buttons: Single Note, Arpeggio, Chord, Fast)
- Show BPM slider (60–240, default 120)
- Show gain slider (0–1, default 0.3)
- Hide frequency/pan/delay/cutoff controls (those are for direct graph variants)

## Package Changes

`browser/moon.pkg` gains imports:
- `"dowdiness/mdsp/scheduler"`
- `"dowdiness/mdsp/pattern"`

Exports gain 7 new functions (listed above).

## Testing

**Existing MoonBit tests:** 17 scheduler tests already cover the core logic. No new MoonBit tests needed — `browser_scheduler.mbt` is thin glue.

**Browser smoke test (Playwright):** Extend to verify the scheduler variant loads and processes blocks without crashing. Same pattern as existing smoke tests.

## File Changes

| File | Change |
|------|--------|
| `browser/browser_scheduler.mbt` | **Create** — scheduler variant glue code |
| `browser/moon.pkg` | **Modify** — add scheduler/pattern imports + new exports |
| `web/processor.js` | **Modify** — add useScheduler branch |
| `web/index.html` | **Modify** — add scheduler UI controls |

## Out of Scope

- Pattern serialization / parsing from JS
- Dynamic voice template changes from JS
- Per-voice parameter control from JS
- Fractional-sample-accurate BPM transitions (current in-place update is block-quantized)
- New Playwright test scenarios (extend existing smoke test only)
