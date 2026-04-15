class MoonBitDspProcessor extends AudioWorkletProcessor {
  constructor(options) {
    super();
    this.freq = 440.0;
    this.gain = 0.3;
    this.pan = 0.0;
    this.delaySamples = Number(options?.processorOptions?.initialDelaySamples ?? 24);
    this.cutoff = 1800.0;
    this.ready = false;
    this.initError = null;
    this.wasm = null;
    this.prefersCompiledHotSwap = Boolean(options?.processorOptions?.useCompiledHotSwap);
    this.prefersCompiledTopologyEdit = Boolean(options?.processorOptions?.useCompiledTopologyEdit);
    this.prefersCompiledStereoHotSwap = Boolean(options?.processorOptions?.useCompiledStereoHotSwap);
    this.prefersCompiledStereoTopologyEdit = Boolean(options?.processorOptions?.useCompiledStereoTopologyEdit);
    this.prefersExitDeliverable = Boolean(options?.processorOptions?.useExitDeliverable);
    this.prefersScheduler = Boolean(options?.processorOptions?.useScheduler);
    this.usesCompiledHotSwap = false;
    this.usesCompiledTopologyEdit = false;
    this.usesCompiledStereoHotSwap = false;
    this.usesCompiledStereoTopologyEdit = false;
    this.usesExitDeliverable = false;
    this.usesCompiledStereoGraph = false;
    this.usesCompiledGraph = false;
    this.usesScheduler = false;
    this.reportedRuntimeError = false;
    this.telemetryCountdown = 0;
    this.telemetryWarmupBlocks = 16;
    this.telemetrySequence = 0;
    this.firstBlockTelemetryReported = false;
    this.forceTelemetryBlocks = 0;
    this._leftPreview = new Float64Array(8);
    this._rightPreview = new Float64Array(8);

    this.port.onmessage = (event) => {
      const data = event.data;
      if (!data || typeof data !== "object") {
        return;
      }
      if (data.type === "set-freq") {
        this.freq = Number(data.value);
      } else if (data.type === "set-gain") {
        this.gain = Number(data.value);
      } else if (data.type === "set-pan") {
        this.pan = Number(data.value);
      } else if (data.type === "set-delay-samples") {
        this.delaySamples = Number(data.value);
      } else if (data.type === "set-cutoff") {
        this.cutoff = Number(data.value);
      } else if (data.type === "set-pattern-text") {
        if (this.usesScheduler && this.wasm &&
            typeof this.wasm.clear_pattern_input === "function" &&
            typeof this.wasm.push_pattern_char === "function" &&
            typeof this.wasm.eval_pattern_input === "function") {
          this.wasm.clear_pattern_input();
          const text = data.text || "";
          for (let i = 0; i < text.length; i++) {
            this.wasm.push_pattern_char(text.charCodeAt(i));
          }
          const result = this.wasm.eval_pattern_input();
          if (result === 0) {
            this.port.postMessage({ type: "pattern-updated" });
          } else {
            this.port.postMessage({ type: "pattern-error", message: "parse error" });
          }
        }
      } else if (data.type === "set-scheduler-bpm") {
        if (this.usesScheduler && this.wasm && typeof this.wasm.set_scheduler_bpm === "function") {
          this.wasm.set_scheduler_bpm(Number(data.bpm));
        }
      } else if (data.type === "set-scheduler-gain") {
        if (this.usesScheduler && this.wasm && typeof this.wasm.set_scheduler_gain === "function") {
          this.wasm.set_scheduler_gain(Number(data.gain));
        }
      } else if (data.type === "queue-hot-swap") {
        if (this.usesCompiledHotSwap && this.wasm && typeof this.wasm.queue_compiled_hot_swap === "function") {
          const queued = this.wasm.queue_compiled_hot_swap();
          if (queued) {
            this.forceTelemetryBlocks = 2;
            this.port.postMessage({
              type: "hot-swap-queued",
              telemetrySequence: this.telemetrySequence,
            });
          } else {
            this.port.postMessage({ type: "error", message: "CompiledDspHotSwap queue_swap failed" });
          }
        }
      } else if (data.type === "queue-stereo-hot-swap") {
        if (this.usesCompiledStereoHotSwap && this.wasm && typeof this.wasm.queue_compiled_stereo_hot_swap === "function") {
          const queued = this.wasm.queue_compiled_stereo_hot_swap();
          if (queued) {
            this.forceTelemetryBlocks = 2;
            this.port.postMessage({
              type: "stereo-hot-swap-queued",
              telemetrySequence: this.telemetrySequence,
            });
          } else {
            this.port.postMessage({ type: "error", message: "CompiledStereoDspHotSwap queue_swap failed" });
          }
        }
      } else if (data.type === "queue-stereo-topology-edit") {
        if (this.usesCompiledStereoTopologyEdit && this.wasm && typeof this.wasm.queue_compiled_stereo_topology_edit === "function") {
          const queued = this.wasm.queue_compiled_stereo_topology_edit();
          if (queued) {
            this.forceTelemetryBlocks = 2;
            this.port.postMessage({
              type: "stereo-topology-edit-queued",
              telemetrySequence: this.telemetrySequence,
            });
          } else {
            this.port.postMessage({ type: "error", message: "CompiledStereoDspTopologyController queue_topology_edit failed" });
          }
        }
      } else if (data.type === "queue-topology-edit") {
        if (this.usesCompiledTopologyEdit && this.wasm && typeof this.wasm.queue_compiled_topology_edit === "function") {
          const queued = this.wasm.queue_compiled_topology_edit();
          if (queued) {
            this.forceTelemetryBlocks = 2;
            this.port.postMessage({
              type: "topology-edit-queued",
              telemetrySequence: this.telemetrySequence,
            });
          } else {
            this.port.postMessage({ type: "error", message: "CompiledDspTopologyController queue_topology_edit failed" });
          }
        }
      } else if (data.type === "queue-topology-delete-edit") {
        if (this.usesCompiledTopologyEdit && this.wasm && typeof this.wasm.queue_compiled_topology_delete_edit === "function") {
          const queued = this.wasm.queue_compiled_topology_delete_edit();
          if (queued) {
            this.forceTelemetryBlocks = 2;
            this.port.postMessage({
              type: "topology-edit-queued",
              telemetrySequence: this.telemetrySequence,
            });
          } else {
            this.port.postMessage({ type: "error", message: "CompiledDspTopologyController queue_topology_delete_edit failed" });
          }
        }
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

      const supportsCompiledStereoGraph =
        typeof this.wasm.init_compiled_stereo_graph === "function" &&
        typeof this.wasm.process_compiled_stereo_block === "function" &&
        typeof this.wasm.compiled_stereo_left_sample === "function" &&
        typeof this.wasm.compiled_stereo_right_sample === "function";

      const supportsCompiledStereoHotSwap =
        typeof this.wasm.init_compiled_stereo_hot_swap_graph === "function" &&
        typeof this.wasm.queue_compiled_stereo_hot_swap === "function" &&
        typeof this.wasm.process_compiled_stereo_hot_swap_block === "function" &&
        typeof this.wasm.compiled_stereo_hot_swap_left_sample === "function" &&
        typeof this.wasm.compiled_stereo_hot_swap_right_sample === "function";

      const supportsCompiledStereoTopologyEdit =
        typeof this.wasm.init_compiled_stereo_topology_edit_graph === "function" &&
        typeof this.wasm.queue_compiled_stereo_topology_edit === "function" &&
        typeof this.wasm.process_compiled_stereo_topology_edit_block === "function" &&
        typeof this.wasm.compiled_stereo_topology_edit_left_sample === "function" &&
        typeof this.wasm.compiled_stereo_topology_edit_right_sample === "function";

      const supportsCompiledHotSwap =
        typeof this.wasm.init_compiled_hot_swap_graph === "function" &&
        typeof this.wasm.queue_compiled_hot_swap === "function" &&
        typeof this.wasm.process_compiled_hot_swap_block === "function" &&
        typeof this.wasm.compiled_hot_swap_output_sample === "function";

      const supportsCompiledTopologyEdit =
        typeof this.wasm.init_compiled_topology_edit_graph === "function" &&
        typeof this.wasm.queue_compiled_topology_edit === "function" &&
        typeof this.wasm.queue_compiled_topology_delete_edit === "function" &&
        typeof this.wasm.process_compiled_topology_edit_block === "function" &&
        typeof this.wasm.compiled_topology_edit_output_sample === "function";

      const supportsCompiledGraph =
        typeof this.wasm.init_compiled_graph === "function" &&
        typeof this.wasm.process_compiled_block === "function" &&
        typeof this.wasm.compiled_output_sample === "function";

      this.usesCompiledHotSwap = false;
      this.usesCompiledTopologyEdit = false;
      this.usesCompiledStereoHotSwap = false;
      this.usesCompiledStereoTopologyEdit = false;
      this.usesCompiledStereoGraph = false;
      this.usesCompiledGraph = false;

      if (this.prefersCompiledHotSwap && supportsCompiledHotSwap) {
        const initialized = this.wasm.init_compiled_hot_swap_graph(sampleRate, 128);
        if (initialized) {
          this.usesCompiledHotSwap = true;
        }
      }

      if (
        !this.usesCompiledHotSwap &&
        this.prefersCompiledTopologyEdit &&
        supportsCompiledTopologyEdit
      ) {
        const initialized = this.wasm.init_compiled_topology_edit_graph(sampleRate, 128);
        if (initialized) {
          this.usesCompiledTopologyEdit = true;
        }
      }

      if (
        !this.usesCompiledHotSwap &&
        !this.usesCompiledTopologyEdit &&
        this.prefersCompiledStereoTopologyEdit &&
        supportsCompiledStereoTopologyEdit
      ) {
        const initialized = this.wasm.init_compiled_stereo_topology_edit_graph(sampleRate, 128);
        if (initialized) {
          this.usesCompiledStereoTopologyEdit = true;
        }
      }

      if (
        !this.usesCompiledHotSwap &&
        !this.usesCompiledTopologyEdit &&
        !this.usesCompiledStereoTopologyEdit &&
        this.prefersCompiledStereoHotSwap &&
        supportsCompiledStereoHotSwap
      ) {
        const initialized = this.wasm.init_compiled_stereo_hot_swap_graph(sampleRate, 128);
        if (initialized) {
          this.usesCompiledStereoHotSwap = true;
        }
      }

      const supportsExitDeliverable =
        typeof this.wasm.init_exit_deliverable_graph === "function" &&
        typeof this.wasm.process_exit_deliverable_block === "function" &&
        typeof this.wasm.exit_deliverable_output_sample === "function";

      const supportsScheduler =
        typeof this.wasm.init_scheduler_graph === "function" &&
        typeof this.wasm.process_scheduler_block === "function" &&
        typeof this.wasm.scheduler_left_sample === "function" &&
        typeof this.wasm.scheduler_right_sample === "function";

      if (
        !this.usesCompiledHotSwap &&
        !this.usesCompiledTopologyEdit &&
        !this.usesCompiledStereoTopologyEdit &&
        !this.usesCompiledStereoHotSwap &&
        this.prefersExitDeliverable &&
        supportsExitDeliverable
      ) {
        const initialized = this.wasm.init_exit_deliverable_graph(sampleRate, 128);
        if (initialized) {
          this.usesExitDeliverable = true;
        }
      }

      if (
        !this.usesCompiledHotSwap &&
        !this.usesCompiledTopologyEdit &&
        !this.usesCompiledStereoTopologyEdit &&
        !this.usesCompiledStereoHotSwap &&
        !this.usesExitDeliverable &&
        this.prefersScheduler &&
        supportsScheduler
      ) {
        const initialized = this.wasm.init_scheduler_graph(sampleRate, 128);
        if (initialized) {
          this.usesScheduler = true;
        }
      }

      if (!this.usesCompiledHotSwap && !this.usesCompiledTopologyEdit && !this.usesCompiledStereoTopologyEdit && !this.usesCompiledStereoHotSwap && !this.usesExitDeliverable && !this.usesScheduler && supportsCompiledStereoGraph) {
        const initialized = this.wasm.init_compiled_stereo_graph(sampleRate, 128);
        if (initialized) {
          this.usesCompiledStereoGraph = true;
        }
      }

      if (
        !this.usesCompiledHotSwap &&
        !this.usesCompiledTopologyEdit &&
        !this.usesCompiledStereoTopologyEdit &&
        !this.usesCompiledStereoHotSwap &&
        !this.usesExitDeliverable &&
        !this.usesScheduler &&
        !this.usesCompiledStereoGraph &&
        supportsCompiledGraph
      ) {
        const initialized = this.wasm.init_compiled_graph(sampleRate, 128);
        if (initialized) {
          this.usesCompiledGraph = true;
        }
      }

      if (
        !this.usesCompiledHotSwap &&
        !this.usesCompiledTopologyEdit &&
        !this.usesCompiledStereoTopologyEdit &&
        !this.usesCompiledStereoHotSwap &&
        !this.usesExitDeliverable &&
        !this.usesScheduler &&
        !this.usesCompiledStereoGraph &&
        !this.usesCompiledGraph &&
        (
          supportsCompiledHotSwap ||
          supportsCompiledTopologyEdit ||
          supportsCompiledStereoTopologyEdit ||
          supportsCompiledStereoHotSwap ||
          supportsExitDeliverable ||
          supportsScheduler ||
          supportsCompiledStereoGraph ||
          supportsCompiledGraph
        )
      ) {
        throw new Error("Compiled browser graph failed to initialize");
      }

      if (
        !this.usesCompiledHotSwap &&
        !this.usesCompiledTopologyEdit &&
        !this.usesCompiledStereoTopologyEdit &&
        !this.usesCompiledStereoHotSwap &&
        !this.usesExitDeliverable &&
        !this.usesScheduler &&
        !this.usesCompiledStereoGraph &&
        !this.usesCompiledGraph &&
        typeof this.wasm.tick !== "function" &&
        typeof this.wasm.tick_source !== "function" &&
        typeof this.wasm.demo_tick !== "function" &&
        typeof this.wasm.demo_tick_source !== "function"
      ) {
        throw new Error("No supported browser DSP exports found");
      }

      this.ready = true;
      this.port.postMessage({
        type: "ready",
        exports: Object.keys(this.wasm),
        mode: this.usesCompiledHotSwap
          ? "compiled-hot-swap-dsp"
          : this.usesCompiledTopologyEdit
            ? "compiled-topology-edit-dsp"
          : this.usesCompiledStereoTopologyEdit
            ? "compiled-stereo-topology-edit-dsp"
          : this.usesCompiledStereoHotSwap
            ? "compiled-stereo-hot-swap-dsp"
          : this.usesExitDeliverable
            ? "exit-deliverable-dsp"
          : this.usesScheduler
            ? "scheduler-dsp"
          : this.usesCompiledStereoGraph
          ? "compiled-stereo-dsp"
          : this.usesCompiledGraph
            ? "compiled-dsp"
            : "legacy-tick",
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
      this.reportBlockTelemetry(left, right);
      return true;
    }

    if (this.usesCompiledHotSwap) {
      const processed = this.wasm.process_compiled_hot_swap_block(
        sampleRate,
        left.length,
      );
      if (!processed) {
        this.fillSilence(left, right);
        if (!this.reportedRuntimeError) {
          this.reportedRuntimeError = true;
          this.port.postMessage({
            type: "error",
            message: "CompiledDspHotSwap browser block processing failed",
          });
        }
        return true;
      }

      for (let index = 0; index < left.length; index += 1) {
        const sample = this.wasm.compiled_hot_swap_output_sample(index);
        left[index] = sample;
        if (right) {
          right[index] = sample;
        }
      }

      this.reportBlockTelemetry(left, right);
      return true;
    }

    if (this.usesCompiledTopologyEdit) {
      if (typeof this.wasm.set_compiled_topology_edit_gain === "function") {
        const updated = this.wasm.set_compiled_topology_edit_gain(this.gain);
        if (!updated) {
          this.fillSilence(left, right);
          if (!this.reportedRuntimeError) {
            this.reportedRuntimeError = true;
            this.port.postMessage({
              type: "error",
              message: "CompiledDspTopologyController browser control update failed",
            });
          }
          return true;
        }
      }
      const processed = this.wasm.process_compiled_topology_edit_block(
        sampleRate,
        left.length,
      );
      if (!processed) {
        this.fillSilence(left, right);
        if (!this.reportedRuntimeError) {
          this.reportedRuntimeError = true;
          this.port.postMessage({
            type: "error",
            message: "CompiledDspTopologyController browser block processing failed",
          });
        }
        return true;
      }

      for (let index = 0; index < left.length; index += 1) {
        const sample = this.wasm.compiled_topology_edit_output_sample(index);
        left[index] = sample;
        if (right) {
          right[index] = sample;
        }
      }

      this.reportBlockTelemetry(left, right);
      return true;
    }

    if (this.usesCompiledStereoTopologyEdit) {
      if (typeof this.wasm.set_compiled_stereo_topology_edit_level === "function") {
        const updated = this.wasm.set_compiled_stereo_topology_edit_level(this.gain);
        if (!updated) {
          this.fillSilence(left, right);
          if (!this.reportedRuntimeError) {
            this.reportedRuntimeError = true;
            this.port.postMessage({
              type: "error",
              message: "CompiledStereoDspTopologyController browser control update failed",
            });
          }
          return true;
        }
      }
      const processed = this.wasm.process_compiled_stereo_topology_edit_block(
        sampleRate,
        left.length,
      );
      if (!processed) {
        this.fillSilence(left, right);
        if (!this.reportedRuntimeError) {
          this.reportedRuntimeError = true;
          this.port.postMessage({
            type: "error",
            message: "CompiledStereoDspTopologyController browser block processing failed",
          });
        }
        return true;
      }

      for (let index = 0; index < left.length; index += 1) {
        left[index] = this.wasm.compiled_stereo_topology_edit_left_sample(index);
        if (right) {
          right[index] = this.wasm.compiled_stereo_topology_edit_right_sample(index);
        }
      }

      this.reportBlockTelemetry(left, right);
      return true;
    }

    if (this.usesExitDeliverable) {
      if (typeof this.wasm.set_exit_deliverable_lfo_rate === "function") {
        this.wasm.set_exit_deliverable_lfo_rate(this.freq);
      }
      if (typeof this.wasm.set_exit_deliverable_cutoff === "function") {
        this.wasm.set_exit_deliverable_cutoff(this.cutoff);
      }
      if (typeof this.wasm.set_exit_deliverable_gain === "function") {
        this.wasm.set_exit_deliverable_gain(this.gain);
      }
      const processed = this.wasm.process_exit_deliverable_block(
        sampleRate,
        left.length,
      );
      if (!processed) {
        this.fillSilence(left, right);
        if (!this.reportedRuntimeError) {
          this.reportedRuntimeError = true;
          this.port.postMessage({
            type: "error",
            message: "Exit deliverable browser block processing failed",
          });
        }
        return true;
      }

      for (let index = 0; index < left.length; index += 1) {
        const sample = this.wasm.exit_deliverable_output_sample(index);
        left[index] = sample;
        if (right) {
          right[index] = sample;
        }
      }

      this.reportBlockTelemetry(left, right);
      return true;
    }

    if (this.usesCompiledStereoHotSwap) {
      const processed = this.wasm.process_compiled_stereo_hot_swap_block(
        sampleRate,
        left.length,
      );
      if (!processed) {
        this.fillSilence(left, right);
        if (!this.reportedRuntimeError) {
          this.reportedRuntimeError = true;
          this.port.postMessage({
            type: "error",
            message: "CompiledStereoDspHotSwap browser block processing failed",
          });
        }
        return true;
      }

      for (let index = 0; index < left.length; index += 1) {
        left[index] = this.wasm.compiled_stereo_hot_swap_left_sample(index);
        if (right) {
          right[index] = this.wasm.compiled_stereo_hot_swap_right_sample(index);
        }
      }

      this.reportBlockTelemetry(left, right);
      return true;
    }

    if (this.usesScheduler) {
      const processed = this.wasm.process_scheduler_block();
      if (!processed) {
        this.fillSilence(left, right);
        if (!this.reportedRuntimeError) {
          this.reportedRuntimeError = true;
          this.port.postMessage({
            type: "error",
            message: "Scheduler block processing failed",
          });
        }
        return true;
      }

      for (let index = 0; index < left.length; index += 1) {
        left[index] = this.wasm.scheduler_left_sample(index);
        if (right) {
          right[index] = this.wasm.scheduler_right_sample(index);
        }
      }

      this.reportBlockTelemetry(left, right);
      return true;
    }

    if (this.usesCompiledStereoGraph) {
      const processed = this.wasm.process_compiled_stereo_block(
        this.freq,
        this.gain,
        this.pan,
        this.delaySamples,
        this.cutoff,
        sampleRate,
        left.length,
      );
      if (!processed) {
        this.fillSilence(left, right);
        if (!this.reportedRuntimeError) {
          this.reportedRuntimeError = true;
          this.port.postMessage({
            type: "error",
            message: "CompiledStereoDsp browser block processing failed",
          });
        }
        return true;
      }

      for (let index = 0; index < left.length; index += 1) {
        left[index] = this.wasm.compiled_stereo_left_sample(index);
        if (right) {
          right[index] = this.wasm.compiled_stereo_right_sample(index);
        }
      }

      this.reportBlockTelemetry(left, right);
      return true;
    }

    if (this.usesCompiledGraph) {
      const processed = this.wasm.process_compiled_block(
        this.freq,
        this.gain,
        sampleRate,
        left.length,
      );
      if (!processed) {
        this.fillSilence(left, right);
        if (!this.reportedRuntimeError) {
          this.reportedRuntimeError = true;
          this.port.postMessage({
            type: "error",
            message: "CompiledDsp browser block processing failed",
          });
        }
        return true;
      }

      for (let index = 0; index < left.length; index += 1) {
        const sample = this.wasm.compiled_output_sample(index);
        left[index] = sample;
        if (right) {
          right[index] = sample;
        }
      }

      this.reportBlockTelemetry(left, right);
      return true;
    }

    for (let index = 0; index < left.length; index += 1) {
      const raw = typeof this.wasm.tick_source === "function"
        ? this.wasm.tick_source(0, this.freq, sampleRate)
        : typeof this.wasm.demo_tick_source === "function"
          ? this.wasm.demo_tick_source(0, this.freq, sampleRate)
          : typeof this.wasm.tick === "function"
            ? this.wasm.tick(this.freq, sampleRate)
            : this.wasm.demo_tick(this.freq, sampleRate);
      const sample = raw * this.gain;
      left[index] = sample;
      if (right) {
        right[index] = sample;
      }
    }

    this.reportBlockTelemetry(left, right);
    return true;
  }

  fillSilence(left, right) {
    left.fill(0);
    if (right) {
      right.fill(0);
    }
  }

  reportBlockTelemetry(left, right) {
    let leftPeak = 0;
    let rightPeak = 0;
    for (let index = 0; index < left.length; index += 1) {
      leftPeak = Math.max(leftPeak, Math.abs(left[index]));
      if (right) {
        rightPeak = Math.max(rightPeak, Math.abs(right[index]));
      }
    }
    if (!right) {
      rightPeak = leftPeak;
    }

    const previewCount = Math.min(8, left.length);
    for (let index = 0; index < previewCount; index += 1) {
      this._leftPreview[index] = left[index];
      this._rightPreview[index] = right ? right[index] : left[index];
    }

    if (!this.firstBlockTelemetryReported) {
      this.firstBlockTelemetryReported = true;
      this.telemetrySequence += 1;
      this.port.postMessage({
        type: "telemetry",
        sequence: this.telemetrySequence,
        freq: this.freq,
        gain: this.gain,
        pan: this.pan,
        delaySamples: this.delaySamples,
        cutoff: this.cutoff,
        overallPeak: Math.max(leftPeak, rightPeak),
        leftPeak,
        rightPeak,
        leftPreview: Array.from(this._leftPreview),
        rightPreview: Array.from(this._rightPreview),
      });
      return;
    }

    if (this.forceTelemetryBlocks > 0) {
      this.forceTelemetryBlocks -= 1;
    } else if (this.telemetryWarmupBlocks > 0) {
      this.telemetryWarmupBlocks -= 1;
      return;
    } else if (this.telemetryCountdown > 0) {
      this.telemetryCountdown -= 1;
      return;
    } else {
      this.telemetryCountdown = 7;
    }

    this.telemetrySequence += 1;

    this.port.postMessage({
      type: "telemetry",
      sequence: this.telemetrySequence,
      freq: this.freq,
      gain: this.gain,
      pan: this.pan,
      delaySamples: this.delaySamples,
      cutoff: this.cutoff,
      overallPeak: Math.max(leftPeak, rightPeak),
      leftPeak,
      rightPeak,
      leftPreview: Array.from(this._leftPreview),
      rightPreview: Array.from(this._rightPreview),
    });
  }
}

registerProcessor("moonbit-dsp", MoonBitDspProcessor);
