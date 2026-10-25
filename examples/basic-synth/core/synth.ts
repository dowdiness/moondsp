import { Graph, type GraphUpdate, type MountedGraph } from "@moondsp/browser";

export const DEFAULT_SETTINGS = { volume: 0.15, cutoff: 2_000 } as const;
export interface Settings { readonly volume: number; readonly cutoff: number }

type SynthParam = keyof Settings | "frequency";
export type SynthGraph = MountedGraph<SynthParam, "amp">;
export type SynthUpdate = GraphUpdate<SynthParam, "amp">;

export const SYNTH_GRAPH = Graph({ ...DEFAULT_SETTINGS, frequency: 261.625565 }, g => {
  const oscillator = g.oscillator("triangle", g.param("frequency"));
  const filter = g.biquad(oscillator, "lowpass", g.param("cutoff"), 0.7);
  const amp = g.adsr({ attackMs: 10, decayMs: 80, sustain: 0.7, releaseMs: 180 });
  return { output: g.gain(g.mul(filter, amp), g.param("volume")), gates: { amp } };
});

export function noteOn(midi: number): SynthUpdate {
  return {
    params: { frequency: 440 * 2 ** ((midi - 69) / 12) },
    gates: [{ target: "amp", action: "on" }],
  };
}

export function noteOff(nextMidi: number | null = null): SynthUpdate {
  return nextMidi === null
    ? { gates: [{ target: "amp", action: "off" }] }
    : {
        params: { frequency: 440 * 2 ** ((nextMidi - 69) / 12) },
        gates: [{ target: "amp", action: "off" }, { target: "amp", action: "on" }],
      };
}
