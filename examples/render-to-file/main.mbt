///|
/// render-to-file:把一段 Mini 记谱离线渲染为 `.wav`。
/// 文件写入仅 native target 支持(wasm/js target 打印提示并退出)。
///
/// 用法(仓库根目录):
///
/// ```sh
/// moon run examples/render-to-file --target native
/// moon run examples/render-to-file --target native -- "note(\"60 [60 67]\")" out.wav 2000
/// ```
///
/// 第三个参数是渲染时长(毫秒)。无参数时使用内置示例乐句;
/// 输出文件可用 ffplay / ffmpeg 播放校验。
fn main {
  let args = @env.args()
  let source = if args.length() > 1 {
    args[1]
  } else {
    "note(\"60 [60 60 67]\") .gain(0.8)"
  }
  let output = if args.length() > 2 { args[2] } else { "out.wav" }
  let seconds = if args.length() > 3 {
    match parse_millis(args[3]) {
      Some(v) => v
      None => {
        println("invalid milliseconds: " + args[3])
        return
      }
    }
  } else {
    2.0
  }
  let bytes = match
    (Ok(@render.render_wav(source~, seconds~, sample_rate=48000)) catch {
      e => Err(e)
    }) {
    Ok(data) => data
    Err(e) => {
      println("render failed: \{Repr(e)}")
      return
    }
  }
  let code = write_wav_file(output, bytes)
  if code == 0 {
    let frames = (bytes.length() - 44) / 4
    println(
      "wrote " +
      output +
      ": " +
      bytes.length().to_string() +
      " bytes, " +
      (frames.to_double() / 48000.0).to_string() +
      " s @ 48 kHz stereo i16",
    )
  } else if code == -100 {
    println(
      "file writing requires the native target: moon run examples/render-to-file --target native",
    )
  } else {
    println("write failed with code " + code.to_string())
  }
}

///|
/// 解析整数毫秒("2000" → 2.0 秒);非法输入返回 None。
fn parse_millis(text : String) -> Double? {
  let mut total = 0
  for i = 0; i < text.length(); i = i + 1 {
    let c = text.get_char(i).unwrap().to_int()
    guard c >= 0x30 && c <= 0x39 else { return None }
    total = total * 10 + (c - 0x30)
  }
  Some(total.to_double() / 1000.0)
}
