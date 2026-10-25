/** Waveforms accepted by oscillator nodes. */
export type Waveform = 'sine' | 'saw' | 'square' | 'triangle';

export interface ParamRef<Name extends string> {
  readonly param: Name;
}

type Scalar<Name extends string> = [Name] extends [never] ? number : number | ParamRef<Name>;

export type BiquadMode = 'lowpass' | 'highpass' | 'bandpass';

declare const graphBrand: unique symbol;
/** Opaque reusable graph created by Graph() in this module; not serializable. */
export interface Graph<Name extends string = never, Gate extends string = never> {
  readonly [graphBrand]: { readonly params: Name; readonly gates: Gate };
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
  adsr(options: {
    readonly attackMs: Scalar<Name>;
    readonly decayMs: Scalar<Name>;
    readonly sustain: Scalar<Name>;
    readonly releaseMs: Scalar<Name>;
  }): GraphSignal<'adsr'>;
}

/** Synchronous, single-owner construction. Returns a frozen opaque graph. */
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
  /** Connect the mono output using native overloads/returns. Throws synchronously after closing/failure. */
  readonly connect: AudioNode['connect'];
  /** Native disconnection, including targeted removal. Available after close for cleanup; does not pause. */
  readonly disconnect: AudioNode['disconnect'];
  /** Compile and register a paused graph, before playback in a suspended context. */
  readonly mount: <Name extends string = never, Gate extends string = never>(
    graph: Graph<Name, Gate>,
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
