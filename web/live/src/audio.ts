// AudioContext + AudioWorklet bootstrap for moondsp's live REPL.
//
// Wraps the browser worklet protocol:
//   send  { type: "set-pattern-text", text } | { type: "set-song-text", text }
//   reply { type: "pattern-updated" } | { type: "pattern-error", message }
//       | { type: "song-updated" }    | { type: "song-error", message }
//
// Does NOT own playback-string state — main.ts decides which explicit mode
// to send and how to handle replies. This module is the transport boundary only.

export type AudioStatus =
  | { kind: "idle" }
  | { kind: "starting" }
  | { kind: "running" }
  | { kind: "error"; message: string };

export type WorkletReply =
  | { type: "pattern-updated"; revision?: number }
  | { type: "pattern-error"; message: string; revision?: number }
  | { type: "song-updated"; revision?: number }
  | { type: "song-error"; message: string; revision?: number }
  | { type: "error"; message: string; code?: number }
  | { type: string; [key: string]: unknown };

export type AudioEngineMode = "scheduler" | "compiled";

export type AudioEngineOptions = {
  enableTelemetry?: boolean;
  enableSchedulerTiming?: boolean;
  schedulerTimingBatchSize?: number;
  sampleRate?: number;
  latencyHint?: AudioContextOptions["latencyHint"];
  mode?: AudioEngineMode;
};

const LEGACY_PROCESSOR_NAME = "moonbit-dsp";
const SCHEDULER_PROCESSOR_URL = "/scheduler-processor.js";
const SCHEDULER_PROCESSOR_NAME = "moondsp-scheduler";

export class AudioEngine {
  private ctx: AudioContext | null = null;
  private node: AudioWorkletNode | null = null;
  private masterGain: GainNode | null = null;
  private currentMode: AudioEngineMode | null = null;
  private replyHandlers: ((r: WorkletReply) => void)[] = [];
  private statusHandlers: ((s: AudioStatus) => void)[] = [];
  private status: AudioStatus = { kind: "idle" };

  /** Exposed for diagnostics. */
  readonly _wasmModule?: WebAssembly.Module;

  constructor(
    private readonly processorUrl = "/processor.js",
    private readonly wasmUrl = "/moonbit_dsp.wasm",
    private readonly options: AudioEngineOptions = {},
  ) {}

  getStatus(): AudioStatus {
    return this.status;
  }

  onReply(handler: (r: WorkletReply) => void): () => void {
    this.replyHandlers.push(handler);
    return () => {
      this.replyHandlers = this.replyHandlers.filter((h) => h !== handler);
    };
  }

  onStatus(handler: (s: AudioStatus) => void): () => void {
    this.statusHandlers.push(handler);
    handler(this.status);
    return () => {
      this.statusHandlers = this.statusHandlers.filter((h) => h !== handler);
    };
  }

  private setStatus(s: AudioStatus): void {
    this.status = s;
    for (const h of this.statusHandlers) h(s);
  }

  /** Must be called from a user gesture handler (click, keypress). */
  async start(): Promise<void> {
    if (this.status.kind === "running" || this.status.kind === "starting") return;
    this.setStatus({ kind: "starting" });

    try {
      const mode = this.options.mode ?? "scheduler";
      if (this.canResumeExistingGraph(mode)) {
        this.setMasterGainImmediate(0);
        await this.ctx!.resume();
        console.info(`[moondsp/live] audioMode=${mode}; resumed existing AudioContext`);
        this.setStatus({ kind: "running" });
        return;
      }

      this.currentMode = mode;
      await this.openContext();

      switch (mode) {
        case "scheduler":
          await this.startSchedulerWorklet();
          break;
        case "compiled":
          await this.startLegacyCompiledWorklet();
          break;
      }

      this.setStatus({ kind: "running" });
    } catch (err) {
      // Tear down any partial graph (ctx/node may have been created above)
      // before transitioning to error so a Retry click rebuilds cleanly.
      this.teardownGraph();
      const message = err instanceof Error ? err.message : String(err);
      this.setStatus({ kind: "error", message });
      throw err;
    }
  }

  private canResumeExistingGraph(mode: AudioEngineMode): boolean {
    if (!this.ctx || this.ctx.state === "closed" || this.currentMode !== mode) {
      return false;
    }
    return this.node !== null;
  }

  private async openContext(): Promise<AudioContext> {
    // Assign to instance field before async work so teardownGraph() can close
    // partially-created contexts if resume/addModule/wasm compile fails.
    const contextOptions: AudioContextOptions = {};
    if (typeof this.options.sampleRate === "number") {
      contextOptions.sampleRate = this.options.sampleRate;
    }
    if (this.options.latencyHint !== undefined) {
      contextOptions.latencyHint = this.options.latencyHint;
    }

    const ctx = new AudioContext(contextOptions);
    this.ctx = ctx;
    this.masterGain = new GainNode(ctx, { gain: 0 });
    this.masterGain.connect(ctx.destination);
    console.info("[moondsp/live] AudioContext", {
      requestedSampleRate: this.options.sampleRate ?? "device-default",
      actualSampleRate: ctx.sampleRate,
      latencyHint: this.options.latencyHint ?? "browser-default",
      baseLatency: ctx.baseLatency,
      outputLatency: ctx.outputLatency,
    });
    await ctx.resume();
    return ctx;
  }

  private requireContext(): AudioContext {
    if (!this.ctx) {
      throw new Error("AudioContext not initialized");
    }
    return this.ctx;
  }

  private async startSchedulerWorklet(): Promise<void> {
    const wasmModule = await this.compileWasmModule();
    const node = await this.createReadyWorkletNode({
      moduleUrl: SCHEDULER_PROCESSOR_URL,
      processorName: SCHEDULER_PROCESSOR_NAME,
      readyLabel: "scheduler worklet",
      options: {
        numberOfInputs: 0,
        numberOfOutputs: 1,
        outputChannelCount: [2],
        processorOptions: { wasmModule },
      },
    });
    this.node = node;
    console.info("[moondsp/live] audioMode=scheduler; dedicated scheduler processor");
  }

  private async startLegacyCompiledWorklet(): Promise<void> {
    const wasmModule = await this.compileWasmModule();
    const node = await this.createReadyWorkletNode({
      moduleUrl: this.processorUrl,
      processorName: LEGACY_PROCESSOR_NAME,
      readyLabel: "worklet",
      options: {
        numberOfInputs: 0,
        numberOfOutputs: 1,
        outputChannelCount: [2],
        processorOptions: {
          wasmModule,
          useScheduler: false,
          useProbeSine: false,
          enableTelemetry: this.options.enableTelemetry === true,
          enableSchedulerTiming: this.options.enableSchedulerTiming === true,
          schedulerTimingBatchSize: this.options.schedulerTimingBatchSize ?? 128,
        },
      },
    });
    this.node = node;
  }

  private async compileWasmModule(): Promise<WebAssembly.Module> {
    const wasmResponse = await fetch(this.wasmUrl);
    if (!wasmResponse.ok) {
      throw new Error(`fetch ${this.wasmUrl}: ${wasmResponse.status}`);
    }
    const wasmBytes = await wasmResponse.arrayBuffer();
    return WebAssembly.compile(wasmBytes);
  }

  private async createReadyWorkletNode(args: {
    moduleUrl: string;
    processorName: string;
    readyLabel: string;
    options: AudioWorkletNodeOptions;
  }): Promise<AudioWorkletNode> {
    const ctx = this.requireContext();
    await ctx.audioWorklet.addModule(args.moduleUrl);
    const node = new AudioWorkletNode(ctx, args.processorName, args.options);
    const ready = this.waitForWorkletReady(node, args.readyLabel);
    node.connect(this.outputDestination());
    await ready;
    return node;
  }

  private outputDestination(): AudioNode {
    if (!this.masterGain) {
      throw new Error("Audio output gain not initialized");
    }
    return this.masterGain;
  }

  private waitForWorkletReady(node: AudioWorkletNode, label: string): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      const timeoutId = window.setTimeout(() => {
        reject(new Error(`${label} ready timeout (5s)`));
      }, 5000);

      node.port.onmessage = (event) => {
        const data = event.data as WorkletReply;
        if (!data || typeof data !== "object") return;
        if (data.type === "ready") {
          window.clearTimeout(timeoutId);
          node.port.onmessage = (e) => this.dispatchReply(e.data as WorkletReply);
          resolve();
          return;
        }
        if (data.type === "error") {
          window.clearTimeout(timeoutId);
          reject(new Error(String(data.message ?? `${label} error`)));
          return;
        }
        this.dispatchReply(data);
      };
    });
  }

  private dispatchReply(data: WorkletReply): void {
    if (!data || typeof data !== "object") return;
    for (const h of this.replyHandlers) h(data);
    if (data.type === "error") {
      // Tear down the live audio graph so a Retry click rebuilds a fresh
      // context. Without this we'd leak the old AudioContext and stack a
      // second one on top of it.
      this.teardownGraph();
      this.setStatus({ kind: "error", message: String(data.message ?? "worklet error") });
    }
    if (data.type === "debug" || data.type === "scheduler-timing") {
      console.debug("[moondsp/live]", data);
    }
  }

  /**
   * Test-only: inject a synthetic worklet reply through the dispatch
   * pipeline. Used by smoke tests to exercise the runtime-error path
   * without crashing the actual wasm graph. Do not call from app code.
   */
  _testInjectReply(reply: WorkletReply): void {
    this.dispatchReply(reply);
  }

  fadeIn(durationMs = 80): void {
    this.rampMasterGain(1, durationMs);
  }

  private async fadeOut(durationMs = 60): Promise<void> {
    this.rampMasterGain(0, durationMs);
    await this.sleep(durationMs);
  }

  private rampMasterGain(value: number, durationMs: number): void {
    if (!this.ctx || !this.masterGain) return;
    const now = this.ctx.currentTime;
    const gain = this.masterGain.gain;
    gain.cancelScheduledValues(now);
    gain.setValueAtTime(gain.value, now);
    gain.linearRampToValueAtTime(value, now + durationMs / 1000);
  }

  private setMasterGainImmediate(value: number): void {
    if (!this.ctx || !this.masterGain) return;
    const now = this.ctx.currentTime;
    const gain = this.masterGain.gain;
    gain.cancelScheduledValues(now);
    gain.setValueAtTime(value, now);
  }

  private sleep(ms: number): Promise<void> {
    return new Promise((resolve) => window.setTimeout(resolve, ms));
  }

  private disconnectOutputNodes(): void {
    if (this.node) {
      try {
        this.node.disconnect();
      } catch {
        /* already disconnected */
      }
      this.node = null;
    }
    if (this.masterGain) {
      try {
        this.masterGain.disconnect();
      } catch {
        /* already disconnected */
      }
      this.masterGain = null;
    }
  }

  private teardownGraph(): void {
    this.disconnectOutputNodes();
    if (this.ctx) {
      // Fire-and-forget; close() returns a Promise but we don't need to await
      // it for the host to begin a fresh start().
      void this.ctx.close().catch(() => undefined);
      this.ctx = null;
    }
    this.currentMode = null;
  }

  setPatternText(text: string, revision?: number): void {
    if (!this.node || !this.usesSchedulerProtocol()) return;
    this.node.port.postMessage({ type: "set-pattern-text", text, revision });
  }

  setSongText(text: string, revision?: number): void {
    if (!this.node || !this.usesSchedulerProtocol()) return;
    this.node.port.postMessage({ type: "set-song-text", text, revision });
  }

  setBpm(bpm: number): void {
    if (!this.node || !this.usesSchedulerProtocol()) return;
    this.node.port.postMessage({ type: "set-scheduler-bpm", bpm });
  }

  private usesSchedulerProtocol(): boolean {
    return this.currentMode === "scheduler";
  }

  setGain(gain: number): void {
    if (!this.node) return;
    if (this.usesSchedulerProtocol()) {
      this.node.port.postMessage({ type: "set-scheduler-gain", gain });
    } else {
      this.node.port.postMessage({ type: "set-gain", value: gain });
    }
  }

  async stop(): Promise<void> {
    if (this.ctx && this.ctx.state !== "closed") {
      try {
        await this.fadeOut();
        await this.ctx.suspend();
      } catch {
        // If suspend is unavailable or fails, fall back to full teardown.
        this.teardownGraph();
      }
    }
    this.setStatus({ kind: "idle" });
  }
}
