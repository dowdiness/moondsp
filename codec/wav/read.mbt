///|
/// 读四字节块 ID 为可打印字符串:ASCII 原样,控制字符转义为 \xNN,
/// 保证错误消息里不出现原始控制字节。
fn tag_at(b : Bytes, off : Int) -> String {
  let hex = "0123456789ABCDEF"
  let buf = StringBuilder()
  for i = 0; i < 4; i = i + 1 {
    let v = b[off + i].to_int()
    if v >= 0x20 && v < 0x7F {
      buf.write_char(v.to_char().unwrap())
    } else {
      buf.write_string("\\x")
      buf.write_char(hex.get_char((v >> 4) & 0xF).unwrap())
      buf.write_char(hex.get_char(v & 0xF).unwrap())
    }
  }
  buf.to_string()
}

///|
/// 读无符号 16 位,按容器字节序。
fn u16_at(b : Bytes, off : Int, big : Bool) -> Int {
  if big {
    b[off].to_int() * 256 + b[off + 1].to_int()
  } else {
    b[off].to_int() + b[off + 1].to_int() * 256
  }
}

///|
/// 读无符号 32 位为 UInt,按容器字节序(供浮点位模式重组)。
fn u32_uint_at(b : Bytes, off : Int, big : Bool) -> UInt {
  if big {
    (b[off].to_uint() << 24) |
    (b[off + 1].to_uint() << 16) |
    (b[off + 2].to_uint() << 8) |
    b[off + 3].to_uint()
  } else {
    b[off].to_uint() |
    (b[off + 1].to_uint() << 8) |
    (b[off + 2].to_uint() << 16) |
    (b[off + 3].to_uint() << 24)
  }
}

///|
/// 读无符号 32 位为 Double:块大小可达 4 GiB,Double 累加规避 Int 32 位溢出。
fn u32_at(b : Bytes, off : Int, big : Bool) -> Double {
  if big {
    b[off].to_double() * 16777216.0 +
    b[off + 1].to_double() * 65536.0 +
    b[off + 2].to_double() * 256.0 +
    b[off + 3].to_double()
  } else {
    b[off].to_double() +
    b[off + 1].to_double() * 256.0 +
    b[off + 2].to_double() * 65536.0 +
    b[off + 3].to_double() * 16777216.0
  }
}

///|
/// 读无符号 24 位,按容器字节序。
fn u24_at(b : Bytes, off : Int, big : Bool) -> Int {
  if big {
    b[off].to_int() * 65536 + b[off + 1].to_int() * 256 + b[off + 2].to_int()
  } else {
    b[off].to_int() + b[off + 1].to_int() * 256 + b[off + 2].to_int() * 65536
  }
}

///|
/// 读 32 位 IEEE 浮点(按位重组,无 FFI)。
fn f32_at(b : Bytes, off : Int, big : Bool) -> Double {
  Float::reinterpret_from_uint(u32_uint_at(b, off, big)).to_double()
}

///|
/// 读 64 位 IEEE 浮点(按位重组,无 FFI)。
fn f64_at(b : Bytes, off : Int, big : Bool) -> Double {
  let first = u32_uint_at(b, off, big).to_uint64()
  let second = u32_uint_at(b, off + 4, big).to_uint64()
  let u = if big { (first << 32) | second } else { (second << 32) | first }
  UInt64::reinterpret_as_double(u)
}

///|
/// 单样本解码:字节偏移 → [-1, 1] Double。
/// PCM 比例取 2^(bits-1)(u8 中心 128):精确的二进分数,decode∘encode 幂等。
fn decode_sample_at(
  b : Bytes,
  off : Int,
  fmt : WavSampleFormat,
  big : Bool,
) -> Double {
  match fmt {
    PcmU8 => (b[off].to_double() - 128.0) / 128.0
    PcmI16 => {
      let u = u16_at(b, off, big)
      let s = if u >= 32768 { u - 65536 } else { u }
      s.to_double() / 32768.0
    }
    PcmI24 => {
      let u = u24_at(b, off, big)
      let s = if u >= 8388608 { u - 16777216 } else { u }
      s.to_double() / 8388608.0
    }
    PcmI32 => {
      let u = u32_at(b, off, big)
      let s = if u >= 2147483648.0 { u - 4294967296.0 } else { u }
      s / 2147483648.0
    }
    IeeeF32 => f32_at(b, off, big)
    IeeeF64 => f64_at(b, off, big)
  }
}

///|
/// 解析 WAV(RIFF 或 RIFX)字节流。未知块(如 LIST/INFO)跳过;
/// 结构损坏一律返回结构化错误,不 panic。
pub fn decode(bytes : Bytes) -> WaveFile raise WavError {
  let total = bytes.length()
  guard total >= 12 else { raise Truncated("RIFF header") }
  let big = match tag_at(bytes, 0) {
    "RIFF" => false
    "RIFX" => true
    _ => raise NotRiff
  }
  guard tag_at(bytes, 8) == "WAVE" else { raise NotWave }
  let mut pos = 12
  let mut fmt : WavSampleFormat? = None
  let mut n_channels = 0
  let mut rate = 0
  let mut data_off = -1
  let mut data_len = 0
  while pos + 8 <= total {
    let id = tag_at(bytes, pos)
    let size_d = u32_at(bytes, pos + 4, big)
    let body = pos + 8
    // 越界或超过 Int 表示范围的块大小都按截断处理
    if size_d < 0.0 || body.to_double() + size_d > total.to_double() {
      raise Truncated("chunk " + id)
    }
    let size = size_d.to_int()
    if id == "fmt " {
      if size < 16 {
        raise InvalidFormat("fmt chunk too small: " + size.to_string())
      }
      let mut tag = u16_at(bytes, body, big)
      n_channels = u16_at(bytes, body + 2, big)
      let rate_d = u32_at(bytes, body + 4, big)
      let bits = u16_at(bytes, body + 14, big)
      if tag == 0xFFFE {
        // WAVE_FORMAT_EXTENSIBLE:真实格式在 SubFormat GUID 的前两字节
        if size < 40 {
          raise InvalidFormat(
            "extensible fmt chunk too small: " + size.to_string(),
          )
        }
        tag = u16_at(bytes, body + 24, big)
      }
      if n_channels <= 0 {
        raise InvalidFormat("channels = " + n_channels.to_string())
      }
      if rate_d <= 0.0 || rate_d >= 2147483648.0 {
        raise InvalidFormat("sample rate out of range")
      }
      rate = rate_d.to_int()
      fmt = match WavSampleFormat::from_tag_bits(tag, bits) {
        Some(f) => Some(f)
        None =>
          raise UnsupportedFormat(
            "format tag " +
            tag.to_string() +
            " with " +
            bits.to_string() +
            " bits",
          )
      }
    } else if id == "data" {
      data_off = body
      data_len = size
    }
    // 块按偶数字节对齐,奇数长度后有一字节填充
    pos = body + size + size % 2
  }
  let format = match fmt {
    Some(f) => f
    None => raise InvalidFormat("no fmt chunk")
  }
  guard data_off >= 0 else { raise InvalidFormat("no data chunk") }
  let bps = format.bytes_per_sample()
  let frame_bytes = bps * n_channels
  guard data_len % frame_bytes == 0 else {
    raise InvalidFormat(
      "data size " +
      data_len.to_string() +
      " not frame-aligned (" +
      frame_bytes.to_string() +
      " bytes/frame)",
    )
  }
  let n = data_len / bps
  let samples : Array[Double] = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    samples[i] = decode_sample_at(bytes, data_off + i * bps, format, big)
  }
  WaveFile::WaveFile(
    sample_rate=rate,
    channels=n_channels,
    samples~,
    source_format=format,
  )
}
