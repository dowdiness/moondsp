# ADR-0017: Mini authoring AcceptedDerived adoption

- **Status:** Accepted (2026-07-08, PR #227)
- **Date:** 2026-07-08
- **Source:**
  [Mini authoring AcceptedDerived migration plan](../plans/2026-07-07-mini-authoring-accepted-derived-migration.md)

## Context

The mini authoring pipeline has two different notions of a parsed document:

- the current candidate, which must report an error for invalid source; and
- the last valid document, which remains useful while the current source is
  invalid.

ADR-0011 initially kept the last successful document as mutable parser state.
That state preserved identity across later valid edits, but it also implicitly
held the last-good value. The two responsibilities have different lifetimes:
identity reuse belongs to parsing, while last-good retention is an acceptance
policy for consumers.

The incremental runtime now provides an accepted-derived primitive for this
policy. It tracks a fallible candidate, retains only successful values, and
uses authoring equality to avoid reporting equivalent accepted values as new.

## Decision

Add a separate accepted channel to the existing mini authoring pipeline.

The current channel remains authoritative for the current source. Invalid
source continues to produce an error there. The accepted channel retains the
latest successful authoring document and returns no value until the first
successful parse.

Keep the parser's previous successful document as candidate-local state solely
for stable identity reuse. A parse failure must update neither that reuse
baseline nor the accepted channel.

Prime the initial candidate before constructing the eager accepted fold. The
candidate mutates its private reuse baseline after a successful parse, so that
mutation must occur outside a reactive compute context. Later candidate reads
remain lazy.

## Relationship to prior ADRs

- **ADR-0011 is extended, not superseded.** Its incremental authoring pipeline,
  whole-document parsing, stable-identity reuse, and persistent lowering cache
  remain the production architecture. This ADR separates last-good retention
  from the parser's reuse state.
- **ADR-0013 remains in force for authoring promotion.** Adding an accepted
  channel does not route production authoring through loom or close any loom
  promotion gate.
- **ADR-0016 is unaffected.** The loom-backed runtime parser and the
  hand-written authoring parser retain separate boundaries.

## Consequences

**Positive**

- Current-source validity and last-good availability have explicit, separate
  semantics.
- Invalid edits remain visible without discarding the latest usable document.
- Stable authoring identity and lowering-cache reuse keep their existing parser
  contract.
- The authoring path exercises the same acceptance model intended for a future
  incremental parser migration.

**Negative**

- The pipeline retains both an accepted value and a parser reuse baseline.
  They intentionally contain related data but have different responsibilities.
- Construction performs one eager parse to establish a safe baseline before
  accepted tracking begins.
- Consumers must choose deliberately between the current and accepted channels.

## Non-goals

- Moving production authoring to loom.
- Changing the current parse result or public error shape.
- Adding accepted snapshot, observation, or revision-time APIs.
- Removing parser-local previous-document state while stable identity reuse
  depends on it.

## Revisit when

Re-evaluate this decision when the authoring path moves to loom, when the
incremental runtime changes its acceptance contract, or when the planned loom
authoring campaign is retired. Keep the accepted channel only if it remains the
single last-good policy at the authoring boundary; otherwise remove or replace
it rather than maintaining two competing acceptance mechanisms.
