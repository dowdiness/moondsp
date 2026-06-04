///|
test "analyze: returns CompiledTemplate with snapshot that survives caller mutation" {
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::output(0),
  ]
  let ct = CompiledTemplate::analyze(template)
  template[0] = DspNode::constant(1.0)
  assert_true(ct.node_at(0).kind() is DspNodeKind::Oscillator)
}

///|
test "analyze: length matches input template length" {
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::gain(0, 0.5),
    DspNode::output(1),
  ]
  let ct = CompiledTemplate::analyze(template)
  @debug.assert_eq(ct.length(), 3)
}

///|
test "orphan_adsr_count: live ADSR returns 0" {
  // ADSR wired through envelope_gain to Output — survives optimization.
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::adsr(attack_ms=10.0, decay_ms=100.0, sustain=0.7, release_ms=300.0),
    DspNode::envelope_gain(input=0, envelope=1, amount=1.0),
    DspNode::output(2),
  ]
  let ct = CompiledTemplate::analyze(template)
  @debug.assert_eq(ct.orphan_adsr_count(), 0)
}

///|
test "orphan_adsr_count: dead ADSR returns 1" {
  // ADSR present but not consumed by Output path — orphan.
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::adsr(attack_ms=10.0, decay_ms=100.0, sustain=0.7, release_ms=300.0),
    DspNode::gain(0, 0.3),
    DspNode::output(2),
  ]
  let ct = CompiledTemplate::analyze(template)
  @debug.assert_eq(ct.orphan_adsr_count(), 1)
}

///|
test "orphan_adsr_count: multiple dead ADSRs returns correct count" {
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::adsr(attack_ms=10.0, decay_ms=100.0, sustain=0.7, release_ms=300.0), // orphan
    DspNode::adsr(attack_ms=5.0, decay_ms=50.0, sustain=0.5, release_ms=100.0), // orphan
    DspNode::adsr(attack_ms=1.0, decay_ms=10.0, sustain=0.9, release_ms=20.0), // orphan
    DspNode::gain(0, 0.3),
    DspNode::output(4),
  ]
  let ct = CompiledTemplate::analyze(template)
  @debug.assert_eq(ct.orphan_adsr_count(), 3)
}

///|
test "is_node_live: surviving node returns true" {
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::output(0),
  ]
  let ct = CompiledTemplate::analyze(template)
  assert_true(ct.is_node_live(0)) // Oscillator survives (feeds Output)
  assert_true(ct.is_node_live(1)) // Output survives
}

///|
test "is_node_live: eliminated node returns false" {
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::adsr(attack_ms=10.0, decay_ms=100.0, sustain=0.7, release_ms=300.0), // orphan — eliminated
    DspNode::gain(0, 0.3),
    DspNode::output(2),
  ]
  let ct = CompiledTemplate::analyze(template)
  assert_false(ct.is_node_live(1)) // ADSR dead
  assert_true(ct.is_node_live(0)) // Osc survives
  assert_true(ct.is_node_live(2)) // Gain survives
  assert_true(ct.is_node_live(3)) // Output survives
}

///|
test "is_node_live: out-of-bounds index returns false (does not abort)" {
  let template = [DspNode::constant(1.0), DspNode::output(0)]
  let ct = CompiledTemplate::analyze(template)
  assert_false(ct.is_node_live(-1))
  assert_false(ct.is_node_live(100))
  assert_false(ct.is_node_live(2)) // exactly one past end
}

///|
/// B5: adsr_authoring_indices count + orphan_adsr_count equals total ADSRs.
test "B5: adsr_authoring_indices accounts for all authoring ADSRs" {
  let nodes : Array[DspNode] = [
    DspNode::oscillator(@dsp.Waveform::Sine, 440.0),
    DspNode::adsr(attack_ms=10.0, decay_ms=50.0, sustain=0.5, release_ms=100.0),
    DspNode::envelope_gain(input=0, envelope=1, amount=1.0),
    DspNode::output(2),
  ]
  let t = CompiledTemplate::analyze(nodes)
  let live = t.adsr_authoring_indices()
  @debug.assert_eq(live.length() + t.orphan_adsr_count(), 1)
  for i in 0..<live.length() {
    let idx = live[i]
    @debug.assert_eq(t.template[idx].kind() is Adsr, true)
    @debug.assert_eq(t.index_map[idx] >= 0, true)
  }
}

///|
/// B5: orphan ADSR excluded from adsr_authoring_indices.
test "B5: orphan ADSR is excluded from adsr_authoring_indices" {
  let nodes : Array[DspNode] = [
    DspNode::oscillator(@dsp.Waveform::Sine, 440.0),
    DspNode::adsr(attack_ms=10.0, decay_ms=50.0, sustain=0.5, release_ms=100.0),
    DspNode::output(0), // ADSR at index 1 is orphan
  ]
  let t = CompiledTemplate::analyze(nodes)
  @debug.assert_eq(t.adsr_authoring_indices().length(), 0)
  @debug.assert_eq(t.orphan_adsr_count(), 1)
}

///|
/// B6: adsr_authoring_indices is monotonically increasing (authoring order).
test "B6: adsr_authoring_indices preserves authoring order" {
  let nodes : Array[DspNode] = [
    DspNode::adsr(attack_ms=10.0, decay_ms=50.0, sustain=0.5, release_ms=100.0),
    DspNode::oscillator(@dsp.Waveform::Sine, 440.0),
    DspNode::adsr(attack_ms=5.0, decay_ms=25.0, sustain=0.7, release_ms=50.0),
    DspNode::envelope_gain(input=1, envelope=0, amount=1.0),
    DspNode::envelope_gain(input=3, envelope=2, amount=1.0),
    DspNode::output(4),
  ]
  let live = CompiledTemplate::analyze(nodes).adsr_authoring_indices()
  @debug.assert_eq(live.length(), 2)
  for i in 1..<live.length() {
    @debug.assert_eq(live[i - 1] < live[i], true)
  }
}

///|
test "CompiledTemplate equality treats unchanged NaN templates as equal" {
  let left = CompiledTemplate::analyze([
    DspNode::constant(0.0 / 0.0),
    DspNode::output(0),
  ])
  let right = CompiledTemplate::analyze([
    DspNode::constant(0.0 / 0.0),
    DspNode::output(0),
  ])
  assert_true(left == right)
}

///|
test "CompiledTemplate equality keeps authoring-only dead nodes visible" {
  let left = CompiledTemplate::analyze([
    DspNode::constant(1.0),
    DspNode::output(0),
  ])
  let right = CompiledTemplate::analyze([
    DspNode::constant(1.0),
    DspNode::constant(2.0),
    DspNode::output(0),
  ])
  assert_false(left == right)
}
