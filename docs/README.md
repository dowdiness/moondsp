# moondsp Documentation

This directory contains architecture blueprints, technical references, integration contracts, performance benchmarks, and design records for `dowdiness/moondsp`.

Use this file as a router. Read the documents for the surface you are changing; do not preload the entire documentation tree.

## Read when changing

| Change | Primary references |
|---|---|
| Authoring or live coding | [`guides/live-coding-cookbook.md`](guides/live-coding-cookbook.md), [`mini-notation.md`](mini-notation.md), [`pattern-algebra.md`](pattern-algebra.md) |
| Graph runtime-control | [`technical-reference.md`](technical-reference.md), [`external-dsl-lowering.md`](external-dsl-lowering.md), and the applicable graph ADR |
| Editor, Song, Update, identity, or playback-origin semantics | [`../CONTEXT.md`](../CONTEXT.md) and the applicable Song/playback ADR |
| Browser ABI or AudioWorklet lifecycle | [`browser-api-contract.md`](browser-api-contract.md) and the relevant browser example |
| Mini notation crossing into DSP graphs | [`mini-graph-authoring-boundary.md`](mini-graph-authoring-boundary.md) and [`external-dsl-lowering.md`](external-dsl-lowering.md) |
| Native CLAP or C ABI | [`clap-plugin-guide.md`](clap-plugin-guide.md) and relevant records in [`development/`](development/) |
| Performance or allocation claim | The relevant dated record in [`performance/`](performance/) and, for hard-real-time claims, [`development/`](development/) |
| Why an architectural choice exists | The applicable record in [`decisions/`](decisions/README.md) |
| Historical reconstruction | [`archive/`](archive/) only when historical context is explicitly requested |

## Guides & Language

- **[`guides/live-coding-cookbook.md`](guides/live-coding-cookbook.md)** — Hands-on recipes from a drum pulse through Euclidean polyrhythms, layered harmony, stereo and room effects, and an arranged song.
- **[`mini-notation.md`](mini-notation.md)** — Pattern syntax: quoted notation, sub-groups, Euclidean rhythms, polyphonic layers, and method chains.
- **[`pattern-algebra.md`](pattern-algebra.md)** — Rational-time pattern engine design: queryable arcs, events, combinators, and value mapping.
- **[`mini-graph-authoring-boundary.md`](mini-graph-authoring-boundary.md)** — Boundary contract for bridging mini-notation events into DSP graph templates without mixing layers.

## Target Profiles

`moondsp` is platform-agnostic. Core audio and pattern computation are strictly decoupled from host platform drivers:

- **Browser:** [`browser-api-contract.md`](browser-api-contract.md) — Web AudioWorklet export ABI (`wasm-gc`), JS/TS bindings, and browser integration review rules.
- **Native DAW:** [`clap-plugin-guide.md`](clap-plugin-guide.md) — Native CLAP plugin architecture, C ABI bridge, Linux/Windows builds, and zero-allocation audit.
- **Host-independent MoonBit:** Direct programmatic API via `GraphEngine` (see [Root README](../README.md#host-independent-moonbit-api)).

For a browser instrument, start with the [basic synth guide](../examples/basic-synth/README.md), which provides Svelte and framework-free adapters over one shared core. Then use the browser contract's [graph lifecycle](browser-api-contract.md#rendering-and-lifecycle) and [live controls](browser-api-contract.md#live-controls) sections.

## Core Architecture & Specifications

- **[`technical-reference.md`](technical-reference.md)** — **Authoritative** reference for graph runtime-control behavior: node types, parameter slots, compilation, and rendering. Update it first when that contract changes; code remains the implementation source of truth.
- **[`blueprint.md`](blueprint.md)** — Architectural vision, design principles, and multi-target roadmap.
- **[`decisions/`](decisions/README.md)** — Architecture Decision Records capturing why key architectural choices were made.
- **[`external-dsl-lowering.md`](external-dsl-lowering.md)** — Contract for external editors and DSLs lowering graphs into `Array[DspNode]` and `CompiledTemplate`.
- **[`editor-audio-preview-handoff.md`](editor-audio-preview-handoff.md)** — State machine and ownership contract for live graph staging and parameter preview.

## Evidence & Contributor Resources

- **[`performance/`](performance/)** — Dated benchmark snapshots and allocation investigations. Each record states its measured scope; it is not a whole-engine or hard-real-time guarantee.
- **[`development/`](development/README.md)** — Hardware probes, zero-allocation audits, DAW compatibility records, and boundary inventories.
- **[GitHub Issues](https://github.com/dowdiness/moondsp/issues)** — Open issues are the source of truth for upcoming work. Per-PR history belongs in `git log`; released behavior belongs in [`CHANGELOG.md`](../CHANGELOG.md).
- **[`../CLAUDE.md`](../CLAUDE.md)** — Always-loaded project router and safety boundaries.

## Historical Archive

Historical design briefs, bootstrap instructions, and completed phase logs live under [`archive/`](archive/). Do not search or modify archived files unless historical context is explicitly requested.
