class MoonDspSchedulerProcessor extends AudioWorkletProcessor {
  constructor(options) {
    super();
    this.ready = false;
    this.wasm = null;
    this.reportedRuntimeError = false;
    this.reportedInitError = false;
    this.gain = this.sanitizeGain(options?.processorOptions?.initialGain ?? 0.3);
    this.bpm = null;
    this.pendingPlayback = null;
    this.graphInitialized = false;
    this.graphBlockSize = 0;

    this.port.onmessage = (event) => {
      const data = event.data;
      if (!data || typeof data !== "object") {
        return;
      }

      if (!this.wasm) {
        return;
      }
      if (data.type === "set-pattern-text") {
        this.setPatternText(data.text || "", typeof data.revision === "number" ? data.revision : undefined);
      } else if (data.type === "set-song-text") {
        this.setSongText(data.text || "", typeof data.revision === "number" ? data.revision : undefined);
      } else if (data.type === "set-scheduler-bpm") {
        this.bpm = Number(data.bpm);
        this.applyBpm();
      } else if (data.type === "set-scheduler-gain") {
        this.gain = this.sanitizeGain(data.gain);
        this.applyGain();
      }
    };

    const wasmModule = options?.processorOptions?.wasmModule;
    if (wasmModule) {
      this.initWasm(wasmModule);
    } else {
      this.port.postMessage({ type: "error", message: "Missing wasm module" });
    }
  }

  async initWasm(wasmModule) {
    try {
      const instance = await WebAssembly.instantiate(wasmModule, {
        spectest: { print_char() {} },
        "moonbit:ffi": {
          make_closure(funcref, closure) {
            return funcref.bind(null, closure);
          },
        },
      });
      this.wasm = instance.exports;

      const missingExports = this.missingExports([
        "init_scheduler_graph",
        "process_scheduler_block",
        "scheduler_left_sample",
        "scheduler_right_sample",
        "set_scheduler_bpm",
        "set_scheduler_gain",
        "clear_pattern_input",
        "push_pattern_char",
        "eval_pattern_input",
        "clear_song_input",
        "push_song_char",
        "eval_song_input",
        "get_pattern_error_length",
        "get_pattern_error_char",
        "get_song_error_length",
        "get_song_error_char",
      ]);
      if (missingExports.length > 0) {
        throw new Error(`Scheduler browser exports not found: ${missingExports.join(", ")}`);
      }

      this.ready = true;
      this.port.postMessage({ type: "ready", mode: "scheduler-dsp" });
    } catch (error) {
      this.ready = false;
      this.port.postMessage({
        type: "error",
        message: error instanceof Error ? error.message : String(error),
      });
    }
  }

  ensureSchedulerGraph(blockSize) {
    if (this.graphInitialized && this.graphBlockSize === blockSize) {
      return true;
    }
    const ok = this.wasm.init_scheduler_graph(sampleRate, blockSize);
    this.graphInitialized = ok;
    this.graphBlockSize = ok ? blockSize : 0;
    if (ok) {
      this.applySchedulerState();
    } else if (!this.reportedInitError) {
      this.reportedInitError = true;
      this.postError(this.browserErrorMessage("Scheduler graph initialization failed"));
    }
    return ok;
  }

  applySchedulerState() {
    this.applyBpm();
    this.applyGain();
    if (!this.pendingPlayback) {
      return;
    }
    if (this.pendingPlayback.kind === "pattern") {
      this.setPatternText(this.pendingPlayback.text, this.pendingPlayback.revision, false);
    } else {
      this.setSongText(this.pendingPlayback.text, this.pendingPlayback.revision, false);
    }
  }

  applyBpm() {
    if (this.graphInitialized && Number.isFinite(this.bpm) && typeof this.wasm.set_scheduler_bpm === "function") {
      this.wasm.set_scheduler_bpm(this.bpm);
    }
  }

  applyGain() {
    if (this.graphInitialized && typeof this.wasm.set_scheduler_gain === "function") {
      this.wasm.set_scheduler_gain(this.gain);
    }
  }

  sanitizeGain(value) {
    const gain = Number(value);
    return Number.isFinite(gain) ? Math.max(0, Math.min(1, gain)) : 0.3;
  }

  setPatternText(text, revision, remember = true) {
    if (remember) {
      this.pendingPlayback = { kind: "pattern", text, revision };
    }
    if (!this.graphInitialized) {
      return;
    }
    if (!this.ready || !this.wasm ||
        typeof this.wasm.clear_pattern_input !== "function" ||
        typeof this.wasm.push_pattern_char !== "function" ||
        typeof this.wasm.eval_pattern_input !== "function") {
      return;
    }
    this.wasm.clear_pattern_input();
    for (let i = 0; i < text.length; i += 1) {
      this.wasm.push_pattern_char(text.charCodeAt(i));
    }
    const result = this.wasm.eval_pattern_input();
    if (result === 0) {
      this.port.postMessage({ type: "pattern-updated", revision });
    } else {
      this.port.postMessage({
        type: "pattern-error",
        message: this.parseErrorMessage("get_pattern_error_length", "get_pattern_error_char", "parse error"),
        revision,
      });
    }
  }

  setSongText(text, revision, remember = true) {
    if (remember) {
      this.pendingPlayback = { kind: "song", text, revision };
    }
    if (!this.graphInitialized) {
      return;
    }
    if (!this.ready || !this.wasm ||
        typeof this.wasm.clear_song_input !== "function" ||
        typeof this.wasm.push_song_char !== "function" ||
        typeof this.wasm.eval_song_input !== "function") {
      return;
    }
    this.wasm.clear_song_input();
    for (let i = 0; i < text.length; i += 1) {
      this.wasm.push_song_char(text.charCodeAt(i));
    }
    const result = this.wasm.eval_song_input();
    if (result === 0) {
      this.port.postMessage({ type: "song-updated", revision });
    } else {
      this.port.postMessage({
        type: "song-error",
        message: this.parseErrorMessage("get_song_error_length", "get_song_error_char", "song parse error"),
        revision,
      });
    }
  }

  process(_inputs, outputs) {
    const output = outputs[0];
    if (!output || output.length === 0) {
      return true;
    }

    const left = output[0];
    const right = output[1];
    if (!this.ready || !this.wasm || !this.ensureSchedulerGraph(left.length)) {
      this.fillSilence(left, right);
      return true;
    }

    const processed = this.wasm.process_scheduler_block();
    if (!processed) {
      this.fillSilence(left, right);
      if (!this.reportedRuntimeError) {
        this.reportedRuntimeError = true;
        this.postError(this.browserErrorMessage("Scheduler block processing failed"));
      }
      return true;
    }

    for (let index = 0; index < left.length; index += 1) {
      left[index] = this.wasm.scheduler_left_sample(index);
      if (right) {
        right[index] = this.wasm.scheduler_right_sample(index);
      }
    }
    return true;
  }

  missingExports(names) {
    return names.filter((name) => typeof this.wasm[name] !== "function");
  }

  postError(message) {
    this.port.postMessage({ type: "error", message });
  }

  fillSilence(left, right) {
    left.fill(0);
    if (right) {
      right.fill(0);
    }
  }

  parseErrorMessage(lengthExport, charExport, fallback) {
    if (this.wasm &&
        typeof this.wasm[lengthExport] === "function" &&
        typeof this.wasm[charExport] === "function") {
      const len = this.wasm[lengthExport]();
      if (len > 0) {
        const codes = new Array(len);
        for (let i = 0; i < len; i += 1) {
          codes[i] = this.wasm[charExport](i);
        }
        return String.fromCharCode(...codes);
      }
    }
    return fallback;
  }

  browserErrorMessage(fallback) {
    return this.parseErrorMessage("get_browser_error_length", "get_browser_error_char", fallback);
  }
}

registerProcessor("moondsp-scheduler", MoonDspSchedulerProcessor);
