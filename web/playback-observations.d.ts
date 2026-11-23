export type ObservationStatistics = Readonly<{ written: number; overwritten: number; busy: number; engineDropped: number }>;
export type OnsetStatistics = ObservationStatistics;
export const ONSET_CAPACITY: number;
export const ONSET_FIELDS: number;
export const ONSET_BYTES: number;
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
  statistics(): ObservationStatistics;
}
export const SIGNAL_CAPACITY: number;
export const SIGNAL_FIELDS: number;
export const SIGNAL_BYTES: number;
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
  statistics(): ObservationStatistics;
}
