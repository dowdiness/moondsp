// Audio resource owner. Opening produces a capability tied to one playback run;
// score/tempo operations do not exist on a stopped engine.
import { decodeWorkletMessage } from "./playback-protocol";
import type { PlaybackInput } from "./authoring";
import type { PlayerReceipt, PlayerSnapshot, RequestId } from "./playback-protocol";
import { ONSET_BYTES, OnsetRing, type OnsetStatistics } from "../../playback-onsets.js";

function abortError(): DOMException {
  return new DOMException("Audio initialization cancelled", "AbortError");
}

// Fetching the engine can stall, and a browser can refuse to run audio that was
// not started inside a user gesture. Either way, a new press can start it.
const STARTUP_DEADLINE_MS = 5000;
function deadlineError(): Error {
  return new Error("Audio did not start within 5 seconds. Press Play again.");
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
export type AudioEngineOptions = {
  sampleRate?: number;
  latencyHint?: AudioContextOptions["latencyHint"];
  enableOnsets?: boolean;
};

export type AudioEvent =
  | { kind: "receipt"; receipt: PlayerReceipt }
  | ({ kind: "status" } & PlayerSnapshot)
  | { kind: "failed"; message: string };
export type CloseSessionResult = { kind: "closed" } | { kind: "session-expired" };
export type SessionCommandResult = "issued" | "session-expired";

export type AudioSession = Readonly<{
  fadeIn(): SessionCommandResult;
  close(): Promise<CloseSessionResult>;
  update(id: RequestId, input: PlaybackInput): SessionCommandResult;
  restart(id: RequestId, input: PlaybackInput): SessionCommandResult;
  play(id: RequestId): SessionCommandResult;
  pause(id: RequestId): SessionCommandResult;
}>;
export type OpenSessionResult =
  | { kind: "opened"; session: AudioSession }
  | { kind: "failed"; message: string }
  | { kind: "busy" };

export type OnsetObservation = Readonly<{ fields: readonly number[]; at: number }>;

type Graph = Readonly<{
  ctx: AudioContext;
  node: AudioWorkletNode;
  gain: GainNode;
  analyser: AnalyserNode;
  onsets: OnsetRing | null;
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
  // Cancelling, the deadline, or a failure while starting aborts the attempt.
  | { kind: "opening"; run: symbol; attempt: AbortController }
  | (GraphRun & { kind: "resuming"; attempt: AbortController })
  | (GraphRun & { kind: "active" | "closing" })
  | { kind: "failed"; message: string };

export class AudioEngine {
  private onsetEpoch = 0;

  get observationGeneration(): number { return this.onsetEpoch; }

  /** Retire queued visuals without changing the transport or accepted score. */
  discardOnsets(): void {
    this.onsetEpoch++;
    const state = this.state;
    if ("graph" in state && state.graph.onsets) {
      state.graph.onsets.read(-1);
      state.graph.node.port.postMessage({ type: "observe-onsets", onsetGeneration: this.onsetEpoch });
    }
  }

  /** Observed device-time mapping, not a second musical clock. Main thread only. */
  readOnsets(now: number): readonly OnsetObservation[] {
    const state = this.state;
    if (state.kind !== "active" || state.graph.ctx.state !== "running" || !state.graph.onsets) return [];
    const rows = state.graph.onsets.read(this.onsetEpoch);
    if (!rows.length) return [];
    const ctx = state.graph.ctx;
    const { contextTime = 0, performanceTime = 0 } = ctx.getOutputTimestamp();
    const outputStarted = performanceTime > 0;
    const offset = outputStarted
      ? performanceTime - contextTime * 1000
      : now - ctx.currentTime * 1000 + ((ctx.baseLatency || 0) + (ctx.outputLatency || 0)) * 1000;
    return rows.map(fields => ({ fields, at: offset + fields[0] * 1000 }));
  }

  onsetStatistics(): OnsetStatistics | null {
    const state = this.state;
    return "graph" in state ? state.graph.onsets?.statistics() ?? null : null;
  }

  /**
   * Copy up to 1024 live post-master samples and return their sample rate, or
   * clear the storage and return 0 when nothing is running.
   */
  readWaveform(target: Float32Array<ArrayBuffer>): number {
    const state = this.state;
    if (state.kind !== "active" || state.graph.ctx.state !== "running") {
      target.fill(0);
      return 0;
    }
    state.graph.analyser.getFloatTimeDomainData(target);
    if (target.length > state.graph.analyser.fftSize) target.fill(0, state.graph.analyser.fftSize);
    return state.graph.ctx.sampleRate;
  }
  private state: EngineState = { kind: "idle" };

  constructor(
    private readonly wasmUrl = "/moonbit_dsp.wasm",
    private readonly options: AudioEngineOptions = {},
  ) {}

  getStatus(): AudioStatus {
    switch (this.state.kind) {
      case "idle": case "suspended": return { kind: "idle" };
      case "opening": case "resuming": return { kind: "starting" };
      case "active": return { kind: "running" };
      case "closing": return { kind: "stopping" };
      case "failed": return { kind: "error", message: this.state.message };
    }
  }

  /**
   * Open a muted session, creating or resuming a healthy graph. Call from a
   * user gesture: the context is created or resumed before this first awaits,
   * so it keeps the gesture's activation. A closing session or a cancelled
   * start gives way at once rather than making the gesture wait for it.
   */
  async openSession(
    deliver: (event: AudioEvent) => void,
    signal?: AbortSignal,
  ): Promise<OpenSessionResult> {
    const previous = this.state;
    switch (previous.kind) {
      case "active": return { kind: "busy" };
      case "opening": case "resuming": if (!previous.attempt.signal.aborted) return { kind: "busy" }; break;
      case "idle": case "suspended": case "closing": case "failed": break;
    }
    if (signal?.aborted) throw abortError();
    // One signal ends the attempt: the caller cancels, the deadline passes, or the graph fails.
    const attempt = new AbortController();
    const timer = window.setTimeout(() => attempt.abort(deadlineError()), STARTUP_DEADLINE_MS);
    const cancel = () => attempt.abort(abortError());
    signal?.addEventListener("abort", cancel, { once: true });
    try {
      const run = Symbol("audio run");
      // Reopening during Stop's fade cancels the fade and keeps the graph.
      if ((previous.kind === "suspended" || previous.kind === "closing") && previous.graph.ctx.state !== "closed") {
        return await this.resume(previous.graph, run, deliver, attempt);
      }
      const opening: EngineState = { kind: "opening", run, attempt };
      this.state = opening;
      let graph: Graph;
      try {
        if (previous.kind === "suspended") void this.dispose(previous.graph);
        graph = await this.createGraph(attempt.signal);
        // These handlers follow the graph's lifetime, not a playback run.
        graph.node.port.onmessage = event => { this.dispatch(event.data, graph); };
        graph.node.onprocessorerror = () => {
          this.dispatch({ type: "error", message: "AudioWorklet processor failed" }, graph);
        };
      } catch (error) {
        // A later start may already have replaced this one.
        if (this.state === opening) this.state = isAbort(error) ? { kind: "idle" } : { kind: "failed", message: errorMessage(error) };
        if (isAbort(error)) throw error;
        return { kind: "failed", message: errorMessage(error) };
      }
      return this.activate(graph, run, deliver);
    } finally {
      window.clearTimeout(timer);
      signal?.removeEventListener("abort", cancel);
    }
  }

  private async resume(
    graph: Graph,
    run: symbol,
    deliver: (event: AudioEvent) => void,
    attempt: AbortController,
  ): Promise<OpenSessionResult> {
    const resuming: EngineState = { kind: "resuming", graph, run, deliver, attempt };
    this.state = resuming;
    try {
      this.ramp(graph, 0, 0);
      await abortable(() => graph.ctx.resume(), attempt.signal);
      return this.activate(graph, run, deliver);
    } catch (error) {
      // Leave the engine to a later start at once; the graph closes behind it.
      if (this.state === resuming) this.state = isAbort(error) ? { kind: "idle" } : { kind: "failed", message: errorMessage(error) };
      await this.dispose(graph);
      if (isAbort(error)) throw error;
      deliver({ kind: "failed", message: errorMessage(error) });
      return { kind: "failed", message: errorMessage(error) };
    }
  }

  private activate(graph: Graph, run: symbol, deliver: (event: AudioEvent) => void): OpenSessionResult {
    this.state = { kind: "active", run, graph, deliver };
    this.discardOnsets();
    graph.node.port.postMessage({ type: "set-scheduler-gain", gain: 0.6 });
    const session: AudioSession = {
      fadeIn: () => this.command(run, "fade-in"),
      close: () => this.close(run),
      update: (id, input) => this.command(run, { type: "player-update", id: id.value, input: input.wire }),
      restart: (id, input) => this.command(run, { type: "player-restart", id: id.value, input: input.wire }),
      play: id => this.command(run, { type: "player-play", id: id.value }),
      pause: id => this.command(run, { type: "player-pause", id: id.value }),
    };
    return { kind: "opened", session };
  }

  private async createGraph(signal: AbortSignal): Promise<Graph> {
    signal.throwIfAborted();
    const ctx = new AudioContext({ sampleRate: this.options.sampleRate, latencyHint: this.options.latencyHint });
    // A browser may create the context suspended until a user gesture lets it run.
    // Ask now, inside the caller's gesture; a session is reported only once audio runs.
    const running = ctx.state === "running" ? Promise.resolve() : ctx.resume();
    void running.catch(() => { /* Observed below, after the graph is built. */ });
    let node: AudioWorkletNode | undefined;
    let gain: GainNode | undefined;
    let analyser: AnalyserNode | undefined;
    try {
      gain = new GainNode(ctx, { gain: 0 });
      analyser = new AnalyserNode(ctx, { fftSize: 1024, smoothingTimeConstant: 0 });
      gain.connect(ctx.destination);
      gain.connect(analyser);
      const response = await abortable(() => fetch(this.wasmUrl, { signal }), signal);
      if (!response.ok) throw new Error(`fetch ${this.wasmUrl}: ${response.status}`);
      const bytes = await abortable(() => response.arrayBuffer(), signal);
      const wasmModule = await abortable(() => WebAssembly.compile(bytes), signal);
      // Onsets reach the page through shared memory, which needs cross-origin isolation.
      const onsets = this.options.enableOnsets !== false &&
        globalThis.crossOriginIsolated && typeof SharedArrayBuffer !== "undefined"
        ? new OnsetRing(new SharedArrayBuffer(ONSET_BYTES)) : null;
      await abortable(() => ctx.audioWorklet.addModule("/scheduler-processor.js"), signal);
      node = new AudioWorkletNode(ctx, "moondsp-scheduler", {
        numberOfInputs: 0, numberOfOutputs: 1, outputChannelCount: [2],
        processorOptions: { wasmModule, onsetBuffer: onsets?.buffer },
      });
      const ready = this.waitForReady(node, signal);
      node.connect(gain);
      await ready;
      await abortable(() => running, signal);
      return { ctx, node, gain, analyser, onsets };
    } catch (error) {
      await release(ctx, node, analyser, gain);
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
          case "status": break;
          case "receipt": fail(new Error("Playback receipt arrived before worklet readiness")); break;
        }
      };
    });
  }


  private dispatch(raw: unknown, graph: Graph): "delivered" | "obsolete-session" {
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
      state.attempt.abort(new Error(message));
      return;
    }
    void this.dispose(state.graph);
    this.state = { kind: "failed", message };
    if (state.kind !== "suspended") state.deliver({ kind: "failed", message });
  }

  /** Test injection crosses the same unknown-message decoder as MessagePort. */
  _testInjectReply(raw: unknown): "delivered" | "obsolete-session" {
    return "graph" in this.state ? this.dispatch(raw, this.state.graph) : "obsolete-session";
  }

  /** One authority check for every command issued by a session capability. */
  private command(run: symbol, command: SessionCommand): SessionCommandResult {
    const state = this.state;
    if (state.kind !== "active" || state.run !== run) return "session-expired";
    if (command === "fade-in") this.ramp(state.graph, 1, 80);
    else if (command.type === "player-restart" || command.type === "player-play" || command.type === "player-pause") {
      this.onsetEpoch++;
      state.graph.node.port.postMessage({ ...command, onsetGeneration: this.onsetEpoch });
    } else state.graph.node.port.postMessage(command);
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
    this.discardOnsets();
    this.state = closing;
    try {
      this.ramp(graph, 0, 60);
      await new Promise<void>(resolve => window.setTimeout(resolve, 60));
      if (this.state !== closing) return { kind: "session-expired" };
      await graph.ctx.suspend();
    } catch {
      if (this.state !== closing) return { kind: "session-expired" };
      void this.dispose(graph);
      this.state = { kind: "idle" };
      return { kind: "closed" };
    }
    if (this.state !== closing) return { kind: "session-expired" };
    this.state = { kind: "suspended", graph };
    return { kind: "closed" };
  }
  private dispose(graph: Graph): Promise<void> {
    return release(graph.ctx, graph.node, graph.analyser, graph.gain);
  }
}

/** Detaches a graph, built or partly built, and closes its context. */
async function release(ctx: AudioContext, ...nodes: (AudioNode | undefined)[]): Promise<void> {
  for (const node of nodes) {
    if (node instanceof AudioWorkletNode) { node.port.onmessage = null; node.onprocessorerror = null; }
    node?.disconnect();
  }
  if (ctx.state !== "closed") await ctx.close().catch(error => console.warn("Audio close failed", error));
}
