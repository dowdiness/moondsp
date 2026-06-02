# Architecture Decision Records

Short, dated records of architectural decisions in `dowdiness/moondsp`. Each
ADR captures **what** was decided and **why**, so future readers (including
the original authors) can understand the reasoning without re-reading the
shipped plan or spec.

## Conventions

- One decision per file. Numbered sequentially: `NNNN-kebab-title.md`.
- Status values: `Proposed`, `Accepted`, `Superseded by ADR-NNNN`, `Rejected`.
- Source links usually point to the original plan or spec under
  `docs/superpowers/{plans,specs}/archive/`. When a decision originates in a
  PR discussion without an archived plan, link or name that PR instead. The
  plan/spec/PR is the design artifact; the ADR is the durable summary.
- An ADR is updated when the decision is **superseded** (record under a new
  ADR and mark the old one) — not when implementation evolves around it.

## Index

- [ADR-0001 — Layered package architecture](0001-layered-package-architecture.md)
- [ADR-0002 — Generic GraphSlot for browser variants](0002-graph-slot-capability-trait.md)
- [ADR-0003 — CompiledTemplate topology artifact](0003-compiled-template-topology-artifact.md)
- [ADR-0004 — Hand-written mini-notation parser](0004-handwritten-mini-notation-parser.md)
- [ADR-0005 — Song sections as the long-form structure layer](0005-song-section-layer.md)
- [ADR-0006 — Scheduler note expiry uses performance time](0006-scheduler-performance-time-expiry.md)
- [ADR-0007 — ControlMap keeps a map-backed accessor surface](0007-control-map-accessor-surface.md)
- [ADR-0008 — Contiguous song layout with computed occurrences](0008-contiguous-song-layout.md)
- [ADR-0009 — Stable identity groundwork for Phase 6](0009-stable-identity-groundwork.md)
- [ADR-0010 — CompiledTemplate as the runtime exchange boundary](0010-compiled-template-runtime-boundary.md)
- [ADR-0011 — Incr-backed mini authoring pipeline](0011-incr-backed-mini-authoring-pipeline.md)
- [ADR-0012 — Loom/CST evaluation for mini authoring](0012-loom-cst-mini-authoring-evaluation.md)
- [ADR-0013 — Loom promotion criteria for mini authoring](0013-loom-promotion-criteria-for-mini-authoring.md)
- [ADR-0014 — Authoring equality and typed graph compile diagnostics](0014-dspnode-compiledtemplate-equality-and-compile-errors.md)
