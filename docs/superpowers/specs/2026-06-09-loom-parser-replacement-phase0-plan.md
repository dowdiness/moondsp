# Phase 0 Plan: Loom Parser Migration Feasibility (6.09.2026)

Goal: run a bounded feasibility gate for replacing both moondsp runtime `@mini.parse` and authoring pipeline parser path under `specs/loom-backend-canary`, proving cross-target build + dependency isolation + parse-error contract compatibility + manifest boundary safety before any production parser migration.

## Preconditions / prerequisites
1. Work from the repo root `/home/antisatori/ghq/github.com/dowdiness/moondsp`.
2. All `moon` commands must be prefixed with `NEW_MOON_MOD=0`.
3. Confirm sibling loom checkout state from root:
   - `../../../canopy/loom/loom`, `../../../canopy/loom/seam`,
     `../../../canopy/loom/pretty`, `../../../canopy/loom/incr/incr`,
     `../../../canopy/loom/text-change` exist.
4. Confirm `../../../canopy/loom/incr` is on `main` (or contains `518305d`) before compiling spike-like consumers, then run `moon clean` after branch changes.
5. Keep existing `specs/loom-mini-cst/` untouched; do not delete/rename any files there.
6. No edits to parser/projection/runtime production packages yet.
7. The contract sources to pin are:
   - `browser/internal/playback_host/playback_host.mbt` (`set_active_pattern_text`, `set_active_song_text`, `get_scheduler_parse_error`, `set_scheduler_parse_error`, `get_pattern_error_length`, `get_pattern_error_char`).
   - `browser/browser_scheduler.mbt` accessors.
   - `mini/mini.mbt`, `mini/doc_parser.mbt`, `mini/song_parser.mbt` error-shape entrypoints.

## Step plan (ordered)

1. **Baseline preflight and canary module directory setup**
   - Files to create:
     - `specs/loom-backend-canary/moon.mod.json`
     - `specs/loom-backend-canary/README.md`
     - `specs/loom-backend-canary/src/moon.pkg`
     - `specs/loom-backend-canary/src/parser_probe.mbt`
     - `specs/loom-backend-canary/src/error_adapter.mbt`
     - `specs/loom-backend-canary/src/manifest_isolation.mbt`
     - `specs/loom-backend-canary/src/parser_probe_test.mbt`
   - Commands:
    - `NEW_MOON_MOD=0 git -C specs/loom-backend-canary status --short > docs/superpowers/specs/2026-06-09-loom-parser-replacement-phase0/artifacts/phase0-step1-baseline.log 2>&1; echo EXIT=$? >> docs/superpowers/specs/2026-06-09-loom-parser-replacement-phase0/artifacts/phase0-step1-baseline.log`
     - `cd /home/antisatori/ghq/github.com/dowdiness/moondsp && ls specs/loom-backend-canary`
   - Acceptance: module path exists with required files; existing spike untouched.

2. **Reuse the existing spike path dependency shape (do not reuse / import it)**
   - `specs/loom-backend-canary/moon.mod.json` must use path deps to:
     - `../../../canopy/loom/loom`
     - `../../../canopy/loom/seam`
     - `../../../canopy/loom/pretty`
     - `../../../canopy/loom/incr/incr`
     - `../../../canopy/loom/text-change`
   - It must also include `dowdiness/moondsp` as parent for parser test fixtures only (`../..`).
   - Command:
     - `cat specs/loom-backend-canary/moon.mod.json`
   - Acceptance: manifest mirrors Phase 0 design and does not modify any existing file under `specs/loom-mini-cst/`.
   - If dependency shape is insufficient to keep phase checks meaningful, log a "bounded upstream change required" issue to Step 4’s report rather than changing production scope.

3. **Define minimal loom parser-surface probe package**
   - `specs/loom-backend-canary/src/parser_probe.mbt` should import a representative parser/diagnostic surface only:
     - `@core.LanguageSpec` creation with mini token/syntax kinds from `loom`/`seam`,
     - parser creation/runtime snapshot,
     - parse/diagnostic accessor calls.
   - `specs/loom-backend-canary/src/parser_probe_test.mbt` defines the **representative parser slice**: exactly ONE representative input per production entrypoint shape — runtime `parse` (`s("bd sd hh sd")`), authoring `parse_doc` (a method-case such as `s("bd sd").jux(rev)` to exercise the PatternDoc/stable-ID path), and `song`-parse (a minimal song form). The slice's job is to import the FULL consumed loom surface so Check #2's dependency scan is meaningful — it is deliberately MINIMAL. Do NOT add the broad grammar/parity matrix here (full provenance/parity is Phase 2 scope, out of Phase 0).
   - Command:
     - `cd /home/antisatori/ghq/github.com/dowdiness/moondsp && NEW_MOON_MOD=0 moon -C specs/loom-backend-canary check > docs/superpowers/specs/2026-06-09-loom-parser-replacement-phase0/artifacts/phase0-step3-check.log 2>&1; echo EXIT=$? >> docs/superpowers/specs/2026-06-09-loom-parser-replacement-phase0/artifacts/phase0-step3-check.log`
   - Acceptance: `moon check` passes for the canary package only.

4. **MULTI-TARGET COMPILE check (Check #1)**
   - For each backend in `wasm-gc`, `native`, `js`:
     - `for target in wasm-gc native js; do log=docs/superpowers/specs/2026-06-09-loom-parser-replacement-phase0/artifacts/phase0-target-$target-build.log; NEW_MOON_MOD=0 moon -C specs/loom-backend-canary build --target $target > $log 2>&1; echo EXIT=$? >> $log; done`
     - `for target in wasm-gc native js; do log=docs/superpowers/specs/2026-06-09-loom-parser-replacement-phase0/artifacts/phase0-target-$target-test.log; NEW_MOON_MOD=0 moon -C specs/loom-backend-canary test --target $target > $log 2>&1; echo EXIT=$? >> $log; done`
   - Acceptance: all six logs end with `EXIT=0`; at least one parser-oriented test passes in each target run.
   - If one backend fails to compile/link in a non-trivial way, capture exact compiler output and mark Check #1 as failed for that backend.

5. **DEPENDENCY-GRAPH / X-SYS isolation check (Check #2)**
   - **Authoritative signal = the probe's actual build graph, NOT a repo grep.** Drive pass/fail from what the canary probe transitively imports (`moon info` + the per-target build logs), because a whole-repo grep hits loom's CLI/binary and `.mooncakes/` and produces false positives.
   - Commands:
     - `NEW_MOON_MOD=0 moon -C specs/loom-backend-canary info > docs/superpowers/specs/2026-06-09-loom-parser-replacement-phase0/artifacts/phase0-info.log 2>&1; echo EXIT=$? >> docs/superpowers/specs/2026-06-09-loom-parser-replacement-phase0/artifacts/phase0-info.log`
     - (already have per-target build logs from Step 4 — reuse them to confirm no target-only symbol pulled the build into a single backend.)
     - LOCALIZER ONLY (run iff the build graph shows a leak): `NEW_MOON_MOD=0 rg --line-number "moonbitlang/x/(sys|ffi|arg|os|io|thread)" ../../../canopy/loom/loom ../../../canopy/loom/seam ../../../canopy/loom/pretty ../../../canopy/loom/incr/incr ../../../canopy/loom/text-change > docs/superpowers/specs/2026-06-09-loom-parser-replacement-phase0/artifacts/phase0-xsys-locate.log 2>&1` (exclude `.mooncakes/` and any `*_cli`/binary package; the grep EXPLAINS a confirmed leak, it does not DECIDE one).
   - Acceptance:
     - The canary probe's transitive dependency graph (`moon info`) shows NO `moonbitlang/x/sys` (or other native-FFI/target-restricted dep) reachable from the consumed parser surface.
     - All three per-target builds (Step 4) succeed with the same import set — no target-only divergence.
     - If a leak IS in the build graph, use the localizer to list each offending package path + upstream API, recorded in the report as bounded-change items.

6. **ERROR-SHAPE / SPAN CANARY (Check #3)**
   - Files to create:
     - `specs/loom-backend-canary/src/error_adapter.mbt`
     - `specs/loom-backend-canary/src/error_adapter_test.mbt`
   - Adapter must normalize loom diagnostics to existing production contract:
     - `Result[..., String]`
     - plain string parse message
     - integer char position (1) used for a UTF-16-style char accessor path.
   - Test inputs must include at least:
     - `""`
     - `foo("bd")`
     - `s("bd`
     - malformed `$:` form
     - valid control-method chain for non-error baseline.
   - Commands:
     - `NEW_MOON_MOD=0 moon -C specs/loom-backend-canary test --target wasm-gc > docs/superpowers/specs/2026-06-09-loom-parser-replacement-phase0/artifacts/phase0-error-shape.log 2>&1; echo EXIT=$? >> docs/superpowers/specs/2026-06-09-loom-parser-replacement-phase0/artifacts/phase0-error-shape.log`
   - Acceptance:
     - bad input returns `Err(msg)` and `msg` contains an indexable position indicator.
     - `msg.length()` and `msg.codepoint-by-index` style accessors emulate `browser/internal/playback_host/playback_host.mbt` access pattern (`get_*_error_length`, `get_*_error_char`) exactly for the canary adapter output.
     - `browser` contract lines are unchanged and remain source-of-truth references.

7. **MANIFEST-ISOLATION CANARY (Check #4)**
   - Files to create:
     - `specs/loom-backend-canary/src/manifest_isolation.mbt`
   - Design target:
     - keep all loom path deps inside a dedicated authoring-only/internal package boundary.
     - keep root package unchanged and ensure public boundary checks remain green.
   - Commands:
     - `NEW_MOON_MOD=0 ./scripts/check-public-boundary.sh > docs/superpowers/specs/2026-06-09-loom-parser-replacement-phase0/artifacts/phase0-public-boundary.log 2>&1; echo EXIT=$? >> docs/superpowers/specs/2026-06-09-loom-parser-replacement-phase0/artifacts/phase0-public-boundary.log`
     - Authoritative bundle inspection (the verified method — `moon package --list` is NOT a real command): `NEW_MOON_MOD=0 moon publish --dry-run > docs/superpowers/specs/2026-06-09-loom-parser-replacement-phase0/artifacts/phase0-publish-dryrun.log 2>&1; echo EXIT=$? >> docs/superpowers/specs/2026-06-09-loom-parser-replacement-phase0/artifacts/phase0-publish-dryrun.log` — inspect the dry-run bundle file list and confirm NOTHING under `specs/` (and no `canopy/loom` path) appears in the published bundle.
   - Acceptance:
     - `check-public-boundary.sh` stays green.
     - root `moon.mod` still excludes `specs/`, and the `moon publish --dry-run` bundle list contains no `specs/`-path or loom-stack file.
     - no runtime-facing package import path in `moon.mod` pulls `loom`/`seam`/`pretty`/`text-change`.

8. **Aggregate GO/NO-GO evidence and finalize**
   - Files to create:
     - `docs/superpowers/specs/2026-06-09-loom-parser-replacement-phase0-report.md`
   - Report template:
     - Date + executor + commit context.
     - Backend matrix (`wasm-gc`, `native`, `js`) with logs and `EXIT` codes.
     - Check #1–#4 outcomes + exact pass/fail evidence and references to log files.
     - "Bounded upstream change list" section if Check #2 or #4 fails.
     - GO/NO-GO final decision with required follow-up action.
   - Command:
     - `cat docs/superpowers/specs/2026-06-09-loom-parser-replacement-phase0-report.md`

9. **Decision gate**
   - **GO**: all four checks pass.
   - **Conditional GO**: all checks pass with a bounded upstream fix list from #2 that is isolated, documented, and feasible.
   - **NO-GO**: any backend compile failure that cannot be fixed by bounded upstream dependency isolation changes, or any immutable boundary leak that persists.

## Risks / fallback
1. Upstream `loom` or `incr` consumes `moonbitlang/x/sys`/FFI in parser surface; fallback is to record exact offending symbols and request upstream helper refactor before Phase 0 passes.
2. JS/native/wasm-gc parity asymmetry in parser/snapshot APIs; fallback is to pin the minimum stable API slice and gate progression on that slice only.
3. If `moon -C specs/loom-backend-canary` command behavior differs by backend, use `moon -C specs/loom-mini-cst` invocation style for consistency, but keep command intent identical and log outputs.
4. A strong reason exists to extend `specs/loom-mini-cst` instead of creating parallel files (e.g., repeated spec drift). If this is the case, pause and ask Opus before executing Step 2 and keep this plan’s intent in place.
