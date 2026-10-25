/** A structured failure from graph mounting, lifecycle, or the audio host. */
export class GraphEngineError extends Error {
  constructor(code, message, nodeIndex) {
    super(message);
    this.name = 'GraphEngineError';
    this.code = code;
    if (nodeIndex !== undefined) this.nodeIndex = nodeIndex;
  }
}

const invalidParams = () => new GraphEngineError('INVALID_GRAPH', 'Graph parameters must be a record of finite numbers');
const snapshotParams = values => {
  if (values === null || typeof values !== 'object' || Array.isArray(values)) throw invalidParams();
  const snapshot = Object.create(null);
  try {
    for (const name of Object.keys(values)) {
      const value = values[name];
      if (typeof value !== 'number' || !Number.isFinite(value)) throw invalidParams();
      snapshot[name] = value;
    }
  } catch (error) {
    if (error instanceof GraphEngineError) throw error;
    throw invalidParams();
  }
  return snapshot;
};

// Capture data once and resolve names using this mount's compiled bindings.
// DSP-specific ranges and atomic application remain MoonBit's responsibility.
const encodeUpdate = (update, bindings) => {
  try {
    const invalid = () => { throw new TypeError('Invalid update data'); };
    const record = value => {
      if (value === null || typeof value !== 'object') invalid();
      const prototype = Object.getPrototypeOf(value);
      if (prototype !== null && prototype !== Object.prototype) invalid();
      return value;
    };
    const data = (value, key) => {
      const descriptor = Object.getOwnPropertyDescriptor(value, key);
      if (!descriptor || !Object.hasOwn(descriptor, 'value')) invalid();
      return descriptor.value;
    };
    // Field order in the caller's object must not change transaction order.
    for (const key of Reflect.ownKeys(record(update))) {
      if (key !== 'params' && key !== 'gates') invalid();
    }
    const commands = [];
    if (Object.hasOwn(update, 'params')) {
      const params = record(data(update, 'params'));
      for (const name of Reflect.ownKeys(params)) {
        if (typeof name !== 'string' || !Object.hasOwn(bindings.params, name)) invalid();
        const value = data(params, name);
        if (typeof value !== 'number' || !Number.isFinite(value)) invalid();
        for (const target of bindings.params[name]) commands.push(target, value);
      }
    }
    if (Object.hasOwn(update, 'gates')) {
      const gates = data(update, 'gates');
      if (!Array.isArray(gates)) invalid();
      const length = data(gates, 'length');
      // Only dense indexed data: no holes, extra keys, or serialization hooks.
      if (length > 64 || Reflect.ownKeys(gates).length !== length + 1) invalid();
      for (let i = 0; i < length; i++) {
        const gate = record(data(gates, String(i)));
        const keys = Reflect.ownKeys(gate);
        if (keys.length !== 2 || !keys.includes('target') || !keys.includes('action')) invalid();
        const target = data(gate, 'target');
        const action = data(gate, 'action');
        if (typeof target !== 'string' || !Object.hasOwn(bindings.gates, target) ||
            (action !== 'on' && action !== 'off')) invalid();
        commands.push(bindings.gates[target], action === 'on' ? 1 : 0);
      }
    }
    return new Float64Array(commands);
  } catch (_) {
    throw new GraphEngineError('INVALID_CONTROL', 'Update must contain finite numeric params and ordered target/action gates');
  }
};

/** Build a reusable description; MoonBit remains the graph validator/compiler. */
export function Graph(params, build) {
  const defaults = Object.freeze(snapshotParams(params));
  const nodes = [];
  const references = new WeakMap();
  let active = true;
  const invalid = message => new GraphEngineError('INVALID_GRAPH', message);
  const index = (reference, kind) => {
    const entry = references.get(reference);
    if (!entry || (kind && entry.kind !== kind)) throw invalid('Expected a node from this graph');
    return entry.index;
  };
  const scalar = value => typeof value === 'object' && value !== null
    ? Object.freeze({ ...value }) : value;
  const add = node => {
    if (!active) throw invalid('Graph construction has finished');
    const reference = Object.freeze({});
    references.set(reference, { index: nodes.length, kind: node.type });
    nodes.push(Object.freeze(node));
    return reference;
  };
  const builder = Object.freeze({
    param(name) {
      if (!active) throw invalid('Graph construction has finished');
      if (!Object.hasOwn(defaults, name)) throw invalid(`Unknown parameter ${name}`);
      return Object.freeze({ param: name });
    },
    oscillator: (waveform, frequency) => add({ type: 'oscillator', waveform, frequency: scalar(frequency) }),
    gain: (input, gain) => add({ type: 'gain', input: index(input), gain: scalar(gain) }),
    mul: (left, right) => add({ type: 'mul', input0: index(left), input1: index(right) }),
    biquad: (input, mode, cutoff, q) => add({ type: 'biquad', input: index(input), mode, cutoff: scalar(cutoff), q: scalar(q) }),
    adsr: ({ attackMs, decayMs, sustain, releaseMs }) => add({
      type: 'adsr', attackMs: scalar(attackMs), decayMs: scalar(decayMs),
      sustain: scalar(sustain), releaseMs: scalar(releaseMs),
    }),
  });
  try {
    const result = build(builder);
    if (!result || typeof result !== 'object' || !Object.hasOwn(result, 'output')) {
      throw invalid('Return an output node synchronously');
    }
    const gates = Object.create(null);
    if (Object.hasOwn(result, 'gates')) {
      if (!result.gates || typeof result.gates !== 'object' || Array.isArray(result.gates)) {
        throw invalid('Expected named ADSR references');
      }
      for (const [name, reference] of Object.entries(result.gates)) gates[name] = index(reference, 'adsr');
    }
    add({ type: 'output', input: index(result.output) });
    return Object.freeze({ params: defaults, gates: Object.freeze(gates), nodes: Object.freeze(nodes) });
  } finally {
    active = false;
  }
}

const hostError = (message, cause) => {
  if (cause instanceof GraphEngineError) return cause;
  const error = new GraphEngineError('HOST_ERROR', message);
  if (cause !== undefined) error.cause = cause;
  return error;
};

const closedError = () => new GraphEngineError('ENGINE_CLOSED', 'The graph engine is closed');

// Both owners use the same release order, even if a native operation throws.
const releaseNode = (node, retire) => {
  node.onprocessorerror = null;
  node.port.onmessage = null;
  let error = null;
  if (retire) {
    try { node.port.postMessage({ type: 'close' }); }
    catch (cause) { error ??= hostError('Failed to retire the graph processor', cause); }
  }
  try { node.disconnect(); }
  catch (cause) { error ??= hostError('Failed to disconnect the graph output', cause); }
  try { node.port.close(); }
  catch (cause) { error ??= hostError('Failed to close the graph message port', cause); }
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
  let interruption = null;
  const loading = new AbortController();
  let interrupt;
  // Resolve rather than reject: interruption can precede the first async wait.
  const interrupted = new Promise(resolve => { interrupt = resolve; });
  const release = () => {
    if (node) releaseNode(node, context.state !== 'closed');
    node = undefined;
  };
  const stop = error => {
    if (interruption) return;
    interruption = error;
    interrupt(error);
    loading.abort();
    release();
  };
  const onAbort = () => {
    const error = new GraphEngineError('ABORTED', 'Graph engine creation was aborted');
    error.cause = signal.reason;
    stop(error);
  };
  const onStateChange = () => {
    if (context.state === 'closed') stop(closedError());
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
      stop(new GraphEngineError('PROCESSOR_FAILED', message));
    };
    node = new AudioWorkletNode(context, 'moondsp-graph', {
      numberOfInputs: 0,
      numberOfOutputs: 1,
      outputChannelCount: [1],
      processorOptions: { wasmModule },
    });
    node.onprocessorerror = () => fail('AudioWorklet processor failed');
    node.port.onmessage = ({ data }) => {
      if (data.type === 'ready') resolveReady();
      else if (data.type === 'fatal') fail(data.message);
    };
    await waitInit(ready);
    onStateChange();
    if (interruption) throw interruption;
    // No await during handoff: runtime monitoring replaces startup monitoring
    // before another browser event can run. Creation's signal owns nothing after this.
    const engine = createSession(context, node, closeTimeoutMs);
    node = undefined;
    return engine;
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
    context.removeEventListener('statechange', onStateChange);
  }
}

// Owns an initialized node only; no loading or creation-cancellation state.
function createSession(context, node, closeTimeoutMs) {
  let nextId = 1;
  let closure = null;
  let terminal = null;
  let released = false;
  const pending = new Map();
  const waiters = new Set();
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
  const release = (retire = false) => {
    if (released) return null;
    released = true;
    context.removeEventListener('statechange', onStateChange);
    return releaseNode(node, retire);
  };
  const onStateChange = () => {
    if (context.state !== 'closed') return;
    rejectPending(closedError());
    const error = release();
    finish(error ? { type: 'failed', error } : { type: 'closed' });
  };
  const fail = message => {
    if (terminal) return;
    const error = new GraphEngineError('PROCESSOR_FAILED', message);
    // Publish the primary failure before cleanup, which cannot replace it.
    finish({ type: 'failed', error });
    rejectPending(error);
    release(!closure && context.state !== 'closed');
  };
  context.addEventListener('statechange', onStateChange);
  node.onprocessorerror = () => fail('AudioWorklet processor failed');
  node.port.onmessage = ({ data }) => {
    if (data.type === 'fatal') { fail(data.message); return; }
    const request = pending.get(data.id);
    if (!request) return;
    pending.delete(data.id);
    if (data.ok) request.resolve(data.value);
    else request.reject(new GraphEngineError(data.error.code, data.error.message, data.error.nodeIndex));
  };

  // Closing/context state retains precedence for commands, independently of wait's result.
  const unavailable = () => closure || context.state === 'closed' ? closedError() : failure();
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
      if (graph !== null && typeof graph === 'object' && !Array.isArray(graph)) {
        graph = { ...graph };
        if (Object.hasOwn(graph, 'params')) graph.params = snapshotParams(graph.params);
        if (Object.hasOwn(graph, 'gates')) graph.gates = snapshotParams(graph.gates);
      }
      const { handle, bindings } = await request('mount', { graph });
      let unmounting = null;
      const command = action => unmounting
        ? Promise.reject(new GraphEngineError('INVALID_HANDLE', 'The graph has been unmounted'))
        : request('command', { handle, command: action });
      return Object.freeze({
        play() { return command(0); },
        pause() { return command(1); },
        update(changes) {
          if (unmounting) return Promise.reject(new GraphEngineError('INVALID_HANDLE', 'The graph has been unmounted'));
          const error = unavailable();
          if (error) return Promise.reject(error);
          let commands;
          try { commands = encodeUpdate(changes, bindings); }
          catch (error) { return Promise.reject(error); }
          return request('update', { handle, commands });
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
