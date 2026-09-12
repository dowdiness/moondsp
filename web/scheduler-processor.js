import { PlaybackController } from "./playback-controller.js";

class MoonDspSchedulerProcessor extends AudioWorkletProcessor {
  constructor(options) {
    super();
    this.ready = false;
    this.wasm = null;
    this.reportedRuntimeError = false;
    this.reportedInitError = false;
    this.gain = this.sanitizeGain(options?.processorOptions?.initialGain ?? 0.3);
    this.pendingTempo = null;
    this.pendingPlayback = null;
    this.playback = null;
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
      if (data.type === "apply-score" || data.type === "restart-playback") {
        if (!this.graphInitialized && data.type === "apply-score" && data.policy === "restart") {
          if (this.pendingPlayback) this.port.postMessage({ type: "playback-superseded", revision: this.pendingPlayback.revision });
          this.pendingPlayback = data;
        } else {
          this.playback?.handle(data);
        }
      } else if (data.type === "set-scheduler-bpm") {
        if (!this.graphInitialized) {
          if (this.pendingTempo) this.port.postMessage({ type: "playback-superseded", revision: this.pendingTempo.revision });
          this.pendingTempo = data;
        } else {
          this.playback.setTempo(data);
        }
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
        "scheduler_bpm",
        "clear_playback_input", "push_playback_char",
        "prepare_pattern_input", "prepare_song_input",
        "apply_prepared_playback", "discard_prepared_playback", "restart_playback",
        "scheduler_sample_position", "get_playback_error_length", "get_playback_error_char",
      ]);
      if (missingExports.length > 0) {
        throw new Error(`Scheduler browser exports not found: ${missingExports.join(", ")}`);
      }

      this.playback = new PlaybackController(this.wasm, reply => this.port.postMessage(reply));
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
    if (this.graphInitialized) {
      if (!this.reportedInitError) {
        this.reportedInitError = true;
        this.postError("Audio block size changed; rebuild the audio engine");
      }
      return false;
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
    if (this.pendingTempo) {
      this.playback.setTempo(this.pendingTempo);
      this.pendingTempo = null;
    }
    this.applyGain();
    if (!this.pendingPlayback) {
      return;
    }
    const request = this.pendingPlayback;
    this.pendingPlayback = null;
    this.playback.handle(request);
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

    this.playback.didRender(left.length);

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
