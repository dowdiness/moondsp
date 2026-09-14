import { GraphEngine, GraphEngineError } from "@moondsp/browser";
import type { GraphEngine as EngineHandle, GraphDescription, GraphControl, MountedGraph } from "@moondsp/browser";
import { createControls, type Phase } from "./controls";
import { createKeyboard } from "./keyboard";
import "./style.css";

// Describe the signal graph once. Playing notes changes controls, not topology.
const OSCILLATOR_NODE = 0;
const FILTER_NODE = 1;
const ADSR_NODE = 2;
const GAIN_NODE = 4;
const DEFAULT_CUTOFF_HZ = 2_000;
const DEFAULT_VOLUME = 0.15;
const SYNTH_GRAPH = {
  nodes: [
    { type: "oscillator", waveform: "triangle", frequency: 261.625565 },
    { type: "biquad", input: OSCILLATOR_NODE, mode: "lowpass", cutoff: DEFAULT_CUTOFF_HZ, q: 0.7 },
    { type: "adsr", attackMs: 10, decayMs: 80, sustain: 0.7, releaseMs: 180 },
    { type: "mul", input0: FILTER_NODE, input1: ADSR_NODE },
    { type: "gain", input: 3, gain: DEFAULT_VOLUME },
    { type: "output", input: GAIN_NODE },
  ],
} as const satisfies GraphDescription;

interface AudioResources {
  context: AudioContext | null;
  engine: EngineHandle | null;
  graph: MountedGraph | null;
  stateChangeListener: (() => void) | null;
}

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

// The UI translates browser gestures into these audio operations.
const controls = createControls({ volume: DEFAULT_VOLUME, cutoff: DEFAULT_CUTOFF_HZ }, {
  start: startAudioFromGesture,
  retry: requestPrepare,
  stopNotes,
  powerOff: requestDispose,
  volumeChanged(value) {
    queueControls([{ type: "setParam", node: GAIN_NODE, slot: "value0", value }]);
  },
  cutoffChanged(value) {
    queueControls([{ type: "setParam", node: FILTER_NODE, slot: "value0", value }]);
  },
});
const keyboard = createKeyboard({ press: playNote, release: releaseNote });

function render(): void {
  controls.render({ phase, errorText, hasContext: context !== null, canControl: canControl() });
  keyboard.setEnabled(phase === "running" && canControl());
}

// Mount while suspended; resume only in the Start button's user gesture.
async function prepare(token: number, signal: AbortSignal): Promise<void> {
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
    await nextGraph.applyControls([
      { type: "setParam", node: GAIN_NODE, slot: "value0", value: controls.volume },
      { type: "setParam", node: FILTER_NODE, slot: "value0", value: controls.cutoff },
    ]);
    if (!isCurrent(token)) {
      clearCurrentResources(resources);
      await cleanupResources(resources);
      return;
    }
    nextEngine.output.connect(nextContext.destination);
    engine = nextEngine;
    mounted = resources.graph;
    initializationAbort = null;
    phase = "suspended";
    errorText = "";
    render();
  } catch (error) {
    clearCurrentResources(resources);
    await cleanupResources(resources);
    if (isCurrent(token)) setError(error);
  }
}

function startAudioFromGesture(): void {
  if (phase === "error" || phase === "idle" || phase === "disposed") {
    requestPrepare();
    return;
  }
  if (phase !== "suspended" || !context || !mounted) return;
  const token = lifecycleToken;
  const nextContext = context;
  const nextGraph = mounted;
  phase = "resuming";
  render();

  // Call resume before awaiting anything so the browser sees the user gesture.
  const resume = nextContext.state === "suspended" ? nextContext.resume() : Promise.resolve();
  void enqueue(async () => {
    if (!isCurrent(token) || context !== nextContext || mounted !== nextGraph) return;
    await resume;
    if (!isCurrent(token)) return;
    await nextGraph.play();
    if (!isCurrent(token)) return;
    phase = nextContext.state === "suspended" ? "suspended" : "running";
    render();
  }).catch((error: unknown) => {
    if (isCurrent(token)) failAudio(error);
  });
}

// Pressing starts a note. Releasing can return to the last remaining held note.
function frequencyForMidi(midi: number): number {
  return 440 * 2 ** ((midi - 69) / 12);
}

function playNote(midi: number): void {
  controls.setNotesHeld(true);
  queueControls([
    { type: "setParam", node: OSCILLATOR_NODE, slot: "value0", value: frequencyForMidi(midi) },
    { type: "gateOn", node: ADSR_NODE },
  ], lifecycleToken, noteEpoch);
}

function releaseNote(nextMidi: number | null): void {
  controls.setNotesHeld(nextMidi !== null);
  const changes: GraphControl[] = [{ type: "gateOff", node: ADSR_NODE }];
  if (nextMidi !== null) {
    changes.push(
      { type: "setParam", node: OSCILLATOR_NODE, slot: "value0", value: frequencyForMidi(nextMidi) },
      { type: "gateOn", node: ADSR_NODE },
    );
  }
  queueControls(changes, lifecycleToken, noteEpoch);
}

function clearHeldNotes(): void {
  keyboard.clear();
  controls.setNotesHeld(false);
}

function stopNotes(): void {
  noteEpoch += 1;
  clearHeldNotes();
  queueControls([{ type: "gateOff", node: ADSR_NODE }], lifecycleToken, noteEpoch);
}

// Cleanup attempts every owned resource, even if an earlier step fails.
async function cleanupResources(resources: AudioResources): Promise<unknown | null> {
  let firstError: unknown | null = null;
  const remember = (error: unknown) => {
    if (firstError === null) firstError = error;
  };
  if (resources.context && resources.stateChangeListener) {
    resources.context.removeEventListener("statechange", resources.stateChangeListener);
  }
  if (resources.graph) {
    try {
      await resources.graph.applyControls([{ type: "gateOff", node: ADSR_NODE }]);
    } catch (error) {
      remember(error);
    }
    try {
      await resources.graph.unmount();
    } catch (error) {
      remember(error);
    }
  }
  if (resources.engine) {
    try {
      resources.engine.output.disconnect();
    } catch (error) {
      remember(error);
    }
    try {
      await resources.engine.close();
    } catch (error) {
      remember(error);
    }
  }
  if (resources.context && resources.context.state !== "closed") {
    try {
      await resources.context.close();
    } catch (error) {
      remember(error);
    }
  }
  return firstError;
}

function clearCurrentResources(resources: AudioResources): void {
  if (resources.graph === mounted) mounted = null;
  if (resources.engine === engine) engine = null;
  if (resources.context === context) {
    context = null;
    contextStateChangeListener = null;
  }
}

async function cleanupCurrentResources(): Promise<unknown | null> {
  const resources: AudioResources = {
    context,
    engine,
    graph: mounted,
    stateChangeListener: contextStateChangeListener,
  };
  clearCurrentResources(resources);
  return cleanupResources(resources);
}

// Serialize operations and invalidate work from a previous power cycle.
function enqueue<T>(operation: () => Promise<T>): Promise<T> {
  const run = serialOperations.then(() => operation(), () => operation());
  serialOperations = run.then(() => undefined, () => undefined);
  return run;
}

function queueControls(changes: readonly GraphControl[], token = lifecycleToken, epoch?: number): void {
  void enqueue(async () => {
    if (!isCurrent(token) || !canControl() || (epoch !== undefined && epoch !== noteEpoch)) return;
    const graph = mounted;
    if (!graph) return;
    await graph.applyControls(changes);
  }).catch((error: unknown) => {
    if (isCurrent(token)) failAudio(error);
  });
}

function isCurrent(token: number): boolean {
  return token === lifecycleToken;
}

function canControl(): boolean {
  return mounted !== null && (phase === "suspended" || phase === "running");
}

function requestPrepare(): void {
  lifecycleToken += 1;
  noteEpoch += 1;
  initializationAbort?.abort();
  const token = lifecycleToken;
  const controller = new AbortController();
  initializationAbort = controller;
  clearHeldNotes();
  phase = "preparing";
  errorText = "";
  render();
  void enqueue(() => prepare(token, controller.signal));
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
    const cleanupError = await cleanupCurrentResources();
    if (!isCurrent(token)) return;
    if (cleanupError !== null) {
      setError(cleanupError);
      return;
    }
    phase = "disposed";
    render();
  }).catch((error: unknown) => {
    if (isCurrent(token)) setError(error);
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

function failAudio(error: unknown): void {
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

function setError(error: unknown): void {
  const detail = error instanceof GraphEngineError ? `${error.code}: ${error.message}`
    : error instanceof Error ? error.message : "Unknown audio error";
  errorText = /AudioContext|AudioWorklet|Wasm|wasm/i.test(detail)
    ? `${detail} Use a browser with AudioWorklet and WebAssembly support, then retry.`
    : `${detail} Check that this example is served by Vite with its package assets, then retry.`;
  phase = "error";
  render();
}

window.addEventListener("blur", stopNotes);
document.addEventListener("visibilitychange", () => {
  if (document.hidden) stopNotes();
});
window.addEventListener("pagehide", requestDispose);
requestPrepare();
