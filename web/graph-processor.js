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
      for (const name of ['graph_host_begin', 'graph_host_push', 'graph_host_prepare',
        'graph_host_command', 'graph_host_process', 'graph_host_sample',
        'get_browser_error_length', 'get_browser_error_char']) {
        if (typeof this.wasm[name] !== 'function') throw new Error(`Missing export: ${name}`);
      }
      this.port.postMessage({ type: 'ready' });
    } catch (error) {
      if (this.closed) return;
      this.failed = true;
      this.port.postMessage({ type: 'fatal', message: String(error.message ?? error) });
    }
  }

  hostError(code, nodeIndex) {
    let message = '';
    for (let i = 0; i < this.wasm.get_browser_error_length(); i++) {
      message += String.fromCharCode(this.wasm.get_browser_error_char(i));
    }
    return Object.assign(new Error(message), { code, nodeIndex });
  }

  mount(graph) {
    const reject = (message, nodeIndex) => {
      throw Object.assign(new Error(message), { code: 'INVALID_GRAPH', nodeIndex });
    };
    if (!graph || !Array.isArray(graph.nodes) || graph.nodes.length === 0 || graph.nodes.length > 64) {
      reject('A graph must contain 1 to 64 nodes');
    }
    if (!this.wasm.graph_host_begin(sampleRate)) throw this.hostError('MOUNT_REJECTED');
    const waveforms = ['sine', 'saw', 'square', 'triangle'];
    for (let i = 0; i < graph.nodes.length; i++) {
      const node = graph.nodes[i];
      if (!node || typeof node !== 'object') reject('Expected a node object', i);
      let kind, value = 0, input = 0, waveform = 0;
      switch (node.type) {
        case 'oscillator':
          kind = 0;
          value = node.frequency;
          waveform = waveforms.indexOf(node.waveform);
          if (waveform < 0) reject('Unknown oscillator waveform', i);
          break;
        case 'gain':
          kind = 1;
          value = node.gain;
          input = node.input;
          break;
        case 'output':
          kind = 2;
          input = node.input;
          break;
        default: reject('Unknown node type', i);
      }
      if (typeof value !== 'number' || !Number.isFinite(value)) reject('Node value must be finite', i);
      if (!Number.isInteger(input) || input < 0 || input >= graph.nodes.length) reject('Input index is outside the graph', i);
      if (!this.wasm.graph_host_push(kind, input, value, waveform)) throw this.hostError('INVALID_GRAPH', i);
    }
    const handle = this.wasm.graph_host_prepare();
    if (handle === 0) throw this.hostError('INVALID_GRAPH');
    return handle;
  }

  receive(data) {
    if (this.closed) return;
    // Cancellation can arrive before WASM instantiation has completed.
    if (data.type === 'close') {
      this.closed = true;
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
          if (!this.wasm.graph_host_command(data.handle, data.command)) throw this.hostError('INVALID_HANDLE');
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
      this.port.postMessage({ type: 'fatal', message: 'Unsupported render quantum: expected 128 frames' });
      return false;
    }
    for (let i = 0; i < channel.length; i++) channel[i] = this.wasm.graph_host_sample(i);
    return true;
  }
}

registerProcessor('moondsp-graph', MoonDspGraphProcessor);
