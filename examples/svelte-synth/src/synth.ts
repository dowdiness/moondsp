import type { GraphDescription, GraphControl } from "@moondsp/browser";

const OSCILLATOR_NODE = 0;
const FILTER_NODE = 1;
const ADSR_NODE = 2;
const GAIN_NODE = 4;

export const DEFAULT_SETTINGS = { volume: 0.15, cutoff: 2_000 } as const;
export interface Settings { readonly volume: number; readonly cutoff: number }

export const SYNTH_GRAPH = {
  params: DEFAULT_SETTINGS,
  nodes: [
    { type: "oscillator", waveform: "triangle", frequency: 261.625565 },
    { type: "biquad", input: OSCILLATOR_NODE, mode: "lowpass", cutoff: { param: "cutoff" }, q: 0.7 },
    { type: "adsr", attackMs: 10, decayMs: 80, sustain: 0.7, releaseMs: 180 },
    { type: "mul", input0: FILTER_NODE, input1: ADSR_NODE },
    { type: "gain", input: 3, gain: { param: "volume" } },
    { type: "output", input: GAIN_NODE },
  ],
} as const satisfies GraphDescription<keyof Settings>;

export function noteOn(midi: number): GraphControl[] {
  return [
    { type: "setParam", node: OSCILLATOR_NODE, slot: "value0", value: 440 * 2 ** ((midi - 69) / 12) },
    { type: "gateOn", node: ADSR_NODE },
  ];
}

export function noteOff(nextMidi: number | null = null): GraphControl[] {
  const gateOff: GraphControl = { type: "gateOff", node: ADSR_NODE };
  return nextMidi === null ? [gateOff] : [gateOff, ...noteOn(nextMidi)];
}
