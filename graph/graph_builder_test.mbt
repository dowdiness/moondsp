///|
test "GraphBuilder: constant produces one node" {
  let c : GraphBuilder = ArithSym::constant(440.0)
  @debug.assert_eq(c.nodes().length(), 1)
}

///|
test "GraphBuilder: mul merges two constants" {
  let a : GraphBuilder = ArithSym::constant(3.0)
  let b : GraphBuilder = ArithSym::constant(4.0)
  let product : GraphBuilder = ArithSym::mul(a, b)
  let nodes = product.nodes()
  @debug.assert_eq(nodes.length(), 3) // const(3), const(4), mul(0,1)
  assert_true(nodes[0].kind() is DspNodeKind::Constant)
  @debug.assert_eq(nodes[0].value0(), 3.0)
  assert_true(nodes[1].kind() is DspNodeKind::Constant)
  @debug.assert_eq(nodes[1].value0(), 4.0)
  assert_true(nodes[2].kind() is DspNodeKind::Mul)
  @debug.assert_eq(nodes[2].input0(), 0)
  @debug.assert_eq(nodes[2].input1(), 1)
}

///|
test "GraphBuilder: mix merges two constants" {
  let a : GraphBuilder = ArithSym::constant(3.0)
  let b : GraphBuilder = ArithSym::constant(4.0)
  let result : GraphBuilder = ArithSym::mix(a, b)
  let nodes = result.nodes()
  @debug.assert_eq(nodes.length(), 3)
  assert_true(nodes[2].kind() is DspNodeKind::Mix)
  @debug.assert_eq(nodes[2].input0(), 0)
  @debug.assert_eq(nodes[2].input1(), 1)
}

///|
test "GraphBuilder: unary chain shares array" {
  let c : GraphBuilder = ArithSym::constant(1.0)
  let g : GraphBuilder = DspSym::gain(c, 0.5)
  let o : GraphBuilder = DspSym::output(g)
  @debug.assert_eq(o.nodes().length(), 3) // const, gain, output
}

///|
test "GraphBuilder: oscillator with frequency input" {
  let freq : GraphBuilder = ArithSym::constant(440.0)
  let osc : GraphBuilder = DspSym::oscillator(freq, Waveform::Sine)
  let nodes = osc.nodes()
  @debug.assert_eq(nodes.length(), 2) // const, oscillator
  assert_true(nodes[1].kind() is DspNodeKind::Oscillator)
  @debug.assert_eq(nodes[1].input0(), 0)
  assert_true(nodes[1].waveform() is Waveform::Sine)
}

///|
test "GraphBuilder: noise source" {
  let n : GraphBuilder = DspSym::noise(42U)
  let nodes = n.nodes()
  @debug.assert_eq(nodes.length(), 1)
  assert_true(nodes[0].kind() is DspNodeKind::Noise)
  @debug.assert_eq(nodes[0].seed(), 42U)
}

///|
test "GraphBuilder: adsr source" {
  let e : GraphBuilder = DspSym::adsr(10.0, 50.0, 0.7, 200.0)
  let nodes = e.nodes()
  @debug.assert_eq(nodes.length(), 1)
  assert_true(nodes[0].kind() is DspNodeKind::Adsr)
  @debug.assert_eq(nodes[0].value0(), 10.0)
  @debug.assert_eq(nodes[0].value1(), 50.0)
  @debug.assert_eq(nodes[0].value2(), 0.7)
  @debug.assert_eq(nodes[0].value3(), 200.0)
}

///|
test "GraphBuilder: clip" {
  let c : GraphBuilder = ArithSym::constant(1.0)
  let clipped : GraphBuilder = ArithSym::clip(c, 0.5)
  let nodes = clipped.nodes()
  @debug.assert_eq(nodes.length(), 2)
  assert_true(nodes[1].kind() is DspNodeKind::Clip)
  @debug.assert_eq(nodes[1].input0(), 0)
  @debug.assert_eq(nodes[1].value0(), 0.5)
}

///|
test "GraphBuilder: biquad filter" {
  let c : GraphBuilder = ArithSym::constant(1.0)
  let filtered : GraphBuilder = FilterSym::biquad(
    c,
    BiquadMode::LowPass,
    1000.0,
    0.707,
  )
  let nodes = filtered.nodes()
  @debug.assert_eq(nodes.length(), 2)
  assert_true(nodes[1].kind() is DspNodeKind::Biquad)
  @debug.assert_eq(nodes[1].input0(), 0)
  @debug.assert_eq(nodes[1].value0(), 1000.0)
  @debug.assert_eq(nodes[1].value1(), 0.707)
  assert_true(nodes[1].filter_mode() is BiquadMode::LowPass)
}

///|
test "GraphBuilder: delay" {
  let c : GraphBuilder = ArithSym::constant(1.0)
  let delayed : GraphBuilder = DelaySym::delay(c, 48000, 24000, 0.5)
  let nodes = delayed.nodes()
  @debug.assert_eq(nodes.length(), 2)
  assert_true(nodes[1].kind() is DspNodeKind::Delay)
  @debug.assert_eq(nodes[1].input0(), 0)
  @debug.assert_eq(nodes[1].delay_max_samples(), 48000)
  @debug.assert_eq(nodes[1].delay_samples(), 24000)
  @debug.assert_eq(nodes[1].value0(), 0.5)
}

///|
test "GraphBuilder: pan" {
  let c : GraphBuilder = ArithSym::constant(1.0)
  let panned : GraphBuilder = StereoSym::pan(c, 0.3)
  let nodes = panned.nodes()
  @debug.assert_eq(nodes.length(), 2)
  assert_true(nodes[1].kind() is DspNodeKind::Pan)
  @debug.assert_eq(nodes[1].input0(), 0)
  @debug.assert_eq(nodes[1].value0(), 0.3)
}

///|
test "GraphBuilder: stereo_gain" {
  let c : GraphBuilder = ArithSym::constant(1.0)
  let p : GraphBuilder = StereoSym::pan(c, 0.0)
  let sg : GraphBuilder = StereoSym::stereo_gain(p, 0.8)
  let nodes = sg.nodes()
  @debug.assert_eq(nodes.length(), 3)
  assert_true(nodes[2].kind() is DspNodeKind::StereoGain)
  @debug.assert_eq(nodes[2].input0(), 1)
  @debug.assert_eq(nodes[2].value0(), 0.8)
}

///|
test "GraphBuilder: stereo_clip" {
  let c : GraphBuilder = ArithSym::constant(1.0)
  let p : GraphBuilder = StereoSym::pan(c, 0.0)
  let sc : GraphBuilder = StereoSym::stereo_clip(p, 0.5)
  let nodes = sc.nodes()
  @debug.assert_eq(nodes.length(), 3)
  assert_true(nodes[2].kind() is DspNodeKind::StereoClip)
  @debug.assert_eq(nodes[2].input0(), 1)
  @debug.assert_eq(nodes[2].value0(), 0.5)
}

///|
test "GraphBuilder: stereo_biquad" {
  let c : GraphBuilder = ArithSym::constant(1.0)
  let p : GraphBuilder = StereoSym::pan(c, 0.0)
  let sb : GraphBuilder = StereoFilterSym::stereo_biquad(
    p,
    BiquadMode::HighPass,
    500.0,
    1.0,
  )
  let nodes = sb.nodes()
  @debug.assert_eq(nodes.length(), 3)
  assert_true(nodes[2].kind() is DspNodeKind::StereoBiquad)
  @debug.assert_eq(nodes[2].input0(), 1)
  @debug.assert_eq(nodes[2].value0(), 500.0)
  @debug.assert_eq(nodes[2].value1(), 1.0)
  assert_true(nodes[2].filter_mode() is BiquadMode::HighPass)
}

///|
test "GraphBuilder: stereo_delay" {
  let c : GraphBuilder = ArithSym::constant(1.0)
  let p : GraphBuilder = StereoSym::pan(c, 0.0)
  let sd : GraphBuilder = StereoDelaySym::stereo_delay(p, 48000, 12000, 0.3)
  let nodes = sd.nodes()
  @debug.assert_eq(nodes.length(), 3)
  assert_true(nodes[2].kind() is DspNodeKind::StereoDelay)
  @debug.assert_eq(nodes[2].input0(), 1)
  @debug.assert_eq(nodes[2].delay_max_samples(), 48000)
  @debug.assert_eq(nodes[2].delay_samples(), 12000)
  @debug.assert_eq(nodes[2].value0(), 0.3)
}

///|
test "GraphBuilder: stereo_mixdown unary" {
  let c : GraphBuilder = ArithSym::constant(1.0)
  let p : GraphBuilder = StereoSym::pan(c, -1.0)
  let mixed : GraphBuilder = StereoSym::stereo_mixdown(p)
  let nodes = mixed.nodes()
  // const(1.0)=0, pan(0)=1, stereo_mixdown(1)=2
  @debug.assert_eq(nodes.length(), 3)
  assert_true(nodes[2].kind() is DspNodeKind::StereoMixDown)
  @debug.assert_eq(nodes[2].input0(), 1)
  @debug.assert_eq(nodes[2].input1(), -1)
}

///|
test "GraphBuilder: stereo_output unary" {
  let c : GraphBuilder = ArithSym::constant(1.0)
  let p : GraphBuilder = StereoSym::pan(c, -1.0)
  let out : GraphBuilder = StereoSym::stereo_output(p)
  let nodes = out.nodes()
  @debug.assert_eq(nodes.length(), 3)
  assert_true(nodes[2].kind() is DspNodeKind::StereoOutput)
  @debug.assert_eq(nodes[2].input0(), 1)
  @debug.assert_eq(nodes[2].input1(), -1)
}

///|
test "GraphBuilder: remap preserves correct indices during merge" {
  // Build a chain: const -> gain -> clip
  let c : GraphBuilder = ArithSym::constant(1.0)
  let g : GraphBuilder = DspSym::gain(c, 0.5)
  let clipped : GraphBuilder = ArithSym::clip(g, 0.8)
  // Build another chain
  let c2 : GraphBuilder = ArithSym::constant(2.0)
  let g2 : GraphBuilder = DspSym::gain(c2, 0.3)
  // Multiply them: merges c2,g2 into c,g,clip array with offset 3
  let result : GraphBuilder = ArithSym::mul(clipped, g2)
  let nodes = result.nodes()
  // Original: const(1)=0, gain(0)=1, clip(1)=2
  // Merged:   const(2)=3, gain(3)=4
  // Mul(2,4)=5
  @debug.assert_eq(nodes.length(), 6)
  assert_true(nodes[3].kind() is DspNodeKind::Constant)
  @debug.assert_eq(nodes[3].value0(), 2.0)
  assert_true(nodes[4].kind() is DspNodeKind::Gain)
  @debug.assert_eq(nodes[4].input0(), 3) // remapped from 0 to 0+3=3
  assert_true(nodes[5].kind() is DspNodeKind::Mul)
  @debug.assert_eq(nodes[5].input0(), 2)
  @debug.assert_eq(nodes[5].input1(), 4)
}

///|
test "GraphBuilder: same-array binary op does not duplicate" {
  // When both operands share the same array (from same source chain),
  // no duplication should occur
  let c : GraphBuilder = ArithSym::constant(1.0)
  let g : GraphBuilder = DspSym::gain(c, 0.5)
  // g shares the same array as c
  // mul(c, g) should just append without merging
  let result : GraphBuilder = ArithSym::mul(c, g)
  let nodes = result.nodes()
  // const=0, gain(0)=1, mul(0,1)=2
  @debug.assert_eq(nodes.length(), 3)
  assert_true(nodes[2].kind() is DspNodeKind::Mul)
  @debug.assert_eq(nodes[2].input0(), 0)
  @debug.assert_eq(nodes[2].input1(), 1)
}

///|
test "GraphBuilder: full mono pipeline" {
  // const -> osc -> gain -> biquad -> output
  let freq : GraphBuilder = ArithSym::constant(440.0)
  let osc : GraphBuilder = DspSym::oscillator(freq, Waveform::Saw)
  let gained : GraphBuilder = DspSym::gain(osc, 0.7)
  let filtered : GraphBuilder = FilterSym::biquad(
    gained,
    BiquadMode::LowPass,
    2000.0,
    0.707,
  )
  let out : GraphBuilder = DspSym::output(filtered)
  let nodes = out.nodes()
  @debug.assert_eq(nodes.length(), 5) // const, osc, gain, biquad, output
  assert_true(nodes[0].kind() is DspNodeKind::Constant)
  assert_true(nodes[1].kind() is DspNodeKind::Oscillator)
  assert_true(nodes[2].kind() is DspNodeKind::Gain)
  assert_true(nodes[3].kind() is DspNodeKind::Biquad)
  assert_true(nodes[4].kind() is DspNodeKind::Output)
}

///|
test "GraphBuilder: adsr * osc pipeline" {
  let env : GraphBuilder = DspSym::adsr(10.0, 50.0, 0.7, 200.0)
  let freq : GraphBuilder = ArithSym::constant(440.0)
  let osc : GraphBuilder = DspSym::oscillator(freq, Waveform::Sine)
  let modulated : GraphBuilder = ArithSym::mul(env, osc)
  let out : GraphBuilder = DspSym::output(modulated)
  let nodes = out.nodes()
  // adsr=0 | const(440)=0, osc(0)=1 -> merged at offset 1
  // result: adsr=0, const(440)=1, osc(1)=2, mul(0,2)=3, output(3)=4
  @debug.assert_eq(nodes.length(), 5)
  assert_true(nodes[0].kind() is DspNodeKind::Adsr)
  assert_true(nodes[1].kind() is DspNodeKind::Constant)
  assert_true(nodes[2].kind() is DspNodeKind::Oscillator)
  @debug.assert_eq(nodes[2].input0(), 1) // remapped: was 0, offset 1, so 1
  assert_true(nodes[3].kind() is DspNodeKind::Mul)
  @debug.assert_eq(nodes[3].input0(), 0)
  @debug.assert_eq(nodes[3].input1(), 2)
  assert_true(nodes[4].kind() is DspNodeKind::Output)
  @debug.assert_eq(nodes[4].input0(), 3)
}
