///|
/// codec — 统一音频解码入口:按容器魔数路由到 WAV / FLAC,输出统一的
/// 交错 [-1, 1] Double 样本(`AudioFile`)。
///
/// 该包只做路由与格式归一,不依赖 engine/scheduler/browser 等上层。

///|
/// 音频来源容器格式。
pub(all) enum SourceFormat {
  Wav
  Flac
} derive(Debug, Eq)

///|
pub extend SourceFormat with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SourceFormat with Eq::{equal, not_equal}

///|
/// 统一解码结果:交错样本,归一化到 [-1, 1]。
pub struct AudioFile {
  priv sample_rate : Int
  priv channels : Int
  priv samples : Array[Double]
  priv source_format : SourceFormat
} derive(Debug)

///|
pub extend AudioFile with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// 构造并校验帧对齐。
pub fn AudioFile::AudioFile(
  sample_rate~ : Int,
  channels~ : Int,
  samples~ : Array[Double],
  source_format~ : SourceFormat,
) -> AudioFile raise CodecError {
  guard sample_rate > 0 else {
    raise NotAudio("sample rate = " + sample_rate.to_string())
  }
  guard channels > 0 else {
    raise NotAudio("channels = " + channels.to_string())
  }
  guard samples.length() % channels == 0 else {
    raise NotAudio(
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
pub fn AudioFile::sample_rate(self : AudioFile) -> Int {
  self.sample_rate
}

///|
pub fn AudioFile::channels(self : AudioFile) -> Int {
  self.channels
}

///|
pub fn AudioFile::samples(self : AudioFile) -> Array[Double] {
  self.samples
}

///|
pub fn AudioFile::source_format(self : AudioFile) -> SourceFormat {
  self.source_format
}

///|
/// 帧数(每声道样本数)。
pub fn AudioFile::frame_count(self : AudioFile) -> Int {
  self.samples.length() / self.channels
}

///|
/// 时长(秒)。
pub fn AudioFile::duration_seconds(self : AudioFile) -> Double {
  self.samples.length().to_double() /
  self.channels.to_double() /
  self.sample_rate.to_double()
}

///|
/// 统一编解码错误:路由失败或底层解码器失败。
pub suberror CodecError {
  NotAudio(String)
  WavFailed(@wav.WavError)
  FlacFailed(@flac.FlacError)
} derive(Debug)

///|
pub extend CodecError with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// 按魔数路由解码:RIFF/RIFX → WAV,fLaC → FLAC。
pub fn decode_any(bytes : Bytes) -> AudioFile raise CodecError {
  guard bytes.length() >= 4 else { raise NotAudio("input too short") }
  let magic = tag4(bytes, 0)
  if magic == "RIFF" || magic == "RIFX" {
    let file = @wav.decode(bytes) catch { e => raise WavFailed(e) }
    AudioFile::AudioFile(
      sample_rate=file.sample_rate(),
      channels=file.channels(),
      samples=file.samples(),
      source_format=Wav,
    )
  } else if magic == "fLaC" {
    flac_to_audio(@flac.decode(bytes) catch { e => raise FlacFailed(e) })
  } else {
    raise NotAudio("unrecognized container magic: " + magic)
  }
}

///|
/// 读四字节魔数(仅用于路由,不用于错误消息,无需转义)。
fn tag4(b : Bytes, off : Int) -> String {
  let buf = StringBuilder()
  for i = 0; i < 4; i = i + 1 {
    buf.write_char(b[off + i].to_int().to_char().unwrap())
  }
  buf.to_string()
}

///|
/// FLAC planar 有符号整数样本 → 统一交错 [-1, 1] Double。
/// 归一化比例 2^(bps-1)(FLAC 样本是有符号 bps 位宽整数),2 的整数幂在
/// Double 下精确,无损位深范围内的往返一致。
fn flac_to_audio(f : @flac.FlacFile) -> AudioFile raise CodecError {
  let info = f.info
  let bps = info.bits_per_sample
  guard bps >= 4 && bps <= 32 else {
    raise NotAudio("flac bits per sample out of range: " + bps.to_string())
  }
  let nch = info.channels
  let frames = if nch > 0 && f.channels.length() > 0 {
    f.channels[0].length()
  } else {
    0
  }
  // 逐次乘 2 构造 2^(bps-1):每次乘法无舍入,精确
  let mut scale = 1.0
  for i = 0; i < bps - 1; i = i + 1 {
    scale = scale * 2.0
  }
  let samples : Array[Double] = Array::make(frames * nch, 0.0)
  let mut idx = 0
  for i = 0; i < frames; i = i + 1 {
    for c = 0; c < nch; c = c + 1 {
      samples[idx] = f.channels[c][i].to_double() / scale
      idx = idx + 1
    }
  }
  AudioFile::AudioFile(
    sample_rate=info.sample_rate,
    channels=nch,
    samples~,
    source_format=Flac,
  )
}
