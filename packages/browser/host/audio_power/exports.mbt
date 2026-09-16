///|
pub fn audio_power_new(
  options : NativeValue,
  graph_engine_factory : NativeValue,
) -> NativeValue {
  export_owner_handle(OwnerState(options, graph_engine_factory))
}

///|
pub fn audio_power_turn_on(
  owner : NativeValue,
  setup_audio : NativeValue,
) -> NativeValue {
  let owner = import_owner_handle(owner)
  guard native_is_callable(setup_audio) else {
    return encode_start_failure(native_invalid_setup_error())
  }
  match owner.current {
    Occupied =>
      return encode_start_failure(
        native_create_dom_exception(
          "Audio is already powered on", "InvalidStateError",
        ),
      )
    Vacant => owner.current = Occupied
  }
  let predecessor_cleanups = owner.pending_retirements
  match decode_native_result(native_create_context(owner.options)) {
    Failed(error) => {
      owner.current = Vacant
      encode_start_failure(error)
    }
    Succeeded(value) => {
      let context = native_context_from_value(value)
      let generation = Generation(owner, context)
      native_listen_for_context_state_changes(
        context,
        generation.retirement_controller.signal(),
        () => {
          if read_context_playback_state(context) is Closed {
            begin_generation_retirement(generation, None)
          }
        },
      )
      // No async boundary, Promise callback, or scheduler hop before this call.
      let admission_resume = native_resume(context)
      start_audio_generation(
        generation, setup_audio, admission_resume, predecessor_cleanups,
      )
      encode_started_generation(
        generation,
        context,
        native_promise(generation.ready),
        native_promise(generation.ended),
      )
    }
  }
}

///|
pub fn powered_audio_resume(
  generation_handle : NativeValue,
) -> @js_async.Promise[NativeValue] {
  let generation = import_generation_handle(generation_handle)
  match generation.state {
    Restoring(_, pending_resume) => native_promise(pending_resume)
    Ready(engine) => {
      guard generation.readiness is Resolved else {
        return native_rejected(
          native_create_dom_exception("Audio is not ready", "InvalidStateError"),
        )
      }
      match read_context_playback_state(engine.context) {
        Playing => native_resolved()
        TemporarilyUnavailable => start_context_resume(generation, engine)
        Closed => {
          begin_generation_retirement(generation, None)
          native_rejected(
            native_create_dom_exception(
              "The audio context is closed", "InvalidStateError",
            ),
          )
        }
      }
    }
    Admitting(_)
    | Suspending(_)
    | WaitingForEngineGate(_)
    | CreatingEngine(_, _)
    | SettingUp(_)
    | Resuming(_, _)
    | Retiring(_)
    | Ended(_) =>
      native_rejected(
        native_create_dom_exception("Audio is not ready", "InvalidStateError"),
      )
  }
}

///|
pub fn powered_audio_turn_off(
  generation_handle : NativeValue,
) -> @js_async.Promise[NativeValue] {
  let generation = import_generation_handle(generation_handle)
  begin_generation_retirement(generation, None)
  native_promise(generation.turn_off_result)
}

///|
fn main {
  ()
}
