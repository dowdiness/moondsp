///|
/// codec/render — 把 Mini 记谱离线渲染为 PCM 样本并编码为 WAV 字节。
///
/// 这是"合成器 ↔ 文件"闭环的桥:复用 scheduler 的 pattern 渲染路径
/// (`PatternScheduler::process_block`)逐块产出干声立体声样本,
/// 再交给 `codec/wav` 编码。全程离线、确定性(同一输入必得同一字节)。
///
/// 该包是 codec 家族中的集成层:依赖 scheduler/mini/dsp;`codec/wav`
/// 与 `codec/flac` 保持为无依赖的叶子包。

///|
/// 离线渲染的可恢复失败。
pub suberror RenderError {
  /// Mini 记谱解析失败(附解析器消息)。
  ParseFailed(String)
  /// 参数或合成器构造非法。
  InvalidConfig(String)
  /// WAV 编码失败。
  EncodeFailed(@wav.WavError)
} derive(Debug)

///|
pub extend RenderError with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// 默认合成器模板:正弦振荡器 → ADSR → 包络增益 → 输出。
/// `note` 控制音高(MIDI→Hz),`gain`/`pan` 走语音参数。
fn synth_template() -> Array[@moondsp.DspNode] {
  [
    @moondsp.DspNode::oscillator(@moondsp.Waveform::Sine, 440.0),
    @moondsp.DspNode::adsr(
      attack_ms=0.01,
      decay_ms=0.1,
      sustain=0.7,
      release_ms=30.0,
    ),
    @moondsp.DspNode::envelope_gain(input=0, envelope=1, amount=1.0),
    @moondsp.DspNode::output(2),
  ]
}

///|
fn synth_bindings() -> @moondsp.ControlBindingBuilder {
  @moondsp.ControlBindingBuilder()
  .bind(
    key="note",
    node_index=0,
    slot=@moondsp.GraphParamSlot::Value0,
    unit=@graph.ControlUnit::MidiToHz,
  )
  .bind_voice(key="gain", param=@graph.VoiceParam::Gain)
  .bind_voice(key="pan", param=@graph.VoiceParam::Pan)
}

///|
/// 把 Mini 记谱离线渲染为交错的 [-1, 1] Double 样本(立体声,左在前)。
///
/// 渲染 `ceil(seconds * sample_rate / block_size)` 个块;
/// 时长总采样数因此向上对齐到块边界。
pub fn render_samples(
  source~ : String,
  seconds~ : Double,
  sample_rate~ : Int,
  block_size? : Int = 128,
  bpm? : Double = 120.0,
  max_voices? : Int = 8,
) -> Array[Double] raise RenderError {
  guard seconds > 0.0 else {
    raise InvalidConfig("seconds must be positive, got " + seconds.to_string())
  }
  guard sample_rate > 0 && block_size > 0 else {
    raise InvalidConfig(
      "sample_rate and block_size must be positive, got " +
      sample_rate.to_string() +
      " / " +
      block_size.to_string(),
    )
  }
  let pat = match @mini.parse(source) {
    Ok(parsed) => parsed
    Err(message) => raise ParseFailed(message)
  }
  let ctx = @dsp.DspContext(sample_rate=sample_rate.to_double(), block_size~)
  let pool : @moondsp.BoundVoicePool = @moondsp.BoundVoicePool(
    @moondsp.AnalyzedGraph::analyze(synth_template()),
    ctx,
    synth_bindings(),
    max_voices~,
  ) catch {
    e => raise InvalidConfig("voice pool rejected: \{Repr(e)}")
  }
  let sched : @scheduler.PatternScheduler = @scheduler.PatternScheduler(
    bpm~,
    ctx~,
    instruments=[(@scheduler.InstrumentSelector::AllEvents, pool)],
  ) catch {
    _ => raise InvalidConfig("scheduler rejected: transport error")
  }
  let blocks = ceil_div(
    (seconds * sample_rate.to_double()).to_int(),
    block_size,
  )
  let left = @dsp.AudioBuffer::filled(block_size)
  let right = @dsp.AudioBuffer::filled(block_size)
  let out : Array[Double] = Array::make(blocks * block_size * 2, 0.0)
  let mut idx = 0
  for b = 0; b < blocks; b = b + 1 {
    sched.process_block(pat, left, right)
    for i = 0; i < block_size; i = i + 1 {
      out[idx] = left.get(i)
      out[idx + 1] = right.get(i)
      idx += 2
    }
  }
  out
}

///|
/// 把 Mini 记谱离线渲染并编码为 WAV 字节(立体声)。
///
/// 示例:`render_wav(source="note(\"60\") [4]", seconds=2.0, sample_rate=48000)`
/// 产出可直接写入 `.wav` 的字节流,ffplay/ffmpeg 均可播放。
pub fn render_wav(
  source~ : String,
  seconds~ : Double,
  sample_rate~ : Int,
  block_size? : Int = 128,
  bpm? : Double = 120.0,
  format? : @wav.WavSampleFormat = PcmI16,
  max_voices? : Int = 8,
) -> Bytes raise RenderError {
  let samples = render_samples(
    source~,
    seconds~,
    sample_rate~,
    block_size~,
    bpm~,
    max_voices~,
  )
  @wav.encode(format~, sample_rate~, channels=2, samples~) catch {
    e => raise EncodeFailed(e)
  }
}

///|
/// 向上取整的整除(n > 0, d > 0)。
fn ceil_div(n : Int, d : Int) -> Int {
  if n <= 0 {
    1
  } else {
    (n + d - 1) / d
  }
}
