///|
using @dsp {type AudioBuffer, type DspContext}

///|
using @graph {
  type ControlBindingBuilder,
  type ControlBindingError,
  type ControlBindingMap,
  type CompiledDsp,
  type CompiledTemplate,
  type GraphControl,
  type GraphControlError,
  type GraphParamSlot,
}

///|
pub enum VoiceState {
  Idle
  Active
  Releasing
} derive(Eq, Debug)

///|
pub impl Show for VoiceState with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
const VOICE_HANDLE_PACK_FACTOR : Int64 = 2147483648L

///|
/// Generation-tagged voice handle.
/// WHY generation counter: slot indices are reused after voice stealing.
/// Without a generation tag, a stale handle from a stolen note could
/// accidentally gate_off or pan the wrong voice occupying that slot.
/// Every note_on increments the slot's generation; all operations compare
/// the handle's generation against the slot's current generation.
#valtype
pub struct VoiceHandle {
  slot : Int
  generation : Int
} derive(Eq, Debug)

///|
pub impl Show for VoiceHandle with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Construct a handle from primitive parts for host-side fixed storage.
pub fn VoiceHandle::from_parts(slot~ : Int, generation~ : Int) -> VoiceHandle {
  { slot, generation }
}

///|
fn VoiceHandle::pack_parts(slot~ : Int, generation~ : Int) -> Int64 {
  slot.to_int64() * VOICE_HANDLE_PACK_FACTOR + generation.to_int64()
}

///|
pub fn VoiceHandle::packed_slot(handle_id : Int64) -> Int {
  (handle_id / VOICE_HANDLE_PACK_FACTOR).to_int()
}

///|
pub fn VoiceHandle::packed_generation(handle_id : Int64) -> Int {
  (handle_id % VOICE_HANDLE_PACK_FACTOR).to_int()
}

///|
pub(all) enum BoundVoicePoolError {
  InvalidMaxVoices
  OrphanAdsr
  CompileRejected
  Binding(ControlBindingError)
} derive(Eq, Debug)

///|
pub impl Show for BoundVoicePoolError with fn output(self, logger) {
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
pub impl Show for VoicePoolError with fn output(self, logger) {
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
pub impl Show for VoiceControlError with fn output(self, logger) {
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
  mut template_generation : Int
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
    template_generation: -1,
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
/// WHY unwrap: VoicePool construction rejects orphan ADSRs (see
/// validate_voice_template) and adsr_authoring_indices is a snapshot of
/// surviving ADSR indices only. Gate operations on those indices must
/// succeed; an Err here means an invariant has been violated.
fn gate_adsrs_at_bool(
  compiled : CompiledDsp,
  authoring_indices : FixedArray[Int],
  gate_on : Bool,
) -> Bool {
  for n in 0..<authoring_indices.length() {
    let i = authoring_indices[n]
    let ok = if gate_on {
      compiled.gate_on_bool(i)
    } else {
      compiled.gate_off_bool(i)
    }
    if !ok {
      return false
    }
  }
  true
}

///|
fn gate_adsrs_at(
  compiled : CompiledDsp,
  authoring_indices : FixedArray[Int],
  gate_on : Bool,
) -> Unit {
  if !gate_adsrs_at_bool(compiled, authoring_indices, gate_on) {
    abort("voice ADSR gate invariant violated")
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
  priv mut template_generation : Int
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
/// ADSR index in the template. If an ADSR is authored into the template
/// but not wired to Output, optimize_graph eliminates it and `gate_on`
/// would now return `Err(OrphanNode)`. Rejecting at pool-construction
/// time keeps the per-note `gate_adsrs_at(...)` loop infallible (it can
/// `.unwrap()`) and surfaces the misconfiguration at the earliest
/// observable point rather than at every note trigger.
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
      for i in 0..<max_voices {
        match CompiledDsp::compile(compiled_template, context) {
          Some(compiled) => {
            slots[i].compiled = Some(compiled)
            slots[i].template_generation = 0
          }
          None => return Err(VoicePoolError::CompileRejected)
        }
      }
      Ok({
        slots,
        adsr_authoring_indices: compiled_template.adsr_authoring_indices(),
        compiled_template,
        compile_context: context,
        next_allocation_order: 0,
        template_generation: 0,
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
  self.template_generation = self.next_template_generation()
  Ok(())
}

///|
fn VoicePool::next_template_generation(self : VoicePool) -> Int {
  if self.template_generation >= @int.MAX_VALUE - 1 {
    for i in 0..<self.max_voices {
      self.slots[i].template_generation = -1
    }
    0
  } else {
    self.template_generation + 1
  }
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
  match self.pool.set_template(compiled_template) {
    Err(error) => return Err(BoundVoicePoolError::from_voice_pool(error))
    Ok(_) => ()
  }
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
/// Trigger a voice with an already-materialized graph-control batch.
/// This bypasses string-key control-map resolution while preserving the same
/// transactional semantics as `VoicePool::note_on`.
pub fn BoundVoicePool::note_on_graph_controls(
  self : BoundVoicePool,
  controls : Array[GraphControl],
) -> VoiceHandle? {
  self.pool.note_on(controls)
}

///|
/// Trigger a voice from four fixed, prevalidated parameter updates and set its
/// pan before it becomes visible to callers. This is for host integrations that
/// validate a stable template outside the audio callback and need a non-allocating
/// note-on path. Returns a negative id on rejection; dynamic graph-control callers
/// should use `note_on_graph_controls`.
pub fn BoundVoicePool::note_on_prevalidated_params4_id(
  self : BoundVoicePool,
  node0 : Int,
  slot0 : GraphParamSlot,
  value0 : Double,
  node1 : Int,
  slot1 : GraphParamSlot,
  value1 : Double,
  node2 : Int,
  slot2 : GraphParamSlot,
  value2 : Double,
  node3 : Int,
  slot3 : GraphParamSlot,
  value3 : Double,
  pan : Double,
) -> Int64 {
  self.pool.note_on_prevalidated_params4_id(
    node0, slot0, value0, node1, slot1, value1, node2, slot2, value2, node3, slot3,
    value3, pan,
  )
}

///|
/// Deprecated compatibility wrapper. Use `note_off_result` to observe stale
/// or invalid handles as `VoiceControlError` values.
#deprecated("Use BoundVoicePool::note_off_result(handle) to observe VoiceControlError")
pub fn BoundVoicePool::note_off(
  self : BoundVoicePool,
  handle : VoiceHandle,
) -> Bool {
  self.note_off_bool(handle)
}

///|
/// Allocation-conscious note-off predicate for host callback paths.
pub fn BoundVoicePool::note_off_bool(
  self : BoundVoicePool,
  handle : VoiceHandle,
) -> Bool {
  self.pool.note_off_bool(handle)
}

///|
pub fn BoundVoicePool::note_off_result(
  self : BoundVoicePool,
  handle : VoiceHandle,
) -> Result[Unit, VoiceControlError] {
  self.pool.note_off_result(handle)
}

///|
/// Deprecated compatibility wrapper. Use `kill_result` to observe stale or
/// invalid handles as `VoiceControlError` values.
#deprecated("Use BoundVoicePool::kill_result(handle) to observe VoiceControlError")
pub fn BoundVoicePool::kill(
  self : BoundVoicePool,
  handle : VoiceHandle,
) -> Bool {
  self.kill_result(handle) is Ok(_)
}

///|
pub fn BoundVoicePool::kill_result(
  self : BoundVoicePool,
  handle : VoiceHandle,
) -> Result[Unit, VoiceControlError] {
  self.pool.kill_result(handle)
}

///|
pub fn BoundVoicePool::note_off_all(self : BoundVoicePool) -> Unit {
  self.pool.note_off_all()
}

///|
pub fn BoundVoicePool::kill_all(self : BoundVoicePool) -> Unit {
  self.pool.kill_all()
}

///|
/// Deprecated compatibility wrapper. Use `set_voice_pan_result` to observe
/// stale or invalid handles as `VoiceControlError` values.
#deprecated("Use BoundVoicePool::set_voice_pan_result(handle, pan) to observe VoiceControlError")
pub fn BoundVoicePool::set_voice_pan(
  self : BoundVoicePool,
  handle : VoiceHandle,
  pan : Double,
) -> Bool {
  self.set_voice_pan_bool(handle, pan)
}

///|
/// Allocation-conscious pan update predicate for host callback paths.
pub fn BoundVoicePool::set_voice_pan_bool(
  self : BoundVoicePool,
  handle : VoiceHandle,
  pan : Double,
) -> Bool {
  self.pool.set_voice_pan_bool(handle, pan)
}

///|
pub fn BoundVoicePool::set_voice_pan_result(
  self : BoundVoicePool,
  handle : VoiceHandle,
  pan : Double,
) -> Result[Unit, VoiceControlError] {
  self.pool.set_voice_pan_result(handle, pan)
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
/// Allocation-conscious live parameter update predicate for host callback paths.
pub fn BoundVoicePool::apply_voice_param_bool(
  self : BoundVoicePool,
  handle : VoiceHandle,
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> Bool {
  self.pool.apply_voice_param_bool(handle, node_index, slot, value)
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
  let count = for i in 0..<self.max_voices; total = 0 {
    if !(self.slots[i].state is VoiceState::Idle) {
      continue total + 1
    }
    continue total
  } nobreak {
    total
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
  let pairs = [
    for i in 0..<self.max_voices if !(self.slots[i].state is VoiceState::Idle) => {
      (i, self.slots[i].allocation_order)
    }
  ]
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
fn VoicePool::activate_slot(
  self : VoicePool,
  slot : VoiceSlot,
  slot_index : Int,
  compiled : CompiledDsp,
  update_pan : Bool,
  pan : Double,
) -> Int64 {
  gate_adsrs_at(compiled, self.adsr_authoring_indices, true)
  slot.compiled = Some(compiled)
  slot.template_generation = self.template_generation
  // WHY direct snapshot reference: `set_template` replaces the pool snapshot
  // instead of mutating it. Holding the current FixedArray preserves the note-on
  // ADSR set for later note_off without allocating a per-note copy.
  slot.adsr_authoring_indices_snapshot = self.adsr_authoring_indices
  if update_pan {
    slot.update_pan(pan)
  }
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
  VoiceHandle::pack_parts(slot=slot_index, generation=slot.generation)
}

///|
fn VoicePool::note_on_prevalidated_params4_id(
  self : VoicePool,
  node0 : Int,
  slot0 : GraphParamSlot,
  value0 : Double,
  node1 : Int,
  slot1 : GraphParamSlot,
  value1 : Double,
  node2 : Int,
  slot2 : GraphParamSlot,
  value2 : Double,
  node3 : Int,
  slot3 : GraphParamSlot,
  value3 : Double,
  pan : Double,
) -> Int64 {
  let slot_index = self.find_slot()
  let slot = self.slots[slot_index]
  let compiled = match slot.compiled {
    Some(existing) if slot.template_generation == self.template_generation =>
      existing
    _ => return -1L
  }
  if !compiled.can_set_param_bool(node0, slot0, value0) ||
    !compiled.can_set_param_bool(node1, slot1, value1) ||
    !compiled.can_set_param_bool(node2, slot2, value2) ||
    !compiled.can_set_param_bool(node3, slot3, value3) {
    return -1L
  }
  compiled.reset_runtime_state()
  if !compiled.set_param_bool(node0, slot0, value0) ||
    !compiled.set_param_bool(node1, slot1, value1) ||
    !compiled.set_param_bool(node2, slot2, value2) ||
    !compiled.set_param_bool(node3, slot3, value3) {
    return -1L
  }
  self.activate_slot(slot, slot_index, compiled, true, pan)
}

///|
pub fn VoicePool::note_on(
  self : VoicePool,
  params : Array[GraphControl],
) -> VoiceHandle? {
  let slot_index = self.find_slot()
  let slot = self.slots[slot_index]
  // WHY fresh compile on active-slot params: keep the old active slot untouched
  // if a stealing note's params reject. Idle slots can reset/reuse their
  // prepared graph because no old voice can be damaged by a rejected note-on.
  let force_fresh = !(slot.state is VoiceState::Idle) && !params.is_empty()
  let mut reused_prepared = false
  let compiled = match slot.compiled {
    Some(existing) if !force_fresh &&
      slot.template_generation == self.template_generation => {
      reused_prepared = true
      existing
    }
    _ =>
      match CompiledDsp::compile(self.compiled_template, self.compile_context) {
        Some(c) => c
        None => return None
      }
  }
  if reused_prepared {
    compiled.reset_runtime_state()
  }
  // WHY transactional: if any param is invalid, the voice is not activated.
  // This prevents partially-configured voices with default/stale settings.
  if !params.is_empty() {
    if compiled.apply_controls(params) is Err(_) {
      return None
    }
  }
  let handle_id = self.activate_slot(slot, slot_index, compiled, false, 0.0)
  Some(
    VoiceHandle::from_parts(
      slot=VoiceHandle::packed_slot(handle_id),
      generation=VoiceHandle::packed_generation(handle_id),
    ),
  )
}

///|
/// Deprecated compatibility wrapper. Use `note_off_result` to observe stale
/// or invalid handles as `VoiceControlError` values.
#deprecated("Use VoicePool::note_off_result(handle) to observe VoiceControlError")
pub fn VoicePool::note_off(self : VoicePool, handle : VoiceHandle) -> Bool {
  self.note_off_bool(handle)
}

///|
/// Allocation-conscious note-off predicate for host callback paths.
fn VoicePool::note_off_bool(self : VoicePool, handle : VoiceHandle) -> Bool {
  match self.resolve_slot(handle) {
    None => false
    Some(slot) => {
      if slot.state is VoiceState::Idle {
        return false
      }
      match slot.compiled {
        Some(compiled) =>
          if gate_adsrs_at_bool(
              compiled,
              slot.adsr_authoring_indices_snapshot,
              false,
            ) {
            slot.state = VoiceState::Releasing
            true
          } else {
            false
          }
        None => false
      }
    }
  }
}

///|
pub fn VoicePool::note_off_result(
  self : VoicePool,
  handle : VoiceHandle,
) -> Result[Unit, VoiceControlError] {
  match self.resolve_slot(handle) {
    None => Err(VoiceControlError::InvalidVoiceHandle(handle))
    Some(slot) => {
      if slot.state is VoiceState::Idle {
        return Err(VoiceControlError::InvalidVoiceHandle(handle))
      }
      match slot.compiled {
        // WHY adsr_authoring_indices_snapshot: uses the indices from
        // note_on time, not the current self.adsr_authoring_indices which
        // may have changed via set_template.
        Some(compiled) =>
          gate_adsrs_at(compiled, slot.adsr_authoring_indices_snapshot, false)
        None => return Err(VoiceControlError::InvalidVoiceHandle(handle))
      }
      slot.state = VoiceState::Releasing
      Ok(())
    }
  }
}

///|
fn VoicePool::kill_result(
  self : VoicePool,
  handle : VoiceHandle,
) -> Result[Unit, VoiceControlError] {
  match self.resolve_slot(handle) {
    None => Err(VoiceControlError::InvalidVoiceHandle(handle))
    Some(slot) => {
      if slot.state is VoiceState::Idle {
        return Err(VoiceControlError::InvalidVoiceHandle(handle))
      }
      match slot.compiled {
        Some(compiled) => compiled.reset_runtime_state()
        None => ()
      }
      slot.state = VoiceState::Idle
      Ok(())
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
pub fn VoicePool::kill_all(self : VoicePool) -> Unit {
  for i = 0; i < self.max_voices; i = i + 1 {
    let slot = self.slots[i]
    if slot.state is VoiceState::Idle {
      continue i + 1
    }
    match slot.compiled {
      Some(compiled) => compiled.reset_runtime_state()
      None => ()
    }
    slot.state = VoiceState::Idle
  }
}

///|
/// Deprecated compatibility wrapper. Use `set_voice_pan_result` to observe
/// stale or invalid handles as `VoiceControlError` values.
#deprecated("Use VoicePool::set_voice_pan_result(handle, pan) to observe VoiceControlError")
pub fn VoicePool::set_voice_pan(
  self : VoicePool,
  handle : VoiceHandle,
  pan : Double,
) -> Bool {
  self.set_voice_pan_bool(handle, pan)
}

///|
/// Allocation-conscious pan update predicate for host callback paths.
fn VoicePool::set_voice_pan_bool(
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
pub fn VoicePool::set_voice_pan_result(
  self : VoicePool,
  handle : VoiceHandle,
  pan : Double,
) -> Result[Unit, VoiceControlError] {
  match self.resolve_slot(handle) {
    None => Err(VoiceControlError::InvalidVoiceHandle(handle))
    Some(slot) => {
      slot.update_pan(pan)
      Ok(())
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
fn VoicePool::apply_voice_param_bool(
  self : VoicePool,
  handle : VoiceHandle,
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> Bool {
  match self.resolve_slot(handle) {
    None => false
    Some(slot_state) =>
      if slot_state.state is VoiceState::Idle {
        false
      } else {
        match slot_state.compiled {
          Some(compiled) =>
            compiled.can_set_param_bool(node_index, slot, value) &&
            compiled.set_param_bool(node_index, slot, value)
          None => false
        }
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
        // Reclaim voices whose envelope has finished, whether in Release
        // or Active (e.g. sustain=0 decay completed). Without this check,
        // silent voices accumulate as zombies and force audible steals.
        if compiled.is_voice_finished() {
          slot.state = VoiceState::Idle
        }
      }
    }
  }
  self.last_sanitized_count = @dsp.sanitize_buffer(left_output, sample_count) +
    @dsp.sanitize_buffer(right_output, sample_count)
}
