// 移植自 moonflac(https://github.com/Xcsa-ee/moonflac)
// 版权:Apache-2.0 (c) Xcsa-ee;来源 commit 151a1aca96925242f0d5f1ea19a79a30ce7b7068(2026-10-31)
// 移植说明:解码逻辑原样保留,仅适配包路径与依赖(见 docs/audio-codec.md)。

//
// 子帧残差：分区 Rice 编码。以下全部约定经 ffmpeg 编码器真实输出 + 手造帧
// 双向交叉验证：
// - 熵编码方法 2 位：0 = Rice（参数 4 位），1 = Rice2（参数 5 位）；
// - 分区序 4 位；每个分区先写参数、再写该分区残差（交错布局）；
// - 首分区样本数 = (块长 >> 分区序) - 预测阶，其余 = 块长 >> 分区序；
// - 商的 unary 是「q 个 0 + 终止 1」，余数参数位宽，值按 zigzag 映射；
// - 转义：参数达上限（15/31）时跟 5 位原码位宽，该分区残差按二补码原样存储。

///|
/// zigzag 逆映射：偶数 u -> u/2，奇数 u -> -(u+1)/2。
fn zigzag_decode(u : Int64) -> Int64 {
  if (u & 1L) != 0L {
    0L - ((u >> 1) + 1L)
  } else {
    u >> 1
  }
}

///|
/// 解码 `size` 个 Rice 残差写入 `xs[idx ..]`（商为 unary「q 个 0 + 1」）。
fn decode_rice_partition(
  br : BitReader,
  xs : Array[Int64],
  idx : Int,
  size : Int,
  param : Int,
) -> Unit {
  let mut j = 0
  while j < size {
    let mut q = 0L
    while br.read_bit() == 0 {
      q += 1L
      if br.truncated {
        break
      }
    }
    let mut rem = 0L
    if param > 0 {
      rem = br.read_bits64(param)
    }
    xs[idx + j] = zigzag_decode((q << param) | rem)
    j += 1
  }
}

///|
/// 解码子帧残差区，就地写入 `xs[order .. block_size]`；
/// 调用前 `xs[0 .. order]` 已填好 warmup 样本（均为 eff 位宽）。
fn decode_residuals(
  br : BitReader,
  xs : Array[Int64],
  block_size : Int,
  order : Int,
) -> Unit raise FlacError {
  if order > block_size {
    raise BadResidual(reason="预测阶超过块长")
  }
  let entropy_method = br.read_bits64(2).to_int()
  br.check()
  if entropy_method > 1 {
    raise BadResidual(reason="熵编码方法 2/3 为保留值")
  }
  let porder = br.read_bits64(4).to_int()
  br.check()
  let parts = 1 << porder
  if block_size % parts != 0 {
    raise BadResidual(reason="块长不能被分区数整除")
  }
  let psize = block_size >> porder
  if psize < order {
    raise BadResidual(reason="每分区样本数小于预测阶")
  }
  let param_len = if entropy_method == 0 { 4 } else { 5 }
  let escape = (1 << param_len) - 1
  let mut idx = order
  let mut p = 0
  while p < parts {
    let size = if p == 0 { psize - order } else { psize }
    let param = br.read_bits64(param_len).to_int()
    if param == escape {
      // 转义：再读 5 位原码位宽，残差按二补码原样存储
      let raw_bits = br.read_bits64(5).to_int()
      let mut j = 0
      while j < size {
        xs[idx + j] = br.read_sample64(raw_bits)
        j += 1
      }
    } else {
      decode_rice_partition(br, xs, idx, size, param)
    }
    br.check()
    idx += size
    p += 1
  }
  if idx != block_size {
    raise BadResidual(reason="分区覆盖样本数与块长不符")
  }
}

///|
/// FIXED 预测重建（阶 0..4），在 eff 位宽域内就地进行。
fn reconstruct_fixed(xs : Array[Int64], block_size : Int, order : Int) -> Unit {
  let mut i = order
  while i < block_size {
    let pred = if order == 1 {
      xs[i - 1]
    } else if order == 2 {
      xs[i - 1] * 2L - xs[i - 2]
    } else if order == 3 {
      xs[i - 1] * 3L - xs[i - 2] * 3L + xs[i - 3]
    } else if order == 4 {
      xs[i - 1] * 4L - xs[i - 2] * 6L + xs[i - 3] * 4L - xs[i - 4]
    } else {
      0L
    }
    xs[i] = xs[i] + pred
    i += 1
  }
}

///|
/// LPC 预测重建：`x[i] = r[i] + (Σ coeff[j] * x[i-1-j]) >> shift`。
/// `shift` 已按规范解释为 s(5)：非负为算术右移，负值为左移。
fn reconstruct_lpc(
  xs : Array[Int64],
  block_size : Int,
  order : Int,
  coeffs : Array[Int64],
  shift : Int,
) -> Unit {
  let mut i = order
  while i < block_size {
    let mut acc = 0L
    for j in 0..<order {
      acc += coeffs[j] * xs[i - 1 - j]
    }
    let pred = if shift >= 0 { acc >> shift } else { acc << -shift }
    xs[i] = xs[i] + pred
    i += 1
  }
}
