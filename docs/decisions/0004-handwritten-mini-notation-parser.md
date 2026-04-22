# ADR-0004: Hand-written mini-notation parser

- **Status:** Accepted
- **Date:** 2026-04-22 (decision shipped 2026-04-15, Phase 5)
- **Source:** [`docs/superpowers/specs/archive/2026-04-15-phase5-text-pattern-design.md`](../superpowers/specs/archive/2026-04-15-phase5-text-pattern-design.md)
  §2 ("Risk: loom wasm-gc compatibility")

## Context

Phase 5 needed a mini-notation parser to take a TidalCycles-style pattern
expression like `s("bd sd hh sd").fast(2)` and produce a `Pat[ControlMap]`
that the existing scheduler/voice infrastructure could consume. The parser
runs **inside the AudioWorklet wasm instance** (so the main thread sends
raw text and the worklet returns either a parsed pattern or an error
message) — which means the parser must compile to **wasm-gc**.

The original plan called for using `dowdiness/loom` (sibling parser
combinator library in the canopy repo) plus `dowdiness/seam` for CST
manipulation. This would have given grammar-as-data, free positional
errors, and zero hand-written tokenizer code. The plan explicitly flagged
the wasm-gc compatibility risk and reserved a fallback:

> canopy targets JS by default. loom must compile to wasm-gc without
> JS-specific FFI. Verify early in implementation. Fallback: hand-written
> recursive descent parser (~150 lines) with the same public API.

The risk gate was the first implementation step. loom did not pass it
cleanly for the wasm-gc target within the Phase 5 budget.

## Decision

Ship the fallback: a hand-written recursive-descent parser in
`mini/parser.mbt`, with no path dependency on `loom` or `seam`.

`mini/` ships with four files:

- `parser.mbt` — recursive-descent parser, `~420 LOC`. Implements the full
  grammar in the spec (`expr`, `primary`, `method`, `notation`, `layer`,
  `element`, `atom`).
- `drums.mbt` — `drum_midi(name) -> Int?` General-MIDI lookup (`bd`=36,
  `sd`=38, `hh`=42, etc.).
- `mini.mbt` — public entry point.
- `mini_test.mbt` — parser tests covering grammar, method chaining, error
  cases, and position information in error messages.

`Pat::filter_map` (added to the `pattern/` package as part of the same
phase) lets the browser layer split a parsed pattern into per-sound
sub-patterns before routing to the corresponding `VoicePool`.

## Consequences

**Positive**

- Phase 5 shipped without introducing a cross-repo dependency that was not
  yet wasm-gc-ready.
- The parser is a single self-contained file with no external grammar DSL
  to learn — easy for a new contributor to read and modify.
- Error messages carry position information (the spec's success criterion).
- Removing loom/seam path deps from `moon.mod.json` (commit `ab43e60`)
  simplified the build graph for the browser target.

**Negative**

- Adding a new mini-notation feature (euclidean rhythms `bd(3,8)`, randomness
  `bd?`, polymeter, etc.) means hand-editing the parser instead of extending
  a grammar definition. The 420-line file will grow with each Phase-6+
  addition.
- Two independent grammars now live in the moondsp ecosystem (this one and
  whatever loom does), with no shared infrastructure. If we later adopt loom,
  this parser becomes the migration cost.
- The parser duplicates lexing concerns (whitespace handling, identifier
  scanning) that a combinator/lexer library would have factored out.

**Revisit when:** loom (or another MoonBit parser library) gains verified
wasm-gc support and the mini-notation surface grows past what the
recursive-descent parser cleanly expresses (rough threshold: when adding
a new feature requires touching more than two of the parser's grammar
functions). At that point, re-evaluate migration vs. extending the
hand-written parser.
