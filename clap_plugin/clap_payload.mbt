///|
/// Anchor the primitive CLAP host bridge in a native main package so `moon build
/// --target native clap_plugin` emits C for the MoonBit payload that a custom
/// CLAP shared-library build can link with a C ABI shim.
fn payload_anchor() -> Int {
  let handle = @host.engine_create(48000.0, 128, 1)
  if handle <= 0 {
    return 0
  }
  ignore(@host.engine_set_param(handle, @engine.CLAP_PARAM_MASTER_GAIN, 0.5))
  ignore(@host.engine_set_param(handle, @engine.CLAP_PARAM_VOICE_GAIN, 0.25))
  ignore(@host.engine_set_param(handle, @engine.CLAP_PARAM_CUTOFF_HZ, 1200.0))
  ignore(@host.engine_set_param(handle, @engine.CLAP_PARAM_RESONANCE, 0.8))
  ignore(@host.engine_set_param(handle, @engine.CLAP_PARAM_PAN, 0.0))
  ignore(@host.engine_note_on(handle, 0, 69, 1.0))
  ignore(@host.engine_process(handle, 16))
  ignore(@host.engine_left_sample(handle, 0))
  ignore(@host.engine_right_sample(handle, 0))
  ignore(@host.engine_master_gain(handle))
  ignore(@host.engine_voice_gain(handle))
  ignore(@host.engine_cutoff_hz(handle))
  ignore(@host.engine_resonance(handle))
  ignore(@host.engine_pan(handle))
  ignore(@host.engine_note_off(handle, 0, 69))
  ignore(@host.engine_all_notes_off(handle))
  ignore(@host.engine_destroy(handle))
  1
}

///|
fn main {
  // This package is a native C payload generator, not a CLI. Keep main empty so
  // `moon build --target native clap_plugin` succeeds while custom CLAP build
  // scripts can link the generated C without invoking `main`.
  ignore(payload_anchor)
}
