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

///|
test "orphan_adsr_count: live ADSR returns 0" {
  // ADSR wired through envelope_gain to Output — survives optimization.
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::adsr(10.0, 100.0, 0.7, 300.0),
    DspNode::envelope_gain(0, 1, 1.0),
    DspNode::output(2),
  ]
  let ct = CompiledTemplate::analyze(template)
  assert_eq(ct.orphan_adsr_count(), 0)
}

///|
test "orphan_adsr_count: dead ADSR returns 1" {
  // ADSR present but not consumed by Output path — orphan.
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::adsr(10.0, 100.0, 0.7, 300.0),
    DspNode::gain(0, 0.3),
    DspNode::output(2),
  ]
  let ct = CompiledTemplate::analyze(template)
  assert_eq(ct.orphan_adsr_count(), 1)
}

///|
test "orphan_adsr_count: multiple dead ADSRs returns correct count" {
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::adsr(10.0, 100.0, 0.7, 300.0), // orphan
    DspNode::adsr(5.0, 50.0, 0.5, 100.0), // orphan
    DspNode::adsr(1.0, 10.0, 0.9, 20.0), // orphan
    DspNode::gain(0, 0.3),
    DspNode::output(4),
  ]
  let ct = CompiledTemplate::analyze(template)
  assert_eq(ct.orphan_adsr_count(), 3)
}
