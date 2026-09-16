///|
extern "js" fn test_context() -> NativeContext =
  #| () => Object.assign(new EventTarget(), {
  #|   state: 'suspended', closes: 0,
  #|   resume() { this.state = 'running'; return Promise.resolve(); },
  #|   suspend() { this.state = 'suspended'; return Promise.resolve(); },
  #|   close() { this.closes++; this.state = 'closed'; return Promise.resolve(); }
  #| })

///|
extern "js" fn test_context_result(context : NativeContext) -> NativeResult =
  #| context => ({ ok: true, value: context })

///|
extern "js" fn test_error() -> @host.NativeError =
  #| () => new Error('sentinel')

///|
extern "js" fn test_error_name(error : @host.NativeError) -> String =
  #| error => error.name

///|
extern "js" fn test_close_count(context : NativeContext) -> Int =
  #| context => context.closes

///|
extern "js" fn test_end_reason(result : NativeValue) -> String =
  #| result => result.reason

///|
extern "js" fn test_failed_identity(
  result : NativeValue,
  error : @host.NativeError,
) -> Bool =
  #| (result, error) => result.reason === 'failed' && result.error === error

///|
extern "js" fn test_same_promise(
  first : @js_async.Promise[NativeValue],
  second : @js_async.Promise[NativeValue],
) -> Bool =
  #| (first, second) => first === second

///|
extern "js" fn test_same_value(
  first : NativeValue,
  second : NativeValue,
) -> Bool =
  #| (first, second) => first === second

///|
extern "js" fn test_same_error(
  first : @host.NativeError,
  second : @host.NativeError,
) -> Bool =
  #| (first, second) => first === second

///|
extern "js" fn test_value() -> NativeValue =
  #| () => ({ tag: 'setup-value' })

///|
extern "js" fn test_delay_close(
  context : NativeContext,
  completion : NativeDeferred,
) -> Unit =
  #| (context, completion) => { context.close = () => { context.closes++; context.state = 'closed'; return completion.promise; }; }

///|
extern "js" fn test_context_closed(context : NativeContext) -> Unit =
  #| context => { context.state = 'closed'; }

///|
extern "js" fn test_engine(completion : NativeDeferred) -> @host.NativeEngine =
  #| completion => {
  #|   const engine = { closes: 0 };
  #|   engine.output = { connect() {}, disconnect() {} };
  #|   engine.close = () => { engine.closes++; return completion.promise; };
  #|   engine.wait = ({ signal }) => new Promise((resolve, reject) => {
  #|     const cancel = () => reject(new DOMException('cancelled', 'AbortError'));
  #|     if (signal.aborted) { cancel(); return; }
  #|     signal.addEventListener('abort', cancel, { once: true });
  #|     completion.promise.then(() => { signal.removeEventListener('abort', cancel); resolve({ type: 'closed' }); },
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
extern "js" fn test_factory(create : () -> @host.NativeEngine) -> NativeValue =
  #| create => async () => create()

///|
extern "js" fn test_delayed_factory(
  completion : NativeDeferred,
  entered : () -> Unit,
) -> NativeValue =
  #| (completion, entered) => () => { entered(); return completion.promise; }

///|
extern "js" fn test_setup(value : NativeValue) -> NativeValue =
  #| value => async () => value

///|
extern "js" fn test_callback(action : () -> NativeValue) -> NativeValue =
  #| action => async () => action()

///|
extern "js" fn test_abort_setup(on_abort : () -> Unit) -> NativeValue =
  #| onAbort => async ({ powerOff }) => { powerOff.addEventListener('abort', onAbort, { once: true }); }

///|
extern "js" fn test_failed_setup(error : @host.NativeError) -> NativeValue =
  #| error => async () => { throw error; }

///|
extern "js" fn test_delay_resume(
  context : NativeContext,
  completion : NativeDeferred,
  entered : () -> Unit,
) -> Unit =
  #| (context, completion, entered) => { context.resume = () => { context.state = 'running'; entered(); return completion.promise; }; }

///|
extern "js" fn test_pending(
  promise : @js_async.Promise[NativeValue],
) -> NativeValue =
  #| promise => { const status = { pending: true }; promise.then(() => { status.pending = false; }, () => { status.pending = false; }); return status; }

///|
extern "js" fn test_is_pending(status : NativeValue) -> Bool =
  #| status => status.pending

///|
extern "js" fn test_outcome(
  promise : @js_async.Promise[NativeValue],
) -> @js_async.Promise[NativeResult] =
  #| promise => promise.then(value => ({ ok: true, value }), error => ({ ok: false, error }))

///|
fn test_owner(
  contexts : Array[NativeContext],
  engines : Array[@host.NativeEngine],
) -> Owner {
  let mut context_index = 0
  let mut engine_index = 0
  Owner(
    native_unit(),
    test_factory(() => {
      let engine = engines[engine_index]
      engine_index += 1
      engine
    }),
    create_context=_ => {
      let context = contexts[context_index]
      context_index += 1
      test_context_result(context)
    },
  )
}

///|
fn test_start(owner : Owner, setup : NativeValue) -> Generation raise {
  guard owner.turn_on(setup) is Ok(generation) else {
    fail("unexpected admission failure")
  }
  observe_rejection(generation.ready())
  generation
}

///|
async test "repeated turn-off closes resources once and retains terminal identity" {
  let context = test_context()
  let close = NativeDeferred::new()
  let engine = test_engine(close)
  let owner = test_owner([context], [engine])
  let generation = test_start(owner, test_setup(native_unit()))
  ignore(generation.ready().wait())
  let first = generation.turn_off()
  let second = generation.turn_off()
  assert_true(test_same_promise(first, second))
  close.resolve(native_unit())
  ignore(first.wait())
  assert_eq(test_close_count(context), 1)
  assert_eq(test_engine_closes(engine), 1)
  let early = generation.ended().wait()
  assert_true(test_same_value(early, generation.ended().wait()))
  assert_eq(test_end_reason(early), "turnedOff")
}

///|
async test "duplicate admission rejects before allocating another context" {
  let context = test_context()
  let close = NativeDeferred::new()
  let engine = test_engine(close)
  let mut allocations = 0
  let owner = Owner(native_unit(), test_factory(() => engine), create_context=_ => {
    allocations += 1
    test_context_result(context)
  })
  let generation = test_start(owner, test_setup(native_unit()))
  guard owner.turn_on(test_setup(native_unit())) is Err(error) else {
    fail("duplicate admission succeeded")
  }
  assert_eq(test_error_name(error), "InvalidStateError")
  assert_eq(allocations, 1)
  let stopped = generation.turn_off()
  close.resolve(native_unit())
  ignore(stopped.wait())
}

///|
async test "reentrant turn-on waits for the retiring generation's cleanup" {
  let first_context = test_context()
  let second_context = test_context()
  let first_close = NativeDeferred::new()
  let second_close = NativeDeferred::new()
  let owner = test_owner([first_context, second_context], [
    test_engine(first_close),
    test_engine(second_close),
  ])
  let replacement : Completion[Result[Generation, @host.NativeError]] = Completion()
  let mut replacement_setup = false
  let first = test_start(
    owner,
    test_abort_setup(() => {
      replacement.complete(
        owner.turn_on(
          test_callback(() => {
            replacement_setup = true
            native_unit()
          }),
        ),
      )
    }),
  )
  ignore(first.ready().wait())
  let stopped = first.turn_off()
  guard replacement.wait() is Ok(second) else {
    fail("reentrant admission failed")
  }
  observe_rejection(second.ready())
  @async.sleep(1)
  assert_false(replacement_setup)
  first_close.resolve(native_unit())
  ignore(stopped.wait())
  ignore(second.ready().wait())
  assert_true(replacement_setup)
  let second_stopped = second.turn_off()
  second_close.resolve(native_unit())
  ignore(second_stopped.wait())
}

///|
async test "rapid replacements retain every predecessor cleanup" {
  let contexts = [test_context(), test_context(), test_context()]
  let first_close = NativeDeferred::new()
  let last_close = NativeDeferred::new()
  let owner = test_owner(contexts, [
    test_engine(first_close),
    test_engine(last_close),
  ])
  let first = test_start(owner, test_setup(native_unit()))
  ignore(first.ready().wait())
  let first_stopped = first.turn_off()
  let middle = test_start(owner, test_setup(native_unit()))
  ignore(middle.turn_off().wait())
  let last = test_start(owner, test_setup(native_unit()))
  let pending = test_pending(last.ready())
  @async.sleep(1)
  assert_true(test_is_pending(pending))
  first_close.resolve(native_unit())
  ignore(first_stopped.wait())
  ignore(last.ready().wait())
  assert_eq(test_close_count(contexts[0]), 1)
  assert_eq(test_close_count(contexts[1]), 1)
  let last_stopped = last.turn_off()
  last_close.resolve(native_unit())
  ignore(last_stopped.wait())
}

///|
async test "turn-off while waiting for predecessors does not wait for them" {
  let first_context = test_context()
  let second_context = test_context()
  let first_close = NativeDeferred::new()
  test_delay_close(first_context, first_close)
  let owner = test_owner([first_context, second_context], [])
  let first = test_start(owner, test_setup(native_unit()))
  let first_stopped = first.turn_off()
  let pending = test_pending(first_stopped)
  let second = test_start(owner, test_setup(native_unit()))
  @async.sleep(1)
  ignore(second.turn_off().wait())
  assert_eq(test_close_count(second_context), 1)
  assert_eq(test_end_reason(second.ended().wait()), "turnedOff")
  assert_true(test_is_pending(pending))
  first_close.resolve(native_unit())
  ignore(first_stopped.wait())
}

///|
async test "primary failure survives cleanup failure and cleanup still closes context" {
  let context = test_context()
  let close = NativeDeferred::new()
  let owner = test_owner([context], [test_engine(close)])
  let primary = test_error()
  let cleanup = test_error()
  let generation = test_start(owner, test_failed_setup(primary))
  let early = generation.ended().wait()
  assert_true(test_failed_identity(early, primary))
  close.reject(cleanup)
  guard test_outcome(generation.turn_off()).wait().decode() is Failed(error) else {
    fail("cleanup succeeded unexpectedly")
  }
  assert_true(test_same_error(error, cleanup))
  assert_true(test_same_value(early, generation.ended().wait()))
  assert_eq(test_close_count(context), 1)
}

///|
async test "late acquired engine is closed once before its context without running setup" {
  let context = test_context()
  let acquisition = NativeDeferred::new()
  let entered : Completion[Unit] = Completion()
  let owner = Owner(
    native_unit(),
    test_delayed_factory(acquisition, () => entered.complete(())),
    create_context=_ => test_context_result(context),
  )
  let mut setup_called = false
  let close = NativeDeferred::new()
  let engine = test_engine(close)
  let generation = test_start(
    owner,
    test_callback(() => {
      setup_called = true
      native_unit()
    }),
  )
  entered.wait()
  let stopped = generation.turn_off()
  @async.sleep(1)
  assert_eq(test_close_count(context), 0)
  acquisition.resolve(test_engine_value(engine))
  @async.sleep(1)
  assert_eq(test_engine_closes(engine), 1)
  assert_eq(test_close_count(context), 0)
  close.resolve(native_unit())
  ignore(stopped.wait())
  assert_eq(test_close_count(context), 1)
  ignore(generation.turn_off().wait())
  assert_eq(test_engine_closes(engine), 1)
  assert_false(setup_called)
}

///|
async test "closed context after admission aborts setup without another browser event" {
  let context = test_context()
  let admission = NativeDeferred::new()
  test_delay_resume(context, admission, () => ())
  let owner = test_owner([context], [])
  let mut setup_called = false
  let generation = test_start(
    owner,
    test_callback(() => {
      setup_called = true
      native_unit()
    }),
  )
  test_context_closed(context)
  admission.resolve(native_unit())
  guard test_outcome(generation.ready()).wait().decode() is Failed(error) else {
    fail("closed context became ready")
  }
  assert_eq(test_error_name(error), "AbortError")
  ignore(generation.turn_off().wait())
  assert_eq(test_end_reason(generation.ended().wait()), "turnedOff")
  assert_false(setup_called)
}

///|
async test "ready waits for final resume and concurrent resume retains one promise" {
  let context = test_context()
  let close = NativeDeferred::new()
  let owner = test_owner([context], [test_engine(close)])
  let final_resume = NativeDeferred::new()
  let entered : Completion[Unit] = Completion()
  let setup_value = test_value()
  let generation = test_start(
    owner,
    test_callback(() => {
      test_delay_resume(context, final_resume, () => entered.complete(()))
      setup_value
    }),
  )
  let pending = test_pending(generation.ready())
  entered.wait()
  @async.sleep(1)
  assert_true(test_is_pending(pending))
  final_resume.resolve(native_unit())
  assert_true(test_same_value(generation.ready().wait(), setup_value))
  ignore(context.suspend().wait())
  let restore = NativeDeferred::new()
  test_delay_resume(context, restore, () => ())
  let first = generation.resume_audio()
  let second = generation.resume_audio()
  assert_true(test_same_promise(first, second))
  restore.resolve(native_unit())
  ignore(first.wait())
  let stopped = generation.turn_off()
  close.resolve(native_unit())
  ignore(stopped.wait())
}
