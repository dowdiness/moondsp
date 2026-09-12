# loom-mini-cst spike

Spike proving the `loom`/`incr` CST → projection → `PatternDoc` pipeline against
the mini-notation grammar, including stage-5 last-good (accepted-derived)
recovery. **Spike-only:** it is not built in CI and is not the production
authoring path (production still uses `MiniAuthoringPipeline` /
`@pattern` against the published `dowdiness/incr`).

## Build prerequisites

This spike is not compiled in CI by design. It path-depends on modules from a
sibling `canopy` checkout, so a fresh `moondsp` clone alone cannot build it.
See `moon.mod.json`.

### 1. Local sibling checkout

The path dependencies in `moon.mod.json` resolve relative to this directory
through a sibling `canopy` checkout under `github.com/dowdiness/`:

| Dep | Path (from `specs/loom-mini-cst/`) | Resolves to |
|-----|-------------------------------------|-------------|
| `dowdiness/loom` | `../../../canopy/deps/loom/loom` | `github.com/dowdiness/canopy/deps/loom/loom` |
| `dowdiness/seam` | `../../../canopy/deps/loom/seam` | `…/canopy/deps/loom/seam` |
| `dowdiness/pretty` | `../../../canopy/deps/loom/pretty` | `…/canopy/deps/loom/pretty` |
| `dowdiness/incr` | `../../../canopy/deps/loom/incr/incr` | `…/canopy/deps/loom/incr/incr` |
| `dowdiness/text_change` | `../../../canopy/deps/loom/text-change` | `…/canopy/deps/loom/text-change` |
| `dowdiness/moondsp` | `../..` | this repo |

The five direct `loom` dependencies live in the sibling `canopy` checkout
under `deps/loom/`; they remain local path dependencies and are not published
inputs to this spike.

### 2. Current local dependency state

The sibling `canopy/deps/loom/incr/incr` module is `0.15.1` and includes incr
#233's diamond-dependency fix (`518305d`). The spike source still targets older
Loom parser and incr APIs, so it does not compile against the current sibling
checkout.

A standalone `moon check` from this directory stops during dependency
resolution: current Loom modules obtain additional local modules through
Canopy's workspace. The 2026-09-12 investigation used a temporary cross-repo
workspace containing this spike, `moondsp`, and the Canopy Loom modules to
reach source compilation. Source compilation then reported the expected
independent drift: Loom's new `SourceId` / parser-context contracts plus the
removed incr `Signal`, `Memo`, and `Observer` APIs.

Issue #226 keeps this spike on local path dependencies; it does not promote or
migrate the non-production Loom parser. That broader work remains under #184
and #185.

### 3. Smoke-check status

There is currently no supported standalone smoke command for this fixture.
Do not treat `NEW_MOON_MOD=0 moon check` from this directory as a
source-compatibility check: it fails at dependency resolution before checking
the spike source. A reproducible workspace-backed smoke command remains part
of the rot-prevention work tracked by #185.

## Why this isn't in CI

CI builds only what lives in the `moondsp` checkout (see `.github/workflows/`:
boundary-check, browser-smoke, clap-prototype). The spike's local-path deps to
`canopy/deps/loom/*` are deliberately outside that boundary, so CI stays green
by never building the spike.

Closing that gap is tracked separately:

- **#184** — decide whether to promote this local-path spike into the
  production authoring path under ADR-0013's remaining gates.
- **#185** — rot prevention for these local build prerequisites.
- **#187** — import-narrowness CI guard.
