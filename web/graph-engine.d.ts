/** Waveforms accepted by oscillator nodes. */
export type Waveform = 'sine' | 'saw' | 'square' | 'triangle';

export interface OscillatorNode {
  readonly type: 'oscillator';
  readonly waveform: Waveform;
  /** Finite frequency in Hz; validated by the host. */
  readonly frequency: number;
}

export interface GainNode {
  readonly type: 'gain';
  /** Index of the input node in GraphDescription.nodes. */
  readonly input: number;
  readonly gain: number;
}

export interface OutputNode {
  readonly type: 'output';
  readonly input: number;
}

/** Authoring data, not a Web Audio AudioNode or a compiled DSP node. */
export interface AdsrNode {
  readonly type: 'adsr';
  readonly attackMs: number;
  readonly decayMs: number;
  readonly sustain: number;
  readonly releaseMs: number;
}

export type BiquadMode = 'lowpass' | 'highpass' | 'bandpass';

export interface BiquadNode {
  readonly type: 'biquad';
  /** Index of the input node in GraphDescription.nodes. */
  readonly input: number;
  readonly mode: BiquadMode;
  readonly cutoff: number;
  readonly q: number;
}

export interface MulNode {
  readonly type: 'mul';
  /** Index of the first input node in GraphDescription.nodes. */
  readonly input0: number;
  /** Index of the second input node in GraphDescription.nodes. */
  readonly input1: number;
}

/** Authoring data, not a Web Audio AudioNode or a compiled DSP node. */
export type GraphNode = OscillatorNode | AdsrNode | BiquadNode | MulNode | GainNode | OutputNode;

/** Reusable description. Bounds, finite values and graph topology are checked at runtime. */
export interface GraphDescription {
  readonly nodes: readonly GraphNode[];
}

export type GraphControl =
  | {
      readonly type: 'setParam';
      readonly node: number;
      readonly slot: 'value0' | 'value1' | 'value2' | 'value3' | 'delaySamples';
      readonly value: number;
    }
  | {
      readonly type: 'gateOn' | 'gateOff';
      readonly node: number;
    };

/** A paused, independent graph returned by GraphEngine.mount; not a constructor. */
export interface MountedGraph {
  /** Start/resume playback. The first successful play seals mount admission. */
  readonly play: () => Promise<void>;
  /** Freeze processing and oscillator phase. */
  readonly pause: () => Promise<void>;
  /** Apply a non-empty, atomically validated batch at a render boundary. */
  readonly applyControls: (controls: readonly GraphControl[]) => Promise<void>;
  /** Permanently detach. Concurrent/repeated calls share the same completion. */
  readonly unmount: () => Promise<void>;
}

export type EngineExit =
  | { readonly type: 'closed' }
  | { readonly type: 'failed'; readonly error: GraphEngineError };

export interface GraphEngineWaitOptions {
  /** Cancels only this wait with AbortError; the engine and other waiters continue. */
  readonly signal?: AbortSignal;
}

export interface GraphEngine {
  /** Mono output; connecting it is the caller's responsibility. */
  readonly output: AudioWorkletNode;
  /** Compile and register a paused graph, before playback in a suspended context. */
  readonly mount: (graph: GraphDescription) => Promise<MountedGraph>;
  /** Observe retained exit without stopping the engine. Pre-aborted signals reject even after exit. */
  readonly wait: (options?: GraphEngineWaitOptions) => Promise<EngineExit>;
  /** Idempotent bounded shutdown; never closes the caller-owned context. */
  readonly close: () => Promise<void>;
}

export interface GraphEngineOptions {
  /** Must be suspended during creation and mounting. */
  readonly context: AudioContext | OfflineAudioContext;
  readonly wasmUrl?: string | URL;
  readonly processorUrl?: string | URL;
  /** Cancels creation only; aborting after success does not close the engine. */
  readonly signal?: AbortSignal;
  /** Close acknowledgement deadline in ms: >0 and <=2147483647; defaults to 5000. */
  readonly closeTimeoutMs?: number;
}

export type GraphEngineErrorCode =
  | 'INVALID_STATE'
  | 'LOAD_FAILED'
  | 'INITIALIZATION_FAILED'
  | 'ABORTED'
  | 'ENGINE_CLOSED'
  | 'PROCESSOR_FAILED'
  | 'MOUNT_CLOSED'
  | 'MOUNT_REJECTED'
  | 'INVALID_GRAPH'
  | 'INVALID_CONTROL'
  | 'INVALID_HANDLE'
  | 'INVALID_REQUEST'
  | 'HOST_ERROR';

/** Structured engine error. Not every native transport exception is wrapped. */
export class GraphEngineError extends Error {
  constructor(code: GraphEngineErrorCode, message: string, nodeIndex?: number);
  code: GraphEngineErrorCode;
  /** Present when a decoding failure identifies a node. */
  nodeIndex?: number;
  /** Original initialization/cleanup exception or arbitrary AbortSignal.reason. */
  cause?: unknown;
}

/** Create a mono engine in a caller-owned context. Graph handles start paused. */
export function GraphEngine(options: GraphEngineOptions): Promise<GraphEngine>;
