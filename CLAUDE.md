# mdsp — MoonBit DSP Audio Engine

Repository guidance lives in `AGENTS.md`.
Use `AGENTS.md` as the source of truth for project structure, MoonBit
conventions, development workflow, and review standards.

@~/.claude/moonbit-base.md

## Project Structure

Single module `dowdiness/mdsp` with packages:

| Package | Purpose |
|---------|---------|
| `lib/` | Core DSP library — oscillators, filters, graph, tagless algebra, voice pool |
| `pattern/` | Pattern engine — rational time, arcs, events, combinators, control maps |
| `/` (root) | Demo entrypoint — wasm/js exports for browser prototype |
| `cmd/main` | Executable entry point |
| `browser/` | Browser/AudioWorklet integration |
| `browser_test/` | Browser integration tests |

## Commands

```bash
moon check && moon test        # 405 tests
moon build --target wasm-gc    # Browser WASM build
moon run cmd/main              # CLI entry point
```

Before every commit:
```bash
moon info && moon fmt
```

## Documentation

**Main docs:** [docs/](docs/)

- **Blueprint:** `docs/salat-engine-blueprint.md` — full architecture vision
- **Phase 0 spec:** `docs/step0-instruction.md` — original proof-of-concept spec
- **Technical reference:** `docs/salat-engine-technical-reference.md` — authoritative for graph runtime-control
- **Structural editor:** `docs/dsp-structural-editor-*.md` — vision and architecture

## Key Facts

- Phases 0–4 complete: AudioWorklet proof, DSP primitives, compiled graph runtime, voice management, pattern engine
- Finally Tagless two-layer architecture (traits + concrete AST)
- Compiled graph with hot-swap, topology editing, and stereo support
- Voice pool: 32+ polyphonic voices with priority stealing and per-voice pan mixdown
- Pattern engine: Strudel-inspired algebra with rational time, 8 combinators, ControlMap output
- Audio constants: 48000 Hz sample rate, 128 samples per buffer
- No allocation in the audio thread; pre-allocated buffers
