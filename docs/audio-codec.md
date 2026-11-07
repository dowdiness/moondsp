# Audio codec: WAV / FLAC / offline render (`codec/`)

`codec/` 为 moondsp 补齐音频文件编解码层:纯 MoonBit 的 WAV 读写、FLAC 解码、
统一解码入口,以及"Mini 记谱 → 离线渲染 → `.wav`"的完整闭环。
零 C 依赖(除 CLI 示例的写文件桥),可编译到 js / wasm-gc / native。

## 包结构

| 包 | 职责 | 依赖 |
|---|---|---|
| `codec/wav` | RIFF/WAVE 解码与编码 | core(debug) |
| `codec/flac` | FLAC 无损解码(移植自 moonflac) | core(buffer/utf8)、moonbitlang/x/crypto(MD5 校验) |
| `codec` | 统一入口 `decode_any` + `AudioFile` | codec/wav、codec/flac |
| `codec/render` | Mini 记谱离线渲染 → PCM/WAV | codec/wav、dsp、graph、mini、scheduler |
| `examples/render-to-file` | CLI 示例:渲染落盘(native) | codec/render、core/env |

## WAV(`codec/wav`)

解码支持:RIFF(小端)与 RIFX(大端)容器;PCM u8/i16/i24/i32 与 IEEE
float32/64;WAVE_FORMAT_EXTENSIBLE(0xFFFE,含 SubFormat GUID);未知块
(LIST/INFO 等)跳过并按偶数字节对齐;所有结构损坏返回结构化错误,不 panic。

```moonbit
// 解码:交错 [-1, 1] Double 样本
let file : WaveFile = @wav.decode(bytes)
file.sample_rate() // Int
file.channels()    // Int
file.samples()     // Array[Double](按声道交错)
file.source_format() // WavSampleFormat

// 编码:六种采样格式;>2 声道自动写 EXTENSIBLE;奇数 data 块自动补零
let bytes : Bytes = @wav.encode(format=PcmI16, sample_rate=48000, channels=2, samples~)
```

量化约定:PCM 以 2^(bits-1) 为比例四舍五入并钳位(精确二进分数),
保证 `decode(encode(x))` 幂等;float32/64 原样按位存取。NaN 归 0、±Inf 取满幅。

## FLAC(`codec/flac`)

移植自 [Xcsa-ee/moonflac](https://github.com/Xcsa-ee/moonflac)
(Apache-2.0,commit `151a1aca96925242f0d5f1ea19a79a30ce7b7068`,2026-10-31),
解码逻辑原样保留,仅适配包路径、依赖与错误类型的 Debug 派生。

- 流程:元数据块 → 帧定位(同步扫描 + 帧头校验)→ 子帧解码 → 声道去相关
- 校验:CRC-8/CRC-16 逐帧校验;STREAMINFO 记录 MD5 时对解码 PCM 做 MD5 校验
- 元数据:SEEKTABLE / VORBIS_COMMENT / PICTURE / CUESHEET / APPLICATION 结构化解析
- 容错:帧头级失败向后扫描重同步;子帧/CRC-16 失败直接报错不跳帧;
  `total_samples` 已知时截断输出并检测截断

```moonbit
let f : @flac.FlacFile = @flac.decode(bytes)
// f.info : StreamInfo(sample_rate / channels / bits_per_sample / total_samples / md5)
// f.channels : Array[Array[Int]](planar,每声道一个数组,bps 位宽有符号值)
```

## 统一入口(`codec`)

```moonbit
let audio : AudioFile = @codec.decode_any(bytes) // 按魔数路由
// RIFF/RIFX → @wav.decode;fLaC → @flac.decode;其他 → NotAudio
// 失败:CodecError { NotAudio(String) | WavFailed(WavError) | FlacFailed(FlacError) }
audio.sample_rate() / audio.channels() / audio.samples() / audio.source_format()
```

同一音频的 WAV 与 FLAC 经 `decode_any` 输出逐位一致(FLAC 无损;见
`codec/decode_test.mbt` 的 ffmpeg 交叉验证)。

## 离线渲染(`codec/render`)

```moonbit
// Mini 记谱 → WAV 字节(确定性输出)
let bytes : Bytes = @render.render_wav(
  source="note(\"60 [60 67]\") .gain(0.8)",
  seconds=2.0,
  sample_rate=48000,        // block_size=128、bpm=120.0、format=PcmI16 有默认值
)
```

渲染路径:`@mini.parse` → `PatternScheduler::process_block` 逐块产出干声
立体声 → 交错成 `Array[Double]` → `@wav.encode`。时长向上对齐到块边界
(`ceil(seconds × sample_rate / block_size)` 块)。

CLI 示例见 [examples/render-to-file](../examples/render-to-file/README.md):
`moon run examples/render-to-file --target native` 产出 `out.wav`,
经 ffprobe 校验格式正确、ffmpeg 解码无错。

## 支持矩阵

| 能力 | js | wasm-gc | native | 说明 |
|---|---|---|---|---|
| WAV 解码/编码 | ✅ | ✅ | ✅ | 纯 MoonBit,零 FFI |
| FLAC 解码 | ✅ | ✅ | ✅ | 纯 MoonBit;MD5 用 moonbitlang/x |
| `decode_any` | ✅ | ✅ | ✅ | |
| `render_wav` | ✅ | ✅ | ✅ | 渲染不涉及 IO |
| CLI 写文件 | ❌ | ❌ | ✅ | `native-stub` C 桥 |

## 测试

- `codec/wav`:23 项(往返幂等、RIFX、EXTENSIBLE、LIST 跳过、结构化错误、
  12k 组 fuzz 零 panic、400 组 quickcheck 性质、ffmpeg 五格式逐样本交叉验证)
- `codec`:ffmpeg 生成同音频 WAV/FLAC,`decode_any` 双路逐位一致
- `codec/render`:确定性、块对齐、往返、结构化错误

## 许可证与移植来源

- 本目录新增代码遵循仓库 LICENSE(Apache-2.0)
- `codec/flac` 移植自 moonflac(Apache-2.0 (c) Xcsa-ee),各文件头部保留
  来源声明:https://github.com/Xcsa-ee/moonflac
- WAV 编解码设计参考 [yabaobao070510/moonvoice](https://github.com/yabaobao070510/moonvoice)
  (Apache-2.0)的同名模块,代码为独立实现
- AI 工具使用:编解码与渲染代码由 AI 辅助生成;正确性由上述测试与
  ffmpeg 外部交叉验证兜底,接口与边界遵循仓库架构评审约定
