import {
  GraphEngine,
  GraphEngineError,
  type EngineExit,
  type GraphControl,
  type GraphDescription,
  type GraphEngineErrorCode,
  type GraphEngineWaitOptions,
  type GraphNode,
  type MountedGraph,
} from '../web/graph-engine.js';

const graph = {
  nodes: [
    { type: 'oscillator', waveform: 'triangle', frequency: 220 },
    { type: 'gain', input: 0, gain: 0.1 },
    { type: 'output', input: 1 },
  ],
} as const satisfies GraphDescription;

const extendedGraph = {
  nodes: [
    { type: 'oscillator', waveform: 'triangle', frequency: 220 },
    { type: 'biquad', input: 0, mode: 'lowpass', cutoff: 2000, q: 0.7 },
    { type: 'adsr', attackMs: 10, decayMs: 80, sustain: 0.7, releaseMs: 180 },
    { type: 'mul', input0: 1, input1: 2 },
    { type: 'gain', input: 3, gain: 0.15 },
    { type: 'output', input: 4 },
  ],
} as const satisfies GraphDescription;

const controls = [
  { type: 'setParam', node: 1, slot: 'value0', value: 0.25 },
  { type: 'gateOn', node: 2 },
] as const satisfies readonly GraphControl[];

async function consume(context: AudioContext | OfflineAudioContext, signal: AbortSignal) {
  const engine: GraphEngine = await GraphEngine({
    context, signal, wasmUrl: new URL('engine.wasm', import.meta.url), processorUrl: './processor.js',
  });
  const sound: MountedGraph = await engine.mount(extendedGraph);
  engine.output.connect(context.destination);
  const playing: Promise<void> = sound.play();
  await playing;
  await sound.pause();
  await sound.applyControls(controls);
  await sound.unmount();
  await engine.close();
  const waitOptions: GraphEngineWaitOptions = {};
  const exit: EngineExit = await engine.wait(waitOptions);
  if (exit.type === 'failed') {
    const failureCode: GraphEngineErrorCode = exit.error.code;
    void failureCode;
  }

  // @ts-expect-error The old lifecycle is not a public alias.
  engine.prepare(graph);
  // @ts-expect-error A mounted graph cannot be started with the old name.
  sound.start();
  // @ts-expect-error Engine lifecycle properties are frozen.
  engine.close = async () => {};
  // @ts-expect-error Mounted handles are type-only, not constructors.
  new MountedGraph();
}

function describe(node: GraphNode): number {
  switch (node.type) {
    case 'oscillator':
      // @ts-expect-error Oscillators do not have graph inputs.
      node.input;
      return node.frequency;
    case 'adsr': return node.sustain;
    case 'biquad': return node.cutoff;
    case 'mul': return node.input0 + node.input1;
    case 'gain': return node.gain;
    case 'output': return node.input;
  }
}

// @ts-expect-error Unknown waveforms must be rejected at the authoring boundary.
const badWaveform: GraphNode = { type: 'oscillator', waveform: 'noise', frequency: 440 };
// @ts-expect-error A gain requires an input index.
const missingInput: GraphNode = { type: 'gain', gain: 0.1 };
// @ts-expect-error Runtime controls only accept the canonical parameter slots.
const badControl: GraphControl = { type: 'setParam', node: 1, slot: 'frequency', value: 440 };
// @ts-expect-error Frequencies are numeric, not strings.
const stringFrequency: GraphNode = { type: 'oscillator', waveform: 'sine', frequency: '440' };
// @ts-expect-error A context is required.
GraphEngine({});

function handle(error: unknown) {
  if (error instanceof GraphEngineError) {
    const code: GraphEngineErrorCode = error.code;
    const index: number | undefined = error.nodeIndex;
    const cause: unknown = error.cause;
    // @ts-expect-error Abort reasons can be arbitrary values, not necessarily Errors.
    const nativeCause: Error = error.cause;
    return { code, index, cause };
  }
  throw error;
}

// @ts-expect-error Error codes form a closed public vocabulary.
new GraphEngineError('NOT_AN_ENGINE_ERROR', 'invalid');
