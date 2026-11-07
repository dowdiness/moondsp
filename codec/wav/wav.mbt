///|
/// codec/wav — 纯 MoonBit 的 RIFF/WAVE 编解码,零 FFI,可编译到 js / wasm-gc / native。
///
/// 解码支持:RIFF(小端)与 RIFX(大端)容器;PCM u8/i16/i24/i32 与 IEEE float32/64;
/// WAVE_FORMAT_EXTENSIBLE(0xFFFE);未知块(如 LIST/INFO)自动跳过并按偶数字节对齐。
/// 编码支持:全部六种采样格式;声道数 > 2 时自动写 WAVE_FORMAT_EXTENSIBLE。
///
/// 样本统一为交错排列、归一化到 [-1, 1] 的 Double。PCM 量化比例取 2^(bits-1)
/// (精确的二进分数),保证 `decode(encode(x))` 幂等:先解码得到量化值,再编码得到相同字节。
///
/// 设计参考:yabaobao070510/moonvoice 的 WAV codec(Apache-2.0)。

///|
/// WAV fmt 块声明的样本存储格式。
pub(all) enum WavSampleFormat {
  PcmU8
  PcmI16
  PcmI24
  PcmI32
  IeeeF32
  IeeeF64
} derive(Debug, Eq)

///|
/// WAV 编解码的可恢复失败。所有结构损坏都返回该错误,不 panic。
pub suberror WavError {
  NotRiff
  NotWave
  Truncated(String)
  InvalidFormat(String)
  UnsupportedFormat(String)
  DataTooLarge
} derive(Debug)

///|
pub extend WavError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend WavSampleFormat with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend WavSampleFormat with Eq::{equal, not_equal}

///|
pub extend WaveFile with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// 解码得到的 WAV 内容:交错样本,统一归一化到 [-1, 1]。
pub struct WaveFile {
  priv sample_rate : Int
  priv channels : Int
  priv samples : Array[Double]
  priv source_format : WavSampleFormat
} derive(Debug)

///|
/// 构造并校验:声道数、采样率为正,样本数按声道帧对齐。
pub fn WaveFile::WaveFile(
  sample_rate~ : Int,
  channels~ : Int,
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
/// 采样率(Hz)。
pub fn WaveFile::sample_rate(self : WaveFile) -> Int {
  self.sample_rate
}

///|
/// 声道数。样本按声道交错排列。
pub fn WaveFile::channels(self : WaveFile) -> Int {
  self.channels
}

///|
/// 交错的归一化样本,长度 = 帧数 × 声道数。
pub fn WaveFile::samples(self : WaveFile) -> Array[Double] {
  self.samples
}

///|
/// fmt 块声明的原始存储格式。
pub fn WaveFile::source_format(self : WaveFile) -> WavSampleFormat {
  self.source_format
}

///|
/// 帧数(每声道的样本数)。
pub fn WaveFile::frame_count(self : WaveFile) -> Int {
  self.samples.length() / self.channels
}

///|
/// 时长(秒)。
pub fn WaveFile::duration_seconds(self : WaveFile) -> Double {
  self.samples.length().to_double() /
  self.channels.to_double() /
  self.sample_rate.to_double()
}

///|
/// 每样本字节数。
pub fn WavSampleFormat::bytes_per_sample(self : WavSampleFormat) -> Int {
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
/// 是否为整数 PCM 格式。
pub fn WavSampleFormat::is_pcm(self : WavSampleFormat) -> Bool {
  match self {
    PcmU8 | PcmI16 | PcmI24 | PcmI32 => true
    IeeeF32 | IeeeF64 => false
  }
}

///|
/// fmt 块中的 format tag(PCM=1,IEEE float=3)。
fn WavSampleFormat::format_tag(self : WavSampleFormat) -> Int {
  match self {
    PcmU8 | PcmI16 | PcmI24 | PcmI32 => 1
    IeeeF32 | IeeeF64 => 3
  }
}

///|
/// (format tag, 位深) → 存储格式;不认识的组合返回 None。
fn WavSampleFormat::from_tag_bits(tag : Int, bits : Int) -> WavSampleFormat? {
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
