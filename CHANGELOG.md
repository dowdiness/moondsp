# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **Collapsed facade**: removed the `dowdiness/moondsp/lib` sub-package. The
  root `dowdiness/moondsp` module now re-exports directly from `@dsp`,
  `@graph`, and `@voice`, eliminating a drift source where symbols added to
  one facade were missed in the other (notably `CompiledTemplate`, now
  exposed at the root). Internal sub-packages that previously imported
  `dowdiness/moondsp/lib @lib` now import `dowdiness/moondsp @moondsp`.
- **Labelled constructor arguments**: five footgun-prone positional
  signatures now require labels at the call site, eliminating whole
  classes of unit / ordering bugs (ms vs. s on ADSR times, sample-rate
  vs. block-size swap on `DspContext`, cutoff-vs-Q swap on biquad):
  `DspContext::new(sample_rate~, block_size~)`,
  `Adsr::new(attack_ms~, decay_ms~, sustain~, release_ms~)`,
  `DspNode::adsr(attack_ms~, decay_ms~, sustain~, release_ms~)`,
  `DspNode::biquad(input~, mode~, cutoff_hz~, q~)`,
  `Oscillator::process(..., freq_hz~)`. The corresponding trait methods
  (`DspSym::adsr`, `FilterSym::biquad`) remain positional for now.

## [0.1.0] - 2026-04-21

First public release. MoonBit DSP audio engine covering Phases 0–5 of the
Salat Engine roadmap: AudioWorklet proof, DSP primitives, compiled graph
runtime, polyphonic voice pool, pattern engine, and a pattern-to-DSP
scheduler with mini-notation support.

### Added

- **DSP primitives** (`dsp/`) — sine/saw/square/triangle oscillators, white
  noise, ADSR envelopes, biquad filters (LPF/HPF/BPF), delay lines with
  feedback, gain, mix, hard clip, equal-power pan, and parameter smoothing.
  All zero-allocation in the audio thread.
- **Compiled graph runtime** (`graph/`) — declare signal graphs as `DspNode`
  arrays, compile to topologically sorted execution plans, process 128
  samples per block at 48 kHz. Hot-swap via equal-power crossfade, runtime
  topology editing (insert/delete/replace), control binding with
  orphan-binding detection, and mono-to-stereo routing.
- **Finally Tagless DSP algebra** — the same graph definition serves as a
  concrete AST for optimization and a trait-driven interpretation for
  extensibility.
- **Polyphonic voice pool** (`voice/`) — 32+ simultaneous voices with
  priority stealing (idle > oldest releasing > oldest active),
  generation-tagged handles, two-stage silence detection, per-voice
  equal-power pan.
- **Pattern engine** (`pattern/`) — standalone package built on rational
  time arcs with eight combinators (`silence`, `pure`, `fast`, `slow`,
  `rev`, `sequence`, `stack`, `every`) producing events over `ControlMap`.
  Zero dependency on the DSP layers.
- **Mini-notation parser** (`mini/`) — text-to-pattern compiler
  (`s("bd sd hh sd").fast(2)`, `note("60 64 67")`), producing
  `Pat[ControlMap]`.
- **Pattern → DSP scheduler** (`scheduler/`) — drives `VoicePool` from a
  `Pat[ControlMap]`, converting the pattern event stream into
  `note_on`/`note_off` calls routed through a `ControlBindingMap`.
- **Browser AudioWorklet integration** (`browser/`) — wasm-gc build with
  multi-pool drum routing and a Playwright-tested end-to-end path.
- **Facade re-export** — the top-level `dowdiness/moondsp` module exposes
  the full library surface via `pub using` (initially through a
  `dowdiness/moondsp/lib` sub-package, collapsed post-release), so
  consumers write `@moondsp.X`.
- **Test suite** — 470 tests across DSP, graph, voice, pattern, mini,
  scheduler, and browser integration.

### Notes

- This is the first tagged release. The library was previously developed
  under the name `mdsp`; all consumer-facing identifiers now use `moondsp`.
- The `moondsp-browser-tools` npm workspace is `private: true` and exists
  only to host Playwright tests for the browser demo.

[Unreleased]: https://github.com/dowdiness/moondsp/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/dowdiness/moondsp/releases/tag/v0.1.0
