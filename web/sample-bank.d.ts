export type SampleLoad = { type: "sample-load"; name: string; data: Float32Array<ArrayBuffer> };
export function sampleBank(sampleRate: number): SampleLoad[];
