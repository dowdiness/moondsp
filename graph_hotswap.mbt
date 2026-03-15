///|
/// Block-boundary mono graph hot-swap wrapper for `CompiledDsp`.
///
/// This first Phase 2 slice supports swapping between already-compiled mono
/// graphs with an optional equal-power crossfade. It does not migrate internal
/// node state between graphs.
struct CompiledDspHotSwap {
  mut active : CompiledDsp
  mut pending : CompiledDsp?
  crossfade_samples : Int
  mut crossfade_position : Int
  old_output : AudioBuffer
  new_output : AudioBuffer
}

///|
/// Create a hot-swap wrapper around an active mono compiled graph.
pub fn CompiledDspHotSwap::from_graph(
  active : CompiledDsp,
  crossfade_samples? : Int = 0,
) -> CompiledDspHotSwap {
  let clamped_crossfade = if crossfade_samples > 0 {
    crossfade_samples
  } else {
    0
  }
  let capacity = active.compiled_buffer_capacity()
  make_compiled_dsp_hot_swap(
    active,
    None,
    clamped_crossfade,
    0,
    AudioBuffer::filled(capacity),
    AudioBuffer::filled(capacity),
  )
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
/// Apply one runtime control message to the active graph.
pub fn CompiledDspHotSwap::apply_control(
  self : CompiledDspHotSwap,
  control : GraphControl,
) -> Bool {
  match self.pending {
    None => self.active.apply_control(control)
    Some(next) => {
      if !valid_hot_swap_control(self.active, control) ||
        !valid_hot_swap_control(next, control) {
        return false
      }
      ignore(self.active.apply_control(control))
      ignore(next.apply_control(control))
      true
    }
  }
}

///|
/// Apply a batch of runtime control messages to the active graph.
pub fn CompiledDspHotSwap::apply_controls(
  self : CompiledDspHotSwap,
  controls : Array[GraphControl],
) -> Bool {
  match self.pending {
    None => self.active.apply_controls(controls)
    Some(next) => {
      if !valid_hot_swap_controls(self.active, controls) ||
        !valid_hot_swap_controls(next, controls) {
        return false
      }
      ignore(self.active.apply_controls(controls))
      ignore(next.apply_controls(controls))
      true
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
  match self.pending {
    None => self.active.process(context, output)
    Some(next) =>
      if self.crossfade_samples <= 0 {
        self.active = next
        self.pending = None
        self.crossfade_position = 0
        self.active.process(context, output)
      } else {
        self.active.process(context, self.old_output)
        next.process(context, self.new_output)
        self.mix_hot_swap_outputs(context, output)
        if self.crossfade_position >= self.crossfade_samples {
          self.active = next
          self.pending = None
          self.crossfade_position = 0
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
    self.old_output,
    self.new_output,
  )
  if sample_count <= 0 {
    output.fill(0.0)
    return
  }

  for index = 0; index < sample_count; index = index + 1 {
    let progress = hot_swap_progress(
      self.crossfade_position,
      self.crossfade_samples,
    )
    let old_gain = equal_power_old_gain(progress)
    let new_gain = equal_power_new_gain(progress)
    output.set(
      index,
      self.old_output.get(index) * old_gain +
      self.new_output.get(index) * new_gain,
    )
    self.crossfade_position = self.crossfade_position + 1
  }

  for index = sample_count; index < output.length(); index = index + 1 {
    output.set(index, 0.0)
  }
}

///|
fn compiled_hot_swap_sample_count(
  context : DspContext,
  output : AudioBuffer,
  old_output : AudioBuffer,
  new_output : AudioBuffer,
) -> Int {
  let bounded = compiled_sample_count(context, output)
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
fn valid_hot_swap_control(
  compiled : CompiledDsp,
  control : GraphControl,
) -> Bool {
  let simulated_nodes = FixedArray::makei(compiled.nodes.length(), index => {
    compiled.nodes[index]
  })
  valid_graph_control(compiled, simulated_nodes, control)
}

///|
fn valid_hot_swap_controls(
  compiled : CompiledDsp,
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
fn make_compiled_dsp_hot_swap(
  active : CompiledDsp,
  pending : CompiledDsp?,
  crossfade_samples : Int,
  crossfade_position : Int,
  old_output : AudioBuffer,
  new_output : AudioBuffer,
) -> CompiledDspHotSwap {
  {
    active,
    pending,
    crossfade_samples,
    crossfade_position,
    old_output,
    new_output,
  }
}
