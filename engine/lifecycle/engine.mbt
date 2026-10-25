///|
// Shared implementation package. Public facades keep these generic types private.
pub suberror LifecycleError {
  InvalidConfiguration
  EngineClosed
  MountClosed
  CapacityExceeded
  InvalidHandle
  BufferSizeMismatch(expected~ : Int, actual~ : Int)
} derive(Debug)

///|
pub extend LifecycleError with @debug.Debug::{to_repr}

///|
priv enum EngineState {
  Mounting
  Sealed
  Closed
}

///|
priv enum GraphState[G] {
  Live(G)
  Unmounted
  Closed
}

///|
priv struct Instance[G] {
  mut state : GraphState[G]
  mut playing : Bool
  output : @dsp.AudioBuffer
}

///|
pub struct Engine[G] {
  priv context : @dsp.DspContext
  priv slots : FixedArray[Instance[G]?]
  priv render : (G, @dsp.DspContext, @dsp.AudioBuffer) -> Unit
  priv mut state : EngineState
}

///|
pub struct Mount[G] {
  priv engine : Engine[G]
  priv instance : Instance[G]
  priv slot : Int
}

///|
pub fn[G] Engine::Engine(
  context : @dsp.DspContext,
  render : (G, @dsp.DspContext, @dsp.AudioBuffer) -> Unit,
  capacity? : Int = 16,
) -> Engine[G] raise LifecycleError {
  guard capacity > 0 &&
    context.block_size() > 0 &&
    @dsp.is_finite_positive(context.sample_rate()) else {
    raise InvalidConfiguration
  }
  { context, render, slots: FixedArray::make(capacity, None), state: Mounting, }
}

///|
pub fn[G] Engine::check_mount(self : Engine[G]) -> Unit raise LifecycleError {
  match self.state {
    Closed => raise EngineClosed
    Sealed => raise MountClosed
    Mounting => ()
  }
  for slot in self.slots {
    if slot is None {
      return
    }
  }
  raise CapacityExceeded
}

///|
// Registration happens only after construction and target resolution succeed.
pub fn[G] Engine::register(
  self : Engine[G],
  graph : G,
) -> Mount[G] raise LifecycleError {
  self.check_mount()
  let slot = for i in 0..<self.slots.length() {
    if self.slots[i] is None {
      break i
    }
  } nobreak {
    raise CapacityExceeded
  }
  let instance = {
    state: Live(graph),
    playing: false,
    output: self.context.make_buffer(),
  }
  self.slots[slot] = Some(instance)
  { engine: self, instance, slot, }
}

///|
// Nullable projection for adapters whose registry removes retired handles.
// For reference-backed graphs this avoids boxing a successful raising return.
pub fn[G] Mount::live_graph(self : Mount[G]) -> G? {
  match self.instance.state {
    Live(graph) => Some(graph)
    Unmounted | Closed => None
  }
}

///|
pub fn[G] Mount::graph(self : Mount[G]) -> G raise LifecycleError {
  match self.instance.state {
    Unmounted => raise InvalidHandle
    Closed => raise EngineClosed
    Live(graph) => graph
  }
}

///|
pub fn[G] Mount::play(self : Mount[G]) -> Unit raise LifecycleError {
  let _ = self.graph()
  self.engine.state = Sealed
  self.instance.playing = true
}

///|
pub fn[G] Mount::pause(self : Mount[G]) -> Unit raise LifecycleError {
  let _ = self.graph()
  self.instance.playing = false
}

///|
pub fn[G] Mount::unmount(self : Mount[G]) -> Unit raise LifecycleError {
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
pub fn[G] Engine::process(
  self : Engine[G],
  output : @dsp.AudioBuffer,
) -> LifecycleError? {
  guard !(self.state is Closed) else { return Some(EngineClosed) }
  guard output.length() == self.context.block_size() else {
    return Some(
      BufferSizeMismatch(
        expected=self.context.block_size(),
        actual=output.length(),
      ),
    )
  }
  output.fill(0.0)
  for slot in self.slots {
    if slot is Some(instance) &&
      instance.playing &&
      instance.state is Live(graph) {
      (self.render)(graph, self.context, instance.output)
      for i in 0..<output.length() {
        output.set(i, output.get(i) + instance.output.get(i))
      }
    }
  }
  None
}

///|
pub fn[G] Engine::close(self : Engine[G]) -> Unit {
  self.state = Closed
  for i in 0..<self.slots.length() {
    if self.slots[i] is Some(instance) {
      instance.state = Closed
    }
    self.slots[i] = None
  }
}
