// 移植自 moonflac(https://github.com/Xcsa-ee/moonflac)
// 版权:Apache-2.0 (c) Xcsa-ee;来源 commit 151a1aca96925242f0d5f1ea19a79a30ce7b7068(2026-10-31)
// 移植说明:解码逻辑原样保留,仅适配包路径与依赖(见 docs/audio-codec.md)。

//
// 元数据块内容读取（M6 增量）。parse_metadata 只记录块的位置，
// 这里按需把 SEEKTABLE / VORBIS_COMMENT / PICTURE / APPLICATION 解析成结构。
// 所有长度字段先做边界与溢出校验——块数据同样来自外部不可信输入。

///|
/// 字节区间切片拷贝（Bytes 无子视图，小范围拷贝即可）。
fn slice_bytes(
  data : Bytes,
  offset : Int,
  length : Int,
) -> Bytes raise FlacError {
  require_range(data, offset, length)
  let buf = @buffer.Buffer()
  for i in 0..<length {
    buf.write_byte(data.unsafe_get(offset + i))
  }
  buf.to_bytes()
}

///|
/// 大端 u32，但要求 < 2^31（长度/尺寸字段语义上限，防 Int 溢出）。
fn be32_len(data : Bytes, offset : Int) -> Int raise FlacError {
  require_range(data, offset, 4)
  let b0 = data.unsafe_get(offset).to_int()
  if b0 >= 0x80 {
    raise BadMetadata(reason="32 位长度字段超出范围")
  }
  (b0 << 24) |
  (data.unsafe_get(offset + 1).to_int() << 16) |
  (data.unsafe_get(offset + 2).to_int() << 8) |
  data.unsafe_get(offset + 3).to_int()
}

///|
/// 小端 u32（VORBIS_COMMENT 用），同样限制 < 2^31。
fn le32_len(data : Bytes, offset : Int) -> Int raise FlacError {
  require_range(data, offset, 4)
  let b3 = data.unsafe_get(offset + 3).to_int()
  if b3 >= 0x80 {
    raise BadMetadata(reason="32 位长度字段超出范围")
  }
  data.unsafe_get(offset).to_int() |
  (data.unsafe_get(offset + 1).to_int() << 8) |
  (data.unsafe_get(offset + 2).to_int() << 16) |
  (b3 << 24)
}

///|
/// SEEKTABLE 的一个定位点。
pub struct SeekPoint {
  /// 该帧首样本的样本序号。
  sample_position : Int64
  /// 该帧在文件中的字节偏移。
  byte_offset : Int64
  /// 该帧的样本数。
  frame_samples : Int
}

///|
/// 读 SEEKTABLE：每点 18 字节（大端 样本号 8 + 字节偏移 8 + 帧长 2）。
/// 样本号全 1 的占位点按规范忽略；点数必须与块长整除。
pub fn read_seektable(
  data : Bytes,
  block : MetadataBlock,
) -> Array[SeekPoint] raise FlacError {
  require_range(data, block.offset, block.length)
  if block.length % 18 != 0 {
    raise BadMetadata(reason="SEEKTABLE 长度不是 18 的倍数")
  }
  let pts : Array[SeekPoint] = []
  let mut off = block.offset
  let end = block.offset + block.length
  while off < end {
    let mut all_ff = true
    for i in 0..<8 {
      if data.unsafe_get(off + i).to_int() != 0xFF {
        all_ff = false
      }
    }
    if !all_ff {
      // 样本号 < 2^63、字节偏移 < 2^63（否则视为非法）
      let b0 = data.unsafe_get(off).to_int()
      let b8 = data.unsafe_get(off + 8).to_int()
      if b0 >= 0x80 || b8 >= 0x80 {
        raise BadMetadata(reason="SEEKTABLE 64 位字段超出范围")
      }
      let mut sample = Int64::from_int(b0)
      let mut byte_off = Int64::from_int(b8)
      for i in 1..<8 {
        sample = (sample << 8) |
          Int64::from_int(data.unsafe_get(off + i).to_int())
        byte_off = (byte_off << 8) |
          Int64::from_int(data.unsafe_get(off + 8 + i).to_int())
      }
      let frame_samples = (data.unsafe_get(off + 16).to_int() << 8) |
        data.unsafe_get(off + 17).to_int()
      pts.push({
        sample_position: sample,
        byte_offset: byte_off,
        frame_samples,
      })
    }
    off += 18
  }
  pts
}

///|
/// VORBIS_COMMENT：小端长度前缀的 UTF-8 文本，注释项为 `KEY=VALUE`。
pub struct VorbisComment {
  /// 写入该注释的编码器标识。
  vendor : String
  /// 全部注释项（保留原始大小写；键在使用时应大小写不敏感比较）。
  comments : Array[(String, String)]
}

///|
/// 读 VORBIS_COMMENT 块。
pub fn read_vorbis_comment(
  data : Bytes,
  block : MetadataBlock,
) -> VorbisComment raise FlacError {
  require_range(data, block.offset, block.length)
  let end = block.offset + block.length
  let mut off = block.offset
  let vendor_len = le32_len(data, off)
  off += 4
  require_range(data, off, vendor_len)
  let vendor = @utf8.decode_lossy(slice_bytes(data, off, vendor_len))
  off += vendor_len
  let count = le32_len(data, off)
  off += 4
  let comments : Array[(String, String)] = []
  let mut i = 0
  while i < count {
    if off > end {
      raise Truncated(offset=off, need=4, actual=end)
    }
    let len = le32_len(data, off)
    off += 4
    if len > end - off {
      raise Truncated(offset=off, need=len, actual=end - off)
    }
    // 在字节层找第一个 '='，避免对解码后的字符串做搜索
    let mut eq = -1
    for k in 0..<len {
      if data.unsafe_get(off + k).to_int() == 0x3D {
        eq = k
      }
      if eq >= 0 {
        break
      }
    }
    if eq < 0 {
      raise BadMetadata(reason="VORBIS_COMMENT 项缺少 = 分隔符")
    }
    let key = @utf8.decode_lossy(slice_bytes(data, off, eq))
    let value = @utf8.decode_lossy(
      slice_bytes(data, off + eq + 1, len - eq - 1),
    )
    comments.push((key, value))
    off += len
    i += 1
  }
  { vendor, comments, }
}

///|
/// PICTURE 块（内嵌图片）。
pub struct Picture {
  /// 图片类型（3 = 封面正/背，规范见 Vorbis PICTURE 规范）。
  picture_type : Int
  /// MIME 类型。
  mime : String
  /// 描述文本。
  description : String
  /// 像素宽（0 = 未知）。
  width : Int
  /// 像素高（0 = 未知）。
  height : Int
  /// 每像素位深（0 = 未知）。
  depth : Int
  /// 调色板颜色数（0 = 非调色板）。
  colors : Int
  /// 图片数据。
  data : Bytes
}

///|
/// 读 PICTURE 块。
pub fn read_picture(
  data : Bytes,
  block : MetadataBlock,
) -> Picture raise FlacError {
  require_range(data, block.offset, block.length)
  let end = block.offset + block.length
  let mut off = block.offset
  let picture_type = be32_len(data, off)
  off += 4
  let mime_len = be32_len(data, off)
  off += 4
  if mime_len > end - off {
    raise Truncated(offset=off, need=mime_len, actual=end - off)
  }
  let mime = @utf8.decode_lossy(slice_bytes(data, off, mime_len))
  off += mime_len
  let desc_len = be32_len(data, off)
  off += 4
  if desc_len > end - off {
    raise Truncated(offset=off, need=desc_len, actual=end - off)
  }
  let description = @utf8.decode_lossy(slice_bytes(data, off, desc_len))
  off += desc_len
  let width = be32_len(data, off)
  off += 4
  let height = be32_len(data, off)
  off += 4
  let depth = be32_len(data, off)
  off += 4
  let colors = be32_len(data, off)
  off += 4
  let data_len = be32_len(data, off)
  off += 4
  if data_len > end - off {
    raise Truncated(offset=off, need=data_len, actual=end - off)
  }
  let picture = slice_bytes(data, off, data_len)
  {
    picture_type,
    mime,
    description,
    width,
    height,
    depth,
    colors,
    data: picture,
  }
}

///|
/// APPLICATION 块：4 字节应用标识 + 剩余数据。
pub struct ApplicationBlock {
  /// 4 字节 ASCII 应用标识。
  app_id : String
  /// 标识之后的应用数据。
  data : Bytes
}

///|
/// 读 APPLICATION 块。
pub fn read_application(
  data : Bytes,
  block : MetadataBlock,
) -> ApplicationBlock raise FlacError {
  require_range(data, block.offset, block.length)
  if block.length < 4 {
    raise BadMetadata(reason="APPLICATION 块短于 4 字节标识")
  }
  let app_id = @utf8.decode_lossy(slice_bytes(data, block.offset, 4))
  let rest = slice_bytes(data, block.offset + 4, block.length - 4)
  { app_id, data: rest, }
}

///|
/// CUESHEET 轨道索引点（RFC 9639 §8.7.1.1）。
pub struct CueSheetIndex {
  /// 相对轨道起点的样本偏移。
  offset : Int64
  /// 索引点编号（0 = 轨道前置空白，之后必须严格递增）。
  index_number : Int
}

///|
/// CUESHEET 轨道（RFC 9639 §8.7.1）。
pub struct CueSheetTrack {
  /// 轨道首个索引点相对音频流起点的样本偏移。
  offset : Int64
  /// 轨道号（CD-DA：1-99，170 = lead-out；非 CD-DA：255 = lead-out）。
  track_number : Int
  /// 12 字节 ISRC（全零表示无）。
  isrc : String
  /// 是否非音频轨道（CD-DA Q 通道控制位 3）。
  is_non_audio : Bool
  /// 是否有预加重（CD-DA Q 通道控制位 5）。
  pre_emphasis : Bool
  /// 索引点（lead-out 轨道必须为空）。
  indexes : Array[CueSheetIndex]
}

///|
/// CUESHEET 块（RFC 9639 §8.7）：CD-DA 轨道结构，或通用的"流内关注点"
/// 定位机制。
pub struct CueSheet {
  /// 128 字节媒体目录号（ASCII，不足右补 0x00；CD-DA 为 13 位数字）。
  media_catalog_number : String
  /// 前导区样本数（仅 CD-DA 有意义，其余应为 0）。
  lead_in_samples : Int64
  /// 是否对应 CD-DA。
  is_cd : Bool
  /// 轨道（最后一轨必须是 lead-out）。
  tracks : Array[CueSheetTrack]
}

///|
/// 校验保留位区必须全零（RFC 9639 对所有保留位的强制要求），
/// 非零时抛 BadMetadata。
fn require_zero_reserved(
  data : Bytes,
  offset : Int,
  length : Int,
  what : String,
) -> Unit raise FlacError {
  require_range(data, offset, length)
  for i in 0..<length {
    if data.unsafe_get(offset + i).to_int() != 0 {
      raise BadMetadata(reason=what)
    }
  }
}

///|
/// 读 u64 大端（CUESHEET 的偏移/前导区字段），要求 < 2^63 防 Int64 溢出
/// 出现负值。
fn read_be64(data : Bytes, offset : Int) -> Int64 raise FlacError {
  require_range(data, offset, 8)
  if data.unsafe_get(offset).to_int() >= 0x80 {
    raise BadMetadata(reason="CUESHEET 64 位字段超出范围")
  }
  let mut v = Int64::from_int(data.unsafe_get(offset).to_int())
  for i in 1..<8 {
    v = (v << 8) | Int64::from_int(data.unsafe_get(offset + i).to_int())
  }
  v
}

///|
/// ASCII 字段去掉尾部 0x00（媒体目录号/ISRC 的定长存储约定）。
fn trim_ascii_nulls(bytes : Bytes) -> String {
  let mut end = bytes.length()
  while end > 0 && bytes.unsafe_get(end - 1).to_int() == 0 {
    end -= 1
  }
  @utf8.decode_lossy(slice_bytes_range(bytes, 0, end))
}

///|
/// slice_bytes 的非 raise 包装（输入已在 require_range 中验证过边界）。
fn slice_bytes_range(bytes : Bytes, offset : Int, length : Int) -> Bytes {
  let buf = @buffer.Buffer()
  for i in 0..<length {
    buf.write_byte(bytes.unsafe_get(offset + i))
  }
  buf.to_bytes()
}

///|
/// 读 CUESHEET 块。保留位区（轨道头/索引点）按规范强制校验为全零。
pub fn read_cuesheet(
  data : Bytes,
  block : MetadataBlock,
) -> CueSheet raise FlacError {
  require_range(data, block.offset, block.length)
  let end = block.offset + block.length
  let mut off = block.offset
  // 媒体目录号：128 字节定长
  if end - off < 128 {
    raise Truncated(offset=off, need=128, actual=end - off)
  }
  let media_catalog_number = trim_ascii_nulls(slice_bytes(data, off, 128))
  off += 128
  let lead_in_samples = read_be64(data, off)
  off += 8
  // is_cd: 1 位 + 7 位保留（凑满 1 字节）+ 258 字节保留
  let is_cd_byte = data.unsafe_get(off).to_int()
  let is_cd = (is_cd_byte & 0x80) != 0
  if (is_cd_byte & 0x7F) != 0 {
    raise BadMetadata(reason="CUESHEET is_cd 后 7 位保留位非零")
  }
  off += 1
  require_zero_reserved(data, off, 258, "CUESHEET 258 字节保留区非零")
  off += 258
  if end - off < 1 {
    raise Truncated(offset=off, need=1, actual=end - off)
  }
  let track_count = data.unsafe_get(off).to_int()
  off += 1
  if track_count < 1 {
    raise BadMetadata(
      reason="CUESHEET 轨道数少于 1（必须有 lead-out）",
    )
  }
  let tracks : Array[CueSheetTrack] = []
  let mut t = 0
  while t < track_count {
    let track_offset = read_be64(data, off)
    off += 8
    if end - off < 1 + 12 + 1 + 13 + 1 {
      raise Truncated(offset=off, need=28, actual=end - off)
    }
    let track_number = data.unsafe_get(off).to_int()
    off += 1
    let isrc = trim_ascii_nulls(slice_bytes(data, off, 12))
    off += 12
    let flags = data.unsafe_get(off).to_int()
    let is_non_audio = (flags & 0x80) != 0
    let pre_emphasis = (flags & 0x40) != 0
    if (flags & 0x3F) != 0 {
      raise BadMetadata(reason="CUESHEET 轨道标志后 6 位保留位非零")
    }
    off += 1
    require_zero_reserved(
      data, off, 13, "CUESHEET 轨道 13 字节保留区非零",
    )
    off += 13
    let index_count = data.unsafe_get(off).to_int()
    off += 1
    let indexes : Array[CueSheetIndex] = []
    let mut k = 0
    while k < index_count {
      if end - off < 12 {
        raise Truncated(offset=off, need=12, actual=end - off)
      }
      let index_offset = read_be64(data, off)
      off += 8
      let index_number = data.unsafe_get(off).to_int()
      off += 1
      require_zero_reserved(
        data, off, 3, "CUESHEET 索引点 3 字节保留区非零",
      )
      off += 3
      indexes.push({ offset: index_offset, index_number, })
      k += 1
    }
    tracks.push({
      offset: track_offset,
      track_number,
      isrc,
      is_non_audio,
      pre_emphasis,
      indexes,
    })
    t += 1
  }
  { media_catalog_number, lead_in_samples, is_cd, tracks, }
}
