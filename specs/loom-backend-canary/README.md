# loom-backend-canary

Phase 0 feasibility **gate** for the loom parser-replacement campaign. This is a
throwaway probe, **not** a parity spike and **not** the production authoring
path. It is distinct from `specs/loom-mini-cst/` (the characterization-gate
parity spike) and never touches it.

## What this proves (and only this)

Phase 0 answers four cross-backend feasibility questions before any production
parser migration begins:

1. **Check #1 — multi-target compile.** The consumed loom stack
   (`loom`/`seam`/`pretty`/`incr`/`text_change`) builds and a parser-oriented
   test passes on all three backends: `wasm-gc`, `native`, `js`.
2. **Check #2 — dependency isolation.** No `moonbitlang/x/sys` (or other
   native-FFI / target-restricted dependency) is reachable from the parser
   surface the probe consumes. Authoritative signal = the probe's actual build
   graph (`moon info` + per-target build logs), not a whole-repo grep.
3. **Check #3 — error-shape / span compatibility.** Loom's `DiagnosticSet` can
   be normalized to the existing production browser contract: a plain-string
   parse message with an indexable position, accessed by `length()` and a
   per-char (UTF-16 code unit) accessor — the shape
   `browser/internal/playback_host/playback_host.mbt`
   (`get_pattern_error_length` / `get_pattern_error_char`) requires.
4. **Check #4 — manifest isolation.** The loom path deps stay confined to this
   `specs/` module; the published `dowdiness/moondsp` bundle excludes `specs/`
   and never pulls a loom-stack file into a runtime-facing package.

## What this is NOT

- Not a CST→PatternDoc parity matrix (Phase 2 scope).
- Not production wiring, an ADR edit, or a loom publish (Phases 1–2).
- The grammar here is deliberately **minimal**: just enough mini-shaped surface
  (one input per production entrypoint shape — runtime `s(...)`, authoring
  method-chain `s(...).jux(rev)`, and a `$:` stack form) to import the full
  consumed loom surface so Check #2's scan is meaningful.

## Build prerequisites

Same sibling-checkout requirement as `specs/loom-mini-cst/`: the five
`path`-deps in `moon.mod.json` resolve to repos checked out as siblings of
`moondsp` under `github.com/dowdiness/canopy/loom/`. The `incr` checkout must be
on `main` (or otherwise contain `518305d`, the diamond-dependency
`push_reachable_count` fix #233). Run `moon clean` after any sibling branch
switch.

All `moon` commands in this module must be prefixed with `NEW_MOON_MOD=0`.

Logs and the GO/NO-GO report live under
`docs/superpowers/specs/2026-06-09-loom-parser-replacement-phase0/`.
