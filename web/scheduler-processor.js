import { PlaybackController } from "./playback-controller.js";

class MoonDspSchedulerProcessor extends AudioWorkletProcessor {
  constructor(options) {
    super();
    this.ready = false;
    this.wasm = null;
    this.reportedRuntimeError = false;
    this.reportedInitError = false;
    this.gain = this.sanitizeGain(options?.processorOptions?.initialGain ?? 0.3);
    this.pendingCommands = [];
    this.playback = null;
    this.graphInitialized = false;
    this.graphBlockSize = 0;
    this.statusCountdown = 0;

    this.port.onmessage = (event) => {
      const data = event.data;
      if (!data || typeof data !== "object") return;
      if (!this.wasm || !this.graphInitialized) {
        this.pendingCommands.push(data);
        return;
      }
      this.dispatchCommand(data);
    };

    const wasmModule = options?.processorOptions?.wasmModule;
    if (wasmModule) {
      this.initWasm(wasmModule);
    } else {
      this.port.postMessage({ type: "error", message: "Missing wasm module" });
    }
  }
  dispatchCommand(data) {
    if (data.type === "player-update" || data.type === "player-restart" ||
        data.type === "player-play" || data.type === "player-pause" ||
        data.type === "player-seek" || data.type === "player-loop" ||
        data.type === "player-seek-section" || data.type === "player-loop-section" ||
        data.type === "player-whole" || data.type === "set-scheduler-bpm") {
      this.playback.handle(data);
    } else if (data.type === "set-scheduler-gain") {
      this.gain = this.sanitizeGain(data.gain);
      this.applyGain();
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
        "init_scheduler_graph", "process_scheduler_block",
        "scheduler_left_sample", "scheduler_right_sample",
        "set_scheduler_bpm", "set_scheduler_gain", "scheduler_bpm",
        "clear_playback_input", "push_playback_char",
        "player_update_input", "player_restart_input", "player_play", "player_pause",
        "player_seek_cycle", "player_loop_cycles", "player_whole_song",
        "player_seek_section", "player_loop_section",
        "player_loop_begin", "player_loop_end", "player_section_count",
        "player_section_start", "player_section_end",
        "player_section_label_length", "player_section_label_char",
        "player_state", "player_pending_count", "player_skipped_count",
        "player_mode", "scheduler_cycle_position",
        "scheduler_sample_position", "get_playback_error_length", "get_playback_error_char",
      ]);
      if (missingExports.length > 0) {
        throw new Error(`Scheduler browser exports not found: ${missingExports.join(", ")}`);
      }

      this.playback = new PlaybackController(this.wasm, reply => this.port.postMessage(reply));
      this.ready = true;
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
      this.port.postMessage({ type: "ready", mode: "scheduler-dsp" });
      this.applySchedulerState();
    } else if (!this.reportedInitError) {
      this.reportedInitError = true;
      this.postError(this.browserErrorMessage("Scheduler graph initialization failed"));
    }
    return ok;
  }

  applySchedulerState() {
    this.applyGain();
    const pending = this.pendingCommands;
    this.pendingCommands = [];
    for (const command of pending) this.dispatchCommand(command);
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
        this.postError(this.playback.errorMessage());
      }
      return true;
    }

    this.statusCountdown -= 1;
    if (this.statusCountdown <= 0) {
      this.statusCountdown = 32;
      this.port.postMessage({ type: "player-status", ...this.playback.snapshot() });
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
