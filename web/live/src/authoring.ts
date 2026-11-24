import {
  create_draft as createDraft,
  player_query_window as playerQueryWindow,
  check_draft_within as checkDraftWithin,
  type QueryWindowHandle,
  draft_state as draftState,
  edit_draft as editDraft,
  prepare_playback as preparePlayback,
  locate_onsets as locateOnsets,
  sound_vocabulary as soundVocabularyWire,
  takes_instruments as takesInstruments,
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

/** A drum or instrument, as people choose it. */
export type SoundEntry = Readonly<{ name: string; description: string }>;
/** The score's sounds. `instruments.default` is what a note plays without `.s`. */
export type SoundVocabulary = Readonly<{
  drums: readonly SoundEntry[];
  instruments: Readonly<{ default: SoundEntry; others: readonly SoundEntry[] }>;
}>;

export function soundVocabulary(): SoundVocabulary {
  const invalid = (): never => { throw new Error("invalid sound vocabulary"); };
  const record = (value: unknown): Record<string, unknown> =>
    typeof value === "object" && value !== null ? value as Record<string, unknown> : invalid();
  const entry = (value: unknown): SoundEntry => {
    const { name, description } = record(value);
    return typeof name === "string" && typeof description === "string" ? Object.freeze({ name, description }) : invalid();
  };
  const entries = (value: unknown): readonly SoundEntry[] =>
    Array.isArray(value) ? Object.freeze(value.map(entry)) : invalid();
  const wire = record(JSON.parse(soundVocabularyWire()));
  const instruments = record(wire.instruments);
  return Object.freeze({
    drums: entries(wire.drums),
    instruments: Object.freeze({ default: entry(instruments.default), others: entries(instruments.others) }),
  });
}

/** Whether `.s` may follow `receiver`, its `let` bindings and one expression. */
export { takesInstruments };

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
