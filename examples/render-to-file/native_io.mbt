///|
/// 写二进制文件的 C 桥(仅 native target)。
/// 返回 0 = 成功;-1 打开失败;-4 写入不完整;-3 参数非法。
#borrow(path, data)
extern "C" fn moondsp_write_file(
  path : String,
  path_units : Int,
  data : Bytes,
  data_len : Int,
) -> Int = "moondsp_write_file"

///|
/// 把渲染得到的 WAV 字节写到磁盘。路径按平台原生规则解析。
fn write_wav_file(output : String, bytes : Bytes) -> Int {
  moondsp_write_file(output, output.length(), bytes, bytes.length())
}
