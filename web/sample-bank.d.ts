export type SampleLoad = { type: "sample-load"; name: string; rootPitch: number; data: Float32Array<ArrayBuffer> };
export function sampleBank(sampleRate: number): SampleLoad[];
