# Playback admission and commit

## Decision

Validate continuing tempo changes in the audio-owner admission operation,
before replacing its pending request. A rejected request must preserve the
current score, transport, and previously accepted pending request. Commit at
the next block applies the validated request without a recoverable rejection.

This decision applies to the current browser playback host. It is based on its
state ownership and exported operations, not a general claim that validation
can always precede asynchronous execution.

## Problem

Accepting a song update before checking tempo representability permits a later
render-block rejection after the JS controller has queued a success receipt.
Audio then keeps the old state while the UI records the rejected score and
tempo. Admission must prevent this disagreement.

The failure is reachable with this valid expression, after one 128-sample block
at 48 kHz, followed by a continuing edit of BPM to 1000:

```js
song(bpm(0.001),
  section("a",1,
    note("60").fast(10000019).fast(100000003).slow(100000000)),
  part("r","a"))
```

Rejecting an unrepresentable conversion is allowed. Reporting that rejection
as a successful update is not.

## Evidence and alternatives

Web Audio separates synchronous validation from queued rendering work, and
processes rendering-side tasks before a render quantum. This supports ordered
application but does not itself prove a queued operation cannot fail. See
[Web Audio 1.0, rendering](https://www.w3.org/TR/webaudio-1.0/#rendering-a-graph)
and the [1.1 draft rendering loop](https://www.w3.org/TR/webaudio-1.1/#rendering-a-graph).

SuperCollider distinguishes command completion and failure, and correlates
`/sync` completion with an ID. This is useful when completion is genuinely
asynchronous; it does not require a mailbox between two synchronous calls in
one worklet. See [Server Command Reference](https://doc.sccode.org/Reference/Server-Command-Reference.html).

JACK prohibits blocking work in the process callback. Moving validation to an
AudioWorklet message handler does not move it off the rendering thread or
establish an allocation-free callback. See [JACK callback contract](https://jackaudio.org/api/group__ClientCallbacks.html).

| Option | Assessment for this host |
| --- | --- |
| Read the shared last-error string after rendering | Reject: a later invalid input can overwrite it while a valid request remains pending. |
| Return a typed commit outcome from block processing | Sound fallback if commit remains fallible; changes the WASM result contract and both worklet adapters. No mailbox is needed for this synchronous handoff. |
| Add a revision-tagged outcome mailbox | Useful across independent producers/consumers; unnecessary state, capacity rules, and draining here. |
| Commit immediately in the message handler | Changes restart, supersession, and applied-score ordering before a block is rendered. Broader than needed. |
| Validate at admission; apply at the block boundary | Selected, subject to the invariant below. Keeps the existing request and receipt protocol. |

## Why admission remains valid

Tempo validation uses the proposed tempo, clock anchor sample and ticks,
sample-rate scale, block size, and active notes' musical endpoints.

The current host owns these inputs and its pending request privately:

- `process_scheduler_block` commits before advancing time or querying new notes.
- Preparation, replacement, input errors, and gain changes do not alter those
  clock inputs or musical endpoints.
- Direct BPM changes alter tempo and cached sample endpoints. They do not alter
  clock anchor ticks/sample or musical endpoints. Validation of a proposed
  tempo replaces the current tempo, so the result is unchanged.
- Restart requests replace the pending request. Restart commit clears old notes
  and resets the clock before using a tempo already checked during preparation.
- Reset and initialization clear pending requests; they cannot apply an old
  validated request against a new engine.

Therefore, for a request that remains pending, admission and commit see the
same inputs relevant to its representability check. This is a code-specific
inference from `live_update.mbt`, `playback_host.mbt`, `transport_facade.mbt`,
and `internal/transport/clock.mbt`.

Keep this invariant inside the host. A future independent clock advance,
sample-rate mutation, scheduled command, or externally injected active note
must revisit it. If inputs can change, use the typed block outcome alternative;
do not rely on stale validation or duplicate a recoverable check silently.

## Implementation and validation

1. Perform layout admission and continuing-tempo validation before publishing
   the new pending state or consuming its prepared token.
2. On failure, use the existing immediate apply-error response. Keep the earlier
   pending request and its JS receipt association intact.
3. Remove the recoverable rejection branch from commit. Treat any violation of
   the proven invariant as an internal defect, not an ignored setter failure.
4. Preserve delayed receipts and existing supersession semantics. Receipt success
   means the edit reservation is accepted, not that every material is audible.

A temporary prototype moved only the preflight location. It checked rejection
of the expression above, preservation of a prior valid request, a subsequent
parse error, an intervening direct BPM change, and successful commit of the
prior request. Existing host tests additionally cover reset, restart, layout
rejection, tempo edits, and invalid tokens. No public ABI or JS protocol change
was needed. All 19 host tests, including the probe, passed on JS, wasm-gc, and
native with moon 0.1.20260814. Prototype source was restored after testing.

The implementation retains one host regression for admission and reservation
preservation and one real-WASM controller regression checking that the rejected
revision gets an error while the valid pending revision gets its receipt.
Commit uses the scheduler's checked setter with an assertion of success, so an
internal invariant violation cannot silently turn into a success receipt.
No numeric-range expansion or new queue infrastructure is part of this fix.

## Product validation

The regression failed before the fix and passed afterward. Full JS, wasm-gc,
and native suites each passed 1,114 tests. The browser suite passed 27 tests
and Live UI passed 36 tests, with no retries. Release WASM and Live builds,
asset hash agreement, and all five boundary checks passed.

All 60 existing release benchmark groups passed with moon 0.1.20260814.
[Raw results](../performance/2026-09-11-playback-admission-benchmarks.txt) were
collected with `NEW_MOON_MOD=0 moon bench --release` in a temporary target
directory, overlapping builds and browser tests. They are a regression snapshot,
not a controlled speed comparison or a measurement of this admission path alone.
