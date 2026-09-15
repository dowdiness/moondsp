/** A structured failure from graph mounting, lifecycle, or the audio host. */
export class GraphEngineError extends Error {
  constructor(code, message, nodeIndex) {
    super(message);
    this.name = 'GraphEngineError';
    this.code = code;
    if (nodeIndex !== undefined) this.nodeIndex = nodeIndex;
  }
}

const hostError = (message, cause) => {
  if (cause instanceof GraphEngineError) return cause;
  const error = new GraphEngineError('HOST_ERROR', message);
  if (cause !== undefined) error.cause = cause;
  return error;
};

/**
 * Create a mono graph engine in a caller-owned, suspended AudioContext.
 * OfflineAudioContext is supported for deterministic host verification.
 * signal owns creation only. wait({ signal }) observes, but never ends, lifetime.
 * close() closes admission synchronously and bounds the shutdown acknowledgement.
 */
export async function GraphEngine({
  context,
  wasmUrl = new URL('./moonbit_dsp.wasm', import.meta.url),
  processorUrl = new URL('./graph-processor.js', import.meta.url),
  signal,
  closeTimeoutMs = 5000,
}) {
  if (!context || context.state !== 'suspended') {
    throw new GraphEngineError('INVALID_STATE', 'Create the engine in a suspended audio context');
  }
  if (!Number.isFinite(closeTimeoutMs) || closeTimeoutMs <= 0 || closeTimeoutMs > 2_147_483_647) {
    throw new GraphEngineError('INVALID_REQUEST', 'closeTimeoutMs must be positive and at most 2147483647');
  }
  let node;
  let nextId = 1;
  let closed = false;
  let closure = null;
  let terminal = null;
  let interruption = null;
  let released = false;
  const pending = new Map();
  const waiters = new Set();
  const loading = new AbortController();
  let interrupt;
  // Resolve rather than reject: interruption can precede the first async wait.
  const interrupted = new Promise(resolve => { interrupt = resolve; });
  const closedError = () => new GraphEngineError('ENGINE_CLOSED', 'The graph engine is closed');
  const failure = () => terminal?.type === 'failed' ? terminal.error : null;
  const finish = exit => {
    if (terminal) return;
    terminal = Object.freeze(exit);
    for (const deliver of waiters) deliver(terminal);
    waiters.clear();
  };
  const rejectPending = error => {
    for (const request of pending.values()) request.reject(error);
    pending.clear();
  };
  // Attempt every local release, including when a native cleanup operation throws.
  const release = (retire = false) => {
    if (released) return null;
    released = true;
    signal?.removeEventListener('abort', onAbort);
    context.removeEventListener('statechange', onStateChange);
    let cleanupError = null;
    if (node) {
      node.onprocessorerror = null;
      node.port.onmessage = null;
      if (!closed || retire) {
        try { node.port.postMessage({ type: 'close' }); }
        catch (error) { cleanupError ??= hostError('Failed to retire the graph processor', error); }
      }
      try { node.disconnect(); }
      catch (error) { cleanupError ??= hostError('Failed to disconnect the graph output', error); }
      try { node.port.close(); }
      catch (error) { cleanupError ??= hostError('Failed to close the graph message port', error); }
    }
    return cleanupError;
  };
  const stop = error => {
    if (interruption) return null;
    interruption = error;
    interrupt(error);
    loading.abort();
    rejectPending(error);
    return release();
  };
  const onAbort = () => {
    const error = new GraphEngineError('ABORTED', 'Graph engine creation was aborted');
    error.cause = signal.reason;
    stop(error);
  };
  const onStateChange = () => {
    if (context.state === 'closed') {
      closed = true;
      const error = stop(closedError());
      finish(error ? { type: 'failed', error } : { type: 'closed' });
    }
  };
  const waitInit = async operation => {
    const value = await Promise.race([
      operation,
      interrupted.then(error => { throw error; }),
    ]);
    onStateChange();
    if (interruption) throw interruption;
    return value;
  };
  signal?.addEventListener('abort', onAbort, { once: true });
  context.addEventListener('statechange', onStateChange);
  if (signal?.aborted) onAbort();
  try {
    if (interruption) throw interruption;
    const response = await waitInit(fetch(wasmUrl, { signal: loading.signal }));
    if (!response.ok) throw new GraphEngineError('LOAD_FAILED', `WASM fetch failed: ${response.status}`);
    const bytes = await waitInit(response.arrayBuffer());
    const wasmModule = await waitInit(WebAssembly.compile(bytes));
    await waitInit(context.audioWorklet.addModule(processorUrl));
    let resolveReady;
    const ready = new Promise(resolve => { resolveReady = resolve; });
    const fail = message => {
      if (terminal) return;
      const error = new GraphEngineError('PROCESSOR_FAILED', message);
      // Report the cause before cleanup; cleanup cannot replace a runtime failure.
      finish({ type: 'failed', error });
      resolveReady(error);
      stop(error);
    };
    node = new AudioWorkletNode(context, 'moondsp-graph', {
      numberOfInputs: 0,
      numberOfOutputs: 1,
      outputChannelCount: [1],
      processorOptions: { wasmModule },
    });
    node.onprocessorerror = () => fail('AudioWorklet processor failed');
    node.port.onmessage = ({ data }) => {
      if (data.type === 'ready') { resolveReady(null); return; }
      if (data.type === 'fatal') { fail(data.message); return; }
      const request = pending.get(data.id);
      if (!request) return;
      pending.delete(data.id);
      if (data.ok) request.resolve(data.value);
      else request.reject(new GraphEngineError(data.error.code, data.error.message, data.error.nodeIndex));
    };
    const error = await waitInit(ready);
    if (error) throw error;
  } catch (cause) {
    onStateChange();
    loading.abort();
    release();
    if (interruption) throw interruption;
    if (cause instanceof GraphEngineError) throw cause;
    const error = new GraphEngineError('INITIALIZATION_FAILED', 'Failed to initialize the graph engine');
    error.cause = cause;
    throw error;
  } finally {
    signal?.removeEventListener('abort', onAbort);
  }

  // Closing/context state retains precedence for commands, independently of wait's result.
  const unavailable = () => closed || context.state === 'closed' ? closedError() : failure();
  const request = (type, payload = {}) => {
    const error = unavailable();
    if (error) return Promise.reject(error);
    const id = nextId++;
    return new Promise((resolve, reject) => {
      pending.set(id, { resolve, reject });
      try { node.port.postMessage({ id, type, ...payload }); }
      catch (error) { pending.delete(id); reject(error); }
    });
  };

  return Object.freeze({
    output: node,
    wait({ signal: observerSignal } = {}) {
      const abortError = () => {
        const error = new DOMException('Engine wait was aborted', 'AbortError');
        error.cause = observerSignal.reason;
        return error;
      };
      if (observerSignal?.aborted) return Promise.reject(abortError());
      if (terminal) return Promise.resolve(terminal);
      return new Promise((resolve, reject) => {
        const detach = () => {
          waiters.delete(deliver);
          observerSignal?.removeEventListener('abort', cancel);
        };
        const deliver = exit => { detach(); resolve(exit); };
        const cancel = () => { detach(); reject(abortError()); };
        waiters.add(deliver);
        observerSignal?.addEventListener('abort', cancel, { once: true });
      });
    },
    async mount(graph) {
      const error = unavailable();
      if (error) throw error;
      if (context.state !== 'suspended') {
        throw new GraphEngineError('MOUNT_CLOSED', 'Mount graphs before playback or resuming the context');
      }
      const handle = await request('mount', { graph });
      let unmounting = null;
      const command = action => unmounting
        ? Promise.reject(new GraphEngineError('INVALID_HANDLE', 'The graph has been unmounted'))
        : request('command', { handle, command: action });
      return Object.freeze({
        play() { return command(0); },
        pause() { return command(1); },
        applyControls(controls) {
          return unmounting
            ? Promise.reject(new GraphEngineError('INVALID_HANDLE', 'The graph has been unmounted'))
            : request('applyControls', { handle, controls });
        },
        unmount() {
          if (!unmounting) unmounting = request('command', { handle, command: 2 });
          return unmounting;
        },
      });
    },
    close() {
      if (closure) return closure;
      // Post before closing admission, without an await or a deferred task start.
      const closing = !failure() && context.state !== 'closed'
        ? request('close') : Promise.resolve();
      closed = true;
      closure = (async () => {
        let timer;
        let closeError = null;
        try {
          await Promise.race([
            closing,
            new Promise((_, reject) => {
              timer = setTimeout(() => reject(hostError('Graph engine close timed out')), closeTimeoutMs);
            }),
          ]);
        } catch (error) {
          // The context may already have stopped the worklet without an acknowledgement.
          if (context.state !== 'closed') closeError = hostError('Failed to close the graph engine', error);
        } finally {
          clearTimeout(timer);
          rejectPending(closeError ?? closedError());
          const cleanupError = release(closeError !== null);
          closeError ??= cleanupError;
          finish(closeError ? { type: 'failed', error: closeError } : { type: 'closed' });
        }
        if (closeError) throw closeError;
      })();
      return closure;
    },
  });
}
