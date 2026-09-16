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
extern "js" fn test_export_generation_handle(
  generation : Generation,
) -> NativeValue =
  #| generation => generation

///|
fn test_start_supervised_generation(
  owner : OwnerState,
  context : NativeContext,
) -> Generation {
  let generation = Generation(owner, context)
  start_generation_supervisor(generation, _ => ())
  generation
}

///|
async test "repeated retirement closes context once and retains terminal identity" {
  let owner = OwnerState(native_unit(), native_unit())
  let context = test_context()
  let generation = test_start_supervised_generation(owner, context)
  owner.current = Occupied
  native_mark_rejection_observed(native_promise(generation.ready))
  let first = powered_audio_turn_off(test_export_generation_handle(generation))
  let second = powered_audio_turn_off(test_export_generation_handle(generation))
  assert_true(test_same_promise(first, second))
  ignore(first.wait())
  assert_eq(test_close_count(context), 1)
  let early = native_promise(generation.ended).wait()
  let late = native_promise(generation.ended).wait()
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
extern "js" fn test_delay_context_close(
  context : NativeContext,
  close_completion : NativeDeferred,
) -> Unit =
  #| (context, closeCompletion) => { context.close = () => { context.closes++; context.state = 'closed'; return closeCompletion.promise; }; }

///|
extern "js" fn test_context_closed(context : NativeContext) -> Unit =
  #| context => { context.state = 'closed'; }

///|
extern "js" fn test_engine(
  close_completion : NativeDeferred,
) -> @host.NativeEngine =
  #| closeCompletion => {
  #|   const engine = { closes: 0, disconnects: 0 };
  #|   engine.output = { connect() {}, disconnect() { engine.disconnects++; } };
  #|   engine.close = () => { engine.closes++; return closeCompletion.promise; };
  #|   engine.wait = ({ signal }) => new Promise((resolve, reject) => {
  #|     const cancel = () => reject(new DOMException('cancelled', 'AbortError'));
  #|     signal.addEventListener('abort', cancel, { once: true });
  #|     closeCompletion.promise.then(() => { signal.removeEventListener('abort', cancel); resolve({ type: 'closed' }); },
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
extern "js" fn test_delayed_engine_factory(
  acquisition_completion : NativeDeferred,
  entered : () -> Unit,
) -> NativeValue =
  #| (acquisitionCompletion, entered) => () => { entered(); return acquisitionCompletion.promise; }

///|
extern "js" fn test_setup_callback(action : () -> Unit) -> NativeValue =
  #| action => async () => action()

///|
extern "js" fn test_setup(value : NativeValue) -> NativeValue =
  #| value => async () => value

///|
extern "js" fn test_delay_context_resume(
  context : NativeContext,
  resume_completion : NativeDeferred,
) -> Unit =
  #| (context, resumeCompletion) => { context.resume = () => { context.state = 'running'; return resumeCompletion.promise; }; }

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
  let result = audio_power_turn_on(export_owner_handle(owner), test_callable())
  assert_eq(test_start_error(result), "InvalidStateError")
  // Node has no AudioContext: missing admission checks would yield ReferenceError.
}

///|
async test "reentrant admission inherits unfinished retirement before abort listeners run" {
  let owner = OwnerState(native_unit(), native_unit())
  let generation = test_start_supervised_generation(owner, test_context())
  let close_gate = native_create_deferred()
  test_delay_context_close(generation.context, close_gate)
  owner.current = Occupied
  let mut admitted = false
  let mut replacement_gate = owner.pending_retirements
  test_on_abort(generation.retirement_controller.signal(), () => {
    admitted = owner.current is Vacant
    replacement_gate = owner.pending_retirements
    owner.current = Occupied
  })
  native_mark_rejection_observed(native_promise(generation.ready))
  begin_generation_retirement(generation, None)
  @async.with_task_group(group => {
    let mut passed = false
    group.spawn_bg(() => {
      wait_for_predecessor_cleanup(replacement_gate)
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
  let a = test_start_supervised_generation(owner, test_context())
  let release_a = native_create_deferred()
  test_delay_context_close(a.context, release_a)
  native_mark_rejection_observed(native_promise(a.ready))
  begin_generation_retirement(a, None)
  let b = test_start_supervised_generation(owner, test_context())
  native_mark_rejection_observed(native_promise(b.ready))
  begin_generation_retirement(b, None)
  ignore(native_promise(b.turn_off_result).wait())
  let c_gate = owner.pending_retirements
  @async.with_task_group(group => {
    let mut passed = false
    group.spawn_bg(() => {
      wait_for_predecessor_cleanup(c_gate)
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
  let generation = Generation(owner, test_context())
  let blocked = native_create_deferred()
  generation.state = WaitingForEngineGate(generation.context)
  native_mark_rejection_observed(native_promise(generation.ready))
  start_generation_supervisor(generation, _ => {
    ignore(
      await_success_or_retire(generation, () => {
        await_browser_operation(native_as_outcome(native_promise(blocked)))
      }),
    )
  })
  @async.sleep(1)
  begin_generation_retirement(generation, None)
  ignore(native_promise(generation.turn_off_result).wait())
  assert_eq(test_close_count(generation.context), 1)
  native_resolve(blocked, native_unit())
}

///|
async test "primary failure remains identical while cleanup failure rejects turn-off" {
  let owner = OwnerState(native_unit(), native_unit())
  let generation = test_start_supervised_generation(owner, test_context())
  let close_gate = native_create_deferred()
  let engine = test_engine(close_gate)
  generation.state = SettingUp(OwnedEngine(generation.context, engine))
  let primary = test_error()
  let cleanup = test_error()
  native_mark_rejection_observed(native_promise(generation.ready))
  begin_generation_retirement(generation, Some(primary))
  let early = native_promise(generation.ended).wait()
  assert_true(test_failed_identity(early, primary))
  native_reject(close_gate, cleanup)
  let off = native_as_outcome(native_promise(generation.turn_off_result)).wait()
  assert_true(test_error_same(off, cleanup))
  assert_true(test_same_value(early, native_promise(generation.ended).wait()))
  assert_eq(test_close_count(generation.context), 1)
}

///|
async test "late acquired engine is closed exactly once and joined before context release" {
  let acquisition = native_create_deferred()
  let entered : Completion[Unit] = Completion()
  let owner = OwnerState(
    native_unit(),
    test_delayed_engine_factory(acquisition, () => entered.complete(())),
  )
  let generation = Generation(owner, test_context())
  let mut setup_called = false
  let close_gate = native_create_deferred()
  let engine = test_engine(close_gate)
  start_audio_generation(
    generation,
    test_setup_callback(() => setup_called = true),
    native_as_outcome(native_resolved()),
    owner.pending_retirements,
  )
  native_mark_rejection_observed(native_promise(generation.ready))
  entered.wait()
  begin_generation_retirement(generation, None)
  @async.sleep(1)
  assert_eq(test_close_count(generation.context), 0)
  native_resolve(acquisition, test_engine_value(engine))
  @async.sleep(1)
  assert_eq(test_engine_closes(engine), 1)
  assert_eq(test_close_count(generation.context), 0)
  native_resolve(close_gate, native_unit())
  ignore(native_promise(generation.turn_off_result).wait())
  assert_eq(test_close_count(generation.context), 1)
  begin_generation_retirement(generation, None)
  assert_eq(test_engine_closes(engine), 1)
  assert_false(setup_called)
}

///|
async test "closed browser state after await retires instead of advancing" {
  let generation = test_start_supervised_generation(
    OwnerState(native_unit(), native_unit()),
    test_context(),
  )
  let operation : Completion[NativeOutcome] = Completion()
  native_mark_rejection_observed(native_promise(generation.ready))
  let waiting = @js_async.Promise::from_async(() => {
    await_success_or_retire(generation, () => operation.wait())
  })
  test_context_closed(generation.context)
  operation.complete(Succeeded(native_unit()))
  assert_true(waiting.wait() is Retired)
  ignore(native_promise(generation.turn_off_result).wait())
  assert_true(generation.readiness is Rejected)
}

///|
async test "ready retains setup value only after final resume and restore shares its promise" {
  let close_gate = native_create_deferred()
  let engine = test_engine(close_gate)
  let context = test_context()
  let owner = OwnerState(native_unit(), test_factory(engine))
  let generation = Generation(owner, context)
  let final_resume = native_create_deferred()
  test_delay_context_resume(context, final_resume)
  let admission = native_as_outcome(native_resolved())
  let setup_value = native_create_turned_off_result()
  start_audio_generation(
    generation,
    test_setup(setup_value),
    admission,
    owner.pending_retirements,
  )
  @async.sleep(1)
  assert_true(generation.readiness is Pending)
  native_resolve(final_resume, native_unit())
  assert_true(
    test_same_value(native_promise(generation.ready).wait(), setup_value),
  )
  ignore(native_suspend(context).wait())
  let restore_gate = native_create_deferred()
  test_delay_context_resume(context, restore_gate)
  let a = powered_audio_resume(test_export_generation_handle(generation))
  let b = powered_audio_resume(test_export_generation_handle(generation))
  assert_true(test_same_promise(a, b))
  native_resolve(restore_gate, native_unit())
  ignore(a.wait())
  begin_generation_retirement(generation, None)
  native_resolve(close_gate, native_unit())
  ignore(native_promise(generation.turn_off_result).wait())
}

///|
extern "js" fn native_as_outcome(
  promise : @js_async.Promise[NativeValue],
) -> @js_async.Promise[NativeResult] =
  #| promise => promise.then(value => ({ ok: true, value }), error => ({ ok: false, error }))
