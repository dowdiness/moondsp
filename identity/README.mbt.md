# Stable authoring identity

`identity` provides dependency-free, type-safe IDs and revision tokens for
incremental editing. Pattern, song, and graph packages can share this vocabulary
without depending on one another.

IDs identify authoring intent rather than array position. Reordering, formatting,
or rebuilding an object should preserve its ID when it still represents the
same authored object.

## Architecture context

In moondsp's layered design, `identity` is a foundational leaf package
providing identity types for structural live editing:

```text
[ graph ] (GraphTemplateDoc, GraphIndexMap)
   ↓ uses GraphNodeId, Revision
[ identity ] ← (stable node identities & revision tokens)
   ↑ uses PatternNodeId, Revision
[ pattern ] (PatternDoc, PatternSnapshot)
```

- **Upstream consumers**: [`graph/`](../graph/) uses `GraphNodeId` and
  `Revision` for template document editing and hot-swap; [`pattern/`](../pattern/)
  uses `PatternNodeId` and `Revision` for incremental pattern tree lowering;
  [`song/`](../song/) uses `SectionId`, `SectionLayerId`, and `OccurrenceId`.
- **Downstream dependencies**: None. `identity` is a pure leaf package with no
  external dependencies.

## API quick reference

| Category | Types | Key operations |
|---|---|---|
| **Graph Identity** | `GraphNodeId` | `GraphNodeId::from_string`, `GraphNodeId::value` |
| **Pattern Identity** | `PatternNodeId` | `PatternNodeId::from_string`, `PatternNodeId::value` |
| **Song & Section Identity** | `SectionId`, `SectionLayerId`, `OccurrenceId` | `SectionId::from_string`, `SectionLayerId::from_string`, `OccurrenceId::from_string` |
| **Revisions** | `Revision` | `Revision::zero`, `Revision::next`, `Revision::value`, `Revision::combine`, `Revision::max` |
| **Errors** | `StableIdError` | `StableIdError::EmptyId`, `StableIdError::InvalidId` |

## Choose the ID type by role

The wrappers prevent IDs from unrelated domains from being mixed accidentally.

| Type | Identifies |
|---|---|
| `PatternNodeId` | A node in an authored pattern tree |
| `SectionId` | A reusable section definition |
| `SectionLayerId` | A named layer inside a section |
| `OccurrenceId` | One placement of a section in a song |
| `GraphNodeId` | An authored DSP graph node |

Create IDs with `from_string` and recover their serialized form with `value`.

```mbt check
///|
test "create typed stable IDs" {
  let pattern = @identity.PatternNodeId::from_string("pattern:intro_1")
  let section = @identity.SectionId::from_string("section.intro")
  let layer = @identity.SectionLayerId::from_string("layer-main")
  let occurrence = @identity.OccurrenceId::from_string("verse:2")
  let graph = @identity.GraphNodeId::from_string("graph.node_3")

  @debug.assert_eq(pattern.value(), "pattern:intro_1")
  @debug.assert_eq(section.value(), "section.intro")
  @debug.assert_eq(layer.value(), "layer-main")
  @debug.assert_eq(occurrence.value(), "verse:2")
  @debug.assert_eq(graph.value(), "graph.node_3")
}
```

The tuple constructors are intentionally not the public construction path.
Named constructors keep validation at the boundary and preserve room for the
representation to change.

## Portable ID strings

Every ID type applies the same validation rule. Values must be non-empty and
contain only:

- ASCII letters `A-Z` and `a-z`;
- digits `0-9`;
- `_`, `-`, `.`, or `:`.

Whitespace, slashes, Unicode letters, and other punctuation are rejected. This
restricted alphabet is safe to persist across authoring formats and host
boundaries without type-specific escaping rules.

```mbt check
///|
test "reject invalid stable IDs" {
  let empty = try {
    let _ = @identity.SectionId::from_string("")
    None
  } catch {
    error => Some(error)
  }
  assert_true(empty is Some(@identity.StableIdError::EmptyId))

  let invalid = try {
    let _ = @identity.GraphNodeId::from_string("oscillator 1")
    None
  } catch {
    error => Some(error)
  }
  assert_true(
    invalid is Some(@identity.StableIdError::InvalidId("oscillator 1")),
  )
}
```

`InvalidId` retains the rejected string so a parser or editor can report the
fault at its own boundary.

## Revision tokens

`Revision` identifies a content version. Start a version lineage with `zero`
and call `next` after an accepted change.

```mbt check
///|
test "advance and compare revisions" {
  let initial = @identity.Revision::zero()
  let edited = initial.next()
  let edited_again = edited.next()

  @debug.assert_eq(initial.value(), 0L)
  @debug.assert_eq(edited.value(), 1L)
  @debug.assert_eq(edited_again.value(), 2L)
  assert_true(initial.max(edited_again) == edited_again)
  assert_true(edited_again.max(edited) == edited_again)
}
```

`max` selects the newer token. If two tokens expose the same compact value, it
uses their internal fingerprint to choose deterministically.

### Aggregate revisions

Use `combine` to derive an aggregate token from ordered child revisions. It is
order-sensitive: changing child order changes the aggregate identity.

```mbt check
///|
test "combine ordered child revisions" {
  let first = @identity.Revision::zero().next()
  let second = first.next()
  let forward = first.combine(second)
  let reverse = second.combine(first)

  assert_true(forward != reverse)

  let zero = @identity.Revision::zero()
  let aggregate_zero = zero.combine(zero)
  @debug.assert_eq(aggregate_zero.value(), zero.value())
  assert_true(aggregate_zero != zero)
}
```

The last assertion demonstrates that `value()` exposes compact ordering and
diagnostic data while equality compares the complete token identity. Compare
`Revision` values directly when deciding whether content changed.

## Identity and display names

Stable IDs and user-facing names serve different purposes. A section can be
renamed while preserving its `SectionId`; moving an occurrence can preserve its
`OccurrenceId`; compacting a graph can preserve each surviving `GraphNodeId`.
Generate a new ID only when authoring creates a distinct object.

The package allocates no global IDs and owns no registry. The authoring layer
chooses and persists strings, then passes validated wrappers into downstream
packages.

## Package boundary

`identity` has no dependency on DSP, graph, pattern, song, or scheduler code.
Higher-level packages use it for:

- pattern-node provenance and incremental lowering;
- stable song definitions, layers, and occurrences;
- graph topology edits addressed by authored node identity;
- revision-gated snapshots committed at runtime boundaries.

See [`song/`](../song/), [`graph/`](../graph/), and
[`scheduler/`](../scheduler/) for consumers of these values.
