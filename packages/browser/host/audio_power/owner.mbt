///|
// This is the only post-await liveness arbitration path. CreatingEngine installs
// its pending-result owner in the state before invoking the factory, so cleanup
// already owns any losing acquisition. Non-resource results can be detached.
async fn await_owned(
  gen : Generation,
  operation : @js_async.Promise[NativeResult],
) -> AwaitOutcome {
  guard is_live(gen) else { return Retired }
  let completion = @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => {
      ignore(
        native_promise(gen.retired).wait(
          abort_controller=@js_async.AbortController::new(),
        ),
      )
      group.return_immediately(Retired)
    })
    // This controller cancels only the waiter, not the underlying operation.
    // Engine acquisition is retained by CreatingEngine/Retirement independently.
    Completed(
      parse_outcome(
        operation.wait(abort_controller=@js_async.AbortController::new()),
      ),
    )
  })
  guard is_live(gen) else { return Retired }
  if disposition(gen.context) is Closed {
    begin_retirement(gen, None)
    return Retired
  }
  match completion {
    Completed(Failed(error)) => {
      begin_retirement(gen, Some(error))
      Retired
    }
    Completed(Succeeded(_)) => completion
    Retired => Retired
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
  let previous = gen.owner.retirement_tail
  // Register the cumulative barrier BEFORE abort invokes arbitrary user listeners.
  gen.owner.retirement_tail = @js_async.Promise::from_async(() => {
    ignore(previous.wait())
    ignore(native_promise(gen.stopped).wait())
    native_unit()
  })
  match primary {
    Some(error) => {
      reject_ready(gen, error)
      ignore(publish_end(gen, native_failed_end(error)))
    }
    None =>
      reject_ready(gen, native_error("Audio setup was aborted", "AbortError"))
  }
  native_resolve(gen.retired, native_unit())
  gen.controller.abort()
  ignore(
    @js_async.Promise::from_async(() => {
      @async.protect_from_cancel(() => {
        cleanup_generation(gen, retirement) catch {
          error => {
            remember_cleanup(retirement, native_defect(error.to_string()))
            // Native failures are values; this catch quarantines only MoonBit defects.
            finish_retirement(gen, retirement)
          }
        }
      })
    }),
  )
}

///|
async fn cleanup_generation(gen : Generation, retirement : Retirement) -> Unit {
  for ;; {
    match retirement.stage {
      ResolvingEngineAcquisition(context, pending) =>
        // GraphEngine abort settles creation without waiting for fetch/compile.
        // A success already in flight is handed to this sole disposing owner.
        match parse_outcome(native_result_promise(pending).wait()) {
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
  native_resolve(gen.stopped, native_unit())
}

///|
async fn setup_flow(
  gen : Generation,
  setup : NativeValue,
  admission : @js_async.Promise[NativeResult],
  gate : @js_async.Promise[NativeValue],
) -> Unit {
  guard await_owned(gen, admission) is Completed(Succeeded(_)) else { return }
  gen.state = Suspending(gen.context)
  guard await_owned(gen, native_suspend(gen.context)) is Completed(Succeeded(_)) else {
    return
  }
  gen.state = WaitingForEngineGate(gen.context)
  guard await_owned(gen, native_as_outcome(gate)) is Completed(Succeeded(_)) else {
    return
  }
  let pending = native_deferred()
  gen.state = CreatingEngine(gen.context, pending)
  let creation = native_graph_engine(
    gen.owner.factory,
    gen.context,
    gen.owner.options,
    gen.controller.signal(),
  )
  native_forward_result(creation, pending)
  guard await_owned(gen, native_result_promise(pending))
    is Completed(Succeeded(value)) else {
    return
  }
  let engine = OwnedEngine(gen.context, native_engine_from_value(value))
  gen.state = SettingUp(engine)
  watch_processor(gen, engine)
  guard await_owned(
      gen,
      native_setup(setup, gen.context, engine.native, gen.controller.signal()),
    )
    is Completed(Succeeded(value)) else {
    return
  }
  gen.state = Resuming(engine, value)
  guard await_owned(gen, native_resume(gen.context)) is Completed(Succeeded(_)) else {
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
fn watch_processor(gen : Generation, engine : OwnedEngine) -> Unit {
  ignore(
    @js_async.Promise::from_async(() => {
      try {
        let exit = @async.with_task_group(group => {
          group.spawn_bg(no_wait=true, () => {
            ignore(
              native_promise(gen.retired).wait(
                abort_controller=@js_async.AbortController::new(),
              ),
            )
            group.return_immediately(None)
          })
          Some(engine.lifetime.wait())
        })
        match exit {
          Some(@host.EngineExit::Failed(error)) =>
            begin_retirement(gen, Some(error.native()))
          Some(@host.EngineExit::Closed) => begin_retirement(gen, None)
          None => () // Retirement cancelled and joined the observation, not cleanup.
        }
      } catch {
        error => begin_retirement(gen, Some(native_defect(error.to_string())))
      }
    }),
  )
}

///|
fn launch_setup(
  gen : Generation,
  setup : NativeValue,
  admission : @js_async.Promise[NativeResult],
  gate : @js_async.Promise[NativeValue],
) -> Unit {
  ignore(
    @js_async.Promise::from_async(() => {
      setup_flow(gen, setup, admission, gate) catch {
        error => begin_retirement(gen, Some(native_defect(error.to_string())))
      }
    }),
  )
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
      try {
        match await_owned(gen, operation) {
          Completed(Succeeded(_)) => {
            gen.state = Ready(engine)
            native_resolve(pending_resume, native_unit())
          }
          Completed(Failed(_)) => fail("unhandled native failure")
          Retired => () // begin_retirement rejected the retained resume promise.
        }
      } catch {
        error => begin_retirement(gen, Some(native_defect(error.to_string())))
      }
    }),
  )
  native_promise(pending_resume)
}
