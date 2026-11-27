# Audio codec: WAV (`codec/wav`)

`codec/wav` gives moondsp a pure MoonBit WAV reader and writer, with no FFI; it builds for js / wasm-gc / native.

| Package | Responsibility | Dependencies |
|---|---|---|
| `codec/wav` | RIFF/WAVE decoding and encoding | core only |

## WAV (`codec/wav`)

Decoding supports RIFF (little-endian) and RIFX (big-endian) containers; PCM u8/i16/i24/i32 and IEEE
float32/64; WAVE_FORMAT_EXTENSIBLE (0xFFFE, including the SubFormat GUID). Unknown chunks
(LIST/INFO and others) are skipped, honoring even-byte padding. Every structural defect returns a structured error instead of panicking.

```moonbit
// Decode: interleaved finite Double samples (PCM in [-1, 1))
let file : WaveFile = @wav.decode(bytes)
file.sample_rate() // Int
file.channels()    // Int
file.samples()     // ReadOnlyArray[Double] (interleaved by channel)
file.source_format() // WavSampleFormat

// Encode: six sample formats; more than 2 channels writes EXTENSIBLE; an odd data chunk is zero-padded
let bytes : Bytes = @wav.encode(format=PcmI16, sample_rate=48000, channels=2, samples~)
```

Samples are finite reals with nominal full scale ±1. PCM scales by 2^(bits-1) (an exact dyadic
fraction), rounds to the nearest step with ties to even (as ffmpeg does), and clamps to
[-1, 1 - 2^-(bits-1)], so `decode(encode(x))` is idempotent. float32 rounds to the nearest `Float`
and float64 is stored bit for bit; neither clamps, so float files may exceed ±1. `encode` and
`decode` reject NaN and ±Inf, and float32 values past its range, with `NonFiniteSample(index~)`.

## Support matrix

| Capability | js | wasm-gc | native | Notes |
|---|---|---|---|---|
| WAV decode/encode | ✅ | ✅ | ✅ | Pure MoonBit, no FFI |

## Tests

The contract of `codec/wav` is written as QuickCheck properties in
[`codec/wav/wav_spec_test.mbt`](../codec/wav/wav_spec_test.mbt). Each states one rule:

1. `encode` accepts exactly the inputs a WAV file can describe: header fields that fit, and
   samples that stay finite in the chosen format.
2. `encode` lays out RIFF, fmt, and data chunks as the format defines.
3. `decode(encode(x))` keeps the sample rate, channels, frames, and format.
4. Each sample comes back as the format stores it: PCM rounded to the nearest step with
   ties to even and clamped, float32 rounded to `Float`, float64 bit for bit.
5. PCM quantization keeps order and is symmetric in sign.
6. `encode(decode(encode(x))) == encode(x)`.
7. Byte order (RIFF/RIFX) and unknown chunks do not change decoded samples.
8. `decode` is total: any bytes either raise `WavError` or give a consistent `WaveFile`, whose
   samples are all finite; float data decodes exactly when every sample is finite.

Expected values come from the format itself, not from the code under test, and the
generators favor full scale, half steps, values past ±1, non-finite input, and header
fields at their limits. `wav_test.mbt` keeps hand-built examples, and
`ffmpeg_crosscheck_test.mbt` compares five formats sample by sample against ffmpeg.

## License and sources

- New code in this directory follows the repository LICENSE (Apache-2.0)
- The WAV codec design follows the module of the same name in [yabaobao070510/moonvoice](https://github.com/yabaobao070510/moonvoice)
  (Apache-2.0); the code is an independent implementation
- AI tool use: the codec code was generated with AI assistance; its correctness is backed by the tests above and
  the external ffmpeg cross-check
