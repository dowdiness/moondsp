///|
/// Parameter id for the final plugin-output gain.
pub const CLAP_PARAM_MASTER_GAIN : Int = 0

///|
/// Parameter id for per-voice oscillator/envelope gain.
pub const CLAP_PARAM_VOICE_GAIN : Int = 1

///|
/// Parameter id for the low-pass cutoff in Hz.
pub const CLAP_PARAM_CUTOFF_HZ : Int = 2

///|
/// Parameter id for the low-pass resonance/Q value.
pub const CLAP_PARAM_RESONANCE : Int = 3

///|
/// Parameter id for per-voice stereo pan in the range [-1, 1].
pub const CLAP_PARAM_PAN : Int = 4

///|
const NOTE_NODE_INDEX : Int = 0

///|
const FILTER_NODE_INDEX : Int = 3

///|
const GAIN_NODE_INDEX : Int = 4

///|
const DEFAULT_SAMPLE_RATE : Double = 48000.0

///|
const MIN_SAFE_SAMPLE_RATE : Double = 8000.0

///|
const DEFAULT_MAX_BLOCK_SIZE : Int = 128

///|
const DEFAULT_MAX_VOICES : Int = 32

///|
const DEFAULT_MASTER_GAIN : Double = 0.8

///|
const DEFAULT_VOICE_GAIN : Double = 0.25

///|
const DEFAULT_CUTOFF_HZ : Double = 1600.0

///|
const DEFAULT_RESONANCE : Double = 0.707

///|
const DEFAULT_PAN : Double = 0.0

///|
pub(all) enum ClapEngineError {
  InvalidSampleRate
  InvalidMaxBlockSize
  InvalidMaxVoices
  PoolInitFailed(@moondsp.BoundVoicePoolError)
} derive(Eq, Debug)

///|
pub impl Show for ClapEngineError with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Native-host-facing synth engine state for an initial CLAP instrument.
///
/// The CLAP C shim should allocate one instance during plugin activation,
/// call note/parameter methods from CLAP events, call `process` for each audio
/// block, then copy `left_sample`/`right_sample` into the host's output ports.
pub struct ClapSynthEngine {
  priv sample_rate : Double
  priv max_block_size : Int
  priv pool : @moondsp.BoundVoicePool
  priv left : @moondsp.AudioBuffer
  priv right : @moondsp.AudioBuffer
  priv render_contexts : FixedArray[@moondsp.DspContext]
  priv active_notes : ActiveNoteTable
  priv mut last_frame_count : Int
  priv mut master_gain : Double
  priv mut voice_gain : Double
  priv mut cutoff_hz : Double
  priv mut resonance : Double
  priv mut pan : Double
}

///|
/// Fixed-capacity active-note index for the CLAP callback path.
///
/// WHY parallel FixedArrays instead of Map: note-on/note-off and automation run
/// inside `process`, so active-note tracking must not allocate or resize.
priv struct ActiveNoteTable {
  used : FixedArray[Bool]
  map_keys : FixedArray[Int]
  keys : FixedArray[Int]
  velocities : FixedArray[Double]
  slots : FixedArray[Int]
  generations : FixedArray[Int]
  mut count : Int
}

///|
fn ActiveNoteTable::new(capacity : Int) -> ActiveNoteTable {
  {
    used: FixedArray::make(capacity, false),
    map_keys: FixedArray::make(capacity, 0),
    keys: FixedArray::make(capacity, -1),
    velocities: FixedArray::make(capacity, 0.0),
    slots: FixedArray::make(capacity, -1),
    generations: FixedArray::make(capacity, -1),
    count: 0,
  }
}

///|
fn ActiveNoteTable::capacity(self : ActiveNoteTable) -> Int {
  self.used.length()
}

///|
fn ActiveNoteTable::is_used(self : ActiveNoteTable, index : Int) -> Bool {
  self.used[index]
}

///|
fn ActiveNoteTable::key_at(self : ActiveNoteTable, index : Int) -> Int {
  self.keys[index]
}

///|
fn ActiveNoteTable::velocity_at(self : ActiveNoteTable, index : Int) -> Double {
  self.velocities[index]
}

///|
fn ActiveNoteTable::handle_at(
  self : ActiveNoteTable,
  index : Int,
) -> @moondsp.VoiceHandle {
  @moondsp.VoiceHandle::from_parts(
    slot=self.slots[index],
    generation=self.generations[index],
  )
}

///|
fn ActiveNoteTable::index_for_map_key(
  self : ActiveNoteTable,
  map_key : Int,
) -> Int? {
  for index in 0..<self.used.length() {
    if self.used[index] && self.map_keys[index] == map_key {
      return Some(index)
    }
  }
  None
}

///|
fn ActiveNoteTable::find_by_key(self : ActiveNoteTable, key : Int) -> Int? {
  for index in 0..<self.used.length() {
    if self.used[index] && self.keys[index] == key {
      return Some(index)
    }
  }
  None
}

///|
fn ActiveNoteTable::clear_index(self : ActiveNoteTable, index : Int) -> Unit {
  if self.used[index] {
    self.used[index] = false
    self.count = self.count - 1
  }
}

///|
fn ActiveNoteTable::clear_all(self : ActiveNoteTable) -> Unit {
  self.used.fill(false)
  self.count = 0
}

///|
fn ActiveNoteTable::remove_for_slot(self : ActiveNoteTable, slot : Int) -> Unit {
  for index in 0..<self.used.length() {
    if self.used[index] && self.slots[index] == slot {
      self.clear_index(index)
    }
  }
}

///|
fn ActiveNoteTable::store_handle_id(
  self : ActiveNoteTable,
  map_key : Int,
  key : Int,
  velocity : Double,
  handle_id : Int64,
) -> Unit {
  let slot = @moondsp.VoiceHandle::packed_slot(handle_id)
  self.remove_for_slot(slot)
  for index in 0..<self.used.length() {
    if !self.used[index] {
      self.used[index] = true
      self.map_keys[index] = map_key
      self.keys[index] = key
      self.velocities[index] = velocity
      self.slots[index] = slot
      self.generations[index] = @moondsp.VoiceHandle::packed_generation(
        handle_id,
      )
      self.count = self.count + 1
      return
    }
  }
}

///|
/// Default subtractive synth template used by the CLAP MVP.
///
/// Authoring-node layout is intentionally fixed because the CLAP parameter
/// bridge binds by node index:
///
/// - 0: constant frequency, bound as `note`
/// - 1: oscillator reading node 0
/// - 2: ADSR envelope gated by the voice pool
/// - 3: low-pass biquad, bound as `cutoff` and `q`
/// - 4: envelope gain, bound as `gain`
/// - 5: mono output, panned by `BoundVoicePool`
pub fn default_synth_template() -> Array[@moondsp.DspNode] {
  [
    @moondsp.DspNode::constant(440.0),
    @moondsp.DspNode::oscillator_from(NOTE_NODE_INDEX, @moondsp.Waveform::Saw),
    @moondsp.DspNode::adsr(
      attack_ms=2.0,
      decay_ms=80.0,
      sustain=0.7,
      release_ms=120.0,
    ),
    @moondsp.DspNode::biquad(
      input=1,
      mode=@moondsp.BiquadMode::LowPass,
      cutoff_hz=DEFAULT_CUTOFF_HZ,
      q=DEFAULT_RESONANCE,
    ),
    @moondsp.DspNode::envelope_gain(
      input=FILTER_NODE_INDEX,
      envelope=2,
      amount=DEFAULT_VOICE_GAIN,
    ),
    @moondsp.DspNode::output(GAIN_NODE_INDEX),
  ]
}

///|
fn synth_bindings() -> @moondsp.ControlBindingBuilder {
  @moondsp.ControlBindingBuilder::new()
  .bind(
    key="note",
    node_index=NOTE_NODE_INDEX,
    slot=@moondsp.GraphParamSlot::Value0,
  )
  .bind(
    key="cutoff",
    node_index=FILTER_NODE_INDEX,
    slot=@moondsp.GraphParamSlot::Value0,
  )
  .bind(
    key="q",
    node_index=FILTER_NODE_INDEX,
    slot=@moondsp.GraphParamSlot::Value1,
  )
  .bind(
    key="gain",
    node_index=GAIN_NODE_INDEX,
    slot=@moondsp.GraphParamSlot::Value0,
  )
}

///|
pub fn ClapSynthEngine::new(
  sample_rate? : Double = DEFAULT_SAMPLE_RATE,
  max_block_size? : Int = DEFAULT_MAX_BLOCK_SIZE,
  max_voices? : Int = DEFAULT_MAX_VOICES,
) -> Result[ClapSynthEngine, ClapEngineError] {
  if !is_valid_sample_rate(sample_rate) {
    return Err(ClapEngineError::InvalidSampleRate)
  }
  if max_block_size <= 0 {
    return Err(ClapEngineError::InvalidMaxBlockSize)
  }
  if max_voices <= 0 {
    return Err(ClapEngineError::InvalidMaxVoices)
  }
  let ctx = @moondsp.DspContext::new(sample_rate~, block_size=max_block_size)
  let template = @moondsp.CompiledTemplate::analyze(default_synth_template())
  match
    @moondsp.BoundVoicePool::new(template, ctx, synth_bindings(), max_voices~) {
    Err(error) => Err(ClapEngineError::PoolInitFailed(error))
    Ok(pool) =>
      Ok({
        sample_rate,
        max_block_size,
        pool,
        left: @moondsp.AudioBuffer::filled(max_block_size),
        right: @moondsp.AudioBuffer::filled(max_block_size),
        render_contexts: FixedArray::makei(max_block_size + 1, fn(block_size) {
          @moondsp.DspContext::new(sample_rate~, block_size~)
        }),
        active_notes: ActiveNoteTable::new(max_voices),
        last_frame_count: 0,
        master_gain: DEFAULT_MASTER_GAIN,
        voice_gain: DEFAULT_VOICE_GAIN,
        cutoff_hz: DEFAULT_CUTOFF_HZ,
        resonance: DEFAULT_RESONANCE,
        pan: DEFAULT_PAN,
      })
  }
}

///|
pub fn ClapSynthEngine::master_gain(self : ClapSynthEngine) -> Double {
  self.master_gain
}

///|
pub fn ClapSynthEngine::voice_gain(self : ClapSynthEngine) -> Double {
  self.voice_gain
}

///|
pub fn ClapSynthEngine::cutoff_hz(self : ClapSynthEngine) -> Double {
  self.cutoff_hz
}

///|
pub fn ClapSynthEngine::resonance(self : ClapSynthEngine) -> Double {
  self.resonance
}

///|
pub fn ClapSynthEngine::pan(self : ClapSynthEngine) -> Double {
  self.pan
}

///|
/// Convert CLAP's `(note_id, key)` pair into the engine's primary active-note
/// map key. CLAP sends `note_id = -1` when no stable note id is assigned; in
/// that case use the MIDI key so note-off can still find the most recent voice
/// for that pitch.
fn note_map_key(note_id : Int, key : Int) -> Int {
  if note_id >= 0 {
    note_id
  } else {
    key
  }
}

///|
fn ClapSynthEngine::release_active_note_index(
  self : ClapSynthEngine,
  index : Int,
) -> Bool {
  if !self.active_notes.is_used(index) {
    return false
  }
  let handle = self.active_notes.handle_at(index)
  self.active_notes.clear_index(index)
  self.pool.note_off_bool(handle)
}

///|
fn ClapSynthEngine::release_active_note(
  self : ClapSynthEngine,
  map_key : Int,
) -> Bool {
  match self.active_notes.index_for_map_key(map_key) {
    None => false
    Some(index) => self.release_active_note_index(index)
  }
}

///|
fn ClapSynthEngine::release_active_note_matching_key(
  self : ClapSynthEngine,
  map_key : Int,
  key : Int,
) -> Bool {
  match self.active_notes.index_for_map_key(map_key) {
    Some(index) if key < 0 || self.active_notes.key_at(index) == key =>
      self.release_active_note_index(index)
    _ => false
  }
}

///|
fn ClapSynthEngine::release_active_notes_by_key(
  self : ClapSynthEngine,
  key : Int,
) -> Bool {
  let mut released = false
  let mut searching = true
  while searching {
    match self.active_notes.find_by_key(key) {
      None => searching = false
      Some(index) =>
        released = self.release_active_note_index(index) || released
    }
  }
  released
}

///|
fn sanitize_velocity(value : Double) -> Double {
  if !@moondsp.is_finite(value) || value < 0.0 {
    0.0
  } else if value > 1.0 {
    1.0
  } else {
    value
  }
}

///|
fn sanitize_gain(value : Double) -> Double {
  if !@moondsp.is_finite(value) || value < 0.0 {
    0.0
  } else if value > 4.0 {
    4.0
  } else {
    value
  }
}

///|
fn sanitize_pan(value : Double) -> Double {
  if !@moondsp.is_finite(value) {
    0.0
  } else if value < -1.0 {
    -1.0
  } else if value > 1.0 {
    1.0
  } else {
    value
  }
}

///|
fn sanitize_resonance(value : Double) -> Double {
  if !@moondsp.is_finite_positive(value) {
    DEFAULT_RESONANCE
  } else if value > 32.0 {
    32.0
  } else {
    value
  }
}

///|
fn is_valid_sample_rate(sample_rate : Double) -> Bool {
  @moondsp.is_finite_positive(sample_rate) &&
  sample_rate >= MIN_SAFE_SAMPLE_RATE
}

///|
fn sanitize_cutoff(value : Double, sample_rate : Double) -> Double {
  let safe_sample_rate = if is_valid_sample_rate(sample_rate) {
    sample_rate
  } else {
    MIN_SAFE_SAMPLE_RATE
  }
  let nyquist = safe_sample_rate * 0.5
  let candidate = if @moondsp.is_finite_positive(value) {
    value
  } else {
    DEFAULT_CUTOFF_HZ
  }
  if candidate >= nyquist {
    nyquist - 1.0
  } else {
    candidate
  }
}

///|
fn sanitize_frame_count(frame_count : Int, max_block_size : Int) -> Int {
  if frame_count <= 0 {
    0
  } else if frame_count > max_block_size {
    max_block_size
  } else {
    frame_count
  }
}

///|
fn midi_to_hz(key : Int) -> Double {
  440.0 * @math.pow(2.0, (key.to_double() - 69.0) / 12.0)
}

///|
pub fn ClapSynthEngine::note_on(
  self : ClapSynthEngine,
  note_id~ : Int,
  key~ : Int,
  velocity~ : Double,
) -> Bool {
  if key < 0 || key > 127 {
    return false
  }
  let map_key = note_map_key(note_id, key)
  ignore(self.release_active_note(map_key))
  let note_velocity = sanitize_velocity(velocity)
  let handle_id = self.pool.note_on_prevalidated_params4_id(
    NOTE_NODE_INDEX,
    @moondsp.GraphParamSlot::Value0,
    midi_to_hz(key),
    FILTER_NODE_INDEX,
    @moondsp.GraphParamSlot::Value0,
    self.cutoff_hz,
    FILTER_NODE_INDEX,
    @moondsp.GraphParamSlot::Value1,
    self.resonance,
    GAIN_NODE_INDEX,
    @moondsp.GraphParamSlot::Value0,
    self.voice_gain * note_velocity,
    self.pan,
  )
  if handle_id < 0L {
    false
  } else {
    self.active_notes.store_handle_id(map_key, key, note_velocity, handle_id)
    true
  }
}

///|
pub fn ClapSynthEngine::note_off(
  self : ClapSynthEngine,
  note_id~ : Int,
  key~ : Int,
) -> Bool {
  if note_id < 0 && key < 0 {
    let had_notes = self.active_notes.count > 0
    self.all_notes_off()
    return had_notes
  }
  if note_id >= 0 {
    let map_key = note_map_key(note_id, key)
    return self.release_active_note_matching_key(map_key, key)
  }
  if key >= 0 {
    self.release_active_notes_by_key(key)
  } else {
    false
  }
}

///|
pub fn ClapSynthEngine::all_notes_off(self : ClapSynthEngine) -> Unit {
  self.pool.note_off_all()
  self.active_notes.clear_all()
}

///|
pub fn ClapSynthEngine::set_master_gain(
  self : ClapSynthEngine,
  value : Double,
) -> Double {
  let sanitized = sanitize_gain(value)
  self.master_gain = sanitized
  sanitized
}

///|
fn ClapSynthEngine::apply_param_to_active_voices(
  self : ClapSynthEngine,
  node_index : Int,
  slot : @moondsp.GraphParamSlot,
  value : Double,
) -> Unit {
  for index in 0..<self.active_notes.capacity() {
    if self.active_notes.is_used(index) {
      ignore(
        self.pool.apply_voice_param_bool(
          self.active_notes.handle_at(index),
          node_index,
          slot,
          value,
        ),
      )
    }
  }
}

///|
fn ClapSynthEngine::apply_voice_gain_to_active_notes(
  self : ClapSynthEngine,
  value : Double,
) -> Unit {
  for index in 0..<self.active_notes.capacity() {
    if self.active_notes.is_used(index) {
      ignore(
        self.pool.apply_voice_param_bool(
          self.active_notes.handle_at(index),
          GAIN_NODE_INDEX,
          @moondsp.GraphParamSlot::Value0,
          value * self.active_notes.velocity_at(index),
        ),
      )
    }
  }
}

///|
pub fn ClapSynthEngine::set_voice_gain(
  self : ClapSynthEngine,
  value : Double,
) -> Double {
  let sanitized = sanitize_gain(value)
  self.voice_gain = sanitized
  self.apply_voice_gain_to_active_notes(sanitized)
  sanitized
}

///|
pub fn ClapSynthEngine::set_cutoff_hz(
  self : ClapSynthEngine,
  value : Double,
) -> Double {
  let sanitized = sanitize_cutoff(value, self.sample_rate)
  self.cutoff_hz = sanitized
  self.apply_param_to_active_voices(
    FILTER_NODE_INDEX,
    @moondsp.GraphParamSlot::Value0,
    sanitized,
  )
  sanitized
}

///|
pub fn ClapSynthEngine::set_resonance(
  self : ClapSynthEngine,
  value : Double,
) -> Double {
  let sanitized = sanitize_resonance(value)
  self.resonance = sanitized
  self.apply_param_to_active_voices(
    FILTER_NODE_INDEX,
    @moondsp.GraphParamSlot::Value1,
    sanitized,
  )
  sanitized
}

///|
pub fn ClapSynthEngine::set_pan(
  self : ClapSynthEngine,
  value : Double,
) -> Double {
  let sanitized = sanitize_pan(value)
  self.pan = sanitized
  for index in 0..<self.active_notes.capacity() {
    if self.active_notes.is_used(index) {
      ignore(
        self.pool.set_voice_pan_bool(
          self.active_notes.handle_at(index),
          sanitized,
        ),
      )
    }
  }
  sanitized
}

///|
/// Flat integer-parameter dispatcher intended for the C CLAP bridge.
pub fn ClapSynthEngine::set_param(
  self : ClapSynthEngine,
  param_id : Int,
  value : Double,
) -> Bool {
  match param_id {
    CLAP_PARAM_MASTER_GAIN => {
      ignore(self.set_master_gain(value))
      true
    }
    CLAP_PARAM_VOICE_GAIN => {
      ignore(self.set_voice_gain(value))
      true
    }
    CLAP_PARAM_CUTOFF_HZ => {
      ignore(self.set_cutoff_hz(value))
      true
    }
    CLAP_PARAM_RESONANCE => {
      ignore(self.set_resonance(value))
      true
    }
    CLAP_PARAM_PAN => {
      ignore(self.set_pan(value))
      true
    }
    _ => false
  }
}

///|
/// Render up to `max_block_size` frames and return the actual processed count.
pub fn ClapSynthEngine::process(
  self : ClapSynthEngine,
  frame_count : Int,
) -> Int {
  let frames = sanitize_frame_count(frame_count, self.max_block_size)
  self.last_frame_count = frames
  self.left.fill(0.0)
  self.right.fill(0.0)
  if frames <= 0 {
    return 0
  }
  let ctx = self.render_contexts[frames]
  self.pool.process(ctx, self.left, self.right)
  let gain = self.master_gain
  for i = 0; i < frames; i = i + 1 {
    self.left.set(i, self.left.get(i) * gain)
    self.right.set(i, self.right.get(i) * gain)
  }
  frames
}

///|
fn checked_sample(
  buffer : @moondsp.AudioBuffer,
  index : Int,
  frame_count : Int,
) -> Double {
  if index >= 0 && index < frame_count {
    buffer.get(index)
  } else {
    0.0
  }
}

///|
pub fn ClapSynthEngine::left_sample(
  self : ClapSynthEngine,
  index : Int,
) -> Double {
  checked_sample(self.left, index, self.last_frame_count)
}

///|
pub fn ClapSynthEngine::right_sample(
  self : ClapSynthEngine,
  index : Int,
) -> Double {
  checked_sample(self.right, index, self.last_frame_count)
}
