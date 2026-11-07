// 移植自 moonflac(https://github.com/Xcsa-ee/moonflac)
// 版权:Apache-2.0 (c) Xcsa-ee;来源 commit 151a1aca96925242f0d5f1ea19a79a30ce7b7068(2026-10-31)
// 移植说明:解码逻辑原样保留,仅适配包路径与依赖(见 docs/audio-codec.md)。

//
// 流式解码（M6 增量）：不一次性物化整条流，逐块取样；`seek` 支持
// 按 SEEKTABLE 跳帧，没有 SEEKTABLE 时从流起点线性推进（正确优先，
// 以编号做头扫描的快速路径留作后续增量）。

///|
/// 按块流式读取的 FLAC 解码器。
pub struct FlacStream {
  /// 流的 STREAMINFO。
  info : StreamInfo
  br : BitReader
  blocks : Array[MetadataBlock]
  frame_offset : Int
  /// 已消费（并已交给调用方）的样本位置。
  mut decoded : Int64
  /// seek 后待返回的目标块尾部（planar）；空数组表示无。
  mut pending : Array[Array[Int]]
  mut eof : Bool
}

///|
/// 解析元数据并就绪于第一个音频帧。
pub fn FlacStream::new(data : Bytes) -> FlacStream raise FlacError {
  let meta = parse_metadata(data)
  let br = BitReader::new(data)
  br.seek(meta.frame_offset * 8)
  {
    info: meta.stream_info,
    br,
    blocks: meta.blocks,
    frame_offset: meta.frame_offset,
    decoded: 0,
    pending: [],
    eof: false,
  }
}

///|
/// 回到流起点。
fn FlacStream::rewind(self : FlacStream) -> Unit {
  self.br.truncated = false
  self.br.seek(self.frame_offset * 8)
  self.decoded = 0
  self.pending = []
}

///|
/// 取下一块样本（planar，`[声道][样本]`）。返回 `None` 表示流已结束。
/// `total_samples` 已知且不足时抛 Truncated，与 `decode` 口径一致。
pub fn FlacStream::next(
  self : FlacStream,
) -> Array[Array[Int]]? raise FlacError {
  if self.pending.length() > 0 {
    let p = self.pending
    self.pending = []
    return Some(p)
  }
  if self.eof {
    return None
  }
  let total = self.info.total_samples
  if total > 0 && self.decoded >= total {
    self.eof = true
    return None
  }
  match decode_next_block(self.br, self.info) {
    None => {
      self.eof = true
      if total > 0 && self.decoded < total {
        raise Truncated(
          offset=self.br.data.length(),
          need=(total - self.decoded).to_int(),
          actual=self.decoded.to_int(),
        )
      }
      None
    }
    Some(b) => {
      let take64 = if total > 0 &&
        self.decoded + Int64::from_int(b.block_size) > total {
        total - self.decoded
      } else {
        Int64::from_int(b.block_size)
      }
      let take = take64.to_int()
      let out : Array[Array[Int]] = []
      for c in 0..<b.channels {
        let arr : Array[Int] = []
        for i in 0..<take {
          arr.push(b.samples[c][i])
        }
        out.push(arr)
      }
      self.decoded += take64
      Some(out)
    }
  }
}

///|
/// 跳到第 `sample` 个样本处；之后 `next` 返回的样本从这里开始。
/// 已到流尾（`total_samples` 已知且 `sample` 不小于它）时之后 `next` 返回 None。
pub fn FlacStream::seek(
  self : FlacStream,
  sample : Int64,
) -> Unit raise FlacError {
  self.pending = []
  self.eof = false
  let total = self.info.total_samples
  if sample <= 0 {
    self.rewind()
    return
  }
  if total > 0 && sample >= total {
    // 跳到流尾：样本位置推进到总长，下一次 next 返回 None
    self.rewind()
    self.decoded = total
    return
  }
  // —— SEEKTABLE：取样本号不大于 sample 的最后一个点 ——
  let mut best_byte : Int64 = -1
  let mut best_sample : Int64 = -1
  for blk in self.blocks {
    if blk.block_type == 3 {
      let pts = read_seektable(self.br.data, blk)
      for p in pts {
        if p.sample_position <= sample && p.sample_position > best_sample {
          best_sample = p.sample_position
          best_byte = p.byte_offset
        }
      }
    }
  }
  if best_byte >= 0 {
    let start_bit = (best_byte * 8).to_int()
    self.br.truncated = false
    self.br.seek(start_bit)
    // 试探：该偏移必须能解析出帧头，否则视为点表不可信，回退线性
    let probe : FrameHeader? = {
      let saved = self.br.pos
      let h = try_parse_header(self.br, self.info)
      self.br.truncated = false
      self.br.seek(saved)
      h
    }
    if probe is Some(_) {
      self.decoded = best_sample
    } else {
      self.rewind()
    }
  } else {
    self.rewind()
  }
  // —— 线性推进到包含 sample 的块，裁出尾部作 pending ——
  while !self.eof {
    let cur = self.decoded
    match decode_next_block(self.br, self.info) {
      None => self.eof = true
      Some(b) => {
        let take64 = if total > 0 && cur + Int64::from_int(b.block_size) > total {
          total - cur
        } else {
          Int64::from_int(b.block_size)
        }
        self.decoded = cur + take64
        if sample < cur + Int64::from_int(b.block_size) {
          // 目标落在本块内
          let off = (sample - cur).to_int()
          let take = take64.to_int()
          let pend : Array[Array[Int]] = []
          for c in 0..<b.channels {
            let arr : Array[Int] = []
            let mut i = off
            while i < take {
              arr.push(b.samples[c][i])
              i += 1
            }
            pend.push(arr)
          }
          self.pending = pend
          return
        }
      }
    }
  }
}
