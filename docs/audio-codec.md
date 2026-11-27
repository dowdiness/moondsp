# Audio codec: WAV (`codec/wav`)

`codec/wav` gives moondsp a pure MoonBit WAV reader and writer, with no FFI; it builds for js / wasm-gc / native.

| Package | Responsibility | Dependencies |
|---|---|---|
| `codec/wav` | RIFF/WAVE decoding and encoding | core (debug) |

## WAV (`codec/wav`)

Decoding supports RIFF (little-endian) and RIFX (big-endian) containers; PCM u8/i16/i24/i32 and IEEE
float32/64; WAVE_FORMAT_EXTENSIBLE (0xFFFE, including the SubFormat GUID). Unknown chunks
(LIST/INFO and others) are skipped, honoring even-byte padding. Every structural defect returns a structured error instead of panicking.

```moonbit
// Decode: interleaved Double samples in [-1, 1]
let file : WaveFile = @wav.decode(bytes)
file.sample_rate() // Int
file.channels()    // Int
file.samples()     // Array[Double] (interleaved by channel)
file.source_format() // WavSampleFormat

// Encode: six sample formats; more than 2 channels writes EXTENSIBLE; an odd data chunk is zero-padded
let bytes : Bytes = @wav.encode(format=PcmI16, sample_rate=48000, channels=2, samples~)
```

Quantization: PCM scales by 2^(bits-1), rounds, and clamps (an exact dyadic fraction),
so `decode(encode(x))` is idempotent; float32/64 are stored bit for bit. NaN becomes 0 and ±Inf becomes full scale.

## Support matrix

| Capability | js | wasm-gc | native | Notes |
|---|---|---|---|---|
| WAV decode/encode | ✅ | ✅ | ✅ | Pure MoonBit, no FFI |

## Tests

- `codec/wav`: 23 tests (idempotent round trips, RIFX, EXTENSIBLE, LIST skipping, structured errors,
  12k fuzz inputs with zero panics, 400 quickcheck property cases, sample-by-sample ffmpeg cross-check of five formats)

## License and sources

- New code in this directory follows the repository LICENSE (Apache-2.0)
- The WAV codec design follows the module of the same name in [yabaobao070510/moonvoice](https://github.com/yabaobao070510/moonvoice)
  (Apache-2.0); the code is an independent implementation
- AI tool use: the codec code was generated with AI assistance; its correctness is backed by the tests above and
  the external ffmpeg cross-check
