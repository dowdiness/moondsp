// Audio resource owner. Opening produces a capability tied to one playback run;
// score/tempo operations do not exist on a stopped engine or compiled session.
import { decodeWorkletMessage } from "./playback-protocol";
import type { PlaybackMode, PlaybackReceipt, ScoreRequest, RequestId, TempoReceipt } from "./playback-protocol";
import type { Tempo } from "./tempo";

export type AudioStatus =
  | { kind: "idle" } | { kind: "starting" } | { kind: "stopping" }
  | { kind: "running" } | { kind: "error"; message: string };
export type AudioEngineMode = "scheduler" | "compiled";
export type AudioEngineOptions = {
  enableTelemetry?: boolean;
  enableSchedulerTiming?: boolean;
  schedulerTimingBatchSize?: number;
  sampleRate?: number;
  latencyHint?: AudioContextOptions["latencyHint"];
  mode?: AudioEngineMode;
};

export type AudioEvent =
  | { kind: "receipt"; receipt: PlaybackReceipt }
  | { kind: "tempo"; receipt: TempoReceipt }
  | { kind: "failed"; message: string };
export type CloseSessionResult = { kind: "closed" } | { kind: "session-expired" };
/** Issued means posted to the worklet or scheduled locally, not accepted by DSP.
 * A session-expired command has no effect; obtain a new session to issue it. */
export type SessionCommandResult = "issued" | "session-expired";

type SessionControls = Readonly<{
  /** Schedule an 80ms output fade-in; this does not confirm score acceptance. */
  fadeIn(): SessionCommandResult;
  /** Expire this session immediately, then fade out and suspend its audio graph. */
  close(): Promise<CloseSessionResult>;
}>;
export type SchedulerSession = SessionControls & Readonly<{
  kind: "scheduler";
  /** Submit a score; a playback receipt reports acceptance or rejection. */
  submitScore(request: ScoreRequest): SessionCommandResult;
  /** Request a tempo change; a tempo receipt reports the effective BPM. */
  requestTempoChange(tempo: Tempo, id: RequestId): SessionCommandResult;
}>;
export type CompiledSession = SessionControls & Readonly<{ kind: "compiled" }>;
export type AudioSession = SchedulerSession | CompiledSession;
export type OpenSessionResult =
  | { kind: "opened"; session: AudioSession }
  | { kind: "failed"; message: string }
  | { kind: "busy" };

type Graph = Readonly<{
  ctx: AudioContext;
  node: AudioWorkletNode;
  gain: GainNode;
}>;
type GraphRun = Readonly<{
  run: symbol;
  graph: Graph;
  deliver: (event: AudioEvent) => void;
}>;
type SessionCommand = "fade-in"
  | Readonly<{ type: "apply-score"; mode: PlaybackMode; text: string;
      policy: "continue" | "restart"; revision: number }>
  | Readonly<{ type: "set-scheduler-bpm"; bpm: number; revision: number }>;
type EngineState =
  | { kind: "idle" }
  | { kind: "suspended"; graph: Graph }
  | { kind: "opening"; run: symbol }
  | (GraphRun & { kind: "active" | "closing" })
  | (GraphRun & { kind: "resuming"; interrupted: (message: string) => void })
  | { kind: "failed"; message: string };

export class AudioEngine {
  private state: EngineState = { kind: "idle" };
  readonly mode: AudioEngineMode;

  constructor(
    private readonly processorUrl = "/processor.js",
    private readonly wasmUrl = "/moonbit_dsp.wasm",
    private readonly options: AudioEngineOptions = {},
  ) {
    this.mode = options.mode ?? "scheduler";
  }

  getStatus(): AudioStatus {
    switch (this.state.kind) {
      case "idle": case "suspended": return { kind: "idle" };
      case "opening": case "resuming": return { kind: "starting" };
      case "active": return { kind: "running" };
      case "closing": return { kind: "stopping" };
      case "failed": return { kind: "error", message: this.state.message };
    }
  }

  /** Open a muted session, creating or resuming a healthy graph.
   * Call from a user gesture so AudioContext.resume retains activation. */
  async openSession(deliver: (event: AudioEvent) => void): Promise<OpenSessionResult> {
    const previous = this.state;
    switch (previous.kind) {
      case "opening": case "resuming": case "active": case "closing": return { kind: "busy" };
      case "idle": case "suspended": case "failed": break;
    }
    const run = Symbol("audio run");
    if (previous.kind === "suspended" && previous.graph.ctx.state !== "closed") {
      return this.resume(previous.graph, run, deliver);
    }
    const opening = { kind: "opening" as const, run };
    this.state = opening;
    let graph: Graph;
    try {
      if (previous.kind === "suspended") this.dispose(previous.graph);
      graph = await this.createGraph();
      // These handlers follow the graph's lifetime, not a playback run.
      graph.node.port.onmessage = event => { this.dispatch(event.data, graph); };
      graph.node.onprocessorerror = () => {
        this.dispatch({ type: "error", message: "AudioWorklet processor failed" }, graph);
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      if (this.state === opening) {
        this.state = { kind: "failed", message };
      }
      return { kind: "failed", message };
    }
    return this.activate(graph, run, deliver);
  }

  private resume(graph: Graph, run: symbol, deliver: (event: AudioEvent) => void): Promise<OpenSessionResult> {
    return new Promise(resolve => {
      // Closing a context can leave its native resume promise pending. The
      // graph owner therefore settles this operation directly on a fault.
      const resuming = { kind: "resuming" as const, graph, run, deliver,
        interrupted: (message: string) => resolve({ kind: "failed", message }) };
      this.state = resuming;
      const failed = (error: unknown) => {
        if (this.state === resuming) {
          this.fail(resuming, error instanceof Error ? error.message : String(error));
        }
      };
      try {
        this.ramp(graph, 0, 0);
        void graph.ctx.resume().then(() => {
          if (this.state === resuming) resolve(this.activate(graph, run, deliver));
        }, failed);
      } catch (error) {
        failed(error);
      }
    });
  }

  private activate(graph: Graph, run: symbol, deliver: (event: AudioEvent) => void): OpenSessionResult {
    this.state = { kind: "active", run, graph, deliver };
    graph.node.port.postMessage(this.mode === "scheduler"
      ? { type: "set-scheduler-gain", gain: 0.6 }
      : { type: "set-gain", value: 0.6 });
    const controls: SessionControls = {
      fadeIn: () => this.command(run, "fade-in"),
      close: () => this.close(run),
    };
    const session: AudioSession = this.mode === "scheduler" ? {
      ...controls, kind: "scheduler",
      submitScore: ({ id, score, policy }) => this.command(run, {
        type: "apply-score", mode: score.mode, text: score.text, policy, revision: id.value,
      }),
      requestTempoChange: (tempo, id) => this.command(run, {
        type: "set-scheduler-bpm", bpm: tempo.value, revision: id.value,
      }),
    } : { ...controls, kind: "compiled" };
    return { kind: "opened", session };
  }

  private async createGraph(): Promise<Graph> {
    const ctx = new AudioContext({ sampleRate: this.options.sampleRate, latencyHint: this.options.latencyHint });
    let node: AudioWorkletNode | undefined;
    let gain: GainNode | undefined;
    try {
      gain = new GainNode(ctx, { gain: 0 });
      gain.connect(ctx.destination);
      await ctx.resume();
      const response = await fetch(this.wasmUrl);
      if (!response.ok) throw new Error(`fetch ${this.wasmUrl}: ${response.status}`);
      const wasmModule = await WebAssembly.compile(await response.arrayBuffer());
      const scheduler = this.mode === "scheduler";
      await ctx.audioWorklet.addModule(scheduler ? "/scheduler-processor.js" : this.processorUrl);
      node = new AudioWorkletNode(ctx, scheduler ? "moondsp-scheduler" : "moonbit-dsp", {
        numberOfInputs: 0, numberOfOutputs: 1, outputChannelCount: [2],
        processorOptions: scheduler ? { wasmModule } : {
          wasmModule, useScheduler: false, useProbeSine: false,
          enableTelemetry: this.options.enableTelemetry === true,
          enableSchedulerTiming: this.options.enableSchedulerTiming === true,
          schedulerTimingBatchSize: this.options.schedulerTimingBatchSize ?? 128,
        },
      });
      const ready = this.waitForReady(node);
      node.connect(gain);
      await ready;
      return { ctx, node, gain };
    } catch (error) {
      if (node) { node.port.onmessage = null; node.onprocessorerror = null; node.disconnect(); }
      gain?.disconnect();
      if (ctx.state !== "closed") void ctx.close().catch(error => console.warn("Audio close failed", error));
      throw error;
    }
  }

  private waitForReady(node: AudioWorkletNode): Promise<void> {
    return new Promise((resolve, reject) => {
      const fail = (message: string) => {
        window.clearTimeout(timeout);
        reject(new Error(message));
      };
      const timeout = window.setTimeout(() => fail("AudioWorklet ready timeout (5s)"), 5000);
      node.onprocessorerror = () => fail("AudioWorklet processor failed during startup");
      node.port.onmessage = event => {
        const message = decodeWorkletMessage(event.data);
        switch (message.kind) {
          case "ready": window.clearTimeout(timeout); resolve(); break;
          case "runtime-error": case "protocol-error": fail(message.message); break;
          case "notice": console.debug("[moondsp/live]", message.data); break;
          case "receipt": case "tempo": fail("Playback receipt arrived before worklet readiness"); break;
        }
      };
    });
  }

  private dispatch(raw: unknown, graph: Graph): "delivered" | "notice" | "obsolete-session" {
    const state = this.state;
    if (!("graph" in state) || state.graph !== graph) return "obsolete-session";
    const message = decodeWorkletMessage(raw);
    switch (message.kind) {
      case "receipt": case "tempo":
        if (state.kind !== "active") return "obsolete-session";
        state.deliver(message);
        return "delivered";
      case "notice": console.debug("[moondsp/live]", message.data); return "notice";
      case "ready":
        this.fail(state, "Worklet announced readiness twice");
        return "delivered";
      case "protocol-error": case "runtime-error":
        this.fail(state, message.message);
        return "delivered";
    }
  }

  private fail(state: Extract<EngineState, { graph: Graph }>, message: string): void {
    this.dispose(state.graph);
    this.state = { kind: "failed", message };
    if (state.kind === "resuming") state.interrupted(message);
    if (state.kind !== "suspended") state.deliver({ kind: "failed", message });
  }

  /** Test injection crosses the same unknown-message decoder as MessagePort. */
  _testInjectReply(raw: unknown): "delivered" | "notice" | "obsolete-session" {
    return "graph" in this.state ? this.dispatch(raw, this.state.graph) : "obsolete-session";
  }

  /** One authority check for every command issued by a session capability. */
  private command(run: symbol, command: SessionCommand): SessionCommandResult {
    const state = this.state;
    if (state.kind !== "active" || state.run !== run) return "session-expired";
    if (command === "fade-in") this.ramp(state.graph, 1, 80);
    else state.graph.node.port.postMessage(command);
    return "issued";
  }

  private ramp(graph: Graph, value: number, durationMs: number): void {
    const now = graph.ctx.currentTime;
    const gain = graph.gain.gain;
    gain.cancelScheduledValues(now);
    gain.setValueAtTime(gain.value, now);
    gain.linearRampToValueAtTime(value, now + durationMs / 1000);
  }

  private async close(run: symbol): Promise<CloseSessionResult> {
    const active = this.state;
    if (active.kind !== "active" || active.run !== run) return { kind: "session-expired" };
    const closing = { ...active, kind: "closing" as const };
    const graph = active.graph;
    this.state = closing;
    try {
      this.ramp(graph, 0, 60);
      await new Promise<void>(resolve => window.setTimeout(resolve, 60));
      if (this.state !== closing) return { kind: "session-expired" };
      await graph.ctx.suspend();
    } catch {
      if (this.state !== closing) return { kind: "session-expired" };
      this.dispose(graph);
      this.state = { kind: "idle" };
      return { kind: "closed" };
    }
    if (this.state !== closing) return { kind: "session-expired" };
    this.state = { kind: "suspended", graph };
    return { kind: "closed" };
  }

  private dispose(graph: Graph): void {
    graph.node.port.onmessage = null;
    graph.node.onprocessorerror = null;
    graph.node.disconnect();
    graph.gain.disconnect();
    if (graph.ctx.state !== "closed") void graph.ctx.close().catch(error => console.warn("Audio close failed", error));
  }
}
