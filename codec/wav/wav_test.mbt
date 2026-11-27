// 黑盒测试:只用 @wav 的公开 API。测试内的字节构造是独立实现,
// 与被测代码互为校验;fuzz 与错误路径共用同一批构造器。

///|
fn b(v : Int) -> Byte {
  v.to_byte()
}

///|
fn le16(v : Int) -> Array[Byte] {
  [b(v & 0xFF), b((v >> 8) & 0xFF)]
}

///|
fn le32(v : Int) -> Array[Byte] {
  [b(v & 0xFF), b((v >> 8) & 0xFF), b((v >> 16) & 0xFF), b((v >> 24) & 0xFF)]
}

///|
fn be16(v : Int) -> Array[Byte] {
  [b((v >> 8) & 0xFF), b(v & 0xFF)]
}

///|
fn be32(v : Int) -> Array[Byte] {
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
/// 构造最小合法 WAV:RIFF/RIFX + fmt + (额外块) + data。额外块插在 fmt 与 data 之间。
fn build_wav(
  le? : Bool = true,
  fmt~ : Array[Byte],
  data~ : Array[Byte],
  extras? : Array[(String, Array[Byte])] = [],
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
    // 奇数长度补零(构造合法输入)
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
/// 16 位 PCM 的 fmt 块(小端)。
fn fmt_pcm16(ch : Int, rate : Int) -> Array[Byte] {
  fmt_tag(1, ch, rate, 16)
}

///|
/// 任意 (tag, bits) 的 fmt 块(小端布局)。
fn fmt_tag(tag : Int, ch : Int, rate : Int, bits : Int) -> Array[Byte] {
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
/// RIFX(大端)布局的 16 位 PCM fmt 块。
fn fmt_pcm16_be(ch : Int, rate : Int) -> Array[Byte] {
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
/// Double 的 8 个小端字节(测试侧独立实现)。
fn f64_bytes(x : Double) -> Array[Byte] {
  let u = Double::reinterpret_as_int64(x).reinterpret_as_uint64()
  let out = le32(u.to_uint().reinterpret_as_int())
  out.append(le32((u >> 32).to_uint().reinterpret_as_int()))
  out
}

///|
/// 捕获 @wav.WavError;不抛错返回 None。
fn err_of(f : () -> Unit raise @wav.WavError) -> @wav.WavError? {
  try {
    f()
    None
  } catch {
    error => Some(error)
  }
}

///|
/// 确定性 LCG,fuzz 可复现。
priv struct TestRng {
  mut state : Int
}

///|
fn TestRng::new(seed : Int) -> TestRng {
  { state: seed, }
}

///|
fn TestRng::next(self : TestRng, mask : Int) -> Int {
  self.state = self.state * 25173 + 13849
  if self.state < 0 {
    self.state = self.state & 0x7FFFFFFF
  }
  self.state & mask
}

///|
test "decode hand-built i16 stereo" {
  // L: [0.5, -0.5, 满幅正, 满幅负]  R: [0, 0, 0, 0]
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
  assert_true(f.duration_seconds() == 4.0 / 44100.0)
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
  // f32: 0.25 精确(位模式 0x3E800000)
  let wav32 = build_wav(fmt=fmt_tag(3, 1, 48000, 32), data=[
    b(0x00),
    b(0x00),
    b(0x80),
    b(0x3E),
  ])
  assert_true(@wav.decode(wav32).samples()[0] == 0.25)
  // f64: 0.1 按位精确还原
  let wav64 = build_wav(fmt=fmt_tag(3, 1, 48000, 64), data=f64_bytes(0.1))
  assert_true(@wav.decode(wav64).samples()[0] == 0.1)
  // f32 存 0.1:解码结果等于 Float(0.1) 的精确值
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
    // 双声道交错
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
        // float64 往返精确
        for i = 0; i < samples.length(); i = i + 1 {
          assert_true(s1[i] == samples[i])
        }
      @wav.IeeeF32 =>
        // float32 量化误差 ≤ 2^-24,远小于 1e-6
        for i = 0; i < samples.length(); i = i + 1 {
          assert_true((s1[i] - samples[i]).abs() < 0.000001)
        }
      _ => ()
    }
    // 幂等:decode(encode(decode(encode(x)))) == decode(encode(x))
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
test "encode sanitizes nan and infinity" {
  let encoded = @wav.encode(format=@wav.PcmI16, sample_rate=8000, channels=1, samples=[
    0.0 / 0.0,
    1.0 / 0.0,
    -1.0 / 0.0,
  ])
  let s = @wav.decode(encoded).samples()
  assert_true(s[0] == 0.0)
  assert_true(s[1] == 32767.0 / 32768.0)
  assert_true(s[2] == -1.0)
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
  // fmt tag 处应为 0xFFFE(小端:FE FF)
  assert_true(encoded[20].to_int() == 0xFE)
  assert_true(encoded[21].to_int() == 0xFF)
  // 声道掩码 (1<<4)-1 = 0x0000000F,位于 offset 40(小端首字节)
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
  // 奇数长度 LIST(3 字节)+ pad,插在 fmt 与 data 之间
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
  assert_true(f.duration_seconds() == 0.0)
}

///|
test "structured errors for malformed inputs" {
  // 截断:不足 12 字节
  let empty = bytes_of([])
  assert_true(
    err_of(() => {
      let _ = @wav.decode(empty)
    })
    is Some(@wav.WavError::Truncated(_)),
  )
  // 非法魔数
  let bad_magic = bytes_of([ascii4("RIFZ"), le32(4), ascii4("WAVE")])
  assert_true(
    err_of(() => {
      let _ = @wav.decode(bad_magic)
    })
    is Some(NotRiff),
  )
  // 缺 WAVE 形式类型
  let no_wave = bytes_of([ascii4("RIFF"), le32(4), ascii4("AVI ")])
  assert_true(
    err_of(() => {
      let _ = @wav.decode(no_wave)
    })
    is Some(NotWave),
  )
  // 只有头,没有块
  let header_only = bytes_of([ascii4("RIFF"), le32(4), ascii4("WAVE")])
  assert_true(
    err_of(() => {
      let _ = @wav.decode(header_only)
    })
    is Some(@wav.WavError::InvalidFormat("no fmt chunk")),
  )
  // 有 fmt 没 data
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
  // fmt 块过小
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
  // 块大小超出文件末尾
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
  // 不支持的格式 tag
  let weird = build_wav(fmt=fmt_tag(7, 1, 8000, 16), data=[b(0), b(0)])
  assert_true(
    err_of(() => {
      let _ = @wav.decode(weird)
    })
    is Some(@wav.WavError::UnsupportedFormat(_)),
  )
  // 声道数为 0
  let zero_ch = build_wav(fmt=fmt_tag(1, 0, 8000, 16), data=[b(0), b(0)])
  assert_true(
    err_of(() => {
      let _ = @wav.decode(zero_ch)
    })
    is Some(@wav.WavError::InvalidFormat(_)),
  )
  // data 不是帧对齐(1 声道 16 位,data 只有 3 字节)
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
  // 2 声道但样本数不对齐
  assert_true(
    err_of(() => {
      let _ = @wav.encode(format=@wav.PcmI16, sample_rate=8000, channels=2, samples=[
        0.0, 0.0, 0.0,
      ])
    })
    is Some(@wav.WavError::InvalidFormat(_)),
  )
  // WaveFile 构造器同样校验
  assert_true(
    err_of(() => {
      let _ = @wav.WaveFile::WaveFile(
        sample_rate=8000,
        channels=2,
        samples=[0.0, 0.0, 0.0],
        source_format=@wav.PcmI16,
      )
    })
    is Some(@wav.WavError::InvalidFormat(_)),
  )
}

///|
test "fuzz: 10k random byte inputs never panic" {
  let rng = TestRng::new(0x5eed)
  for i = 0; i < 10000; i = i + 1 {
    let len = 4 + rng.next(95)
    let fa : FixedArray[Byte] = FixedArray::make(len, b(0))
    for j = 0; j < len; j = j + 1 {
      fa[j] = b(rng.next(0xFF))
    }
    // 每第 3 组输入偏向合法结构头,以覆盖 fmt/data 深层解析路径
    if i % 3 == 0 && len >= 44 {
      fa[0] = b(0x52)
      fa[1] = b(0x49)
      fa[2] = b(0x46)
      fa[3] = b(0x46)
      fa[8] = b(0x57)
      fa[9] = b(0x41)
      fa[10] = b(0x56)
      fa[11] = b(0x45)
      fa[12] = b(0x66)
      fa[13] = b(0x6D)
      fa[14] = b(0x74)
      fa[15] = b(0x20)
      fa[16] = b(16)
    }
    let _ = err_of(() => {
      let _ = @wav.decode(Bytes::from_array(fa))
    })
  }
}

///|
test "fuzz: mutated valid files never panic" {
  let valid = @wav.encode(format=@wav.PcmI16, sample_rate=44100, channels=2, samples=[
    0.1, -0.2, 0.3, -0.4, 0.5, -0.6, 0.7, -0.8,
  ])
  let original : FixedArray[Byte] = FixedArray::make(valid.length(), b(0))
  for i = 0; i < valid.length(); i = i + 1 {
    original[i] = valid[i]
  }
  let rng = TestRng::new(0xC0FFEE)
  let mut round = 0
  while round < 2000 {
    let mutated = FixedArray::make(original.length(), b(0))
    for j = 0; j < original.length(); j = j + 1 {
      mutated[j] = original[j]
    }
    let n_flips = 1 + rng.next(3)
    let mut flips = 0
    while flips < n_flips {
      let pos = rng.next(original.length() - 1)
      mutated[pos] = b(rng.next(0xFF))
      flips = flips + 1
    }
    let _ = err_of(() => {
      let _ = @wav.decode(Bytes::from_array(mutated))
    })
    round = round + 1
  }
}

///|
test "prop: pcm i16 encode/decode round trip is idempotent (quickcheck)" {
  @qc.quick_check_fn_error(
    fn(x : Double) raise {
      if x.is_nan() || x.is_inf() {
        return true
      }
      let samples : Array[Double] = [x, -x]
      let e1 = @wav.encode(
        format=@wav.PcmI16,
        sample_rate=8000,
        channels=2,
        samples~,
      )
      let d1 = @wav.decode(e1)
      let e2 = @wav.encode(
        format=@wav.PcmI16,
        sample_rate=8000,
        channels=2,
        samples=d1.samples(),
      )
      e1 == e2
    },
    max_success=200,
  )
}

///|
test "prop: decode of valid encode never fails (quickcheck)" {
  @qc.quick_check_fn(
    fn(x : Double) {
      if x.is_nan() || x.is_inf() {
        return true
      }
      let samples : Array[Double] = [x, x, -x, -x]
      match
        err_of(() => {
          let _ = @wav.decode(
            @wav.encode(
              format=@wav.PcmI24,
              sample_rate=44100,
              channels=4,
              samples~,
            ),
          )
        }) {
        None => true
        Some(_) => false
      }
    },
    max_success=200,
  )
}
