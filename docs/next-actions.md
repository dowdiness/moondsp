# Next Actions

Updated: 2026-09-12

Forward-looking handoff only. Per-PR history belongs in `git log`; released
behavior belongs in `CHANGELOG.md`.

## Current State

- `main` includes PR #241 (`ca940d7`), which adds one shared stereo room-reverb
  bus across synth and drum routes.
- Browser live playback supports pattern and song inputs, immutable named
  pattern definitions, prepared score updates, playback-position preservation,
  next-material-entry edit application, independent synth-note envelopes, and
  a single Play/Stop transport.
- Production browser playback still selects Triangle while issue #212's
  affected-Windows real-time Sine crackle matrix remains unresolved. The local
  page-thread and offline AudioWorklet probes produce identical PCM; do not
  change DSP behavior without the missing real-time evidence.
- The native CLAP path remains a prototype. Validator, allocation audit, bridge
  guard, and one Bitwig/Windows load are complete; broader real-host coverage is
  tracked by issue #180.
- Phase 6 incremental authoring remains in progress. Runtime Mini parsing and
  `MiniAuthoringPipeline` have separate promotion boundaries; do not move the
  authoring path to Loom without a new decision satisfying ADR-0013's remaining
  gates.
- PR #86 prepares release `v0.6.0`. It updates release metadata only; do not tag
  or publish until the release checks and PR review complete.

## Recommended Next Slice

After `v0.6.0`, migrate `dowdiness/incr` from `0.9.0` to `0.14.0` under issue
#226.

Keep the migration bounded to the published API changes recorded by that issue:
`Signal` → `Input`, `Memo` → `Derived`, scope constructor updates, and
`PatternDoc` revision tracking. Do not combine it with Mini syntax, Loom
promotion, or a new incremental-parser design.

## Conditional Reliability Slice

If the affected Windows/Chrome environment is available, issue #212 outranks
new feature work:

1. Run the existing real-time harness across scheduler/direct, Triangle/Sine,
   gain, sample-rate, and latency-hint variants.
2. Save the JSON telemetry and a human audible verdict for each run.
3. Change production behavior only if that evidence isolates a source-level
   mitigation.

## Alternative Slices

- **Mini `+` overlay sugar (#217)** — lower directly to the existing `stack`
  algebra. Keep numeric addition and `ControlMap` merging out of scope.
- **Browser protocol/status (#156, #216)** — document the compiled-demo versus
  live-scheduler worklet split, then add only status or room controls justified
  by a concrete live UI consumer.
- **CLAP real-host coverage (#180)** — record two additional hash-verified
  host/OS results before changing the prototype status.

## Deferred

- Implicit top-level newline overlay (#219) until song-mode, comment, blank-line,
  and coexistence semantics are specified.
- Broad `browser/internal/playback_host` cleanup (#214) without a concrete
  defect or measured maintenance problem.
- Loom-backed authoring-parser promotion without the remaining ADR-0013 gates.
- Offline rendering until it has a tracking issue, boundary, and acceptance
  criteria.

## Acceptance Checks

- Normal code/docs slices: `NEW_MOON_MOD=0 moon check --deny-warn` and
  `NEW_MOON_MOD=0 moon test --release`.
- Architecture boundary changes:
  `./scripts/check-public-boundary.sh` and
  `./scripts/check-architecture-boundaries.sh`.
- Browser facade/export changes: `./scripts/check-browser-abi.sh`; update
  `browser/browser_abi.baseline` only for reviewed intentional ABI changes.
- Release prep: also run `NEW_MOON_MOD=0 moon info`,
  `NEW_MOON_MOD=0 moon fmt`, and `NEW_MOON_MOD=0 moon package --list`, then
  inspect the generated package contents.
- Graph runtime-control behavior changes: update
  `docs/salat-engine-technical-reference.md` first.
