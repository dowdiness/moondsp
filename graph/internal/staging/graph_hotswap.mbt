///|
/// Shared hot-swap state for both mono and stereo compiled graphs.
///
/// Mono uses `old_output`/`new_output` (stereo buffers are zero-length).
/// Stereo uses `old_left`/`old_right`/`new_left`/`new_right` (mono buffers
/// are zero-length). Zero-length rather than Option so crossfade code can
/// call buffer methods unconditionally without branching per sample.
priv struct HotSwapGraph {
  mut active : @runtime.CompiledGraph
  mut pending : @runtime.CompiledGraph?
  crossfade_samples : Int
  mut crossfade_position : Int
  old_output : AudioBuffer
  new_output : AudioBuffer
  old_left : AudioBuffer
  old_right : AudioBuffer
  new_left : AudioBuffer
  new_right : AudioBuffer
}

///|
/// Block-boundary mono graph hot-swap wrapper for `CompiledDsp`.
///
/// This first Phase 2 slice supports swapping between already-compiled mono
/// graphs with an optional equal-power crossfade. It does not migrate internal
/// node state between graphs.
struct CompiledDspHotSwap(HotSwapGraph)

///|
/// Block-boundary stereo graph hot-swap wrapper for `CompiledStereoDsp`.
///
/// This first stereo parity slice supports swapping between already-compiled
/// terminal-stereo graphs with an optional equal-power crossfade. It does not
/// migrate internal node state between graphs.
struct CompiledStereoDspHotSwap(HotSwapGraph)

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
/// Queue a new compiled graph, resetting the crossfade position.
fn HotSwapGraph::queue_swap_impl(
  self : HotSwapGraph,
  next : @runtime.CompiledGraph,
) -> Result[Unit, HotSwapQueueError] {
  if self.active.compile_sample_rate() != next.compile_sample_rate() {
    return Err(
      HotSwapQueueError::SampleRateMismatch(
        self.active.compile_sample_rate(),
        next.compile_sample_rate(),
      ),
    )
  }
  let active_capacity = self.active.compiled_buffer_capacity()
  let next_capacity = next.compiled_buffer_capacity()
  if active_capacity != next_capacity {
    return Err(
      HotSwapQueueError::BlockCapacityMismatch(active_capacity, next_capacity),
    )
  }
  self.pending = Some(next)
  self.crossfade_position = 0
  Ok(())
}

///|
/// Apply one runtime control message to the active (and pending) graph.
fn HotSwapGraph::apply_control_impl(
  self : HotSwapGraph,
  control : GraphControl,
) -> Result[Unit, GraphControlError] {
  match self.pending {
    None =>
      graph_control_result_from_runtime(self.active.apply_control_impl(control))
    Some(next) => {
      match valid_hot_swap_control_graph_result(self.active, control) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      match valid_hot_swap_control_graph_result(next, control) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      match
        graph_control_result_from_runtime(
          self.active.apply_control_impl(control),
        ) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      match
        graph_control_result_from_runtime(next.apply_control_impl(control)) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      Ok(())
    }
  }
}

///|
/// Apply a batch of runtime control messages to the active (and pending) graph.
fn HotSwapGraph::apply_controls_impl(
  self : HotSwapGraph,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  match self.pending {
    None =>
      graph_control_result_from_runtime(
        self.active.apply_controls_impl(controls),
      )
    Some(next) => {
      match valid_hot_swap_controls_graph_result(self.active, controls) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      match valid_hot_swap_controls_graph_result(next, controls) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      match
        graph_control_result_from_runtime(
          self.active.apply_controls_impl(controls),
        ) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      match
        graph_control_result_from_runtime(next.apply_controls_impl(controls)) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      Ok(())
    }
  }
}

///|
/// Create a hot-swap wrapper around an active mono compiled graph.
pub fn CompiledDspHotSwap::from_graph(
  active : @runtime.CompiledDsp,
  crossfade_samples? : Int = 0,
) -> CompiledDspHotSwap {
  let clamped_crossfade = clamp_crossfade_samples(crossfade_samples)
  let capacity = active.compiled_buffer_capacity()
  CompiledDspHotSwap({
    active: active.raw_graph(),
    pending: None,
    crossfade_samples: clamped_crossfade,
    crossfade_position: 0,
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
pub fn CompiledDspHotSwap::queue_swap(
  self : CompiledDspHotSwap,
  next : @runtime.CompiledDsp,
) -> Result[Unit, HotSwapQueueError] {
  self.0.queue_swap_impl(next.raw_graph())
}

///|
pub fn CompiledDspHotSwap::apply_control(
  self : CompiledDspHotSwap,
  control : GraphControl,
) -> Result[Unit, GraphControlError] {
  self.0.apply_control_impl(control)
}

///|
pub fn CompiledDspHotSwap::apply_controls(
  self : CompiledDspHotSwap,
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
  @runtime.CompiledDsp::from_graph(graph).process(context, output)
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
  @runtime.CompiledStereoDsp::from_graph(graph).process(
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
    let progress = hot_swap_progress(
      self.crossfade_position,
      self.crossfade_samples,
    )
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
    self.crossfade_position = self.crossfade_position + 1
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
pub fn CompiledDspHotSwap::process(
  self : CompiledDspHotSwap,
  context : DspContext,
  output : AudioBuffer,
) -> Unit {
  match self.0.pending {
    None => process_mono_runtime_graph(self.0.active, context, output)
    Some(next) =>
      if self.0.crossfade_samples <= 0 {
        self.0.active = next
        self.0.pending = None
        self.0.crossfade_position = 0
        process_mono_runtime_graph(self.0.active, context, output)
      } else {
        process_mono_runtime_graph(self.0.active, context, self.0.old_output)
        process_mono_runtime_graph(next, context, self.0.new_output)
        let sample_count = compiled_hot_swap_sample_count(
          context,
          output,
          self.0.old_output,
          self.0.new_output,
        )
        self.0.crossfade_block(output, output, output, false, sample_count)
        if self.0.crossfade_position >= self.0.crossfade_samples {
          self.0.active = next
          self.0.pending = None
          self.0.crossfade_position = 0
        }
      }
  }
}

///|
/// Create a hot-swap wrapper around an active stereo compiled graph.
pub fn CompiledStereoDspHotSwap::from_graph(
  active : @runtime.CompiledStereoDsp,
  crossfade_samples? : Int = 0,
) -> CompiledStereoDspHotSwap {
  let clamped_crossfade = clamp_crossfade_samples(crossfade_samples)
  let capacity = active.compiled_buffer_capacity()
  CompiledStereoDspHotSwap({
    active: active.raw_graph(),
    pending: None,
    crossfade_samples: clamped_crossfade,
    crossfade_position: 0,
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
pub fn CompiledStereoDspHotSwap::queue_swap(
  self : CompiledStereoDspHotSwap,
  next : @runtime.CompiledStereoDsp,
) -> Result[Unit, HotSwapQueueError] {
  self.0.queue_swap_impl(next.raw_graph())
}

///|
pub fn CompiledStereoDspHotSwap::apply_control(
  self : CompiledStereoDspHotSwap,
  control : GraphControl,
) -> Result[Unit, GraphControlError] {
  self.0.apply_control_impl(control)
}

///|
pub fn CompiledStereoDspHotSwap::apply_controls(
  self : CompiledStereoDspHotSwap,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  self.0.apply_controls_impl(controls)
}

///|
/// Process one block, crossfading between the active and pending stereo graphs
/// when a swap is in flight.
pub fn CompiledStereoDspHotSwap::process(
  self : CompiledStereoDspHotSwap,
  context : DspContext,
  left_output : AudioBuffer,
  right_output : AudioBuffer,
) -> Unit {
  match self.0.pending {
    None =>
      process_stereo_runtime_graph(
        self.0.active,
        context,
        left_output,
        right_output,
      )
    Some(next) =>
      if self.0.crossfade_samples <= 0 {
        self.0.active = next
        self.0.pending = None
        self.0.crossfade_position = 0
        process_stereo_runtime_graph(
          self.0.active,
          context,
          left_output,
          right_output,
        )
      } else {
        process_stereo_runtime_graph(
          self.0.active,
          context,
          self.0.old_left,
          self.0.old_right,
        )
        process_stereo_runtime_graph(
          next,
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
          left_output, left_output, right_output, true, sample_count,
        )
        if self.0.crossfade_position >= self.0.crossfade_samples {
          self.0.active = next
          self.0.pending = None
          self.0.crossfade_position = 0
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
fn valid_hot_swap_control_graph_result(
  compiled : @runtime.CompiledGraph,
  control : @model.GraphControl,
) -> Result[Unit, GraphControlError] {
  graph_control_result_from_runtime(compiled.validate_controls_impl([control]))
}

///|
fn valid_hot_swap_controls_graph_result(
  compiled : @runtime.CompiledGraph,
  controls : Array[@model.GraphControl],
) -> Result[Unit, GraphControlError] {
  graph_control_result_from_runtime(compiled.validate_controls_impl(controls))
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
