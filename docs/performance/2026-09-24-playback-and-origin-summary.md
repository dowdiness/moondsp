# Playback and exact-origin findings — September 2026

Consolidates 2026-09-08–2026-09-24 investigations. Original version-controlled records are in the [pre-consolidation snapshot](https://github.com/dowdiness/moondsp/tree/5a8e495e5ba3524ebe856643fd0526eff3440430/docs/performance); standalone working-tree reports and replay archives were removed.

Measurements used release wasm-gc, Moon 0.1.20260904/07, Ryzen 7 6800H / Linux WSL2. Browser workloads used 48 kHz and **128 frames** per block (2.667 ms quantum). Page-local Wasm measurements are not AudioWorklet callback timings. Worklet `Date.now()` measurements resolve only integer milliseconds; muted/headless or WSLg output is not listening/loopback proof. Comparisons and their limits below are historical, not current release guarantees.

## Player bounds

The 2026-09-16 bounded-player study admitted all 30 shipped source examples (up to 2,201 characters). First-block render after 16 warmup and 64 measured operations: mean 0.648 ms, p95 0.9 ms, max 1.2 ms. Five pathological cases were rejected: four for query expansion and one for excessive Euclidean steps. Separate ingress checks rejected 8,193-character and 1 MiB inputs exceeding the 8,192-character cap. The 1 MiB input was rejected in 1.2 ms without changing state.

The pathological source was rejected, not rendered faster. Supported-workload and retained-state bounds do not establish allocation-free rendering or AudioWorklet deadline safety.

## Player owner

The 2026-09-16 page-local production-Wasm study used a 12-section, 2,851-character, 240-cycle score, 60 iterations and 750-block steady batches. Update p95 was **2.80 ms**, Restart p95 **2.90 ms**, against a 2.667 ms quantum. Steady render p95 of 0.26 ms is a distribution of batch means, not per-block p95; input transfer is excluded. No paired baseline was run.

The earlier 2026-09-08 unified-API study measured preparation p95 **3.30 ms** (max 4.80 ms). Separating prepare/apply/play APIs makes ownership explicit but does not move preparation off the audio owner or eliminate its allocations. These timings do not establish glitch-free playback.

## Player reliability

Release-Wasm admission checks rejected a finite endpoint outside the transport range and repeats shorter than one audio block while preserving accepted state and continued rendering. A repeat exactly one block long was accepted. These are correctness boundaries, not latency guarantees.

The 2026-09-08 preparation experiments exercised headless/headed playback, busy Workers and a full 121-second score. A deliberate 100 ms stall produced 138 underrun events / 1,604.25 ms missing output; ordinary trials observed none. This calibrated local experiment did not justify mandatory Worker migration or establish a release-wide underrun guarantee.

## Player review

The 2026-09-17 review-fix study (`67f2003` plus PR271 fixes) ran the actual scheduler AudioWorklet with 40 alternating 120/121 BPM edits. **Owner Update p95/max was 11 ms**, exceeding one quantum. Edited render p95 was 1 ms; about 69% of readings were zero (250 of 362, inferred from the integer-ms mean and maximum), so the clock could not resolve those callbacks. Interarrival gaps reached 24 ms both with and without edits in headless callback bursts; they are not audible-dropout evidence.

Retained-history stress hit the pending-material limit at round 256 after 766 updates. Rejected resubmission preserved state; Restart recovered. Deep malformed parser input was rejected while controls remained usable. All 30 supported sources produced finite stereo output. Source admission and retained-state limits are not hard-real-time guarantees.

## Playback visualization

The 2026-09-19 probe, based on `632233f9bb9bc9e463899a1902b02bb5f66c4115`, ran real DSP but generated **synthetic observation records**. It did not implement actual onset extraction, editor mapping or painted highlights. Its then-current provenance IDs were not exact authored-atom identities: successful delete/recreate reused `mini:note:c3:0`, and transformed paths could contain multiple atoms or end at a control node. This is a warning against using that representation as exact highlighting identity, not a prohibition on later exact-origin designs.

A one-credit transport with an eight-Float64 record, producer ring 64 and UI queue 4,096 was feasible in the local experiment, not approved for production. Dense drops were 8.2–8.7%; overflow drops 89.9%; no product loss budget was set. Allocation attribution, real onset integration and output-device verification were not established.

## Unified playback and authoring identity

Historical live-update validation queued all routes before rendering the next block and retained only the latest pending snapshot per route. Those results describe the measured revision; the current API remains defined by the scheduler guide and technical reference.

Other useful correctness findings:

- Anchored transport preserved exact position through repeated tempo edits and an eight-hour fractional-tempo query, within Int64 rational limits.
- Independent three-/four-cycle entries replaced at their own boundaries without postponement. A 128.5-sample entry was silent for an edit at sample 128 and audible at 129.
- Public transforms once retained content identity despite changing events, allowing a note filtered to silence to keep playing. Known transforms now update content identity; content comparison remains conservative and caller-supplied musical operations matter.
- Light Orbit live-edit comparisons matched both edited checkpoints and the original audio after cancelling an edit. Normalized-overlay construction was 15.8–23.8% more expensive in its snapshot; prepared two-material render was essentially unchanged (130.22→130.19 µs), not a causal speedup claim.

## Exact origin

The 2026-09-24 baseline was `0ca1f514822213cab90e4f16faa5c040778a7b20`. Release WAT retained query-time `OriginBindings.Link` and `EventOrigin` construction. The fix moved immutable origin preparation to cold atom compilation and forwarded completed origins through reference callbacks. Post-fix WAT no longer contained the old query-time origin-building closure; scoped values, paths, events and query arrays still allocated. Removing identified origin construction is not whole-render allocation freedom.

Cold compilation rose about **1.7×** for the nested workload (26.90→44.40–45.40 µs) and **2.7×** for 32 paths (96.77→256.43–262.85 µs). Nested query timings overlapped before/after; they did not establish a speedup. This trades cold preparation for immutable-origin reuse during queries.

A later cache comparison used that cold-origin implementation as its baseline. It adopted a directly accessible first entry and a sparse secondary context-hash index; full binding witnesses, epochs and dependency tokens remain checked on hash collisions. Rejected approaches:

- Forward binding paths: small atom-heavy improvement, worse large branching.
- Compile-only binding memo: improvement too small/inconsistent for added state.
- Hashing every lookup: better large cases, overhead on small cases.
- Cached fingerprints: did not remove that small-case cost.

Paired AB/BA cold preparation improved 15.0–16.4% at 512 paths and 6.7–10.3% at 128 paths, but regressed 1.6–7.9% at 32 paths. The original nested workload added 0.3–0.6 µs. This is a scalability tradeoff, not a universal speedup. Integrated Worklet arms accepted 40 updates and drained pending state; reported render maxima of 1–3 ms cannot establish exact deadline misses or compliance with an integer-ms clock. Retained heap, allocated bytes and GC-pause costs were not measured.

## Evidence omitted

Generic post-change full-suite timing dumps and validation-only reports had no controlled before/after baseline or additional decision-bearing conclusion. They were removed rather than copied into this summary. In-tree benchmarks remain available for new measurements; old test-pass counts are not evidence that the current checkout was tested during this documentation change.
