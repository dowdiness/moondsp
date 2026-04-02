///|
pub enum VoiceState {
  Idle
  Active
  Releasing
} derive(Eq, Show)

///|
/// Generation-tagged voice handle.
/// WHY generation counter: slot indices are reused after voice stealing.
/// Without a generation tag, a stale handle from a stolen note could
/// accidentally gate_off or pan the wrong voice occupying that slot.
/// Every note_on increments the slot's generation; all operations compare
/// the handle's generation against the slot's current generation.
pub struct VoiceHandle {
  slot : Int
  generation : Int
} derive(Eq, Show)

///|
priv struct VoiceSlot {
  mut compiled : CompiledDsp?
  /// WHY per-slot template snapshot: after set_template, the pool's template
  /// changes. note_off must iterate the SAME template that was used at
  /// note_on time to find the correct ADSR node indices. Without this,
  /// gate_off would target wrong nodes if the new template has ADSRs at
  /// different positions.
  mut template_snapshot : Array[DspNode]
  mut state : VoiceState
  mut generation : Int
  mut allocation_order : Int
  /// WHY cached gains instead of a pan field: avoids 2 trig calls (cos + sin)
  /// per voice per block in process(). Updated only when pan changes
  /// (control-rate), not per block. The pan position is fully encoded by the
  /// gain pair — no separate pan field needed.
  mut pan_left_gain : Double
  mut pan_right_gain : Double
  mono_buffer : AudioBuffer
}

///|
fn VoiceSlot::new(block_size : Int) -> VoiceSlot {
  {
    compiled: None,
    template_snapshot: [],
    state: VoiceState::Idle,
    generation: 0,
    allocation_order: 0,
    // Center pan: cos(π/4) = sin(π/4) ≈ 0.7071
    pan_left_gain: feedback_pan_left_gain(0.0),
    pan_right_gain: feedback_pan_right_gain(0.0),
    mono_buffer: AudioBuffer::filled(block_size),
  }
}

///|
fn VoiceSlot::is_handle_valid(self : VoiceSlot, handle : VoiceHandle) -> Bool {
  handle.generation == self.generation
}

///|
/// WHY feedback_pan_*: these are the engine's existing equal-power pan
/// functions (cos/sin law with clamping and NaN safety). The "feedback"
/// prefix is a historical artifact — they implement standard constant-power
/// panning reused here for voice-level mixdown.
fn VoiceSlot::update_pan(self : VoiceSlot, pan : Double) -> Unit {
  let clamped = pan.clamp(min=-1.0, max=1.0)
  self.pan_left_gain = feedback_pan_left_gain(clamped)
  self.pan_right_gain = feedback_pan_right_gain(clamped)
}

///|
/// Gate on or off all ADSR nodes in a compiled graph using authoring indices.
/// WHY authoring indices: CompiledDsp::gate_on/gate_off accept original
/// authoring indices and internally map through index_map (which accounts
/// for optimizer elimination + topological reordering).
fn gate_all_adsrs(
  compiled : CompiledDsp,
  template : Array[DspNode],
  gate_on : Bool,
) -> Unit {
  for i = 0; i < template.length(); i = i + 1 {
    if template[i].kind is Adsr {
      if gate_on {
        ignore(compiled.gate_on(i))
      } else {
        ignore(compiled.gate_off(i))
      }
    }
  }
}

///|
/// Resolve a VoiceHandle to the slot it references, returning None if the
/// handle is out of bounds or stale (slot was stolen and reused).
fn VoicePool::resolve_slot(
  self : VoicePool,
  handle : VoiceHandle,
) -> VoiceSlot? {
  if handle.slot < 0 || handle.slot >= self.max_voices {
    return None
  }
  let slot = self.slots[handle.slot]
  if !slot.is_handle_valid(handle) {
    return None
  }
  Some(slot)
}

///|
pub struct VoicePool {
  priv slots : FixedArray[VoiceSlot]
  priv mut template : Array[DspNode]
  priv compile_context : DspContext
  priv mut next_allocation_order : Int
  priv max_voices : Int
  priv mut last_sanitized_count : Int
}

///|
/// WHY test_compile: validates the template structurally (reachable Output
/// node, no invalid cycles, valid node indices) before accepting it. This
/// is a correctness gate so that per-voice note_on compiles can assume the
/// template is well-formed. The compiled result is discarded.
/// WHY template.copy(): the pool must own a stable snapshot. compile()
/// internally calls optimize_graph which may consume or mutate the array.
pub fn VoicePool::new(
  template : Array[DspNode],
  context : DspContext,
  max_voices? : Int = 32,
) -> VoicePool? {
  if max_voices <= 0 {
    return None
  }
  let test_compile = CompiledDsp::compile(template, context)
  if test_compile is None {
    return None
  }
  let block_size = context.block_size()
  let slots = FixedArray::makei(max_voices, _ => VoiceSlot::new(block_size))
  Some({
    slots,
    template: template.copy(),
    compile_context: context,
    next_allocation_order: 0,
    max_voices,
    last_sanitized_count: 0,
  })
}

///|
pub fn VoicePool::set_template(
  self : VoicePool,
  template : Array[DspNode],
) -> Bool {
  let test_compile = CompiledDsp::compile(template, self.compile_context)
  if test_compile is None {
    return false
  }
  self.template = template.copy()
  true
}

///|
pub fn VoicePool::active_voice_count(self : VoicePool) -> Int {
  let mut count = 0
  for i = 0; i < self.max_voices; i = i + 1 {
    if !(self.slots[i].state is VoiceState::Idle) {
      count = count + 1
    }
  }
  count
}

///|
pub fn VoicePool::last_sanitized_count(self : VoicePool) -> Int {
  self.last_sanitized_count
}

///|
/// WHY three-tier priority: Idle slots are free — no audible cost.
/// Releasing voices are already fading out, so stealing them causes minimal
/// pop. Active voices are a last resort — cutting them is audible but
/// unavoidable at full polyphony. Within each tier, oldest-first ensures
/// the most recently played notes survive longest.
fn VoicePool::find_slot(self : VoicePool) -> Int {
  // Priority 1: any idle slot (free)
  for i = 0; i < self.max_voices; i = i + 1 {
    if self.slots[i].state is VoiceState::Idle {
      return i
    }
  }
  // Priority 2: oldest releasing voice (least audible pop)
  let mut best_releasing = -1
  let mut best_releasing_order = @int.MAX_VALUE
  for i = 0; i < self.max_voices; i = i + 1 {
    if self.slots[i].state is VoiceState::Releasing &&
      self.slots[i].allocation_order < best_releasing_order {
      best_releasing = i
      best_releasing_order = self.slots[i].allocation_order
    }
  }
  if best_releasing >= 0 {
    return best_releasing
  }
  // Priority 3: oldest active voice (audible cut, last resort)
  let mut best_active = 0
  let mut best_active_order = @int.MAX_VALUE
  for i = 0; i < self.max_voices; i = i + 1 {
    if self.slots[i].allocation_order < best_active_order {
      best_active = i
      best_active_order = self.slots[i].allocation_order
    }
  }
  best_active
}

///|
/// Reassign allocation_order values to a dense sequential range (0, 1, 2, ...)
/// preserving relative ordering. Called when next_allocation_order is about to
/// overflow. This keeps the oldest-first voice-stealing heuristic correct.
fn VoicePool::compact_allocation_orders(self : VoicePool) -> Unit {
  // Collect (slot_index, allocation_order) pairs for non-idle slots
  let pairs : Array[(Int, Int)] = []
  for i = 0; i < self.max_voices; i = i + 1 {
    if !(self.slots[i].state is VoiceState::Idle) {
      pairs.push((i, self.slots[i].allocation_order))
    }
  }
  // Sort by allocation_order ascending to preserve relative age
  pairs.sort_by(fn(a, b) { a.1.compare(b.1) })
  // Reassign sequential orders starting from 0
  for j = 0; j < pairs.length(); j = j + 1 {
    self.slots[pairs[j].0].allocation_order = j
  }
  // Set pool counter to next available value
  self.next_allocation_order = pairs.length()
}

///|
pub fn VoicePool::note_on(
  self : VoicePool,
  params : Array[GraphControl],
) -> VoiceHandle? {
  let slot_index = self.find_slot()
  let slot = self.slots[slot_index]
  let compiled = match
    CompiledDsp::compile(self.template, self.compile_context) {
    Some(c) => c
    None => return None
  }
  // WHY transactional: if any param is invalid, the voice is not activated.
  // This prevents partially-configured voices with default/stale settings.
  if params.length() > 0 {
    if !compiled.apply_controls(params) {
      return None
    }
  }
  gate_all_adsrs(compiled, self.template, true)
  slot.compiled = Some(compiled)
  // WHY snapshot: note_off needs the SAME template to find ADSR indices.
  // See VoiceSlot.template_snapshot doc comment for the full rationale.
  slot.template_snapshot = self.template
  slot.state = VoiceState::Active
  // WHY overflow guard on generation: after 2^31 increments the counter
  // wraps negative, which could revalidate stale VoiceHandles. Resetting
  // to 0 safely invalidates all outstanding handles for this slot.
  slot.generation = if slot.generation >= @int.MAX_VALUE - 1 {
    0
  } else {
    slot.generation + 1
  }
  slot.allocation_order = self.next_allocation_order
  // WHY overflow guard on allocation_order: if the pool-wide counter wraps
  // negative, the oldest-first stealing heuristic breaks. Compact all slot
  // orders into a dense sequential range preserving relative order.
  if self.next_allocation_order >= @int.MAX_VALUE - 1 {
    self.compact_allocation_orders()
  } else {
    self.next_allocation_order = self.next_allocation_order + 1
  }
  Some({ slot: slot_index, generation: slot.generation })
}

///|
pub fn VoicePool::note_off(self : VoicePool, handle : VoiceHandle) -> Bool {
  match self.resolve_slot(handle) {
    None => false
    Some(slot) => {
      if slot.state is VoiceState::Idle {
        return false
      }
      match slot.compiled {
        // WHY template_snapshot: uses the template from note_on time, not
        // the current self.template which may have changed via set_template.
        Some(compiled) =>
          gate_all_adsrs(compiled, slot.template_snapshot, false)
        None => ()
      }
      slot.state = VoiceState::Releasing
      true
    }
  }
}

///|
pub fn VoicePool::note_off_all(self : VoicePool) -> Unit {
  for i = 0; i < self.max_voices; i = i + 1 {
    let slot = self.slots[i]
    if slot.state is VoiceState::Active {
      match slot.compiled {
        Some(compiled) =>
          gate_all_adsrs(compiled, slot.template_snapshot, false)
        None => ()
      }
      slot.state = VoiceState::Releasing
    }
  }
}

///|
pub fn VoicePool::set_voice_pan(
  self : VoicePool,
  handle : VoiceHandle,
  pan : Double,
) -> Bool {
  match self.resolve_slot(handle) {
    None => false
    Some(slot) => {
      slot.update_pan(pan)
      true
    }
  }
}

///|
pub fn VoicePool::voice_state(
  self : VoicePool,
  handle : VoiceHandle,
) -> VoiceState {
  match self.resolve_slot(handle) {
    None => VoiceState::Idle
    Some(slot) => slot.state
  }
}

///|
pub fn VoicePool::process(
  self : VoicePool,
  context : DspContext,
  left_output : AudioBuffer,
  right_output : AudioBuffer,
) -> Unit {
  for i = 0; i < self.max_voices; i = i + 1 {
    let slot = self.slots[i]
    if slot.state is VoiceState::Idle {
      continue i + 1
    }
    match slot.compiled {
      None => {
        slot.state = VoiceState::Idle
        continue i + 1
      }
      Some(compiled) => {
        compiled.process(context, slot.mono_buffer)
        // WHY cached gains: pan_left_gain/pan_right_gain are updated only
        // when set_voice_pan is called (control-rate), not here (audio-rate).
        // This avoids 2 trig calls per voice per block.
        let left_gain = slot.pan_left_gain
        let right_gain = slot.pan_right_gain
        let sample_count = if context.block_size() < left_output.length() {
          context.block_size()
        } else {
          left_output.length()
        }
        for s = 0; s < sample_count; s = s + 1 {
          let mono = slot.mono_buffer.get(s)
          left_output.set(s, left_output.get(s) + mono * left_gain)
          right_output.set(s, right_output.get(s) + mono * right_gain)
        }
        if slot.state is VoiceState::Releasing && compiled.is_voice_finished() {
          slot.state = VoiceState::Idle
          slot.compiled = None
        }
      }
    }
  }
  let sample_count = if context.block_size() < left_output.length() {
    context.block_size()
  } else {
    left_output.length()
  }
  self.last_sanitized_count = sanitize_buffer(left_output, sample_count) +
    sanitize_buffer(right_output, sample_count)
}
