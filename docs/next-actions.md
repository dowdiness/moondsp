# Next Actions

Updated: 2026-05-11

This is the active handoff list for future sessions. It should stay short and
actionable; move completed design notes or implementation plans under
`docs/superpowers/{specs,plans}/archive/` when they ship.

## Current State

- `main` is clean and pushed through `195acc3 feat: add topology queue result APIs`.
- Core silent-failure hardening shipped so far:
  - `GraphControlError` result APIs for direct compiled mono/stereo graphs.
  - `HotSwapQueueError` result APIs for mono/stereo hot-swap queues.
  - `GraphTopologyQueueError` result APIs for mono/stereo topology edit queues.
  - runtime-control `GraphControlError` result APIs for mono/stereo hot-swap
    and topology wrapper controls.
  - `BoundVoicePool` owns template validation and `ControlBindingMap` lifetime,
    so `PatternScheduler` no longer carries stale bindings.
- Latest full verification for topology queue result APIs:
  - `rtk moon fmt`
  - `rtk moon info`
  - `rtk moon check`
  - `rtk moon test`
  - `rtk moon build --target wasm-gc`
  - `rtk git diff --check`

## Recommended Next Slice

1. Add browser error visibility for queue/control failures.

   Keep the wasm-facing boolean exports if that is easiest for the browser ABI,
   but route internals through result APIs and expose a small last-error
   string/code helper for hot-swap, topology, and runtime-control paths.

2. Decide whether topology edit diagnostics need to be more precise.

   `GraphTopologyQueueError::InvalidEdit(index)` is intentionally compact. If
   callers need richer edit-shape reasons, expand it before the topology queue
   API hardens further. Otherwise leave it as the stable contract.

3. Start Phase 6 design after the browser error-visibility decision is settled.

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
