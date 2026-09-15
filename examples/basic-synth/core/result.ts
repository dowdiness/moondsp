export type Result<T> = { readonly ok: true; readonly value: T } | { readonly ok: false; readonly error: Error };

export function andThen<T, U>(result: Result<T>, next: (value: T) => Result<U>): Result<U> {
  return result.ok ? next(result.value) : result;
}

export function failure(error: unknown): Result<never> {
  return { ok: false, error: error instanceof Error ? error : new Error(String(error)) };
}

/** Catch exceptions only where an external action enters the result flow. */
export function attempt<T>(action: () => T): Result<T> {
  try {
    return { ok: true, value: action() };
  } catch (error) {
    return failure(error);
  }
}

export async function attemptAsync<T>(action: () => Promise<T>): Promise<Result<T>> {
  try {
    return { ok: true, value: await action() };
  } catch (error) {
    return failure(error);
  }
}
