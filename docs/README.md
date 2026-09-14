# moondsp Documentation

This directory contains architecture blueprints, technical references, integration contracts, performance benchmarks, and design records for `dowdiness/moondsp`.

---

## 1. Guides & Language (Authoring & Live Coding)

- **[`mini-notation.md`](mini-notation.md)** — Concise pattern syntax: quoted notation, sub-groups, Euclidean rhythms (`bd(3,8)`), polyphonic layers (`$:`), and method chains (`.fast()`, `.jux()`).
- **[`pattern-algebra.md`](pattern-algebra.md)** — Rational-time pattern engine design: queryable arcs, events, combinators, and value mapping.
- **[`mini-graph-authoring-boundary.md`](mini-graph-authoring-boundary.md)** — Boundary contract for bridging mini-notation events into DSP graph templates without mixing layers.

---

## 2. Target Profiles (Platform Integration)

`moondsp` is platform-agnostic. Core audio and pattern computation are strictly decoupled from host platform drivers:

- 🌐 **Browser Target**: **[`browser-api-contract.md`](browser-api-contract.md)** — Web AudioWorklet export ABI (`wasm-gc`), JS/TS bindings, and browser integration review rules.
- 🎛️ **Native DAW Target**: **[`clap-plugin-guide.md`](clap-plugin-guide.md)** — Native CLAP plugin architecture, C ABI bridge (`clap_host`), Linux/Windows builds, and zero-allocation audit.
- 🖥️ **Host-Independent MoonBit Target**: Direct programmatic API via `GraphEngine` (see [Root README](../README.md#host-independent-moonbit-api)).

---

## 3. Core Architecture & Specifications

- **[`technical-reference.md`](technical-reference.md)** — **Authoritative** reference for graph runtime-control behavior: node types, parameter slots, topological compiler, and zero-allocation execution. If code and any other doc disagree, this document and the code take precedence.
- **[`blueprint.md`](blueprint.md)** — Complete architectural vision, design principles, and multi-target roadmap.
- **[`decisions/`](decisions/README.md)** — Architecture Decision Records (ADRs 0001 through 0017) capturing *why* key architectural choices were made.
- **[`external-dsl-lowering.md`](external-dsl-lowering.md)** — Contract for external editors and DSLs lowering graphs into `Array[DspNode]` and `CompiledTemplate`.
- **[`editor-audio-preview-handoff.md`](editor-audio-preview-handoff.md)** — State machine and ownership contract for live graph staging and parameter preview.

---

## 4. Evidences & Contributor Resources

- **[`performance/`](performance/)** — Dated real-time audio benchmark snapshots and allocation audits.
- **[`development/`](development/README.md)** — Hardware probes, zero-allocation audits, DAW compatibility records, and boundary inventories.
- **[`next-actions.md`](next-actions.md)** — Active handoff list for upcoming priorities.
- **[`../CLAUDE.md`](../CLAUDE.md)** — Project conventions and contributor quick reference.

---

## Historical Archive

Historical design briefs, bootstrap instructions, and completed phase logs live under **[`archive/`](archive/)**. Do not search or modify archived files unless historical context is explicitly requested.
