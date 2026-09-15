///|
/// The JavaScript GraphEngine returned by @moondsp/browser, not a DSP engine.
#external
pub type NativeEngine

///|
/// Opaque JavaScript value, preserving an error or arbitrary cause by identity.
#external
pub type NativeError

///|
#external
priv type NativeExit

///|
#external
priv type CloseOutcome

///|
extern "js" fn native_wait(
  engine : NativeEngine,
  signal : @js_async.AbortSignal,
) -> @js_async.Promise[NativeExit] =
  #| (engine, signal) => engine.wait({ signal })

///|
extern "js" fn native_close(
  engine : NativeEngine,
) -> @js_async.Promise[CloseOutcome] =
  #| engine => {
  #|   try {
  #|     return engine.close().then(() => ({ ok: true }), error => ({ ok: false, error }));
  #|   } catch (error) {
  #|     return Promise.resolve({ ok: false, error });
  #|   }
  #| }

///|
extern "js" fn exit_failed(exit : NativeExit) -> Bool =
  #| exit => exit.type === "failed"

///|
extern "js" fn exit_error(exit : NativeExit) -> NativeError =
  #| exit => exit.error

///|
extern "js" fn close_ok(outcome : CloseOutcome) -> Bool =
  #| outcome => outcome.ok

///|
extern "js" fn close_error(outcome : CloseOutcome) -> NativeError =
  #| outcome => outcome.error

///|
/// A retained host error. No stringification, copying, or second error taxonomy.
/// Inspect native() when crossing back to JavaScript to retain all metadata.
pub struct RuntimeFailure {
  priv error : NativeError
}

///|
fn RuntimeFailure::RuntimeFailure(error : NativeError) -> RuntimeFailure {
  { error, }
}

///|
pub fn RuntimeFailure::native(self : RuntimeFailure) -> NativeError {
  self.error
}

///|
extern "js" fn error_code(error : NativeError) -> String =
  #| error => error.code

///|
pub fn RuntimeFailure::code(self : RuntimeFailure) -> String {
  error_code(self.error)
}

///|
extern "js" fn error_message(error : NativeError) -> String =
  #| error => error.message

///|
pub fn RuntimeFailure::message(self : RuntimeFailure) -> String {
  error_message(self.error)
}

///|
extern "js" fn has_node_index(error : NativeError) -> Bool =
  #| error => Number.isInteger(error.nodeIndex)

///|
extern "js" fn node_index(error : NativeError) -> Int =
  #| error => error.nodeIndex

///|
pub fn RuntimeFailure::node_index(self : RuntimeFailure) -> Int? {
  if has_node_index(self.error) {
    Some(node_index(self.error))
  } else {
    None
  }
}

///|
extern "js" fn has_cause(error : NativeError) -> Bool =
  #| error => "cause" in error

///|
extern "js" fn error_cause(error : NativeError) -> NativeError =
  #| error => error.cause

///|
/// None means absent; an explicit null or undefined cause is still Some.
pub fn RuntimeFailure::cause(self : RuntimeFailure) -> NativeError? {
  if has_cause(self.error) {
    Some(error_cause(self.error))
  } else {
    None
  }
}

///|
pub enum EngineExit {
  Closed
  Failed(RuntimeFailure)
}

///|
/// A lifetime view of an existing JS engine. JavaScript owns its sole terminal state.
pub struct EngineLifetime {
  priv native : NativeEngine
}

///|
pub fn EngineLifetime::EngineLifetime(native : NativeEngine) -> EngineLifetime {
  { native, }
}

///|
/// Observe the retained terminal result. Task cancellation only detaches this wait.
/// Failed is a value, not a task-group failure. Pause and command errors do not exit.
pub async fn EngineLifetime::wait(self : EngineLifetime) -> EngineExit {
  let exit = @js_async.run_promise(signal => native_wait(self.native, signal))
  if exit_failed(exit) {
    Failed(RuntimeFailure(exit_error(exit)))
  } else {
    Closed
  }
}

///|
/// Request close and observe cleanup, even during task cancellation. The native
/// GraphEngine owns idempotence and the finite closeTimeoutMs deadline. It never
/// closes the caller's AudioContext. Native rejection is a structured Result.
pub async fn EngineLifetime::close(
  self : EngineLifetime,
) -> Result[Unit, RuntimeFailure] {
  @async.protect_from_cancel(() => {
    let outcome = native_close(self.native).wait()
    if close_ok(outcome) {
      Ok(())
    } else {
      Err(RuntimeFailure(close_error(outcome)))
    }
  })
}
