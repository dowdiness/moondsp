# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Breaking changes

- Removed legacy browser facade route shell types `SoundPool`,
  `SchedulerRouteSelector`, and `SchedulerRoute`. They existed only to keep an
  older leaked browser interface shape alive; runtime routing remains behind the
  browser worklet exports.
- Removed the graph package's accidental DSP facade re-exports. Import DSP
  types, traits, and helpers from `dowdiness/moondsp/dsp` or the root
  `dowdiness/moondsp` facade instead of `dowdiness/moondsp/graph`.

### Added

- Added generated verification for the CLAP prototype's MoonBit native bridge
  header, mapping stable `mb_engine_*` C aliases to the current generated
  `clap_host` symbols.
- Formalized the browser parse/control result-code and error-message transport
  contract, with stable documentation names for scheduler parse results and
  browser graph error codes.
- Added a browser facade/worklet ABI contract guide covering supported exports,
  internal boundaries, semver policy, and the ABI baseline review workflow.
- Added an automated browser facade/export ABI baseline check for
  `browser/pkg.generated.mbti` and the JS/wasm-gc export lists in
  `browser/moon.pkg`.
- Added an external DSL lowering contract guide and regression fixtures for
  `Array[DspNode]` → `CompiledTemplate` → compile/control binding flows.
- Added `DspNode` / `CompiledTemplate` authoring equality and result-typed
  `CompiledDsp::compile_result` / `CompiledStereoDsp::compile_result` graph
  diagnostics for external reactive authoring flows.
- Added internal mini authoring token edit-span realignment coverage so
  unchanged prefix/suffix tokens preserve identity while changed duplicate
  tokens receive fresh keys.
- Added `MiniAuthoringPipeline::set_input_with_source_edit(...)` so editor
  integrations can provide the concrete source edit span for ambiguous
  identical-token edits.
- Mini authoring now feeds aligned token identities into `PatternDoc` atom IDs
  inside the pipeline, preserving duplicate sound/note provenance across
  source-span edits while retaining the existing `mini:sound:bd:N` ID shape.
- Added source-span regression coverage for duplicate note provenance and parse
  error recovery in the mini authoring pipeline.
- Updated the nested loom mini-CST spike to use Loom's stable projection identity
  helpers for atom provenance, with `set_source` source-diff fallback coverage.
- Added ADR-0012 to scope a loom/CST mini authoring evaluation before any
  runtime parser migration.
- Added a nested `specs/loom-mini-cst/` spike module with a tiny loom grammar
  for duplicate mini atom span evaluation.
- Extended the loom/CST spike with `apply_edit` insertion/deletion
  characterization tests, including current deletion no-reuse behavior.
- Added typed voice mutation APIs for handle-based controls:
  `VoicePool::note_off_result`, `VoicePool::set_voice_pan_result`,
  `BoundVoicePool::note_off_result`, `BoundVoicePool::kill_result`, and
  `BoundVoicePool::set_voice_pan_result`. Existing Bool-returning wrappers
  remain and delegate to the result path.

### Deprecated

- Deprecated the Bool-returning voice-control compatibility wrappers
  `VoicePool::note_off`, `VoicePool::set_voice_pan`,
  `BoundVoicePool::note_off`, `BoundVoicePool::kill`, and
  `BoundVoicePool::set_voice_pan`. Use the corresponding `*_result` methods to
  observe `VoiceControlError` instead of collapsing rejections to `false`.

### Changed

- Tightened `browser/internal/playback_host` helper exposure so browser
  whitebox probes are package-local and the facade compatibility hook no longer
  exposes host-owned pools, schedulers, or buffers.

## [0.5.1] - 2026-05-20

### Added

- Mini notation now accepts `.cutoff(f)` method chains such as
  `s("bd").cutoff(200)`, lowering through the existing `ControlMap` and
  `merge_control` path in both runtime parsing and PatternDoc parsing.
- Mini notation now accepts `.gain(g)` and `.pan(p)` method chains with the
  same runtime and PatternDoc lowering path as `.cutoff(f)`.

## [0.5.0] - 2026-05-20

### Breaking changes

- **`AudioBuffer::as_fixed_array` has been removed.** The method exposed
  the buffer's internal storage directly, letting callers bypass the
  `AudioBuffer` write methods and any validation attached to them.

  **Migration:** use `AudioBuffer::all` / `AudioBuffer::any` for
  predicate-style scans, or use `length` + `get` for indexed reads.
  Use `AudioBuffer::adopt` only when an explicit zero-copy shared-storage
  contract is required.

- **`AudioBuffer::new` (and `AudioBuffer::AudioBuffer`) now defensively
  copies its argument.** Previously, the constructor stored the caller's
  `FixedArray` by reference, so the buffer and the source array shared
  storage in both directions: writes to the source appeared in the
  buffer, and writes through `AudioBuffer::set` / `AudioBuffer::fill`
  mutated the source. Both directions are now decoupled.

  **Migration:** callers that depended on the shared-storage behavior
  should replace `AudioBuffer::new(arr)` with `AudioBuffer::adopt(arr)`.
  See the constructor docstrings in `dsp/buffer.mbt` for the full
  contract on both forms.

- **`AudioBuffer` now normalizes non-finite samples on MoonBit-owned
  writes.** Values written through `AudioBuffer::new`, `AudioBuffer::filled`,
  `AudioBuffer::fill`, and `AudioBuffer::set` convert `NaN`, `+Inf`, and
  `-Inf` to `0.0`; finite values, including values outside `[-1, 1]`, pass
  through unchanged. `AudioBuffer::adopt` remains the explicit zero-copy
  bypass for retained source-handle mutation, though writes through
  `buf.set(...)` and `buf.fill(...)` on an adopted buffer still normalize.

### Added

- `AudioBuffer::all((Double) -> Bool raise?) -> Bool raise?` and
  `AudioBuffer::any((Double) -> Bool raise?) -> Bool raise?` — predicate
  scans over buffer samples with `raise?` parity to the underlying
  collection helpers.

- `AudioBuffer::adopt(FixedArray[Double]) -> AudioBuffer` — explicit
  zero-copy adoption for FFI / SharedArrayBuffer–style buffer bridging.
  The buffer and the source array share storage; mutations through the
  retained source handle bypass any future write-time validation by
  design.

## [0.4.0] - 2026-05-18

This release bundles two breaking refactors of the graph public API plus
a `dsp` package visibility tightening:

1. **Graph runtime exchange boundary is now `CompiledTemplate`.**
   `Array[DspNode]` remains the *authoring* exchange type; `CompiledTemplate`
   is the *runtime* exchange type, produced by the single canonical crossing
   `CompiledTemplate::analyze`. See
   [ADR-0010](docs/decisions/0010-compiled-template-runtime-boundary.md) for
   the contract and `scripts/check-public-boundary.sh` for enforcement.
2. **Runtime graph control API is now `Result`-typed.** Across all six
   `Compiled*` wrapper types in the graph package and the
   `GraphControllable` trait, every control method (`gate_on`, `gate_off`,
   `set_param`, `apply_control`, `apply_controls`, `queue_swap`,
   `queue_topology_edit`, `queue_topology_edits`) returns
   `Result[Unit, ErrorType]` with a specific rejection reason. The
   `_result` suffix is gone from these graph control methods:
   `apply_control_result` is now `apply_control`, etc. This closes the
   silent-failure footgun class addressed previously by `BoundVoicePool`
   (see
   `docs/superpowers/specs/archive/2026-05-11-bound-voice-pool-design.md`),
   where `ignore(...)` on a Bool control return swallowed the rejection
   reason and let stale-template errors propagate unnoticed. (Note:
   `BoundVoicePool::apply_voice_control_result` / `_controls_result` /
   `validate_voice_controls_result` in the `voice/` package keep their
   suffix; that surface is unchanged by this release and will be
   harmonized in a follow-up.)
3. **`dsp` package visibility tightening.** `EnvStage` enum tightened from
   `pub(all)` to `pub`; `ChannelSpec` trait tightened from `pub(open)` to
   `pub`. External `is EnvStage::X` pattern matching continues to work;
   external variant construction and external `ChannelSpec` impls are
   no longer permitted. See "Breaking changes — `dsp` visibility
   tightening" below. (Also in this release, but non-breaking: a
   per-block-constant hoisting pass on `Adsr::process` and
   `Oscillator::process_waveform` — see "Performance" below.)

### Migration — `CompiledTemplate` boundary

```moonbit
// Before (v0.3.x)
CompiledDsp::compile(nodes, ctx)
CompiledStereoDsp::compile(nodes, ctx)
VoicePool::new(nodes, ctx, max_voices=4)              // -> VoicePool?
VoicePool::set_template(pool, nodes)                  // -> Bool
BoundVoicePool::new(nodes, ctx, builder, max_voices=4)
BoundVoicePool::set_template(pool, nodes, builder)

// After (v0.4.0)
let template = CompiledTemplate::analyze(nodes)
CompiledDsp::compile(template, ctx)
CompiledStereoDsp::compile(template, ctx)
VoicePool::new(template, ctx, max_voices=4)           // -> Result[VoicePool, VoicePoolError]
VoicePool::set_template(pool, template)               // -> Result[Unit, VoicePoolError]
BoundVoicePool::new(template, ctx, builder, max_voices=4)
BoundVoicePool::set_template(pool, template, builder)
```

### Migration — Result-typed control API

```moonbit
// Before (v0.3.x)
let ok = compiled.gate_on(0)                          // -> Bool
let ok = compiled.set_param(1, GraphParamSlot::Value0, 0.5)  // -> Bool
let ok = compiled.apply_control(GraphControl::gate_on(0))    // -> Bool (via trait)
let ok = hot_swap.queue_swap(replacement)             // -> Bool
let ok = topology.queue_topology_edit(edit)           // -> Bool
// Result-typed peers were spelled with a `_result` suffix:
let r = compiled.gate_on_result(0)                    // -> Result[Unit, GraphControlError]

// After (v0.4.0)
let r = compiled.gate_on(0)                           // -> Result[Unit, GraphControlError]
let r = compiled.set_param(1, GraphParamSlot::Value0, 0.5)   // -> Result[Unit, GraphControlError]
let r = compiled.apply_control(GraphControl::gate_on(0))     // -> Result[Unit, GraphControlError]
let r = hot_swap.queue_swap(replacement)              // -> Result[Unit, HotSwapQueueError]
let r = topology.queue_topology_edit(edit)            // -> Result[Unit, GraphTopologyQueueError]
// The `_result`-suffixed methods are gone. Drop the suffix to get the same behavior.
```

Common assertion-rewrite patterns:

| Before                                              | After                                                        |
| --------------------------------------------------- | ------------------------------------------------------------ |
| `assert_true(x.gate_on(i))`                         | `assert_true(x.gate_on(i) is Ok(_))`                         |
| `assert_false(x.queue_swap(g))`                     | `assert_true(x.queue_swap(g) is Err(_))`                     |
| `if !x.apply_controls(params) { ... }`              | `if x.apply_controls(params) is Err(_) { ... }`              |
| `match x.gate_on_result(i) { ... }`                 | `match x.gate_on(i) { ... }` — drop the `_result` suffix     |
| `ignore(x.gate_on(i))` in production code           | `ignore(x.gate_on(i))` still type-checks, but consider whether swallowing the error is correct; in tests, prefer `is Ok(_)`; in benchmarks where success is required, `.unwrap()` |

### Breaking changes — `CompiledTemplate` boundary

- **`CompiledDsp::compile(Array[DspNode], DspContext)` removed.**
  `compile_template` renamed to `compile(CompiledTemplate, DspContext)`.
  Same for `CompiledStereoDsp`.
- **`VoicePool::new` and `set_template` now take `CompiledTemplate` and
  return `Result[..., VoicePoolError]`.** Variants: `InvalidMaxVoices`,
  `OrphanAdsr`, `CompileRejected`. Mirrors `BoundVoicePoolError` minus
  `Binding(...)`.
- **`BoundVoicePool::new` and `set_template` now take `CompiledTemplate`.**
  Return shape (`Result[..., BoundVoicePoolError]`) unchanged.
- **`optimize_graph` is now package-private.** Use
  `CompiledTemplate::analyze` instead — it runs constant folding and
  dead-node elimination exactly once and produces the runtime boundary
  type in one step. Removed from the root facade re-export list.

### Breaking changes — Result-typed control API

- **Bool-returning control methods deleted on `CompiledDsp` and
  `CompiledStereoDsp`** (`gate_on`, `gate_off`, `set_param`,
  `apply_control`, `apply_controls`). The previously-named `_result` peers
  absorb those names and return `Result[Unit, GraphControlError]`.
- **Bool-returning `queue_swap` deleted on `CompiledDspHotSwap` and
  `CompiledStereoDspHotSwap`.** `queue_swap_result` is renamed
  `queue_swap` and returns `Result[Unit, HotSwapQueueError]`. The other
  control methods (`gate_on`, `gate_off`, `set_param`, `apply_control`,
  `apply_controls`) on these types had no Bool peer — they are renamed
  (suffix dropped) but no API was deleted.
- **Bool-returning `queue_topology_edit` / `queue_topology_edits` deleted
  on `CompiledDspTopologyController` and
  `CompiledStereoDspTopologyController`.** `_result` peers absorb those
  names and return `Result[Unit, GraphTopologyQueueError]`. Other control
  methods are renamed (no Bool peers existed).
- **`GraphControllable` trait now returns `Result[Unit, GraphControlError]`**
  from both `apply_control` and `apply_controls`. The trait was also
  tightened from `pub(open)` to `pub` in this release, sealing it against
  external impls; only the in-package `Compiled*` types implement it, and
  they have been updated.
- **All `*_result`-suffixed public methods on graph `Compiled*` types
  removed** (their behaviour is now the only behaviour, exposed without
  the suffix): `apply_control_result`, `apply_controls_result`,
  `validate_controls_result`, `gate_on_result`, `gate_off_result`,
  `set_param_result`, `queue_swap_result`, `queue_topology_edit_result`,
  `queue_topology_edits_result`. The `voice/` package's
  `BoundVoicePool::apply_voice_control_result` family is *not* part of
  this change and keeps its current names.
- Pure Bool queries on `Compiled*` types — `is_voice_finished` and
  `has_feedback_edges` — are intentionally kept; they are queries, not
  control operations. Other Bool-returning public APIs across the package
  (`node_accepts_slot`, `GraphTemplateDoc::contains_node` / `contains_retired_node`,
  trait methods on `NodeEditable` / `NodeFoldable` / `NodeStateful`,
  the module-level `is_finite`) are unaffected.

### Breaking changes — `dsp` visibility tightening

- **`EnvStage` enum tightened from `pub(all)` to `pub`.** External
  `is EnvStage::X` pattern matching continues to work per MoonBit
  access-control rules (`pub` types remain readable / destructurable from
  outside the package). External *construction* of `EnvStage` variants is
  no longer permitted; downstream code that needs an `EnvStage` value
  should read it from `Adsr::stage(self)`. No call site in the workspace
  constructed `EnvStage` variants externally.
- **`ChannelSpec` trait tightened from `pub(open)` to `pub`.** Only `Mono`
  and `Stereo` implement `ChannelSpec`, both inside `dsp/`. Downstream
  packages can no longer add their own `ChannelSpec` impls. The
  tagless-algebra traits (`ArithSym`, `DspSym`, `FilterSym`, `StereoSym`,
  `DelaySym`, `StereoFilterSym`, `StereoDelaySym`) stay `pub(open)` —
  alternate interpreters like `GraphBuilder` need them.

### Added

- `CompiledTemplate::adsr_authoring_indices(Self) -> FixedArray[Int]` —
  authoring indices of surviving ADSR nodes, used by `voice/` for
  note_on / note_off gating.
- `GraphBuilder::analyze(Self) -> CompiledTemplate` — sugar over
  `CompiledTemplate::analyze(builder.nodes())`.
- `BoundVoicePoolError::from_voice_pool(VoicePoolError) -> Self` —
  remaps a `VoicePoolError` into a `BoundVoicePoolError` for callers
  composing the two error types.
- `VoicePoolError` re-exported through the root `@moondsp` facade so
  consumers can pattern-match `VoicePool::new` Results ergonomically.

### Performance — `dsp` per-block hoisting

- **`Adsr::process` no longer re-validates `sample_rate` per sample.**
  Validation runs once at block entry; a new private `Adsr::tick_step`
  stepper assumes a finite positive `sample_rate` and is called directly
  inside the per-sample loop. The public `Adsr::tick(context)` retains
  its full validation contract for direct callers.
- **`Oscillator::process_waveform` hoists `freq_hz / sample_rate` out of
  the per-sample loop.** A new private
  `Oscillator::tick_step(waveform, phase_increment)` is called inside the
  loop, eliminating both per-sample validation and per-sample division.
  Added a guard on the quotient: the buffer is silenced if
  `phase_increment` is non-finite (e.g. `Double::MAX / Double::MIN_POSITIVE`
  → `Inf`), matching dsp's existing fill-0-on-invalid pattern. The
  block-processing path (`process_waveform`) is now safe against
  pathological quotients that would previously NaN-poison the oscillator
  phase. Direct callers of `tick_waveform` still need to validate the
  quotient themselves; that path is unchanged in this release.
- Replaced the magic literal `6.283185307179586` with `2.0 * @math.PI` in
  `sample_for_phase`, matching the convention in `filter.mbt` and
  `pan.mbt`.

### Carve-outs (NOT migrated — see ADR-0010 § Boundary exceptions)

The following public APIs keep `Array[DspNode]` in their signatures by
design. Each is enforced by an allowlist entry in
`scripts/check-public-boundary.sh`.

- `CompiledTemplate::analyze(Array[DspNode])` — the canonical authoring
  → runtime crossing; the entire migration is built around this entry
  point.
- `replay(Array[DspNode])` — pre-optimize debug / round-trip.
- `CompiledDspTopologyController::from_nodes(Array, ctx, crossfade?)` and
  `CompiledStereoDspTopologyController::from_nodes(...)` — edit-as-you-go
  composites.
- `GraphBuilder::nodes`, `GraphTemplateDoc::nodes` — authoring /
  inspection accessors.
- `GraphTemplateDoc::from_nodes`, `::insert_chain` — authoring artifact
  construction.
- `GraphIndexMap::insert_chain`, `GraphTopologyEdit::InsertChain` (and
  constructor) — authoring payloads.

### Internal

- `voice/` internal storage migrated from `Array[DspNode]` snapshots to
  `FixedArray[Int]` ADSR-authoring-index snapshots. The PR-2 pinning
  tests (`voice/voice_pinning_test.mbt`) pin the public outcome of
  `VoicePool::new` and `set_template` across the migration.
- Added `scripts/check-public-boundary.sh` and
  `.github/workflows/boundary-check.yml` enforcing ADR-0010 carve-outs
  in CI.

## [0.3.1] - 2026-05-17

### Added

- **`PatternScheduler::bpm()` read accessor.** Restores public read access
  to the current tempo after v0.3.0 privatized the `bpm` field. The
  accessor returns the sanitized value (NaN/Inf rejected, clamped to
  ≥1.0 at construction and `set_bpm`). Symmetric with the existing
  `sample_counter()` reader; non-breaking.

## [0.3.0] - 2026-05-16

### Breaking changes

- **`DspNode::delay`, `DspNode::stereo_delay`, `DspNode::envelope_gain` now
  require labelled arguments.** Each of these constructors takes two `Int`
  positions for distinct roles (input source vs delay-buffer capacity;
  input signal vs envelope modulator) where order is silently flippable.
  New signatures (label names match the existing parameter names — no
  rename, no defaults changed):
  - `DspNode::delay(input~, max_delay_samples~, delay_samples?, feedback?)`
  - `DspNode::stereo_delay(input~, max_delay_samples~, delay_samples?, feedback?)`
  - `DspNode::envelope_gain(input~, envelope~, amount~)`
- **`PatternScheduler` struct fields are now private.** The fields `bpm`,
  `sample_counter`, `ctx`, `active_notes`, and `mapper` were exposed as
  public on the struct, allowing external readers (and external writers
  for the `mut` ones) to bypass the scheduler's invariants. They are now
  `priv`. Purpose-built observation remains through methods
  (`sample_counter`, `current_block`, `active_note_count`,
  `active_note_source`, `active_note_matches`); BPM changes go through
  `set_bpm`. Direct reads of `bpm`, `ctx`, `mapper`, and the backing
  `active_notes` array are no longer public API. (A `PatternScheduler::bpm()`
  read accessor lands in v0.3.1.)
- **`NodeSpanning`, `NodeFoldable`, `NodeStateful`, `NodeEditable` traits
  removed from the public `@moondsp` facade.** These are graph-internal
  implementation-detail traits (used to classify `DspNode` variants
  during compile/optimize/edit). They had no documented external
  consumers and the trait surface itself remains usable inside
  `@dowdiness/moondsp/graph` for internal extension.

### Changed

- **Constructors migrated to canonical `Type::Type` form** across the
  codebase (v0.9.2 toolchain alignment; 30 `#alias(new)` shims total,
  of which 21 are public constructor aliases in the generated
  interfaces). Old `Type::new(…)` call sites continue to work via the
  shims — no migration required for consumers, but new code should
  prefer the canonical form (`Adsr::Adsr(...)`,
  `DspContext::DspContext(...)`, `Rational::Rational(...)`, etc.).

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

[Unreleased]: https://github.com/dowdiness/moondsp/compare/v0.5.1...HEAD
[0.5.1]: https://github.com/dowdiness/moondsp/releases/tag/v0.5.1
[0.5.0]: https://github.com/dowdiness/moondsp/releases/tag/v0.5.0
[0.4.0]: https://github.com/dowdiness/moondsp/releases/tag/v0.4.0
[0.3.1]: https://github.com/dowdiness/moondsp/releases/tag/v0.3.1
[0.3.0]: https://github.com/dowdiness/moondsp/releases/tag/v0.3.0
[0.2.0]: https://github.com/dowdiness/moondsp/releases/tag/v0.2.0
[0.1.0]: https://github.com/dowdiness/moondsp/releases/tag/v0.1.0
