// The specification of codec/wav, written as QuickCheck properties.
//
// Each test "spec N: ..." states one rule of the contract. Expected values are
// computed here from the WAV format itself (field widths, the 2^(bits-1) PCM
// scale), never from the code under test. Generators lean on the edges where
// codecs break: full scale, half-LSB points, values past ±1, non-finite input,
// and header fields at their 16- and 32-bit limits.
//
// 1. encode accepts exactly the inputs a WAV header can describe.
// 2. encode lays out RIFF, fmt, and data chunks as the format defines.
// 3. decode(encode(x)) keeps the sample rate, channels, frames, and format.
// 4. Each sample comes back as the format stores it: PCM rounded to the
//    nearest step (clamped, NaN as 0), float32 rounded to Float, float64 exact.
// 5. PCM quantization keeps order.
// 6. encode(decode(encode(x))) == encode(x).
// 7. Byte order (RIFF/RIFX) and unknown chunks do not change decoded samples.
// 8. decode is total: any bytes either raise WavError or give a consistent
//    WaveFile.

///|
#derive(Debug)
priv struct Case {
  format : @wav.WavSampleFormat
  sample_rate : Int32
  channels : Int32
  samples : Array[Double]
}

///|
fn bits_of(format : @wav.WavSampleFormat) -> Int32 {
  match format {
    PcmU8 => 8
    PcmI16 => 16
    PcmI24 => 24
    PcmI32 => 32
    IeeeF32 => 32
    IeeeF64 => 64
  }
}

///|
fn is_pcm(format : @wav.WavSampleFormat) -> Bool {
  !(format is (IeeeF32 | IeeeF64))
}

///|
fn encode_case(c : Case) -> Bytes? {
  try
    @wav.encode(
      format=c.format,
      sample_rate=c.sample_rate,
      channels=c.channels,
      samples=c.samples,
    )
  catch {
    _ => None
  } noraise {
    bytes => Some(bytes)
  }
}

///|
fn decode_or_none(bytes : Bytes) -> @wav.WaveFile? {
  try @wav.decode(bytes) catch {
    _ => None
  } noraise {
    file => Some(file)
  }
}

///|
fn u16_le(bytes : Bytes, off : Int32) -> Int32 {
  bytes[off].to_int() | (bytes[off + 1].to_int() << 8)
}

///|
fn u32_le(bytes : Bytes, off : Int32) -> Int64 {
  u16_le(bytes, off).to_int64() | (u16_le(bytes, off + 2).to_int64() << 16)
}

// Generators

///|
fn gen_format() -> @cqc.Generator[@wav.WavSampleFormat] {
  @cqc.elements([PcmU8, PcmI16, PcmI24, PcmI32, IeeeF32, IeeeF64])
}

///|
fn gen_pcm_format() -> @cqc.Generator[@wav.WavSampleFormat] {
  @cqc.elements([PcmU8, PcmI16, PcmI24, PcmI32])
}

///|
/// Samples biased to the values where quantization goes wrong.
fn gen_sample() -> @cqc.Generator[Double] {
  let unit = @cqc.Generator((_, rs) => rs.next_double() * 2.0 - 1.0)
  let wide = @cqc.Generator((_, rs) => rs.next_double() * 8.0 - 4.0)
  // Points on a 2^-17 grid, which includes every 16-bit half step
  let half_steps = @cqc.int_range(-131072, 131072).map(k => {
    k.to_double() / 131072.0
  })
  let special = @cqc.elements([
    0.0,
    -0.0,
    1.0,
    -1.0,
    32767.0 / 32768.0,
    1.0000001,
    -1.0000001,
    0.5 / 32768.0,
    -0.5 / 32768.0,
    1.5 / 32768.0,
    -1.5 / 32768.0,
    0.5 / 128.0,
    -0.5 / 128.0,
    1.0e300,
    -1.0e300,
    5.0e-324,
    0.0 / 0.0,
    1.0 / 0.0,
    -1.0 / 0.0,
  ])
  @cqc.frequency([(4, unit), (3, half_steps), (2, special), (1, wide)])
}

///|
fn gen_case() -> @cqc.Generator[Case] {
  let gen_channels = @cqc.frequency([
    (8, @cqc.int_range(1, 4)),
    (1, @cqc.int_range(5, 20)),
  ])
  let gen_rate = @cqc.frequency([
    (4, @cqc.elements([8000, 22050, 44100, 48000, 96000])),
    (1, @cqc.int_range(1, 1000000)),
  ])
  gen_format().flat_map(format => {
    gen_channels.flat_map(channels => {
      gen_rate.flat_map(sample_rate => {
        @cqc.int_range(0, 24).flat_map(frames => {
          gen_sample()
          .array_with_size(frames * channels)
          .map(samples => { format, sample_rate, channels, samples, })
        })
      })
    })
  })
}

///|
/// Shrinks toward fewer frames and zero samples, so a failure reports a small case.
fn shrink_case(c : Case) -> Iter[Case] {
  let out : Array[Case] = []
  let frames = c.samples.length() / c.channels
  if frames > 0 {
    out.push({ ..c, samples: c.samples[0:frames / 2 * c.channels].to_owned(), })
    out.push({
      ..c,
      samples: c.samples[0:(frames - 1) * c.channels].to_owned(),
    })
  }
  for i, x in c.samples {
    if x != 0.0 || x.is_nan() {
      let zeroed = c.samples.copy()
      zeroed[i] = 0.0
      out.push({ ..c, samples: zeroed, })
    }
  }
  out.iter()
}

///|
fn check_case(f : (Case) -> Bool) -> Unit raise {
  @qc.quick_check(
    @qc.forall_shrink(gen_case(), shrink_case, f),
    max_success=500,
  )
}

// Properties

///|
test "spec 1: encode accepts exactly the inputs a WAV header can describe" {
  let gen_rate = @cqc.elements([
    -2147483648, -1, 0, 1, 44100, 268435455, 268435456, 536870911, 2147483647,
  ])
  // Around the 16-bit block_align limit for 1, 2, 3, 4, and 8 bytes per sample
  let gen_channels = @cqc.elements([
    -1, 0, 1, 2, 3, 18, 19, 8191, 8192, 16383, 16384, 21845, 21846, 32767, 32768,
    65535, 65536,
  ])
  let gen_params = gen_format().flat_map(format => {
    gen_rate.flat_map(sample_rate => {
      gen_channels.flat_map(channels => {
        @cqc.int_range(0, 1).flat_map(frames => {
          @cqc.int_range(0, 3).map(extra => {
            let n = (if channels > 0 { channels } else { 1 }) * frames +
              (if extra == 0 { 1 } else { 0 })
            { format, sample_rate, channels, samples: Array::make(n, 0.25), }
          })
        })
      })
    })
  })
  @qc.quick_check(
    @qc.forall(gen_params, c => {
      let bytes_per_sample = bits_of(c.format) / 8
      let block_align = c.channels.to_int64() * bytes_per_sample.to_int64()
      let describable = c.sample_rate > 0 &&
        c.channels > 0 &&
        c.samples.length() % c.channels == 0 &&
        block_align <= 0xFFFFL &&
        c.sample_rate.to_int64() * block_align <= 0xFFFFFFFFL
      (encode_case(c) is Some(_)) == describable
    }),
    max_success=1000,
  )
}

///|
test "spec 2: encode lays out RIFF, fmt, and data chunks as the format defines" {
  check_case(c => {
    guard encode_case(c) is Some(w) else { return false }
    let bytes_per_sample = bits_of(c.format) / 8
    let extensible = c.channels > 2
    let fmt_size = if extensible { 40 } else { 16 }
    let data_size = c.samples.length() * bytes_per_sample
    let data_at = 20 + fmt_size
    let tag = if is_pcm(c.format) { 1 } else { 3 }
    let block_align = c.channels * bytes_per_sample
    w.length() == data_at + 8 + data_size + data_size % 2 &&
    w[0:4] == b"RIFF" &&
    u32_le(w, 4) == (w.length() - 8).to_int64() &&
    w[8:16] == b"WAVEfmt " &&
    u32_le(w, 16) == fmt_size.to_int64() &&
    u16_le(w, 20) == (if extensible { 0xFFFE } else { tag }) &&
    u16_le(w, 22) == c.channels &&
    u32_le(w, 24) == c.sample_rate.to_int64() &&
    u32_le(w, 28) == c.sample_rate.to_int64() * block_align.to_int64() &&
    u16_le(w, 32) == block_align &&
    u16_le(w, 34) == bytes_per_sample * 8 &&
    (!extensible || u16_le(w, 44) == tag) &&
    w[data_at:data_at + 4] == b"data" &&
    u32_le(w, data_at + 4) == data_size.to_int64() &&
    (data_size % 2 == 0 || w[w.length() - 1] == b'\x00')
  })
}

///|
test "spec 3: decode(encode(x)) keeps sample rate, channels, frames, and format" {
  check_case(c => {
    guard encode_case(c) is Some(w) && decode_or_none(w) is Some(f) else {
      return false
    }
    f.sample_rate() == c.sample_rate &&
    f.channels() == c.channels &&
    f.frame_count() == c.samples.length() / c.channels &&
    f.samples().length() == c.samples.length() &&
    f.source_format() == c.format
  })
}

///|
/// What one sample `x` must decode to after `encode` in `format`.
fn sample_survives(
  format : @wav.WavSampleFormat,
  x : Double,
  d : Double,
) -> Bool {
  match format {
    IeeeF64 => d.reinterpret_as_int64() == x.reinterpret_as_int64()
    IeeeF32 => {
      let expected = Float::from_double(x).to_double()
      if expected.is_nan() {
        d.is_nan()
      } else {
        d == expected
      }
    }
    _ => {
      // PCM: a whole step of 2^-(bits-1) inside [-1, 1 - step], at most half a
      // step from x clamped to that range; NaN is silence
      let full = (1L << (bits_of(format) - 1)).to_double()
      let top = (full - 1.0) / full
      let steps = d * full
      let on_grid = steps == steps.floor() && d >= -1.0 && d <= top
      let target = if x.is_nan() {
        0.0
      } else if x > top {
        top
      } else if x < -1.0 {
        -1.0
      } else {
        x
      }
      on_grid && (d - target).abs() <= 0.5 / full
    }
  }
}

///|
test "spec 4: each sample comes back as its format stores it" {
  check_case(c => {
    guard encode_case(c) is Some(w) && decode_or_none(w) is Some(f) else {
      return false
    }
    let decoded = f.samples()
    for i, x in c.samples {
      if !sample_survives(c.format, x, decoded[i]) {
        return false
      }
    }
    true
  })
}

///|
test "spec 5: PCM quantization keeps order" {
  let finite = gen_sample().map(x => if x.is_nan() { 0.0 } else { x })
  let gen = gen_pcm_format().flat_map(format => {
    finite.zip(finite).map(pair => (format, pair.0, pair.1))
  })
  @qc.quick_check(
    @qc.forall(gen, t => {
      let (format, x, y) = t
      let (lo, hi) = if x <= y { (x, y) } else { (y, x) }
      guard encode_case({
          format,
          sample_rate: 8000,
          channels: 1,
          samples: [lo, hi],
        })
        is Some(w) &&
        decode_or_none(w) is Some(f) else {
        return false
      }
      f.samples()[0] <= f.samples()[1]
    }),
    max_success=1000,
  )
}

///|
test "spec 6: encode(decode(encode(x))) == encode(x)" {
  check_case(c => {
    guard encode_case(c) is Some(w) && decode_or_none(w) is Some(f) else {
      return false
    }
    let again = encode_case({ ..c, samples: f.samples().iter().to_array(), })
    again == Some(w)
  })
}

///|
test "spec 7: byte order and unknown chunks do not change decoded samples" {
  let gen_chunk = @cqc.elements([
    "LIST", "JUNK", "bext", "fact", "cue ", "a\u{1}\u{0}z",
  ]).flat_map(id => {
    @cqc.int_range(0, 7).flat_map(n => {
      @cqc.int_range(0, 255).array_with_size(n).map(body => (id, body))
    })
  })
  let gen = @cqc.elements([true, false]).flat_map(little => {
    @cqc.int_range(1, 4).flat_map(channels => {
      @cqc.int_range(0, 6).flat_map(frames => {
        @cqc.frequency([
          (3, @cqc.int_range(-32768, 32767)),
          (1, @cqc.elements([-32768, -1, 0, 1, 32767])),
        ])
        .array_with_size(channels * frames)
        .flat_map(values => {
          @cqc.int_range(0, 3).flat_map(n => {
            gen_chunk
            .array_with_size(n)
            .map(chunks => (little, channels, values, chunks))
          })
        })
      })
    })
  })
  @qc.quick_check(
    @qc.forall(gen, t => {
      let (little, channels, values, chunks) = t
      let data : Array[Byte] = []
      for v in values {
        data.append(if little { le16(v) } else { be16(v) })
      }
      let wav = build_wav(
        le=little,
        fmt=if little {
          fmt_pcm16(channels, 22050)
        } else {
          fmt_pcm16_be(channels, 22050)
        },
        data~,
        extras=chunks.map(chunk => (chunk.0, chunk.1.map(b))),
      )
      guard decode_or_none(wav) is Some(f) else { return false }
      f.channels() == channels &&
      f.sample_rate() == 22050 &&
      f.samples() ==
      ReadOnlyArray::from_array(values.map(v => v.to_double() / 32768.0))
    }),
    max_success=500,
  )
}

///|
/// A decoded file that is consistent with itself.
fn consistent(f : @wav.WaveFile) -> Bool {
  f.channels() > 0 &&
  f.sample_rate() > 0 &&
  f.samples().length() == f.frame_count() * f.channels() &&
  (!is_pcm(f.source_format()) || f.samples().all(x => x >= -1.0 && x < 1.0))
}

///|
test "spec 8: decode raises WavError or gives a consistent file, for any bytes" {
  // Valid files with overwritten bytes and a cut end reach the deep parsing paths
  let gen_edit = @cqc.int_range(0, 1 << 20).zip(@cqc.int_range(0, 255))
  let gen_damaged = gen_case().flat_map(c => {
    gen_edit
    .array_with_size(4)
    .flat_map(edits => {
      @cqc.int_range(0, 4).flat_map(n_edits => {
        @cqc.int_range(0, 1 << 20).map(cut => {
          (c, edits[0:n_edits].to_owned(), cut)
        })
      })
    })
  })
  @qc.quick_check(
    @qc.forall(gen_damaged, t => {
      let (c, edits, cut) = t
      guard encode_case(c) is Some(w) else { return false }
      let damaged = FixedArray::makei(w.length(), i => w[i])
      for edit in edits {
        damaged[edit.0 % damaged.length()] = edit.1.to_byte()
      }
      let keep = if cut % 3 == 0 {
        cut % (damaged.length() + 1)
      } else {
        damaged.length()
      }
      let bytes = Bytes::from_array(damaged)[0:keep].to_owned()
      match decode_or_none(bytes) {
        Some(f) => consistent(f)
        None => true
      }
    }),
    max_success=3000,
  )
  // Arbitrary bytes, half of them behind a valid RIFF/WAVE/fmt prefix
  let gen_bytes = @cqc.elements([true, false]).flat_map(prefixed => {
    @cqc.int_range(0, 96).flat_map(n => {
      @cqc.int_range(0, 255).array_with_size(n).map(body => (prefixed, body))
    })
  })
  @qc.quick_check(
    @qc.forall(gen_bytes, t => {
      let (prefixed, body) = t
      let head : Array[Byte] = if prefixed {
        let h = ascii4("RIFF")
        h.append(le32(4 + body.length() + 4))
        h.append(ascii4("WAVE"))
        h.append(ascii4("fmt "))
        h
      } else {
        []
      }
      let bytes = bytes_of([head, body.map(b)])
      match decode_or_none(bytes) {
        Some(f) => consistent(f)
        None => true
      }
    }),
    max_success=3000,
  )
}
