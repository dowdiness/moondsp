# mdsp

A live-codable DSP audio engine written in [MoonBit](https://www.moonbitlang.com/), targeting browser AudioWorklet via wasm-gc. Patterns describe *what* plays *when*; DSP graphs describe *how* it sounds.

mdsp combines a Strudel/TidalCycles-inspired pattern algebra with a compiled signal-processing graph, a polyphonic voice pool, and a browser AudioWorklet runtime — all in one codebase, all in MoonBit.

## Quick start

```bash
moon check && moon test   # type-check + run 405 tests
moon build --target wasm-gc   # build for browser
moon run cmd/main             # run CLI entry point
```

To hear it in the browser, open `web/index.html` after building. The AudioWorklet loads the compiled wasm-gc module and drives the DSP graph in real time.

## What mdsp can do today

**DSP primitives** — sine/saw/square/triangle oscillators, white noise, ADSR envelopes, biquad filters (LPF/HPF/BPF), delay lines with feedback, gain, mix, hard clip, equal-power pan, and parameter smoothing. All zero-allocation in the audio thread.

**Compiled graph runtime** — declare a signal graph as an array of `DspNode` values, compile it into a topologically sorted execution plan, and process 128 samples per block at 48 kHz. Supports hot-swap (equal-power crossfade between graphs), topology editing (insert/delete/replace nodes at runtime), and mono-to-stereo routing.

**Finally Tagless DSP algebra** — the same graph definition works as both a concrete AST for optimization and a trait-driven interpretation for extensibility:

```moonbit nocheck
///|
fn[T : FilterSym] exit_deliverable() -> T {
  let lfo = T::oscillator(T::constant(2.0), Waveform::Sine)
  let freq = range(lfo, 200.0, 400.0)
  let carrier = T::oscillator(freq, Waveform::Sine)
  let filtered = T::biquad(carrier, BiquadMode::LowPass, 800.0, 1.0)
  T::output(T::gain(filtered, 0.3))
}
```

This compiles into an FM synthesis patch: a 2 Hz LFO sweeps a carrier between 200–400 Hz through a low-pass filter.

**Polyphonic voice pool** — 32+ simultaneous voices with priority-based stealing (idle > oldest releasing > oldest active), generation-tagged handles for safe note control, two-stage silence detection (ADSR idle AND output buffer silent), and per-voice equal-power pan mixed to stereo. No allocation during `process()`.

**Pattern engine** — a standalone `pattern/` package implementing Strudel's core model: patterns are query functions over rational-time arcs, producing events with control maps. Eight combinators (`silence`, `pure`, `fast`, `slow`, `rev`, `sequence`, `stack`, `every`) compose into expressive rhythmic structures:

```moonbit nocheck
// C major triad played twice per cycle
sequence([note_name("c3"), note_name("e3"), note_name("g3")]).fast(Rational::from_int(2))
```

Querying this over one cycle produces 6 events with exact rational time boundaries — no floating-point drift.

## How it works

The engine has two independent layers connected by a control map:

```
Pattern Engine                    DSP Engine
  Pat.query(arc)                    CompiledDsp.process(ctx, buf)
       |                                  |
       v                                  v
  Array[Event[ControlMap]]         VoicePool.process(ctx, L, R)
       |                                  ^
       +-- { note: 60, cutoff: 800 } -----+
           event_to_dsp (Phase 5)
```

**Pattern layer** operates at "human time" — rational fractions of musical cycles. It produces events describing what should happen.

**DSP layer** operates at "audio time" — 128 samples per callback at 48 kHz (2.67 ms budget). It compiles declarative node graphs into flat execution plans and runs them without allocation.

Phase 5 (not yet implemented) will bridge the two: pattern events become `VoicePool::note_on` calls with `GraphControl` parameters.

## Repository layout

```
lib/           Core DSP: oscillators, filters, graph compiler, voice pool
pattern/       Pattern engine: rational time, combinators, control maps (standalone)
browser/       AudioWorklet integration (wasm-gc/js exports)
web/           Browser demo UI (HTML + AudioWorklet processor)
cmd/main/      CLI entry point
docs/          Architecture blueprint, technical reference, performance snapshots
```

The `pattern/` package has zero dependency on `lib/` — it compiles and tests independently.

## Performance

All process benchmarks at 128 samples / 48 kHz (budget: 2.67 ms):

| Graph | Nodes | Process time |
|-------|------:|-------------:|
| Passthrough | 2 | 0.19 us |
| Minimal voice (osc + gain) | 4 | 1.20 us |
| FM synthesis voice | 12 | 6.79 us |
| Full voice (osc + noise + ADSR + filter + delay) | 12 | 3.43 us |
| Feedback voice (z^-1 back-edge) | 7 | 4.46 us |
| Stereo chain (15 nodes) | 15 | 5.67 us |

At 7 us per FM voice, 32 simultaneous voices fit in ~224 us — well under the 2.67 ms real-time budget. Compilation takes 1–13 us. Hot-swap crossfade takes 7–27 us. See `docs/performance/` for dated benchmark snapshots.

## Development

```bash
moon check          # type-check
moon test           # run all 405 tests
moon test -p lib    # run DSP tests only
moon test -p pattern # run pattern tests only
moon info && moon fmt   # regenerate interfaces + format (run before committing)
moon bench --release -p lib -f graph_benchmark.mbt   # run performance benchmarks
```

The project follows an incremental edit rule: run `moon check` after every file edit, fix errors before proceeding.

## Documentation

- **[Blueprint](docs/salat-engine-blueprint.md)** — full architecture vision, design principles, and Phases 0–9 roadmap
- **[Technical reference](docs/salat-engine-technical-reference.md)** — node types, parameter slots, runtime control surface
- **[Performance snapshots](docs/performance/)** — dated benchmark results (new measurements go in new files)
- **[Design specs](docs/superpowers/specs/)** — per-feature design documents
- **[Implementation plans](docs/superpowers/plans/)** — task-level plans for each feature

## Project status

| Phase | Status | Summary |
|-------|--------|---------|
| 0 — Platform proof | Complete | MoonBit wasm-gc runs in browser AudioWorklet |
| 1 — DSP primitives | Complete | Oscillators, filters, envelopes, delay, gain, mix, clip, pan |
| 2 — Graph compiler | Complete | Compiled graphs, hot-swap, topology editing, stereo |
| 3 — Voice management | Complete | 32+ voice pool with priority stealing and stereo mixdown |
| 4 — Pattern engine | Complete | Rational time, 8 combinators, ControlMap output |
| 5 — Pattern x DSP | Next | Wire pattern events to voice allocation |
| 6 — incr integration | Planned | Incremental memoization for pattern/graph changes |
| 7+ — UI, native, collab | Planned | REPL, CLAP plugins, CRDT multi-user |

## License

Apache-2.0
