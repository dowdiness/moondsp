# Next Actions

Updated: 2026-05-18

Forward-looking handoff for the next session. Keep short and actionable;
per-PR verification logs and merged-PR lists live in `git log` and
`CHANGELOG.md`, not here.

## Current State

- `main` HEAD: `ad29723 refactor!: tighten dsp visibility and fix per-sample re-validation (#59)`.
- Latest release: **v0.3.1** (2026-05-11). **v0.4.0 is staged on `main`** —
  PRs #55, #56, #57, #58, #59 merged; `moon.mod.json` already at `0.4.0`;
  `CHANGELOG.md` has a `[0.4.0] - 2026-05-17` block covering #57/#58 but
  **not yet updated for #59** (dsp `EnvStage`/`ChannelSpec` visibility
  tightening + per-sample re-validation hot-path fix); no v0.4.0 git tag yet.
- No active feature branch; no open PRs.
- Known outstanding warnings: 8 `[0020]` Show-vs-Debug deprecations in
  `pattern/property_test.mbt` + `pattern/pattern_doc_test.mbt`, originating
  in `@qc.quick_check_fn`'s trait bound. Pinned on `moonbitlang/quickcheck`
  publishing ≥0.14.0 (verified: 0.13.0 still has the old bound). No action
  on our side until mooncakes ships 0.14.0.

For shipped-work history, read `CHANGELOG.md`. For the broader backlog
(quick wins, pre-1.0 API hygiene, Phase 6+ roadmap), read
`memory/project_backlog.md`.

## Recommended Next Slice

**Cut v0.4.0.** All breaking changes for this release have landed.
Sequence per `memory/project_010_release.md`:

1. Add PR #59 entries to the existing `[0.4.0]` block in `CHANGELOG.md`:
   `EnvStage` `pub(all)` → `pub`, `ChannelSpec` `pub(open)` → `pub`, and the
   hot-path per-sample re-validation fix in `Adsr::process` /
   `Oscillator::process_waveform`. Update the date to 2026-05-18 to match
   the actual tag date.
2. Run external Codex on the full `[0.4.0]` changelog block before tagging
   per `memory/feedback_codex_changelog_review.md`.
3. Atomic publish: `git tag -a v0.4.0` → `git push origin v0.4.0` →
   `gh release create v0.4.0 --notes-file CHANGELOG.md` →
   `moon publish --dry-run` → `moon publish`.

## Alternative Slices

- **`AudioBuffer::as_fixed_array` encapsulation cleanup** — quick win
  recorded in `memory/project_backlog.md`. Add `every`/`any`/`all`/`iter`
  methods to `AudioBuffer`, migrate ~150 read-only call sites, deprecate
  or privatize `as_fixed_array`. Single-PR scope, mostly test files.

- **`validate_voice_template` double-compile** — quick win recorded in
  `memory/project_backlog.md`. Run microbenchmark first (per
  `moonbit-perf-investigation`), then either add a fast topology
  validator on `CompiledTemplate` or cache the validation compile result
  for `note_on`.

- **Open another Phase 6+ slice** (per `memory/project_backlog.md`):
  incremental reparsing with loom, canopy structural editor, or
  per-sound parameter control. Each is multi-session scope; brainstorm
  before planning.

## Acceptance Checks For API-Hardening Slices

- Run `rtk moon info` and review `.mbti` diffs for intentional public API
  changes.
- Run `rtk moon fmt`, `rtk moon check`, and `rtk moon test`.
- If root facade or browser-relevant graph APIs changed, run
  `rtk moon build --target wasm-gc`.
- Update `docs/salat-engine-technical-reference.md` first for graph
  runtime-control behavior changes.
