# ADR-0032: WAV reading and writing belong to an offline leaf, `codec/wav`, outside the engine

- **Status:** Proposed
- **Date:** 2026-11-27
- **Source:** [PR #287](https://github.com/dowdiness/moondsp/pull/287) by
  e780671166-netizen (commit `2db8138`); extraction in
  [Amp thread T-01a21aa6](https://ampcode.com/threads/T-01a21aa6-491f-72f4-832a-8f84a00f8cc2)
- **Refines:** [ADR-0001](0001-layered-package-architecture.md) (layered
  package architecture)
- **Related:** [ADR-0027](0027-scalar-trig-leaf.md) (a leaf package below
  the engine), [ADR-0026](0026-sample-playback.md) (recorded samples)

## Context

moondsp has no way to read or write audio files. PR #287 adds WAV and FLAC
codecs, a format-sniffing `decode_any`, offline rendering of Mini scores to
WAV, and unrelated fixes, in one commit of about 5,000 lines on an old base.
We take only its WAV part, which stands alone: the `codec/wav` package
imports nothing from moondsp and only `moonbitlang/core` from outside.

ADR-0001 sets the package layers, and ADR-0027 is the precedent for a leaf
that sits outside them and imports no moondsp package.

## Decision

1. **`codec/wav` is a leaf.** It depends only on `moonbitlang/core` (and on
   `moonbitlang/quickcheck` in its tests). It imports no moondsp package.

2. **It is for offline use only.** `decode` and `encode` allocate their
   results, so the audio path must never call them. dsp, graph, voice,
   scheduler, engine, and browser packages do not import `codec/wav`;
   `scripts/check-architecture-boundaries.sh` rejects such an import, on top
   of its per-package allowlists.

3. **The public API is `decode` and `encode` and what they need:**

   ```moonbit
   pub fn decode(Bytes) -> WaveFile raise WavError
   pub fn encode(format~ : WavSampleFormat, sample_rate~ : Int, channels~ : Int, samples~ : ArrayView[Double]) -> Bytes raise WavError
   ```

   - `WaveFile` has private fields, and only `decode` builds one. It reads
     back as `sample_rate`, `channels`, `frame_count`, `source_format`, and
     `samples`. `samples` is a `ReadOnlyArray`, so a caller cannot change
     the frame count behind `WaveFile`'s back.
   - `samples` are Doubles normalized to [-1, 1] and interleaved by channel,
     at the file's own sample rate. Mixing down to mono, converting to
     `Float`, and resampling for the sample store (ADR-0026 Decision 7)
     are the loader's job, not the codec's.
   - `WavError` is `pub`: callers match its cases but cannot construct them.
     `UnsupportedFormat` carries the format tag and bit depth; the other
     payloads are messages for people.
   - `encode` rejects any value its header cannot hold (a 16-bit
     `block_align`, a 32-bit byte rate) instead of writing a wrong header.
   - `WavSampleFormat` is `pub(all)`, because callers pass it to `encode`.
     One enum serves both directions: every format `decode` reads, `encode`
     can also write.

4. **Out of scope:** FLAC, `decode_any`, and `codec/render`, which PR #287
   also proposes. Each needs its own decision.

## Consequences

- ADR-0001's dependency rules hold: `codec/wav` adds no edge into `dsp` or
  any other layer, so `dsp`'s internal dependencies stay as ADR-0027 left
  them.
- The ffmpeg cross-check tests embed ffmpeg-made WAV files and the expected
  samples as hex, so they run on every CI target without ffmpeg. The script
  that generated them is not in the repository, so the fixtures cannot be
  regenerated.
- Whether adding FLAC brings in a `moonbitlang/x` dependency is for a later
  ADR.

## Rejected alternatives

- **Not taking WAV support.** Offline rendering, sample loading outside the
  browser, and tests that compare rendered audio all need a file format,
  and this package is small, standalone, and tested.
- **Taking all of PR #287.** It mixes several independent decisions (a new
  external dependency, FLAC, an offline renderer, and scheduler and voice
  fixes) and conflicts with the current main in four files.
- **Putting the codec inside `dsp`.** `dsp` holds allocation-free audio
  primitives; an allocating file parser would put code the audio path must
  not call next to code it does, and the boundary script could no longer
  keep them apart.
