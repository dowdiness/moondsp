///|
/// codec/wav — a pure MoonBit RIFF/WAVE decoder and encoder, with no FFI; builds for js / wasm-gc / native.
///
/// Decoding supports RIFF (little-endian) and RIFX (big-endian) containers; PCM u8/i16/i24/i32 and IEEE float32/64;
/// WAVE_FORMAT_EXTENSIBLE (0xFFFE). Unknown chunks (such as LIST/INFO) are skipped, honoring even-byte padding.
/// Encoding supports all six sample formats; more than 2 channels writes WAVE_FORMAT_EXTENSIBLE.
///
/// Samples are interleaved, finite Doubles with nominal full scale ±1: PCM samples lie in
/// [-1, 1), and float samples may exceed ±1. Neither `decode` nor `encode` accepts NaN or ±Inf.
/// PCM scales by 2^(bits-1) (an exact dyadic fraction) and rounds to the nearest step, ties to
/// even, so `decode(encode(x))` is idempotent: decoding yields the quantized value, and encoding
/// it again yields the same bytes.
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
  UnsupportedFormat(tag~ : Int32, bits~ : Int32)
  NonFiniteSample(index~ : Int32)
  DataTooLarge
}

///|
/// Decoded WAV content: interleaved finite samples, in [-1, 1) when the source is PCM.
#derive(Debug)
pub struct WaveFile {
  priv sample_rate : Int32
  priv channels : Int32
  priv samples : ReadOnlyArray[Double]
  priv source_format : WavSampleFormat
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
/// Interleaved finite samples; length = frame count × channel count.
pub fn WaveFile::samples(self : WaveFile) -> ReadOnlyArray[Double] {
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
/// Bytes per sample.
fn WavSampleFormat::bytes_per_sample(self : WavSampleFormat) -> Int32 {
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
