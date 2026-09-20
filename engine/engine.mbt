///|
/// Recoverable failures of the host-independent graph engine.
pub suberror GraphEngineError {
  InvalidConfiguration
  EngineClosed
  MountClosed
  CapacityExceeded
  InvalidHandle
  InvalidGraph(@graph.GraphCompileError)
  BufferSizeMismatch(expected~ : Int, actual~ : Int)
  ControlRejected(@graph.GraphControlError)
} derive(Debug)

///|
priv enum EngineState {
  Mounting
  Sealed
  Closed
}

///|
priv enum GraphState {
  Live(@graph.Dsp)
  Unmounted
  Closed
}

///|
priv struct EngineGraph {
  mut state : GraphState
  mut playing : Bool
  output : @dsp.AudioBuffer
}

///|
fn EngineGraph::EngineGraph(
  graph : @graph.Dsp,
  ctx : @dsp.DspContext,
) -> EngineGraph {
  { state: Live(graph), playing: false, output: ctx.make_buffer(), }
}

///|
/// An independent mono runtime. Mounting allocates; processing reuses buffers.
/// No browser, global registry, or transport is required by this API.
pub struct GraphEngine {
  priv context : @dsp.DspContext
  priv slots : FixedArray[EngineGraph?]
  priv mut state : EngineState
}

///|
/// A typed, engine-owned capability. It cannot address another engine's graph.
pub struct MountedGraph {
  priv engine : GraphEngine
  priv instance : EngineGraph
  priv slot : Int
}

///|
fn MountedGraph::MountedGraph(
  engine : GraphEngine,
  instance : EngineGraph,
  slot : Int,
) -> MountedGraph {
  { engine, instance, slot, }
}

///|
/// Create an engine with a fixed render context and bounded live graph count.
pub fn GraphEngine::GraphEngine(
  context : @dsp.DspContext,
  capacity? : Int = 16,
) -> GraphEngine raise GraphEngineError {
  guard capacity > 0 &&
    context.block_size() > 0 &&
    @dsp.is_finite_positive(context.sample_rate()) else {
    raise InvalidConfiguration
  }
  { context, slots: FixedArray::make(capacity, None), state: Mounting, }
}

///|
/// Compile canonical authoring nodes and register a paused, independent graph.
/// Failed compilation leaves capacity and mount admission unchanged.
/// The first successful play seals mounting for this engine's lifetime.
pub fn GraphEngine::mount(
  self : GraphEngine,
  nodes : Array[@graph.DspNode],
) -> MountedGraph raise GraphEngineError {
  match self.state {
    Closed => raise EngineClosed
    Sealed => raise MountClosed
    Mounting => ()
  }
  let slot = for i in 0..<self.slots.length() {
    if self.slots[i] is None {
      break i
    }
  } nobreak {
    raise CapacityExceeded
  }
  let compiled = match
    @graph.Dsp::compile_result(
      @graph.AnalyzedGraph::analyze(nodes),
      self.context,
    ) {
    Ok(graph) => graph
    Err(error) => raise InvalidGraph(error)
  }
  let instance = EngineGraph(compiled, self.context)
  self.slots[slot] = Some(instance)
  MountedGraph(self, instance, slot)
}

///|
fn MountedGraph::graph(
  self : MountedGraph,
) -> @graph.Dsp raise GraphEngineError {
  match self.instance.state {
    Unmounted => raise InvalidHandle
    Closed => raise EngineClosed
    Live(graph) => graph
  }
}

///|
/// Start or resume this graph without resetting its DSP state.
pub fn MountedGraph::play(self : MountedGraph) -> Unit raise GraphEngineError {
  let _ = self.graph()
  self.engine.state = Sealed
  self.instance.playing = true
}

///|
/// Freeze processing, preserving phase and all other runtime state.
pub fn MountedGraph::pause(self : MountedGraph) -> Unit raise GraphEngineError {
  let _ = self.graph()
  self.instance.playing = false
}

///|
/// Apply a validated runtime control batch atomically at the next render
/// boundary. The controls target original authoring node indices.
pub fn MountedGraph::apply_controls(
  self : MountedGraph,
  controls : Array[@graph.GraphControl],
) -> Unit raise GraphEngineError {
  let graph = self.graph()
  match graph.apply_controls(controls) {
    Ok(_) => ()
    Err(error) => raise ControlRejected(error)
  }
}

///|
/// Permanently detach this graph. Repeated unmount is harmless, even if a later
/// mount reuses its slot. Other graphs and engines are not affected.
pub fn MountedGraph::unmount(
  self : MountedGraph,
) -> Unit raise GraphEngineError {
  match self.instance.state {
    Unmounted => ()
    Closed => raise EngineClosed
    Live(_) => {
      self.instance.state = Unmounted
      self.engine.slots[self.slot] = None
    }
  }
}

///|
/// Replace the caller's output with the sum of playing graphs. The buffer must
/// match the engine's block size. Validation precedes any DSP state advance.
pub fn GraphEngine::process(
  self : GraphEngine,
  output : @dsp.AudioBuffer,
) -> Unit raise GraphEngineError {
  guard !(self.state is Closed) else { raise EngineClosed }
  guard output.length() == self.context.block_size() else {
    raise BufferSizeMismatch(
      expected=self.context.block_size(),
      actual=output.length(),
    )
  }
  output.fill(0.0)
  for slot in self.slots {
    if slot is Some(instance) &&
      instance.playing &&
      instance.state is Live(graph) {
      graph.process(self.context, instance.output)
      for i in 0..<output.length() {
        output.set(i, output.get(i) + instance.output.get(i))
      }
    }
  }
}

///|
/// End this engine and release its compiled graphs. Repeated close is harmless.
pub fn GraphEngine::close(self : GraphEngine) -> Unit {
  self.state = Closed
  for i in 0..<self.slots.length() {
    if self.slots[i] is Some(instance) {
      instance.state = Closed
    }
    self.slots[i] = None
  }
}
