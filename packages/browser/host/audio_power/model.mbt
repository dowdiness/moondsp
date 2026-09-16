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
priv struct OwnerState {
  mut current : CurrentSlot
  mut retirement_tail : @list.List[Completion[Unit]]
  options : NativeValue
  factory : NativeValue
}

///|
fn OwnerState::OwnerState(
  options : NativeValue,
  factory : NativeValue,
) -> OwnerState {
  { current: Vacant, retirement_tail: @list.List::List([]), options, factory, }
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
  stopped : Completion[Unit]
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
    stopped: Completion(),
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
  Completed(NativeValue)
  Retired
}
