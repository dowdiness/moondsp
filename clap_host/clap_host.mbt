///|
let engine_slots : Array[@engine.ClapSynthEngine?] = []

///|
fn handle_to_index(handle : Int) -> Int {
  handle - 1
}

///|
fn valid_handle_index(handle : Int) -> Int? {
  let index = handle_to_index(handle)
  if handle <= 0 || index < 0 || index >= engine_slots.length() {
    None
  } else {
    Some(index)
  }
}

///|
fn push_engine(engine : @engine.ClapSynthEngine) -> Int {
  for i = 0; i < engine_slots.length(); i = i + 1 {
    match engine_slots[i] {
      None => {
        engine_slots[i] = Some(engine)
        return i + 1
      }
      Some(_) => ()
    }
  }
  engine_slots.push(Some(engine))
  engine_slots.length()
}

///|
fn get_engine(handle : Int) -> @engine.ClapSynthEngine? {
  match valid_handle_index(handle) {
    Some(index) => engine_slots[index]
    None => None
  }
}

///|
/// Create a CLAP synth engine slot and return its positive handle.
///
/// Returns `0` on validation or initialization failure. This flat primitive
/// API is intended for a C CLAP shim; it deliberately avoids returning
/// MoonBit objects or `Result` values across the native boundary.
pub fn engine_create(
  sample_rate : Double,
  max_block_size : Int,
  max_voices : Int,
) -> Int {
  match
    @engine.ClapSynthEngine::new(sample_rate~, max_block_size~, max_voices~) {
    Ok(engine) => push_engine(engine)
    Err(_) => 0
  }
}

///|
/// Destroy an engine handle. Returns `false` for stale/invalid handles.
pub fn engine_destroy(handle : Int) -> Bool {
  match valid_handle_index(handle) {
    None => false
    Some(index) =>
      match engine_slots[index] {
        None => false
        Some(engine) => {
          engine.all_notes_off()
          engine_slots[index] = None
          true
        }
      }
  }
}

///|
pub fn engine_note_on(
  handle : Int,
  note_id : Int,
  key : Int,
  velocity : Double,
) -> Bool {
  match get_engine(handle) {
    Some(engine) => engine.note_on(note_id~, key~, velocity~)
    None => false
  }
}

///|
pub fn engine_note_off(handle : Int, note_id : Int, key : Int) -> Bool {
  match get_engine(handle) {
    Some(engine) => engine.note_off(note_id~, key~)
    None => false
  }
}

///|
pub fn engine_all_notes_off(handle : Int) -> Bool {
  match get_engine(handle) {
    Some(engine) => {
      engine.all_notes_off()
      true
    }
    None => false
  }
}

///|
pub fn engine_set_param(handle : Int, param_id : Int, value : Double) -> Bool {
  match get_engine(handle) {
    Some(engine) => engine.set_param(param_id, value)
    None => false
  }
}

///|
/// Render up to the engine's preallocated max block size.
///
/// Returns the actual processed frame count, or `0` for an invalid handle.
pub fn engine_process(handle : Int, frame_count : Int) -> Int {
  match get_engine(handle) {
    Some(engine) => engine.process(frame_count)
    None => 0
  }
}

///|
pub fn engine_left_sample(handle : Int, index : Int) -> Double {
  match get_engine(handle) {
    Some(engine) => engine.left_sample(index)
    None => 0.0
  }
}

///|
pub fn engine_right_sample(handle : Int, index : Int) -> Double {
  match get_engine(handle) {
    Some(engine) => engine.right_sample(index)
    None => 0.0
  }
}

///|
pub fn engine_master_gain(handle : Int) -> Double {
  match get_engine(handle) {
    Some(engine) => engine.master_gain()
    None => 0.0
  }
}

///|
pub fn engine_voice_gain(handle : Int) -> Double {
  match get_engine(handle) {
    Some(engine) => engine.voice_gain()
    None => 0.0
  }
}

///|
pub fn engine_cutoff_hz(handle : Int) -> Double {
  match get_engine(handle) {
    Some(engine) => engine.cutoff_hz()
    None => 0.0
  }
}

///|
pub fn engine_resonance(handle : Int) -> Double {
  match get_engine(handle) {
    Some(engine) => engine.resonance()
    None => 0.0
  }
}

///|
pub fn engine_pan(handle : Int) -> Double {
  match get_engine(handle) {
    Some(engine) => engine.pan()
    None => 0.0
  }
}
