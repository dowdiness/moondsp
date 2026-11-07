# render-to-file

把一段 [Mini 记谱](../../docs/mini-notation.md) 离线渲染为 `.wav`
(48 kHz 立体声 16-bit PCM)。文件写入仅支持 native target
(`moon run` 的 `--target native`),wasm/js target 会打印提示退出。

## 三步复现

```sh
# 1. 用内置示例乐句渲染 2 秒到 out.wav
moon run examples/render-to-file --target native

# 2. 自定义乐句 / 输出名 / 时长(毫秒)
moon run examples/render-to-file --target native -- "note(\"60 [60 67]\")" out.wav 2000

# 3. 外部校验(可选)
ffprobe out.wav
```

预期输出:

```text
wrote out.wav: 384044 bytes, 2 s @ 48 kHz stereo i16
```

`ffprobe` 应显示 `pcm_s16le, 48000 Hz, 2 channels, duration=2.000000`。

## 实现说明

- 渲染走 `codec/render` 的 `render_wav`:Mini 解析 → `PatternScheduler`
  逐块离线渲染 → `codec/wav` 编码,全程确定性。
- 写文件通过 `io.c`(`native-stub`)桥接平台 `FILE*`;MoonBit 侧声明见
  `native_io.mbt`,仅 native target 编译。
