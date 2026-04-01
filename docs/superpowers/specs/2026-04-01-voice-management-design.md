# Phase 3: Voice Management — Design Spec

> **Date:** 2026-04-01
> **Scope:** Polyphonic voice pool with pre-allocated slots, priority-based stealing, and per-voice pan mixdown.

---

## Goal

Enable polyphonic playback — multiple overlapping notes, each with independent DSP state (oscillator phase, filter coefficients, envelope levels) — by managing a pool of pre-compiled graph instances.

**Deliverable:** A `VoicePool` that handles 32-64 simultaneous voices of any compiled graph topology, with stereo output via per-voice equal-power pan.

---

## Architecture

### Voice Pool Model

A `VoicePool` manages N pre-allocated voice slots. All voices share the same graph topology (the "template"), but each is a separate `CompiledDsp` instance with independent DSP state.

```
Template (Array[DspNode])
    │
    ├─compile─→ Voice 0 (CompiledDsp) — state: Idle/Active/Releasing
    ├─compile─→ Voice 1 (CompiledDsp)
    │   ...
    └─compile─→ Voice N-1 (CompiledDsp)

process() → for each non-idle voice:
    voice.compiled.process(ctx, voice.mono_buf)
    left[i]  += mono_buf[i] * left_gain(pan)
    right[i] += mono_buf[i] * right_gain(pan)
```

### Why Voice Pool, Not ECS

The blueprint listed ECS as candidate B. Voice pool was chosen for Phase 3 because:
- Simpler: one struct, ~300 lines, no framework dependency
- Sufficient for the Phase 3 deliverable (fixed parameter set via GraphControl)
- ECS's open extensibility is valuable when the Pattern Engine (Phase 4-5) arrives with arbitrary control maps — at that point, migration to ECS can be evaluated with concrete requirements rather than speculative ones

---

## Voice States

```
Idle ──note_on──→ Active ──note_off──→ Releasing ──adsr idle──→ Idle
                     │                                             ↑
                     └───────────note_off (no ADSR)────────────────┘
```

- **Idle:** Silent, available for allocation. Skipped during `process()`.
- **Active:** Gate is on, producing sound. ADSR in attack/decay/sustain.
- **Releasing:** Gate is off, ADSR in release stage, still producing sound. Will transition to Idle when all ADSR nodes reach Idle stage.

---

## Voice Stealing (Priority-Based)

When `note_on` is called and all slots are occupied:

1. **First choice:** any `Idle` slot (free allocation)
2. **Second choice:** the oldest `Releasing` voice (least audible pop — already fading out)
3. **Last resort:** the oldest `Active` voice (audible cut, but unavoidable at full polyphony)

"Oldest" is determined by a monotonic allocation counter incremented on each `note_on`.

---

## API Surface

```moonbit
pub enum VoiceState {
  Idle
  Active
  Releasing
}

pub struct VoicePool {
  fn new(
    template : Array[DspNode],
    context : DspContext,
    max_voices~ : Int = 32,
  ) -> VoicePool?

  fn note_on(self, params : Array[GraphControl]) -> Int
  // Allocate or steal a voice, compile from template, apply params,
  // gate_on all ADSR nodes. Returns voice slot index (0..max_voices-1)
  // or -1 if compilation fails.

  fn note_off(self, voice_index : Int) -> Unit
  // Gate_off all ADSR nodes. Voice transitions to Releasing.

  fn note_off_all(self) -> Unit
  // Gate_off all active voices.

  fn set_voice_pan(self, voice_index : Int, pan : Double) -> Unit
  // Set per-voice pan position [-1, 1]. Default 0.0 (center).

  fn set_template(self, template : Array[DspNode]) -> Bool
  // Update the template for future voice allocations.
  // Does NOT recompile active voices (recompile-on-steal strategy).

  fn process(
    self,
    context : DspContext,
    left_output : AudioBuffer,
    right_output : AudioBuffer,
  ) -> Unit
  // Process all non-idle voices, mix down to stereo with per-voice pan.

  fn active_voice_count(self) -> Int
  // Number of non-idle voices (Active + Releasing).

  fn voice_state(self, voice_index : Int) -> VoiceState
  // Query a specific voice's state.
}
```

### note_on Parameters

`note_on` accepts `Array[GraphControl]` which maps directly to the existing runtime control system:
- `GraphControl::set_param(node_index, GraphParamSlot::Value0, 440.0)` — set oscillator frequency
- `GraphControl::gate_on(adsr_node_index)` — handled automatically by the pool

The caller (future Pattern Engine) is responsible for mapping note numbers to frequencies and building the `GraphControl` array. The voice pool does not know about MIDI, note names, or scales.

---

## Per-Voice Pan and Stereo Mixdown

Each voice slot stores `pan : Double` (range [-1, 1], default 0.0).

**Mixdown formula (equal-power pan law):**
```
left_gain  = cos((pan + 1) * π/4)
right_gain = sin((pan + 1) * π/4)

for each sample i:
    left_output[i]  += mono_buffer[i] * left_gain
    right_output[i] += mono_buffer[i] * right_gain
```

Pan gains are computed once per voice per block (pan is constant within a block), not per sample.

**Pre-allocated buffers:** Each voice slot has one `AudioBuffer` for mono output. The left/right output buffers are provided by the caller — the pool accumulates into them (caller must clear them before calling `process`).

---

## Voice Lifecycle and ADSR Integration

**How the pool knows when a releasing voice has finished:**

A new method `CompiledDsp::is_voice_finished` scans the compiled graph's `env_states` array. If all ADSR nodes are in `EnvStage::Idle`, the voice is finished.

```moonbit
pub fn CompiledDsp::is_voice_finished(self) -> Bool
```

This is a read-only O(N) scan where N is the node count — no allocation, runs after each voice's `process()`.

**Edge case:** If the graph has no ADSR nodes, `is_voice_finished` returns `true` immediately after `gate_off`. The voice becomes `Idle` on the next `process()` call — correct behavior for envelope-less graphs (they have no release tail to wait for).

---

## Template Changes (Recompile-on-Steal)

When `set_template` is called:
1. The new template is stored
2. Active/Releasing voices continue with their existing compiled graphs
3. The next `note_on` compiles from the updated template

This avoids N simultaneous recompilations. Voices naturally cycle through their release tails and get recycled with the new template. The audible inconsistency (old vs new template voices playing simultaneously) is brief and acceptable for live-coding workflows.

---

## No Allocation in the Audio Thread

`process()` touches only pre-allocated memory:
- Voice mono buffers: allocated at pool construction
- Per-voice pan gains: computed in-place (two Doubles per voice)
- Left/right output: caller-provided, accumulated into

`note_on` does allocate (compiles a new graph), but `note_on` is called from the control thread (pattern engine / user input), not from the audio callback.

---

## File Structure

| File | Responsibility |
|------|---------------|
| `lib/voice.mbt` | `VoiceState` enum, `VoiceSlot` struct, `VoicePool` struct + all methods |
| `lib/voice_test.mbt` | Blackbox tests: allocation, stealing, lifecycle, mixdown, template changes |

---

## Testing

1. **Allocation:** `note_on` returns valid indices, fills pool to capacity
2. **Stealing order:** when full, steals Releasing before Active, oldest first within each category
3. **Lifecycle:** note_on → process → note_off → process until ADSR idle → voice reclaimed as Idle
4. **Stereo mixdown:** center pan → equal L/R energy, hard left → L only, hard right → R only
5. **Template change:** `set_template` mid-playback; new voices use new template, old voices keep old
6. **is_voice_finished:** returns true when all ADSRs are idle, true immediately for no-ADSR graphs
7. **Property test:** total output energy bounded by sum of individual voice energies
8. **Benchmark:** `process()` with 32 active FM voices at 128 samples — must stay under 2.67 ms

---

## Success Criteria

1. 32 simultaneous voices of FM voice graph process within 1 ms at 128 samples (benchmarks show ~7 µs per voice × 32 = ~224 µs + mixdown overhead)
2. No allocation during `process()`
3. Voice stealing produces no crash and minimal audible artifacts
4. All existing 310 tests remain green
5. New tests cover allocation, stealing, lifecycle, mixdown, and template changes

---

## Future Work (Not in Scope)

- Per-voice stereo post-processing (delay, filter) — add when needed
- MIDI note-to-voice mapping — Pattern Engine responsibility (Phase 4-5)
- Voice groups / layering — Phase 5+ if needed
- Migration to ECS — evaluate when Pattern Engine control maps are concrete
