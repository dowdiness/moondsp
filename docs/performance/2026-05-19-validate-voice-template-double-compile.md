# Performance Investigation — 2026-05-19: `validate_voice_template` double-compile

Targeted microbenchmark of a long-standing backlog optimization claim:
`voice/voice.mbt::validate_voice_template` runs `CompiledDsp::compile(...)`
purely as a topology-validity check and discards the result, while
`VoicePool::note_on` later compiles again per voice. The proposed fix was
to extract a topology-only `is_compilable_in(ctx) -> Bool` that skips
materialization.

Per the `moonbit-perf-investigation` skill, the bench must reproduce the
cost in isolation before any fix is designed. This snapshot captures the
pre-design measurement and the verdict drawn from it.

## Environment

- **CPU:** AMD Ryzen 7 6800H with Radeon Graphics
- **OS:** Linux 6.6.87.2-microsoft-standard-WSL2
- **MoonBit:** moon 0.1.20260512 (81d40e3 2026-05-12)
- **Git commit:** 8de21068aa774ee0a5132aab293635a1c35bb430 (post-PR #60)
- **Bench file:** `voice/voice_benchmark.mbt`
- **Commands:**
  - wasm-gc: `moon bench --package dowdiness/moondsp/voice`
  - native: `moon bench --target native --package dowdiness/moondsp/voice`
- **Regression suite:** `moon check && moon test` — 0 errors, all
  pre-existing benches unchanged.

## Fixtures

Three topologies expressed as `Array[DspNode]` to avoid pulling the
`GraphBuilder` fluent API into the voice package:

| Fixture | Nodes | Topology |
|---|---:|---|
| `minimal_voice` | 4 | osc → ADSR → mul → output |
| `fm_voice` | 11 | const → osc → gain (FM depth) → const → mix → `oscillator_from` → ADSR → mul → biquad → gain → output |
| `full_voice` | 10 | osc + noise·gain → mix → ADSR → mul → biquad → gain → delay → output |

`fm_voice` uses `oscillator_from(input_index, waveform)` so the modulator
chain is actually wired to the carrier's frequency input. An earlier
draft used `oscillator(Sine, fixed_freq)` for the carrier, which made
the modulator nodes unreachable and let `analyze` dead-code-eliminate
them. The Codex review on this investigation caught the bug; the numbers
below are post-fix.

## Measurements

Three bench groups, all measuring control-thread cost (no audio thread
involvement):

- `set_template` — exercises `validate_voice_template` in isolation:
  pool already constructed and slots allocated, so the call cost is
  dominated by the discarded `CompiledDsp::compile(...)` plus a
  template-reference swap.
- `note_on` — the per-voice compile that is paid by design (`max_voices=1`
  forces slot stealing every iteration, recompiling each time;
  `params=[]` skips control validation).
- `voicepool_new` — validate + 32 × `VoiceSlot::new` (each allocates a
  `mono_buffer` of `block_size=128` doubles). `CompiledTemplate::analyze`
  is hoisted out of the bench closure, so the number reports the
  steady-state per-call cost from an already-analyzed template, not the
  cost from raw authoring nodes.

### wasm-gc (browser AudioWorklet target)

| Fixture | `set_template` (waste) | `note_on` (productive) | ratio | `voicepool_new` |
|---|---:|---:|---:|---:|
| minimal_voice (4 nodes) | 1.56 µs | 1.65 µs | 0.94× | 5.76 µs |
| fm_voice (11 nodes) | 4.18 µs | 4.25 µs | 0.98× | 8.05 µs |
| full_voice (10 nodes) | 6.96 µs | 7.06 µs | 0.99× | 11.43 µs |

### native (future CLAP-plugin target)

| Fixture | `set_template` (waste) | `note_on` (productive) | ratio | `voicepool_new` |
|---|---:|---:|---:|---:|
| minimal_voice (4 nodes) | 1.62 µs | 1.59 µs | 1.02× | 3.57 µs |
| fm_voice (11 nodes) | 3.04 µs | 3.42 µs | 0.89× | 5.36 µs |
| full_voice (10 nodes) | 4.73 µs | 4.47 µs | 1.06× | 6.68 µs |

## Interpretation

The waste-to-productive ratio is **0.89×–1.06× across both targets** —
the validator does pay roughly the full cost of `CompiledDsp::compile`
and discards the result. So the double-compile is real, not hypothetical.

The absolute magnitude is **1.6–7 µs of control-thread work per
`set_template` / `VoicePool::new` call**, with native actually cheaper
than wasm-gc on the larger fixtures (no RC-overhead blowup, contra the
hypothesis from the MoonBit cost-model notes).

The `VoicePool::new` gap above `set_template` is ~3.5–4.2 µs across all
fixtures, matching expected cost for 32 × `VoiceSlot::new` (each
allocating a `block_size=128` `AudioBuffer`). For small graphs, slot
allocation costs roughly as much as the validate-compile itself.

## Verdict

**Defer the optimization indefinitely.** Control-thread budgets are at
least 16.6 ms (one frame at 60 Hz) and realistically 100 ms ("feels
instant" for authoring). Even 1000 `set_template`/s on the slowest
fixture costs 7 ms/s of wasted CPU, which is invisible to a user.

The proposed fix (extract `CompiledTemplate::is_compilable_in(ctx)`
topology-only check) would require factoring the structural validation
out of `CompiledDsp::compile` in the graph package, which is non-trivial
refactoring for a saving nobody can perceive.

Revisit only if:

1. A real authoring-latency complaint surfaces against `set_template` or
   pool construction.
2. Live-coding patterns push `set_template` rates above ~1 kHz sustained.
3. A JS-target deployment is added (only wasm-gc + native verified
   here).

The benchmark file lives in-tree so any future complaint can re-measure
in seconds.
