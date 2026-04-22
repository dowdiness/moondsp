# Architecture Decision Records

Short, dated records of architectural decisions in `dowdiness/moondsp`. Each
ADR captures **what** was decided and **why**, so future readers (including
the original authors) can understand the reasoning without re-reading the
shipped plan or spec.

## Conventions

- One decision per file. Numbered sequentially: `NNNN-kebab-title.md`.
- Status values: `Proposed`, `Accepted`, `Superseded by ADR-NNNN`, `Rejected`.
- Source links point to the original plan or spec under
  `docs/superpowers/{plans,specs}/archive/`. The plan/spec is the design
  artifact; the ADR is the durable summary.
- An ADR is updated when the decision is **superseded** (record under a new
  ADR and mark the old one) — not when implementation evolves around it.

## Index

- [ADR-0001 — Layered package architecture](0001-layered-package-architecture.md)
- [ADR-0002 — Generic GraphSlot for browser variants](0002-graph-slot-capability-trait.md)
- [ADR-0003 — CompiledTemplate topology artifact](0003-compiled-template-topology-artifact.md)
- [ADR-0004 — Hand-written mini-notation parser](0004-handwritten-mini-notation-parser.md)
