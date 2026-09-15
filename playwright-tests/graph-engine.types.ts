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

const parameterizedGraph = {
  params: { volume: 0.2, cutoff: 1800 },
  nodes: [
    { type: 'oscillator', waveform: 'sine', frequency: 220 },
    { type: 'biquad', input: 0, mode: 'lowpass', cutoff: { param: 'cutoff' }, q: 0.7 },
    { type: 'gain', input: 1, gain: { param: 'volume' } },
    { type: 'output', input: 2 },
  ],
} as const satisfies GraphDescription<'volume' | 'cutoff'>;

const controls = [
  { type: 'setParam', node: 1, slot: 'value0', value: 0.25 },
  { type: 'gateOn', node: 2 },
] as const satisfies readonly GraphControl[];

async function consume(context: AudioContext | OfflineAudioContext, signal: AbortSignal) {
  const engine: GraphEngine = await GraphEngine({
    context, signal, wasmUrl: new URL('engine.wasm', import.meta.url), processorUrl: './processor.js',
  });
  const sound: MountedGraph = await engine.mount(extendedGraph);
  const parameterized = await engine.mount(parameterizedGraph);
  await parameterized.setParams({ volume: 0.3 });
  await parameterized.setParams({});
  // @ts-expect-error Named parameter values must be numbers.
  await parameterized.setParams({ volume: 'loud' });
  // @ts-expect-error Fresh extra parameter keys are rejected.
  await parameterized.setParams({ unknown: 1 });
  const knownValues: { volume: number } = { volume: 0.4 };
  await parameterized.setParams(knownValues);
  const extraValues = { volume: 0.4, typo: 1 };
  // @ts-expect-error Prebound records must not bypass exact parameter keys.
  await parameterized.setParams(extraValues);
  // @ts-expect-error Omission is supported; explicit undefined is not.
  await parameterized.setParams({ volume: undefined });
  const plain = await engine.mount(graph);
  await plain.setParams({});
  // @ts-expect-error Numeric-only graphs do not acquire parameter names.
  await plain.setParams({ volume: 0.2 });
  const wrongReference = {
    params: { volume: 0.2 },
    nodes: [{ type: 'gain', input: 0, gain: { param: 'typo' } }],
  } as const;
  // @ts-expect-error References must not widen the keys inferred from defaults.
  await engine.mount(wrongReference);
  const undeclaredReference = { nodes: [{ type: 'gain', input: 0, gain: { param: 'volume' } }] } as const;
  // @ts-expect-error References alone cannot declare parameters.
  await engine.mount(undeclaredReference);
  const dynamic: GraphDescription<string> = parameterizedGraph;
  const dynamicValues: Record<string, number> = { volume: 0.2 };
  await (await engine.mount(dynamic)).setParams(dynamicValues);
  engine.output.connect(context.destination);
  const playing: Promise<void> = sound.play();
  await playing;
  await sound.pause();
  await sound.applyControls(controls);
  await sound.unmount();
  await parameterized.unmount();
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
const missingParameterRef = {
  params: { volume: 0.2 },
  // @ts-expect-error Parameter references must use a declared name.
  nodes: [{ type: 'gain', input: 0, gain: { param: 'loudness' } }],
} as const satisfies GraphDescription<'volume'>;

// @ts-expect-error Error codes form a closed public vocabulary.
new GraphEngineError('NOT_AN_ENGINE_ERROR', 'invalid');
