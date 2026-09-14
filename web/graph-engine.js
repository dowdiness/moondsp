/** A structured failure from graph mounting, lifecycle, or the audio host. */
export class GraphEngineError extends Error {
  constructor(code, message, nodeIndex) {
    super(message);
    this.name = 'GraphEngineError';
    this.code = code;
    if (nodeIndex !== undefined) this.nodeIndex = nodeIndex;
  }
}

/**
 * Create a mono graph engine in a caller-owned, suspended AudioContext.
 * OfflineAudioContext is also supported for deterministic host verification.
 * Mount all graphs before playing any graph or resuming the context.
 * A MountedGraph is an opaque handle: play(), pause(), and unmount() return promises.
 * pause() preserves oscillator phase. unmount() permanently invalidates the handle.
 * signal cancels creation only; successful engines are ended with close().
 */
export async function GraphEngine({
  context,
  wasmUrl = new URL('./moonbit_dsp.wasm', import.meta.url),
  processorUrl = new URL('./graph-processor.js', import.meta.url),
  signal,
}) {
  if (!context || context.state !== 'suspended') {
    throw new GraphEngineError('INVALID_STATE', 'Create the engine in a suspended audio context');
  }
  let node;
  let nextId = 1;
  let closed = false;
  let closure = null;
  let failure = null;
  let interruption = null;
  let released = false;
  const pending = new Map();
  const loading = new AbortController();
  let interrupt;
  // Resolve rather than reject: interruption can precede the first async wait.
  const interrupted = new Promise(resolve => { interrupt = resolve; });
  const closedError = () => new GraphEngineError('ENGINE_CLOSED', 'The graph engine is closed');
  const rejectPending = error => {
    for (const request of pending.values()) request.reject(error);
    pending.clear();
  };
  const release = () => {
    if (released) return;
    released = true;
    signal?.removeEventListener('abort', onAbort);
    context.removeEventListener('statechange', onStateChange);
    if (node) {
      node.onprocessorerror = null;
      node.port.onmessage = null;
      if (!closed) node.port.postMessage({ type: 'close' });
      node.disconnect();
      node.port.close();
    }
  };
  const stop = error => {
    if (interruption) return;
    interruption = error;
    interrupt(error);
    loading.abort();
    rejectPending(error);
    release();
  };
  const onAbort = () => {
    const error = new GraphEngineError('ABORTED', 'Graph engine creation was aborted');
    error.cause = signal.reason;
    stop(error);
  };
  const onStateChange = () => {
    if (context.state === 'closed') {
      closed = true;
      stop(closedError());
    }
  };
  const wait = async operation => {
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
    const response = await wait(fetch(wasmUrl, { signal: loading.signal }));
    if (!response.ok) throw new GraphEngineError('LOAD_FAILED', `WASM fetch failed: ${response.status}`);
    const bytes = await wait(response.arrayBuffer());
    const wasmModule = await wait(WebAssembly.compile(bytes));
    await wait(context.audioWorklet.addModule(processorUrl));
    let resolveReady;
    const ready = new Promise(resolve => { resolveReady = resolve; });
    const fail = message => {
      failure = new GraphEngineError('PROCESSOR_FAILED', message);
      resolveReady(failure);
      rejectPending(failure);
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
    const error = await wait(ready);
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
    // The signal owns creation, not the returned engine's lifetime.
    signal?.removeEventListener('abort', onAbort);
  }

  // Terminal engine/context state takes precedence over processor failure
  // and mount admission, independent of earlier playback.
  const unavailable = () => closed || context.state === 'closed'
    ? new GraphEngineError('ENGINE_CLOSED', 'The graph engine is closed')
    : failure;
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
        unmount() {
          if (!unmounting) unmounting = request('command', { handle, command: 2 });
          return unmounting;
        },
      });
    },
    close() {
      if (closure) return closure;
      // Post the sole close request before closing local admission. There is
      // no await here: later calls cannot enqueue work behind that request.
      const closing = !failure && context.state !== 'closed'
        ? request('close') : Promise.resolve();
      closed = true;
      closure = closing.catch(error => {
        // Context shutdown already stops rendering; no acknowledgement is needed.
        if (context.state !== 'closed') throw error;
      }).finally(() => {
        rejectPending(closedError());
        release();
      });
      return closure;
    },
  });
}
