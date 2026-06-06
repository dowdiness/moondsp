# Graph facade/internal model parity

`graph/internal/model` is the canonical owner of raw graph-node storage and
node-kind semantics. The public `graph/` package intentionally does **not**
re-export that raw model surface directly. It keeps graph-owned wrappers so the
supported downstream import path and generated interface stay anchored at
`dowdiness/moondsp/graph`.

## Compatibility policy

| Duplicated concept | Policy | Rationale |
| --- | --- | --- |
| `DspNode` | Keep wrapped by the public facade. | `Array[DspNode]` is the authoring exchange type from ADR-0010. The facade owns the supported origin path while raw storage remains internal. |
| `DspNodeKind` | Keep a facade enum mirrored from the model enum. | Public compile/control/topology errors mention node kinds; those signatures should stay graph-owned. Exhaustive conversion catches new model variants. |
| `GraphParamSlot` | Keep a facade enum mirrored from the model enum. | Slots appear in public controls, bindings, and errors. The facade maps slots to the model at package boundaries. |
| `GraphControl` | Keep wrapped by the public facade. | Runtime control messages cross into model/runtime internals, but callers should construct and inspect them through `graph/`. |
| `GraphControlKind` | Keep a facade enum mirrored from the model enum. | The public facade exposes stable read-only control classification without exposing internal control storage. |
| `NodeSpanning`, `NodeFoldable`, `NodeStateful`, `NodeEditable` | Keep facade traits mirrored from model traits. | Public capability traits remain graph-owned and delegate to model semantics for `DspNode`. |
| Internal model helpers (`node_with_*`, `remap_node_inputs`, validation helpers) | Do not re-export unless a concrete public use case appears. | They are implementation hooks for template/runtime/staging internals, not downstream authoring API. |

This is a deliberate wrapper policy, not accidental duplication. If a future
change re-exports any of these model types, review `graph/pkg.generated.mbti`
for origin-path drift and update this document together with ADR-0015 if the
public compatibility policy changes.

## Conversion inventory

| Conversion/wrapper | Direction | Expected status |
| --- | --- | --- |
| `DspNode::from_model` / `DspNode::raw` | model ↔ facade | Private bridge for facade/runtime/template/staging code. |
| `GraphControl::from_model` / `GraphControl::raw` | model ↔ facade | Private bridge for control binding, identity, runtime, and staging code. |
| `dsp_node_kind_from_model` | model → facade | Exhaustive mapping for public errors, accessors, and tests. |
| `GraphParamSlot::to_model` | facade → model | Exhaustive mapping for controls, bindings, and identity helpers. |
| `graph_param_slot_from_model` | model → facade | Exhaustive mapping for public controls, bindings, and errors. |
| `graph_control_kind_from_model` | model → facade | Exhaustive mapping for public `GraphControl::kind`. |
| `dsp_nodes_to_model` / `dsp_nodes_from_model` | array bridge | Private bridge at `CompiledTemplate` and authoring/topology boundaries. |
| `node_accepts_slot` facade function | facade → model | Public forwarding function; parity is checked against model behavior. |
| Node trait impls for facade `DspNode` | facade → model | Public trait surface delegates to model `node_*` semantics. |

## Guardrails

- `graph/graph_model_facade_parity_wbtest.mbt` checks constructor forwarding,
  enum conversion, control conversion, slot acceptance, and trait behavior
  against `graph/internal/model`.
- `scripts/check-graph-model-facade-parity.sh` parses generated `.mbti` files
  and fails when mirrored variants, public `DspNode`/`GraphControl` methods,
  `node_accepts_slot`, or Node trait shapes drift.
- `scripts/check-architecture-boundaries.sh` runs the parity script so regular
  boundary validation catches facade/model drift.

When adding a graph node kind, slot, control variant, or public model method,
update the internal model, public facade conversion/wrapper, parity tests, and
then run:

```bash
moon check
moon test
moon info
scripts/check-public-boundary.sh
scripts/check-architecture-boundaries.sh
```
