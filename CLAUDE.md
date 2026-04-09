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
| `scheduler/` | Pattern scheduler — bridges pattern engine to DSP voice pool |
| `browser_test/` | Browser integration tests |

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
