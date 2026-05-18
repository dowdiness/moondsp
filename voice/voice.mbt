///|
using @dsp {type AudioBuffer, type DspContext}

///|
using @graph {
  type ControlBindingBuilder,
  type ControlBindingError,
  type ControlBindingMap,
  type CompiledDsp,
  type CompiledTemplate,
  type DspNode,
  type GraphControl,
  type GraphControlError,
}

///|
pub enum VoiceState {
  Idle
  Active
  Releasing
} derive(Eq, Debug)

///|
pub impl Show for VoiceState with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

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
} derive(Eq, Debug)

///|
pub impl Show for VoiceHandle with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub(all) enum BoundVoicePoolError {
  InvalidMaxVoices
  OrphanAdsr
  CompileRejected
  Binding(ControlBindingError)
} derive(Eq, Debug)

///|
pub impl Show for BoundVoicePoolError with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Failure modes for VoicePool construction and template replacement.
/// Mirrors BoundVoicePoolError minus the Binding(...) variant
/// (VoicePool has no bindings).
pub(all) enum VoicePoolError {
  InvalidMaxVoices
  OrphanAdsr
  CompileRejected
} derive(Eq, Debug)

///|
pub impl Show for VoicePoolError with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Lift a VoicePoolError to a BoundVoicePoolError. Used by
/// BoundVoicePool's constructors after delegating to
/// validate_voice_template (which now returns VoicePoolError after
/// the boundary-type migration per ADR-0010).
pub fn BoundVoicePoolError::from_voice_pool(
  e : VoicePoolError,
) -> BoundVoicePoolError {
  match e {
    VoicePoolError::InvalidMaxVoices => BoundVoicePoolError::InvalidMaxVoices
    VoicePoolError::OrphanAdsr => BoundVoicePoolError::OrphanAdsr
    VoicePoolError::CompileRejected => BoundVoicePoolError::CompileRejected
  }
}

///|
pub(all) enum VoiceControlError {
  InvalidVoiceHandle(VoiceHandle)
  Graph(GraphControlError)
} derive(Debug)

///|
pub impl Show for VoiceControlError with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
priv struct VoiceSlot {
  mut compiled : CompiledDsp?
  /// WHY per-slot snapshot: after set_template, the pool's
  /// adsr_authoring_indices changes. note_off must iterate the SAME
  /// indices used at note_on to gate the right ADSRs. Without this,
  /// gate_off would target wrong nodes (or miss freshly-orphaned ADSRs)
  /// if the new template differs.
  mut adsr_authoring_indices_snapshot : FixedArray[Int]
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
#alias(new)
fn VoiceSlot::VoiceSlot(block_size : Int) -> VoiceSlot {
  {
    compiled: None,
    adsr_authoring_indices_snapshot: FixedArray::make(0, 0),
    state: VoiceState::Idle,
    generation: 0,
    allocation_order: 0,
    // Center pan: cos(π/4) = sin(π/4) ≈ 0.7071
    pan_left_gain: @dsp.pan_left_gain(0.0),
    pan_right_gain: @dsp.pan_right_gain(0.0),
    mono_buffer: AudioBuffer::filled(block_size),
  }
}

///|
fn VoiceSlot::is_handle_valid(self : VoiceSlot, handle : VoiceHandle) -> Bool {
  handle.generation == self.generation
}

///|
fn VoiceSlot::update_pan(self : VoiceSlot, pan : Double) -> Unit {
  let clamped = pan.clamp(min=-1.0, max=1.0)
  self.pan_left_gain = @dsp.pan_left_gain(clamped)
  self.pan_right_gain = @dsp.pan_right_gain(clamped)
}

///|
/// Gate on or off all surviving ADSR nodes using authoring indices.
/// WHY authoring indices: CompiledDsp::gate_on/gate_off accept original
/// authoring indices and internally map through index_map (which
/// accounts for optimizer elimination + topological reordering).
fn gate_adsrs_at(
  compiled : CompiledDsp,
  authoring_indices : FixedArray[Int],
  gate_on : Bool,
) -> Unit {
  for n in 0..<authoring_indices.length() {
    let i = authoring_indices[n]
    if gate_on {
      ignore(compiled.gate_on(i))
    } else {
      ignore(compiled.gate_off(i))
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
  priv mut adsr_authoring_indices : FixedArray[Int]
  priv mut compiled_template : CompiledTemplate
  priv compile_context : DspContext
  priv mut next_allocation_order : Int
  priv max_voices : Int
  priv mut last_sanitized_count : Int
}

///|
fn validate_voice_template(
  compiled_template : CompiledTemplate,
  context : DspContext,
) -> Result[Unit, VoicePoolError] {
  if compiled_template.orphan_adsr_count() > 0 {
    return Err(VoicePoolError::OrphanAdsr)
  }
  // Sanity-compile to catch non-orphan problems (feedback cycle validation
  // etc.). Result discarded — per-voice slots compile their own on note_on.
  if CompiledDsp::compile(compiled_template, context) is None {
    return Err(VoicePoolError::CompileRejected)
  }
  Ok(())
}

///|
/// WHY test_compile: validates the template structurally (reachable Output
/// node, no invalid cycles, valid node indices) before accepting it. This
/// is a correctness gate so that per-voice note_on compiles can assume the
/// template is well-formed. The compiled result is discarded.
/// WHY orphan-ADSR reject: `VoicePool::note_on` calls `gate_on` for every
/// ADSR index in the template. If an ADSR is authored into the template but
/// not wired to Output, optimize_graph eliminates it, `gate_on` maps the
/// index to -1 and silently no-ops, and voices play with a 0 envelope —
/// a frustrating footgun. Reject at pool-construction time with a clear
/// failure rather than at note-trigger time with silent audio.
/// WHY adsr_authoring_indices snapshot: the pool's long-lived snapshot
/// (used by note_on to gate ADSRs, and refreshed by set_template) stores
/// only the indices needed for gating — not the full template — so the
/// caller's CompiledTemplate can be freely discarded after VoicePool::new
/// returns. optimize_graph does not mutate its input, so neither
/// CompiledTemplate::analyze nor CompiledDsp::compile disturbs the
/// caller's array.
pub fn VoicePool::new(
  compiled_template : CompiledTemplate,
  context : DspContext,
  max_voices? : Int = 32,
) -> Result[VoicePool, VoicePoolError] {
  if max_voices <= 0 {
    return Err(VoicePoolError::InvalidMaxVoices)
  }
  match validate_voice_template(compiled_template, context) {
    Err(error) => Err(error)
    Ok(_) => {
      let block_size = context.block_size()
      let slots = FixedArray::makei(max_voices, _ => VoiceSlot::new(block_size))
      Ok({
        slots,
        adsr_authoring_indices: compiled_template.adsr_authoring_indices(),
        compiled_template,
        compile_context: context,
        next_allocation_order: 0,
        max_voices,
        last_sanitized_count: 0,
      })
    }
  }
}

///|
pub fn VoicePool::set_template(
  self : VoicePool,
  compiled_template : CompiledTemplate,
) -> Result[Unit, VoicePoolError] {
  match validate_voice_template(compiled_template, self.compile_context) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  self.compiled_template = compiled_template
  self.adsr_authoring_indices = compiled_template.adsr_authoring_indices()
  Ok(())
}

///|
pub struct BoundVoicePool {
  priv pool : VoicePool
  priv mut bindings : ControlBindingMap
}

///|
pub fn BoundVoicePool::new(
  compiled_template : CompiledTemplate,
  context : DspContext,
  bindings : ControlBindingBuilder,
  max_voices? : Int = 32,
) -> Result[BoundVoicePool, BoundVoicePoolError] {
  let pool = match VoicePool::new(compiled_template, context, max_voices~) {
    Ok(pool) => pool
    Err(error) => return Err(BoundVoicePoolError::from_voice_pool(error))
  }
  match bindings.build(compiled_template) {
    Ok(bindings) => Ok({ pool, bindings })
    Err(error) => Err(BoundVoicePoolError::Binding(error))
  }
}

///|
pub fn BoundVoicePool::set_template(
  self : BoundVoicePool,
  compiled_template : CompiledTemplate,
  bindings : ControlBindingBuilder,
) -> Result[Unit, BoundVoicePoolError] {
  match validate_voice_template(compiled_template, self.pool.compile_context) {
    Err(error) => return Err(BoundVoicePoolError::from_voice_pool(error))
    Ok(_) => ()
  }
  let next_bindings = match bindings.build(compiled_template) {
    Ok(bindings) => bindings
    Err(error) => return Err(BoundVoicePoolError::Binding(error))
  }
  self.pool.adsr_authoring_indices = compiled_template.adsr_authoring_indices()
  self.pool.compiled_template = compiled_template
  self.bindings = next_bindings
  Ok(())
}

///|
pub fn BoundVoicePool::note_on_controls(
  self : BoundVoicePool,
  controls : Map[String, Double],
) -> VoiceHandle? {
  self.pool.note_on(self.bindings.resolve_controls(controls))
}

///|
pub fn BoundVoicePool::note_off(
  self : BoundVoicePool,
  handle : VoiceHandle,
) -> Bool {
  self.pool.note_off(handle)
}

///|
pub fn BoundVoicePool::kill(
  self : BoundVoicePool,
  handle : VoiceHandle,
) -> Bool {
  self.pool.kill(handle)
}

///|
pub fn BoundVoicePool::note_off_all(self : BoundVoicePool) -> Unit {
  self.pool.note_off_all()
}

///|
pub fn BoundVoicePool::set_voice_pan(
  self : BoundVoicePool,
  handle : VoiceHandle,
  pan : Double,
) -> Bool {
  self.pool.set_voice_pan(handle, pan)
}

///|
/// Validate a live control batch against an active voice without mutating it.
pub fn BoundVoicePool::validate_voice_controls_result(
  self : BoundVoicePool,
  handle : VoiceHandle,
  controls : Array[GraphControl],
) -> Result[Unit, VoiceControlError] {
  self.pool.validate_voice_controls_result(handle, controls)
}

///|
/// Apply one validated graph control to an already-sounding voice.
pub fn BoundVoicePool::apply_voice_control_result(
  self : BoundVoicePool,
  handle : VoiceHandle,
  control : GraphControl,
) -> Result[Unit, VoiceControlError] {
  self.pool.apply_voice_controls_result(handle, [control])
}

///|
/// Apply a graph-control batch transactionally to an already-sounding voice.
pub fn BoundVoicePool::apply_voice_controls_result(
  self : BoundVoicePool,
  handle : VoiceHandle,
  controls : Array[GraphControl],
) -> Result[Unit, VoiceControlError] {
  self.pool.apply_voice_controls_result(handle, controls)
}

///|
pub fn BoundVoicePool::voice_state(
  self : BoundVoicePool,
  handle : VoiceHandle,
) -> VoiceState {
  self.pool.voice_state(handle)
}

///|
pub fn BoundVoicePool::active_voice_count(self : BoundVoicePool) -> Int {
  self.pool.active_voice_count()
}

///|
pub fn BoundVoicePool::last_sanitized_count(self : BoundVoicePool) -> Int {
  self.pool.last_sanitized_count()
}

///|
pub fn BoundVoicePool::process(
  self : BoundVoicePool,
  context : DspContext,
  left : AudioBuffer,
  right : AudioBuffer,
) -> Unit {
  self.pool.process(context, left, right)
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
/// Number of non-finite samples replaced with 0.0 during the most recent
/// process() call, across both L and R output channels after mixdown.
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
    CompiledDsp::compile(self.compiled_template, self.compile_context) {
    Some(c) => c
    None => return None
  }
  // WHY transactional: if any param is invalid, the voice is not activated.
  // This prevents partially-configured voices with default/stale settings.
  if params.length() > 0 {
    if compiled.apply_controls(params) is Err(_) {
      return None
    }
  }
  gate_adsrs_at(compiled, self.adsr_authoring_indices, true)
  slot.compiled = Some(compiled)
  // WHY snapshot + copy: note_off needs the SAME indices that were used at
  // note_on to gate the right ADSRs. .copy() is load-bearing — without it,
  // a subsequent set_template would mutate this slot's snapshot and the
  // already-sounding voice would gate_off against the wrong index set.
  // See VoiceSlot.adsr_authoring_indices_snapshot doc comment.
  slot.adsr_authoring_indices_snapshot = self.adsr_authoring_indices.copy()
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
        // WHY adsr_authoring_indices_snapshot: uses the indices from
        // note_on time, not the current self.adsr_authoring_indices which
        // may have changed via set_template.
        Some(compiled) =>
          gate_adsrs_at(compiled, slot.adsr_authoring_indices_snapshot, false)
        None => ()
      }
      slot.state = VoiceState::Releasing
      true
    }
  }
}

///|
fn VoicePool::kill(self : VoicePool, handle : VoiceHandle) -> Bool {
  match self.resolve_slot(handle) {
    None => false
    Some(slot) => {
      if slot.state is VoiceState::Idle {
        return false
      }
      slot.compiled = None
      slot.state = VoiceState::Idle
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
          gate_adsrs_at(compiled, slot.adsr_authoring_indices_snapshot, false)
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
fn VoicePool::compiled_voice_result(
  self : VoicePool,
  handle : VoiceHandle,
) -> Result[CompiledDsp, VoiceControlError] {
  match self.resolve_slot(handle) {
    None => Err(VoiceControlError::InvalidVoiceHandle(handle))
    Some(slot) =>
      if slot.state is VoiceState::Idle {
        Err(VoiceControlError::InvalidVoiceHandle(handle))
      } else {
        match slot.compiled {
          Some(compiled) => Ok(compiled)
          None => Err(VoiceControlError::InvalidVoiceHandle(handle))
        }
      }
  }
}

///|
fn VoicePool::validate_voice_controls_result(
  self : VoicePool,
  handle : VoiceHandle,
  controls : Array[GraphControl],
) -> Result[Unit, VoiceControlError] {
  let compiled = match self.compiled_voice_result(handle) {
    Ok(compiled) => compiled
    Err(error) => return Err(error)
  }
  match compiled.validate_controls(controls) {
    Ok(_) => Ok(())
    Err(error) => Err(VoiceControlError::Graph(error))
  }
}

///|
fn VoicePool::apply_voice_controls_result(
  self : VoicePool,
  handle : VoiceHandle,
  controls : Array[GraphControl],
) -> Result[Unit, VoiceControlError] {
  let compiled = match self.compiled_voice_result(handle) {
    Ok(compiled) => compiled
    Err(error) => return Err(error)
  }
  match compiled.apply_controls(controls) {
    Ok(_) => Ok(())
    Err(error) => Err(VoiceControlError::Graph(error))
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
  let sample_count = if context.block_size() < left_output.length() {
    context.block_size()
  } else {
    left_output.length()
  }
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
  self.last_sanitized_count = @dsp.sanitize_buffer(left_output, sample_count) +
    @dsp.sanitize_buffer(right_output, sample_count)
}
