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
pub extend GraphEngineError with @moonbitlang/core/debug.Debug::{to_repr}

///|
fn lifecycle_error(error : @lifecycle.LifecycleError) -> GraphEngineError {
  match error {
    InvalidConfiguration => InvalidConfiguration
    EngineClosed => EngineClosed
    MountClosed => MountClosed
    CapacityExceeded => CapacityExceeded
    InvalidHandle => InvalidHandle
    BufferSizeMismatch(expected~, actual~) =>
      BufferSizeMismatch(expected~, actual~)
  }
}

///|
/// An independent mono runtime. Mounting allocates; processing reuses buffers.
pub struct GraphEngine {
  priv context : @dsp.DspContext
  priv raw : @lifecycle.Engine[@graph.Dsp]
}

///|
/// A typed, engine-owned capability, with no browser binding surface.
pub struct MountedGraph {
  priv raw : @lifecycle.Mount[@graph.Dsp]
}

///|
pub fn GraphEngine::GraphEngine(
  context : @dsp.DspContext,
  capacity? : Int = 16,
) -> GraphEngine raise GraphEngineError {
  let raw = @lifecycle.Engine::Engine(context, @graph.Dsp::process, capacity~) catch {
    error => raise lifecycle_error(error)
  }
  { context, raw, }
}

///|
/// Compile and register a paused graph. First successful play seals mounting.
pub fn GraphEngine::mount(
  self : GraphEngine,
  nodes : Array[@graph.DspNode],
) -> MountedGraph raise GraphEngineError {
  self.raw.check_mount() catch {
    error => raise lifecycle_error(error)
  }
  let compiled = match
    @graph.Dsp::compile_result(
      @graph.AnalyzedGraph::analyze(nodes),
      self.context,
    ) {
    Ok(graph) => graph
    Err(error) => raise InvalidGraph(error)
  }
  let raw = self.raw.register(compiled) catch {
    error => raise lifecycle_error(error)
  }
  { raw, }
}

///|
pub fn MountedGraph::play(self : MountedGraph) -> Unit raise GraphEngineError {
  self.raw.play() catch {
    error => raise lifecycle_error(error)
  }
}

///|
pub fn MountedGraph::pause(self : MountedGraph) -> Unit raise GraphEngineError {
  self.raw.pause() catch {
    error => raise lifecycle_error(error)
  }
}

///|
/// Atomically apply controls addressed by original authoring node index.
pub fn MountedGraph::apply_controls(
  self : MountedGraph,
  controls : Array[@graph.GraphControl],
) -> Unit raise GraphEngineError {
  let graph = self.raw.graph() catch { error => raise lifecycle_error(error) }
  match graph.apply_controls(controls) {
    Ok(_) => ()
    Err(error) => raise ControlRejected(error)
  }
}

///|
pub fn MountedGraph::unmount(
  self : MountedGraph,
) -> Unit raise GraphEngineError {
  self.raw.unmount() catch {
    error => raise lifecycle_error(error)
  }
}

///|
pub fn GraphEngine::process(
  self : GraphEngine,
  output : @dsp.AudioBuffer,
) -> Unit raise GraphEngineError {
  if self.raw.process(output) is Some(error) {
    raise lifecycle_error(error)
  }
}

///|
pub fn GraphEngine::close(self : GraphEngine) -> Unit {
  self.raw.close()
}
