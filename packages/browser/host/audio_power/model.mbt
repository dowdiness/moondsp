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
priv struct OwnerState {
  mut current : CurrentSlot
  mut retirement_tail : @js_async.Promise[NativeValue]
  options : NativeValue
  factory : NativeValue
}

///|
fn OwnerState::OwnerState(
  options : NativeValue,
  factory : NativeValue,
) -> OwnerState {
  { current: Vacant, retirement_tail: native_resolved(), options, factory, }
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
  CreatingEngine(NativeContext, NativeDeferred)
  SettingUp(OwnedEngine)
  Resuming(OwnedEngine, NativeValue)
  Ready(OwnedEngine)
  Restoring(OwnedEngine, NativeDeferred)
  Retiring(Retirement)
  Ended(NativeValue)
}

///|
priv enum RetirementStage {
  ResolvingEngineAcquisition(NativeContext, NativeDeferred)
  Disconnecting(OwnedEngine)
  ClosingEngine(OwnedEngine)
  ClosingContext(NativeContext)
  Complete
}

///|
priv struct Retirement {
  mut stage : RetirementStage
  primary : @host.NativeError?
  mut cleanup_error : @host.NativeError?
}

///|
fn Retirement::Retirement(
  stage : RetirementStage,
  primary : @host.NativeError?,
) -> Retirement {
  { stage, primary, cleanup_error: None, }
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
  owner : OwnerState
  // Public observation borrows this reference; state variants govern ownership.
  context : NativeContext
  controller : @js_async.AbortController
  ready : NativeDeferred
  ended : NativeDeferred
  off : NativeDeferred
  stopped : NativeDeferred
  retired : NativeDeferred
  mut readiness : ReadySettlement
  mut publication : EndPublication
  mut state : GenerationState
}

///|
fn Generation::Generation(
  owner : OwnerState,
  context : NativeContext,
) -> Generation {
  let gen = {
    owner,
    context,
    controller: @js_async.AbortController::new(),
    ready: native_deferred(),
    ended: native_deferred(),
    off: native_deferred(),
    stopped: native_deferred(),
    retired: native_deferred(),
    readiness: Pending,
    publication: Unpublished,
    state: Admitting(context),
  }
  // Internal retirement can fail without a caller requesting turnOff. Mark the
  // retained promise observed, while still returning that same rejecting promise.
  native_observe_rejection(native_promise(gen.off))
  gen
}

///|
fn is_live(gen : Generation) -> Bool {
  match gen.state {
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
fn reject_ready(gen : Generation, error : @host.NativeError) -> Unit {
  match gen.readiness {
    Pending => {
      gen.readiness = Rejected
      native_reject(gen.ready, error)
    }
    Resolved | Rejected => ()
  }
}

///|
fn publish_end(gen : Generation, result : NativeValue) -> NativeValue {
  match gen.publication {
    Unpublished => {
      gen.publication = Published(result)
      native_resolve(gen.ended, result)
      result
    }
    Published(retained) => retained
  }
}

///|
fn remember_cleanup(retirement : Retirement, error : @host.NativeError) -> Unit {
  match retirement.cleanup_error {
    None => retirement.cleanup_error = Some(error)
    Some(_) => ()
  }
}

///|
priv enum AwaitOutcome {
  Completed(NativeOutcome)
  Retired
}
