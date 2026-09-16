/// <reference lib="esnext.disposable" />
import { AudioPower, type AudioSetup, type AudioEnd, type PoweredAudio } from '../web/audio-power.js';
import type { GraphEngine, MountedGraph } from '../web/graph-engine.js';

const power: AudioPower = AudioPower({
  contextOptions: { sampleRate: 48000 },
  wasmUrl: new URL('engine.wasm', import.meta.url),
  processorUrl: './processor.js',
  closeTimeoutMs: 1000,
});
const independent: AudioPower = AudioPower();

const powered = power.turnOn(async (setup: AudioSetup) => {
  const context: AudioContext = setup.context;
  const engine: GraphEngine = setup.engine;
  const signal: AbortSignal = setup.powerOff;
  signal.throwIfAborted();
  const graph = await engine.mount({ nodes: [
    { type: 'oscillator', waveform: 'sine', frequency: 220 },
    { type: 'gain', input: 0, gain: 0.1 },
    { type: 'output', input: 1 },
  ] });
  await graph.play();
  void context;
  return { graph, name: 'instrument' as const };
});
const exact: PoweredAudio<{ graph: MountedGraph; name: 'instrument' }> = powered;
const ready: Promise<{ graph: MountedGraph; name: 'instrument' }> = powered.ready;
const ended: Promise<AudioEnd> = powered.ended;
const resumed: Promise<void> = powered.resume();
const stopped: Promise<void> = powered.turnOff();
const context: AudioContext = powered.context;
const other: PoweredAudio<number> = independent.turnOn(async () => 42);

async function inspectValue() {
  const result = await powered.ready;
  const name: 'instrument' = result.name;
  // @ts-expect-error Setup inference must not widen the return value to any.
  const invalid: number = result.name;
  void name;
  const end = await powered.ended;
  if (end.reason === 'failed') {
    const error: Error = end.error;
    void error;
  } else {
    // @ts-expect-error A clean turn-off has no error.
    end.error;
  }
}

// @ts-expect-error AudioPower owns its context, not caller-provided contexts.
AudioPower({ context: new AudioContext() });
// @ts-expect-error Offline rendering uses the root GraphEngine entry point.
AudioPower({ context: new OfflineAudioContext(1, 128, 48000) });
// @ts-expect-error Setup is required.
power.turnOn();
// @ts-expect-error Public methods are readonly.
power.turnOn = independent.turnOn;
// @ts-expect-error Context is readonly.
powered.context = new AudioContext();
// @ts-expect-error Readiness is readonly.
powered.ready = ready;
// @ts-expect-error End observation is readonly.
powered.ended = ended;
// @ts-expect-error Resume is readonly.
powered.resume = async () => {};
// @ts-expect-error Turn-off is readonly.
powered.turnOff = async () => {};
// @ts-expect-error End is a retained promise, not a wait method.
powered.wait();
// @ts-expect-error No builder setters are exposed.
power.withContext(context);
// @ts-expect-error No async-dispose surface is exposed.
powered[Symbol.asyncDispose]();
