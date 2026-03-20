///|
test "GraphBuilder: constant produces one node" {
  let c : @mdsp.GraphBuilder = @mdsp.ArithSym::constant(440.0)
  assert_eq(c.nodes().length(), 1)
}

///|
test "GraphBuilder: mul merges two constants" {
  let a : @mdsp.GraphBuilder = @mdsp.ArithSym::constant(3.0)
  let b : @mdsp.GraphBuilder = @mdsp.ArithSym::constant(4.0)
  let product : @mdsp.GraphBuilder = @mdsp.ArithSym::mul(a, b)
  let nodes = product.nodes()
  assert_eq(nodes.length(), 3) // const(3), const(4), mul(0,1)
  assert_true(nodes[0].kind is @mdsp.DspNodeKind::Constant)
  assert_eq(nodes[0].value0, 3.0)
  assert_true(nodes[1].kind is @mdsp.DspNodeKind::Constant)
  assert_eq(nodes[1].value0, 4.0)
  assert_true(nodes[2].kind is @mdsp.DspNodeKind::Mul)
  assert_eq(nodes[2].input0, 0)
  assert_eq(nodes[2].input1, 1)
}

///|
test "GraphBuilder: mix merges two constants" {
  let a : @mdsp.GraphBuilder = @mdsp.ArithSym::constant(3.0)
  let b : @mdsp.GraphBuilder = @mdsp.ArithSym::constant(4.0)
  let result : @mdsp.GraphBuilder = @mdsp.ArithSym::mix(a, b)
  let nodes = result.nodes()
  assert_eq(nodes.length(), 3)
  assert_true(nodes[2].kind is @mdsp.DspNodeKind::Mix)
  assert_eq(nodes[2].input0, 0)
  assert_eq(nodes[2].input1, 1)
}

///|
test "GraphBuilder: unary chain shares array" {
  let c : @mdsp.GraphBuilder = @mdsp.ArithSym::constant(1.0)
  let g : @mdsp.GraphBuilder = @mdsp.DspSym::gain(c, 0.5)
  let o : @mdsp.GraphBuilder = @mdsp.DspSym::output(g)
  assert_eq(o.nodes().length(), 3) // const, gain, output
}

///|
test "GraphBuilder: oscillator with frequency input" {
  let freq : @mdsp.GraphBuilder = @mdsp.ArithSym::constant(440.0)
  let osc : @mdsp.GraphBuilder = @mdsp.DspSym::oscillator(
    freq,
    @mdsp.Waveform::Sine,
  )
  let nodes = osc.nodes()
  assert_eq(nodes.length(), 2) // const, oscillator
  assert_true(nodes[1].kind is @mdsp.DspNodeKind::Oscillator)
  assert_eq(nodes[1].input0, 0)
  assert_true(nodes[1].waveform is @mdsp.Waveform::Sine)
}

///|
test "GraphBuilder: noise source" {
  let n : @mdsp.GraphBuilder = @mdsp.DspSym::noise(42U)
  let nodes = n.nodes()
  assert_eq(nodes.length(), 1)
  assert_true(nodes[0].kind is @mdsp.DspNodeKind::Noise)
  assert_eq(nodes[0].seed, 42U)
}

///|
test "GraphBuilder: adsr source" {
  let e : @mdsp.GraphBuilder = @mdsp.DspSym::adsr(10.0, 50.0, 0.7, 200.0)
  let nodes = e.nodes()
  assert_eq(nodes.length(), 1)
  assert_true(nodes[0].kind is @mdsp.DspNodeKind::Adsr)
  assert_eq(nodes[0].value0, 10.0)
  assert_eq(nodes[0].value1, 50.0)
  assert_eq(nodes[0].value2, 0.7)
  assert_eq(nodes[0].value3, 200.0)
}

///|
test "GraphBuilder: clip" {
  let c : @mdsp.GraphBuilder = @mdsp.ArithSym::constant(1.0)
  let clipped : @mdsp.GraphBuilder = @mdsp.ArithSym::clip(c, 0.5)
  let nodes = clipped.nodes()
  assert_eq(nodes.length(), 2)
  assert_true(nodes[1].kind is @mdsp.DspNodeKind::Clip)
  assert_eq(nodes[1].input0, 0)
  assert_eq(nodes[1].value0, 0.5)
}

///|
test "GraphBuilder: biquad filter" {
  let c : @mdsp.GraphBuilder = @mdsp.ArithSym::constant(1.0)
  let filtered : @mdsp.GraphBuilder = @mdsp.FilterSym::biquad(
    c,
    @mdsp.BiquadMode::LowPass,
    1000.0,
    0.707,
  )
  let nodes = filtered.nodes()
  assert_eq(nodes.length(), 2)
  assert_true(nodes[1].kind is @mdsp.DspNodeKind::Biquad)
  assert_eq(nodes[1].input0, 0)
  assert_eq(nodes[1].value0, 1000.0)
  assert_eq(nodes[1].value1, 0.707)
  assert_true(nodes[1].filter_mode is @mdsp.BiquadMode::LowPass)
}

///|
test "GraphBuilder: delay" {
  let c : @mdsp.GraphBuilder = @mdsp.ArithSym::constant(1.0)
  let delayed : @mdsp.GraphBuilder = @mdsp.DelaySym::delay(c, 48000, 24000, 0.5)
  let nodes = delayed.nodes()
  assert_eq(nodes.length(), 2)
  assert_true(nodes[1].kind is @mdsp.DspNodeKind::Delay)
  assert_eq(nodes[1].input0, 0)
  assert_eq(nodes[1].delay_max_samples, 48000)
  assert_eq(nodes[1].delay_samples, 24000)
  assert_eq(nodes[1].value0, 0.5)
}

///|
test "GraphBuilder: pan" {
  let c : @mdsp.GraphBuilder = @mdsp.ArithSym::constant(1.0)
  let panned : @mdsp.GraphBuilder = @mdsp.StereoSym::pan(c, 0.3)
  let nodes = panned.nodes()
  assert_eq(nodes.length(), 2)
  assert_true(nodes[1].kind is @mdsp.DspNodeKind::Pan)
  assert_eq(nodes[1].input0, 0)
  assert_eq(nodes[1].value0, 0.3)
}

///|
test "GraphBuilder: stereo_gain" {
  let c : @mdsp.GraphBuilder = @mdsp.ArithSym::constant(1.0)
  let p : @mdsp.GraphBuilder = @mdsp.StereoSym::pan(c, 0.0)
  let sg : @mdsp.GraphBuilder = @mdsp.StereoSym::stereo_gain(p, 0.8)
  let nodes = sg.nodes()
  assert_eq(nodes.length(), 3)
  assert_true(nodes[2].kind is @mdsp.DspNodeKind::StereoGain)
  assert_eq(nodes[2].input0, 1)
  assert_eq(nodes[2].value0, 0.8)
}

///|
test "GraphBuilder: stereo_clip" {
  let c : @mdsp.GraphBuilder = @mdsp.ArithSym::constant(1.0)
  let p : @mdsp.GraphBuilder = @mdsp.StereoSym::pan(c, 0.0)
  let sc : @mdsp.GraphBuilder = @mdsp.StereoSym::stereo_clip(p, 0.5)
  let nodes = sc.nodes()
  assert_eq(nodes.length(), 3)
  assert_true(nodes[2].kind is @mdsp.DspNodeKind::StereoClip)
  assert_eq(nodes[2].input0, 1)
  assert_eq(nodes[2].value0, 0.5)
}

///|
test "GraphBuilder: stereo_biquad" {
  let c : @mdsp.GraphBuilder = @mdsp.ArithSym::constant(1.0)
  let p : @mdsp.GraphBuilder = @mdsp.StereoSym::pan(c, 0.0)
  let sb : @mdsp.GraphBuilder = @mdsp.StereoFilterSym::stereo_biquad(
    p,
    @mdsp.BiquadMode::HighPass,
    500.0,
    1.0,
  )
  let nodes = sb.nodes()
  assert_eq(nodes.length(), 3)
  assert_true(nodes[2].kind is @mdsp.DspNodeKind::StereoBiquad)
  assert_eq(nodes[2].input0, 1)
  assert_eq(nodes[2].value0, 500.0)
  assert_eq(nodes[2].value1, 1.0)
  assert_true(nodes[2].filter_mode is @mdsp.BiquadMode::HighPass)
}

///|
test "GraphBuilder: stereo_delay" {
  let c : @mdsp.GraphBuilder = @mdsp.ArithSym::constant(1.0)
  let p : @mdsp.GraphBuilder = @mdsp.StereoSym::pan(c, 0.0)
  let sd : @mdsp.GraphBuilder = @mdsp.StereoDelaySym::stereo_delay(
    p, 48000, 12000, 0.3,
  )
  let nodes = sd.nodes()
  assert_eq(nodes.length(), 3)
  assert_true(nodes[2].kind is @mdsp.DspNodeKind::StereoDelay)
  assert_eq(nodes[2].input0, 1)
  assert_eq(nodes[2].delay_max_samples, 48000)
  assert_eq(nodes[2].delay_samples, 12000)
  assert_eq(nodes[2].value0, 0.3)
}

///|
test "GraphBuilder: stereo_mixdown binary merge" {
  let a : @mdsp.GraphBuilder = @mdsp.ArithSym::constant(1.0)
  let pa : @mdsp.GraphBuilder = @mdsp.StereoSym::pan(a, -1.0)
  let b : @mdsp.GraphBuilder = @mdsp.ArithSym::constant(2.0)
  let pb : @mdsp.GraphBuilder = @mdsp.StereoSym::pan(b, 1.0)
  let mixed : @mdsp.GraphBuilder = @mdsp.StereoSym::stereo_mixdown(pa, pb)
  let nodes = mixed.nodes()
  // a: const(1.0)=0, pan=1 | b: const(2.0)=0, pan=1 -> merged at offset 2
  // result: const(1.0)=0, pan(0)=1, const(2.0)=2, pan(2)=3, stereo_mixdown(1,3)=4
  assert_eq(nodes.length(), 5)
  assert_true(nodes[4].kind is @mdsp.DspNodeKind::StereoMixDown)
  assert_eq(nodes[4].input0, 1)
  assert_eq(nodes[4].input1, 3)
}

///|
test "GraphBuilder: stereo_output binary merge" {
  let a : @mdsp.GraphBuilder = @mdsp.ArithSym::constant(1.0)
  let pa : @mdsp.GraphBuilder = @mdsp.StereoSym::pan(a, -1.0)
  let b : @mdsp.GraphBuilder = @mdsp.ArithSym::constant(2.0)
  let pb : @mdsp.GraphBuilder = @mdsp.StereoSym::pan(b, 1.0)
  let out : @mdsp.GraphBuilder = @mdsp.StereoSym::stereo_output(pa, pb)
  let nodes = out.nodes()
  assert_eq(nodes.length(), 5)
  assert_true(nodes[4].kind is @mdsp.DspNodeKind::StereoOutput)
  assert_eq(nodes[4].input0, 1)
  assert_eq(nodes[4].input1, 3)
}

///|
test "GraphBuilder: remap preserves correct indices during merge" {
  // Build a chain: const -> gain -> clip
  let c : @mdsp.GraphBuilder = @mdsp.ArithSym::constant(1.0)
  let g : @mdsp.GraphBuilder = @mdsp.DspSym::gain(c, 0.5)
  let clipped : @mdsp.GraphBuilder = @mdsp.ArithSym::clip(g, 0.8)
  // Build another chain
  let c2 : @mdsp.GraphBuilder = @mdsp.ArithSym::constant(2.0)
  let g2 : @mdsp.GraphBuilder = @mdsp.DspSym::gain(c2, 0.3)
  // Multiply them: merges c2,g2 into c,g,clip array with offset 3
  let result : @mdsp.GraphBuilder = @mdsp.ArithSym::mul(clipped, g2)
  let nodes = result.nodes()
  // Original: const(1)=0, gain(0)=1, clip(1)=2
  // Merged:   const(2)=3, gain(3)=4
  // Mul(2,4)=5
  assert_eq(nodes.length(), 6)
  assert_true(nodes[3].kind is @mdsp.DspNodeKind::Constant)
  assert_eq(nodes[3].value0, 2.0)
  assert_true(nodes[4].kind is @mdsp.DspNodeKind::Gain)
  assert_eq(nodes[4].input0, 3) // remapped from 0 to 0+3=3
  assert_true(nodes[5].kind is @mdsp.DspNodeKind::Mul)
  assert_eq(nodes[5].input0, 2)
  assert_eq(nodes[5].input1, 4)
}

///|
test "GraphBuilder: same-array binary op does not duplicate" {
  // When both operands share the same array (from same source chain),
  // no duplication should occur
  let c : @mdsp.GraphBuilder = @mdsp.ArithSym::constant(1.0)
  let g : @mdsp.GraphBuilder = @mdsp.DspSym::gain(c, 0.5)
  // g shares the same array as c
  // mul(c, g) should just append without merging
  let result : @mdsp.GraphBuilder = @mdsp.ArithSym::mul(c, g)
  let nodes = result.nodes()
  // const=0, gain(0)=1, mul(0,1)=2
  assert_eq(nodes.length(), 3)
  assert_true(nodes[2].kind is @mdsp.DspNodeKind::Mul)
  assert_eq(nodes[2].input0, 0)
  assert_eq(nodes[2].input1, 1)
}

///|
test "GraphBuilder: full mono pipeline" {
  // const -> osc -> gain -> biquad -> output
  let freq : @mdsp.GraphBuilder = @mdsp.ArithSym::constant(440.0)
  let osc : @mdsp.GraphBuilder = @mdsp.DspSym::oscillator(
    freq,
    @mdsp.Waveform::Saw,
  )
  let gained : @mdsp.GraphBuilder = @mdsp.DspSym::gain(osc, 0.7)
  let filtered : @mdsp.GraphBuilder = @mdsp.FilterSym::biquad(
    gained,
    @mdsp.BiquadMode::LowPass,
    2000.0,
    0.707,
  )
  let out : @mdsp.GraphBuilder = @mdsp.DspSym::output(filtered)
  let nodes = out.nodes()
  assert_eq(nodes.length(), 5) // const, osc, gain, biquad, output
  assert_true(nodes[0].kind is @mdsp.DspNodeKind::Constant)
  assert_true(nodes[1].kind is @mdsp.DspNodeKind::Oscillator)
  assert_true(nodes[2].kind is @mdsp.DspNodeKind::Gain)
  assert_true(nodes[3].kind is @mdsp.DspNodeKind::Biquad)
  assert_true(nodes[4].kind is @mdsp.DspNodeKind::Output)
}

///|
test "GraphBuilder: adsr * osc pipeline" {
  let env : @mdsp.GraphBuilder = @mdsp.DspSym::adsr(10.0, 50.0, 0.7, 200.0)
  let freq : @mdsp.GraphBuilder = @mdsp.ArithSym::constant(440.0)
  let osc : @mdsp.GraphBuilder = @mdsp.DspSym::oscillator(
    freq,
    @mdsp.Waveform::Sine,
  )
  let modulated : @mdsp.GraphBuilder = @mdsp.ArithSym::mul(env, osc)
  let out : @mdsp.GraphBuilder = @mdsp.DspSym::output(modulated)
  let nodes = out.nodes()
  // adsr=0 | const(440)=0, osc(0)=1 -> merged at offset 1
  // result: adsr=0, const(440)=1, osc(1)=2, mul(0,2)=3, output(3)=4
  assert_eq(nodes.length(), 5)
  assert_true(nodes[0].kind is @mdsp.DspNodeKind::Adsr)
  assert_true(nodes[1].kind is @mdsp.DspNodeKind::Constant)
  assert_true(nodes[2].kind is @mdsp.DspNodeKind::Oscillator)
  assert_eq(nodes[2].input0, 1) // remapped: was 0, offset 1, so 1
  assert_true(nodes[3].kind is @mdsp.DspNodeKind::Mul)
  assert_eq(nodes[3].input0, 0)
  assert_eq(nodes[3].input1, 2)
  assert_true(nodes[4].kind is @mdsp.DspNodeKind::Output)
  assert_eq(nodes[4].input0, 3)
}

///|
test "replay: Constant+Mul through Eval" {
  let nodes : Array[@mdsp.DspNode] = [
    @mdsp.DspNode::constant(3.0),
    @mdsp.DspNode::constant(4.0),
    @mdsp.DspNode::mul(0, 1),
  ]
  let result : Eval = @mdsp.replay(nodes).unwrap()
  assert_eq(result.value, 12.0)
}

///|
test "replay: Gain+Clip+Output through Eval" {
  let nodes : Array[@mdsp.DspNode] = [
    @mdsp.DspNode::constant(5.0),
    @mdsp.DspNode::gain(0, 0.5),
    @mdsp.DspNode::clip(1, 2.0),
    @mdsp.DspNode::output(2),
  ]
  let result : Eval = @mdsp.replay(nodes).unwrap()
  // 5.0 * 0.5 = 2.5, clipped to 2.0
  assert_eq(result.value, 2.0)
}

///|
test "replay: tagless -> GraphBuilder -> replay roundtrip" {
  let a : @mdsp.GraphBuilder = @mdsp.ArithSym::constant(3.0)
  let b : @mdsp.GraphBuilder = @mdsp.ArithSym::constant(4.0)
  let product : @mdsp.GraphBuilder = @mdsp.ArithSym::mul(a, b)
  let result : Eval = @mdsp.replay(product.nodes()).unwrap()
  assert_eq(result.value, 12.0)
}
