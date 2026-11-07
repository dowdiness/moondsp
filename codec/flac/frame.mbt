// 移植自 moonflac(https://github.com/Xcsa-ee/moonflac)
// 版权:Apache-2.0 (c) Xcsa-ee;来源 commit 151a1aca96925242f0d5f1ea19a79a30ce7b7068(2026-10-31)
// 移植说明:解码逻辑原样保留,仅适配包路径与依赖(见 docs/audio-codec.md)。

//
// 音频帧头解析与同步扫描。帧头结构（各字段宽度与校验已由 ffmpeg
// 交叉验证：帧同步 14 位 + 保留位 + 块长码/采样率码/声道分配/位深码 +
// UTF-8 形变变长帧号/样本号 + 扩展字段 + CRC-8）。

///|
/// 解析成功的帧头。
priv struct FrameHeader {
  /// 本帧每声道的样本数。
  block_size : Int
  /// 声道分配码：0..7 独立声道，8=left/side，9=right/side，10=mid/side。
  channel_assignment : Int
  /// 声道数。
  channels : Int
  /// 本帧位深（side 声道会在此基础上 +1）。
  bits_per_sample : Int
  /// 帧起始字节偏移（CRC-16 覆盖范围的起点）。
  start_byte : Int
}

///|
/// 采样率码 1..11 对应的固定采样率。
fn fixed_sample_rate(code : Int) -> Int {
  if code == 1 {
    return 88200
  }
  if code == 2 {
    return 176400
  }
  if code == 3 {
    return 192000
  }
  if code == 4 {
    return 8000
  }
  if code == 5 {
    return 16000
  }
  if code == 6 {
    return 22050
  }
  if code == 7 {
    return 24000
  }
  if code == 8 {
    return 32000
  }
  if code == 9 {
    return 44100
  }
  if code == 10 {
    return 48000
  }
  96000
}

///|
/// 读 UTF-8 形变的变长正整数（借 UTF-8 字节形状编码最长 36 位，
/// 与 Unicode 语义无关：0xFF 非法、前缀单个 1 非法、续字节须为 10xxxxxx）。
fn read_coded_number(br : BitReader) -> Int64 raise FlacError {
  let b0 = br.read_bits64(8).to_int()
  br.check()
  if b0 == 0xFF {
    raise BadFrameHeader(reason="变长帧号出现 0xFF")
  }
  let mut k = 0
  let mut mask = 0x80
  while mask != 0 && (b0 & mask) != 0 {
    k += 1
    mask = mask >> 1
  }
  if k == 0 {
    return Int64::from_int(b0)
  }
  if k == 1 {
    // 10xxxxxx 是续字节形状，不能作为首字节
    raise BadFrameHeader(reason="变长帧号首字节非法")
  }
  // k 个前导 1 -> 共 k 字节；首字节数据位 8-k-1 个
  let mut value = Int64::from_int(b0 & ((1 << (7 - k)) - 1))
  for _ in 1..<k {
    let b = br.read_bits64(8).to_int()
    br.check()
    if (b & 0xC0) != 0x80 {
      raise BadFrameHeader(reason="变长帧号续字节非法")
    }
    value = (value << 6) | Int64::from_int(b & 0x3F)
  }
  value
}

///|
/// 在字节层面扫描下一个帧同步候选（0xFF + 111110x，且保留位为 0）。
/// 返回字节偏移，未找到返回 -1。
fn scan_sync(data : Bytes, from_byte : Int) -> Int {
  let mut i = if from_byte < 0 { 0 } else { from_byte }
  while i + 1 < data.length() {
    if data.unsafe_get(i).to_int() == 0xFF &&
      (data.unsafe_get(i + 1).to_int() & 0xFE) == 0xF8 {
      return i
    }
    i += 1
  }
  -1
}

///|
/// 从当前位置（须在帧起始字节上）解析完整帧头，含 CRC-8 校验。
/// 成功后读取器停在子帧区起点（字节对齐）。
fn parse_frame_header(
  br : BitReader,
  info : StreamInfo,
) -> FrameHeader raise FlacError {
  if !br.is_aligned() {
    raise BadFrameHeader(reason="帧头未字节对齐")
  }
  let start_byte = br.pos >> 3
  let sync = br.read_bits64(14).to_int()
  // 每读完一个字段就先 check 越界，避免"数据不足"被后续字段校验
  // 误报成 BadFrameHeader（增量解码依赖 Truncated 与之区分）。
  br.check()
  if sync != 0x3FFE {
    raise BadFrameHeader(reason="帧同步码错误")
  }
  let reserved = br.read_bit()
  br.check()
  if reserved != 0 {
    raise BadFrameHeader(reason="帧头保留位非零")
  }
  let _ = br.read_bit() // 阻塞策略位：M1 不做按样本号校验，读过即可
  br.check()
  let bs_code = br.read_bits64(4).to_int()
  br.check()
  if bs_code == 0 {
    raise BadFrameHeader(reason="块长码 0 为保留值")
  }
  let sr_code = br.read_bits64(4).to_int()
  br.check()
  if sr_code == 15 {
    raise BadFrameHeader(reason="采样率码 15 为保留值")
  }
  let ch_code = br.read_bits64(4).to_int()
  br.check()
  if ch_code > 10 {
    raise BadFrameHeader(reason="声道分配码超过 10")
  }
  let ss_code = br.read_bits64(3).to_int()
  br.check()
  if ss_code == 3 {
    raise BadFrameHeader(reason="位深码 3 为保留值")
  }
  let last_reserved = br.read_bit()
  br.check()
  if last_reserved != 0 {
    raise BadFrameHeader(reason="帧头末保留位非零")
  }
  let _ = read_coded_number(br) // 帧号/样本号：读过即校验其编码合法性
  // 块长扩展字段（跟在变长帧号之后）
  let mut block_size = if bs_code == 1 {
    192
  } else if bs_code <= 5 {
    576 << (bs_code - 2)
  } else if bs_code <= 7 {
    0 // 8/16 位扩展字段，下面读取
  } else {
    256 << (bs_code - 8)
  }
  if bs_code == 6 {
    block_size = br.read_bits64(8).to_int() + 1
  } else if bs_code == 7 {
    block_size = br.read_bits64(16).to_int() + 1
  }
  br.check()
  // RFC 9639 §9.1.6：块长 65536（码 7 的字段值 65535）被规范禁止
  // （"A value of 65535 ... is forbidden"），因为 STREAMINFO 的
  // max_block_size 是 u(16)，最大只能表示 65535。合法上限是 65535。
  if block_size < 1 || block_size > 65535 {
    raise BadFrameHeader(reason="块长超出合法范围（1..65535）")
  }
  // 采样率扩展字段
  let mut sample_rate = if sr_code == 0 {
    info.sample_rate
  } else if sr_code <= 11 {
    fixed_sample_rate(sr_code)
  } else {
    0
  }
  if sr_code == 12 {
    sample_rate = br.read_bits64(8).to_int() * 1000
  } else if sr_code == 13 {
    sample_rate = br.read_bits64(16).to_int()
  } else if sr_code == 14 {
    sample_rate = br.read_bits64(16).to_int() * 10
  }
  br.check()
  if sample_rate < 1 {
    raise BadFrameHeader(reason="采样率为 0")
  }
  // 此处读取器落在字节边界：帧头全部字段都是字节数的整数倍
  if !br.is_aligned() {
    raise BadFrameHeader(reason="帧头结束未字节对齐")
  }
  let header_end = br.pos >> 3
  let expect_crc = br.read_bits64(8).to_int()
  br.check()
  let actual = crc8_range(br.data, start_byte, header_end)
  if expect_crc != actual {
    raise BadCrc(kind="CRC-8", expected=actual, actual=expect_crc)
  }
  let channels = if ch_code < 8 { ch_code + 1 } else { 2 }
  let bits_per_sample = if ss_code == 0 {
    info.bits_per_sample
  } else if ss_code == 1 {
    8
  } else if ss_code == 2 {
    12
  } else if ss_code == 4 {
    16
  } else if ss_code == 5 {
    20
  } else if ss_code == 6 {
    24
  } else {
    32
  }
  {
    block_size,
    channel_assignment: ch_code,
    channels,
    bits_per_sample,
    start_byte,
  }
}
