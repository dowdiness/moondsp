class MoonBitDspProcessor extends AudioWorkletProcessor {
  constructor(options) {
    super();
    this.freq = 440.0;
    this.gain = 0.3;
    this.ready = false;
    this.initError = null;
    this.wasm = null;

    this.port.onmessage = (event) => {
      const data = event.data;
      if (!data || typeof data !== "object") {
        return;
      }
      if (data.type === "set-freq") {
        this.freq = Number(data.value);
      } else if (data.type === "set-gain") {
        this.gain = Number(data.value);
      }
    };

    const wasmModule = options?.processorOptions?.wasmModule;
    if (wasmModule) {
      this.initWasm(wasmModule);
    } else {
      this.initError = "Missing wasm module";
      this.port.postMessage({ type: "error", message: this.initError });
    }
  }

  async initWasm(wasmModule) {
    try {
      const importObject = {
        spectest: {
          print_char() {},
        },
        "moonbit:ffi": {
          make_closure(funcref, closure) {
            return funcref.bind(null, closure);
          },
        },
      };

      const instance = await WebAssembly.instantiate(wasmModule, importObject);
      this.wasm = instance.exports;
      if (typeof this.wasm.reset_phase === "function") {
        this.wasm.reset_phase();
      }
      if (typeof this.wasm.tick !== "function") {
        throw new Error("tick export not found");
      }
      this.ready = true;
      this.port.postMessage({
        type: "ready",
        exports: Object.keys(this.wasm),
      });
    } catch (error) {
      this.initError = error instanceof Error ? error.message : String(error);
      this.port.postMessage({ type: "error", message: this.initError });
    }
  }

  process(_inputs, outputs) {
    const output = outputs[0];
    if (!output || output.length === 0) {
      return true;
    }

    const left = output[0];
    const right = output[1];

    if (!this.ready || !this.wasm) {
      left.fill(0);
      if (right) {
        right.fill(0);
      }
      return true;
    }

    for (let index = 0; index < left.length; index += 1) {
      const sample = this.wasm.tick(this.freq, sampleRate) * this.gain;
      left[index] = sample;
      if (right) {
        right[index] = sample;
      }
    }

    return true;
  }
}

registerProcessor("moonbit-dsp", MoonBitDspProcessor);
