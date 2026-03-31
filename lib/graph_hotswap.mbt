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
fn valid_hot_swap_control(
  compiled : CompiledDsp,
  control : GraphControl,
) -> Bool {
  let simulated_nodes = FixedArray::makei(compiled.0.nodes.length(), index => {
    compiled.0.nodes[index]
  })
  valid_graph_control(compiled, simulated_nodes, control)
}

///|
fn valid_hot_swap_controls(
  compiled : CompiledDsp,
  controls : Array[GraphControl],
) -> Bool {
  let simulated_nodes = FixedArray::makei(compiled.0.nodes.length(), index => {
    compiled.0.nodes[index]
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

///|
/// Block-boundary stereo graph hot-swap wrapper for `CompiledStereoDsp`.
///
/// This first stereo parity slice supports swapping between already-compiled
/// terminal-stereo graphs with an optional equal-power crossfade. It does not
/// migrate internal node state between graphs.
struct CompiledStereoDspHotSwap {
  mut active : CompiledStereoDsp
  mut pending : CompiledStereoDsp?
  crossfade_samples : Int
  mut crossfade_position : Int
  old_left : AudioBuffer
  old_right : AudioBuffer
  new_left : AudioBuffer
  new_right : AudioBuffer
}

///|
/// Create a hot-swap wrapper around an active stereo compiled graph.
pub fn CompiledStereoDspHotSwap::from_graph(
  active : CompiledStereoDsp,
  crossfade_samples? : Int = 0,
) -> CompiledStereoDspHotSwap {
  let clamped_crossfade = if crossfade_samples > 0 {
    crossfade_samples
  } else {
    0
  }
  let capacity = active.compiled_buffer_capacity()
  make_compiled_stereo_dsp_hot_swap(
    active,
    None,
    clamped_crossfade,
    0,
    AudioBuffer::filled(capacity),
    AudioBuffer::filled(capacity),
    AudioBuffer::filled(capacity),
    AudioBuffer::filled(capacity),
  )
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
/// Apply one runtime control message to the active stereo graph.
pub fn CompiledStereoDspHotSwap::apply_control(
  self : CompiledStereoDspHotSwap,
  control : GraphControl,
) -> Bool {
  match self.pending {
    None => self.active.apply_control(control)
    Some(next) => {
      if !valid_hot_swap_control_stereo(self.active, control) ||
        !valid_hot_swap_control_stereo(next, control) {
        return false
      }
      ignore(self.active.apply_control(control))
      ignore(next.apply_control(control))
      true
    }
  }
}

///|
/// Apply a batch of runtime control messages to the active stereo graph.
pub fn CompiledStereoDspHotSwap::apply_controls(
  self : CompiledStereoDspHotSwap,
  controls : Array[GraphControl],
) -> Bool {
  match self.pending {
    None => self.active.apply_controls(controls)
    Some(next) => {
      if !valid_hot_swap_controls_stereo(self.active, controls) ||
        !valid_hot_swap_controls_stereo(next, controls) {
        return false
      }
      ignore(self.active.apply_controls(controls))
      ignore(next.apply_controls(controls))
      true
    }
  }
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
  match self.pending {
    None => self.active.process(context, left_output, right_output)
    Some(next) =>
      if self.crossfade_samples <= 0 {
        self.active = next
        self.pending = None
        self.crossfade_position = 0
        self.active.process(context, left_output, right_output)
      } else {
        self.active.process(context, self.old_left, self.old_right)
        next.process(context, self.new_left, self.new_right)
        self.mix_hot_swap_outputs(context, left_output, right_output)
        if self.crossfade_position >= self.crossfade_samples {
          self.active = next
          self.pending = None
          self.crossfade_position = 0
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
    self.old_left,
    self.old_right,
    self.new_left,
    self.new_right,
  )
  if sample_count <= 0 {
    left_output.fill(0.0)
    right_output.fill(0.0)
    return
  }

  for index = 0; index < sample_count; index = index + 1 {
    let progress = hot_swap_progress(
      self.crossfade_position,
      self.crossfade_samples,
    )
    let old_gain = equal_power_old_gain(progress)
    let new_gain = equal_power_new_gain(progress)
    left_output.set(
      index,
      self.old_left.get(index) * old_gain + self.new_left.get(index) * new_gain,
    )
    right_output.set(
      index,
      self.old_right.get(index) * old_gain +
      self.new_right.get(index) * new_gain,
    )
    self.crossfade_position = self.crossfade_position + 1
  }

  for index = sample_count; index < left_output.length(); index = index + 1 {
    left_output.set(index, 0.0)
  }
  for index = sample_count; index < right_output.length(); index = index + 1 {
    right_output.set(index, 0.0)
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

///|
fn valid_hot_swap_control_stereo(
  compiled : CompiledStereoDsp,
  control : GraphControl,
) -> Bool {
  let simulated_nodes = FixedArray::makei(compiled.nodes.length(), index => {
    compiled.nodes[index]
  })
  valid_graph_control_stereo(compiled, simulated_nodes, control)
}

///|
fn valid_hot_swap_controls_stereo(
  compiled : CompiledStereoDsp,
  controls : Array[GraphControl],
) -> Bool {
  let simulated_nodes = FixedArray::makei(compiled.nodes.length(), index => {
    compiled.nodes[index]
  })
  for index = 0; index < controls.length(); index = index + 1 {
    if !valid_graph_control_stereo(compiled, simulated_nodes, controls[index]) {
      return false
    }
  }
  true
}

///|
fn make_compiled_stereo_dsp_hot_swap(
  active : CompiledStereoDsp,
  pending : CompiledStereoDsp?,
  crossfade_samples : Int,
  crossfade_position : Int,
  old_left : AudioBuffer,
  old_right : AudioBuffer,
  new_left : AudioBuffer,
  new_right : AudioBuffer,
) -> CompiledStereoDspHotSwap {
  {
    active,
    pending,
    crossfade_samples,
    crossfade_position,
    old_left,
    old_right,
    new_left,
    new_right,
  }
}
