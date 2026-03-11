# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

`mdsp` is a MoonBit DSP audio engine library in the Salat Engine project. The
current goal is Phase 0: proving MoonBit `wasm-gc` can generate audio in an
`AudioWorklet`, while keeping a path open for native targets such as CLAP
plugins.

You can browse and install extra skills here:
<https://github.com/moonbitlang/skills>

## Project Structure

- MoonBit packages are organized per directory; each directory contains a
  `moon.pkg` file listing its dependencies. Each package has its files and
  blackbox test files (ending in `_test.mbt`) and whitebox test files (ending in
  `_wbtest.mbt`).

- In the toplevel directory, there is a `moon.mod.json` file listing module
  metadata.

- The root package exports the core DSP library from `mdsp.mbt`.

- `cmd/main/` contains the executable entry point and its package manifest.

- `docs/` contains the main design documents:
  `docs/salat-engine-blueprint.md` for the full architecture vision and
  `docs/step0-instruction.md` for the current phase spec.

- For Phase 2 graph runtime-control behavior, treat
  `docs/salat-engine-technical-reference.md` as the authoritative source of
  truth. Update it first whenever `CompiledDsp`, `GraphControl`,
  `apply_control(...)`, `apply_controls(...)`, or the runtime-control support
  matrix changes; only then adjust summary docs like `RESULTS.md` or
  `docs/salat-engine-blueprint.md` if needed.

## Package Map

- `/` (root package): core DSP library

- `cmd/main`: executable entry point

## Architecture

- Follow the blueprint direction: a Finally Tagless two-layer architecture
  using traits for extensibility and enums for concrete ASTs.

- Favor incremental computation for memoized DSP graph updates.

- Do not allocate in the audio thread; prefer pre-allocated buffers.

- Compile the graph instead of interpreting it.

- Audio constants used by the project are `48000` Hz sample rate and `128`
  samples per buffer.

## MoonBit Language Notes

- Be careful with `pub` vs `pub(all)`; they have different semantics.

- `._` tuple access is deprecated; use `.0`, `.1`, and so on.

- `try?` does not catch `abort`; use explicit error handling when needed.

- The `?` operator is not always supported; fall back to explicit
  `match`-based handling when necessary.

- `ref` is a reserved keyword; do not use it as a variable or field name.

- Blackbox tests cannot construct internal structs. Use whitebox tests or
  expose constructors when needed.

- Prefer MoonBit 0.8 constructor style for wrapper and record APIs: declare an
  internal constructor in the `struct` body (for example
  `fn new(data : FixedArray[Double]) -> AudioBuffer`) and expose public
  `Type::new(...)` or named helpers like `Type::filled(...)` explicitly. Use
  this to keep zero-copy and allocating construction paths distinct.

- For cross-target builds, prefer per-file conditional compilation rather than
  `supported-targets` in package configuration.

## Coding convention

- MoonBit code is organized in block style, each block is separated by `///|`,
  the order of each block is irrelevant. In some refactorings, you can process
  block by block independently.

- Try to keep deprecated blocks in file called `deprecated.mbt` in each
  directory.

- Trait implementations should use `pub impl Trait for Type with ...`, with one
  method per impl block.

- Arrow functions should use `() => expr` or `() => { ... }`. For an empty
  function body, use `() => ()`.

## Tooling

- `moon check` type-checks the project and also runs in the pre-commit hook.

- `moon build` builds the project.

- `moon build --target wasm-gc` builds for the current browser-targeted
  WebAssembly GC work.

- `moon run cmd/main` runs the CLI entry point.

- `moon fmt` formats the code.

- `moon ide` provides project navigation helpers like `peek-def`, `outline`, and
  `find-references`. See $moonbit-agent-guide for details.

- `moon info` is used to update the generated interface of the package, each
  package has a generated interface file `.mbti`, it is a brief formal
  description of the package. If nothing in `.mbti` changes, this means your
  change does not bring the visible changes to the external package users, it is
  typically a safe refactoring.

- In the last step, run `moon info && moon fmt` to update the interface and
  format the code. Check the diffs of `.mbti` file to see if the changes are
  expected.

- Run `moon test` to check tests pass. MoonBit supports snapshot testing; when
  changes affect outputs, run `moon test --update` to refresh snapshots.

- Prefer `assert_eq` or `assert_true(pattern is Pattern(...))` for results that
  are stable or very unlikely to change. Use snapshot tests to record current
  behavior. For solid, well-defined results (e.g. scientific computations),
  prefer assertion tests. You can use `moon coverage analyze > uncovered.log` to
  see which parts of your code are not covered by tests.

- If a user asks to use a tool, agent, or command name that is not obviously a
  built-in assistant tool, first verify whether it exists as a local CLI in the
  terminal before saying it is unavailable.

## Development Workflow

1. Make edits.
2. Run `moon check`.
3. Run `moon test`.
4. Run `moon test --update` if snapshots need to change.
5. Run `moon info`.
6. Check `.mbti` diffs and confirm any interface changes are expected.
7. Run `moon fmt`.

- The minimum pre-commit workflow is `moon info && moon fmt`, then inspect the
  `.mbti` diff.

- Git hooks can be enabled with
  `chmod +x .githooks/pre-commit && git config core.hooksPath .githooks`.

## Code Review Standards

- Review thoroughly even for small changes.

- Pay attention to integer overflow, zero or negative inputs, boundary
  validation, and generation wrap-around.

- Do not suggest removing public API wrapper or ID types merely because they
  appear unused locally; downstream packages may rely on them.

- Verify actual API names before writing tests or review comments.

## Git Workflow

- Check whether the repository is initialized before running git commands.

- After rebases, verify files still live in the correct directories.

- If a request mentions committing remaining files, interpret it generously but
  verify what is actually staged and modified.
