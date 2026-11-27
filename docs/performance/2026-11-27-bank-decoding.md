# Decoding the built-in bank's recordings

Measured 2026-11-27 with
[`decode-check.cjs`](../../scripts/bench-sample-copy/decode-check.cjs), which
decodes each FLAC file under `web/live/public/samples/vcsl/` with
`decodeAudioData` in an `OfflineAudioContext` at 48 kHz and at 44.1 kHz, and
compares the 48 kHz result with ffmpeg 7.1's decode of the same file.

## Results

| Browser | Channels | Length at 48 kHz | Largest difference from ffmpeg | Length at 44.1 kHz |
|---|---|---|---|---|
| Chromium 159 (Playwright, Linux) | 1 | as encoded | 1.53 × 10⁻⁵ (half a 16-bit step) | 44,100/48,000 of it, within 1 sample |
| Firefox 159 (Playwright, Linux) | 1 | as encoded | 0 | 44,100/48,000 of it, exactly |
| WebKit 27.2 (Playwright, Linux) | 1 | as encoded | 0 | 44,100/48,000 of it, exactly |
| Safari 27.2 (macOS 27.2, Mac satellite) | 1 | as encoded | 0 | 44,100/48,000 of it, exactly |

For example, `piano_c2` is 576,000 samples at 48 kHz and 529,200 at
44.1 kHz in every browser. Peaks stay within 0.47–0.505 after resampling
(0.5 as encoded). Safari also decoded every file in a live `AudioContext`,
which ran at 48 kHz on that Mac.

So the bank's files load unchanged into a context at either rate:
`decodeAudioData` resamples to the context's rate, and the store holds
waveforms at the engine's rate (ADR-0026), so roots stay where they are.

Safari ran the committed script through `safari-driver.cjs` on a Mac
satellite, with ffmpeg 7.1's decode as the reference.

## Limits

- At 176.4 kHz, `piano_c2` (12 s) resamples to about 2.12 million samples,
  over the 1,440,000-sample waveform limit, and is refused as `length`.
- At 192 kHz the bank needs about 9.0 million samples, over the 8,388,608
  total, so the last loads are refused as `memory`.

Both show on the sample status channel as over-limit, as ADR-0026 Decision 6
designs.

```sh
REFS=$(mktemp -d)
for f in web/live/public/samples/vcsl/*.flac; do
  ffmpeg -v error -i "$f" -f f32le -acodec pcm_f32le "$REFS/$(basename "$f" .flac).f32"
done
NODE_PATH=web/live/node_modules node scripts/bench-sample-copy/decode-check.cjs "$REFS" chromium
```
