///|
pub fn audio_power_new(
  options : NativeValue,
  graph_engine_factory : NativeValue,
) -> NativeValue {
  owner_value(OwnerState(options, graph_engine_factory))
}

///|
pub fn audio_power_turn_on(
  owner : NativeValue,
  setup : NativeValue,
) -> NativeValue {
  let owner = owner_from_value(owner)
  guard native_callable(setup) else {
    return started_error(native_type_error())
  }
  match owner.current {
    Occupied =>
      return started_error(
        native_error("Audio is already powered on", "InvalidStateError"),
      )
    Vacant => owner.current = Occupied
  }
  let gate = owner.retirement_tail
  match parse_outcome(native_context(owner.options)) {
    Failed(error) => {
      owner.current = Vacant
      started_error(error)
    }
    Succeeded(value) => {
      let context = native_context_from_value(value)
      let gen = Generation(owner, context)
      native_listen(context, gen.controller.signal(), () => {
        if disposition(context) is Closed {
          begin_retirement(gen, None)
        }
      })
      // No async boundary, Promise callback, or scheduler hop before this call.
      let admission = native_resume(context)
      launch_setup(gen, setup, admission, gate)
      started_ok(
        gen,
        context,
        native_promise(gen.ready),
        native_promise(gen.ended),
      )
    }
  }
}

///|
pub fn powered_audio_resume(
  generation : NativeValue,
) -> @js_async.Promise[NativeValue] {
  let gen = generation_from_value(generation)
  match gen.state {
    Restoring(_, pending_resume) => native_promise(pending_resume)
    Ready(engine) => {
      guard gen.readiness is Resolved else {
        return native_rejected(
          native_error("Audio is not ready", "InvalidStateError"),
        )
      }
      match disposition(engine.context) {
        Playing => native_resolved()
        TemporarilyUnavailable => restore(gen, engine)
        Closed => {
          begin_retirement(gen, None)
          native_rejected(
            native_error("The audio context is closed", "InvalidStateError"),
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
      native_rejected(native_error("Audio is not ready", "InvalidStateError"))
  }
}

///|
pub fn powered_audio_turn_off(
  generation : NativeValue,
) -> @js_async.Promise[NativeValue] {
  let gen = generation_from_value(generation)
  begin_retirement(gen, None)
  native_promise(gen.off)
}

///|
fn main {
  ()
}
