// 移植自 moonflac(https://github.com/Xcsa-ee/moonflac)
// 版权:Apache-2.0 (c) Xcsa-ee;来源 commit 151a1aca96925242f0d5f1ea19a79a30ce7b7068(2026-10-31)
// 移植说明:解码逻辑原样保留,仅适配包路径与依赖(见 docs/audio-codec.md)。

//
// MSB-first 位读取器：FLAC 的比特流最高位先读——每个字节内 bit7 最先读出，
// 跨字节时高位字节先读。这与 moonvorbis 里 Vorbis 的 LSB-first 恰好相反。
//
// 越界读取不 panic：读到末尾会置 `truncated` 标志并返回 0，
// 由调用方在帧边界上用 `check` 统一转成错误。

///|
/// MSB-first 位读取器。
struct BitReader {
  data : Bytes
  mut pos : Int // 当前位位置，从 0 开始
  mut truncated : Bool // 是否发生过越界读取
}

///|
/// 用整段字节序列构造从第 0 位开始的读取器。
fn BitReader::new(data : Bytes) -> BitReader {
  { data, pos: 0, truncated: false, }
}

///|
/// 总位数。
pub fn BitReader::total_bits(self : BitReader) -> Int {
  self.data.length() * 8
}

///|
/// 剩余可读位数。
pub fn BitReader::remaining_bits(self : BitReader) -> Int {
  self.total_bits() - self.pos
}

///|
/// 移动到位位置 `pos`（字节对齐处）。越界位置视为读取失败而不是 panic。
fn BitReader::seek(self : BitReader, pos : Int) -> Unit {
  if pos < 0 || pos > self.total_bits() {
    self.truncated = true
    self.pos = if pos < 0 { 0 } else { self.total_bits() }
    return
  }
  self.pos = pos
}

///|
/// 读 1 位（MSB-first）。越界时返回 0 并置 truncated。
pub fn BitReader::read_bit(self : BitReader) -> Int {
  let byte_index = self.pos >> 3
  if byte_index >= self.data.length() {
    self.truncated = true
    return 0
  }
  let shift = 7 - (self.pos & 7)
  self.pos += 1
  (self.data.unsafe_get(byte_index).to_int() >> shift) & 1
}

///|
/// 连续读 `n` 位（`0 <= n <= 40`），按位扩展后的 Int64 返回。
/// 用 Int64 累加避免 31 位以上左移溢出 Int。
fn BitReader::read_bits64(self : BitReader, n : Int) -> Int64 {
  guard! n >= 0 && n <= 40
  let mut acc = 0L
  for _ in 0..<n {
    acc = acc * 2 + Int64::from_int(self.read_bit())
  }
  acc
}

///|
/// 读 `n` 位并符号扩展为 Int64（子帧位宽最大 33，side 声道在 32bps 时需要）。
fn BitReader::read_sample64(self : BitReader, n : Int) -> Int64 {
  if n <= 0 {
    if n < 0 {
      self.truncated = true
    }
    return 0L
  }
  if n >= 64 {
    self.truncated = true
    return 0L
  }
  let v = self.read_bits64(n)
  let limit = Int64::from_int(1) << (n - 1)
  if v >= limit {
    v - (Int64::from_int(1) << n)
  } else {
    v
  }
}

///|
/// 是否落在字节边界上。
fn BitReader::is_aligned(self : BitReader) -> Bool {
  (self.pos & 7) == 0
}

///|
/// 若发生过越界读取，抛出 Truncated 错误（带发生时的位置）。
fn BitReader::check(self : BitReader) -> Unit raise FlacError {
  if self.truncated {
    let offset = self.pos
    self.truncated = false
    raise Truncated(offset~, need=1, actual=self.data.length() * 8)
  }
}
