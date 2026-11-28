// Characterization of a known `GraphBuilder` issue: values share one mutable
// node array. These tests pin today's behavior so a fix shows up as a diff.

///|
test "GraphBuilder known issue: variants from one base leak into each other" {
  let freq : @graph.GraphBuilder = ArithSym::constant(220.0)
  let base : @graph.GraphBuilder = DspSym::oscillator(freq, Waveform::Saw)
  let v1 : @graph.GraphBuilder = DspSym::output(DspSym::gain(base, 0.5))
  let v2 : @graph.GraphBuilder = DspSym::output(DspSym::gain(base, 0.1))
  ignore(v2)
  let outputs = v1
    .nodes()
    .filter(n => n.kind() is @graph.DspNodeKind::Output)
    .length()
  // Expected for independent values: 4 nodes and 1 output.
  assert_true(v1.nodes().length() == 6)
  assert_true(outputs == 2)
}

///|
test "GraphBuilder known issue: a signal reused after a merge is duplicated" {
  let two : @graph.GraphBuilder = ArithSym::constant(2.0)
  let lfo : @graph.GraphBuilder = DspSym::oscillator(two, Waveform::Sine)
  let x : @graph.GraphBuilder = ArithSym::constant(1.0)
  let result : @graph.GraphBuilder = ArithSym::mix(ArithSym::mul(x, lfo), lfo)
  let oscillators = result
    .nodes()
    .filter(n => n.kind() is @graph.DspNodeKind::Oscillator)
    .length()
  // Expected with sharing preserved: 5 nodes and 1 oscillator.
  assert_true(result.nodes().length() == 7)
  assert_true(oscillators == 2)
}
