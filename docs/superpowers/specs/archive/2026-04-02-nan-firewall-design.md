# NaN Firewall at Graph Output Boundary

**Date:** 2026-04-02
**Status:** Approved (revised after Codex review)
**Motivation:** Audit finding — if any DSP node produces NaN (e.g., a filter with extreme parameters), it propagates silently through the entire downstream graph to the speaker output. Industry standard is output sanitization at the rendering boundary.

## Problem

Non-finite values (NaN, Inf) produced by any node propagate through all downstream nodes with no recovery mechanism. The browser's WebAudio spec silently zeros non-finite AudioWorklet output, but provides no diagnostic. The DSP engine should catch and report corruption before it leaves the graph.

## Design

### Sanitize function (shared helper)

```moonbit
fn sanitize_buffer(buffer : AudioBuffer, sample_count : Int) -> Int
```

Single pass over the buffer. For each sample where `!is_finite(sample)`, replace with 0.0 and increment counter. Returns count of sanitized samples (0 = clean output).

**Precondition:** `sample_count` is clamped internally to `min(sample_count, buffer.length())`, consistent with the existing `effective_sample_count` pattern used throughout the DSP engine. Zero or negative `sample_count` results in no work and returns 0.

### Signature change for process functions

```moonbit
// Mono graph — returns number of non-finite samples replaced with 0.0
pub fn CompiledDsp::process(self, context, output) -> Int

// Stereo graph — returns total sanitized across both L and R channels
pub fn CompiledStereoDsp::process(self, context, left_output, right_output) -> Int
```

This is a public API break (Unit → Int). Accepted because the project is pre-1.0 and all callers are internal.

### Where it runs

**Graph output boundary:** At the end of each `process` function, after the process loop has written to the output buffer(s). One call to `sanitize_buffer` per output buffer (1 for mono, 2 for stereo). This is the last step before samples leave the graph.

**VoicePool output boundary:** After per-voice processing and pan/gain/accumulate mixdown, sanitize the final left and right output buffers. Per-voice sanitization catches corruption within each voice's graph, but the mixdown math (multiplication, accumulation) can produce new non-finite values. The VoicePool firewall catches those.

### Replacement strategy

Non-finite samples are replaced with 0.0 (silence). This is a **containment strategy, not transparent recovery** — it may produce audible clicks or discontinuities at the corruption boundary. The alternative approaches (mute whole block, hold last valid sample) are policy choices that can be layered on top later if artifact quality matters. For a safety firewall, deterministic silence is the correct default.

### What it does NOT do

- **Diagnose the source** — it doesn't identify which node produced the NaN. That's the debug validation mode (separate TODO).
- **Fix the corruption** — it replaces with silence. The corrupted node's internal state (e.g., biquad delay lines) may still contain NaN. Existing per-node defenses (biquad's `invalidate()`) handle internal recovery.
- **Affect hot-swap or topology edit** — those wrappers call the underlying `process()` and inherit the sanitization automatically. Hot-swap crossfade math is applied to already-sanitized buffers.

### Caller impact

- **Browser `process_*_block` functions:** Currently call `process()` and ignore return (was Unit). After change, they get an Int they can ignore or check for telemetry. All callers must be updated to handle the new return type.
- **VoicePool::process:** Calls `CompiledDsp::process` per voice (sanitized per voice), then does its own mixdown. Sanitizes final output buffers after mixdown. Returns total sanitized count.
- **HotSwapGraph:** Calls `CompiledDsp::process` / `CompiledStereoDsp::process` internally. The sanitization happens inside those calls. Hot-swap crossfade operates on sanitized buffers, so no additional firewall needed.

### Performance

`sanitize_buffer` is one branch per sample (128 samples at 48kHz = 128 branches per block). The branch is almost always not-taken (clean output), so the CPU branch predictor will handle it efficiently. Cost is negligible compared to the oscillator/filter math in the process loop.

## Testing

1. **sanitize_buffer: clean buffer returns 0** — verify no modifications
2. **sanitize_buffer: NaN replaced with 0.0** — inject NaN at known positions, verify exact count
3. **sanitize_buffer: +Inf and -Inf replaced** — verify both infinities are caught
4. **sanitize_buffer: sample_count clamped** — `sample_count > buffer.length()` doesn't overflow
5. **sanitize_buffer: zero sample_count returns 0** — no work done
6. **sanitize_buffer: idempotent** — sanitizing a sanitized buffer returns 0
7. **CompiledDsp::process: clean graph returns 0** — normal operation
8. **CompiledDsp::process: NaN constant is sanitized** — Constant(NaN) → output 0.0, return > 0
9. **CompiledStereoDsp::process: both channels sanitized** — returns combined count
10. **VoicePool::process: mixdown sanitized** — verify final output is finite after voice accumulation
