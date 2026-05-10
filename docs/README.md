# moondsp documentation

This directory holds architecture, reference, performance, and design material
for `dowdiness/moondsp`. Read order below goes roughly from "new user" to
"contributor" to "historical".

## Start here

- **[`../README.md`](../README.md)** — package landing page: quick start, what
  the library does, repository layout, project status.
- **[`../CLAUDE.md`](../CLAUDE.md)** — one-page project map and MoonBit/workflow
  conventions. Useful before editing code.

## Concepts & architecture

- **[`salat-engine-blueprint.md`](salat-engine-blueprint.md)** — full
  architecture vision, design principles, and multi-phase roadmap. Describes
  both what is implemented and what is planned — treat phase labels in the
  blueprint as the roadmap view, and the root README's project-status table as
  the authoritative current-state view.

## Reference (current behavior)

- **[`salat-engine-technical-reference.md`](salat-engine-technical-reference.md)**
  — **authoritative** for graph runtime-control behavior: node types,
  parameter slots, control-binding surface, topology editing, hot-swap. If
  code and any other doc disagree, this document and the code take priority.
- **[`next-actions.md`](next-actions.md)** — active handoff list for future
  sessions. Keep this short and update it when priorities change.
- **[`performance/`](performance/)** — dated benchmark snapshots. New
  measurements go in new files (do not edit historical entries in place).
  Latest:
  [`performance/2026-05-10-post-architecture-redesign-and-jux.md`](performance/2026-05-10-post-architecture-redesign-and-jux.md)
  covers the post-architecture graph hot paths plus dedicated `.jux`
  pattern/mini/scheduler benchmarks.

## Reviews

Point-in-time analyses. Each review is dated and should be moved to
`archive/` once its recommendations have shipped or been rejected, rather
than edited in place.

Currently empty; completed reviews live under [`archive/`](archive/).

## Decisions

- **[`decisions/`](decisions/)** — Architecture Decision Records. Short,
  durable summaries of *why* the codebase looks the way it does. Read these
  before re-litigating a settled architectural choice; the source plan/spec
  for each decision lives under `superpowers/{plans,specs}/archive/`.

## Contributor design docs

Per-feature design briefs and task-level plans. "Current" is what has not
shipped yet; once a feature is merged its design/plan is moved under
`archive/` and should not be read as a description of live behavior.

For the durable architectural rationale behind shipped work, prefer the
ADRs under [`decisions/`](decisions/) — those distill *why* the codebase
looks the way it does, and link back to the specific archived plan/spec
for full context.

- **[`superpowers/specs/`](superpowers/specs/)** — design specs for
  in-flight work. Currently empty; shipped specs live under `archive/`.
- **[`superpowers/plans/`](superpowers/plans/)** — implementation plans
  for in-flight work. Currently empty; shipped plans live under `archive/`.
- `superpowers/specs/archive/` and `superpowers/plans/archive/` — shipped
  features. Historical context only. The `.jux(f)` stereo-split spec and
  implementation plan shipped and now live there.

## Exploratory / vision (not implemented)

These are direction documents, not descriptions of shipped behavior. They may
diverge from current code.

- **[`dsp-structural-editor-vision.md`](dsp-structural-editor-vision.md)** —
  text-shaped authoring experience for `moondsp` (draft).
- **[`dsp-structural-editor-architecture.md`](dsp-structural-editor-architecture.md)**
  — architectural sketch for the same.

## Historical

Do not read files in this section unless user explicitly asks for historical
context. These documents describe past work and will not match current code.

- [`archive/`](archive/) — shipped phase design briefs, the early audit, the
  original bootstrap instructions, and the Phase 0/1/2 status log:
  - `archive/api-design-review-2026-04-21.md` — public-API design review
    whose prioritized recommendations have shipped.
  - `archive/audit-2026-04-02.md` — deep technical audit snapshot.
  - `archive/phase1-*-long-stretch.md` — Phase 1 DSP-primitive design briefs.
  - `archive/phase2-*-design-brief.md` — Phase 2 stereo-graph design briefs.
  - `archive/step0-instruction.md` — original bootstrap instructions.
  - `archive/RESULTS.md` — early Phase 0/1/2 status log.
