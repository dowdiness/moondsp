///|
// The single post-await liveness check. Retirement cancels observation through
// the surrounding task group; resource acquisition has a protected child owner.
async fn await_owned(
  gen : Generation,
  operation : async () -> NativeOutcome,
) -> AwaitOutcome {
  guard is_live(gen) else { return Retired }
  let completion = operation()
  guard is_live(gen) else { return Retired }
  if disposition(gen.context) is Closed {
    begin_retirement(gen, None)
    return Retired
  }
  match completion {
    Failed(error) => {
      begin_retirement(gen, Some(error))
      Retired
    }
    Succeeded(value) => Completed(value)
  }
}

///|
fn begin_retirement(gen : Generation, primary : @host.NativeError?) -> Unit {
  let stage = match gen.state {
    Admitting(context) | Suspending(context) | WaitingForEngineGate(context) =>
      ClosingContext(context)
    CreatingEngine(context, pending) =>
      ResolvingEngineAcquisition(context, pending)
    SettingUp(engine) | Resuming(engine, _) => Disconnecting(engine)
    Ready(engine) => Disconnecting(engine)
    Restoring(engine, pending_resume) => {
      let error = match primary {
        Some(error) => error
        None => native_error("Audio was turned off", "AbortError")
      }
      native_reject(pending_resume, error)
      Disconnecting(engine)
    }
    Retiring(_) | Ended(_) => return
  }
  let retirement = Retirement(stage, primary)
  gen.state = Retiring(retirement)
  gen.owner.current = Vacant
  // Capture every pending predecessor BEFORE abort invokes arbitrary listeners.
  // Persistent snapshots keep reentrant replacements gated without a join task.
  gen.owner.retirement_tail = gen.owner.retirement_tail
    .drop_while(completion => completion.value is Some(_))
    .prepend(gen.stopped)
  match primary {
    Some(error) => {
      reject_ready(gen, error)
      ignore(publish_end(gen, native_failed_end(error)))
    }
    None =>
      reject_ready(gen, native_error("Audio setup was aborted", "AbortError"))
  }
  gen.controller.abort()
}

///|
async fn cleanup_generation(gen : Generation, retirement : Retirement) -> Unit {
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
        match parse_outcome(native_disconnect(engine.native)) {
          Failed(error) => remember_cleanup(retirement, error)
          Succeeded(_) => ()
        }
        retirement.stage = ClosingEngine(engine)
      }
      ClosingEngine(engine) => {
        match engine.lifetime.close() {
          Err(error) => remember_cleanup(retirement, error.native())
          Ok(_) => ()
        }
        retirement.stage = ClosingContext(engine.context)
      }
      ClosingContext(context) => {
        if !(disposition(context) is Closed) {
          match parse_outcome(native_close_context(context).wait()) {
            Failed(error) => remember_cleanup(retirement, error)
            Succeeded(_) => ()
          }
        }
        retirement.stage = Complete
      }
      Complete => {
        finish_retirement(gen, retirement)
        break
      }
    }
  }
}

///|
fn finish_retirement(gen : Generation, retirement : Retirement) -> Unit {
  let result = match retirement.primary {
    Some(error) => native_failed_end(error)
    None =>
      match retirement.cleanup_error {
        Some(error) => native_failed_end(error)
        None => native_clean_end()
      }
  }
  let retained = publish_end(gen, result)
  gen.state = Ended(retained)
  match retirement.cleanup_error {
    Some(error) => native_reject(gen.off, error)
    None => native_resolve(gen.off, native_unit())
  }
  gen.stopped.complete(())
}

///|
async fn setup_flow(
  gen : Generation,
  setup : NativeValue,
  admission : @js_async.Promise[NativeResult],
  group : @async.TaskGroup[Unit],
  gate : @list.List[Completion[Unit]],
) -> Unit {
  guard await_owned(gen, () => observe_operation(admission)) is Completed(_) else {
    return
  }
  gen.state = Suspending(gen.context)
  guard await_owned(gen, () => observe_operation(native_suspend(gen.context)))
    is Completed(_) else {
    return
  }
  gen.state = WaitingForEngineGate(gen.context)
  guard await_owned(gen, () => {
      wait_for_gate(gate)
      Succeeded(native_unit())
    })
    is Completed(_) else {
    return
  }
  let pending : Completion[NativeOutcome] = Completion()
  gen.state = CreatingEngine(gen.context, pending)
  let creation = native_graph_engine(
    gen.owner.factory,
    gen.context,
    gen.owner.options,
    gen.controller.signal(),
  )
  group.spawn_bg(no_wait=true, () => {
    @async.protect_from_cancel(() => {
      pending.complete(parse_outcome(creation.wait()))
    })
  })
  guard await_owned(gen, () => pending.wait()) is Completed(value) else {
    return
  }
  let engine = OwnedEngine(gen.context, native_engine_from_value(value))
  gen.state = SettingUp(engine)
  group.spawn_bg(no_wait=true, () => watch_processor(gen, engine))
  guard await_owned(gen, () => {
      observe_operation(
        native_setup(setup, gen.context, engine.native, gen.controller.signal()),
      )
    })
    is Completed(value) else {
    return
  }
  gen.state = Resuming(engine, value)
  guard await_owned(gen, () => observe_operation(native_resume(gen.context)))
    is Completed(_) else {
    return
  }
  // Treat connection as potentially partially effective: retirement must attempt
  // disconnect even if native connect throws after making the connection.
  match parse_outcome(native_connect(engine.native, gen.context)) {
    Failed(error) => begin_retirement(gen, Some(error))
    Succeeded(_) =>
      if is_live(gen) {
        gen.state = Ready(engine)
        gen.readiness = Resolved
        native_resolve(gen.ready, value)
      }
  }
}

///|
async fn watch_processor(gen : Generation, engine : OwnedEngine) -> Unit {
  match engine.lifetime.wait() {
    @host.EngineExit::Failed(error) =>
      begin_retirement(gen, Some(error.native()))
    @host.EngineExit::Closed => begin_retirement(gen, None)
  }
}

///|
async fn wait_for_gate(gate : @list.List[Completion[Unit]]) -> Unit {
  for completion in gate.iter() {
    completion.wait()
  }
}

///|
// One JS entry task owns setup, processor observation, and late acquisition.
// Cancel/join its children first, then complete resource cleanup without cancellation.
fn supervise(
  gen : Generation,
  run : async (@async.TaskGroup[Unit]) -> Unit,
) -> Unit {
  ignore(
    @js_async.Promise::from_async(() => {
      @async.with_task_group(group => {
        group.spawn_bg(no_wait=true, () => run(group))
        wait_for_retirement(gen)
      }) catch {
        error => begin_retirement(gen, Some(native_defect(error.to_string())))
      }
      guard gen.state is Retiring(retirement) else {
        fail("retirement signal without a retiring generation")
      }
      @async.protect_from_cancel(() => {
        cleanup_generation(gen, retirement) catch {
          error => {
            remember_cleanup(retirement, native_defect(error.to_string()))
            // Native failures are values; only MoonBit defects reach this catch.
            finish_retirement(gen, retirement)
          }
        }
      })
    }),
  )
}

///|
fn launch_setup(
  gen : Generation,
  setup : NativeValue,
  admission : @js_async.Promise[NativeResult],
  gate : @list.List[Completion[Unit]],
) -> Unit {
  supervise(gen, group => setup_flow(gen, setup, admission, group, gate))
}

///|
fn restore(
  gen : Generation,
  engine : OwnedEngine,
) -> @js_async.Promise[NativeValue] {
  let pending_resume = native_deferred()
  gen.state = Restoring(engine, pending_resume)
  let operation = native_resume(gen.context)
  ignore(
    @js_async.Promise::from_async(() => {
      @async.with_task_group(group => {
        group.spawn_bg(no_wait=true, () => {
          wait_for_retirement(gen)
          group.return_immediately(())
        })
        if await_owned(gen, () => observe_operation(operation)) is Completed(_) {
          gen.state = Ready(engine)
          native_resolve(pending_resume, native_unit())
        }
      }) catch {
        error => begin_retirement(gen, Some(native_defect(error.to_string())))
      }
    }),
  )
  native_promise(pending_resume)
}
