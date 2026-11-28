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
- [ADR-0006 — Scheduler note deadlines preserve their time domain](0006-scheduler-performance-time-expiry.md)
- [ADR-0007 — ControlMap keeps a map-backed accessor surface](0007-control-map-accessor-surface.md)
- [ADR-0008 — Contiguous song layout with computed occurrences](0008-contiguous-song-layout.md)
- [ADR-0009 — Stable identity groundwork for Phase 6](0009-stable-identity-groundwork.md)
- [ADR-0010 — CompiledTemplate as the runtime exchange boundary](0010-compiled-template-runtime-boundary.md)
- [ADR-0011 — Incr-backed mini authoring pipeline](0011-incr-backed-mini-authoring-pipeline.md)
- [ADR-0012 — Loom/CST evaluation for mini authoring](0012-loom-cst-mini-authoring-evaluation.md)
- [ADR-0013 — Loom promotion criteria for mini authoring](0013-loom-promotion-criteria-for-mini-authoring.md)
- [ADR-0014 — Authoring equality and typed graph compile diagnostics](0014-dspnode-compiledtemplate-equality-and-compile-errors.md)
- [ADR-0015 — Graph, scheduler, and browser internal boundaries](0015-graph-internal-boundaries-and-maintainability.md)
- [ADR-0016 — Loom-backed runtime mini parser](0016-loom-backed-runtime-mini-parser.md)
- [ADR-0017 — Mini authoring AcceptedDerived adoption](0017-mini-authoring-accepted-derived.md)
- [ADR-0018 — Playback visualization follows event origins](0018-playback-visualization-origin-truth.md)
- [ADR-0019 — Parameter automation through automatic control buses](0019-automatic-control-buses.md)
- [ADR-0020 — Controls are typed signals with one representation](0020-controls-as-signals.md)
- [ADR-0021 — Song structure is generic over its content](0021-song-structure-generic-over-content.md)
- [ADR-0022 — Score events carry the sound they play](0022-score-events-carry-their-sound.md) (Proposed)
- [ADR-0023 — The parser owns the score vocabulary](0023-the-parser-owns-the-score-vocabulary.md) (Accepted)
- [ADR-0024 — Each time transform is defined once, for events and signals](0024-time-maps-defined-once.md)
- [ADR-0025 — One-shot signals start where their material enters](0025-one-shot-signals-start-at-entry.md)
- [ADR-0026 — Scores play recorded samples](0026-sample-playback.md)
- [ADR-0027 — Allocation-free trigonometry is a leaf below dsp and Mini](0027-scalar-trig-leaf.md) (Accepted)
- [ADR-0028 — Tracked and untracked material are told apart where an entry is built](0028-tracked-and-untracked-told-apart-at-the-entry.md) (Accepted)
- [ADR-0029 — The player is platform-free, below the browser host](0029-platform-free-player.md) (Accepted)
- [ADR-0030 — Players accept scores, from text or from content](0030-players-accept-scores.md) (Accepted)
- [ADR-0031 — Playback takes one view of a pattern, whatever tracks it](0031-playback-material-is-one-view.md) (Accepted)
- [ADR-0032 — A Mini song's sections and parts are identified by their names](0032-mini-song-identities-are-their-names.md) (Accepted)
- [ADR-0033 — The scheduler decides whether a song can replace the playing one](0033-the-scheduler-decides-what-continues.md) (Accepted)
- [ADR-0034 — A song is built one way, from identified parts](0034-a-song-is-built-one-way.md) (Accepted)
- [ADR-0035 — The scheduler reports observations, the player keeps them typed, the browser encodes them](0035-players-keep-typed-observations.md) (Accepted)
