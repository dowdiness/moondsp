# DSP Structural Editor Vision

Date: 2026-03-31
Status: Draft

## 1. Goal

Design a text-shaped DSP authoring experience for `mdsp` that preserves
node-level collaborative semantics and permanent structural identity without
making raw source text the canonical source of truth.

This document is intentionally a vision document, not an execution plan. It
captures direction, principles, and desired properties. It does not claim that
all details are finalized or implementation-ready.

## 2. Why This Exists

`mdsp` already has a strong runtime-side story:

- declarative graph authoring through `DspNode`
- graph construction through `GraphBuilder`
- compiled mono and stereo graph runtimes
- runtime control through `GraphControl`
- narrow runtime topology updates through `GraphTopologyEdit`
- hot-swap wrappers for graph replacement

What it does not yet have is a text-shaped authoring model that can support:

- stable semantic identity across edits
- collaboration at the node level rather than at the character level
- structural editing without reparsing the entire file as the authority path

## 3. Problem Statement

A plain text CRDT plus whole-file parser is not enough for the editor we want.

If text is canonical:

- structure is recovered from parser output rather than owned directly
- wrap, unwrap, reorder, and move operations tend to destroy identity
- concurrent structural edits merge as text, not as structure
- parser recovery can erase semantic continuity

For a collaborative DSP editor, this is the wrong authority boundary.

## 4. Direction

The editor should be structure-first:

- the canonical document is structural
- collaboration operates on structural patches
- text is a projection of the structural document
- local parsing is a bridge from bounded text edits into structure
- lowering into `mdsp` remains a separate runtime boundary

This is the key design move. Everything else follows from it.

## 5. Design Principles

### 5.1 Permanent Identity

Each structural node should have a stable identity that is not derived from text
position.

Moving, wrapping, or reformatting should not by itself destroy identity.

### 5.2 Text as Projection

The user should still be able to work in a text-shaped language, but that text
should be rendered from structure rather than treated as the canonical state.

### 5.3 Native Structural Edits

Topology changes should be native structural operations, not sugar over whole
document text rewrite.

Examples:

- insert node
- delete node
- wrap node
- unwrap node
- rewire input
- move definition

### 5.4 Local Parsing Only

Parsing remains useful, but in a narrower role:

- parse numbers, names, and bounded expressions
- interpret local text edits into structural patches
- validate projections and imports

Whole-file reparsing should not be the primary authority path for identity-
sensitive editing.

### 5.5 Invalid States Must Be Structural

The editor must be able to represent incomplete or invalid states directly in
the document model rather than collapsing back into “broken file text.”

Examples:

- holes
- invalid fields
- dangling references
- missing inputs
- conflict nodes

### 5.6 Runtime Separation

The editor document is not the runtime graph.

The system should maintain a deliberate boundary:

`editor document -> normalized DSP graph -> Array[DspNode] -> compiled runtime`

That preserves the existing `mdsp` architecture rather than replacing it.

## 6. Product Shape

The long-term experience should feel like a text language with structural
awareness rather than a hidden node editor.

That means:

- a readable textual DSL
- structural selections and actions
- stable IDs under projection refresh
- collaboration semantics anchored to nodes and fields
- a path for both text editing and structural editing

## 7. Editing Modes

The editor should eventually support three complementary modes:

### 7.1 Structural Mode

The user performs semantic operations directly on the structure.

### 7.2 Field Text Mode

The user edits bounded textual fields such as:

- names
- numbers
- short parameter expressions

### 7.3 Full Text Projection Mode

The user sees and navigates a full-file textual projection, but edits are
routed through structural regions and field-local parsers rather than through
unrestricted whole-file text authority.

## 8. Relationship to Collaboration

The collaboration model should target nodes, fields, and structural relations,
not just byte ranges.

Presence should eventually point to semantic targets such as:

- node IDs
- field IDs
- edges or slots

Projected text spans are a rendering convenience, not the primary collaboration
anchor.

## 9. Relationship to `mdsp`

This work should complement the existing runtime rather than disturb it.

The editor layer should lower into the current `mdsp` graph model and then
reuse the current runtime capabilities:

- `GraphControl` for supported runtime parameter changes
- `GraphTopologyEdit` for narrow structural runtime edits
- full compile plus hot-swap when needed

The editor is allowed to represent states the current runtime does not accept.
Validation and lowering are responsible for reporting that mismatch clearly.

## 10. First-Language Shape

The first usable DSP text form should be explicit and structural.

A shape like this is preferred:

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

This is a better starting point than a dense expression-only syntax because it
makes:

- node boundaries explicit
- references legible
- identity preservation easier
- topology edits easier to model

## 11. Non-Goals for the First Iteration

The vision does not require the first iteration to solve:

- unrestricted whole-file raw text editing with full identity preservation
- complete collaborative structural conflict calculus
- a final UI design
- a fully general DSP surface syntax

The first iteration only needs to prove that structure-first editing can coexist
with a text-shaped language and the current `mdsp` runtime.

## 12. Success Criteria

This vision is on the right track if the eventual system can demonstrate:

- permanent node identity across ordinary edits
- a readable text projection
- native structural topology edits
- bounded local text parsing into structure
- lowering into the current `mdsp` graph/runtime stack
- collaboration anchored to semantic structure instead of byte offsets

