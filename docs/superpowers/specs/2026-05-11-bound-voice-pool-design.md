# Bound Voice Pool — Design Spec

**Date:** 2026-05-11
**Status:** Draft — awaiting implementation
**Related:** `docs/api-design-review-2026-04-21.md`, PR #8/#9 follow-up

## Goal

Remove the silent-failure path where a `ControlBindingMap` validated against
one voice template is later used with a `VoicePool` whose template was changed
by `VoicePool::set_template`.

At the same time, remove the extra `CompiledTemplate::analyze(template)` call
from browser/scheduler pool construction. Template topology should be analyzed
once, then reused for orphan-ADSR validation, binding validation, and compile.

## Current Failure Mode

`ControlBindingBuilder::build(compiled_template)` proves that bindings are
valid for that one compiled template: node indices are in bounds, slots match
node kinds, target nodes survive `optimize_graph`, and keys are unique.

`PatternScheduler` then stores only the resulting `ControlBindingMap`.
`VoicePool` separately stores a mutable current template. If
`VoicePool::set_template(new_template)` succeeds, the scheduler's binding map
is still type-level valid, but it may now:

- point at a different node kind at the same authoring index,
- no-op against a node eliminated in the new template,
- or keep working by accident when the new template happens to match.

The wrong-kind case is often caught by `CompiledDsp::apply_controls`, but the
same-index compatible-kind and optimized-away cases can silently retarget or
drop controls.

Browser pool construction also repeats topology analysis:

1. `VoicePool::new(template, ctx)` calls `CompiledTemplate::analyze`.
2. `VoicePool::new` calls `CompiledDsp::compile`, which optimizes again.
3. `make_drum_pool` / `make_synth_pool` call
   `CompiledTemplate::analyze(template)` again for binding validation.

## Non-goals

- Do not solve direct low-level `GraphControl` misuse. Callers who bypass
  `ControlBindingMap` can still construct bad controls.
- Do not introduce a dynamic warning-only API. The design should make the
  scheduler/browser safe path structurally unable to pair stale bindings with a
  new template.
- Do not change pattern language semantics.
- Do not remove `VoiceSlot.template_snapshot`; note-off still needs the exact
  authoring template active at note-on time.

## Chosen Design

Introduce a `BoundVoicePool` composite that owns both:

- a `VoicePool`
- the `ControlBindingMap` proven against that pool's current template

`PatternScheduler` stops storing `ControlBindingMap`. It remains responsible
for time, active note expiry, and control-map normalization, but it passes raw
control maps to `BoundVoicePool`, which resolves bindings and triggers voices
atomically against its own current binding map.

### New Public Type

```moonbit
pub struct BoundVoicePool {
  priv pool : VoicePool
  priv bindings : ControlBindingMap
}
```

Core methods:

```moonbit
pub fn BoundVoicePool::new(
  template : Array[DspNode],
  context : DspContext,
  bindings : ControlBindingBuilder,
  max_voices? : Int = 32,
) -> Result[BoundVoicePool, BoundVoicePoolError]

pub fn BoundVoicePool::set_template(
  self : BoundVoicePool,
  template : Array[DspNode],
  bindings : ControlBindingBuilder,
) -> Result[Unit, BoundVoicePoolError]

pub fn BoundVoicePool::note_on_controls(
  self : BoundVoicePool,
  controls : Map[String, Double],
) -> VoiceHandle?

pub fn BoundVoicePool::note_off(self : BoundVoicePool, handle : VoiceHandle) -> Bool
pub fn BoundVoicePool::set_voice_pan(
  self : BoundVoicePool,
  handle : VoiceHandle,
  pan : Double,
) -> Bool
pub fn BoundVoicePool::process(
  self : BoundVoicePool,
  context : DspContext,
  left : AudioBuffer,
  right : AudioBuffer,
) -> Unit
```

`BoundVoicePool::set_template` is transactional: analyze/validate/compile the
new template and bindings first; mutate neither `pool` nor `bindings` if any
step fails.

`BoundVoicePool` should live in `voice/`. The current dependency graph supports
that: `voice/` already imports `dsp/` and `graph/`, while `scheduler/` and
`browser/` consume the root `@moondsp` facade. This avoids creating a new bridge
package and does not introduce a package cycle.

### Error Type

```moonbit
pub(all) enum BoundVoicePoolError {
  InvalidMaxVoices
  OrphanAdsr
  CompileRejected
  Binding(ControlBindingError)
}
```

The old `VoicePool::new(...) -> VoicePool?` can remain as the low-level API for
callers that do not need bindings. `BoundVoicePool::new` should use the same
validation path but return a specific error.

## Reuse One Template Analysis

Extend `CompiledTemplate` to retain the optimized nodes as well as the
authoring snapshot and index map:

```moonbit
pub struct CompiledTemplate {
  priv template : Array[DspNode]
  priv optimized : Array[DspNode]
  priv index_map : FixedArray[Int]
}
```

Then add graph compile entrypoints that reuse the analysis:

```moonbit
pub fn CompiledDsp::compile_template(
  compiled_template : CompiledTemplate,
  context : DspContext,
) -> CompiledDsp?

pub fn CompiledStereoDsp::compile_template(
  compiled_template : CompiledTemplate,
  context : DspContext,
) -> CompiledStereoDsp?
```

Implementation sketch:

- `CompiledTemplate::analyze` still copies the authoring template once.
- It stores the `optimized` nodes returned by `optimize_graph(snapshot)`.
- `CompiledDsp::compile_template` calls the existing internal compile path with
  `compiled_template.optimized` and `compiled_template.index_map`, avoiding a
  second optimization pass.
- `ControlBindingBuilder::build` keeps taking `CompiledTemplate`, so binding
  validation reuses the same artifact.
- `BoundVoicePool::new` does one `CompiledTemplate::analyze`, then:
  - rejects `orphan_adsr_count() > 0`,
  - builds bindings with the same compiled template,
  - compiles with `CompiledDsp::compile_template`.

### VoicePool Internals

The current `VoicePool::new` cannot be reused by `BoundVoicePool::new` as-is:
it calls `CompiledTemplate::analyze(template)` internally, which would preserve
the duplicate-analysis problem. Add a shared internal constructor/validator
that accepts a precomputed `CompiledTemplate`.

Recommended internal shape:

```moonbit
fn VoicePool::new_validated(
  template : Array[DspNode],
  compiled_template : CompiledTemplate,
  context : DspContext,
  max_voices : Int,
) -> Result[VoicePool, BoundVoicePoolError]
```

`VoicePool::new` can keep its existing public `VoicePool?` surface by calling
`CompiledTemplate::analyze(template)` and then `new_validated(...)`, mapping
errors back to `None`.

To avoid a remaining per-note optimization pass, `VoicePool` should store the
current `CompiledTemplate` alongside its template snapshot and use
`CompiledDsp::compile_template(self.compiled_template, self.compile_context)`
inside `note_on`. This preserves the existing `VoiceSlot.template_snapshot`
behavior for note-off correctness while reusing the topology artifact for each
voice compile.

`CompiledTemplate` should remain immutable from outside `graph/`. Do not expose
the optimized node array as public API; `CompiledDsp::compile_template` and
`CompiledStereoDsp::compile_template` should be the public consumers. If
`voice/` needs the authoring snapshot, either keep its existing copied
`template : Array[DspNode]` field or add a deliberately named snapshot accessor
that returns a copy.

## Scheduler Changes

Current:

```moonbit
PatternScheduler {
  bindings : ControlBindingMap
}

process_block(pat, pool : VoicePool, left, right)
```

After:

```moonbit
PatternScheduler {
  // no bindings field
}

process_block(pat, pool : BoundVoicePool, left, right)
```

`PatternScheduler::process_events` keeps building the normalized control map
and extracting `VoiceAction`s. Instead of:

```moonbit
let controls = self.bindings.resolve_controls(map)
match pool.note_on(controls) { ... }
```

it calls:

```moonbit
match pool.note_on_controls(map) { ... }
```

That makes stale binding pairs unrepresentable in the scheduler/browser path.

## Browser Changes

`SoundPool` changes from:

```moonbit
pool : @moondsp.VoicePool
scheduler : @scheduler.PatternScheduler
```

to:

```moonbit
pool : @moondsp.BoundVoicePool
scheduler : @scheduler.PatternScheduler
```

`make_drum_pool` constructs `BoundVoicePool` with an empty
`ControlBindingBuilder`. `make_synth_pool` constructs it with the `"note"`
binding builder. Neither function calls `CompiledTemplate::analyze` directly.

## Compatibility

This is a pre-1.0 API hardening change, so breaking scheduler/browser APIs is
acceptable.

Recommended compatibility posture:

- Keep low-level `VoicePool` for direct graph-control callers.
- Move public scheduler/browser examples to `BoundVoicePool`.
- Keep `ControlBindingMap` public because advanced users may still want
  explicit binding resolution. Keep its stale-template warning because low-level
  users can still manually pair an old binding map with a changed `VoicePool`;
  the warning just no longer applies to the default scheduler/browser path.
- Consider changing `VoicePool::set_template` from `Bool` to a result-typed
  API in a later pass. `BoundVoicePool::set_template` should be result-typed
  from the start.

## Test Plan

- `BoundVoicePool::new` succeeds for valid empty bindings.
- `BoundVoicePool::new` returns `Binding(...)` for invalid binding builders.
- `VoicePool::note_on` uses the stored `CompiledTemplate` path rather than
  calling `CompiledDsp::compile`, so voice trigger does not re-run
  `optimize_graph`.
- `BoundVoicePool::set_template` rejects orphan ADSR templates and leaves the
  previous template/bindings active.
- `BoundVoicePool::set_template` rejects bindings invalid for the new template
  and leaves the previous template/bindings active.
- New voices after successful `set_template` use the new template and new
  bindings.
- Scheduler no longer stores `ControlBindingMap`.
- Browser `make_drum_pool` / `make_synth_pool` no longer call
  `CompiledTemplate::analyze` directly.
- Existing `moon test` suite remains green.

## Open Questions

- Should `VoicePool::new` become result-typed in the same implementation pass,
  or should `BoundVoicePool::new` be the first result-typed pool constructor?
- Should `BoundVoicePool::note_on_controls` return `VoiceHandle?` for parity
  with `VoicePool::note_on`, or a result type that distinguishes rejected
  controls from compile failure?
