import { GraphEngine, GraphEngineError } from "@moondsp/browser";
import type { GraphEngine as EngineHandle, GraphControl, MountedGraph } from "@moondsp/browser";
import { errorMessage, type ControlState, type Phase } from "./controls";
import { attempt, attemptAsync, type Result } from "./result";
import { SYNTH_GRAPH, volumeControl, cutoffControl, noteOn, noteOff, type Settings } from "./synth";

export interface AudioView {
  render(state: ControlState): void;
  setNotesHeld(held: boolean): void;
  clearNotes(): void;
}

export interface AudioActions {
  start(): void;
  initialize(): void;
  stopNotes(): void;
  powerOff(): void;
  press(midi: number): void;
  release(nextMidi: number | null): void;
  volumeChanged(value: number): void;
  cutoffChanged(value: number): void;
}

interface AudioResources {
  context: AudioContext | null;
  engine: EngineHandle | null;
  graph: MountedGraph | null;
  stateChangeListener: (() => void) | null;
}

/** Audio effects only. Values and commands arrive as data; no DOM reads occur here. */
export function createAudio(view: AudioView, initialSettings: Settings): AudioActions {
  let settings = initialSettings;
  let phase: Phase = "idle";
  let context: AudioContext | null = null;
  let engine: EngineHandle | null = null;
  let mounted: MountedGraph | null = null;
  let contextStateChangeListener: (() => void) | null = null;
  let errorText = "";
  let initializationAbort: AbortController | null = null;
  let lifecycleToken = 0;
  let noteEpoch = 0;
  let serialOperations: Promise<void> = Promise.resolve();

  function render(): void {
    view.render({ phase, errorText, hasContext: context !== null, canControl: canControl() });
  }

  // Mount while suspended; resume only in the Start button's user gesture.
  async function initializeAudio(token: number, signal: AbortSignal): Promise<void> {
    const resources: AudioResources = { context: null, engine: null, graph: null, stateChangeListener: null };
    try {
      if (!isCurrent(token)) return;
      if (typeof AudioContext === "undefined") throw new Error("AudioContext is unavailable");
      const nextContext = new AudioContext();
      resources.context = nextContext;
      context = nextContext;
      addContextListener(nextContext, token, resources);
      if (nextContext.state !== "suspended") await nextContext.suspend();
      if (!nextContext.audioWorklet) throw new Error("AudioWorklet is unavailable");
      const nextEngine = await GraphEngine({ context: nextContext, signal });
      resources.engine = nextEngine;
      if (!isCurrent(token)) {
        clearCurrentResources(resources);
        await cleanupResources(resources);
        return;
      }
      const nextGraph = await nextEngine.mount(SYNTH_GRAPH);
      resources.graph = nextGraph;
      if (!isCurrent(token)) {
        clearCurrentResources(resources);
        await cleanupResources(resources);
        return;
      }
      await nextGraph.applyControls([volumeControl(settings.volume), cutoffControl(settings.cutoff)]);
      if (!isCurrent(token)) {
        clearCurrentResources(resources);
        await cleanupResources(resources);
        return;
      }
      nextEngine.output.connect(nextContext.destination);
      engine = nextEngine;
      mounted = nextGraph;
      initializationAbort = null;
      phase = "suspended";
      errorText = "";
      render();
    } catch (error) {
      clearCurrentResources(resources);
      await cleanupResources(resources);
      throw error; // The queue converts the external failure to Result.
    }
  }

  function startAudioFromGesture(): void {
    if (phase === "error" || phase === "idle" || phase === "disposed") {
      requestInitializeAudio();
      return;
    }
    if (phase !== "suspended" || !context || !mounted) return;
    const token = lifecycleToken;
    const nextContext = context;
    const nextGraph = mounted;
    phase = "resuming";
    render();
    // attemptAsync invokes its action immediately, before its first await.
    // Never defer resume to the serialized queue: admission needs this gesture.
    const resume = attemptAsync(() => nextContext.state === "suspended" ? nextContext.resume() : Promise.resolve());
    void enqueue(async () => {
      if (!isCurrent(token) || context !== nextContext || mounted !== nextGraph) return;
      const resumed = await resume;
      if (!resumed.ok) throw resumed.error;
      if (!isCurrent(token)) return;
      await nextGraph.play();
      if (!isCurrent(token)) return;
      phase = nextContext.state === "suspended" ? "suspended" : "running";
      render();
    }).then(result => handleFailure(result, token));
  }

  function playNote(midi: number): void {
    view.setNotesHeld(true);
    queueControls(noteOn(midi), lifecycleToken, noteEpoch);
  }

  function releaseNote(nextMidi: number | null): void {
    view.setNotesHeld(nextMidi !== null);
    queueControls(noteOff(nextMidi), lifecycleToken, noteEpoch);
  }

  function clearHeldNotes(): void {
    view.clearNotes();
    view.setNotesHeld(false);
  }

  function stopNotes(): void {
    noteEpoch += 1;
    clearHeldNotes();
    queueControls(noteOff(), lifecycleToken, noteEpoch);
  }

  // Cleanup deliberately does NOT short-circuit: every owned resource is attempted.
  async function cleanupResources(resources: AudioResources): Promise<Result<void>> {
    let result: Result<void> = { ok: true, value: undefined };
    const remember = (step: Result<unknown>) => {
      if (result.ok && !step.ok) result = step;
    };
    if (resources.context && resources.stateChangeListener) {
      const { context: ownedContext, stateChangeListener } = resources;
      remember(attempt(() => ownedContext.removeEventListener("statechange", stateChangeListener)));
    }
    if (resources.graph) {
      const graph = resources.graph;
      remember(await attemptAsync(() => graph.applyControls(noteOff())));
      remember(await attemptAsync(() => graph.unmount()));
    }
    if (resources.engine) {
      const ownedEngine = resources.engine;
      remember(attempt(() => ownedEngine.output.disconnect()));
      remember(await attemptAsync(() => ownedEngine.close()));
    }
    if (resources.context && resources.context.state !== "closed") {
      const ownedContext = resources.context;
      remember(await attemptAsync(() => ownedContext.close()));
    }
    return result;
  }

  function clearCurrentResources(resources: AudioResources): void {
    if (resources.graph === mounted) mounted = null;
    if (resources.engine === engine) engine = null;
    if (resources.context === context) {
      context = null;
      contextStateChangeListener = null;
    }
  }

  async function cleanupCurrentResources(): Promise<Result<void>> {
    const resources: AudioResources = { context, engine, graph: mounted, stateChangeListener: contextStateChangeListener };
    clearCurrentResources(resources);
    return cleanupResources(resources);
  }

  // A failed action stays on the failure rail; later queued actions can still run.
  function enqueue(operation: () => Promise<void>): Promise<Result<void>> {
    const run = serialOperations.then(() => attemptAsync(operation));
    serialOperations = run.then(() => undefined);
    return run;
  }

  function handleFailure(result: Result<void>, token: number): void {
    if (!result.ok && isCurrent(token)) failAudio(result.error);
  }

  function queueControls(changes: readonly GraphControl[], token = lifecycleToken, epoch?: number): void {
    void enqueue(async () => {
      if (!isCurrent(token) || !canControl() || (epoch !== undefined && epoch !== noteEpoch)) return;
      const graph = mounted;
      if (graph) await graph.applyControls(changes);
    }).then(result => handleFailure(result, token));
  }

  function isCurrent(token: number): boolean {
    return token === lifecycleToken;
  }

  function canControl(): boolean {
    return mounted !== null && (phase === "suspended" || phase === "running");
  }

  function requestInitializeAudio(): void {
    lifecycleToken += 1;
    noteEpoch += 1;
    initializationAbort?.abort();
    const token = lifecycleToken;
    const controller = new AbortController();
    initializationAbort = controller;
    clearHeldNotes();
    phase = "loading";
    errorText = "";
    render();
    void enqueue(() => initializeAudio(token, controller.signal)).then(result => {
      if (!result.ok && isCurrent(token)) setError(result.error);
    });
  }

  function requestDispose(): void {
    lifecycleToken += 1;
    noteEpoch += 1;
    initializationAbort?.abort();
    initializationAbort = null;
    clearHeldNotes();
    const token = lifecycleToken;
    phase = "disposing";
    render();
    void enqueue(async () => {
      const cleaned = await cleanupCurrentResources();
      if (!isCurrent(token)) return;
      if (!cleaned.ok) throw cleaned.error;
      phase = "disposed";
      render();
    }).then(result => {
      if (!result.ok && isCurrent(token)) setError(result.error);
    });
  }

  function addContextListener(nextContext: AudioContext, token: number, resources: AudioResources): void {
    const listener = () => {
      if (!isCurrent(token) || context !== nextContext) return;
      if (nextContext.state === "closed") {
        failAudio(new GraphEngineError("ENGINE_CLOSED", "The audio context was closed"));
      } else if (nextContext.state === "suspended" && phase === "running") {
        phase = "suspended";
        stopNotes();
        render();
      }
    };
    resources.stateChangeListener = listener;
    contextStateChangeListener = listener;
    nextContext.addEventListener("statechange", listener);
  }

  function failAudio(error: Error): void {
    if (phase === "disposing" || phase === "disposed") return;
    lifecycleToken += 1;
    noteEpoch += 1;
    initializationAbort?.abort();
    initializationAbort = null;
    clearHeldNotes();
    const token = lifecycleToken;
    setError(error);
    void enqueue(async () => {
      await cleanupCurrentResources();
      if (isCurrent(token) && phase === "error") render();
    });
  }

  function setError(error: Error): void {
    const detail = error instanceof GraphEngineError ? `${error.code}: ${error.message}` : error.message;
    errorText = errorMessage(detail);
    phase = "error";
    render();
  }

  return {
    start: startAudioFromGesture,
    initialize: requestInitializeAudio,
    stopNotes,
    powerOff: requestDispose,
    press: playNote,
    release: releaseNote,
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
