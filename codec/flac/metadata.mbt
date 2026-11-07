// 移植自 moonflac(https://github.com/Xcsa-ee/moonflac)
// 版权:Apache-2.0 (c) Xcsa-ee;来源 commit 151a1aca96925242f0d5f1ea19a79a30ce7b7068(2026-10-31)
// 移植说明:解码逻辑原样保留,仅适配包路径与依赖(见 docs/audio-codec.md)。

//
// FLAC 流自描述头：`fLaC` 魔数 + 元数据块链。
// STREAMINFO 是必且唯一的第一个块；其余块（PADDING/SEEKTABLE/VORBIS_COMMENT/…）
// 在 M1 只记录偏移与长度，内容解析留给后续增量。
// 所有输入校验都返回结构化错误——文件是外部不可信输入。

///|
/// STREAMINFO 的解析结果。
pub struct StreamInfo {
  /// 最小块长（样本数）。
  min_block_size : Int
  /// 最大块长（样本数）。
  max_block_size : Int
  /// 最小帧长（字节），0 表示未知。
  min_frame_size : Int
  /// 最大帧长（字节），0 表示未知。
  max_frame_size : Int
  /// 采样率（Hz），1..655350。
  sample_rate : Int
  /// 声道数，1..8。
  channels : Int
  /// 位深，4..32。
  bits_per_sample : Int
  /// 总样本数，0 表示未知。
  total_samples : Int64
  /// MD5 原始签名（16 字节）。
  md5 : Bytes
}

///|
/// STREAMINFO 之外的元数据块（只记录位置，不拷贝数据）。
pub struct MetadataBlock {
  /// 块类型码（1=PADDING 2=APPLICATION 3=SEEKTABLE 4=VORBIS_COMMENT 5=CUESHEET 6=PICTURE）。
  block_type : Int
  /// 相对文件起始的字节偏移。
  offset : Int
  /// 载荷字节长度。
  length : Int
}

///|
/// 元数据解析结果。
pub struct ParsedMetadata {
  /// 流的 STREAMINFO。
  stream_info : StreamInfo
  /// 其余元数据块（不含 STREAMINFO）。
  blocks : Array[MetadataBlock]
  /// 第一个音频帧的字节偏移。
  frame_offset : Int
}

///|
/// 断言 `[offset, offset + length)` 在数据范围内，否则抛 Truncated。
fn require_range(
  data : Bytes,
  offset : Int,
  length : Int,
) -> Unit raise FlacError {
  if offset < 0 ||
    length < 0 ||
    offset > data.length() ||
    data.length() - offset < length {
    raise Truncated(offset~, need=length, actual=data.length())
  }
}

///|
/// 读 1..3 字节大端序无符号整数（帧长/块长字段都在 24 位内，不会溢出 Int）。
fn read_be(data : Bytes, offset : Int, length : Int) -> Int raise FlacError {
  require_range(data, offset, length)
  let mut v = 0
  for i in 0..<length {
    v = (v << 8) | data.unsafe_get(offset + i).to_int()
  }
  v
}

///|
/// 解析 STREAMINFO 的 34 字节载荷。
fn parse_streaminfo(data : Bytes, offset : Int) -> StreamInfo raise FlacError {
  require_range(data, offset, 34)
  let min_block_size = read_be(data, offset, 2)
  let max_block_size = read_be(data, offset + 2, 2)
  let min_frame_size = read_be(data, offset + 4, 3)
  let max_frame_size = read_be(data, offset + 7, 3)
  // 字节 10..18：20 位采样率 | 3 位声道数-1 | 5 位位深-1 | 36 位总样本数
  let b0 = data.unsafe_get(offset + 10).to_int()
  let b1 = data.unsafe_get(offset + 11).to_int()
  let b2 = data.unsafe_get(offset + 12).to_int()
  let b3 = data.unsafe_get(offset + 13).to_int()
  let sample_rate = (b0 << 12) | (b1 << 4) | (b2 >> 4)
  let channels = ((b2 >> 1) & 0x7) + 1
  let bits_per_sample = (((b2 & 0x1) << 4) | (b3 >> 4)) + 1
  let mut total = Int64::from_int(b3 & 0x0F) << 32
  for i in 14..<18 {
    total = total |
      (Int64::from_int(data.unsafe_get(offset + i).to_int()) << ((17 - i) * 8))
  }
  if sample_rate < 1 || sample_rate > 655350 {
    raise BadMetadata(reason="采样率非法")
  }
  if bits_per_sample < 4 || bits_per_sample > 32 {
    raise BadMetadata(reason="位深非法（合法范围 4..32）")
  }
  if channels < 1 || channels > 8 {
    raise BadMetadata(reason="声道数非法")
  }
  if max_block_size < 16 ||
    min_block_size < 1 ||
    min_block_size > max_block_size {
    raise BadMetadata(reason="块长范围非法")
  }
  let md5w = @buffer.Buffer()
  for i in 18..<34 {
    md5w.write_byte(data.unsafe_get(offset + i))
  }
  {
    min_block_size,
    max_block_size,
    min_frame_size,
    max_frame_size,
    sample_rate,
    channels,
    bits_per_sample,
    total_samples: total,
    md5: md5w.to_bytes(),
  }
}

///|
/// 解析 `fLaC` 魔数与全部元数据块，返回 STREAMINFO、其余块的位置表与
/// 第一个音频帧的偏移。
pub fn parse_metadata(data : Bytes) -> ParsedMetadata raise FlacError {
  require_range(data, 0, 4)
  if data.unsafe_get(0).to_int() != 0x66 ||
    data.unsafe_get(1).to_int() != 0x4C ||
    data.unsafe_get(2).to_int() != 0x61 ||
    data.unsafe_get(3).to_int() != 0x43 {
    raise NotFlac
  }
  let mut info : StreamInfo? = None
  let blocks = []
  let mut p = 4
  let mut frame_offset = -1
  while frame_offset < 0 {
    require_range(data, p, 4)
    let first = data.unsafe_get(p).to_int()
    let last = (first >> 7) & 1
    let block_type = first & 0x7F
    // 24 位块长——不能按 32 位大端整数读，last 标志会把 Int 顶溢出
    let length = (data.unsafe_get(p + 1).to_int() << 16) |
      (data.unsafe_get(p + 2).to_int() << 8) |
      data.unsafe_get(p + 3).to_int()
    require_range(data, p + 4, length)
    if block_type == 0 {
      if info is Some(_) {
        raise BadMetadata(reason="STREAMINFO 出现多次")
      }
      if length != 34 {
        raise BadMetadata(reason="STREAMINFO 长度必须为 34")
      }
      info = Some(parse_streaminfo(data, p + 4))
    } else if block_type == 127 {
      // 127 是禁用值（避免与帧同步码混淆）；7..126 为保留值，真实文件
      // （xiph 官方测试文件含 type 126）在用，按 libFLAC 的做法跳过继续
      raise BadMetadata(reason="元数据块类型 127 为禁用值")
    } else {
      blocks.push({ block_type, offset: p + 4, length, })
    }
    p = p + 4 + length
    if last != 0 {
      frame_offset = p
    }
  }
  match info {
    Some(stream_info) => { stream_info, blocks, frame_offset, }
    None => raise BadMetadata(reason="缺少 STREAMINFO")
  }
}
