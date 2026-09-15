///|
extern "js" fn failed_engine(cause_kind : Int) -> @host.NativeEngine =
  #| kind => {
  #|   const error = Object.assign(new Error("processor failed"), { code: "PROCESSOR_FAILED", nodeIndex: 7 });
  #|   if (kind === 1) error.cause = null;
  #|   if (kind === 2) error.cause = undefined;
  #|   return {
  #|     error,
  #|     wait: () => Promise.resolve({ type: "failed", error }),
  #|     close: () => Promise.reject(error),
  #|   };
  #| }

///|
extern "js" fn same_error(
  engine : @host.NativeEngine,
  error : @host.NativeError,
) -> Bool =
  #| (engine, error) => engine.error === error

///|
extern "js" fn is_null(value : @host.NativeError) -> Bool =
  #| value => value === null

///|
extern "js" fn is_undefined(value : @host.NativeError) -> Bool =
  #| value => value === undefined

///|
async test "failure and close rejection retain structured native error identity" {
  let native = failed_engine(0)
  let lifetime = @host.EngineLifetime::EngineLifetime(native)
  guard lifetime.wait() is Failed(error) else { fail("expected failure") }
  assert_true(same_error(native, error.native()))
  assert_eq(error.code(), "PROCESSOR_FAILED")
  assert_eq(error.node_index(), Some(7))
  guard lifetime.close() is Err(close_error) else {
    fail("expected close failure")
  }
  assert_true(same_error(native, close_error.native()))
}

///|
async test "absent and explicitly null or undefined causes remain distinct" {
  let missing = @host.EngineLifetime::EngineLifetime(failed_engine(0)).wait()
  guard missing is Failed(missing_error) else { fail("expected failure") }
  assert_true(missing_error.cause() is None)
  let null_exit = @host.EngineLifetime::EngineLifetime(failed_engine(1)).wait()
  guard null_exit is Failed(null_error) else { fail("expected failure") }
  guard null_error.cause() is Some(null_cause) else {
    fail("lost explicit null cause")
  }
  assert_true(is_null(null_cause))
  let undefined_exit = @host.EngineLifetime::EngineLifetime(failed_engine(2)).wait()
  guard undefined_exit is Failed(undefined_error) else {
    fail("expected failure")
  }
  guard undefined_error.cause() is Some(undefined_cause) else {
    fail("lost explicit undefined cause")
  }
  assert_true(is_undefined(undefined_cause))
}
