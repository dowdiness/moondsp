# ADR-0003: CompiledTemplate as topology artifact for orphan detection

- **Status:** Accepted
- **Date:** 2026-04-22 (decision shipped 2026-04-18, PR #9)
- **Source:** [`docs/superpowers/specs/archive/2026-04-18-control-binding-orphan-design.md`](../superpowers/specs/archive/2026-04-18-control-binding-orphan-design.md)
- **Related:** PR #8 (orphan-ADSR detection in `VoicePool`)

## Context

`ControlBindingBuilder::build(template)` validated three properties against
the raw authoring template: `node_index` bounds, slot-vs-kind compatibility,
and duplicate keys. It did not consider what `optimize_graph` actually kept.

The failure mode was silent: if a bound node was dead-code-eliminated, every
`resolve_controls` call emitted a `GraphControl::set_param` that the compiled
graph dropped (`CompiledGraph.index_map[i] = -1` → no-op). Audio looked
plausible — no errors, no crashes — but control knobs did nothing.

PR #8 had shipped the same fix shape for orphan ADSR nodes by exposing a
public `CompiledDsp::orphan_adsr_count(template)` method. This had two
problems: (1) `CompiledDsp` had to take the template back as an argument
because it had discarded its source after compilation, and (2) the
control-binding orphan case needed the same topology information but at a
different point in the lifecycle. Adding a second `orphan_*_count` method
each time a new validation site appeared would not scale.

The deeper observation: binding validation needs the **template snapshot**
(for slot-vs-kind lookups and bounds) and the **optimization result** (for
liveness). Both are pure topology concerns — no buffers, no envelope state,
no feedback registers, no `DspContext`. `CompiledDsp` conflated topology
with runtime state, which is why the Codex review had flagged the
`orphan_adsr_count(template)` shape.

## Decision

Introduce `graph/compiled_template.mbt` holding a new artifact:

```moonbit
pub struct CompiledTemplate {
  priv template  : Array[DspNode]   // defensive copy at analyze time
  priv index_map : FixedArray[Int]  // from optimize_graph
}

pub fn CompiledTemplate::analyze(template : Array[DspNode]) -> CompiledTemplate
pub fn CompiledTemplate::orphan_adsr_count(self) -> Int
fn CompiledTemplate::is_node_live(self, index : Int) -> Bool   // package-private
fn CompiledTemplate::node_at(self, index : Int) -> DspNode     // package-private
fn CompiledTemplate::length(self) -> Int                       // package-private
```

`CompiledTemplate::analyze` is **infallible** because `optimize_graph` cannot
fail. The defensive copy isolates the artifact from caller mutation.

`ControlBindingBuilder::build(template)` becomes
`build(compiled_template : CompiledTemplate)`. Validation order is:

1. bounds → `InvalidNodeIndex(i)`
2. slot-vs-kind → `InvalidSlotForNode(i, slot)`
3. liveness → `OrphanBinding(key, i)` **(new)**
4. duplicate key → `DuplicateKey(key)`

`VoicePool::new` and `VoicePool::set_template` migrate from
`test_compile.orphan_adsr_count(template)` to
`CompiledTemplate::analyze(template).orphan_adsr_count()`. The public
`CompiledDsp::orphan_adsr_count(template)` method is removed.

## Consequences

**Positive**

- Two distinct silent-failure footguns (orphan ADSRs, orphan bindings) now
  fail loud at construction time with specific error variants carrying the
  offending key/index.
- The "leak the template back to the compiled artifact" anti-pattern is gone.
  Topology questions go to a topology artifact; runtime questions go to
  `CompiledDsp`.
- `CompiledTemplate::analyze` skips all buffer and state allocation, so the
  orphan-ADSR gate in `VoicePool` is cheaper than the previous
  compile-then-query path.
- The pattern generalises: future "is this authoring-time configuration valid
  given what the optimiser kept?" checks go on `CompiledTemplate`, not on
  `CompiledDsp`.

**Negative**

- Breaking signature change: every existing `build(template)` call site in
  `lib/`, `scheduler/`, `browser/`, `voice/`, plus tests, had to migrate to
  `build(CompiledTemplate::analyze(template))`. Mechanical, but ~22 sites.
- `CompiledDsp::orphan_adsr_count(template)` is gone — any external consumer
  who picked it up between PR #8 and PR #9 must move to `CompiledTemplate`.
- `VoicePool` still has to call `CompiledDsp::compile(template, context)?`
  after the orphan gate to catch non-topology problems (feedback cycle
  validation, etc.). The compile result is discarded. Slightly redundant
  but preserves the existing sanity check.

**Known follow-up footgun (not addressed)** — After
`VoicePool::set_template` swaps the pool template, a `ControlBindingMap`
validated against the prior template remains type-level valid but silently
targets the new template's nodes. Mitigated by a docstring warning on
`ControlBindingMap`. Structural fix deferred (options: identity check at
apply, `BoundVoicePool` composite, atomic `set_template_with_bindings`).
