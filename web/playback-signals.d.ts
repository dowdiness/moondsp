export const SIGNAL_CAPACITY: number;
export const SIGNAL_FIELDS: number;
export const SIGNAL_BYTES: number;
export type SignalStatistics = Readonly<{ written: number; dropped: number }>;
export class SignalRing {
  constructor(buffer: SharedArrayBuffer);
  readonly buffer: SharedArrayBuffer;
  write(wasm: {
    player_signal_count(): number;
    player_signal_field(index: number, field: number): number;
    player_signal_clear(): void;
    player_signal_dropped(): number;
  }, engineBlockStart: number, audioBlockTime: number, sampleRate: number, generation: number): void;
  read(generation: number): number[][];
  statistics(): SignalStatistics;
}
