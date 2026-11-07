// 移植自 moonflac(https://github.com/Xcsa-ee/moonflac)
// 版权:Apache-2.0 (c) Xcsa-ee;来源 commit 151a1aca96925242f0d5f1ea19a79a30ce7b7068(2026-10-31)
// 移植说明:解码逻辑原样保留,仅适配包路径与依赖(见 docs/audio-codec.md)。

//
// 子帧解析：子帧头（1 位零填充 + 6 位类型 + wasted bits 标志）与四类子帧
// （CONSTANT / VERBATIM / FIXED / LPC）。类型位图、wasted bits 的
// 「(k-1) 个 0 + 终止 1」计数约定均经 ffmpeg 双向验证。
// wasted 语义：按 eff = bps - k 位宽解码/重建，最后整体左移 k 还原。

///|
/// 解码一个子帧，把 `block_size` 个样本写入 `xs`（Int64 中间域：
/// side 声道在 bps=32 时宽 33 位，且残差重建可能瞬时超宽）。
fn decode_subframe(
  br : BitReader,
  xs : Array[Int64],
  block_size : Int,
  bps : Int,
) -> Unit raise FlacError {
  if br.read_bit() != 0 {
    raise BadSubframe(reason="子帧首保留位非零")
  }
  let subframe_type = br.read_bits64(6).to_int()
  br.check()
  // wasted bits：unary 计 (k-1) 个 0，终止 1；k = 零个数 + 1
  let mut k = 0
  if br.read_bit() != 0 {
    while br.read_bit() == 0 {
      k += 1
      if br.truncated {
        break
      }
    }
    k += 1
  }
  if k > bps {
    raise BadSubframe(reason="wasted 位数超过子帧位宽")
  }
  let eff = bps - k
  if subframe_type == 0 {
    // CONSTANT：一个样本值填满整帧
    let v = br.read_sample64(eff)
    for i in 0..<block_size {
      xs[i] = v
    }
  } else if subframe_type == 1 {
    // VERBATIM：逐样本原样存储
    for i in 0..<block_size {
      xs[i] = br.read_sample64(eff)
    }
  } else if subframe_type >= 8 && subframe_type <= 12 {
    // FIXED，阶 = 类型码 - 8
    let order = subframe_type - 8
    if order > block_size {
      raise BadSubframe(reason="FIXED 阶超过块长")
    }
    for i in 0..<order {
      xs[i] = br.read_sample64(eff)
    }
    decode_residuals(br, xs, block_size, order)
    reconstruct_fixed(xs, block_size, order)
  } else if subframe_type >= 32 {
    // LPC，阶 = 类型码低 5 位 + 1（1..32）
    let order = (subframe_type & 31) + 1
    if order > block_size {
      raise BadSubframe(reason="LPC 阶超过块长")
    }
    for i in 0..<order {
      xs[i] = br.read_sample64(eff)
    }
    let precision_field = br.read_bits64(4).to_int()
    if precision_field == 15 {
      // RFC 9639 Table 22：系数精度字段 = (精度位数 - 1)，"0b1111 is forbidden"。
      // 即字段 15 对应 16-bit 精度，规范不允许出现；读到它说明码流非法。
      // 合法范围是字段 0..14 = 精度 1..15 bit，全部支持。
      raise BadSubframe(
        reason="LPC 系数精度字段 0b1111（RFC 9639 禁止值）",
      )
    }
    let precision = precision_field + 1
    // RFC 9639 Table 22：Prediction right shift 是 s(5)，范围 -16..15。
    // 字段值为二补码：>= 16 表示负数（即预测左移）。
    let shift_field = br.read_bits64(5).to_int()
    let shift = if shift_field >= 16 { shift_field - 32 } else { shift_field }
    let coeffs = []
    for _ in 0..<order {
      coeffs.push(br.read_sample64(precision))
    }
    decode_residuals(br, xs, block_size, order)
    reconstruct_lpc(xs, block_size, order, coeffs, shift)
  } else {
    raise BadSubframe(reason="子帧类型为保留值")
  }
  br.check()
  if k > 0 {
    for i in 0..<block_size {
      xs[i] = xs[i] << k
    }
  }
}
