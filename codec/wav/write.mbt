///|
/// Writes a little-endian 16-bit value.
fn put_u16le(fa : FixedArray[Byte], off : Int32, v : Int32) -> Unit {
  fa[off] = (v & 0xFF).to_byte()
  fa[off + 1] = ((v >> 8) & 0xFF).to_byte()
}

///|
/// Writes a little-endian 32-bit value (negative values are masked as two's complement, keeping the bit pattern).
fn put_u32le(fa : FixedArray[Byte], off : Int32, v : Int32) -> Unit {
  fa[off] = (v & 0xFF).to_byte()
  fa[off + 1] = ((v >> 8) & 0xFF).to_byte()
  fa[off + 2] = ((v >> 16) & 0xFF).to_byte()
  fa[off + 3] = ((v >> 24) & 0xFF).to_byte()
}

///|
/// Writes a four-byte ASCII chunk ID.
fn put_tag(fa : FixedArray[Byte], off : Int32, tag : String) -> Unit {
  for i = 0; i < 4; i = i + 1 {
    fa[off + i] = tag.get_char(i).unwrap().to_int().to_byte()
  }
}

///|
/// Rounds to the nearest integer, ties to even (IEEE 754 roundTiesToEven), as
/// ffmpeg does when it converts float to PCM.
fn round_ties_even(v : Double) -> Double {
  let r = v.floor()
  let frac = v - r
  if frac > 0.5 || (frac == 0.5 && r % 2.0 != 0.0) {
    r + 1.0
  } else {
    r
  }
}

///|
/// Finite float → integer sample: scale by `scale`, round ties to even, and
/// clamp to [lo, hi]. With the 2^(bits-1) decode scale, decode∘encode is idempotent.
fn quantize(x : Double, scale : Double, lo : Int32, hi : Int32) -> Int32 {
  let r = round_ties_even(x * scale)
  if r > hi.to_double() {
    hi
  } else if r < lo.to_double() {
    lo
  } else {
    r.to_int()
  }
}

///|
/// Whether `x` stays finite when stored in `format`: float32 overflows past
/// about 3.4e38.
fn stores_finite(x : Double, format : WavSampleFormat) -> Bool {
  let stored = if format is IeeeF32 {
    Float::from_double(x).to_double()
  } else {
    x
  }
  !stored.is_nan() && !stored.is_inf()
}

///|
/// Encodes one finite sample at a byte offset (little-endian).
fn encode_sample_at(
  fa : FixedArray[Byte],
  off : Int32,
  x : Double,
  fmt : WavSampleFormat,
) -> Unit {
  match fmt {
    PcmU8 => fa[off] = (quantize(x, 128.0, -128, 127) + 128).to_byte()
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
/// Channel mask for WAVE_FORMAT_EXTENSIBLE, which is written only for more than
/// 2 channels: the first n speaker positions, or 0 (no assignment) past the
/// 18 positions the format defines.
fn channel_mask(n : Int32) -> Int32 {
  if n <= 18 {
    (1 << n) - 1
  } else {
    0
  }
}

///|
/// Encodes interleaved samples as a WAV (RIFF, little-endian) byte stream.
///
/// - The length of `samples` must be a multiple of `channels` (frame-aligned)
/// - Every sample must stay finite in `format`; otherwise `NonFiniteSample` names the first one
/// - PCM quantization: scale 2^(bits-1), round ties to even, and clamp; `decode(encode(x))` is idempotent
/// - Float formats keep values past ±1
/// - More than 2 channels writes WAVE_FORMAT_EXTENSIBLE
/// - An odd-length data chunk is padded with a zero byte
pub fn encode(
  format~ : WavSampleFormat,
  sample_rate~ : Int32,
  channels~ : Int32,
  samples~ : ArrayView[Double],
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
  // block_align is a 16-bit field and the byte rate a 32-bit one
  let block_align = channels * bps
  guard block_align <= 0xFFFF else {
    raise InvalidFormat("channels = " + channels.to_string())
  }
  let byte_rate = sample_rate.to_int64() * block_align.to_int64()
  guard byte_rate <= 0xFFFFFFFFL else {
    raise InvalidFormat("sample rate = " + sample_rate.to_string())
  }
  let n = samples.length()
  let data_size = n * bps
  // Leave room for the 44-byte header so the RIFF size cannot overflow Int/UInt32
  guard data_size < 2147483603 else { raise DataTooLarge }
  let extensible = channels > 2
  let fmt_size = if extensible { 40 } else { 16 }
  let total = 12 + 8 + fmt_size + 8 + data_size + data_size % 2
  let fa : FixedArray[Byte] = FixedArray::make(total, b'\x00')
  // RIFF header
  put_tag(fa, 0, "RIFF")
  put_u32le(fa, 4, total - 8)
  put_tag(fa, 8, "WAVE")
  // fmt chunk
  put_tag(fa, 12, "fmt ")
  put_u32le(fa, 16, fmt_size)
  let tag = format.format_tag()
  put_u16le(fa, 20, if extensible { 0xFFFE } else { tag })
  put_u16le(fa, 22, channels)
  put_u32le(fa, 24, sample_rate)
  put_u32le(fa, 28, byte_rate.to_int())
  put_u16le(fa, 32, block_align)
  put_u16le(fa, 34, bps * 8)
  if extensible {
    put_u16le(fa, 36, 22)
    put_u16le(fa, 38, bps * 8)
    put_u32le(fa, 40, channel_mask(channels))
    // SubFormat GUID = little-endian layout of KSDATAFORMAT_SUBTYPE_PCM / IEEE_FLOAT:
    // 00000001-0000-0010-8000-00AA00389B71 (Data1 = the real format tag)
    put_u16le(fa, 44, tag)
    let guid_rest = b"\x00\x00\x00\x00\x10\x00\x80\x00\x00\xAA\x00\x38\x9B\x71"
    for i = 0; i < guid_rest.length(); i = i + 1 {
      fa[46 + i] = guid_rest[i]
    }
  }
  // data chunk
  let data_hdr = 12 + 8 + fmt_size
  put_tag(fa, data_hdr, "data")
  put_u32le(fa, data_hdr + 4, data_size)
  let body = data_hdr + 8
  for i = 0; i < n; i = i + 1 {
    guard stores_finite(samples[i], format) else {
      raise NonFiniteSample(index=i)
    }
    encode_sample_at(fa, body + i * bps, samples[i], format)
  }
  // Odd-length data chunk: RIFF requires even alignment, so one zero pad byte follows (already counted in total)
  Bytes::from_array(fa)
}
