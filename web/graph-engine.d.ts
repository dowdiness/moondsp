/** Waveforms accepted by oscillator nodes. */
export type Waveform = 'sine' | 'saw' | 'square' | 'triangle';

export interface ParamRef<Name extends string> {
  readonly param: Name;
}

type Scalar<Name extends string> = [Name] extends [never] ? number : number | ParamRef<Name>;

export interface OscillatorNode<Name extends string = never> {
  readonly type: 'oscillator';
  readonly waveform: Waveform;
  /** Finite frequency in Hz; validated by the host. */
  readonly frequency: Scalar<Name>;
}

export interface GainNode<Name extends string = never> {
  readonly type: 'gain';
  /** Index of the input node in Graph.nodes. */
  readonly input: number;
  readonly gain: Scalar<Name>;
}

export interface OutputNode {
  readonly type: 'output';
  readonly input: number;
}

/** Authoring data, not a Web Audio AudioNode or a compiled DSP node. */
export interface AdsrNode<Name extends string = never> {
  readonly type: 'adsr';
  readonly attackMs: Scalar<Name>;
  readonly decayMs: Scalar<Name>;
  readonly sustain: Scalar<Name>;
  readonly releaseMs: Scalar<Name>;
}

export type BiquadMode = 'lowpass' | 'highpass' | 'bandpass';

export interface BiquadNode<Name extends string = never> {
  readonly type: 'biquad';
  /** Index of the input node in Graph.nodes. */
  readonly input: number;
  readonly mode: BiquadMode;
  readonly cutoff: Scalar<Name>;
  readonly q: Scalar<Name>;
}

export interface MulNode {
  readonly type: 'mul';
  /** Index of the first input node in Graph.nodes. */
  readonly input0: number;
  /** Index of the second input node in Graph.nodes. */
  readonly input1: number;
}

/** Authoring data, not a Web Audio AudioNode or a compiled DSP node. */
export type GraphNode<Name extends string = never> =
  | OscillatorNode<Name> | AdsrNode<Name> | BiquadNode<Name> | MulNode | GainNode<Name> | OutputNode;

/** Reusable description. Bounds, finite values and graph topology are checked at runtime. */
export interface Graph<Name extends string = never, Gate extends string = never> {
  readonly nodes: readonly GraphNode<Name>[];
  readonly params?: Readonly<Record<Name, number>>;
  /** Names of reachable ADSR nodes, validated when mounted. */
  readonly gates?: Readonly<Record<Gate, number>>;
}

export interface GraphUpdate<Name extends string = never, Gate extends string = never> {
  readonly params?: Partial<Record<Name, number>>;
  readonly gates?: readonly { readonly target: Gate; readonly action: 'on' | 'off' }[];
}

declare const nodeBrand: unique symbol;
/** Opaque authoring reference. Runtime checks reject references from other builders. */
export interface GraphSignal<Kind extends string = string> {
  readonly [nodeBrand]: Kind;
}

export interface GraphBuilder<Name extends string> {
  param(name: Name): ParamRef<Name>;
  oscillator(waveform: Waveform, frequency: Scalar<Name>): GraphSignal;
  gain(input: GraphSignal, gain: Scalar<Name>): GraphSignal;
  mul(left: GraphSignal, right: GraphSignal): GraphSignal;
  biquad(input: GraphSignal, mode: BiquadMode, cutoff: Scalar<Name>, q: Scalar<Name>): GraphSignal;
  adsr(options: Omit<AdsrNode<Name>, 'type'>): GraphSignal<'adsr'>;
}

/** Synchronous, single-owner construction. Returns a frozen reusable description. */
export function Graph<Name extends string = never, Gate extends string = never>(
  params: Readonly<Record<Name, number>>,
  build: (graph: GraphBuilder<NoInfer<Name>>) => {
    readonly output: GraphSignal;
    readonly gates?: Readonly<Record<Gate, GraphSignal<'adsr'>>>;
  },
): Graph<Name, Gate>;

/** A paused, independent graph returned by GraphEngine.mount; not a constructor. */
export interface MountedGraph<Name extends string = never, Gate extends string = never> {
  /** Start/resume playback. The first successful play seals mount admission. */
  readonly play: () => Promise<void>;
  /** Freeze processing and oscillator phase. */
  readonly pause: () => Promise<void>;
  /** Apply parameters, then ordered gate actions, as one atomic render-boundary update.
   * Values preserves exact parameter keys even for prebound objects, not only literals.
   */
  readonly update: <Values extends Partial<Record<Name, number>> = Partial<Record<Name, number>>>(
    changes: Omit<GraphUpdate<Name, Gate>, 'params'> & {
      readonly params?: Values & Record<Exclude<keyof Values, Name>, never>;
    },
  ) => Promise<void>;
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
  readonly mount: <Name extends string = never, Gate extends string = never>(
    graph: Graph<NoInfer<Name>, NoInfer<Gate>> & {
      readonly params?: Readonly<Record<Name, number>>;
      readonly gates?: Readonly<Record<Gate, number>>;
    },
  ) => Promise<MountedGraph<Name, Gate>>;
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
