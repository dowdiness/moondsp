# moondsp

A live-codable DSP audio engine written in [MoonBit](https://www.moonbitlang.com/), targeting browser AudioWorklet via wasm-gc. Patterns describe *what* plays *when*; DSP graphs describe *how* it sounds.

moondsp combines a Strudel/TidalCycles-inspired pattern algebra with a compiled signal-processing graph, a polyphonic voice pool, and a browser AudioWorklet runtime — all in one codebase, all in MoonBit.

## Quick start

```bash
moon check && moon test       # type-check + run the full test suite
moon build --target wasm-gc   # build for browser
moon run cmd/main             # run CLI entry point
```

To hear it in the browser, open `web/index.html` after building. The AudioWorklet loads the compiled wasm-gc module and drives the DSP graph in real time.

## What moondsp can do today

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

**Mini-notation parser** — the `mini/` package turns a short text string into a `Pat[ControlMap]`, so you can write `s("bd sd hh sd")` or `note("60 64 67")` and chain `.fast(n)`, `.slow(n)`, `.rev()` on the result.

**Pattern → DSP scheduler** — the `scheduler/` package drives a `VoicePool` from a `Pat[ControlMap]`: it converts the pattern's event stream into `note_on`/`note_off` calls, routes control-map entries through a `ControlBindingMap`, and ticks the block clock. `PatternScheduler::process_block` is the one call that turns patterns into audio.

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
           PatternScheduler.process_block
```

**Pattern layer** operates at "human time" — rational fractions of musical cycles. It produces events describing what should happen.

**DSP layer** operates at "audio time" — 128 samples per callback at 48 kHz (2.67 ms budget). It compiles declarative node graphs into flat execution plans and runs them without allocation.

**Bridge** — `scheduler/` connects the two: `PatternScheduler::process_block` queries a `Pat[ControlMap]` over the current block's time arc, turns events into `VoicePool::note_on`/`note_off` calls, and pushes control-map entries through a `ControlBindingMap` onto `GraphControl` slots.

## Repository layout

```
./              Library public API facade (`moondsp.mbt` re-exports from dsp/, graph/, voice/)
dsp/            DSP primitives, tagless algebra, pan math
graph/          Compiled graph runtime, topology editing, hot-swap, control binding
voice/          Polyphonic voice pool with priority stealing
pattern/        Pattern engine: rational time, combinators, control maps (standalone)
mini/           Mini-notation parser: text → Pat[ControlMap]
scheduler/      Pattern scheduler: bridges pattern events to voice pool
browser/        AudioWorklet integration (wasm-gc/js exports)
browser_test/   Browser-integration test wrapper
web/            Browser demo UI (HTML + AudioWorklet processor)
cmd/main/       CLI entry point
docs/           Architecture blueprint, technical reference, performance snapshots
```

The `pattern/` package has zero dependency on the DSP layers — it compiles and tests independently.

## Performance

The audio budget at 128 samples / 48 kHz is 2.67 ms per block. The graph
runtime is designed around that budget: a single compiled voice (oscillator
+ filter + delay + ADSR) processes in the low-microsecond range, and 32
simultaneous FM voices comfortably fit inside the block. Compilation and
hot-swap crossfades are also microsecond-scale, so graphs can be rebuilt or
swapped between blocks without audible glitches.

For measured numbers, see the dated snapshots under
[`docs/performance/`](docs/performance/) (new measurements go in new files —
older snapshots are preserved rather than overwritten, so you can see drift
over time).

## Development

```bash
moon check            # type-check
moon test             # run the full test suite
moon test -p dowdiness/moondsp  # run integration tests against the facade (root package only)
moon test -p pattern  # run pattern-engine tests only
moon info && moon fmt # regenerate interfaces + format (run before committing)
moon bench --release -p graph -f graph_benchmark.mbt  # run performance benchmarks
npm run test:browser  # Playwright browser-integration tests (builds wasm-gc first)
```

The project follows an incremental edit rule: run `moon check` after every file edit, fix errors before proceeding.

## Documentation

Start at the **[docs index](docs/README.md)**, which groups material by audience:

- **[Technical reference](docs/salat-engine-technical-reference.md)** — node types, parameter slots, runtime control surface (authoritative for graph runtime-control behavior)
- **[Blueprint](docs/salat-engine-blueprint.md)** — full architecture vision, design principles, roadmap
- **[Performance snapshots](docs/performance/)** — dated benchmark results (new measurements go in new files)
- **[Architecture decisions](docs/decisions/)** — short ADRs distilling *why* the codebase looks the way it does (each links to the archived plan/spec)
- **[`CLAUDE.md`](CLAUDE.md)** — project map and conventions for contributors

## Project status

| Phase | Status | Summary |
|-------|--------|---------|
| 0 — Platform proof | Complete | MoonBit wasm-gc runs in browser AudioWorklet |
| 1 — DSP primitives | Complete | Oscillators, filters, envelopes, delay, gain, mix, clip, pan |
| 2 — Graph compiler | Complete | Compiled graphs, hot-swap, topology editing, stereo |
| 3 — Voice management | Complete | 32+ voice pool with priority stealing and stereo mixdown |
| 4 — Pattern engine | Complete | Rational time, 8 combinators, ControlMap output |
| 5 — Pattern × DSP | Complete | `scheduler/` + `mini/` wire pattern events to voice allocation |
| 6 — incr integration | Planned | Incremental memoization for pattern/graph changes |
| 7+ — UI, native, collab | Planned | REPL, CLAP plugins, CRDT multi-user |

## License

Apache-2.0
