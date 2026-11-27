///|
/// 由 Int 构造 Byte。不写字节字面量:moonc v0.10.14 对 `b'\xNN'` 字面量存在
/// 编译期 ICE,统一走 `to_byte()` 规避(与 moonvoice 的处理一致)。
fn byte_of(v : Int) -> Byte {
  v.to_byte()
}

///|
/// 写小端 16 位。
fn put_u16le(fa : FixedArray[Byte], off : Int, v : Int) -> Unit {
  fa[off] = (v & 0xFF).to_byte()
  fa[off + 1] = ((v >> 8) & 0xFF).to_byte()
}

///|
/// 写小端 32 位(负数按补码掩码,位模式不变)。
fn put_u32le(fa : FixedArray[Byte], off : Int, v : Int) -> Unit {
  fa[off] = (v & 0xFF).to_byte()
  fa[off + 1] = ((v >> 8) & 0xFF).to_byte()
  fa[off + 2] = ((v >> 16) & 0xFF).to_byte()
  fa[off + 3] = ((v >> 24) & 0xFF).to_byte()
}

///|
/// 写四字节 ASCII 块 ID(不足补空格)。
fn put_tag(fa : FixedArray[Byte], off : Int, tag : String) -> Unit {
  for i = 0; i < 4; i = i + 1 {
    fa[off + i] = if i < tag.length() {
      byte_of(tag.get_char(i).unwrap().to_int())
    } else {
      byte_of(32)
    }
  }
}

///|
/// [-1, 1] 浮点 → 整数样本:比例 scale,四舍五入,钳位到 [lo, hi]。
/// NaN 归 0,±Inf 取满幅。配合 2^(bits-1) 的解码比例,decode∘encode 幂等。
fn quantize(x : Double, scale : Double, lo : Int, hi : Int) -> Int {
  if x.is_nan() {
    return 0
  }
  let v = x * scale
  if v.is_inf() {
    return if v > 0.0 { hi } else { lo }
  }
  let r = v.round()
  if r > hi.to_double() {
    return hi
  }
  if r < lo.to_double() {
    return lo
  }
  r.to_int()
}

///|
/// 单样本编码:[-1, 1] Double → 字节偏移(小端)。
fn encode_sample_at(
  fa : FixedArray[Byte],
  off : Int,
  x : Double,
  fmt : WavSampleFormat,
) -> Unit {
  match fmt {
    PcmU8 => fa[off] = byte_of(quantize(x, 128.0, -128, 127) + 128)
    PcmI16 => put_u16le(fa, off, quantize(x, 32768.0, -32768, 32767))
    PcmI24 => {
      let v = quantize(x, 8388608.0, -8388608, 8388607)
      fa[off] = (v & 0xFF).to_byte()
      fa[off + 1] = ((v >> 8) & 0xFF).to_byte()
      fa[off + 2] = ((v >> 16) & 0xFF).to_byte()
    }
    PcmI32 =>
      put_u32le(fa, off, quantize(x, 2147483648.0, -2147483648, 2147483647))
    IeeeF32 =>
      put_u32le(
        fa,
        off,
        Float::from_double(x).reinterpret_as_uint().reinterpret_as_int(),
      )
    IeeeF64 => {
      let u = Double::reinterpret_as_int64(x).reinterpret_as_uint64()
      put_u32le(fa, off, u.to_uint().reinterpret_as_int())
      put_u32le(fa, off + 4, (u >> 32).to_uint().reinterpret_as_int())
    }
  }
}

///|
/// 常见声道布局掩码(EXTENSIBLE 用):1=前中,2=前左+前右,其余低位全 1。
fn default_channel_mask(n : Int) -> Int {
  if n == 1 {
    0x4
  } else if n == 2 {
    0x3
  } else {
    (1 << n) - 1
  }
}

///|
/// 将交错样本编码为 WAV(RIFF,小端)字节流。
///
/// - `samples` 长度必须是 `channels` 的整数倍(帧对齐)
/// - PCM 量化:比例 2^(bits-1),四舍五入并钳位;`decode(encode(x))` 幂等
/// - 声道数 > 2 自动写 WAVE_FORMAT_EXTENSIBLE
/// - data 块奇数长度自动补零对齐
pub fn encode(
  format~ : WavSampleFormat,
  sample_rate~ : Int,
  channels~ : Int,
  samples~ : Array[Double],
) -> Bytes raise WavError {
  guard sample_rate > 0 else {
    raise InvalidFormat("sample rate = " + sample_rate.to_string())
  }
  guard channels > 0 else {
    raise InvalidFormat("channels = " + channels.to_string())
  }
  guard samples.length() % channels == 0 else {
    raise InvalidFormat(
      "sample count " +
      samples.length().to_string() +
      " not aligned to " +
      channels.to_string() +
      " channels",
    )
  }
  let bps = format.bytes_per_sample()
  let n = samples.length()
  let data_size = n * bps
  // 留出 44 字节头空间,保证 RIFF 尺寸不溢出 Int/UInt32
  guard data_size < 2147483603 else { raise DataTooLarge }
  let extensible = channels > 2
  let fmt_size = if extensible { 40 } else { 16 }
  let total = 12 + 8 + fmt_size + 8 + data_size + data_size % 2
  let fa : FixedArray[Byte] = FixedArray::make(total, byte_of(0))
  // RIFF 头
  put_tag(fa, 0, "RIFF")
  put_u32le(fa, 4, total - 8)
  put_tag(fa, 8, "WAVE")
  // fmt 块
  put_tag(fa, 12, "fmt ")
  put_u32le(fa, 16, fmt_size)
  let tag = format.format_tag()
  put_u16le(fa, 20, if extensible { 0xFFFE } else { tag })
  put_u16le(fa, 22, channels)
  put_u32le(fa, 24, sample_rate)
  let block_align = channels * bps
  put_u32le(fa, 28, sample_rate * block_align)
  put_u16le(fa, 32, block_align)
  put_u16le(fa, 34, bps * 8)
  if extensible {
    put_u16le(fa, 36, 22)
    put_u16le(fa, 38, bps * 8)
    put_u32le(fa, 40, default_channel_mask(channels))
    // SubFormat GUID = KSDATAFORMAT_SUBTYPE_PCM / IEEE_FLOAT 的小端布局:
    // 00000001-0000-0010-8000-00AA00389B71(Data1 = 真实 format tag)
    put_u16le(fa, 44, tag)
    fa[46] = byte_of(0x00)
    fa[47] = byte_of(0x00)
    fa[48] = byte_of(0x00)
    fa[49] = byte_of(0x00)
    put_u16le(fa, 50, 0x0010)
    fa[52] = byte_of(0x80)
    fa[53] = byte_of(0x00)
    fa[54] = byte_of(0x00)
    fa[55] = byte_of(0xAA)
    fa[56] = byte_of(0x00)
    fa[57] = byte_of(0x38)
    fa[58] = byte_of(0x9B)
    fa[59] = byte_of(0x71)
  }
  // data 块
  let data_hdr = 12 + 8 + fmt_size
  put_tag(fa, data_hdr, "data")
  put_u32le(fa, data_hdr + 4, data_size)
  let body = data_hdr + 8
  for i = 0; i < n; i = i + 1 {
    encode_sample_at(fa, body + i * bps, samples[i], format)
  }
  // data 块奇数长度:RIFF 要求偶对齐,补一个零字节(已在 total 计入)
  Bytes::from_array(fa)
}
