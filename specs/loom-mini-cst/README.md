# loom-mini-cst spike

Spike proving the `loom`/`incr` CST → projection → `PatternDoc` pipeline against
the mini-notation grammar, including stage-5 last-good (accepted-derived)
recovery. **Spike-only:** it is not built in CI and is not the production
authoring path (production uses `@mini.Draft` with explicit causal transactions;
only `@pattern` retains the published `dowdiness/incr/types` dependency).

The former `MiniAuthoringPipeline` comparison is historical. Draft source IDs
and Loom graph IDs are different contracts: compare musical output and test each
owner's identity lifetimes, rather than requiring cross-owner ID-string equality.
See the [current authoring contract](../../docs/plans/2026-09-09-playback-position-ui.md).

## Build prerequisites

This spike is not compiled in CI by design. It path-depends on modules from a
sibling `canopy` checkout, so a fresh `moondsp` clone alone cannot build it.
See `moon.mod.json`.

### 1. Local sibling checkout

The path dependencies in `moon.mod.json` resolve relative to this directory
through a sibling `canopy` checkout under `github.com/dowdiness/`:

| Dep | Path (from `specs/loom-mini-cst/`) | Resolves to |
|-----|-------------------------------------|-------------|
| `dowdiness/diagnostic` | `../../../canopy/deps/loom/diagnostic` | `github.com/dowdiness/canopy/deps/loom/diagnostic` |
| `dowdiness/graphviz` | `../../../canopy/deps/graphviz` | `…/canopy/deps/graphviz` |
| `dowdiness/loom` | `../../../canopy/deps/loom/loom` | `…/canopy/deps/loom/loom` |
| `dowdiness/moji` | `../../../canopy/deps/loom/moji` | `…/canopy/deps/loom/moji` |
| `dowdiness/seam` | `../../../canopy/deps/loom/seam` | `…/canopy/deps/loom/seam` |
| `dowdiness/pretty` | `../../../canopy/deps/loom/pretty` | `…/canopy/deps/loom/pretty` |
| `dowdiness/incr` | `../../../canopy/deps/loom/incr/incr` | `…/canopy/deps/loom/incr/incr` |
| `dowdiness/text_change` | `../../../canopy/deps/loom/text-change` | `…/canopy/deps/loom/text-change` |
| `dowdiness/moondsp` | `../..` | this repo |

The eight Canopy dependencies remain local path dependencies and are not
published inputs to this spike.

### 2. Current local dependency state

The sibling `canopy/deps/loom/incr/incr` module is `0.15.1` and includes incr
#233's diamond-dependency fix (`518305d`). The spike now targets Loom's
`SourceId`-aware parser APIs and incr's `Input`, `Derived`, and `Watch`
lifecycle.

The checked-in `moon.work` lists this spike, `moondsp`, and every local Canopy
module needed for dependency resolution. These path dependencies follow the
current sibling checkout rather than a pinned revision, so API drift can still
require a compatibility update.

The relative paths assume the canonical sibling layout shown above. From a
linked worktree nested under `moondsp/.worktrees/`, use the canonical checkout
or make `canopy` available at the same relative path expected by `moon.mod.json`
and `moon.work`.

This compatibility setup remains spec-local. It does not promote the Loom
parser or add Loom-stack dependencies to published `moondsp` packages.

### 3. Failure policy

Recoverable mini-notation syntax problems remain values: CST entry points return
them in `DiagnosticSet`, while semantic projection entry points return `Err(String)`.
They do not use Loom's raising channel.

The CST helpers retain their historical `raise LexError` surface. A fatal Loom
`Failure` is therefore normalized to `LexError`; that adapter preserves the
spec API but does not claim the underlying failure was lexical.

`LoomMiniAtomProjection` also retains its historical non-raising constructor
and mutation methods. Its edit evidence is staged before the parser snapshot is
updated, so a raised parser-engine failure can leave those two inputs
inconsistent. The `try!` calls deliberately treat that state as unsafe to
continue rather than disguising it as a recoverable syntax error. The one-shot
song projection has no escaped mutable state and safely converts parser
initialization failure to its existing `Err(String)` boundary.

### 4. Smoke-check status

With the sibling checkout in place, run the supported source-compatibility
checks from this directory:

```bash
NEW_MOON_MOD=0 moon check
NEW_MOON_MOD=0 moon test src
```

The scoped test command runs only this spike's tests. A bare `moon test` also
runs tests from the sibling workspace members, so unrelated Canopy failures are
not evidence that this fixture failed.

## Why this isn't in CI

CI builds only what lives in the `moondsp` checkout (see `.github/workflows/`:
boundary-check, browser-smoke, clap-prototype). The spike's local-path deps to
`canopy/deps/loom/*` are deliberately outside that boundary, so CI stays green
by never building the spike.

Related decisions and guards:

- **ADR-0016** records the Loom-backed runtime parser decision that followed
  the promotion investigation in #184.
- **#185** documented the local sibling-checkout requirement and intentionally
  left this spike outside CI.
- **#187** added the import-narrowness guard for production packages.
