# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-05-16

### Breaking changes

- **`PatternScheduler::new` signature** — the `bindings~ : ControlBindingMap`
  parameter was removed. `BoundVoicePool` now owns the binding map and is
  passed to scheduler block-processing methods in place of the raw
  `VoicePool`. Migrate by constructing a `BoundVoicePool` from your pool
  plus bindings and replacing `pool` arguments to `process_block`,
  `process_events`, and `expire_notes` with the bound pool.
- **Positional-to-labelled DSP/browser helper arguments** — to surface
  ordering mistakes at compile time, the following calls now require
  labelled arguments instead of positional ones: `Oscillator::process`,
  `Oscillator::process_waveform`, `Oscillator::tick`,
  `Oscillator::tick_waveform`, `Gain::process`, `Clip::process`,
  `Pan::process`, `DspNode::stereo_gain`, `DspNode::stereo_clip`,
  `DspNode::stereo_biquad`, `DemoSource::tick_source`, browser `tick`,
  browser `tick_source`, and the matching `browser_test` shims.
- **Public struct field/raw-constructor abstraction** — several DSP/graph
  structs no longer expose raw fields or internal constructors as part of
  the public surface. Affected types include state fields on `Adsr`,
  `AudioBuffer`, `Biquad`, `DelayLine`, `DspContext`, `Noise`,
  `Oscillator`, `ParamSmoother`; dummy unit fields on `Gain`, `Clip`,
  `Mix`, `Pan`; raw `DspNode` and `GraphControl` fields and internal
  constructors; `GraphBuilder` and `ControlBindingBuilder` internals; and
  `PatternScheduler.bindings`. Use the public constructors (`DspNode::adsr`,
  `Gain::new`, etc.) and accessor methods (`DspNode::kind`, `input0`,
  `value0`, …) instead of field access.

### Removed

- **`pattern.ControlMap::inner`** — was marked `#deprecated` in `v0.1.0`;
  use `ControlMap::entries`, `each`, `get`, `set`, `merge`, `single`, or
  `empty` instead.

### Added

- **Mini-notation grammar extensions:**
  - **Top-level `stack(p1, p2, ...)` primitive** (#20) — combine independent
    patterns at the expression level, including cross-source mixes like
    `stack(s("bd sd"), note("60 64"))`. Each argument is a full expression,
    so per-arg method chains and result method chains both work. Closes
    the gap that previously forced layer-stacking inside a single notation
    string (which can't mix `s` and `note`).
  - **Euclidean rhythms** (#15) — `s("bd(3,8)")` and `s("bd(3,8,2)")` for
    pulses, steps, and rotation.
  - **Step operators `*n` / `/n`** (#18) — in-slot replication and stretch
    (`s("bd*4")`, `s("bd/2")`).
  - **`degradeBy(p)` method, `every(n, f)` method, `?` step operator** (#17)
    — probabilistic event drop, periodic transformations, and per-step
    50% drop with deterministic seeding.
  - **`.jux(f)` method** (#19) — Strudel-style stereo split with `f`
    applied to the right channel only.
- **Drum sounds:** `cp` (clap, MIDI 39) and `oh` (open hi-hat, MIDI 46),
  with synthesis templates and per-sound routing (#21).
- **Live-coding REPL** (#12) — `web/live/` Strudel-style editor surface
  with CodeMirror 6, debounced eval, inline parse-error squiggles via
  the canopy adapter, and a "kept last good" recovery model. Includes
  runtime-error teardown coverage (#14), design-system overhaul
  (typography, tokens, motion, a11y), and a mini-notation cheatsheet
  sidebar.
- **Live REPL autocomplete + syntax highlighting** (#23) — context-aware
  completions across four cursor positions: top-level functions
  (`s`, `note`, `stack`), method chain (`.fast` / `.slow` / `.rev` /
  `.degradeBy` / `.every` / `.jux`), drum names inside `s("…")`, and
  callbacks inside `jux(…)` / `every(_, …)`. Backed by a small Lezer
  grammar for the outer surface; the inner mini-notation stays opaque
  to keep the wasm-side parser the single source of truth. Includes
  default syntax highlighting and bracket auto-pairing.
- **Phase 6 identity groundwork** — new dependency-free `identity/` package
  with typed stable IDs, `Revision`, and revision comparison plus ordered
  aggregation helpers; `song/` now supports explicit occurrence IDs, stable-ID
  lookup, and ID-preserving tests across reordering and section length changes.
- **Phase 6 pattern authoring groundwork** — `pattern/` now has an
  identity-bearing authoring document with private node storage, revisioned
  edits, stable node lookup helpers, and lowering back to the existing runtime
  pattern query model. Aggregate pattern documents derive their revision from
  an ordered child-revision mix so changed child content invalidates parent
  snapshots. The authoring layer covers the runtime pattern operations,
  including filtering, Euclidean rhythms, degradation, periodic transforms,
  stereo split, and control-map merging.
- **Phase 6 pattern lowering cache** — lowering reuse keyed by stable node
  identity, a private subtree token, and full revision equality, with
  per-node revision metadata inside authoring storage. Editing one child
  invalidates that child and its ancestors while sibling lowerings are
  reused; divergent edits forked from the same base document do not alias
  cache entries.
- **Phase 6 mini-notation stable-ID reconciliation** (#36) — deterministic
  `PatternNodeId` assignment for parsed mini atoms, combinators, sequences,
  stacks, and method chains. New `parse_doc`, `parse_doc_reusing`,
  `parse_snapshot`, and `parse_snapshot_reusing` entry points expose mini
  output through `PatternDoc` / `PatternSnapshot` while preserving the
  existing `parse` API. `PatternDoc::subdoc` lets reconciliation reuse
  unchanged parsed subtrees so whitespace-only and unaffected-token
  reparses hit the lowering cache.
- **Phase 6 graph identity mapping** (#37) — new `GraphTemplateDoc` owns
  stable `GraphNodeId` authoring IDs, graph nodes, revisions, and a
  retired-ID set; `GraphIndexMap` maps stable IDs to existing graph
  indices and builds existing `GraphControl`, `ControlBindingBuilder`, and
  `GraphTopologyEdit` values at API boundaries. Document edits preserve
  IDs across replacements/rewires, append for inserts, compact for
  deletes, and reject reuse of retired IDs in the same document. The root
  `@moondsp` facade re-exports `GraphNodeId`, `Revision`, and
  `StableIdError` for documented facade consumers.
- **`song/` package — long-form arrangement layer** — new `song/` package
  introduces `Section`, `SectionBody` / `SectionLayer`, `SectionPatch`,
  and `Song` / `SongPart` as the long-form arrangement layer between the
  pattern engine and the scheduler, before the explicit-start ranges and
  identity-bearing authoring docs land in the entries below.
- **Sample-time scheduler note expiry** — scheduler note expiry switched
  from a tick counter to sample time via `PerformanceTime`,
  `cycle_to_sample`, and `expire_notes_at`, so already-active notes keep
  stable gate-off sample times across tempo changes.
- **Phase 6 song authoring** — explicit-start layout ranges with
  gaps/overlaps and `Song::occurrences_at` / `occurrences_intersecting`
  point and range lookup (#38); `Song::gap_spans` plus `Song::fill_gaps`
  for derived boundary fills that preserve existing IDs (#39); song
  mini-notation (`parse_song`, `section`, `part`, `part_id`, `fill`) over
  the existing pattern mini surface (#40); `TimeScope` rate transforms
  (`at_rate`, `fast`, `slow`) routed through both `Song::query` and
  direct section playback (#41); secondary indexes for occurrence name,
  stable ID, start time, and end time, preserving authoring-order overlap
  semantics (#42); identity-preserving section/layer authoring with
  display rename stability and revision boundaries (#43); and an
  identity-preserving song layout authoring model that survives rename,
  insertion, removal, reorder, explicit-start, and section-length edits
  (#44).
- **Phase 6 scheduler snapshot swap and edit orchestration** —
  block-boundary snapshot swap (`PatternScheduler::queue_pattern_snapshot`
  + `process_snapshot_block`) with let-ring across silent replacements
  and coalescing of multiple staged snapshots (#35); shared pattern/song
  snapshot staging with whole-document and layout-scoped revision tokens
  plus authored source provenance on active notes (#45); affected-voice
  selectors targeting pattern node, section, layer, occurrence, or
  combined identities, with explicit preserve / release / immediate-stop
  policies and authored provenance on sourced snapshot queries (#46);
  `AffectedVoiceEditScope` and
  `PatternScheduler::apply_affected_voice_policy_for_edit` mapping
  pattern-node / occurrence / section / section-bounded layer edits to
  affected-voice targets (#47); unified
  `PatternScheduler::queue_playback_snapshot_edit` plus
  pattern/song-specific wrappers that stage replacement and apply the
  selected policy together (#48); active-voice live-control batches with
  preflighted all-or-nothing rejection on invalid controls and
  stale-handle rejection (#49); and live-control changes integrated into edit
  application so successful edits report both live-controlled voice count
  and scheduler-owned active-note removals (#50).
- **Scheduler edit orchestration documentation** (#51) — `scheduler/`
  ships a checked-markdown README example walking the public edit
  orchestration workflow from a sourced active pattern snapshot through
  replacement staging, affected-voice policy, optional live-control
  changes, and outcome counts. The example is run as part of package
  checks so future API drift fails the build.

### Changed

- Drum names cheatsheet trimmed to only the implemented sounds
  (`bd, sd, hh, cp, oh`); `cb`/`rim`/`tom` removed pending real
  synthesis design.
- DSP/browser demo helper APIs now label the remaining ambiguity-prone
  `Oscillator::process`, `DemoSource::tick_source`, `tick`, and
  `tick_source` parameters.
- Topology queue diagnostics now report
  `InvalidEdit(index, reason)` with stable `GraphTopologyEditError` reasons
  instead of only the failing batch index.
- `BoundVoicePool` now owns template validation and `ControlBindingMap`
  lifetime, so `PatternScheduler` no longer carries stale bindings.
- Graph control, hot-swap queue, topology queue, and runtime-control
  wrappers now provide `Result`-typed companion APIs
  (`GraphControlError`, `HotSwapQueueError`, `GraphTopologyQueueError`)
  on the mono and stereo paths so callers can observe errors instead of
  silently dropping invalid operations. The existing `Bool`-returning
  helpers remain for compatibility. Browser graph queue/control paths
  expose last-error string/code helpers while preserving the boolean
  wasm ABI.

### Fixed

- Feedback-recurrence Playwright flake — replaced fixed-sequence guard
  with polling for actual convergence band, removing CI runner timing
  dependence.

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

[0.2.0]: https://github.com/dowdiness/moondsp/releases/tag/v0.2.0
[0.1.0]: https://github.com/dowdiness/moondsp/releases/tag/v0.1.0
