///|
// The single post-await liveness check. Retirement cancels observation through
// the surrounding task group; resource acquisition has a protected child owner.
async fn await_success_or_retire(
  generation : Generation,
  perform_operation : async () -> NativeOutcome,
) -> AwaitOutcome {
  guard is_generation_live(generation) else { return Retired }
  let completion = perform_operation()
  guard is_generation_live(generation) else { return Retired }
  if read_context_playback_state(generation.context) is Closed {
    begin_generation_retirement(generation, None)
    return Retired
  }
  match completion {
    Failed(error) => {
      begin_generation_retirement(generation, Some(error))
      Retired
    }
    Succeeded(value) => Completed(value)
  }
}

///|
fn begin_generation_retirement(
  generation : Generation,
  primary_error : @host.NativeError?,
) -> Unit {
  let stage = match generation.state {
    Admitting(context) | Suspending(context) | WaitingForEngineGate(context) =>
      ClosingContext(context)
    CreatingEngine(context, pending) =>
      ResolvingEngineAcquisition(context, pending)
    SettingUp(engine) | Resuming(engine, _) => Disconnecting(engine)
    Ready(engine) => Disconnecting(engine)
    Restoring(engine, pending_resume) => {
      let error = match primary_error {
        Some(error) => error
        None =>
          native_create_dom_exception("Audio was turned off", "AbortError")
      }
      native_reject(pending_resume, error)
      Disconnecting(engine)
    }
    Retiring(_) | Ended(_) => return
  }
  let retirement = Retirement(stage, primary_error)
  generation.state = Retiring(retirement)
  generation.owner.current = Vacant
  // Capture every pending predecessor BEFORE abort invokes arbitrary listeners.
  // Persistent snapshots keep reentrant replacements gated without a join task.
  generation.owner.pending_retirements = generation.owner.pending_retirements
    .drop_while(completion => completion.value is Some(_))
    .prepend(generation.cleanup_finished)
  match primary_error {
    Some(error) => {
      reject_pending_readiness(generation, error)
      ignore(
        publish_end_once(generation, native_create_failed_end_result(error)),
      )
    }
    None =>
      reject_pending_readiness(
        generation,
        native_create_dom_exception("Audio setup was aborted", "AbortError"),
      )
  }
  generation.retirement_controller.abort()
}

///|
async fn close_generation_resources(
  generation : Generation,
  retirement : Retirement,
) -> Unit {
  for ;; {
    match retirement.stage {
      ResolvingEngineAcquisition(context, pending) =>
        // GraphEngine abort settles creation without waiting for fetch/compile.
        // A success already in flight is handed to this sole disposing owner.
        match pending.wait() {
          Succeeded(value) =>
            retirement.stage = ClosingEngine(
              OwnedEngine(context, native_engine_from_value(value)),
            )
          Failed(_) => retirement.stage = ClosingContext(context)
        }
      Disconnecting(engine) => {
        match decode_native_result(native_disconnect_output(engine.native)) {
          Failed(error) => retain_first_cleanup_error(retirement, error)
          Succeeded(_) => ()
        }
        retirement.stage = ClosingEngine(engine)
      }
      ClosingEngine(engine) => {
        match engine.lifetime.close() {
          Err(error) => retain_first_cleanup_error(retirement, error.native())
          Ok(_) => ()
        }
        retirement.stage = ClosingContext(engine.context)
      }
      ClosingContext(context) => {
        if !(read_context_playback_state(context) is Closed) {
          match decode_native_result(native_close_context(context).wait()) {
            Failed(error) => retain_first_cleanup_error(retirement, error)
            Succeeded(_) => ()
          }
        }
        retirement.stage = Complete
      }
      Complete => {
        complete_generation_retirement(generation, retirement)
        break
      }
    }
  }
}

///|
fn complete_generation_retirement(
  generation : Generation,
  retirement : Retirement,
) -> Unit {
  let result = match retirement.primary_error {
    Some(error) => native_create_failed_end_result(error)
    None =>
      match retirement.cleanup_error {
        Some(error) => native_create_failed_end_result(error)
        None => native_create_turned_off_result()
      }
  }
  let retained = publish_end_once(generation, result)
  generation.state = Ended(retained)
  match retirement.cleanup_error {
    Some(error) => native_reject(generation.turn_off_result, error)
    None => native_resolve(generation.turn_off_result, native_unit())
  }
  generation.cleanup_finished.complete(())
}

///|
async fn initialize_generation_audio(
  generation : Generation,
  setup_audio : NativeValue,
  admission_resume : @js_async.Promise[NativeResult],
  lifetime_tasks : @async.TaskGroup[Unit],
  predecessor_cleanups : @list.List[Completion[Unit]],
) -> Unit {
  guard await_success_or_retire(generation, () => {
      await_browser_operation(admission_resume)
    })
    is Completed(_) else {
    return
  }
  generation.state = Suspending(generation.context)
  guard await_success_or_retire(generation, () => {
      await_browser_operation(native_suspend(generation.context))
    })
    is Completed(_) else {
    return
  }
  generation.state = WaitingForEngineGate(generation.context)
  guard await_success_or_retire(generation, () => {
      wait_for_predecessor_cleanup(predecessor_cleanups)
      Succeeded(native_unit())
    })
    is Completed(_) else {
    return
  }
  let engine_acquisition : Completion[NativeOutcome] = Completion()
  generation.state = CreatingEngine(generation.context, engine_acquisition)
  let engine_creation = native_create_graph_engine(
    generation.owner.graph_engine_factory,
    generation.context,
    generation.owner.options,
    generation.retirement_controller.signal(),
  )
  lifetime_tasks.spawn_bg(no_wait=true, () => {
    @async.protect_from_cancel(() => {
      engine_acquisition.complete(decode_native_result(engine_creation.wait()))
    })
  })
  guard await_success_or_retire(generation, () => engine_acquisition.wait())
    is Completed(engine_value) else {
    return
  }
  let engine = OwnedEngine(
    generation.context,
    native_engine_from_value(engine_value),
  )
  generation.state = SettingUp(engine)
  lifetime_tasks.spawn_bg(no_wait=true, () => {
    retire_when_engine_exits(generation, engine)
  })
  guard await_success_or_retire(generation, () => {
      await_browser_operation(
        native_call_setup_audio(
          setup_audio,
          generation.context,
          engine.native,
          generation.retirement_controller.signal(),
        ),
      )
    })
    is Completed(setup_value) else {
    return
  }
  generation.state = Resuming(engine, setup_value)
  guard await_success_or_retire(generation, () => {
      await_browser_operation(native_resume(generation.context))
    })
    is Completed(_) else {
    return
  }
  // Treat connection as potentially partially effective: retirement must attempt
  // disconnect even if native connect throws after making the connection.
  match
    decode_native_result(
      native_connect_output_to_destination(engine.native, generation.context),
    ) {
    Failed(error) => begin_generation_retirement(generation, Some(error))
    Succeeded(_) =>
      if is_generation_live(generation) {
        generation.state = Ready(engine)
        generation.readiness = Resolved
        native_resolve(generation.ready, setup_value)
      }
  }
}

///|
async fn retire_when_engine_exits(
  generation : Generation,
  engine : OwnedEngine,
) -> Unit {
  match engine.lifetime.wait() {
    @host.EngineExit::Failed(error) =>
      begin_generation_retirement(generation, Some(error.native()))
    @host.EngineExit::Closed => begin_generation_retirement(generation, None)
  }
}

///|
async fn wait_for_predecessor_cleanup(
  predecessor_cleanups : @list.List[Completion[Unit]],
) -> Unit {
  for completion in predecessor_cleanups.iter() {
    completion.wait()
  }
}

///|
// One JS entry task owns setup, processor observation, and late acquisition.
// Cancel/join its children first, then complete resource cleanup without cancellation.
fn start_generation_supervisor(
  generation : Generation,
  run_startup : async (@async.TaskGroup[Unit]) -> Unit,
) -> Unit {
  ignore(
    @js_async.Promise::from_async(() => {
      @async.with_task_group(group => {
        group.spawn_bg(no_wait=true, () => run_startup(group))
        wait_for_retirement_request(generation)
      }) catch {
        error =>
          begin_generation_retirement(
            generation,
            Some(native_create_internal_error(error.to_string())),
          )
      }
      guard generation.state is Retiring(retirement) else {
        fail("retirement signal without a retiring generation")
      }
      @async.protect_from_cancel(() => {
        close_generation_resources(generation, retirement) catch {
          error => {
            retain_first_cleanup_error(
              retirement,
              native_create_internal_error(error.to_string()),
            )
            // Native failures are values; only MoonBit defects reach this catch.
            complete_generation_retirement(generation, retirement)
          }
        }
      })
    }),
  )
}

///|
fn start_audio_generation(
  generation : Generation,
  setup_audio : NativeValue,
  admission_resume : @js_async.Promise[NativeResult],
  predecessor_cleanups : @list.List[Completion[Unit]],
) -> Unit {
  start_generation_supervisor(generation, group => {
    initialize_generation_audio(
      generation, setup_audio, admission_resume, group, predecessor_cleanups,
    )
  })
}

///|
fn start_context_resume(
  generation : Generation,
  engine : OwnedEngine,
) -> @js_async.Promise[NativeValue] {
  let pending_resume = native_create_deferred()
  generation.state = Restoring(engine, pending_resume)
  let resume_operation = native_resume(generation.context)
  ignore(
    @js_async.Promise::from_async(() => {
      @async.with_task_group(group => {
        group.spawn_bg(no_wait=true, () => {
          wait_for_retirement_request(generation)
          group.return_immediately(())
        })
        if await_success_or_retire(generation, () => {
            await_browser_operation(resume_operation)
          })
          is Completed(_) {
          generation.state = Ready(engine)
          native_resolve(pending_resume, native_unit())
        }
      }) catch {
        error =>
          begin_generation_retirement(
            generation,
            Some(native_create_internal_error(error.to_string())),
          )
      }
    }),
  )
  native_promise(pending_resume)
}
