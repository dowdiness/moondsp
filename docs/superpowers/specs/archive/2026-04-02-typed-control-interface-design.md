# Typed Control Interface Design

**Date:** 2026-04-02
**Status:** Approved (revised after Codex review)
**Motivation:** Audit finding S4 — ControlMap uses `Map[String, Double]` with no compile-time verification that pattern keys match DSP control slots. A typo produces silence, not an error.

## Problem

The pattern engine produces `ControlMap(Map[String, Double])` with string keys like `"note"`, `"cutoff"`, `"gain"`, `"pan"`. The DSP engine consumes `GraphControl` with `(node_index, GraphParamSlot, value)`. There is no bridging code and no type safety at the boundary. Phase 5 (pattern-driven voice triggering) requires this bridge.

## Approach: Bridge Layer (Option B)

Keep the pattern engine's string-keyed `ControlMap` unchanged. Add a validated `ControlBindingMap` in the `lib/` package that maps string keys to graph control targets. Type safety is enforced at graph construction time, not in the pattern engine.

**Why not replace ControlMap?** The pattern engine's string keys are a domain language for musicians (Strudel compatibility). The type safety problem is at the bridge, not in the pattern layer.

## Data Structures

### ControlBinding

A single mapping from a string key to a graph control target.

```moonbit
pub struct ControlBinding {
  key : String
  node_index : Int
  slot : GraphParamSlot

  fn new(key~ : String, node_index~ : Int, slot~ : GraphParamSlot) -> ControlBinding
} derive(Show, Eq)
```

### ControlBindingError

Structured error type for build-time validation failures. Provides diagnostic context rather than collapsing all failures into `None`.

```moonbit
pub(all) enum ControlBindingError {
  InvalidNodeIndex(Int)
  InvalidSlotForNode(Int, GraphParamSlot)
  DuplicateKey(String)
} derive(Show, Eq)
```

### ControlBindingBuilder (validated builder: accumulating phase)

Collects bindings before validation. Can add bindings, cannot resolve controls.

```moonbit
pub struct ControlBindingBuilder {
  bindings : Array[ControlBinding]

  fn new() -> ControlBindingBuilder
} derive(Show)
```

Methods:
- `bind(self, key~, node_index~, slot~) -> ControlBindingBuilder` — add a binding, returns self for chaining (mutates internal array)
- `build(self, template : Array[DspNode]) -> Result[ControlBindingMap, ControlBindingError]` — validate and transition

### ControlBindingMap (validated builder: proven-valid phase)

Proven-valid binding map. Can resolve controls, cannot be modified. No public constructor — only reachable through `ControlBindingBuilder::build()`.

```moonbit
pub struct ControlBindingMap {
  bindings : Array[ControlBinding]
} derive(Show, Eq)
```

Methods:
- `resolve_controls(self, controls : Map[String, Double]) -> Array[GraphControl]` — convert pattern controls to graph controls

## Index Semantics

Binding `node_index` values are **authoring indices** — positions in the original `Array[DspNode]` template as written by the graph author. These are the same indices used by `GraphControl::set_param` and `VoicePool::note_on`. They are stable across:
- Graph compilation (optimizer may reorder internally, but controls use the `index_map` to translate)
- Hot-swap (new graph compiled from same template keeps the same authoring indices)

A `ControlBindingMap` must be rebuilt if the template itself changes (different node array). This is the same constraint as `VoicePool::set_template` — changing the template invalidates all prior compiled state.

## Validation (in build())

The `build()` method validates each binding against the graph template:

1. **Node index bounds:** `0 <= node_index < template.length()`. Failure: `InvalidNodeIndex(node_index)`.
2. **Slot compatibility:** The node at that index must accept the given `slot` for `SetParam` controls. This is a structural check — "does this node kind accept Value0?" — not a value-domain check. It reuses the same node-kind/slot compatibility logic as `updated_node_param`. Failure: `InvalidSlotForNode(node_index, slot)`.
3. **No duplicate keys:** Two bindings with the same string key are rejected. Failure: `DuplicateKey(key)`.

Returns `Err(ControlBindingError)` on the first validation failure. Returns `Ok(ControlBindingMap)` on success.

**What validation does NOT check:**
- Value-domain constraints (e.g., cutoff > 0, gain finite). Those are checked downstream by `apply_control` at runtime, where the actual value is known.
- Duplicate targets (two different keys bound to the same `(node_index, slot)`) are allowed. This supports aliases — e.g., both `"freq"` and `"note"` targeting the same oscillator. Controls are emitted in binding insertion order; if two keys resolve to the same target, the last one wins at `apply_controls` time.

## Bridge Function (resolve_controls)

```moonbit
pub fn ControlBindingMap::resolve_controls(
  self : ControlBindingMap,
  controls : Map[String, Double],
) -> Array[GraphControl]
```

For each binding **in insertion order**:
1. Look up `binding.key` in the `Map[String, Double]`
2. If present: emit `GraphControl::set_param(binding.node_index, binding.slot, value)`
3. If absent: skip (missing keys are not errors — a pattern event may carry only a subset of controls)

**Ordering guarantee:** Controls are emitted in binding insertion order (the order `bind()` was called). This is deterministic and testable. If two keys alias the same target, the later binding's value overwrites the earlier one.

**Unrecognized keys** in the input map (keys with no binding) are silently ignored. This preserves forward compatibility — patterns can carry metadata keys that aren't graph parameters.

**Value passthrough:** This layer does not validate or transform values. `NaN`, `Inf`, negative values are passed through to `GraphControl::set_param`, which delegates to the existing `updated_node_param` validation. Values rejected there cause `apply_control` to return false, which is the caller's responsibility to handle.

## Usage

```moonbit
// At pool creation — validated once:
let bindings = ControlBindingBuilder()
  .bind(key="note", node_index=0, slot=Value0)
  .bind(key="cutoff", node_index=3, slot=Value0)
  .bind(key="gain", node_index=4, slot=Value0)
  .build(template)

match bindings {
  Ok(map) => {
    // At note event (Phase 5 bridge):
    let controls = map.resolve_controls(event_controls)
    pool.note_on(controls)
  }
  Err(e) => abort("invalid control binding: \{e}")
}
```

## Package Location

All new types and functions live in `lib/` — this is a DSP concept. The pattern engine (`pattern/`) is not modified.

`resolve_controls` accepts `Map[String, Double]` directly (the inner type of ControlMap) rather than importing `ControlMap` from `pattern/`. This avoids adding `pattern/` as a dependency of `lib/` and keeps the packages independent.

Callers that have a `ControlMap` destructure it at the call site: `bindings.resolve_controls(control_map.0)` (where `.0` accesses the inner Map from the newtype wrapper).

**Future consideration:** If Phase 5 adds substantial integration logic (gate semantics, pitch-to-frequency conversion), a dedicated bridge package that depends on both `lib/` and `pattern/` may be cleaner. For now, `lib/` is sufficient.

## What This Does NOT Cover

- **Gate-on/gate-off from note events** — Phase 5 will add semantics where a `"note"` key triggers ADSR gate_on. That is a separate concern layered on top of the binding map. The binding map only handles `SetParam` controls; gate logic will be a distinct translation step.
- **Replacing the pattern engine's string keys** — they stay as-is.
- **Runtime parameter smoothing** — bindings map values directly; smoothing is handled downstream by the DSP nodes.
- **Value-domain validation** — whether a cutoff value is positive or a gain is finite is checked by the existing `apply_control` path, not by the binding layer.
- **Pitch-to-frequency conversion** — `"note"` maps to a node parameter as a raw Double (MIDI note number). Conversion to Hz is a Phase 5 concern.

## Testing

1. **Valid binding construction:** Builder with correct node indices and slots produces `Ok(map)`
2. **Invalid node index:** Returns `Err(InvalidNodeIndex(n))`
3. **Invalid slot for node kind:** Returns `Err(InvalidSlotForNode(n, slot))`
4. **Duplicate keys:** Returns `Err(DuplicateKey(key))`
5. **Duplicate targets allowed:** Two keys bound to the same `(node_index, slot)` produces `Ok`
6. **Resolve with full map:** All bound keys are converted to correct GraphControl values in insertion order
7. **Resolve with partial map:** Missing keys are skipped, present keys are converted
8. **Resolve with extra keys:** Unbound keys in the input map are ignored
9. **Resolve ordering:** Controls emitted in binding insertion order, verified by snapshot test
10. **Integration with VoicePool:** Resolved controls are accepted by `VoicePool::note_on`
11. **Empty builder:** `ControlBindingBuilder().build(template)` with zero bindings produces `Ok` with empty resolve output
