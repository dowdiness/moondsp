# ADR-0016: Loom-backed runtime mini parser

- **Status:** Accepted (2026-06-10, PR #196)
- **Date:** 2026-06-10
- **Source:** Loom parser replacement campaign —
  [Phase 0 feasibility report](../superpowers/specs/2026-06-09-loom-parser-replacement-phase0-report.md)
  (GO, PR #189),
  [Phase 2 plan](../superpowers/specs/2026-06-09-loom-parser-replacement-phase2-plan.md)
  and its merged evidence (PR #190, #192, #194), and the Phase 2 provenance
  notes (`specs/loom-mini-cst/docs/phase2-provenance-notes.md`).

## Context

ADR-0004 shipped the hand-written recursive-descent runtime parser because
loom did not clear the wasm-gc risk gate inside the Phase 5 budget. ADR-0012
scoped a loom/CST evaluation outside production. ADR-0013 defined promotion
criteria and explicitly listed the runtime swap as a non-goal.

Since then the replacement campaign closed the gates that justified those
boundaries:

- **Phase 0 (feasibility, GO):** the consumed loom stack builds and its
  parser tests pass on wasm-gc, native, and js; its build graph contains only
  `dowdiness/*` packages plus `moonbitlang/core` (zero `moonbitlang/x/*`, so
  no native-FFI leak); a canary error adapter normalized loom's
  `DiagnosticSet` onto the production `Result[_, String]` + char-accessor
  contract; and the publish bundle provably excludes all `specs/` and
  loom-stack files. This retires ADR-0004's wasm-gc risk and ADR-0013's
  dependency-hygiene risk at canary scale.
- **Phase 2 (build/parity, complete):** the `specs/loom-mini-cst` spike
  proved doc-level value parity against the hand-written parser over an
  84-input corpus (66 parse Ok on both sides, 18 rejected by both): root/leaf
  IDs, `ControlMap` entries, and whole/part `TimeSpan`s over a fixed `[0, 8)`
  window, plus a corpus-driven provenance matrix and positive-control
  calibration tests that guard the harness itself (provenance notes, PR #190
  and #194). Separately, song-level parity
  (`specs/loom-mini-cst/src/song_projection_test.mbt`, PR #192) builds a real
  `@song.Song[ControlMap]` on both sides and compares by name and value —
  BPM, ordered occurrences, section name/length, per-section body events and
  whole-song query events over the parity windows — across 8 valid and 13
  malformed song inputs with its own positive control. The song evidence is
  real but narrower than the doc evidence: a smaller corpus and no leaf-ID
  axis (`Pat::query` carries no source IDs). Exactly one divergence survived
  triage across all of it, and it is a defect on the hand-written side (see
  "Intentional behavior change").

ADR-0013's forcing functions have also fired. The user-selected campaign
driver is the editor: structured syntax, ranges, and recoverable diagnostics
that the `Err(String)` parser cannot provide — the second forcing function on
ADR-0013's list. The consolidation function (one grammar source instead of
two drifting parser paths) is the secondary driver. Per ADR-0013, spec-local
parity alone was never approval; this ADR is the explicit decision that
clause required.

### The runtime surface being replaced

The runtime parser has exactly two production call sites, both in
`browser/internal/playback_host/playback_host.mbt`:

- `set_active_pattern_text` → `@mini.parse(text)` (pattern path), and
- `set_active_song_text` → `@mini.parse_song_with_bpm(text)` (song path).

CLAP/native never calls `mini.parse`; native is compile-only for the parser.
Each path has its own error accessors on the browser surface
(`get_pattern_error_length`/`get_pattern_error_char` and
`get_song_error_length`/`get_song_error_char`), which expose the `Err`
message as UTF-16 code units across the wasm-gc boundary. These exports are
pinned by `browser/browser_abi.baseline`.

Threading: the browser host (`web/processor.js`) invokes parsing inside the
AudioWorklet's `port.onmessage` handler. Per the AudioWorklet execution
model, the rendering thread services port messages outside `process()`
invocations — parsing is not inside the 128-sample `process()` callback, but
it shares the rendering thread, so an excessively slow parse can still delay
the next quantum (~2.67 ms at 48 kHz / 128 samples) and cause an audible
dropout. The hand-written parser already allocates in this context
today; the swap changes the amount of edit-time work, not which thread does
it. The relevant performance gate is therefore **edit-time parse latency in
the message-handler context**, not DSP throughput, and the audio-callback
zero-allocation audit (CLAP) is unaffected.

### The error-message gap the adapter must close

Phase 2's Err-message divergence table (18 rows, in the provenance notes) is
the contract input for the runtime error adapter:

- the hand-written parser always emits a character position
  (`position N: ...`); loom's projection-level messages never do, and
- 7 of 18 malformed inputs collapse to loom's generic
  `loom mini syntax has diagnostics`, because CST-level failures are
  flattened by the projection.

So the adapter must consume loom's **raw CST diagnostics** (the
`DiagnosticSet`, which carries primary spans), not the projection's flattened
string. Phase 0 prototyped exactly this shape in
`specs/loom-backend-canary/src/error_adapter.mbt`: first diagnostic → plain
string carrying an indexable offset, served through length/char accessors
byte-compatible with the production pair.

## Decision

Replace the implementations behind both runtime entry points —
`@mini.parse` and `@mini.parse_song_with_bpm` — with loom-CST-backed parsing,
keeping the `@mini` public surface, the browser ABI, and the error contract
frozen.

Specifically:

1. **Frozen public surface.** `@mini.parse(String) -> Result[Pat[ControlMap],
   String]` and `@mini.parse_song_with_bpm(String) -> Result[ParsedSong,
   String]` keep their signatures. `browser/` and `playback_host` callers do
   not change; `browser_abi.baseline` must remain byte-identical.
2. **Error contract preserved, position-bearing.** `Err` stays a plain
   `String` consumed by the existing length/char accessors. Messages must
   carry a character position derived from loom's raw CST diagnostics, so the
   browser error UX (position display) is preserved. Exact message text
   remains non-contractual, as in Phase 2.
3. **Both runtime paths swap together.** Swapping only the pattern path would
   leave two grammars in the runtime build and forfeit the consolidation
   driver. The song path's Phase 2 evidence is narrower than the doc path's
   (21 song inputs, structural name+value standard, no leaf-ID axis), so this
   ADR does not treat it as already sufficient: acceptance gate 1 requires
   the song corpus to be widened to the song-relevant malformed and edge
   families before the swap merges. If that widening surfaces divergences
   that cannot be closed within the phase, the song path's swap is deferred —
   the pattern path does not wait for it.
4. **Whole-source parsing only.** The browser protocol delivers complete
   pattern/song text per evaluation; no reactive parser state needs to
   persist across calls. Incremental reparse (`apply_edit` reuse) is an
   authoring concern and stays out of the runtime path.
5. **Registry dependencies only.** The loom stack enters the root `moon.mod`
   as published, versioned mooncakes dependencies — never path deps. This
   makes Phase 1 (publishing the loom stack) a hard prerequisite: this ADR is
   the integration demand the deferred-publish decision was waiting for.

## Relationship to prior ADRs

This ADR supersedes specific clauses rather than whole documents. On
acceptance:

- **ADR-0004** (hand-written runtime parser): the runtime-parser decision is
  superseded by this ADR. Its "revisit when" condition — verified wasm-gc
  support plus grammar growth pressure — is met (Phase 0; the editor driver).
  Mark ADR-0004 "Superseded by ADR-0016" when the swap ships.
- **ADR-0013** (promotion criteria): superseded clauses —
  - non-goal "Routing `mini.parse` … through loom" (the `mini.parse` part
    only);
  - non-goal "Adding loom, seam, or other loom-stack packages to the root
    `moon.mod`" (registry versions are now approved; path deps remain
    forbidden);
  - non-goal "Publishing, tagging, or otherwise unblocking a release" (Phase
    1 publish becomes a prerequisite of this decision);
  - non-goal "Treating shipped spec-local parity … as approval" (this ADR is
    the explicit approval that clause demanded);
  - promotion gate "Runtime isolation" (its own escape clause — "unless the
    browser build proof is part of the same decision" — is exercised here:
    the browser build proof is an acceptance gate below).

  ADR-0013 clauses that remain in force —
  - non-goal: routing `parse_doc` / `MiniAuthoringPipeline` through loom
    (the authoring swap is a separate later decision; until then production
    keeps the hand-written authoring parser, and the temporary cost is two
    parser implementations again — now in the opposite direction from
    ADR-0013's maintenance-cost note);
  - non-goal: changing the public `Result[_, String]` error shape;
  - non-goal: pulling nested spike path deps into releasable code;
  - the authoring promotion gates (full `PatternDoc` provenance, error
    recovery, semantic projection through a production-shaped authoring
    boundary) — they gate the authoring swap, not this one.
- **ADR-0012** (evaluation scope): unaffected; its evaluation completed and
  fed Phase 2. It is retired wholesale only when the hand-written parser is
  deleted (campaign Phase 4), alongside the remainder of ADR-0013.

## Non-goals

- The authoring swap (`parse_doc`, `MiniAuthoringPipeline`) and deletion of
  the hand-written parser — campaign Phase 4, separate decision.
- Fixing the hand-written parser's trailing-junk leniency in `mini/` — a
  candidate independent fix; this ADR only records the behavior delta below.
- Incremental runtime reparsing or editor wiring.
- Any change to the browser export surface, message protocol, or scheduler
  behavior.
- CLAP/native runtime parsing (none exists).

## Intentional behavior change: trailing-junk strictness

Phase 2's single sanctioned divergence: the hand-written notation parser does
not check end-of-input after the top-level layer, so a stray `]` is silently
ignored and everything after it is silently dropped — `s("bd] sd")` plays
only `bd`. Loom rejects such input with diagnostics.

After the swap, inputs that previously played truncated patterns will return
parse errors instead. This ADR declares that strictness change intentional
and user-visible: silent data loss is a defect, not a compatibility surface.
The pinned characterization test (`known divergence: oracle silently drops
trailing junk after stray ']'…` in the spike) documents both sides; if the
hand-written parser gains the end-of-input check before the swap ships, the
delta disappears and the corpus folds those inputs into the malformed set.

## Acceptance gates

The swap merges only when all of these hold, in the shipped `mini/` package
(not the spike):

1. **Differential parity at the real boundary.** The Phase 2 doc corpus (all
   84 inputs) and the song corpus run against the new loom-backed
   `@mini.parse` / `@mini.parse_song_with_bpm` with the hand-written parser
   as oracle — same value-level standard as Phase 2 (Ok/Err agreement;
   lowered events over the `[0, 8)` window; song structure by name and
   value). Before this gate counts, the song corpus must be widened from its
   Phase 2 size (8 valid / 13 malformed) to cover the song-relevant
   malformed and edge families at the same systematic standard the doc
   corpus reached in Piece 4. The hand-written parser still exists during
   Phase 3 (the authoring path uses it), so this is a directly testable
   in-repo differential gate, including a positive control proving the
   harness can fail.
2. **Error-position parity.** Every corpus Err case yields a message carrying
   a character position through the production accessors, built from raw CST
   diagnostics — eliminating the 7/18 generic-collapse rows. Message text
   stays non-contractual. The song error channel also carries non-parser
   failures (`route_songs_for_current_routes` routing errors share
   `get_song_error_*`); those are outside the parser swap and must be shown
   unchanged by a routing-failure regression case through the same
   accessors.
3. **Edit-time performance.** A microbenchmark compares loom-backed and
   hand-written parse latency over the full corpus (per the repo benchmark
   rule: `moon bench`, dated snapshot under `docs/performance/`). Hard gate:
   the maximum observed loom-backed parse latency over the corpus stays
   under half the render-quantum period (≤ 1.3 ms at 48 kHz / 128 samples)
   on the benchmark host. The loom/hand-written latency ratio is recorded in
   the snapshot as context, not as a gate. The browser E2E check below must
   show no audible-dropout symptom on the parse path.
4. **Build, ABI, and browser proof.** With the loom stack in the root
   `moon.mod`: `moon check`, full `moon test`, and
   `moon build --target wasm-gc` pass; `browser_abi.baseline` is unchanged;
   the Playwright browser tests pass against the rebuilt worklet wasm,
   including a parse-error path exercising the position accessors.
5. **Release-manifest proof.** Re-run the Phase 0 Check #4 procedure against
   the new dependency set: publish-bundle inspection shows no `specs/` or
   path-dep leakage, with a positive control validating the detector. All
   loom-stack imports resolve to registry versions.
6. **Pinned-registry build proof.** The full build and test suite passes in
   an environment with no sibling `canopy`/`loom`/`incr` checkouts and no
   path-dep overrides — every loom-stack dependency resolves from the
   registry at an explicitly pinned version, and each pinned version
   demonstrably contains the fixes the spike's build prerequisite names
   (the incr `518305d` diamond-dependency era). CI satisfying gate 4 on a
   clean runner is the natural witness; the point is that the swap must not
   silently depend on the sibling-checkout operational prerequisite that
   Phase 0 and the spike tolerated.

## Sequencing

1. **Accept this ADR** (Codex design validation per repo discipline).
2. **Phase 1 — publish the loom stack.** Enumerate the publish closure from
   Phase 0's recorded build graph — `loom`, `seam`, `pretty`, `text_change`,
   plus the transitive `canopy` and `moji` packages that appeared in the
   canary graph (`incr` is already on mooncakes and pinned) — and publish
   whatever subset is actually consumed, with versions containing the
   incr-`518305d`-era fixes the spike already requires. Publishing now is
   consistent with the deferred-publish decision: Phase 3 is the integration
   demand it was waiting for, and Phase 2's completion means loom's
   parser-facing API has parity evidence behind it, addressing the
   version-churn concern that justified deferral.
3. **Phase 3 — the swap itself**, gated by the acceptance list above. The
   grammar and projection knowledge ports from the spike into shipping
   `mini/`; the spike remains untouched as the characterization record until
   Phase 4 retires it.
4. **Phase 4 (later, separate decision)** — authoring swap, hand-written
   parser deletion, and wholesale supersession of ADR-0004/0011/0012/0013.

## Consequences

**Positive**

- One grammar source for runtime parsing, with CST structure, spans, and
  recoverable diagnostics available to the future editor path — the campaign
  driver.
- Parse errors gain uniform, span-derived positions; the silent-truncation
  defect class is rejected instead of played.
- The loom stack becomes a published, versioned dependency — ending the
  sibling-path-dep era for everything downstream of this decision and making
  the spike's evidence reproducible in CI.

**Negative / accepted costs**

- Until Phase 4, production again carries two parser implementations
  (loom runtime, hand-written authoring) — the mirror image of ADR-0013's
  maintenance-cost note, accepted as a transitional state.
- moondsp's build and release graph takes on the loom-stack registry
  dependencies and their version-coordination cost (the cost ADR-0013 priced
  as "main-package dependency cost").
- Edit-time parse cost is expected to rise (CST construction plus projection
  versus direct recursive descent); gate 3 bounds it, but the floor is
  unlikely to match the hand-written parser.
- A class of previously-accepted (silently truncated) inputs becomes errors —
  intentional, but visible to existing users.
