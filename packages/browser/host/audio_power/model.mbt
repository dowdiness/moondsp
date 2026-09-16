///|
priv enum NativeOutcome {
  Succeeded(NativeValue)
  Failed(@host.NativeError)
}

///|
priv enum ContextDisposition {
  Playing
  TemporarilyUnavailable
  Closed
}

///|
priv enum CurrentSlot {
  Vacant
  Occupied
}

///|
// Sticky, typed completion shared by cancellable MoonBit waiters. Producers run
// in MoonBit tasks; browser callbacks enter through js_async's scheduler bridge.
priv struct Completion[T] {
  mut value : T?
  changed : @async.CondVar
}

///|
fn[T] Completion::Completion() -> Completion[T] {
  { value: None, changed: @async.CondVar::Cond(), }
}

///|
fn[T] Completion::complete(self : Completion[T], value : T) -> Unit {
  guard self.value is None else { return }
  self.value = Some(value)
  self.changed.broadcast()
}

///|
async fn[T] Completion::wait(self : Completion[T]) -> T {
  for ;; {
    match self.value {
      Some(value) => return value
      None => self.changed.wait()
    }
  }
}

///|
priv struct Owner {
  mut current : CurrentSlot
  mut pending_retirements : @list.List[Completion[Unit]]
  options : NativeValue
  graph_engine_factory : NativeValue
  create_context : (NativeValue) -> NativeResult
}

///|
fn Owner::Owner(
  options : NativeValue,
  graph_engine_factory : NativeValue,
  create_context? : (NativeValue) -> NativeResult = NativeContext::create,
) -> Owner {
  {
    current: Vacant,
    pending_retirements: @list.List::List([]),
    options,
    graph_engine_factory,
    create_context,
  }
}

///|
priv struct OwnedEngine {
  context : NativeContext
  native : @host.NativeEngine
  lifetime : @host.EngineLifetime
}

///|
fn OwnedEngine::OwnedEngine(
  context : NativeContext,
  native : @host.NativeEngine,
) -> OwnedEngine {
  { context, native, lifetime: @host.EngineLifetime::EngineLifetime(native), }
}

///|
priv enum GenerationState {
  Admitting(NativeContext)
  Suspending(NativeContext)
  WaitingForEngineGate(NativeContext)
  CreatingEngine(NativeContext, Completion[NativeOutcome])
  SettingUp(OwnedEngine)
  Resuming(OwnedEngine, NativeValue)
  Ready(OwnedEngine)
  Restoring(OwnedEngine, NativeDeferred)
  Retiring(Retirement)
  Ended(NativeValue)
}

///|
priv enum RetirementStage {
  ResolvingEngineAcquisition(NativeContext, Completion[NativeOutcome])
  Disconnecting(OwnedEngine)
  ClosingEngine(OwnedEngine)
  ClosingContext(NativeContext)
  Complete
}

///|
priv struct Retirement {
  mut stage : RetirementStage
  primary_error : @host.NativeError?
  mut cleanup_error : @host.NativeError?
}

///|
fn Retirement::Retirement(
  stage : RetirementStage,
  primary_error : @host.NativeError?,
) -> Retirement {
  { stage, primary_error, cleanup_error: None, }
}

///|
priv enum ReadySettlement {
  Pending
  Resolved
  Rejected
}

///|
priv enum EndPublication {
  Unpublished
  Published(NativeValue)
}

///|
priv struct Generation {
  owner : Owner
  // Public observation borrows this reference; state variants govern ownership.
  context : NativeContext
  retirement_controller : @js_async.AbortController
  ready_result : NativeDeferred
  end_result : NativeDeferred
  turn_off_result : NativeDeferred
  cleanup_finished : Completion[Unit]
  mut readiness : ReadySettlement
  mut publication : EndPublication
  mut state : GenerationState
}

///|
fn Generation::Generation(owner : Owner, context : NativeContext) -> Generation {
  let generation = {
    owner,
    context,
    retirement_controller: @js_async.AbortController::new(),
    ready_result: NativeDeferred::new(),
    end_result: NativeDeferred::new(),
    turn_off_result: NativeDeferred::new(),
    cleanup_finished: Completion(),
    readiness: Pending,
    publication: Unpublished,
    state: Admitting(context),
  }
  // Internal retirement can fail without a caller requesting turnOff. Mark the
  // retained promise observed, while still returning that same rejecting promise.
  observe_rejection(NativeDeferred::promise(generation.turn_off_result))
  generation
}

///|
fn Generation::is_live(self : Generation) -> Bool {
  match self.state {
    Admitting(_)
    | Suspending(_)
    | WaitingForEngineGate(_)
    | CreatingEngine(_, _)
    | SettingUp(_)
    | Resuming(_, _)
    | Ready(_)
    | Restoring(_, _) => true
    Retiring(_) | Ended(_) => false
  }
}

///|
fn Generation::reject_ready(
  self : Generation,
  error : @host.NativeError,
) -> Unit {
  match self.readiness {
    Pending => {
      self.readiness = Rejected
      self.ready_result.reject(error)
    }
    Resolved | Rejected => ()
  }
}

///|
fn Generation::publish_end(
  self : Generation,
  result : NativeValue,
) -> NativeValue {
  match self.publication {
    Unpublished => {
      self.publication = Published(result)
      self.end_result.resolve(result)
      result
    }
    Published(retained) => retained
  }
}

///|
fn Retirement::record(self : Retirement, error : @host.NativeError) -> Unit {
  match self.cleanup_error {
    None => self.cleanup_error = Some(error)
    Some(_) => ()
  }
}

///|
priv enum AwaitOutcome {
  Completed(NativeValue)
  Retired
}

///|
fn Generation::ready(self : Generation) -> @js_async.Promise[NativeValue] {
  self.ready_result.promise()
}

///|
fn Generation::ended(self : Generation) -> @js_async.Promise[NativeValue] {
  self.end_result.promise()
}
