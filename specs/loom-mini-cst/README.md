# loom-mini-cst spike

Spike proving the `loom`/`incr` CST → projection → `PatternDoc` pipeline against
the mini-notation grammar, including stage-5 last-good (accepted-derived)
recovery. **Spike-only:** it is not built in CI and is not the production
authoring path (production still uses `MiniAuthoringPipeline` /
`@pattern` against the published `dowdiness/incr`).

## Build prerequisites

This spike compiles green **nowhere in CI** — by design. It `path`-deps five
sibling repos that live outside the `moondsp` checkout, so a fresh `moondsp`
clone alone cannot build it. See `moon.mod.json`.

### 1. Local sibling checkouts

The path-deps in `moon.mod.json` resolve, relative to this directory, to repos
checked out as siblings of `moondsp` under `github.com/dowdiness/`:

| Dep | Path (from `specs/loom-mini-cst/`) | Resolves to |
|-----|-------------------------------------|-------------|
| `dowdiness/loom` | `../../../canopy/loom/loom` | `github.com/dowdiness/canopy/loom/loom` |
| `dowdiness/seam` | `../../../canopy/loom/seam` | `…/canopy/loom/seam` |
| `dowdiness/pretty` | `../../../canopy/loom/pretty` | `…/canopy/loom/pretty` |
| `dowdiness/incr` | `../../../canopy/loom/incr/incr` | `…/canopy/loom/incr/incr` |
| `dowdiness/text_change` | `../../../canopy/loom/text-change` | `…/canopy/loom/text-change` |
| `dowdiness/moondsp` | `../..` | this repo |

All five `canopy/loom/*` repos are **independent working repos**, not git
submodules of `moondsp`. You must clone them yourself.

### 2. Required `canopy/loom/incr` checkout state

The spike builds correctly **only** when the sibling `canopy/loom/incr` repo is
on `main` (or any commit containing incr #233's fix, commit `518305d`,
`fix(incr): correct push_reachable_count for diamond dependencies`).

If `incr` has drifted to an older branch/tag that predates `518305d`, the spike
fails with the **diamond-freeze symptom**: the stage-5 accepted-derived eager
fold silently stops updating because a candidate has dynamic diamond deps. This
is not a spike bug — it is the missing #233 fix.

### 3. `moon clean` after switching incr branches

After checking out a different `incr` branch/commit, run `moon clean` in this
directory before rebuilding. Stale build artifacts survive the branch switch and
reproduce the old behavior otherwise.

```bash
# from specs/loom-mini-cst/
git -C ../../../canopy/loom/incr switch main   # ensure #233 fix is present
moon clean
moon check && moon test
```

## Why this isn't in CI

CI builds only what lives in the `moondsp` checkout (see `.github/workflows/`:
boundary-check, browser-smoke, clap-prototype). The spike's local-path deps to
`canopy/loom/*` are deliberately outside that boundary, so CI stays green by
never building the spike.

Closing that gap is tracked separately:

- **#184** — promote the spike to the published registry `dowdiness/incr` so it
  becomes CI-buildable. **Blocked** on incr #233 reaching mooncakes.
- **#185** — this rot-prevention work (these build prerequisites + an optional
  lightweight "spike still parses" CI guard).
- **#187** — import-narrowness CI guard.
