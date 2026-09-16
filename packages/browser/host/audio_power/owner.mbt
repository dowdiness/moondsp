///|
fn Owner::turn_on(
  self : Owner,
  setup : NativeValue,
) -> Result[Generation, @host.NativeError] {
  guard setup.is_callable() else { return Err(native_invalid_setup_error()) }
  match self.current {
    Occupied =>
      return Err(dom_error("Audio is already powered on", "InvalidStateError"))
    Vacant => self.current = Occupied
  }
  let predecessors = self.pending_retirements
  match (self.create_context)(self.options).decode() {
    Failed(error) => {
      self.current = Vacant
      Err(error)
    }
    Succeeded(value) => {
      let context = NativeContext::from_js(value)
      let generation = Generation(self, context)
      context.on_change(generation.retirement_controller.signal(), () => {
        if context.state() is Closed {
          generation.retire(None)
        }
      })
      // Admission stays in the caller's gesture, before entering async code.
      let admission = context.resume_audio()
      generation.start(setup, admission, predecessors)
      Ok(generation)
    }
  }
}

///|
fn Generation::resume_audio(
  self : Generation,
) -> @js_async.Promise[NativeValue] {
  match self.state {
    Restoring(_, pending) => pending.promise()
    Ready(engine) => {
      guard self.readiness is Resolved else {
        return native_rejected(
          dom_error("Audio is not ready", "InvalidStateError"),
        )
      }
      match self.context.state() {
        Playing => native_resolved()
        TemporarilyUnavailable => {
          let pending = NativeDeferred::new()
          self.state = Restoring(engine, pending)
          let operation = self.context.resume_audio()
          ignore(
            @js_async.Promise::from_async(() => {
              @async.with_task_group(group => {
                group.spawn_bg(no_wait=true, () => {
                  self.wait_for_stop()
                  group.return_immediately(())
                })
                if self.step(() => await_browser_operation(operation))
                  is Completed(_) {
                  self.state = Ready(engine)
                  pending.resolve(native_unit())
                }
              }) catch {
                error => self.retire(Some(internal_error(error.to_string())))
              }
            }),
          )
          pending.promise()
        }
        Closed => {
          self.retire(None)
          native_rejected(
            dom_error("The audio context is closed", "InvalidStateError"),
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
      native_rejected(dom_error("Audio is not ready", "InvalidStateError"))
  }
}

///|
fn Generation::turn_off(self : Generation) -> @js_async.Promise[NativeValue] {
  self.retire(None)
  self.turn_off_result.promise()
}

///|
// One task owns startup, observation, late acquisition, and protected cleanup.
fn Generation::start(
  self : Generation,
  setup : NativeValue,
  admission : @js_async.Promise[NativeResult],
  predecessors : @list.List[Completion[Unit]],
) -> Unit {
  ignore(
    @js_async.Promise::from_async(() => {
      @async.with_task_group(group => {
        group.spawn_bg(no_wait=true, () => {
          self.setup(setup, admission, group, predecessors)
        })
        self.wait_for_stop()
      }) catch {
        error => self.retire(Some(internal_error(error.to_string())))
      }
      guard self.state is Retiring(retirement) else {
        fail("retirement signal without a retiring generation")
      }
      @async.protect_from_cancel(() => {
        self.cleanup(retirement) catch {
          error => {
            // Native failures are values; only MoonBit defects reach this catch.
            retirement.record(internal_error(error.to_string()))
            self.finish(retirement)
          }
        }
      })
    }),
  )
}

///|
async fn Generation::setup(
  self : Generation,
  setup : NativeValue,
  admission : @js_async.Promise[NativeResult],
  group : @async.TaskGroup[Unit],
  predecessors : @list.List[Completion[Unit]],
) -> Unit {
  guard self.step(() => await_browser_operation(admission)) is Completed(_) else {
    return
  }
  self.state = Suspending(self.context)
  guard self.step(() => await_browser_operation(self.context.suspend()))
    is Completed(_) else {
    return
  }
  self.state = WaitingForEngineGate(self.context)
  guard self.step(() => {
      for completion in predecessors.iter() {
        completion.wait()
      }
      Succeeded(native_unit())
    })
    is Completed(_) else {
    return
  }
  let acquisition : Completion[NativeOutcome] = Completion()
  self.state = CreatingEngine(self.context, acquisition)
  let creation = create_engine(
    self.owner.graph_engine_factory,
    self.context,
    self.owner.options,
    self.retirement_controller.signal(),
  )
  group.spawn_bg(no_wait=true, () => {
    @async.protect_from_cancel(() => {
      acquisition.complete(creation.wait().decode())
    })
  })
  guard self.step(() => acquisition.wait()) is Completed(value) else { return }
  let engine = OwnedEngine(self.context, native_engine_from_value(value))
  self.state = SettingUp(engine)
  group.spawn_bg(no_wait=true, () => {
    match engine.lifetime.wait() {
      @host.EngineExit::Failed(error) => self.retire(Some(error.native()))
      @host.EngineExit::Closed => self.retire(None)
    }
  })
  guard self.step(() => {
      await_browser_operation(
        call_setup(
          setup,
          self.context,
          engine.native,
          self.retirement_controller.signal(),
        ),
      )
    })
    is Completed(value) else {
    return
  }
  self.state = Resuming(engine, value)
  guard self.step(() => await_browser_operation(self.context.resume_audio()))
    is Completed(_) else {
    return
  }
  // Connect may throw after taking effect; retirement must still disconnect.
  match connect_output(engine.native, self.context).decode() {
    Failed(error) => self.retire(Some(error))
    Succeeded(_) =>
      if self.is_live() {
        self.state = Ready(engine)
        self.readiness = Resolved
        self.ready_result.resolve(value)
      }
  }
}

///|
// Every startup/restore step uses the same post-await liveness arbitration.
// Resource acquisition has a protected owner even when its observer is cancelled.
async fn Generation::step(
  self : Generation,
  operation : async () -> NativeOutcome,
) -> AwaitOutcome {
  guard self.is_live() else { return Retired }
  let outcome = operation()
  guard self.is_live() else { return Retired }
  if self.context.state() is Closed {
    self.retire(None)
    return Retired
  }
  match outcome {
    Failed(error) => {
      self.retire(Some(error))
      Retired
    }
    Succeeded(value) => Completed(value)
  }
}

///|
fn Generation::retire(self : Generation, error : @host.NativeError?) -> Unit {
  let stage = match self.state {
    Admitting(context) | Suspending(context) | WaitingForEngineGate(context) =>
      ClosingContext(context)
    CreatingEngine(context, pending) =>
      ResolvingEngineAcquisition(context, pending)
    SettingUp(engine) | Resuming(engine, _) | Ready(engine) =>
      Disconnecting(engine)
    Restoring(engine, pending) => {
      pending.reject(
        match error {
          Some(error) => error
          None => dom_error("Audio was turned off", "AbortError")
        },
      )
      Disconnecting(engine)
    }
    Retiring(_) | Ended(_) => return
  }
  let retirement = Retirement(stage, error)
  self.state = Retiring(retirement)
  self.owner.current = Vacant
  // Register cleanup before abort can synchronously reenter Owner::turn_on.
  self.owner.pending_retirements = self.owner.pending_retirements
    .drop_while(completion => completion.value is Some(_))
    .prepend(self.cleanup_finished)
  match error {
    Some(error) => {
      self.reject_ready(error)
      ignore(self.publish_end(failed_end(error)))
    }
    None =>
      self.reject_ready(dom_error("Audio setup was aborted", "AbortError"))
  }
  self.retirement_controller.abort()
}

///|
async fn Generation::cleanup(
  self : Generation,
  retirement : Retirement,
) -> Unit {
  for ;; {
    match retirement.stage {
      ResolvingEngineAcquisition(context, pending) =>
        // The protected acquisition child hands any late success to cleanup.
        match pending.wait() {
          Succeeded(value) =>
            retirement.stage = ClosingEngine(
              OwnedEngine(context, native_engine_from_value(value)),
            )
          Failed(_) => retirement.stage = ClosingContext(context)
        }
      Disconnecting(engine) => {
        match disconnect_output(engine.native).decode() {
          Failed(error) => retirement.record(error)
          Succeeded(_) => ()
        }
        retirement.stage = ClosingEngine(engine)
      }
      ClosingEngine(engine) => {
        match engine.lifetime.close() {
          Err(error) => retirement.record(error.native())
          Ok(_) => ()
        }
        retirement.stage = ClosingContext(engine.context)
      }
      ClosingContext(context) => {
        if !(context.state() is Closed) {
          match context.close().wait().decode() {
            Failed(error) => retirement.record(error)
            Succeeded(_) => ()
          }
        }
        retirement.stage = Complete
      }
      Complete => {
        self.finish(retirement)
        break
      }
    }
  }
}

///|
fn Generation::finish(self : Generation, retirement : Retirement) -> Unit {
  let result = match retirement.primary_error {
    Some(error) => failed_end(error)
    None =>
      match retirement.cleanup_error {
        Some(error) => failed_end(error)
        None => turned_off()
      }
  }
  self.state = Ended(self.publish_end(result))
  match retirement.cleanup_error {
    Some(error) => self.turn_off_result.reject(error)
    None => self.turn_off_result.resolve(native_unit())
  }
  self.cleanup_finished.complete(())
}
