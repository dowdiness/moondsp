///|
extern "js" fn test_context() -> NativeContext =
  #| () => Object.assign(new EventTarget(), {
  #|   state: 'suspended', closes: 0,
  #|   resume() { this.state = 'running'; return Promise.resolve(); },
  #|   suspend() { this.state = 'suspended'; return Promise.resolve(); },
  #|   close() { this.closes++; this.state = 'closed'; return Promise.resolve(); }
  #| })

///|
extern "js" fn test_error() -> @host.NativeError =
  #| () => new Error('sentinel')

///|
extern "js" fn test_close_count(context : NativeContext) -> Int =
  #| context => context.closes

///|
extern "js" fn test_failed_identity(
  result : NativeValue,
  error : @host.NativeError,
) -> Bool =
  #| (result, error) => result.reason === 'failed' && result.error === error

///|
extern "js" fn test_same_promise(
  a : @js_async.Promise[NativeValue],
  b : @js_async.Promise[NativeValue],
) -> Bool =
  #| (a, b) => a === b

///|
extern "js" fn test_same_value(a : NativeValue, b : NativeValue) -> Bool =
  #| (a, b) => a === b

///|
extern "js" fn test_generation_value(gen : Generation) -> NativeValue =
  #| gen => gen

///|
fn test_generation(owner : OwnerState, context : NativeContext) -> Generation {
  let gen = Generation(owner, context)
  supervise(gen, _ => ())
  gen
}

///|
async test "repeated retirement closes context once and retains terminal identity" {
  let owner = OwnerState(native_unit(), native_unit())
  let context = test_context()
  let gen = test_generation(owner, context)
  owner.current = Occupied
  native_observe_rejection(native_promise(gen.ready))
  let first = powered_audio_turn_off(test_generation_value(gen))
  let second = powered_audio_turn_off(test_generation_value(gen))
  assert_true(test_same_promise(first, second))
  ignore(first.wait())
  assert_eq(test_close_count(context), 1)
  let early = native_promise(gen.ended).wait()
  let late = native_promise(gen.ended).wait()
  assert_true(test_same_value(early, late))
  assert_true(owner.current is Vacant)
}

///|
extern "js" fn test_callable() -> NativeValue =
  #| () => async () => undefined

///|
extern "js" fn test_start_error(value : NativeValue) -> String =
  #| value => value.error?.name

///|
extern "js" fn test_on_abort(
  signal : @js_async.AbortSignal,
  action : () -> Unit,
) -> Unit =
  #| (signal, action) => signal.addEventListener('abort', action, { once: true })

///|
extern "js" fn test_close_gate(
  context : NativeContext,
  gate : NativeDeferred,
) -> Unit =
  #| (context, gate) => { context.close = () => { context.closes++; context.state = 'closed'; return gate.promise; }; }

///|
extern "js" fn test_context_closed(context : NativeContext) -> Unit =
  #| context => { context.state = 'closed'; }

///|
extern "js" fn test_engine(gate : NativeDeferred) -> @host.NativeEngine =
  #| gate => {
  #|   const engine = { closes: 0, disconnects: 0 };
  #|   engine.output = { connect() {}, disconnect() { engine.disconnects++; } };
  #|   engine.close = () => { engine.closes++; return gate.promise; };
  #|   engine.wait = ({ signal }) => new Promise((resolve, reject) => {
  #|     const cancel = () => reject(new DOMException('cancelled', 'AbortError'));
  #|     signal.addEventListener('abort', cancel, { once: true });
  #|     gate.promise.then(() => { signal.removeEventListener('abort', cancel); resolve({ type: 'closed' }); },
  #|       error => { signal.removeEventListener('abort', cancel); resolve({ type: 'failed', error }); });
  #|   });
  #|   return engine;
  #| }

///|
extern "js" fn test_engine_value(engine : @host.NativeEngine) -> NativeValue =
  #| engine => engine

///|
extern "js" fn test_engine_closes(engine : @host.NativeEngine) -> Int =
  #| engine => engine.closes

///|
extern "js" fn test_factory(engine : @host.NativeEngine) -> NativeValue =
  #| engine => async () => engine

///|
extern "js" fn test_factory_gate(
  gate : NativeDeferred,
  entered : () -> Unit,
) -> NativeValue =
  #| (gate, entered) => () => { entered(); return gate.promise; }

///|
extern "js" fn test_setup_callback(action : () -> Unit) -> NativeValue =
  #| action => async () => action()

///|
extern "js" fn test_setup(value : NativeValue) -> NativeValue =
  #| value => async () => value

///|
extern "js" fn test_resume_gate(
  context : NativeContext,
  gate : NativeDeferred,
) -> Unit =
  #| (context, gate) => { context.resume = () => { context.state = 'running'; return gate.promise; }; }

///|
extern "js" fn test_error_same(
  result : NativeResult,
  error : @host.NativeError,
) -> Bool =
  #| (result, error) => !result.ok && result.error === error

///|
test "occupied owner rejects before allocating a context" {
  let owner = OwnerState(native_unit(), native_unit())
  owner.current = Occupied
  let result = audio_power_turn_on(owner_value(owner), test_callable())
  assert_eq(test_start_error(result), "InvalidStateError")
  // Node has no AudioContext: missing admission checks would yield ReferenceError.
}

///|
async test "reentrant admission inherits unfinished retirement before abort listeners run" {
  let owner = OwnerState(native_unit(), native_unit())
  let gen = test_generation(owner, test_context())
  let close_gate = native_deferred()
  test_close_gate(gen.context, close_gate)
  owner.current = Occupied
  let mut admitted = false
  let mut replacement_gate = owner.retirement_tail
  test_on_abort(gen.controller.signal(), () => {
    admitted = owner.current is Vacant
    replacement_gate = owner.retirement_tail
    owner.current = Occupied
  })
  native_observe_rejection(native_promise(gen.ready))
  begin_retirement(gen, None)
  @async.with_task_group(group => {
    let mut passed = false
    group.spawn_bg(() => {
      wait_for_gate(replacement_gate)
      passed = true
    })
    @async.sleep(1)
    assert_false(passed)
    native_resolve(close_gate, native_unit())
  })
  assert_true(admitted)
  assert_true(owner.current is Occupied)
}

///|
async test "rapid retirements retain every earlier cleanup in the engine gate" {
  let owner = OwnerState(native_unit(), native_unit())
  let a = test_generation(owner, test_context())
  let release_a = native_deferred()
  test_close_gate(a.context, release_a)
  native_observe_rejection(native_promise(a.ready))
  begin_retirement(a, None)
  let b = test_generation(owner, test_context())
  native_observe_rejection(native_promise(b.ready))
  begin_retirement(b, None)
  ignore(native_promise(b.off).wait())
  let c_gate = owner.retirement_tail
  @async.with_task_group(group => {
    let mut passed = false
    group.spawn_bg(() => {
      wait_for_gate(c_gate)
      passed = true
    })
    @async.sleep(1)
    assert_false(passed)
    native_resolve(release_a, native_unit())
  })
  assert_eq(test_close_count(a.context), 1)
  assert_eq(test_close_count(b.context), 1)
}

///|
async test "pre-engine retirement bypasses unfinished setup and later gates" {
  let owner = OwnerState(native_unit(), native_unit())
  let gen = Generation(owner, test_context())
  let blocked = native_deferred()
  gen.state = WaitingForEngineGate(gen.context)
  native_observe_rejection(native_promise(gen.ready))
  supervise(gen, _ => {
    ignore(
      await_owned(gen, () => {
        observe_operation(native_as_outcome(native_promise(blocked)))
      }),
    )
  })
  @async.sleep(1)
  begin_retirement(gen, None)
  ignore(native_promise(gen.off).wait())
  assert_eq(test_close_count(gen.context), 1)
  native_resolve(blocked, native_unit())
}

///|
async test "primary failure remains identical while cleanup failure rejects turn-off" {
  let owner = OwnerState(native_unit(), native_unit())
  let gen = test_generation(owner, test_context())
  let close_gate = native_deferred()
  let engine = test_engine(close_gate)
  gen.state = SettingUp(OwnedEngine(gen.context, engine))
  let primary = test_error()
  let cleanup = test_error()
  native_observe_rejection(native_promise(gen.ready))
  begin_retirement(gen, Some(primary))
  let early = native_promise(gen.ended).wait()
  assert_true(test_failed_identity(early, primary))
  native_reject(close_gate, cleanup)
  let off = native_as_outcome(native_promise(gen.off)).wait()
  assert_true(test_error_same(off, cleanup))
  assert_true(test_same_value(early, native_promise(gen.ended).wait()))
  assert_eq(test_close_count(gen.context), 1)
}

///|
async test "late acquired engine is closed exactly once and joined before context release" {
  let acquisition = native_deferred()
  let entered : Completion[Unit] = Completion()
  let owner = OwnerState(
    native_unit(),
    test_factory_gate(acquisition, () => entered.complete(())),
  )
  let gen = Generation(owner, test_context())
  let mut setup_called = false
  let close_gate = native_deferred()
  let engine = test_engine(close_gate)
  launch_setup(
    gen,
    test_setup_callback(() => setup_called = true),
    native_as_outcome(native_resolved()),
    owner.retirement_tail,
  )
  native_observe_rejection(native_promise(gen.ready))
  entered.wait()
  begin_retirement(gen, None)
  @async.sleep(1)
  assert_eq(test_close_count(gen.context), 0)
  native_resolve(acquisition, test_engine_value(engine))
  @async.sleep(1)
  assert_eq(test_engine_closes(engine), 1)
  assert_eq(test_close_count(gen.context), 0)
  native_resolve(close_gate, native_unit())
  ignore(native_promise(gen.off).wait())
  assert_eq(test_close_count(gen.context), 1)
  begin_retirement(gen, None)
  assert_eq(test_engine_closes(engine), 1)
  assert_false(setup_called)
}

///|
async test "closed browser state after await retires instead of advancing" {
  let gen = test_generation(
    OwnerState(native_unit(), native_unit()),
    test_context(),
  )
  let operation : Completion[NativeOutcome] = Completion()
  native_observe_rejection(native_promise(gen.ready))
  let waiting = @js_async.Promise::from_async(() => {
    await_owned(gen, () => operation.wait())
  })
  test_context_closed(gen.context)
  operation.complete(Succeeded(native_unit()))
  assert_true(waiting.wait() is Retired)
  ignore(native_promise(gen.off).wait())
  assert_true(gen.readiness is Rejected)
}

///|
async test "ready retains setup value only after final resume and restore shares its promise" {
  let close_gate = native_deferred()
  let engine = test_engine(close_gate)
  let context = test_context()
  let owner = OwnerState(native_unit(), test_factory(engine))
  let gen = Generation(owner, context)
  let final_resume = native_deferred()
  test_resume_gate(context, final_resume)
  let admission = native_as_outcome(native_resolved())
  let setup_value = native_clean_end()
  launch_setup(gen, test_setup(setup_value), admission, owner.retirement_tail)
  @async.sleep(1)
  assert_true(gen.readiness is Pending)
  native_resolve(final_resume, native_unit())
  assert_true(test_same_value(native_promise(gen.ready).wait(), setup_value))
  ignore(native_suspend(context).wait())
  let restore_gate = native_deferred()
  test_resume_gate(context, restore_gate)
  let a = powered_audio_resume(test_generation_value(gen))
  let b = powered_audio_resume(test_generation_value(gen))
  assert_true(test_same_promise(a, b))
  native_resolve(restore_gate, native_unit())
  ignore(a.wait())
  begin_retirement(gen, None)
  native_resolve(close_gate, native_unit())
  ignore(native_promise(gen.off).wait())
}

///|
extern "js" fn native_as_outcome(
  promise : @js_async.Promise[NativeValue],
) -> @js_async.Promise[NativeResult] =
  #| promise => promise.then(value => ({ ok: true, value }), error => ({ ok: false, error }))
