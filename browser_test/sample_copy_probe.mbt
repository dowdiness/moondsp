///|
/// Measurement prototype for ADR-0026: how long JS takes to copy a decoded
/// waveform into a wasm-gc buffer one sample per call. JS cannot write a
/// wasm-gc array directly, so every sample crosses as one export call. This is
/// not the sample store; it only owns one 32-bit float waveform.
let sample_copy_buffer : @ref.Ref[FixedArray[Float]] = Ref(
  FixedArray::make(0, 0.0),
)

///|
/// Allocate a zeroed waveform of `length` samples, replacing the previous one.
/// Returns the length, or -1 when `length` is negative.
pub fn sample_copy_reserve(length : Int32) -> Int32 {
  guard length >= 0 else { return -1 }
  sample_copy_buffer.val = FixedArray::make(length, 0.0)
  length
}

///|
/// Write one sample. An index outside the waveform writes nothing.
pub fn sample_copy_write(index : Int32, value : Float) -> Unit {
  let data = sample_copy_buffer.val
  if index >= 0 && index < data.length() {
    data[index] = value
  }
}

///|
/// The sample at `index`, or 0 outside the waveform.
pub fn sample_copy_sample(index : Int32) -> Double {
  let data = sample_copy_buffer.val
  if index >= 0 && index < data.length() {
    data[index].to_double()
  } else {
    0.0
  }
}

///|
/// The sum of every sample, so a caller can check the whole copy landed.
pub fn sample_copy_checksum() -> Double {
  let mut sum = 0.0
  for value in sample_copy_buffer.val {
    sum = sum + value.to_double()
  }
  sum
}

///|
/// Measurement prototype for ADR-0026 stage 3: the store a host would make at
/// start-up, so JS can time making it.
let sample_store_probe : @ref.Ref[@moondsp.SampleStore] = Ref(
  @moondsp.SampleStore(entries=0, max_length=0, capacity=0),
)

///|
/// Make a store of these sizes, replacing the previous one. Returns its
/// capacity.
pub fn sample_store_create(
  entries : Int32,
  max_length : Int32,
  capacity : Int32,
) -> Int32 {
  sample_store_probe.val = @moondsp.SampleStore(
    entries~,
    max_length~,
    capacity~,
  )
  sample_store_probe.val.capacity()
}

///|
let sample_player_probe_graph : @ref.Ref[@moondsp.Dsp?] = Ref(None)

///|
/// The audit's store and the waveform it registers as sample 0.
let sample_player_probe_store : @ref.Ref[
  (@moondsp.SampleStore, FixedArray[Float])?,
] = Ref(None)

///|
let sample_player_probe_output : @ref.Ref[@moondsp.AudioBuffer] = Ref(
  @moondsp.AudioBuffer::filled(128),
)

///|
let sample_player_probe_context : @ref.Ref[@moondsp.DspContext] = Ref(
  @moondsp.DspContext(sample_rate=48000.0, block_size=128),
)

///|
/// Register one second of a 440 Hz sine as sample 0, root pitch 69, and
/// compile a sample player of it at `pitch` and `speed`, playing the slice
/// from `begin` to `end`, at 48 kHz in blocks of 128, for the allocation
/// audit. Returns 1, or 0 when compiling fails.
pub fn sample_player_probe_init(
  pitch : Double,
  speed : Double,
  begin : Double,
  end : Double,
) -> Int32 {
  // Room for the waveform and two replacements, which `reload` writes while
  // the player still plays an earlier one.
  let store = @moondsp.SampleStore(
    entries=1,
    max_length=48000,
    capacity=3 * 48000,
  )
  let sine = FixedArray::makei(48000, index => {
    Float::from_double(
      @math.sin(2.0 * @math.PI * 440.0 * index.to_double() / 48000.0),
    )
  })
  guard store.register(0, sine, root_pitch=69.0) is None else { return 0 }
  sample_player_probe_store.val = Some((store, sine))
  let context = @moondsp.DspContext(
    sample_rate=48000.0,
    block_size=128,
    samples=store,
  )
  sample_player_probe_context.val = context
  sample_player_probe_graph.val = @moondsp.Dsp::compile(
    @moondsp.AnalyzedGraph::analyze([
      @moondsp.DspNode::sample_player(number=0.0, pitch~, speed~, begin~, end~),
      @moondsp.DspNode::output(0),
    ]),
    context,
  )
  if sample_player_probe_graph.val is Some(_) {
    1
  } else {
    0
  }
}

///|
/// Load sample 0 again as a host does: scan the store for the waveform the
/// player still plays, then register the same sine. Returns 1, or 0 when the
/// registration fails.
pub fn sample_player_probe_reload() -> Int32 {
  guard sample_player_probe_store.val is Some((store, sine)) &&
    sample_player_probe_graph.val is Some(graph) else {
    return 0
  }
  store.begin_scan()
  graph.mark_samples()
  store.end_scan()
  if store.register(0, sine, root_pitch=69.0) is None {
    1
  } else {
    0
  }
}

///|
/// Render `blocks` blocks, resetting the graph every `reset_every` blocks
/// (never when 0), and return the sum of the squares of every rendered
/// sample, its energy.
pub fn sample_player_probe_process(
  blocks : Int32,
  reset_every : Int32,
) -> Double {
  guard sample_player_probe_graph.val is Some(graph) else { return 0.0 }
  let context = sample_player_probe_context.val
  let output = sample_player_probe_output.val
  let mut sum = 0.0
  for block in 0..<blocks {
    if reset_every > 0 && block % reset_every == 0 {
      graph.reset_runtime_state()
    }
    graph.process(context, output)
    for index in 0..<output.length() {
      sum = sum + output.get(index) * output.get(index)
    }
  }
  sum
}
