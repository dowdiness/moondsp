# moondsp — Library API Design Review

**Date:** 2026-04-21
**Version under review:** 0.1.0
**Scope:** The `dowdiness/moondsp` root facade and the four sub-packages it
re-exports (`dsp`, `graph`, `voice`, `lib`). Pattern / mini / scheduler /
browser layers are referenced where relevant but not the primary target of
this review.

This is a point-in-time design review. It does **not** describe current
behavior authoritatively — the code and `salat-engine-technical-reference.md`
do. Once any item here ships or is rejected, this document should be moved
to `archive/` rather than edited in place.

## Status of prioritised actions

- **(1) Fix facade drift — ✅ shipped 2026-04-21.** The
  `dowdiness/moondsp/lib` sub-package was removed; the root
  `dowdiness/moondsp` module now re-exports directly from `@dsp`, `@graph`,
  and `@voice`. `CompiledTemplate` is now exposed at the root. Internal
  sub-packages migrated from `@lib` to `@moondsp`. The "Scope" paragraph
  above still mentions `lib` as that was the state at the time of the
  review; the current code no longer has a `lib/` package.
- **(2) Abstract state-bearing DSP structs — open.**
- **(3) Label the footgun constructors — open.**

## Step 1 — Facts / Assumptions / Unknowns

### Facts

- Module name: `dowdiness/moondsp`, version `0.1.0`, Apache-2.0, single dep
  `moonbitlang/quickcheck` (dev).
- Root package re-exports 44 symbols (types / traits / functions) from three
  packages via `pub using`.
- There are **two facade layers**: `./moondsp.mbt` (root) and `lib/` — both
  re-export the same surface minus one mismatch (`CompiledTemplate` is in
  `@lib` but not in `@moondsp`).
- Target backend: `wasm-gc` for browser AudioWorklet; CLI via default target.
  No LLVM / C target configured.
- Audio constants fixed at 48 kHz / 128 samples per buffer.
- `pub(open)` traits: all seven DSP symantic traits (`ArithSym`, `DspSym`,
  `FilterSym`, `DelaySym`, `StereoSym`, `StereoFilterSym`, `StereoDelaySym`),
  four Node traits (`NodeEditable`, `NodeFoldable`, `NodeSpanning`,
  `NodeStateful`), two graph-facing traits (`GraphControllable`,
  `GraphDebuggable`), and `ChannelSpec`.
- `pub(all)` enums: `BiquadMode`, `EnvStage`, `Waveform`, `DspNodeKind` (18
  variants), `GraphParamSlot`, `GraphTopologyInputSlot`, `GraphControlKind`,
  `GraphTopologyEdit` (6 variants), `GraphValidationError`,
  `ControlBindingError`, `VoiceState`.
- `pub struct` with all fields public: `Adsr` (including `mut stage`,
  `mut level`), `AudioBuffer` (`data : FixedArray[Double]`), `DelayLine`
  (`mut write_pos`, `mut delay_samples`, `mut feedback`), `DspContext`,
  `Noise`, `Oscillator` (`mut phase`), `ParamSmoother` (all three fields
  `mut`), `DspNode` (12 fields), `ControlBinding`, `ControlBindingBuilder`,
  `VoiceHandle`, plus marker structs (`Mono`, `Stereo`, `Gain`, `Mix`, `Pan`,
  `Clip`, `DemoSource`, `Biquad` with "private fields" comment).
- Abstract types (`type` with no visibility on fields): `CompiledDsp`,
  `CompiledDspHotSwap`, `CompiledDspTopologyController`, stereo variants,
  `VoicePool` (struct with hidden fields), `ControlBindingMap`, `ActiveNote`.
- Silent-failure convention: many mutations return `Bool` (`gate_on/off`,
  `set_param`, `queue_swap`, `queue_topology_edit`, `set_template`,
  `set_voice_pan`, `note_off`). Compilation entry points return `T?`
  (`CompiledDsp::compile`, `VoicePool::new`, `replay`).
- `ControlBindingBuilder::build` returns
  `Result[_, ControlBindingError]` — the only `Result`-typed API in the
  public surface.
- `Adsr::new(Double, Double, Double, Double)` — four positional unlabelled
  doubles. ADSR ms-vs-s confusion is a documented recurring footgun.
- No `derive(Show)` on most types; `ControlBinding`, `ControlBindingError`,
  `ControlBindingMap`, `GraphParamSlot`, `GraphValidationError`,
  `VoiceHandle`, `VoiceState`, `Rational`, `TimeSpan` derive `@debug.Debug`
  with manual `impl Show`.

### Assumptions

- Primary target consumer: `cmd/main`, `browser/`, and external MoonBit
  packages depending on `dowdiness/moondsp` — realtime-audio application
  authors, not casual scripters.
- Stability guarantee: pre-1.0, breaking changes allowed; `CHANGELOG.md`
  implies SemVer intent going forward.
- The seven DSP traits are `pub(open)` because downstream users are expected
  to plug alternative interpretations (optimizer, pretty-printer, CSE) on
  top of `GraphBuilder`. This is the finally-tagless design.
- `pub(all)` on `DspNodeKind` / `GraphParamSlot` / `GraphTopologyEdit` is
  intended so downstream code can pattern-match on node kinds, not so
  downstream can construct arbitrary variants directly.

### Unknowns

- Whether external (non-repo) users exist today. No evidence of dependents
  in-tree beyond `cmd/`, `browser/`, `browser_test/`.
- Whether `lib/` is intended to remain as a public import path or be
  deprecated once `@moondsp` is considered authoritative.
- Target stability horizon: is the 0.1.0 → 1.0 contract intended to freeze
  any of the current `pub(all)` shapes?
- Whether `DspNode::new(...12 positional args)` is considered public API or
  an accident of `pub` visibility.

## Step 2 — Programmer UX Definition

Measured against the current surface, "good UX" for moondsp means:

| Property | Operational definition |
|---|---|
| Minimal-example legibility | A user should be able to build a graph, compile, and process one buffer using only `GraphBuilder`, `exit_deliverable`, `CompiledDsp::compile`, `DspContext::new`, `AudioBuffer::filled`, `CompiledDsp::process`. Six names. |
| Concept budget at standard usage | Adds `ControlBindingBuilder`, `ControlBindingMap`, `VoicePool`, `GraphControl`, `GraphParamSlot`. Five more names. |
| Hidden from most users | `DspNode::new` 12-arg constructor, individual marker structs (`Gain`, `Mix`, `Pan`, `Clip`), `optimize_graph`, `sanitize_buffer`, `mono_shape`, `stereo_shape`, `node_accepts_slot`. |
| Misuse to prevent at type-level | (1) Constructing an `AudioBuffer` whose length ≠ `block_size`; (2) calling `CompiledDsp::process` on a buffer from a different `DspContext`; (3) passing an `AudioBuffer` with NaN-laden data; (4) constructing an `Adsr` where seconds were passed in where ms were expected; (5) applying a `GraphControl` with a `GraphParamSlot` the target node doesn't accept; (6) holding a stale `VoiceHandle` after generation wrap. |

Against those: (1) – (4) are **not** prevented at the type level. (5) is
detected at runtime via `set_param` returning `Bool` and via
`ControlBindingBuilder::build`'s `OrphanBinding` / `InvalidSlotForNode`
errors — caught at binding construction, not at control emission. (6) is
detected via generation tagging — a correct design.

## Step 3 — Core Design Decisions

### 3.1 Package Design

**Decision:** Keep the three-package internal split (`dsp/`, `graph/`,
`voice/`) but collapse the **two** facades (`@moondsp` and `@lib`) into one.

**Alternatives:** (a) drop `@lib` and have `@moondsp` re-export directly
from `@dsp` / `@graph` / `@voice`; (b) drop `@moondsp.mbt`'s facade and
rename `@lib` → `@moondsp`; (c) keep both.

**Reason:** MoonBit `pub using` from a facade re-exports transitively. The
current setup has two identical facades minus the `CompiledTemplate` drift
— every public addition requires editing **two** re-export lists. The drift
is already visible: `CompiledTemplate` is exposed in
`lib/pkg.generated.mbti` but absent from the root facade. This is a
stability bug: consumers writing `@moondsp.CompiledTemplate` cannot
compile, while `@moondsp.lib.CompiledTemplate` works. Pick one facade.

### 3.2 Type Visibility

| Type | Current | Proposed | Reason |
|---|---|---|---|
| `AudioBuffer` | `pub` (all fields) | `pub` **readonly** (no `mut`, no `pub(all)`) | `data : FixedArray[Double]` is accessible but not mutable without `set`. Fine. The risk: users construct `AudioBuffer::new(arr)` where `arr.length() ≠ block_size`. Add either a `DspContext`-parameterised constructor or a debug check. |
| `DspContext` | `pub` | Keep | Immutable, two fields, no hidden invariants. |
| `Adsr` | `pub` with `mut stage`, `mut level`, `mut level_at_release` | **abstract type** | `stage`/`level` are internal state driven by `tick`/`gate_on`/`gate_off`. External mutation breaks the state machine. The fact that `stage()` and `level()` accessors exist is proof these are observables, not writables. |
| `DelayLine` | `pub` with `mut write_pos`, `mut delay_samples`, `mut feedback` | **abstract type** | Setter methods (`set_delay_samples`, `set_feedback`) already exist — making fields mutable is a footgun. Setting `delay_samples > max_delay_samples` via field write silently corrupts the read loop. |
| `Oscillator`, `Noise`, `ParamSmoother` | `pub` with `mut` fields | **abstract type** | Same reasoning. The accessor / mutator methods are the contract; field access duplicates. |
| `DspNode` | `pub` with 12 fields + `new(...)` positional constructor | **abstract type**, keep per-kind constructors (`DspNode::adsr`, `DspNode::biquad`…) | The 12-arg `new` is a liability: it accepts arbitrary combinations that violate invariants (e.g. `DspNodeKind::Adsr` with `value0 = attack_s_not_ms`). The per-kind constructors are already the sanctioned API. Hide the raw `new`. |
| `ControlBinding` | `pub` (labelled `new`) | Keep as `pub`, fields readable | Fields `key` / `node_index` / `slot` are by design inspectable (logging, debug). No internal mutation. |
| `ControlBindingBuilder` | `pub` (exposes `bindings : Array[…]`) | **abstract type** (hide `bindings` field) | Internal accumulator. Exposing the array lets users bypass `.bind()` and construct orphaned / duplicate bindings that `.build()` is supposed to detect. |
| `VoiceHandle` | `pub` (struct with `slot`, `generation`) | Keep | Generation tagging is safe by design; users can't forge a valid handle because the pool checks both fields. |
| Marker structs (`Gain`, `Mix`, `Pan`, `Clip`, `Mono`, `Stereo`) | `pub` with dummy `unit : Unit` field | **abstract type** or `priv` | These hold no state. They exist only to host methods. The `unit : Unit` field is a smell. Methods could be free functions or moved onto `DspContext`. |

**Future breakage risk of current design:** any internal change to `Adsr`,
`DelayLine`, `Oscillator`, `ParamSmoother`, `DspNode` field representation
is a **breaking change** for downstream, because fields are `pub`. This is
the largest stability liability in the API.

### 3.3 Trait Design

All DSP symantic traits are `pub(open)`. Node traits are `pub(open)`.
`GraphControllable` and `GraphDebuggable` are `pub(open)`.

**What breaks if a third party implements `DspSym` / `FilterSym` / ...?**
Nothing — that is the intended extension point. The `replay` function
explicitly uses bounded generics
(`T : ArithSym + DspSym + FilterSym + DelaySym + StereoSym + ...`), and
`GraphBuilder` is one concrete implementation. The tagless design is the
whole point.

**What breaks if a third party implements `NodeEditable` / `NodeFoldable`
/ `NodeSpanning` / `NodeStateful`?** These traits take `Self` where `Self`
is only ever `DspNode` in practice — the graph runtime (`optimize_graph`,
`node_accepts_slot`) operates on `DspNode` directly. An external
`impl NodeFoldable for MyNode` would not be consumed by any library
function. **These traits leak implementation detail** — they're the
trait-ified internals of `DspNode`. They should be private to `graph/`
unless a concrete use case for external implementation exists.

**Decision:** seal `NodeEditable`, `NodeFoldable`, `NodeSpanning`,
`NodeStateful` (make them `priv` or simply unexport). Keep DSP symantic
traits `pub(open)`.

**What breaks if a third party implements `GraphControllable`?** Their
type could be passed to any function taking `GraphControllable`, but there
are none in the public surface — it's only implemented by library-owned
`Compiled*` types. Same question: what's the use case? If there isn't one,
seal it.

### 3.4 Method vs Function

Current: `is_finite`, `is_finite_positive`, `lin_map`, `range`,
`pan_left_gain`, `pan_right_gain`, `sanitize_buffer`,
`effective_sample_count`, `exit_deliverable`, `mono_shape`, `stereo_shape`,
`node_accepts_slot`, `optimize_graph`, `replay`, `max_feedback_amount` —
**15 top-level functions**.

**Issue:** `is_finite`, `mono_shape`, `stereo_shape`,
`max_feedback_amount`, `pan_left_gain` / `right_gain` read as library-level
utilities but `effective_sample_count(ctx, buf)`,
`sanitize_buffer(buf, limit)`, `node_accepts_slot(node, slot)` are natural
methods.

**Decision:**
- `effective_sample_count(ctx, buf)` → `buf.effective_samples(ctx)` or
  `ctx.effective_samples(buf)`
- `sanitize_buffer(buf, limit)` → `buf.sanitize(limit~)` with a labelled
  argument (see 3.6)
- `node_accepts_slot(node, slot)` → `node.accepts_slot(slot)`
- `pan_left_gain` / `pan_right_gain` → either
  `Pan::left_gain(p)` / `Pan::right_gain(p)` or combine into a single
  `pan_gains(p) -> (Double, Double)` to make "use matching pair" the
  default
- `is_finite`, `is_finite_positive` — keep top-level; they are numeric
  predicates on `Double` and MoonBit can't add `Double::is_finite` from
  this package (orphan rule) — unless a newtype is involved.

### 3.5 Construction & State Safety

**`CompiledDsp::compile(nodes, ctx) -> Self?`:** the `?` return swallows
*why* compilation failed. `GraphValidationError` exists but isn't
surfaced. **Decision:** change to
`Result[Self, Array[GraphValidationError]]`. This is a hot path for user
errors; `Option` is the wrong modality.

**Invalid intermediate states:**
- `DspNode::new(kind, in0, in1, v0..v3, waveform, filter_mode, delay_max,
  delay_samples, seed)` is constructable with any combination of fields —
  e.g., a `Noise` node with a stray `waveform`. The per-kind constructors
  prevent this; the raw `new` does not. Hide it.
- `AudioBuffer::filled(len, init~ : Double)` allows any length.
  Length ≠ `block_size` is latent until `process()` runs. Consider
  `DspContext::make_buffer()` that returns a correctly-sized buffer.
- `ControlBindingBuilder::bind(key=, node_index=, slot=)` — `node_index` is
  a raw `Int`. Off-by-one and stale indices are silently accepted until
  `.build(template)` runs. The `CompiledTemplate::analyze(nodes)`
  indirection (not exposed in root facade!) already does the validation;
  the orphan-detection work in PR #9 confirms this is a known pain point.

**Ordering:** hot-swap and topology edits are queue-based and
one-edit-per-block — this is explicit in `queue_swap` /
`queue_topology_edit` returning `Bool`. The `Bool` hides *why* the queue
was rejected (already pending vs invalid edit). **Decision:** return a
small error enum (`QueuedOK`, `AlreadyQueued`, `InvalidEdit(reason)`).

### 3.6 Argument Design

Current labelled args: `from_graph(..., crossfade_samples? : Int)`,
`from_nodes(..., crossfade_samples? : Int)`,
`VoicePool::new(..., max_voices? : Int)`,
`DspNode::delay(..., delay_samples? : Int, feedback? : Double)`,
`AudioBuffer::filled(Int, init? : Double)`,
`ControlBinding::new(key~, node_index~, slot~)`.

**Unlabelled-positional offenders:**
- `Adsr::new(Double, Double, Double, Double)` — attack, decay, sustain,
  release. Unit ambiguity (ms vs s), order ambiguity. **Decision:**
  `Adsr::new(attack_ms~, decay_ms~, sustain~, release_ms~)`. A labelled
  API prevents recurrence of the ms-vs-s footgun.
- `DspContext::new(Double, Int)` — sample rate and block size. Swapping
  yields runtime chaos. **Decision:**
  `DspContext::new(sample_rate~, block_size~)`.
- `DspNode::adsr(Double, Double, Double, Double)`,
  `DspNode::biquad(Int, BiquadMode, Double, Double)` — same problem.
- `GraphControl::set_param(Int, GraphParamSlot, Double)` — node index,
  slot, value. Readable but not labelled; the `Int` being "node index" is
  not obvious at the call site.
- `Oscillator::process(Self, DspContext, AudioBuffer, Double)` — what's
  the `Double`? (It's frequency in Hz.) Label it.

**Justifying optional args:** `crossfade_samples?`, `max_voices?`,
`feedback?`, `delay_samples?`, `init?` are all orthogonal knobs with
sensible defaults. None overlap with another positional arg. No ambiguity
introduced.

### 3.7 Error Modeling

Current matrix:

| Shape | Used for | Issue |
|---|---|---|
| `T?` | `compile`, `VoicePool::new`, `note_on`, `replay`, `voice_state(handle)` | Loses error reason. Three of these represent distinct failure modes. |
| `Bool` | `gate_on/off`, `set_param`, `queue_swap`, `queue_topology_edit(s)`, `set_template`, `set_voice_pan`, `note_off` | Silent failure family — user can't tell *why* the call was a no-op. |
| `Result[_, ControlBindingError]` | `ControlBindingBuilder::build` | Good — precedent. |
| `Result[Pat[…], String]` | `mini.parse` | `String` error type is opaque. |

What the user can do after each failure:
- `compile → None` — user has a malformed graph. Can't fix it without
  knowing which node failed.
- `set_param → false` — was the node index out of range? The slot
  invalid? Has the controller finished? User can't tell.
- `queue_swap → false` — previous swap still pending, or new graph
  incompatible?
- `note_on → None` — pool full, or template not yet compiled?

**Decision:** every `Bool` return on a mutation should become either
`Result[Unit, <narrow error>]` or, where the call is genuinely advisory
(debugger attach, fire-and-forget control), stay `Bool` but add a query
method for the last rejection reason. This is the single largest
cognitive-load improvement.

Silent-failure footgun tracking is already a known concern in the
project — the structural fix belongs in the API, not in documentation.

### 3.8 Derive Usage

Current: `derive(Eq)` on BiquadMode, EnvStage, Waveform, DspNodeKind,
GraphControlKind, GraphTopologyInputSlot, GraphValidationError,
ControlBindingError, ControlBinding, VoiceHandle, VoiceState, Rational,
TimeSpan, Event (implicit). `derive(@debug.Debug)` on most of the same,
plus manual `impl Show`.

**Does derive leak implementation details?**
- `Eq` on `DspNodeKind` — safe; it's a tag. Semantically meaningful.
- `Eq` on `ControlBinding` — safe; structural equality of three fields is
  what the user wants.
- `Eq` on `VoiceHandle` — safe; `(slot, generation)` is the identity.
- `Eq` on `Rational` — safe *iff* Rationals are always reduced. If not
  (`Rational::new(2, 4)` vs `Rational::new(1, 2)`), derived `Eq` lies.
  **Verify**: check reduction invariant.
- `Debug` on `ControlBindingMap` (struct with private fields, yet derives
  `Debug`) — `Debug` derives reach into private fields. Safe for
  debugging but changes to private layout change debug output. Probably
  fine for a 0.1.0 library, but worth noting.

**Manual `Show` + derived `Debug`:** the MoonBit convention is
`derive(Debug)` + manual `impl Show` for `inspect`-friendly pretty
output. Consistent with the codebase.

### 3.9 MoonBit Feature Usage Discipline

| Feature | Usage | Verdict |
|---|---|---|
| `using @pkg { type T }` aliases | Heavy (both facades) | **Too much**. Drift between the two facades is already visible (`CompiledTemplate`). Collapse to one. |
| Autofill / labelled optional args | Used for `crossfade_samples?`, `max_voices?`, etc. | Good. Expand coverage — see 3.6. |
| Overloaded literals | Not visible in this surface. | N/A |
| `pub(open)` traits | 13 traits | **Over-used**. The four Node traits should be sealed (see 3.3). |
| `pub(all)` enums | 11 enums | **Split the call**: `BiquadMode`, `Waveform`, `EnvStage`, `DspNodeKind`, `GraphParamSlot`, `GraphTopologyInputSlot`, `GraphControlKind`, `VoiceState` — matching-friendly tags, `pub(all)` OK. `GraphTopologyEdit` — 6 variants each with positional fields; `pub(all)` allows downstream to construct directly without using `GraphTopologyEdit::replace_node(...)` smart constructors. Consider narrowing to `pub` with factory methods. `GraphValidationError`, `ControlBindingError` — useful to pattern-match externally, keep `pub(all)`. |

## Step 4 — API Proposal

Consolidated public surface (proposed, not current):

```
@moondsp
├── Context & buffers
│   ├── DspContext (pub, immutable, labelled new)
│   ├── AudioBuffer (pub, readonly data, ctx-aware factory)
│   └── DspContext::make_buffer() -> AudioBuffer
├── Node construction (tagless)
│   ├── GraphBuilder (impls all Sym traits)
│   └── exit_deliverable[T]() -> T
├── Compilation
│   ├── CompiledDsp (abstract) with compile(nodes, ctx) -> Result[Self, [GraphValidationError]]
│   ├── CompiledStereoDsp (abstract)
│   └── CompiledTemplate (abstract — ADD to facade)
├── Runtime control
│   ├── CompiledDspHotSwap / TopologyController (abstract)
│   ├── GraphControl + GraphControlKind (pub(all) enum, factory methods)
│   ├── GraphParamSlot (pub(all) — matching-friendly)
│   └── GraphTopologyEdit (pub with factory-only construction)
├── Control binding
│   ├── ControlBinding (pub, readonly, labelled new)
│   ├── ControlBindingBuilder (abstract — hide bindings array)
│   ├── ControlBindingMap (abstract)
│   └── ControlBindingError (pub(all), rich variants)
├── Voice pool
│   ├── VoicePool (abstract)
│   ├── VoiceHandle (pub, generation-safe)
│   └── VoiceState (pub(all))
├── DSP nodes (all ABSTRACT, accessed via factory methods)
│   ├── Adsr, DelayLine, Oscillator, Noise, ParamSmoother, Biquad
│   ├── Gain, Mix, Pan, Clip (or dropped — see 3.2)
│   └── Mono, Stereo (marker via ChannelSpec trait)
├── DSP traits (pub(open))
│   └── ArithSym, DspSym, FilterSym, DelaySym, StereoSym, StereoFilterSym, StereoDelaySym, ChannelSpec
├── Enums (pub(all) — matching-friendly)
│   └── BiquadMode, EnvStage, Waveform, DspNodeKind, VoiceState, GraphParamSlot, GraphTopologyInputSlot, GraphControlKind
├── Errors (pub(all))
│   └── GraphValidationError, ControlBindingError, <new> QueueError
└── Utilities (top-level or methods where natural)
    └── is_finite, is_finite_positive, lin_map, range, replay, max_feedback_amount

SEALED/HIDDEN (remove from public surface):
- NodeEditable, NodeFoldable, NodeSpanning, NodeStateful traits
- GraphDebuggable (move to test-only package or keep internal)
- DspNode::new 12-arg constructor
- optimize_graph, node_accepts_slot, sanitize_buffer, mono_shape, stereo_shape, effective_sample_count
  (methods on DspNode / AudioBuffer / DspContext, not top-level)
- DemoSource (looks like a testing/demo helper — does the public API need it?)
```

## Step 5 — Usage Examples

### 1. Minimal Example

```moonbit
fn main {
  let ctx = DspContext::new(sample_rate=48000.0, block_size=128)
  let patch : GraphBuilder = exit_deliverable()
  let compiled = CompiledDsp::compile(patch.nodes(), ctx).unwrap()
  let buf = ctx.make_buffer()
  compiled.process(ctx, buf)
}
```

**Learns:** three concepts — context, graph-as-value, compiled processor.
**Misuse prevented:** labelled args block sample-rate / block-size swap;
`ctx.make_buffer()` guarantees buffer sizing. **Correctness inferable from
types:** yes — nothing compiles without a matching `DspContext`.

### 2. Standard Usage

```moonbit
let template = [
  DspNode::oscillator(Waveform::Sine, 440.0),
  DspNode::adsr(attack_ms=5.0, decay_ms=50.0, sustain=0.7, release_ms=200.0),
  DspNode::envelope_gain(0, 1, 0.5),
  DspNode::output(2),
]
let bindings = ControlBindingBuilder::new()
  .bind(key="freq", node_index=0, slot=GraphParamSlot::Value0)
  .bind(key="gain", node_index=2, slot=GraphParamSlot::Value0)
  .build(CompiledTemplate::analyze(template)) // Result
  |> unwrap
let pool = VoicePool::new(template, ctx, max_voices=16).unwrap()
let handle = pool.note_on(bindings.resolve_controls({"freq": 220.0, "gain": 0.3})).unwrap()
```

**Learns:** pattern of template-as-data, builder-for-bindings, voice pool
on top. **Misuse prevented:** labelled `adsr` args (ms explicit);
`ControlBindingBuilder::build` catches orphan bindings *before* runtime;
generation-tagged handle. **Inferable:** yes for the happy path; the
`.unwrap()`s are obvious error boundaries.

### 3. Advanced Usage

```moonbit
struct MyCseInterp { table : Map[String, Int] }

pub impl ArithSym for MyCseInterp with constant(x) { ... }
pub impl DspSym   for MyCseInterp with oscillator(self, w) { ... }
pub impl FilterSym for MyCseInterp with biquad(self, m, f, q) { ... }
// ...

fn[T : FilterSym] my_patch() -> T { ... }
let plain = my_patch[GraphBuilder]()
let cse   = my_patch[MyCseInterp]()
```

**Learns:** tagless algebra allows alternative interpretations. **Misuse
prevented:** bounded generics force implementing the required trait
hierarchy. **Inferable:** yes — `FilterSym : DspSym : ArithSym` chain is
clear from trait declarations.

## Step 6 — Misuse Analysis

| Misuse | Currently prevented? | Fix |
|---|---|---|
| Swap `(sample_rate, block_size)` in `DspContext::new` | No (positional) | Labelled args |
| Pass seconds to Adsr expecting ms | No (positional, same type) | Labelled `attack_ms~` / `release_ms~` |
| Construct `AudioBuffer` with length ≠ `block_size` | No | Ctx-aware factory + debug assert |
| Mutate `Oscillator.phase` mid-process via field write | No (`mut` exposed) | Abstract type |
| Construct `DspNode` with mismatched kind/fields | No (`DspNode::new` exposed) | Hide raw `new` |
| Call `set_param` with wrong slot for a node | Runtime (returns `false` silently) | Return `Result` with reason |
| Hold stale `VoiceHandle` after generation wrap | Yes — generation check | (no change; verify wrap-around is handled) |
| Construct orphan `ControlBinding` | Yes at `.build()` time via `OrphanBinding` | (good) |
| Duplicate keys in `ControlBindingBuilder` | Yes at `.build()` via `DuplicateKey` | (good) |
| Queue second hot-swap while previous is in flight | Runtime (`queue_swap → false`) | Return `Result[Unit, QueueError]` |
| Implement `NodeFoldable` for external type expecting library use | Type-system allows it, library ignores it | Seal the trait |
| Call `@moondsp.CompiledTemplate` expecting it to exist | Compile error on current code | Fix facade drift |

**Reviewer detection without running code:** most of the above become
reviewable at call sites *if* labelled args + abstract types + `Result`
returns are adopted. Today, a reviewer scanning a diff can't tell whether
`DspContext::new(128, 48000)` is wrong or whether `set_param(...)` was
checked for success.

## Step 7 — Alternative Designs

### 7.1 Sealed Node traits vs `pub(open)` — chosen: **sealed**

- **Chosen:** seal `NodeEditable`, `NodeFoldable`, `NodeSpanning`,
  `NodeStateful`.
- **Trade-off:** loses a theoretical extension point; none is used.
- **Future compatibility:** sealing → opening is non-breaking; opening →
  sealing is breaking. Default to sealed.
- **Cognitive load:** four fewer traits in the API surface (from 13 → 9).

### 7.2 Readonly `pub` vs `pub(all)` for state-bearing DSP types — chosen: **abstract type**

- **Chosen:** abstract (`type Adsr`, etc.).
- **Trade-off:** external users lose `adsr.stage` field read — but the
  `stage()` accessor already exists, so nothing is lost.
- **Future compatibility:** field additions / removals inside an abstract
  type are non-breaking. Today they are breaking.
- **Cognitive load:** users can't be confused about which field is safe to
  touch; only method-level API exists.

### 7.3 Optional args vs config struct for `VoicePool::new` — chosen: **optional args**

- **Chosen:** keep `max_voices? : Int`, keep `crossfade_samples? : Int`.
- **Trade-off:** two knobs is fine for labelled-optional. Four or more
  would justify a config struct.
- **Future compatibility:** adding a new optional-labelled arg is
  non-breaking. A config struct is non-breaking to add fields if declared
  `pub` (readonly) with labelled constructor.
- **Cognitive load:** fewer named types.

### 7.4 Derive-heavy vs manual `Show` — chosen: **current mix (derive `Debug`, manual `Show`)**

- **Chosen:** unchanged. It matches MoonBit `inspect` / `Debug` / `Show`
  convention.
- **Trade-off:** small maintenance cost for manual `Show`, buys formatting
  control.
- **Future compatibility:** low risk.

## Step 8 — Stability Analysis

**What breaks users if changed:**
- Any `pub` field on state-bearing DSP structs. **Highest risk.**
  Recommend abstracting *before* 1.0.
- `pub(all)` enum variants. Adding variants is breaking for exhaustive
  matchers. `GraphTopologyEdit` (6 variants, likely to grow) is the most
  at-risk; `DspNodeKind` (18 variants, likely to grow) second. Consider
  `pub` + factory constructors + a `non_exhaustive`-like convention
  (MoonBit has no such attribute; the pattern `_ => ...` discipline needs
  to be documented).
- `pub(open)` traits. Adding a method is breaking. The symantic trait
  hierarchy (`ArithSym` / `DspSym` / `FilterSym` / ...) is at-risk — new
  DSP primitives require new trait methods.
- Any positional argument reorder. Labelling pre-1.0 is cheap; post-1.0
  is not.

**Hardest APIs to evolve:**
- The seven symantic traits — adding a primitive (e.g. `waveshaper`)
  requires adding a method to `DspSym` or creating a new trait and wiring
  it into bounded-generic consumers like `replay`.
- `CompiledTemplate`, `ControlBindingMap` — abstract today, good.
- `DspNodeKind` — growing enum; every addition is a breaking change for
  exhaustive matchers downstream.

**Abstraction leaks:**
- `GraphBuilder::nodes_ : Array[DspNode]` field — the underscore hints at
  "don't touch me" but the field is still `pub`. If the builder ever
  needs to store auxiliary state (debug origin, index maps), this leaks.
- `PatternScheduler` (scheduler package) exposes `mut bpm`,
  `mut sample_counter`, `ctx`, `active_notes`, `bindings`, `mapper` —
  four internal fields, mutable, public. Highest-churn structure in the
  surface.

**Must NEVER be exposed:**
- Internal `DspNode` layout (already exposed — regret).
- Voice-pool internal buffers, ring indices, generation counter
  representation.
- Crossfade state machine.
- Any audio-thread allocation surface (all hidden today; keep it that
  way).

## Step 9 — Final Conclusion

The moondsp public API is **functional and cohesive for the single-repo
use case**, but it is **not yet stability-ready for external consumers**.
The two largest risks are:

1. **Excessive field exposure on state-bearing DSP structs** (`Adsr`,
   `DelayLine`, `Oscillator`, `ParamSmoother`, `DspNode`). Every field
   access is a future breaking change. The fix — abstracting the types —
   is mechanical and safe, because accessor methods already exist for
   every read the user needs.

2. **The silent-failure `Bool`-return family** — `gate_on/off`,
   `set_param`, `queue_swap`, `queue_topology_edit*`, `set_voice_pan`.
   These shift diagnosis onto runtime and make code reviewable only by
   running it. Narrow error enums are the fix.

Secondary issues: the two-facade drift (`@moondsp` vs `@lib` with
`CompiledTemplate` missing from root), over-open Node traits, positional
ADSR / context constructors, and the raw `DspNode::new` backdoor.

### Final Mandatory Check

- **Can a user infer correct usage from types alone?** Partially. Not for
  ms-vs-s ADSR args, not for `(sample_rate, block_size)` order, not for
  "did this mutation succeed." → **No** under current API; **Yes** under
  the proposed revisions.
- **Can a reviewer detect misuse without running code?** No today —
  positional doubles and `Bool` returns are invisible in diffs. Yes
  under proposed revisions (labelled args + `Result`).
- **Can future changes be made without breaking contracts?** No today —
  public fields on state-bearing structs pin the internal layout. Yes
  under proposed revisions (abstract types).

Under the current API two of three answer "No". **Revision recommended
before 1.0.**

### Top-3 Prioritised Actions

1. **Fix facade drift**: pick one of `@moondsp` / `@lib`, move
   `CompiledTemplate` into the root facade, delete the duplicate.
   Mechanical, unblocks external use.
2. **Abstract state-bearing DSP structs** (`Adsr`, `DelayLine`,
   `Oscillator`, `Noise`, `ParamSmoother`, and hide `DspNode::new`).
   Mechanical — all reads already have accessors.
3. **Label the footgun constructors**: `DspContext::new`, `Adsr::new`,
   `DspNode::adsr`, `DspNode::biquad`, `Oscillator::process`. Two hours
   of work, permanent dividend in call-site legibility.

Items 1 and 3 are pre-1.0-essential and touch no internals. Item 2 is the
largest stability win and can be staged package-by-package under the
`pub using` facade without breaking downstream code within this repo
(since the re-export target can flip from `pub` struct to abstract type
transparently for `@moondsp.X` callers — they only use methods).
