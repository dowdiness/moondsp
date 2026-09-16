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
// Retained JS-facing promises only. Internal completions remain typed in MoonBit.
#external
priv type NativeDeferred

///|
extern "js" fn NativeContext::create(options : NativeValue) -> NativeResult =
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
extern "js" fn native_normalize_result_error(
  result : NativeResult,
) -> @host.NativeError =
  #| result => {
  #|   const error = result.error;
  #|   try {
  #|     if (typeof Error.isError === 'function') {
  #|       if (Error.isError(error)) return error;
  #|     } else {
  #|       // Older browsers lack the realm-independent branded check.
  #|       const tag = Object.prototype.toString.call(error);
  #|       if (error instanceof Error || tag === '[object Error]' || tag === '[object DOMException]') return error;
  #|     }
  #|     return new Error(String(error));
  #|   } catch {
  #|     return new Error('Non-Error exception');
  #|   }
  #| }

///|
fn NativeResult::decode(result : NativeResult) -> NativeOutcome {
  if native_result_ok(result) {
    Succeeded(native_result_value(result))
  } else {
    Failed(native_normalize_result_error(result))
  }
}

///|
extern "js" fn NativeContext::from_js(value : NativeValue) -> NativeContext =
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
fn NativeContext::state(context : NativeContext) -> ContextDisposition {
  match native_context_state(context) {
    0 => Playing
    2 => Closed
    _ => TemporarilyUnavailable
  }
}

///|
extern "js" fn dom_error(message : String, name : String) -> @host.NativeError =
  #| (message, name) => new DOMException(message, name)

///|
extern "js" fn internal_error(message : String) -> @host.NativeError =
  #| message => new Error(message)

///|
extern "js" fn NativeValue::is_callable(value : NativeValue) -> Bool =
  #| value => typeof value === "function"

///|
extern "js" fn native_invalid_setup_error() -> @host.NativeError =
  #| () => new TypeError("setupAudio must be a function")

///|
extern "js" fn NativeContext::resume_audio(
  context : NativeContext,
) -> @js_async.Promise[NativeResult] =
  #| context => {
  #|   try { return Promise.resolve(context.resume()).then(value => ({ ok: true, value }), error => ({ ok: false, error })); }
  #|   catch (error) { return Promise.resolve({ ok: false, error }); }
  #| }

///|
extern "js" fn NativeContext::suspend(
  context : NativeContext,
) -> @js_async.Promise[NativeResult] =
  #| context => {
  #|   try { return Promise.resolve(context.suspend()).then(value => ({ ok: true, value }), error => ({ ok: false, error })); }
  #|   catch (error) { return Promise.resolve({ ok: false, error }); }
  #| }

///|
extern "js" fn NativeContext::close(
  context : NativeContext,
) -> @js_async.Promise[NativeResult] =
  #| context => {
  #|   try { return Promise.resolve(context.close()).then(value => ({ ok: true, value }), error => ({ ok: false, error })); }
  #|   catch (error) { return Promise.resolve({ ok: false, error }); }
  #| }

///|
extern "js" fn NativeContext::on_change(
  context : NativeContext,
  remove_listener_on_abort : @js_async.AbortSignal,
  on_state_change : () -> Unit,
) -> Unit =
  #| (context, removeListenerOnAbort, onStateChange) => context.addEventListener("statechange", onStateChange, { signal: removeListenerOnAbort })

///|
extern "js" fn create_engine(
  graph_engine_factory : NativeValue,
  context : NativeContext,
  options : NativeValue,
  cancel_creation : @js_async.AbortSignal,
) -> @js_async.Promise[NativeResult] =
  #| (graphEngineFactory, context, options, cancelCreation) => {
  #|   try { return Promise.resolve(graphEngineFactory({ context, wasmUrl: options?.wasmUrl, processorUrl: options?.processorUrl, closeTimeoutMs: options?.closeTimeoutMs, signal: cancelCreation })).then(value => ({ ok: true, value }), error => ({ ok: false, error })); }
  #|   catch (error) { return Promise.resolve({ ok: false, error }); }
  #| }

///|
extern "js" fn connect_output(
  engine : @host.NativeEngine,
  context : NativeContext,
) -> NativeResult =
  #| (engine, context) => { try { engine.output.connect(context.destination); return { ok: true }; } catch (error) { return { ok: false, error }; } }

///|
extern "js" fn disconnect_output(engine : @host.NativeEngine) -> NativeResult =
  #| engine => { try { engine.output.disconnect(); return { ok: true }; } catch (error) { return { ok: false, error }; } }

///|
extern "js" fn call_setup(
  setup_audio : NativeValue,
  context : NativeContext,
  engine : @host.NativeEngine,
  power_off : @js_async.AbortSignal,
) -> @js_async.Promise[NativeResult] =
  #| (setupAudio, context, engine, powerOff) => {
  #|   try { return Promise.resolve(setupAudio(Object.freeze({ context, engine, powerOff }))).then(value => ({ ok: true, value }), error => ({ ok: false, error })); }
  #|   catch (error) { return Promise.resolve({ ok: false, error }); }
  #| }

///|
extern "js" fn NativeDeferred::new() -> NativeDeferred =
  #| () => { let resolve, reject; const promise = new Promise((a,b) => { resolve=a; reject=b; }); return { promise, resolve, reject }; }

///|
extern "js" fn NativeDeferred::promise(
  deferred : NativeDeferred,
) -> @js_async.Promise[NativeValue] =
  #| deferred => deferred.promise

///|
extern "js" fn NativeDeferred::resolve(
  deferred : NativeDeferred,
  value : NativeValue,
) -> Unit =
  #| (deferred, value) => deferred.resolve(value)

///|
extern "js" fn NativeDeferred::reject(
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
extern "js" fn observe_rejection(
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
extern "js" fn turned_off() -> NativeValue =
  #| () => Object.freeze({ reason: "turnedOff" })

///|
extern "js" fn failed_end(error : @host.NativeError) -> NativeValue =
  #| error => Object.freeze({ reason: "failed", error })

///|
extern "js" fn Owner::to_js(owner : Owner) -> NativeValue =
  #| value => value

///|
extern "js" fn Owner::from_js(value : NativeValue) -> Owner =
  #| value => value

///|
extern "js" fn Generation::from_js(value : NativeValue) -> Generation =
  #| value => value

///|
extern "js" fn started_result(
  generation : Generation,
  context : NativeContext,
  ready : @js_async.Promise[NativeValue],
  ended : @js_async.Promise[NativeValue],
) -> NativeValue =
  #| (generation, context, ready, ended) => ({ ok: true, generation, context, ready, ended })

///|
extern "js" fn start_error(error : @host.NativeError) -> NativeValue =
  #| error => ({ ok: false, error })

///|
// Cancel observation, not the underlying browser operation. Resource acquisition
// instead uses an uncancellable wait held by its structured owner.
extern "js" fn native_observe_operation(
  operation : @js_async.Promise[NativeResult],
  cancel_observation : @js_async.AbortSignal,
) -> @js_async.Promise[NativeResult] =
  #| (operation, cancelObservation) => new Promise((resolve, reject) => {
  #|   const cancel = () => { cancelObservation.removeEventListener('abort', cancel); reject(cancelObservation.reason); };
  #|   if (cancelObservation.aborted) { cancel(); return; }
  #|   cancelObservation.addEventListener('abort', cancel, { once: true });
  #|   operation.then(
  #|     value => { cancelObservation.removeEventListener('abort', cancel); resolve(value); },
  #|     error => { cancelObservation.removeEventListener('abort', cancel); reject(error); },
  #|   );
  #| })

///|
// The Promise bridge also wakes MoonBit's JS scheduler when retirement originates
// in a synchronous JS call or browser event, outside a running MoonBit task.
extern "js" fn native_wait_for_abort(
  abort_to_observe : @js_async.AbortSignal,
  cancel_observation : @js_async.AbortSignal,
) -> @js_async.Promise[NativeValue] =
  #| (abortToObserve, cancelObservation) => new Promise((resolve, reject) => {
  #|   const detach = () => {
  #|     abortToObserve.removeEventListener('abort', ended);
  #|     cancelObservation.removeEventListener('abort', cancelled);
  #|   };
  #|   const ended = () => { detach(); resolve(undefined); };
  #|   const cancelled = () => { detach(); reject(cancelObservation.reason); };
  #|   if (abortToObserve.aborted) { ended(); return; }
  #|   if (cancelObservation.aborted) { cancelled(); return; }
  #|   abortToObserve.addEventListener('abort', ended, { once: true });
  #|   cancelObservation.addEventListener('abort', cancelled, { once: true });
  #| })

///|
async fn await_browser_operation(
  operation : @js_async.Promise[NativeResult],
) -> NativeOutcome {
  NativeResult::decode(
    @js_async.run_promise(signal => native_observe_operation(operation, signal)),
  )
}

///|
async fn Generation::wait_for_stop(generation : Generation) -> Unit {
  ignore(
    @js_async.run_promise(signal => {
      native_wait_for_abort(generation.retirement_controller.signal(), signal)
    }),
  )
}
