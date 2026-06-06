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
| `dowdiness/moondsp` | `./` | Library public API facade — re-exports the full library surface from `@dsp`, `@graph`, `@voice`, and `@identity` so external consumers and internal sub-packages both write `@moondsp.X` |
| `dowdiness/moondsp/dsp` | `dsp/` | DSP primitives (oscillators, filters, tagless algebra, pan math) |
| `dowdiness/moondsp/graph` | `graph/` | Compiled graph runtime (compile, optimize, topology edit, hot-swap, control binding) |
| `dowdiness/moondsp/voice` | `voice/` | Polyphonic voice pool with priority stealing |
| `dowdiness/moondsp/identity` | `identity/` | Dependency-free stable ID wrappers and revision tokens for incremental editing |
| `dowdiness/moondsp/pattern` | `pattern/` | Standalone pattern engine (rational time, combinators, control maps, authoring docs) — zero dep on the DSP layers |
| `dowdiness/moondsp/mini` | `mini/` | Mini-notation parser: text → `Pat[ControlMap]` (e.g. `s("bd sd hh sd").fast(2)`) |
| `dowdiness/moondsp/song` | `song/` | Long-form section scaffold with identity `TimeScope`, between pattern and scheduler |
| `dowdiness/moondsp/scheduler` | `scheduler/` | Pattern scheduler — bridges pattern engine to DSP voice pool |
| `dowdiness/moondsp/browser` | `browser/` | AudioWorklet export wrapper with multi-pool drum routing |
| `dowdiness/moondsp/browser_test` | `browser_test/` | Browser integration test wrapper |
| `dowdiness/moondsp/clap_engine` | `clap_engine/` | Native CLAP synth engine core around graph + voice pool |
| `dowdiness/moondsp/clap_host` | `clap_host/` | Primitive integer-handle bridge for C CLAP shims |
| `dowdiness/moondsp/clap_plugin` | `clap_plugin/` | Native payload package plus prototype CLAP C ABI shim |
| `dowdiness/moondsp/cmd/main` | `cmd/main/` | CLI entry point |

## Architecture

- **Finally Tagless two-layer:** traits for extensibility, enums for concrete ASTs
- **Compiled graph:** compile the DSP graph, do not interpret it
- **No audio-thread allocation:** pre-allocated buffers only
- **Incremental computation:** memoized DSP graph updates
- **Audio constants:** 48000 Hz sample rate, 128 samples per buffer
- **Graph boundary types:** `Array[DspNode]` is the authoring exchange type; `CompiledTemplate` is the runtime exchange type. One canonical crossing: `CompiledTemplate::analyze`. See ADR-0010 for the contract and `scripts/check-public-boundary.sh` for enforcement.

**Source of truth:** `docs/salat-engine-technical-reference.md` is authoritative for graph runtime-control behavior. Update it first whenever these change.

## Native ABI and CLAP Policy

- Keep host/plugin ABI details at the outer boundary: CLAP C ABI in
  `clap_plugin/`, primitive MoonBit handles in `clap_host/`, synth state in
  `clap_engine/`, reusable DSP below.
- Prefer official vendored headers or repeatable verification over handwritten
  native ABI subsets.
- Vendored native headers must record upstream version, source URL, checksum,
  and license.
- Do not let CLAP host/plugin details leak into graph, voice, pattern,
  scheduler, or browser packages.
- Validator success is necessary evidence, not DAW-readiness. Do not claim
  DAW-ready until a real CLAP host/DAW has loaded the plugin.
- Keep the production gates explicit: stable MoonBit bridge symbols, real
  host/DAW load, and audio-thread allocation audit.

## MoonBit Style Notes

- Loop expressions are best for loops that naturally compute a value: sums,
  counts, folds, `any`/`all` scans, min/max/peak searches, and small tuple
  accumulators. Do not mechanically rewrite procedural loops; keep parser
  state machines, buffer-filling loops, hot DSP paths, and side-effect-heavy
  graph/edit code imperative when that is clearer.

## Commands

```bash
moon check && moon test        # full test suite
moon build --target wasm-gc    # Browser WASM build
moon run cmd/main              # CLI entry point
scripts/build-clap-prototype.sh # Linux CLAP prototype shared object
scripts/smoke-clap-prototype.sh # Local CLAP dlopen/process smoke test
scripts/validate-clap-prototype.sh # Build + clap-validator prototype check
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

The SessionStart hook runs `scripts/package-overview.sh` which provides a live package map at the start of every session. Use `moon ide outline <path>` to explore any package's public API before modifying it. Read `moon.mod` for module dependencies.
