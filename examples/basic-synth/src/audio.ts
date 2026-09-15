import { GraphEngine, GraphEngineError } from "@moondsp/browser";
import type { GraphEngine as EngineHandle, GraphControl, MountedGraph } from "@moondsp/browser";
import { errorMessage, type ControlState } from "./controls";
import { attempt, attemptAsync, type Result } from "./result";
import { SYNTH_GRAPH, volumeControl, cutoffControl, noteOn, noteOff, type Settings } from "./synth";

export interface AudioView {
  render(state: ControlState): void;
  clearNotes(): void;
}

export interface AudioActions {
  powerOn(): void;
  stopNotes(): void;
  powerOff(): void;
  press(midi: number): void;
  release(nextMidi: number | null): void;
  volumeChanged(value: number): void;
  cutoffChanged(value: number): void;
}

type OwnedResources =
  | { stage: "empty" }
  | { stage: "context"; context: AudioContext }
  | { stage: "engine"; context: AudioContext; engine: EngineHandle };

interface AudioOwner {
  readonly signal: AbortSignal;
  open(settings: () => Settings, onContext: (context: AudioContext) => void): Promise<AudioSession>;
  close(): Promise<Result<void>>;
}

// Handles are usable together only after initialization. Only owner may release them.
interface AudioSession {
  readonly owner: AudioOwner;
  readonly context: AudioContext;
  readonly engine: EngineHandle;
  readonly graph: MountedGraph;
  operations: Promise<void>;
  noteEpoch: number;
}

type AudioState =
  | { phase: "idle" | "disposed" }
  | { phase: "loading" | "disposing"; owner: AudioOwner }
  | { phase: "suspended" | "resuming" | "running"; session: AudioSession }
  | { phase: "error"; owner: AudioOwner; error: Error };

// One owner spans partial acquisition, the published session, and retirement.
// Retirement bypasses the command queue: a pending command must not prevent close.
function createAudioOwner(previous?: AudioOwner): AudioOwner {
  const predecessor = previous?.close();
  const cancellation = new AbortController();
  const { signal } = cancellation;
  let resources: OwnedResources = { stage: "empty" };
  let closure: Promise<Result<void>> | undefined;
  const owner: AudioOwner = {
    signal,
    async open(readSettings, onContext) {
      try {
        // Admit this context in the Power on gesture, before any await.
        // Loading may outlast transient user activation.
        signal.throwIfAborted();
        if (typeof AudioContext === "undefined") throw new Error("AudioContext is unavailable");
        const context = new AudioContext();
        resources = { stage: "context", context };
        const admission = attemptAsync(() => context.resume());
        onContext(context);
        const admitted = await admission;
        if (!admitted.ok) throw admitted.error;
        signal.throwIfAborted();
        // The graph API requires suspended mounting, even after admission.
        await context.suspend();
        if (predecessor) await predecessor;
        signal.throwIfAborted();
        if (!context.audioWorklet) throw new Error("AudioWorklet is unavailable");
        const engine = await GraphEngine({ context, signal });
        // The factory may have resolved immediately before retirement. Do not adopt
        // that late handle into resources already handed to cleanup.
        if (signal.aborted) {
          await attemptAsync(() => engine.close());
          signal.throwIfAborted();
        }
        resources = { stage: "engine", context, engine };
        const graph = await engine.mount(SYNTH_GRAPH);
        signal.throwIfAborted();
        const settings = readSettings();
        await graph.applyControls([volumeControl(settings.volume), cutoffControl(settings.cutoff)]);
        signal.throwIfAborted();
        await graph.play();
        signal.throwIfAborted();
        await context.resume();
        signal.throwIfAborted();
        engine.output.connect(context.destination);
        return { owner, context, engine, graph, operations: Promise.resolve(), noteEpoch: 0 };
      } catch (error) {
        await owner.close();
        throw error;
      }
    },
    close() {
      if (closure) return closure;
      cancellation.abort(); // Detach the context listener and the lifetime observer now.
      const owned = resources;
      closure = (async () => {
        const result = await cleanupResources(owned);
        resources = { stage: "empty" };
        if (predecessor) await predecessor;
        return result;
      })();
      return closure;
    },
  };
  return owner;
}

// Attempt every release, preserving the first cleanup failure. The app owns context.
async function cleanupResources(resources: OwnedResources): Promise<Result<void>> {
  let result: Result<void> = { ok: true, value: undefined };
  const remember = (step: Result<unknown>) => {
    if (result.ok && !step.ok) result = step;
  };
  if (resources.stage === "engine") {
    remember(attempt(() => resources.engine.output.disconnect()));
    remember(await attemptAsync(() => resources.engine.close()));
  }
  if (resources.stage !== "empty" && resources.context.state !== "closed") {
    remember(await attemptAsync(() => resources.context.close()));
  }
  return result;
}

/** Audio effects only. Values and commands arrive as data; no DOM reads occur here. */
export function createAudio(view: AudioView, initialSettings: Settings): AudioActions {
  let settings = initialSettings;
  let state: AudioState = { phase: "idle" };

  function currentOwner(): AudioOwner | undefined {
    if ("owner" in state) return state.owner;
    if ("session" in state) return state.session.owner;
    return undefined;
  }

  function currentSession(): AudioSession | undefined {
    return "session" in state ? state.session : undefined;
  }

  function canControl(): boolean {
    return state.phase === "suspended" || state.phase === "running";
  }

  function render(): void {
    let errorText = "";
    if (state.phase === "error") {
      const { error } = state;
      const detail = error instanceof GraphEngineError ? `${error.code}: ${error.message}` : error.message;
      errorText = errorMessage(detail);
    }
    view.render({ phase: state.phase, errorText });
  }

  // Only this transition publishes a complete session. Stale work cannot publish.
  function requestInitializeAudio(): void {
    const owner = createAudioOwner(currentOwner());
    state = { phase: "loading", owner };
    view.clearNotes();
    render();
    void attemptAsync(() => owner.open(() => settings, context => {
      context.addEventListener("statechange", () => {
        if (currentOwner() !== owner) return;
        if (context.state === "closed") requestDispose();
        else if (context.state === "suspended" && state.phase === "running") {
          state = { phase: "suspended", session: state.session };
          stopNotes();
          render();
        }
      }, { signal: owner.signal });
      render();
    })).then(result => {
      if (state.phase !== "loading" || state.owner !== owner) return;
      if (!result.ok) {
        failAudio(result.error, owner);
        return;
      }
      const session = result.value;
      state = { phase: session.context.state === "running" ? "running" : "suspended", session };
      void observeEngine(session);
      render();
    });
  }

  async function observeEngine(session: AudioSession): Promise<void> {
    const { owner, engine } = session;
    const result = await attemptAsync(() => engine.wait({ signal: owner.signal }));
    if (owner.signal.aborted || currentSession() !== session) return;
    if (!result.ok) failAudio(result.error, owner);
    else if (result.value.type === "failed") failAudio(result.value.error, owner);
    else requestDispose();
  }

  function powerOnFromGesture(): void {
    if (state.phase === "error" || state.phase === "idle" || state.phase === "disposed") {
      requestInitializeAudio();
      return;
    }
    if (state.phase !== "suspended") return;
    const { session } = state;
    const { context, graph } = session;
    state = { phase: "resuming", session };
    render();
    // attemptAsync invokes its action immediately, before its first await.
    // Never defer resume to the serialized queue: admission needs this gesture.
    const resume = attemptAsync(() => context.state === "suspended" ? context.resume() : Promise.resolve());
    enqueue(session, async () => {
      const resumed = await resume;
      if (!resumed.ok) throw resumed.error;
      if (currentSession() !== session) return;
      await graph.play();
      if (currentSession() !== session) return;
      state = { phase: context.state === "suspended" ? "suspended" : "running", session };
      render();
    });
  }

  function stopNotes(): void {
    const session = currentSession();
    if (session) session.noteEpoch += 1;
    view.clearNotes();
    queueControls(noteOff(), true);
  }

  // Commands serialize within a session, never across retired and new sessions.
  function enqueue(session: AudioSession, operation: () => Promise<void>): void {
    const run = session.operations.then(() => attemptAsync(async () => {
      if (currentSession() === session) await operation();
    }));
    session.operations = run.then(result => {
      if (!result.ok && currentSession() === session) failAudio(result.error, session.owner);
    });
  }

  function queueControls(changes: readonly GraphControl[], note = false): void {
    const session = currentSession();
    if (!session) return;
    const epoch = session.noteEpoch;
    enqueue(session, async () => {
      if (!canControl() || (note && epoch !== session.noteEpoch)) return;
      await session.graph.applyControls(changes);
    });
  }

  function requestDispose(): void {
    const owner = currentOwner();
    view.clearNotes();
    if (!owner) {
      state = { phase: "disposed" };
      render();
      return;
    }
    const disposing: AudioState = { phase: "disposing", owner };
    state = disposing;
    const closing = owner.close();
    render();
    void closing.then(result => {
      if (state !== disposing) return;
      if (!result.ok) failAudio(result.error, owner);
      else {
        state = { phase: "disposed" };
        render();
      }
    });
  }

  function failAudio(error: Error, owner: AudioOwner): void {
    if (currentOwner() !== owner) return;
    const failed: AudioState = { phase: "error", owner, error };
    state = failed;
    view.clearNotes();
    const closing = owner.close();
    render(); // Publish the primary failure without waiting for cleanup.
    void closing.then(() => {
      if (state === failed) render();
    });
  }

  return {
    powerOn: powerOnFromGesture,
    stopNotes,
    powerOff: requestDispose,
    press(midi: number) {
      queueControls(noteOn(midi), true);
    },
    release(nextMidi: number | null) {
      queueControls(noteOff(nextMidi), true);
    },
    volumeChanged(value: number) {
      settings = { ...settings, volume: value };
      queueControls([volumeControl(value)]);
    },
    cutoffChanged(value: number) {
      settings = { ...settings, cutoff: value };
      queueControls([cutoffControl(value)]);
    },
  };
}
