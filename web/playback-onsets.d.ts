export const ONSET_CAPACITY: number;
export const ONSET_FIELDS: number;
export const ONSET_BYTES: number;
export type OnsetStatistics = Readonly<{ written: number; overwritten: number; busy: number; engineDropped: number }>;
export class OnsetRing {
  constructor(buffer: SharedArrayBuffer);
  readonly buffer: SharedArrayBuffer;
  write(wasm: {
    player_onset_count(): number;
    player_onset_field(index: number, field: number): number;
    player_onset_clear(): void;
    player_onset_dropped(): number;
  }, engineBlockStart: number, audioBlockTime: number, sampleRate: number, generation: number): void;
  read(generation: number): number[][];
  statistics(): OnsetStatistics;
}
