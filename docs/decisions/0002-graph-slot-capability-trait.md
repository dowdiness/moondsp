# ADR-0002: Generic GraphSlot for browser variants

- **Status:** Accepted
- **Date:** 2026-04-22 (decision shipped 2026-04-17)
- **Source:** [`docs/superpowers/specs/archive/2026-04-17-browser-slot-refactor-design.md`](../superpowers/specs/archive/2026-04-17-browser-slot-refactor-design.md)
- **Audit reference:** `docs/archive/audit-2026-04-02.md` §S2 ("Browser package is monolithic")

## Context

The `browser/` package exposes seven near-identical graph variants to
JavaScript as wasm exports (mono compiled, mono hot-swap, mono topology
edit, stereo, stereo hot-swap, stereo topology edit, exit-deliverable). Each
variant file repeated the same skeleton:

- five `@ref.Ref` globals (graph, context, output buffer(s), sample_rate,
  block_size)
- an `ensure_*` function with identical rate/block caching logic
- a `reset_*` function that nulls all five refs
- public `init_*_graph`, `process_*_block`, and `*_output_sample` wrappers

The 2026-04-02 audit predicted: *"the next bug will come from a change
applied to 5 of 6 variants."* Phase 6 work would add more variants,
compounding the risk.

A naive abstraction — making the lifecycle a generic struct over the graph
type alone — does not work, because mono variants take one buffer (`process(ctx, out)`)
and stereo variants take two (`process(ctx, left, right)`); the sample
accessors also differ in name (`sample(i)` vs. `left_sample(i)` /
`right_sample(i)`). A trait covering both `process` and accessors would be
either over-broad or non-uniform.

## Decision

Introduce `browser/slot.mbt` containing:

1. **`priv trait Output { reset(Self); allocate(Self, block_size : Int) }`**
   — capability trait holding only the methods whose signatures are uniform
   across mono and stereo.
2. **`priv struct MonoOut`** and **`priv struct StereoOut`**, each owning
   their buffer ref(s) and implementing `Output`. Type-specific accessors
   (`sample`, `left_sample`, `right_sample`, `get`, `left_buf`, `right_buf`)
   stay on the concrete types — not on the trait.
3. **`priv struct GraphSlot[T, O]`** — generic over graph type `T` and output
   shape `O`. Holds the five-ref scaffolding and a `compile : (DspContext) -> T?`
   closure. Lifecycle methods are bounded: `fn[T, O : Output] GraphSlot::ensure(...)`.

Each variant file shrinks to a single `GraphSlot` global plus thin public
wasm-export wrappers. Variant-specific extras (gain refs, inserted flags)
stay as plain module-level `@ref.Ref`s next to their use sites.

`browser_scheduler.mbt` is explicitly out of scope — it holds four
`SoundPool` globals with a pattern, structurally different from the seven
graph variants.

## Consequences

**Positive**

- Uniform-signature lifecycle methods (`ensure`, `reset`, `allocate`) exist
  in exactly one place. The audit-flagged "change applied to 5 of 6 variants"
  failure mode is structurally eliminated.
- Concrete output type is preserved at call sites because `O` is a type
  parameter, not a trait object — `stereo.output.sample(i)` is a compile
  error rather than a runtime zero. No runtime dispatch overhead.
- `browser/` source shrank ~30–40% with no change to wasm export names.
  Playwright tests pass unchanged (the wasm ABI is byte-stable).
- Adding a new variant (Phase 6+) becomes a one-file change: declare the
  `GraphSlot[NewGraphType, MonoOut|StereoOut]` and write the public wrappers.

**Negative**

- The `compile` closure allocates once when each top-level slot is constructed
  (function fields with captures). wasm-gc tolerates this, but reviewers must
  remember that closures are non-zero cost.
- `graph_val()` / `ctx_val()` unwrap without checking. Preserves the current
  contract (callers always call `ensure` first) and the panic behaviour matches
  pre-refactor — but this is a sharp edge.
- The capability trait is intentionally narrow (two methods). Future shapes
  that don't fit `MonoOut` / `StereoOut` will need new concrete types rather
  than extension of the trait.

**Rejected alternative** — Swapping `@ref.Ref` for `mut` struct fields would
simplify the slot further but is a larger semantic shift than "dedupe existing
scaffolding" and would have made review harder. Deferred.
