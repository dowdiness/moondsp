// 移植自 moonflac(https://github.com/Xcsa-ee/moonflac)
// 版权:Apache-2.0 (c) Xcsa-ee;来源 commit 151a1aca96925242f0d5f1ea19a79a30ce7b7068(2026-10-31)
// 移植说明:解码逻辑原样保留,仅适配包路径与依赖(见 docs/audio-codec.md)。

//
// 真正的增量流式解码：调用方按任意块大小持续喂入字节，本模块内部
// 维护一个未消费字节缓冲区，元数据凑齐即解析、每凑齐一帧即解码吐出，
// 不要求一次性拿到完整文件。与 `FlacStream`（一次性拿到完整 Bytes，
// 按帧惰性解码）不同，这里解决的是"边收边解"。
//
// 契约：FLAC 顶层结构（元数据块、帧）全部字节对齐、顺序排列，
// 因此 `next_frame_byte` 位置是确定的，不需要 `decode`/`FlacStream`
// 那套"扫描同步码重同步"的容错——增量场景下"当前缓冲区里扫不到
// 同步码"不代表"整条流没有同步码"，只代表"还没传完"。这里把
// "数据不足"（可继续 feed）与"真正的格式错误"严格区分：数据不足
// 时 `next` 返回 None 等待更多输入；`finish()` 声明输入结束后，
// `total_samples` 已知且未解满才升级为 Truncated 错误。

///|
/// 增量 FLAC 解码器。
pub struct FlacFeeder {
  /// 未消费字节（`buf[0]` 对应整个流的绝对偏移 `base_offset`）。
  mut buf : Array[Byte]
  /// `buf[0]` 在整条流中的绝对字节偏移。
  mut base_offset : Int
  /// 已解析的 STREAMINFO（元数据凑齐前为 None）。
  mut info : StreamInfo?
  /// 元数据块（不含 STREAMINFO）。
  mut blocks : Array[MetadataBlock]
  /// 下一帧的绝对起始字节偏移（元数据凑齐后有效）。
  mut next_frame_byte : Int
  /// 元数据是否已完整解析。
  mut meta_done : Bool
  /// `finish()` 是否已被调用（不会再有新输入）。
  mut finished : Bool
  /// 已交付给调用方的样本数。
  mut decoded : Int64
  /// 流是否已确定结束。
  mut eof : Bool
}

///|
/// 创建空的增量解码器，等待第一次 `feed`。
pub fn FlacFeeder::new() -> FlacFeeder {
  {
    buf: [],
    base_offset: 0,
    info: None,
    blocks: [],
    next_frame_byte: 0,
    meta_done: false,
    finished: false,
    decoded: 0,
    eof: false,
  }
}

///|
/// 追加一段输入字节。可在任意时刻调用任意次，块大小不限。
pub fn FlacFeeder::feed(self : FlacFeeder, chunk : Bytes) -> Unit {
  for i in 0..<chunk.length() {
    self.buf.push(chunk.unsafe_get(i))
  }
}

///|
/// 当前缓冲区内容转成 `Bytes` 快照（喂给需要连续 `Bytes` 的解析器）。
fn FlacFeeder::snapshot(self : FlacFeeder) -> Bytes {
  let w = @buffer.Buffer()
  for i in 0..<self.buf.length() {
    w.write_byte(self.buf[i])
  }
  w.to_bytes()
}

///|
/// 丢弃 `buf` 前缀（已消费的部分），保持缓冲区只装"未解码的尾部"，
/// 防止长流增量解码时内存无界增长。
fn FlacFeeder::compact(self : FlacFeeder) -> Unit {
  let drop = self.next_frame_byte - self.base_offset
  if drop <= 0 {
    return
  }
  let keep : Array[Byte] = []
  for i in drop..<self.buf.length() {
    keep.push(self.buf[i])
  }
  self.buf = keep
  self.base_offset = self.next_frame_byte
}

///|
/// 是否已确定不会再有更多块。
pub fn FlacFeeder::is_done(self : FlacFeeder) -> Bool {
  self.eof
}

///|
/// 尝试解析元数据：数据不足返回 false（继续等 feed），解析成功返回
/// true，真正的格式错误直接上抛。
fn FlacFeeder::try_metadata(self : FlacFeeder) -> Bool raise FlacError {
  if self.meta_done {
    return true
  }
  let data = self.snapshot()
  match
    (Some(parse_metadata(data)) catch {
      FlacError::Truncated(..) => None
      e => raise e
    }) {
    None => false
    Some(meta) => {
      self.info = Some(meta.stream_info)
      self.blocks = meta.blocks
      self.next_frame_byte = meta.frame_offset
      self.meta_done = true
      true
    }
  }
}

///|
/// 取下一块样本（planar，`[声道][样本]`）。
///
/// - `Some(block)`：解出了一个完整块，继续调用 `next` 取下一块。
/// - `None`：当前无法再产出一个完整块。可能是"还需要更多数据"
///   （`is_done()` 为 false），也可能是"流已结束"（`is_done()` 为 true）。
/// - 抛 `Truncated`：仅在 `finish()` 已调用、`total_samples` 已知
///   且未解满时发生（与整文件 `decode` 对截断文件的处理一致）。
pub fn FlacFeeder::next(
  self : FlacFeeder,
) -> Array[Array[Int]]? raise FlacError {
  if self.eof {
    return None
  }
  if !self.try_metadata() {
    return None
  }
  let info = match self.info {
    Some(i) => i
    None => abort("元数据已解析但 info 缺失")
  }
  let total = info.total_samples
  if total > 0 && self.decoded >= total {
    self.eof = true
    return None
  }
  // —— 解一帧：按 next_frame_byte 精确定位，不做扫描重同步 ——
  let data = self.snapshot()
  let br = BitReader::new(data)
  br.seek((self.next_frame_byte - self.base_offset) * 8)
  let h : FrameHeader = parse_frame_header(br, info) catch {
    FlacError::Truncated(..) => {
      // 帧头数据还没喂够：等更多输入。finish() 之后且 total_samples
      // 已知时，这是真正的截断，升级为错误。
      if self.finished && total > 0 {
        self.raise_truncation(info)
      }
      return None
    }
    e => raise e
  }
  let temp : Array[Array[Int64]] = []
  for _ in 0..<h.channels {
    temp.push(Array::make(h.block_size, 0L))
  }
  decode_frame_body(br, h, temp) catch {
    FlacError::Truncated(..) => {
      // 帧头解析成功但帧体没喂够：等更多输入，规则同上。
      if self.finished && total > 0 {
        self.raise_truncation(info)
      }
      return None
    }
    e => raise e
  }
  self.next_frame_byte = self.base_offset + (br.pos >> 3)
  self.compact()
  let samples = decorrelate(h, temp)
  // total_samples 已知时截断到总长（本帧是最后一帧才会触发）
  let take64 = if total > 0 &&
    self.decoded + Int64::from_int(h.block_size) > total {
    total - self.decoded
  } else {
    Int64::from_int(h.block_size)
  }
  let take = take64.to_int()
  let out : Array[Array[Int]] = []
  for c in 0..<h.channels {
    let arr : Array[Int] = []
    for i in 0..<take {
      arr.push(samples[c][i])
    }
    out.push(arr)
  }
  self.decoded += take64
  Some(out)
}

///|
/// `total_samples` 已知且未解满时报 Truncated，口径与整文件 `decode` 一致。
fn FlacFeeder::raise_truncation(
  self : FlacFeeder,
  info : StreamInfo,
) -> Unit raise FlacError {
  let total = info.total_samples
  raise Truncated(
    offset=self.base_offset + self.buf.length(),
    need=(total - self.decoded).to_int(),
    actual=self.decoded.to_int(),
  )
}

///|
/// 声明不会再有新输入。若 `total_samples` 已知且尝试解完缓冲区内
/// 剩余完整帧后仍未解满，抛 Truncated；`total_samples` 未知时，
/// 缓冲区尾部不足一帧的数据按整文件 `decode` 的口径静默忽略。
pub fn FlacFeeder::finish(self : FlacFeeder) -> Unit raise FlacError {
  self.finished = true
  let info = match self.info {
    Some(i) => i
    None =>
      raise Truncated(
        offset=self.buf.length(),
        need=4,
        actual=self.buf.length(),
      )
  }
  // 先把缓冲区里还剩的完整帧尽量解完
  while !self.eof {
    let before = self.next_frame_byte
    let _ = self.next()
    if self.next_frame_byte == before {
      break
    }
  }
  let total = info.total_samples
  if total > 0 && self.decoded < total {
    self.raise_truncation(info)
  }
  self.eof = true
}
