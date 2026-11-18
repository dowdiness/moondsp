///|
/// Parameter id for the final plugin-output gain.
pub const CLAP_PARAM_MASTER_GAIN : Int32 = 0

///|
/// Parameter id for per-voice oscillator/envelope gain.
pub const CLAP_PARAM_VOICE_GAIN : Int32 = 1

///|
/// Parameter id for the low-pass cutoff in Hz.
pub const CLAP_PARAM_CUTOFF_HZ : Int32 = 2

///|
/// Parameter id for the low-pass resonance/Q value.
pub const CLAP_PARAM_RESONANCE : Int32 = 3

///|
/// Parameter id for per-voice stereo pan in the range [-1, 1].
pub const CLAP_PARAM_PAN : Int32 = 4

///|
const NOTE_NODE_INDEX : Int32 = 0

///|
const FILTER_NODE_INDEX : Int32 = 3

///|
const GAIN_NODE_INDEX : Int32 = 4

///|
const DEFAULT_SAMPLE_RATE : Double = 48000.0

///|
const MIN_SAFE_SAMPLE_RATE : Double = 8000.0

///|
const DEFAULT_MAX_BLOCK_SIZE : Int32 = 128

///|
const DEFAULT_MAX_VOICES : Int32 = 32

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
#derive(Eq, Debug)
pub(all) suberror ClapEngineError {
  InvalidSampleRate
  InvalidMaxBlockSize
  InvalidMaxVoices
  PoolInitFailed(@moondsp.BoundVoicePoolError)
}

///|
pub extend ClapEngineError with Eq::{not_equal, equal}

///|
pub extend ClapEngineError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub impl Show for ClapEngineError with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub extend ClapEngineError with Show::{to_string, output}

///|
/// Native-host-facing synth engine state for an initial CLAP instrument.
///
/// The CLAP C shim should allocate one instance during plugin activation,
/// call note/parameter methods from CLAP events, call `process` for each audio
/// block, then copy `left_sample`/`right_sample` into the host's output ports.
pub struct ClapSynthEngine {
  priv sample_rate : Double
  priv max_block_size : Int32
  priv pool : @moondsp.BoundVoicePool
  priv left : @moondsp.AudioBuffer
  priv right : @moondsp.AudioBuffer
  priv render_contexts : FixedArray[@moondsp.DspContext]
  priv active_notes : ActiveNoteTable
  priv mut last_frame_count : Int32
  /// Each host parameter's sanitized value, indexed by parameter id. The voice
  /// parameters are buses: every sounding voice follows them, including its
  /// release tail (ADR-0019 Decision 1). Master gain scales the output.
  priv params : FixedArray[Double]
  /// One follower per voice bus, resolved at activation so note-on attaches
  /// them without allocating.
  priv followers : FixedArray[@moondsp.VoiceFollower]
  /// Frames rendered since activation: the time voices read their buses at.
  priv mut rendered_frames : Int64
}

///|
/// The voice parameters host automation drives, by binding key.
let voice_buses : Array[(String, Int32)] = [
  ("gain", CLAP_PARAM_VOICE_GAIN),
  ("cutoff", CLAP_PARAM_CUTOFF_HZ),
  ("q", CLAP_PARAM_RESONANCE),
  ("pan", CLAP_PARAM_PAN),
]

///|
/// Fixed-capacity active-note index for the CLAP callback path.
///
/// WHY parallel FixedArrays instead of Map: note-on/note-off and automation run
/// inside `process`, so active-note tracking must not allocate or resize.
priv struct ActiveNoteTable {
  used : FixedArray[Bool]
  map_keys : FixedArray[Int32]
  keys : FixedArray[Int32]
  slots : FixedArray[Int32]
  generations : FixedArray[Int32]
  mut count : Int32
}

///|
fn ActiveNoteTable::ActiveNoteTable(capacity : Int32) -> ActiveNoteTable {
  {
    used: FixedArray::make(capacity, false),
    map_keys: FixedArray::make(capacity, 0),
    keys: FixedArray::make(capacity, -1),
    slots: FixedArray::make(capacity, -1),
    generations: FixedArray::make(capacity, -1),
    count: 0,
  }
}

///|
fn ActiveNoteTable::is_used(self : ActiveNoteTable, index : Int32) -> Bool {
  self.used[index]
}

///|
fn ActiveNoteTable::key_at(self : ActiveNoteTable, index : Int32) -> Int32 {
  self.keys[index]
}

///|
fn ActiveNoteTable::handle_at(
  self : ActiveNoteTable,
  index : Int32,
) -> @moondsp.VoiceHandle {
  @moondsp.VoiceHandle::from_parts(
    slot=self.slots[index],
    generation=self.generations[index],
  )
}

///|
fn ActiveNoteTable::index_for_map_key(
  self : ActiveNoteTable,
  map_key : Int32,
) -> Int32? {
  for index in 0..<self.used.length() {
    if self.used[index] && self.map_keys[index] == map_key {
      return Some(index)
    }
  }
  None
}

///|
fn ActiveNoteTable::find_by_key(self : ActiveNoteTable, key : Int32) -> Int32? {
  for index in 0..<self.used.length() {
    if self.used[index] && self.keys[index] == key {
      return Some(index)
    }
  }
  None
}

///|
fn ActiveNoteTable::clear_index(self : ActiveNoteTable, index : Int32) -> Unit {
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
fn ActiveNoteTable::remove_for_slot(
  self : ActiveNoteTable,
  slot : Int32,
) -> Unit {
  for index in 0..<self.used.length() {
    if self.used[index] && self.slots[index] == slot {
      self.clear_index(index)
    }
  }
}

///|
fn ActiveNoteTable::store_handle_id(
  self : ActiveNoteTable,
  map_key : Int32,
  key : Int32,
  handle_id : Int64,
) -> Unit {
  let slot = @moondsp.VoiceHandle::packed_slot(handle_id)
  self.remove_for_slot(slot)
  for index in 0..<self.used.length() {
    if !self.used[index] {
      self.used[index] = true
      self.map_keys[index] = map_key
      self.keys[index] = key
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
/// - 4: envelope gain, set to each note's velocity
/// - 5: mono output; the voice frame applies `gain` and `pan`
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
      amount=1.0,
    ),
    @moondsp.DspNode::output(GAIN_NODE_INDEX),
  ]
}

///|
fn synth_bindings() -> @moondsp.ControlBindingBuilder {
  @moondsp.ControlBindingBuilder()
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
  .bind_voice(key="gain", param=Gain)
  .bind_voice(key="pan", param=Pan)
}

///|
pub fn ClapSynthEngine::ClapSynthEngine(
  sample_rate~ : Double = DEFAULT_SAMPLE_RATE,
  max_block_size~ : Int32 = DEFAULT_MAX_BLOCK_SIZE,
  max_voices~ : Int32 = DEFAULT_MAX_VOICES,
) -> ClapSynthEngine raise ClapEngineError {
  if !is_valid_sample_rate(sample_rate) {
    raise ClapEngineError::InvalidSampleRate
  }
  if max_block_size <= 0 {
    raise ClapEngineError::InvalidMaxBlockSize
  }
  if max_voices <= 0 {
    raise ClapEngineError::InvalidMaxVoices
  }
  let ctx = @moondsp.DspContext(sample_rate~, block_size=max_block_size)
  let template = @moondsp.AnalyzedGraph::analyze(default_synth_template())
  let pool = @moondsp.BoundVoicePool(
    template,
    ctx,
    synth_bindings(),
    max_voices~,
  ) catch {
    error => raise ClapEngineError::PoolInitFailed(error)
  }
  let params = FixedArray::make(5, 0.0)
  params[CLAP_PARAM_MASTER_GAIN] = DEFAULT_MASTER_GAIN
  params[CLAP_PARAM_VOICE_GAIN] = DEFAULT_VOICE_GAIN
  params[CLAP_PARAM_CUTOFF_HZ] = DEFAULT_CUTOFF_HZ
  params[CLAP_PARAM_RESONANCE] = DEFAULT_RESONANCE
  params[CLAP_PARAM_PAN] = DEFAULT_PAN
  let followers = FixedArray::from_array(
    voice_buses.map(bus => {
      let id = bus.1
      pool.follower(bus.0, (_, _) => params[id]).unwrap()
    }),
  )
  {
    sample_rate,
    max_block_size,
    pool,
    left: @moondsp.AudioBuffer::filled(max_block_size),
    right: @moondsp.AudioBuffer::filled(max_block_size),
    render_contexts: FixedArray::makei(max_block_size + 1, fn(block_size) {
      @moondsp.DspContext(sample_rate~, block_size~)
    }),
    active_notes: ActiveNoteTable(max_voices),
    last_frame_count: 0,
    params,
    followers,
    rendered_frames: 0L,
  }
}

///|
pub fn ClapSynthEngine::master_gain(self : ClapSynthEngine) -> Double {
  self.params[CLAP_PARAM_MASTER_GAIN]
}

///|
pub fn ClapSynthEngine::voice_gain(self : ClapSynthEngine) -> Double {
  self.params[CLAP_PARAM_VOICE_GAIN]
}

///|
pub fn ClapSynthEngine::cutoff_hz(self : ClapSynthEngine) -> Double {
  self.params[CLAP_PARAM_CUTOFF_HZ]
}

///|
pub fn ClapSynthEngine::resonance(self : ClapSynthEngine) -> Double {
  self.params[CLAP_PARAM_RESONANCE]
}

///|
pub fn ClapSynthEngine::pan(self : ClapSynthEngine) -> Double {
  self.params[CLAP_PARAM_PAN]
}

///|
/// Convert CLAP's `(note_id, key)` pair into the engine's primary active-note
/// map key. CLAP sends `note_id = -1` when no stable note id is assigned; in
/// that case use the MIDI key so note-off can still find the most recent voice
/// for that pitch.
fn note_map_key(note_id : Int32, key : Int32) -> Int32 {
  if note_id >= 0 {
    note_id
  } else {
    key
  }
}

///|
fn ClapSynthEngine::release_active_note_index(
  self : ClapSynthEngine,
  index : Int32,
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
  map_key : Int32,
) -> Bool {
  match self.active_notes.index_for_map_key(map_key) {
    None => false
    Some(index) => self.release_active_note_index(index)
  }
}

///|
fn ClapSynthEngine::release_active_note_matching_key(
  self : ClapSynthEngine,
  map_key : Int32,
  key : Int32,
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
  key : Int32,
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
fn sanitize_frame_count(frame_count : Int32, max_block_size : Int32) -> Int32 {
  if frame_count <= 0 {
    0
  } else if frame_count > max_block_size {
    max_block_size
  } else {
    frame_count
  }
}

///|
fn midi_to_hz(key : Int32) -> Double {
  440.0 * @math.pow(2.0, (key.to_double() - 69.0) / 12.0)
}

///|
pub fn ClapSynthEngine::note_on(
  self : ClapSynthEngine,
  note_id~ : Int32,
  key~ : Int32,
  velocity~ : Double,
) -> Bool {
  if key < 0 || key > 127 {
    return false
  }
  let map_key = note_map_key(note_id, key)
  ignore(self.release_active_note(map_key))
  let handle_id = self.pool.note_on_prevalidated_params4_id(
    NOTE_NODE_INDEX,
    @moondsp.GraphParamSlot::Value0,
    midi_to_hz(key),
    FILTER_NODE_INDEX,
    @moondsp.GraphParamSlot::Value0,
    self.cutoff_hz(),
    FILTER_NODE_INDEX,
    @moondsp.GraphParamSlot::Value1,
    self.resonance(),
    GAIN_NODE_INDEX,
    @moondsp.GraphParamSlot::Value0,
    sanitize_velocity(velocity),
    self.pan(),
  )
  if handle_id < 0L {
    return false
  }
  let handle = @moondsp.VoiceHandle::from_parts(
    slot=@moondsp.VoiceHandle::packed_slot(handle_id),
    generation=@moondsp.VoiceHandle::packed_generation(handle_id),
  )
  // The voice frame's gain comes from its bus at the next block.
  for follower in self.followers {
    ignore(self.pool.follow(handle, follower))
  }
  self.active_notes.store_handle_id(map_key, key, handle_id)
  true
}

///|
pub fn ClapSynthEngine::note_off(
  self : ClapSynthEngine,
  note_id~ : Int32,
  key~ : Int32,
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
  self.params[CLAP_PARAM_MASTER_GAIN] = sanitized
  sanitized
}

///|
pub fn ClapSynthEngine::set_voice_gain(
  self : ClapSynthEngine,
  value : Double,
) -> Double {
  let sanitized = sanitize_gain(value)
  self.params[CLAP_PARAM_VOICE_GAIN] = sanitized
  sanitized
}

///|
pub fn ClapSynthEngine::set_cutoff_hz(
  self : ClapSynthEngine,
  value : Double,
) -> Double {
  let sanitized = sanitize_cutoff(value, self.sample_rate)
  self.params[CLAP_PARAM_CUTOFF_HZ] = sanitized
  sanitized
}

///|
pub fn ClapSynthEngine::set_resonance(
  self : ClapSynthEngine,
  value : Double,
) -> Double {
  let sanitized = sanitize_resonance(value)
  self.params[CLAP_PARAM_RESONANCE] = sanitized
  sanitized
}

///|
pub fn ClapSynthEngine::set_pan(
  self : ClapSynthEngine,
  value : Double,
) -> Double {
  let sanitized = sanitize_pan(value)
  self.params[CLAP_PARAM_PAN] = sanitized
  sanitized
}

///|
/// Flat integer-parameter dispatcher intended for the C CLAP bridge.
pub fn ClapSynthEngine::set_param(
  self : ClapSynthEngine,
  param_id : Int32,
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
  frame_count : Int32,
) -> Int32 {
  let frames = sanitize_frame_count(frame_count, self.max_block_size)
  self.last_frame_count = frames
  self.left.fill(0.0)
  self.right.fill(0.0)
  if frames <= 0 {
    return 0
  }
  let ctx = self.render_contexts[frames]
  self.pool.update_follows(self.rendered_frames, 1L)
  self.pool.process(ctx, self.left, self.right)
  self.rendered_frames = self.rendered_frames + frames.to_int64()
  let gain = self.master_gain()
  for i = 0; i < frames; i = i + 1 {
    self.left.set(i, self.left.get(i) * gain)
    self.right.set(i, self.right.get(i) * gain)
  }
  frames
}

///|
fn checked_sample(
  buffer : @moondsp.AudioBuffer,
  index : Int32,
  frame_count : Int32,
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
  index : Int32,
) -> Double {
  checked_sample(self.left, index, self.last_frame_count)
}

///|
pub fn ClapSynthEngine::right_sample(
  self : ClapSynthEngine,
  index : Int32,
) -> Double {
  checked_sample(self.right, index, self.last_frame_count)
}
