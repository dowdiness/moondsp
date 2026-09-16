///|
#external
pub type NativeValue

///|
#external
priv type NativeContext

///|
#external
priv type NativeResult

///|
#external
priv type NativeDeferred

///|
extern "js" fn native_context(options : NativeValue) -> NativeResult =
  #| options => {
  #|   try { return { ok: true, value: new AudioContext(options?.contextOptions) }; }
  #|   catch (error) { return { ok: false, error }; }
  #| }

///|
extern "js" fn native_result_ok(result : NativeResult) -> Bool =
  #| result => result.ok

///|
extern "js" fn native_result_value(result : NativeResult) -> NativeValue =
  #| result => result.value

///|
extern "js" fn native_result_error(result : NativeResult) -> @host.NativeError =
  #| result => result.error instanceof Error ? result.error : new Error(String(result.error))

///|
fn parse_outcome(result : NativeResult) -> NativeOutcome {
  if native_result_ok(result) {
    Succeeded(native_result_value(result))
  } else {
    Failed(native_result_error(result))
  }
}

///|
extern "js" fn native_context_from_value(value : NativeValue) -> NativeContext =
  #| value => value

///|
extern "js" fn native_engine_from_value(
  value : NativeValue,
) -> @host.NativeEngine =
  #| value => value

///|
extern "js" fn native_context_state(context : NativeContext) -> Int =
  #| context => context.state === "running" ? 0 : context.state === "closed" ? 2 : 1

///|
fn disposition(context : NativeContext) -> ContextDisposition {
  match native_context_state(context) {
    0 => Playing
    2 => Closed
    _ => TemporarilyUnavailable
  }
}

///|
extern "js" fn native_error(
  message : String,
  name : String,
) -> @host.NativeError =
  #| (message, name) => new DOMException(message, name)

///|
extern "js" fn native_defect(message : String) -> @host.NativeError =
  #| message => new Error(message)

///|
extern "js" fn native_callable(value : NativeValue) -> Bool =
  #| value => typeof value === "function"

///|
extern "js" fn native_type_error() -> @host.NativeError =
  #| () => new TypeError("setupAudio must be a function")

///|
extern "js" fn native_resume(
  context : NativeContext,
) -> @js_async.Promise[NativeResult] =
  #| context => {
  #|   try { return Promise.resolve(context.resume()).then(value => ({ ok: true, value }), error => ({ ok: false, error })); }
  #|   catch (error) { return Promise.resolve({ ok: false, error }); }
  #| }

///|
extern "js" fn native_suspend(
  context : NativeContext,
) -> @js_async.Promise[NativeResult] =
  #| context => {
  #|   try { return Promise.resolve(context.suspend()).then(value => ({ ok: true, value }), error => ({ ok: false, error })); }
  #|   catch (error) { return Promise.resolve({ ok: false, error }); }
  #| }

///|
extern "js" fn native_close_context(
  context : NativeContext,
) -> @js_async.Promise[NativeResult] =
  #| context => {
  #|   try { return Promise.resolve(context.close()).then(value => ({ ok: true, value }), error => ({ ok: false, error })); }
  #|   catch (error) { return Promise.resolve({ ok: false, error }); }
  #| }

///|
extern "js" fn native_listen(
  context : NativeContext,
  signal : @js_async.AbortSignal,
  callback : () -> Unit,
) -> Unit =
  #| (context, signal, callback) => context.addEventListener("statechange", callback, { signal })

///|
extern "js" fn native_graph_engine(
  factory : NativeValue,
  context : NativeContext,
  options : NativeValue,
  signal : @js_async.AbortSignal,
) -> @js_async.Promise[NativeResult] =
  #| (factory, context, options, signal) => {
  #|   try { return Promise.resolve(factory({ context, wasmUrl: options?.wasmUrl, processorUrl: options?.processorUrl, closeTimeoutMs: options?.closeTimeoutMs, signal })).then(value => ({ ok: true, value }), error => ({ ok: false, error })); }
  #|   catch (error) { return Promise.resolve({ ok: false, error }); }
  #| }

///|
extern "js" fn native_connect(
  engine : @host.NativeEngine,
  context : NativeContext,
) -> NativeResult =
  #| (engine, context) => { try { engine.output.connect(context.destination); return { ok: true }; } catch (error) { return { ok: false, error }; } }

///|
extern "js" fn native_disconnect(engine : @host.NativeEngine) -> NativeResult =
  #| engine => { try { engine.output.disconnect(); return { ok: true }; } catch (error) { return { ok: false, error }; } }

///|
extern "js" fn native_setup(
  callback : NativeValue,
  context : NativeContext,
  engine : @host.NativeEngine,
  signal : @js_async.AbortSignal,
) -> @js_async.Promise[NativeResult] =
  #| (callback, context, engine, signal) => {
  #|   try { return Promise.resolve(callback(Object.freeze({ context, engine, powerOff: signal }))).then(value => ({ ok: true, value }), error => ({ ok: false, error })); }
  #|   catch (error) { return Promise.resolve({ ok: false, error }); }
  #| }

///|
extern "js" fn native_deferred() -> NativeDeferred =
  #| () => { let resolve, reject; const promise = new Promise((a,b) => { resolve=a; reject=b; }); return { promise, resolve, reject }; }

///|
extern "js" fn native_promise(
  deferred : NativeDeferred,
) -> @js_async.Promise[NativeValue] =
  #| deferred => deferred.promise

///|
extern "js" fn native_result_promise(
  deferred : NativeDeferred,
) -> @js_async.Promise[NativeResult] =
  #| deferred => deferred.promise

///|
extern "js" fn native_resolve(
  deferred : NativeDeferred,
  value : NativeValue,
) -> Unit =
  #| (deferred, value) => deferred.resolve(value)

///|
extern "js" fn native_reject(
  deferred : NativeDeferred,
  error : @host.NativeError,
) -> Unit =
  #| (deferred, error) => deferred.reject(error)

///|
extern "js" fn native_rejected(
  error : @host.NativeError,
) -> @js_async.Promise[NativeValue] =
  #| error => Promise.reject(error)

///|
extern "js" fn native_observe_rejection(
  promise : @js_async.Promise[NativeValue],
) -> Unit =
  #| promise => { promise.catch(() => {}); }

///|
extern "js" fn native_unit() -> NativeValue =
  #| () => undefined

///|
extern "js" fn native_resolved() -> @js_async.Promise[NativeValue] =
  #| () => Promise.resolve(undefined)

///|
extern "js" fn native_as_outcome(
  promise : @js_async.Promise[NativeValue],
) -> @js_async.Promise[NativeResult] =
  #| promise => promise.then(value => ({ ok: true, value }), error => ({ ok: false, error }))

///|
extern "js" fn native_clean_end() -> NativeValue =
  #| () => Object.freeze({ reason: "turnedOff" })

///|
extern "js" fn native_failed_end(error : @host.NativeError) -> NativeValue =
  #| error => Object.freeze({ reason: "failed", error })

///|
extern "js" fn owner_value(owner : OwnerState) -> NativeValue =
  #| value => value

///|
extern "js" fn owner_from_value(value : NativeValue) -> OwnerState =
  #| value => value

///|
extern "js" fn generation_from_value(value : NativeValue) -> Generation =
  #| value => value

///|
extern "js" fn started_ok(
  gen : Generation,
  context : NativeContext,
  ready : @js_async.Promise[NativeValue],
  ended : @js_async.Promise[NativeValue],
) -> NativeValue =
  #| (generation, context, ready, ended) => ({ ok: true, generation, context, ready, ended })

///|
extern "js" fn started_error(error : @host.NativeError) -> NativeValue =
  #| error => ({ ok: false, error })

///|
extern "js" fn native_forward_result(
  promise : @js_async.Promise[NativeResult],
  sink : NativeDeferred,
) -> Unit =
  #| (promise, sink) => { promise.then(sink.resolve); }
