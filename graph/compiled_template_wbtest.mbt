///|
test "analyze: returns CompiledTemplate with snapshot that survives caller mutation" {
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::output(0),
  ]
  let ct = CompiledTemplate::analyze(template)
  // Mutate the caller's array post-analyze.
  template[0] = DspNode::constant(1.0)
  // Snapshot inside CompiledTemplate is independent.
  assert_true(ct.node_at(0).kind is DspNodeKind::Oscillator)
}

///|
test "analyze: length matches input template length" {
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::gain(0, 0.5),
    DspNode::output(1),
  ]
  let ct = CompiledTemplate::analyze(template)
  assert_eq(ct.length(), 3)
}
