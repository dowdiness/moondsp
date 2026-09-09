# ADR-0006: Scheduler note deadlines preserve their time domain

- **Status:** Accepted
- **Updated:** 2026-09-09

## Context

Pattern composition uses rational musical time. Voice rendering uses integer
sample positions. A tempo edit must preserve the music already played while
changing how much physical time remains until a musical boundary. A deadline
expressed in seconds must stay fixed instead.

## Decision

Keep a sounding note's musical endpoint when its duration belongs to musical
time. Cache the corresponding sample deadline for rendering. Recompute that
cache when tempo changes. Notes with physical deadlines retain their samples.
A released note is no longer eligible for retiming.

Use one clock conversion anchored at the next unrendered sample and the
musical position reached there. Tempo changes preserve the anchor and affect
only subsequent progression. Conversion decisions are deterministic; the
scheduler owns voice mutation and audio rendering.

Preflight a tempo change before changing the clock or any active deadline.
Browser routes sharing the transport must accept or reject it together.

Render note starts and gate-offs at their sample boundaries inside each block.
Round a fractional boundary upward to the first sample at or after it. Retain
an onset rounded into the next block so querying half-open musical spans does
not lose it. Changing tempo does not retrigger or retune a sounding voice.

## Consequences

- Musical and physical durations respond differently to tempo edits by design.
- The render loop uses sample deadlines while composition retains musical time.
- Segment buffers are allocated before rendering. Pattern queries and dispatch
  still require a separate allocation audit.
- Numeric conversion has explicit precision and range limits. It reports
  unrepresentable input instead of wrapping integers.
- Pattern-entry edit boundaries, nested clock domains, groove, and rubato
  remain separate work. They must preserve endpoint ownership when added.

The current API, numeric limits, and render error behavior are documented in
[the scheduler guide](../../scheduler/README.mbt.md#transport).
