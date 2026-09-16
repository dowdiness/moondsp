///|
pub fn audio_power_new(
  options : NativeValue,
  graph_engine_factory : NativeValue,
) -> NativeValue {
  Owner(options, graph_engine_factory).to_js()
}

///|
pub fn audio_power_turn_on(
  owner : NativeValue,
  setup_audio : NativeValue,
) -> NativeValue {
  match Owner::from_js(owner).turn_on(setup_audio) {
    Ok(generation) =>
      started_result(
        generation,
        generation.context,
        generation.ready(),
        generation.ended(),
      )
    Err(error) => start_error(error)
  }
}

///|
pub fn powered_audio_resume(
  generation_handle : NativeValue,
) -> @js_async.Promise[NativeValue] {
  Generation::from_js(generation_handle).resume_audio()
}

///|
pub fn powered_audio_turn_off(
  generation_handle : NativeValue,
) -> @js_async.Promise[NativeValue] {
  Generation::from_js(generation_handle).turn_off()
}

///|
fn main {
  ()
}
