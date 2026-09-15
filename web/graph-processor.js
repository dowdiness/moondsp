// Private transport for graph-engine.js. Public callers use the engine API.
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
        'graph_host_command', 'graph_host_apply_controls', 'graph_host_process', 'graph_host_sample', 'graph_host_close',
        'graph_host_error_length', 'graph_host_error_char']) {
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
    let encoded = '';
    for (let i = 0; i < this.wasm.graph_host_error_length(); i++) {
      encoded += String.fromCharCode(this.wasm.graph_host_error_char(i));
    }
    const detail = JSON.parse(encoded);
    return Object.assign(new Error(detail.message), detail);
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
    return handle;
  }

  applyControls(handle, controls) {
    let encoded;
    try {
      encoded = JSON.stringify(controls);
    } catch (_) {
      throw Object.assign(new Error('Invalid graph controls'), { code: 'INVALID_CONTROL' });
    }
    this.wasm.graph_host_clear_input();
    if (encoded !== undefined) {
      for (const char of encoded) this.wasm.graph_host_push_char(char.codePointAt(0));
    }
    if (!this.wasm.graph_host_apply_controls(handle)) throw this.hostError();
  }

  setParams(handle, values) {
    let encoded;
    try {
      encoded = JSON.stringify(values);
    } catch (_) {
      throw Object.assign(new Error('Invalid graph parameters'), { code: 'INVALID_CONTROL' });
    }
    this.wasm.graph_host_clear_input();
    if (encoded !== undefined) {
      for (const char of encoded) this.wasm.graph_host_push_char(char.codePointAt(0));
    }
    if (!this.wasm.graph_host_set_params(handle)) throw this.hostError();
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
        case 'applyControls':
          if (!Number.isInteger(data.handle) || data.handle <= 0 || data.handle >= 2147483647) {
            throw Object.assign(new Error('Invalid graph handle'), { code: 'INVALID_HANDLE' });
          }
          value = this.applyControls(data.handle, data.controls);
          break;
        case 'setParams':
          if (!Number.isInteger(data.handle) || data.handle <= 0 || data.handle >= 2147483647) {
            throw Object.assign(new Error('Invalid graph handle'), { code: 'INVALID_HANDLE' });
          }
          value = this.setParams(data.handle, data.values);
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
