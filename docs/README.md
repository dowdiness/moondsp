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
- **[`performance/`](performance/)** — dated benchmark snapshots. New
  measurements go in new files (do not edit historical entries in place).

## Reviews

Point-in-time analyses. Each review is dated and should be moved to
`archive/` once its recommendations have shipped or been rejected, rather
than edited in place.

- **[`api-design-review-2026-04-21.md`](api-design-review-2026-04-21.md)**
  — public-API design review of the root `@moondsp` facade and `dsp` /
  `graph` / `voice` sub-packages. Flags facade drift, over-exposed DSP
  struct fields, and the silent-failure `Bool`-return family as
  pre-1.0 stability risks.

## Contributor design docs

Per-feature design briefs and task-level plans. "Current" is what has not
shipped yet; once a feature is merged its design/plan is moved under
`archive/` and should not be read as a description of live behavior.

- **[`superpowers/specs/`](superpowers/specs/)** — current design specs.
- **[`superpowers/plans/`](superpowers/plans/)** — current implementation plans.
- `superpowers/specs/archive/` and `superpowers/plans/archive/` — shipped
  features. Historical context only.

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
  - `archive/audit-2026-04-02.md` — deep technical audit snapshot.
  - `archive/phase1-*-long-stretch.md` — Phase 1 DSP-primitive design briefs.
  - `archive/phase2-*-design-brief.md` — Phase 2 stereo-graph design briefs.
  - `archive/step0-instruction.md` — original bootstrap instructions.
  - `archive/RESULTS.md` — early Phase 0/1/2 status log.
