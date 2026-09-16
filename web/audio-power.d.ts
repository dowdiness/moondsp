import type { GraphEngine } from "./graph-engine.js";

export interface AudioPowerOptions {
  /** Options for the new realtime AudioContext; existing contexts cannot be adopted. */
  readonly contextOptions?: AudioContextOptions;
  readonly wasmUrl?: string | URL;
  readonly processorUrl?: string | URL;
  /**
   * Engine close-acknowledgement deadline in milliseconds (default 5000).
   * Not a deadline for setup, AudioContext.close(), or total cleanup.
   */
  readonly closeTimeoutMs?: number;
}

export interface AudioSetup {
  /** Borrowed, package-owned context. Observe it; leave resume/close to PoweredAudio. */
  readonly context: AudioContext;
  /** Borrowed engine for graph setup/control; the package owns connection and close. */
  readonly engine: GraphEngine;
  /**
   * Aborted as soon as this generation starts turning off, including on failure.
   * Pass to cancellable application work and check after uncancellable awaits.
   * Turning off discards late setup results; it cannot forcibly stop your callback
   * or undo application side effects. Application-created resources remain yours.
   */
  readonly powerOff: AbortSignal;
}

/** Retained termination reason, not proof that cleanup has finished. */
export type AudioEnd =
  | { readonly reason: "turnedOff" }
  | { readonly reason: "failed"; readonly error: Error };

/** One power cycle. Retain this handle: its methods cannot act on a replacement. */
export interface PoweredAudio<Value> {
  /**
   * Borrowed, package-owned context, available immediately for state observation.
   * readonly prevents replacing this reference, not calling native mutators.
   * Use resume()/turnOff() rather than managing the context directly.
   */
  readonly context: AudioContext;
  /**
   * Resolves with the exact setup return value after final resume and connection.
   * Rejects AbortError if clean turn-off occurs before readiness, or the startup
   * failure otherwise. An already-settled ready promise never changes.
   * Observe rejection even if ended is your single source of failure reporting.
   */
  readonly ready: Promise<Value>;
  /**
   * Always resolves once to the same frozen AudioEnd; late observers get it too.
   * A primary failure is published before cleanup, which cannot replace it.
   * Without a primary failure, resolves after cleanup: turnedOff on success,
   * failed on cleanup error. Await turnOff() to join cleanup in either case.
   */
  readonly ended: Promise<AudioEnd>;
  /**
   * Restore a ready generation after suspension/interruption. Call directly from
   * a user gesture: native resume is invoked before this method returns.
   * Already running resolves without native resume; an in-flight restore shares
   * one promise. Rejects InvalidStateError before readiness or after retirement.
   * Turning off during restore rejects its promise without reviving the generation.
   */
  readonly resume: () => Promise<void>;
  /**
   * Begin retiring only this generation synchronously, aborting its setup signal
   * and allowing a new turnOn(). Concurrent/late calls return the same promise.
   * Joins package-owned cleanup without awaiting arbitrary pending setup work.
   * Attempts all applicable cleanup steps; rejects with the first cleanup error.
   * A prior startup/processor failure stays in ended, not in this cleanup result.
   */
  readonly turnOff: () => Promise<void>;
}

/** Application-scoped owner; keep one instance across repeated power cycles. */
export interface AudioPower {
  /**
   * Call directly from a user gesture, before any await. Context construction and
   * its first native resume happen before this method returns the generation.
   * Setup runs while suspended: mount/configure graphs and call play() yourself.
   * The package performs final resume/connection before ready resolves.
   * Replacement context admission is immediate; engine creation waits for all
   * earlier retirements on this owner. Different AudioPower owners are independent.
   *
   * @throws TypeError if setupAudio is not callable.
   * @throws InvalidStateError if this owner already has a non-retiring generation.
   * @throws Any native AudioContext construction error.
   * Once a handle is returned, startup failures use ready/ended, not a sync throw.
   */
  readonly turnOn: <Value>(
    setupAudio: (audio: AudioSetup) => Promise<Value>,
  ) => PoweredAudio<Value>;
}

/** Create an independent owner without allocating an AudioContext or engine. */
export function AudioPower(
  options?: AudioPowerOptions,
): AudioPower;
