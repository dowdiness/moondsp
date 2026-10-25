import {
  GraphEngine,
  Graph,
  GraphEngineError,
  type EngineExit,
  type GraphEngineErrorCode,
  type GraphEngineWaitOptions,
  type MountedGraph,
} from '../web/graph-engine.js';

const graph = Graph({}, g => ({ output: g.gain(g.oscillator('triangle', 220), 0.1) }));

const extendedGraph = Graph({}, g => {
  const filtered = g.biquad(g.oscillator('triangle', 220), 'lowpass', 2000, 0.7);
  const envelope = g.adsr({ attackMs: 10, decayMs: 80, sustain: 0.7, releaseMs: 180 });
  return { output: g.gain(g.mul(filtered, envelope), 0.15) };
});

const parameterizedGraph = Graph({ volume: 0.2, cutoff: 1800 }, g => ({
  output: g.gain(g.biquad(g.oscillator('sine', 220), 'lowpass', g.param('cutoff'), 0.7), g.param('volume')),
})) satisfies Graph<'volume' | 'cutoff'>;

// @ts-expect-error Graphs are opaque, not structural wire descriptions.
const rawGraph: Graph = { nodes: [] };
// @ts-expect-error Empty objects cannot counterfeit graph tokens.
const emptyGraph: Graph = {};
// @ts-expect-error Node arrays are private implementation details.
graph.nodes;
// @ts-expect-error Parameter defaults are not exposed on the token.
parameterizedGraph.params;
// @ts-expect-error Gate metadata is hidden on the token.
graph.gates;

async function consume(context: AudioContext | OfflineAudioContext, signal: AbortSignal) {
  const engine: GraphEngine = await GraphEngine({
    context, signal, wasmUrl: new URL('engine.wasm', import.meta.url), processorUrl: './processor.js',
  });
  const sound: MountedGraph = await engine.mount(extendedGraph);
  const parameterized = await engine.mount(parameterizedGraph);
  await parameterized.update({ params: { volume: 0.3 } });
  await parameterized.update({});
  // @ts-expect-error Named parameter values must be numbers.
  await parameterized.update({ params: { volume: 'loud' } });
  // @ts-expect-error Fresh extra parameter keys are rejected.
  await parameterized.update({ params: { unknown: 1 } });
  const knownValues: { volume: number } = { volume: 0.4 };
  await parameterized.update({ params: knownValues });
  const extraValues = { volume: 0.4, typo: 1 };
  // @ts-expect-error Prebound records must not bypass exact parameter keys.
  await parameterized.update({ params: extraValues });
  // @ts-expect-error Omission is supported; explicit undefined is not.
  await parameterized.update({ params: { volume: undefined } });
  const plain = await engine.mount(graph);
  await plain.update({});
  // @ts-expect-error Numeric-only graphs do not acquire parameter names.
  await plain.update({ params: { volume: 0.2 } });
  const rawDescription = {
    params: { volume: 0.2 },
    nodes: [
      { type: 'oscillator', waveform: 'sine', frequency: 220 },
      { type: 'gain', input: 0, gain: { param: 'volume' } },
      { type: 'output', input: 1 },
    ],
  } as const;
  // @ts-expect-error Even prebound, well-shaped wire descriptions are not graph tokens.
  await engine.mount(rawDescription);
  // @ts-expect-error Mount does not admit empty structural counterfeits.
  await engine.mount({});
  const dynamic: Graph<string> = parameterizedGraph;
  const dynamicValues: Record<string, number> = { volume: 0.2 };
  await (await engine.mount(dynamic)).update({ params: dynamicValues });
  const built = Graph({ pitch: 220 }, g => {
    const oscillator = g.oscillator('sine', g.param('pitch'));
    const amp = g.adsr({ attackMs: 0, decayMs: 0, sustain: 1, releaseMs: 10 });
    // @ts-expect-error Numeric indices are not builder references.
    g.gain(0, 0.1);
    // @ts-expect-error Parameter names come from defaults, not their usages.
    g.param('typo');
    return { output: g.mul(oscillator, amp), gates: { amp } };
  });
  const instrument = await engine.mount(built);
  await instrument.update({ params: { pitch: 440 }, gates: [{ target: 'amp', action: 'on' }] });
  // @ts-expect-error Gate names come from graph declarations.
  await instrument.update({ gates: [{ target: 'other', action: 'off' }] });
  // @ts-expect-error Parameter names survive builder and mount inference.
  await instrument.update({ params: { other: 1 } });
  // @ts-expect-error Graphs without gates cannot receive gate actions.
  await plain.update({ gates: [{ target: 'amp', action: 'on' }] });
  // @ts-expect-error Async construction cannot return a graph.
  Graph({}, async g => ({ output: g.oscillator('sine', 220) }));
  // @ts-expect-error A gate must refer to an ADSR, not an oscillator.
  Graph({}, g => { const osc = g.oscillator('sine', 220); return { output: osc, gates: { amp: osc } }; });
  // @ts-expect-error The replaced update API is not retained as an alias.
  instrument.setParams({ pitch: 440 });
  const connected: AudioNode = engine.connect(context.destination);
  const indexed: AudioNode = engine.connect(context.destination, 0, 0);
  const gain = context.createGain();
  const paramConnected: void = engine.connect(gain.gain);
  const indexedParam: void = engine.connect(gain.gain, 0);
  const connect: AudioNode['connect'] = engine.connect;
  const disconnect: AudioNode['disconnect'] = engine.disconnect;
  engine.disconnect();
  engine.disconnect(0);
  engine.disconnect(gain);
  engine.disconnect(gain, 0);
  engine.disconnect(gain, 0, 0);
  engine.disconnect(gain.gain);
  engine.disconnect(gain.gain, 0);
  void [connected, indexed, paramConnected, indexedParam, connect, disconnect];
  // @ts-expect-error The native worklet is private.
  engine.output;
  // @ts-expect-error Raw transport is not part of the public API.
  engine.port;
  // @ts-expect-error AudioParam routing has no input index.
  engine.connect(gain.gain, 0, 0);
  const playing: Promise<void> = sound.play();
  await playing;
  await sound.pause();
  await sound.update({});
  // @ts-expect-error Raw numeric controls are not a public API.
  sound.applyControls([]);
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

// @ts-expect-error Unknown waveforms must be rejected at the authoring boundary.
Graph({}, g => ({ output: g.oscillator('noise', 440) }));
// @ts-expect-error A gain requires a signal input and a value.
Graph({}, g => ({ output: g.gain(0.1) }));
// @ts-expect-error Frequencies are numeric, not strings.
Graph({}, g => ({ output: g.oscillator('sine', '440') }));
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
Graph({ volume: 0.2 }, g => ({
  // @ts-expect-error Parameter references must use a declared name.
  output: g.gain(g.oscillator('sine', 220), g.param('loudness')),
}));

// @ts-expect-error Error codes form a closed public vocabulary.
new GraphEngineError('NOT_AN_ENGINE_ERROR', 'invalid');
