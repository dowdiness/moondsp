// Audio resource owner. Opening produces a capability tied to one playback run;
// score/tempo operations do not exist on a stopped engine or compiled session.
import { decodeWorkletMessage } from "./playback-protocol";
import type { PlaybackInput } from "./authoring";
import type { PlayerReceipt, PlayerSnapshot, RequestId } from "./playback-protocol";

function abortError(): DOMException {
  return new DOMException("Audio initialization cancelled", "AbortError");
}

function timeoutError(): Error {
  return new Error("Audio initialization timeout (5s)");
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function isAbort(error: unknown): boolean {
  return error instanceof DOMException && error.name === "AbortError";
}

function abortable<T>(start: () => Promise<T>, signal: AbortSignal): Promise<T> {
  signal.throwIfAborted();
  const promise = start();
  return new Promise<T>((resolve, reject) => {
    const onAbort = () => reject(signal.reason ?? abortError());
    signal.addEventListener("abort", onAbort, { once: true });
    if (signal.aborted) onAbort();
    void promise.then(value => {
      signal.removeEventListener("abort", onAbort);
      resolve(value);
    }, error => {
      signal.removeEventListener("abort", onAbort);
      reject(error);
    });
  });
}

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
  | { kind: "receipt"; receipt: PlayerReceipt }
  | ({ kind: "status" } & PlayerSnapshot)
  | { kind: "failed"; message: string };
export type CloseSessionResult = { kind: "closed" } | { kind: "session-expired" };
export type SessionCommandResult = "issued" | "session-expired";

type SessionControls = Readonly<{
  fadeIn(): SessionCommandResult;
  close(): Promise<CloseSessionResult>;
}>;
export type SchedulerSession = SessionControls & Readonly<{
  kind: "scheduler";
  update(id: RequestId, input: PlaybackInput): SessionCommandResult;
  restart(id: RequestId, input: PlaybackInput): SessionCommandResult;
  play(id: RequestId): SessionCommandResult;
  pause(id: RequestId): SessionCommandResult;
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
  | Readonly<{ type: "player-update" | "player-restart"; id: number; input: string }>
  | Readonly<{ type: "player-play" | "player-pause"; id: number }>;
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
  async openSession(
    deliver: (event: AudioEvent) => void,
    signal?: AbortSignal,
  ): Promise<OpenSessionResult> {
    const previous = this.state;
    switch (previous.kind) {
      case "opening": case "resuming": case "active": case "closing": return { kind: "busy" };
      case "idle": case "suspended": case "failed": break;
    }
    if (signal?.aborted) throw abortError();
    const deadline = new AbortController();
    const timer = window.setTimeout(() => deadline.abort(timeoutError()), 5000);
    const abort = () => deadline.abort(signal?.reason instanceof DOMException && signal.reason.name === "AbortError"
      ? signal.reason : abortError());
    signal?.addEventListener("abort", abort, { once: true });
    try {
      const run = Symbol("audio run");
      if (previous.kind === "suspended" && previous.graph.ctx.state !== "closed") {
        return await this.resume(previous.graph, run, deliver, deadline.signal);
      }
      const opening = { kind: "opening" as const, run };
      this.state = opening;
      let graph: Graph;
      try {
        if (previous.kind === "suspended") await this.disposeAndWait(previous.graph);
        graph = await this.createGraph(deadline.signal);
        if (this.state !== opening || deadline.signal.aborted) {
          await this.disposeAndWait(graph);
          throw deadline.signal.reason ?? abortError();
        }
        // These handlers follow the graph's lifetime, not a playback run.
        graph.node.port.onmessage = event => { this.dispatch(event.data, graph); };
        graph.node.onprocessorerror = () => {
          this.dispatch({ type: "error", message: "AudioWorklet processor failed" }, graph);
        };
      } catch (error) {
        if (this.state === opening) this.state = deadline.signal.aborted && isAbort(error)
          ? { kind: "idle" } : { kind: "failed", message: errorMessage(error) };
        if (isAbort(error)) throw error;
        return { kind: "failed", message: errorMessage(error) };
      }
      return this.activate(graph, run, deliver);
    } finally {
      window.clearTimeout(timer);
      signal?.removeEventListener("abort", abort);
    }
  }

  private async resume(
    graph: Graph,
    run: symbol,
    deliver: (event: AudioEvent) => void,
    signal: AbortSignal,
  ): Promise<OpenSessionResult> {
    let interrupted!: (message: string) => void;
    const fault = new Promise<never>((_resolve, reject) => {
      interrupted = message => reject(new Error(message));
    });
    const resuming = { kind: "resuming" as const, graph, run, deliver, interrupted };
    this.state = resuming;
    try {
      this.ramp(graph, 0, 0);
      await abortable(() => Promise.race([graph.ctx.resume(), fault]), signal);
      signal.throwIfAborted();
      if (this.state !== resuming) throw abortError();
      return this.activate(graph, run, deliver);
    } catch (error) {
      await this.disposeAndWait(graph);
      if (this.state === resuming) this.state = isAbort(error)
        ? { kind: "idle" } : { kind: "failed", message: errorMessage(error) };
      if (isAbort(error)) throw error;
      deliver({ kind: "failed", message: errorMessage(error) });
      return { kind: "failed", message: errorMessage(error) };
    }
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
      update: (id, input) => this.command(run, { type: "player-update", id: id.value, input: input.wire }),
      restart: (id, input) => this.command(run, { type: "player-restart", id: id.value, input: input.wire }),
      play: id => this.command(run, { type: "player-play", id: id.value }),
      pause: id => this.command(run, { type: "player-pause", id: id.value }),
    } : { ...controls, kind: "compiled" };
    return { kind: "opened", session };
  }

  private async createGraph(signal: AbortSignal): Promise<Graph> {
    signal.throwIfAborted();
    const ctx = new AudioContext({ sampleRate: this.options.sampleRate, latencyHint: this.options.latencyHint });
    let node: AudioWorkletNode | undefined;
    let gain: GainNode | undefined;
    try {
      gain = new GainNode(ctx, { gain: 0 });
      gain.connect(ctx.destination);
      await abortable(() => ctx.resume(), signal);
      const response = await abortable(() => fetch(this.wasmUrl, { signal }), signal);
      if (!response.ok) throw new Error(`fetch ${this.wasmUrl}: ${response.status}`);
      const bytes = await abortable(() => response.arrayBuffer(), signal);
      const wasmModule = await abortable(() => WebAssembly.compile(bytes), signal);
      const scheduler = this.mode === "scheduler";
      await abortable(() => ctx.audioWorklet.addModule(scheduler ? "/scheduler-processor.js" : this.processorUrl), signal);
      signal.throwIfAborted();
      node = new AudioWorkletNode(ctx, scheduler ? "moondsp-scheduler" : "moonbit-dsp", {
        numberOfInputs: 0, numberOfOutputs: 1, outputChannelCount: [2],
        processorOptions: scheduler ? { wasmModule } : {
          wasmModule, useScheduler: false, useProbeSine: false,
          enableTelemetry: this.options.enableTelemetry === true,
          enableSchedulerTiming: this.options.enableSchedulerTiming === true,
          schedulerTimingBatchSize: this.options.schedulerTimingBatchSize ?? 128,
        },
      });
      const ready = this.waitForReady(node, signal);
      node.connect(gain);
      await ready;
      if (signal.aborted) throw signal.reason ?? abortError();
      return { ctx, node, gain };
    } catch (error) {
      if (node) { node.port.onmessage = null; node.onprocessorerror = null; node.disconnect(); }
      gain?.disconnect();
      if (ctx.state !== "closed") await ctx.close().catch(closeError => console.warn("Audio close failed", closeError));
      throw error;
    }
  }

  private waitForReady(node: AudioWorkletNode, signal: AbortSignal): Promise<void> {
    signal.throwIfAborted();
    return new Promise<void>((resolve, reject) => {
      const fail = (error: unknown) => {
        signal.removeEventListener("abort", onAbort);
        reject(error);
      };
      const onAbort = () => fail(signal.reason ?? abortError());
      signal.addEventListener("abort", onAbort, { once: true });
      node.onprocessorerror = () => fail(new Error("AudioWorklet processor failed during startup"));
      node.port.onmessage = event => {
        const message = decodeWorkletMessage(event.data);
        switch (message.kind) {
          case "ready": signal.removeEventListener("abort", onAbort); resolve(); break;
          case "runtime-error": case "protocol-error": fail(new Error(message.message)); break;
          case "notice": console.debug("[moondsp/live]", message.data); break;
          case "status": break;
          case "receipt": fail(new Error("Playback receipt arrived before worklet readiness")); break;
        }
      };
    });
  }


  private dispatch(raw: unknown, graph: Graph): "delivered" | "notice" | "obsolete-session" {
    const state = this.state;
    if (!("graph" in state) || state.graph !== graph) return "obsolete-session";
    const message = decodeWorkletMessage(raw);
    switch (message.kind) {
      case "receipt":
        if (state.kind !== "active") return "obsolete-session";
        state.deliver(message);
        return "delivered";
      case "status":
        if (state.kind === "active") state.deliver(message);
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
    if (state.kind === "resuming") {
      state.interrupted(message);
      return;
    }
    this.dispose(state.graph);
    this.state = { kind: "failed", message };
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
  private async disposeAndWait(graph: Graph): Promise<void> {
    graph.node.port.onmessage = null;
    graph.node.onprocessorerror = null;
    graph.node.disconnect();
    graph.gain.disconnect();
    if (graph.ctx.state !== "closed") await graph.ctx.close().catch(error => console.warn("Audio close failed", error));
  }

  private dispose(graph: Graph): void {
    graph.node.port.onmessage = null;
    graph.node.onprocessorerror = null;
    graph.node.disconnect();
    graph.gain.disconnect();
    if (graph.ctx.state !== "closed") void graph.ctx.close().catch(error => console.warn("Audio close failed", error));
  }
}
