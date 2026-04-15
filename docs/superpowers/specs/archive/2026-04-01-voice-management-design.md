# Phase 3: Voice Management — Design Spec

> **Date:** 2026-04-01
> **Scope:** Polyphonic voice pool with pre-allocated slots, priority-based stealing, and per-voice pan mixdown.

---

## Goal

Enable polyphonic playback — multiple overlapping notes, each with independent DSP state (oscillator phase, filter coefficients, envelope levels) — by managing a pool of voice slots that compile on demand from a shared template.

**Deliverable:** A `VoicePool` that handles 32-64 simultaneous mono voices (`CompiledDsp` only, not `CompiledStereoDsp`) with stereo output via per-voice equal-power pan mixdown. Performance target: 32 FM-class voices within 1 ms at 128 samples. Larger or feedback-heavy graphs may support fewer voices — the pool does not enforce a voice count guarantee for arbitrary topologies.

---

## Architecture

### Voice Pool Model

A `VoicePool` manages N voice slots. All voices share the same mono graph topology (the "template"), but each is a separate `CompiledDsp` instance with independent DSP state. Voice slots are pre-allocated at pool construction; each `note_on` compiles the template into the slot (compilation is ~5-13 µs, acceptable for control-rate events but not for audio-rate calls).

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

### Threading Model (Phase 3: Single-Threaded)

Phase 3 assumes **single-threaded access**: `note_on`, `note_off`, `set_template`, and `process` are all called from the same thread (or with external synchronization). There is no internal queuing or block-boundary staging.

This matches the current browser AudioWorklet model where `postMessage` delivers control events and the worklet processes them before calling `process()`. A queued `queue_note_on`/`apply_pending_controls` model (matching the engine's existing `queue_swap`/`queue_topology_edit` pattern) is deferred to Phase 5 when the Pattern Engine drives voice events at potentially higher rates.

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

/// Generation-tagged handle. The generation counter prevents stale handles
/// from operating on a slot that has been stolen and reused for a different note.
pub struct VoiceHandle {
  slot : Int       // index into the voice array (0..max_voices-1)
  generation : Int  // monotonic counter, incremented on each note_on for this slot
}

pub struct VoicePool {
  fn new(
    template : Array[DspNode],
    context : DspContext,
    max_voices~ : Int = 32,
  ) -> VoicePool?

  fn note_on(self, params : Array[GraphControl]) -> VoiceHandle?
  // Allocate or steal a voice, compile from template, validate and apply
  // params transactionally via apply_controls(), gate_on all ADSR nodes.
  // Returns a generation-tagged handle, or None if compilation or param
  // validation fails. On validation failure, the voice is not activated.

  fn note_off(self, handle : VoiceHandle) -> Bool
  // Gate_off all ADSR nodes if the handle's generation matches the slot's
  // current generation. Returns false (no-op) if the handle is stale
  // (slot was stolen and reused). Voice transitions to Releasing.

  fn note_off_all(self) -> Unit
  // Gate_off all Active voices. Ignores Idle and already-Releasing voices.

  fn set_voice_pan(self, handle : VoiceHandle, pan : Double) -> Bool
  // Set per-voice pan position [-1, 1]. Returns false if handle is stale.

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
  // Automatically reclaims finished voices (see Voice Lifecycle below).

  fn active_voice_count(self) -> Int
  // Number of non-idle voices (Active + Releasing).

  fn voice_state(self, handle : VoiceHandle) -> VoiceState
  // Query a voice's state. Returns Idle if handle is stale.
}
```

### VoiceHandle Safety

Voice handles are generation-tagged: each slot has a generation counter incremented on every `note_on`. A `VoiceHandle` stores both the slot index and the generation at allocation time. All operations that take a `VoiceHandle` compare the handle's generation against the slot's current generation — if they differ, the handle is stale (the slot was stolen and reused) and the operation returns `false` / `Idle`. This prevents accidentally releasing or panning the wrong note after a steal.

### note_on: Transactional Parameter Application

`note_on` follows a strict sequence:
1. Select a slot (idle, or steal per priority rules)
2. Compile the current template into the slot
3. Validate and apply all `params` via `apply_controls()` as one batch — if any param is invalid, the voice is not activated and `note_on` returns `None`
4. Gate on all ADSR nodes in the graph
5. Return a `VoiceHandle` with the slot's new generation

`note_on` accepts `Array[GraphControl]` which maps directly to the existing runtime control system:
- `GraphControl::set_param(node_index, GraphParamSlot::Value0, 440.0)` — set oscillator frequency
- `GraphControl::gate_on(adsr_node_index)` — handled automatically by the pool (step 4)

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

## Voice Lifecycle and Silence Detection

**How the pool knows when a releasing voice has finished:**

A new method `CompiledDsp::is_voice_finished` uses a two-stage check:

1. **ADSR check:** Scan the compiled graph's `env_states` array. If any ADSR node is NOT in `EnvStage::Idle`, the voice is still producing sound — return `false`.
2. **Energy check:** If all ADSRs are idle (or there are no ADSRs), check whether the voice's last output buffer is silent (all samples below a threshold, e.g., 0.0001). This catches delay/feedback tails that continue ringing after the envelope has closed.

```moonbit
pub fn CompiledDsp::is_voice_finished(self) -> Bool
// Returns true only when all ADSRs are idle AND the output buffer is silent.
```

This is a read-only O(N) scan — no allocation, runs after each voice's `process()`.

**Why both checks:** ADSR-only detection would cut voices with downstream delay or feedback tails that are still audible. Energy-only detection would keep voices alive unnecessarily during the sustain stage (where the output is non-zero but the user expects the voice to stay active). The two-stage approach handles both correctly:
- Voice with ADSR + delay: ADSR reaches idle, but delay tail keeps output non-silent → voice stays alive until tail decays below threshold
- Voice with no ADSR: `is_voice_finished` returns true when output is silent
- Voice in sustain: ADSR is not idle → voice stays Active regardless of output level

---

## Template Changes (Recompile-on-Steal)

When `set_template` is called:
1. The new template is stored
2. Active/Releasing voices continue with their existing compiled graphs
3. The next `note_on` compiles from the updated template

This avoids N simultaneous recompilations. Voices naturally cycle through their release tails and get recycled with the new template. The audible inconsistency (old vs new template voices playing simultaneously) is brief and acceptable for live-coding workflows.

---

## Allocation Budget

**`process()` — zero allocation.** Touches only pre-allocated memory:
- Voice mono buffers: allocated at pool construction (one per slot)
- Per-voice pan gains: computed in-place (two Doubles per voice)
- Left/right output: caller-provided, accumulated into

**`note_on` — allocates (compiles a graph).** Each `note_on` call invokes `CompiledDsp::compile`, which allocates buffers, state arrays, etc. (~5-13 µs for current graph sizes). This is acceptable because `note_on` is a control-rate event (called at note boundaries, not per sample), and in the Phase 3 single-threaded model it runs between `process()` calls, not during them.

---

## File Structure

| File | Responsibility |
|------|---------------|
| `lib/voice.mbt` | `VoiceState` enum, `VoiceSlot` struct, `VoicePool` struct + all methods |
| `lib/voice_test.mbt` | Blackbox tests: allocation, stealing, lifecycle, mixdown, template changes |

---

## Testing

1. **Allocation:** `note_on` returns valid handles, fills pool to capacity
2. **Stealing order:** when full, steals Releasing before Active, oldest first within each category
3. **Stale handle safety:** `note_off` with a stale handle (slot was stolen) returns false, does not affect the new voice
4. **Transactional note_on:** invalid params cause `note_on` to return None without activating the voice
5. **Lifecycle:** note_on → process → note_off → process until silence → voice reclaimed as Idle
6. **Delay tail:** voice with delay keeps playing after ADSR idle until output decays below threshold
7. **Stereo mixdown:** center pan → equal L/R energy, hard left → L only, hard right → R only
8. **Template change:** `set_template` mid-playback; new voices use new template, old voices keep old
9. **is_voice_finished:** two-stage check — ADSR idle AND output silent
10. **Property test:** total output energy bounded by sum of individual voice energies
11. **Benchmark:** `process()` with 32 active FM voices at 128 samples — must stay under 2.67 ms

---

## Success Criteria

1. 32 simultaneous FM voices process within 1 ms at 128 samples (~7 µs × 32 = ~224 µs + mixdown)
2. No allocation during `process()`
3. Voice stealing produces no crash and minimal audible artifacts
4. Stale `VoiceHandle` operations are no-ops (never affect wrong voice)
5. Invalid `note_on` params do not produce partially-configured active voices
6. Voices with delay tails stay alive until output is silent, not just ADSR idle
7. All existing 310 tests remain green
8. New tests cover allocation, stealing, handle safety, lifecycle, delay tails, mixdown, and template changes

---

## Future Work (Not in Scope)

- **Block-boundary queuing** — `queue_note_on`/`apply_pending_controls` model for thread-safe control from Pattern Engine (Phase 5)
- **Per-voice stereo post-processing** (delay, filter) — add when needed
- **MIDI note-to-voice mapping** — Pattern Engine responsibility (Phase 4-5)
- **Voice groups / layering** — Phase 5+ if needed
- **Migration to ECS** — evaluate when Pattern Engine control maps are concrete
- **`CompiledStereoDsp` voice templates** — per-voice stereo graphs if mono + pan mixdown proves insufficient
