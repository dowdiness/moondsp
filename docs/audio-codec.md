# Audio codec: WAV (`codec/wav`)

`codec/wav` 为 moondsp 提供纯 MoonBit 的 WAV 读写,零 FFI,可编译到 js / wasm-gc / native。

| 包 | 职责 | 依赖 |
|---|---|---|
| `codec/wav` | RIFF/WAVE 解码与编码 | core(debug) |

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

## 支持矩阵

| 能力 | js | wasm-gc | native | 说明 |
|---|---|---|---|---|
| WAV 解码/编码 | ✅ | ✅ | ✅ | 纯 MoonBit,零 FFI |

## 测试

- `codec/wav`:23 项(往返幂等、RIFX、EXTENSIBLE、LIST 跳过、结构化错误、
  12k 组 fuzz 零 panic、400 组 quickcheck 性质、ffmpeg 五格式逐样本交叉验证)

## 许可证与来源

- 本目录新增代码遵循仓库 LICENSE(Apache-2.0)
- WAV 编解码设计参考 [yabaobao070510/moonvoice](https://github.com/yabaobao070510/moonvoice)
  (Apache-2.0)的同名模块,代码为独立实现
- AI 工具使用:编解码代码由 AI 辅助生成;正确性由上述测试与
  ffmpeg 外部交叉验证兜底
