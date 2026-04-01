///|
/// Shared hot-swap state for both mono and stereo compiled graphs.
///
/// Mono uses `old_output`/`new_output` (stereo buffers are zero-length).
/// Stereo uses `old_left`/`old_right`/`new_left`/`new_right` (mono buffers
/// are zero-length). Zero-length rather than Option so crossfade code can
/// call buffer methods unconditionally without branching per sample.
priv struct HotSwapGraph {
  mut active : CompiledGraph
  mut pending : CompiledGraph?
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
/// Queue a new compiled graph, resetting the crossfade position.
///
/// Returns `false` when the replacement graph is incompatible with the active
/// graph's compile-time sample rate or block capacity.
fn HotSwapGraph::queue_swap_impl(
  self : HotSwapGraph,
  next : CompiledGraph,
) -> Bool {
  if self.active.compile_sample_rate != next.compile_sample_rate {
    return false
  }
  if self.active.compiled_buffer_capacity() != next.compiled_buffer_capacity() {
    return false
  }
  self.pending = Some(next)
  self.crossfade_position = 0
  true
}

///|
/// Apply one runtime control message to the active (and pending) graph.
fn HotSwapGraph::apply_control_impl(
  self : HotSwapGraph,
  control : GraphControl,
) -> Bool {
  match self.pending {
    None => self.active.apply_control_impl(control)
    Some(next) => {
      if !valid_hot_swap_control_graph(self.active, control) ||
        !valid_hot_swap_control_graph(next, control) {
        return false
      }
      ignore(self.active.apply_control_impl(control))
      ignore(next.apply_control_impl(control))
      true
    }
  }
}

///|
/// Apply a batch of runtime control messages to the active (and pending) graph.
fn HotSwapGraph::apply_controls_impl(
  self : HotSwapGraph,
  controls : Array[GraphControl],
) -> Bool {
  match self.pending {
    None => self.active.apply_controls_impl(controls)
    Some(next) => {
      if !valid_hot_swap_controls_graph(self.active, controls) ||
        !valid_hot_swap_controls_graph(next, controls) {
        return false
      }
      ignore(self.active.apply_controls_impl(controls))
      ignore(next.apply_controls_impl(controls))
      true
    }
  }
}

///|
/// Create a hot-swap wrapper around an active mono compiled graph.
pub fn CompiledDspHotSwap::from_graph(
  active : CompiledDsp,
  crossfade_samples? : Int = 0,
) -> CompiledDspHotSwap {
  let clamped_crossfade = clamp_crossfade_samples(crossfade_samples)
  let capacity = active.compiled_buffer_capacity()
  CompiledDspHotSwap({
    active: active.0,
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
/// Returns `false` when the replacement graph is incompatible with the active
/// graph's compile-time sample rate or block capacity.
pub fn CompiledDspHotSwap::queue_swap(
  self : CompiledDspHotSwap,
  next : CompiledDsp,
) -> Bool {
  self.0.queue_swap_impl(next.0)
}

///|
/// Apply one runtime control message to the active graph.
pub fn CompiledDspHotSwap::apply_control(
  self : CompiledDspHotSwap,
  control : GraphControl,
) -> Bool {
  self.0.apply_control_impl(control)
}

///|
/// Apply a batch of runtime control messages to the active graph.
pub fn CompiledDspHotSwap::apply_controls(
  self : CompiledDspHotSwap,
  controls : Array[GraphControl],
) -> Bool {
  self.0.apply_controls_impl(controls)
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
    None => CompiledDsp(self.0.active).process(context, output)
    Some(next) =>
      if self.0.crossfade_samples <= 0 {
        self.0.active = next
        self.0.pending = None
        self.0.crossfade_position = 0
        CompiledDsp(self.0.active).process(context, output)
      } else {
        CompiledDsp(self.0.active).process(context, self.0.old_output)
        CompiledDsp(next).process(context, self.0.new_output)
        self.mix_hot_swap_outputs(context, output)
        if self.0.crossfade_position >= self.0.crossfade_samples {
          self.0.active = next
          self.0.pending = None
          self.0.crossfade_position = 0
        }
      }
  }
}

///|
fn CompiledDspHotSwap::mix_hot_swap_outputs(
  self : CompiledDspHotSwap,
  context : DspContext,
  output : AudioBuffer,
) -> Unit {
  let sample_count = compiled_hot_swap_sample_count(
    context,
    output,
    self.0.old_output,
    self.0.new_output,
  )
  if sample_count <= 0 {
    output.fill(0.0)
    return
  }

  for index = 0; index < sample_count; index = index + 1 {
    let progress = hot_swap_progress(
      self.0.crossfade_position,
      self.0.crossfade_samples,
    )
    let old_gain = equal_power_old_gain(progress)
    let new_gain = equal_power_new_gain(progress)
    output.set(
      index,
      apply_crossfade_sample(
        self.0.old_output.get(index),
        self.0.new_output.get(index),
        old_gain,
        new_gain,
      ),
    )
    self.0.crossfade_position = self.0.crossfade_position + 1
  }

  for index = sample_count; index < output.length(); index = index + 1 {
    output.set(index, 0.0)
  }
}

///|
/// Create a hot-swap wrapper around an active stereo compiled graph.
pub fn CompiledStereoDspHotSwap::from_graph(
  active : CompiledStereoDsp,
  crossfade_samples? : Int = 0,
) -> CompiledStereoDspHotSwap {
  let clamped_crossfade = clamp_crossfade_samples(crossfade_samples)
  let capacity = active.compiled_buffer_capacity()
  CompiledStereoDspHotSwap({
    active: active.0,
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
/// Returns `false` when the replacement graph is incompatible with the active
/// graph's compile-time sample rate or block capacity.
pub fn CompiledStereoDspHotSwap::queue_swap(
  self : CompiledStereoDspHotSwap,
  next : CompiledStereoDsp,
) -> Bool {
  self.0.queue_swap_impl(next.0)
}

///|
/// Apply one runtime control message to the active stereo graph.
pub fn CompiledStereoDspHotSwap::apply_control(
  self : CompiledStereoDspHotSwap,
  control : GraphControl,
) -> Bool {
  self.0.apply_control_impl(control)
}

///|
/// Apply a batch of runtime control messages to the active stereo graph.
pub fn CompiledStereoDspHotSwap::apply_controls(
  self : CompiledStereoDspHotSwap,
  controls : Array[GraphControl],
) -> Bool {
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
      CompiledStereoDsp(self.0.active).process(
        context, left_output, right_output,
      )
    Some(next) =>
      if self.0.crossfade_samples <= 0 {
        self.0.active = next
        self.0.pending = None
        self.0.crossfade_position = 0
        CompiledStereoDsp(self.0.active).process(
          context, left_output, right_output,
        )
      } else {
        CompiledStereoDsp(self.0.active).process(
          context,
          self.0.old_left,
          self.0.old_right,
        )
        CompiledStereoDsp(next).process(
          context,
          self.0.new_left,
          self.0.new_right,
        )
        self.mix_hot_swap_outputs(context, left_output, right_output)
        if self.0.crossfade_position >= self.0.crossfade_samples {
          self.0.active = next
          self.0.pending = None
          self.0.crossfade_position = 0
        }
      }
  }
}

///|
fn CompiledStereoDspHotSwap::mix_hot_swap_outputs(
  self : CompiledStereoDspHotSwap,
  context : DspContext,
  left_output : AudioBuffer,
  right_output : AudioBuffer,
) -> Unit {
  let sample_count = compiled_stereo_hot_swap_sample_count(
    context,
    left_output,
    right_output,
    self.0.old_left,
    self.0.old_right,
    self.0.new_left,
    self.0.new_right,
  )
  if sample_count <= 0 {
    left_output.fill(0.0)
    right_output.fill(0.0)
    return
  }

  for index = 0; index < sample_count; index = index + 1 {
    let progress = hot_swap_progress(
      self.0.crossfade_position,
      self.0.crossfade_samples,
    )
    let old_gain = equal_power_old_gain(progress)
    let new_gain = equal_power_new_gain(progress)
    left_output.set(
      index,
      apply_crossfade_sample(
        self.0.old_left.get(index),
        self.0.new_left.get(index),
        old_gain,
        new_gain,
      ),
    )
    right_output.set(
      index,
      apply_crossfade_sample(
        self.0.old_right.get(index),
        self.0.new_right.get(index),
        old_gain,
        new_gain,
      ),
    )
    self.0.crossfade_position = self.0.crossfade_position + 1
  }

  for index = sample_count; index < left_output.length(); index = index + 1 {
    left_output.set(index, 0.0)
  }
  for index = sample_count; index < right_output.length(); index = index + 1 {
    right_output.set(index, 0.0)
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
  let bounded = effective_sample_count(context, output)
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
fn valid_hot_swap_control_graph(
  compiled : CompiledGraph,
  control : GraphControl,
) -> Bool {
  let simulated_nodes = FixedArray::makei(compiled.nodes.length(), index => {
    compiled.nodes[index]
  })
  valid_graph_control(compiled, simulated_nodes, control)
}

///|
fn valid_hot_swap_controls_graph(
  compiled : CompiledGraph,
  controls : Array[GraphControl],
) -> Bool {
  let simulated_nodes = FixedArray::makei(compiled.nodes.length(), index => {
    compiled.nodes[index]
  })
  for index = 0; index < controls.length(); index = index + 1 {
    if !valid_graph_control(compiled, simulated_nodes, controls[index]) {
      return false
    }
  }
  true
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
