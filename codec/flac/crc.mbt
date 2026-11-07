// 移植自 moonflac(https://github.com/Xcsa-ee/moonflac)
// 版权:Apache-2.0 (c) Xcsa-ee;来源 commit 151a1aca96925242f0d5f1ea19a79a30ce7b7068(2026-10-31)
// 移植说明:解码逻辑原样保留,仅适配包路径与依赖(见 docs/audio-codec.md)。

//
// FLAC 用的两个循环冗余校验（多项式与覆盖范围已由 ffmpeg 交叉验证）：
// - CRC-8：x^8 + x^2 + x + 1（0x07），覆盖帧头起始到 CRC-8 字节之前；
// - CRC-16：x^16 + x^15 + x^2 + 1（0x8005），覆盖帧起始到子帧字节对齐处。
// 两者都是 init=0、不反转、不异或输出的直接计算。

///|
/// 对字节区间 `[start, end)` 计算 CRC-8（多项式 0x07）。
fn crc8_range(data : Bytes, start : Int, end : Int) -> Int {
  let mut c = 0
  let hi = if end < data.length() { end } else { data.length() }
  let mut i = start
  while i < hi {
    c = c ^ data.unsafe_get(i).to_int()
    for _ in 0..<8 {
      c = if (c & 0x80) != 0 {
        ((c << 1) ^ 0x07) & 0xFF
      } else {
        (c << 1) & 0xFF
      }
    }
    i += 1
  }
  c
}

///|
/// 对字节区间 `[start, end)` 计算 CRC-16（多项式 0x8005）。
fn crc16_range(data : Bytes, start : Int, end : Int) -> Int {
  let mut c = 0
  let hi = if end < data.length() { end } else { data.length() }
  let mut i = start
  while i < hi {
    c = c ^ (data.unsafe_get(i).to_int() << 8)
    for _ in 0..<8 {
      c = if (c & 0x8000) != 0 {
        ((c << 1) ^ 0x8005) & 0xFFFF
      } else {
        (c << 1) & 0xFFFF
      }
    }
    i += 1
  }
  c
}
