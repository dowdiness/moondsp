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
  | { type: "pattern-updated"; revision?: number }
  | { type: "pattern-error"; message: string; revision?: number }
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
      // Assign to instance fields immediately so teardownGraph() can see
      // them if any later step throws (404 wasm, addModule failure, ready
      // timeout). Without this, partially-constructed contexts leak.
      this.ctx = new AudioContext({ sampleRate: 48000 });
      await this.ctx.resume();
      await this.ctx.audioWorklet.addModule(this.processorUrl);

      const wasmResponse = await fetch(this.wasmUrl);
      if (!wasmResponse.ok) {
        throw new Error(`fetch ${this.wasmUrl}: ${wasmResponse.status}`);
      }
      const wasmBytes = await wasmResponse.arrayBuffer();
      const wasmModule = await WebAssembly.compile(wasmBytes);

      this.node = new AudioWorkletNode(this.ctx, "moonbit-dsp", {
        numberOfInputs: 0,
        numberOfOutputs: 1,
        outputChannelCount: [2],
        processorOptions: {
          wasmModule,
          useScheduler: true,
        },
      });
      const node = this.node;

      // Wait for the worklet to confirm wasm init before declaring `running`.
      // Messages sent before `ready` are silently dropped by processor.js.
      const ready = new Promise<void>((resolve, reject) => {
        const timeoutId = window.setTimeout(() => {
          reject(new Error("worklet ready timeout (5s)"));
        }, 5000);
        node.port.onmessage = (event) => {
          const data = event.data as WorkletReply;
          if (!data || typeof data !== "object") return;
          if (data.type === "ready") {
            window.clearTimeout(timeoutId);
            // Swap in the steady-state handler before resolving.
            node.port.onmessage = (e) => this.dispatchReply(e.data as WorkletReply);
            resolve();
            return;
          }
          if (data.type === "error") {
            window.clearTimeout(timeoutId);
            reject(new Error(String(data.message ?? "worklet error")));
            return;
          }
          // Forward anything else through normal channels.
          this.dispatchReply(data);
        };
      });

      node.connect(this.ctx.destination);

      await ready;

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
  }

  /**
   * Test-only: inject a synthetic worklet reply through the dispatch
   * pipeline. Used by smoke tests to exercise the runtime-error path
   * without crashing the actual wasm graph. Do not call from app code.
   */
  _testInjectReply(reply: WorkletReply): void {
    this.dispatchReply(reply);
  }

  private teardownGraph(): void {
    if (this.node) {
      try {
        this.node.disconnect();
      } catch {
        /* already disconnected */
      }
      this.node = null;
    }
    if (this.ctx) {
      // Fire-and-forget; close() returns a Promise but we don't need to await
      // it for the host to begin a fresh start().
      void this.ctx.close().catch(() => undefined);
      this.ctx = null;
    }
  }

  setPatternText(text: string, revision?: number): void {
    if (!this.node) return;
    this.node.port.postMessage({ type: "set-pattern-text", text, revision });
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
      try {
        this.node.disconnect();
      } catch {
        /* already disconnected */
      }
      this.node = null;
    }
    if (this.ctx) {
      try {
        await this.ctx.close();
      } catch {
        /* already closed */
      }
      this.ctx = null;
    }
    this.setStatus({ kind: "idle" });
  }
}
