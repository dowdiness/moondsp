// 移植自 moonflac(https://github.com/Xcsa-ee/moonflac)
// 版权:Apache-2.0 (c) Xcsa-ee;来源 commit 151a1aca96925242f0d5f1ea19a79a30ce7b7068(2026-10-31)
// 移植说明:解码逻辑原样保留,仅适配包路径与依赖(见 docs/audio-codec.md)。

//
// 顶层解码编排：元数据 → 帧定位（同步扫描 + 帧头校验）→ 子帧解码 →
// 声道去相关 → 输出。声道去相关公式（left/right/side、mid/side 的
// `mid' = (mid<<1)|(side&1)` 还原）经 ffmpeg 手造帧与真实文件双向验证；
// side 声道位宽恒为 bps+1（bps=32 时 33 位，故子帧域用 Int64）。
// 帧迭代逻辑集中在 `decode_next_block`，整文件 `decode` 与流式
// `FlacStream` 共用同一条路径。

///|
/// 整文件解码结果（planar：每声道一个样本数组，样本为 bps 位宽的有符号值）。
pub struct FlacFile {
  /// 流的 STREAMINFO 等元数据。
  info : StreamInfo
  /// 每声道样本（声道数 = `info.channels`）。
  channels : Array[Array[Int]]
}

///|
/// 一个完整块的解码产物（已按声道分配去相关，长度 = 帧的 block_size）。
priv struct Block {
  block_size : Int
  channels : Int
  samples : Array[Array[Int]]
}

///|
/// 尝试在读取器当前位置解析帧头：任何帧头级失败（同步码、保留位、
/// 变长帧号、CRC-8、截断）都折叠为 None，交给上层决定是否继续扫描；
/// 帧头之后的子帧/CRC-16 错误则直接上抛，不静默跳过。
fn try_parse_header(br : BitReader, info : StreamInfo) -> FrameHeader? {
  Some(parse_frame_header(br, info)) catch {
    _ => None
  }
}

///|
/// 解码帧体：各声道子帧 + 零填充到字节边界 + CRC-16 校验。
/// 成功后读取器停在下一帧起点（字节边界）。
fn decode_frame_body(
  br : BitReader,
  h : FrameHeader,
  temp : Array[Array[Int64]],
) -> Unit raise FlacError {
  let side_idx = if h.channel_assignment == 8 || h.channel_assignment == 10 {
    1
  } else if h.channel_assignment == 9 {
    0
  } else {
    -1
  }
  for c in 0..<h.channels {
    let cbps = if c == side_idx {
      h.bits_per_sample + 1
    } else {
      h.bits_per_sample
    }
    decode_subframe(br, temp[c], h.block_size, cbps)
  }
  // 子帧区零填充到字节边界（帧 CRC-16 之前）
  if !br.is_aligned() {
    let pad = 8 - (br.pos & 7)
    for _ in 0..<pad {
      if br.read_bit() != 0 {
        raise BadSubframe(reason="帧尾填充位非零")
      }
    }
  }
  br.check()
  let crc_pos = br.pos >> 3
  let expect = br.read_bits64(16).to_int()
  br.check()
  let actual = crc16_range(br.data, h.start_byte, crc_pos)
  if expect != actual {
    raise BadCrc(kind="CRC-16", expected=actual, actual=expect)
  }
}

///|
/// 把子帧域（Int64）的声道矩阵按声道分配去相关成最终 Int 样本。
fn decorrelate(
  h : FrameHeader,
  temp : Array[Array[Int64]],
) -> Array[Array[Int]] {
  let out : Array[Array[Int]] = []
  for _ in 0..<h.channels {
    out.push([])
  }
  let assign = h.channel_assignment
  if assign <= 7 {
    for c in 0..<h.channels {
      let t = temp[c]
      for i in 0..<h.block_size {
        out[c].push(t[i].to_int())
      }
    }
  } else if assign == 8 {
    // left / side
    for i in 0..<h.block_size {
      let l = temp[0][i]
      out[0].push(l.to_int())
      out[1].push((l - temp[1][i]).to_int())
    }
  } else if assign == 9 {
    // side / right
    for i in 0..<h.block_size {
      let r = temp[1][i]
      out[0].push((temp[0][i] + r).to_int())
      out[1].push(r.to_int())
    }
  } else {
    // mid / side：mid 丢过 LSB，用 side 的最低位补回
    for i in 0..<h.block_size {
      let side = temp[1][i]
      let mid2 = (temp[0][i] << 1) | (side & 1L)
      out[0].push(((mid2 + side) >> 1).to_int())
      out[1].push(((mid2 - side) >> 1).to_int())
    }
  }
  out
}

///|
/// 定位并解码下一个完整块。
/// 帧头级失败向后扫描同步码重同步（容忍尾部杂字节）；扫描到尽头返回 None。
/// 子帧或 CRC-16 失败直接上抛，不跳帧。
fn decode_next_block(
  br : BitReader,
  info : StreamInfo,
) -> Block? raise FlacError {
  let mut header : FrameHeader? = None
  let mut scan_done = false
  while header is None && !scan_done {
    let cur = br.pos >> 3
    br.truncated = false
    header = try_parse_header(br, info)
    if header is None {
      let next = scan_sync(br.data, cur + 1)
      if next < 0 {
        scan_done = true
      } else {
        br.seek(next * 8)
      }
    }
  }
  match header {
    None => None
    Some(h) => {
      let temp : Array[Array[Int64]] = []
      for _ in 0..<h.channels {
        temp.push(Array::make(h.block_size, 0L))
      }
      decode_frame_body(br, h, temp)
      Some({
        block_size: h.block_size,
        channels: h.channels,
        samples: decorrelate(h, temp),
      })
    }
  }
}

///|
/// 十六进制编码（MD5 错误消息用）。
fn hex_string(bytes : Bytes) -> String {
  let hexs : Array[String] = [
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f",
  ]
  let mut out = ""
  for i in 0..<bytes.length() {
    let v = bytes.unsafe_get(i).to_int()
    out = out + hexs[v >> 4] + hexs[v & 0xF]
  }
  out
}

///|
/// 若 STREAMINFO 写了 MD5（非全零）则校验：交织小端、每样本符号扩展到
/// ceil(bps/8) 字节后紧凑打包（RFC 9639 §8.4，含 4/12/20 位等非 8 倍数
/// 位深；8/16/24/32 位的打包方式此前已与 ffmpeg 写入值交叉验证）。
fn verify_md5(
  info : StreamInfo,
  channels : Array[Array[Int]],
) -> Unit raise FlacError {
  let mut has_md5 = false
  for i in 0..<info.md5.length() {
    if info.md5.unsafe_get(i).to_int() != 0 {
      has_md5 = true
    }
  }
  if !has_md5 {
    return
  }
  let bps = info.bits_per_sample
  if bps > 32 {
    return
  }
  // RFC 9639 §8.4：位深非整数字节时，每个样本符号扩展到下一个完整
  // 字节数（ceil(bps/8)），小端存储、跨声道交织。Int 的补码表示
  // 已天然完成符号扩展，取低 nbytes 字节即可——8/16/24/32 位时
  // ceil(bps/8)==bps/8，与既有验证过的行为完全一致。
  let nbytes = (bps + 7) / 8
  let nch = channels.length()
  if nch == 0 {
    return
  }
  let frames = channels[0].length()
  let ctx = @crypto.MD5::new()
  let buf = @buffer.Buffer()
  for f in 0..<frames {
    for c in 0..<nch {
      let v = channels[c][f]
      for i in 0..<nbytes {
        buf.write_byte(((v >> (8 * i)) & 0xFF).to_byte())
      }
    }
    if buf.length() >= 65536 {
      ctx.update(buf.to_bytes())
      buf.reset()
    }
  }
  if buf.length() > 0 {
    ctx.update(buf.to_bytes())
  }
  let fa = ctx.finalize()
  let dbuf = @buffer.Buffer()
  for i in 0..<fa.length() {
    dbuf.write_byte(fa[i])
  }
  let digest = dbuf.to_bytes()
  if !digest.equal(info.md5) {
    raise Md5Mismatch(expected=hex_string(info.md5), actual=hex_string(digest))
  }
}

///|
/// 解码整条 FLAC 流。
///
/// - 帧头级失败会向后扫描同步码尝试重同步（容忍尾部附带的标签等杂字节）；
/// - 子帧或 CRC-16 失败直接报错，不跳帧，保证错误可见；
/// - `STREAMINFO.total_samples` 非 0 时以此为准截断输出，且帧数不足会报
///   Truncated 而不是静默少样本；
/// - STREAMINFO 记录了 MD5 时校验解码 PCM 的 MD5（4–32 位全支持）。
pub fn decode(data : Bytes) -> FlacFile raise FlacError {
  let meta = parse_metadata(data)
  let info = meta.stream_info
  let br = BitReader::new(data)
  br.seek(meta.frame_offset * 8)
  let out : Array[Array[Int]] = []
  for _ in 0..<info.channels {
    out.push([])
  }
  let total = info.total_samples
  let mut decoded : Int64 = 0
  let mut eof = false
  while !eof {
    if total > 0 && decoded >= total {
      break
    }
    match decode_next_block(br, info) {
      None => eof = true
      Some(b) => {
        // total_samples 已知时截断到总长
        let take64 = if total > 0 &&
          decoded + Int64::from_int(b.block_size) > total {
          total - decoded
        } else {
          Int64::from_int(b.block_size)
        }
        let take = take64.to_int()
        for c in 0..<b.channels {
          let src = b.samples[c]
          for i in 0..<take {
            out[c].push(src[i])
          }
        }
        decoded += take64
      }
    }
  }
  if total > 0 && decoded < total {
    raise Truncated(
      offset=data.length(),
      need=(total - decoded).to_int(),
      actual=decoded.to_int(),
    )
  }
  verify_md5(info, out)
  { info, channels: out, }
}
