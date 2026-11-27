// Black-box tests: only @wav's public API. The byte builders here are an independent implementation,
// so they and the code under test check each other; fuzzing and error paths share the same builders.

///|
fn b(v : Int32) -> Byte {
  v.to_byte()
}

///|
fn le16(v : Int32) -> Array[Byte] {
  [b(v & 0xFF), b((v >> 8) & 0xFF)]
}

///|
fn le32(v : Int32) -> Array[Byte] {
  [b(v & 0xFF), b((v >> 8) & 0xFF), b((v >> 16) & 0xFF), b((v >> 24) & 0xFF)]
}

///|
fn be16(v : Int32) -> Array[Byte] {
  [b((v >> 8) & 0xFF), b(v & 0xFF)]
}

///|
fn be32(v : Int32) -> Array[Byte] {
  [b((v >> 24) & 0xFF), b((v >> 16) & 0xFF), b((v >> 8) & 0xFF), b(v & 0xFF)]
}

///|
fn ascii4(s : String) -> Array[Byte] {
  let out : Array[Byte] = []
  for i = 0; i < 4; i = i + 1 {
    out.push(b(s.get_char(i).unwrap().to_int()))
  }
  out
}

///|
fn bytes_of(parts : Array[Array[Byte]]) -> Bytes {
  let mut total = 0
  for p in parts {
    total = total + p.length()
  }
  let fa : FixedArray[Byte] = FixedArray::make(total, b(0))
  let mut off = 0
  for p in parts {
    for i = 0; i < p.length(); i = i + 1 {
      fa[off + i] = p[i]
    }
    off = off + p.length()
  }
  Bytes::from_array(fa)
}

///|
/// Builds a minimal valid WAV: RIFF/RIFX + fmt + (extra chunks) + data. Extra chunks go between fmt and data.
fn build_wav(
  le~ : Bool = true,
  fmt~ : Array[Byte],
  data~ : Array[Byte],
  extras~ : Array[(String, Array[Byte])] = [],
) -> Bytes {
  let mut riff_size = 4 +
    8 +
    fmt.length() +
    8 +
    data.length() +
    data.length() % 2
  for pair in extras {
    riff_size = riff_size + 8 + pair.1.length() + pair.1.length() % 2
  }
  let body : Array[Array[Byte]] = []
  body.push(ascii4(if le { "RIFF" } else { "RIFX" }))
  body.push(if le { le32(riff_size) } else { be32(riff_size) })
  body.push(ascii4("WAVE"))
  body.push(ascii4("fmt "))
  body.push(if le { le32(fmt.length()) } else { be32(fmt.length()) })
  body.push(fmt)
  for pair in extras {
    body.push(ascii4(pair.0))
    body.push(if le { le32(pair.1.length()) } else { be32(pair.1.length()) })
    body.push(pair.1)
    // Pad odd lengths with a zero byte (to build valid input)
    if pair.1.length() % 2 == 1 {
      body.push([b(0)])
    }
  }
  body.push(ascii4("data"))
  body.push(if le { le32(data.length()) } else { be32(data.length()) })
  body.push(data)
  if data.length() % 2 == 1 {
    body.push([b(0)])
  }
  bytes_of(body)
}

///|
/// fmt chunk for 16-bit PCM (little-endian).
fn fmt_pcm16(ch : Int32, rate : Int32) -> Array[Byte] {
  fmt_tag(1, ch, rate, 16)
}

///|
/// fmt chunk for any (tag, bits) (little-endian layout).
fn fmt_tag(tag : Int32, ch : Int32, rate : Int32, bits : Int32) -> Array[Byte] {
  let align = ch * (bits / 8)
  let out : Array[Byte] = []
  out.append(le16(tag))
  out.append(le16(ch))
  out.append(le32(rate))
  out.append(le32(rate * align))
  out.append(le16(align))
  out.append(le16(bits))
  out
}

///|
/// 16-bit PCM fmt chunk in RIFX (big-endian) layout.
fn fmt_pcm16_be(ch : Int32, rate : Int32) -> Array[Byte] {
  let align = ch * 2
  let out : Array[Byte] = []
  out.append(be16(1))
  out.append(be16(ch))
  out.append(be32(rate))
  out.append(be32(rate * align))
  out.append(be16(align))
  out.append(be16(16))
  out
}

///|
/// The 8 little-endian bytes of a Double (independent test-side implementation).
fn f64_bytes(x : Double) -> Array[Byte] {
  let u = Double::reinterpret_as_int64(x).reinterpret_as_uint64()
  let out = le32(u.to_uint().reinterpret_as_int())
  out.append(le32((u >> 32).to_uint().reinterpret_as_int()))
  out
}

///|
/// Catches @wav.WavError; returns None when nothing is raised.
fn err_of(f : () -> Unit raise @wav.WavError) -> @wav.WavError? {
  try {
    f()
    None
  } catch {
    error => Some(error)
  }
}

///|
test "decode hand-built i16 stereo" {
  // L: [0.5, -0.5, positive full scale, negative full scale]  R: [0, 0, 0, 0]
  let data : Array[Byte] = []
  data.append(le16(16384))
  data.append(le16(0))
  data.append(le16(-16384))
  data.append(le16(0))
  data.append(le16(32767))
  data.append(le16(0))
  data.append(le16(-32768))
  data.append(le16(0))
  let wav = build_wav(fmt=fmt_pcm16(2, 44100), data~)
  let f = @wav.decode(wav)
  assert_true(f.sample_rate() == 44100)
  assert_true(f.channels() == 2)
  assert_true(f.frame_count() == 4)
  assert_true(f.source_format() is @wav.PcmI16)
  let s = f.samples()
  assert_true(s[0] == 0.5)
  assert_true(s[1] == 0.0)
  assert_true(s[2] == -0.5)
  assert_true(s[3] == 0.0)
  assert_true(s[4] == 32767.0 / 32768.0)
  assert_true(s[5] == 0.0)
  assert_true(s[6] == -1.0)
  assert_true(s[7] == 0.0)
}

///|
test "decode u8 pcm is unsigned with 128 center" {
  let wav = build_wav(fmt=fmt_tag(1, 1, 8000, 8), data=[b(0), b(128), b(255)])
  let f = @wav.decode(wav)
  let s = f.samples()
  assert_true(s[0] == -1.0)
  assert_true(s[1] == 0.0)
  assert_true(s[2] == 127.0 / 128.0)
}

///|
test "decode i24 and i32 spot values" {
  // i24: 0x010000 = 65536 → 65536/8388608 = 0.0078125
  let wav24 = build_wav(fmt=fmt_tag(1, 1, 48000, 24), data=[
    b(0x00),
    b(0x00),
    b(0x01),
  ])
  assert_true(@wav.decode(wav24).samples()[0] == 0.0078125)
  // i32: 0x04000000 = 67108864 → 67108864/2147483648 = 0.03125
  let wav32 = build_wav(fmt=fmt_tag(1, 1, 48000, 32), data=[
    b(0x00),
    b(0x00),
    b(0x00),
    b(0x04),
  ])
  assert_true(@wav.decode(wav32).samples()[0] == 0.03125)
}

///|
test "decode ieee float32 and float64" {
  // f32: 0.25 is exact (bit pattern 0x3E800000)
  let wav32 = build_wav(fmt=fmt_tag(3, 1, 48000, 32), data=[
    b(0x00),
    b(0x00),
    b(0x80),
    b(0x3E),
  ])
  assert_true(@wav.decode(wav32).samples()[0] == 0.25)
  // f64: 0.1 is restored bit-exact
  let wav64 = build_wav(fmt=fmt_tag(3, 1, 48000, 64), data=f64_bytes(0.1))
  assert_true(@wav.decode(wav64).samples()[0] == 0.1)
  // f32 storing 0.1: the decoded value equals Float(0.1) exactly
  let bits = Float::from_double(0.1).reinterpret_as_uint().reinterpret_as_int()
  let wav32b = build_wav(fmt=fmt_tag(3, 1, 48000, 32), data=[
    b(bits & 0xFF),
    b((bits >> 8) & 0xFF),
    b((bits >> 16) & 0xFF),
    b((bits >> 24) & 0xFF),
  ])
  assert_true(
    @wav.decode(wav32b).samples()[0] == Float::from_double(0.1).to_double(),
  )
}

///|
test "round trip through every format is exact or idempotent" {
  let base : Array[Double] = [
    0.0, 1.0, -1.0, 0.5, -0.25, 0.123456, -0.7, 0.0009765625, 0.999999, -0.999999,
  ]
  let formats : Array[@wav.WavSampleFormat] = [
    @wav.PcmU8,
    @wav.PcmI16,
    @wav.PcmI24,
    @wav.PcmI32,
    @wav.IeeeF32,
    @wav.IeeeF64,
  ]
  for fmt in formats {
    // Interleaved stereo
    let samples : Array[Double] = []
    for v in base {
      samples.push(v)
      samples.push(-v * 0.5)
    }
    let encoded = @wav.encode(
      format=fmt,
      sample_rate=48000,
      channels=2,
      samples~,
    )
    let d1 = @wav.decode(encoded)
    assert_true(d1.sample_rate() == 48000)
    assert_true(d1.channels() == 2)
    assert_true(d1.source_format() == fmt)
    let s1 = d1.samples()
    match fmt {
      @wav.IeeeF64 =>
        // float64 round trip is exact
        for i = 0; i < samples.length(); i = i + 1 {
          assert_true(s1[i] == samples[i])
        }
      @wav.IeeeF32 =>
        // float32 quantization error ≤ 2^-24, far below 1e-6
        for i = 0; i < samples.length(); i = i + 1 {
          assert_true((s1[i] - samples[i]).abs() < 0.000001)
        }
      _ => ()
    }
    // Idempotent: decode(encode(decode(encode(x)))) == decode(encode(x))
    let encoded2 = @wav.encode(
      format=fmt,
      sample_rate=48000,
      channels=2,
      samples=s1,
    )
    let s2 = @wav.decode(encoded2).samples()
    for i = 0; i < s1.length(); i = i + 1 {
      assert_true(s1[i] == s2[i])
    }
  }
}

///|
test "encode pcm i16 quantization spot values" {
  let encoded = @wav.encode(format=@wav.PcmI16, sample_rate=8000, channels=1, samples=[
    0.5, 1.0, -1.0, 0.0,
  ])
  let s = @wav.decode(encoded).samples()
  assert_true(s[0] == 0.5)
  assert_true(s[1] == 32767.0 / 32768.0)
  assert_true(s[2] == -1.0)
  assert_true(s[3] == 0.0)
}

///|
test "encode rounds pcm half steps to even, as ffmpeg does" {
  // ffmpeg -c:a pcm_s16le gives these from the same float32 input
  let half_steps : Array[Double] = [0.5, 1.5, 2.5, -0.5, -1.5, -2.5, 3.5, -3.5]
  let encoded = @wav.encode(
    format=@wav.PcmI16,
    sample_rate=8000,
    channels=1,
    samples=half_steps.map(v => v / 32768.0),
  )
  let steps = @wav.decode(encoded).samples().map(x => x * 32768.0)
  assert_true(
    steps ==
    ReadOnlyArray::from_array([0.0, 2.0, 2.0, 0.0, -2.0, -2.0, 4.0, -4.0]),
  )
}

///|
test "encode and decode reject non-finite samples" {
  let encodes = (format, x : Double) => {
    err_of(() => {
      let _ = @wav.encode(format~, sample_rate=8000, channels=1, samples=[
        0.0, x,
      ])
    })
  }
  for format in [@wav.PcmI16, @wav.IeeeF32, @wav.IeeeF64] {
    for x in [0.0 / 0.0, 1.0 / 0.0, -1.0 / 0.0] {
      assert_true(
        encodes(format, x) is Some(@wav.WavError::NonFiniteSample(index=1)),
      )
    }
  }
  // Finite as a Double, but infinite as float32
  assert_true(
    encodes(@wav.IeeeF32, 1.0e39)
    is Some(@wav.WavError::NonFiniteSample(index=1)),
  )
  assert_true(encodes(@wav.IeeeF64, 1.0e39) is None)
  assert_true(encodes(@wav.PcmI16, 1.0e39) is None)
  // A float file holding NaN or Inf (from another writer) does not decode
  let nan_f32 = build_wav(
    fmt=fmt_tag(3, 1, 8000, 32),
    data=[..le32(0), ..le32(0x7FC00000)],
  )
  assert_true(
    err_of(() => {
      let _ = @wav.decode(nan_f32)
    })
    is Some(@wav.WavError::NonFiniteSample(index=1)),
  )
  let inf_f64 = build_wav(
    fmt=fmt_tag(3, 1, 8000, 64),
    data=f64_bytes(-1.0 / 0.0),
  )
  assert_true(
    err_of(() => {
      let _ = @wav.decode(inf_f64)
    })
    is Some(@wav.WavError::NonFiniteSample(index=0)),
  )
}

///|
test "encode more than two channels writes extensible" {
  let samples : Array[Double] = Array::make(8, 0.25)
  let encoded = @wav.encode(
    format=@wav.PcmI16,
    sample_rate=48000,
    channels=4,
    samples~,
  )
  // The fmt tag should be 0xFFFE (little-endian: FE FF)
  assert_true(encoded[20].to_int() == 0xFE)
  assert_true(encoded[21].to_int() == 0xFF)
  // Channel mask (1<<4)-1 = 0x0000000F at offset 40 (first little-endian byte)
  assert_true(encoded[40].to_int() == 0x0F)
  let f = @wav.decode(encoded)
  assert_true(f.channels() == 4)
  assert_true(f.source_format() is @wav.PcmI16)
  assert_true(f.frame_count() == 2)
}

///|
test "encode 24-bit mono odd frame count pads data chunk" {
  let encoded = @wav.encode(format=@wav.PcmI24, sample_rate=8000, channels=1, samples=[
    0.5,
  ])
  // 12 + 8 + 16 + 8 + 3 + 1(pad) = 48
  assert_true(encoded.length() == 48)
  let f = @wav.decode(encoded)
  assert_true(f.frame_count() == 1)
  assert_true(f.samples()[0] == 0.5)
}

///|
test "decode skips list chunk and honors odd-chunk padding" {
  // Odd-length LIST (3 bytes) + pad, between fmt and data
  let wav = build_wav(
    fmt=fmt_pcm16(1, 8000),
    data=[b(0x01), b(0x00), b(0x00), b(0x80)],
    extras=[("LIST", [b(1), b(2), b(3)])],
  )
  let f = @wav.decode(wav)
  assert_true(f.frame_count() == 2)
  assert_true(f.samples()[0] == 1.0 / 32768.0)
  assert_true(f.samples()[1] == -1.0)
}

///|
test "decode rifx big-endian container" {
  let data : Array[Byte] = []
  data.append(be16(16384))
  data.append(be16(0))
  data.append(be16(0x8000))
  data.append(be16(0))
  let wav = build_wav(le=false, fmt=fmt_pcm16_be(2, 44100), data~)
  let f = @wav.decode(wav)
  assert_true(f.sample_rate() == 44100)
  assert_true(f.channels() == 2)
  let s = f.samples()
  assert_true(s[0] == 0.5)
  assert_true(s[1] == 0.0)
  assert_true(s[2] == -1.0)
  assert_true(s[3] == 0.0)
}

///|
test "decode empty data is valid" {
  let wav = build_wav(fmt=fmt_pcm16(1, 8000), data=[])
  let f = @wav.decode(wav)
  assert_true(f.frame_count() == 0)
}

///|
test "structured errors for malformed inputs" {
  // Truncated: fewer than 12 bytes
  let empty = bytes_of([])
  assert_true(
    err_of(() => {
      let _ = @wav.decode(empty)
    })
    is Some(@wav.WavError::Truncated(_)),
  )
  // Invalid magic
  let bad_magic = bytes_of([ascii4("RIFZ"), le32(4), ascii4("WAVE")])
  assert_true(
    err_of(() => {
      let _ = @wav.decode(bad_magic)
    })
    is Some(NotRiff),
  )
  // Missing WAVE form type
  let no_wave = bytes_of([ascii4("RIFF"), le32(4), ascii4("AVI ")])
  assert_true(
    err_of(() => {
      let _ = @wav.decode(no_wave)
    })
    is Some(NotWave),
  )
  // Header only, no chunks
  let header_only = bytes_of([ascii4("RIFF"), le32(4), ascii4("WAVE")])
  assert_true(
    err_of(() => {
      let _ = @wav.decode(header_only)
    })
    is Some(@wav.WavError::InvalidFormat("no fmt chunk")),
  )
  // fmt without data
  let fmt_only_parts : Array[Array[Byte]] = [
    ascii4("RIFF"),
    le32(4 + 8 + 16),
    ascii4("WAVE"),
    ascii4("fmt "),
    le32(16),
  ]
  fmt_only_parts.push(fmt_pcm16(1, 8000))
  let fmt_only = bytes_of(fmt_only_parts)
  assert_true(
    err_of(() => {
      let _ = @wav.decode(fmt_only)
    })
    is Some(@wav.WavError::InvalidFormat("no data chunk")),
  )
  // fmt chunk too small
  let tiny_fmt = bytes_of([
    ascii4("RIFF"),
    le32(4 + 8 + 8),
    ascii4("WAVE"),
    ascii4("fmt "),
    le32(8),
    [b(1)],
    [b(0)],
    [b(2)],
    [b(0)],
    [b(0x22)],
    [b(0x56)],
    [b(0)],
    [b(0)],
  ])
  assert_true(
    err_of(() => {
      let _ = @wav.decode(tiny_fmt)
    })
    is Some(@wav.WavError::InvalidFormat(_)),
  )
  // Chunk size past the end of the file
  let overrun = bytes_of([
    ascii4("RIFF"),
    le32(100),
    ascii4("WAVE"),
    ascii4("data"),
    le32(1000),
    [b(1)],
    [b(2)],
  ])
  assert_true(
    err_of(() => {
      let _ = @wav.decode(overrun)
    })
    is Some(@wav.WavError::Truncated(_)),
  )
  // Unsupported format tag
  let weird = build_wav(fmt=fmt_tag(7, 1, 8000, 16), data=[b(0), b(0)])
  assert_true(
    err_of(() => {
      let _ = @wav.decode(weird)
    })
    is Some(@wav.WavError::UnsupportedFormat(tag=7, bits=16)),
  )
  // Zero channels
  let zero_ch = build_wav(fmt=fmt_tag(1, 0, 8000, 16), data=[b(0), b(0)])
  assert_true(
    err_of(() => {
      let _ = @wav.decode(zero_ch)
    })
    is Some(@wav.WavError::InvalidFormat(_)),
  )
  // data not frame-aligned (1 channel, 16-bit, data is only 3 bytes)
  let unaligned = build_wav(fmt=fmt_pcm16(1, 8000), data=[b(1), b(2), b(3)])
  assert_true(
    err_of(() => {
      let _ = @wav.decode(unaligned)
    })
    is Some(@wav.WavError::InvalidFormat(_)),
  )
}

///|
test "encode rejects invalid parameters" {
  let ok_samples : Array[Double] = [0.0, 0.0]
  assert_true(
    err_of(() => {
      let _ = @wav.encode(
        format=@wav.PcmI16,
        sample_rate=0,
        channels=1,
        samples=ok_samples,
      )
    })
    is Some(@wav.WavError::InvalidFormat(_)),
  )
  assert_true(
    err_of(() => {
      let _ = @wav.encode(
        format=@wav.PcmI16,
        sample_rate=8000,
        channels=0,
        samples=ok_samples,
      )
    })
    is Some(@wav.WavError::InvalidFormat(_)),
  )
  // 2 channels but the sample count is not aligned
  assert_true(
    err_of(() => {
      let _ = @wav.encode(format=@wav.PcmI16, sample_rate=8000, channels=2, samples=[
        0.0, 0.0, 0.0,
      ])
    })
    is Some(@wav.WavError::InvalidFormat(_)),
  )
}

///|
test "encode rejects values its header fields cannot hold" {
  let encodes = (format, sample_rate, channels) => {
    err_of(() => {
      let _ = @wav.encode(
        format~,
        sample_rate~,
        channels~,
        samples=Array::make(channels, 0.0),
      )
    })
  }
  // block_align (channels × bytes per sample) is a 16-bit field
  assert_true(encodes(@wav.PcmI16, 8000, 32767) is None)
  assert_true(
    encodes(@wav.PcmI16, 8000, 32768) is Some(@wav.WavError::InvalidFormat(_)),
  )
  // The byte rate (sample rate × block_align) is a 32-bit field
  assert_true(encodes(@wav.IeeeF64, 268435455, 2) is None)
  assert_true(
    encodes(@wav.IeeeF64, 268435456, 2) is Some(@wav.WavError::InvalidFormat(_)),
  )
  // Past the 18 defined speaker positions, the channel mask is 0
  let wav = @wav.encode(
    format=@wav.PcmU8,
    sample_rate=8000,
    channels=19,
    samples=Array::make(19, 0.0),
  )
  assert_true(wav[40] == b'\x00' && wav[41] == b'\x00' && wav[42] == b'\x00')
}
