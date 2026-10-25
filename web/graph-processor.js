// Private transport for graph-engine.js. Public callers use the engine API.
const hostErrorCodes = [
  null, 'INVALID_STATE', 'ENGINE_CLOSED', 'MOUNT_CLOSED', 'MOUNT_REJECTED',
  'INVALID_HANDLE', 'PROCESSOR_FAILED', 'INVALID_CONTROL', 'INVALID_GRAPH',
];

class MoonDspGraphProcessor extends AudioWorkletProcessor {
  constructor(options) {
    super();
    this.wasm = null;
    this.failed = false;
    this.closed = false;
    this.port.onmessage = ({ data }) => this.receive(data);
    this.initialize(options.processorOptions.wasmModule);
  }

  async initialize(module) {
    try {
      const instance = await WebAssembly.instantiate(module, {
        spectest: { print_char() {} },
        'moonbit:ffi': {
          make_closure(funcref, closure) { return funcref.bind(null, closure); },
        },
      });
      if (this.closed) return;
      this.wasm = instance.exports;
      for (const name of ['graph_host_init', 'graph_host_clear_input', 'graph_host_push_char', 'graph_host_mount',
        'graph_host_command', 'graph_host_update', 'graph_host_process', 'graph_host_sample', 'graph_host_close',
        'graph_host_begin_update', 'graph_host_push_update', 'graph_host_bindings_length', 'graph_host_bindings_char',
        'graph_host_error_length', 'graph_host_error_char', 'graph_host_error_code', 'graph_host_error_node_index']) {
        if (typeof this.wasm[name] !== 'function') throw new Error(`Missing export: ${name}`);
      }
      if (!this.wasm.graph_host_init(sampleRate)) throw this.hostError();
      this.port.postMessage({ type: 'ready' });
    } catch (error) {
      if (this.closed) return;
      this.failed = true;
      this.port.postMessage({ type: 'fatal', message: String(error.message ?? error) });
    }
  }

  hostError() {
    let message = '';
    for (let i = 0; i < this.wasm.graph_host_error_length(); i++) {
      message += String.fromCharCode(this.wasm.graph_host_error_char(i));
    }
    const error = new Error(message);
    error.code = hostErrorCodes[this.wasm.graph_host_error_code()];
    const nodeIndex = this.wasm.graph_host_error_node_index();
    if (nodeIndex >= 0) error.nodeIndex = nodeIndex;
    return error;
  }

  mount(graph) {
    // Only serialization lives here; MoonBit decodes, validates, and mounts.
    const encoded = JSON.stringify(graph);
    this.wasm.graph_host_clear_input();
    if (encoded !== undefined) {
      for (const char of encoded) this.wasm.graph_host_push_char(char.codePointAt(0));
    }
    const handle = this.wasm.graph_host_mount();
    if (handle === 0) throw this.hostError();
    let bindings = '';
    for (let i = 0; i < this.wasm.graph_host_bindings_length(); i++) {
      bindings += String.fromCharCode(this.wasm.graph_host_bindings_char(i));
    }
    return { handle, bindings: JSON.parse(bindings) };
  }

  update(handle, commands) {
    if (!(commands instanceof Float64Array) || commands.length % 2 !== 0 || commands.length > 640) {
      throw Object.assign(new Error('Invalid update batch'), { code: 'INVALID_CONTROL' });
    }
    this.wasm.graph_host_begin_update();
    for (let i = 0; i < commands.length; i += 2) {
      const target = commands[i];
      if (!Number.isInteger(target) || target < 0 || target >= 320) {
        throw Object.assign(new Error('Invalid update target'), { code: 'INVALID_CONTROL' });
      }
      if (!this.wasm.graph_host_push_update(target, commands[i + 1])) throw this.hostError();
    }
    if (!this.wasm.graph_host_update(handle)) throw this.hostError();
  }

  receive(data) {
    if (this.closed) return;
    // Cancellation can arrive before WASM instantiation has completed.
    if (data.type === 'close') {
      this.closed = true;
      this.wasm?.graph_host_close?.();
      this.wasm = null;
      this.port.postMessage({ id: data.id, ok: true });
      return;
    }
    if (!this.wasm || this.failed) return;
    try {
      let value;
      switch (data.type) {
        case 'mount': value = this.mount(data.graph); break;
        case 'command':
          if (!Number.isInteger(data.handle) || data.handle <= 0 || data.handle >= 2147483647 ||
              !Number.isInteger(data.command) || data.command < 0 || data.command > 2) {
            throw Object.assign(new Error('Invalid graph command'), { code: 'INVALID_HANDLE' });
          }
          if (!this.wasm.graph_host_command(data.handle, data.command)) throw this.hostError();
          break;
        case 'update':
          if (!Number.isInteger(data.handle) || data.handle <= 0 || data.handle >= 2147483647) {
            throw Object.assign(new Error('Invalid graph handle'), { code: 'INVALID_HANDLE' });
          }
          value = this.update(data.handle, data.commands);
          break;
        default: throw Object.assign(new Error('Unknown request'), { code: 'INVALID_REQUEST' });
      }
      this.port.postMessage({ id: data.id, ok: true, value });
    } catch (error) {
      this.port.postMessage({ id: data.id, ok: false, error: {
        code: error.code ?? 'HOST_ERROR', message: error.message ?? String(error), nodeIndex: error.nodeIndex,
      } });
    }
  }

  process(_inputs, outputs) {
    const channel = outputs[0]?.[0];
    if (this.closed || this.failed) return false;
    if (!channel || !this.wasm) return true;
    if (!this.wasm.graph_host_process(channel.length)) {
      this.failed = true;
      this.port.postMessage({ type: 'fatal', message: this.hostError().message });
      return false;
    }
    for (let i = 0; i < channel.length; i++) channel[i] = this.wasm.graph_host_sample(i);
    return true;
  }
}

registerProcessor('moondsp-graph', MoonDspGraphProcessor);
