///|
pub enum VoiceState {
  Idle
  Active
  Releasing
} derive(Eq, Show)

///|
pub struct VoiceHandle {
  slot : Int
  generation : Int
} derive(Eq, Show)

///|
priv struct VoiceSlot {
  mut compiled : CompiledDsp?
  mut state : VoiceState
  mut generation : Int
  mut allocation_order : Int
  mut pan : Double
  mono_buffer : AudioBuffer
}

///|
fn VoiceSlot::new(block_size : Int) -> VoiceSlot {
  {
    compiled: None,
    state: VoiceState::Idle,
    generation: 0,
    allocation_order: 0,
    pan: 0.0,
    mono_buffer: AudioBuffer::filled(block_size),
  }
}

///|
fn VoiceSlot::is_handle_valid(self : VoiceSlot, handle : VoiceHandle) -> Bool {
  handle.generation == self.generation
}

///|
pub struct VoicePool {
  priv slots : FixedArray[VoiceSlot]
  priv mut template : Array[DspNode]
  priv compile_context : DspContext
  priv mut next_allocation_order : Int
  priv max_voices : Int
}

///|
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
fn VoicePool::find_slot(self : VoicePool) -> Int {
  for i = 0; i < self.max_voices; i = i + 1 {
    if self.slots[i].state is VoiceState::Idle {
      return i
    }
  }
  let mut best_releasing = -1
  let mut best_releasing_order = 2147483647
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
  let mut best_active = 0
  let mut best_active_order = 2147483647
  for i = 0; i < self.max_voices; i = i + 1 {
    if self.slots[i].allocation_order < best_active_order {
      best_active = i
      best_active_order = self.slots[i].allocation_order
    }
  }
  best_active
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
  if params.length() > 0 {
    if !compiled.apply_controls(params) {
      return None
    }
  }
  let nodes = self.template
  for i = 0; i < nodes.length(); i = i + 1 {
    if nodes[i].kind is Adsr {
      ignore(compiled.gate_on(i))
    }
  }
  slot.compiled = Some(compiled)
  slot.state = VoiceState::Active
  slot.generation = slot.generation + 1
  slot.allocation_order = self.next_allocation_order
  self.next_allocation_order = self.next_allocation_order + 1
  Some({ slot: slot_index, generation: slot.generation })
}

///|
pub fn VoicePool::note_off(self : VoicePool, handle : VoiceHandle) -> Bool {
  if handle.slot < 0 || handle.slot >= self.max_voices {
    return false
  }
  let slot = self.slots[handle.slot]
  if !slot.is_handle_valid(handle) {
    return false
  }
  if slot.state is VoiceState::Idle {
    return false
  }
  match slot.compiled {
    Some(compiled) => {
      let nodes = self.template
      for i = 0; i < nodes.length(); i = i + 1 {
        if nodes[i].kind is Adsr {
          ignore(compiled.gate_off(i))
        }
      }
    }
    None => ()
  }
  slot.state = VoiceState::Releasing
  true
}

///|
pub fn VoicePool::note_off_all(self : VoicePool) -> Unit {
  for i = 0; i < self.max_voices; i = i + 1 {
    let slot = self.slots[i]
    if slot.state is VoiceState::Active {
      match slot.compiled {
        Some(compiled) => {
          let nodes = self.template
          for j = 0; j < nodes.length(); j = j + 1 {
            if nodes[j].kind is Adsr {
              ignore(compiled.gate_off(j))
            }
          }
        }
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
  if handle.slot < 0 || handle.slot >= self.max_voices {
    return false
  }
  let slot = self.slots[handle.slot]
  if !slot.is_handle_valid(handle) {
    return false
  }
  slot.pan = pan.clamp(min=-1.0, max=1.0)
  true
}

///|
pub fn VoicePool::voice_state(
  self : VoicePool,
  handle : VoiceHandle,
) -> VoiceState {
  if handle.slot < 0 || handle.slot >= self.max_voices {
    return VoiceState::Idle
  }
  let slot = self.slots[handle.slot]
  if !slot.is_handle_valid(handle) {
    return VoiceState::Idle
  }
  slot.state
}
