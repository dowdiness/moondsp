///|
/// Shared hot-swap state for both mono and stereo compiled graphs.
///
/// Mono uses `old_output`/`new_output` (stereo buffers are zero-length).
/// Stereo uses `old_left`/`old_right`/`new_left`/`new_right` (mono buffers
/// are zero-length). Zero-length rather than Option so crossfade code can
/// call buffer methods unconditionally without branching per sample.
priv enum GraphSwapState {
  Playing(@runtime.CompiledGraph)
  Switching(PreparedGraphSwap)
}

///|
priv struct CrossfadeProgress {
  length : Int
  mut position : Int
}

///|
priv enum GraphSwapMode {
  Cut
  Crossfade(CrossfadeProgress)
}

///|
priv struct PreparedGraphSwap {
  old : @runtime.CompiledGraph
  next : @runtime.CompiledGraph
  mode : GraphSwapMode
  completion : GraphSwapState
}

///|
priv struct HotSwapGraph {
  mut state : GraphSwapState
  crossfade_samples : Int
  old_output : AudioBuffer
  new_output : AudioBuffer
  old_left : AudioBuffer
  old_right : AudioBuffer
  new_left : AudioBuffer
  new_right : AudioBuffer
}

///|
/// Block-boundary mono graph hot-swap wrapper for `Dsp`.
///
/// This first Phase 2 slice supports swapping between already-compiled mono
/// graphs with an optional equal-power crossfade. It does not migrate internal
/// node state between graphs.
struct DspHotSwap(HotSwapGraph)

///|
/// Block-boundary stereo graph hot-swap wrapper for `StereoDsp`.
///
/// This first stereo parity slice supports swapping between already-compiled
/// terminal-stereo graphs with an optional equal-power crossfade. It does not
/// migrate internal node state between graphs.
struct StereoDspHotSwap(HotSwapGraph)

///|
/// Failure reason for result-typed hot-swap queue APIs.
pub(all) enum HotSwapQueueError {
  SampleRateMismatch(Double, Double)
  BlockCapacityMismatch(Int, Int)
} derive(Debug)

///|
pub impl Show for HotSwapQueueError with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Queue a new compiled graph. A direct queue replaces the next graph during
/// a fade while retaining the currently playing graph as the old side.
fn HotSwapGraph::queue_swap_impl(
  self : HotSwapGraph,
  next : @runtime.CompiledGraph,
) -> Result[Unit, HotSwapQueueError] {
  let old = match self.state {
    Playing(active) => active
    Switching(prepared) => prepared.old
  }
  if old.compile_sample_rate() != next.compile_sample_rate() {
    return Err(
      HotSwapQueueError::SampleRateMismatch(
        old.compile_sample_rate(),
        next.compile_sample_rate(),
      ),
    )
  }
  let old_capacity = old.compiled_buffer_capacity()
  let next_capacity = next.compiled_buffer_capacity()
  if old_capacity != next_capacity {
    return Err(
      HotSwapQueueError::BlockCapacityMismatch(old_capacity, next_capacity),
    )
  }
  let mode = if self.crossfade_samples > 0 {
    GraphSwapMode::Crossfade({ length: self.crossfade_samples, position: 0, })
  } else {
    GraphSwapMode::Cut
  }
  self.state = GraphSwapState::Switching({
    old,
    next,
    mode,
    completion: GraphSwapState::Playing(next),
  })
  Ok(())
}

///|
/// Apply one runtime control message to the active and next graphs.
fn HotSwapGraph::apply_control_impl(
  self : HotSwapGraph,
  control : GraphControl,
) -> Result[Unit, GraphControlError] {
  match self.state {
    Playing(graph) =>
      graph_control_result_from_runtime(graph.apply_control_impl(control))
    Switching(prepared) =>
      graph_control_result_from_runtime(
        prepared.old.apply_controls_to_pair(prepared.next, [control]),
      )
  }
}

///|
/// Apply a batch of runtime control messages to the active and next graphs.
fn HotSwapGraph::apply_controls_impl(
  self : HotSwapGraph,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  match self.state {
    Playing(graph) =>
      graph_control_result_from_runtime(graph.apply_controls_impl(controls))
    Switching(prepared) =>
      graph_control_result_from_runtime(
        prepared.old.apply_controls_to_pair(prepared.next, controls),
      )
  }
}

///|
/// Create a hot-swap wrapper around an active mono compiled graph.
pub fn DspHotSwap::from_graph(
  active : @runtime.Dsp,
  crossfade_samples? : Int = 0,
) -> DspHotSwap {
  let clamped_crossfade = clamp_crossfade_samples(crossfade_samples)
  let capacity = active.compiled_buffer_capacity()
  DspHotSwap({
    state: GraphSwapState::Playing(active.raw_graph()),
    crossfade_samples: clamped_crossfade,
    old_output: AudioBuffer::filled(capacity),
    new_output: AudioBuffer::filled(capacity),
    old_left: AudioBuffer::filled(0),
    old_right: AudioBuffer::filled(0),
    new_left: AudioBuffer::filled(0),
    new_right: AudioBuffer::filled(0),
  })
}

///|
/// Queue a replacement graph for the next `process(...)` call.
///
/// Returns an error when the replacement graph is incompatible with the active
/// graph's compile-time sample rate or block capacity.
pub fn DspHotSwap::queue_swap(
  self : DspHotSwap,
  next : @runtime.Dsp,
) -> Result[Unit, HotSwapQueueError] {
  self.0.queue_swap_impl(next.raw_graph())
}

///|
pub fn DspHotSwap::apply_control(
  self : DspHotSwap,
  control : GraphControl,
) -> Result[Unit, GraphControlError] {
  self.0.apply_control_impl(control)
}

///|
pub fn DspHotSwap::apply_controls(
  self : DspHotSwap,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  self.0.apply_controls_impl(controls)
}

///|
/// Hot-swap stores bare runtime graph state; processing still goes through the
/// mono runtime wrapper so mono/stereo behavior stays owned by runtime.
fn process_mono_runtime_graph(
  graph : @runtime.CompiledGraph,
  context : DspContext,
  output : AudioBuffer,
) -> Unit {
  @runtime.Dsp::from_graph(graph).process(context, output)
}

///|
/// Hot-swap stores bare runtime graph state; processing still goes through the
/// stereo runtime wrapper so mono/stereo behavior stays owned by runtime.
fn process_stereo_runtime_graph(
  graph : @runtime.CompiledGraph,
  context : DspContext,
  left_output : AudioBuffer,
  right_output : AudioBuffer,
) -> Unit {
  @runtime.StereoDsp::from_graph(graph).process(
    context, left_output, right_output,
  )
}

///|
/// Shared crossfade loop for both mono and stereo hot-swap.
///
/// Applies equal-power crossfade sample-by-sample between old and new graphs'
/// scratch buffers, writing into the output buffers. The `is_stereo` flag
/// selects which scratch buffer set to read from (mono: old_output/new_output;
/// stereo: old_left/old_right/new_left/new_right).
fn HotSwapGraph::crossfade_block(
  self : HotSwapGraph,
  fade : CrossfadeProgress,
  output : AudioBuffer,
  left_output : AudioBuffer,
  right_output : AudioBuffer,
  is_stereo : Bool,
  sample_count : Int,
) -> Unit {
  if sample_count <= 0 {
    output.fill(0.0)
    if is_stereo {
      left_output.fill(0.0)
      right_output.fill(0.0)
    }
    return
  }
  for index in 0..<sample_count {
    let progress = hot_swap_progress(fade.position, fade.length)
    let old_gain = equal_power_old_gain(progress)
    let new_gain = equal_power_new_gain(progress)
    if is_stereo {
      left_output.set(
        index,
        apply_crossfade_sample(
          self.old_left.get(index),
          self.new_left.get(index),
          old_gain,
          new_gain,
        ),
      )
      right_output.set(
        index,
        apply_crossfade_sample(
          self.old_right.get(index),
          self.new_right.get(index),
          old_gain,
          new_gain,
        ),
      )
    } else {
      output.set(
        index,
        apply_crossfade_sample(
          self.old_output.get(index),
          self.new_output.get(index),
          old_gain,
          new_gain,
        ),
      )
    }
    fade.position += 1
  }
  if is_stereo {
    for index in sample_count..<left_output.length() {
      left_output.set(index, 0.0)
    }
    for index in sample_count..<right_output.length() {
      right_output.set(index, 0.0)
    }
  } else {
    for index in sample_count..<output.length() {
      output.set(index, 0.0)
    }
  }
}

///|
/// Process one block, crossfading between the active and pending graphs when a
/// swap is in flight.
pub fn DspHotSwap::process(
  self : DspHotSwap,
  context : DspContext,
  output : AudioBuffer,
) -> Unit {
  match self.0.state {
    Playing(graph) => process_mono_runtime_graph(graph, context, output)
    Switching(prepared) =>
      match prepared.mode {
        Cut => {
          let completion = prepared.completion
          self.0.state = completion
          process_mono_runtime_graph(prepared.next, context, output)
        }
        Crossfade(state) => {
          process_mono_runtime_graph(prepared.old, context, self.0.old_output)
          process_mono_runtime_graph(prepared.next, context, self.0.new_output)
          let sample_count = compiled_hot_swap_sample_count(
            context,
            output,
            self.0.old_output,
            self.0.new_output,
          )
          self.0.crossfade_block(
            state, output, output, output, false, sample_count,
          )
          if state.position >= state.length {
            self.0.state = prepared.completion
          }
        }
      }
  }
}

///|
/// Create a hot-swap wrapper around an active stereo compiled graph.
pub fn StereoDspHotSwap::from_graph(
  active : @runtime.StereoDsp,
  crossfade_samples? : Int = 0,
) -> StereoDspHotSwap {
  let clamped_crossfade = clamp_crossfade_samples(crossfade_samples)
  let capacity = active.compiled_buffer_capacity()
  StereoDspHotSwap({
    state: GraphSwapState::Playing(active.raw_graph()),
    crossfade_samples: clamped_crossfade,
    old_output: AudioBuffer::filled(0),
    new_output: AudioBuffer::filled(0),
    old_left: AudioBuffer::filled(capacity),
    old_right: AudioBuffer::filled(capacity),
    new_left: AudioBuffer::filled(capacity),
    new_right: AudioBuffer::filled(capacity),
  })
}

///|
/// Queue a replacement stereo graph for the next `process(...)` call.
///
/// Returns an error when the replacement graph is incompatible with the active
/// graph's compile-time sample rate or block capacity.
pub fn StereoDspHotSwap::queue_swap(
  self : StereoDspHotSwap,
  next : @runtime.StereoDsp,
) -> Result[Unit, HotSwapQueueError] {
  self.0.queue_swap_impl(next.raw_graph())
}

///|
pub fn StereoDspHotSwap::apply_control(
  self : StereoDspHotSwap,
  control : GraphControl,
) -> Result[Unit, GraphControlError] {
  self.0.apply_control_impl(control)
}

///|
pub fn StereoDspHotSwap::apply_controls(
  self : StereoDspHotSwap,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  self.0.apply_controls_impl(controls)
}

///|
/// Process one block, crossfading between the active and pending stereo graphs
/// when a swap is in flight.
pub fn StereoDspHotSwap::process(
  self : StereoDspHotSwap,
  context : DspContext,
  left_output : AudioBuffer,
  right_output : AudioBuffer,
) -> Unit {
  match self.0.state {
    Playing(graph) =>
      process_stereo_runtime_graph(graph, context, left_output, right_output)
    Switching(prepared) =>
      match prepared.mode {
        Cut => {
          self.0.state = prepared.completion
          process_stereo_runtime_graph(
            prepared.next,
            context,
            left_output,
            right_output,
          )
        }
        Crossfade(state) => {
          process_stereo_runtime_graph(
            prepared.old,
            context,
            self.0.old_left,
            self.0.old_right,
          )
          process_stereo_runtime_graph(
            prepared.next,
            context,
            self.0.new_left,
            self.0.new_right,
          )
          let sample_count = compiled_stereo_hot_swap_sample_count(
            context,
            left_output,
            right_output,
            self.0.old_left,
            self.0.old_right,
            self.0.new_left,
            self.0.new_right,
          )
          self.0.crossfade_block(
            state, left_output, left_output, right_output, true, sample_count,
          )
          if state.position >= state.length {
            self.0.state = prepared.completion
          }
        }
      }
  }
}

///|
fn clamp_crossfade_samples(crossfade_samples : Int) -> Int {
  if crossfade_samples > 0 {
    crossfade_samples
  } else {
    0
  }
}

///|
/// WHY a named function for a one-liner: the equal-power crossfade blend
/// formula is used in both mono and stereo mix_hot_swap_outputs. Naming it
/// makes the intent legible at both call sites and keeps the crossfade
/// math in one place if the blend curve ever changes.
fn apply_crossfade_sample(
  old_val : Double,
  new_val : Double,
  old_gain : Double,
  new_gain : Double,
) -> Double {
  old_val * old_gain + new_val * new_gain
}

///|
fn compiled_hot_swap_sample_count(
  context : DspContext,
  output : AudioBuffer,
  old_output : AudioBuffer,
  new_output : AudioBuffer,
) -> Int {
  let bounded = @dsp.effective_sample_count(context, output)
  if bounded < old_output.length() {
    if bounded < new_output.length() {
      bounded
    } else {
      new_output.length()
    }
  } else if old_output.length() < new_output.length() {
    old_output.length()
  } else {
    new_output.length()
  }
}

///|
fn hot_swap_progress(position : Int, crossfade_samples : Int) -> Double {
  if crossfade_samples <= 0 {
    1.0
  } else if position <= 0 {
    0.0
  } else if position >= crossfade_samples {
    1.0
  } else {
    position.to_double() / crossfade_samples.to_double()
  }
}

///|
fn equal_power_old_gain(progress : Double) -> Double {
  @math.cos(progress * 0.5 * @math.PI)
}

///|
fn equal_power_new_gain(progress : Double) -> Double {
  @math.sin(progress * 0.5 * @math.PI)
}

///|
fn compiled_stereo_sample_count(
  context : DspContext,
  left_output : AudioBuffer,
  right_output : AudioBuffer,
) -> Int {
  let output_length = if left_output.length() < right_output.length() {
    left_output.length()
  } else {
    right_output.length()
  }
  if output_length < context.block_size() {
    output_length
  } else {
    context.block_size()
  }
}

///|
fn compiled_stereo_hot_swap_sample_count(
  context : DspContext,
  left_output : AudioBuffer,
  right_output : AudioBuffer,
  old_left : AudioBuffer,
  old_right : AudioBuffer,
  new_left : AudioBuffer,
  new_right : AudioBuffer,
) -> Int {
  let bounded = compiled_stereo_sample_count(context, left_output, right_output)
  let old_length = if old_left.length() < old_right.length() {
    old_left.length()
  } else {
    old_right.length()
  }
  let new_length = if new_left.length() < new_right.length() {
    new_left.length()
  } else {
    new_right.length()
  }
  let bounded_old = if bounded < old_length { bounded } else { old_length }
  if bounded_old < new_length {
    bounded_old
  } else {
    new_length
  }
}
