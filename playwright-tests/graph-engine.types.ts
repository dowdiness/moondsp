import {
  createGraphEngine,
  GraphEngineError,
  type GraphDescription,
  type GraphEngine,
  type GraphEngineErrorCode,
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

async function consume(context: AudioContext | OfflineAudioContext, signal: AbortSignal) {
  const engine: GraphEngine = await createGraphEngine({
    context, signal, wasmUrl: new URL('engine.wasm', import.meta.url), processorUrl: './processor.js',
  });
  const sound: MountedGraph = await engine.mount(graph);
  engine.output.connect(context.destination);
  const playing: Promise<void> = sound.play();
  await playing;
  await sound.pause();
  await sound.unmount();
  await engine.close();

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
    case 'gain': return node.gain;
    case 'output': return node.input;
  }
}

// @ts-expect-error Unknown waveforms must be rejected at the authoring boundary.
const badWaveform: GraphNode = { type: 'oscillator', waveform: 'noise', frequency: 440 };
// @ts-expect-error A gain requires an input index.
const missingInput: GraphNode = { type: 'gain', gain: 0.1 };
// @ts-expect-error Frequencies are numeric, not strings.
const stringFrequency: GraphNode = { type: 'oscillator', waveform: 'sine', frequency: '440' };
// @ts-expect-error A context is required.
createGraphEngine({});

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
