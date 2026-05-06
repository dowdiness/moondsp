// AudioContext + AudioWorklet bootstrap for moondsp's live REPL.
//
// Wraps the existing web/processor.js worklet protocol:
//   send  { type: "set-pattern-text", text }
//   reply { type: "pattern-updated" } | { type: "pattern-error", message }
//
// Does NOT own pattern-string state — main.ts decides when to send and
// how to handle replies. This module is the transport boundary only.

export type AudioStatus =
  | { kind: "idle" }
  | { kind: "starting" }
  | { kind: "running" }
  | { kind: "error"; message: string };

export type WorkletReply =
  | { type: "pattern-updated" }
  | { type: "pattern-error"; message: string }
  | { type: "error"; message: string }
  | { type: string; [key: string]: unknown };

export class AudioEngine {
  private ctx: AudioContext | null = null;
  private node: AudioWorkletNode | null = null;
  private replyHandlers: ((r: WorkletReply) => void)[] = [];
  private statusHandlers: ((s: AudioStatus) => void)[] = [];
  private status: AudioStatus = { kind: "idle" };

  constructor(
    private readonly processorUrl = "/processor.js",
    private readonly wasmUrl = "/moonbit_dsp.wasm",
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
      const ctx = new AudioContext({ sampleRate: 48000 });
      await ctx.audioWorklet.addModule(this.processorUrl);

      const wasmResponse = await fetch(this.wasmUrl);
      if (!wasmResponse.ok) {
        throw new Error(`fetch ${this.wasmUrl}: ${wasmResponse.status}`);
      }
      const wasmBytes = await wasmResponse.arrayBuffer();
      const wasmModule = await WebAssembly.compile(wasmBytes);

      const node = new AudioWorkletNode(ctx, "moonbit-dsp-processor", {
        numberOfInputs: 0,
        numberOfOutputs: 1,
        outputChannelCount: [2],
        processorOptions: {
          wasmModule,
          useScheduler: true,
        },
      });

      node.port.onmessage = (event) => {
        const data = event.data as WorkletReply;
        if (!data || typeof data !== "object") return;
        for (const h of this.replyHandlers) h(data);
        if (data.type === "error") {
          this.setStatus({ kind: "error", message: String(data.message ?? "worklet error") });
        }
      };

      node.connect(ctx.destination);

      this.ctx = ctx;
      this.node = node;
      this.setStatus({ kind: "running" });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      this.setStatus({ kind: "error", message });
      throw err;
    }
  }

  setPatternText(text: string): void {
    if (!this.node) return;
    this.node.port.postMessage({ type: "set-pattern-text", text });
  }

  setBpm(bpm: number): void {
    if (!this.node) return;
    this.node.port.postMessage({ type: "set-scheduler-bpm", bpm });
  }

  setGain(gain: number): void {
    if (!this.node) return;
    this.node.port.postMessage({ type: "set-scheduler-gain", gain });
  }

  async stop(): Promise<void> {
    if (this.node) {
      this.node.disconnect();
      this.node = null;
    }
    if (this.ctx) {
      await this.ctx.close();
      this.ctx = null;
    }
    this.setStatus({ kind: "idle" });
  }
}
