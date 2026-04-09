# mdsp — MoonBit DSP audio engine (Salat Engine)

`mdsp` is a MoonBit DSP audio engine library in the Salat Engine project.
Phases 0–4 are complete: wasm-gc AudioWorklet proof (Phase 0), DSP primitives
(Phase 1), compiled graph runtime with hot-swap, topology editing, and
stereo support (Phase 2), polyphonic voice pool with priority stealing and
per-voice pan mixdown (Phase 3), and Strudel-inspired pattern engine with
rational time and combinators (Phase 4). The path remains open for native
targets such as CLAP plugins.

@~/.claude/moonbit-base.md

## Project Structure

**Module:** `dowdiness/mdsp`

| Package | Path | Purpose |
|---------|------|---------|
| `dowdiness/mdsp` | `./` | Demo entrypoint (`mdsp.mbt`), delegates to `lib/` |
| `dowdiness/mdsp/lib` | `lib/` | Core DSP library (oscillators, filters, graph compiler, voice pool) |
| `dowdiness/mdsp/pattern` | `pattern/` | Standalone pattern engine (rational time, combinators, control maps) — zero dep on `lib/` |
| `dowdiness/mdsp/browser` | `browser/` | AudioWorklet export wrapper |
| `dowdiness/mdsp/browser_test` | `browser_test/` | Browser integration test wrapper |
| `dowdiness/mdsp/cmd/main` | `cmd/main/` | CLI entry point |

## Commands

```bash
moon check                      # Lint
moon test                       # Run tests
moon build --target wasm-gc     # Build for browser (AudioWorklet)
moon run cmd/main               # Run CLI
moon info && moon fmt           # Before committing
```

## Architecture

- **Finally Tagless two-layer:** traits for extensibility, enums for concrete ASTs
- **Compiled graph:** compile the DSP graph, do not interpret it
- **No audio-thread allocation:** pre-allocated buffers only
- **Incremental computation:** memoized DSP graph updates
- **Audio constants:** 48000 Hz sample rate, 128 samples per buffer

**Source of truth:** `docs/salat-engine-technical-reference.md` is authoritative for Phase 2 graph runtime-control behavior (`CompiledDsp`, `GraphControl`, `apply_control`, `apply_controls`, runtime-control support matrix). Update it first whenever these change.

## Key Facts

**Docs:** [docs/salat-engine-blueprint.md](docs/salat-engine-blueprint.md) (full architecture vision), [docs/salat-engine-technical-reference.md](docs/salat-engine-technical-reference.md) (Phase 2 reference), [docs/step0-instruction.md](docs/step0-instruction.md) (Phase 0 spec)
