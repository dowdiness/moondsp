# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-04-22

First public release. MoonBit DSP audio engine covering Phases 0–5 of the
Salat Engine roadmap: AudioWorklet proof, DSP primitives, compiled graph
runtime, polyphonic voice pool, pattern engine, and a pattern-to-DSP
scheduler with mini-notation support.

### Added

- **DSP primitives** (`dsp/`) — sine/saw/square/triangle oscillators, white
  noise, ADSR envelopes, biquad filters (LPF/HPF/BPF), delay lines with
  feedback, gain, mix, hard clip, equal-power pan, and parameter smoothing.
  Primitive `process` methods and the compiled-graph per-sample render
  loop are zero-allocation; allocation paths (graph/voice instantiation,
  graph rebuild and topology/hot-swap setup, scheduler pattern query and
  control resolution, browser scheduler routing, debug validation,
  browser telemetry) live outside that loop.
- **Compiled graph runtime** (`graph/`) — declare signal graphs as `DspNode`
  arrays, compile to topologically sorted execution plans, process
  context-sized blocks (the browser AudioWorklet path uses 128-sample
  render quanta at 48 kHz). Hot-swap via equal-power crossfade, runtime
  topology editing (insert/delete/replace), control binding with
  orphan-binding detection, and mono-to-stereo routing.
- **Stereo graph path** — `CompiledStereoDsp` carries terminal-stereo
  graphs (`Mono → Pan → stereo post-processing → StereoOutput`), with
  `StereoGain`/`StereoClip`/`StereoBiquad`/`StereoDelay` post-processing
  nodes, `StereoMixDown` for fold-down, and parallel hot-swap and
  topology controllers (`CompiledStereoDspHotSwap`,
  `CompiledStereoDspTopologyController`).
- **Feedback graphs** — automatic `z^-1` back-edge insertion via a
  self-register model. Direct self-feedback, multiple simultaneous
  back-edges, and mixed-shape feedback (mono back-edges through `Pan`
  into terminal stereo) all compile to bounded recurrences.
- **Finally Tagless DSP algebra** — the same graph definition serves as a
  concrete AST for optimization and a trait-driven interpretation for
  extensibility.
- **Polyphonic voice pool** (`voice/`) — 32+ simultaneous voices with
  priority stealing (idle > oldest releasing > oldest active),
  generation-tagged handles, two-stage silence detection, per-voice
  equal-power pan.
- **Pattern engine** (`pattern/`) — standalone package built on rational
  time arcs with nine combinators (`silence`, `pure`, `fast`, `slow`,
  `rev`, `sequence`, `stack`, `every`, `filter_map`) producing events
  over `ControlMap`. Zero dependency on the DSP layers.
- **Mini-notation parser** (`mini/`) — text-to-pattern compiler
  (`s("bd sd hh sd").fast(2)`, `note("60 64 67")`), producing
  `Pat[ControlMap]`.
- **Pattern → DSP scheduler** (`scheduler/`) — drives `VoicePool` from a
  `Pat[ControlMap]`. Each event triggers `note_on` with control values
  resolved through a `ControlBindingMap`, and schedules the matching
  `note_off` from the event's end time.
- **Browser AudioWorklet integration** (`browser/`) — wasm-gc build with
  multi-pool drum routing and a Playwright-tested end-to-end path.
- **Facade re-export** — the top-level `dowdiness/moondsp` module
  re-exports the core DSP/graph/voice surface via `pub using` from `@dsp`,
  `@graph`, and `@voice`, so consumers write `@moondsp.X` for primitives,
  the compiled graph runtime, and the voice pool. The higher-level
  `pattern/`, `mini/`, `scheduler/`, and `browser/` packages are imported
  directly under their canonical paths.
- **Test suite** — 573 MoonBit tests across DSP, graph, voice, pattern,
  mini, and scheduler, plus a separate Playwright browser-integration
  suite (`npm run test:browser`).

### Notes

- This is the first tagged release. The library was previously developed
  under the name `mdsp`; all consumer-facing identifiers now use `moondsp`.
- **Labelled constructor arguments**: five constructors take labelled
  arguments at the call site to make intent explicit and surface ordering
  mistakes at compile time (ms vs. s on ADSR times, sample-rate vs.
  block-size on `DspContext`, cutoff vs. Q on biquad):
  `DspContext::new(sample_rate~, block_size~)`,
  `Adsr::new(attack_ms~, decay_ms~, sustain~, release_ms~)`,
  `DspNode::adsr(attack_ms~, decay_ms~, sustain~, release_ms~)`,
  `DspNode::biquad(input~, mode~, cutoff_hz~, q~)`,
  `Oscillator::process(..., freq_hz~)`. The corresponding trait methods
  (`DspSym::adsr`, `FilterSym::biquad`) remain positional for now.
- The `moondsp-browser-tools` npm workspace is `private: true` and exists
  only to host Playwright tests for the browser demo.

[0.1.0]: https://github.com/dowdiness/moondsp/releases/tag/v0.1.0
