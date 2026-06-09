# Phase 0 Report: Loom Parser Migration Feasibility Gate

- **Date:** 2026-06-09
- **Executor:** Claude (Opus 4.8), executing-plans discipline
- **Plan:** `docs/superpowers/specs/2026-06-09-loom-parser-replacement-phase0-plan.md`
- **Verdict:** ✅ **GO**

## Commit context

| Repo | HEAD | Note |
|------|------|------|
| `dowdiness/moondsp` | `c568aea` | Phase 0 plan commit; canary + this report are uncommitted new files under `specs/loom-backend-canary/` and `docs/superpowers/specs/2026-06-09-loom-parser-replacement-phase0/`. |
| `dowdiness/incr` (sibling) | `c85b08c` (`main`) | Switched from a detached `v0.7.1` (`304feb3`) tag at preflight — `v0.7.1` does **not** contain `518305d` (diamond-dependency `push_reachable_count` fix #233); `main` does. This matches the existing `specs/loom-mini-cst/` build prerequisite. |
| `dowdiness/loom` (sibling) | `4add99f` | Detached at the current remote-`main` tip (#276, incr 0.9.0 pin bump); ahead of the stale local `main` ref. No switch needed. |

The probe is a **new, isolated module** at `specs/loom-backend-canary/`. The
existing `specs/loom-mini-cst/` characterization spike was **not touched**
(verified in the bundle positive control below — it is absent from the publish
bundle alongside the new canary).

## Backend matrix (Check #1)

The consumed loom stack (`loom`/`seam`/`pretty`/`incr`/`text_change`) builds and
its parser-oriented tests pass on all three backends. Each runner's own exit
code was captured (`cmd > log 2>&1; echo EXIT=$? >> log`), never a piped status.

| Backend | Build | Test | Tests |
|---------|-------|------|-------|
| `wasm-gc` | `EXIT=0` | `EXIT=0` | 9 passed / 0 failed |
| `native` | `EXIT=0` | `EXIT=0` | 9 passed / 0 failed |
| `js` | `EXIT=0` | `EXIT=0` | 9 passed / 0 failed |

Logs: `artifacts/phase0-target-{wasm-gc,native,js}-{build,test}.log`
(all six end `EXIT=0`). `moon check`: `artifacts/phase0-step3-check.log`
(`EXIT=0`).

## Check outcomes

### Check #1 — Multi-target compile: ✅ PASS

All six build/test logs end `EXIT=0`; ≥1 parser-oriented test passes per target
(the representative slice: runtime `s("bd sd hh sd")`, authoring
`s("bd sd").jux(rev)` with stable-ID projection, `$:`-stack song form, plus an
incremental `apply_edit` advance).

### Check #2 — Dependency / x-sys isolation: ✅ PASS

Authoritative signal = the probe's actual build graph (`moon info` +
`moon check --dry-run` package list + the three per-target builds), **not** a
whole-repo grep.

- The canary build graph consumes only `dowdiness/*` packages — `loom`, `seam`,
  `pretty`, `incr`, `text_change`, plus transitive `dowdiness/canopy` and
  `dowdiness/moji` — and `moonbitlang/core` builtins.
- **Zero `moonbitlang/x/*`** packages in the graph. An explicit
  `x/(sys|ffi|os|io|thread|arg)` probe over the dry-run build commands returned
  nothing, so the **localizer grep was not needed** (no leak to explain).
- All three per-target builds succeed with the **same import set** — no
  target-only divergence. This is corroborating: `moonbitlang/x/sys` is
  native-only and would have **failed** the `wasm-gc` and `js` builds had it
  been reachable. They passed.

Log: `artifacts/phase0-info.log` (`EXIT=0`) — its appended "Check #2
build-graph evidence" section persists the deduped package list (only
`dowdiness/*` + `moonbitlang/core`) and the explicit `moonbitlang/x/(sys|ffi|os|
io|thread|arg)` probe result (`NONE`), so the claim is auditable from the repo
alone, not from unstated console output.

### Check #3 — Error-shape / span compatibility: ✅ PASS

What the production contract actually requires
(`browser/internal/playback_host/playback_host.mbt`): `@mini.parse` returns
`Result[_, String]`; on `Err(msg)`, the browser performs **only** two
operations on the plain string — `get_pattern_error_length()` = `msg.length()`
and `get_pattern_error_char(i)` = `msg[i].to_int()` (UTF-16 code unit, `0` out
of range). It does **not** require any particular message format — production
messages are plain strings such as `"empty input"` or `"0:invalid ..."`.

`src/error_adapter.mbt` reduces loom's `@core.DiagnosticSet` to exactly that
shape: a `Result[_, String]` whose `Err` is a plain string, with
`canary_error_length` / `canary_error_char` matching the two production
accessors byte-for-byte (`.length()` + per-index UTF-16 access, `0`
out-of-range). The `"<offset>: <message>"` formatting and the test's
"first char is a digit" assertion are a **canary convention** demonstrating that
loom's span info (`Diagnostic.primary`) *can* be embedded into the message — not
a production requirement. The load-bearing compatibility result is that the two
accessor operations work on the adapter output; the prefix is a free design
choice Phase 1 may keep or drop.

Tested inputs (all on `wasm-gc`, `artifacts/phase0-error-shape.log`, `EXIT=0`,
9/9):

- `""` → `Err` with indexable offset ✓
- `foo("bd")` → `Err` (unknown primary) ✓
- `s("bd` → `Err` (unterminated) ✓
- malformed `$:` → `Err` ✓
- `s("bd sd").jux(rev)` → `Ok(2)` (non-error baseline; same shape, well-formed) ✓

The `browser` contract lines remain the source of truth and are **unchanged**.

### Check #4 — Manifest isolation: ✅ PASS

- `scripts/check-public-boundary.sh` → `EXIT=0`
  ("OK: all public `Array[DspNode]` entries match ADR-0010 carve-outs").
  Log: `artifacts/phase0-public-boundary.log`.
- Root `moon.mod` `options(exclude: [...])` explicitly lists **`"specs/"`** and
  **`"docs/superpowers/"`** (and `docs/archive/`).
- **Authoritative bundle inspection** of the dry-run artifact
  `_build/publish/dowdiness-moondsp-0.5.1.zip` (357 files):
  - A **path-delimited** grep (`specs/|loom-backend-canary|loom-mini-cst|
    canopy/|/loom/|/seam/|/pretty/|text-change/|/incr/`) returns **zero**
    matches — no `specs/` path or loom-stack package file is bundled. Both the
    new canary **and** the existing `loom-mini-cst` spike are absent. (A looser
    substring grep for `loom` matches three *moondsp-owned* docs whose filenames
    contain "loom" — `docs/loom-upstream-requirements.md`,
    `docs/decisions/00{12,13}-loom-*.md` — which are correctly bundled and are
    not loom-stack files; see `artifacts/phase0-publish-dryrun.log`.)
  - **Positive control:** the same detector found 171 matches for real runtime
    packages (`dsp/`, `graph/`, `mini/`, `pattern/`, `scheduler/`) and
    `docs/performance/*` is bundled — so the empty `specs/` result is a genuine
    null, not a broken matcher.
  - `docs/superpowers/` (this report + logs) is **not** in the bundle.
  - No runtime-facing `moon.mod` import path pulls `loom`/`seam`/`pretty`/
    `text_change`.

Note: `moon publish --dry-run` returned `EXIT=255`, but the cause is a
**server-side 409 duplicate-version** rejection (version `0.5.1` is already
published) that fires *after* local bundle assembly — it is unrelated to
isolation. The bundle was assembled locally and inspected directly (above). Log:
`artifacts/phase0-publish-dryrun.log` (includes the appended bundle inspection).

## Bounded upstream change list

**None.** No Check required an upstream `loom`/`incr` change. The only
prerequisite is operational, not a code change: the sibling `incr` checkout must
be on `main` (or otherwise contain `518305d`) — identical to the existing
`specs/loom-mini-cst/` build prerequisite, documented in both READMEs.

## Decision gate

All four checks pass with no bounded upstream fix required.

> ## ✅ GO
>
> The loom stack is feasible as a cross-backend (`wasm-gc` / `native` / `js`)
> parser foundation for moondsp: it builds and tests green on all three targets,
> pulls no `moonbitlang/x/sys` (or other native-FFI / target-restricted)
> dependency, its diagnostics normalize cleanly onto the existing browser
> parse-error contract, and the loom path deps stay confined to the `specs/`
> module — excluded from the published `dowdiness/moondsp` bundle.

### Required follow-up (Phase 1 entry, out of Phase 0 scope)

- Phase 1+ work (CST→PatternDoc parity, production wiring, ADR edits, loom
  publish) is **not** started here — Phase 0 was feasibility only.
- The `incr`-on-`main` operational prerequisite must hold for any environment
  that builds the loom-backed path until `incr 0.9.x` (containing `518305d`) is
  the pinned registry release consumed without a path-dep override.
- Decide whether `specs/loom-backend-canary/` is retained as a standing
  cross-backend smoke probe or removed once Phase 1 lands a CI-built path.
