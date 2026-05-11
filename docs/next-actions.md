# Next Actions

Updated: 2026-05-11

This is the active handoff list for future sessions. It should stay short and
actionable; move completed design notes or implementation plans under
`docs/superpowers/{specs,plans}/archive/` when they ship.

## Current State

- `main` was last pushed through `a15d572 feat: add wrapper control result APIs`;
  current working tree contains the browser queue/control error-visibility
  slice.
- Core silent-failure hardening shipped so far:
  - `GraphControlError` result APIs for direct compiled mono/stereo graphs.
  - `HotSwapQueueError` result APIs for mono/stereo hot-swap queues.
  - `GraphTopologyQueueError` result APIs for mono/stereo topology edit queues.
  - runtime-control `GraphControlError` result APIs for mono/stereo hot-swap
    and topology wrapper controls.
  - browser graph queue/control paths expose last-error string/code helpers
    while preserving the boolean wasm ABI.
  - `BoundVoicePool` owns template validation and `ControlBindingMap` lifetime,
    so `PatternScheduler` no longer carries stale bindings.
- Latest full verification for browser queue/control error visibility:
  - `rtk moon fmt`
  - `rtk moon info`
  - `rtk moon check`
  - `rtk moon test`
  - `rtk moon build --target wasm-gc`
  - `rtk node --check web/processor.js`
  - `rtk npm run test:browser`
  - `rtk git diff --check`

## Recommended Next Slice

1. Decide whether topology edit diagnostics need to be more precise.

   `GraphTopologyQueueError::InvalidEdit(index)` is intentionally compact. If
   callers need richer edit-shape reasons, expand it before the topology queue
   API hardens further. Otherwise leave it as the stable contract.

2. Start Phase 6 design after the topology diagnostic decision is settled.

   The Phase 6 design should focus on stable IDs, incremental invalidation
   boundaries, and how pattern/DSP graph edits map onto existing result-typed
   control, hot-swap, topology, and bound voice-pool APIs.

## Acceptance Checks For API-Hardening Slices

- Run `rtk moon info` and review `.mbti` diffs for intentional public API
  changes.
- Run `rtk moon fmt`, `rtk moon check`, and `rtk moon test`.
- If root facade or browser-relevant graph APIs changed, run
  `rtk moon build --target wasm-gc`.
- Update `docs/salat-engine-technical-reference.md` first for graph
  runtime-control behavior changes.
