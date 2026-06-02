# Editor audio preview handoff

This contract defines how an external authoring UI such as Canopy hands graph
preview work to MoonDsp without moving parser, lowering, template analysis, or
compile work onto the audio callback. It builds on the external DSL lowering
contract and the Mini/graph bridge contract rather than redefining either one.

## Ownership boundary

An editor or external graph DSL owns the authoring model:

- source text, CST/projection state, and source ranges;
- stable graph node IDs and the current stable-ID -> authoring-index map;
- control declarations: stable control keys, target stable IDs, target
  `GraphParamSlot`s, and declaration source ranges;
- source-language diagnostics before `Array[DspNode]` exists;
- the last-good source/lowering snapshot when the current edit is invalid.

MoonDsp owns runtime artifacts and validation at the graph boundary:

- `CompiledTemplate::analyze(Array[DspNode])` as the single crossing from an
  authoring graph snapshot to a template artifact;
- `ControlBindingBuilder::build(template)` validation against that template;
- `CompiledDsp::compile_result` / `CompiledStereoDsp::compile_result`
  diagnostics for MoonDsp graph rejection;
- `GraphControl` / `ControlBindingMap` runtime-control validation;
- `CompiledDspHotSwap`, `CompiledStereoDspHotSwap`, topology controllers, and
  `BoundVoicePool::set_template` block-boundary staging.

Parser work, projection, semantic lowering, `CompiledTemplate::analyze`,
binding validation, compile, hot-swap setup, and voice-pool template replacement
are editor/control-thread work. The audio callback only processes already
compiled runtimes and applies already prepared block-boundary controls or swaps.

A `Ready` or last-good preview bundle should contain the authoring revision,
source maps, the `Array[DspNode]` snapshot, the `CompiledTemplate`, bindings
proven against that template, and the compiled runtime or owning wrapper
(`CompiledDspHotSwap`, stereo hot-swap, topology controller, or
`BoundVoicePool`). The editor owns the metadata and source maps; MoonDsp runtime
objects own their compiled graph state. Replace the bundle only after every
piece for the candidate revision validates.

## Preview state machine

The preview panel should expose the state of the current authoring revision, not
just whether audio is currently audible.

```text
Idle
  | enable preview or first graph edit
  v
Analyzing(authoring_revision)
  | valid lower + analyze + bindings + compile + stage
  v
Ready(runtime_revision)
  | topology/control-declaration/default edit
  v
Analyzing(next_authoring_revision)
  | failure and previous ready runtime exists
  v
UsingLastGoodTemplate(last_good_runtime_revision, diagnostics)
  | next successful topology analysis/compile/stage
  v
Ready(next_runtime_revision)

Analyzing(first_authoring_revision)
  | failure and no previous ready runtime exists
  v
Failed(diagnostics)
```

State meanings:

| State | Meaning | Audio behavior |
| --- | --- | --- |
| `Idle` | Preview is disabled or no graph has been requested. | No MoonDsp preview runtime is required. |
| `Analyzing` | The editor/control side is validating, lowering, analyzing, building bindings, compiling, or staging a candidate. | Keep the current runtime playing if one exists; never block the audio callback on this work. |
| `Ready` | A template, binding map, and runtime have been prepared and accepted for preview. | Process the active runtime; apply accepted controls at block boundaries. |
| `UsingLastGoodTemplate` | The latest edit failed, but a previous ready runtime/template remains usable. | Continue playing the last-good runtime/template and display diagnostics for the failed candidate. Do not queue a hot-swap or replace a voice-pool template from the failed candidate. |
| `Failed` | The latest edit failed and there is no last-good runtime/template for this preview session. | Show diagnostics; no preview audio is available until the next successful candidate. |

Parameter-only edit rejection does not require a topology state transition. A
bad `GraphControl` batch is reported as a control diagnostic while the existing
`Ready` or `UsingLastGoodTemplate` runtime remains unchanged. If the UI models a
combined transaction containing both a topology edit and live controls, reject
the whole transaction and keep the last-good runtime/template.

## Which edits require topology analysis

Use topology analysis and replacement when the authoring graph snapshot changes:

- adding, deleting, inserting, or rewiring DSP nodes;
- changing a node kind;
- changing terminal shape (`Output` vs `StereoOutput`) or graph routing shape;
- changing graph-authored static defaults encoded in `DspNode` values;
- adding/removing a control declaration, changing a control key, or changing a
  declaration's target stable node ID or `GraphParamSlot`;
- rebuilding or replacing a prepared template selected by Mini or another
  external pattern/control layer.

Topology replacement flow:

```text
normalized authoring graph revision
  -> Array[DspNode]
  -> CompiledTemplate::analyze
  -> rebuild ControlBindingBuilder from stable declarations
  -> ControlBindingBuilder::build(template)
  -> CompiledDsp::compile_result / CompiledStereoDsp::compile_result
  -> queue hot-swap, queue topology controller edit, or BoundVoicePool::set_template
  -> publish at the next block boundary
```

For editor diagnostics, prefer compiling the full candidate snapshot with
`compile_result` before staging. Topology controller queue errors are still
useful for result-typed edit batches, but `GraphTopologyQueueError::RecompileRejected`
does not carry the same source-mappable detail as `compile_result`.

## Which edits are control updates only

Use the control path when the graph topology and control declarations are
unchanged and only runtime values change:

- `GraphOperation::SetParam`-style edits for an already declared parameter;
- `GraphControl::set_param`, `gate_on`, and `gate_off` targeting live authoring
  indices;
- Mini/pattern `ControlMap` events resolved through the current
  `ControlBindingMap`;
- scheduler live voice-control edits that target already-sounding voices.

Control update flow:

```text
stable control key or stable target node ID
  -> current GraphIndexMap / ControlBindingMap
  -> GraphControl batch
  -> runtime validation / preflight
  -> transactional block-boundary apply
```

A valid control batch does not rebuild the template. An invalid batch rejects
transactionally: none of its controls are applied, no graph recompilation is
attempted, and the preview reports a control diagnostic. During an in-flight
hot-swap, controls must validate against both active and pending graphs; if
either graph rejects the batch, neither graph is mutated.

## Diagnostic mapping for Canopy

Canopy should keep source mapping data alongside each authoring revision:

- stable node ID -> current authoring index;
- authoring index -> stable node ID;
- stable node ID -> source ranges for the node, each input slot, and each
  parameter slot;
- stable control key -> declaration source range and target stable node ID/slot;
- edit-batch item -> source range for topology controller diagnostics.

Use those maps as follows:

- Parser, projection, name-resolution, and semantic-lowering errors are Canopy
  diagnostics. Report them directly from the source/projection layer and stop
  before constructing `Array[DspNode]`.
- `ControlBindingError` reports a key or authoring index. Map keys through the
  control declaration table, and map indices through authoring index -> stable
  node ID -> source range.
- `GraphCompileError` node indices are original authoring indices when MoonDsp
  can map them back. Map the index to a stable node ID, then to the narrowest
  known source range for the reported input slot or `GraphParamSlot`. Global
  compile errors such as missing/multiple outputs should highlight the graph or
  terminal declaration region.
- `GraphControlError` reports the current authoring index and slot/kind. Map it
  through the active preview revision's index map and show it as a rejected
  parameter update, not as a topology failure.
- `GraphTopologyQueueError::InvalidEdit(batch_index, reason)` maps first to the
  source range of the submitted edit operation, then to stable node IDs carried
  by that operation. If the queue reports `RecompileRejected`, reproduce the
  candidate snapshot through `compile_result` for source-mappable details when
  the UI needs a precise diagnostic.

`CompiledTemplate::analyze` itself is infallible and does not validate source
language semantics or numeric parameter domains. Diagnostics shown in the
`Analyzing` state therefore come from the editor's own analysis/lowering,
control-binding validation, compile diagnostics, runtime-control validation, or
queue/staging APIs.

## Staged preview example

A typical external UI edit should follow this shape:

1. User inserts a filter or clip node in Canopy.
2. Canopy updates its normalized graph, stable IDs, and source-range maps.
3. On the control side, Canopy lowers the valid snapshot to `Array[DspNode]`,
   analyzes it, rebuilds bindings from stable control declarations, and calls
   `compile_result`.
4. If compile succeeds, Canopy queues a hot-swap or replaces the bound voice
   pool's prepared template. The audio callback observes the replacement only at
   the next block boundary.
5. If compile fails, Canopy enters `UsingLastGoodTemplate` when a previous
   runtime exists, or `Failed` when none exists, and maps diagnostics through
   the authoring index/stable-ID/source-range tables.
6. If the user then turns a knob for an already declared gain/cutoff/frequency,
   Canopy resolves the stable ID or control key to a `GraphControl` and applies
   the control batch at a block boundary without rebuilding the graph.

The checked fixture in `editor_preview_handoff_test.mbt` exercises this pattern:
it builds a stable-ID `GraphTemplateDoc`, stages an append-only topology
replacement through `CompiledDspHotSwap::queue_swap`, applies a stable-ID
parameter update while the replacement is pending, and verifies that a failed
candidate maps its compile diagnostic back to the authoring node ID while the
last-good runtime remains usable.
