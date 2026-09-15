///|
#external
pub type JsValue

///|
extern "js" fn signal_aborted(signal : @js_async.AbortSignal) -> Bool =
  #| signal => signal.aborted

///|
extern "js" fn rejected_abort(
  signal : @js_async.AbortSignal,
) -> @js_async.Promise[JsValue] =
  #| signal => Promise.reject(Object.assign(new DOMException("Operation aborted", "AbortError"), { cause: signal.reason }))

///|
extern "js" fn aborted_json() -> JsValue =
  #| () => ({ type: "aborted" })

///|
extern "js" fn reject_aborted_result(
  promise : @js_async.Promise[JsValue],
  signal : @js_async.AbortSignal,
) -> @js_async.Promise[JsValue] =
  #| (promise, signal) => promise.then(value => {
  #|   if (value.type === "aborted") throw Object.assign(new DOMException("Operation aborted", "AbortError"), { cause: signal.reason });
  #|   return value;
  #| })

///|
extern "js" fn abort_notification(
  signal : @js_async.AbortSignal,
  cancellation : @js_async.AbortSignal,
) -> @js_async.Promise[Unit] =
  #| (signal, cancellation) => new Promise((resolve, reject) => {
  #|   const detach = () => {
  #|     signal.removeEventListener("abort", aborted);
  #|     cancellation.removeEventListener("abort", cancelled);
  #|   };
  #|   const aborted = () => { detach(); resolve(); };
  #|   const cancelled = () => { detach(); reject(new DOMException("Observer cancelled", "AbortError")); };
  #|   signal.addEventListener("abort", aborted, { once: true });
  #|   cancellation.addEventListener("abort", cancelled, { once: true });
  #|   if (signal.aborted) aborted();
  #|   else if (cancellation.aborted) cancelled();
  #| })

///|
/// async 0.21.3's from_async abort handler cancels without rescheduling the JS
/// event loop. Deliver external abort through a Promise, then cancel the scope
/// inside that loop. No polling, private scheduler API, or dependency patch.
fn export_with_signal(
  signal : @js_async.AbortSignal,
  action : async () -> JsValue,
) -> @js_async.Promise[JsValue] {
  guard !signal_aborted(signal) else { return rejected_abort(signal) }
  let promise = @js_async.Promise::from_async(() => {
    @async.with_task_group(group => {
      group.spawn_bg(no_wait=true, () => {
        @js_async.run_promise(cancellation => {
          abort_notification(signal, cancellation)
        })
        group.return_immediately(aborted_json())
      })
      action()
    })
  })
  reject_aborted_result(promise, signal)
}

///|
extern "js" fn closed_json() -> JsValue =
  #| () => ({ type: "closed" })

///|
extern "js" fn failed_json(error : @host.NativeError) -> JsValue =
  #| error => ({ type: "failed", error })

///|
fn exit_json(exit : @host.EngineExit) -> JsValue {
  match exit {
    Closed => closed_json()
    Failed(error) => failed_json(error.native())
  }
}

///|
extern "js" fn close_failed_json(error : @host.NativeError) -> JsValue =
  #| error => ({ ok: false, error })

///|
extern "js" fn close_ok_json() -> JsValue =
  #| () => ({ ok: true })

///|
pub fn engine_lifetime_wait(
  native : @host.NativeEngine,
  signal : @js_async.AbortSignal,
) -> @js_async.Promise[JsValue] {
  let lifetime = @host.EngineLifetime::EngineLifetime(native)
  export_with_signal(signal, () => exit_json(lifetime.wait()))
}

///|
pub fn engine_lifetime_close(
  native : @host.NativeEngine,
) -> @js_async.Promise[JsValue] {
  let lifetime = @host.EngineLifetime::EngineLifetime(native)
  @js_async.Promise::from_async(() => {
    match lifetime.close() {
      Ok(_) => close_ok_json()
      Err(error) => close_failed_json(error.native())
    }
  })
}

///|
extern "js" fn worker_stopped(log : JsValue) -> Unit =
  #| log => { log.push({ type: "worker-stopped" }); }

///|
extern "js" fn cleanup_ok(log : JsValue) -> Unit =
  #| log => { log.push({ type: "cleanup-ok" }); }

///|
extern "js" fn cleanup_failed(log : JsValue, error : @host.NativeError) -> Unit =
  #| (log, error) => { log.push({ type: "cleanup-failed", error }); }

///|
/// The group body observes lifetime; its background worker must finish BEFORE
/// cleanup. Cancellation of the export must still run bounded native close.
pub fn engine_lifetime_group_probe(
  native : @host.NativeEngine,
  signal : @js_async.AbortSignal,
  log : JsValue,
) -> @js_async.Promise[JsValue] {
  let lifetime = @host.EngineLifetime::EngineLifetime(native)
  export_with_signal(signal, () => {
    let exit = @async.with_task_group(group => {
      group.add_defer(() => {
        match lifetime.close() {
          Ok(_) => cleanup_ok(log)
          Err(error) => cleanup_failed(log, error.native())
        }
      })
      group.spawn_bg(no_wait=true, () => {
        defer worker_stopped(log)
        @async.sleep(60_000)
      })
      lifetime.wait()
    })
    exit_json(exit)
  })
}

///|
fn main {
  ()
}
