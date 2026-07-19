# Control-aware partial evaluation

- **Status:** Exploratory; not approved for implementation
- **Recorded:** 2026-07-19
- **Context:** [PR #228](https://github.com/dowdiness/moondsp/pull/228)
- **Evidence:** [runtime-control constant-fold barrier snapshot](performance/2026-07-19-runtime-control-constant-fold-barriers.md)

## Question

Must an authoring control point and the DSP operation executed for every sample
remain the same runtime object?

The current safe answer is yes: a foldable node that exposes an authored
runtime parameter remains in the execution graph. This preserves control
identity, binding semantics, reset behavior, and authoring-index diagnostics.
It also retains that node's per-sample buffer pass.

The possible future answer is no. Authoring identity, control dependency, and
sample-by-sample execution can be represented separately. A compiler could
then preserve a control point while partially evaluating its constant signal
region.

This note records that direction for later evaluation. It is not an ADR and
does not supersede current runtime-control behavior.

## Current safe design

Constant folding may eliminate a pure constant region. It must not replace a
runtime-updatable control point with an execution value that no longer
preserves the authored control contract.

Dependencies that are independent of runtime control may still fold beneath a
retained control point. The retained control is intentionally conservative: it
makes correctness local and keeps runtime updates, bindings, reset, lifecycle,
and topology contracts coherent.

## Motivation for revisiting

Retaining a control point also retains its per-sample execution cost. The
current isolated evidence shows a bounded single-control cost, but generated
graphs or concurrent processing may accumulate many such costs. See the linked
performance snapshot for implementation-specific cases and measurements.

Controls whose inputs depend on sample data were never constant-fold
candidates. The opportunity is limited to runtime-updatable controls inside
otherwise constant regions.

## Proposed separation

Treat compilation as producing three conceptual artifacts:

1. **Authoring control model** — preserves stable authoring identity, parameter
   defaults, validation rules, binding targets, and diagnostics.
2. **Control dependency plan** — records which derived scalar values or
   execution-plan patches depend on each authored control.
3. **Optimized execution plan** — contains only the operations required for
   sample processing, including partially evaluated constants.

Under this model, a runtime update recomputes only the derived values that
depend on the changed authored parameter. The authored control remains valid
even when its corresponding operation is absent from per-sample execution.

## Functional core and imperative shell

The design should keep decisions deterministic and isolate publication at the
runtime boundary.

The functional core would own:

- analysis of constant regions and their runtime-control dependencies;
- validation of control batches against authoring semantics;
- the transition from control state plus a control batch to new control state
  plus a dirty dependency set;
- recomputation of affected derived scalars;
- creation of an immutable execution-plan patch or structured diagnostic.

The imperative shell would own:

- receiving runtime control messages;
- scheduling recomputation outside the audio callback where possible;
- publishing a complete patch at a block boundary;
- revision checks, cancellation, hot-swap lifecycle, and topology lifecycle;
- pre-allocation and ownership of any audio-thread-visible storage.

The audio callback must never observe a partially applied control batch.

## Required invariants

Any implementation must preserve all of the following:

- **Authoring identity:** a control continues to target its authored parameter
  even when the corresponding DSP operation is absent from the execution plan.
- **Transactional batches:** either every control and dependent value in a
  batch becomes visible together, or none does.
- **Reset fidelity:** reset restores authored defaults and all derived values,
  not merely the latest execution-plan constants.
- **Orphan semantics:** genuinely unreachable authoring nodes and bindings
  retain their existing orphan errors.
- **Validation parity:** parameter kind, slot, range, and finiteness checks
  remain identical to the non-specialized path.
- **Revision safety:** a patch computed for an old topology or hot-swap
  revision cannot update a newer execution plan.
- **Mono/stereo parity:** specialization cannot change routing or signal shape.
- **Feedback safety:** cyclic, stateful, or sample-dependent regions are never
  treated as control-time scalar recipes.
- **Audio-thread safety:** processing performs no allocation, locking, graph
  traversal, or unbounded recomputation.
- **Determinism:** the same authoring snapshot and ordered control batches
  produce the same derived values and execution state.

## Eligibility

A region is a candidate only when every value in the region can be recomputed
from immutable literals and authored runtime parameters without reading sample
buffers or mutable DSP state.

Do not specialize a region that contains:

- sample-dependent, stateful, time-dependent, or nondeterministic operations;
- sample buffers or signal-dependent branches;
- topology-dependent routing that can change signal shape;
- invalid parameters whose rejection would otherwise be observable;
- a dependency cycle between derived controls.

When eligibility is uncertain, retain the original runtime node.

## Control update sequence

A candidate implementation should behave conceptually as follows:

```text
control batch
  -> validate against authoring control model
  -> compute next control state and dirty dependency set
  -> recompute affected derived scalars
  -> build a revision-tagged immutable patch
  -> publish the complete patch at a block boundary
  -> audio callback reads the new derived values
```

Recomputation must be proportional to the affected dependency region, not the
entire authoring graph. Duplicate dependencies within a batch should be
coalesced before recomputation.

## Alternatives

### Retain runtime nodes

This is the current design. It is simple, locally correct, and predictable.
Keep it unless measurements demonstrate a meaningful cost.

### Recompile the complete graph after each control update

This restores folding but expands control latency, allocation, revision, and
hot-swap complexity. It is unsuitable as the default response to frequent
controls.

### Control-aware partial evaluation

This is the preferred candidate if optimization becomes necessary. It retains
control semantics while limiting recomputation to dependent constant regions.
Its cost is additional compiler metadata and lifecycle logic.

### Specialized generated DSP code

Generating or patching target-specific code could remove more dispatch, but it
would substantially increase backend, validation, and deployment complexity.
Do not begin here.

## Evidence required before implementation

Do not implement this design from a single-control result alone. First add
repeatable scaling measurements across:

- low through stress-level counts of affected controls and concurrent work;
- simple and composed constant dependency regions;
- sparse and dense control updates;
- individual controls and transactional batches;
- reset, lifecycle replacement, and topology replacement;
- every production execution target.

Record absolute processing time, the share of the real-time budget, update
latency, allocation behavior, and worst-case variance. Compare retained-control
processing with a prototype dependency-recompute path under equivalent
workloads.

## Revisit criteria

Revisit this design when at least one of these is true:

- representative production or generated graphs spend a material, agreed
  share of the real-time budget on affected retained controls;
- retained barriers contribute to a reproduced missed-deadline or voice-count
  limit;
- a real authoring workflow routinely produces enough controls in constant
  regions to create measurable cumulative cost;
- another feature already requires an explicit authored-control dependency
  plan, making partial evaluation an incremental addition rather than a new
  subsystem.

Do not proceed based only on a large relative percentage against a trivial
baseline.

## Suggested delivery slices

If a revisit criterion is met:

1. Add scaling benchmarks without changing runtime behavior.
2. Prototype pure constant-region analysis and dependency recipes behind an
   internal boundary.
3. Prove control, reset, orphan, batch, and revision semantics with
   deterministic tests.
4. Benchmark the prototype against retained nodes on representative graphs.
5. Add block-boundary patch publication with pre-allocated runtime storage.
6. Adopt the specialized path only for proven-eligible regions, retaining the
   current barrier path as the fallback.
7. Write an ADR only after the prototype demonstrates correctness and a
   meaningful performance benefit.

## Open questions

- Which representation should own derived values without exposing mutable
  compiler internals?
- Which host execution context owns dependency recomputation?
- How should control smoothing interact with a value that would otherwise be
  constant between updates?
- Can one dependency representation serve reset, hot-swap state inheritance,
  topology edits, and future incremental authoring without coupling them?
- What revision granularity prevents stale publication without forcing a full
  plan rebuild?
- At what update frequency does retaining the runtime operation become cheaper
  than repeated control-time recomputation?
