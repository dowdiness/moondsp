///|
/// Stable C ABI for the CLAP shim (`moondsp_clap.c`). `#export_name` fixes each
/// symbol name, so the shim no longer depends on MoonBit's package mangling.
/// Bool results cross as `int32_t` 1 or 0; `moondsp_clap_moonbit.h` declares
/// the same signatures.
fn bool_abi(value : Bool) -> Int32 {
  if value {
    1
  } else {
    0
  }
}

///|
#export_name("mb_engine_create")
pub fn mb_engine_create(
  sample_rate : Double,
  max_block_size : Int32,
  max_voices : Int32,
) -> Int32 {
  @host.engine_create(sample_rate, max_block_size, max_voices)
}

///|
#export_name("mb_engine_destroy")
pub fn mb_engine_destroy(handle : Int32) -> Int32 {
  bool_abi(@host.engine_destroy(handle))
}

///|
#export_name("mb_engine_note_on")
pub fn mb_engine_note_on(
  handle : Int32,
  note_id : Int32,
  key : Int32,
  velocity : Double,
) -> Int32 {
  bool_abi(@host.engine_note_on(handle, note_id, key, velocity))
}

///|
#export_name("mb_engine_note_off")
pub fn mb_engine_note_off(
  handle : Int32,
  note_id : Int32,
  key : Int32,
) -> Int32 {
  bool_abi(@host.engine_note_off(handle, note_id, key))
}

///|
#export_name("mb_engine_all_notes_off")
pub fn mb_engine_all_notes_off(handle : Int32) -> Int32 {
  bool_abi(@host.engine_all_notes_off(handle))
}

///|
#export_name("mb_engine_set_param")
pub fn mb_engine_set_param(
  handle : Int32,
  param_id : Int32,
  value : Double,
) -> Int32 {
  bool_abi(@host.engine_set_param(handle, param_id, value))
}

///|
#export_name("mb_engine_process")
pub fn mb_engine_process(handle : Int32, frame_count : Int32) -> Int32 {
  @host.engine_process(handle, frame_count)
}

///|
#export_name("mb_engine_left_sample")
pub fn mb_engine_left_sample(handle : Int32, index : Int32) -> Double {
  @host.engine_left_sample(handle, index)
}

///|
#export_name("mb_engine_right_sample")
pub fn mb_engine_right_sample(handle : Int32, index : Int32) -> Double {
  @host.engine_right_sample(handle, index)
}

///|
#export_name("mb_engine_master_gain")
pub fn mb_engine_master_gain(handle : Int32) -> Double {
  @host.engine_master_gain(handle)
}

///|
#export_name("mb_engine_voice_gain")
pub fn mb_engine_voice_gain(handle : Int32) -> Double {
  @host.engine_voice_gain(handle)
}

///|
#export_name("mb_engine_cutoff_hz")
pub fn mb_engine_cutoff_hz(handle : Int32) -> Double {
  @host.engine_cutoff_hz(handle)
}

///|
#export_name("mb_engine_resonance")
pub fn mb_engine_resonance(handle : Int32) -> Double {
  @host.engine_resonance(handle)
}

///|
#export_name("mb_engine_pan")
pub fn mb_engine_pan(handle : Int32) -> Double {
  @host.engine_pan(handle)
}
