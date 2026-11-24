///|
/// A store whose sample 0 is `length` samples of `at(index)`, root pitch 60.
fn sample_graph_store(
  length : Int32,
  at : (Int32) -> Double,
) -> @dsp.SampleStore {
  let store = @dsp.SampleStore(entries=2, max_length=length, capacity=length)
  let waveform = FixedArray::makei(length, index => {
    Float::from_double(at(index))
  })
  guard store.register(0, waveform, root_pitch=60.0) is None else {
    abort("sample graph store rejected its waveform")
  }
  store
}

///|
fn sample_graph_render(
  nodes : Array[@graph.DspNode],
  context : DspContext,
  blocks : Int32,
) -> Array[Double] {
  let graph = @graph.Dsp::compile(@graph.AnalyzedGraph::analyze(nodes), context).unwrap()
  let block = AudioBuffer::filled(context.block_size())
  let rendered = []
  for _ in 0..<blocks {
    graph.process(context, block)
    for index in 0..<block.length() {
      rendered.push(block.get(index))
    }
  }
  rendered
}

///|
test "a compiled sample player reads the waveform from its context's store" {
  let store = sample_graph_store(6, index => (index + 1).to_double() / 8.0)
  let context = DspContext(sample_rate=48000.0, block_size=4, samples=store)
  let player = [
    @graph.DspNode::sample_player(number=0.0, pitch=60.0, speed=1.0),
    @graph.DspNode::output(0),
  ]
  assert_eq(sample_graph_render(player, context, 2), [
    0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.0, 0.0,
  ])
  let unregistered = [
    @graph.DspNode::sample_player(number=1.0, pitch=60.0, speed=1.0),
    @graph.DspNode::output(0),
  ]
  assert_eq(sample_graph_render(unregistered, context, 1), [0.0, 0.0, 0.0, 0.0])
  let no_store = DspContext(sample_rate=48000.0, block_size=4)
  assert_eq(sample_graph_render(player, no_store, 1), [0.0, 0.0, 0.0, 0.0])
}

///|
test "a sample player rejects non-finite params at compile and at runtime" {
  let context = DspContext(sample_rate=48000.0, block_size=4)
  let nan = 0.0 / 0.0
  assert_true(
    @graph.Dsp::compile(
      @graph.AnalyzedGraph::analyze([
        @graph.DspNode::sample_player(number=0.0, pitch=60.0, speed=nan),
        @graph.DspNode::output(0),
      ]),
      context,
    )
    is None,
  )
  let graph = @graph.Dsp::compile(
    @graph.AnalyzedGraph::analyze([
      @graph.DspNode::sample_player(number=0.0, pitch=60.0, speed=1.0),
      @graph.DspNode::output(0),
    ]),
    context,
  ).unwrap()
  assert_true(graph.set_param_bool(0, @graph.GraphParamSlot::Value2, 2.0))
  assert_true(!graph.set_param_bool(0, @graph.GraphParamSlot::Value1, nan))
  assert_true(!graph.set_param_bool(0, @graph.GraphParamSlot::Value3, 1.0))
}

///|
test "a topology recompile keeps the context's sample store" {
  let store = sample_graph_store(64, _ => 0.5)
  let context = DspContext(
    sample_rate=HOT_SWAP_SAMPLE_RATE,
    block_size=HOT_SWAP_BLOCK_SIZE,
    samples=store,
  )
  let topology = @graph.DspTopologyController::from_nodes(
    [
      @graph.DspNode::sample_player(number=0.0, pitch=60.0, speed=1.0),
      @graph.DspNode::gain(0, 1.0),
      @graph.DspNode::output(1),
    ],
    context,
    crossfade_samples=HOT_SWAP_CROSSFADE_SAMPLES,
  ).unwrap()
  let block = AudioBuffer::filled(HOT_SWAP_BLOCK_SIZE)
  topology.process(context, block)
  assert_true(block.every(sample => sample == 0.5))
  assert_true(
    topology.queue_topology_edit(
      @graph.GraphTopologyEdit::replace_node(1, @graph.DspNode::gain(0, 2.0)),
    )
    is Ok(_),
  )
  // Two blocks cross-fade; the third is the recompiled graph alone.
  for _ in 0..<3 {
    topology.process(context, block)
  }
  assert_true(block.every(sample => sample == 1.0))
}
