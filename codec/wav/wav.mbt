///|
/// codec/wav — a pure MoonBit RIFF/WAVE decoder and encoder, with no FFI; builds for js / wasm-gc / native.
///
/// Decoding supports RIFF (little-endian) and RIFX (big-endian) containers; PCM u8/i16/i24/i32 and IEEE float32/64;
/// WAVE_FORMAT_EXTENSIBLE (0xFFFE). Unknown chunks (such as LIST/INFO) are skipped, honoring even-byte padding.
/// Encoding supports all six sample formats; more than 2 channels writes WAVE_FORMAT_EXTENSIBLE.
///
/// Samples are always interleaved Doubles normalized to [-1, 1]. PCM scales by 2^(bits-1)
/// (an exact dyadic fraction), so `decode(encode(x))` is idempotent: decoding yields the quantized value, and encoding it again yields the same bytes.
///
/// Design reference: the WAV codec in yabaobao070510/moonvoice (Apache-2.0).

///|
/// The sample storage format declared by the WAV fmt chunk.
#derive(Debug, Eq)
pub(all) enum WavSampleFormat {
  PcmU8
  PcmI16
  PcmI24
  PcmI32
  IeeeF32
  IeeeF64
}

///|
/// A recoverable WAV decode or encode failure. Every structural defect returns this error instead of panicking.
#derive(Debug)
pub suberror WavError {
  NotRiff
  NotWave
  Truncated(String)
  InvalidFormat(String)
  UnsupportedFormat(String)
  DataTooLarge
}

///|
pub extend WavError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend WavSampleFormat with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend WavSampleFormat with Eq::{equal, not_equal}

///|
pub extend WaveFile with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Decoded WAV content: interleaved samples normalized to [-1, 1].
#derive(Debug)
pub struct WaveFile {
  priv sample_rate : Int32
  priv channels : Int32
  priv samples : Array[Double]
  priv source_format : WavSampleFormat
}

///|
/// Builds and validates: channel count and sample rate are positive, and the sample count is aligned to whole frames.
pub fn WaveFile::WaveFile(
  sample_rate~ : Int32,
  channels~ : Int32,
  samples~ : Array[Double],
  source_format~ : WavSampleFormat,
) -> WaveFile raise WavError {
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
  { sample_rate, channels, samples, source_format, }
}

///|
/// Sample rate in Hz.
pub fn WaveFile::sample_rate(self : WaveFile) -> Int32 {
  self.sample_rate
}

///|
/// Channel count. Samples are interleaved by channel.
pub fn WaveFile::channels(self : WaveFile) -> Int32 {
  self.channels
}

///|
/// Interleaved normalized samples; length = frame count × channel count.
pub fn WaveFile::samples(self : WaveFile) -> Array[Double] {
  self.samples
}

///|
/// The original storage format declared by the fmt chunk.
pub fn WaveFile::source_format(self : WaveFile) -> WavSampleFormat {
  self.source_format
}

///|
/// Frame count (samples per channel).
pub fn WaveFile::frame_count(self : WaveFile) -> Int32 {
  self.samples.length() / self.channels
}

///|
/// Duration in seconds.
pub fn WaveFile::duration_seconds(self : WaveFile) -> Double {
  self.samples.length().to_double() /
  self.channels.to_double() /
  self.sample_rate.to_double()
}

///|
/// Bytes per sample.
pub fn WavSampleFormat::bytes_per_sample(self : WavSampleFormat) -> Int32 {
  match self {
    PcmU8 => 1
    PcmI16 => 2
    PcmI24 => 3
    PcmI32 => 4
    IeeeF32 => 4
    IeeeF64 => 8
  }
}

///|
/// Whether this is an integer PCM format.
pub fn WavSampleFormat::is_pcm(self : WavSampleFormat) -> Bool {
  match self {
    PcmU8 | PcmI16 | PcmI24 | PcmI32 => true
    IeeeF32 | IeeeF64 => false
  }
}

///|
/// The format tag in the fmt chunk (PCM = 1, IEEE float = 3).
fn WavSampleFormat::format_tag(self : WavSampleFormat) -> Int32 {
  match self {
    PcmU8 | PcmI16 | PcmI24 | PcmI32 => 1
    IeeeF32 | IeeeF64 => 3
  }
}

///|
/// (format tag, bit depth) → storage format; unknown combinations return None.
fn WavSampleFormat::from_tag_bits(
  tag : Int32,
  bits : Int32,
) -> WavSampleFormat? {
  if tag == 1 {
    match bits {
      8 => Some(PcmU8)
      16 => Some(PcmI16)
      24 => Some(PcmI24)
      32 => Some(PcmI32)
      _ => None
    }
  } else if tag == 3 {
    match bits {
      32 => Some(IeeeF32)
      64 => Some(IeeeF64)
      _ => None
    }
  } else {
    None
  }
}
