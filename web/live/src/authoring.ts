import {
  create_draft as createDraft,
  player_query_window as playerQueryWindow,
  check_draft_within as checkDraftWithin,
  type QueryWindowHandle,
  draft_state as draftState,
  edit_draft as editDraft,
  prepare_playback as preparePlayback,
  locate_onsets as locateOnsets,
  vocabulary as vocabularyWire,
  methods_after as methodsAfterWire,
  type DraftHandle,
} from "./generated/authoring.js";

import type { AudioFormat } from "./playback-protocol";
import { decodeDraftVersion, type DraftVersion } from "./draft-version";

/** Why the draft cannot play, as the parser decided it. */
export type SourceProblem =
  /** The code is wrong at `at`, a UTF-16 offset into the draft's text. */
  | Readonly<{ kind: "mistake"; at: number; message: string }>
  /** The code is valid but more than playback can afford. */
  | Readonly<{ kind: "over-limit"; message: string }>
  /** The compiler broke its own invariant; the author cannot fix it. */
  | Readonly<{ kind: "internal"; message: string }>;
export type DraftState = Readonly<{ text: string; version: DraftVersion; problem: SourceProblem | null }>;
export type DraftEdit = Readonly<{ from: number; to: number; inserted: string }>;
export type LocatedOnset = Readonly<{
  from: number;
  to: number;
  references: readonly Readonly<{ from: number; to: number }>[];
  notation: Readonly<{ from: number; to: number; start: number; pitch: number | null }> | null;
}>;

/** A name written on its own: a drum, an instrument, or a signal. */
export type Term = Readonly<{ name: string; description: string }>;
/** Where a call is written. */
export type Position = "declaration" | "arrangement" | "pattern" | "song-item" | "after-song" | "after-pattern" | "callback" | "after-signal";
/** What completion offers in an argument; `number` and `text` offer nothing. */
export type ArgumentKind = "drums" | "instruments" | "callback" | "control" | "pattern" | "song-item" | "number" | "text";
export type Argument = Readonly<{ name: string; kind: ArgumentKind }>;
/** A name written with arguments: required, then optional, then any number of `repeated`. */
export type Call = Readonly<{
  name: string;
  position: Position;
  description: string;
  required: readonly Argument[];
  optional: readonly Argument[];
  repeated: Argument | null;
}>;
/** Every name a score writes (ADR-0023). `instruments.default` is what a note plays without `.s`. */
export type Vocabulary = Readonly<{
  drums: readonly Term[];
  instruments: Readonly<{ default: Term; others: readonly Term[] }>;
  /** Recorded samples, accepted by both `s("…")` and `.s("…")` (ADR-0026). */
  samples: readonly Term[];
  signals: readonly Term[];
  calls: readonly Call[];
}>;

const POSITIONS: readonly Position[] = ["declaration", "arrangement", "pattern", "song-item", "after-song", "after-pattern", "callback", "after-signal"];
const ARGUMENT_KINDS: readonly ArgumentKind[] = ["drums", "instruments", "callback", "control", "pattern", "song-item", "number", "text"];

const invalidVocabulary = (): never => { throw new Error("invalid vocabulary"); };
const record = (value: unknown): Record<string, unknown> =>
  typeof value === "object" && value !== null ? value as Record<string, unknown> : invalidVocabulary();
const list = <T>(value: unknown, item: (value: unknown) => T): readonly T[] =>
  Array.isArray(value) ? Object.freeze(value.map(item)) : invalidVocabulary();
const text = (value: unknown): string => typeof value === "string" ? value : invalidVocabulary();
const oneOf = <T extends string>(options: readonly T[]) => (value: unknown): T =>
  options.find(option => option === value) ?? invalidVocabulary();

function decodeTerm(value: unknown): Term {
  const { name, description } = record(value);
  return Object.freeze({ name: text(name), description: text(description) });
}

function decodeArgument(value: unknown): Argument {
  const { name, kind } = record(value);
  return Object.freeze({ name: text(name), kind: oneOf(ARGUMENT_KINDS)(kind) });
}

function decodeCall(value: unknown): Call {
  const { name, position, description, required, optional, repeated } = record(value);
  return Object.freeze({
    name: text(name),
    position: oneOf(POSITIONS)(position),
    description: text(description),
    required: list(required, decodeArgument),
    optional: list(optional, decodeArgument),
    repeated: repeated === null ? null : decodeArgument(repeated),
  });
}

/** The score's vocabulary, read once when the score tools load. */
export function vocabulary(): Vocabulary {
  const wire = record(JSON.parse(vocabularyWire()));
  const instruments = record(wire.instruments);
  return Object.freeze({
    drums: list(wire.drums, decodeTerm),
    instruments: Object.freeze({ default: decodeTerm(instruments.default), others: list(instruments.others, decodeTerm) }),
    samples: list(wire.samples, decodeTerm),
    signals: list(wire.signals, decodeTerm),
    calls: list(wire.calls, decodeCall),
  });
}

/** The methods that may follow `receiver`, its `let` bindings and one expression. */
export function methodsAfter(receiver: string): readonly Call[] {
  return list(JSON.parse(methodsAfterWire(receiver)), decodeCall);
}

function decodeProblem(raw: unknown, text: string): SourceProblem | null | undefined {
  if (raw === null) return null;
  if (typeof raw !== "object") return undefined;
  const { kind, at, message } = raw as Record<string, unknown>;
  if (typeof message !== "string") return undefined;
  if (kind === "mistake") {
    return Number.isSafeInteger(at) && Number(at) >= 0 && Number(at) <= text.length
      ? Object.freeze({ kind, at: Number(at), message }) : undefined;
  }
  return kind === "over-limit" || kind === "internal" ? Object.freeze({ kind, message }) : undefined;
}

function decodeState(raw: { text: unknown; version: unknown; problem: unknown }): DraftState {
  const version = decodeDraftVersion(raw.version);
  const text = raw.text;
  const problem = typeof text === "string" ? decodeProblem(raw.problem, text) : undefined;
  if (!version || typeof text !== "string" || problem === undefined) throw new Error("invalid authoring state");
  return Object.freeze({ text, version, problem });
}


/** The window a player queries over; only `playerWindow` can create one. */
export type PlayerWindow = Readonly<{ handle: QueryWindowHandle }>;

/** The window of a player running in `format`, or why no player can run it. */
export function playerWindow(format: AudioFormat): { kind: "runs"; window: PlayerWindow } | { kind: "unsupported"; message: string } {
  let outcome: { kind: "runs"; window: PlayerWindow } | { kind: "unsupported"; message: string } | undefined;
  playerQueryWindow(format.sampleRate, format.blockSize,
    handle => { outcome = { kind: "runs", window: Object.freeze({ handle }) }; },
    message => { outcome = { kind: "unsupported", message }; });
  if (!outcome) throw new Error("authoring did not answer for the player format");
  return outcome;
}

let inputFromDraft: (wire: string, state: DraftState) => PlaybackInput;

/** Immutable capability; only Draft preparation can create it. */
export class PlaybackInput {
  private constructor(private readonly encoded: string, readonly source: string, readonly draftVersion: DraftVersion) {
    Object.freeze(this);
  }
  get wire(): string { return this.encoded; }
  static {
    inputFromDraft = (wire, state) => new PlaybackInput(wire, state.text, state.version);
  }
}

/** Main-thread ownership, independent of AudioContext and playback-run lifetime. */
export class Draft {
  private readonly handle: DraftHandle;
  constructor(text: string) {
    let handle: DraftHandle | undefined;
    createDraft(text, created => { handle = created; }, message => { throw new Error(message); });
    if (!handle) throw new Error("authoring constructor did not return a Draft");
    this.handle = handle;
  }
  state(): DraftState {
    return decodeState(JSON.parse(draftState(this.handle)));
  }
  edit(transaction: Readonly<{ base: DraftVersion; edits: readonly DraftEdit[] }>): DraftState {
    const result = JSON.parse(editDraft(this.handle, JSON.stringify(transaction)));
    if (!result.ok) throw new Error(result.message);
    return decodeState(result.state);
  }
  /** From now on, also report what a player querying over `window` would refuse, before it is asked to play. */
  checkWithin(window: PlayerWindow): DraftState {
    return decodeState(JSON.parse(checkDraftWithin(this.handle, window.handle)));
  }
  prepare(): PlaybackInput {
    const result = JSON.parse(preparePlayback(this.handle));
    if (!result.ok) throw new Error(result.message);
    return inputFromDraft(result.input, this.state());
  }
  locateOnsets(rows: readonly (readonly number[])[]): readonly (LocatedOnset | null)[] {
    const result: unknown = JSON.parse(locateOnsets(this.handle, JSON.stringify(rows)));
    if (!Array.isArray(result) || result.length !== rows.length) throw new Error("Invalid playback origin lookup");
    const range = (value: unknown): boolean => {
      if (typeof value !== "object" || value === null) return false;
      const item = value as Record<string, unknown>;
      return Number.isSafeInteger(item.from) && Number.isSafeInteger(item.to) &&
        Number(item.from) >= 0 && Number(item.to) > Number(item.from);
    };
    for (const item of result) {
      if (item === null) continue;
      if (!range(item) || !Array.isArray(item.references) || !item.references.every(range) ||
        (item.notation !== null && (!range(item.notation) ||
          !Number.isFinite(item.notation.start) ||
          (item.notation.pitch !== null && !Number.isFinite(item.notation.pitch))))) {
        throw new Error("Invalid playback origin location");
      }
    }
    return result as (LocatedOnset | null)[];
  }

}
