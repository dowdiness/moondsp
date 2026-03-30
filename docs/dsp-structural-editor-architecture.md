# DSP Structural Editor Architecture

Date: 2026-03-31
Status: Draft

## 1. Purpose

This document describes the proposed architecture for a structure-first DSP
editor for `mdsp`.

Unlike the companion vision document, this document is intended to define the
main model boundaries and contracts. It is still draft-level architecture, not
yet a v1 implementation plan.

## 2. Architectural Boundary

The architecture is:

```text
StructuralDoc
  -> Projection(text + source map)
  -> Local text edit bridge
  -> NormalizedDslGraph
  -> Array[DspNode]
  -> CompiledDsp / CompiledStereoDsp
```

The important constraint is that `StructuralDoc`, not raw text, is canonical.

## 3. Canonical Model

### 3.1 Core IDs

The document model needs permanent identifiers for:

- `DocId`
- `NodeId`
- `EdgeId`
- `FieldId`

These IDs must not be derived from text position.

### 3.2 Conceptual Document Shape

The document model should represent:

- DSP definitions
- DSP topology
- local field values
- embedded expression subtrees
- placeholders and invalid states

The exact final representation is not yet fixed, but the architecture assumes:

- topology is represented structurally rather than reconstructed from raw text
- field-local expressions are distinct from graph-level topology

### 3.3 Suggested Node Shape

The architecture expects something conceptually like:

```text
Node {
  id       : NodeId
  kind     : DspCtor
  fields   : Map[FieldKey, FieldValue]
  children : Array[ChildRef]
  attrs    : NodeAttrs
}
```

This is a design shape, not a final API.

### 3.4 Structural Identity Rules

The architecture depends on these invariants:

- `NodeId` is stable across formatting changes
- moving a node does not change its ID
- wrapping allocates a new wrapper ID while preserving wrapped descendants
- unwrapping preserves the promoted descendant where semantically valid
- identity is not recomputed from whole-file parser position

## 4. Structural Patch Layer

### 4.1 Role

All structural edits and collaboration events should operate on structural
patches rather than on whole-file text diffs.

### 4.2 Minimum Patch Concepts

The architecture expects patch operations equivalent to:

- create node
- set field
- insert child / edge
- delete edge
- move child / edge
- replace subtree
- set presence
- resolve conflict

The exact API names can change, but the patch layer must operate on semantic IDs
and remain valid independently of text rendering.

### 4.3 Deletion Model

Deletion should be modeled as structural disconnection or replacement rather
than simple identity erasure.

This is required for:

- history
- reconciliation
- stable editor state

The exact orphan/garbage-collection policy remains open and should be specified
before implementation begins.

## 5. Projection Layer

### 5.1 Role

The projection layer renders the canonical structural document into a textual
DSL view.

Projection result:

```text
Projection {
  text       : String
  source_map : SourceMap
}
```

### 5.2 Source Map Contract

The source map must allow the editor to recover structural targets from text
positions.

At minimum it should support mapping:

- text span -> node
- text span -> field
- text span -> structural role where relevant

The architecture assumes that text navigation and selection can be translated
back into structural targets.

### 5.3 Projection Properties

Projection should be:

- deterministic for the same structural document
- stable enough to preserve orientation across refresh
- able to recover editable regions without full reparsing

Because text is projected, whitespace normalization and formatting changes do
not alter semantic identity.

## 6. Editing Model

### 6.1 Structural Editing

Structural actions operate directly on the canonical document.

Examples:

- insert node
- delete node
- wrap or unwrap node
- rewire input
- move definition

These edits bypass whole-file text rewriting as the source of truth.

### 6.2 Field-Local Text Editing

Text editing is still supported, but at bounded scopes such as:

- numeric parameters
- names
- small embedded expressions

Field-local text edits are interpreted by local parsers and translated into
structural patches.

### 6.3 Full Text View

The architecture allows a full-file text view, but it should be treated as a
projection-driven interface rather than as an unrestricted canonical text
buffer.

Unsupported free-form edits are not yet architecturally fixed. They may
eventually be:

- rejected
- converted into invalid-field states
- handled through explicit raw-text islands

That policy must be chosen before implementation.

## 7. Parse Bridge

### 7.1 Purpose

Parsing is used to interpret bounded text edits into structure.

It is not the authority for structural identity.

### 7.2 Expected Inputs

The parse bridge should support bounded regions such as:

- literal fields
- identifier fields
- parameter-expression fields
- narrow, explicitly owned text blocks

### 7.3 Expected Outputs

A parse bridge should yield one of:

- an updated field value
- a replacement expression subtree
- an invalid-field result
- a placeholder or hole state

### 7.4 Identity Preservation

When local parsing yields a replacement subtree, identity should be preserved by
semantic role rather than by raw position alone.

This is a hard architectural requirement even though the exact matching
algorithm remains open.

## 8. Invalid-State Model

The architecture requires structural representations for unresolved states.

Important categories include:

- `Hole`
- `InvalidField`
- `DanglingRef`
- `MissingInput`
- `Conflict`

This allows the editor to remain structure-first even when user text is
incomplete or invalid.

## 9. Lowering Boundary

### 9.1 Normalization

Before lowering to `mdsp`, the structural document should be normalized into a
runtime-facing DSP graph form.

Expected responsibilities:

- resolve named references
- validate required inputs
- identify runtime-updatable parameters
- preserve a mapping from structural IDs to lowered graph entities

### 9.2 `DspNode` Lowering

The normalized graph then lowers to `Array[DspNode]`.

This lowering stage should be deterministic and intentionally narrower than the
editor document model. The editor may represent states that the runtime cannot
compile yet.

## 10. Runtime Integration

### 10.1 Existing Runtime Paths

The architecture assumes reuse of current runtime update paths:

- `GraphControl`
- `GraphTopologyEdit`
- full compile plus hot swap

### 10.2 Structural ID to Runtime Mapping

Because the current runtime APIs target authoring-order node indices, the
editor/runtime bridge must maintain a per-version mapping:

```text
NodeId -> authoring_index
```

This keeps the editor model ID-based while allowing reuse of current runtime
APIs.

### 10.3 Update Classification

The runtime bridge should prefer:

1. `GraphControl`
2. `GraphTopologyEdit`
3. full replacement

This depends on a later diff layer, but the architecture assumes that the
editor model will not expose runtime indices to users.

## 11. Collaboration Model

The collaboration target should be semantic structure rather than byte ranges.

Presence and edits should eventually target:

- nodes
- fields
- structural relations

Text spans remain projection-level conveniences for rendering and selection.

The exact conflict calculus is still open. The architecture only assumes that
structural conflicts must not be silently reduced to plain text merges.

## 12. First DSL Shape

The architecture favors an explicit DSL shape for the first usable version:

```text
node main = osc sine {
  freq = 440
}

node amp = gain {
  input = main
  amount = 0.2
}

output master = amp
```

This shape is preferred because it provides:

- explicit node boundaries
- explicit fields
- explicit references
- a clear separation between topology and local values

## 13. Open Architectural Questions

The following questions remain open and should be resolved before a concrete v1
plan is written:

- whether the canonical topology model is tree-shaped, explicit-edge, or hybrid
- how orphaned nodes and garbage collection are handled without weakening
  permanent identity guarantees
- how comments and user formatting choices are represented in a projection-first
  system
- what source-map ownership rules apply to punctuation, whitespace, and repeated
  references
- what unsupported full-text edits do in the first implementation
- what exact matching rules define semantic-role identity preservation
- what subset of structural changes are eligible for `GraphTopologyEdit`

## 14. Non-Goals of This Document

This architecture document does not define:

- a final patch wire format
- a final UI
- a full collaboration conflict calculus
- a concrete v1 milestone plan
- the exact MoonBit file/module layout

Those belong in later design or planning documents once the open architectural
questions above are resolved.

