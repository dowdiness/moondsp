import {
  create_draft as createDraft,
  player_query_window as playerQueryWindow,
  check_draft_within as checkDraftWithin,
  type QueryWindowHandle,
  draft_state as draftState,
  edit_draft as editDraft,
  prepare_playback as preparePlayback,
  locate_onsets as locateOnsets,
  type DraftHandle,
} from "./generated/authoring.js";

import type { AudioFormat } from "./playback-protocol";
import { decodeDraftVersion, type DraftVersion } from "./draft-version";

export type DraftState = Readonly<{ text: string; version: DraftVersion; diagnostic: string | null }>;
export type DraftEdit = Readonly<{ from: number; to: number; inserted: string }>;
export type LocatedOnset = Readonly<{
  from: number;
  to: number;
  references: readonly Readonly<{ from: number; to: number }>[];
  notation: Readonly<{ from: number; to: number; start: number; pitch: number | null }> | null;
}>;

function decodeState(raw: { text: string; version: unknown; diagnostic: string | null }): DraftState {
  const version = decodeDraftVersion(raw.version);
  if (!version || typeof raw.text !== "string" || (raw.diagnostic !== null && typeof raw.diagnostic !== "string")) {
    throw new Error("invalid authoring state");
  }
  return Object.freeze({ text: raw.text, version, diagnostic: raw.diagnostic });
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
