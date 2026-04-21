# moondsp — MoonBit DSP Audio Engine

`moondsp` is a MoonBit DSP audio engine library in the Salat Engine project.
Phases 0–5 complete: AudioWorklet proof, DSP primitives, compiled graph
runtime with hot-swap and stereo, voice pool with priority stealing,
pattern engine with rational time, pattern scheduler, and text-to-audio
pipeline with mini-notation parser and synthesized drum sounds. The path
remains open for native targets such as CLAP plugins.

@~/.claude/moonbit-base.md

## Project Structure

**Module:** `dowdiness/moondsp`

| Package | Path | Purpose |
|---------|------|---------|
| `dowdiness/moondsp` | `./` | Library public API facade — re-exports the full library surface from `@dsp`, `@graph`, and `@voice` so external consumers and internal sub-packages both write `@moondsp.X` |
| `dowdiness/moondsp/dsp` | `dsp/` | DSP primitives (oscillators, filters, tagless algebra, pan math) |
| `dowdiness/moondsp/graph` | `graph/` | Compiled graph runtime (compile, optimize, topology edit, hot-swap, control binding) |
| `dowdiness/moondsp/voice` | `voice/` | Polyphonic voice pool with priority stealing |
| `dowdiness/moondsp/pattern` | `pattern/` | Standalone pattern engine (rational time, combinators, control maps) — zero dep on the DSP layers |
| `dowdiness/moondsp/mini` | `mini/` | Mini-notation parser: text → `Pat[ControlMap]` (e.g. `s("bd sd hh sd").fast(2)`) |
| `dowdiness/moondsp/scheduler` | `scheduler/` | Pattern scheduler — bridges pattern engine to DSP voice pool |
| `dowdiness/moondsp/browser` | `browser/` | AudioWorklet export wrapper with multi-pool drum routing |
| `dowdiness/moondsp/browser_test` | `browser_test/` | Browser integration test wrapper |
| `dowdiness/moondsp/cmd/main` | `cmd/main/` | CLI entry point |

## Architecture

- **Finally Tagless two-layer:** traits for extensibility, enums for concrete ASTs
- **Compiled graph:** compile the DSP graph, do not interpret it
- **No audio-thread allocation:** pre-allocated buffers only
- **Incremental computation:** memoized DSP graph updates
- **Audio constants:** 48000 Hz sample rate, 128 samples per buffer

**Source of truth:** `docs/salat-engine-technical-reference.md` is authoritative for graph runtime-control behavior. Update it first whenever these change.

## Commands

```bash
moon check && moon test        # 470 tests
moon build --target wasm-gc    # Browser WASM build
moon run cmd/main              # CLI entry point
```

Before every commit:
```bash
moon info && moon fmt
```

## Documentation

Browse `docs/` for architecture, decisions, development guides, and performance snapshots. Key rules:

- Architecture docs = principles only, never reference specific types/fields/lines
- Code is the source of truth — if a doc and the code disagree, the doc is wrong
- `docs/salat-engine-technical-reference.md` is authoritative for graph runtime-control
- `docs/archive/` = completed work. Do not search here unless asked for historical context.

## Package Map

The SessionStart hook runs `scripts/package-overview.sh` which provides a live package map at the start of every session. Use `moon ide outline <path>` to explore any package's public API before modifying it. Read `moon.mod.json` for module dependencies.
