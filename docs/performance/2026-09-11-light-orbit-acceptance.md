# Light Orbit: live-edit acceptance

The [named score](../../examples/light-orbit.mini) reuses the two melodies,
drums, harmony, bass, and a drum group across 12 sections. This example already
exists on main; the playback changes make edits wait for each material's next
entry. The [equivalence test](../../mini/orbit_fixture_test.mbt) passes for all
240 cycles and the finite ending, comparing every event with the original score.

## Audio comparison

A temporary native test used the production browser-host preparation, routing,
scheduler, voice pools, and rendering path. Four runs started the complete score
at 120 BPM, 48 kHz, with 128-sample blocks. At sample 312064, just after cycle 13,
they submitted respectively:

1. The unchanged score.
2. A change from E4 to F#4 in the shared motif.
3. The motif change plus a change of the shared orbit to Eb5 Bb4 Ab4 F5.
4. Both changes followed by the original score, cancelling the edit.

Each run submitted invalid song text after the first update. Preparation failed
without discarding the accepted edit. Three left-channel blocks were compared:

| Block start | Position | Observed result |
| --- | --- | --- |
| 332800 | Before cycle 15 | Both edits match the original audio exactly |
| 371200 | Between cycles 15 and 16 | Both edits match the motif-only edit; they differ from the original |
| 396800 | After cycle 16 | Both edits differ from the motif-only edit |

The cancellation run matches the original at all three checkpoints. These
results locate the two changes on opposite sides of their distinct entries:
the three-cycle motif restarts at 15, and the four-cycle orbit at 16. Exact
boundary timing is covered by the scheduler's permanent sample-boundary tests.

The temporary test passed and was removed to avoid maintaining three additional
copies of the full song. Small permanent playback tests cover the underlying
entry, invalid-input, and cancellation contracts. The Live UI acceptance test
loads the example file directly and exercises shared-material edits, invalid
input, reverting, and Stop through the editor and AudioWorklet.

## Scope and limits

This is automated event and audio comparison, not subjective listening approval.
Only the early two-melody section was rendered for the edit comparison; the
whole-score equivalence check queries events without rendering the entire song.
UI receipts acknowledge acceptance, not the instant every material becomes
audible. Layout changes still require Stop then Play. Effects and
transport-position UI are separate work.
